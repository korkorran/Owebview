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
| [`hellowv/`](hellowv/) | JavaScript | The tour. Assets loaded from `web/`, three bindings (add, OS detection, native file picker), a Dock icon, and a native menu bar with accelerators. |
| [`timer/`](timer/) | JavaScript | A stopwatch driven from the page, paused and resumed from the terminal through `Webview.dispatch`. Two executables, `timer_posix` and `timer_lwt`, implementing the same thing with raw threads and with Lwt. |
| [`d3/`](d3/) | JavaScript | A rainfall bar chart with a vendored D3.js. No bindings at all — proof that a serious JS library drops straight into the window. |
| [`three/`](three/) | JavaScript | Rotating 3D shapes with a vendored three.js, over WebGL. Also binding-free. |
| [`chat_window/`](chat_window/) | OCaml | A message list rendered by an OCaml front-end. Messages are typed in the terminal — pseudonym, then text — and pushed into the page from a reader thread through `Webview.dispatch`. |
| [`file_reader/`](file_reader/) | OCaml | One button, the native file browser behind it. Picking a file shows its path and contents, and picking another replaces them. Uses `Webview_desktop.Dialog` and both outcomes of a binding promise — resolved and rejected. |
| [`js_of_ocaml/`](js_of_ocaml/) | OCaml | The same app as `hellowv`, with the page's logic written in OCaml too — compiled by `js_of_ocaml` with [Brr](https://erratique.ch/software/brr), so both sides of the bridge are OCaml. |

Two of them have notes of their own: [`timer/README.md`](timer/README.md) on
using Owebview with Lwt, and [`js_of_ocaml/README.md`](js_of_ocaml/README.md)
on the OCaml front-end.

The [tutorial](../tutorial/) builds the same ideas up step by step, from a
first window to a complete application.
