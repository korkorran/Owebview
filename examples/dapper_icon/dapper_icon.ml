(* An application icon, and nothing else.

   The smallest example that shows a window wearing a real icon instead of the
   generic executable one. There is no web/ directory here: the page is an
   inline HTML string, so the icon is the only file on disk and it sits
   directly beside the binary.

   What to look at is outside the window: the Dock on macOS, the taskbar or
   the window switcher on Linux and Windows. *)

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

let () =
  (* Linux only, no-op elsewhere, and it has to come before [create] so that it
     applies to the first window. Under Wayland the desktop matches this id
     against an installed .desktop file to find the icon; see
     examples/hellowv/install-desktop-entry.sh. *)
  Webview_desktop.Icon.set_app_id "dapper_icon";

  let w = Webview.create () in
  Webview.set_title w "Dapper";
  Webview.set_size w ~width:420 ~height:300 Webview.Hint_none;
  Webview.set_html w page;

  (* [exe_dir] rather than [assets_dir]: with no web/ directory, the icon is
     staged straight beside the binary by the alias in dune. *)
  let icon =
    Filename.concat (Webview_desktop.Locate_assets.exe_dir ()) "dapper.png"
  in

  (* Dispatched, not called outright: on macOS the process only becomes a
     Dock-visible application once [run] has started, and an icon set before
     that is ignored. The callback runs on the UI thread once the loop is
     going. *)
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview_desktop.Icon.set_app_icon w icon)
  else prerr_endline "dapper.png is missing — run `dune build` first";

  Webview.run w;
  Webview.destroy w
