"""Open a real native window, perform automatic discovery and export a report."""
import json
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile


def main():
    bundle = Path(sys.argv[1]).resolve()
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.andotsy.screensharing-proxy"
    assert info["LSMinimumSystemVersion"] == "14.0"
    icon = bundle / "Contents/Resources/AppIcon.icns"
    assert icon.read_bytes().startswith(b"icns") and icon.stat().st_size > 1000
    binary = bundle / "Contents/MacOS/ScreenSharingProxy"
    version = subprocess.run([str(binary), "--version"], capture_output=True, text=True, check=True)
    assert version.stdout.strip() == "Screen Sharing Proxy " + info["SSPReleaseVersion"]
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    with tempfile.TemporaryDirectory(prefix="ssp-app-") as temporary:
        report = Path(temporary) / "report.json"
        result = subprocess.run([str(binary), "--smoke-test", str(report)], capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "Native window and automatic discovery passed." in result.stdout
        data = json.loads(report.read_text())
        assert data["toolVersion"] == info["SSPReleaseVersion"]
        assert data["platform"] == "macOS" and data["probes"]
        assert data["privateDetailsIncluded"] is False
        assert data["highPerformanceRelay"] == "notVerified"
        assert stat.S_IMODE(report.stat().st_mode) == 0o600
    print("Native app window, discovery, resources, signature and export passed.")


if __name__ == "__main__":
    main()
