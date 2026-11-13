"""Finder layout in points, matching render-background.swift's 640 × 520 artwork."""

from pathlib import Path
import plistlib

application = Path(defines["app"])
files = [str(application)]
symlinks = {"Applications": "/Applications"}
# Hiding the extension writes FinderInfo onto the signed app bundle, which
# fails codesign --verify --strict. Leave its metadata untouched.
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
# Allow for the title, path, and status bars, which Finder may show globally.
window_rect = ((200, 200), (640, 520))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {application.name: (137, 200), "Applications": (503, 200)}

# Use the app's compiled icon for the mounted disk, when one is available.
with (application / "Contents/Info.plist").open("rb") as info_file:
    icon_name = plistlib.load(info_file).get("CFBundleIconFile", "")
if icon_name:
    icon_path = application / "Contents/Resources" / icon_name
    if not icon_path.suffix:
        icon_path = icon_path.with_suffix(".icns")
    if icon_path.is_file():
        icon = str(icon_path)
