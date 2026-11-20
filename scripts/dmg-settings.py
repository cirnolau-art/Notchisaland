"""Finder layout for the drag-to-install disk image; no Finder automation required."""
from pathlib import Path
import subprocess

app = Path(defines["app"])
files = [str(app)]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
size = "64m"
icon = str(app / "Contents/Resources/AppIcon.icns")
background = defines["background"]
default_view = "icon-view"
window_rect = ((420, 220), (660, 430))
icon_locations = {app.name: (180, 210), "Applications": (480, 210)}
icon_size = 112
text_size = 13
label_pos = "bottom"
arrange_by = None
grid_spacing = 80
show_icon_preview = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False


def create_hook(mount_point, settings):
    # Finder metadata written onto a signed .app can invalidate strict verification.
    # Check the copy inside the image before finalizing it.
    subprocess.run(["codesign", "--verify", "--deep", "--strict",
                    str(Path(mount_point) / app.name)], check=True)
