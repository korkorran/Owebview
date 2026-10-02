# 04 — An asynchronous backend with Lwt

[← Previous: The JavaScript ↔ OCaml bridge](03-js-bridge.md) · [Table of contents](README.md) · [Next: A 100% OCaml application →](05-full-ocaml.md)

At the end of [step 03](03-js-bridge.md) we had a rule and a workaround: a
binding callback runs on the UI thread, so anything slow inside it freezes the
window — and the escape hatch was to spawn a raw `Thread` and call
`Webview.return` from there.

That works, but it does not scale to an application. Real backends wait on
several things at once: timers, sockets, subprocesses, files. This step gives
them a proper concurrency runtime — [Lwt](https://github.com/ocsigen/lwt) — and
shows how to make it live alongside the webview's own event loop.

The reference implementation is
[`examples/timer/timer_lwt.ml`](../examples/timer/timer_lwt.ml), with more notes
in [`examples/timer/README.md`](../examples/timer/README.md).

## The problem: two event loops

Two facts collide.

1. **`Webview.bind` is not Lwt-shaped.** Its handler must return `unit`, not
   `unit Lwt.t`. There is nowhere to hand a promise back to.
2. **Both `Webview.run` and `Lwt_main.run` are blocking event loops.** Each one
   owns its thread until it is done. They cannot take turns on the same thread.

So they get one thread each. And the assignment is not arbitrary:

> **The webview event loop keeps the process's main thread; Lwt moves to a
> spawned thread.**

Not the other way around. macOS requires the Cocoa/WebKit UI loop to run on the
process's main thread — detaching `Webview.run` to another thread and keeping
`Lwt_main.run` on the main one hangs. The arrangement below is the portable one.

## The `dune` file

```dune
(executable
 (name main)
 (libraries owebview owebview.desktop lwt.unix threads.posix))

(alias
 (name all)
 (deps
  (glob_files web/*)))
```

`lwt.unix` brings in Lwt together with its Unix bindings — `Lwt_unix`,
`Lwt_io` and, importantly here, `Lwt_preemptive`. `threads.posix` is what lets
us create the thread Lwt will run on. The `all` alias stages `web/` as in
[step 02](02-assets.md).

Install the dependency if you do not have it yet:

```sh
opam install lwt
```

## The shape of the program

```ocaml
let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "Async backend";
  Webview.set_size w ~width:640 ~height:480 Webview.Hint_none;

  (* ... bindings ... *)

  let index = Filename.concat (Webview_desktop.Locate_assets.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  (* Lwt gets its own thread; the webview keeps the main one. *)
  let _ : Thread.t = Thread.create (fun () -> Lwt_main.run (app w)) () in

  Webview.run w;
  Webview.destroy w
```

`app w` is your backend: a **long-lived** `unit Lwt.t`. This matters more than
it looks — if that promise resolves, `Lwt_main.run` returns, the Lwt loop stops,
and every later `run_in_main` has nowhere to go. Your application logic should
be something that keeps running for as long as the window is open.

## `lwt_bind` — from a JS call to an Lwt promise

The handler passed to `Webview.bind` runs on the UI thread and must return
`unit`. We need it to *start* an Lwt computation on the Lwt thread and come back
immediately. Six lines do it:

```ocaml
let lwt_bind w name (f : string -> string -> unit Lwt.t) =
  Webview.bind w name (fun id req ->
      Lwt_preemptive.run_in_main (fun () ->
          Lwt.return (Lwt.async (fun () -> f id req))))
```

Read it from the inside out:

- `f id req` is your handler — an ordinary Lwt computation.
- `Lwt.async` starts it and returns immediately, without waiting for it to
  finish. Fire-and-forget is what we want: the answer will come later, through
  `Webview.return`.
- `Lwt_preemptive.run_in_main` is the hop between threads. It takes a function
  and runs it **on the thread executing `Lwt_main.run`**, which is the only
  thread allowed to touch the Lwt scheduler.
- `Lwt.return` is there because `run_in_main` expects a function returning a
  promise; starting the task is all we do, so we wrap the `unit` immediately.

The net effect: the UI thread is released as fast as it can be, and the actual
work runs on the Lwt thread where sleeping, reading a socket or awaiting a
subprocess costs nothing.

Handlers then look like normal Lwt code:

```ocaml
lwt_bind w "fetch_report" (fun id req ->
    let name =
      match Scanf.sscanf_opt req "[%S]" (fun s -> s) with
      | Some s -> s
      | None -> "unknown"
    in
    let* () = Lwt_unix.sleep 2.0 in     (* cooperative: nothing is frozen *)
    Webview.return w id ~error:false
      ~result:(json_string (Printf.sprintf "report for %s" name));
    Lwt.return_unit)
```

Note the difference with the raw-thread version of [step 03](03-js-bridge.md):
`Lwt_unix.sleep 2.0` does not block a thread, it yields. A hundred concurrent
calls to `fetch_report` cost one thread, not a hundred.

`Webview.return` is called from the Lwt thread, which is fine — it is the one
function in the API explicitly safe to call from anywhere.

## Driving the page from Lwt

The other direction is unchanged from [step 03](03-js-bridge.md): the Lwt thread
is not the UI thread, so JavaScript calls go through `Webview.dispatch`.

```ocaml
let push w js = Webview.dispatch w (fun w -> Webview.eval w js)
```

Which makes a periodic push into the page a three-line Lwt loop:

```ocaml
let ticker w =
  let rec loop n =
    let* () = Lwt_unix.sleep 1.0 in
    push w (Printf.sprintf "setUptime(%d)" n);
    loop (n + 1)
  in
  loop 0
```

And the backend itself is just the composition of those long-lived tasks:

```ocaml
let app w =
  let* () = Lwt_io.printl "[lwt] event loop started" in
  Lwt.join [ ticker w; watch_something_else w ]
```

`Lwt.join` never resolves as long as one of its components runs, which gives us
the long-lived promise `Lwt_main.run` needs.

## Reading the terminal, the Lwt way

The bundled example wires the terminal to the page: each `<Enter>` pauses or
resumes the timer. It is a good illustration because it involves both directions
at once — a blocking-looking read that is really cooperative, and a JS call from
off the UI thread:

```ocaml
let terminal_loop w =
  let running = ref true in
  let rec loop () =
    let* line = Lwt_io.read_line_opt Lwt_io.stdin in
    match line with
    | None -> Lwt.return_unit                    (* EOF: stop listening *)
    | Some _ ->
        let cmd = if !running then "stop()" else "start()" in
        running := not !running;
        Webview.dispatch w (fun w -> Webview.eval w cmd);
        loop ()
  in
  loop ()
```

Compare it with the `threads.posix` version in
[`examples/timer/timer_posix.ml`](../examples/timer/timer_posix.ml), which does
the same thing with `input_line` on a dedicated thread. Same behaviour; the Lwt
one composes with everything else the backend is waiting on.

## Thread-safety, revisited

| Called from | What is safe |
|-------------|--------------|
| The UI thread — a binding callback, a `dispatch` callback, or before `run` | Everything. |
| The Lwt thread, or any other | `Webview.return` and `Webview.dispatch`. Route everything else through `dispatch`. |

A word about `Webview.terminate`. It is safe from a binding callback — that is
the UI thread — and the underlying library implements it with a dispatch on the
GTK backend. But it is not portably thread-safe: on Windows it posts a quit
message to the *calling* thread's queue, which does nothing useful when that
thread is not the UI one. From the Lwt thread, close the window like this:

```ocaml
Webview.dispatch w Webview.terminate
```

Only `webview_return` carries an explicit cross-thread guarantee upstream, so
`dispatch` is the rule and `return` the exception.

## Pitfalls

- **`Lwt_main.run` returning early.** If `app w` resolves — a `Lwt.return_unit`
  at the end of a sequence, a task that finishes — the Lwt loop stops silently.
  Bindings still fire, `run_in_main` then has no loop to hand work to, and the
  app appears to hang. Keep a task alive.
- **A binding that fires before the Lwt thread is up.** `run_in_main` needs
  `Lwt_main.run` to be running. Spawn the Lwt thread before `Webview.run`, as
  above, and there is a window of a few milliseconds at startup; if a page can
  call a binding that early, have the handler tolerate it.
- **Blocking calls on the Lwt thread.** `Unix.sleep`, `input_line`,
  `Unix.read` — any of them stalls the whole Lwt loop. Use the `Lwt_unix` /
  `Lwt_io` equivalents, or `Lwt_preemptive.detach` for code you cannot convert.
- **Exceptions swallowed by `Lwt.async`.** A handler that raises goes to
  `Lwt.async_exception_hook`, whose default behaviour terminates the program.
  Set it to something you can see:

  ```ocaml
  Lwt.async_exception_hook :=
    fun exn -> Printf.eprintf "lwt: %s\n%!" (Printexc.to_string exn)
  ```

- **A promise that is never settled.** Still true, and easier to do here: every
  path of an Lwt handler, including its error path, must reach a
  `Webview.return`. `Lwt.catch` around the body is a good habit.

## Exercises

1. Turn `fetch_report` into something real — read a file with `Lwt_io`, or query
   an HTTP endpoint — and reject the promise with `~error:true` when it fails.
2. Add a `cancel()` binding that stops the ticker, using an `Lwt_switch` or a
   simple `bool ref` the loop checks.
3. Fire ten concurrent `fetch_report` calls from the page and watch them all
   answer after roughly two seconds, not twenty. Then do the same against the
   raw-thread version of [step 03](03-js-bridge.md) to feel the difference.
4. Run [`examples/timer/timer_lwt.ml`](../examples/timer/timer_lwt.ml) and its
   `timer_posix` twin side by side:

   ```sh
   dune exec examples/timer/timer_lwt.exe
   ```

## What's next

The backend is now as expressive as any OCaml server. The frontend, though, is
still JavaScript. In [step 05](05-full-ocaml.md) we replace it: the page's logic
gets written in OCaml too, compiled to JavaScript with `js_of_ocaml`, so a
single language covers the whole application.
