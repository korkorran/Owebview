# Examples

Build once, then run any of them — the assets are staged next to the binaries
by `dune build`, so `dune exec` alone is not enough:

```sh
dune build
dune exec examples/hellowv/hellowv.exe
```

| Example | Front-end | What it shows |
|---|---|---|
| [`random_generator/`](random_generator/) | JavaScript | The smallest complete app: an inline HTML string, one `Webview.bind` exposing OCaml's random number generator to a button. No assets, no files. |
| [`dapper_icon/`](dapper_icon/) | — | An application icon and nothing else: an inline HTML page, one PNG staged beside the binary, and `Webview_desktop.Icon`. The only example that locates its asset with `Locate_assets.exe_dir`, having no `web/` directory at all. `--install-icon` writes the `.desktop` entry Linux needs under Wayland, from OCaml rather than from a shell script. |
| [`hellowv/`](hellowv/) | JavaScript | The tour. Assets loaded from `web/`, three bindings (add, OS detection, native file picker), a Dock icon, and a native menu bar with accelerators. |
| [`timer/`](timer/) | JavaScript | A stopwatch driven from the page, paused and resumed from the terminal through `Webview.dispatch`. Two executables, `timer_posix` and `timer_lwt`, implementing the same thing with raw threads and with Lwt. |
| [`d3/`](d3/) | JavaScript | A rainfall bar chart with a vendored D3.js. No bindings at all — proof that a serious JS library drops straight into the window. |
| [`three/`](three/) | JavaScript | Rotating 3D shapes with a vendored three.js, over WebGL. Also binding-free. |
| [`chat_window/`](chat_window/) | OCaml | A message list rendered by an OCaml front-end. Messages are typed in the terminal — pseudonym, then text — and pushed into the page from a reader thread through `Webview.dispatch`. |
| [`file_reader/`](file_reader/) | OCaml | Pick a file with the native browser to show its path and contents, then save a copy of it under a new name. Uses all three of `Webview_desktop.Dialog`'s file dialogs and both outcomes of a binding promise — resolved and rejected. |
| [`menubar_calc/`](menubar_calc/) | OCaml | A calculator with no buttons: every operation is a menu bar item with a keyboard accelerator. Shows `Webview_desktop.Menu`, state held by the application and pushed to the page, and an in-page modal for the one thing the native dialogs cannot ask for — a number. |
| [`hellowv_ml/`](hellowv_ml/) | OCaml | The same app as `hellowv`, with the page's logic written in OCaml too — compiled by `js_of_ocaml` with [Brr](https://erratique.ch/software/brr), so both sides of the bridge are OCaml. |

Two of them have notes of their own: [`timer/README.md`](timer/README.md) on
using Owebview with Lwt, and [`hellowv_ml/README.md`](hellowv_ml/README.md)
on the OCaml front-end.

The [tutorial](../tutorial/) builds the same ideas up step by step, from a
first window to a complete application.
