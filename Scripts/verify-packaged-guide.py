"""Run the exact offline guide command on a disposable macOS copy."""
from html.parser import HTMLParser
from pathlib import Path
import shlex
import shutil
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
        if tag == "code" and dict(attrs).get("id") == "discovery-command":
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
    volume_literal = "'/Volumes/Screen Sharing Proxy Diagnostics/screensharing-proxy-diagnose'"
    download_literal = '"$HOME/Downloads/ScreenSharingProxy-Diagnostics.XXXXXX"'
    assert snippet.count(volume_literal) == 1
    assert snippet.count(download_literal) == 1
    with tempfile.TemporaryDirectory(prefix="ssp-guide-") as temporary:
        root = Path(temporary)
        fixture = root / "Volume with spaces"
        fixture.mkdir()
        tool = fixture / "screensharing-proxy-diagnose"
        shutil.copy2(volume / tool.name, tool)
        subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;00000000;ScreenSharingProxy packaging test;", str(tool)], check=True)
        command = snippet.replace(volume_literal, shlex.quote(str(tool)))
        command = command.replace(download_literal, shlex.quote(str(root / "ScreenSharingProxy-Diagnostics.XXXXXX")))
        script = root / "guide.zsh"
        script.write_text(command + "\n")
        subprocess.run(["/bin/zsh", "-n", str(script)], check=True)
        result = subprocess.run(["/bin/zsh", str(script)], capture_output=True, text=True, timeout=90)
        assert result.returncode in (0, 3), result.stderr
        installed = list(root.glob("ScreenSharingProxy-Diagnostics.*"))
        assert len(installed) == 1
        copied = installed[0] / tool.name
        assert (installed[0] / "proxyd-report.json").is_file()
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(copied)], check=True)
        quarantine = subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(copied)], capture_output=True)
        assert quarantine.returncode != 0
        # The guide must reject a validly signed, unrelated executable.
        # Apple system executables carry protected file flags. Copy only their
        # signed contents; reproducing those flags requires privileges and is
        # irrelevant to this identity-rejection test.
        shutil.copyfile("/bin/echo", tool)
        tool.chmod(0o755)
        unrelated = subprocess.run(["/bin/zsh", str(script)], capture_output=True, timeout=30)
        assert unrelated.returncode not in (0, 3)
    print("Offline guide command and unrelated-executable rejection passed.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Surface the exact failing check through GitHub's Checks API as well
        # as the job log. No collected diagnostic report is included here.
        detail = traceback.format_exc().replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print("::error title=Offline guide verification::" + detail, flush=True)
        raise
