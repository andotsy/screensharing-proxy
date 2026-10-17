"""Finder layout for the release workflow; no Finder automation required."""

from pathlib import Path

# dmgbuild executes settings without __file__; the workflow runs at repo root.
root = Path(defines.get("root", ".")).resolve()
files = [
    str(root / ".build" / "native-bundle" / "ScreenSharingProxy.app"),
    str(root / "Packaging" / "README.html"),
]
symlinks = {"Applications": "/Applications", "Terminal": "/System/Applications/Utilities/Terminal.app"}
format = "UDZO"
filesystem = "HFS+"
background = str(root / ".build" / "dmg-background.png")
# Leave room for users who force Finder's tab/status bars on globally.
window_rect = ((160, 180), (760, 600))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
show_icon_preview = False
arrange_by = None
grid_spacing = 90
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 88
icon_locations = {
    "ScreenSharingProxy.app": (190, 214),
    "Applications": (570, 214),
    "README.html": (270, 402),
    "Terminal": (490, 402),
}
# Finder already treats .app as a bundle. Setting its hidden-extension flag
# adds FinderInfo to the signed bundle and breaks strict signature validation.
hide_extensions = []
