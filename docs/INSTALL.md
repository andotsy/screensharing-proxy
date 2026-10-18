# Install Screen Sharing Proxy

Download `ScreenSharingProxy-v0.1.0-alpha.6-macOS-arm64.dmg` from the
[prerelease](https://github.com/andotsy/screensharing-proxy/releases/tag/v0.1.0-alpha.6).
Requires Apple silicon and macOS 14+. No Xcode or Python installation is needed.

1. Open the DMG and drag **ScreenSharingProxy.app** onto **Applications**.
2. Open the app on the **controlling/viewer Mac**. Quit its existing Screen Sharing session.
3. In **Proxy**, enter the remote Mac's IPv4 address and click **Connect**.
4. Sign in in Apple's Screen Sharing window and select High Performance when offered.
5. Keep this app open while sharing. **Stop Relay** or quitting the app stops its owned Ruby process.

**Proxy, Settings and Diagnostics are available in this first relay app alpha.**
There is no ten-minute session limit; an idle gap after TCP closes ends after two
minutes. Settings exposes optional local/remote TCP and UDP media-base ports.
No firewall, interface, route, display or system-service configuration is changed.

The app shows **TCP only** when no UDP has passed through Ruby. A working screen
with that label does not prove Apple's UDP high-performance media path, and can
be slower than a direct connection. The restricted viewer's rules remain untested.

**Save Session Report…** exports private transport counters as JSON. **Diagnostics**
retains the one-click collection and automatic ZIP save dialog; **Save ZIP Again…**
reuses a completed collection. Reports exclude credentials and packet contents.

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
