#!/usr/bin/env bash
#
# install-sync-schedule.sh — install (or refresh / remove) a weekly systemd USER timer
# that re-syncs your "Liked (Flowstate)" mirror playlist, so it keeps up as you
# like/unlike songs. Default cadence: weekly, Sundays 04:00 (Persistent=true, so a
# missed run fires at the next boot/login).
#
#   bash scripts/install-sync-schedule.sh            # install or refresh
#   bash scripts/install-sync-schedule.sh --run-now  # …and run one sync immediately
#   bash scripts/install-sync-schedule.sh --remove   # uninstall the timer + runtime copy
#
# The sync's runtime is COPIED into ~/.config/flowstate and run from there, so the
# timer keeps working even if the plugin folder moves or is removed. Credentials:
# ~/.config/flowstate/sync.env (just SPOTIFY_CLIENT_ID — PKCE, no secret; see
# sync.env.example). The OAuth token lives beside it as liked-sync-token.json.
#
# Everything is per-user (systemctl --user). No sudo or pkexec is required.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flowstate"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="flowstate-liked-sync"

if [ "${1:-}" = "--remove" ]; then
  systemctl --user disable --now "$UNIT.timer" >/dev/null 2>&1 || true
  rm -f "$UNIT_DIR/$UNIT.timer" "$UNIT_DIR/$UNIT.service" "$CONFIG_DIR/sync-liked-playlist.py"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "✓ Removed the weekly Liked-mirror sync."
  echo "  Kept: $CONFIG_DIR/sync.env and liked-sync-token.json (delete the folder to purge)."
  exit 0
fi

mkdir -p "$CONFIG_DIR" "$UNIT_DIR"
cp "$SCRIPT_DIR/sync-liked-playlist.py" "$CONFIG_DIR/sync-liked-playlist.py"
chmod 700 "$CONFIG_DIR"

cat > "$UNIT_DIR/$UNIT.service" <<UNITEOF
[Unit]
Description=Flowstate: refresh the "Liked (Flowstate)" mirror playlist

[Service]
Type=oneshot
EnvironmentFile=-%h/.config/flowstate/sync.env
ExecStart=/usr/bin/python3 %h/.config/flowstate/sync-liked-playlist.py
UNITEOF

cat > "$UNIT_DIR/$UNIT.timer" <<UNITEOF
[Unit]
Description=Flowstate: weekly Liked-Songs mirror refresh

[Timer]
OnCalendar=Sun *-*-* 04:00:00
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
UNITEOF

systemctl --user daemon-reload
systemctl --user enable --now "$UNIT.timer" >/dev/null

echo "✓ Installed weekly Liked-mirror sync: $UNIT.timer"
echo "  Schedule : Sundays 04:00 (weekly; catches up after downtime)"
echo "  Runtime  : $CONFIG_DIR/  (sync-liked-playlist.py, sync.env, liked-sync-token.json)"
echo "  Status   : systemctl --user list-timers $UNIT.timer"
echo "  Logs     : journalctl --user -u $UNIT.service"
echo "  Run now  : systemctl --user start $UNIT.service"

if [ "${1:-}" = "--run-now" ]; then
  systemctl --user start "$UNIT.service"
fi
