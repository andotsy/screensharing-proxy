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

| Question | Current answer |
| --- | --- |
| Uploaded binary origin | Separate unblocked Mac; user reports 26.7.1 (25G241); metadata says SDK/minimum 26.7 |
| Affected viewer/remote OS builds | Not collected |
| Allowed `proxyd` path / interface | Not collected; neither attachment establishes it |
| Actual filter and effective rule | User-reported restriction; not reproduced |
| Receiving socket owner(s) | Not collected on the affected viewer |
| Server media address derivation | TCP local/peer IPs with configured UDP base, confirmed in supplied daemon |
| Viewer binding / source validation | Not established; native client not supplied |
| Loopback delivery and socket coexistence | Not tested |
| Complete High Performance session via relay | Not tested |

The user prefers viewer-only installation and recalls `proxyd`, rather than
Python, as the allowed executable. Python cannot acquire another process's
allowance by being launched by it. Identify the permitted socket owner and its
supported interface before selecting the backend.

Next: obtain the viewer report when available, resolve native-client bindings
and the permitted process, then run the address-separated relay experiment in
the research note. No daemon execution, firewall changes or live forwarding
were performed during this research. Create `docs/adr/0001-transport.md` only
after a complete data path is demonstrated.

The existing protocol/lifecycle code controls a future app-owned adapter. It is
not a protocol for Apple's daemon and grants no ability to reconfigure it.
