let () =
  (* Library version info (no window needed). *)
  let v = Webview.version () in
  Printf.printf "using webview %s\n%!" v.Webview.version_number;

  let w = Webview.create ~debug:true () in
  Webview.set_title w "Hello from OCaml";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;

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
      let result = Printf.sprintf "show(%S)" (Utils.detect_os ()) in
      Webview.eval w result;
      Webview.return w id ~error:false ~result:"");

  (* Load the page from on-disk files (web/) instead of an inline HTML string.
     The CSS and JS referenced with relative paths in index.html are resolved
     relative to that file. We locate the web/ directory from the executable
     location, so it works both installed and from the build tree. *)
  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
