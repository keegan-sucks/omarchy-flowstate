#!/usr/bin/env bash
#
# install-ncspot.sh — opt-in: install ncspot, the recommended music player for
# Flowstate. ncspot supports shuffle over MPRIS (the official Spotify Linux
# client does not). After installing, run `ncspot` once to log in (Spotify
# Premium required for playback).
#
#   ./install-ncspot.sh

set -euo pipefail

if command -v ncspot >/dev/null 2>&1; then
  echo "ncspot is already installed ($(ncspot --version 2>/dev/null))."
  exit 0
fi

if command -v omarchy-pkg >/dev/null 2>&1 || omarchy pkg --help >/dev/null 2>&1; then
  omarchy pkg add ncspot
elif command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --needed ncspot
else
  echo "Couldn't find omarchy pkg or pacman. Install 'ncspot' with your package manager." >&2
  exit 1
fi

echo
echo "ncspot installed. Run 'ncspot' once in a terminal to log in (Premium required)."
echo "Flowstate will then prefer ncspot automatically."
