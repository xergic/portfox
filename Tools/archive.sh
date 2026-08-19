#!/bin/bash
# A local stand-in for .github/workflows/release.yml, minus the Developer ID.
# The result is ad hoc signed, so whoever receives it has to clear the
# quarantine flag by hand. Tag a version instead when that is not acceptable.
set -euo pipefail

cd "$(dirname "$0")/.."

version=${1:-}
if [ -z "$version" ]; then
  version=$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
  version=${version#v}
fi
# Monotonic without a CI run number to borrow, which is what CFBundleVersion needs.
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

out=dist
archive="$out/PortFox.xcarchive"
app="$out/PortFox.app"
dmg="$out/PortFox-$version.dmg"

rm -rf "$out"
mkdir -p "$out"
make gen

# archive with a generic destination, never build. `xcodebuild build` resolves
# the destination to this Mac's own arch and silently ships a single slice.
xcodebuild archive \
  -project PortFox.xcodeproj \
  -scheme PortFox \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  -quiet \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build"

# -exportArchive wants a team and an export plist. Ad hoc signing has neither,
# so lift the app straight out of the archive.
cp -R "$archive/Products/Applications/PortFox.app" "$app"

archs=$(lipo -archs "$app/Contents/MacOS/PortFox")
for arch in arm64 x86_64; do
  case " $archs " in
    *" $arch "*) ;;
    *) echo "Missing the $arch slice, the build is not universal" >&2; exit 1 ;;
  esac
done

Tools/make-dmg.sh "$app" "$dmg" PortFox >/dev/null

echo "$dmg"
echo "version $version ($build), $archs"
echo "Ad hoc signed. The recipient runs: xattr -dr com.apple.quarantine /Applications/PortFox.app"
