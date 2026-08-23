#!/usr/bin/env bash
#
# install-blocker.sh — one-time setup for Flowstate's site blocking.
# Installs the privileged hosts helper to a root-owned path and adds a scoped
# NOPASSWD sudoers rule so the plugin can toggle /etc/hosts without a password.
#
#   sudo ./install-blocker.sh          # install
#   sudo ./install-blocker.sh --uninstall
#
# The core plugin (timer, Spotify, Obsidian) works without this; only site
# blocking depends on it.

set -euo pipefail

DEST="/usr/local/bin/flowstate-hosts"
SUDOERS="/etc/sudoers.d/flowstate"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC_DIR}/flowstate-hosts.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$DEST" "$SUDOERS"
  echo "Flowstate blocker removed."
  exit 0
fi

if [ ! -f "$SRC" ]; then
  echo "Cannot find flowstate-hosts.sh next to this script ($SRC)." >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-root}"

# Install the helper root-owned and NOT writable by the target user — this is
# what makes the NOPASSWD rule safe (the user can run it but cannot alter it).
install -o root -g root -m 0755 "$SRC" "$DEST"

TMP="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: %s\n' "$TARGET_USER" "$DEST" > "$TMP"
chmod 0440 "$TMP"

if visudo -c -f "$TMP" >/dev/null; then
  install -o root -g root -m 0440 "$TMP" "$SUDOERS"
  rm -f "$TMP"
else
  rm -f "$TMP"
  echo "sudoers validation failed; nothing changed." >&2
  exit 1
fi

echo "Flowstate blocker installed."
echo "  helper : $DEST"
echo "  sudoers: $SUDOERS ($TARGET_USER may toggle blocking without a password)"
