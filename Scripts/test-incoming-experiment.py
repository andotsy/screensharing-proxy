#!/usr/bin/env python3
"""Native command smoke checks using owned high ports and no remote packets."""
import argparse
import errno
import json
import os
from pathlib import Path
import random
import select
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest

PARSER = argparse.ArgumentParser()
PARSER.add_argument('executable', type=Path)
PARSER.add_argument('--mode', choices=['incoming', 'loopback'], default='incoming')
OPTIONS, REST = PARSER.parse_known_args()
EXECUTABLE = OPTIONS.executable.resolve()
REMOTE = '192.0.2.1'  # UDP connect chooses a route; the fixture sends no packets.


@unittest.skipUnless(sys.platform == 'darwin', 'Native macOS experiment')
class ExperimentTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='ssp-experiment-')
        self.output = Path(self.directory.name) / 'result.json'
        self.children = []
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
            route.connect((REMOTE, 9))
            self.address = route.getsockname()[0]
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            self.listener_port = reservation.getsockname()[1]
        for _ in range(50):
            self.base = random.randrange(20000, 50000)
            try:
                self.assert_ports_available()
                break
            except OSError as error:
                if error.errno != errno.EADDRINUSE:
                    raise
        else:
            self.fail('No free high-port range')

    def tearDown(self):
        for process in self.children:
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=2)
                self.fail('Experiment did not clean up after termination')
        self.directory.cleanup()

    def assert_ports_available(self):
        sockets = []
        try:
            addresses = [self.address, '127.0.0.1'] if OPTIONS.mode == 'loopback' else [self.address]
            for address in addresses:
                for offset in range(3):
                    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    sockets.append(sock)
                    sock.bind((address, self.base + offset))
            if OPTIONS.mode == 'loopback':
                sock = socket.socket()
                sockets.append(sock)
                sock.bind(('127.0.0.1', self.listener_port))
                sock.listen(1)
        finally:
            for sock in sockets:
                sock.close()

    def start(self):
        arguments = [
            str(EXECUTABLE), OPTIONS.mode, '--remote', REMOTE,
            '--media-base', str(self.base), '--duration', '10', '--output', str(self.output),
        ]
        if OPTIONS.mode == 'loopback':
            arguments += ['--listen-port', str(self.listener_port)]
        process = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(process)
        return process

    def wait_ready(self, process):
        message = b''
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if select.select([process.stderr], [], [], .1)[0]:
                chunk = os.read(process.stderr.fileno(), 4096)
                if not chunk:
                    break
                message += chunk
                self.assertLess(len(message), 16384)
                if b'Relay ready.' in message:
                    return
        self.fail('Experiment did not become ready')

    def read_report(self):
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
        data = self.output.read_text()
        self.assertNotIn(REMOTE, data)
        self.assertNotIn(self.address, data)
        self.assertNotIn(self.directory.name, data)
        report = json.loads(data)
        self.assertEqual(report['schemaVersion'], 6)
        self.assertEqual(report['highPerformanceSession'], 'unverified')
        if OPTIONS.mode == 'loopback':
            self.assertEqual(report['experiment'], 'loopback-ruby-tcp-udp')
            self.assertEqual(report['forwardedToNativeDatagrams'], 0)
            self.assertEqual(report['forwardedToRemoteDatagrams'], 0)
            self.assertNotIn('submittedDatagrams', report)
            self.assertFalse(report['nativeTCPAccepted'])
            self.assertFalse(report['remoteTCPConnected'])
            self.assertEqual(report['nativeTCPConnectionCount'], 0)
            self.assertEqual(report['remoteTCPConnectionCount'], 0)
            self.assertEqual(report['completedTCPConnectionCount'], 0)
        else:
            self.assertEqual(report['experiment'], 'incoming-ruby-udp')
            self.assertEqual(report['receivedDatagrams'], 0)
        return report

    def test_signals_stop_reap_and_save_private_report(self):
        for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=number):
                self.output = Path(self.directory.name) / f'result-{number}.json'
                process = self.start()
                self.wait_ready(process)
                process.send_signal(number)
                process.communicate(timeout=5)
                self.assertEqual(process.returncode, 130)
                report = self.read_report()
                self.assertEqual(report['termination'], 'interrupted')
                self.assertTrue(report['relayReady'])
                self.assertTrue(report['relayStopAcknowledged'])
                self.assert_ports_available()

    def test_deadline_stops_without_user_intervention(self):
        process = self.start()
        self.wait_ready(process)
        process.communicate(timeout=14)
        self.assertEqual(process.returncode, 0)
        report = self.read_report()
        self.assertEqual(report['termination'], 'durationReached')
        self.assertTrue(report['relayStopAcknowledged'])
        self.assertGreaterEqual(report['elapsedSeconds'], 10)
        self.assertLess(report['elapsedSeconds'], 14)
        self.assert_ports_available()

    def test_existing_report_is_preserved_before_startup(self):
        self.output.write_bytes(b'existing-report')
        process = self.start()
        process.communicate(timeout=5)
        self.assertEqual(process.returncode, 64)
        self.assertEqual(self.output.read_bytes(), b'existing-report')
        self.assert_ports_available()

    def test_existing_socket_is_preserved_and_failure_is_reported(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as occupied:
            occupied.bind((self.address, self.base + 1))
            process = self.start()
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 1)
            report = self.read_report()
            self.assertEqual(report['failure'], 'addressInUse')
            expected_operation = 'udpExternalBind' if OPTIONS.mode == 'loopback' else 'socketReservation'
            self.assertEqual(report['failureOperation'], expected_operation)
            if OPTIONS.mode == 'loopback':
                self.assertEqual(report['failurePort'], self.base + 1)
            self.assertEqual(report['failureSystemError'], 'addressInUse')
            self.assertFalse(report['relayReady'])
            self.assertEqual(occupied.getsockname(), (self.address, self.base + 1))
        self.assert_ports_available()

    @unittest.skipUnless(OPTIONS.mode == 'loopback', 'Only loopback owns a TCP listener')
    def test_tcp_conflict_report_names_the_actual_port_and_operation(self):
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1', self.listener_port))
            occupied.listen(1)
            process = self.start()
            _, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 1)
            report = self.read_report()
            self.assertEqual(report['failure'], 'addressInUse')
            self.assertEqual(report['failureOperation'], 'tcpListenerBind')
            self.assertEqual(report['failurePort'], self.listener_port)
            self.assertIn(f'Affected port: {self.listener_port}.'.encode(), stderr)
            self.assertFalse(report['relayReady'])
            self.assertEqual(occupied.getsockname(), ('127.0.0.1', self.listener_port))
        self.assert_ports_available()


if __name__ == '__main__':
    unittest.main(argv=['test-incoming-experiment.py'] + REST)
