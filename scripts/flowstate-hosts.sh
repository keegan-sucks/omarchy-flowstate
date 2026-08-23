#!/usr/bin/env bash
#
# flowstate-hosts — privileged /etc/hosts toggle for Flowstate.
# Installed to /usr/local/bin/flowstate-hosts (root-owned) by install-blocker.sh
# and run via a scoped NOPASSWD sudoers rule. Only ever edits the region between
# its own markers; the rest of /etc/hosts is untouched.
#
# Usage (as root):
#   flowstate-hosts on      # reads domains from stdin, one per line
#   flowstate-hosts off
#
# Reading domains from stdin keeps the sudoers rule tiny and avoids ARG_MAX
# limits with large blocklists.

set -euo pipefail

HOSTS="/etc/hosts"
BEGIN="# >>> flowstate >>>"
END="# <<< flowstate <<<"

ACTION="${1:-}"

strip_block() {
  sed -i "\|^${BEGIN}\$|,\|^${END}\$|d" "$HOSTS"
}

ensure_trailing_newline() {
  [ -s "$HOSTS" ] && [ -n "$(tail -c1 "$HOSTS")" ] && printf '\n' >> "$HOSTS" || true
}

case "$ACTION" in
  on)
    strip_block
    ensure_trailing_newline
    {
      echo "$BEGIN"
      while IFS= read -r raw; do
        d="${raw,,}"
        d="${d//[[:space:]]/}"
        [ -z "$d" ] && continue
        [[ "$d" =~ ^[a-z0-9.-]+$ ]] || continue
        echo "0.0.0.0 $d"
        echo ":: $d"
      done
      echo "$END"
    } >> "$HOSTS"
    ;;
  off)
    strip_block
    ;;
  *)
    echo "usage: flowstate-hosts <on|off>   (on reads domains from stdin)" >&2
    exit 2
    ;;
esac
