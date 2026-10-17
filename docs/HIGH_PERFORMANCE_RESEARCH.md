# High Performance Screen Sharing: services and relay requirements

Follow-up on 2026-10-18: native development is now available on the user's
macOS 26.7.1 Mac. [AVConference transport findings](AVCONFERENCE_TRANSPORT_FINDINGS.md)
record an explicit-destination send path for unconnected UDP sockets and the
remaining receive/source-validation limits. The incoming-only relay subsequently
failed on the previously working pair, with gray video and host RTCP timeouts.
The new [loopback candidate](LOOPBACK_EXPERIMENT_GUIDE.md) forwards TCP and both
UDP directions with matching local peer tuples. Native socket tests pass; a
complete live session remains unproven. Its first live tests subsequently failed
after the login prompt without reported UDP exchange. The [current handoff](HANDOFF.md)
records the supervisor fix and additional evidence needed for the address errors.

Research date: 2026-10-17. This updates the preliminary transport hypothesis used
for the diagnostic alphas. It is static analysis and documented research, not a
successful relay experiment.

The supplied files came from a **separate, unblocked Mac running macOS 26.7.1
(25G241)**, as reported by the user. They were not copied from the affected
viewer or remote Mac. They establish implementation details for that build,
not the affected viewer's running processes or firewall policy. Its diagnostics
are still pending.

## Evidence and confidence

- **Apple documentation:** TCP 5900 for initial control, UDP 5900–5902 for High
  Performance RTP/RTCP, and a configurable UDP base independent of the initial
  TCP listener. These are documented requirements. [1–3]
- **Supplied binaries:** metadata, imports, embedded entitlements and arm64e
  disassembly inspected without executing them. Addresses below refer to these
  files before ASLR. Signature trust was not verified on this Linux host.
- **Independent implementation:** iShareScreen code and protocol notes inspected
  at a fixed revision. Its author reports interoperable sessions; we have not
  run the implementation or reproduced those packet observations. Its memo is
  experimental and disagrees with its own code on one field discussed below. [4]
- **Still missing:** native-viewer socket bindings, filter attribution, the
  permitted `proxyd` identity/interface and a complete live relay experiment.

## What crosses the network

Apple's macOS 26 guide requires both Macs to communicate over UDP 5900, 5901 and
5902. It recommends consistent low latency and **75 Mbit/s for one 4K display**.
Apple's port reference explicitly identifies RTP/RTCP on these UDP ports and RFB
on TCP 5900. [1][2]

The official `ScreenSharingHostSettings.PortBase` schema sets the initial UDP
port, incremented for additional connections, independently of the initial TCP
5900 listener. The separate connection declaration exposes a TCP `Port` setting.
Changing a relay's TCP listener therefore does not automatically remap media.
These settings do not provide a generic forwarding API. No managed configuration
was applied in this research. [3]

| Flow | Purpose and evidence | Relay responsibility |
| --- | --- | --- |
| TCP 5900 by default | RFB authentication/control, Apple session/display/media negotiation. Port documented by Apple; handlers present in the supplied daemon. | Full bidirectional byte stream, including control after video begins. |
| UDP base, normally 5900 | Apple documents RTP/RTCP. Independent implementation identifies audio and multiplexed audio feedback. | Complete datagrams in both directions, including feedback/liveness. |
| UDP base + 1, normally 5901 | Apple documents RTP/RTCP. Independent implementation identifies video and multiplexed video feedback. | Complete datagrams in both directions with bounded delay/buffering. |
| UDP base + 2, normally 5902 | Required by Apple's guide; additional video capacity is consistent with negotiation structures. Exact active role on the target session is unmeasured. | Include in the experiment; do not classify as a dedicated RTCP port. |

These are the documented default ports and the independently reported common
mapping, not an exhaustive specification of every version/mode. DNS/Bonjour
and optional authentication services are separate from the media path.

## Service responsibilities

| Component | Established role | Evidence limit |
| --- | --- | --- |
| Screen Sharing.app on the viewer | Native session client and UI. | Its executable was not supplied; exact media socket ownership/binding remains unknown. |
| `screensharingd` on the controlled Mac | RFB authentication/control and dispatch of media configuration to session agents. | The server attachment does not identify the blocked receiving process on the viewer. |
| `ScreensharingAgent` on the controlled Mac | The daemon starts/contacts `com.apple.screensharing.agent` and dispatches display/media work through agent RPCs. Independent analysis identifies its AVConference setup. | The agent executable was not supplied for independent disassembly here. |
| `AVConference.framework` | Private framework imported by `avconferenced`; independent implementation identifies its media negotiation/SRTP role. | Framework implementation was not included; modern macOS may store it in the dyld shared cache. |
| `avconferenced` | Small, feature-gated AVConference service entry point with network/socket-delegation entitlements. | Presence and capability do not prove this process owns a particular session's sockets. |
| `SSFileCopySender` / `SSFileCopyReceiver` | Separate helpers included in the supplied server bundle. | No evidence they need separate forwarding for the initial video/audio experiment. |
| Recalled `proxyd` | User-reported allowed executable. | Neither attachment identifies it or establishes a forwarding API for Python. |

The server binary contains `AcceptNewConnectionTCP`, SRP/authentication handlers,
`HandleServerMediaStreamConfiguration` and agent RPCs. Its load commands do not
directly import AVConference; media work is dispatched through the agent path.
This does not exclude indirect framework loading by other components.

## Findings from the supplied build

### The `avconferenced` executable is not the media implementation

It contains x86_64/arm64e slices. Embedded metadata identifies
`com.apple.avconferenced`, version `2215.5.1`, SDK/minimum OS 26.7. In arm64e:

- `0x1000008e4` calls `VCFeatureFlagManager_UseAvconferenced`.
- The enabled branch calls `AVConferenceServerStartInternal(1)` at
  `0x100000934`, then runs the main run loop.
- The disabled branch logs `avconferenced main() is disabled.` and returns.

Most implementation is therefore beyond this small executable, in its private
framework dependency. Its entry point provides no general TCP/UDP proxy command
interface in the inspected code.

The embedded entitlement `com.apple.private.network.socket-delegate` matters.
XNU supports effective PID/UUID association through `SO_DELEGATED` and
`SO_DELEGATED_UUID`. [5] Inspect effective filter attribution alongside `lsof`
ownership. This does not prove delegation is used for the affected session or
how its firewall evaluates it. Python does not inherit that entitlement or an
allow rule merely by being launched by another process.

### Server media addresses are derived from the TCP connection

The server is `com.apple.screensharing.daemon`, version `3.9.8`, build
`744.4.105.1`, SDK/minimum OS 26.7. In the path identified by
`HandleServerMediaStreamConfiguration`:

1. `0x10003da74`: `getsockname` on the viewer connection descriptor.
2. `0x10003ecc8`: `getpeername` on the same descriptor.
3. `0x10003f884`: calls the managed UDP-base getter at `0x10004cf04`, whose key
   is `portBase` (CFString at `0x1000aa608`) and fallback is `0x170c` = 5900.
4. `0x10003f88c`–`0x10003f894`: converts that base to network order and writes it
   into both local and remote socket-address structures.
5. `0x10003f92c` onward: copies those addresses and the media configuration into
   the buffer passed through `SetMediaStreamConfiguration` at `0x10003fa18`.

Thus this server path obtains media IPs from the TCP endpoints and initializes
media ports from the configured base. It does not simply use the TCP peer's
ephemeral source port for media.

The getter's helper at `0x10004d55c` calls `CFPreferencesCopyAppValue` at
`0x10004d57c` for `hostSettings` in `com.apple.ScreenSharingServer`. Its dictionary
check and error string identify that domain/key; `0x10004d604` accepts a numeric
`portBase` in 1024–65535 and otherwise uses the caller's default. Alpha 3 reads
the visible dictionary with a bounded `defaults read` and retains only the base.
That current-user view is not proof of the daemon's effective preferences, the
remote host's settings or a negotiated media endpoint.

**Implication:** a local TCP relay connecting outward from the viewer's LAN IP
can cause this server path to address media to that LAN IP and the UDP base.
Forwarding encrypted media locally may therefore be possible without editing
media offers. This still depends on native-viewer binding/source validation,
and does not prove later AVConference negotiation never changes an endpoint.

### The connection editor's Port field and native UDP sockets

The native connection editor exposes a custom Port even with High Performance
selected. Apple's connection schema defines `Port` as **the TCP port number on
the host to initiate the connection**. Its separate host settings schema defines
`PortBase` for UDP and explicitly says it does not change the initial TCP port.
[3] A local Ruby listener can therefore use a different TCP port from the
remote server. This removes any need to move the remote server's TCP listener
merely to reach the relay. It does not establish separate local UDP media ports.

The [older custom-port answer](https://superuser.com/a/472119) changes the server's
launchd TCP listener. It predates High Performance mode and provides no evidence
about its UDP transport. Its system-file/service changes were not performed.

Read-only inspection on the macOS 26.6.2 (25G83), arm64 CI host locates
`+[SSSession udpSocketWithAVCMediaStreamConfig:port:]` in the system
ScreenSharing framework. `Scripts/inspect-viewer-framework.swift` loads that
framework and reads bounded method metadata/code without invoking the method
or opening a native session. The initial method capture is preserved in
[run 39067471379](https://github.com/andotsy/screensharing-proxy/actions/runs/39067471379).
The follow-up [evidence job](https://github.com/andotsy/screensharing-proxy/actions/runs/39067881619/job/117499207660)
resolves the Objective-C calls and authenticated import slots to `socket`,
`setsockopt`, `__bind`, `inet_addr`/`inet_pton`, `__connect`, `__error` and `close`.
Those function pointers are read, not invoked. Relevant offsets from the method
entry are +0x44 (socket), +0x68/+0x80 (reuse options), +0x12c (bind), +0x1f8
(connect), +0x210 (compare errno with Darwin EADDRINUSE, 48), and +0x330 (close).
Disassembly establishes this sequence in the inspected method:

1. Read `remoteAddress.isIPv6` from the media configuration and create a UDP
   socket for the corresponding address family.
2. Request both `SO_REUSEADDR` and `SO_REUSEPORT`. The method does not check the
   results of those option calls.
3. Bind a wildcard local address using the supplied 16-bit media port. On bind
   failure, log the error, close the socket and return -1. This method contains
   no retry selecting another port.
4. Replace the wildcard with `remoteAddress.ip`, retaining that same port, and
   connect the UDP socket to it. Return the descriptor on success. It also
   tolerates `EADDRINUSE` from **connect**; other connect failures close it.

The observed port argument is independent of a TCP connect operation in this
method. The server evidence above independently initializes media ports from
its UDP base. The connection field therefore cannot be assumed to change the
native viewer's local media port or solve a same-address media collision.

The reuse options refine the earlier conflict hypothesis: a wildcard bind is
not automatically exclusive, and a future experiment must account for native
reuse before deciding which separately addressed sockets can coexist. Reuse
does not by itself prove which receiver gets a packet or solve identical local
and peer tuples. The Ruby experiment currently deliberately omits reuse options
and has not demonstrated coexistence with this native method. Adding a loopback
alias alone would not prove that implementation works either.

These findings describe the CI host's method, not every AVConference path or
the restricted viewer's macOS 27.0.1 implementation. Caller retries, later socket
changes, loopback acceptance, actual filter attribution and working media remain
unmeasured. In particular, tolerating a failed UDP connect must not be mistaken
for evidence of successful delivery.

### Published protocol notes are not an exact specification for this build

The independent implementation reports HEVC/H.265 video and AAC audio over
SRTP, with SRTCP/RTCP feedback multiplexed on media ports. Its code implements
AES-256-CTR and HMAC-SHA1-80 media protection, using keys exchanged in encrypted
control messages. [4] An opaque relay does not need to implement these codecs
or cryptographic algorithms.

A concrete inconsistency: protocol memo section 10.3 calls the flags at offset
`+6` little-endian; `protocol/negotiation.py:205` at the same revision writes
big-endian. The supplied daemon reads that word and executes a `rev` at
`0x10003d954` before storing it back. Its diagnostic path also labels length
fields audio and `v1`–`v4`. That does not establish four active video channels or
additional required ports. Matched client/agent analysis and captures are needed
before implementing any wire parser from the published structure layout.

## What Python would transport

For an opaque relay, Apple retains authentication, key negotiation, video/audio
encoding and decoding, and media feedback generation. Python would:

1. Forward the full TCP control stream with ordering, backpressure and half-close.
   Keep it running for input, cursor, display changes, renegotiation and teardown.
2. Forward every datagram for each active media tuple in both directions without
   changing its bytes. Include encrypted video/audio, sender/receiver reports,
   keyframe/loss feedback, application-specific feedback and liveness traffic.
3. Preserve datagram boundaries and the source/destination tuples expected on
   each side. Detect truncation, bound queues, expose drops and avoid tunnelling
   real-time media over TCP. Prepare UDP sockets before negotiation starts media.
4. Clean up on cancellation/reconnect, reject stale session traffic and handle
   interface/address-family changes. Measure sustained throughput and latency on
   the actual viewer; the documented bandwidth requirement is not a benchmark.

No SRTP keys, video decoding or recreation of AVConference is needed **if** the
endpoint routing remains opaque. Editing encrypted negotiation would be a much
larger design. iShareScreen is a replacement client that authenticates and
decodes; it does not demonstrate transparent proxying of Apple's native viewer.
Its source was read as research, not copied into this project or installed/run.

## Concrete next experiment

Test an address-separated local path if the native viewer permits it:

```text
Native viewer          Local relay                    Remote Mac
  TCP ----------------> loopback TCP listener --------> TCP 5900
  UDP <---------------> local-facing UDP sockets
                               |
                        LAN-facing UDP sockets <-----> UDP base + active offsets
```

The local-facing sender must present the server tuple Apple's client expects.
The LAN-facing sender must present the viewer tuple the remote derives from
TCP. Separate loopback addresses are one candidate for avoiding same-address,
same-port collisions. This is untested, and a second loopback address may need
explicit macOS interface configuration; an unprivileged deployment is not yet
established.

Resolve these gates before implementing the production data path:

- Native client binds to a specific IP or wildcard? High Performance accepts a
  loopback control target? Which source address/port does its receiver accept?
- Relay can own LAN UDP ports while Apple owns local media ports without
  `SO_REUSEPORT` races? Loopback delivery survives the unchanged blocked rule?
- Actual receiving executable is allowed by the actual filter? If only `proxyd`
  is allowed, what supported API makes it own/forward the required flows?
- Effective socket delegation changes filter attribution for these flows?
- Video, audio, input, feedback/recovery, display changes and reconnect work
  through the full path with acceptable sustained latency and throughput?

Pending viewer diagnostics address processes, tuples and visible rules, but
cannot alone prove these gates. Read-only socket/header/log observations and a
controlled live experiment remain necessary. Next useful static targets are the
native Screen Sharing client, ScreensharingAgent and matching AVConference
implementation; the two attachments do not contain the entire media stack.

Alpha 3 adds paired before/during captures, per-sample relevant process identities
even without sockets, component and enclosing-bundle firewall queries, the socket
delegation entitlement, loopback/wildcard/non-loopback binding categories, and
default/visible-preference port hints. It does not collect packet headers, logs,
payloads, or effective socket delegation. Independent captures use different
redaction scopes; paired app captures share a scope without exporting its map.

## Provenance and sources

Supplied binaries stay outside the repository. SHA-256:

| Input | Digest |
| --- | --- |
| `avconferenced` | `5f732b6b7996d81fd218f769f3fb8b106915c9254f13ce0847117f9847557f62` |
| `screensharingd.bundle.zip` | `5ea3370bf01bac673b8c210a2810fe463503d368f1ba444a48d4ccfbd9fe3477` |
| Extracted `Contents/MacOS/screensharingd` | `314b46c1219009ee4a57daf5feb6d15b9bdde16a055a99484790911b1d74343d` |

Method: selective ZIP extraction; `plistlib`; strings; Mach-O load commands;
LLVM `llvm-objdump --macho --arch=arm64e --disassemble`; targeted control/data-flow
inspection and CFString resolution. Not a complete decompilation or a
cryptographic validation of the supplied binaries.

1. [Apple: Screen sharing type options, macOS 26](https://support.apple.com/guide/mac-help/screen-sharing-type-options-on-mac-mchl1883115d/26/mac/26).
2. [Apple: TCP and UDP ports used by Apple software products](https://support.apple.com/en-us/103229).
3. Apple device-management revision `09f249a06e7e3289930bf6d05f38fb562f748ebf`:
   [host settings](https://github.com/apple/device-management/blob/09f249a06e7e3289930bf6d05f38fb562f748ebf/declarative/declarations/configurations/screensharing.host.settings.yaml)
   and [connection](https://github.com/apple/device-management/blob/09f249a06e7e3289930bf6d05f38fb562f748ebf/declarative/declarations/configurations/screensharing.connection.yaml).
4. iShareScreen revision `9ab40d3a3151524f954cff9d6239d891197c1705`:
   [experimental memo](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md),
   [negotiation](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/src/isharescreen/proxy/protocol/negotiation.py),
   [session/socket code](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/src/isharescreen/proxy/session.py)
   and [SRTP](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/src/isharescreen/proxy/protocol/srtp.py).
5. [Apple XNU delegated socket handling](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_socket.c):
   `SO_DELEGATED`, `SO_DELEGATED_UUID`, `so_set_effective_pid`, `so_set_effective_uuid`.
