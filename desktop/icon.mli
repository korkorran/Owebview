(** Application icon and application id.

    Give the application a real icon in the Dock, the taskbar or the window
    switcher, instead of the generic executable one.

    {2 Do you need this?}

    Mostly during development, and for an executable shipped on its own: there
    the system has nothing but the binary to go on. An application distributed
    as a proper package carries its icon in the package itself, which the
    system picks up before any of your code runs, and both functions then have
    nothing left to do — the desktop entry a package installs already names the
    icon, and already matches the process by its executable name. *)

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

val install_desktop_entry :
  ?name:string ->
  ?comment:string ->
  ?categories:string list ->
  ?exec:string ->
  app_id:string ->
  icon:string ->
  unit ->
  string option
(** Install the [.desktop] file a Linux desktop needs in order to show the
    application's icon, and return the path written.

    {!set_app_icon} only sets the X11 [_NET_WM_ICON] property, which native
    Wayland does not have: there, the shell resolves an application's icon
    from an installed [.desktop] file, matched against the running process by
    its application id. Under Wayland the icon therefore never appears until
    such a file exists — and that is what this writes.

    The entry goes to [$XDG_DATA_HOME/applications], or
    [$HOME/.local/share/applications] when that variable is unset, under a
    name derived from [app_id]. Writing it again simply replaces it. To remove
    it, delete the returned path: nothing else is left behind.

    - [app_id] is written as [StartupWMClass], the key the shell matches the
      process against, so it must be the same string passed to {!set_app_id}.
    - [icon] is an absolute path to the image; it must exist.
    - [exec] is the command the desktop launches, and defaults to
      [Sys.executable_name] — which is usually what you want, since the
      running binary is the one being described.
    - [name] is the label shown to the user, and defaults to [app_id].
    - [comment] and [categories] are written only if given;
      [~categories:["Development"]] becomes [Categories=Development;].

    Returns [None], having done nothing, on any platform other than Linux:
    elsewhere the icon comes from the application itself or from its bundle,
    and there is no desktop entry to install.

    Raises [Failure] if [icon] does not exist, if neither [XDG_DATA_HOME] nor
    [HOME] is set, or if any value contains a newline — the entry format has
    no escape for one, and it would start a new key.

    After installing, [update-desktop-database] is run when available, since
    some desktops cache that directory; its failure is not reported. *)
