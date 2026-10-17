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

`VTPRecvProc` reads socket traffic and passes packets to
`VTP_DemuxPacketsToVFDList`. The demultiplexer considers real descriptors,
packet classifications and media identifiers. `_RTPRecvWithSocket` subsequently
uses `VTP_Recvfrom` and `_RTPTransport_ParseVTPPacket`. The separate transport
callback `_VCTransportStreamVTPHandlePacketReceived` converts a VTP packet and
invokes the registered callback.

The framework also contains `VCSDInfoIsSrcDstInfoMatchedWithIP`, which compares
the supplied source IP with stored peer information for type-2/unconnected
contexts. Its existence must not be ignored, but this inspection did not
establish whether the active Screen Sharing receive path calls it or whether
it applies to every media stream. Do not infer either source acceptance or
rejection from its name alone.

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
- 66 Swift tests in 12 suites and the release build pass with warnings as errors.
- Four packaged-command smoke tests pass, including INT/TERM/HUP cleanup,
  automatic timeout, exclusive report creation, occupied-port refusal, report
  privacy and port release. These fixtures use high ports and send no packets
  to the documentation-only remote address.

The standalone [incoming experiment command](INCOMING_EXPERIMENT_GUIDE.md)
reuses the existing Swift supervisor and system Ruby. It reports local UDP
submission, never decoded video or working High Performance. The app's Proxy
and Settings tabs remain disabled.
