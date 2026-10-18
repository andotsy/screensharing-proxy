#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
swift build -c release --product screensharing-proxy-experiment -Xswiftc -warnings-as-errors
case "${1:-incoming}" in
  incoming)
    destination=dist/ScreenSharingProxy-IncomingExperiment-macOS-arm64
    launcher=Packaging/RunIncomingExperiment.command
    guide=docs/INCOMING_EXPERIMENT_GUIDE.md ;;
  loopback)
    destination=dist/ScreenSharingProxy-LoopbackExperiment-macOS-arm64
    launcher=Packaging/RunLoopbackExperiment.command
    guide=docs/LOOPBACK_EXPERIMENT_GUIDE.md ;;
  *) printf 'Choose incoming or loopback.\n' >&2; exit 2 ;;
esac
# The development archive is not a published release asset. Refuse replacement
# so previously collected reports beside an extracted command are never removed.
test ! -e "$destination"
test ! -e "$destination.zip"
mkdir -p "$destination"
cp .build/release/screensharing-proxy-experiment "$destination/"
cp -R .build/release/ScreenSharingProxy_ProxyCore.bundle "$destination/"
cp "$launcher" "$destination/Run.command"
cp "$guide" "$destination/README.md"
if [[ "${1:-incoming}" == loopback ]]; then
    cp docs/NATIVE_LOCAL_TARGET_FINDINGS.md "$destination/"
fi
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
