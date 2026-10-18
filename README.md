# Screen Sharing Proxy

A native macOS project investigating a viewer-side relay for Apple's High
Performance Screen Sharing.

**Native relay app prerelease: `v0.1.0-alpha.6`.** The Apple silicon DMG contains
`ScreenSharingProxy.app`, the user-supplied icon, Applications shortcut and an
offline guide. See [installation](docs/INSTALL.md) and [release notes](docs/releases/0.1.0-alpha.6.md).

On the **controlling Mac**, open **Proxy**, enter the remote IPv4 address and
click **Connect**. The app starts the system Ruby relay, then opens Apple's
Screen Sharing for authentication and mode selection. **Stop Relay** and quitting
the app clean up the owned process. **Settings** contains optional port settings;
**Diagnostics** retains one-click collection and private ZIP export. Session
transport counters can be saved as JSON. The app has no ten-minute experiment cap.

**Performance remains experimental.** A user selected High Performance and
confirmed video plus keyboard/mouse, but that attempt's counters show TCP-only
forwarding with no UDP. The app reports observed transport without claiming
verified high-performance media. Direct sharing may still be faster; operation
under the restricted viewer's rules, audio and sustained stability remain unverified.
The relay does not decode media, handle credentials or change network/display settings.
See [the current handoff](docs/HANDOFF.md) for evidence and the [loopback guide](docs/LOOPBACK_EXPERIMENT_GUIDE.md)
for the separate bounded command-line experiment.

Implemented:

- Native app with Proxy, Settings and Diagnostics tabs. Owned relay start/stop,
  private session reports, one-button diagnostics, automatic ZIP Save dialog and save retry.
  No active Dock preference, login startup or background menu bar utility.
- A read-only macOS diagnostic CLI: firewall entries, executable identities,
  launchd manifest candidates, and correlated TCP/UDP socket snapshots.
- Performance component evidence for the viewer, server, session agent and
  `avconferenced`, including separate app/executable firewall rules, socket
  delegation entitlements, binding categories and visible host UDP-base settings.
- Ten socket snapshots per collection, including unattributed UDP sockets so no
  remote IP entry is required. The ZIP includes diagnostics.json and README.txt.
- Automatic discovery and selection of an explicitly allowed `proxyd`, including
  checks for global overrides, missing executables and ambiguous candidates.
- Bounded subprocess output, monotonic deadlines, cancellation, process-group
  cleanup and exit-status preservation.
- Bounded versioned backend event framing and a session lifecycle that rejects
  stale generations and waits for process exit before allowing another start.
- Tests for failures, races, parsing and default report redaction.

GitHub Actions runs the macOS build/tests on pushes to `main`. Version tags run
the native app DMG workflow, verify the mounted app, launch it, exercise discovery/export and offline commands,
and publish a prerelease only after the uploaded checksums pass. Published assets
are never replaced under an existing version.

On the **viewer Mac**, using Swift 6.2+ / Xcode 26.2, automatically find the allowed
`proxyd` without supplying its path:

```sh
swift run -c release screensharing-proxy-diagnose discover --output proxyd-report.json
```

For the full socket investigation, start the problematic High
Performance connection and run from this checkout:

```sh
swift run -c release screensharing-proxy-diagnose collect \
  --remote REMOTE_IP --samples 3 --output viewer-report.json
```

Replace `REMOTE_IP` with the remote Mac's numeric IP. The report is redacted by
default and the output file is created with owner-only permissions. No elevated
access is requested and no firewall or sharing settings are changed. Read
[the diagnostic guide](docs/DIAGNOSTICS.md) for visibility limits and interpretation.
On Linux the command reports the unsupported platform and exits 2.

Development:

```sh
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

Native macOS development uses the installed Xcode toolchain and system Ruby.
In the original Linux cloud workspace use `bash Scripts/swift-cloud.sh test -j 4
-Xswiftc -warnings-as-errors` instead; the wrapper uses the installed, verified
Swift 6.2 Linux toolchain and writable caches. There are no external package
dependencies.

Build a separate, ad-hoc-signed loopback-relay test ZIP on Apple silicon macOS:

```sh
bash Packaging/build-relay-experiment.sh loopback
```

This is a development artifact for controlled testing, not a published working
proxy. The experiment branch's workflow also saves it as a CI artifact. Read the
[native AVConference findings](docs/AVCONFERENCE_TRANSPORT_FINDINGS.md) before
interpreting relay counters as media success.

[Implementation handoff](docs/HANDOFF.md) ·
[Transport findings](docs/TRANSPORT_FINDINGS.md) ·
[Full plan](docs/IMPLEMENTATION_PLAN.md)
