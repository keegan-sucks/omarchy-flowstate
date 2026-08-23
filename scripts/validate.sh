#!/usr/bin/env bash
# Validate the plugin against the Omarchy manifest schema and lint the QML.
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

omarchy plugin validate "$plugin_dir"

if command -v qmllint >/dev/null 2>&1; then
  qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
    "$plugin_dir/FocusState.qml" \
    "$plugin_dir/BarWidget.qml" \
    "$plugin_dir/Panel.qml" \
    "$plugin_dir/CompactField.qml"
else
  echo "qmllint not found; skipped QML lint." >&2
fi
