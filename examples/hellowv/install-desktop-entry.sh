#!/usr/bin/env bash
# Installs (or removes, with --uninstall) a .desktop file for the hellowv
# example so its window gets a real Dock/taskbar icon on Linux.
#
# Why this is needed (see desktop/icon.mli, set_app_icon / set_app_id): under
# native Wayland (GNOME's default), the Dock resolves an app's icon from an
# installed .desktop file matched by the process's app id, not from
# _NET_WM_ICON (an X11-only property that set_app_icon sets, and that Wayland
# doesn't have). hellowv.ml calls [Webview_desktop.Icon.set_app_id "hellowv"] before
# creating its window; this script installs a .desktop file whose
# StartupWMClass matches that id, so GNOME (and other desktops) can find it.
#
# Usage:
#   ./install-desktop-entry.sh            # build + install for the current user
#   ./install-desktop-entry.sh --uninstall

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
apps_dir="$data_home/applications"
desktop_file="$apps_dir/owebview-hellowv.desktop"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f -- "$desktop_file"
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  echo "Removed $desktop_file"
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script only makes sense on Linux (Dock icon via .desktop file)." >&2
  exit 1
fi

binary="$repo_root/_build/default/examples/hellowv/hellowv.exe"
icon="$script_dir/web/hello.png"

if [[ ! -x "$binary" ]]; then
  echo "Building examples/hellowv/hellowv.exe..."
  (cd "$repo_root" && dune build examples/hellowv/hellowv.exe)
fi

if [[ ! -f "$icon" ]]; then
  echo "Missing icon: $icon" >&2
  exit 1
fi

mkdir -p -- "$apps_dir"
cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Hello WebView (owebview)
Comment=owebview hellowv example
Exec=$binary
Icon=$icon
StartupWMClass=hellowv
Terminal=false
Categories=Development;
EOF

command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true

echo "Installed $desktop_file"
echo "Run 'dune exec examples/hellowv/hellowv.exe' again — its window should now"
echo "show the hello.png icon in the Dock/taskbar."
echo "(Undo with: $0 --uninstall)"
