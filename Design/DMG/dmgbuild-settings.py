# dmgbuild settings for Nomi's DMG window. scripts/build-dmg.sh passes the paths with -D.
# The positions match Design/DMG/make-background.swift: a 720 x 560 window with
# 120-point icons, Nomi at (200, 205), Applications at (520, 205), and the
# "Open Settings" guide at (608, 408), centered in the steps panel with its two-line label.
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
guide = defines["guide"]  # noqa: F821
background = defines["background"]  # noqa: F821

volume_name = "Nomi"
format = "UDZO"
filesystem = "HFS+"

files = [app, guide]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(guide)]

# dmgbuild pairs background.png with background@2x.png for Retina screens.
window_rect = ((200, 120), (720, 560))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 120
text_size = 12
arrange_by = None
icon_locations = {
    "Nomi.app": (200, 205),
    "Applications": (520, 205),
    os.path.basename(guide): (608, 408),
}
