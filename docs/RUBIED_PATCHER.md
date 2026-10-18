# Screen Sharing Rubyfier

This patcher creates **Screen Sharing Rubyfied.app** from the Screen Sharing app
already installed on this Mac, then adds our launcher, transport dylib and system
Ruby relay. The original app and sharing service are unchanged. The package
contains our files only; it does not distribute Apple's executable or resources.

The copied app preserves Apple's localized names and app-menu labels, appending
**Rubyfied** to each. For example, Ukrainian displays **Спільний екран Rubyfied**
and French displays **Partage d’écran Rubyfied**.

High Performance video, audio, and keyboard/mouse control have been verified
without administrator privileges on macOS 26.7.1. Version 1.0.0 uses Apple's
in-process media engine and native image queue. Restricted-policy receiving and
sustained performance remain separate, unverified checks.

## Use

1. Open **Screen Sharing Rubyfier.app** on the controlling Mac. Click **Create
   Rubyfied App…**, then choose a writable folder, such as your user Applications
   folder. The console shows progress and allows text selection and copying.
   **Copy All** darkens while pressed and shows a trailing checkmark for two
   seconds after copying successfully.
   An existing Rubyfied app is never overwritten. The compiled dylib, launcher,
   optool and Ruby scripts are bundled; no Xcode, command line tools, Python or
   gems need to be installed. System Ruby and codesign are used locally.
2. Open **Screen Sharing Rubyfied.app**. If Apple's original viewer is running,
   Rubyfied offers to quit it, with a warning that viewer sessions will disconnect.
   Cancelling aborts Rubyfied. It never force-quits the viewer or stops the sharing
    service on this Mac.
   Allow Local Network access when prompted. A previously denied choice can be
   changed in System Settings → Privacy & Security → Local Network.
3. In the native connection UI, enter the sharing Mac's **real IPv4 address** and
   normal TCP port, then authenticate normally. Do not enter 127.0.0.1 or 15900.
   Choose High Performance when offered.
4. Quit Rubyfied to stop its Ruby child and release its sockets. A new native
   connection attempt can restart an exited relay after bounded cleanup; at most
   three restarts are permitted per minute. An active relay stays pinned to its
   selected host/port, so quit/reopen before changing an active target.

The patcher currently accepts the tested Screen Sharing 764.2 executable from
macOS 26.7.1 (25G241) on Apple silicon. It checks the installed native executable
against the exact build used
to compile/test the payload and refuses other builds. A macOS update requires a
new compatibility check and a new copy. It does not replace the system VNC URL
handler, copy existing saved passwords, or retain Apple's private entitlements.

## Transport and evidence limits

The dylib replaces the native session engine's
`connectToAddress:withOptions:timeout:` method, after the UI has resolved and
classified the real host. It prepares the existing Ruby TCP/UDP loopback relay
and passes a loopback transport address to the original engine method. That
address retains Apple's `originalAddress` link through the native
`resolvedFromAddress:` factory. A bare loopback address loses the host metadata
needed to present the login dialog and reconnect after discovery. The native UI
keeps its original resolved target. The adapter replaces the native UDP socket
helper with an exclusive, connected loopback socket and updates the media
configuration's local/remote transport addresses before Apple's existing XPC
socket-dictionary handoff. Media keys and codec configuration stay opaque.

The relay owns external sockets and bounded opaque forwarding; the native
engine retains authentication and decoding. The internal TCP listener uses
15900, so a sharing service's TCP 5900 listener does not conflict. UDP 5900–5902
must be available. Bind errors stop the attempt without evicting another owner.
Rubyfied uses separate native UDP ports 15900–15902 on 127.0.0.1. For each
channel, Ruby owns both LAN:P ↔ host:P and loopback:P ↔ loopback:15900+channel;
Apple receives the reverse connected loopback socket. There is no wildcard
native receiver or duplicate-tuple connect failure, and the native socket can
send feedback with `send`, without a supplied destination. IPv4-mapped loopback
configuration is normalized to match the actual socket. Conflicting native
ports fail explicitly instead of sharing packets between receivers.

Live debugging found that avconferenced rejects the ad-hoc copy's
`vcMediaStreamSetSessionConfig` request at its authorization check. Selecting
AVCVideoStream/AVCAudioStream's in-process path starts both native streams and
restores audio and feedback. AVCRemoteVideoClient still queries the separate
service for a video slot, so Rubyfied supplies a small local client backed by
the in-process VCVideoStream's existing VCImageQueue. Apple's viewer receives
the native slot and actual first-frame notification. This restores the picture;
the user confirmed moving video, input, and audio together. No media payload,
password or negotiated key is copied into diagnostics.

Normal app launch is subject to macOS Local Network privacy, unlike an SSH
launch. The copied executable receives unique LC_UUID values instead of sharing
Apple's executable UUIDs, and its bundle declares a Local Network usage message.
See Apple's [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
The fresh production copy was then opened through LaunchServices and the user
confirmed High Performance video, input and audio work normally.

Private counters and fixed error labels are saved to
`~/Library/Logs/Screen Sharing Rubyfied/latest-session.json`. No passwords, media
keys, payloads or host addresses are written by our shim. Apple's own logging
and preferences remain managed by Apple's implementation.

Report schema 5 (`transportRevision: 6`) records adapter-side refusal reasons separately from backend
socket failures. The dialog identifies a different selected host/port, pending cleanup, the
restart limit, or the actual socket operation/error/port. A stopped relay is
retired before a new attempt; its old reader must reach EOF before the next
reader starts. A `ready` event records successful relay reservation;
it does not establish native authentication or media delivery.
`nativeMedia` records connected socket creations, native stream-start successes
or failures, first-frame callbacks, received-RTCP callbacks and RTP/RTCP
timeouts. Absent counters mean no corresponding callback has been observed.
`nativeMediaFailure` gives the failing native socket stage, local port and errno.
These counters do not claim input, audio, sustained stability or filter acceptance.
`nativeVideo` reports the last sampled stream's image-queue frame count and
renderer readiness. `highPerformanceSession: "videoDecoded"` requires the native
decoder's first-frame observation; it does not claim the broader live-test matrix.

Retry recovery addresses a pre-media failure: the user's report had a TCP accept but
zero upstream connects/bytes and no native UDP calls, followed by a retained
stopped-task refusal. The user subsequently confirmed r4 still connects in
Standard mode. The mode-specific timeout cause is not established.
`connectionRequests` keeps the last 16 native requests: relative timing, TCP
port, loopback/reuse flags, and scalar quality/virtual-display option values.
`relayConfiguration` records the selected ports; neither field records a host
address or credentials. `relayGeneration` identifies child restarts and the
last three `previousAttempts` retain backend counters and failures. Native media
callback counters and the request trace are cumulative for the app lifetime.
TCP-connect timeouts now identify `hostConnect` rather than `waiting`.

A controlled bound-but-unavailable TCP peer reproduced failure followed by the
stopped-task trap. After making that same peer available, Rubyfied restarts the Ruby
child and forwards bytes successfully in the same process, preserving the old
failure and enforcing the restart bound. Run `python3 Scripts/test-rubyfied-retry.py`
to exercise that lifecycle without the system viewer or real credentials.


## Development

`bash Packaging/build-app.sh` builds **Screen Sharing Rubyfier.app** in
`.build/native-bundle/`. `Packaging/build-rubied-patcher.sh` builds its payload.
The bundled optool and ArgumentParser sources, revisions, licenses and local
padding corrections are documented in `ThirdParty/optool/PROVENANCE.md`.
Only the copied executable receives a load command; the launcher does not rely
on `DYLD_INSERT_LIBRARIES`.

`python3 Scripts/test-rubyfied-media.py` exercises the real native in-process
stream, outgoing feedback, image-queue slot and observer cleanup with owned
loopback peers. Invalid synthetic packets must not claim decoded video.

Native UI smoke mode is
`Screen Sharing Rubyfied.app/Contents/MacOS/RubiedLauncher --rubied-self-test`;
it loads the shim, checks its method signatures, opens the native UI and tests
a synthetic TCP greeting plus bidirectional datagrams through all three actual
Apple XPC socket dictionaries and the owned Ruby child. It verifies local/peer
addresses, IPv4-mapped configuration, destination-free connected sends and
explicit refusal of an occupied native port. It uses temporary ports and
does not close the original viewer. This fixture passed locally with developer
tool discovery disabled; it does not prove authenticated media or input works.


The native login regression can be run on a created copy:

```sh
python3 Scripts/test-rubyfied-login.py "/path/to/Screen Sharing Rubyfied.app"
```

It builds an isolated test copy with a unique bundle ID, uses a synthetic RFB
peer on owned high ports, presents the real native sign-in dialog, submits only
a fixed dummy password, reconnects and displays a synthetic desktop. Keychain
lookup/save are disabled in that test copy. Reverting only the original-address
link makes the same regression fail before the login dialog. This verifies the
pre-login repair, not Apple High Performance authentication or decoded SRTP.


## Protocol reference

The user supplied public remotex revision
[e6dbd009](https://github.com/andrewtheguy/remotex/commit/e6dbd0090a295897d06978a073191d9cb176f656).
That commit changes Standard-mode Full-quality decoding, while the repository
at that revision also contains a substantial independent High Performance
client in
[`src/vnc_apple_media.rs`](https://github.com/andrewtheguy/remotex/blob/e6dbd0090a295897d06978a073191d9cb176f656/src/vnc_apple_media.rs)
and measured protocol notes in
[`docs/apple-vnc-889.md`](https://github.com/andrewtheguy/remotex/blob/e6dbd0090a295897d06978a073191d9cb176f656/docs/apple-vnc-889.md).
Its media receiver uses ordinary connected UDP sockets with address/port reuse,
then handles negotiation, SRTP and feedback itself. It does not demonstrate
handing those packets into Apple's simultaneously running receiver. It is a
useful protocol/state-machine reference and an alternative client architecture;
using it under the user's filter constraint would still require proving the
allowed Ruby-owned network path. No upstream code was imported in this fix.
