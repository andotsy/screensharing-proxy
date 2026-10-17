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

Next work, in order:

1. Run `screensharing-proxy-diagnose` on the viewer Mac and inspect the identified
   `proxyd` interface (`discover` automatically selects an explicitly allowed
   candidate). Complete the two-Mac transport experiment in the plan.
2. Build the proven adapter/data path and its realistic local TCP/UDP tests.
   Do not fill the missing mechanism with a guessed TCP-only implementation.
3. Wire the native app to the real adapter supervisor and the tested lifecycle.
   Native pane layout, menu, settings, icon and diagnostics presentation may be
   developed independently while waiting for Mac evidence, using inert fixtures.
4. Adapt the reference's packaging/CI/DMG pipeline into this repo, then perform
   macOS builds and installed-app/live acceptance tests.

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

Validation recorded for this implementation: 41 Swift Testing tests in five
suites passed; debug and release builds passed with warnings as errors. Release
CLI smoke checks passed for help, unsupported-platform behavior, invalid input,
0600 report creation, refusal to overwrite and refusal to follow output symlinks.
The verified cloud installation script was executed for a fresh extraction and
then rerun to check repeatability. Native macOS compilation, actual firewall
output, process ownership on the viewer and High Performance forwarding remain
unvalidated. Synthetic macOS-shaped fixtures are explicitly not live evidence.

The user subsequently authorized the initial commit and first release. The first
version is `v0.1.0-alpha.1`, explicitly a diagnostic alpha containing the compiled
CLI in a macOS arm64 DMG. See `.github/workflows/release.yml` and the release notes.
Publication depends on the macOS workflow passing; do not infer publication from
a local tag. Other workspace repositories remain read-only. No firewall/display
changes or running network relay have been made by this implementation.
