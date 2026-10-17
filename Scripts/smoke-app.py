"""Open a native window, collect once, accept the save sheet and inspect the ZIP."""
import json
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import zipfile


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
        report = Path(temporary) / "diagnostics.zip"
        try:
            result = subprocess.run([str(binary), "--smoke-test", str(report)], capture_output=True, text=True, timeout=90)
        except subprocess.TimeoutExpired as error:
            print(error.stdout or b"", error.stderr or b"", flush=True)
            raise
        assert result.returncode == 0, result.stdout + result.stderr
        assert "Native collection, save dialog and ZIP export passed." in result.stdout
        with zipfile.ZipFile(report) as archive:
            assert archive.testzip() is None
            assert set(archive.namelist()) == {"diagnostics.json", "README.txt"}
            data = json.loads(archive.read("diagnostics.json"))
            assert b"Send this ZIP" in archive.read("README.txt")
        assert data["schemaVersion"] == 2 and len(data["samples"]) == 10
        assert data["components"]
        assert data["toolVersion"] == info["SSPReleaseVersion"]
        assert data["platform"] == "macOS" and data["probes"]
        assert data["privateDetailsIncluded"] is False
        assert data["highPerformanceRelay"] == "notVerified"
        assert stat.S_IMODE(report.stat().st_mode) == 0o600

    print("Native app window, save dialog, ZIP, resources and signature passed.")


if __name__ == "__main__":
    main()
