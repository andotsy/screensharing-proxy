#!/usr/bin/env python3
"""Verify actual AVC startup, feedback, local video slots and observer cleanup."""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='rubyfied-media-') as directory:
        root = Path(directory)
        source = (ROOT / 'Sources/Rubied/RubiedTransport.m').read_text()
        destination = '[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Screen Sharing Rubyfied"]'
        assert source.count(destination) == 1
        source = source.replace(destination, '@' + json.dumps(str(root / 'reports')))
        fixture = root / 'fixture.m'
        fixture.write_text(source + '\n' + (ROOT / 'Scripts/probe-rubyfied-media.m').read_text())
        binary = root / 'fixture'
        subprocess.run(['clang', '-arch', 'arm64', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                        '-framework', 'Foundation', '-framework', 'AppKit', '-framework', 'QuartzCore',
                        str(fixture), '-o', str(binary)], check=True, timeout=60)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=25)
        # Native logs are not a diagnostic output surface. Only fixture labels.
        for line in (result.stdout + result.stderr).splitlines():
            if line.startswith(('Native in-process', 'Native media fixture failed:')):
                print(line)
        assert result.returncode == 0, f'Native media fixture exited {result.returncode}'


if __name__ == '__main__':
    main()
