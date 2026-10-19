#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
destination=${1:?Supply a new output folder}
test ! -e "$destination"
if [[ ! -f ThirdParty/optool/optool/operations.m ||
      ! -f ThirdParty/optool/optool/FSArgumentParser/ArgumentParser/XPMArgumentParser.m ]]; then
    printf 'Missing optool dependencies. Run: git submodule update --init --recursive\n' >&2
    exit 1
fi
mkdir -p "$destination/Payload/Relay"
clang -arch arm64e -dynamiclib -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework AppKit -framework QuartzCore Sources/Rubied/RubiedTransport.m \
    -o "$destination/Payload/RubiedTransport.dylib"
clang -arch arm64 -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework AppKit Sources/Rubied/RubiedLauncher.m \
    -o "$destination/Payload/RubiedLauncher"
codesign --force --sign - "$destination/Payload/RubiedTransport.dylib"
codesign --force --sign - "$destination/Payload/RubiedLauncher"
clang -arch arm64 -O2 -fobjc-arc -Wno-deprecated-declarations -framework Foundation \
    ThirdParty/optool/optool/*.m ThirdParty/optool/optool/FSArgumentParser/ArgumentParser/*.m \
    -o "$destination/Payload/optool"
codesign --force --sign - "$destination/Payload/optool"
mkdir -p "$destination/Licenses"
cp ThirdParty/optool/LICENSE "$destination/Licenses/optool.txt"
cp ThirdParty/optool/optool/FSArgumentParser/LICENSE.md "$destination/Licenses/ArgumentParser.md"
cp Sources/Rubied/Relay/{relay,loopback-relay}.rb "$destination/Payload/Relay/"
cp Packaging/Rubied/{Patch.command,patch.rb} "$destination/"
cp docs/RUBIED_PATCHER.md "$destination/README.md"
chmod 755 "$destination/Patch.command"
cp Packaging/Rubied/compatibility.json "$destination/Payload/compatibility.json"
printf 'Patcher payload built. Apple app files are copied on the destination Mac.\n'
