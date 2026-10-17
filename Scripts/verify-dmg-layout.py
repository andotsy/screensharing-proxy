"""Inspect the actual Finder metadata and background in the mounted DMG."""
from pathlib import Path
import subprocess
import sys
from ds_store import DSStore

volume = Path(sys.argv[1])
with DSStore.open(str(volume / '.DS_Store'), 'r') as store:
    positions = {entry.filename: entry.value for entry in store if entry.code == b'Iloc'}
    view = store['.']['icvp']
    window = store['.']['bwsp']
assert positions['ScreenSharingProxy.app'] == (190, 214), positions
assert positions['Applications'] == (570, 214), positions
assert positions['README.html'] == (270, 402), positions
assert positions['Terminal'] == (490, 402), positions
assert view['iconSize'] == 88 and view['textSize'] == 13
assert view['backgroundType'] == 2 and view['backgroundImageAlias']
assert not window['ShowToolbar'] and not window['ShowSidebar']
assert '760, 600' in window['WindowBounds'], window
assert any((volume / '.background').iterdir())
for name, width, height in [('dmg-background.png', 760, 560), ('dmg-background@2x.png', 1520, 1120)]:
    result = subprocess.run(['/usr/bin/sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(Path('.build') / name)],
                            capture_output=True, text=True, check=True)
    assert f'pixelWidth: {width}' in result.stdout and f'pixelHeight: {height}' in result.stdout
print('Finder icon positions, window layout and Retina background passed.')
