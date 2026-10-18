#!/usr/bin/env python3
"""Exercise the copied native UI's discovery, sign-in, reconnect and desktop.

Uses an isolated bundle ID, dummy credentials, a synthetic RFB 3.3 peer and
owned high ports. Never authenticates to an actual sharing host or logs payloads.
The native TCP/UDP self-test separately checks all three actual UDP helpers.
"""
import argparse
import concurrent.futures
import contextlib
import json
from pathlib import Path
import plistlib
import random
import select
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path, help='A created Screen Sharing Rubyfied.app')
    parser.add_argument('--transport-source', type=Path, default=ROOT / 'Sources/Rubied/RubiedTransport.m')
    options = parser.parse_args()
    stop = threading.Event()
    counts = {'accepted': 0, 'authenticated': 0, 'frames': 0}
    with contextlib.ExitStack() as stack:
        temporary = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix='rubyfied-login-')))
        app = temporary / 'Screen Sharing Rubyfied.app'
        shutil.copytree(options.app.resolve(), app, symlinks=True)
        plist = app / 'Contents/Info.plist'
        info = plistlib.loads(plist.read_bytes())
        identifier = 'com.andotsy.rubyfied-login-fixture.' + uuid.uuid4().hex
        info['CFBundleIdentifier'] = identifier
        plist.write_bytes(plistlib.dumps(info))
        route = stack.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        route.connect(('192.0.2.1', 9))  # Address selection only; sends nothing.
        address = route.getsockname()[0]
        listener = stack.enter_context(socket.socket())
        listener.bind((address, 0))
        listener.listen(3)
        listener.settimeout(.1)
        remote_port = listener.getsockname()[1]
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            listener_port = reservation.getsockname()[1]
        for attempt in range(100):
            media_base = random.randrange(20000, 49000)
            try:
                with contextlib.ExitStack() as reservations:
                    for host in (address, '127.0.0.1'):
                        for offset in range(6):
                            sock = reservations.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
                            sock.bind((host, media_base + offset))
                break
            except OSError:
                if attempt == 99:
                    raise
        source = options.transport_source.read_text()
        identity = '@"com.andotsy.screensharing-rubyfied"'
        report_directory = '[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Screen Sharing Rubyfied"]'
        assert source.count(identity) == source.count(report_directory) == 1
        source = source.replace(identity, '@' + json.dumps(identifier))
        source = source.replace(report_directory, '@' + json.dumps(str(temporary / 'reports')))
        definitions = '\n'.join([
            '#define FIXTURE_MEDIA_BASE ' + str(media_base),
            '#define FIXTURE_LISTENER_PORT ' + str(listener_port),
            '#define FIXTURE_URL @' + json.dumps(f'vnc://{address}:{remote_port}'),
        ])
        fixture = temporary / 'fixture.m'
        fixture.write_text(definitions + '\n' + source + '\n' +
                           (ROOT / 'Scripts/probe-rubyfied-login.m').read_text())
        library = app / 'Contents/Frameworks/RubiedTransport.dylib'
        subprocess.run(['clang', '-arch', 'arm64e', '-dynamiclib', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                        '-framework', 'Foundation', '-framework', 'AppKit', str(fixture), '-o', str(library)],
                       check=True, timeout=60)
        for target in (library, app):
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(target)],
                           check=True, capture_output=True, timeout=15)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True, timeout=15)

        def exact(peer, count):
            data = bytearray()
            while len(data) < count and not stop.is_set():
                part = peer.recv(count - len(data))
                if not part:
                    raise EOFError()
                data.extend(part)
            if len(data) != count:
                raise EOFError()
            return bytes(data)

        def serve(peer):
            with peer:
                peer.settimeout(5)
                try:
                    peer.sendall(b'RFB 003.003\n')
                    assert exact(peer, 12) == b'RFB 003.003\n'
                    peer.sendall(struct.pack('>I', 2) + bytes(16))
                    exact(peer, 16)  # Discard the synthetic challenge response.
                    counts['authenticated'] += 1
                    peer.sendall(struct.pack('>I', 0))
                    exact(peer, 1)
                    pixel_format = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
                    name = b'Rubyfied synthetic login fixture'
                    peer.sendall(struct.pack('>HH', 64, 64) + pixel_format + struct.pack('>I', len(name)) + name)
                    while not stop.is_set():
                        if not select.select([peer], [], [], .1)[0]:
                            continue
                        kind = exact(peer, 1)[0]
                        if kind == 0:
                            pixel_format = exact(peer, 19)[3:]
                        elif kind == 2:
                            count = struct.unpack('>H', exact(peer, 3)[1:])[0]
                            assert count <= 4096
                            exact(peer, count * 4)
                        elif kind == 3:
                            exact(peer, 9)
                            bpp, _, big, colour, r, g, b, rs, gs, bs = struct.unpack('>BBBBHHHBBBxxx', pixel_format)
                            assert bpp in (8, 16, 32) and colour
                            pixel = ((r // 3) << rs) | ((g // 2) << gs) | ((b // 2) << bs)
                            peer.sendall(struct.pack('>BBHHHHHi', 0, 0, 1, 0, 0, 64, 64, 0) +
                                         pixel.to_bytes(bpp // 8, 'big' if big else 'little') * (64 * 64))
                            counts['frames'] += 1
                            stop.wait(1 / 30)
                        elif kind == 4:
                            exact(peer, 7)
                        elif kind == 5:
                            exact(peer, 5)
                        elif kind == 6:
                            length = struct.unpack('>I', exact(peer, 7)[3:])[0]
                            assert length <= 65536
                            exact(peer, length)  # Never retain clipboard data.
                        else:
                            return
                except (OSError, EOFError):
                    pass

        def accept():
            with concurrent.futures.ThreadPoolExecutor(3) as peers:
                futures = []
                while not stop.is_set():
                    try:
                        peer, _ = listener.accept()
                    except socket.timeout:
                        continue
                    counts['accepted'] += 1
                    assert counts['accepted'] <= 6
                    futures.append(peers.submit(serve, peer))
                for future in futures:
                    future.result(timeout=6)

        with concurrent.futures.ThreadPoolExecutor(1) as executor:
            server = executor.submit(accept)
            process = subprocess.Popen([str(app / 'Contents/MacOS/ScreenSharingNative'), '-AppleLanguages', '(en)'],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            timed_out = False
            try:
                _, stderr = process.communicate(timeout=20)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.terminate()
                try:
                    _, stderr = process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    _, stderr = process.communicate(timeout=3)
            finally:
                stop.set()
                server.result(timeout=8)
            markers = '\n'.join(line for line in stderr.splitlines() if line.startswith('RUBIED_LOGIN_FIXTURE'))
            print(markers)
            print(json.dumps(counts))
            assert not timed_out, 'Native login did not reach a desktop before the deadline.'
            assert process.returncode == 0, process.returncode
            assert 'loginPrompt=1' in markers and 'desktop=1 submitted=1' in markers
            assert counts['accepted'] >= 2 and counts['authenticated'] >= 1 and counts['frames'] >= 1
            report = json.loads((temporary / 'reports/latest-session.json').read_text())
            assert 'ready' in report and 'failed' not in report and 'adapterFailure' not in report
            assert report['controlConnections']['connected'] >= 2
        print('Native discovery, sign-in, reconnect and synthetic desktop passed.')


if __name__ == '__main__':
    main()
