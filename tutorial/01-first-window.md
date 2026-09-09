# 01 — Your first window

[← Table of contents](README.md) · [Next: Real assets on disk →](02-assets.md)

Our starting point is the smallest useful Owebview program: a native window that
displays a page of HTML. Six function calls, no assets, no JavaScript bridge yet.

By the end of this step you will know the lifecycle of a webview — how one is
created, configured, run, and disposed of — and why the order of those calls
matters.

## Setting up the project

Create a directory for the tutorial project and add the two files Dune needs:

```sh
mkdir hello-owebview && cd hello-owebview
```

`dune-project`:

```dune
(lang dune 3.0)
```

`dune`:

```dune
(executable
 (name main)
 (libraries owebview))
```

The OPAM package is named `owebview` — that is what goes in `(libraries ...)` —
but the module it installs is called `Webview`. Every function we call below is
therefore `Webview.something`.

## The program

`main.ml`:

```ocaml
let () =
  (* 1. Create the webview instance. *)
  let w = Webview.create () in

  (* 2. Configure the native window. *)
  Webview.set_title w "My first Owebview window";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;

  (* 3. Give it something to render. *)
  Webview.set_html w
    {|<!doctype html>
      <html>
        <body style="font-family: system-ui; text-align: center">
          <h1>Hello from OCaml 👋</h1>
          <p>This page is rendered by the system web engine.</p>
        </body>
      </html>|};

  (* 4. Run the event loop — blocks until the window is closed. *)
  Webview.run w;

  (* 5. Release the resources. *)
  Webview.destroy w
```

Build and launch it:

```sh
dune exec ./main.exe
```

A native window opens, 480×320, titled *My first Owebview window*, showing your
HTML. Close it and the program exits.

## What each call does

### `Webview.create`

```ocaml
val create : ?debug:bool -> unit -> t
```

Creates the window and the browser widget inside it, and returns an opaque
handle `t`. Every other function takes that handle as its first argument.

The optional `~debug:true` enables the developer tools of the underlying engine
— the Web Inspector on macOS, the WebKit inspector on Linux, DevTools on
Windows — which you will want as soon as the page grows past a heading:

```ocaml
let w = Webview.create ~debug:true () in
```

Note that the window is not shown yet: nothing appears on screen until
`Webview.run` starts the event loop.

### `Webview.set_title`

```ocaml
val set_title : t -> string -> unit
```

Sets the text of the title bar. It can be called again at any time, including
from a callback while the app is running, to reflect the application's state.

### `Webview.set_size`

```ocaml
val set_size : t -> width:int -> height:int -> hint -> unit
```

Sets the size of the window in pixels. The `hint` decides how those numbers are
interpreted:

| Hint | Meaning |
|------|---------|
| `Webview.Hint_none` | The initial size; the user can resize the window freely. |
| `Webview.Hint_min` | The minimum size; the window cannot be made smaller. |
| `Webview.Hint_max` | The maximum size; the window cannot be made larger. |
| `Webview.Hint_fixed` | The exact size; the window is not resizable at all. |

`Hint_none` is the usual choice for a first window. To pin a small utility panel
to one size, use `Hint_fixed`; to keep a resizable window from collapsing to
nothing, call `set_size` twice — once with `Hint_none` for the initial size, once
with `Hint_min` for the floor.

### `Webview.set_html`

```ocaml
val set_html : t -> string -> unit
```

Loads an HTML string as the current document. It is the fastest way to get
pixels on screen, and OCaml's `{|...|}` quoted string literals make it painless:
no escaping is needed, so quotes, backslashes and newlines can be written
verbatim.

Inline HTML is fine for a splash screen or a tiny panel, but relative URLs have
no base to resolve against — `<link href="style.css">` or `<img src="logo.png">`
will not load. Real assets are the subject of [step 02](02-assets.md).

### `Webview.run`

```ocaml
val run : t -> unit
```

Shows the window and runs the native event loop. **It blocks** until the window
is closed (or until something calls `Webview.terminate`), so it is normally the
last statement of your program before cleanup.

Two consequences worth remembering from the start:

- `run` **must be called on the main thread**. macOS in particular requires
  Cocoa's event loop to own the process's main thread. When you later need a
  concurrent backend, it is the *other* work that moves to another thread, not
  `run` — that is exactly what [step 04](04-async-lwt.md) is about.
- While `run` blocks, it releases the OCaml runtime lock, so other OCaml threads
  keep making progress. To touch the webview from one of them, use
  `Webview.dispatch` ([step 03](03-js-bridge.md)).

### `Webview.destroy`

```ocaml
val destroy : t -> unit
```

Destroys the window and frees the associated native resources, along with any
OCaml closures the webview was holding alive. Call it once, after `run` has
returned; the handle must not be used afterwards.

## Closing the window from OCaml

Closing the window with the title bar button ends `run` on its own. To do the
same from code — a *Quit* button, a finished task, a timeout — call:

```ocaml
val terminate : t -> unit
```

It stops the loop started by `run`, which then returns and lets your program
proceed to `destroy`. It is safe to call from a binding callback, which is how
you will wire it to a button in the next steps.

## Checking your setup

The library version can be queried without opening any window, which makes it a
handy first thing to print when something looks off:

```ocaml
let v = Webview.version () in
Printf.printf "using webview %s\n%!" v.Webview.version_number
```

## Exercises

1. Pass `~debug:true` to `create`, relaunch, and open the inspector
   (right-click → *Inspect Element*, where the platform offers it).
2. Swap `Hint_none` for `Hint_fixed` and try to resize the window.
3. Add a `<button>` to the HTML and give it an `onclick` that changes the page
   text. Everything inside the page still works as it would in a browser — only
   the *OCaml* side of the conversation is missing so far.

## What's next

The inline HTML string is already cramped. In
[step 02](02-assets.md) we move the page into real `.html`, `.css` and image
files, load them with `Webview.navigate`, and let `Webview.Utils.web_dir` find
them whether the program runs from the build tree or from an installed location.
