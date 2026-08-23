#!/usr/bin/env bash
#
# flowstate-session.sh — unprivileged focus-session orchestrator.
# Invoked by the Flowstate plugin (Quickshell.execDetached), never by hand.
#
# Usage:
#   flowstate-session.sh <on|off> <playlist> <volume> \
#                        <blockSites 0|1> <openSpotify 0|1> <openObsidian 0|1> \
#                        <categoriesCsv> <extraDomainsCsv> \
#                        <spotifyWorkspace> <focusWorkspace> \
#                        <isolateObsidian 0|1> <shuffle 0|1>
#
# Music is driven through spotify_player (https://github.com/aome510/spotify-player):
# a terminal TUI that is also its own Spotify Connect streaming device and CLI
# server. That gives first-class shuffle, Liked Songs, and volume control —
# things the official Linux client cannot do over MPRIS.

set -uo pipefail

ACTION="${1:-}"
PLAYLIST="${2:-}"
VOLUME="${3:-35}"
BLOCK="${4:-0}"
OPEN_SPOTIFY="${5:-0}"
OPEN_OBSIDIAN="${6:-0}"
CATEGORIES="${7:-}"
EXTRA_DOMAINS="${8:-}"
SPOTIFY_WS="${9:-9}"
FOCUS_WS_ARG="${10:-0}"
ISOLATE="${11:-1}"
SHUFFLE="${12:-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BLOCKLIST_DIR="$SCRIPT_DIR/../blocklists"
HOSTS_BIN="/usr/local/bin/flowstate-hosts"
SPOTIFY_CLASS="flowstate-spotify"       # window class for placement
PARK_WS="special:flowstate"             # hidden workspace for isolated windows
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/flowstate"
PREV_VOL_FILE="$STATE_DIR/prev-volume"
FOCUS_WS_FILE="$STATE_DIR/focus-workspace"
# Integrated-device name spotify_player registers (config device.name; default
# "spotify-player"). Overridable if you changed it in app.toml.
SP_DEVICE="${FLOWSTATE_SP_DEVICE:-spotify-player}"

mkdir -p "$STATE_DIR"

LOG_FILE="$STATE_DIR/session.log"
log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

notify() {
  command -v omarchy-notification-send >/dev/null 2>&1 \
    && omarchy-notification-send -g "◷" "Flowstate" "$1" || true
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- Launchers -------------------------------------------------------------

launch_app() {
  if have uwsm; then setsid uwsm app -- "$@" >/dev/null 2>&1 &
  elif have gtk-launch; then setsid gtk-launch "$1" >/dev/null 2>&1 &
  else setsid "$@" >/dev/null 2>&1 & fi
}

# Launch spotify_player inside a terminal, tagged with a class so it can be
# placed on the music workspace.
launch_spotify() {
  if have ghostty; then setsid ghostty --class="$SPOTIFY_CLASS" -e spotify_player >/dev/null 2>&1 &
  elif have alacritty; then setsid alacritty --class "$SPOTIFY_CLASS" -e spotify_player >/dev/null 2>&1 &
  elif have kitty; then setsid kitty --class "$SPOTIFY_CLASS" spotify_player >/dev/null 2>&1 &
  elif have foot; then setsid foot --app-id="$SPOTIFY_CLASS" spotify_player >/dev/null 2>&1 &
  elif have wezterm; then setsid wezterm start --class "$SPOTIFY_CLASS" -- spotify_player >/dev/null 2>&1 &
  else setsid xterm -e spotify_player >/dev/null 2>&1 & fi
}

# --- Hyprland window placement --------------------------------------------

hypr_addr_by_class() {  # exact case-insensitive class match -> addresses, one per line
  local cls="${1,,}"
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg c "$cls" '.[] | select((.class // "" | ascii_downcase) == $c) | .address'
}

# Obsidian is an Electron app; its Hyprland class is "md.obsidian.Obsidian" and
# its process name isn't a clean "obsidian", so match on a substring instead.
obsidian_addrs() {
  hyprctl clients -j 2>/dev/null \
    | jq -r '.[] | select((.class // "" | ascii_downcase) | contains("obsidian")) | .address'
}

obsidian_running() {
  obsidian_addrs | grep -q . && return 0
  pgrep -fi '(^|/)obsidian' >/dev/null 2>&1
}

active_ws_id() { hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1'; }

# Hyprland 0.56 dispatches via a Lua API: `hyprctl dispatch` evaluates its arg
# as Lua where hl.dsp.* are the dispatchers. The classic string form
# ("movetoworkspacesilent 9,address:X") is gone — it errors as invalid Lua.
hdisp() { hyprctl dispatch "$1" >/dev/null 2>&1; }

# Move a specific window (by address) to a workspace, silently (follow=false).
move_window_to_ws() {  # <address> <workspace>
  hdisp "hl.dsp.window.move({ workspace = \"$2\", follow = false, window = \"address:$1\" })"
}

place_class_on_ws() {  # <class> <ws>  (silent; waits briefly for the window)
  local cls="$1" ws="$2" a i
  [ "$ws" -gt 0 ] 2>/dev/null || return 0
  for i in $(seq 1 40); do
    a="$(hypr_addr_by_class "$cls" | head -1)"
    [ -n "$a" ] && break
    sleep 0.25
  done
  hypr_addr_by_class "$cls" | while IFS= read -r a; do
    [ -n "$a" ] && move_window_to_ws "$a" "$ws"
  done
}

# Park every window currently on $1 that is NOT Obsidian into the hidden
# special workspace, so Obsidian is left alone on the focus workspace.
park_others() {
  local ws="$1" a
  hyprctl clients -j 2>/dev/null \
    | jq -r --argjson ws "$ws" '.[] | select(.workspace.id == $ws and (((.class // "" | ascii_downcase) | contains("obsidian")) | not)) | .address' \
    | while IFS= read -r a; do
        [ -n "$a" ] && move_window_to_ws "$a" "$PARK_WS"
      done
}

# Move everything we parked back onto the focus workspace.
unpark_to() {
  local ws="$1" a
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg w "$PARK_WS" '.[] | select((.workspace.name // "") == $w) | .address' \
    | while IFS= read -r a; do
        [ -n "$a" ] && move_window_to_ws "$a" "$ws"
      done
}

# --- spotify_player CLI helpers -------------------------------------------

sp() { spotify_player "$@" 2>/dev/null; }

sp_running() { pgrep -x spotify_player >/dev/null 2>&1; }

# Wait until spotify_player's OWN Connect device is visible to the Web API, then
# echo its exact name. We never fall back to another device — controlling the
# user's phone/desktop is exactly the bug we must avoid.
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
sp_device_volume()   { sp get key playback | jq -r '.device.volume_percent // empty' 2>/dev/null; }

sp_ensure_shuffle_on() {
  [ "$(sp_shuffle_state)" = "true" ] && return 0
  sp playback shuffle >/dev/null 2>&1 || true
}

# A soundtrack "playlist" value that means "the user's Liked/Saved songs".
is_liked() {
  case "${1,,}" in
    liked|likes|ncspot:liked|*:collection:tracks|*:collection) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse a Spotify URI or share URL into CTX_TYPE (playlist|album|artist) and
# CTX_ID (bare base62 id). Bare ids are assumed to be playlists.
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
      # strip an optional locale segment like "intl-de/"
      case "$rest" in intl-*/*) rest="${rest#*/}" ;; esac
      case "$rest" in
        playlist/*) CTX_TYPE=playlist ;;
        album/*)    CTX_TYPE=album ;;
        artist/*)   CTX_TYPE=artist ;;
      esac
      CTX_ID="${rest#*/}"; CTX_ID="${CTX_ID%%\?*}"; CTX_ID="${CTX_ID%%/*}"
      ;;
    *)
      # bare id
      CTX_TYPE=playlist; CTX_ID="$raw"
      ;;
  esac
}

start_soundtrack() {
  if is_liked "$PLAYLIST"; then
    # NOTE: `start liked --random` is broken in spotify_player 0.24.1 (it leaves
    # the previous context untouched and doesn't play). Plain `start liked`
    # works; shuffle is applied separately via sp_ensure_shuffle_on.
    log "start: liked"
    sp playback start liked >/dev/null 2>&1
  else
    parse_context "$PLAYLIST"
    if [ -z "$CTX_ID" ]; then
      notify "No soundtrack configured"
      return 1
    fi
    log "start: context $CTX_TYPE $CTX_ID (shuffle=$SHUFFLE)"
    if [ "$SHUFFLE" = "1" ]; then
      sp playback start context "$CTX_TYPE" --id "$CTX_ID" --shuffle >/dev/null 2>&1
    else
      sp playback start context "$CTX_TYPE" --id "$CTX_ID" >/dev/null 2>&1
    fi
  fi
}

# Start the soundtrack and make sure it is actually playing on our device;
# retry a few times because a freshly connected device can ignore the first
# request while it settles.
start_soundtrack_verified() {
  local i
  for i in 1 2 3 4; do
    start_soundtrack
    sleep 2
    if [ "$(sp_playback_status)" = "true" ]; then
      log "playback confirmed playing (attempt $i)"
      return 0
    fi
    sp playback play >/dev/null 2>&1
    sleep 1
    [ "$(sp_playback_status)" = "true" ] && { log "playback confirmed after play (attempt $i)"; return 0; }
    log "not playing yet (attempt $i)"
  done
  return 1
}

# --- Blocklist -------------------------------------------------------------

build_domains() {
  {
    local c f
    IFS=',' read -ra cats <<< "$CATEGORIES"
    for c in "${cats[@]}"; do
      c="${c//[[:space:]]/}"
      [ -z "$c" ] && continue
      f="$BLOCKLIST_DIR/${c}.txt"
      [ -f "$f" ] && grep -vE '^[[:space:]]*(#|$)' "$f"
    done
    local e
    IFS=',' read -ra extras <<< "$EXTRA_DOMAINS"
    for e in "${extras[@]}"; do echo "$e"; done
  } | tr ',[:space:]' '\n' | awk 'NF' | while IFS= read -r d; do
        echo "$d"
        case "$d" in www.*) ;; *) echo "www.$d" ;; esac
      done | sort -u
}

# --- Engage / release ------------------------------------------------------

engage() {
  log "=== ENGAGE playlist='$PLAYLIST' vol=$VOLUME block=$BLOCK spotify=$OPEN_SPOTIFY obsidian=$OPEN_OBSIDIAN spWS=$SPOTIFY_WS focusWS=$FOCUS_WS_ARG isolate=$ISOLATE shuffle=$SHUFFLE"
  log "env: hyprctl=$(command -v hyprctl || echo none) HIS=${HYPRLAND_INSTANCE_SIGNATURE:-unset}"

  # 1. Block distracting sites. (/etc/hosts is consulted before DNS via nss
  #    'files', so no cache flush is needed — which also avoids a polkit prompt.)
  if [ "$BLOCK" = "1" ]; then
    if [ -x "$HOSTS_BIN" ]; then
      local domains; domains="$(build_domains)"
      if [ -n "$domains" ]; then
        if printf '%s\n' "$domains" | sudo -n "$HOSTS_BIN" on 2>/dev/null; then
          log "blocked $(printf '%s\n' "$domains" | wc -l) domains"
        else
          log "block FAILED (sudo -n $HOSTS_BIN on)"
          notify "Site blocking not set up — run scripts/install-blocker.sh"
        fi
      fi
    else
      log "block skipped: helper missing"
      notify "Site blocking not set up — run scripts/install-blocker.sh"
    fi
  fi

  # 2. Obsidian: launch, place on the focus workspace, and isolate it there.
  if [ "$OPEN_OBSIDIAN" = "1" ]; then
    local focus_ws="$FOCUS_WS_ARG"
    [ "$focus_ws" = "0" ] && focus_ws="$(active_ws_id)"
    echo "$focus_ws" > "$FOCUS_WS_FILE"
    log "obsidian: focus_ws=$focus_ws running=$(obsidian_running && echo yes || echo no)"

    have obsidian && ! obsidian_running && { log "launching obsidian"; launch_app obsidian; }

    local a i
    for i in $(seq 1 80); do
      a="$(obsidian_addrs | head -1)"
      [ -n "$a" ] && break
      sleep 0.25
    done
    log "obsidian addr=${a:-none}"

    if [ -n "$a" ]; then
      obsidian_addrs | while IFS= read -r addr; do
        [ -n "$addr" ] && move_window_to_ws "$addr" "$focus_ws"
      done
      [ "$ISOLATE" = "1" ] && { park_others "$focus_ws"; log "parked others off ws $focus_ws"; }
      hdisp "hl.dsp.focus({ workspace = \"$focus_ws\" })"
      hdisp "hl.dsp.focus({ window = \"address:$a\" })"
      log "obsidian moved to ws $focus_ws and focused"
    else
      log "obsidian window not found"
      notify "Obsidian didn't open in time"
    fi
  fi

  # 3. Spotify via spotify_player: launch (out of the way), start the
  #    soundtrack shuffled, set the focus volume (restoring it on release).
  if [ "$OPEN_SPOTIFY" = "1" ]; then
    if ! have spotify_player; then
      log "spotify_player not installed"
      notify "spotify_player not installed — run scripts/install-spotify-player.sh"
      return
    fi

    if sp_running; then log "spotify_player already running"; else log "launching spotify_player in $SPOTIFY_CLASS"; launch_spotify; fi
    place_class_on_ws "$SPOTIFY_CLASS" "$SPOTIFY_WS"
    log "placed $SPOTIFY_CLASS on ws $SPOTIFY_WS (addr=$(hypr_addr_by_class "$SPOTIFY_CLASS" | head -1))"

    local dev
    if dev="$(sp_wait_device)"; then
      log "device found: $dev"
      # Route control to OUR integrated device; retry, it may still be settling.
      for i in $(seq 1 8); do sp connect --name "$dev" >/dev/null 2>&1 && break; sleep 1; done
      log "connected; playback device now: $(sp get key playback | jq -r '.device.name // "none"' 2>/dev/null)"

      if start_soundtrack_verified; then
        [ "$SHUFFLE" = "1" ] && { sp_ensure_shuffle_on; log "shuffle ensured on"; }
        # Capture the pre-session device volume, then dip to the focus volume.
        local prev; prev="$(sp_device_volume)"
        echo "${prev:-100}" > "$PREV_VOL_FILE"
        [[ "$VOLUME" =~ ^[0-9]+$ ]] && sp playback volume "$VOLUME" >/dev/null 2>&1
        log "playing='$(sp get key playback | jq -r '.item.name // "?"' 2>/dev/null)' prevVol=${prev:-100} setVol=$VOLUME"
      else
        log "playback FAILED to start"
        notify "Couldn't start the soundtrack"
      fi
    else
      log "device never appeared (auth/Premium?)"
      notify "spotify_player device didn't come up (is it authenticated? Premium?)"
    fi
  fi
  log "=== ENGAGE done ==="
}

release() {
  log "=== RELEASE ==="
  # Unblock sites.
  if [ "$BLOCK" = "1" ] && [ -x "$HOSTS_BIN" ]; then
    sudo -n "$HOSTS_BIN" off 2>/dev/null || true
  fi

  # Un-isolate: move parked windows back onto the focus workspace.
  if [ "$OPEN_OBSIDIAN" = "1" ] && [ "$ISOLATE" = "1" ]; then
    local focus_ws="0"
    [ -f "$FOCUS_WS_FILE" ] && focus_ws="$(cat "$FOCUS_WS_FILE")"
    [ "$focus_ws" = "0" ] && focus_ws="$(active_ws_id)"
    unpark_to "$focus_ws"
  fi

  # Restore the pre-session Spotify volume, then pause. (Obsidian stays open.)
  if [ "$OPEN_SPOTIFY" = "1" ] && have spotify_player && sp_running; then
    if [ -f "$PREV_VOL_FILE" ]; then
      local v; v="$(cat "$PREV_VOL_FILE")"
      [[ "$v" =~ ^[0-9]+$ ]] && sp playback volume "$v" >/dev/null 2>&1
      rm -f "$PREV_VOL_FILE"
    fi
    sp playback pause >/dev/null 2>&1
  fi
}

case "$ACTION" in
  on)  engage ;;
  off) release ;;
  *)   echo "usage: $0 <on|off> ..." >&2; exit 2 ;;
esac
