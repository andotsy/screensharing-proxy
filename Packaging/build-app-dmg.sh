#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${SSP_VERSION:?Set SSP_VERSION to the release version}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]
bash Packaging/build-app.sh
stage=$(mktemp -d "$PWD/.build/app-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto .build/native-bundle/ScreenSharingProxy.app "$stage/ScreenSharingProxy.app"
cp Packaging/README.html "$stage/README.html"
ln -s /Applications "$stage/Applications"
ln -s /System/Applications/Utilities/Terminal.app "$stage/Terminal"
mkdir -p dist
dmg="dist/ScreenSharingProxy-v$version-macOS-arm64.dmg"
if [[ -e "$dmg" ]]; then
    printf 'The output DMG already exists; use a new version or remove the earlier local build.\n' >&2
    exit 1
fi
hdiutil create -volname 'Screen Sharing Proxy' -fs HFS+ -format UDZO -srcfolder "$stage" "$dmg"
hdiutil verify "$dmg"
printf 'Built %s\n' "$dmg"
