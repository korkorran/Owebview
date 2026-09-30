# owebview

OCaml binding for the [webview](https://github.com/webview/webview) library.

> A thin binding that covers the full webview 0.12 C API. It stays low-level on
> purpose — higher-level conveniences are left to the caller.

## Architecture

| File | Role |
|---|---|
| `lib/webview.mli` / `.ml` | OCaml API + `external` declarations |
| `lib/webview_stubs.cpp` | C ↔ OCaml glue for the `vendor/webview.h` API (runtime lock, GC roots for callbacks) |
| `lib/icon_stubs.cpp` | `set_app_icon` / `set_app_id`: direct Cocoa/GTK/Win32 calls, outside the webview API |
| `lib/icon.ml` | Application icon/id externals (`Webview.Icon`) |
| `lib/utils.ml` | Filesystem helpers (`Webview.Utils`) to locate assets |
| `lib/dune` | Compiles the C++ stub and links the native libraries |
| `lib/config/discover.ml` | Detects platform C++ flags at build time (dune-configurator) |
| `examples/hellowv/hellowv.ml` | Minimal window with two JS → OCaml bindings |
| `examples/hellowv/utils.ml` | Example-local helper (host OS detection) |
| `examples/hellowv/web/` | Page assets (`index.html` + `style.css` + `app.js`) |
| `examples/hellowv/install-desktop-entry.sh` | Installs a `.desktop` file so the example gets a real Dock icon on Linux/Wayland |
| `examples/timer/` | Seconds counter, pure HTML/CSS/JS with OCaml bindings |
| `examples/d3/` | Bar chart with a vendored D3.js (no bindings) |
| `examples/three/` | 3D shapes (WebGL) with a vendored three.js (no bindings) |
| `vendor/webview.h` | Vendored webview amalgamated single-header (0.12) |

The implementation deliberately uses **manual C stubs** rather than `ctypes`,
in order to make the two sensitive points explicit:

1. **`webview_run` is blocking** → `caml_release_runtime_system()` around the
   call, and `caml_acquire_runtime_system()` at the entry of each callback.
2. **Closure survival** → each closure passed to `bind` is registered via
   `caml_register_generational_global_root` so it is not collected.

## Requirements

- OCaml + dune (`opam install dune`)
- A C++ compiler
- The native dependencies:
  - **macOS**: WebKit / Cocoa (provided by the system)
  - **Linux**: `gtk+-3.0` + `webkit2gtk-4.1` (`-dev` packages)
  - **Windows**: WebView2 (install with nuget)

## Build & run

```sh
# Build and run the example (works from any directory)
dune exec examples/hellowv/hellowv.exe
```

The `webview.h` header is vendored in `vendor/` as webview's **amalgamated
single-header**: the entire C API and its C++ implementation are inlined into
one file, so there is nothing extra to fetch or build for webview itself (only
the system web engine is linked — see below).

The platform-specific C++ compile/link flags are detected automatically at
build time by `lib/config/discover.ml` (dune-configurator): the WebKit/Cocoa
frameworks on macOS, and the `gtk+-3.0` / `webkit2gtk-4.1` flags from
`pkg-config` on Linux. No manual editing of `lib/dune` is needed — just make
sure the `-dev` packages are installed on Linux (they are declared as the
package's opam `depexts`).

## Page assets

The example does not inline its HTML in OCaml: it loads the files in
`examples/hellowv/web/` (`index.html`, which references `style.css` and `app.js`) via
`Webview.navigate` with a `file://` URL. The OCaml bindings (`add`, `os_type`)
stay reachable from JS as `window.<name>(...)`.

The asset directory is resolved relative to the executable, so the example runs
from any working directory:

- **Dev** (`dune exec`): the files are read from the source tree.
- **Build tree**: `dune build` stages `web/` next to the binary (via the `all`
  alias in `examples/dune`), so `_build/.../examples/` is a self-contained
  bundle. The example is a dev artifact — it is **not** installed.

## Install

```sh
dune build @install
dune install --prefix /path/to/prefix owebview
```

This installs the **library** only. The `hellowv` example (its binary and its
`web/` assets) is a development build and is intentionally not installed into
the opam switch.

