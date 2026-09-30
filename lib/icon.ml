(* Application icon and application id.

   These two entry points are not part of the webview C API: they call into
   Cocoa, GTK and Win32 directly (see icon_stubs.cpp). [set_app_icon] works on
   the native top-level window rather than on a [Webview.t], which is what
   keeps the stub -- and this module -- independent of the webview API.
   [Webview.Icon] wraps it so that callers pass the webview handle and the
   window is looked up with [Webview.get_window]. *)

external set_app_icon : nativeint -> string -> unit
  = "ocaml_webview_set_app_icon"

external set_app_id : string -> unit = "ocaml_webview_set_app_id"
