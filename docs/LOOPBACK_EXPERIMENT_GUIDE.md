# Loopback TCP/UDP experiment

## Current test: local TCP port 5900

This local **port diagnostics v6** build identifies the exact failed socket
operation and affected port. The previous port-5900 package failed even after
the user fully quit Screen Sharing and visible port checks printed nothing.
This build improves diagnosis; it does not yet fix that unidentified conflict.
The first Terminal line must include **port diagnostics v6**.

The previous `127.0.0.1:15900` target triggers a native viewer check that disables
High Performance. On macOS 26.7.1, Apple's own address classifier identifies a
local address on a nondefault TCP port as a tunnel. The viewer marks it as unable
to use Pro mode. This explains a concrete defect in the old test design; its
working TCP video/input and zero UDP do not prove a complete High Performance
relay. See [the native classification evidence](NATIVE_LOCAL_TARGET_FINDINGS.md).

`Run.command` now explicitly uses **127.0.0.1:5900**. This avoids that particular
nondefault-port classification. It is still a test: Apple's viewer also checks
whether this Mac already has local Screen Sharing enabled, and port 5900 may be
occupied. If reservation fails or Apple refuses to connect to the same Mac,
stop and report that result. Do not disable services or change configuration.
No full High Performance result is claimed until real video, input and UDP
traffic through this corrected target have been observed.

The following history describes the earlier experiments.

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

The next schema-3 report identified `routeChanged` at `routeCheck`, before any
native TCP accept. The relay incorrectly stopped whenever a fresh UDP socket
selected a different source address, even if its existing bound sockets remained
usable. This revision keeps those sockets pinned and checks that their address
is still assigned to an up interface. It stops with `localAddressUnavailable`
at `sourceCheck` if that address is gone or down. It does not rebind sockets or
change network configuration. The report cannot explain why the fresh socket
selected another source on the test Mac.

`Run.command` now opens Apple's Screen Sharing URL handler after Relay ready.
The native launch path reaches a local listener without editing a saved entry.
After a full quit of the viewer, the next live attempt reached TCP but ended
after 17 bytes toward the viewer and 12 toward the host. Local testing with the
actual Apple viewer exposed another defect: it closes an initial discovery TCP
connection, shows the login prompt, then reconnects to sign in. The relay used
to close its listener on the first accept and exit when that first pair closed.

This revision keeps the listener and media reservations through sequential TCP
connections. A native test now reaches a synthetic desktop through both
connections using the real Ruby relay. It tests the login connection lifecycle;
full native High Performance operation remains unverified.

## One attempt on the controlling Mac

Nothing needs installing on the screen-sharing host. Use an Apple silicon Mac
and its built-in system Ruby; Python is not needed.

1. Fully quit Screen Sharing with **Command-Q** on the **controlling** Mac, then
   unzip this package into a new folder.
2. Open `Run.command`. Enter the **host's IPv4 address** at the Terminal prompt.
3. Wait for **Relay ready**. Screen Sharing opens automatically to
   **127.0.0.1:5900**. Authenticate with the **remote Mac's account**, and choose
   **High Performance** when offered. Leave your saved connection out of this
   attempt. The relay forwards the opaque control stream; it does not collect
   credentials or decode media.
4. Check video, keyboard/mouse and enabled audio. In the active session's View
   menu, note whether **Adaptive Quality** and **Full Quality** are selectable;
   Apple documents these as Standard-only controls. Check the relayed session,
   not the separate direct connection. If the connection fails, note
   the exact error and whether it appeared before or after entering credentials.
   The JSON records transport progress without credentials or payloads. Stop
   with Ctrl-C if still running; one failed attempt is sufficient for diagnosis.
5. Press **Ctrl-C** in Terminal to save `loopback-*.json` beside `Run.command`.
   The relay stays running through login reconnections. It also stops at the
   ten-minute limit, or after two minutes waiting for a TCP connection. Restart
   `Run.command` before connecting again if the relay has already stopped.

If High Performance is unavailable for the localhost connection, that is a
failed negotiation test; Standard mode is not a successful result. After testing,
disconnect the localhost connection and use your original host connection to
return to normal sharing.

If the automatic launch cannot open Screen Sharing, use its **New Connection**
button (or Command-N), enter **127.0.0.1:5900** in the single **Connect To** field,
and click Connect while the relay is running. The address includes the port.
The edited saved-entry Connect action previously produced no accepted TCP
connection; its cause has not been established.

An `addressInUse` result preserves the existing owner and releases partial
reservations. A native service may retain ports after disconnect; do not stop
services or change interfaces, routes, firewall rules or media preferences.
Fully quitting the Screen Sharing app released the direct session's visible
media sockets, but the relay still failed in the user's repeat attempt. An empty
port listing does not establish that every required port is available.
The older `socketReservation` failure does not identify TCP versus UDP.
This build uses report schema 6 and names the bind/connect operation and
`failurePort`; the earlier CI-binary port-5900 package remains schema 5.
This experiment uses only the existing loopback and routed local addresses.

The executable is ad-hoc signed and not notarized. Do not disable Gatekeeper or
change security settings. The released app's Proxy and Settings tabs stay disabled.

## Report and advanced invocation

Reports are owner-only, never overwrite an existing file, and exclude addresses,
paths, credentials and payloads. `forwardedToNativeDatagrams` and
`forwardedToRemoteDatagrams` count successful UDP socket submissions; byte counts
also include TCP. Neither indicates accepted SRTP or decoded video. The report's
`highPerformanceSession` remains `unverified`; record your observations separately.

Schema 5 retains `nativeTCPConnectionCount`, `remoteTCPConnectionCount` and
`completedTCPConnectionCount`, cumulative across this attempt. Completed counts retired pairs, including reset/closed peers, not successful
sessions. `lastTCPClosure` distinguishes EOF, peer closure and reset;
`discardedTCPBytes` counts queued bytes abandoned after a peer closes.
The four TCP booleans describe the current pair, or the last completed pair
while waiting for another connection. They describe sockets, not authentication;
read EOF does not explain why a peer closed.
`failureOperation` and `failureSystemError` contain finite labels, not
raw exception text. Older reports may contain `routeChanged` / `routeCheck`;
this revision no longer compares fresh route selections. A normal `relayExited`
result can still accompany a failed
Screen Sharing attempt. The relay does not parse or diagnose authentication.

```sh
./screensharing-proxy-experiment loopback --remote 192.0.2.10 \
  --output new-result.json --duration 60 --listen-port 5900 \
  --remote-control-port 5900 --media-base 5900 --open-viewer
```

Replace the documentation address with the host's address. The local TCP port
must match the connection editor; the remote TCP port and media base must match
the host's existing configuration. This command does not change that configuration.
Pass `--listen-port 5900` explicitly: the older executable's command-line default
remains 15900 for compatibility with existing fixtures. Other local TCP ports
trigger Apple's tunnel classification and are unsuitable for this media test.
IPv6 and hostnames are not supported by this experiment.
Omit `--open-viewer` to start only the relay and connect manually after ready.
