# Using Owebview with Lwt

`Webview.bind` is not directly compatible with Lwt: its handler must return
`unit`, not `unit Lwt.t`. This is because `Webview.run` starts a **blocking**
event loop, and the functions registered with `bind` are called from inside
that loop.

So you have two event loops that cannot share a thread — the webview one and the
Lwt one. Run each on its own thread:

1. **The main thread runs the webview event loop** (`Webview.run`). On macOS
   this is mandatory: the Cocoa/WebKit UI loop must run on the process's main
   thread. (Running it on another thread hangs.)
2. **A dedicated thread runs the Lwt event loop** (`Lwt_main.run`).

> ⚠️ Do *not* do the opposite (detach `Webview.run` and keep `Lwt_main.run` on
> the main thread): it fails on macOS for the reason above.

## Bootstrapping

Create and run the webview on the main thread, and spawn a thread for Lwt:

```ocaml
let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "Hello from OCaml";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;
  (* ... bindings, navigate ... *)

  (* Lwt runs on its own thread; the webview keeps the main thread. *)
  let _ = Thread.create (fun () -> Lwt_main.run (app_logic w)) () in

  Webview.run w;
  Webview.destroy w
```

`app_logic w` is a long-lived `unit Lwt.t` (your application; it must not resolve
immediately, otherwise `Lwt_main.run` returns and the Lwt loop stops).

In `dune`, this needs both libraries: `(libraries webview lwt.unix threads.posix)`.

## Calling Lwt code from a binding: `lwt_bind`

A `bind` handler runs on the webview (main) thread. Use `lwt_bind` to hop onto
the Lwt thread and run an Lwt handler there, without blocking the UI loop:

```ocaml
(* Runs [f id req] on the thread executing Lwt_main.run (the dedicated Lwt
   thread). [run_in_main] hands the work over; [Lwt.async] makes it
   fire-and-forget, so the webview loop is not blocked while [f] runs. *)
let lwt_bind : Webview.t -> string -> (string -> string -> unit Lwt.t) -> unit =
 fun w name f ->
  Webview.bind w name (fun id req ->
      Lwt_preemptive.run_in_main (fun () ->
          Lwt.return (Lwt.async (fun () -> f id req))))

lwt_bind w "add" (fun id req ->
    let result =
      match Scanf.sscanf_opt req "[%d,%d]" (fun a b -> a + b) with
      | Some n -> string_of_int n
      | None -> "null"
    in
    Webview.return w id ~error:false ~result;
    Lwt.return_unit)
```

## Calling the UI from the Lwt thread: `dispatch`

The other direction — running code on the webview thread from the Lwt thread —
uses `Webview.dispatch`:

```ocaml
Webview.dispatch w (fun w -> Webview.eval w "/* JS to run on the UI thread */")
```

## Thread-safety

These functions are safe to call from a thread other than the webview loop:

- `Webview.return`
- `Webview.dispatch`

A complete, working example is
[`examples/timer/timer_lwt.ml`](timer_lwt.ml).
