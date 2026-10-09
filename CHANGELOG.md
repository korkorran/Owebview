# Changelog

## 0.2.0

The package now installs **two libraries**.

- `owebview` — the webview binding, and nothing else.
- `owebview.desktop` (new) — native desktop integration: menu bars with
  keyboard accelerators (`Webview_desktop.Menu`), modal confirm and
  file/folder dialogs (`Webview_desktop.Dialog`), the application icon and id
  (`Webview_desktop.Icon`), and locating the `web/` directory relative to the
  executable (`Webview_desktop.Locate_assets`).

The last two moved out of `owebview`, which makes this release **breaking**:

- `Webview.set_app_icon` / `Webview.set_app_id` → `Webview_desktop.Icon.*`
- `Webview.Utils` → `Webview_desktop.Locate_assets`
- `Locate_assets.asset_dir` is gone: assets are read from beside the
  executable only, so run `dune build` before `dune exec`.

## 0.1.0

First release: OCaml bindings covering the whole webview 0.12 C API — window
lifecycle, navigation and inline HTML, the JavaScript bridge, threading and
native handles — plus two conveniences, locating the `web/` assets directory
and setting an application icon for a development build.
