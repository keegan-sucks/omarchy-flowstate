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

# Run under a fixed, trusted PATH and resolve every helper to an absolute path, so a
# hostile entry planted earlier in the user's PATH can never shadow the tools we call.
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/share/omarchy/bin
pin() {  # <command> -> absolute path (or fail loudly)
  local p; p="$(command -v -- "$1" 2>/dev/null || true)"
  [[ -n "$p" && -x "$p" ]] || { printf 'flowstate: required command not found: %s\n' "$1" >&2; exit 127; }
  printf '%s' "$p"
}
opt() { command -v -- "$1" 2>/dev/null || true; }   # optional tool -> abs path or ""

PYTHON=/usr/bin/python3
BASH="$(pin bash)"; CAT="$(pin cat)"; RM="$(pin rm)"; MKDIR="$(pin mkdir)"; CHMOD="$(pin chmod)"
SETSID="$(pin setsid)"; TIMEOUT="$(pin timeout)"; TEE="$(pin tee)"; AWK="$(pin awk)"; HEAD="$(pin head)"
GUM="$(opt gum)"; OMARCHY="$(opt omarchy)"
BROWSER_LAUNCH="$(opt omarchy-launch-browser)"; [[ -z "$BROWSER_LAUNCH" ]] && BROWSER_LAUNCH="$(opt xdg-open)"

SCRIPT_DIR="$(cd -- "$("$(pin dirname)" -- "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-liked-playlist.py"
PLUGIN_ID="io.github.keegan-sucks.flowstate"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flowstate"
ENV_FILE="$CONFIG_DIR/sync.env"
DASHBOARD="https://developer.spotify.com/dashboard"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
confirm() {  # <prompt> [default y|n]
  local ans
  if [[ -n "$GUM" ]]; then
    if [ "${2:-n}" = y ]; then "$GUM" confirm "$1"; else "$GUM" confirm --default=false "$1"; fi
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
  if [[ -n "$GUM" ]]; then "$GUM" input --placeholder "$1"; else read -r -p "$1: " REPLY || REPLY=""; echo "$REPLY"; fi
}
open_url() {
  [[ -n "$BROWSER_LAUNCH" ]] && "$SETSID" "$BROWSER_LAUNCH" "$1" >/dev/null 2>&1 &
  return 0
}

"$CAT" <<'TXT'

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

[[ -x "$PYTHON" ]] || { echo "python3 is required (it ships with Omarchy)."; exit 1; }
[[ -f "$SYNC_SCRIPT" ]] || { echo "flowstate: sync script missing: $SYNC_SCRIPT" >&2; exit 1; }

# --- 1. Client ID -------------------------------------------------------------
echo
bold "1) Create a free Spotify app, then paste its Client ID here."
"$CAT" <<TXT
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

# Refuse a symlinked config dir, then write the env file with an O_EXCL temp +
# atomic rename so the write never follows a pre-planted symlink.
[[ -L "$CONFIG_DIR" ]] && { echo "flowstate: refusing to use symlinked directory: $CONFIG_DIR" >&2; exit 1; }
"$MKDIR" -p -- "$CONFIG_DIR"
"$CHMOD" 700 -- "$CONFIG_DIR"
umask 077
env_tmp="$("$(pin mktemp)" -- "$CONFIG_DIR/.sync.env.XXXXXX")" || exit 1
"$CAT" >"$env_tmp" <<ENV
# Flowstate Liked-Songs mirror (PKCE flow — only a Client ID is needed; there is NO secret).
SPOTIFY_CLIENT_ID=$CID
SPOTIFY_REDIRECT_URI=http://127.0.0.1:8888/callback
ENV
"$CHMOD" 600 -- "$env_tmp"
[[ -L "$ENV_FILE" ]] && "$RM" -f -- "$ENV_FILE"
"$(pin mv)" -f -- "$env_tmp" "$ENV_FILE"
echo "Saved your Client ID to $ENV_FILE"

# --- 2. Install the weekly timer + authorize + first sync ----------------------
echo
bold "2) Installing the weekly refresh and authorizing (a browser tab will open —"
echo "   approve access; nothing is stored but an OAuth token in $CONFIG_DIR)…"
"$BASH" "$SCRIPT_DIR/install-sync-schedule.sh" >/dev/null
"$RM" -f -- "$CONFIG_DIR/liked-sync-token.json"          # force a fresh PKCE authorization

# Run the first authorization + sync under a hard wall-clock deadline, in its own
# session (setsid --wait), escalating TERM->KILL if it overruns, and cap the
# captured output — a stuck browser auth can never hang setup or spew unbounded
# data. The scheduled timer and this first run execute the same in-place snapshot.
# The exit status travels through a temp file because a $(pipeline) assignment's
# own PIPESTATUS reflects the assignment, not the inner pipeline.
rc_file="$("$(pin mktemp)")"
set +e
URI="$( { "$SETSID" --wait "$TIMEOUT" --signal=TERM --kill-after=10s 900s \
            "$PYTHON" "$SYNC_SCRIPT"; echo "$?" >"$rc_file"; } \
        | "$TEE" /dev/tty | "$HEAD" -c 65536 | "$AWK" '/Flowstate slot target/ {print $NF}')"
set -e
rc="$("$CAT" "$rc_file" 2>/dev/null || echo 1)"; "$RM" -f -- "$rc_file"
if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
  echo "Authorization timed out (15 min). Re-run  bash scripts/setup-liked.sh  to retry." >&2
fi

echo
echo "────────────────────────────────────────────"
echo "✓ Done. Your Liked Songs mirror auto-refreshes weekly (Sundays 04:00)."
echo
if [ -n "$URI" ]; then
  echo "Slot target for your Liked Songs:"
  echo "    $URI"
  echo
  if [ -n "$OMARCHY" ] && confirm "Point Flowstate's soundtrack slot 3 at it now (named 'Liked')?" y; then
    if "$OMARCHY" bar set "$PLUGIN_ID" slot3Uri "$URI" >/dev/null 2>&1 \
       && "$OMARCHY" bar set "$PLUGIN_ID" slot3Label "Liked" >/dev/null 2>&1; then
      echo "Slot 3 → Liked. Pick it in the panel and start a session."
    else
      echo "Couldn't write the setting automatically — paste the URI into a slot under ⚙ Edit."
    fi
  else
    echo "Paste it into a slot under ⚙ Edit → Soundtrack slots."
  fi
fi
