# 02 — Real assets on disk

[← Previous: Your first window](01-first-window.md) · [Table of contents](README.md) · [Next: The JavaScript ↔ OCaml bridge →](03-js-bridge.md)

The inline HTML string of [step 01](01-first-window.md) got cramped fast, and it
cannot pull in a stylesheet or an image. In this step we move the interface into
real `.html`, `.css` and `.png` files, load it with `Webview.navigate`, and let
`Webview_desktop.Locate_assets.web_dir` find those files whether the program runs from the build
tree or from an installed location.

## The project layout

```
hello-owebview/
├── dune-project
├── dune
├── main.ml
└── web/
    ├── index.html
    ├── style.css
    └── logo.png
```

The `web/` name is not arbitrary: it is the directory `Webview_desktop.Locate_assets.web_dir`
looks for, so following the convention saves you from computing paths yourself.

## The page

`web/index.html` — an ordinary page, with ordinary *relative* links:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Hello Owebview</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <img src="logo.png" width="120" alt="logo" />
    <h1>Hello from OCaml</h1>
    <p>This page comes from real files on disk.</p>
  </body>
</html>
```

`web/style.css`:

```css
body {
  font-family: system-ui, sans-serif;
  text-align: center;
  padding-top: 2rem;
  color: #222;
  background: #fafafa;
}
h1 { font-weight: 600; }
```

Drop any image you like in `web/logo.png`.

## The OCaml side

`main.ml`:

```ocaml
let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "Hello Owebview";
  Webview.set_size w ~width:640 ~height:480 Webview.Hint_none;

  (* Locate web/index.html relative to the executable, not to the cwd. *)
  let index = Filename.concat (Webview_desktop.Locate_assets.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
```

That is the whole change: `set_html` becomes `navigate`, pointed at a `file://`
URL built from `Webview_desktop.Locate_assets.web_dir ()`.

## `Webview.navigate`

```ocaml
val navigate : t -> string -> unit
```

Loads a URL into the window. Four schemes are supported:

| Scheme | Use |
|--------|-----|
| `file://` | A page from the local filesystem — what we do here. |
| `http://`, `https://` | A remote page, or a local development server. |
| `data:` | An inline document encoded in the URL itself. |

Unlike `set_html`, the loaded document has a real base URL, so every relative
reference in the page — `style.css`, `logo.png`, `app.js` — is resolved against
the directory holding `index.html`. That is the whole point of this step.

Two things to keep in mind about the URL:

- **It must be absolute.** `file://web/index.html` is not a path relative to
  anything; the part after `file://` is read as an absolute filesystem path.
  This is why we build it from `web_dir ()`, which always returns an absolute
  directory.
- **It is a URL, not a path.** Characters that are special in URLs (spaces,
  `#`, `?`) need percent-encoding. It is rarely a problem in a build tree, but
  it can bite on a path like `/Users/me/My Projects/…`.

`navigate` can be called again at any point in the life of the window, including
from a callback, to swap the whole page.

## Finding the assets: `Webview_desktop.Locate_assets`

(This module is in `owebview.desktop`, hence the extra entry in the `dune`
file below.)

Why not just write `"file://" ^ "web/index.html"`, or use a relative path?
Because a relative path is resolved against the **current working directory**,
which is not where your program lives. Launch the binary by double-clicking it,
from a Dock icon, or from another directory, and the page vanishes.

The `Webview_desktop.Locate_assets` module resolves assets against the *executable* instead:

```ocaml
val exe_dir   : unit -> string
val asset_dir : unit -> string
val web_dir   : ?dir:string -> unit -> string
```

### `exe_dir`

The absolute path of the directory containing the running executable. Everything
else is built on it.

### `asset_dir`

The same, with one adjustment for development. Under `dune exec`, your binary
lives in `_build/<context>/…` while your source assets stay in the source tree —
they are two different directories. `asset_dir` strips the `_build/<context>/`
segment, mapping the build path back to the matching source directory. When the
executable is not under a `_build` directory, it returns `exe_dir` unchanged.

### `web_dir`

The directory to resolve web assets against — this is the one you will actually
call. It looks for an `index.html` in `exe_dir ()/web`, and uses that directory
if it finds one; otherwise it falls back to `asset_dir ()/web`, in the source
tree.

The build-tree copy comes first on purpose: it holds both the assets staged from
your sources *and* any **generated** ones — for instance an `app.js` produced by
`js_of_ocaml` in [step 05](05-full-ocaml.md), which exists nowhere in the source
tree. The fallback covers the case where nothing has been staged yet.

`web` is only the default name. If your assets live somewhere else, name the
directory and the same two-place lookup applies to it:

```ocaml
let index = Filename.concat (Locate_assets.web_dir ~dir:"assets" ()) "index.html"
```

Remember to match it in the `dune` alias below — `(glob_files assets/*)`.

Concretely, in this project:

```
after `dune build`:                 after `dune exec` alone (nothing staged):
exe_dir   = …/_build/default        exe_dir   = …/_build/default
asset_dir = …/hello-owebview        asset_dir = …/hello-owebview
web_dir   = …/_build/default/web    web_dir   = …/hello-owebview/web
```

Either way the page loads, which is exactly what you want while developing.

## The `dune` file

```dune
(executable
 (name main)
 (libraries owebview owebview.desktop))

; Stage the web/ assets next to the built binary, so the build tree is
; self-contained. See Webview_desktop.Locate_assets.web_dir.
(alias
 (name all)
 (deps
  (glob_files web/*)))
```

Two changes from [step 01](01-first-window.md). The stanza gains
`owebview.desktop`, the companion library where the asset-locating helper
lives, alongside the other things that address the system rather than the web
view — [step 06](06-app-icon.md) is where the rest of it shows up. And the new
`alias` below it.

Dune only copies a source file into `_build` when something depends on it, and
nothing in an `executable` stanza depends on your CSS. Attaching
`(glob_files web/*)` to the `all` alias — the one plain `dune build` builds —
tells Dune to stage the whole directory next to the binary. Your build tree then
contains a complete, runnable application:

```
_build/default/
├── main.exe
└── web/
    ├── index.html
    ├── style.css
    └── logo.png
```

Build and run:

```sh
dune build
dune exec ./main.exe
```

`glob_files` is not recursive. If you organise assets in subdirectories, use
`(glob_files_rec web/**)` instead — or list the extra directories explicitly.

## Shipping the assets

`web_dir` looks beside the executable first, and that rule is what makes a
release work: place the `web/` directory next to the installed binary — inside
the `.app` bundle on macOS, next to the `.exe` on Windows, in the same
installation directory on Linux — and the same code finds it, with no `_build`
in sight and no dependency on the working directory.

## A note on the `file://` origin

Loading resources referenced by the document — stylesheets, scripts, images,
fonts — works exactly as in a browser. Scripted network access does not:
`fetch()` and `XMLHttpRequest` against `file://` URLs run into the engine's
cross-origin rules and are commonly blocked, with WebKit being the strictest.

That is rarely a limitation in practice, because you have something better: the
data can come straight from OCaml through a binding, which is precisely what
[step 03](03-js-bridge.md) introduces. If you really do need a page that behaves
like a hosted one, serve `web/` over `http://localhost:<port>` and `navigate`
there instead.

## Exercises

1. Delete `_build` and run `dune exec ./main.exe` without a prior `dune build`.
   The page should still load — from the source tree this time. Print
   `Webview_desktop.Locate_assets.web_dir ()` to see which branch was taken.
2. Run the binary directly from another directory
   (`cd /tmp && …/_build/default/main.exe`). It keeps working, which a
   cwd-relative path would not.
3. Add a second page, `web/about.html`, and a link to it from `index.html`.
   Relative navigation inside the window works like a browser.

## What's next

The page is real now, but the conversation is one-way: OCaml hands over a
document and steps aside. In [step 03](03-js-bridge.md) we open the bridge —
`Webview.bind` to expose OCaml functions to JavaScript, `Webview.eval` to call
into the page, and `Webview.dispatch` to do it safely from another thread.
