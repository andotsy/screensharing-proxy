#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
swift build -c release --product screensharing-proxy-experiment -Xswiftc -warnings-as-errors
destination=dist/ScreenSharingProxy-IncomingExperiment-macOS-arm64
# The development archive is not a published release asset. Refuse replacement
# so previously collected reports beside an extracted command are never removed.
test ! -e "$destination"
test ! -e "$destination.zip"
mkdir -p "$destination"
cp .build/release/screensharing-proxy-experiment "$destination/"
cp -R .build/release/ScreenSharingProxy_ProxyCore.bundle "$destination/"
cp Packaging/RunIncomingExperiment.command "$destination/Run.command"
cp docs/INCOMING_EXPERIMENT_GUIDE.md "$destination/README.md"
git rev-parse HEAD > "$destination/SOURCE_COMMIT.txt"
if test -n "$(git status --porcelain)"; then
    printf 'Includes uncommitted working-tree changes.\n' >> "$destination/SOURCE_COMMIT.txt"
fi
chmod 755 "$destination/Run.command"
codesign --force --sign - --identifier com.andotsy.screensharing-proxy.experiment "$destination/screensharing-proxy-experiment"
codesign --verify --strict "$destination/screensharing-proxy-experiment"
test "$(lipo -archs "$destination/screensharing-proxy-experiment")" = arm64
"$destination/screensharing-proxy-experiment" --help > /dev/null
ditto -c -k --sequesterRsrc --keepParent "$destination" "$destination.zip"
shasum -a 256 "$destination.zip"
