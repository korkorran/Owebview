# 06 — Bonus: an icon in the Dock

[← Previous: A 100% OCaml application](05-full-ocaml.md) · [Table of contents](README.md)

Your application works. It also shows the generic executable icon in the Dock,
the taskbar and the window switcher, which is the one detail that keeps giving
away that it is "a binary that opens a window" rather than an app.

Two functions fix that, and they do quite different things:

| Function | Scope | Platforms |
|----------|-------|-----------|
| `Webview.Icon.set_app_icon` | Sets an icon from an image file | macOS, Windows, Linux/GTK3 |
| `Webview.Icon.set_app_id` | Declares a process-wide application id | Linux only (no-op elsewhere) |

Both live in the `Webview.Icon` submodule — like `Webview.Utils` in
[step 02](02-assets.md), it groups what is not part of the webview API itself.
The signatures below are written as they appear inside it.

On macOS and Windows the first one is all you need. On Linux the answer depends
on whether the session is X11 or Wayland — and under Wayland, `set_app_icon`
alone will do nothing at all. That is the interesting part of this step.

The reference implementation is
[`examples/hellowv/hellowv.ml`](../examples/hellowv/hellowv.ml), together with
its [`install-desktop-entry.sh`](../examples/hellowv/install-desktop-entry.sh).

## `Webview.Icon.set_app_icon`

```ocaml
val set_app_icon : t -> string -> unit
```

It takes a path to an image file. What it actually sets depends on the backend:

| Platform | What it sets | Notes |
|----------|--------------|-------|
| **macOS** | The Dock icon, via `NSApp setApplicationIconImage:` | Application-global — the `t` argument is ignored. Timing matters, see below. |
| **Windows** | The window icon, via `WM_SETICON` | The file is decoded with WIC, so `.png`, `.jpg`, `.bmp`, `.gif`, `.tif` and `.ico` all work; it is rescaled to the system's large and small icon metrics. |
| **Linux / GTK 3** | The window icon (taskbar, switcher), via `gtk_window_set_icon_from_file` | Under X11 this becomes the `_NET_WM_ICON` property. Under Wayland, see below. |
| **Linux / GTK 4** | Nothing | GTK 4 removed per-window icon-from-file; the `.desktop` route is the only one. |
| Anything else | Nothing | A silent no-op. |

It **raises `Failure`** when the image cannot be loaded — a missing file, an
unreadable format — so guard it if the icon is optional:

```ocaml
let icon = Filename.concat (Webview.Utils.web_dir ()) "hello.png" in
if Sys.file_exists icon then Webview.Icon.set_app_icon w icon
```

Note where the icon lives: next to the web assets, found with
`Webview.Utils.web_dir ()` exactly as `index.html` was in
[step 02](02-assets.md). Same reasoning, same benefit — it works from the build
tree and from an installed location, and it does not depend on the working
directory.

A single square PNG of 512×512 is the practical choice: every backend accepts
it, and each one downscales to whatever size it needs.

## The macOS timing trap

This is the one that costs people an afternoon:

```ocaml
(* Wrong: nothing happens. *)
Webview.Icon.set_app_icon w icon;
Webview.run w
```

The process only becomes a *regular*, Dock-visible application once Cocoa has
finished launching — inside `applicationDidFinishLaunching:`, which fires
**after** `Webview.run` has started the loop. Setting the icon before that point
means setting it on an application that has no Dock tile yet, and the call is
quietly ignored.

The fix is the thread tool from [step 03](03-js-bridge.md), used for its *timing*
rather than for thread safety. `Webview.dispatch` schedules work on the UI
thread, and dispatched callbacks are processed once the loop is running — that
is to say, once the app is active:

```ocaml
let icon = Filename.concat (Webview.Utils.web_dir ()) "hello.png" in
if Sys.file_exists icon then
  Webview.dispatch w (fun w -> Webview.Icon.set_app_icon w icon);

Webview.run w
```

The call is written *before* `run`, but it executes *after* it starts. This is
the form the bundled examples use, and it is harmless on the other platforms —
the icon is simply set a few milliseconds later.

## Linux: `set_app_icon` is not enough

```ocaml
val set_app_id : string -> unit
```

Note the signature: no `t`. It is process-wide, and it must be called **before**
`Webview.create`, so that it applies to the first window that gets realized.

```ocaml
let () =
  Webview.Icon.set_app_id "hellowv";     (* before create *)
  let w = Webview.create () in
  ...
```

On Linux it calls `g_set_prgname`, which becomes:

- the **`WM_CLASS`** class name under X11, and
- the toplevel's **`app_id`** under Wayland.

On every other backend it does nothing.

### Why this matters

Under X11, a window carries its own icon as a property, and `set_app_icon` sets
it. Under native Wayland — GNOME's default for years now — **that property does
not exist**. There is no protocol for a window to hand the compositor a bitmap.
Instead, the shell takes the window's `app_id`, looks for an installed
`.desktop` file that matches, and takes the icon from there.

So the chain under Wayland is:

```
Webview.Icon.set_app_id "hellowv"
        │  (becomes the Wayland app_id)
        ▼
  hellowv.desktop          ← installed in ~/.local/share/applications/
        │  matched by its filename id or its StartupWMClass=
        ▼
     Icon=/path/to/hello.png
```

`set_app_icon` is not useless on Linux — it still gives you the window icon
under X11 and GTK 3 — but it cannot be the whole answer. Call both.

### The `.desktop` file

A minimal entry, installed in `~/.local/share/applications/` for the current
user (or `/usr/share/applications/` system-wide):

```ini
[Desktop Entry]
Type=Application
Name=Hello WebView
Comment=An owebview application
Exec=/path/to/hellowv.exe
Icon=/path/to/hello.png
StartupWMClass=hellowv
Terminal=false
Categories=Development;
```

The line that does the work is `StartupWMClass=hellowv` — it must match the
string you passed to `Webview.Icon.set_app_id`. (A shell will also match the
`.desktop` file's own id, i.e. its filename, so naming the file `hellowv.desktop`
achieves the same thing; `StartupWMClass` is the explicit and more reliable
form.)

`Icon=` takes either an absolute path or a name resolved from the icon theme.
An absolute path is the simplest thing that works; a properly packaged
application installs its icon into the hicolor theme and refers to it by name.

Some desktops cache the applications directory, so finish with:

```sh
update-desktop-database ~/.local/share/applications
```

[`examples/hellowv/install-desktop-entry.sh`](../examples/hellowv/install-desktop-entry.sh)
does all of this for the bundled example, and undoes it with `--uninstall`:

```sh
./examples/hellowv/install-desktop-entry.sh
dune exec examples/hellowv/hellowv.exe     # now with a real Dock icon
```

## Putting it together

```ocaml
let () =
  (* Process-wide, Linux-only, and it must come before [create]. *)
  Webview.Icon.set_app_id "hellowv";

  let w = Webview.create ~debug:true () in
  Webview.set_title w "Hello from OCaml";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;

  (* Dispatched, so that on macOS it runs once the app is active. *)
  let icon = Filename.concat (Webview.Utils.web_dir ()) "hello.png" in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview.Icon.set_app_icon w icon);

  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
```

Six lines, and they cover all three platforms.

## Beyond the library: real packaging

`set_app_icon` exists so that a plain executable gets a decent icon. A
*distributed* application usually goes further, and that part is outside
Owebview's scope:

- **macOS** — ship a `.app` bundle. Its `Info.plist` names an `.icns` file, and
  the system uses it in the Finder, in the Dock and in Spotlight, before your
  code even runs. `set_app_icon` then becomes optional, or a way to show state
  (a badge, a different icon while working).
- **Windows** — embed the icon as a resource in the `.exe`, so Explorer shows it
  too. `WM_SETICON` only affects a running window.
- **Linux** — install a `.desktop` file and a themed icon through your package,
  which is exactly what the script above imitates for a single user.

Think of these two functions as what makes the app look right *while it runs*;
packaging is what makes it look right *before* it runs.

## Checklist

| Symptom | Likely cause |
|---------|--------------|
| Nothing happens on macOS | The call was not dispatched, so it ran before the app became active. |
| `Failure "set_app_icon: …"` | Bad path, or a format the platform's decoder cannot read. Guard with `Sys.file_exists`. |
| Works on X11, not on Wayland | Expected. Add `set_app_id` **and** an installed `.desktop` file. |
| Nothing happens on Linux at all | Possibly GTK 4, where the call is a no-op. The `.desktop` route is the only one. |
| The `.desktop` file is ignored | `StartupWMClass` does not match the `set_app_id` string, or the database needs `update-desktop-database`. |
| The icon looks blurry | Provide a larger source image; each backend downscales. |

## Exercises

1. Add an icon to the application you built in [step 05](05-full-ocaml.md), and
   verify that it survives a `dune build` — the file has to be staged by the
   `all` alias, like every other asset in `web/`.
2. Make the icon reflect state: call `set_app_icon` from a binding to swap
   between two images while a task runs. (macOS shows this best, since its icon
   is application-global.)
3. On Linux, run the app, install the `.desktop` file, and run it again. If you
   are on GNOME, check which session you are in with
   `echo $XDG_SESSION_TYPE` and see how the behaviour differs between `x11` and
   `wayland`.

## The end — and where to go next

That is the tour: a window, real assets, the bridge, an asynchronous backend, a
frontend in OCaml, and the polish on top. Everything else is ordinary OCaml and
ordinary web development.

Worth reading next:

- [`lib/webview.mli`](../lib/webview.mli) — the complete API, well commented.
  A few things this tutorial did not need: `Webview.get_window` and
  `Webview.get_native_handle` for platform-specific FFI (a native file dialog,
  for instance), and `Webview.version`.
- [`examples/`](../examples/) — the bundled programs, including the two the
  tutorial did not lean on: [`d3`](../examples/d3/) and
  [`three`](../examples/three/), which show that a serious JavaScript library
  drops straight into an Owebview window.
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — how the binding itself is put
  together, if you want to hack on it.

The project is developed and tested mainly on macOS, so reports about building
and running it on Linux distributions are especially welcome — see the
*Contributing* section of the [main README](../README.md).
