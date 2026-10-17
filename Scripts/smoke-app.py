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
        pair_path = Path(temporary) / "pair.json"
        pair_run = subprocess.run([str(binary), "--smoke-pair", str(pair_path)], capture_output=True, text=True, timeout=120)
        assert pair_run.returncode == 0, pair_run.stdout + pair_run.stderr
        pair = json.loads(pair_path.read_text())
        assert pair["kind"] == "screenSharingCapturePair"
        before, during = pair["baseline"], pair["duringSession"]
        assert before["capturePhase"] == "baseline" and during["capturePhase"] == "duringSession"
        assert before["redactionScopeID"] == during["redactionScopeID"]
        assert len(before["samples"]) == 3 and len(during["samples"]) == 10
        for capture in (before, during):
            assert capture["schemaVersion"] == 2 and capture["components"]
            assert capture["mediaPortConfiguration"]["activeSessionUDPBase"] == "unknown"
            assert not capture["privateDetailsIncluded"]
        assert stat.S_IMODE(pair_path.stat().st_mode) == 0o600
    print("Native app window, discovery, resources, signature and export passed.")


if __name__ == "__main__":
    main()
