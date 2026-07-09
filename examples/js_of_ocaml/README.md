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