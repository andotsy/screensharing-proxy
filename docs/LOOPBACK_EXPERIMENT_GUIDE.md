# Loopback TCP/UDP experiment

This replaces the **test approach**, not the released diagnostic app. The earlier
incoming-only test produced a gray screen and disconnection on a previously
working pair. The host logged missing RTCP feedback. That report did not prove
why feedback was absent or whether Apple's viewer accepted forwarded media.

This candidate forwards TCP and both UDP directions. The viewer connects to
127.0.0.1, and locally forwarded UDP comes from that same address and media port.
Tests with Apple's actual UDP helper exchange datagrams through the real Ruby
relay on all three channels. A complete native High Performance session is still
unverified, including whether the viewer negotiates it through localhost.

## One attempt on the controlling Mac

Nothing needs installing on the screen-sharing host. Use an Apple silicon Mac
and its built-in system Ruby; Python is not needed.

1. Disconnect Screen Sharing on the **controlling** Mac and unzip this package.
2. Open `Run.command`. Enter the **host's IPv4 address** at the Terminal prompt.
3. Wait for **Relay ready**. In Apple's Screen Sharing connection editor, use
   **Host: 127.0.0.1**, **Port: 15900**, **Type: High Performance**. Authenticate
   normally with the remote Mac's account. The relay forwards the opaque control
   stream; it does not collect credentials or decode media.
4. Check video, keyboard/mouse and enabled audio. If the connection fails, note
   the error; the JSON counters distinguish forwarding toward Apple from UDP
   feedback forwarded toward the host. Stop with Ctrl-C if still running.
5. The attempt ends on TCP close, Ctrl-C or the ten-minute limit. Its
   `loopback-*.json` report appears beside `Run.command`. Run `Run.command` again
   **before** a new connection attempt; do not reconnect through a stopped relay.

If High Performance is unavailable for the localhost connection, that is a
failed negotiation test; Standard mode is not a successful result. After testing,
disconnect the localhost connection and use your original host connection to
return to normal sharing.

An `addressInUse` result preserves the existing owner and releases partial
reservations. A native service may retain ports after disconnect; do not stop
services or change interfaces, routes, firewall rules or media preferences.
This experiment uses only the existing loopback and routed local addresses.

The executable is ad-hoc signed and not notarized. Do not disable Gatekeeper or
change security settings. The released app's Proxy and Settings tabs stay disabled.

## Report and advanced invocation

Reports are owner-only, never overwrite an existing file, and exclude addresses,
paths, credentials and payloads. `forwardedToNativeDatagrams` and
`forwardedToRemoteDatagrams` count successful UDP socket submissions; byte counts
also include TCP. Neither indicates accepted SRTP or decoded video. The report's
`highPerformanceSession` remains `unverified`; record your observations separately.

```sh
./screensharing-proxy-experiment loopback --remote 192.0.2.10 \
  --output new-result.json --duration 60 --listen-port 15900 \
  --remote-control-port 5900 --media-base 5900
```

Replace the documentation address with the host's address. The local TCP port
must match the connection editor; the remote TCP port and media base must match
the host's existing configuration. This command does not change that configuration.
IPv6 and hostnames are not supported by this experiment.
