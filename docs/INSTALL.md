# Install Screen Sharing Proxy

Download `ScreenSharingProxy-v0.1.0-alpha.4-macOS-arm64.dmg` from the
[prerelease](https://github.com/andotsy/screensharing-proxy/releases/tag/v0.1.0-alpha.4).
Requires Apple silicon and macOS 14+. No Xcode or Python installation is needed.

1. Open the DMG and drag **ScreenSharingProxy.app** onto **Applications**.
2. Open **Screen Sharing Proxy** on the viewer Mac with the blocked service.
   The **Diagnostics** tab is selected automatically.
3. Keep the Screen Sharing connection attempt open and click **Collect Diagnostics**.
4. When the Save dialog appears, choose where to save the ZIP, then send that ZIP
   to the person helping you. Private addresses and paths are hidden automatically.

If you cancel the Save dialog, **Save ZIP Again…** saves the completed report
without collecting again. Closing the window quits the app.

**Only Diagnostics is available in this alpha. Proxy and Settings are grayed out;
traffic forwarding is not implemented yet.**
The app leaves firewall and display settings unchanged. It runs on demand and
removes its own launch-at-login registration from older diagnostic alphas.

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
