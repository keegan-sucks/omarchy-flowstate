#!/usr/bin/env bash
#
# install-spotify-player.sh — install spotify_player, the music engine Flowstate
# drives. spotify_player is a terminal Spotify client that doubles as its own
# Spotify Connect streaming device and CLI server, which is what makes
# first-class shuffle, Liked Songs, and scripted volume control possible.
#
#   ./install-spotify-player.sh
#
# Spotify Premium is required for playback/streaming. After installing, you must
# authenticate once (this script offers to run it for you):
#
#   spotify_player authenticate
#
set -euo pipefail

if command -v spotify_player >/dev/null 2>&1; then
  echo "spotify_player is already installed ($(spotify_player --version 2>/dev/null))."
else
  echo "Installing spotify-player (AUR; this compiles from source and may take a few minutes)…"
  if command -v omarchy >/dev/null 2>&1 && omarchy pkg --help >/dev/null 2>&1; then
    # Omarchy's package helper (routes AUR packages to the AUR helper).
    omarchy pkg aur add spotify-player 2>/dev/null || omarchy pkg add spotify-player
  elif command -v paru >/dev/null 2>&1; then
    paru -S --needed spotify-player
  elif command -v yay >/dev/null 2>&1; then
    yay -S --needed spotify-player
  else
    echo "No AUR helper (paru/yay) or omarchy pkg found." >&2
    echo "Install 'spotify-player' from the AUR manually, then re-run." >&2
    exit 1
  fi
fi

echo
echo "spotify_player installed."
echo
echo "Authentication (Spotify Premium required):"
echo "  spotify_player authenticate"
echo "  → opens a browser for the OAuth login, then a librespot login for streaming."
echo
read -r -p "Run 'spotify_player authenticate' now? [Y/n] " ans || ans=""
case "${ans,,}" in
  n|no) echo "Skipped. Run 'spotify_player authenticate' before your first session." ;;
  *)    spotify_player authenticate ;;
esac
