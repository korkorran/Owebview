(* Front-end of the menu bar calculator, in OCaml.

   Compiled to JavaScript by js_of_ocaml (see dune) and using Brr for the DOM.
   The page is a view: the number and the history live in the application (see
   ../menubar_calc.ml), which pushes the whole state here after every change.

   Two functions are put on the global object for it to call:

   - [render state] redraws the list and the result;
   - [askNumber ()] opens the prompt, because the menu item that needs a
     number has no native dialog to ask with. *)

let find_el id = Brr.Document.find_el_by_id Brr.G.document (Jstr.v id)

(* Put [f] on the global object, so the application can reach it by name with
   [Webview.eval]. A top-level [let] compiled by js_of_ocaml lives inside a
   module closure and is not reachable that way. *)
let register name f = Jv.set Jv.global name (Jv.repr f)

let set_hidden el v = Brr.El.set_prop Brr.El.Prop.hidden v el

let run _event =
  let history_el = Option.get (find_el "history") in
  let none_el = Option.get (find_el "none") in
  let value_el = Option.get (find_el "value") in
  let overlay = Option.get (find_el "overlay") in
  let input = Option.get (find_el "number") in
  let ok = Option.get (find_el "ok") in

  (* One history line: "× 2  →  24". *)
  let entry jv =
    let span cls text =
      Brr.El.span ~at:[ Brr.At.class' (Jstr.v cls) ] [ Brr.El.txt text ]
    in
    Brr.El.li
      [
        span "op" (Jv.to_jstr (Jv.get jv "op"));
        span "arrow" (Jstr.v "→");
        span "result" (Jv.to_jstr (Jv.get jv "result"));
      ]
  in

  (* Called by the application after every change, with the whole state. *)
  let render state =
    let entries = Jv.to_list entry (Jv.get state "history") in
    Brr.El.set_children history_el entries;
    set_hidden none_el (entries <> []);
    Brr.El.set_children value_el [ Brr.El.txt (Jv.to_jstr (Jv.get state "value")) ]
  in

  let close_prompt () = set_hidden overlay true in
  let open_prompt () =
    set_hidden overlay false;
    Brr.El.set_prop Brr.El.Prop.value (Jstr.v "") input;
    Brr.El.set_has_focus true input
  in

  (* OK hands the number to the application and closes. An empty or
     unparsable field is simply ignored. *)
  let confirm () =
    (* Jstr.to_float never fails: it yields nan on an unparsable field. *)
    let n = Jstr.to_float (Brr.El.prop Brr.El.Prop.value input) in
    if not (Float.is_nan n) then
      ignore (Jv.call Jv.global "set_number" [| Jv.of_float n |]);
    close_prompt ()
  in
  ignore (Brr.Ev.listen Brr.Ev.click (fun _ -> confirm ()) (Brr.El.as_target ok));

  (* Enter confirms, Escape gives a way out: the prompt has an OK button but
     no Cancel. Both only while it is open. *)
  let on_keydown ev =
    if not (Brr.El.prop Brr.El.Prop.hidden overlay) then
      let key = Brr.Ev.Keyboard.key (Brr.Ev.as_type ev) in
      if Jstr.equal key (Jstr.v "Enter") then confirm ()
      else if Jstr.equal key (Jstr.v "Escape") then close_prompt ()
  in
  ignore
    (Brr.Ev.listen Brr.Ev.keydown on_keydown
       (Brr.Document.as_target Brr.G.document));

  register "render" render;
  register "askNumber" open_prompt;

  (* The page is ready: ask for the initial state, rather than having the
     application guess when the page has finished loading. *)
  ignore (Jv.call Jv.global "ready" [||])

let () =
  ignore
    (Brr.Ev.listen Brr.Ev.dom_content_loaded run
       (Brr.Document.as_target Brr.G.document))
