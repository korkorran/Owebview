let get_element_by_id : Jstr.t -> Brr.El.t option =
 fun id -> Brr.Document.find_el_by_id Brr.G.document id

(** Call the binding in the application, then gives the response to the callback
*)
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

(** Register the function in the global object in order to use it from the main
    application *)
let register : string -> 'a -> unit =
 fun name f -> Jv.set Jv.global name (Jv.repr f)

let run event_target =
  ignore event_target;

  (* This code is executed once the view is initialized, the elements are all
  ready *)
  let out = Option.get (get_element_by_id (Jstr.v "out")) in
  let btn_add = Option.get (get_element_by_id (Jstr.v "btn-add")) in
  let btn_os = Option.get (get_element_by_id (Jstr.v "btn-os")) in

  let show content =
    Brr.El.set_prop (Brr.El.Prop.jstr (Jstr.v "textContent")) content out
  in

  (* Register the function [show] in the global object. The function can be
  called using [eval] in the application *)
  let () = register "show" show in

  let () =
    let target = Brr.El.as_target btn_add in
    let _ : Brr.Ev.listener =
      Brr.Ev.listen Brr.Ev.click
        (fun _ -> (call "add" [| Jv.of_int 20; Jv.of_int 22 |]) show)
        target
    in
    ()
  in

  let target = Brr.El.as_target btn_os in
  let _ =
    Brr.Ev.listen Brr.Ev.click
      (fun _ ->
        ((* Call without argument *)
         call "os_type" [||]) (fun response ->
            (* Ignore the response here, the function [show] is called
              directly from the application *)
            ignore response))
      target
  in
  ()

let _ =
  Brr.Ev.listen Brr.Ev.dom_content_loaded run
    (Brr.Document.as_target Brr.G.document)
