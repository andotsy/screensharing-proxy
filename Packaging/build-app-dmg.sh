#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${SSP_VERSION:?Set SSP_VERSION to the release version}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]
bash Packaging/build-app.sh
mkdir -p dist
dmg="dist/ScreenSharingProxy-v$version-macOS-arm64.dmg"
if [[ -e "$dmg" ]]; then
    printf 'The output DMG already exists; use a new version or remove the earlier local build.\n' >&2
    exit 1
fi
python3 -m venv .build/dmg-venv
.build/dmg-venv/bin/python -m pip install --disable-pip-version-check -r Packaging/requirements.txt
swift -warnings-as-errors Packaging/dmg-background.swift .build/dmg-background .build/native-bundle/ScreenSharingProxy.app
.build/dmg-venv/bin/dmgbuild -s Packaging/dmg-settings.py "Screen Sharing Proxy v$version" "$dmg"
hdiutil verify "$dmg"
printf 'Built %s\n' "$dmg"
