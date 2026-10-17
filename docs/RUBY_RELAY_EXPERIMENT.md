# Ruby relay experiment

Status: the transport implementation passes local tests, but the proposed native
connection path is **blocked under the no-interface-change constraint**. It is
not enabled in the application and is not a functioning High Performance proxy.

A different incoming-only candidate now passes macOS UDP delivery probes,
including the actual native socket-creation helper. That candidate is described
below; it is not yet implemented by `Resources/relay.rb`, and AVConference/live
High Performance behavior remains untested.

The user selected system Ruby after the restricted Mac listed /usr/bin/ruby as
allowed and the Python runtime as blocked. This is an experimental data path;
only a live High Performance session can establish that Apple accepts it.

## Concrete path

- Native Screen Sharing connects to 127.0.0.2:15900. Its local control address
  must be 127.0.0.1; reject a different address rather than guessing UDP routing.
- Ruby binds local UDP 127.0.0.2:5900–5902, connected to 127.0.0.1 on the same
  ports. The native viewer is expected to own 127.0.0.1:5900–5902.
- Ruby derives its external source address from routing to the remote IPv4
  address. Bind outgoing control TCP and external UDP to that same source IP.
- External UDP is bound to 5900–5902 and connected to the remote on those ports.
  Prepare all six UDP sockets before opening the native connection. Fail closed
  on a bind conflict; do not use SO_REUSEPORT to race Apple's sockets.
- Forward TCP opaquely with bounded backpressure and half-close. Forward UDP
  opaquely with preserved datagram boundaries and fixed peer addresses. No
  media-over-TCP fallback, payload logs, credential handling or wire rewriting.
- One local connection per process. Close listeners after acceptance. Stop all
  sockets on EOF, app exit, explicit stop, failed startup or connection deadline.

## Loopback address prerequisite (interface changes declined)

macOS normally has 127.0.0.1 but may not permit binding 127.0.0.2 without adding
an alias to lo0. This experiment assumes separate addresses because the native
client and relay use the same UDP port numbers. Preflight can try binding the address
without changing configuration. The relay must report a missing address rather
than modify interfaces itself.

The user explicitly declined adding/removing interface addresses. Do not add an
alias, change routes/firewall rules, or prompt again for this operation. The
commands below document the rejected approach, not setup instructions:

```
/sbin/ifconfig lo0 alias 127.0.0.2 netmask 255.255.255.255
```

This needs macOS administrator authorization. It adds one local address; it
does not change a firewall rule or a default route. Do not alter an existing
127.0.0.2 address. If this app added it, cleanup uses:

```
/sbin/ifconfig lo0 -alias 127.0.0.2
```

No provisioning is authorized or executed. Test whether macOS can bind and route
the separate addresses without configuration; do not infer this from Linux.
If loopback High Performance is rejected, or native wildcard UDP conflicts,
stop this hypothesis and inspect the observed bindings. A remote companion does
not by itself fix either local problem.

## Acceptance

Local integration tests must cover real bidirectional TCP and UDP on all three
ports, source tuples, arbitrary binary data, half-close, backpressure, unexpected
senders, bind failures, cancellation and process cleanup. macOS CI must test
system Ruby 2.6, packaged resources and native lifecycle. Neither substitutes for
the restricted Mac: require High Performance video, full keyboard/mouse control,
audio when enabled, ten minutes of changing video and reconnect with the original
firewall rules unchanged. Runtime receipt and Apple local delivery remain gates.

## Results

- Ruby 2.6.10 on Linux: nine real-socket/startup tests pass, including all three
  media ports, empty and maximum IPv4 UDP datagrams, exact source tuples, binary
  TCP transfers larger than the bounded queues, half-close, unexpected UDP
  senders, partial bind failure, parent-pipe EOF and socket cleanup.
- Swift: 63 tests pass, including the new interactive process supervisor,
  cancellation escalation, private configuration over stdin, protocol rejection
  and media counters. The release build passes with warnings treated as errors.
- [macOS experiment run 39066437389](https://github.com/andotsy/screensharing-proxy/actions/runs/39066437389):
  Apple's Ruby 2.6.10 passes startup checks and the Swift suite. The full
  distinct-address traffic fixture is intentionally skipped there; it must not
  silently configure aliases just to make the tests pass.
- The macOS runner binds/connects 127.0.0.1, ::1 and fe80::1%lo0, but each TCP
  client's source address is identical to its destination. Binding 127.0.0.2,
  127.0.0.3 or 127.0.0.4 returns EADDRNOTAVAIL. No interface configuration was
  changed. The existing loopback addresses do not provide the separated tuples
  required by this experiment. This is CI-host evidence, not a measurement of
  every possible address on the user's Mac.
- [Native validation at b2519df](https://github.com/andotsy/screensharing-proxy/actions/runs/39067471379)
  passes the 63 Swift tests, system Ruby startup checks, app build/signature,
  native smoke test and embedded relay resource check. The accompanying
  [normal CI](https://github.com/andotsy/screensharing-proxy/actions/runs/39067474822)
  also passes, including DMG assembly. These checks do not run a live session.

The connection editor's custom Port is the TCP control destination, so using
a custom relay TCP listener is supported. It does not settle media port
selection. Static inspection of the macOS 26.6.2 viewer framework finds a
wildcard UDP bind to the supplied media port followed by a connect to the same
port on the configured media peer. It requests SO_REUSEADDR and SO_REUSEPORT;
the relay currently omits both. Socket coexistence therefore needs a native
experiment even on a host with suitable distinct addresses. See
[the detailed evidence and limits](HIGH_PERFORMANCE_RESEARCH.md#the-connection-editors-port-field-and-native-udp-sockets).

A remote companion can separate its own native connection by binding its TCP
source to one existing address and connecting to another existing address.
That does not establish how to make Apple's viewer choose distinct local
addresses: the viewer's TCP connect remains under Apple's control. Do not
implement a companion as if it automatically removes the viewer-side collision.

Do not enable a Connect button that is known to require the rejected setup, or
publish a working-proxy claim from these transport tests. A next design must
demonstrate native viewer media binding/port selection under unchanged interface
configuration, or establish a separately authorized packet-delivery mechanism.
Neither encrypted negotiation rewriting nor privileged packet injection has
been implemented or established by this experiment.

## Socket reuse and a different incoming path

`Scripts/probe-udp-reuse.rb` exercises 16 combinations of binding order, relay
reuse options, wildcard/specific binding and connected/unconnected relay sockets
on the existing loopback address. It uses ephemeral ports, bounded synthetic
packets and owned sockets; it changes no interface, route or firewall settings.
A separate-port control checks that the fixture observes both directions.

On macOS 26.6.2 (25G83), system Ruby 2.6.10, five same-port cases fail to bind;
eleven permit traffic but deliver both senders' packets to one socket. None
exchange packets in both directions. The four-packet-per-direction control
passes. Linux differs in duplicate-connect behavior, so Linux outcomes cannot
substitute for Darwin. See [run 39068526125, evidence job](https://github.com/andotsy/screensharing-proxy/actions/runs/39068526125/job/117501103435).

Darwin's duplicate connected tuple produces EADDRINUSE. When the native pattern
opens second, its bind can succeed and its failed connect leaves it wildcard
and unconnected. The inspected Apple helper deliberately returns that descriptor.
This suggests a different design, without a loopback TCP proxy:

```text
Native Screen Sharing -- normal TCP control --> remote Mac
Remote media ---------> Ruby's connected UDP socket on the viewer's LAN IP
                        Ruby forwards unchanged bytes from a separate local socket
                        --> native unconnected UDP socket
Native feedback ------> remote Mac, directly, with an explicit UDP destination
```

Ruby must bind/connect the exact remote media tuples before the native client
opens them. It can then receive the external packets on its connected sockets.
Locally forwarded packets have a different source tuple, so they can reach the
native unconnected socket instead of returning to Ruby. This is normal UDP
delivery through owned sockets, not raw-packet injection. No interface alias,
packet-filter rule, service restart or control-stream rewriting is involved.

The follow-up [Ruby model](https://github.com/andotsy/screensharing-proxy/actions/runs/39068822986/job/117501981543)
demonstrates remote-to-relay receipt, local delivery to the native-pattern socket,
and direct feedback to the remote fixture with the expected source port. Sending
feedback without a destination fails with EDESTADDRREQ. For this bounded
one-machine model, different ephemeral loopback ports stand in for different
Mac addresses; it does not execute Apple's media implementation.

`Scripts/probe-native-udp.m` then invokes the **actual** inspected
`+[SSSession udpSocketWithAVCMediaStreamConfig:port:]` method with a minimal
configuration fixture. It first reserves a connected tuple using the route's
existing source address and a documentation-only remote IP. UDP connect selects
the route without sending data to that IP. Local and remote media ports are
equal, as in the native method. Only a random local test packet is transmitted.
The [native-helper evidence job](https://github.com/andotsy/screensharing-proxy/actions/runs/39069041292/job/117502634477)
reports:

- A valid native descriptor at the expected media port.
- Wildcard local binding and ENOTCONN from getpeername.
- Exact local payload/source delivery to the native socket.
- No local packet delivered to the reserved connected socket.

The helper runs in the fixture process, not Apple's viewer/avconferenced
processes. It proves this method and kernel can provide the candidate's receive
path on that CI build; it does not prove firewall attribution or SRTP processing.

Before treating this as a usable relay, establish all of the following:

1. AVConference preserves the unconnected socket and accepts authenticated media
   delivered from the local forwarding source, rather than requiring the remote
   source tuple in user space.
2. Its outbound RTP/RTCP path supplies the remote destination. A plain send on
   this unconnected descriptor cannot supply feedback.
3. The restricted OS build behaves compatibly, allows external receipt by the
   selected Ruby executable, and permits the local delivery under its existing
   filter rules. Descriptor ownership alone does not settle effective identity.
4. Startup ordering is safe: detect an existing conflicting session, fail instead
   of taking it over, and clean up only app-owned sockets. Keep TCP direct and
   match the real viewer source address, remote address and configured media base.
5. The resulting session has High Performance video, audio when enabled, input,
   feedback/recovery, reconnect and bounded sustained resource use.

This candidate refines the design rather than proving every earlier conflict
assumption false. The separate-address relay remains disabled; do not silently
relabel it as the new incoming-only path or claim the model opened a full session.
