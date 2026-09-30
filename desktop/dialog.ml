(* The stubs work on the native parent window rather than on a [Webview.t],
   which is what keeps dialog_stubs.cpp free of any reference to the webview C
   API. A null handle is not an error here: the dialog is simply unparented.

   The open dialogs report a cancellation as the empty string, so that the C
   side never has to allocate an OCaml option. *)
external raw_confirm : nativeint -> string -> string -> bool
  = "ocaml_webview_dialog_confirm"

external raw_open : nativeint -> string -> bool -> string
  = "ocaml_webview_dialog_open"

let confirm w ?(title = "") message =
  raw_confirm (Webview.get_window w) title message

let open_ w title directory =
  match raw_open (Webview.get_window w) title directory with
  | "" -> None
  | path -> Some path

let open_file w ?(title = "") () = open_ w title false
let open_directory w ?(title = "") () = open_ w title true
