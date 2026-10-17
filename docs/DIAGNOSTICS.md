# Collecting the viewer's evidence

The command is for the **viewer Mac**: the Mac running Screen Sharing to view
the other Mac. A report helps identify the recalled `proxyd` and the relevant
receiving sockets. It does not establish a working relay or diagnose a firewall
drop from a missing packet alone.

The recommended collection is the native app from alpha 4:

1. Open the app on the viewer and keep the Screen Sharing connection attempt open.
2. Click **Collect Diagnostics**. Collection takes ten socket snapshots.
3. The Save dialog opens automatically. Save the ZIP and forward it for investigation.

The ZIP contains `diagnostics.json` (schema 2) and `README.txt`. Private addresses
and paths are redacted automatically. No manual remote IP, privacy choice,
baseline or phase selection is needed. All visible UDP sockets are retained;
unknown owners/ports stay unattributed rather than being labelled session traffic.
Saving uses owner-only permissions and atomic replacement after Save dialog
confirmation. If saving is cancelled or fails, **Save ZIP Again…** reuses the
completed archive. Cancelling collection preserves the previous completed archive.
Closing the window quits, waits for owned probes to stop, and cancels an open
save sheet. There are no Dock/startup settings or background menu bar utility.
The app removes its own legacy launch-at-login registration when upgrading.

Alpha 3 used a paired capture UI; it has been replaced by this one-action flow.
Older paired exports remain interpretable using their `redactionScopeID`.

For CLI collection, use a local checkout with Swift 6.2+ and Xcode 26.2 (or the corresponding Swift
toolchain). Building and running this collector requires no Python. From the
repository directory:

```sh
swift build -c release -Xswiftc -warnings-as-errors
.build/release/screensharing-proxy-diagnose discover --output proxyd-report.json
```

Discovery finds candidate paths automatically from the firewall list, running
processes and launchd metadata. It checks executable accessibility and explicit
incoming rules. When a candidate has no recognized list entry, it queries
`socketfilterfw --getappblocked PATH` using the discovered path. No path input or
manual configuration is required. Unknown query output is not interpreted as allow.

`runtimeCandidates` separately records Python/Ruby entries from the firewall
list, including versioned executables and Python.app bundles. It records the
listed rule, resolved executable/accessibility and signing identity where readable;
private paths remain redacted. Bundle executables come from bounded Info.plist
metadata, never guessed names. These runtimes are not executed or promoted to
verified relays. A `proxyDiscovery.status` of `notFound` means only that no exact
`proxyd` was found; it does not mean no Python/Ruby runtime is allowed.

For exact `proxyd` discovery, a unique allowed executable is selected. If several distinct executables are
allowed, the sole observed running one is preferred; multiple running matches
or multiple inactive matches remain ambiguous. Aliases of the same file are
deduplicated, while conflicting alias rules prevent selection. Global block-all,
unreadable policy and a disabled application firewall have explicit outcomes.
Signed-app defaults and a valid signature alone never count as explicit allowance.

`proxyDiscovery.selectedExecutable` reports the selected executable (redacted if
private). Selection is a prerequisite observation, not proof of forwarding
capabilities or a working High Performance session. The native app can use the
raw in-memory result of `DiagnosticsCollector.inspect` for its startup preflight;
it should rerun discovery on startup/start instead of saving a permission assumption.

`discover` exits 0 when a candidate is selected, 3 when discovery remains unresolved,
and 2 on an unsupported platform. `collect` exits 0 even for a partial macOS report;
read probe outcomes and completeness rather than interpreting exit 0 as readiness.

For socket evidence while the failure is happening:

```sh
.build/release/screensharing-proxy-diagnose collect \
  --remote REMOTE_IP --samples 10 --phase duringSession --output viewer-report.json
```

Start the failing High Performance session before collecting. `REMOTE_IP` must
be a numeric IPv4/IPv6 address, including a scope such as `%en0` for link-local
IPv6 when appropriate. Hostnames are not resolved by this collector. A different
address family/peer selected by Screen Sharing needs its own observation.

For comparison, collect another report with Screen Sharing disconnected using
a **new output filename** and `--phase baseline`. Independent CLI invocations
have separate redaction scopes; do not compare address/path token numbers between
them. The native app exports a single collection with ten snapshots. The CLI refuses to overwrite existing files or follow
an output symlink. `--samples` is 1–10; `--interval` is 0.2–5 seconds. Each probe
has a three-second deadline; sample cadence includes probe execution time, so
these are not fixed-frequency packet measurements. Ctrl-C cancels the active
probe, cleans up its process group, and emits a partial report with exit 130.

What it reads:

- Public OS version/architecture fields.
- `socketfilterfw --getglobalstate`, `--getblockall`, `--getallowsigned`, and
  `--listapps`; application entries are retained with private paths redacted, so
  an inaccurate recollection of the daemon's name can be resolved from the list.
  `--getappblocked PATH` is also read-only and used for unresolved proxy candidates
  and accessible performance components. Component executable and enclosing-bundle
  rules/queries are separate observations, including any conflicts.
- `ps -axo pid=,lstart=,comm=` before and after each `lsof` sample. `comm` reads
  executable paths, not command-line arguments. `lsof -nP -iTCP -iUDP -F0pcftPnT`
  supplies structured socket records.
- Screen Sharing client, `screensharingd`, `ScreensharingAgent` and `avconferenced`
  paths from known locations, processes, firewall entries and service metadata.
  `samples[].processes` includes PID, start time and before/after presence, even
  without sockets; name-based role hints do not authenticate the executable.
- Exact-name `proxyd` candidates in process/firewall data and matching launchd
  plists in the system, local and current user's standard launch directories.
  Only labels, program paths and Mach-service/socket names are retained. It does
  not dump service environments or program arguments, or call `launchctl print`.
  Relevant Apple service manifests are included too, including the session-agent
  manifest at `/private/etc/com.apple.screensharing.agent.launchd` if present.
- `codesign` verification/identity for up to eight discovered candidates, plus
  `man -w proxyd` to locate a local manual if available. It never executes the
  discovered daemon or guesses command flags for it.
- For up to sixteen performance component paths, signature/identity and
  `com.apple.private.network.socket-delegate` from bounded `codesign` entitlement
  output. Only that boolean is retained. Missing/unreadable output stays unknown;
  a true entitlement does not prove delegation is used or identify an effective PID.
- `defaults read com.apple.ScreenSharingServer hostSettings`, retaining only a
  valid `portBase` in 1024–65535. This is the local preference view visible to the
  collecting user. A failed read remains unavailable, never a confirmed default.
  The documented default is recorded separately as 5900; the active session base
  remains unknown. Other host settings and raw output are not exported.

The commands do not enumerate process environments, request packet captures,
change a firewall rule, reconfigure a service or establish a network connection.
They run as the current user. Incomplete visibility is recorded; do not interpret
an absent process/socket as proof that it does not exist. Nonzero `lsof` status
remains incomplete even when it could mean no matching sockets.

Default reports replace private addresses and non-system executable paths with
consistent tokens within that report. System executable paths, ports, PIDs,
service labels and signing identifiers remain visible because they identify the
mechanism being investigated. Token mappings are not exported; tokens are not
stable across independent collections. The ten snapshots in one report share a
`redactionScopeID`. Older alpha-3 pairs also share a scope. `--include-private` explicitly retains addresses
and full paths for local investigation. Raw stdout/stderr from probes is never
included in the report. Report files are mode 0600 regardless of the current umask.

Socket selection includes known Screen Sharing/media/proxyd names, connected
sockets matching `--remote`, default TCP 5900 / UDP 5900–5902 port hints,
UDP base/base+1/base+2 hints from the visible local host preference, and all
other UDP sockets. Port arithmetic never wraps past 65535. Port hints may
match unrelated traffic and are not protocol identification. `localAddressKind`
and `remoteAddressKind` preserve wildcard/loopback/non-loopback distinctions even
when the literal address is redacted. UDP without another match is marked
`unattributedUDPSocket` when connected or `unattributedUDPListener` otherwise.
An unconnected UDP socket has no known peer and
may belong to an unrelated app. Unresolved process identities stay unresolved;
two consistent snapshots reduce races but do not make collection atomic.

Interpret results carefully:

| Field | Establishes | Does not establish |
| --- | --- | --- |
| `listedFirewallRule: allow` | A recognized allow entry was read | Effective permission through every filter, or inherited permission for another executable |
| `proxyDiscovery.status: selected` | An accessible candidate has explicit allowance without a known global override | A supported proxy API, effective permission through another filter, or successful media routing |
| `signatureVerified: true` | The signature command completed successfully | Forwarding capability or firewall allowance |
| `components` | Observed or known-location component paths and separate firewall/signing checks | That the executable is active, owns media or is the effective firewall identity |
| `mediaPortConfiguration` | Documented default and any visible local host preference | The remote host's settings or active session ports |
| `services` | Matching static launchd metadata | Running service ownership or a public forwarding API |
| Socket with `remotePeerMatch` | A connected socket reports that peer | UDP media purpose, received data, or decoded video |
| `consistentProcessSnapshots` | PID/start/path matched before and after | An atomic snapshot or elimination of every PID-reuse race |
| `highPerformanceRelay: notVerified` | No live relay result is being claimed | A failed experiment; none has run yet |

Next, inspect the identified executable's local manual and documented interfaces.
Resolve whether it supports per-session UDP as well as the control path. The
two-Mac experiment and unchanged-firewall acceptance criteria are in
`IMPLEMENTATION_PLAN.md`. There is deliberately no command that launches
`proxyd`, redirects packets, changes firewall policy or installs a remote helper.
