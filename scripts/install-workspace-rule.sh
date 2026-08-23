#!/usr/bin/env bash
#
# install-workspace-rule.sh — opt-in: place the music player on a far-off
# workspace so it stays out of the way. Adds Hyprland (Omarchy Lua) window
# rules to ~/.config/hypr/hyprland.lua for both the official Spotify client and
# the ncspot terminal (class "flowstate-ncspot").
#
#   ./install-workspace-rule.sh [workspace]   # default workspace: 9
#   ./install-workspace-rule.sh --uninstall
#
# No sudo needed — this edits your own Hyprland config.

set -euo pipefail

CFG="${HOME}/.config/hypr/hyprland.lua"
BEGIN="-- >>> flowstate workspace rule >>>"
END="-- <<< flowstate workspace rule <<<"

[ -f "$CFG" ] || { echo "Not found: $CFG (is this Omarchy?)" >&2; exit 1; }

strip_block() {
  sed -i "\|^${BEGIN}\$|,\|^${END}\$|d" "$CFG"
  # drop a trailing blank line left behind, if any
  sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$CFG" 2>/dev/null || true
}

if [ "${1:-}" = "--uninstall" ]; then
  strip_block
  echo "Removed Flowstate workspace rule from $CFG"
  hyprctl reload >/dev/null 2>&1 || true
  exit 0
fi

WS="${1:-9}"
[[ "$WS" =~ ^[0-9]+$ ]] || { echo "workspace must be a number" >&2; exit 1; }

strip_block
[ -s "$CFG" ] && [ -n "$(tail -c1 "$CFG")" ] && printf '\n' >> "$CFG"
cat >> "$CFG" <<EOF
${BEGIN}
o.window("^([sS]potify)\$", { workspace = "${WS} silent" })
o.window("^(flowstate-ncspot)\$", { workspace = "${WS} silent" })
${END}
EOF

echo "Added Flowstate workspace rule (workspace ${WS}) to $CFG"
if hyprctl reload >/dev/null 2>&1; then
  echo "Reloaded Hyprland."
else
  echo "Reload Hyprland (or log out/in) for it to take effect."
fi
