
let () =
  (* Library version info (no window needed). *)
  let v = Webview.version () in
  Printf.printf "using webview %s\n%!" v.Webview.version_number;

  (* App id (Linux only, no-op elsewhere): must be set before [create] so it
     applies to the first window. On Linux this becomes the X11 WM_CLASS /
     Wayland app_id, which desktop shells match against an installed
     .desktop file to pick a Dock icon — see install-desktop-entry.sh and
     the set_app_id/set_app_icon docs in desktop/icon.mli. *)
  Webview_desktop.Icon.set_app_id "hellowv";

  let w = Webview.create ~debug:true () in
  Webview.set_title w "Hello from OCaml";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;

  (* Custom Dock icon: if a hello.png sits next to the web assets, use it
     instead of the generic executable icon. Drop your own hello.png in
     examples/hellowv/web/ to see it. webview only turns the process into a
     regular (Dock-visible) app inside applicationDidFinishLaunching:, which
     fires *after* [run] starts, so we set the icon from a dispatched callback
     (it runs on the UI thread once the app is active) — setting it before [run]
     is too early and the Dock ignores it (macOS).

     On Linux, this alone only sets the window icon (taskbar/switcher) and,
     under X11, _NET_WM_ICON. GNOME's Dock under Wayland ignores it entirely
     and instead needs an installed .desktop file matching set_app_id above
     — run ./install-desktop-entry.sh once to see it there too. *)
  let icon = Filename.concat (Webview.Utils.web_dir ()) "hello.png" in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview_desktop.Icon.set_app_icon w icon);

  (* Native handles (opaque pointers, for platform-specific FFI such as a file
     dialog). 0n means unavailable. *)
  Printf.printf "native window handle = %nx\n%!" (Webview.get_window w);
  ignore (Webview.get_native_handle w Webview.Browser_controller);

  (* Expose window.add(a, b) to JS. [req] is a JSON array of the arguments. *)
  Webview.bind w "add" (fun id req ->
      Printf.printf "binding called <add>: id=%s req=%s\n%!" id req;
      let result =
        match Scanf.sscanf_opt req "[%d,%d]" (fun a b -> a + b) with
        | Some n -> string_of_int n
        | None -> "null"
      in
      Webview.return w id ~error:false ~result);

  (* Expose window.os_type() to JS. Returns the host OS as a JSON string. *)
  Webview.bind w "os_type" (fun id req ->
      Printf.printf "binding called <os_type>: id=%s req=%s\n%!" id req;
      let result = Printf.sprintf "%S" (Utils.detect_os ()) in
      Webview.return w id ~error:false ~result);

  (* The native file browser, shared by the binding and the menu item below.
     Both callers already run on the UI thread, which is where a modal dialog
     has to be shown, so neither needs a [dispatch]: the call blocks until the
     user answers and the window behind it is unresponsive meanwhile — that is
     what "modal" means. See desktop/dialog.mli. *)
  let choose_file () =
    Webview_desktop.Dialog.open_file w ~title:"Choose a file" ()
  in

  (* Expose window.pick_file() to JS: hand the chosen path back to the page,
     or null if the user cancelled. *)
  Webview.bind w "pick_file" (fun id req ->
      Printf.printf "binding called <pick_file>: id=%s req=%s\n%!" id req;
      let result =
        match choose_file () with
        | Some path -> Utils.json_quote path
        | None -> "null"
      in
      Webview.return w id ~error:false ~result);

  (* Show a value in the page's <pre id="out">, through the [show] function
     app.js puts on the global object. *)
  let show_in_page w text =
    Webview.eval w
      (Printf.sprintf "if (typeof show === 'function') show(%s);"
         (Utils.json_quote text))
  in

  (* A native menu bar, doing from the system menu what the buttons do from
     the page. Installed from a [dispatch] callback because on macOS the
     application only has a menu bar once it is active, which happens after
     [run] starts — the same timing constraint as the Dock icon above.

     Menu callbacks run on the UI thread, so they can drive the webview
     directly. Note the macOS convention the first entry relies on: the system
     draws it with the application's own name, whatever title we give it, so
     that is where Quit belongs. *)
  Webview.dispatch w (fun w ->
      let module Menu = Webview_desktop.Menu in
      Menu.set w
        [
          ( "hellowv",
            [
              Menu.item "Quit" ~key:'q' ~modifiers:[ Menu.Cmd ] (fun () ->
                  Webview.terminate w);
            ] );
          ( "File",
            [
              Menu.item "Open…" ~key:'o' ~modifiers:[ Menu.Cmd ] (fun () ->
                  match choose_file () with
                  | Some path -> show_in_page w path
                  | None -> show_in_page w "(cancelled)");
              Menu.separator;
              Menu.item "OS type" (fun () ->
                  show_in_page w (Utils.detect_os ()));
            ] );
        ]);

  (* Load the page from on-disk files (web/) instead of an inline HTML string.
     The CSS and JS referenced with relative paths in index.html are resolved
     relative to that file. We locate the web/ directory from the executable
     location, so it works both installed and from the build tree. *)
  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
