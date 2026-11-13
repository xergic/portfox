#!/bin/bash
# dmgbuild writes Finder metadata directly, so CI needs no Finder session.
set -euo pipefail

app=${1:?usage: make-dmg.sh <app> <output.dmg> [volume-name]}
dmg=${2:?usage: make-dmg.sh <app> <output.dmg> [volume-name]}
volume=${3:-Portfox}

scripts=$(cd "$(dirname "$0")" && pwd)
if ! command -v dmgbuild >/dev/null; then
  echo "Install the DMG tools: python3 -m venv .venv-dmg && .venv-dmg/bin/pip install -r Tools/dmg/requirements.txt" >&2
  echo "Then add .venv-dmg/bin to PATH." >&2
  exit 1
fi
if [ ! -d "$app/Contents" ] || [[ "$app" != *.app ]]; then
  echo "Expected a macOS .app bundle: $app" >&2
  exit 1
fi
app=$(cd "$(dirname "$app")" && pwd)/$(basename "$app")

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

swift "$scripts/dmg/render-background.swift" "$stage/background.tiff"

rm -f "$dmg"
dmgbuild -s "$scripts/dmg/settings.py" -D "app=$app" \
  -D "background=$stage/background.tiff" "$volume" "$dmg"
echo "$dmg"
