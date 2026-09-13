#!/usr/bin/env bash
#
# install-sync-schedule.sh — install (or refresh / remove) a weekly systemd USER
# timer that re-syncs your "Liked (Flowstate)" mirror playlist, so it keeps up as
# you like/unlike songs. Default cadence: weekly, Sundays 04:00 (Persistent=true,
# so a missed run fires at the next boot/login).
#
#   bash scripts/install-sync-schedule.sh            # install or refresh
#   bash scripts/install-sync-schedule.sh --run-now  # …and run one sync immediately
#   bash scripts/install-sync-schedule.sh --remove   # uninstall the timer
#
# The timer runs THIS plugin's own sync-liked-playlist.py, in place: the scheduled
# code stays bound to the installed (reviewed) plugin snapshot rather than a mutable
# copy, and the service runs sandboxed. If you move or uninstall the plugin the
# timer stops — re-run this to repoint it. Credentials live in
# ~/.config/flowstate/sync.env (just SPOTIFY_CLIENT_ID — PKCE, no secret; see
# sync.env.example); the OAuth token lives beside it as liked-sync-token.json.
#
# Everything is per-user (systemctl --user). No sudo or pkexec is required.
set -euo pipefail

# Run under a fixed, trusted PATH and resolve every helper to an absolute path, so a
# hostile entry planted earlier in the user's PATH can never shadow the tools we call.
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/share/omarchy/bin
pin() {  # <command> -> absolute path (or fail loudly)
  local p; p="$(command -v -- "$1" 2>/dev/null || true)"
  [[ -n "$p" && -x "$p" ]] || { printf 'flowstate: required command not found: %s\n' "$1" >&2; exit 127; }
  printf '%s' "$p"
}
SYSTEMCTL="$(pin systemctl)"; MKDIR="$(pin mkdir)"; CHMOD="$(pin chmod)"
RM="$(pin rm)"; MV="$(pin mv)"; MKTEMP="$(pin mktemp)"; CAT="$(pin cat)"; DIRNAME="$(pin dirname)"
PYTHON=/usr/bin/python3

SCRIPT_DIR="$(cd -- "$("$DIRNAME" -- "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-liked-playlist.py"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flowstate"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="flowstate-liked-sync"

# Refuse to operate through a symlinked config/unit dir — a planted link could
# redirect our writes (unit files, credentials) somewhere else.
for d in "$CONFIG_DIR" "$UNIT_DIR"; do
  [[ -L "$d" ]] && { printf 'flowstate: refusing to use symlinked directory: %s\n' "$d" >&2; exit 1; }
done

if [ "${1:-}" = "--remove" ]; then
  "$SYSTEMCTL" --user disable --now "$UNIT.timer" >/dev/null 2>&1 || true
  "$RM" -f -- "$UNIT_DIR/$UNIT.timer" "$UNIT_DIR/$UNIT.service" \
              "$CONFIG_DIR/sync-liked-playlist.py"   # also drop any legacy copied runtime
  "$SYSTEMCTL" --user daemon-reload >/dev/null 2>&1 || true
  echo "✓ Removed the weekly Liked-mirror sync."
  echo "  Kept: $CONFIG_DIR/sync.env and liked-sync-token.json (delete the folder to purge)."
  exit 0
fi

[[ -f "$SYNC_SCRIPT" ]] || { printf 'flowstate: sync script missing: %s\n' "$SYNC_SCRIPT" >&2; exit 1; }

"$MKDIR" -p -- "$CONFIG_DIR" "$UNIT_DIR"
"$CHMOD" 700 -- "$CONFIG_DIR"

# Write each unit to an O_EXCL temp file in the same directory, then atomically
# rename it into place — no write ever follows a pre-planted symlink at the
# destination name, and readers never see a half-written unit.
install_unit() {  # <dest>  (content on stdin)
  local dest="$1" tmp
  tmp="$("$MKTEMP" -- "$UNIT_DIR/.${UNIT}.XXXXXX")" || exit 1
  "$CAT" >"$tmp"
  "$CHMOD" 600 -- "$tmp"
  [[ -L "$dest" ]] && "$RM" -f -- "$dest"
  "$MV" -f -- "$tmp" "$dest"
}

install_unit "$UNIT_DIR/$UNIT.service" <<UNITEOF
[Unit]
Description=Flowstate: refresh the "Liked (Flowstate)" mirror playlist

[Service]
Type=oneshot
# Closed environment; interpreter and code pinned to absolute paths, code bound to
# the installed plugin snapshot.
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=FLOWSTATE_CONFIG_DIR=%h/.config/flowstate
EnvironmentFile=-%h/.config/flowstate/sync.env
ExecStart=$PYTHON $SYNC_SCRIPT

# --- sandbox: a network + config-write oneshot needs very little authority ---
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/flowstate
PrivateTmp=true
PrivateDevices=true
ProtectClock=true
ProtectHostname=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectProc=invisible
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
CapabilityBoundingSet=
UMask=0077
UNITEOF

install_unit "$UNIT_DIR/$UNIT.timer" <<UNITEOF
[Unit]
Description=Flowstate: weekly Liked-Songs mirror refresh

[Timer]
OnCalendar=Sun *-*-* 04:00:00
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
UNITEOF

"$SYSTEMCTL" --user daemon-reload
"$SYSTEMCTL" --user enable --now "$UNIT.timer" >/dev/null

echo "✓ Installed weekly Liked-mirror sync: $UNIT.timer"
echo "  Schedule : Sundays 04:00 (weekly; catches up after downtime)"
echo "  Runs     : $SYNC_SCRIPT (sandboxed, in place)"
echo "  Config   : $CONFIG_DIR/  (sync.env, liked-sync-token.json)"
echo "  Status   : systemctl --user list-timers $UNIT.timer"
echo "  Logs     : journalctl --user -u $UNIT.service"
echo "  Run now  : systemctl --user start $UNIT.service"

if [ "${1:-}" = "--run-now" ]; then
  "$SYSTEMCTL" --user start "$UNIT.service"
fi
