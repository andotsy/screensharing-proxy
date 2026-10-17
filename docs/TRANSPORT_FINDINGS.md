# Transport findings

Status on 2026-10-17: **documented transport and server-side address derivation
identified; backend selection and a live relay experiment remain pending**.

See [the service and transport research](HIGH_PERFORMANCE_RESEARCH.md) for pinned
sources, attachment hashes, disassembly evidence and the concrete experiment.
The earlier generic TCP/UDP hypothesis was insufficient as a transport design.

Established by Apple documentation:

- Initial RFB control uses TCP 5900 by default.
- High Performance requires bidirectional UDP 5900–5902. Apple's port reference
  identifies RTP/RTCP on these ports.
- Managed `PortBase` changes the UDP base independently of the initial TCP port.
  A different TCP listener does not automatically remap media.

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

| Question | Current answer |
| --- | --- |
| Uploaded binary origin | Separate unblocked Mac; user reports 26.7.1 (25G241); metadata says SDK/minimum 26.7 |
| Affected viewer/remote OS builds | Not collected |
| Allowed `proxyd` path / interface | Not collected; neither attachment establishes it |
| Actual filter and effective rule | User-reported restriction; not reproduced |
| Receiving socket owner(s) | Not collected on the affected viewer |
| Server media address derivation | TCP local/peer IPs with configured UDP base, confirmed in supplied daemon |
| Viewer binding / source validation | Direct working session: specific-address UDP 5900 and wildcard UDP 5901; bindings and peer acceptance through a relay remain untested |
| Loopback delivery and socket coexistence | Not tested |
| Complete High Performance session via relay | Not tested |

The user initially recalled proxyd as the permitted executable. The unrestricted
capture supplies Python/Ruby candidates, but the restricted Mac's identity and
effective permission still need measurement. Python cannot acquire another
process's allowance by being launched by it.

Next: use the unrestricted pair to test native bindings and source acceptance
through the address-separated relay, including a remote companion when needed.
Obtain the restricted viewer report when available and repeat the proven path
under its existing firewall rules. No daemon execution, firewall changes or live
forwarding were performed during this research. Create `docs/adr/0001-transport.md`
only after a complete data path is demonstrated.

The existing protocol/lifecycle code controls a future app-owned adapter. It is
not a protocol for Apple's daemon and grants no ability to reconfigure it.
