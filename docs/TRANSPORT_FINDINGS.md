# Transport findings

**Latest Rubyfier test:** the user confirms Standard mode works in r3, while
High Performance is a grey screen with incoming Ruby UDP, native helper calls,
and zero outgoing UDP. R4 gives AVC exclusive connected loopback media sockets
on separate native ports; its Apple socket-dictionary and three-channel
round-trip tests pass. Native stream/first-frame/feedback callbacks are now
counted. The user will run the live test; decoded High Performance is pending.
See [the r4 path](RUBIED_PATCHER.md).

**Current direction:** the user requested a self-contained Screen Sharing
Rubyfier patcher. The copied native app now passes injected UI launch and a
synthetic TCP plus three-channel bidirectional native UDP fixture through Ruby.
It bypasses the UI local-target classification by adapting the engine transport
after classification. Live High Performance remains unproven. See
[patcher details](RUBIED_PATCHER.md) and [current handoff](HANDOFF.md).
The earlier loopback and privileged-UDP investigations below are historical.

**Current blocker:** native macOS 26.7.1 inspection and an owned-process runtime
probe show that 127.0.0.1:15900 triggers Apple's local-tunnel classification,
which disables Pro mode. The previous TCP-only session does not validate the
intended media path. The corrected launcher tests local TCP 5900, subject to
existing port ownership and Apple's self-connection check. Release is held.
See [native local target findings](NATIVE_LOCAL_TARGET_FINDINGS.md).

The schema-6 controlling-Mac attempt now identifies a TCP 5900 listener bind
conflict, after all UDP reservations succeeded. Fully quitting the viewer did
not resolve it. Read-only native policy inspection excludes the known quality
option/internal-build preference as a simple fix. An incoming-only design that
preserves the remote source address is being investigated locally before any
further live trial; no successful native media path is claimed. A privileged
raw descriptor, retained after dropping root, now passes source-preserving
delivery to the actual Apple UDP helper on owned high ports. This remains a
socket fixture, not a live SRTP session or app implementation. See
[the source-preserving investigation](SOURCE_PRESERVING_UDP_FINDINGS.md).

Latest status on 2026-10-18: the user reports a live connection through the
loopback relay after the login-reconnect fix, explicitly selecting High
Performance with keyboard and mouse working. Response is slower and colors
slightly more vibrant; causes and successful-session counters are pending.
This is success on the previously working setup, not a restricted-policy test.
Audio, sustained stability and fresh reconnection remain to be checked.

Earlier status: **both incoming-only and initial loopback live tests failed**.
The loopback attempt reached a login prompt but recorded no UDP exchange. Two
reports had `localAddressUnavailable` without an operation label. A separate
`incompatibleProtocol` report matches a reproduced clean-exit supervisor race,
now fixed. A subsequent schema-3 report identified `routeChanged` at `routeCheck`
before any native TCP accept. The relay now verifies its pinned address remains
assigned/up instead of aborting when a fresh socket selects another source.
`Run.command` opens a new native connection after ready. The next live attempt
reached login but stopped after 17/12 TCP bytes. Local Apple-viewer testing
exposed a discovery connection followed by a separate login connection. The
loopback relay now preserves its listener and media sockets between sequential
TCP pairs; the native viewer reaches a synthetic desktop through it. Full High
Performance media/input remains unproven.
See [the current handoff](HANDOFF.md).

The previously working 26.7.1 pair produced gray video and a generic stream error
on repeated incoming-only attempts. Ruby received/submitted media, while host
logs in the matching minute reported missing RTCP feedback. This is not evidence
about the restricted Mac's filter. See the [AVConference follow-up](AVCONFERENCE_TRANSPORT_FINDINGS.md).

`loopback-relay.rb` now forwards TCP and both UDP directions. A connected loopback
feedback receiver and a distinct local injector preserve the peer address/port
Apple expects when connecting to 127.0.0.1:15900. Actual Apple-created sockets
exchange packets through the real Ruby child on all three channels. This requires
no aliases or configuration changes; localhost High Performance negotiation and
complete live media/input remain gates. See [test instructions](LOOPBACK_EXPERIMENT_GUIDE.md).

The user selected system Ruby and declined interface configuration changes.
The original [Ruby relay experiment](RUBY_RELAY_EXPERIMENT.md) forwards TCP and all
three UDP ports in local tests, but macOS CI rejects the separate loopback
addresses with EADDRNOTAVAIL. Its available loopback targets select the same
source/destination address. The proposed native path therefore requires a new
demonstrated binding mechanism under the user's constraint. It is not enabled
in the app, and no working High Performance relay is claimed.

A subsequent UDP reuse experiment demonstrated a candidate incoming path
without aliases: reserve the network tuple first, let the native helper return
an unconnected socket after its tolerated duplicate-connect error, and forward
incoming bytes locally to that socket. The actual native helper accepts the
local test packet on macOS 26.6.2 CI. AVConference source validation, outbound
feedback were then unresolved; the later live attempt failed as recorded above.
The restricted Mac's filter remains untested. This candidate is retained in
incoming-relay.rb, separately from the address-separated relay; see the
[probe results and acceptance gates](RUBY_RELAY_EXPERIMENT.md#socket-reuse-and-a-different-incoming-path).

See [the service and transport research](HIGH_PERFORMANCE_RESEARCH.md) for pinned
sources, attachment hashes, disassembly evidence and the concrete experiment.
The earlier generic TCP/UDP hypothesis was insufficient as a transport design.

Established by Apple documentation:

- Initial RFB control uses TCP 5900 by default.
- High Performance requires bidirectional UDP 5900–5902. Apple's port reference
  identifies RTP/RTCP on these ports.
- Managed `PortBase` changes the UDP base independently of the initial TCP port.
  A different TCP listener does not automatically remap media.

The native GUI exposes that custom TCP destination through its Port field,
including in High Performance mode. Static inspection of the macOS 26.6.2 CI
host's viewer framework finds a UDP creation method that requests reuse options,
binds a wildcard local address at the supplied media port, and connects to the
media peer on that same port. It does not retry a different port on bind failure
inside this method. This refines the bind-conflict hypothesis but does not prove
socket coexistence or packet delivery. See the
[method evidence and version limits](HIGH_PERFORMANCE_RESEARCH.md#the-connection-editors-port-field-and-native-udp-sockets).

Established in supplied macOS 26.7.1 (25G241) files from a separate unblocked Mac:

- `screensharingd` handles server control and dispatches media configuration to
  the session agent. Its media setup reads TCP local/peer IP addresses, assigns
  the configured UDP base to both, and sends the configuration through agent IPC.
- `avconferenced` has a small feature-gated entry point into private AVConference;
  its presence does not establish that it owns the affected session's sockets.
- Its embedded socket-delegation entitlement makes effective network identity
  worth checking alongside the process that holds a descriptor.

Independent implementation evidence identifies HEVC video/AAC audio over SRTP,
with feedback multiplexed on media ports. We have not reproduced its live
measurements. An opaque Python relay should carry the complete TCP stream and
UDP datagrams both ways while Apple retains authentication and media processing.

The server's endpoint derivation makes a viewer-only, address-separated local
relay worth testing. Native-viewer binding behavior, source-tuple acceptance,
port conflicts and actual filtering still determine whether it works.

The user explicitly permits a companion on the remote Mac if necessary;
installation on the controlling Mac alone is a preference. The goal includes
full keyboard/mouse control in both cases. A paired relay can choose its outer
transport ports and control both local connections, but still has to demonstrate
compatible native socket bindings and accepted source tuples at both ends.

The alpha-5 capture from an unrestricted macOS 26.7.1 (25G241) viewer is a
user-confirmed working High Performance session. All ten complete snapshots show
the Screen Sharing client connected to peer TCP 5900, avconferenced UDP 5900 to
the same peer, and avconferenced wildcard UDP 5901. This gives a working-session
reference and exposes a potential relay bind conflict. It does not establish
effective socket delegation or a successful proxied path.

That capture also identifies five accessible, signature-verified Python/Ruby
firewall targets listed as allowed. /usr/bin/python3 has the signing identifier
com.apple.dt.xcode_select.tool-shim-public; its actual launched executable and
receiving-socket identity still need testing. No runtime was executed by the
collector, and no exact proxyd was found. Keep the source ZIP outside the repo.

The subsequent alpha-5 capture from the restricted viewer reports **macOS 27.0.1
(26A434), arm64**. The user confirms an attempted High Performance connection
that failed. This differs from the working reference and supplied binaries;
the previous disassembly is not evidence of identical implementation on 27.0.1.
The remote OS build and precise visible failure stage remain unconfirmed.

The ZIP passes CRC validation. All ten snapshots are complete with zero unparsed
records; all 63 probes exit without truncation. The two nonzero exits are the
missing proxyd manual and unavailable local host media preference. Completeness
describes the collected observations, not visibility into every system socket.
Across approximately twelve seconds, the relevant observations are:

| Samples (zero-based) | Observation |
| --- | --- |
| 0–2 | Screen Sharing and avconferenced processes present; no sockets attributed to them in the report |
| 3 | Screen Sharing has an established TCP connection to remote port 5900 |
| 4–7 | Established TCP to the same peer, with a different local ephemeral port; the reason for the change is unmeasured |
| 8–9 | TCP remains established; avconferenced has connected IPv4 UDP local 5900 → peer 5900 and local 5901 → peer 5901, using the same local/peer addresses as TCP |

Unlike the working reference's wildcard UDP 5901, both restricted-viewer UDP
sockets have a specific local address and remote peer. This is a difference in
observed bindings, not proof that the OS version or firewall caused it. Only two
snapshots show media sockets. No UDP 5902 is observed; its absence does not remove
it from the documented range. A connected UDP socket does not establish delivery.
The TCP descriptor is labelled IPv6 by lsof; that alone does not identify the
on-wire address family. Process identities are stable across the observations.

The firewall list contains eight allow and eight block entries. The explicit
Screen Sharing block targets the **viewer client executable**, not a listed
screensharingd rule. Neither screensharingd nor avconferenced has an explicit
entry in this capture; absence is not an allow decision. avconferenced again has
the socket-delegation entitlement, without proof of actual delegated identity.

| Restricted-viewer runtime candidate | Listed rule | Identity / implication |
| --- | --- | --- |
| Python.app | Block | Accessible signed executable, identifier com.apple.python3; private installation path omitted |
| /usr/bin/python3 | Allow | Accessible signed com.apple.dt.xcode_select.tool-shim-public launcher; launched runtime and its receiving identity are unknown |
| /usr/bin/ruby | Allow | Accessible signed com.apple.ruby executable; first candidate for a controlled inbound TCP/UDP test, not yet a verified relay |

No exact proxyd is discovered. No runtime was executed. The Python shim's allow
entry must not be treated as permission for the blocked Python.app; this report
does not show whether the shim launches that particular installation.

The collector reports global firewall and block-all states as **unknown** and
all component per-target queries as unknown, despite those commands exiting
zero with no stderr. Signed-app policy is empty. Their original stdout is not
retained, so the cause and actual policy cannot be reconstructed. Preserve
unknown rather than infer enabled/disabled from listed entries. A future probe
should retain bounded, privacy-safe evidence for unrecognized firewall output
before changing parsers. The report contains no packet counters or filter logs
and does not prove which process identity was filtered or where packets dropped.

| Question | Current answer |
| --- | --- |
| Uploaded binary origin | Separate unblocked Mac; user reports 26.7.1 (25G241); metadata says SDK/minimum 26.7 |
| Affected viewer/remote OS builds | Restricted viewer 27.0.1 (26A434), arm64; remote build unconfirmed |
| Allowed `proxyd` path / interface | No exact proxyd found in either capture; restricted viewer has Ruby and Python-shim allow entries, but Python.app is blocked |
| Actual filter and effective rule | Viewer client explicitly listed blocked; global policy and effective socket attribution unknown; user confirms failed High Performance attempt |
| Receiving socket owner(s) | Restricted viewer: avconferenced holds connected UDP 5900 and 5901 to the TCP peer in the final two snapshots; delivery and filter identity unverified |
| Server media address derivation | TCP local/peer IPs with configured UDP base, confirmed in supplied daemon |
| Viewer binding / source validation | Working session: specific-address UDP 5900 and wildcard UDP 5901. Restricted attempt: specific-address connected UDP 5900 and 5901. Relay bindings and peer acceptance remain untested |
| Loopback delivery and socket coexistence | Incoming candidate passes real Ruby/native-helper socket tests on 26.6.2 CI and local 26.7.1; AVConference media acceptance is unproven |
| Complete High Performance session via relay | Not tested |

The user initially recalled proxyd as the permitted executable. Both captures now
supply runtime candidates, but their actual receiving permission still needs
measurement. Python cannot acquire another process's allowance by being launched
by it. Ruby is a plausible alternative on the restricted Mac if peer tests pass;
the application should not require Python when its real runtime is blocked.

Next: verify an allowed runtime's actual socket identity and bidirectional TCP/UDP
delivery between the two Macs under the existing rules, beginning with system
Ruby. Resolve the global-policy evidence gap. In parallel with that experimental
design, use the unrestricted pair to test native bindings and source acceptance
through the address-separated relay, including a remote companion when needed;
repeat a proven path on the restricted 27.0.1 viewer. No daemon execution,
firewall changes or live forwarding were performed during this research. Create
`docs/adr/0001-transport.md` only after a complete data path is demonstrated.

The existing protocol/lifecycle code controls a future app-owned adapter. It is
not a protocol for Apple's daemon and grants no ability to reconfigure it.
