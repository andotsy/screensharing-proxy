#!/usr/bin/env python3
"""Real socket tests for the Ruby adapter. No firewall/interface changes.

The full fixture uses 127.0.0.1 through .5. Linux routes these by default;
macOS requires preconfigured aliases. --portable checks startup on either OS.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import queue
import random
import socket
import subprocess
import threading
import time
import unittest
import uuid

PARSER = argparse.ArgumentParser()
PARSER.add_argument('--ruby', default='/usr/bin/ruby')
PARSER.add_argument('--script', type=Path, default=Path(__file__).resolve().parents[1] / 'Sources/ProxyCore/Resources/relay.rb')
PARSER.add_argument('--portable', action='store_true')
OPTIONS, REST = PARSER.parse_known_args()


class Child:
    def __init__(self, config):
        self.process = subprocess.Popen(
            [OPTIONS.ruby, '--disable-gems', str(OPTIONS.script)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
        self.events = queue.Queue(maxsize=128)
        self.reader = threading.Thread(target=self.read_events, daemon=True)
        self.reader.start()
        data = config if isinstance(config, bytes) else json.dumps(config).encode() + b'\n'
        self.process.stdin.write(data)
        self.process.stdin.flush()

    def read_events(self):
        for line in self.process.stdout:
            try:
                self.events.put(json.loads(line), timeout=3)
            except (ValueError, queue.Full):
                return

    def event(self, name, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            event = self.events.get(timeout=max(0.01, deadline - time.monotonic()))
            if name in event['event']:
                return event['event'][name]
            if 'failed' in event['event']:
                raise AssertionError(event)
        raise AssertionError('Expected event: ' + name)

    def close(self):
        if not self.process.stdin.closed:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=2)
            raise AssertionError('Relay ignored control-pipe EOF')
        self.reader.join(timeout=2)
        self.process.stdout.close()
        stderr = self.process.stderr.read()
        self.process.stderr.close()
        if stderr:
            raise AssertionError('Relay wrote unexpected stderr')


def stream_socket(address, port=0):
    s = socket.socket()
    s.settimeout(3)
    s.bind((address, port))
    s.listen(1)
    return s


class StartupTests(unittest.TestCase):
    def test_invalid_configuration_is_structured_and_private(self):
        child = Child(b'{"private":"not a valid configuration"}\n')
        try:
            self.assertEqual(child.event('failed')['code'], 'invalidConfiguration')
            self.assertEqual(child.process.wait(timeout=3), 1)
        finally:
            child.close()

    def test_oversized_configuration_is_rejected(self):
        child = Child(b' ' * 8193 + b'\n')
        try:
            self.assertEqual(child.event('failed')['code'], 'invalidConfiguration')
        finally:
            child.close()


@unittest.skipIf(OPTIONS.portable, 'Full fixture needs distinct local addresses')
class ForwardingTests(unittest.TestCase):
    def setUp(self):
        self.owned = []
        self.child = None
        self.remote = self.own(stream_socket('127.0.0.4'))
        reservation = stream_socket('127.0.0.2')
        listener_port = reservation.getsockname()[1]
        reservation.close()
        for attempt in range(30):
            base = random.randrange(20_000, 50_000)
            pending = []
            try:
                for address in ['127.0.0.1', '127.0.0.4']:
                    for offset in range(3):
                        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        pending.append(s)
                        s.settimeout(2)
                        s.bind((address, base + offset))
                break
            except OSError:
                for s in pending:
                    s.close()
        else:
            self.fail('No fixture port range available')
        self.owned.extend(pending)
        self.native_udp, self.remote_udp = pending[:3], pending[3:]
        self.config = {
            'version': 1, 'sessionID': str(uuid.uuid4()),
            'remoteAddress': '127.0.0.4', 'externalAddress': '127.0.0.3',
            'remoteControlPort': self.remote.getsockname()[1],
            'listenerAddress': '127.0.0.2', 'nativeAddress': '127.0.0.1',
            'listenerPort': listener_port, 'mediaBase': base}

    def own(self, s):
        self.owned.append(s)
        return s

    def tearDown(self):
        if self.child:
            self.child.close()
        for s in self.owned:
            s.close()

    def start(self):
        self.child = Child(self.config)
        self.child.event('ready')

    def connect(self, source='127.0.0.1'):
        client = self.own(socket.socket())
        client.settimeout(5)
        client.bind((source, 0))
        client.connect(('127.0.0.2', self.config['listenerPort']))
        return client

    def connected_pair(self):
        self.start()
        client = self.connect()
        server, peer = self.remote.accept()
        self.own(server)
        server.settimeout(5)
        self.assertEqual(peer[0], '127.0.0.3')
        server.sendall(b'RFB 003.889\n')
        self.assertEqual(client.recv(12), b'RFB 003.889\n')
        return client, server

    def test_full_duplex_udp_source_ports_and_empty_maximum_datagrams(self):
        self.connected_pair()
        for offset in range(3):
            port = self.config['mediaBase'] + offset
            for length in [0, 1, 1400, 65_507]:
                payload = os.urandom(length)
                self.native_udp[offset].sendto(payload, ('127.0.0.2', port))
                actual, source = self.remote_udp[offset].recvfrom(65_535)
                self.assertEqual((actual, source), (payload, ('127.0.0.3', port)))
                self.remote_udp[offset].sendto(payload, source)
                actual, source = self.native_udp[offset].recvfrom(65_535)
                self.assertEqual((actual, source), (payload, ('127.0.0.2', port)))
        media = self.child.event('media')
        self.assertEqual(media['sentDatagrams'], 12)
        self.assertEqual(media['receivedDatagrams'], 12)
        self.assertEqual(media['droppedDatagrams'], 0)

    def test_tcp_backpressure_and_half_close(self):
        client, server = self.connected_pair()
        outgoing, response = os.urandom(3_000_000), os.urandom(2_000_000)

        def remote_work():
            data = bytearray()
            time.sleep(0.15)  # Let the relay's bounded write queue fill.
            while True:
                part = server.recv(65_536)
                if not part:
                    break
                data.extend(part)
            self.assertEqual(bytes(data), outgoing)
            server.sendall(response)
            server.shutdown(socket.SHUT_WR)

        with concurrent.futures.ThreadPoolExecutor(1) as executor:
            future = executor.submit(remote_work)
            client.sendall(outgoing)
            client.shutdown(socket.SHUT_WR)
            received = bytearray()
            while True:
                part = client.recv(65_536)
                if not part:
                    break
                received.extend(part)
            self.assertEqual(bytes(received), response)
            future.result(timeout=5)
        self.child.event('stopped')
        self.assertEqual(self.child.process.wait(timeout=3), 0)

    def test_unexpected_udp_sender_is_not_forwarded(self):
        self.connected_pair()
        intruder = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        intruder.bind(('127.0.0.5', self.config['mediaBase']))
        intruder.sendto(b'unexpected sender', ('127.0.0.3', self.config['mediaBase']))
        self.native_udp[0].settimeout(0.2)
        with self.assertRaises(socket.timeout):
            self.native_udp[0].recvfrom(1024)
        self.remote_udp[0].sendto(b'expected sender', ('127.0.0.3', self.config['mediaBase']))
        self.assertEqual(self.native_udp[0].recvfrom(1024)[0], b'expected sender')

    def test_bind_conflict_fails_and_releases_partially_prepared_sockets(self):
        occupied = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        occupied.bind(('127.0.0.2', self.config['mediaBase'] + 1))
        self.child = Child(self.config)
        self.assertEqual(self.child.event('failed')['code'], 'addressInUse')
        self.child.process.wait(timeout=3)
        probe = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        probe.bind(('127.0.0.2', self.config['mediaBase']))

    def test_unavailable_local_address_is_reported(self):
        self.config['externalAddress'] = '192.0.2.222'
        self.child = Child(self.config)
        self.assertEqual(self.child.event('failed')['code'], 'localAddressUnavailable')

    def test_wrong_native_source_fails_closed(self):
        self.start()
        self.connect('127.0.0.5')
        self.assertEqual(self.child.event('failed')['code'], 'nativeSourceMismatch')

    def test_parent_pipe_eof_stops_a_live_session_and_releases_ports(self):
        client, server = self.connected_pair()
        self.child.process.stdin.close()
        self.child.event('stopped')
        self.assertEqual(self.child.process.wait(timeout=3), 0)
        self.assertEqual(client.recv(1), b'')
        self.assertEqual(server.recv(1), b'')
        for address in ['127.0.0.2', '127.0.0.3']:
            for offset in range(3):
                probe = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
                probe.bind((address, self.config['mediaBase'] + offset))


if __name__ == '__main__':
    unittest.main(argv=['test-ruby-relay.py'] + REST)
