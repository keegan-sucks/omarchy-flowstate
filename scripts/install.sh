#!/usr/bin/env bash
#
# install.sh — one-shot setup for Flowstate.
#
# Runs the individual setup steps in order:
#   1. validate + enable the plugin, and place its bar icon (you pick where)
#   2. install spotify_player (AUR) and offer to authenticate
#   3. install the privileged /etc/hosts blocker (needs sudo)
#
# Each step is safe to re-run. Pass --section <left|center|right> to skip the
# bar-position prompt.
#
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ID="io.github.keegan-sucks.flowstate"

SECTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --section) SECTION="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

command -v omarchy >/dev/null 2>&1 || { echo "This isn't an Omarchy system (no 'omarchy' command)." >&2; exit 1; }

# --- 1. Plugin ------------------------------------------------------------
bold "1/3 · Plugin"
if omarchy plugin validate "$PLUGIN_DIR"; then
  echo "  manifest valid."
else
  echo "  plugin failed validation — aborting." >&2
  exit 1
fi

if [ -z "$SECTION" ]; then
  echo "  Where should the Flowstate icon sit on the bar?"
  echo "    1) center   2) left   3) right"
  read -r -p "  Choose [1]: " pick || pick=""
  case "$pick" in
    2) SECTION="left" ;;
    3) SECTION="right" ;;
    *) SECTION="center" ;;
  esac
fi

echo "  Enabling plugin in the $SECTION section…"
omarchy plugin enable "$PLUGIN_ID" --section "$SECTION" \
  || omarchy bar put "$PLUGIN_ID" --section "$SECTION" \
  || echo "  (couldn't auto-place; add it from the bar settings and move it with: omarchy bar move $PLUGIN_ID --section $SECTION)"

# --- 2. spotify_player ----------------------------------------------------
echo
bold "2/3 · Music engine (spotify_player)"
bash "$SCRIPT_DIR/install-spotify-player.sh"

# --- 3. Site blocker ------------------------------------------------------
echo
bold "3/3 · Site blocker (needs sudo)"
echo "  Installs a root-owned /etc/hosts helper + a scoped NOPASSWD sudoers rule"
echo "  so sessions can toggle blocking without a password prompt."
read -r -p "  Set up site blocking now? [Y/n] " ans || ans=""
case "${ans,,}" in
  n|no) echo "  Skipped. Run later: sudo $SCRIPT_DIR/install-blocker.sh" ;;
  *)    sudo bash "$SCRIPT_DIR/install-blocker.sh" ;;
esac

echo
bold "Done."
echo "Flowstate is on your bar. Left-click it to open the panel; middle-click starts a session."
echo "Music workspace defaults to 9; Obsidian is isolated on your active workspace."
echo "Tune everything in the panel, or with: omarchy bar set $PLUGIN_ID <key> <value>"
