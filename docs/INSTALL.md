# Diagnostic alpha installation

Download the macOS arm64 DMG from the GitHub prerelease. This alpha contains the
compiled diagnostic CLI and an offline guide; the relay and native GUI are still
pending. Requires Apple silicon and macOS 14+. Xcode/Python are not needed to run
the binary. The release is ad hoc signed and not notarized.

Open README.html inside the mounted image and its Terminal shortcut. The guide
copies the tool to a fresh Downloads folder, verifies its signature and identity,
removes quarantine only from that copy, and collects a redacted report:

```sh
(
set -eu
tool_dir=$(mktemp -d "$HOME/Downloads/ScreenSharingProxy-Diagnostics.XXXXXX")
tool="$tool_dir/screensharing-proxy-diagnose"
cp '/Volumes/Screen Sharing Proxy Diagnostics/screensharing-proxy-diagnose' "$tool"
/usr/bin/codesign --verify --strict "$tool"
/usr/bin/codesign --display --verbose=2 "$tool" 2>&1 | /usr/bin/grep -Fx 'Identifier=com.andotsy.screensharing-proxy.diagnose' >/dev/null
if /usr/bin/xattr -p com.apple.quarantine "$tool" >/dev/null 2>&1; then
    /usr/bin/xattr -d com.apple.quarantine "$tool"
fi
printf 'Tool and report folder: %s\n' "$tool_dir"
"$tool" discover --output "$tool_dir/proxyd-report.json"
)
```

Exit 3 means discovery remained unresolved; a report is still written. The
report folder is printed in Terminal. See DIAGNOSTICS.md for data visibility,
privacy, and optional session collection. No firewall or display setting changes.

For download integrity, place the DMG and SHA256SUMS in one directory and run
`shasum -a 256 -c SHA256SUMS` there before mounting the image.
