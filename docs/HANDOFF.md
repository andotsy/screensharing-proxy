# Implementation handoff

## Current resume point — Screen Sharing Rubyfier, 2026-10-18

### Latest follow-up: connected media sockets, local r4

The user confirms r3 Standard mode works. High Performance still shows a grey
screen: the supplied schema-2 report has 27,428 received UDP datagrams, zero
sent, 3,680 dropped, eight native helper calls and eight completed TCP pairs.
The presence of `stopped` does not establish an unexpected relay exit.

An owned native `newRTPSocketDictionaryWithConfig:port:` fixture proves the r3
layout could return an unconnected descriptor after the duplicate connect
conflict. R4 replaces the injected UDP helper, using exclusive connected
127.0.0.1:15900–15902 native sockets paired with Ruby's loopback:5900–5902
sockets. Only Ruby binds the external media tuples. Config transport addresses
are updated before Apple's existing XPC handoff; negotiated keys/codec settings
remain opaque. IPv4-mapped loopback inputs are normalized. The standalone
unpatched-viewer relay keeps its earlier mode; `nativeMediaBase` opts into r4.

The report is schema 3 / transportRevision 4. `nativeMedia` now counts connected
socket creation and actual SSSession stream-start, first-frame, received-RTCP,
RTP-timeout and RTCP-timeout callbacks. `nativeMediaFailure` reports stage/port/
errno for native socket failures. Missing callback counters mean none observed.
This fixes a demonstrated socket topology weakness, not a confirmed diagnosis
of the user's live decoder failure. Live High Performance remains pending.
The user chose to run the live test themselves rather than provide viewer SSH.

R4 validation passed: 78 Swift tests, warnings-as-errors release build, 23
loopback tests (the optional original native helper case was run separately),
native login/reconnect/synthetic desktop, mounted payload byte comparison,
strict signatures, DMG integrity/layout/Retina background, offline guide,
private diagnostic app smoke and the packaged native transport self-test with
developer tools disabled. The latter uses real Apple XPC socket dictionaries,
checks connected local/peer tuples, destination-free feedback sends on all
three channels, IPv4-mapped configuration and occupied-native-port refusal.
Evidence is in `work/rubyfier-r4-validation` beside the checkout. An additional
scratch AVC negotiator/receiver initialized and configured but produced no
feedback with synthetic non-media packets; it is not a decoded-media test.

The user authorized committing/pushing all work directly to main. Both author
and committer must be `andotsy` with the GitHub noreply identity in AGENTS.md;
GitHub access goes through `debian@debian-vm.local`. Nine incorrectly attributed
older branch commits were rewritten, including all descendants, and the clean
history was published and verified. Both local clones/reflogs were corrected.
PR #1 removal was requested: GitHub exposes no PR deletion API. GitHub Support
must purge its retained references/cached old commits; closing a PR or deleting
its branch alone does not perform that purge. Do not claim those caches erased.

### Previous follow-up: native login fix, local r3

The other controlling Mac reported an immediate pre-login failure under r2. Its
JSON had `ready`, two completed TCP pairs, 34 received / 24 sent bytes, `stopped`,
zero media and zero native UDP helper calls, with no backend failure context.
This shows relay reservation/handshake traffic, but does not identify which
adapter-side guard refused the later attempt or prove native media delivery.
Do not describe this as a demonstrated UDP bind failure from that JSON alone.
The goal remains an administrator-free Ruby network path into the native viewer.

A native UI reproduction found a concrete pre-login defect: constructing a bare
loopback SSAddress discards the root input address used by the authentication
UI. The shim now uses `ipv6AddressWithIn6Addr:port:resolvedFromAddress:`; Apple
preserves the root `originalAddress` through successive resolution objects.
The new `Scripts/test-rubyfied-login.py` / `probe-rubyfied-login.m` regression
uses a unique copied-app identity and synthetic RFB peer. It presents the actual
native sign-in UI, submits a dummy password with keychain access/save disabled,
reconnects through the same relay and displays a synthetic desktop. It passes
with two TCP connections; reverting only the address-provenance fix makes it
fail before the login dialog. No real credentials or real-host authentication
are involved in that regression. Initial investigation also observed the local
Apple host's pre-authentication response, without entering credentials.

Report schema 2 records `adapterFailure` separately. Stopped relay and different
host/port selections now have distinct dialog/report reasons; backend reservation
failures show their actual operation, socket error and affected port. Report
mutation/writes are synchronized with the reader. Owned-port fixtures verify
TCP conflict attribution, same-target reuse, host/port refusal, stopped-relay
reporting and release of all UDP ports. The final r3 mounted DMG passed strict
signatures, native patch/UI/console/minimum checks, root-address preservation,
TCP plus all three bidirectional native UDP channels, integrity and layout.
All 78 Swift tests and the release build passed with warnings as errors.
Evidence is in `work/rubyfier-r3-final-validation` and the nearby reproduction
and negative-control logs. Authenticated Apple High Performance video/input,
SRTP processing and restricted-filter receiving permission still need a live test.

The user also supplied public remotex commit `e6dbd0090a295897d06978a073191d9cb176f656`.
Its delta concerns Standard-mode Full-quality rendering. Its existing
`src/vnc_apple_media.rs` is useful High Performance protocol reference: ordinary
connected UDP sockets, SRTP, RTCP, offers and media processing. It is its own
client, so it does not prove simultaneous Ruby/Apple socket handoff. A custom
client using that architecture would still need Ruby-owned external sockets
under the user's filter constraint. No upstream implementation was copied and
no rewrite was authorized. See the pinned links in `RUBIED_PATCHER.md`.

The user changed direction to a self-contained graphical patcher. Its exact
bundle name, display name, window title and app menu are **Screen Sharing
Rubyfier.app** / **Screen Sharing Rubyfier**. It creates **Screen Sharing
Rubyfied.app**. Develop on this Mac. Commit/push is now authorized; the live
High Performance release gate awaits the r4 user test.

The patcher reuses the app, authoritative icon and existing DMG layout. Rubyfy
and Diagnostics are the current tabs. It includes a scrollable, read-only,
selectable NSTextView console and Copy All, streams bounded tool output, and
allows cancellation. The window starts at 740×680 content points and enforces
680×620 minimum content size, including SwiftUI layout updates. The explanatory
text is “Adds our Ruby relay to a separate copy of Screen Sharing. Your original
app stays untouched.” Do not restore the rejected “familiar interface” wording.

`Packaging/build-app.sh` now builds `.build/native-bundle/Screen Sharing Rubyfier.app`.
It embeds optool, the precompiled arm64e dylib, launcher and Ruby scripts. The
optool revision and ArgumentParser license/provenance are in ThirdParty/optool.
Local fixes validate every padding byte and avoid an out-of-bounds zero append.
The runtime patcher uses system Ruby, plutil and codesign; no Xcode, command line
tools, Python or gems need installation on the target. It verifies the original
Apple executable hash against the tested 764.2 build from macOS 26.7.1 (25G241),
creates a private staging copy, injects LC_LOAD_DYLIB, ad hoc signs and verifies,
then moves the copy into a user-selected writable folder. Existing copies are
never overwritten. Apple binaries and scratch research remain outside the repo
and outside the distributed patcher. Developer-tool discovery was disabled for
the successful patch/launch fixture, not physically uninstalled from this Mac.

The copied native process hooks the checked SSSession transport entry after UI
host classification; native UI retains the real remote identity. The engine
receives an internal loopback endpoint after the owned Ruby relay is ready.
Use the real remote IPv4 address in the native UI, not 127.0.0.1:15900. No raw
socket, administrator access, network settings or sharing-service changes are
used. The launcher offers to quit the original viewer if running, with a clear
session-disconnection warning and Cancel; it never force-quits it. One remote
host per app lifetime is supported for now. Quit/reopen after relay failure.

Local validation: 78 Swift tests passed with warnings as errors; release build
and signatures passed. The integrated `--patch-smoke-test` creates a real copy,
checks visible UI, console and window minimum, and launches the injected native
self-test. It passed with a synthetic TCP greeting and bidirectional datagrams
on all three actual native UDP helper sockets through Ruby. Creating a copy
through the real folder chooser/button also passed; minimum size was exercised
by dragging. The test uses owned temporary ports and leaves current sharing
sessions untouched. Full High Performance authentication, decoded video, input,
audio, performance and restricted-policy receiving permission remain unproven.

The current local DMG candidate is
`ScreenSharingRubyfier-local-20261018-r4-macOS-arm64.dmg` in the task outputs
folder, with an adjacent `.dmg.sha256` file. Generate a fresh Rubyfied app with
r4; updating the patcher alone does not update an existing copy. SHA-256:
`33f9cd3c37f7aa9ed697564e59463f61f45ae984f4bd2be0cbe101f1b65cc4da`.

The preceding r2 SSH resumption completed two user requests: Copy All darkens while
pressed and shows a trailing checkmark for two seconds after successful copying;
the copied viewer preserves each localized app name and app-menu label with a
Rubyfied suffix. Both changes were already in source when the session resumed.
Validation passed: all 78 Swift tests and release build with warnings as errors,
323 localized strings across the three modified tables, all 41 localized app
names, strict signatures, DMG integrity and Finder/Retina layout. The actual
mounted DMG matches the built bundle and passed the integrated patch/native
TCP plus three-channel bidirectional UDP smoke test with developer-tool discovery
disabled. Evidence is in `work/rubyfier-r2-validation` beside the checkout.

This remains a local build. The next meaningful gate is a live test on the
controlling Mac using the copied app. Transport reports go to
`~/Library/Logs/Screen Sharing Rubyfied/latest-session.json`.
See [patcher notes](RUBIED_PATCHER.md). Earlier investigations below are historical.

## Earlier relay release work — 2026-10-18

The latest user request reauthorizes **commits, pushes, CI and an app DMG release**.
Develop natively on this Mac, using the existing VM GitHub login only for Git/API
operations. Release alpha 6 introduces Proxy and Settings alongside Diagnostics.
Preserve the current icon/DMG layout and all published tags/assets.

### Release held: native local-port gate found

The schema-6 user report now identifies **`tcpListenerBind`, port 5900,
`addressInUse`**, before ready, after all UDP reservations succeeded. Elapsed
time was 0.077 seconds; no TCP connection or media traffic occurred. The user
had already fully quit the viewer. Do not ask for another identical retry.

The user requested deeper native reverse engineering. On this development
sharing host, ordinary lsof also showed no TCP listener, while netstat showed
launchd holding wildcard TCP 5900. This demonstrates the visibility limitation,
not the identity of the controlling Mac's owner. Native inspection confirms
`screenSharingEnabledLocally` queries `SMJobIsEnabled` for the sharing service.
The `AllowLocalConnect` preference is gated by an internal-build check (false
here). An owned-process fixture invoking Apple's unchanged Pro-mode predicate
returns false with the local-tunnel flag even when its delegate requests Pro.
No transport-target/proxy override was found among native URL option handlers.

The next investigated design keeps direct native TCP and preserves the remote
UDP source while injecting to existing loopback. Published XNU source permits
this with an unbound privileged raw IPv4 socket; policy and actual delivery
remain gates. The user explicitly approved the bounded local administrator
test. It creates a raw socket, drops privilege, and uses synthetic payloads and
owned high ports with both an ordinary receiver and Apple's actual UDP helper.
No active Screen Sharing socket or system configuration is changed.

That local fixture now demonstrates successful source-preserving delivery into
both an ordinary UDP socket and the actual Apple-created wildcard socket, with
no injection loop into the LAN receiver. A numeric-Boolean assertion error was
corrected after inspecting the successful native result. See
[source-preserving UDP findings](SOURCE_PRESERVING_UDP_FINDINGS.md) for evidence,
privilege requirements and the remaining gates. The mechanism is not integrated
into the app/backend and no new live-test package has been delivered. Next work
is a bounded privilege bootstrap and UDP-only backend, followed by native media
validation; do not repeat the blocked loopback TCP experiment.

Latest port-5900 attempt stopped before ready with `addressInUse` at the old
generic `socketReservation` stage. A later viewer-side lsof showed avconferenced
holding connected UDP 5900 and wildcard UDP 5901; timing relative to the failed
attempt was not established. With Screen Sharing fully quit, both TCP-listener/UDP
checks printed nothing. The user confirms already starting the port-5900 launcher
in that state, including a repeat attempt, with the same generic failure. Do not
ask them to repeat that unchanged package. The subsequently distributed
schema-6 diagnostic build identified the TCP listener bind failure above. Hidden
service sockets remain possible; no empty lsof result proves every required port
is available.

Local follow-up code now reports loopback UDP external/feedback/injector bind,
UDP connect, TCP bind/listen and the affected numeric port. No owner is killed
or bypassed. The new CLI schema is 6 and app report schema 2. Old failure-context
frames without a port still decode. 77 Swift tests, 16 actual Ruby/native-helper
tests and the release build pass. These local changes are not yet committed
or pushed. The replacement local package is
`ScreenSharingProxy-LoopbackExperiment-port-diagnostics-v6-20261018-macOS-arm64.zip`.
Its signed packaged executable passes separate owned TCP and UDP conflict checks;
the archive integrity and arm64 architecture were verified. It is locally built,
not CI-built, and changes diagnostic attribution rather than reservation behavior.
The previously delivered CI-binary package uses schema 5. The schema-6 result
above supersedes the generic reservation failure for this attempt.

After the TCP-only report, the user asked to fix missing UDP and explicitly
requested GPT-6.1 SOL public research. That research and local native inspection
identified a concrete setup defect: Apple's 26.7.1 viewer classifies a local
address on TCP 15900 as a tunnel and disables Pro mode. Runtime classification
in an owned process confirms result 2 for 127.0.0.1:15900, versus result 1 at 5900.
See [native target findings](NATIVE_LOCAL_TARGET_FINDINGS.md).

`RunLoopbackExperiment.command` now explicitly passes `--listen-port 5900` and
saves a distinct `loopback-port-diagnostics-v6-*.json`. This avoids the nondefault-port gate,
but local sharing-service refusal/port ownership and real UDP delivery still
need the controlling Mac. Do not change services or interfaces. The app's old
default is not yet corrected; release/tag remains held until a native path works.
The user observed greyed-out quality menu items on their direct connection,
not the relayed connection. Do not substitute that for a relayed-session check.

Commit 4e17331's CI runs 39081555460 and 39081551339 both passed. There is no
alpha-6 tag/release. Existing authentication suffices; no new GitHub login is
required. The initial workflow-edit push was rejected for missing scope; that
unneeded workflow change was removed before the successful push.

The local test deliverable is
`ScreenSharingProxy-LoopbackExperiment-tcp5900-4e17331-macOS-arm64.zip`, SHA-256
`59df91e3baac23fa833a4ecb92a4d68c843beba6d25369613d898b95c0e5cc24`.
It reuses the unmodified executable/resources from successful CI artifact
12119441112, with only the launcher/docs changed locally. Source identity,
signature, ZIP integrity and launcher arguments were checked. These follow-up
changes are uncommitted; no new CI run or release was started. This variant
failed before ready even with the viewer fully quit; replace it for the next
attempt with the locally built exact-port diagnostics package.

### TCP-only live report and release work

The user then supplied the successful attempt's schema-4 report: 215.47 seconds,
1,962,312,977 bytes toward the viewer, 169,672 toward the host, zero UDP submissions
or relay drops, three accepted/connected TCP pairs and two completed pairs. The
user confirms closing Screen Sharing themselves; the final tcpWrite/other failure
therefore coincided with manual closure. Do not claim a spontaneous crash.
The user selected High Performance and input worked, but the counters establish
TCP-only forwarding for this attempt, not the intended native UDP media path.
Performance and colors differed from direct sharing; transport selection remains
unresolved. The app labels TCP-only evidence explicitly and does not promote
High Performance verification.

The forwarding optimization was preceded by an Instruments Time Profiler capture
of the owned Ruby child under synthetic local traffic. Avoiding a second select
pass and buffer copies, with bounded 256 KiB reads, improved 15-second bulk
throughput from 2,450 to 7,109 MiB/s. A 3,000-sample tiny-message test measured
median round-trip 58.5 -> 48.7 microseconds (p95 123.8 -> 114.6). These are local
fixtures, not a measured improvement to live Apple sharing or a universal speed
claim. Raw trace/fixture files remain outside the repository.

The native app owns the Ruby child, launches the viewer only after ready, drains
final events on stop/quit, saves a private session JSON, and shows actual transport
counters. It opts out of the CLI's duration cap; parent ownership and connect/idle
deadlines remain. A reset/closed peer retires only its TCP pair and counts discarded
queued bytes; network/startup/parent-output errors still fail. Completed TCP counts
now include reset/closed pairs, with an explicit connectionClosed reason.
The CLI report schema is 5; the app session report schema is 1.

Local release validation: 76 Swift tests, 15 loopback tests (including the real
Apple UDP helper), four CLI checks, release build/signature and native packaged
smoke checks pass. The latter starts/stops the actual embedded Ruby from the app,
exports private session data and verifies all reserved ports are released.
Proxy and Settings were visually inspected; Connect enables for a valid address.
The existing branch CI runs the native relay regressions; the unchanged release
workflow builds the DMG and exercises the updated packaged-app smoke checks.

### First reported live High Performance success

The user connected using the local login-reconnect package, explicitly confirms
selecting High Performance, and confirms keyboard and mouse both work. This is
the first reported live video-and-control success through the loopback relay on
the previously working setup. The user reports slower response and slightly more
vibrant colors. No schema-4 report from this successful attempt has been received
yet; throughput, loss, latency, CPU cost and display/HDR settings are unmeasured.
Do not describe the session as Standard or infer a color-conversion operation in
the relay: it forwards opaque bytes/datagrams without decoding or re-encoding.

Next compare the native HDR/color profile and virtual display resolution with
the direct connection, and inspect the saved counters before changing transport
behavior. The command still ends after ten minutes. Audio, sustained stability,
fresh reconnection and operation on the restricted setup remain unverified.
Keep the released app diagnostic-only; no app enablement or new publication was
requested. The following paragraphs describe the preceding failure and repair.

### Login reconnect repair

The user fully quit Screen Sharing and retried the local loopback package.
A login prompt now appeared, then a generic connection failure. The schema-3
report shows both TCP connections established, 17 bytes toward native / 12 toward
remote, both read sides closed, no UDP and a clean relay exit after 12.82 seconds.
The error does not establish that sharing is disabled or authentication rejected.

A local synthetic RFB server exposed a concrete lifecycle defect using the
actual macOS 26.7.1 Apple viewer: it opens a discovery TCP connection, closes it
before the password prompt, then opens another connection to sign in. The old
relay closed its listener on first accept and terminated after that pair's EOF.
This is consistent with the reported short exchange; the report contains no
payloads and cannot prove its exact protocol contents.

The uncommitted loopback fix retains the listener and UDP reservations across
sequential TCP pairs. Only one pair is active, both half-closes must drain before
replacement, and closed sockets/buffers are released. The next connection may
wait in the bounded listener backlog. Initial/inter-connection waits remain
limited to 120 seconds, with the command's ten-minute overall limit and existing
parent EOF/signal cleanup. Other relay modes retain their previous lifecycle.
Schema 4 adds accepted/connected/completed TCP counts; booleans describe the
current pair or the last completed pair during the idle gap. No payload parsing
or credential handling was added.

Native validation now passed discovery, dummy login and display of a synthetic
VNC desktop through the actual Ruby relay in one process: two accepted and
connected pairs, then two completed pairs after closing the test window.
The temporary profile/window and owned processes were cleaned up; original
connections were preserved. This proves the reconnect path, not native Apple
High Performance authentication, video, input or restricted-filter permission.
Thirteen loopback regressions pass, including queued reconnection while the
first pair drains, bidirectional UDP after reconnection, and existing cleanup,
source-guard and native UDP-helper checks. All 72 Swift tests pass locally.
The release experiment build and four packaged command checks in each mode
also pass. The local deliverable is named
`ScreenSharingProxy-LoopbackExperiment-local-login-reconnect-20261018-macOS-arm64.zip`,
SHA-256 `0c220af520b46da8d461cc4595fdf18bea32fea8d9052219944c87495db7bdf5`.
Its embedded resources/launcher/guide match the sources, ZIP integrity and
ad-hoc signature verify, and SOURCE_COMMIT marks uncommitted changes. No commit,
push, cloud run or published asset change was made for this fix.

The prior no-window attempt had zero TCP, 6,748 aggregate drops and a clean
Ctrl-C stop. A full quit allowed the following attempt to reach a login prompt;
the original no-op's cause remains unestablished. Drops combine several causes
and cannot be labelled remote video or an authentication/firewall failure.

### Previous route-guard repair

The subsequent schema-3 attempt failed with **`routeChanged` / `routeCheck`**
after about 20 seconds, with ready true, no native TCP acceptance and zero
traffic. The user edited a saved connection to 127.0.0.1:15900 and Connect did
nothing. This report proves the periodic fresh-source comparison stopped the
relay, not that its already-bound sockets were unusable or that the host rejected
authentication. It does not identify why source selection differed.

Both relay candidates now keep the original source and periodically verify it
is assigned to an up interface using Ruby's read-only `Socket.getifaddrs`.
No rebind, route/interface change or system-service operation is performed.
Missing/down addresses fail with `localAddressUnavailable` at `sourceCheck`;
actual socket errors retain their operation/category. Legacy route labels remain
decodable. Native regressions show TCP and both UDP directions still work after
the old fresh-source comparison would abort, and missing/down-source fixtures
fail and release sockets. The incoming candidate shares the corrected guard.

A fresh native Connect To entry and Apple's `vnc://127.0.0.1:15900` URL handler
both reached a local synthetic TCP listener on this 26.7.1 Mac. The saved-entry
no-op remains unexplained. `Run.command` now passes `--open-viewer`: after ready,
the command invokes the URL handler through a bounded `/usr/bin/open` child.
It neither edits saved profiles nor selects High Performance or supplies login
credentials. The user chooses High Performance when Apple offers it. See the
[updated guide](LOOPBACK_EXPERIMENT_GUIDE.md). Do not recommend the old 66f17be
package again: it still has the over-strict guard.

Validation: 72 Swift tests, release build, 12 loopback and seven incoming relay
tests, four command checks in each mode, and two portable Ruby startup checks
pass natively (seven distinct-address fixtures skip). The actual viewer also auto-launched through the release
relay to a temporary synthetic TCP greeting server on the development VM:
both TCP progress flags became true, 12 bytes passed in each direction, and
the duration limit stopped/reaped the relay with a stop acknowledgement. This
does not test authentication, media or a full High Performance session.

### Earlier loopback reports and supervisor repair

The first loopback live test also **failed**. Four schema-2 reports reached ready
on 26.7.1 with zero UDP submissions. Two ended with `localAddressUnavailable`
after 15–20 seconds and no reported TCP bytes; one was interrupted with zero
traffic; one recorded 17 bytes toward native / 12 toward remote, a stop
acknowledgement and `incompatibleProtocol`. The user confirms a login prompt
appeared before failure. The reports cannot identify the failing socket call
or prove an authentication rejection. Keep the uploaded archive private.

A regression reproduces the supervisor misclassifying stdout EOF as incompatible
when Ruby has emitted `stopped` but has not exited yet. The fix allows bounded
exit grace and still rejects EOF without a terminal event. Schema-3 reports now
include TCP acceptance/connection/read-EOF flags and fixed failure-operation and
socket-error labels; Ruby emits final counters before failure. A changed fresh
source had a distinct code, which localized the later failure described above.
The earlier schema-2 address errors cannot be retrospectively assigned to a
particular operation. Do not claim the transport works or infer a
firewall/authentication cause.

Current validation commands include the normal Swift suite/release build,
`test-loopback-relay.py --native-helper .build/probe-native-udp`, the incoming
and portable relay tests, and command smoke tests in both modes. Later paragraphs
retain the history and superseded test counts.

The incoming-only candidate has now **failed live on the previously working
setup**. The user observed a gray startup screen followed by a generic broken
stream error on repeated attempts. The submitted 26.7.1 report recorded 19,492
received datagrams / 22,254,056 bytes and 19,484 local submissions / 22,250,684
bytes over 52.06 seconds, eight reported drops, and clean user interruption.
Host-side logs from the matching minute repeatedly reported an RTCP timeout
with no previous receive timestamp. This is transport incompatibility on the
working pair; it does not test the affected 27.0.1 viewer's firewall. Keep the
submitted JSON and local log material outside the repository.

The next candidate is `loopback-relay.rb`: TCP on 127.0.0.1:15900, external
fixed-peer UDP, connected loopback feedback receivers, and separate injectors
from 127.0.0.1 at the media port to the existing routed local IP at that port.
Apple's later wildcard bind/duplicate connect returns an unconnected descriptor.
Unlike the incoming-only approach, incoming media presents the same peer address
and port as the TCP target, and both UDP directions go through Ruby. Eight native
relay tests pass, including the actual Apple helper through the real Ruby child
on all three channels, bidirectional datagram boundaries, TCP, refusal of active
owners, cleanup and fresh restart. TCP SO_REUSEADDR permits restarting after the
previous owned connection's TIME_WAIT; no SO_REUSEPORT is used for TCP.

Use `screensharing-proxy-experiment loopback --remote HOST_IP --output NEW.json`
or build `bash Packaging/build-relay-experiment.sh loopback`. The controlling
Mac connects to **127.0.0.1, TCP Port 15900, High Performance** after Relay ready;
start a fresh experiment for every attempt. See `LOOPBACK_EXPERIMENT_GUIDE.md`.
The command's schema-2 report distinguishes datagrams forwarded to native and
to remote. No full session has passed on this candidate, and localhost High
Performance negotiation remains a gate. The app stays diagnostic-only. Do not
ask the user to retry the failed incoming-only package unchanged.

Source-check follow-up finds the receive call chain down to
`VCSDInfoIsSrcDstInfoMatchedWithIP`. The inspected result marks connection health;
it has not been proven to discard the media. Do not claim a confirmed source
rejection diagnosis. Read `AVCONFERENCE_TRANSPORT_FINDINGS.md` for scope.

Current local validation is 67 Swift tests, release builds, eight loopback Ruby
tests, six incoming Ruby tests and four command smoke tests per mode. The following
paragraphs describe the earlier incoming implementation and remain historical
where they recommend that failed candidate or report older counts.

Development now runs natively on the user's Apple silicon Mac, in the local
`screensharing-proxy` checkout for this chat. Use its installed Xcode Swift 6.3
and `/usr/bin/ruby` 2.6.10. The former `/workspace` Linux toolchain paths below
are historical cloud setup, not prerequisites for local macOS work. The Debian
VM has GitHub access as andotsy if needed; it is not needed to build or test.
Use author and committer `andotsy <143706459+andotsy@users.noreply.github.com>`.

The experiment branch already included `incoming-relay.rb` at d759794. Some
earlier paragraphs and the PR description lagged that implementation. The
incoming relay keeps TCP/direct native feedback unchanged, reserves the network
UDP tuples before Apple starts, and submits received datagrams locally. Its six
native socket tests pass on this Mac, including Apple's actual UDP helper.

The separate `screensharing-proxy-experiment` command now provides a bounded
manual test through the existing Ruby supervisor. It refuses existing sockets
and report files, stops on INT/TERM/HUP or a duration limit, reaps its child and
saves owner-only aggregate counters without private endpoints or media bytes.
Run `bash Packaging/build-relay-experiment.sh` for the separate development ZIP;
see `INCOMING_EXPERIMENT_GUIDE.md`. This is not a working-proxy release, and the
native app remains diagnostic-only.

Read `AVCONFERENCE_TRANSPORT_FINDINGS.md` for new local 26.7.1 evidence: native
AVConference contains an explicit-destination feedback path for an unconnected
UDP socket. Source acceptance and full live media processing remain unproven;
the framework also has source-IP matching logic whose applicability to this
session has not been established. No private API is used by the relay or test
command, and the live media service was not attached to or changed.

Validation: 66 Swift tests, release build, six incoming-relay native tests and
four packaged-command smoke tests pass locally. Original relay portable checks
pass with the seven distinct-address cases explicitly skipped. Media ports were
already occupied on this Mac; high-port fixtures preserved those sockets. A
live session needs an identified remote Mac and a fresh native connection after
the relay is ready. Do not stop system services to reclaim retained sockets.

The user clarified that this development Mac is the **screen-sharing host** in
their current, unrelated working setup. Do not attempt to run the viewer relay
against that setup's existing host sockets or ask the user to reconnect without
a viewer-side test ready. Give the test package to the controlling Mac: disconnect
its session, start the experiment with the host IP, wait for Relay ready, then
connect normally in High Performance mode. The current unrestricted setup can
establish transport compatibility; it cannot establish the affected Macs' filter
behavior. No change to the host is required for this incoming-only candidate.

```sh
swift test -j 4 -Xswiftc -warnings-as-errors
swift build -c release -j 4 -Xswiftc -warnings-as-errors
clang -fobjc-arc -framework Foundation Scripts/probe-native-udp.m -o .build/probe-native-udp
python3 Scripts/test-incoming-relay.py --native-helper .build/probe-native-udp -v
python3 Scripts/test-ruby-relay.py --portable -v
bash Packaging/build-relay-experiment.sh
python3 Scripts/test-incoming-experiment.py dist/ScreenSharingProxy-IncomingExperiment-macOS-arm64/screensharing-proxy-experiment -v
```

The packaging command refuses an existing destination/archive to avoid deleting
reports. Move an earlier build aside before intentionally rebuilding. The
subsequent sections preserve earlier implementation context; the current state
above supersedes stale test counts and unimplemented-candidate descriptions.

## Earlier implementation context

Latest work is on `ruby-relay-experiment`. The user chose system Ruby and
explicitly declined interface changes. `Resources/relay.rb` implements bounded
opaque TCP forwarding and three fixed-peer UDP channels, and `RubyRelayRunner`
adds owned stdin/EOF supervision, bounded events and stop escalation. Nine real
Ruby traffic/startup tests pass on Linux; 63 Swift tests pass on Linux and macOS.
The native app remains diagnostic-only: macOS CI could not bind 127.0.0.2 without
an alias, and the user declined that setup. Read `RUBY_RELAY_EXPERIMENT.md`; do
not assume a remote companion fixes the viewer's local socket collision. No
interface/firewall changes or native High Performance relay have been performed.

The user's native GUI screenshot confirms a custom connection Port with High
Performance selected. Apple defines it as the TCP destination, separately from
the host UDP PortBase. The current research script reads the native viewer's UDP
socket method on macOS 26.6.2 CI: it requests SO_REUSEADDR/SO_REUSEPORT, binds a
wildcard at the media port, then connects to the media peer at the same port.
It does not retry a new port on bind failure inside that method. Revisit socket
coexistence with those reuse options; neither the existing Ruby implementation
nor adding a separate address alone establishes native interoperability. Read
HIGH_PERFORMANCE_RESEARCH.md for the exact evidence and version limits. Native
app, resource, smoke and DMG checks pass at b2519df; no live relay is validated.

Latest follow-up: Scripts/probe-udp-reuse.rb finds that all 16 same-loopback-port
combinations fail to exchange packets bidirectionally on macOS. However, a
connected network socket reserved first can coexist with a native unconnected
socket after the native connect returns EADDRINUSE. A Ruby model successfully
receives remote traffic, forwards it locally to that socket, and sends native
feedback directly with an explicit destination. Scripts/probe-native-udp.m
invokes the actual Apple UDP helper and confirms it returns a wildcard,
unconnected descriptor which accepts a local test packet at the media port.
Read RUBY_RELAY_EXPERIMENT.md for the evidence links and scope limits. The next
candidate can keep TCP direct and relay incoming UDP only, but AVConference's
source acceptance, explicit-destination feedback, startup conflicts, effective
firewall treatment and live behavior on the restricted OS remain gates. The
existing relay.rb does not implement this candidate. The later incoming-relay.rb
does; neither path is enabled in the app or proven with a complete native session.

The user authorized implementation on the current model on 2026-10-17, with
complex infrastructure first and simpler UI/distribution work later on Sol.

Implemented and exercised on Linux with Swift 6.2:

- `CProcessSupport` + `BoundedCommandRunner`: absolute-path spawning without a
  shell, null stdin, independent bounded output capture, monotonic deadlines,
  cancellation, TERM/KILL escalation and cleanup of the owned process group.
  The parent observes exit without reaping (`waitid` + `WNOWAIT`), performs group
  cleanup while the child PID is still reserved, then reaps the original child.
  Original exit code/signal and timeout/cancellation remain distinct.
- `DiagnosticsCollector`: read-only macOS probes, structured lsof parsing,
  executable identity correlation, launchd candidate metadata, firewall/signing
  observations, default redaction and honest incomplete/unknown states.
- Automatic `proxyd` discovery, requested by the user during implementation:
  gather candidates from firewall/process/service evidence, check accessibility
  and incoming rules, deduplicate aliases, prefer a sole running allowed candidate,
  and refuse unknown, blocked or ambiguous choices. `DiagnosticsCollector.inspect`
  returns a raw in-memory selection for the app and a redacted report for sharing.
  No manual `proxyd` path input is needed. Rediscover before starting a session;
  selection does not establish a supported forwarding API.
- `BackendLineDecoder`: incremental newline-delimited versioned JSON with 16 KiB
  frame and 64 KiB read limits, UTF-8/schema/version validation and fail-stop
  behavior. EOF with a partial frame fails. The decoder cannot be reused after EOF.
- `SessionLifecycle`: fresh UUID per attempt; old events/exits are ignored; ready
  is required before traffic; counters cannot regress; explicit stop wins over
  late ready; another start waits for process exit; cancelled preflight and failed
  spawn have explicit cleanup paths. “Relaying” means byte activity, never video
  presentation or successful High Performance negotiation.

These pieces are foundations, not a complete long-running backend supervisor.
The command runner is for bounded probes, with stdin set to `/dev/null`. Do not
reuse it as a live relay transport. A future adapter supervisor must add writable
stdin, command/request correlation, handshake deadlines, parent-EOF handling,
retry policy and integration with the lifecycle. An existing system daemon keeps
its own documented IPC/lifecycle; do not impose this event protocol on it.

The runner cleans up children remaining in its owned process group. A daemon
that deliberately detaches into another group is outside that ownership. The
diagnostic commands should not daemonize. No user-space timeout can guarantee
reaping a process stuck indefinitely in an uninterruptible kernel operation.
Do not install a competing process-wide SIGCHLD reaper around this runner.

Backend event wire examples (one JSON object per line):

```json
{"version":1,"sessionID":"00000000-0000-0000-0000-000000000001","event":{"ready":{}}}
{"version":1,"sessionID":"00000000-0000-0000-0000-000000000001","event":{"traffic":{"receivedBytes":1024,"sentBytes":128}}}
{"version":1,"sessionID":"00000000-0000-0000-0000-000000000001","event":{"failed":{"code":"addressInUse"}}}
{"version":1,"sessionID":"00000000-0000-0000-0000-000000000001","event":{"stopped":{}}}
```

Any protocol/state error should stop and reap the owned adapter before permitting
another start. `stopped` acknowledges a request; it never substitutes for the OS
termination event. Counters are cumulative within one session identifier. Error
codes are structured; private paths and raw stderr do not belong in wire messages.

Static transport research was completed on the supplied files from a separate
unblocked macOS 26.7.1 (25G241) Mac. Read `HIGH_PERFORMANCE_RESEARCH.md` before
backend work. Apple documents UDP 5900–5902 RTP/RTCP; the supplied daemon derives
media IPs from TCP endpoints and initializes ports from `portBase`. An opaque
address-separated relay is now a concrete experiment, with native-viewer binding
and actual filter attribution still unresolved. The uploaded `avconferenced` is
a feature-gated entry point; its private framework implementation was not supplied.

Alpha 3 adds schema-2 performance component/process/binding evidence and visible
`com.apple.ScreenSharingServer` host preferences. The native app exports a
schema-1 paired envelope with `baseline` and `duringSession`, sharing a redaction
scope, remote IP and privacy setting. See `DIAGNOSTICS.md` for interpretation.
The `codesign` socket-delegation boolean is capability evidence, not effective
socket attribution. No user payloads or uploaded binaries are in the repository.

Next work, in order:

1. Use the restricted viewer's captured rules to test actual inbound TCP/UDP
   reception, beginning with /usr/bin/ruby. Resolve unrecognized firewall policy
   output. Use the working unrestricted capture as a reference and complete
   the transport experiment, with a remote companion if needed, as now authorized.
2. Build the proven adapter/data path and its realistic local TCP/UDP tests.
   Do not fill the missing mechanism with a guessed TCP-only implementation.
3. Wire the native app to the proven adapter supervisor and tested lifecycle.
   The native diagnostic UI, menu, optional login setting and icon are implemented;
   do not present the diagnostic-only state as a working relay.
4. Complete installed-app and live transport acceptance on the user's Macs.
   Native app and DMG assembly use `Packaging/build-app.sh` and `build-app-dmg.sh`.

Commands in the current cloud workspace:

```sh
bash Scripts/swift-cloud.sh test -j 4 -Xswiftc -warnings-as-errors
bash Scripts/swift-cloud.sh build -c release -j 4 -Xswiftc -warnings-as-errors
.build/release/screensharing-proxy-diagnose --help
```

The Swift 6.2 Linux archive was verified against Swift's release signature from
the official website repository. Its primary signing fingerprint is
`52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`; the verified archive SHA-256 is
`8e3d63a3371caad495e694414b9b9a22c5f68c6473077406c7296472a41bc077`.
The toolchain lives outside the checkout in `/workspace/.toolchains/`; caches
are under `/workspace/.cache/`. `HOME` is unchanged. No external Swift dependencies
are declared. macOS builds use the local Xcode toolchain directly.

Portable validation: 57 Swift Testing tests in ten suites pass with warnings
as errors, covering the core and the app's serial collection/cancellation state
and private atomic report writer. The app target is macOS-only; its real window,
automatic discovery and report export are exercised by `Scripts/smoke-app.py` in
macOS CI. Live viewer firewall output and High Performance forwarding still need
testing on the user's Macs. Synthetic fixtures and CI hosts do not establish
that transport works.

`v0.1.0-alpha.1` is the published standalone CLI diagnostic alpha.
`v0.1.0-alpha.2` adds a native diagnostic `.app` and new DMG; confirm publication in
GitHub Releases rather than inferring it from a tag. Alpha 3 adds the expanded
performance diagnostics and paired-capture workflow. Published assets are never
replaced under the same version. The user authorized commits and releases.
Other workspace repositories remain read-only. No firewall/display changes or
running network relay have been made by this implementation.

Alpha 4 keeps the Screen Sharing Proxy app shell with Proxy, Diagnostics and
Settings tabs. Only Diagnostics is enabled and selected; the other tabs are
grayed out. Its content replaces the paired-capture UI with one Collect Diagnostics button.
It collects ten snapshots, creates a ZIP (diagnostics.json + README.txt), and
opens NSSavePanel automatically. Save cancellation/failure preserves the archive;
collection cancellation preserves the prior archive. Closing quits and waits for
probe cleanup. Legacy login registration is removed; Dock/menu bar settings are
gone. All visible UDP sockets are retained, with unknown traffic unattributed.
The arrow/divider icon is built from the Icon Composer document Packaging/AppIcon.icon.
The DMG uses pinned dmgbuild, fixed Finder positions and 1x/2x backgrounds; its
version label comes from SSPReleaseVersion. Live relay feasibility is still pending.

Runtime candidates now include Python/Ruby firewall targets (versioned names and
app bundles). They remain separate from exact proxyd discovery and are never
executed or called verified relays. The user supplied an unredacted report from
a nonaffected viewer; keep the uploaded JSON outside the repository. Its three
snapshots showed Screen Sharing TCP to 5900, avconferenced UDP 5900 to peer 5900,
and avconferenced wildcard UDP 5901. This establishes an observed descriptor
owner and potential bind conflict on that Mac, not effective filter attribution
or the affected viewer's policy. System Python/Ruby and other runtime entries
were explicitly listed as allowed; no proxyd was found.

The native smoke test presents and cancels the real Save sheet, then writes its
collected ZIP through the shared private writer. Apple disallows programmatic
NSSavePanel.ok calls on macOS 10.15+, so the test does not claim to simulate a
user's Save click. Portable tests cover save outcomes, retry/cancellation, ZIP
compatibility and atomic file writing. A manual user Save click remains an
installed-app acceptance check.

Alpha 5 orders the tabs Proxy, Settings, Diagnostics. Diagnostics is still the
selected, enabled tab. Keep the user's updated Icon Composer document as the
app icon source for future releases; do not restore the earlier generated PNG.
The content header (icon, app name and ALPHA badge) is removed; tabs sit directly
below the native window title.

Deployment clarification: installation on the controlling Mac alone is preferred,
but the user explicitly authorizes a remote companion if necessary. Both options
must preserve full interactive Screen Sharing, including keyboard/mouse control.
Do not ask again whether installation on both Macs is acceptable. This does not
settle the separate technical questions around bindings, local delivery and
effective firewall identity, or authorize unrelated privileged network changes.

The user confirmed that the alpha-5 ZIP was captured during working High
Performance sharing on the unrestricted Mac. Ten complete snapshots show the
same TCP/UDP pattern as the earlier capture. Five Python/Ruby firewall entries
are allowed, accessible and signature-verified; /usr/bin/python3 identifies as
an Xcode tool shim. Preserve this as the working reference, without committing
the uploaded ZIP or its private metadata. See TRANSPORT_FINDINGS.md.

The restricted viewer's alpha-5 ZIP has now been analyzed. It reports macOS
27.0.1 (26A434), arm64, whereas the working reference and supplied binaries are
26.7.1. The user confirms a failed High Performance attempt. TCP 5900 establishes
during collection; the last two of ten complete snapshots show avconferenced
connected UDP local 5900/5901 to the same peer's 5900/5901. Neither packet delivery
nor the precise visible failure stage is recorded. The viewer client executable
is explicitly listed blocked; avconferenced and screensharingd have no explicit
list entry. System Ruby and the Python launcher shim are listed allowed, while
Python.app is blocked. No exact proxyd was found; no runtime was executed.

Global firewall state, block-all and all per-component incoming queries are
unknown despite successful probe exits; the collector discarded the unrecognized
stdout. Preserve this as an evidence gap, not an enabled/disabled assumption or
an invented parser fix. See TRANSPORT_FINDINGS.md for the comparison and next
experiment. Keep both uploaded archives and private paths outside the repo.
