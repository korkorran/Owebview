type t
(* Runtime representation is a nativeint holding the C [webview_t] pointer.
   It is abstract in the .mli so callers cannot do arithmetic on it. *)

type hint = Hint_none | Hint_min | Hint_max | Hint_fixed

(** This function is not required, as the enum representation is an int, but
    will ensure safety in case of reodering *)
let int_of_hint = function
  | Hint_none -> 0
  | Hint_min -> 1
  | Hint_max -> 2
  | Hint_fixed -> 3

(* The constant constructors above map to 0,1,2,3 at runtime, which matches
   WEBVIEW_HINT_NONE/MIN/MAX/FIXED, so they can be passed straight to C. *)

type native_handle_kind = Ui_window | Ui_widget | Browser_controller

(* Like [int_of_hint]: explicit mapping so reordering the variant stays safe.
   Matches WEBVIEW_NATIVE_HANDLE_KIND_UI_WINDOW/UI_WIDGET/BROWSER_CONTROLLER. *)
let int_of_native_handle_kind = function
  | Ui_window -> 0
  | Ui_widget -> 1
  | Browser_controller -> 2

(* Field order must match the record block built by the C stub
   (ocaml_webview_version). *)
type version_info = {
  major : int;
  minor : int;
  patch : int;
  version_number : string;
  pre_release : string;
  build_metadata : string;
}

external _create : bool -> t = "ocaml_webview_create"
external destroy : t -> unit = "ocaml_webview_destroy"
external run : t -> unit = "ocaml_webview_run"
external terminate : t -> unit = "ocaml_webview_terminate"
external set_title : t -> string -> unit = "ocaml_webview_set_title"
external _set_size : t -> int -> int -> int -> unit = "ocaml_webview_set_size"
external navigate : t -> string -> unit = "ocaml_webview_navigate"
external set_html : t -> string -> unit = "ocaml_webview_set_html"
external init : t -> string -> unit = "ocaml_webview_init"
external eval : t -> string -> unit = "ocaml_webview_eval"

external bind : t -> string -> (string -> string -> unit) -> unit
  = "ocaml_webview_bind"

external unbind : t -> string -> unit = "ocaml_webview_unbind"

external dispatch : t -> (t -> unit) -> unit = "ocaml_webview_dispatch"

external _return : t -> string -> int -> string -> unit = "ocaml_webview_return"

external version : unit -> version_info = "ocaml_webview_version"
external get_window : t -> nativeint = "ocaml_webview_get_window"

external _get_native_handle : t -> int -> nativeint
  = "ocaml_webview_get_native_handle"

let create ?(debug = false) () = _create debug
let set_size w ~width ~height hint = _set_size w width height (int_of_hint hint)
let return w id ~error ~result = _return w id (if error then 1 else 0) result

let get_native_handle w kind =
  _get_native_handle w (int_of_native_handle_kind kind)

(* Re-export the filesystem helpers as [Webview.Utils]. *)
module Utils = Utils
