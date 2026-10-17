# Native AVConference transport follow-up

Inspected locally on 2026-10-18: Apple silicon, macOS 26.7.1 (25G241), system
Ruby 2.6.10, Xcode Swift 6.3. The restricted viewer's reported 27.0.1 build is
still a separate, untested target.

This inspection loaded the system AVConference framework in a disposable
process and disassembled its methods with LLDB. It did not attach to the running
media service, invoke its session APIs, capture media, or alter network settings.
Raw framework metadata/disassembly stays outside the repository. A temporary
loader called only `dlopen`, a local breakpoint marker, and `dlclose`.

## Outbound feedback

The inspected functions establish an explicit-destination path for unconnected
UDP sockets inside AVConference:

1. `-[VCTransportSessionSocket connectSocket:remoteAddress:storage:]` converts
   the configured address and calls `VTP_SetSourceDestinationWithIPPort`. In
   this inspected method, the name does not denote a fresh POSIX `connect` call.
2. `VTP_SetSourceDestinationWithIPPort` updates a virtual descriptor's stored
   destination through `VCSDInfoConstructWithSocket`.
3. `VCSDInfoConstructWithSocket` calls `getpeername`. A connected socket selects
   destination-info type 3; failure plus a supplied peer selects type 2 and
   copies that peer. An unconnected socket therefore has an implemented path.
4. `_RTCPSendWithSocket` calls `VTP_Send`, which calls
   `_VTP_SendWithSourceDestinationInfo`. Its type-2 branch passes the stored
   peer and a cleared connected flag to `VTP_SendOnePacketWithSocket`.
5. `VTP_SendOnePacketWithSocket` converts that peer to a sockaddr, puts it in
   `msghdr.msg_name` with a nonzero length, and calls `sendmsg`. The connected
   branch instead supplies a null destination.

This removes the assumption that all native feedback necessarily uses a plain
`send` on the unconnected descriptor. It is static control/data-flow evidence,
not proof that a live Screen Sharing session selects and completes this path.

## Incoming packet acceptance remains open

### Live failure and source-check follow-up

The user subsequently tested the incoming-only command on the previously
working 26.7.1 pair. Repeated attempts showed gray startup video and a generic
stream failure. The report contains 19,492 received datagrams, 19,484 local
submissions and eight drops over 52.06 seconds, ending by user interruption.
This establishes Ruby receipt and local submission, not native acceptance.
It is not a test of the restricted 27.0.1 setup.

Read-only host log inspection for the corresponding minute found eight
`checkRTCPPacketTimeoutAgainstTime:lastReceivedPacketTime:` errors, each with
the last receive timestamp reported as `nan`. This supports missing accepted
RTCP feedback on the host during those starts. It does not distinguish no send,
bad routing, rejected feedback or a viewer that never accepted media. Other
sessions were not correlated by a shared identifier, so the temporal match is
evidence rather than a complete per-session trace. Raw reports/logs stay private.

Bounded direct-branch inspection now establishes this socket receive chain:

`VTPRecvProc` -> `VTP_SetConnectionFlagsForPacket` ->
`VCSDInfoIsPacketFromKnownRemote` -> `VCSDInfoIsSrcDstInfoMatchedWithIP`.

For the observed type-2 socket context, the final routine compares the configured
IPv4 peer with the packet source. The connection-flags routine starts the packet
field at offset 0xe0 at -1 and changes it to zero on a known-peer match when a
connection-manager lookup has not already supplied a classification. The
inspected `VTPRecvProc` consumer skips `_VTP_HealthPrint` for -1. It still proceeds
to packet processing/demultiplexing; this is **not proof of a media-drop gate**.
Earlier uncertainty about the caller is resolved, but the actual failure cause
remains unproven. No native method, memory, service or filter was patched.

The new [loopback candidate](LOOPBACK_EXPERIMENT_GUIDE.md) removes the local
source mismatch and forwards feedback through Ruby. Its native-helper fixture
proves equal-port, peer-preserving delivery and feedback on this OS. These are
socket-level results, not a passed native SRTP session or a confirmed fix.

`VTPRecvProc` reads socket traffic and passes packets to
`VTP_DemuxPacketsToVFDList`. The demultiplexer considers real descriptors,
packet classifications and media identifiers. `_RTPRecvWithSocket` subsequently
uses `VTP_Recvfrom` and `_RTPTransport_ParseVTPPacket`. The separate transport
callback `_VCTransportStreamVTPHandlePacketReceived` converts a VTP packet and
invokes the registered callback.

The initial inspection also found `VCSDInfoIsSrcDstInfoMatchedWithIP`, which compares
the supplied source IP with stored peer information for type-2/unconnected
contexts. The later follow-up above identifies a socket receive caller without
establishing its effect on the failed session. Do not infer source acceptance
or rejection from the function's name alone.

Consequently, local delivery to Apple's kernel socket still does not establish
that locally forwarded SRTP is accepted, authenticated and decoded. The next
decisive check is a controlled live High Performance session, including input,
enabled audio, feedback/recovery and fresh reconnect, followed by the same test
under the restricted viewer's existing rules.

## Local validation

- Six incoming-relay real-socket tests pass, including the actual Apple UDP
  helper at equal local/remote media ports on all three channels.
- Two portable startup checks for the original relay pass. Seven tests needing
  distinct loopback addresses are explicitly skipped on macOS.
- Eight loopback-relay tests pass, including bidirectional real-Ruby/native-helper
  delivery on all three channels, TCP half-close, fresh restart and occupied owners.
- 67 Swift tests in 12 suites and the release build pass with warnings as errors.
- Four packaged-command smoke tests per mode cover INT/TERM/HUP cleanup,
  automatic timeout, exclusive report creation, occupied-port refusal, report
  privacy and port release. These fixtures use high ports and send no packets
  to the documentation-only remote address.

The standalone [loopback experiment command](LOOPBACK_EXPERIMENT_GUIDE.md)
reuses the existing Swift supervisor and system Ruby. It reports local UDP
submission, never decoded video or working High Performance. The app's Proxy
and Settings tabs remain disabled.
