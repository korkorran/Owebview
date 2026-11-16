(* Front-end of the chat window, in OCaml.

   This file is compiled to JavaScript by js_of_ocaml (see dune) and uses Brr
   for the DOM. It owns the message list; the OCaml process on the other side
   of the bridge never touches the page directly, it only calls the [post]
   function registered below -- see ../chat_window.ml. *)

let find_el id = Brr.Document.find_el_by_id Brr.G.document (Jstr.v id)

(* Put [f] on the global object, so that the application can reach it by name
   with [Webview.eval]. A top-level [let] compiled by js_of_ocaml lives inside
   a module closure and is not reachable that way: making it callable is an
   explicit act. *)
let register name f = Jv.set Jv.global name (Jv.repr f)

let run _event =
  (* Runs once the DOM is complete, so the lookups below are safe. *)
  let messages = Option.get (find_el "messages") in
  let placeholder = find_el "empty" in

  (* window.post(author, text): append one message and scroll to it. Both
     arguments arrive as JavaScript strings, hence [Jstr.t]. *)
  let post author text =
    (* The first message retires the "no message yet" line. *)
    Option.iter Brr.El.remove placeholder;
    let item =
      Brr.El.li
        ~at:[ Brr.At.class' (Jstr.v "message") ]
        [
          Brr.El.span ~at:[ Brr.At.class' (Jstr.v "author") ] [ Brr.El.txt author ];
          Brr.El.p ~at:[ Brr.At.class' (Jstr.v "text") ] [ Brr.El.txt text ];
        ]
    in
    Brr.El.append_children messages [ item ];
    (* Keep the newest message in view.

       [Brr.El.scroll_into_view] would be the idiomatic call, but it raises a
       TypeError under WebKit -- with and without [~align_v] -- so the plain
       DOM method is called directly instead. *)
    ignore (Jv.call (Brr.El.to_jv item) "scrollIntoView" [||])
  in
  register "post" post

let () =
  Brr.Ev.listen Brr.Ev.dom_content_loaded run
    (Brr.Document.as_target Brr.G.document)
  |> ignore
