# Source-preserving incoming UDP investigation

Inspected and locally exercised on 2026-10-18, macOS 26.7.1 (25G241), arm64,
using system Ruby 2.6.10 and the installed ScreenSharing.framework. This is a
transport feasibility result, not a successful High Performance session.

## Why this path

The controlling Mac's schema-6 report identifies `tcpListenerBind`, port 5900,
`addressInUse`, after every preceding UDP reservation succeeded. Its viewer had
already been fully quit. Native viewer inspection also shows that local TCP
15900 disables Pro mode, while local TCP 5900 encounters the sharing-service
self-connection check. Repeating those attempts adds no new evidence.

Keep Apple's TCP connection directly to the real host instead. Ruby reserves
the incoming LAN UDP tuple before the viewer starts. For each accepted datagram,
it preserves the encrypted payload and remote source IP/port, but changes the
local destination to the already configured 127.0.0.1 address. A privileged raw
IPv4 descriptor permits this envelope without an alias, route or firewall change.
Apple's outgoing traffic remains direct; this candidate does not count native
feedback as forwarded by Ruby.

```text
Host:P -> controller LAN:P -> Ruby UDP receiver
                           -> raw IPv4/UDP envelope
Host:P -> 127.0.0.1:P      -> Apple's wildcard UDP socket
```

The earlier incoming-only relay used a new local source address and ephemeral
port. The new candidate removes that mismatch. The old source mismatch is not
yet proven to have caused the gray-screen failure: native inspection found
source classification but did not establish its final media-drop consequence.

## Kernel evidence

The public kernel revision below is older than the installed OS. The successful
local fixture corroborates the specific delivery mechanism, not every policy
branch in that source revision.

- An unbound raw socket with `IP_HDRINCL` selects raw output without explicitly
  binding the supplied source. The source-interface check permits that case.
  [Raw output](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/netinet/raw_ip.c#L519),
  [source check](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/netinet/ip_output.c#L737).
- Destination 127.0.0.1 follows loopback routing, and IP protocol 17 selects
  normal UDP input. The LAN-bound receiver does not match the loopback
  destination. Existing policy checks still apply.
  [IP input](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/netinet/ip_input.c#L708),
  [UDP lookup](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/netinet/udp_usrreq.c#L692).
- Darwin requires host byte order for raw IPv4 `ip_len` and `ip_off`.
  UDP fields remain network byte order; changing the destination requires a
  newly computed UDP pseudoheader checksum. Preserve the media payload exactly.
  [Apple raw-IP API](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man4/ip.4),
  [UDP checksum](https://www.rfc-editor.org/rfc/rfc768.html).

## Actual local result

The user explicitly approved an administrator prompt for a bounded local fixture.
The root Ruby process created only the raw descriptor, then permanently dropped
UID, GID and supplementary groups before creating the receiving sockets or
starting the native helper. It used owned ephemeral ports, a documentation-only
source address and a synthetic 32-byte payload. Every transmitted packet was
destined to 127.0.0.1. No current sharing session, service, interface, route,
firewall rule or preference was changed.

1. An ordinary wildcard UDP socket received the exact payload with the expected
   nonlocal source address and source port.
2. A separate receiver reserved a LAN-address UDP tuple and connected to that
   documentation peer without sending it any data.
3. The installed Apple's `udpSocketWithAVCMediaStreamConfig:port:` method created
   the native socket. The duplicate connect left it unconnected and wildcard,
   as in the previously verified socket-reuse fixtures.
4. The raw injected packet reached that actual Apple-created socket with the
   expected remote source tuple. The external receiver did not receive it.

The initial Ruby assertion incorrectly treated the native JSON's numeric zero
as false; Ruby treats zero as truthy. The captured native result already showed
`injectionMatchesConfiguredPeer: true`, `nativeConnected: 0`, and
`nativeWildcard: 1`. The assertion was corrected and those recorded results
were independently checked. Do not describe that assertion failure as a kernel
or Apple socket failure. Raw fixture output and native disassembly remain outside
the repository.

## Remaining work

This mechanism has not been integrated into the app or the relay backend. The
released/delivered loopback packages do not implement it. No replacement live
test package is supplied by this investigation.

Integration must keep the privileged bootstrap bounded, discard root immediately,
retain owned-process cleanup, validate a single configured peer, construct valid
bounded packets, reject conflicting loopback receivers, and handle backpressure
without unlimited buffering. Administrator authorization is needed for raw
socket creation; this is a new startup requirement, not a hidden preference.
The raw descriptor remains a powerful capability even after dropping root.

Then verify actual encrypted video/audio, keyboard/mouse, native feedback and
reconnect on the previously working setup. Finally test the restricted Mac's
existing policy and OS version separately. Socket-level receipt does not prove
SRTP authentication/decoding or that the restricted filter permits this path.
Do not release the app as a working High Performance proxy before those gates.
