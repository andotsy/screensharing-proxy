"""Inspect the actual Finder metadata and background in the mounted DMG."""
from pathlib import Path
import struct
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
# dmgbuild combines the 1x and @2x PNGs into a hidden multi-image TIFF.
background = (volume / '.background.tiff').read_bytes()
assert background[:2] in (b'II', b'MM')
endian = '<' if background[:2] == b'II' else '>'
def u16(offset):
    return struct.unpack_from(endian + 'H', background, offset)[0]
def u32(offset):
    return struct.unpack_from(endian + 'I', background, offset)[0]
assert u16(2) == 42
offset = u32(4)
sizes, visited = [], set()
while offset:
    assert offset not in visited and len(visited) < 8
    visited.add(offset)
    count = u16(offset)
    dimensions = {}
    for index in range(count):
        entry = offset + 2 + index * 12
        tag, kind = u16(entry), u16(entry + 2)
        if tag in (256, 257):
            assert u32(entry + 4) == 1 and kind in (3, 4)
            dimensions[tag] = u16(entry + 8) if kind == 3 else u32(entry + 8)
    sizes.append((dimensions[256], dimensions[257]))
    offset = u32(offset + 2 + count * 12)
assert sorted(sizes) == [(760, 560), (1520, 1120)], sizes
for name, width, height in [('dmg-background.png', 760, 560), ('dmg-background@2x.png', 1520, 1120)]:
    result = subprocess.run(['/usr/bin/sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(Path('.build') / name)],
                            capture_output=True, text=True, check=True)
    assert f'pixelWidth: {width}' in result.stdout and f'pixelHeight: {height}' in result.stdout
print('Finder icon positions, window layout and Retina background passed.')
