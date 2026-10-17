"""Exercise the built CLI on either host platform; no third-party dependencies."""
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def main():
    binary = str(Path(sys.argv[1]).resolve())

    def run(*arguments):
        return subprocess.run([binary, *arguments], capture_output=True, text=True, timeout=90)

    help_result = run("--help")
    assert help_result.returncode == 0 and "discover" in help_result.stdout
    version = run("--version")
    assert version.returncode == 0 and version.stdout.startswith("screensharing-proxy-diagnose ")
    assert run("collect", "--remote", "invalid.example").returncode == 64

    with tempfile.TemporaryDirectory(prefix="ssp-cli-") as temporary:
        report_path = Path(temporary) / "report.json"
        result = run("discover", "--output", str(report_path))
        if sys.platform == "darwin":
            assert result.returncode in (0, 3), result.stderr
        else:
            assert result.returncode == 2, result.stderr
        report = json.loads(report_path.read_text())
        assert report["highPerformanceRelay"] == "notVerified"
        assert report["toolVersion"] == version.stdout.strip().split(" ", 1)[1]
        assert stat.S_IMODE(report_path.stat().st_mode) == 0o600
        if sys.platform == "darwin":
            assert report["platform"] == "macOS" and report["probes"]
            assert (result.returncode == 0) == (report["proxyDiscovery"]["status"] == "selected")
        else:
            assert report["proxyDiscovery"]["status"] == "unsupportedPlatform"
            assert report["probes"] == []

        original = report_path.read_bytes()
        assert run("discover", "--output", str(report_path)).returncode == 64
        assert report_path.read_bytes() == original
        link = Path(temporary) / "link.json"
        link.symlink_to(report_path)
        assert run("discover", "--output", str(link)).returncode == 64
        assert report_path.read_bytes() == original
    print("CLI smoke checks passed (" + sys.platform + ").")


if __name__ == "__main__":
    main()
