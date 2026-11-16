(* Front-end of the file reader, in OCaml.

   Compiled to JavaScript by js_of_ocaml (see dune) and using Brr for the DOM.
   It owns the button and the display; the file itself is chosen and read on
   the OCaml side, behind the pick_file binding — see ../file_reader.ml. *)

let find_el id = Brr.Document.find_el_by_id Brr.G.document (Jstr.v id)

(* Call a binding exposed by the application. It is a function on the global
   object returning a promise, so [on_ok] receives what it resolved with and
   [on_error] what it was rejected with. *)
let call name args ~on_ok ~on_error =
  let promise = Jv.call Jv.global name args in
  ignore
    (Jv.Promise.then' promise
       (fun v ->
         on_ok v;
         Jv.null)
       (fun e ->
         on_error e;
         Jv.null))

let set_text el s = Brr.El.set_children el [ Brr.El.txt s ]

let run _event =
  (* Runs once the DOM is complete, so the lookups below are safe. *)
  let button = Option.get (find_el "pick") in
  let save = Option.get (find_el "save") in
  let status = Option.get (find_el "status") in
  let path_el = Option.get (find_el "path") in
  let content_el = Option.get (find_el "content") in

  let show_status ?(error = false) text =
    set_text status (Jstr.v text);
    Brr.El.set_class (Jstr.v "error") error status;
    Brr.El.set_prop Brr.El.Prop.hidden false status
  in
  let show_file v =
    let jstr field = Jv.to_jstr (Jv.get v field) in
    set_text path_el (jstr "path");
    set_text content_el (jstr "content");
    Brr.El.set_prop Brr.El.Prop.hidden false path_el;
    Brr.El.set_prop Brr.El.Prop.hidden false content_el;
    (* There is something to save now. In Brr [disabled] is an attribute
       rather than a property, and removing it is what enables the button. *)
    Brr.El.set_at Brr.At.Name.disabled None save;
    if Jv.to_bool (Jv.get v "truncated") then
      show_status "Showing the first megabyte only."
    else Brr.El.set_prop Brr.El.Prop.hidden true status
  in

  (* Picking again simply replaces what is on screen. *)
  let on_click _ =
    call "pick_file" [||]
      ~on_ok:(fun v ->
        if Jv.is_null v then show_status "Cancelled — no file chosen."
        else show_file v)
      ~on_error:(fun e -> show_status ~error:true (Jstr.to_string (Jv.to_jstr e)))
  in
  ignore (Brr.Ev.listen Brr.Ev.click on_click (Brr.El.as_target button));

  (* Save a copy of the displayed file under a name the user chooses. The
     button is disabled until there is one, so no guard is needed here. *)
  let on_save _ =
    call "save_as" [||]
      ~on_ok:(fun v ->
        if Jv.is_null v then show_status "Save cancelled."
        else
          show_status
            (Printf.sprintf "Saved to %s" (Jstr.to_string (Jv.to_jstr v))))
      ~on_error:(fun e -> show_status ~error:true (Jstr.to_string (Jv.to_jstr e)))
  in
  ignore (Brr.Ev.listen Brr.Ev.click on_save (Brr.El.as_target save))

let () =
  ignore
    (Brr.Ev.listen Brr.Ev.dom_content_loaded run
       (Brr.Document.as_target Brr.G.document))
