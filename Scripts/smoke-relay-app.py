"""Exercise the packaged native proxy with real owned Ruby sockets, no remote send."""
import json
from pathlib import Path
import random
import socket
import stat
import subprocess
import sys
import tempfile

bundle = Path(sys.argv[1]).resolve()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
    route.connect(('192.0.2.1', 9))
    address = route.getsockname()[0]

def available(listener, base):
    sockets = []
    try:
        for local in (address, '127.0.0.1'):
            for offset in range(3):
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sockets.append(sock); sock.bind((local, base + offset))
        sock = socket.socket(); sockets.append(sock)
        sock.bind(('127.0.0.1', listener)); sock.listen(1)
    finally:
        for sock in sockets: sock.close()

for _ in range(50):
    listener, base = random.randrange(20000, 30000), random.randrange(35000, 50000)
    try: available(listener, base); break
    except OSError: pass
else: raise RuntimeError('No free fixture ports')
with tempfile.TemporaryDirectory(prefix='ssp-native-relay-') as temporary:
    report = Path(temporary) / 'session.json'
    result = subprocess.run([str(bundle/'Contents/MacOS/ScreenSharingProxy'), '--relay-smoke-test',
                             str(report), str(listener), str(base)], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stderr
    assert 'Native proxy readiness, stop, report and child cleanup passed.' in result.stdout
    data = report.read_text(); parsed = json.loads(data)
    assert address not in data and temporary not in data and '192.0.2.1' not in data
    assert parsed['relayStopAcknowledged'] and parsed['termination'] == 'stopped'
    assert parsed['nativeTCPConnectionCount'] == 0 and parsed['forwardedToNativeBytes'] == 0
    assert parsed['highPerformanceSession'] == 'unverified'
    assert stat.S_IMODE(report.stat().st_mode) == 0o600
available(listener, base)
print('Packaged Proxy view, real relay readiness, private session report and port release passed.')
