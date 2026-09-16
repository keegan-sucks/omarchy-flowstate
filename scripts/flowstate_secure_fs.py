#!/usr/bin/env python3
"""TOCTOU-safe filesystem primitives shared by Flowstate's sync tooling.

Every credential / unit / token write in this plugin lands somewhere under the
user's config tree, and a co-resident process running as the same user could try
to redirect those writes by swapping a *parent* directory for a symlink between
the moment we check a path and the moment we use it. A final-component
`O_NOFOLLOW` (or an `os.path.islink()` guard) does not close that window, because
it never binds the identity of the directories above the leaf.

The functions here traverse a path one component at a time from the filesystem
root, opening each with `O_NOFOLLOW | O_DIRECTORY` so a symlinked component is
refused outright, and then perform every create / fsync / rename / unlink
*relative to the retained directory file descriptor* (openat/renameat/unlinkat).
Once a directory fd is validated it is never re-resolved by name, so there is no
window for a swap to redirect the operation.

Usable two ways:
  • imported (``import flowstate_secure_fs as sfs``) by sync-liked-playlist.py, and
  • as a tiny CLI (``python3 flowstate_secure_fs.py <mkdir|write|rm> …``) so the
    setup/install shell scripts get the same guarantees for their file writes.
"""

import os
import secrets
import stat
import sys

# Walk flags: read-only, must be a real directory, never traverse a symlink,
# close-on-exec so a validated fd can't leak into a child we spawn.
_WALK_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_CLOEXEC

# Generous ceilings — the files we manage (env, token, systemd units) are tiny;
# these only exist to refuse a pathologically large payload.
MAX_WRITE_BYTES = 1 << 20
MAX_READ_BYTES = 1 << 20


def dir_fd(path: str, *, create: bool = False, mode: int = 0o700) -> int:
    """Return an fd for ``path``, opening each component with O_NOFOLLOW.

    A symlinked component anywhere in the path raises OSError (ELOOP) rather than
    being followed. With ``create=True`` missing components are created (mkdir +
    fchmod to defeat umask); without it a missing component raises
    FileNotFoundError. The caller owns the returned fd and must close it.
    """
    parts = [p for p in os.path.abspath(path).split(os.sep) if p]
    fd = os.open("/", _WALK_FLAGS)          # the root is never a symlink
    try:
        for comp in parts:
            if comp in (os.curdir, os.pardir):
                raise ValueError(f"unsafe path component {comp!r} in {path!r}")
            try:
                nfd = os.open(comp, _WALK_FLAGS, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(comp, mode, dir_fd=fd)
                nfd = os.open(comp, _WALK_FLAGS, dir_fd=fd)
                os.fchmod(nfd, mode)         # exact perms regardless of umask
            os.close(fd)
            fd = nfd
        return fd
    except BaseException:
        os.close(fd)
        raise


def _check_name(name: str) -> None:
    if os.sep in name or name in ("", os.curdir, os.pardir):
        raise ValueError(f"unsafe file name {name!r}")


def read_bounded(dfd: int, name: str, limit: int = MAX_READ_BYTES) -> bytes | None:
    """Read ``name`` under ``dfd`` without following a symlink; None if absent.

    Reads at most ``limit`` bytes and rejects a file that would exceed it, so a
    swapped-in giant file cannot be slurped into memory.
    """
    _check_name(name)
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dfd)
    except FileNotFoundError:
        return None
    except OSError:
        # ELOOP (a symlink was planted at the name) or similar — treat as
        # unreadable rather than trust whatever it points at.
        return None
    with os.fdopen(fd, "rb", closefd=True) as fh:
        data = fh.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"{name} exceeds the {limit}-byte ceiling")
    return data


def atomic_write(dfd: int, name: str, data: bytes, mode: int = 0o600) -> None:
    """Create ``name`` under ``dfd`` atomically: O_EXCL temp → fsync → renameat.

    The temp file is created with O_CREAT|O_EXCL|O_NOFOLLOW relative to the
    validated dir fd, flushed and fsynced, then renamed into place (renameat on
    the same dir fd). Any symlink pre-planted at the destination name is removed
    first with unlinkat, so no write ever follows an attacker-chosen link.
    """
    _check_name(name)
    tmp = f".{name}.{secrets.token_hex(8)}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                 mode, dir_fd=dfd)
    try:
        os.fchmod(fd, mode)                 # exact perms regardless of umask
        with os.fdopen(fd, "wb", closefd=True) as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        try:
            if stat.S_ISLNK(os.lstat(name, dir_fd=dfd).st_mode):
                os.unlink(name, dir_fd=dfd)
        except FileNotFoundError:
            pass
        os.rename(tmp, name, src_dir_fd=dfd, dst_dir_fd=dfd)
        try:
            os.fsync(dfd)                   # persist the rename in the directory
        except OSError:
            pass
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=dfd)
        except OSError:
            pass
        raise


def remove(dfd: int, name: str) -> None:
    """Unlink ``name`` under ``dfd`` (unlinkat); a no-op if it is already gone.

    unlinkat removes the link itself, so a symlink planted at the name is
    deleted rather than followed.
    """
    _check_name(name)
    try:
        os.unlink(name, dir_fd=dfd)
    except FileNotFoundError:
        pass


# --- CLI (for the shell scripts) --------------------------------------------

def _cli(argv: list[str]) -> int:
    import argparse

    ap = argparse.ArgumentParser(prog="flowstate_secure_fs", add_help=True)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_mkdir = sub.add_parser("mkdir", help="create a directory chain (O_NOFOLLOW per component)")
    p_mkdir.add_argument("--path", required=True)
    p_mkdir.add_argument("--mode", default="700")

    p_write = sub.add_parser("write", help="atomically write stdin into <dir>/<name>")
    p_write.add_argument("--dir", required=True)
    p_write.add_argument("--name", required=True)
    p_write.add_argument("--mode", default="600")
    p_write.add_argument("--dir-mode", default="700")

    p_rm = sub.add_parser("rm", help="unlink one or more names under <dir>")
    p_rm.add_argument("--dir", required=True)
    p_rm.add_argument("--name", action="append", default=[], required=True)

    args = ap.parse_args(argv)

    if args.cmd == "mkdir":
        os.close(dir_fd(args.path, create=True, mode=int(args.mode, 8)))
        return 0

    if args.cmd == "write":
        data = sys.stdin.buffer.read(MAX_WRITE_BYTES + 1)
        if len(data) > MAX_WRITE_BYTES:
            sys.stderr.write("flowstate: refusing to write more than "
                             f"{MAX_WRITE_BYTES} bytes\n")
            return 1
        fd = dir_fd(args.dir, create=True, mode=int(args.dir_mode, 8))
        try:
            atomic_write(fd, args.name, data, int(args.mode, 8))
        finally:
            os.close(fd)
        return 0

    if args.cmd == "rm":
        try:
            fd = dir_fd(args.dir, create=False)
        except FileNotFoundError:
            return 0                        # nothing to remove
        try:
            for name in args.name:
                remove(fd, name)
        finally:
            os.close(fd)
        return 0

    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(_cli(sys.argv[1:]))
    except (OSError, ValueError) as err:
        sys.stderr.write(f"flowstate: secure filesystem operation failed: {err}\n")
        raise SystemExit(1)
