# Incoming UDP experiment

**Failed live candidate:** the user tested this on a previously working macOS
26.7.1 setup and repeatedly saw a gray screen followed by a generic stream error.
Ruby received media, but the host logged missing RTCP feedback. Do not repeat this
unchanged test as the next step. See [the loopback experiment](LOOPBACK_EXPERIMENT_GUIDE.md)
for the new, still unproven candidate; the instructions below preserve the earlier
experiment for research.

This is a separate development experiment for Apple silicon Macs. It uses
Apple's `/usr/bin/ruby` and requires no Python installation. It has not yet
demonstrated a full High Performance session. The released app remains
diagnostic-only; this package does not replace it.

Run this package on the Mac **connecting to and controlling** the shared screen.
Nothing from this package needs to run on the screen-sharing host. A working,
unrestricted pair can test transport compatibility before repeating the test
on the affected controlling Mac; success on that pair does not prove the
restricted Mac's firewall permits the same path.

## Run on the controlling Mac

1. Disconnect existing Screen Sharing sessions. The experiment refuses existing
   UDP owners rather than replacing them. A service may retain sockets after
   disconnect; an `addressInUse` result is a failed preflight, not permission to
   terminate that service.
2. Open `Run.command` and enter the remote Mac's numeric IPv4 address. For a
   nondefault existing media base, use the command below instead.
3. Wait for **Relay ready**, then connect Apple's Screen Sharing directly to
   the same remote Mac and explicitly select **High Performance**. Do not
   connect to a loopback address or change the native TCP port for this test.
4. Check changing video, keyboard/mouse control, audio if enabled, and whether
   the session recovers after a pause. Keep the test running for ten minutes
   when it is usable. Record what worked and when any failure occurred.
5. Press Ctrl-C to stop early. The experiment otherwise stops after ten minutes.
   It saves an `incoming-*.json` report beside `Run.command`. Its termination
   removes only its own sockets; reconnect normally after the experiment ends.

Run a new experiment before testing reconnect: do not reuse a session whose
native sockets were created before the relay reserved its ports.

The executable is ad-hoc signed, like the development app, and is not notarized.
Do not disable Gatekeeper or change system security settings for the experiment.

For an existing nondefault UDP media base or shorter bounded test:

```sh
./screensharing-proxy-experiment incoming --remote 192.0.2.10 \
  --media-base 6200 --duration 60 --output new-result.json
```

Replace the documentation address with the remote Mac's address. The media base
must match the existing native configuration; this command does not configure
Apple's ports. IPv6 and hostnames are not supported by this experiment.

## Interpret the result

- `relayReady` means three connected UDP sockets were reserved. It does not
  mean the firewall permits receipt or that a native session works.
- `receivedDatagrams` counts datagrams Ruby read from the fixed remote peer.
- `submittedDatagrams` counts successful submissions to the local UDP stack.
  It does not confirm delivery to AVConference, authentication or video decoding.
- Native TCP and outbound feedback remain direct and are not counted here.
- `highPerformanceSession` stays `unverified`; supply observations separately.
- `addressInUse` preserves the existing owner and cleans up partial reservations.

The report has owner-only permissions and contains OS version, duration, counters,
stop reason and structured failure codes. It contains no addresses, paths,
credentials or media bytes. Existing report files are never overwritten.

For a useful result, include whether High Performance actually displayed video,
whether keyboard/mouse and enabled audio worked, both Macs' OS builds, and the
result of a fresh reconnect. Run the existing app's diagnostics separately if
socket ownership or firewall evidence is needed. No packet capture is required.
