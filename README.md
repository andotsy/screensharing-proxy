# Screen Sharing Rubyfier

A native macOS patcher for High Performance Screen Sharing through system Ruby.
**Version 1.0.1** supports native video, audio, and keyboard/mouse control.

**Screen Sharing Rubyfier.app** creates **Screen Sharing Rubyfied.app** from the
Apple viewer already installed on the controlling Mac. It bundles optool, a
compiled transport library and Ruby scripts; applying the patch requires no Xcode,
command line tools, Python or gems. The original app and system settings remain
untouched. The copy keeps the native connection UI and authentication flow.

Click **Create Rubyfied App…** and choose a writable folder. Watch progress in the
scrollable, selectable console, then open the created app and enter the sharing
Mac's real IPv4 address. The copy offers to quit the original viewer if needed.
See [installation](docs/INSTALL.md) and [patcher details](docs/RUBIED_PATCHER.md).

The current payload accepts the tested Screen Sharing executable from macOS
26.7.1 (25G241), on Apple silicon. Other native builds fail the compatibility check.
Live High Performance video, audio, and keyboard/mouse control have been verified
on that build. Ruby owns the external network sockets; Apple's native media
engine and image queue run inside the copied viewer. Other macOS builds and
operation under the restricted viewer's network rules remain unverified.
Allow Local Network access when macOS asks. See the installation guide if a
previously denied permission prevents the connection.

The app retains private diagnostics with one-click collection and ZIP export.
The original icon and DMG layout are preserved. Build the local patcher with
`bash Packaging/build-app.sh`; versioned DMG packaging uses
`SSP_VERSION=1.0.1 bash Packaging/build-app-dmg.sh`. These commands do not
publish a release. Existing tags and published assets must never be replaced.

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
