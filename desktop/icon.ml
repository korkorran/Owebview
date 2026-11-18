(* The stub works on the native top-level window rather than on a [Webview.t]:
   that is what keeps icon_stubs.cpp free of any reference to the webview C
   API. The handle is resolved here with [Webview.get_window], which is part of
   the core library's public interface — so this library needs nothing from
   owebview beyond what any other user of it can reach. *)
external raw_set_app_icon : nativeint -> string -> unit
  = "ocaml_webview_set_app_icon"

external set_app_id : string -> unit = "ocaml_webview_set_app_id"

let set_app_icon w path = raw_set_app_icon (Webview.get_window w) path

(* ---- the desktop entry --------------------------------------------------

   [set_app_icon] only sets the X11 _NET_WM_ICON property, which native
   Wayland does not have: there, the shell resolves an application's icon from
   an installed .desktop file matched by the process's app id. So on a Wayland
   desktop the icon never appears until such a file exists, which is what
   [install_desktop_entry] writes. *)

(* $XDG_DATA_HOME/applications, falling back to the specified default. *)
let applications_dir () =
  let data_home =
    match Sys.getenv_opt "XDG_DATA_HOME" with
    | Some dir when dir <> "" -> dir
    | _ -> (
        match Sys.getenv_opt "HOME" with
        | Some home -> Filename.concat home ".local/share"
        | None ->
            failwith
              "install_desktop_entry: neither XDG_DATA_HOME nor HOME is set")
  in
  Filename.concat data_home "applications"

(* [Sys.mkdir] creates one level, so walk the path. *)
let rec mkdir_p dir =
  if not (Sys.file_exists dir) then (
    let parent = Filename.dirname dir in
    if parent <> dir then mkdir_p parent;
    try Sys.mkdir dir 0o755 with Sys_error _ when Sys.file_exists dir -> ())

(* A newline in a value would start a new key, so it is refused rather than
   written out: the entry format has no escape for it. *)
let check_value field v =
  if String.exists (fun c -> c = '\n' || c = '\r') v then
    failwith
      (Printf.sprintf "install_desktop_entry: %s must not contain a newline"
         field)

(* Refresh the desktop database, if the tool is there. Some desktops cache the
   applications directory and would not notice the new file otherwise. Failure
   is not reported: the entry is written either way, and the cache catches up
   on the next login. *)
let refresh_database dir =
  if Sys.command "command -v update-desktop-database >/dev/null 2>&1" = 0 then
    ignore
      (Sys.command
         (Printf.sprintf "update-desktop-database %s >/dev/null 2>&1"
            (Filename.quote dir)))

let install_desktop_entry ?name ?comment ?categories ?exec ~app_id ~icon () =
  (* This library links neither Unix nor threads, so there is no [uname] to
     call; /proc/version is the cheapest marker of a Linux kernel. *)
  if not (Sys.file_exists "/proc/version") then None
  else begin
    let exec = match exec with Some e -> e | None -> Sys.executable_name in
    let name = match name with Some n -> n | None -> app_id in
    check_value "app_id" app_id;
    check_value "icon" icon;
    check_value "exec" exec;
    check_value "name" name;
    Option.iter (check_value "comment") comment;
    if not (Sys.file_exists icon) then
      failwith
        (Printf.sprintf "install_desktop_entry: no such icon file: %s" icon);

    let buf = Buffer.create 256 in
    let add k v = Buffer.add_string buf (k ^ "=" ^ v ^ "\n") in
    Buffer.add_string buf "[Desktop Entry]\n";
    add "Type" "Application";
    add "Name" name;
    Option.iter (add "Comment") comment;
    add "Exec" exec;
    add "Icon" icon;
    (* What the shell matches the running process against. *)
    add "StartupWMClass" app_id;
    (* This describes a windowed application, never a console one. *)
    add "Terminal" "false";
    Option.iter
      (fun cs -> add "Categories" (String.concat ";" cs ^ ";"))
      categories;

    let dir = applications_dir () in
    (* The file's own name need not match [app_id], since StartupWMClass says
       which process it describes; it is namespaced to avoid colliding with
       anything else in a shared directory. *)
    let path = Filename.concat dir ("owebview-" ^ app_id ^ ".desktop") in
    mkdir_p dir;
    let oc = open_out path in
    Fun.protect
      ~finally:(fun () -> close_out_noerr oc)
      (fun () -> output_string oc (Buffer.contents buf));
    refresh_database dir;
    Some path
  end
