# Screen Sharing Proxy — implementation plan

Planning date: 2026-10-17. Status: first infrastructure implementation completed;
transport experiment pending. See `HANDOFF.md` for the current implementation.

The user subsequently authorized implementation on the current model, beginning
with complex infrastructure. Simpler UI/distribution work may move to
gpt-6.1-sol-xhigh later. The transport design retains its mandatory feasibility
experiment; the UI and release design can be specified independently.

## 1. Goal and repository roles

Build a native macOS utility that makes Apple's **High Performance Screen
Sharing** usable when incoming traffic for its receiving process is blocked on
the **viewer Mac**, while a suitable relay process is permitted. The remote Mac
already accepts the required traffic.

Use these terms consistently:

- **Viewer:** the Mac the user operates, running Apple's Screen Sharing client
  and the proposed proxy app. This is the Mac with the firewall restriction.
- **Remote:** the Mac whose desktop is displayed. Its firewall is not the
  reported problem.
- **Relay:** the process that actually owns the network sockets receiving the
  traffic. Its executable identity and effective firewall treatment matter.

`/workspace/screensharing-proxy` is the working repository. It was empty before
this planning document. Other workspace checkouts are read-only. The application
must build independently without dependencies on sibling checkouts. Do not
publish private project names, repository links or commit identifiers.

The proxy does not configure displays, call private display APIs, manage
WindowServer, or restart Apple's sharing services. Existing display-management
tools on the remote Mac remain independent.

The user also requires automatic discovery of the `proxyd` executable with
incoming connections allowed. The app must perform this preflight itself; it
must not require the user to locate or enter the daemon path. Distinguish missing,
blocked, unknown and ambiguous candidates. The first implementation provides
this discovery in the shared core and diagnostic CLI.

Initial scope: one viewer, one remote profile, one active Screen Sharing session,
native menu bar app, a useful diagnostics panel, and a downloadable DMG.
The user confirmed a viewer-only installation is preferred. Plan v1 around that
boundary; a remote companion would require a later explicit scope change. No
public relay service is planned.

## 2. What is established and what is not

| Item | Evidence / conclusion |
| --- | --- |
| Native UI and release design | A native settings panel and independently built diagnostic DMG are planned. |
| High Performance transport | Working hypothesis: separate control, UDP media and feedback paths. The actual flows still need to be observed. |
| Port 5900 | A normal starting point for RFB/TCP control; not a complete High Performance transport specification. Actual flows must be observed. |
| Firewall problem | Reported by the user; not independently reproduced. The exact firewall implementation and receiving executable remain to be identified. |
| Allowed process | The user recalls that `proxyd`, rather than `/usr/bin/python3`, is allowed. Its exact identity, supported interfaces and actual permission are unconfirmed. |
| Development host | This cloud machine is Debian Linux x86_64. Python is available; Swift/Xcode and macOS frameworks are not. |
| Current application state | A diagnostic CLI, portable process/protocol/lifecycle core and tests exist. No relay backend, GUI or successful proxy session has been demonstrated. |

**Do not design around an assumed TCP-only solution.** TCP forwarding may carry
login/control while video or feedback continues directly to a blocked UDP socket.
Standard Screen Sharing success is not High Performance success.

The user's clarification makes **identify `proxyd` and its capabilities** the
first investigation. Do not select Python as the receiving process by default.
A Python process does not run "through proxyd" merely because it is launched
from another process. A launchd parent, process name, port number, or copied
executable name does not establish firewall identity. Check the executable that
owns the socket and the firewall's observed decision. If `proxyd` is an existing
Apple component, identify its documented capabilities before treating it as a
general-purpose forwarding service.

Likewise, `/usr/bin/python3` cannot be assumed to be a usable runtime on every
clean Mac. Some installations depend on Command Line Tools or expose a launcher
stub. A bundled Python or a Swift helper would have a different identity and
cannot silently substitute for the reportedly permitted executable.

Do not hardcode UDP 5900–5902, assume that global HTTP/SOCKS proxy settings affect
Screen Sharing, or assume the receiving process is named `screensharingd` on the
viewer. The client, an agent, or a media service may own the relevant sockets.

## 3. First milestone: prove the complete network path

Implement a small diagnostic collector and disposable relay experiment before
the production backend. Run the network experiment on the two actual Macs;
Linux tests and GitHub-hosted macOS runners cannot reproduce this firewall setup.

### 3.1 Record a precise baseline

Record both OS builds and architectures, the selected Screen Sharing mode, the
viewer/remote roles, active interfaces, address families, and observed failure:
unable to connect, successful authentication with no picture, missing audio,
or later disconnection. Keep private addresses and raw diagnostic material local.

On the viewer, inspect:

- `sw_vers`, `uname -m`, running Screen Sharing/media process executable paths,
  and `lsof -nP -iTCP -iUDP` correlated with the specific session's processes.
- For Apple's Application Firewall, read-only `socketfilterfw` global state,
  block-all state, signed-app settings and relevant application entries. If a
  different filter is responsible, use its actual rule/log evidence instead.
- The exact allowed `proxyd` path, file identity/code signature where applicable,
  owning service, documented command/IPC/configuration interface, supported
  protocols and launch behavior. Resolve it from the firewall entry and process
  information; do not assume that a similarly named Apple service is the same
  program. Read its local manual/service metadata once identified. Determine
  whether clients can request per-session forwarding without changing a global
  system proxy. Do not launch it with guessed private flags.
- Only if that investigation gives Python a real role, inspect the exact runtime
  version and required standard-library features. Test the eventual app's launch
  arrangement, not only invocation from Terminal.
- Narrow, session-scoped packet-header observations on the physical and loopback
  interfaces, plus bounded relevant Apple logs. Request administrative access
  only if the diagnostic operation needs it. Payload dumping is unnecessary.

Do not toggle the global firewall or modify the blocked app's rule as part of
the solution. Existing known-good sessions can supply a comparison baseline.
If unavailable, report that the absolute performance baseline is missing.

Produce a flow table: initiating side, receiving process/path, TCP or UDP,
local/remote tuple, direction, purpose when established, and the evidence for it.
Observe authentication, media startup, video, audio, feedback and reconnect.
Do not infer a media stream's identity from port numbers alone.

### 3.2 Test the allowed socket owner

Use a minimal controlled peer exchange between these two Macs to demonstrate
that the proposed process can receive both the relevant TCP and UDP traffic
under the existing firewall rules. Verify actual bytes in both directions.
An open port, successful bind, or allowed entry in a settings list is insufficient.

Check whether the permission changes when a service is requested by the native
app (or a Python backend is launched, if applicable), when its resources reside
inside a signed app bundle, or after the app is moved
from Downloads to Applications. Do not rename binaries or modify Apple-signed
executables to manufacture the expected identity.

### 3.3 Resolve routing and negotiation

The preferred experiment is an opaque transport relay: Apple's endpoints retain
authentication, encryption, encoding and decoding. The relay forwards bytes or
datagrams without interpreting credentials or decrypting media.

For control, try a separate loopback listener, provisionally TCP 15900, forwarding
to the remote's observed control port (normally TCP 5900). Port 5900 is not
privileged, but may already be occupied. Never evict an existing listener.
Verify that connecting Apple's client to a custom loopback endpoint still offers
High Performance mode and authenticates the intended remote identity.

For media, establish all of the following before calling the design viable:

1. How the remote learns the viewer's media/feedback endpoints, whether they
   come from transport addresses or negotiated fields, and whether those fields
   are encrypted or authenticated.
2. How incoming media reaches a relay-owned external socket instead of the
   blocked Apple socket, and how outbound feedback traverses the correct path.
3. Whether forwarding to loopback is accepted by both the firewall and Apple's
   receiver, including connected-UDP peer checks and expected source tuples.
4. Whether Apple binds wildcard addresses/ports that conflict with the relay,
   and how IPv4 and IPv6 selection affect the complete path.
5. Whether the implementation relies on undocumented protocol rewriting. If so,
   record that explicitly; it is not an opaque, stable forwarding implementation.

Simply binding a second socket on Apple's port, using `SO_REUSEPORT`, or sending
the datagram back to the same host cannot establish reliable interception and
may distribute packets incorrectly or loop them. Relaying a TCP connection does
not automatically redirect separately negotiated UDP streams. A generic SOCKS
service, SSH TCP forward, or remote companion alone does not resolve these issues.

### 3.4 Choose one proven design

| Result | Decision |
| --- | --- |
| Existing allowed system service exposes a supported interface that carries the complete session | Use that interface; do not introduce a Python dependency without a purpose. |
| Python can own the necessary sockets and all endpoints can be routed through it without privileged interception | Use the supervised Python relay described below. This is the preferred Python design. |
| Only narrowly scoped local packet redirection can make the relay path work | Treat this as a privileged architecture change. Prove packet-filter ordering, socket attribution, source-tuple preservation, return routing and cleanup before proposing the helper. |
| A remote companion or a packet tunnel is required | This exceeds the preferred viewer-only/simple-relay design. Document the evidence and required scope change; do not implement it without agreement. Prove the full path; do not assume a companion fixes negotiation. |
| No complete path works under the existing constraints | Record the failed hypothesis and required constraint change. Do not ship a TCP-only app claiming to fix High Performance mode. |

Any privileged variant needs its own design record and tests. A packet-filter
variant must preserve existing rules, use only its own narrowly scoped state,
and have crash/reboot cleanup. It must not flush global rules or disable filtering.
A Network Extension or signed privileged service may change entitlement/signing
requirements and therefore cannot inherit an ad-hoc-only release plan blindly.

Deliver `docs/TRANSPORT_FINDINGS.md` with OS builds, sanitized flow table,
experiment commands, observed outcomes and unknowns, plus
`docs/adr/0001-transport.md` with the chosen data path and exact process ownership.
An unsuccessful experiment is a useful result; it does not unlock implementation
of a backend whose essential mechanism is still unknown.

**Gate:** with the original blocked rule unchanged, demonstrate an actual High
Performance picture, keyboard/pointer input, audio when enabled, sustained
changing video for at least ten minutes, and successful disconnect/reconnect.
Record which flows pass through the relay and any flows intentionally left direct.
Repeat the original direct failure sufficiently to distinguish a transient
connection recovery from a relay fix, when doing so does not disrupt other work.

## 4. Production architecture after the transport gate

Working product name: **Screen Sharing Proxy**. Swift package/executable:
`ScreenSharingProxy`; app: `ScreenSharingProxy.app`; bundle identifier:
`com.andotsy.screensharing-proxy`. Initial target: Apple silicon, macOS 14+;
record tested OS versions separately from the deployment minimum. Use Swift 6.2+
and the macOS 26 SDK, matching the reference's build tooling.

Logical components:

- **ProxyCore:** configuration, draft/committed settings, endpoint validation,
  backend protocol, capabilities, state transitions and diagnostic models.
- **ScreenSharingProxy:** SwiftUI/AppKit UI, login item registration, window/menu
  management, platform probes and process supervision.
- **Relay backend:** investigate an adapter to the recalled allowed `proxyd`
  first, using only its established interface and ownership model. Only the
  backend proven by milestone 1 becomes the production data path. If Python wins,
  package standard-library Python source as an app resource and execute the
  exact verified absolute interpreter path. No pip dependency at runtime.
- **Development fixtures:** local TCP/UDP peers and a deterministic fake backend
  for testing failure, cancellation and UI behavior without live Screen Sharing.

The main app normally runs as the logged-in user. A Python backend is its child,
not an always-running root daemon. Login startup uses `SMAppService.mainApp`.
Do not create a standalone LaunchDaemon unless the accepted transport design
requires it. The app bundle contains its own resources and never reads runtime
files from sibling checkouts.

### Python relay requirements, if selected

- Choose the minimum Python version from the measured system runtime. Use
  compatible standard-library APIs and test that version in CI. Do not assume
  the Python version used for packaging equals the target runtime.
- Resolve and validate the interpreter during a bounded preflight. Use isolated,
  unbuffered execution without bytecode writes (`-I -u -B`, if supported by the
  established runtime), explicit script paths and an explicit working directory.
  Do not use a shell command string or a PATH-based interpreter fallback.
- TCP forwarding: partial reads/writes, backpressure, bounded buffers, connect
  deadlines, independent EOF/half-close handling and reliable cancellation.
- UDP forwarding: preserve datagram boundaries, support both directions, enforce
  the proven endpoint mappings, reject unexpected peers, bound queues and expire
  session state. Handle truncation/oversized datagrams explicitly. Do not add
  retransmission, decode media, or put a TCP wrapper around UDP by default.
- Bind control only to loopback. Any necessary external media listener binds
  only the selected interface/address and accepts only the selected peer/session.
  Pin resolved endpoints for the active session; do not accept arbitrary
  destinations from network clients. Avoid an unauthenticated general relay.
- Implement only proven address families. If IPv6 is not supported in v1, reject
  it clearly and ensure a successful-looking IPv4 control connection cannot
  leave an unsupported IPv6 media path active.
- Measure relay CPU, memory, throughput, drops and latency under representative
  traffic. The experiment decides whether Python is adequate; no fixed claim
  about FPS or performance is made from forwarded byte counts.

### Backend control and supervision

Use inherited stdin/stdout pipes for versioned newline-delimited JSON commands
and events. Use stderr for bounded diagnostic logs. This avoids opening a local
HTTP control server. Include protocol version, request ID and a fresh session
identifier; validate message size and schema. Never carry video over these pipes.

These pipes describe an app-owned child/adapter. An existing system `proxyd`
keeps its established IPC and service lifecycle; do not claim ownership of that
daemon, kill it on quit, or impose this protocol on it. The adapter must release
only this app's session resources and prove cleanup if the app exits or crashes.
If the service provides no supported per-session lifecycle, the integration has
not passed the feasibility gate.

Commands for an app-owned backend: `configure`, `start`, `stop`, `snapshot`,
`shutdown`. Events:
`ready`, `state`, `metrics`, `error`, `stopped`. `ready` includes resolved endpoint
and backend capability information. Capture stderr independently so a full pipe
cannot deadlock startup or shutdown.

The supervisor owns the child process object and termination observer. Require
a handshake within a bounded deadline; distinguish permission, missing runtime,
address conflict, DNS/connect, and incompatible protocol errors. Child exit must
be observed before resources are considered released. Parent/control-pipe EOF
must stop the relay and close sockets, including after an app crash.

Serialize lifecycle operations. Stop cancels pending starts and retry timers.
Graceful shutdown has a bounded timeout, followed by termination of only the
owned child if necessary. Avoid stale-PID kills. An active-session crash becomes
an explicit interrupted state; never claim the Apple session silently recovered.
At most three bounded retries for transient pre-session launch failures; no
retry loop for missing permissions, occupied ports or invalid configuration.

State model: `off → checking → starting → listening → relaying`, with explicit
`stopping`, `interrupted`, and `blocked(reason)` states. Relay traffic counters
establish transport activity, not successful frame decoding. Only show a
High Performance/presentation confirmation when supported by actual evidence;
otherwise label the UI “Traffic flowing” or “Waiting for Screen Sharing”.

### Configuration and data

Use UserDefaults for UI preferences and a schema-versioned atomic configuration
file under `~/Library/Application Support/ScreenSharingProxy/` for the single
remote profile. Store host, observed/default control port, local endpoint choice
and only transport options established by the experiment. Backend discovery
results should be refreshed rather than treated as permanent permissions.

Do not store Screen Sharing passwords; Apple's client owns its authentication.
Do not log protocol payloads, credentials or media keys. Diagnostics redact
private endpoint details by default. Rotate logs during long-running sessions,
not just at process spawn; an initial bound is 5 MiB per file plus two old files.

## 5. Native app and interaction design

Adapt the reference's `PanelController`, `WindowMaterialBackground`, pane strip,
grouped rows, button treatment and menu bar integration. Use a roughly 580×546
resizable panel with stable dimensions, scrolling content and native system
accent colors. Navigation: **Connection**, **General**, **Diagnostics**.

**Connection:** a plain-language status and optional error, the remote address
and port, a separate **Start Proxy / Stop Proxy** control, and **Open Screen
Sharing** enabled only once the endpoint is ready. Launch the verified connection
form through `NSWorkspace`; prove that the chosen URL/launch path reaches the
intended native client with High Performance available. Never silently switch
to Standard mode.

Endpoint edits form a draft with separate trailing **Revert** and **Apply**
buttons beneath the scrolling content, matching the reference. Apply persists
valid changes while stopped. During an active session, make the fields read-only
and explain that the proxy must be stopped before changing the destination.
Closing the panel hides it and preserves the running connection; **Quit** stops
the relay and therefore may end a proxied connection. Display configuration is
outside this application's lifecycle.

**General:** launch at login, show in menu bar, show in Dock, and an optional
start-proxy-at-login preference (off initially). Keep a recoverable visible entry
point if both visibility settings are changed. Login may start the saved relay
when explicitly enabled; it should not force an Apple login prompt by opening
Screen Sharing automatically.

**Diagnostics:** backend availability, observed listener/session state, platform
versions, last failure, current transport counts, **Copy Diagnostics**, and
**Open Logs**. Technical port mappings and interpreter identity belong here,
not in the primary connection flow. “Permission unknown” must stay distinct from
“blocked”. Avoid broad recurring `log show` or privileged polling.

Menu: current status, open connection panel, start/stop, open Screen Sharing,
diagnostics and quit. Use an accessible monochrome template icon; distinguish
states with text, not color alone. Support keyboard navigation, VoiceOver,
light/dark appearances, nondefault accent, Reduce Transparency, Increase Contrast
and long error messages. Guard macOS 26 glass button styles with availability
checks; retain native macOS 14 styles below that.

## 6. Icon direction

Use **two endpoint dots linked through a central rounded relay block**, with two
offset opposing arrow paths. The silhouette should read as an intermediary
passing traffic in both directions at 16–32 px. Avoid locks or shields, which
would imply security features, and avoid outward resize arrows.

App artwork: deep blue/teal paths on a pale cyan tile; a charcoal/blue dark
appearance with lighter cyan paths. UI controls continue to use the system accent.
Use an original vector source, a separate simplified menu glyph, an Icon Composer
document for current macOS, and a deterministic ICNS fallback generator. Review
actual Finder, Dock and menu bar sizes. Icon production happens during
implementation, not this planning phase.

## 7. Proposed repository layout

```text
AGENTS.md                         # repository scope and implementation rules
Package.swift
Sources/ProxyCore/
Sources/ScreenSharingProxy/
Relay/                            # only if the Python backend is proven
Tests/ProxyCoreTests/
Tests/ScreenSharingProxyTests/
Tests/RelayTests/
Tests/Fixtures/
Packaging/
  build-app.sh
  Info.plist
  AppIcon.icon/
  app-icon.swift
  dmg-background.swift
  dmg-settings.py
  requirements.txt
  README.html
Scripts/                          # narrowly scoped development diagnostics
.github/workflows/ci.yml
.github/workflows/release.yml
docs/IMPLEMENTATION_PLAN.md
docs/TRANSPORT_FINDINGS.md
docs/adr/0001-transport.md
docs/DEVELOPMENT.md
docs/INSTALL.md
docs/TESTING.md
assets/
```

Create only the files required by the selected design. A service-backed relay
does not need a pretend Python package. Add ignored paths for generated bundles,
Swift build output, DMGs, caches and local diagnostics. Do not commit packet
captures, raw private logs, signing material or local user paths.

## 8. Build, CI and DMG release

Independent CI runs on pull requests and default-branch changes; release runs
only for a version tag or an explicit dispatch naming an existing tag.

**CI:** run the Python standard-library unit/integration tests on Linux and
macOS if that backend is selected. Run Swift debug build, tests and release
build with warnings as errors on a verified Apple silicon macOS runner using
Xcode 26.2. Verify runner architecture instead of assuming a label is arm64.
Pin GitHub Actions to reviewed commit SHAs. Preserve test command exit status
and verify nonzero test execution. CI gets no live Screen Sharing credentials.

**Bundle assembly:** require an explicit `SCREENSHARING_PROXY_VERSION`; reject
invalid/missing versions. Build resources into a self-contained
`ScreenSharingProxy.app`. If using system Python, the bundle contains the relay
source and all app resources, with its external interpreter prerequisite stated
accurately. Generate current appearance assets and ICNS fallback, populate
bundle versions and deployment target, and sign inside-out. Verify resource
lookup with the app moved to a path containing spaces and without the checkout.

Initially follow the reference's ad-hoc signing/no-notarization model only if
the proven backend and privilege requirements permit it. Code signing and
firewall permission are distinct checks; confirm the installed release's actual
socket owner. A Developer ID certificate/notarization is a later option, not an
invented required secret. Privileged/extension variants must settle their signing
requirements before this milestone is considered complete.

**DMG:** adapt the reference's pinned `dmgbuild` requirements, generated background
and app-to-Applications arrow layout, with `README.html` and Terminal shortcut.
The guide must work offline. Publish a styled compressed DMG and `SHA256SUMS`,
not a ZIP. Required interpreter installation, if any, must be visible in the
guide; do not label the app dependency-free if that is false.

If using the reference's manual quarantine/signature repair approach, adapt all
paths and bundle checks to this app and test the exact command on a disposable
copy. Keep `docs/INSTALL.md` and the embedded guide in sync. Never modify or
re-sign the system interpreter. A repair script must reject unrelated apps.

**Release checks:** verify version/tag/HEAD consistency, binary architecture,
deployment target, code signatures, packaged relay resources, light/dark icon
assets, DMG integrity, mounted contents, offline guide and installed-resource
resolution. Create a draft release, upload DMG/checksums, download and verify the
uploaded assets, then publish only when the release invocation is authorized.
Never replace a published binary under an existing version. The live two-Mac
matrix remains a release prerequisite and is not claimed by hosted CI.

## 9. Validation and acceptance

| Layer | Required coverage |
| --- | --- |
| Relay TCP | Full-duplex payload identity, partial writes, backpressure, EOF/half-close, failed connect, cancellation and repeated sessions. |
| Relay UDP | Datagram boundaries/size handling, bidirectional mapping, unexpected-peer rejection, expiry, queue bounds, loss/reordering behavior and supported address families. |
| Lifecycle | Missing interpreter/service, malformed IPC, oversized events, stderr flood, occupied port, child crash, parent crash/EOF, stop during startup, duplicate starts and bounded shutdown. |
| Configuration/UI | Draft/apply/revert, invalid host/port, no reconfiguration while active, persistence, hidden/reopened panel, login registration failures and accessible status. |
| macOS integration | Real allowed executable launched from installed app, firewall attribution, custom endpoint/client launch, and complete TCP/media/feedback routing. |
| Live session | High Performance explicitly selected; changing video, audio when enabled, pointer/keyboard, reconnect, sleep/wake/network change, lock/unlock and cleanup after quit/crash. |
| Packaging | Install on a test Mac, runtime prerequisite handling, resources without checkout, icons, signatures, DMG/readme integrity and update behavior. |

Use existing public interfaces where possible and realistic local peers for
transport tests. Tests must not disable a firewall, change a real user's sharing
settings, or depend on an active personal session. Use real macOS process tests
for supervision as well as fakes; fakes alone cannot prove cleanup behavior.

For a passing live run, record mode, OS builds, endpoint family, actual owner of
the receiving sockets, duration, reconnect outcome, and CPU/memory/latency/drop
observations. High forwarded throughput does not establish low latency or decoded
FPS. Set performance thresholds from the initial measured baseline before
optimizing. Include a higher-resolution session if that is the user's actual
workflow, without having this app change display modes itself.

Do not call the product complete if only loopback tests, TCP authentication,
standard-mode screen sharing, or macOS compilation passes.

## 10. Implementation order and handoff

1. **Feasibility evidence:** identify the recalled `proxyd` executable, establish
   its supported forwarding capabilities within the viewer-only scope;
   add the diagnostic collector, run the two-Mac experiment, and write the
   transport findings and decision record. This is the first implementation task.
2. **Transport slice:** build the selected backend and realistic TCP/UDP fixtures;
   demonstrate the same successful path through the production backend.
3. **Native shell and lifecycle:** add package/core/app targets, process control,
   configuration, states, login handling and failure tests. A UI skeleton and
   packaging scaffolding may be prepared while awaiting Mac access, but do not
   treat them as evidence that the network mechanism works.
4. **Complete UX and diagnostics:** implement the Connection/General/Diagnostics
   panes, menu, endpoint launch, original icon and useful error reporting.
5. **Distribution:** adapt bundle assembly, CI and DMG release checks; verify an
   installed app on the target Macs, including the allowed process identity.
6. **Acceptance:** run the live matrix and record limitations. Release only after
   the core High Performance/firewall acceptance gate passes.

Suggested bounded changesets follow these six milestones, with tests and docs
alongside the behavior they describe. Keep display management outside this app.
Create commits, tags, pushes and releases only when authorized by the user.

Before continuing, the next model should read this document and `HANDOFF.md`,
check current user answers and repository status, and preserve the read-only
reference boundary. Implementation is now authorized. Do not claim a model
switch has occurred; the user will choose when to move simpler work to Sol.

### Pending observations, with defaults that do not block planning

- Exact executable currently permitted: **user recalls `proxyd`, not Python;
  exact path and capabilities must be measured before choosing the backend**.
  No assumption that `proxyd` and Python are equivalent.
- Deployment: **viewer-only preferred, confirmed by the user**. A companion is
  outside the v1 plan unless the user later accepts a necessary scope change.
- Access to the two Macs: **not available in this Linux session**. Prepare the
  experiment for a later Mac session; do not claim a remote connection was tested.
- Firewall implementation and OS builds: **record during the first experiment**.

## 11. Research limits

The transport design remains a hypothesis rather than a current Apple protocol
specification. Confirm supported platform interfaces from official documentation
and measurements during the Mac feasibility work. The actual viewer firewall,
Python identity, `proxyd` interface and High Performance relay behavior still
require validation on the user's Macs.
