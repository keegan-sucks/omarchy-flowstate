#!/usr/bin/env bash
#
# flowstate-session.sh — soundtrack orchestrator for the Flowstate bar widget.
# Invoked by the plugin (Quickshell.execDetached), never by hand.
#
# Usage:
#   flowstate-session.sh <on|off|break|resume|next> \
#                        <playlist> <volume> <spotifyWorkspace> <shuffle 0|1> <nowPlaying 0|1>
#
#   on      start the soundtrack (launch/connect, random-start, duck volume)
#   off     restore the previous volume and pause (player left open)
#   break   pause during a short break
#   resume  resume when focus returns (re-engages if the device dropped)
#   next    skip the current song
#
# Music runs through spotify_player (https://github.com/aome510/spotify-player): a
# terminal client that is its own Spotify Connect device + CLI server, giving
# first-class shuffle, Liked Songs, and volume control. Streaming needs Premium.

set -uo pipefail

ACTION="${1:-}"
PLAYLIST="${2:-}"
VOLUME="${3:-35}"
SPOTIFY_WS="${4:-9}"
SHUFFLE="${5:-1}"
NOWPLAY="${6:-0}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SPOTIFY_CLASS="flowstate-spotify"       # window class for placement
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/flowstate"
PREV_VOL_FILE="$STATE_DIR/prev-volume"
NOWPLAY_PID_FILE="$STATE_DIR/nowplay.pid"
LOG_FILE="$STATE_DIR/session.log"

mkdir -p "$STATE_DIR"
log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
have() { command -v "$1" >/dev/null 2>&1; }
notify() {
  have omarchy-notification-send && omarchy-notification-send -g "◷" "Flowstate" "$1" || true
}

# --- Launch + Hyprland placement ------------------------------------------

# Launch spotify_player inside a terminal tagged with a class so it can be moved
# to the music workspace out of the way.
launch_spotify() {
  if have ghostty;    then setsid ghostty --class="$SPOTIFY_CLASS" -e spotify_player >/dev/null 2>&1 &
  elif have alacritty; then setsid alacritty --class "$SPOTIFY_CLASS" -e spotify_player >/dev/null 2>&1 &
  elif have kitty;     then setsid kitty --class "$SPOTIFY_CLASS" spotify_player >/dev/null 2>&1 &
  elif have foot;      then setsid foot --app-id="$SPOTIFY_CLASS" spotify_player >/dev/null 2>&1 &
  elif have wezterm;   then setsid wezterm start --class "$SPOTIFY_CLASS" -- spotify_player >/dev/null 2>&1 &
  else setsid xterm -e spotify_player >/dev/null 2>&1 & fi
}

hypr_addr_by_class() {  # exact case-insensitive class match -> addresses
  local cls="${1,,}"
  have hyprctl && have jq || return 0
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg c "$cls" '.[] | select((.class // "" | ascii_downcase) == $c) | .address'
}

# Hyprland 0.56 dispatches through a Lua API; the classic string form is gone.
hdisp() { hyprctl dispatch "$1" >/dev/null 2>&1; }
move_window_to_ws() {  # <address> <workspace>
  hdisp "hl.dsp.window.move({ workspace = \"$2\", follow = false, window = \"address:$1\" })"
}

# Move the player's window to the music workspace, silently. Waits briefly for it.
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

# --- spotify_player CLI ----------------------------------------------------

sp() { spotify_player "$@" 2>/dev/null; }
sp_running() { pgrep -x spotify_player >/dev/null 2>&1; }

# Wait for spotify_player's OWN Connect device, echo its exact name. We never
# fall back to another device — controlling the user's phone is the bug to avoid.
SP_DEVICE="${FLOWSTATE_SP_DEVICE:-spotify-player}"
sp_wait_device() {
  local i devs name
  for i in $(seq 1 60); do
    devs="$(sp get key devices)"
    if [ -n "$devs" ]; then
      name="$(echo "$devs" | jq -r --arg d "$SP_DEVICE" \
        '[.[] | select((.name // "" | ascii_downcase) | contains($d | ascii_downcase))][0].name // empty' 2>/dev/null)"
      [ -n "$name" ] && { echo "$name"; return 0; }
    fi
    sleep 0.5
  done
  return 1
}

sp_playback_status() { sp get key playback | jq -r '.is_playing // false' 2>/dev/null; }
sp_shuffle_state()   { sp get key playback | jq -r '.shuffle_state // false' 2>/dev/null; }
sp_repeat_state()    { sp get key playback | jq -r '.repeat_state // empty' 2>/dev/null; }
sp_device_volume()   { sp get key playback | jq -r '.device.volume_percent // empty' 2>/dev/null; }
sp_track_name()      { sp get key playback | jq -r '.item.name // empty' 2>/dev/null; }

sp_ensure_shuffle_on() {
  local i
  for i in 1 2 3; do
    [ "$(sp_shuffle_state)" = "true" ] && return 0
    sp playback shuffle >/dev/null 2>&1
    sleep 0.5
  done
}

# Repeat the whole context (playlist / liked). Starting playback resets repeat to
# "off" and the read lags, so cycle off→track→context blindly, then fix a rare
# dropped cycle once it settles.
ensure_repeat_context() {
  sp playback repeat >/dev/null 2>&1     # off -> track
  sleep 0.7
  sp playback repeat >/dev/null 2>&1     # track -> context
  sleep 1.2
  [ "$(sp_repeat_state)" = "track" ] && sp playback repeat >/dev/null 2>&1
}

# --- Target parsing --------------------------------------------------------

is_liked() {
  case "${1,,}" in
    liked|likes|ncspot:liked|*:collection:tracks|*:collection) return 0 ;;
    *) return 1 ;;
  esac
}

CTX_TYPE=""; CTX_ID=""
parse_context() {
  local raw="$1" rest
  CTX_TYPE=""; CTX_ID=""
  case "$raw" in
    spotify:playlist:*) CTX_TYPE=playlist; CTX_ID="${raw##*:}" ;;
    spotify:album:*)    CTX_TYPE=album;    CTX_ID="${raw##*:}" ;;
    spotify:artist:*)   CTX_TYPE=artist;   CTX_ID="${raw##*:}" ;;
    *open.spotify.com/*)
      rest="${raw#*open.spotify.com/}"
      case "$rest" in intl-*/*) rest="${rest#*/}" ;; esac
      case "$rest" in
        playlist/*) CTX_TYPE=playlist ;;
        album/*)    CTX_TYPE=album ;;
        artist/*)   CTX_TYPE=artist ;;
      esac
      CTX_ID="${rest#*/}"; CTX_ID="${CTX_ID%%\?*}"; CTX_ID="${CTX_ID%%/*}"
      ;;
    *) CTX_TYPE=playlist; CTX_ID="$raw" ;;   # bare id
  esac
}

start_soundtrack() {
  if is_liked "$PLAYLIST"; then
    log "start: liked"
    sp playback start liked >/dev/null 2>&1
  else
    parse_context "$PLAYLIST"
    [ -z "$CTX_ID" ] && { notify "No soundtrack configured"; return 1; }
    log "start: context $CTX_TYPE $CTX_ID"
    sp playback start context "$CTX_TYPE" --id "$CTX_ID" >/dev/null 2>&1
  fi
}

# Start and confirm it is actually playing on our device (a freshly connected
# device can ignore the first request while it settles).
start_soundtrack_verified() {
  local i
  for i in 1 2 3 4; do
    start_soundtrack || return 1
    sleep 2
    [ "$(sp_playback_status)" = "true" ] && { log "playing (attempt $i)"; return 0; }
    sp playback play >/dev/null 2>&1
    sleep 1
    [ "$(sp_playback_status)" = "true" ] && { log "playing after play (attempt $i)"; return 0; }
  done
  return 1
}

# --- Now-playing watcher ---------------------------------------------------

stop_nowplay_watcher() {
  [ -f "$NOWPLAY_PID_FILE" ] && kill "$(cat "$NOWPLAY_PID_FILE")" 2>/dev/null
  rm -f "$NOWPLAY_PID_FILE"
}

start_nowplay_watcher() {
  stop_nowplay_watcher
  (
    local last="" pj name artists msg
    while :; do
      pj="$(sp get key playback)"
      if [ "$(echo "$pj" | jq -r '.is_playing // false' 2>/dev/null)" = "true" ]; then
        name="$(echo "$pj" | jq -r '.item.name // empty' 2>/dev/null)"
        if [ -n "$name" ] && [ "$name" != "$last" ]; then
          last="$name"
          artists="$(echo "$pj" | jq -r '(.item.artists // []) | map(.name) | join(", ")' 2>/dev/null)"
          msg="$name"; [ -n "$artists" ] && msg="$name — $artists"
          notify "♪ $msg"
        fi
      fi
      sleep 3
    done
  ) >/dev/null 2>&1 &
  echo $! > "$NOWPLAY_PID_FILE"
  disown 2>/dev/null || true
}

# --- Actions ---------------------------------------------------------------

engage() {
  log "=== ENGAGE playlist='$PLAYLIST' vol=$VOLUME ws=$SPOTIFY_WS shuffle=$SHUFFLE nowplay=$NOWPLAY"
  have spotify_player || { notify "spotify_player not installed — run scripts/install-spotify-player.sh"; return; }

  sp_running || { log "launching spotify_player"; launch_spotify; }
  place_class_on_ws "$SPOTIFY_CLASS" "$SPOTIFY_WS"

  local dev
  if ! dev="$(sp_wait_device)"; then
    log "device never appeared"
    notify "spotify_player device didn't come up (authenticated? Premium?)"
    return
  fi
  local i
  for i in $(seq 1 8); do sp connect --name "$dev" >/dev/null 2>&1 && break; sleep 1; done
  log "connected to device: $dev"

  # Remember the pre-session device volume so it can be restored on stop.
  local prev; prev="$(sp_device_volume)"
  echo "${prev:-100}" > "$PREV_VOL_FILE"

  if [ "$SHUFFLE" = "1" ]; then
    # Random start: begin MUTED, shuffle on, skip a few tracks to a varied first
    # song, then unmute to the focus volume (contexts always begin at track 1).
    sp playback volume 0 >/dev/null 2>&1
    if start_soundtrack_verified; then
      sp_ensure_shuffle_on
      local n=$(( (RANDOM % 4) + 2 ))     # 2..5
      local k
      for ((k = 0; k < n; k++)); do sp playback next >/dev/null 2>&1; sleep 0.7; done
      [[ "$VOLUME" =~ ^[0-9]+$ ]] && sp playback volume "$VOLUME" >/dev/null 2>&1   # always unmute
      ensure_repeat_context
      log "playing='$(sp_track_name)' setVol=$VOLUME (random start)"
    else
      [[ "$VOLUME" =~ ^[0-9]+$ ]] && sp playback volume "$VOLUME" >/dev/null 2>&1   # never strand at 0
      notify "Couldn't start the soundtrack"
    fi
  else
    [[ "$VOLUME" =~ ^[0-9]+$ ]] && sp playback volume "$VOLUME" >/dev/null 2>&1
    if start_soundtrack_verified; then ensure_repeat_context; else notify "Couldn't start the soundtrack"; fi
  fi

  [ "$NOWPLAY" = "1" ] && start_nowplay_watcher
  log "=== ENGAGE done ==="
}

release() {
  log "=== RELEASE ==="
  stop_nowplay_watcher
  if have spotify_player && sp_running; then
    if [ -f "$PREV_VOL_FILE" ]; then
      local v; v="$(cat "$PREV_VOL_FILE")"
      [[ "$v" =~ ^[0-9]+$ ]] && sp playback volume "$v" >/dev/null 2>&1
      rm -f "$PREV_VOL_FILE"
    fi
    sp playback pause >/dev/null 2>&1
  fi
}

do_break() {
  log "break: pause"
  have spotify_player && sp_running && sp playback pause >/dev/null 2>&1 || true
}

do_resume() {
  log "resume: play"
  have spotify_player && sp_running || return 0
  sp playback play >/dev/null 2>&1
  sleep 0.8
  # Spotify can deactivate the librespot device during a break, so a bare play
  # has no track to resume — reconnect and restart the soundtrack.
  [ -z "$(sp_track_name)" ] && { log "resume: device dropped, re-engaging"; engage; }
}

do_next() {
  have spotify_player && sp_running && sp playback next >/dev/null 2>&1 || true
}

case "$ACTION" in
  on)     engage ;;
  off)    release ;;
  break)  do_break ;;
  resume) do_resume ;;
  next)   do_next ;;
  *)      echo "usage: $0 <on|off|break|resume|next> <playlist> <volume> <workspace> <shuffle> <nowplay>" >&2; exit 2 ;;
esac
