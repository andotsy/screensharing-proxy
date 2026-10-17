# Screen Sharing Proxy

A native macOS project investigating a viewer-side relay for Apple's High
Performance Screen Sharing.

**First prerelease: `v0.1.0-alpha.1` (diagnostic alpha).** Its macOS arm64 DMG
contains a compiled diagnostic CLI, an offline guide and a Terminal shortcut.
See [installation](docs/INSTALL.md) and [release notes](docs/releases/0.1.0-alpha.1.md).

The first implementation supplies the difficult process-control and evidence
collection foundations. **There is no functioning Screen Sharing relay or GUI
yet.** The reportedly permitted `proxyd` executable and its forwarding interface
must be identified on the viewer Mac before a backend is chosen.

Implemented:

- A read-only macOS diagnostic CLI: firewall entries, executable identities,
  launchd manifest candidates, and correlated TCP/UDP socket snapshots.
- Automatic discovery and selection of an explicitly allowed `proxyd`, including
  checks for global overrides, missing executables and ambiguous candidates.
- Bounded subprocess output, monotonic deadlines, cancellation, process-group
  cleanup and exit-status preservation.
- Bounded versioned backend event framing and a session lifecycle that rejects
  stale generations and waits for process exit before allowing another start.
- Tests for failures, races, parsing and default report redaction.

GitHub Actions runs the macOS build/tests on pushes to `main`. Version tags run
the diagnostic DMG workflow, verify the mounted contents and offline commands,
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

In this cloud workspace use `bash Scripts/swift-cloud.sh test -j 4
-Xswiftc -warnings-as-errors` instead; the wrapper uses the installed, verified
Swift 6.2 Linux toolchain and writable caches. There are no external package
dependencies.

[Implementation handoff](docs/HANDOFF.md) ·
[Transport findings](docs/TRANSPORT_FINDINGS.md) ·
[Full plan](docs/IMPLEMENTATION_PLAN.md)
