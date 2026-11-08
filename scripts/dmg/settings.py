# dmgbuild settings for scripts/dmg.sh: the usual drag-to-Applications window.
#
# No background picture on purpose: Finder draws icon labels white in Dark Mode, which can't
# be read on a light picture. The plain window follows the system appearance.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(app)

format = "ULMO"  # LZMA, the smallest; opens on macOS 10.15+
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volume_icon") or None  # noqa: F821

window_rect = ((200, 160), (600, 360))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (150, 160),
    "Applications": (450, 160),
}
