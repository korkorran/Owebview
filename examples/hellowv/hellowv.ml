
let () =
  (* Library version info (no window needed). *)
  let v = Webview.version () in
  Printf.printf "using webview %s\n%!" v.Webview.version_number;

  (* App id (Linux only, no-op elsewhere): must be set before [create] so it
     applies to the first window. On Linux this becomes the X11 WM_CLASS /
     Wayland app_id, which desktop shells match against an installed
     .desktop file to pick a Dock icon — see install-desktop-entry.sh and
     the set_app_id/set_app_icon docs in lib/webview.mli. *)
  Webview.set_app_id "hellowv";

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
    Webview.dispatch w (fun w -> Webview.set_app_icon w icon);

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

  (* Load the page from on-disk files (web/) instead of an inline HTML string.
     The CSS and JS referenced with relative paths in index.html are resolved
     relative to that file. We locate the web/ directory from the executable
     location, so it works both installed and from the build tree. *)
  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
