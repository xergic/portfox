#!/bin/bash
# hdiutil, not create-dmg. The pretty-window variants position icons by driving
# Finder over AppleScript, which has no session to talk to on a CI runner.
set -euo pipefail

app=${1:?usage: make-dmg.sh <app> <output.dmg> [volume-name]}
dmg=${2:?usage: make-dmg.sh <app> <output.dmg> [volume-name]}
volume=${3:-Portfox}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
hdiutil create -volname "$volume" -srcfolder "$stage" -ov -format UDZO -quiet "$dmg"
echo "$dmg"
