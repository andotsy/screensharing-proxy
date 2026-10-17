# Install Screen Sharing Proxy

Download `ScreenSharingProxy-v0.1.0-alpha.2-macOS-arm64.dmg` from the
[prerelease](https://github.com/andotsy/screensharing-proxy/releases/tag/v0.1.0-alpha.2).
Requires Apple silicon and macOS 14+. No Xcode or Python installation is needed.

1. Open the DMG and drag **ScreenSharingProxy.app** onto **Applications**.
2. Open **Screen Sharing Proxy** from Applications. Its window opens and searches
   automatically for an explicitly allowed `proxyd`. The menu bar icon reopens
   the window after you close it.
3. Start the failing Screen Sharing session, optionally enter the remote Mac's
   numeric IP, then choose **Collect Diagnostics**. The Diagnostics pane lets you
   copy or save the report. Private addresses and paths are redacted by default.

**This is a diagnostic alpha. It does not forward Screen Sharing traffic yet.**
The app leaves firewall and display settings unchanged. Launch at login is off
unless you enable it in General.

The app is ad hoc signed and not notarized. If macOS blocks opening the downloaded
app, open the included Terminal shortcut and run this command after installing
it in Applications. It checks the app identity and signature, removes quarantine
only from that app, then opens it:

```sh
(
set -eu
app='/Applications/ScreenSharingProxy.app'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = com.andotsy.screensharing-proxy
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign --display --verbose=2 "$app" 2>&1 | /usr/bin/grep -Fx 'Identifier=com.andotsy.screensharing-proxy' >/dev/null
/usr/bin/xattr -dr com.apple.quarantine "$app"
/usr/bin/open "$app"
)
```

Do not run the command on an untrusted download. `SHA256SUMS` is published beside
the DMG; run `shasum -a 256 -c SHA256SUMS` with both files in one directory to check
the download before mounting it.

The CLI is also included at
`/Applications/ScreenSharingProxy.app/Contents/MacOS/screensharing-proxy-diagnose`.
See [diagnostics](DIAGNOSTICS.md) for its options and report visibility limits.
The older `v0.1.0-alpha.1` release contains only the standalone diagnostic CLI.
