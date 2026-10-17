#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${SSP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :SSPReleaseVersion' Packaging/Info.plist)}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
test "$(/usr/libexec/PlistBuddy -c 'Print :SSPReleaseVersion' Packaging/Info.plist)" = "$version"
swift build -c release -Xswiftc -warnings-as-errors
test "$(.build/release/ScreenSharingProxy --version)" = "Screen Sharing Proxy $version"
test "$(.build/release/screensharing-proxy-diagnose --version)" = "screensharing-proxy-diagnose $version"

bundle=.build/native-bundle/ScreenSharingProxy.app
rm -rf .build/native-bundle
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" .build/AppIcon.iconset
cp Packaging/Info.plist "$bundle/Contents/Info.plist"
cp .build/release/ScreenSharingProxy .build/release/screensharing-proxy-diagnose "$bundle/Contents/MacOS/"
swift Packaging/app-icon.swift Packaging/Artwork/AppIcon.png .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
plutil -lint "$bundle/Contents/Info.plist"
for executable in ScreenSharingProxy screensharing-proxy-diagnose; do
    test "$(lipo -archs "$bundle/Contents/MacOS/$executable")" = arm64
    test "$(xcrun vtool -show-build "$bundle/Contents/MacOS/$executable" | awk '$1 == "minos" { print $2 }')" = 14.0
done
codesign --force --sign - --identifier com.andotsy.screensharing-proxy.diagnose "$bundle/Contents/MacOS/screensharing-proxy-diagnose"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
printf 'Built %s\n' "$bundle"
