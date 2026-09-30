(** Native modal dialogs.

    The system's own dialogs, not HTML ones: an alert asking the user to
    confirm, and the file browser asking them to pick a file or a directory.

    {1 How to call them}

    Every function here is {b modal and synchronous}: it blocks, running the
    platform's own event loop, until the user dismisses the dialog, and it
    returns what they chose. The window behind it stops responding for the
    duration, which is the point of a modal dialog.

    They must be called {b on the UI thread} — the thread running
    {!Webview.run}. In practice that means from a binding callback, which is
    the natural place for them:

    {[
      Webview.bind w "pick_file" (fun id _req ->
          let result =
            match Webview_desktop.Dialog.open_file w ~title:"Choose a file" () with
            | Some path -> Printf.sprintf "%S" path
            | None -> "null"
          in
          Webview.return w id ~error:false ~result)
    ]}

    From any other thread, hop onto the UI thread with {!Webview.dispatch}
    first. Note that a dispatched callback returns [unit], so the answer has
    to be carried out of it by other means — a [ref], a mutex, an
    [Lwt_mvar.t].

    On macOS the process must be an active application for a modal dialog to
    appear, which it only becomes once {!Webview.run} has started — the same
    constraint as {!Icon.set_app_icon}.

    {1 Platform notes}

    - {b macOS}: [NSAlert] and [NSOpenPanel], run app-modally. The webview
      window is ignored as a parent: attaching a sheet requires a completion
      block, which the Objective-C runtime C API cannot express.
    - {b Linux}: [GtkMessageDialog] and [GtkFileChooserDialog], modal and
      transient for the webview window. {b GTK 4 is not supported} — it
      removed [gtk_dialog_run] and the dialog constructors used here; on a
      GTK 4 build these functions are no-ops ([false] and [None]).
    - {b Windows}: [MessageBoxW] and [IFileOpenDialog], owned by the webview
      window.
    - Any other backend: a no-op ([false] and [None]). *)

val confirm : Webview.t -> ?title:string -> string -> bool
(** [confirm w message] shows a question dialog with the platform's standard
    OK and Cancel buttons, and returns [true] if the user confirmed.

    Cancelling returns [false], and so does dismissing the dialog any other
    way — Escape, or the window's close button. Treat [false] as "did not
    confirm" rather than as "pressed Cancel".

    [?title] is the headline: the window title on Linux and Windows, the bold
    first line of the alert on macOS, where [message] then becomes the
    smaller informative text below it. Omit it for a plain one-line question.

    {[
      if Dialog.confirm w ~title:"Quit" "Discard unsaved changes?" then
        Webview.terminate w
    ]} *)

val open_file : Webview.t -> ?title:string -> unit -> string option
(** [open_file w ()] opens the system file browser and returns the absolute
    path of the single existing file the user picked, or [None] if they
    cancelled.

    [?title] replaces the dialog's default heading. There is no file-type
    filter: every file is selectable. *)

val open_directory : Webview.t -> ?title:string -> unit -> string option
(** [open_directory w ()] is {!open_file} for directories: it returns the
    absolute path of the single existing directory the user picked, or [None]
    if they cancelled. *)
