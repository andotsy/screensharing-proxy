# Ruby relay experiment

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
an alias to lo0. Separate addresses are needed because the native client and
relay use the same UDP port numbers. Preflight can try binding the address
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
