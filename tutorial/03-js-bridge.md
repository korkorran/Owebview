# 03 — The JavaScript ↔ OCaml bridge

[← Previous: Real assets on disk](02-assets.md) · [Table of contents](README.md) · [Next: Asynchronous backend with Lwt →](04-async-lwt.md)

So far OCaml has been a launcher: it opens a window, hands over a document, and
steps aside. This step opens the two-way channel that makes Owebview an
*application* framework rather than a viewer.

Four functions do the work:

| Direction | Function | What it does |
|-----------|----------|--------------|
| JS → OCaml | `Webview.bind` | Exposes an OCaml function as `window.name(...)`, returning a JS `Promise`. |
| OCaml → JS | `Webview.return` | Resolves (or rejects) the promise of a pending call. |
| OCaml → JS | `Webview.eval` | Runs a snippet of JavaScript in the current page. |
| OCaml → JS | `Webview.init` | Injects JavaScript to run on every page load, before the page's own scripts. |

Plus one that is not about direction but about threads — `Webview.dispatch` —
and which you will need as soon as any work happens off the UI thread.

We will build a window with three OCaml-backed buttons and a clock that OCaml
pushes into the page once a second.

## The project

```
bridge-demo/
├── dune-project
├── dune
├── main.ml
└── web/
    ├── index.html
    ├── style.css
    └── app.js
```

`dune`:

```dune
(executable
 (name main)
 (libraries owebview owebview.desktop threads.posix unix yojson))

(alias
 (name all)
 (deps
  (glob_files web/*)))
```

Compared with [step 02](02-assets.md), only the libraries changed.
`yojson` is the new one: both halves of the bridge are JSON, and the section
"Speaking JSON" below says why OCaml's `Printf` and `Scanf` cannot stand in
for it.
`threads.posix` gives us the background thread that drives the clock, and `unix`
the wall-clock time. The `all` alias still stages `web/` next to the binary, as
explained in the previous step. Nothing about the *bridge* itself needs an extra
library: `bind`, `eval` and `dispatch` all come from `owebview`.

## The OCaml side

`main.ml`:

```ocaml
let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "The bridge";
  Webview.set_size w ~width:640 ~height:480 Webview.Hint_none;

  (* window.add(a, b) -> Promise<number> *)
  Webview.bind w "add" (fun id req ->
      let result =
        match Yojson.Safe.from_string req with
        | `List [ `Int a; `Int b ] -> string_of_int (a + b)
        | _ | (exception Yojson.Json_error _) -> "null"
      in
      Webview.return w id ~error:false ~result);

  (* window.greet(name) -> Promise<string>, rejected on a bad argument. *)
  Webview.bind w "greet" (fun id req ->
      match Yojson.Safe.from_string req with
      | `List [ `String name ] ->
          let result =
            Yojson.Safe.to_string (`String (Printf.sprintf "Hello, %s!" name))
          in
          Webview.return w id ~error:false ~result
      | _ | (exception Yojson.Json_error _) ->
          Webview.return w id ~error:true
            ~result:
              (Yojson.Safe.to_string
                 (`String "greet expects one string argument")));

  (* window.quit() -> closes the window from the page. *)
  Webview.bind w "quit" (fun _id _req -> Webview.terminate w);

  let index = Filename.concat (Webview_desktop.Locate_assets.assets_dir "web") "index.html" in
  Webview.navigate w ("file://" ^ index);

  (* A background thread pushes the time into the page every second. It is not
     the UI thread, so the call goes through [dispatch]. *)
  ignore
    (Thread.create
       (fun () ->
         while true do
           Thread.delay 1.0;
           let t = Unix.localtime (Unix.time ()) in
           let now =
             Printf.sprintf "%02d:%02d:%02d" t.Unix.tm_hour t.Unix.tm_min
               t.Unix.tm_sec
           in
           let js =
             Printf.sprintf "setClock(%s)" (Yojson.Safe.to_string (`String now))
           in
           Webview.dispatch w (fun w -> Webview.eval w js)
         done)
       ());

  Webview.run w;
  Webview.destroy w
```

## The page

`web/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>The bridge</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <h1>OCaml ↔ JavaScript</h1>
    <p class="clock" id="clock">--:--:--</p>
    <div class="actions">
      <button id="btn-add">add(20, 22)</button>
      <button id="btn-greet">greet("world")</button>
      <button id="btn-bad">greet() — rejected</button>
      <button id="btn-quit">quit</button>
    </div>
    <pre id="out"></pre>
    <script src="app.js"></script>
  </body>
</html>
```

`web/app.js`:

```js
// The bindings declared from OCaml are plain functions on `window`, and each
// one returns a Promise.
const out = document.querySelector("#out");
const show = (value) => { out.textContent = String(value); };

document.querySelector("#btn-add").addEventListener("click", async () => {
  const sum = await add(20, 22);   // resolves with the number 42
  show(`add(20, 22) = ${sum}`);
});

document.querySelector("#btn-greet").addEventListener("click", () => {
  greet("world").then(show);
});

document.querySelector("#btn-bad").addEventListener("click", () => {
  greet().catch((err) => show(`rejected: ${err}`));
});

document.querySelector("#btn-quit").addEventListener("click", () => quit());

// Called from OCaml through Webview.eval — so it must live on `window`.
window.setClock = (text) => {
  document.querySelector("#clock").textContent = text;
};
```

Build and run it:

```sh
dune build
dune exec ./main.exe
```

## `Webview.bind` — calling OCaml from JavaScript

```ocaml
val bind : t -> string -> (string -> string -> unit) -> unit
```

`Webview.bind w "add" f` makes `window.add(...)` available to the page. Calling
it from JavaScript returns a `Promise` and invokes `f id req` on the OCaml side,
where:

- **`id`** identifies this particular call. It is the token you must hand back
  to `Webview.return` to settle the promise the page is waiting on. Treat it as
  opaque, and never reuse it: one `id`, one answer.
- **`req`** is the argument list, **as a JSON array in a string**. `add(20, 22)`
  arrives as `"[20,22]"`, `greet("world")` as `"[\"world\"]"`, and a call with
  no arguments as `"[]"`.

A binding is not a function that returns a value; it is a callback that must
*eventually* answer. Nothing forces that answer to come immediately, or even
from the same thread — which is exactly what makes long-running work possible
(and is the subject of [step 04](04-async-lwt.md)). But a call that is never
answered leaves a promise pending in the page forever.

Two rules worth knowing before you hit them:

- Binding a name twice raises `Failure`. Use `Webview.unbind w "name"` first if
  you really mean to replace it.
- The name becomes a property of `window`, so it must not collide with one that
  already exists — `print`, `close`, `open`, `name`, `status` are all taken, and
  the page will throw `Property "print" already exists` when the binding is
  installed. This is why the bundled timer example calls its binding
  `print_time` rather than `print`.

Bindings can be added and removed while the app runs, but the usual place is
before `navigate`, so they are in place by the time the page's scripts run.

## `Webview.return` — answering the page

```ocaml
val return : t -> string -> error:bool -> result:string -> unit
```

`Webview.return w id ~error ~result` settles the promise of the call `id`:
`~error:false` resolves it with `result`, `~error:true` rejects it with
`result` as the reason (what `.catch(err => ...)` receives).

**`result` is JSON text, not a value.** It is parsed on the JavaScript side, so
what you pass must be a complete JSON document:

| You want JS to see | Pass as `~result` |
|--------------------|-------------------|
| `42` | `"42"` |
| `"hello"` | `"\"hello\""` — i.e. `Printf.sprintf "%S" "hello"` |
| `true` | `"true"` |
| `null` | `"null"` |
| `{ok: true, n: 3}` | `"{\"ok\":true,\"n\":3}"` |
| `undefined` | `""` (the empty string) |

Passing a bare `"hello"` — without the quotes *inside* the string — is the
classic first mistake: it is not valid JSON, and the promise is rejected with
`Failed to parse binding result as JSON` instead of resolving.

`Webview.return` is safe to call from any thread: internally it schedules the
reply on the UI thread for you. This is a deliberate exception — everything
else in the API is not.

## Speaking JSON

The bridge is a text protocol in **both** directions: `req` arrives as JSON,
`result` leaves as JSON. So both ends need a JSON library — here
[Yojson](https://github.com/ocaml-community/yojson), which is why it is in the
`dune` file above.

The tempting alternative is `Printf.sprintf "%S"` to encode and
`Scanf.sscanf_opt req "[%S]"` to decode. It is small, dependency-free, and
wrong in both directions, for the same underlying reason: `Printf` and `Scanf`
speak the syntax of **OCaml** literals, not JSON's.

| | What goes wrong |
|---|---|
| `Printf "%S"` | escapes non-ASCII bytes in decimal — `"café"` becomes `"caf\195\169"`, which JSON rejects, and the promise fails with a parse error |
| `Scanf "%S"` | does not know `\u00e9`, JSON's own spelling, and expects OCaml's `\233` instead |
| `"[%S]"` | matches a request holding exactly one string and nothing else: `["Bob","x"]` and `["Bob",42]` both fail |

With Yojson, encoding is one call and decoding is a pattern match:

```ocaml
Yojson.Safe.to_string (`String "Hello")        (* -> "\"Hello\"" *)

match Yojson.Safe.from_string req with
| `List [ `String name ] -> ...
| _ | (exception Yojson.Json_error _) -> ...
```

One shape to watch when matching numbers: **JavaScript has a single number
type, and `JSON.stringify` writes `42`, never `42.0`.** A whole number
therefore arrives as `` `Int `` even when the page meant a float, so a binding
that accepts decimals has to match both:

```ocaml
| `List [ `Int n ]   -> use (float_of_int n)
| `List [ `Float n ] -> use n
```

## `Webview.eval` and `Webview.init` — calling JavaScript from OCaml

```ocaml
val eval : t -> string -> unit
val init : t -> string -> unit
```

`eval` runs a snippet in the page as it is right now. It is fire-and-forget:
there is no return value, and no error is reported back to OCaml. To get an
answer, have the JavaScript call one of your bindings.

Note that `eval` is only useful once something exists to call — which is why our
`app.js` assigns `window.setClock`. A `const` or `function` declared at the top
level of a module or of an ordinary script is not automatically reachable this
way; putting it on `window` makes the contract explicit.

`init` registers a snippet that runs **on every page load, before the page's own
scripts**. It is the right place for anything the page should be able to assume
exists from its very first line — a configuration object, a small shim, a logger:

```ocaml
Webview.init w
  {|window.APP = { version: "1.0", platform: "ocaml" };|};
```

Call `init` before `navigate`; it applies to loads that happen afterwards, not to
the document already on screen.

Both take JavaScript source as a string, so anything you interpolate must be
escaped as JavaScript. Building `eval` snippets by string concatenation with
user data is the same injection hazard it is on the web; go through a JSON
encoder, as `setClock(%s)` does above with `Yojson.Safe.to_string`.

## `Webview.dispatch` — the threading rule

```ocaml
val dispatch : t -> (t -> unit) -> unit
```

The rule is short: **the webview may only be driven from the UI thread** — the
thread that called `Webview.run`. `eval`, `set_title`, `navigate`, `set_html`,
`terminate` and friends all assume it.

`dispatch w f` schedules `f` to run once on that thread, and is safe to call
from anywhere. That is why the clock thread above does not call `eval` directly:

```ocaml
Webview.dispatch w (fun w -> Webview.eval w js)
```

Note the shadowing: the callback receives the handle as its argument, which is
the idiom the examples use. Any exception raised inside `f` is dropped — there
is no OCaml handler on the native stack to catch it — so handle your own errors
inside the callback.

To summarise:

| Called from | What is safe |
|-------------|--------------|
| The UI thread (a binding callback, a `dispatch` callback, before `run`) | Everything. |
| Any other thread | `Webview.return` and `Webview.dispatch` — nothing else. |

There is a second, subtler rule that follows from the same fact: **a binding
callback runs on the UI thread**, so blocking inside it freezes the window.
`Thread.delay`, a synchronous HTTP request, a long computation — all of them
stall the event loop and the interface goes unresponsive. Move the work to
another thread and call `Webview.return` from there when it is done:

```ocaml
Webview.bind w "slow" (fun id _req ->
    ignore
      (Thread.create
         (fun () ->
           Thread.delay 2.0;                       (* off the UI thread *)
           Webview.return w id ~error:false ~result:"null")
         ()))
```

That pattern is exactly what [`examples/timer/timer_posix.ml`](../examples/timer/timer_posix.ml)
does, and [step 04](04-async-lwt.md) replaces the raw threads with Lwt.

## `Webview.unbind`

```ocaml
val unbind : t -> string -> unit
```

Removes a binding and deletes the property from `window`; it raises `Failure` if
no such binding exists. You rarely need it, but it matters for memory: `bind`
keeps your closure alive as a GC root for as long as the binding exists.
`unbind` releases it, and so does `Webview.destroy` for every binding still
registered — which is one more reason to call `destroy` rather than just letting
the program exit.

## Pitfalls

- **A pending promise that never settles.** Every path through a binding must
  reach a `Webview.return` — including the error paths.
- **`result` that is not JSON.** See the table above; the symptom is a rejected
  promise with a parse error.
- **A blocked UI thread.** If the window freezes while OCaml works, the work is
  on the wrong thread.
- **`eval` from a background thread.** Wrap it in `dispatch`.
- **A binding name already on `window`.** Rename it.
- **A binding declared after the page used it.** Bind before `navigate`.

With `~debug:true`, the inspector's console is where all of this shows up:
rejected promises, missing functions and JSON errors are all reported there.

## Exercises

1. Add a `read_file(path)` binding that returns the contents of a file as a JSON
   string, and reject the promise with a message when the file does not exist.
2. Make the clock stoppable: add a `toggle_clock()` binding that flips a `bool
   ref` the background thread reads.
3. Feed `greet` a non-ASCII name (`greet("café")`) and watch it round-trip.
   Then swap the `Yojson.Safe.to_string` on the reply for
   `Printf.sprintf "%S"` and watch the promise reject instead: the decimal
   escapes it emits are not JSON, and the page never sees your answer.

## What's next

Our slow work ran on a raw `Thread`. In [step 04](04-async-lwt.md) we give the
backend a real concurrency story: Lwt on one thread, the webview event loop on
the other, and bindings whose handlers are ordinary Lwt promises.
