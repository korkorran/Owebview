(** Owebview — OCaml bindings for {{:https://github.com/webview/webview}webview}
    0.12.

    Open a native window backed by the operating system's web engine, load
    HTML/CSS/JS, and call back and forth between the page's JavaScript and
    OCaml — no Electron, no bundler.

    {[
      let () =
        let w = Webview.create () in
        Webview.set_title w "Hello";
        Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;
        Webview.set_html w "<h1>Hello from OCaml</h1>";
        Webview.run w;
        Webview.destroy w
    ]} *)

type t
(** An opaque handle to a webview instance (a C [webview_t]). *)

(** Window sizing behaviour, mirrors [WEBVIEW_HINT_*]. *)
type hint =
  | Hint_none  (** width/height are the initial size *)
  | Hint_min  (** width/height are the minimum bounds *)
  | Hint_max  (** width/height are the maximum bounds *)
  | Hint_fixed  (** window is not resizable *)

(** {1 Lifecycle} *)

val create : ?debug:bool -> unit -> t
(** [create ?debug ()] creates a new webview. When [debug] is true the developer
    tools are enabled (default [false]). *)

val destroy : t -> unit
(** Destroy the webview and free associated resources. *)

val run : t -> unit
(** Run the main loop. {b Blocks} the calling thread until the window is closed
    and {b must be called on the main thread}. The OCaml runtime lock is
    released for the duration so other threads keep running. *)

val terminate : t -> unit
(** Stop the main loop started by {!run}. Safe to call from a binding. *)

(** {1 Window} *)

val set_title : t -> string -> unit
(** [set_title w title] sets the window title. *)

val set_size : t -> width:int -> height:int -> hint -> unit
(** [set_size w ~width ~height hint] sets the window size in pixels; [hint]
    controls how the size is interpreted (see {!type:hint}). *)

(** {1 Navigation and content} *)

val navigate : t -> string -> unit
(** Navigate to a URL (supports [http://], [https://], [file://], [data:]). *)

val set_html : t -> string -> unit
(** Load the given HTML string as the document. *)

val init : t -> string -> unit
(** Inject JS to be run on every page load, before page scripts. *)

val eval : t -> string -> unit
(** Evaluate JS in the current page. *)

(** {1 JavaScript bridge}

    Expose OCaml functions to the page as [window.<name>(...)] and resolve the
    JavaScript promises they return. *)

val bind : t -> string -> (string -> string -> unit) -> unit
(** [bind w name f] exposes a JS function [window.name(...)] that calls back
    into [f id req], where [req] is a JSON array string of the JS arguments. The
    callback must eventually answer with {!return} (using [id]).

    The closure is kept alive as a GC root until the binding is removed with
    {!unbind} or the webview is {!destroy}ed. Raises [Failure] if a binding
    with the same [name] already exists. *)

val unbind : t -> string -> unit
(** [unbind w name] removes the binding [name] created with {!bind}, releasing
    the closure's GC root. Raises [Failure] if no such binding exists. *)

val return : t -> string -> error:bool -> result:string -> unit
(** [return w id ~error ~result] resolves (or rejects, if [error]) the JS
    promise associated with the call [id]. [result] must be a JSON value. *)

(** {1 Threading} *)

val dispatch : t -> (t -> unit) -> unit
(** [dispatch w f] schedules [f] to run once on the UI thread (the thread
    running {!run}), passing it the webview handle. This is the thread-safe way
    to drive the webview from another thread: call e.g. {!eval} or
    {!set_title} from inside [f]. Any exception raised by [f] is dropped. *)

(** {1 Library version} *)

(** The library's version information, as returned by {!version}. *)
type version_info = {
  major : int;
  minor : int;
  patch : int;
  version_number : string;  (** SemVer ["MAJOR.MINOR.PATCH"] string *)
  pre_release : string;  (** SemVer pre-release labels, or [""] *)
  build_metadata : string;  (** SemVer build metadata, or [""] *)
}

val version : unit -> version_info
(** The webview library's version information. *)

(** {1 Native handles} *)

(** The kind of native handle to retrieve with {!get_native_handle}, mirrors
    [WEBVIEW_NATIVE_HANDLE_KIND_*]. *)
type native_handle_kind =
  | Ui_window  (** top-level window: [NSWindow]/[GtkWindow]/[HWND] *)
  | Ui_widget  (** browser widget: [NSView]/[GtkWidget]/[HWND] *)
  | Browser_controller
      (** [WKWebView]/[WebKitWebView]/[ICoreWebView2Controller] *)

val get_window : t -> nativeint
(** [get_window w] returns the native top-level window handle as a pointer
    ([0n] if unavailable). Interpret it with platform-specific FFI. *)

val get_native_handle : t -> native_handle_kind -> nativeint
(** [get_native_handle w kind] returns the requested native handle as a pointer
    ([0n] if unavailable). *)
