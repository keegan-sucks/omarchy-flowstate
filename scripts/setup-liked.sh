#!/usr/bin/env bash
#
# setup-liked.sh — interactive, OPTIONAL setup for the Liked-Songs auto-refresh.
#
# Flowstate works fully WITHOUT this — it plays any Spotify playlist out of the box.
# This only turns your *Liked Songs* into a self-refreshing mirror playlist.
# Run it whenever (from the panel's ⚙ Edit → "Auto-refresh Liked Songs…" button, or
# by hand):   bash scripts/setup-liked.sh
#
# No sudo or pkexec is required. Everything lands in ~/.config/flowstate.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.keegan-sucks.flowstate"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flowstate"
ENV_FILE="$CONFIG_DIR/sync.env"
DASHBOARD="https://developer.spotify.com/dashboard"

have() { command -v "$1" >/dev/null 2>&1; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }
confirm() {  # <prompt> [default y|n]
  local ans
  if have gum; then
    if [ "${2:-n}" = y ]; then gum confirm "$1"; else gum confirm --default=false "$1"; fi
  else
    read -r -p "$1 [$([ "${2:-n}" = y ] && echo Y/n || echo y/N)] " ans || ans=""
    case "${ans,,}" in
      "") [ "${2:-n}" = y ] ;;
      y|yes) return 0 ;;
      *) return 1 ;;
    esac
  fi
}
ask() {  # <prompt> -> stdout
  if have gum; then gum input --placeholder "$1"; else read -r -p "$1: " REPLY || REPLY=""; echo "$REPLY"; fi
}
open_url() {
  if have omarchy-launch-browser; then setsid omarchy-launch-browser "$1" >/dev/null 2>&1 &
  elif have xdg-open; then setsid xdg-open "$1" >/dev/null 2>&1 &
  fi
}

cat <<'TXT'

Flowstate — Liked Songs
───────────────────────
Spotify can't shuffle Liked Songs directly, so you point a slot at a mirror playlist.

★ EASIEST — no account setup, ~30 seconds (recommended):
    In Spotify: open Liked Songs → Ctrl-A → right-click → Add to playlist →
    New playlist, then paste that playlist's link into a Flowstate slot
    (⚙ Edit → Soundtrack slots). Done — you can stop here.

This tool is the OPTIONAL alternative: it builds that mirror for you and keeps it in
sync automatically every week. The trade-off is it needs your own free Spotify app —
just a Client ID (no password, no secret), ~2 min — because Spotify no longer lets one
shared app serve everyone.

TXT

if ! confirm "Set up the optional weekly auto-refresh now?" n; then
  echo "Skipped. Re-run  bash scripts/setup-liked.sh  whenever you like."
  exit 0
fi

have python3 || { echo "python3 is required (it ships with Omarchy)."; exit 1; }

# --- 1. Client ID -------------------------------------------------------------
echo
bold "1) Create a free Spotify app, then paste its Client ID here."
cat <<TXT
     • Opening  $DASHBOARD  → "Create app"
     • Redirect URI (exactly):   http://127.0.0.1:8888/callback
     • APIs used: check "Web API".  Copy the Client ID from the app's Settings.
       (Ignore the client secret — PKCE doesn't use one.)
TXT
open_url "$DASHBOARD"
echo
CID="$(ask "Paste your Client ID")"
CID="${CID//[[:space:]]/}"
[[ "$CID" =~ ^[A-Za-z0-9]{16,64}$ ]] || { echo "That doesn't look like a Spotify Client ID — aborting."; exit 1; }

mkdir -p "$CONFIG_DIR"
umask 077
cat > "$ENV_FILE" <<ENV
# Flowstate Liked-Songs mirror (PKCE flow — only a Client ID is needed; there is NO secret).
SPOTIFY_CLIENT_ID=$CID
SPOTIFY_REDIRECT_URI=http://127.0.0.1:8888/callback
ENV
chmod 600 "$ENV_FILE"
echo "Saved your Client ID to $ENV_FILE"

# --- 2. Install the weekly timer + authorize + first sync ----------------------
echo
bold "2) Installing the weekly refresh and authorizing (a browser tab will open —"
echo "   approve access; nothing is stored but an OAuth token in $CONFIG_DIR)…"
bash "$SCRIPT_DIR/install-sync-schedule.sh" >/dev/null
rm -f "$CONFIG_DIR/liked-sync-token.json"          # force a fresh PKCE authorization

URI="$(python3 "$CONFIG_DIR/sync-liked-playlist.py" | tee /dev/tty | awk '/Flowstate slot target/ {print $NF}')"

echo
echo "────────────────────────────────────────────"
echo "✓ Done. Your Liked Songs mirror auto-refreshes weekly (Sundays 04:00)."
echo
if [ -n "$URI" ]; then
  echo "Slot target for your Liked Songs:"
  echo "    $URI"
  echo
  if have omarchy && confirm "Point Flowstate's soundtrack slot 3 at it now (named 'Liked')?" y; then
    if omarchy bar set "$PLUGIN_ID" slot3Uri "$URI" >/dev/null 2>&1 \
       && omarchy bar set "$PLUGIN_ID" slot3Label "Liked" >/dev/null 2>&1; then
      echo "Slot 3 → Liked. Pick it in the panel and start a session."
    else
      echo "Couldn't write the setting automatically — paste the URI into a slot under ⚙ Edit."
    fi
  else
    echo "Paste it into a slot under ⚙ Edit → Soundtrack slots."
  fi
fi
