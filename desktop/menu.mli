(** The native menu bar.

    The system's own menu bar — the strip at the top of the screen on macOS,
    the one under the title bar on Linux and Windows — described as an
    ordinary OCaml value and installed in one call:

    {[
      let quit () = Webview.terminate w in
      Webview_desktop.Menu.set w
        [
          ("MyApp", [ Menu.item "Quit" ~key:'q' ~modifiers:[ Cmd ] quit ]);
          ( "File",
            [
              Menu.item "Open…" ~key:'o' ~modifiers:[ Cmd ] pick_file;
              Menu.separator;
              Menu.submenu "Recent" [ Menu.item "example.txt" reopen ];
            ] );
        ]
    ]}

    {1 How to call it}

    {!set} must run on the UI thread — the thread running {!Webview.run} — and
    on macOS only once the application is active, which it becomes after
    {!Webview.run} has started. The reliable place is therefore a
    {!Webview.dispatch} callback, the same pattern {!Icon.set_app_icon} needs:

    {[
      Webview.dispatch w (fun w -> Menu.set w menus);
      Webview.run w
    ]}

    Item callbacks are invoked on the UI thread too, so they may drive the
    webview directly — {!Webview.eval}, {!Webview.terminate} — with no
    {!Webview.dispatch} in between. An exception escaping a callback is
    dropped: there is no OCaml handler on the native stack below it.

    {1 What differs between platforms}

    - {b macOS}: the menu bar is {e application-global}, so the [Webview.t]
      argument is ignored. Note the platform convention: the {b first} menu is
      the application menu, and the system draws it with the application's own
      name whatever title you give it. Put your Quit item there, as in the
      example above, and give the remaining menus their real names.
    - {b Linux (GTK 3)}: the bar belongs to the window, and installing it
      re-parents webview's widget under a [GtkBox]. Calling {!set} again
      replaces the bar rather than stacking a second one. {b GTK 4 is not
      supported} — it replaced [GtkMenuBar] with the [GMenu] model — and
      {!set} is a no-op there.
    - {b Windows}: the bar belongs to the window, and its window procedure is
      subclassed to receive [WM_COMMAND]. Accelerators work, but by a route
      worth knowing about: Windows runs them from the message loop, via
      [TranslateAccelerator], and webview's loop does not call it — so {!set}
      installs a [WH_GETMESSAGE] hook on {b the calling thread} and translates
      there. Two consequences. The hook belongs to the thread that called
      {!set}, so call it from the UI thread like everything else here. And a
      menu shortcut takes precedence over the page: the hook sees the
      keystroke before it is dispatched, and swallows the ones it claims, so
      a page listening for Ctrl-O will not also see it.
    - Any other backend: a no-op. *)

(** A keyboard modifier. *)
type modifier =
  | Cmd
      (** The platform's primary modifier: Command on macOS, Control on Linux
          and Windows, where there is no Command key. *)
  | Ctrl  (** Control, on every platform. *)
  | Alt  (** Option on macOS, Alt elsewhere. *)
  | Shift

type item
(** One entry in a menu: a clickable item, a separator, or a nested submenu. *)

val item : ?key:char -> ?modifiers:modifier list -> string -> (unit -> unit) -> item
(** [item label on_click] is a clickable entry that calls [on_click ()] on the
    UI thread when chosen.

    [?key] and [?modifiers] give it a keyboard shortcut: [~key:'o'
    ~modifiers:[ Cmd ]] is Command-O on macOS and Control-O elsewhere. Use a
    lowercase letter; with no [?key] the item has no shortcut, and
    [?modifiers] is then ignored. *)

val separator : item
(** A horizontal rule between groups of items. *)

val submenu : string -> item list -> item
(** [submenu label items] nests a menu inside another one. *)

val set : Webview.t -> (string * item list) list -> unit
(** [set w menus] replaces the whole menu bar, [menus] being the top-level
    menus in order, each a title and its contents.

    Calling it again replaces the previous bar entirely; the callbacks of the
    old one are released. Passing [[]] installs an empty bar. *)
