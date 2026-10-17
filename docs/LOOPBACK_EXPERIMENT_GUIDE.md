# Loopback TCP/UDP experiment

This replaces the **test approach**, not the released diagnostic app. The earlier
incoming-only test produced a gray screen and disconnection on a previously
working pair. The host logged missing RTCP feedback. That report did not prove
why feedback was absent or whether Apple's viewer accepted forwarded media.

This candidate forwards TCP and both UDP directions. The viewer connects to
127.0.0.1, and locally forwarded UDP comes from that same address and media port.
Tests with Apple's actual UDP helper exchange datagrams through the real Ruby
relay on all three channels. The first live loopback attempts failed after the
login prompt, with no reported UDP exchange. Two reported an unavailable local
address; the old report did not identify which operation failed. One reported
`incompatibleProtocol` alongside a clean stop acknowledgement. A reproduced
supervisor race could mislabel a clean exit that way and is now fixed.

This revision improves failure evidence, not a proven fix for connection setup.
Schema-3 reports retain final counters and identify TCP acceptance/connection,
read-side closures, the failing operation and a fixed socket-error category.
A changed selected route now has its own `routeChanged` code. Full native High
Performance operation remains unverified.

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
   the exact error and whether it appeared before or after entering credentials.
   The JSON records transport progress without credentials or payloads. Stop
   with Ctrl-C if still running; one failed attempt is sufficient for diagnosis.
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

`nativeTCPAccepted` and `remoteTCPConnected` describe sockets, not authentication.
`nativeTCPReadClosed` and `remoteTCPReadClosed` record read EOF, not why a peer
closed. `failureOperation` and `failureSystemError` contain finite labels, not
raw exception text. A normal `relayExited` result can still accompany a failed
Screen Sharing attempt. The relay does not parse or diagnose authentication.

```sh
./screensharing-proxy-experiment loopback --remote 192.0.2.10 \
  --output new-result.json --duration 60 --listen-port 15900 \
  --remote-control-port 5900 --media-base 5900
```

Replace the documentation address with the host's address. The local TCP port
must match the connection editor; the remote TCP port and media base must match
the host's existing configuration. This command does not change that configuration.
IPv6 and hostnames are not supported by this experiment.
