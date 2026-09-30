(* The stub works on the native top-level window rather than on a [Webview.t]:
   that is what keeps icon_stubs.cpp free of any reference to the webview C
   API. The handle is resolved here with [Webview.get_window], which is part of
   the core library's public interface — so this library needs nothing from
   owebview beyond what any other user of it can reach. *)
external raw_set_app_icon : nativeint -> string -> unit
  = "ocaml_webview_set_app_icon"

external set_app_id : string -> unit = "ocaml_webview_set_app_id"

let set_app_icon w path = raw_set_app_icon (Webview.get_window w) path
