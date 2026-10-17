#!/usr/bin/env python3
"""Exercise the real Ruby child on one existing address, on Linux and Darwin."""
import argparse
import errno
import json
import os
from pathlib import Path
import random
import runpy
import socket
import subprocess
import sys
import unittest
import uuid

PARSER = argparse.ArgumentParser()
PARSER.add_argument('--ruby', default='/usr/bin/ruby')
PARSER.add_argument('--native-helper', type=Path)
OPTIONS, REST = PARSER.parse_known_args()
SUPPORT = runpy.run_path(str(Path(__file__).with_name('test-ruby-relay.py')))
SUPPORT['OPTIONS'].ruby = OPTIONS.ruby
SUPPORT['OPTIONS'].script = Path(__file__).resolve().parents[1] / 'Sources/ProxyCore/Resources/incoming-relay.rb'
Child = SUPPORT['Child']


class IncomingTests(unittest.TestCase):
    def setUp(self):
        self.owned, self.children = [], []
        self.remote_base, self.remote = self.reserve_three()
        self.base, reservations = self.reserve_three()
        for s in reservations:
            s.close()
        self.config = {'version': 1, 'sessionID': str(uuid.uuid4()), 'remoteAddress': '127.0.0.1',
                       'mediaBase': self.base, 'remoteMediaBase': self.remote_base}

    def own(self, s):
        self.owned.append(s)
        s.settimeout(2)
        return s

    def reserve_three(self):
        for _ in range(50):
            base, sockets = random.randrange(20000, 50000), []
            try:
                for offset in range(3):
                    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    sockets.append(s)
                    s.bind(('127.0.0.1', base + offset))
                self.owned.extend(sockets)
                for s in sockets:
                    s.settimeout(2)
                return base, sockets
            except OSError:
                for s in sockets:
                    s.close()
        self.fail('No free fixture range')

    def start(self, config=None):
        child = Child(config or self.config)
        self.children.append(child)
        return child

    def native(self, offset=0, connected=False):
        s = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        s.bind(('0.0.0.0', self.base + offset))
        if connected:
            s.connect(('127.0.0.1', self.remote_base + offset))
        return s

    def tearDown(self):
        for child in self.children:
            child.close()
        for s in self.owned:
            s.close()

    def test_all_channels_preserve_datagrams_and_count_local_submission(self):
        child = self.start()
        child.event('ready')
        native = [self.native(i) for i in range(3)]
        for index, peer in enumerate(self.remote):
            for length in (0, 1, 1400, 65507):
                data = os.urandom(length)
                peer.sendto(data, ('127.0.0.1', self.base + index))
                actual, sender = native[index].recvfrom(65535)
                self.assertEqual(actual, data)
                self.assertEqual(sender[0], '127.0.0.1')
                self.assertNotEqual(sender[1], self.remote_base + index)
        media = child.event('media')
        self.assertEqual(media, {'receivedDatagrams': 12, 'sentDatagrams': 12, 'droppedDatagrams': 0})

    def test_connected_network_socket_rejects_other_sources(self):
        child = self.start()
        child.event('ready')
        intruder = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        intruder.sendto(b'unrelated', ('127.0.0.1', self.base))
        media = child.event('media')
        self.assertEqual(media['receivedDatagrams'], 0)
        native = self.native()
        self.remote[0].sendto(b'expected', ('127.0.0.1', self.base))
        self.assertEqual(native.recvfrom(1024)[0], b'expected')

    def test_existing_reusable_wildcard_and_connected_owners_prevent_startup(self):
        for connected in (False, True):
            with self.subTest(connected=connected):
                occupied = self.native(offset=1, connected=connected)
                child = self.start()
                self.assertEqual(child.event('failed')['code'], 'addressInUse')
                self.assertEqual(child.process.wait(timeout=3), 1)
                probe = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
                probe.bind(('127.0.0.1', self.base))  # First reservation was cleaned up.
                probe.close()
                occupied.close()

    def test_second_relay_cannot_replace_first_and_parent_eof_releases_ports(self):
        child = self.start()
        child.event('ready')
        second = self.start()
        self.assertEqual(second.event('failed')['code'], 'addressInUse')
        child.process.stdin.close()
        child.event('stopped')
        self.assertEqual(child.process.wait(timeout=3), 0)
        for offset in range(3):
            probe = self.own(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
            probe.bind(('127.0.0.1', self.base + offset))

    @unittest.skipUnless(sys.platform == 'darwin', 'Darwin duplicate-connect behavior')
    def test_native_connect_fallback_and_direct_feedback_with_real_ruby_receiver(self):
        child = self.start()
        child.event('ready')
        native = self.native()
        with self.assertRaises(OSError) as caught:
            native.connect(('127.0.0.1', self.remote_base))
        self.assertEqual(caught.exception.errno, errno.EADDRINUSE)
        self.remote[0].sendto(b'incoming', ('127.0.0.1', self.base))
        self.assertEqual(native.recvfrom(1024)[0], b'incoming')
        native.sendto(b'feedback', ('127.0.0.1', self.remote_base))
        self.assertEqual(self.remote[0].recvfrom(1024), (b'feedback', ('127.0.0.1', self.base)))

    @unittest.skipUnless(OPTIONS.native_helper, 'Native Apple helper supplied by macOS CI')
    def test_actual_apple_helper_coexists_with_ruby_at_equal_media_ports(self):
        config = dict(self.config, remoteAddress='192.0.2.1', remoteMediaBase=self.base)
        child = self.start(config)
        child.event('ready')
        for offset in range(3):
            completed = subprocess.run([str(OPTIONS.native_helper), '--reserved-port', str(self.base + offset)],
                                       capture_output=True, timeout=12, check=True)
            result = json.loads(completed.stdout)
            self.assertNotIn('errorType', result)
            self.assertTrue(result['nativeReturnedDescriptor'])
            self.assertTrue(result['nativeWildcard'])
            self.assertFalse(result['nativeConnected'])
            self.assertTrue(result['nativeMediaPortMatches'])
            self.assertTrue(result['localInjectionToNative'])


if __name__ == '__main__':
    unittest.main(argv=['test-incoming-relay.py'] + REST)
