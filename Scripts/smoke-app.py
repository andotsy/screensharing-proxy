"""Check the bundle's resources and signature, then open its window once."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def main():
    bundle = Path(sys.argv[1]).resolve()
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    assert bundle.name == "Screen Sharing Rubyfier.app"
    assert info["CFBundleName"] == info["CFBundleDisplayName"] == "Screen Sharing Rubyfier"
    assert info["CFBundleIdentifier"] == "com.andotsy.screensharing-proxy"
    assert info["LSMinimumSystemVersion"] == "14.0"
    icon = bundle / "Contents/Resources/AppIcon.icns"
    assert icon.read_bytes().startswith(b"icns") and icon.stat().st_size > 1000
    assert info["CFBundleIconName"] == "AppIcon"
    assert (bundle / "Contents/Resources/Assets.car").stat().st_size > 1000
    payload = bundle / "Contents/Resources/Rubyfier"
    for name in ["patch.rb", "Payload/optool", "Payload/RubiedLauncher",
                 "Payload/RubiedTransport.dylib", "Payload/Relay/loopback-relay.rb",
                 "Payload/Relay/relay.rb", "Payload/compatibility.json",
                 "Licenses/optool.txt", "Licenses/ArgumentParser.md"]:
        assert (payload / name).stat().st_size > 0, name
    binary = bundle / "Contents/MacOS/ScreenSharingProxy"
    version = subprocess.run([str(binary), "--version"], capture_output=True, text=True, check=True)
    assert version.stdout.strip() == "Screen Sharing Rubyfier " + info["SSPReleaseVersion"]
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    with tempfile.TemporaryDirectory(prefix="ssp-app-") as temporary:
        marker = Path(temporary) / "window-ready.txt"
        process = subprocess.Popen([str(binary), "--smoke-test", str(marker)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            stdout, stderr = process.communicate(timeout=45)
        except subprocess.TimeoutExpired:
            # Capture only this disposable CI app and the hosted runner desktop.
            debug = Path('.build/native-smoke-debug')
            debug.mkdir(parents=True, exist_ok=True)
            for command in [
                ['/usr/bin/sample', str(process.pid), '1', '-file', str(debug / 'sample.txt')],
                ['/usr/sbin/screencapture', '-x', '-m', str(debug / 'desktop.png')],
            ]:
                try:
                    subprocess.run(command, capture_output=True, timeout=10)
                except subprocess.TimeoutExpired:
                    pass
            process.kill()
            stdout, stderr = process.communicate(timeout=10)
            (debug / 'app.log').write_text(stdout + stderr)
            print(stdout + stderr, flush=True)
            raise
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=10)
        assert process.returncode == 0, stdout + stderr
        assert "Native window, console, minimum size and bundled patcher passed." in stdout
        assert marker.read_text() == f"Screen Sharing Rubyfier {info['SSPReleaseVersion']} window ready\n"
    print("Native window, bundled patcher, resources and signature passed.")


if __name__ == "__main__":
    main()
