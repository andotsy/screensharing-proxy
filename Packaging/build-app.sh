#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${SSP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :SSPReleaseVersion' Packaging/Info.plist)}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
test "$(/usr/libexec/PlistBuddy -c 'Print :SSPReleaseVersion' Packaging/Info.plist)" = "$version"
swift build -c release -Xswiftc -warnings-as-errors
test "$(.build/release/ScreenSharingProxy --version)" = "Screen Sharing Rubyfier $version"
test "$(.build/release/screensharing-proxy-diagnose --version)" = "screensharing-proxy-diagnose $version"

bundle=".build/native-bundle/Screen Sharing Rubyfier.app"
rm -rf .build/native-bundle
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" .build/AppIcon.iconset
cp Packaging/Info.plist "$bundle/Contents/Info.plist"
cp .build/release/ScreenSharingProxy .build/release/screensharing-proxy-diagnose "$bundle/Contents/MacOS/"
cp -R .build/release/ScreenSharingProxy_ProxyCore.bundle "$bundle/Contents/Resources/"
rm -rf .build/rubyfier-payload
bash Packaging/build-rubied-patcher.sh .build/rubyfier-payload
cp -R .build/rubyfier-payload "$bundle/Contents/Resources/Rubyfier"
# Assets.car carries the light, dark and tinted icon appearances for macOS 26.
xcrun actool "$PWD/Packaging/AppIcon.icon" --compile "$PWD/$bundle/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "$PWD/.build/app-icon-info.plist" --output-format human-readable-text
test -s "$bundle/Contents/Resources/Assets.car"
# Replace actool's partial ICNS with every size rendered from the compiled icon.
swift Packaging/app-icon.swift "$bundle" .build/AppIcon.iconset
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
