(** Application icon and application id.

    Give the application a real icon in the Dock, the taskbar or the window
    switcher, instead of the generic executable one.

    Neither entry point belongs to the webview API: they call into Cocoa, GTK
    and Win32 directly. *)

val set_app_icon : Webview.t -> string -> unit
(** [set_app_icon w path] sets the application/window icon from an image file,
    so a plain executable shows a custom icon instead of the generic one:

    - {b macOS}: the Dock icon (application-global; [w] is ignored).
    - {b Linux/GTK}: the window's icon (taskbar/switcher).
    - {b Windows}: the window's icon via [WM_SETICON]. The file is decoded with
      WIC, so any format Windows imaging supports works ([.png], [.jpg],
      [.bmp], [.gif], [.tif], [.ico]); it is rescaled to the system icon sizes.

    Raises [Failure] if the image cannot be loaded, or if the backend provides
    no native window; a no-op on other backends.

    On macOS the process only becomes a regular (Dock-visible) app once
    {!Webview.run} has started, so call this {b once the app is active} — e.g.
    from a {!Webview.dispatch} callback — otherwise the Dock ignores it.

    {b Linux/Wayland}: this alone is not enough to get a custom Dock icon.
    [set_app_icon] only sets the X11 [_NET_WM_ICON] property, which does not
    exist under native Wayland (the default on e.g. GNOME/Fedora); the Dock
    there resolves an app's icon from an installed [.desktop] file instead.
    Pair this with {!set_app_id} and an installed [.desktop] file whose id (or
    [StartupWMClass=]) matches. *)

val set_app_id : string -> unit
(** [set_app_id id] sets the process-wide application id used by the windowing
    system to associate this process's windows with an installed [.desktop]
    file:

    - {b Linux/GTK}: sets the GLib program name ([g_set_prgname]), which
      becomes the X11 [WM_CLASS] class name, and, under Wayland, the toplevel's
      [app_id]. Desktop shells (e.g. GNOME) match this id against an installed
      [.desktop] file's id or its [StartupWMClass=] to decide which icon to
      show in the Dock/taskbar.
    - {b other backends}: a no-op.

    Call this once, {b before} {!Webview.create}, so it applies to the first
    window realized. See {!set_app_icon} for why this matters on
    Linux/Wayland. *)
