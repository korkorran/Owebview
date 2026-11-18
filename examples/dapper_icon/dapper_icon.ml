(* An application icon, and nothing else.

   The smallest example that shows a window wearing a real icon instead of the
   generic executable one. There is no web/ directory here: the page is an
   inline HTML string, so the icon is the only file on disk and it sits
   directly beside the binary.

   What to look at is outside the window: the Dock on macOS, the taskbar or
   the window switcher on Linux and Windows.

   Run with --install-icon to install the desktop entry that Linux needs for
   any of that to show up under Wayland. *)

let page =
  {|<!doctype html>
    <html lang="en">
      <body style="font-family: system-ui; margin: 2rem; line-height: 1.5">
        <h2 style="margin-top: 0">Dapper</h2>
        <p>This window has no assets of its own — the page you are reading is
           an inline string.</p>
        <p>The one file it does carry is its icon. Look for the bow tie in the
           Dock, the taskbar, or the window switcher.</p>
      </body>
    </html>|}

(* The application id. It is what a Wayland desktop matches against the
   installed .desktop file, so [set_app_id] and the entry have to agree —
   passing the same string to both is what arranges that. *)
let app_id = "dapper_icon"

(* The icon lives beside the binary: [exe_dir] rather than [assets_dir],
   since this example has no web/ directory for the latter to find. *)
let icon_path () =
  Filename.concat (Webview_desktop.Locate_assets.exe_dir ()) "dapper.png"

(* --install-icon: write the .desktop entry, then say what happened.

   All of the work is in the library — [Webview_desktop.Icon] knows where the
   entry belongs and what it must contain. What is left here is the policy an
   application has to choose for itself: which labels to use, and what to tell
   the user afterwards. *)
let install_icon () =
  match
    Webview_desktop.Icon.install_desktop_entry ~app_id ~icon:(icon_path ())
      ~name:"Dapper (owebview)" ~comment:"owebview dapper_icon example"
      ~categories:[ "Development" ] ()
  with
  | None ->
      prerr_endline
        "--install-icon only applies on Linux: elsewhere the icon comes from \
         the application itself, and this example already sets it.";
      exit 1
  | Some path ->
      Printf.printf "Installed %s\n" path;
      print_endline
        "Run it again without the option — the bow tie should now show in the \
         Dock or taskbar.";
      Printf.printf "Undo with: rm %s\n" (Filename.quote path)

let run_window () =
  (* Linux only, no-op elsewhere, and it has to come before [create] so that it
     applies to the first window. This is the id the installed .desktop file
     carries as StartupWMClass. *)
  Webview_desktop.Icon.set_app_id app_id;

  let w = Webview.create () in
  Webview.set_title w "Dapper";
  Webview.set_size w ~width:420 ~height:300 Webview.Hint_none;
  Webview.set_html w page;

  (* Dispatched, not called outright: on macOS the process only becomes a
     Dock-visible application once [run] has started, and an icon set before
     that is ignored. The callback runs on the UI thread once the loop is
     going. *)
  let icon = icon_path () in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview_desktop.Icon.set_app_icon w icon)
  else prerr_endline "dapper.png is missing — run `dune build` first";

  Webview.run w;
  Webview.destroy w

let () =
  match List.tl (Array.to_list Sys.argv) with
  | [] -> run_window ()
  | [ "--install-icon" ] -> (
      try install_icon ()
      with Failure msg ->
        prerr_endline msg;
        exit 1)
  | _ ->
      prerr_endline "usage: dapper_icon [--install-icon]";
      exit 2
