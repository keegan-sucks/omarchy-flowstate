#!/usr/bin/env bash
#
# flowstate-session.sh — soundtrack orchestrator for the Flowstate bar widget.
# Invoked by the plugin (Quickshell.execDetached), never by hand.
#
# Usage:
#   flowstate-session.sh <on|off|break|resume|next> <target> <volume> <workspace> <shuffle 0|1>
#
#   on      start the soundtrack (launch Spotify if needed, random-start, duck volume)
#   off     restore the previous volume and pause (Spotify is left open)
#   break   pause during a short break
#   resume  resume when focus returns (restarts the context if Spotify lost it)
#   next    skip the current song
#
# Music runs through the OFFICIAL Spotify desktop app, driven over MPRIS (D-Bus) with
# busctl — the same idea as Flowstate for macOS driving Spotify.app over AppleScript.
# No extra player, no CLI, no login inside Flowstate: you just stay logged into the
# Spotify app you already use. Each slot target is an ordinary playlist / album /
# artist URI or open.spotify.com link. Liked Songs work via a *mirror playlist*
# (see scripts/setup-liked.sh and the README) because the desktop app cannot
# shuffle Liked Songs as a context.

set -uo pipefail

ACTION="${1:-}"
TARGET="${2:-}"
VOLUME="${3:-35}"
SPOTIFY_WS="${4:-9}"
SHUFFLE="${5:-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/flowstate"
PREV_VOL_FILE="$STATE_DIR/prev-volume"
LOG_FILE="$STATE_DIR/session.log"

BUS="org.mpris.MediaPlayer2.spotify"
OBJ="/org/mpris/MediaPlayer2"
PLAYER="org.mpris.MediaPlayer2.Player"
SPOTIFY_CLASS="spotify"                 # Hyprland window class (case-insensitive match)

mkdir -p "$STATE_DIR"
log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
have() { command -v "$1" >/dev/null 2>&1; }
notify() {
  if have omarchy-notification-send; then omarchy-notification-send -g "◷" "Flowstate" "$1"
  elif have notify-send; then notify-send "Flowstate" "$1"; fi
  return 0
}

# --- MPRIS helpers -----------------------------------------------------------

# busctl prints typed values ("s \"Playing\"", "b true", "d 0.35"); strip the type + quotes.
sp_get()  { busctl --user get-property "$BUS" "$OBJ" "$PLAYER" "$1" 2>/dev/null | sed -E 's/^[a-z] //; s/^"(.*)"$/\1/'; }
sp_set()  { busctl --user set-property "$BUS" "$OBJ" "$PLAYER" "$1" "$2" "$3" >/dev/null 2>&1; }   # <prop> <sig> <value>
sp_call() { busctl --user call "$BUS" "$OBJ" "$PLAYER" "$@" >/dev/null 2>&1; }                    # <method> [sig args…]
sp_up()   { busctl --user status "$BUS" >/dev/null 2>&1; }

sp_status()  { sp_get PlaybackStatus; }           # Playing | Paused | Stopped
sp_playing() { [ "$(sp_status)" = "Playing" ]; }

# Volume is 0.0–1.0 on the bus; Flowstate talks in percent.
sp_volume_pct() { local v; v="$(sp_get Volume)"; [ -n "$v" ] && awk -v v="$v" 'BEGIN{printf "%d", (v*100)+0.5}'; }
sp_set_volume_pct() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 0
  local p=$1; [ "$p" -gt 100 ] && p=100
  sp_set Volume d "$(awk -v p="$p" 'BEGIN{printf "%.3f", p/100}')"
}

sp_wait_up() {  # wait for the MPRIS name to appear (Spotify freshly launched)
  local i
  for i in $(seq 1 60); do sp_up && return 0; sleep 0.5; done
  return 1
}

# --- Launch + Hyprland placement --------------------------------------------

launch_spotify() {
  if have uwsm-app; then setsid uwsm-app -- spotify >/dev/null 2>&1 &
  else setsid spotify >/dev/null 2>&1 & fi
}

hypr_addr_by_class() {  # case-insensitive class match -> window addresses
  local cls="${1,,}"
  have hyprctl && have jq || return 0
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg c "$cls" '.[] | select((.class // "" | ascii_downcase) == $c) | .address'
}

# Hyprland ≥ 0.56 dispatches through a Lua API; older releases use the classic string.
move_window_to_ws() {  # <address> <workspace>
  hyprctl dispatch "hl.dsp.window.move({ workspace = \"$2\", follow = false, window = \"address:$1\" })" >/dev/null 2>&1 \
    || hyprctl dispatch movetoworkspacesilent "$2,address:$1" >/dev/null 2>&1
}

# Move a freshly launched Spotify window to the music workspace, silently, so it
# never lands on (or steals focus from) the workspace you are working in.
place_class_on_ws() {  # <class> <ws>
  local cls="$1" ws="$2" a i
  [ "$ws" -gt 0 ] 2>/dev/null || return 0
  have hyprctl && have jq || return 0
  for i in $(seq 1 40); do
    a="$(hypr_addr_by_class "$cls" | head -1)"
    [ -n "$a" ] && break
    sleep 0.25
  done
  hypr_addr_by_class "$cls" | while IFS= read -r a; do
    [ -n "$a" ] && move_window_to_ws "$a" "$ws"
  done
}

# --- Target parsing → a spotify: URI ----------------------------------------

is_liked() {
  case "${1,,}" in
    liked|likes|ncspot:liked|*:collection:tracks|*:collection) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve a slot target to a `spotify:<kind>:<id>` URI that OpenUri accepts.
# Accepts spotify: URIs, open.spotify.com links (incl. intl-xx/ paths and ?si=…),
# or a bare id (assumed to be a playlist). Output is restricted to URI-safe chars.
resolve_uri() {
  local raw="${1// /}" uri="" rest kind
  [ -z "$raw" ] && return 1
  case "$raw" in
    spotify:*) uri="$raw" ;;
    *open.spotify.com/*)
      rest="${raw#*open.spotify.com/}"
      case "$rest" in intl-*/*) rest="${rest#*/}" ;; esac
      kind="${rest%%/*}"
      rest="${rest#*/}"; rest="${rest%%\?*}"; rest="${rest%%/*}"
      case "$kind" in playlist|album|artist|track) uri="spotify:$kind:$rest" ;; esac
      ;;
    *) uri="spotify:playlist:$raw" ;;
  esac
  [[ "$uri" =~ ^spotify:[A-Za-z0-9._:-]+$ ]] || return 1
  echo "$uri"
}

# --- Soundtrack sequence -----------------------------------------------------

# Start the context and confirm Spotify actually reports Playing (a just-launched
# app can swallow the first OpenUri while it warms up).
open_uri_verified() {  # <uri>
  local i j
  for i in 1 2 3; do
    sp_call OpenUri s "$1"
    for j in $(seq 1 12); do sleep 0.5; sp_playing && { log "playing (attempt $i)"; return 0; }; done
    sp_call Play; sleep 1
    sp_playing && { log "playing after Play (attempt $i)"; return 0; }
  done
  return 1
}

sp_ensure_shuffle() {  # <true|false>
  sp_set Shuffle b "$1"; sleep 0.4
  [ "$(sp_get Shuffle)" = "$1" ] || { sp_set Shuffle b "$1"; sleep 0.4; }
}

sp_ensure_repeat_context() {
  sp_set LoopStatus s Playlist; sleep 0.4
  [ "$(sp_get LoopStatus)" = "Playlist" ] || sp_set LoopStatus s Playlist
}

engage() {
  log "=== ENGAGE target='$TARGET' vol=$VOLUME ws=$SPOTIFY_WS shuffle=$SHUFFLE"

  if is_liked "$TARGET"; then
    log "target is 'liked' — not playable directly"
    notify "Liked Songs need a mirror playlist — open ⚙ Edit → Liked Songs for the 30-second setup"
    return 1
  fi
  local uri
  if ! uri="$(resolve_uri "$TARGET")"; then
    notify "No soundtrack configured — set a Spotify playlist in ⚙ Edit"
    return 1
  fi

  local launched=0
  if ! sp_up; then
    have spotify || { notify "Spotify isn't installed (omarchy pkg aur add spotify)"; return 1; }
    log "launching spotify"
    launch_spotify; launched=1
    place_class_on_ws "$SPOTIFY_CLASS" "$SPOTIFY_WS" &
    if ! sp_wait_up; then
      notify "Spotify didn't come up — is it logged in?"
      return 1
    fi
    sleep 1   # let it finish loading before the first command
  fi

  # Remember the pre-session volume so it can be restored at the end. A freshly
  # launched Spotify reports 0 until something plays, so in that case we read it
  # right after playback starts instead (a sub-second blip, unavoidable).
  local prev=""
  if [ "$launched" = 0 ]; then
    prev="$(sp_volume_pct)"
    [ -n "$prev" ] && [ "$prev" -gt 0 ] && echo "$prev" > "$PREV_VOL_FILE"
    sp_set_volume_pct 0          # start muted so track 1 + the shuffle skips are silent
  fi

  if ! open_uri_verified "$uri"; then
    [ -n "$prev" ] && sp_set_volume_pct "$prev"      # never strand Spotify at 0
    notify "Couldn't start the soundtrack — is Spotify logged in?"
    return 1
  fi

  if [ "$launched" = 1 ]; then
    prev="$(sp_volume_pct)"
    [ -n "$prev" ] && [ "$prev" -gt 0 ] && echo "$prev" > "$PREV_VOL_FILE"
    sp_set_volume_pct 0
  fi

  if [ "$SHUFFLE" = "1" ]; then
    sp_ensure_shuffle true
    local n=$(( (RANDOM % 4) + 1 )) k           # jump to a varied track in shuffle order
    for ((k = 0; k < n; k++)); do sp_call Next; sleep 0.4; done
  fi
  sp_ensure_repeat_context                       # loop so a focus block never falls silent
  sp_playing || sp_call Play
  sp_set_volume_pct "$VOLUME"                    # unmute to the focus volume
  log "=== ENGAGE done: uri=$uri prev=${prev:-?} focus=$VOLUME ==="
}

release() {
  log "=== RELEASE ==="
  sp_up || { rm -f "$PREV_VOL_FILE"; return 0; }
  if [ -f "$PREV_VOL_FILE" ]; then
    local v; v="$(cat "$PREV_VOL_FILE")"
    sp_set_volume_pct "$v"
    rm -f "$PREV_VOL_FILE"
  fi
  sp_call Pause
}

do_break() {
  log "break: pause"
  sp_up && sp_call Pause
  return 0
}

do_resume() {
  log "resume: play"
  sp_up || { engage; return; }                   # Spotify was closed during the break
  sp_call Play
  sleep 1
  sp_playing && return 0
  log "resume: context lost — re-engaging"
  engage
}

do_next() { sp_up && sp_call Next; return 0; }

case "$ACTION" in
  on)     engage ;;
  off)    release ;;
  break)  do_break ;;
  resume) do_resume ;;
  next)   do_next ;;
  *)      echo "usage: $0 <on|off|break|resume|next> <target> <volume> <workspace> <shuffle>" >&2; exit 2 ;;
esac
