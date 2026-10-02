# 05 — A 100% OCaml application

[← Previous: Asynchronous backend with Lwt](04-async-lwt.md) · [Table of contents](README.md) · [Next: Bonus, a Dock icon →](06-app-icon.md)

Everything so far has been OCaml on one side of the bridge and JavaScript on the
other. This step removes the JavaScript: the page's logic is written in OCaml
too, compiled to `app.js` by
[js_of_ocaml](https://github.com/ocsigen/js_of_ocaml), with
[Brr](https://erratique.ch/software/brr) as the browser API.

Nothing about Owebview changes. The window still loads an `index.html`, still
exposes bindings with `Webview.bind`, still pushes into the page with
`Webview.eval`. What changes is who writes `app.js`: Dune does.

The reference implementation is
[`examples/js_of_ocaml/`](../examples/js_of_ocaml/).

```sh
dune exec examples/js_of_ocaml/hellowv.exe
```

## The project layout

```
full-ocaml/
├── dune-project
├── dune              ← the backend executable (native)
├── main.ml
├── utils.ml
└── web/
    ├── dune          ← the frontend executable (js_of_ocaml)
    ├── app.ml
    ├── index.html
    └── style.css
```

Two executables, two Dune stanzas, two compilation targets — one native binary
that opens the window, one JavaScript bundle that runs inside it. The `web/`
directory holds the second one, next to the HTML that loads it.

Note what is *not* there: `app.js`. It is generated.

## The frontend `dune`

`web/dune`:

```dune
(executable
 (name app)
 (libraries brr)
 (js_of_ocaml
  (flags
   (:standard --target-env browser)))
 (modes js)
 (link_flags
  (:standard -no-check-prims)))

(rule
 (targets app.js)
 (deps app.bc.js)
 (action
  (copy %{deps} %{targets})))
```

Four things are happening:

- **`(modes js)`** tells Dune to compile this executable to JavaScript instead
  of to a native binary. That is the whole js_of_ocaml integration — no
  external command to run, no build script.
- **`(libraries brr)`** brings in Brr, the OCaml binding to the browser APIs:
  the DOM, events, `window`, promises. Install it with `opam install brr`.
- **`--target-env browser`** tells js_of_ocaml which environment it is
  generating code for, so it does not emit Node-specific shims.
- **`-no-check-prims`** relaxes the check for external C primitives that have no
  JavaScript implementation. Standard practice for a browser bundle.

The `rule` at the end is the piece people forget. Dune names the output
`app.bc.js`, but `index.html` refers to `app.js`:

```html
<script src="app.js"></script>
```

Rather than write the Dune-internal name into the HTML, we copy the artefact to
the name the page expects. Both files end up in `_build/…/web/`.

## The backend `dune`

Unchanged from [step 02](02-assets.md):

```dune
(executable
 (name main)
 (libraries owebview owebview.desktop unix threads.posix))

(alias
 (name all)
 (deps
  (glob_files web/*)))
```

This is where the design of `Webview_desktop.Locate_assets.web_dir` pays off. Remember that it
looks for `exe_dir ()/web` **first**, and only falls back to the source tree.
Here that ordering is not a nicety, it is a requirement: `index.html` and
`style.css` are staged there from your sources, but `app.js` exists **only** in
the build tree — it is generated, and there is no copy of it to fall back to. So
build before you run:

```sh
dune build
dune exec ./main.exe
```

A bare `dune exec ./main.exe` on a cold tree may resolve `web_dir` to the source
directory, where the page will load but the script will be missing.

## The frontend, in OCaml

`web/app.ml` needs to do three things: find elements, react to clicks, and talk
to the backend. Brr covers the first two; the bridge needs two small helpers.

### Finding elements

```ocaml
let get_element_by_id : Jstr.t -> Brr.El.t option =
 fun id -> Brr.Document.find_el_by_id Brr.G.document id
```

`Brr.G.document` is the global `document`, and `Jstr.t` is a JavaScript string —
distinct from OCaml's `string`, built with `Jstr.v "out"`. The lookup returns an
option, which is Brr being honest about a DOM that may not contain the element.

### Calling a binding

A binding is a function on the global object returning a promise, so calling it
from OCaml means calling into JavaScript. `Jv` — Brr's untyped JavaScript value
layer — is the tool:

```ocaml
let call : string -> Jv.t array -> (Jstr.t -> unit) -> unit =
 fun name args f ->
  let promise = Jv.call Jv.global name args in
  let _ =
    Jv.Promise.then' promise
      (fun v ->
        let content = Jv.to_jstr v in
        let () = f content in
        Jv.null)
      (fun response ->
        let () = Brr.Console.(log [ response ]) in
        response)
  in
  ()
```

- `Jv.call Jv.global name args` is `window[name](...args)` — exactly the call
  the page made in plain JavaScript back in [step 03](03-js-bridge.md).
- `Jv.Promise.then'` attaches the two continuations: the resolution handler
  calls back into your OCaml code, the rejection handler logs to the console.
  That second one is where a `~error:true` from `Webview.return` lands.

Arguments are built with the `Jv.of_*` family:

```ocaml
call "add" [| Jv.of_int 20; Jv.of_int 22 |] show
call "os_type" [||] (fun _ -> ())
```

Note that this helper assumes the binding resolves with something the DOM can
render as text. It is deliberately loose — `Jv.to_jstr` is a cast, not a
validation. A stricter version would decode the `Jv.t` according to what each
binding is documented to return, and that is worth doing as soon as the payloads
grow past a number or a line of text.

### Being called by the backend

The other direction needs the OCaml function to be reachable from JavaScript, so
it has to live on the global object:

```ocaml
let register : string -> 'a -> unit =
 fun name f -> Jv.set Jv.global name (Jv.repr f)
```

`Jv.repr` reinterprets an OCaml value as a JavaScript one — for a function, the
closure js_of_ocaml compiled. After `register "show" show`, the backend can do:

```ocaml
Webview.eval w "show(\"hello\")"
```

This is the same contract as `window.setClock = …` in
[step 03](03-js-bridge.md), and it has the same reason to exist: a top-level
`let` compiled by js_of_ocaml is not a global variable, it is a value inside a
module closure. Making it callable is an explicit act.

### Wiring it up

```ocaml
let run _event =
  let out = Option.get (get_element_by_id (Jstr.v "out")) in
  let btn_add = Option.get (get_element_by_id (Jstr.v "btn-add")) in

  let show content =
    Brr.El.set_prop (Brr.El.Prop.jstr (Jstr.v "textContent")) content out
  in
  register "show" show;

  let _ : Brr.Ev.listener =
    Brr.Ev.listen Brr.Ev.click
      (fun _ -> call "add" [| Jv.of_int 20; Jv.of_int 22 |] show)
      (Brr.El.as_target btn_add)
  in
  ()

let _ =
  Brr.Ev.listen Brr.Ev.dom_content_loaded run
    (Brr.Document.as_target Brr.G.document)
```

The `dom_content_loaded` listener is what makes the `Option.get`s safe: the
script runs before the DOM is complete, so element lookups wait for the event.
It is the OCaml spelling of the guard every frontend needs.

## Two ways to answer, seen side by side

The bundled example is instructive because its two bindings answer differently.

`add` resolves its promise, and the page uses the value:

```ocaml
Webview.bind w "add" (fun id req ->
    let result =
      match Scanf.sscanf_opt req "[%d,%d]" (fun a b -> a + b) with
      | Some n -> string_of_int n
      | None -> "null"
    in
    Webview.return w id ~error:false ~result);
```

`os_type` pushes the result into the page itself, then settles the promise with
nothing:

```ocaml
Webview.bind w "os_type" (fun id _req ->
    let js = Printf.sprintf "show(%s)" (Utils.js_quote (Utils.detect_os ())) in
    Webview.eval w js;
    Webview.return w id ~error:false ~result:"");
```

Recall from [step 03](03-js-bridge.md) that an empty `~result` resolves the
promise with `undefined` — the call still has to be answered, it just carries no
value. Use the first form when the page needs an answer to *its* question; the
second when the backend is really notifying the page.

## Quoting, again — and a helper worth stealing

Interpolating into `eval` means writing JavaScript source, and
[step 03](03-js-bridge.md) already warned against `Printf`'s `%S`. In this
context the failure is different and nastier: `%S` escapes bytes above 127 as a
decimal `\ddd`, which JavaScript reads as a legacy **octal** escape — so `"café"`
does not fail loudly, it arrives mangled.

[`examples/js_of_ocaml/utils.ml`](../examples/js_of_ocaml/utils.ml) carries a
correct `js_quote`: it passes UTF-8 bytes through untouched and escapes only
what would close the literal or break the line.

```ocaml
let js_quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c < 0x20 || Char.code c = 0x7f ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b
```

It is thirteen lines and it is correct for both `eval` snippets and
`~result` payloads. Copy it into your project — or reach for a JSON library once
you are sending structures rather than strings.

## What you gain, what you pay

**You gain** one language, one toolchain, one set of types across the whole
application — and a compiler that checks your frontend. The natural next move is
to share code: put the types your bindings exchange in a plain OCaml library and
depend on it from both executables. A library with no C stubs and no `Unix`
compiles for both native and JavaScript, so a single definition of your protocol
serves both ends of the bridge, and a change to it breaks the build instead of
breaking at runtime.

**You pay** in verbosity — the OCaml above is longer than the equivalent
JavaScript, and `Jv` is untyped at the boundary anyway — and in bundle size,
since js_of_ocaml ships the runtime and whatever the OCaml standard library
pulls in. For a page with three buttons, plain JavaScript is smaller and
simpler. The trade turns in OCaml's favour as the frontend grows real logic,
real state and real data structures.

Also worth knowing: `~debug:true` on `Webview.create` still gives you the
inspector, but what you see in it is compiled JavaScript. Pass
`--source-map` in the js_of_ocaml flags to get your `.ml` back in the debugger.

## Pitfalls

- **`app.js` missing.** The page loads, blank, and the console reports a 404.
  Run `dune build` before `dune exec`, and check that the copy rule is present.
- **`Option.get` raising at startup.** The script ran before the DOM existed.
  Wrap the setup in a `dom_content_loaded` listener.
- **A backend `eval` calling a function the page has not registered yet.** Guard
  it — `if (typeof show === 'function') show(…)` — as the bundled example does
  for messages typed before the page finishes loading.
- **`Jstr.t` versus `string`.** They are different types on purpose. `Jstr.v`
  and `Jstr.to_string` cross the boundary.
- **Forgetting `register`.** A perfectly good OCaml function that `eval` cannot
  see is the most common five-minute confusion of this step.

## Exercises

1. Add a `greet(name)` binding and call it from `app.ml` with a value read from
   an `<input>` — `Brr.El.prop Brr.El.Prop.value` gets you the text.
2. Make the rejection path visible: reject a promise from OCaml with
   `~error:true` and display the message in the page rather than logging it.
3. Extract the protocol — the binding names and the shape of their arguments —
   into a `shared/` library used by both executables, and watch a rename break
   the build on both sides at once.
4. Add `--source-map` to the frontend's js_of_ocaml flags and step through
   `app.ml` in the inspector.

## What's next

The application is complete and it is entirely OCaml. What is left is the layer
of polish that makes it look like a real desktop app rather than a binary that
happens to open a window. [Step 06](06-app-icon.md) covers the icon — in the
Dock, in the taskbar, in the switcher — and the platform quirks that come with
it.
