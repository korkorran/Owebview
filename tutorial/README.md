<p align="center">
  <img src="https://raw.githubusercontent.com/korkorran/Owebview/main/logo.png" width="160" alt="owebview">
</p>
<h1 align="center">Owebview Tutorial</h1>
<p align="center"><b>Build native desktop apps in OCaml, with the web as your UI toolkit.</b></p>

## Welcome

Welcome! This tutorial walks you through [Owebview](https://github.com/korkorran/Owebview),
OCaml bindings to [webview](https://github.com/webview/webview), step by step.

Owebview opens a native window backed by the operating system's own web engine —
WebKit on macOS, WebKitGTK on Linux, WebView2 on Windows — and lets you fill it
with HTML, CSS and JavaScript. No Electron, no bundler, no packaged browser: a
single OCaml executable and a handful of static files.

Each step is a small, self-contained program. We start with a window that shows a
line of HTML, and finish with a full application whose UI *and* backend are both
written in OCaml. Along the way you will see how to ship on-disk assets, bridge
JavaScript and OCaml, run asynchronous work with Lwt, and give your app a proper
icon in the Dock.

**Prerequisites:** an OPAM switch with OCaml and Dune, plus the library itself:

```sh
opam install owebview
```

On Windows, install the Microsoft WebView2 package (`nuget install Microsoft.Web.WebView2`)
before the OPAM installation. On Unix, OPAM pulls in everything else.

The API reference lives in [`webview/webview.mli`](../webview/webview.mli), and the
finished programs of the [`examples/`](../examples/) directory are the natural
next reading once you are done here.

## Table of contents

| # | Step | What you learn |
|---|------|----------------|
| 01 | [Your first window](01-first-window.md) | `Webview.create`, `set_title`, `set_size`, `set_html`, `run`, `destroy` — the lifecycle of a window, from an inline HTML string. |
| 02 | [Real assets on disk](02-assets.md) | `Webview.navigate` to load an `index.html` with its CSS and images; locating them with `Webview.Utils.web_dir`; the `dune` file that stages `web/` next to the binary. |
| 03 | [The JavaScript ↔ OCaml bridge](03-js-bridge.md) | `Webview.bind` to expose OCaml functions as `window.f()` promises, `Webview.return` to answer them, `Webview.eval` to call into the page, `Webview.dispatch` to do it safely from another thread — and the matching `dune` setup. |
| 04 | [Asynchronous backend with Lwt](04-async-lwt.md) | Sharing the main thread between `Webview.run` and `Lwt_main.run`, wrapping bindings into Lwt handlers, and driving the page from a concurrent backend. Based on [`examples/timer/timer_lwt.ml`](../examples/timer/timer_lwt.ml). |
| 05 | [A 100% OCaml application](05-full-ocaml.md) | Writing the frontend in OCaml too, compiled with `js_of_ocaml` (`(modes js)`) and [Brr](https://erratique.ch/software/brr): calling bindings and registering JS-visible functions from OCaml. Based on [`examples/js_of_ocaml/`](../examples/js_of_ocaml/). |
| 06 | [Bonus: a Dock icon](06-app-icon.md) | `Webview_desktop.Icon.set_app_icon` on Windows, macOS and GTK, its timing constraints, and `Webview_desktop.Icon.set_app_id` plus a `.desktop` file for Wayland-based desktops. Introduces the companion library `owebview.desktop`. |

Ready? Start with [step 01](01-first-window.md).
