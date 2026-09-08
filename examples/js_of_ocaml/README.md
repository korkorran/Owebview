# Full OCaml application

Ocaml is able to compile to javascript using [js_of_ocaml](https://github.com/ocsigen/js_of_ocaml/). This can be automated in dune by adding [(modes js)](https://dune.readthedocs.io/en/stable/jsoo.html) in the executable rule.


In the example, we are using the [Brr](https://erratique.ch/software/brr) for the interaction with the webview API.

This function gives an example of call a fuction declared in the application and gives the answer to a callback:

```
(** Call the binding in the application, then gives the response to the callback *)
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

(In a general way, the OCaml code will be more verbose than the same code in pure javascript)

The example also show how to declare a function and to call it directly using `Webview.eval`.

```
(** Register the function in the global object in order to use it from the main
    application *)
let register : string -> 'a -> unit =
 fun name f -> Jv.set Jv.global name (Jv.repr f)
```

## From the terminal to the page

The example also goes the other way round: anything typed in the terminal is
pushed to the page and rendered in `<pre id="out">`. It reuses the `show`
function that `app.ml` registered on the global object, so no extra binding is
needed on the JS side.

```
let line = input_line stdin in
let js =
  Printf.sprintf "if (typeof show === 'function') show(%s);" (Utils.js_quote line)
in
Webview.dispatch w (fun w -> Webview.eval w js)
```

Two things are worth noting.

`input_line` blocks, so the loop runs on its own thread (hence `threads.posix`
in the `dune` file). A webview may only be touched from the thread that called
`Webview.run`, so the evaluation is handed over with `Webview.dispatch` rather
than calling `Webview.eval` directly from the reader thread.

The message is interpolated into JavaScript source, so it has to be quoted as a
JS literal. `Printf`'s `%S` looks like the obvious tool but is the wrong one: it
escapes bytes above 127 as a decimal `\ddd`, which JavaScript reads as a legacy
*octal* escape, so any accented or emoji input reaches the page mangled.
`Utils.js_quote` passes UTF-8 bytes through untouched and escapes only what
would close the literal or break the line.