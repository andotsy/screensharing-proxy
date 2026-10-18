# Install Screen Sharing Rubyfier

Screen Sharing Rubyfier 1.0.2 is available for Apple silicon. The patcher window runs
on macOS 14+ and creates Rubyfied from any installed Screen Sharing build, but it
has only been tested with the Screen Sharing executable from macOS 26.7.1 (25G241).

1. Open the DMG and drag **Screen Sharing Rubyfier.app** onto **Applications**.
2. Open Rubyfier on the **controlling Mac**. Click **Create Rubyfied App…** and
   choose a writable folder. Your user Applications folder avoids admin access.
3. Open the resulting **Screen Sharing Rubyfied.app**. If the original viewer is
    running, the copy offers to quit it; doing so disconnects its viewer sessions.
   Allow **Local Network** access when macOS asks. If access was previously
   denied, enable Rubyfied in System Settings → Privacy & Security → Local Network.
4. Enter the remote Mac's **real IPv4 address** in the native connection window,
   authenticate normally and choose High Performance when offered. Do not enter
   a loopback address or port 15900.
5. Quit Rubyfied to stop its relay. A new connection attempt can restart a stopped
   relay, up to three times per minute. Quit/reopen before switching an active
   relay to another host. Rubyfier itself can be closed after creation.

The patcher bundles optool, the compiled transport library and relay scripts.
No Xcode, command line tools, Python or gems need to be installed. It uses system
Ruby and codesign, modifies only the new app copy, and never overwrites an
existing copy. No interface, route, firewall or sharing-service setting changes.

Rubyfied keeps a private log of transport counters in
`~/Library/Logs/Screen Sharing Rubyfied/latest-session.json`.

Live High Performance video, audio, and keyboard/mouse control have been verified
on the supported build. Native sign-in, retry recovery and three bidirectional
media channels also have automated coverage. Sustained performance and operation
under the restricted viewer's network rules remain unverified.

## If macOS blocks the app

This build is ad hoc signed and not notarized. For a download you trust, open the
included Terminal shortcut and run this command after installing it in Applications.
It verifies the bundle identity and signature, removes quarantine only from that
app, then opens it. An ad hoc signature checks integrity, not publisher identity.

```sh
(
set -eu
app='/Applications/Screen Sharing Rubyfier.app'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = com.andotsy.screensharing-proxy
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign --display --verbose=2 "$app" 2>&1 | /usr/bin/grep -Fx 'Identifier=com.andotsy.screensharing-proxy' >/dev/null
/usr/bin/xattr -dr com.apple.quarantine "$app"
/usr/bin/open "$app"
)
```

Use the accompanying SHA256SUMS to check the archive before opening it:
`shasum -a 256 -c SHA256SUMS` with both files in the same folder.

See the [patcher notes](RUBIED_PATCHER.md) for how the copy is made.
