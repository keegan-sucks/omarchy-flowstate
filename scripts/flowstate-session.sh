#!/usr/bin/env bash
#
# flowstate-session.sh — unprivileged focus-session orchestrator.
# Invoked by the Flowstate plugin (Quickshell.execDetached), never by hand.
#
# Usage:
#   flowstate-session.sh <on|off> <playlistUri> <volume> \
#                        <blockSites 0|1> <openMusic 0|1> <openObsidian 0|1> \
#                        <categoriesCsv> <extraDomainsCsv> \
#                        <musicWorkspace> <playerPref auto|ncspot|spotify> <shuffle 0|1>
#
# Music player: ncspot is preferred when installed (it supports shuffle, which
# the official Spotify Linux client ignores over MPRIS); otherwise the official
# Spotify client is used. Both are driven over MPRIS.

set -uo pipefail

ACTION="${1:-}"
PLAYLIST="${2:-}"
VOLUME="${3:-40}"
BLOCK="${4:-0}"
OPEN_MUSIC="${5:-0}"
OBSIDIAN="${6:-0}"
CATEGORIES="${7:-}"
EXTRA_DOMAINS="${8:-}"
MUSIC_WS="${9:-9}"
PLAYER_PREF="${10:-auto}"
SHUFFLE="${11:-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BLOCKLIST_DIR="$SCRIPT_DIR/../blocklists"
HOSTS_BIN="/usr/local/bin/flowstate-hosts"
NCSPOT_CLASS="flowstate-ncspot"
MPRIS_OBJ="/org/mpris/MediaPlayer2"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/flowstate"
PREV_VOL_FILE="$STATE_DIR/prev-volume"

notify() {
  command -v omarchy-notification-send >/dev/null 2>&1 \
    && omarchy-notification-send -g "◷" "Flowstate" "$1" || true
}

# --- Player selection ------------------------------------------------------

# Resolve which player to use: prefer ncspot when installed unless overridden.
PLAYER="spotify"
case "$PLAYER_PREF" in
  ncspot)  command -v ncspot  >/dev/null 2>&1 && PLAYER="ncspot" ;;
  spotify) PLAYER="spotify" ;;
  *)       command -v ncspot  >/dev/null 2>&1 && PLAYER="ncspot" ;;
esac
# Fall back if the chosen player isn't actually installed.
[ "$PLAYER" = "spotify" ] && ! command -v spotify >/dev/null 2>&1 \
  && command -v ncspot >/dev/null 2>&1 && PLAYER="ncspot"

# pactl application.name to match for per-app volume.
APP_NAME="spotify"; [ "$PLAYER" = "ncspot" ] && APP_NAME="ncspot"

BUS=""   # resolved once the player is up

player_running() { pgrep -x "$PLAYER" >/dev/null 2>&1; }

# The MPRIS bus name. Spotify's is fixed; ncspot's carries an instance suffix.
player_bus() {
  if [ "$PLAYER" = "spotify" ]; then
    echo "org.mpris.MediaPlayer2.spotify"
  else
    dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.ListNames 2>/dev/null \
      | grep -o 'org.mpris.MediaPlayer2.ncspot[^"]*' | head -1
  fi
}

player_ready() {
  local b; b="$(player_bus)"
  [ -n "$b" ] || return 1
  dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner string:"$b" 2>/dev/null | grep -q "boolean true"
}

launch_app() {
  if command -v uwsm >/dev/null 2>&1; then setsid uwsm app -- "$@" >/dev/null 2>&1 &
  elif command -v gtk-launch >/dev/null 2>&1; then setsid gtk-launch "$1" >/dev/null 2>&1 &
  else setsid "$@" >/dev/null 2>&1 & fi
}

# Launch ncspot inside a terminal, tagged with a class so a Hyprland window
# rule can place it (see scripts/install-workspace-rule.sh).
launch_ncspot() {
  if command -v ghostty >/dev/null 2>&1; then
    setsid ghostty --class="$NCSPOT_CLASS" -e ncspot >/dev/null 2>&1 &
  elif command -v alacritty >/dev/null 2>&1; then
    setsid alacritty --class "$NCSPOT_CLASS" -e ncspot >/dev/null 2>&1 &
  elif command -v kitty >/dev/null 2>&1; then
    setsid kitty --class "$NCSPOT_CLASS" ncspot >/dev/null 2>&1 &
  elif command -v foot >/dev/null 2>&1; then
    setsid foot --app-id="$NCSPOT_CLASS" ncspot >/dev/null 2>&1 &
  elif command -v wezterm >/dev/null 2>&1; then
    setsid wezterm start --class "$NCSPOT_CLASS" -- ncspot >/dev/null 2>&1 &
  else
    setsid xterm -e ncspot >/dev/null 2>&1 &
  fi
}

launch_player() {
  if [ "$PLAYER" = "ncspot" ]; then launch_ncspot; else launch_app spotify; fi
}

# --- MPRIS helpers (operate on $BUS) ---------------------------------------

mpris() {
  local method="$1"; shift
  dbus-send --print-reply --dest="$BUS" "$MPRIS_OBJ" \
    "org.mpris.MediaPlayer2.Player.${method}" "$@" >/dev/null 2>&1
}

player_status() {
  dbus-send --print-reply --dest="$BUS" "$MPRIS_OBJ" \
    org.freedesktop.DBus.Properties.Get \
    string:org.mpris.MediaPlayer2.Player string:PlaybackStatus 2>/dev/null \
    | grep -o 'string "[^"]*"' | tail -1 | sed 's/string "//;s/"//'
}

set_shuffle() {
  dbus-send --print-reply --dest="$BUS" "$MPRIS_OBJ" \
    org.freedesktop.DBus.Properties.Set string:org.mpris.MediaPlayer2.Player \
    string:Shuffle variant:boolean:"$1" >/dev/null 2>&1 || true
}

player_sink_exists() {
  pactl list sink-inputs 2>/dev/null | grep -qiE "application\.name = \"${APP_NAME}\""
}

get_player_volume() {
  pactl list sink-inputs 2>/dev/null | awk -v app="$APP_NAME" '
    BEGIN { RS = "Sink Input #" }
    tolower($0) ~ ("application.name = \"" app "\"") {
      if (match($0, /[0-9]+%/)) { print substr($0, RSTART, RLENGTH - 1); exit }
    }'
}

set_player_volume() {
  local pct="$1" id=""
  [[ "$pct" =~ ^[0-9]+$ ]] || return 0
  (( pct > 100 )) && pct=100
  while IFS= read -r line; do
    case "$line" in
      "Sink Input #"*) id="${line#Sink Input #}" ;;
      *application.name*)
        case "${line,,}" in
          *"application.name = \"${APP_NAME}\""*)
            [ -n "$id" ] && pactl set-sink-input-volume "$id" "${pct}%" 2>/dev/null || true ;;
        esac ;;
    esac
  done < <(pactl list sink-inputs 2>/dev/null)
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
  # 1. Block distracting sites.
  if [ "$BLOCK" = "1" ]; then
    if [ -x "$HOSTS_BIN" ]; then
      local domains; domains="$(build_domains)"
      if [ -n "$domains" ]; then
        if printf '%s\n' "$domains" | sudo -n "$HOSTS_BIN" on 2>/dev/null; then
          resolvectl flush-caches 2>/dev/null || true
        else
          notify "Site blocking not set up — run scripts/install-blocker.sh"
        fi
      fi
    else
      notify "Site blocking not set up — run scripts/install-blocker.sh"
    fi
  fi

  # 2. Open Obsidian (only if not already running).
  if [ "$OBSIDIAN" = "1" ] && ! pgrep -x obsidian >/dev/null 2>&1; then
    launch_app obsidian
  fi

  # 3. Open the music player and start the soundtrack.
  if [ "$OPEN_MUSIC" = "1" ]; then
    local was_running=1
    player_running || was_running=0
    player_running || launch_player

    local i
    for i in $(seq 1 60); do player_ready && break; sleep 0.5; done
    BUS="$(player_bus)"

    if [ -n "$BUS" ] && player_ready; then
      # Capture the pre-session volume BEFORE OpenUri (which starts a fresh
      # 100% stream) so it can be restored later.
      local prev=""
      if [ "$was_running" = "1" ]; then
        for i in $(seq 1 20); do player_sink_exists && break; sleep 0.5; done
        prev="$(get_player_volume)"
      else
        sleep 3
      fi

      if [ -n "$PLAYLIST" ]; then
        mpris OpenUri string:"$PLAYLIST"
        sleep 2
      fi

      for i in $(seq 1 8); do
        [ "$(player_status)" = "Playing" ] && break
        mpris Play
        sleep 1
      done

      # Always-shuffle (honored by ncspot; ignored by the official client).
      [ "$SHUFFLE" = "1" ] && set_shuffle true

      for i in $(seq 1 20); do player_sink_exists && break; sleep 0.5; done
      sleep 1
      mkdir -p "$STATE_DIR"
      echo "${prev:-100}" > "$PREV_VOL_FILE"
      set_player_volume "$VOLUME"
    else
      notify "Music player didn't come up in time"
    fi
  fi
}

release() {
  # Unblock sites.
  if [ "$BLOCK" = "1" ] && [ -x "$HOSTS_BIN" ]; then
    sudo -n "$HOSTS_BIN" off 2>/dev/null && resolvectl flush-caches 2>/dev/null || true
  fi

  # Restore the pre-session volume, then pause. (Obsidian is left open.)
  if [ "$OPEN_MUSIC" = "1" ]; then
    BUS="$(player_bus)"
    if [ -n "$BUS" ] && player_ready; then
      if [ -f "$PREV_VOL_FILE" ]; then
        set_player_volume "$(cat "$PREV_VOL_FILE")"
        rm -f "$PREV_VOL_FILE"
      fi
      mpris Pause
    fi
  fi
}

case "$ACTION" in
  on)  engage ;;
  off) release ;;
  *)   echo "usage: $0 <on|off> ..." >&2; exit 2 ;;
esac
