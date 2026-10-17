# Implementation handoff

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

1. Run `screensharing-proxy-diagnose` on the viewer Mac and inspect the identified
   `proxyd` interface (`discover` automatically selects an explicitly allowed
   candidate). Complete the two-Mac transport experiment in the plan.
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
