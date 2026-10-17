#!/usr/bin/env python3
"""Bounded read-only symbol/string evidence; never runs Apple's services."""
from pathlib import Path
import re
import subprocess

targets = [
    Path('/System/Applications/Utilities/Screen Sharing.app/Contents/MacOS/Screen Sharing'),
    Path('/System/Library/CoreServices/RemoteManagement/ScreensharingAgent.bundle/Contents/MacOS/ScreensharingAgent'),
    Path('/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd'),
]
pattern = re.compile(r'port.?base|udp|rtcp|loopback|localhost|sockname|peername|media.{0,20}(port|address)|(?:local|remote|peer).{0,20}(port|address)|bind.{0,15}(port|socket)', re.I)
for target in targets:
    print('COMPONENT', target.name, flush=True)
    if not target.is_file():
        print('unavailable')
        continue
    for command in [['/usr/bin/otool', '-L', str(target)], ['/usr/bin/strings', '-a', str(target)]]:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
        assert len(result.stdout) < 16 * 1024 * 1024
        lines = result.stdout.decode('utf-8', errors='replace').splitlines()
        if command[0].endswith('strings'):
            lines = list(dict.fromkeys(line for line in lines if pattern.search(line)))[:120]
        else:
            lines = [line for line in lines if '/System/' in line][:50]
        for line in lines:
            print(line[:400])
