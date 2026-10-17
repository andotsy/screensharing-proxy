"""Run the exact offline guide command on a disposable macOS copy."""
from html.parser import HTMLParser
from pathlib import Path
import json
import plistlib
import shlex
import subprocess
import sys
import tempfile
import traceback


class CommandBlock(HTMLParser):
    def __init__(self):
        super().__init__()
        self.inside = False
        self.blocks = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag == "code" and dict(attrs).get("id") == "launch-command":
            self.inside = True
            self.blocks += 1

    def handle_endtag(self, tag):
        if tag == "code":
            self.inside = False

    def handle_data(self, data):
        if self.inside:
            self.parts.append(data)


def main():
    volume = Path(sys.argv[1]).resolve()
    parser = CommandBlock()
    parser.feed((volume / "README.html").read_text())
    assert parser.blocks == 1
    snippet = "".join(parser.parts).strip()
    assert snippet in Path("docs/INSTALL.md").read_text()
    app_literal = "'/Applications/ScreenSharingProxy.app'"
    assert snippet.count(app_literal) == 1
    with tempfile.TemporaryDirectory(prefix="ssp-guide-") as temporary:
        root = Path(temporary)
        app = root / "Applications with spaces/ScreenSharingProxy.app"
        app.parent.mkdir()
        subprocess.run(["/usr/bin/ditto", str(volume / app.name), str(app)], check=True)
        subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;00000000;ScreenSharingProxy packaging test;", str(app)], check=True)
        report = root / "native-report.json"
        command = snippet.replace(app_literal, shlex.quote(str(app)))
        # Keep the guide's launch command, with a test-only argument so the
        # launched native app exports evidence and quits after discovery.
        command = command.replace('/usr/bin/open "$app"',
            '/usr/bin/open -W "$app" --args --smoke-test ' + shlex.quote(str(report)))
        script = root / "guide.zsh"
        script.write_text(command + "\n")
        subprocess.run(["/bin/zsh", "-n", str(script)], check=True)
        result = subprocess.run(["/bin/zsh", str(script)], capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, result.stderr
        assert json.loads(report.read_text())["platform"] == "macOS"
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        quarantine = subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(app)], capture_output=True)
        assert quarantine.returncode != 0
        # A signed app with another identity must be rejected before removing
        # its quarantine marker or attempting to launch it.
        plist = app / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info["CFBundleIdentifier"] = "com.andotsy.packaging.unrelated"
        plist.write_bytes(plistlib.dumps(info))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", info["CFBundleIdentifier"], str(app)], check=True)
        subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;00000000;ScreenSharingProxy packaging test;", str(app)], check=True)
        unrelated = subprocess.run(["/bin/zsh", str(script)], capture_output=True, timeout=30)
        assert unrelated.returncode != 0
        subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(app)], check=True, capture_output=True)
    print("Offline app launch command and unrelated-app rejection passed.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Surface the exact failing check through GitHub's Checks API as well
        # as the job log. No collected diagnostic report is included here.
        detail = traceback.format_exc().replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print("::error title=Offline guide verification::" + detail, flush=True)
        raise
