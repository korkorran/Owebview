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

(** {1 Application icon} *)

(** Give the application a real icon in the Dock, the taskbar or the window
    switcher, instead of the generic executable one.

    Neither entry point belongs to the webview API: they call into
    Cocoa, GTK and Win32 directly. *)
module Icon : sig
  val set_app_icon : t -> string -> unit
  (** [set_app_icon w path] sets the application/window icon from an image
      file, so a plain executable shows a custom icon instead of the generic
      one:

      - {b macOS}: the Dock icon (application-global; [w] is ignored).
      - {b Linux/GTK}: the window's icon (taskbar/switcher).
      - {b Windows}: the window's icon via [WM_SETICON]. The file is decoded
        with WIC, so any format Windows imaging supports works ([.png],
        [.jpg], [.bmp], [.gif], [.tif], [.ico]); it is rescaled to the system
        icon sizes.

      Raises [Failure] if the image cannot be loaded, or if the backend
      provides no native window; a no-op on other backends.

      On macOS the process only becomes a regular (Dock-visible) app once
      {!run} has started, so call this {b once the app is active} — e.g. from
      a {!dispatch} callback — otherwise the Dock ignores it.

      {b Linux/Wayland}: this alone is not enough to get a custom Dock icon.
      [set_app_icon] only sets the X11 [_NET_WM_ICON] property, which does not
      exist under native Wayland (the default on e.g. GNOME/Fedora); the Dock
      there resolves an app's icon from an installed [.desktop] file instead.
      Pair this with {!set_app_id} and an installed [.desktop] file whose id
      (or [StartupWMClass=]) matches. *)

  val set_app_id : string -> unit
  (** [set_app_id id] sets the process-wide application id used by the
      windowing system to associate this process's windows with an installed
      [.desktop] file:

      - {b Linux/GTK}: sets the GLib program name ([g_set_prgname]), which
        becomes the X11 [WM_CLASS] class name, and, under Wayland, the
        toplevel's [app_id]. Desktop shells (e.g. GNOME) match this id against
        an installed [.desktop] file's id or its [StartupWMClass=] to decide
        which icon to show in the Dock/taskbar.
      - {b other backends}: a no-op.

      Call this once, {b before} {!create}, so it applies to the first window
      realized. See {!set_app_icon} for why this matters on Linux/Wayland. *)
end

(** {1 Locating assets} *)

(** Filesystem helpers for locating on-disk assets (HTML/CSS/JS) relative to the
    running executable, independently of the current working directory. *)
module Utils : sig
  val exe_dir : unit -> string
  (** Absolute path to the directory containing the running executable. *)

  val asset_dir : unit -> string
  (** Directory to resolve on-disk assets against. When launched via
      [dune exec], the executable lives under [_build/<context>/], where the
      source assets are not copied; this maps such a path back to the matching
      source directory. From an installed location the executable directory is
      used as-is. *)

  val web_dir : unit -> string
  (** Directory to resolve web assets against. This is [asset_dir]/web. *)
end
