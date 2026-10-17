#!/usr/bin/env python3
"""Darwin relay fixtures using existing addresses and synthetic local traffic."""
import argparse
import concurrent.futures
import errno
import json
import os
from pathlib import Path
import random
import runpy
import select
import socket
import subprocess
import sys
import tempfile
import unittest
import uuid

PARSER = argparse.ArgumentParser()
PARSER.add_argument('--native-helper', type=Path)
OPTIONS, REST = PARSER.parse_known_args()
SUPPORT = runpy.run_path(str(Path(__file__).with_name('test-ruby-relay.py')))
SUPPORT['OPTIONS'].script = Path(__file__).resolve().parents[1] / 'Sources/ProxyCore/Resources/loopback-relay.rb'
Child = SUPPORT['Child']


@unittest.skipUnless(sys.platform == 'darwin', 'Requires Darwin duplicate-connect semantics')
class LoopbackTests(unittest.TestCase):
    def setUp(self):
        self.owned, self.children = [], []
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
            route.connect(('192.0.2.1', 9))  # Select an existing address; no send.
            self.address = route.getsockname()[0]
        self.remote = self.tcp_listener(self.address)
        listener = self.tcp_listener('127.0.0.1')
        self.listener_port = listener.getsockname()[1]
        listener.close()
        self.remote_base, self.media = self.reserve_three([self.address])
        self.base, reservations = self.reserve_three([self.address, '127.0.0.1'])
        for sock in reservations:
            sock.close()
        self.config = {'version': 1, 'sessionID': str(uuid.uuid4()), 'remoteAddress': self.address,
                       'remoteControlPort': self.remote.getsockname()[1], 'listenerPort': self.listener_port,
                       'mediaBase': self.base, 'remoteMediaBase': self.remote_base}

    def own(self, sock):
        self.owned.append(sock)
        sock.settimeout(3)
        return sock

    def tcp_listener(self, address):
        sock = self.own(socket.socket())
        sock.bind((address, 0))
        sock.listen(1)
        return sock

    def reserve_three(self, addresses):
        for _ in range(50):
            base, pending = random.randrange(20000, 50000), []
            try:
                for address in addresses:
                    for offset in range(3):
                        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        pending.append(sock)
                        sock.bind((address, base + offset))
                for sock in pending:
                    self.own(sock)
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 131072)
                return base, pending
            except OSError as error:
                for sock in pending:
                    sock.close()
                if error.errno != errno.EADDRINUSE:
                    raise
        self.fail('No free fixture ports')

    def start(self):
        child = Child(self.config)
        self.children.append(child)
        return child

    def connected_pair(self):
        child = self.start()
        child.event('ready')
        client = self.own(socket.socket())
        client.connect(('127.0.0.1', self.listener_port))
        server, peer = self.remote.accept()
        self.own(server)
        self.assertEqual(peer[0], self.address)
        server.sendall(b'ready')
        self.assertEqual(client.recv(5), b'ready')
        return child, client, server

    def native(self, offset):
        sock = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 131072)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
        sock.bind(('0.0.0.0', self.base + offset))
        with self.assertRaises(OSError) as caught:
            sock.connect(('127.0.0.1', self.base + offset))
        self.assertEqual(caught.exception.errno, errno.EADDRINUSE)
        self.assertEqual(sock.getsockname(), ('0.0.0.0', self.base + offset))
        return sock

    def tearDown(self):
        for child in self.children:
            child.close()
        for sock in self.owned:
            sock.close()

    def test_all_channels_preserve_expected_peers_and_datagram_boundaries(self):
        child, _, _ = self.connected_pair()
        native = [self.native(offset) for offset in range(3)]
        for offset, peer in enumerate(self.media):
            for length in (0, 1, 1400, 65507):
                payload = os.urandom(length)
                peer.sendto(payload, (self.address, self.base + offset))
                self.assertEqual(native[offset].recvfrom(65535), (payload, ('127.0.0.1', self.base + offset)))
                native[offset].sendto(payload, ('127.0.0.1', self.base + offset))
                self.assertEqual(peer.recvfrom(65535), (payload, (self.address, self.base + offset)))
        self.assertEqual(child.event('media'), {'receivedDatagrams': 12, 'sentDatagrams': 12, 'droppedDatagrams': 0})
        self.assertEqual(select.select(native + self.media, [], [], .1)[0], [])

    def test_tcp_backpressure_and_half_close(self):
        child, client, server = self.connected_pair()
        request, reply = os.urandom(2_000_000), os.urandom(2_000_000)
        def remote_work():
            received = bytearray()
            while True:
                part = server.recv(65536)
                if not part:
                    break
                received.extend(part)
            self.assertEqual(bytes(received), request)
            server.sendall(reply)
            server.shutdown(socket.SHUT_WR)
        with concurrent.futures.ThreadPoolExecutor(1) as executor:
            future = executor.submit(remote_work)
            client.sendall(request)
            client.shutdown(socket.SHUT_WR)
            received = bytearray()
            while True:
                part = client.recv(65536)
                if not part:
                    break
                received.extend(part)
            self.assertEqual(bytes(received), reply)
            future.result(timeout=5)
        final = {}
        while 'stopped' not in final:
            event = child.events.get(timeout=3)['event']
            self.assertNotIn('failed', event)
            final.update(event)
        self.assertEqual(final['traffic'], {'receivedBytes': len(reply) + 5, 'sentBytes': len(request)})
        self.assertEqual(final['control'], {'nativeAccepted': True, 'remoteConnected': True,
                                          'nativeReadClosed': True, 'remoteReadClosed': True})
        self.assertEqual(child.process.wait(timeout=3), 0)

    def test_existing_owners_refuse_startup_and_partial_reservations_are_released(self):
        for address in ('0.0.0.0', '127.0.0.1', self.address):
            with self.subTest(address=address):
                occupied = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
                occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                occupied.bind((address, self.base + 1))
                child = self.start()
                self.assertEqual(child.event('failed')['code'], 'addressInUse')
                self.assertEqual(child.process.wait(timeout=3), 1)
                for free_address in (self.address, '127.0.0.1'):
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                        probe.bind((free_address, self.base))
                occupied.close()

    def test_parent_eof_releases_tcp_and_all_udp_reservations(self):
        child, _, _ = self.connected_pair()
        child.process.stdin.close()
        child.event('stopped')
        self.assertEqual(child.process.wait(timeout=3), 0)
        for address in (self.address, '127.0.0.1'):
            for offset in range(3):
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                    probe.bind((address, self.base + offset))
        with socket.socket() as probe:
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            probe.bind(('127.0.0.1', self.listener_port))
            probe.listen(1)

    def test_unexpected_network_peer_is_not_forwarded(self):
        child, _, _ = self.connected_pair()
        native = self.native(0)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
            sender.bind((self.address, 0))
            source = sender.getsockname()
            sender.sendto(b'unrelated', (self.address, self.base))
        # Apple's wildcard socket can receive unrelated packets directly. This
        # is not a local firewall: verify Ruby neither forwards nor counts them.
        self.assertEqual(native.recvfrom(1024), (b'unrelated', source))
        self.assertEqual(child.event('media')['receivedDatagrams'], 0)

    def test_existing_tcp_listener_is_preserved(self):
        with socket.socket() as occupied:
            occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            occupied.bind(('127.0.0.1', self.listener_port))
            occupied.listen(1)
            child = self.start()
            self.assertEqual(child.event('failed')['code'], 'addressInUse')
            self.assertEqual(child.process.wait(timeout=3), 1)
            with socket.socket() as client:
                client.connect(('127.0.0.1', self.listener_port))
                accepted, _ = occupied.accept()
                accepted.close()

    def test_fresh_relay_can_restart_after_a_completed_tcp_session(self):
        child, client, server = self.connected_pair()
        client.shutdown(socket.SHUT_WR)
        self.assertEqual(server.recv(1), b'')
        server.shutdown(socket.SHUT_WR)
        self.assertEqual(client.recv(1), b'')
        child.event('stopped')
        self.assertEqual(child.process.wait(timeout=3), 0)
        client.close(); server.close()
        next_child, next_client, next_server = self.connected_pair()
        next_client.sendall(b'new attempt')
        self.assertEqual(next_server.recv(11), b'new attempt')
        self.assertIsNone(next_child.process.poll())

    def test_failure_identifies_outbound_bind_without_exposing_addresses(self):
        # Simulate a source disappearing after UDP reservation, without changing
        # any interface. Exercise the actual failing TCP bind and final events.
        script = SUPPORT['OPTIONS'].script
        with tempfile.TemporaryDirectory(prefix='ssp-failure-fixture-') as directory:
            wrapper = Path(directory) / 'fixture.rb'
            wrapper.write_text(f"""
require {json.dumps(str(script))}
module MissingSourceFixture
  def prepare
    super
    @external = '192.0.2.254'
  end
end
ScreenSharingRelay::LoopbackRelay.prepend(MissingSourceFixture)
exit ScreenSharingRelay::LoopbackRelay.new(STDIN, STDOUT).run
""")
            child = Child(self.config, script=wrapper)
            self.children.append(child)
            child.event('ready')
            with socket.socket() as client:
                client.connect(('127.0.0.1', self.listener_port))
                self.assertEqual(child.event('control'), {
                    'nativeAccepted': True, 'remoteConnected': False,
                    'nativeReadClosed': False, 'remoteReadClosed': False})
                context = child.event('failureContext')
                self.assertEqual(context, {'operation': 'hostBind', 'systemError': 'addressUnavailable'})
                self.assertNotIn('192.0.2.254', json.dumps(context))
                self.assertNotIn(directory, json.dumps(context))
                self.assertEqual(child.event('failed')['code'], 'localAddressUnavailable')
                self.assertEqual(child.process.wait(timeout=3), 1)

    def test_new_route_selection_does_not_abort_usable_pinned_sockets(self):
        script = SUPPORT['OPTIONS'].script
        with tempfile.TemporaryDirectory(prefix='ssp-route-fixture-') as directory:
            wrapper = Path(directory) / 'fixture.rb'
            wrapper.write_text(f"""
require {json.dumps(str(script))}
module ChangedRouteFixture
  def route_address
    @ready ? '192.0.2.254' : super
  end
end
ScreenSharingRelay::LoopbackRelay.prepend(ChangedRouteFixture)
exit ScreenSharingRelay::LoopbackRelay.new(STDIN, STDOUT).run
""")
            child = Child(self.config, script=wrapper)
            self.children.append(child)
            child.event('ready')
            # Cross the five-second check before connecting, as in the failed
            # live attempt. The previous guard aborted these usable sockets.
            for _ in range(6):
                child.event('media')
            client = self.own(socket.socket())
            client.connect(('127.0.0.1', self.listener_port))
            server, peer = self.remote.accept()
            self.own(server)
            self.assertEqual(peer[0], self.address)
            client.sendall(b'control')
            self.assertEqual(server.recv(7), b'control')
            server.sendall(b'reply')
            self.assertEqual(client.recv(5), b'reply')
            native = self.native(0)
            self.media[0].sendto(b'media', (self.address, self.base))
            self.assertEqual(native.recvfrom(1024), (b'media', ('127.0.0.1', self.base)))
            native.sendto(b'feedback', ('127.0.0.1', self.base))
            self.assertEqual(self.media[0].recvfrom(1024), (b'feedback', (self.address, self.base)))
            self.assertIsNone(child.process.poll())

    def test_missing_or_down_pinned_address_stops_and_releases_sockets(self):
        script = SUPPORT['OPTIONS'].script
        for mode in ('missing', 'down'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='ssp-source-fixture-') as directory:
                wrapper = Path(directory) / 'fixture.rb'
                wrapper.write_text(f"""
require {json.dumps(str(script))}
module MissingInterfaceFixture
  def getifaddrs
    super.flat_map do |interface|
      if interface.addr && interface.addr.ipv4? && interface.addr.ip_address == {json.dumps(self.address)}
        {json.dumps(mode)} == 'missing' ? [] : [Struct.new(:addr, :flags).new(interface.addr, interface.flags & ~Socket::IFF_UP)]
      else
        [interface]
      end
    end
  end
end
Socket.singleton_class.prepend(MissingInterfaceFixture)
module CheckImmediatelyFixture
  def prepare
    super
    @source_check = 0
  end
end
ScreenSharingRelay::LoopbackRelay.prepend(CheckImmediatelyFixture)
exit ScreenSharingRelay::LoopbackRelay.new(STDIN, STDOUT).run
""")
                child = Child(self.config, script=wrapper)
                self.children.append(child)
                child.event('ready')
                self.assertEqual(child.event('failureContext'), {'operation': 'sourceCheck', 'systemError': None})
                self.assertEqual(child.event('failed')['code'], 'localAddressUnavailable')
                self.assertEqual(child.process.wait(timeout=3), 1)
                for address in (self.address, '127.0.0.1'):
                    for offset in range(3):
                        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                            probe.bind((address, self.base + offset))
                with socket.socket() as probe:
                    probe.bind(('127.0.0.1', self.listener_port))
                    probe.listen(1)

    def test_refused_host_connection_reports_connect_stage(self):
        self.remote.close()
        child = self.start()
        child.event('ready')
        with socket.socket() as client:
            client.connect(('127.0.0.1', self.listener_port))
            self.assertEqual(child.event('control'), {
                'nativeAccepted': True, 'remoteConnected': False,
                'nativeReadClosed': False, 'remoteReadClosed': False})
            self.assertEqual(child.event('failureContext'), {
                'operation': 'hostConnect', 'systemError': 'connectionRefused'})
            self.assertEqual(child.event('failed')['code'], 'connectFailed')
            self.assertEqual(child.process.wait(timeout=3), 1)

    @unittest.skipUnless(OPTIONS.native_helper, 'Supply the actual Apple helper')
    def test_actual_apple_sockets_exchange_through_real_ruby_on_all_channels(self):
        self.connected_pair()
        for offset, peer in enumerate(self.media):
            helper = subprocess.Popen([str(OPTIONS.native_helper), '--loopback-roundtrip-port', str(self.base + offset)],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                self.assertTrue(select.select([helper.stdout], [], [], 5)[0])
                self.assertEqual(helper.stdout.readline(), b'ready\n')
                payload = os.urandom(32)
                peer.sendto(payload, (self.address, self.base + offset))
                self.assertEqual(peer.recvfrom(1024), (payload, (self.address, self.base + offset)))
                output, _ = helper.communicate(timeout=5)
                self.assertEqual(helper.returncode, 0)
                result = json.loads(output)
                self.assertNotIn('errorType', result)
                self.assertTrue(result['nativeWildcard'])
                self.assertFalse(result['nativeConnected'])
                self.assertTrue(result['injectionMatchesConfiguredPeer'])
            finally:
                if helper.poll() is None:
                    helper.kill()
                helper.communicate(timeout=3)


if __name__ == '__main__':
    unittest.main(argv=['test-loopback-relay.py'] + REST)
