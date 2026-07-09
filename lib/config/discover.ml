module C = Configurator.V1

(* C++ standard required to compile webview_stubs.cpp, on every platform. *)
let std_flags = [ "-std=c++11" ]

(* macOS: WebKit/Cocoa are system frameworks, no pkg-config needed. *)
let macos_link_flags =
  [ "-lc++"; "-lobjc"; "-framework"; "WebKit"; "-framework"; "Cocoa" ]

let mingw_flags = [ "-std=c++14";  ]

let mingw_link_flags =
  [ "-lstdc++"; "-ladvapi32"; "-lole32"; "-lshell32"; "-lshlwapi"; "-luser32"; "-lversion" ]
(* Linux: the webview backend is GTK 3 + WebKitGTK. *)
let linux_packages = [ "gtk+-3.0"; "webkit2gtk-4.1" ]

(* Query pkg-config for each package and merge the results. Returns None if
   pkg-config is unavailable or any package is missing. *)
let linux_flags c =
  match C.Pkg_config.get c with
  | None -> None
  | Some pc ->
      let results = List.map (fun p -> C.Pkg_config.query pc ~package:p) linux_packages in
      if List.mem None results then None
      else
        let confs =
          List.map (function Some conf -> conf | None -> assert false) results
        in
        let cflags = List.concat (List.map (fun (c : C.Pkg_config.package_conf) -> c.cflags) confs) in
        let libs = List.concat (List.map (fun (c : C.Pkg_config.package_conf) -> c.libs) confs) in
        Some (cflags, libs)

let () =
  C.main ~name:"webview" (fun c ->
      let system =
        match C.ocaml_config_var c "system" with Some s -> s | None -> ""
      in
      let cflags, link_flags =
        match system with
        | "macosx" -> (std_flags, macos_link_flags)
        | "mingw64" ->
            begin match (Sys.getenv_opt "MICROSOFT_WEB_WEBVIEW2") with
            | Some webview2_path ->
              let mingw_flags = [ "-isystem"; webview2_path ^ "/build/native/include" ] @  mingw_flags in
              (mingw_flags, mingw_link_flags)
            | None ->
                C.die
                  "the environment variable MICROSOFT_WEB_WEBVIEW2 is not \
                   set. Please download the package from %s and declare the path in \
                   the environment."
                  "https://www.nuget.org/packages/Microsoft.Web.WebView2"
            end
        | _ -> (
            (* Assume a Linux system with pkg-config + the -dev packages. *)
            match linux_flags c with
            (* -lstdc++ links the GNU C++ runtime needed by the stub; on macOS
               this role is played by -lc++ in macos_link_flags. *)
            | Some (cflags, libs) -> (std_flags @ cflags, "-lstdc++" :: libs)
            | None ->
                C.die
                  "could not detect the webview native dependencies via \
                   pkg-config (need %s). Install the -dev packages (see the \
                   package depexts)."
                  (String.concat " " linux_packages))
      in
      C.Flags.write_sexp "c_flags.sexp" cflags;
      C.Flags.write_sexp "c_library_flags.sexp" link_flags)
