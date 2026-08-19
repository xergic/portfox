#!/bin/bash
# The macos-26 image ships Xcode 26 as its default, but the default has drifted
# on past images. PortFox needs 26 for the Icon Composer .icon bundle, so pick
# the newest 26.x explicitly when the default is anything else.
set -euo pipefail

if [ "$(xcodebuild -version | awk 'NR==1 {print $2}' | cut -d. -f1)" != "26" ]; then
    newest=$(printf '%s\n' /Applications/Xcode_26*.app | sort -V | tail -1)
    if [ ! -d "$newest" ]; then
        echo "No Xcode 26 on this runner image. Installed:" >&2
        ls -d /Applications/Xcode*.app >&2
        exit 1
    fi
    sudo xcode-select -s "$newest"
fi

xcodebuild -version
