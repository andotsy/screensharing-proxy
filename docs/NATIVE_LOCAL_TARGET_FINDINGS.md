# Native local target classification

Research date: 2026-10-18. Native host: macOS 26.7.1 (25G241), arm64.
The alpha-6 release is held pending a working native UDP path. Passing relay
socket tests and a TCP video/input session do not satisfy that gate.

## Confirmed defect in the previous target

Read-only inspection of ScreenSharing.framework, loaded into an owned disposable
process, found this call chain:

1. `SSAddressResolver.localhostMatchesAddress:` checks whether the address belongs
   to this Mac. For a local address it returns 1 for TCP port 0/default or 5900,
   and 2 for another port. A remote address returns 0.
2. `SSSessionView.connect` sets `connectionDoesNotSupportProMode` for result 2.
3. `ssSessionWantsProModeInterface:` returns false for that flag. Its diagnostic
   describes an SSH tunnel that does not support Pro mode.

A separate owned-process runtime probe called the observed classifier with
numeric addresses; it made no TCP/UDP connections and changed no preferences:

| Target | Classifier result |
| --- | --- |
| IPv4 loopback, TCP 5900 | 1 |
| IPv4 loopback, TCP 15900 | 2 |
| IPv6 loopback, TCP 5900 | 1 |
| IPv6 loopback, TCP 15900 | 2 |
| Documentation-only remote IPv4, either port | 0 |

The existing `127.0.0.1:15900` experiment therefore requests a native target that
disables Pro mode on this OS. This is a concrete setup defect consistent with
the live zero-UDP report. It does not reconstruct that historical session's UI
state, and does not mean the user did not select High Performance earlier.

The classifier treats existing local interface addresses as local too. Merely
replacing loopback with this Mac's LAN address on port 15900 does not fix it.
No conclusion about macOS 27's implementation follows from this probe.

A follow-up requested by the user tested this development Mac's existing
Thunderbolt IPv4 address with the same unmodified native classifier. Its own
Thunderbolt address returns 1 at port 5900 and 2 at port 15900, matching loopback;
the other Mac's address returns 0 at both ports. This probe performs no network
connections or configuration changes. Disassembly of `isLocal:` explicitly
enumerates `getifaddrs` and compares IPv4/IPv6 interface addresses. The connection
path applies the classifier to `resolvedAddresses`, so a hostname resolving to
the controlling Mac's own interface address does not avoid the check. A genuinely
remote address avoids this particular gate but does not itself provide the
required local Ruby UDP ingress.

An additional bounded local socket probe tested wildcard listeners without
assigning another address. TCP and UDP reached 127.0.0.1, but TCP timed out and
UDP was not received at unassigned 127.0.0.2. Wildcard binding is therefore not
a demonstrated replacement for the rejected alias. Published
[XNU destination matching](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/netinet/ip_input.c#L1317)
requires a configured destination before local socket delivery; this older
public kernel source corroborates, rather than directly audits, the installed OS.

## Corrected experiment and remaining gate

The user's schema-6 attempt fails at `tcpListenerBind`, port 5900, with
`addressInUse`. All preceding UDP reservations completed; startup stopped before
ready or any TCP accept. Fully quitting the viewer did not resolve it.

On the development sharing host, ordinary lsof returned no TCP 5900 listener,
but the kernel socket table showed a wildcard launchd listener at that port.
This reproduces the visibility discrepancy, not ownership on the controlling
Mac. Apple's launch job declares a `vnc-server` socket; launchd can hold that
socket independently of a viewer window or a running server process.
See [Apple's launchd socket lifecycle](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).

Further native inspection and an owned-process predicate fixture establish:

- `screenSharingEnabledLocally` calls `SMJobIsEnabled` for
  `com.apple.screensharing`; it is not a test for an open viewer window.
- `AllowLocalConnect` is consulted only after `SSIsInternalBuild` succeeds;
  the installed production framework returns false for that internal check.
- `ssSessionWantsProModeInterface:` returns false with the local-tunnel flag
  even when the app delegate requests Pro mode. The fixture executes the
  original implementation with inert getters, without connecting a session.
- URL options dispatch to enumerated `option_*:` handlers. Quality and virtual
  display requests exist; no separate transport address, proxy endpoint or
  local-target exemption was found in that surface. This is an inspected
  surface, not a proof that every private entry point has been exhausted.

Changing a quality URL parameter or retrying another local port therefore
does not supply an evidence-based fix for this path.

The launcher now explicitly selects local TCP 5900. No published asset/tag is
replaced. The viewer has a separate self-connection refusal when local Screen
Sharing is enabled; the relay also fails without disturbing existing port owners.
Thus port 5900 is a candidate, not a universal solution. No service or network
configuration changes are part of the test.

Collect one relayed session's active mode, video/input result and UDP counters.
The user has checked greyed-out quality controls on a direct connection only;
that is not an observation of the relay connection. If true media starts but
relay UDP stays zero, observe the peer's UDP headers across physical/loopback
interfaces and address families rather than infer absence from reserved sockets.
Encrypted control bytes must remain opaque; do not collect credentials or keys.

The app implementation at this point still has the old default local TCP port.
Do not tag/release it as a working High Performance app. Integrate a proven target
and its eligibility checks before releasing. The existing macOS CI runs passed
the app lifecycle, TCP/UDP fixtures and packaging checks, not this native gate.

## Public research

- [Apple Screen Sharing guide](https://support.apple.com/guide/mac-help/share-the-screen-of-another-mac-mh14066/mac):
  Adaptive Quality and Full Quality are Standard-only controls; virtual displays
  and their Dynamic Resolution/HDR controls identify the High Performance UI.
- [Apple High Performance requirements](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac):
  bidirectional UDP is required, and only one High Performance session is allowed
  per Mac. Do not attribute an unrelated direct session's logs to the relay.
- [Remotex measured protocol](https://github.com/andrewtheguy/remotex/blob/main/docs/apple-vnc-889.md)
  and [media receiver](https://github.com/andrewtheguy/remotex/blob/main/src/vnc_apple_media.rs):
  independent implementation evidence distinguishes Standard TCP image codecs
  from High Performance media negotiation, uses the TCP peer/local IPs and the
  announced UDP ports, and reports native media failure closing the session.
- [iShareScreen experimental specification](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md):
  media-init signaling alone does not demonstrate the offer/answer exchange or
  UDP media. Its framebuffer fallback profile is not evidence that Apple's own
  viewer silently falls back.
- [Rootshell transport configuration](https://github.com/kitknox/rootshell/blob/main/rootshell/Features/VNC/VNCConnectionConfig.swift):
  another client separates stream-only jump transports from datagram-capable
  High Performance transport. That is its policy, not Apple's local-address rule.

No verified native-viewer loopback TCP+UDP proxy matching these constraints was
found in the GitHub/Gist/Stack Overflow/discussion search. Public implementations
provide useful protocol evidence, not an already validated replacement relay.
