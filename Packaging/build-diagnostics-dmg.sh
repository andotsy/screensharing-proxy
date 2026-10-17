#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=${SSP_VERSION:?Set SSP_VERSION, for example 0.1.0-alpha.1}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-alpha\.[0-9]+)?$ ]]; then
    printf 'Invalid SSP_VERSION.\n' >&2
    exit 64
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf 'Build this diagnostic alpha on an Apple silicon Mac.\n' >&2
    exit 1
fi

swift build -c release -Xswiftc -warnings-as-errors
binary=.build/release/screensharing-proxy-diagnose
test "$("$binary" --version)" = "screensharing-proxy-diagnose $version"
test "$(lipo -archs "$binary")" = arm64
test "$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }')" = 14.0

stage=$(mktemp -d "$PWD/.build/diagnostics-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp "$binary" "$stage/screensharing-proxy-diagnose"
cp Packaging/README.html "$stage/README.html"
ln -s /System/Applications/Utilities/Terminal.app "$stage/Terminal"
codesign --force --sign - --identifier com.andotsy.screensharing-proxy.diagnose "$stage/screensharing-proxy-diagnose"
codesign --verify --strict "$stage/screensharing-proxy-diagnose"

mkdir -p dist
dmg="dist/ScreenSharingProxy-Diagnostics-v$version-macOS-arm64.dmg"
if [[ -e "$dmg" ]]; then
    printf 'The output DMG already exists; choose a new version or remove your earlier build.\n' >&2
    exit 1
fi
hdiutil create -volname 'Screen Sharing Proxy Diagnostics' -fs HFS+ -format UDZO -srcfolder "$stage" "$dmg"
hdiutil verify "$dmg"
printf 'Built %s\n' "$dmg"
