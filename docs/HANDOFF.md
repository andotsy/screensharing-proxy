# Implementation handoff

## Current resume point — 2026-10-18

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
