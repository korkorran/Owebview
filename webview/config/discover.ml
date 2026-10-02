module C = Configurator.V1

(* C++ standard required to compile webview_stubs.cpp, on every platform. *)
let std_flags = [ "-std=c++11" ]

(* macOS: WebKit/Cocoa are system frameworks, no pkg-config needed. *)
let macos_link_flags =
  [ "-lc++"; "-lobjc"; "-framework"; "WebKit"; "-framework"; "Cocoa" ]

let mingw_flags = [ "-std=c++14";  ]

(* -static-libgcc and -static-libstdc++ fold the GCC runtime into the
   executable instead of leaving it to find libgcc_s_seh-1.dll,
   libstdc++-6.dll and libwinpthread-1.dll beside itself at startup. Without
   them a program linked against this library is not redistributable on its
   own: it runs on the machine that built it, where the toolchain's bin/ is on
   PATH, and fails everywhere else.

   The two halves are not obtained the same way. -static-libgcc is handled by
   the common gcc driver and takes effect as written.

   libstdc++ needs the blunter form. -static-libstdc++ is implemented by the
   *g++* driver (g++spec.cc), which swaps the -lstdc++ it adds itself for the
   static archive; OCaml links through the C driver against an explicit
   -lstdc++, so that option is a no-op here — which is why it is gone and
   "-l:libstdc++.a" takes its place. That spelling names the archive outright
   and does not depend on which driver is in use.

   Verify on Windows with:

     objdump -p _build/default/<your exe> | grep 'DLL Name'

   Nothing belonging to the toolchain should be listed. Should the link fail
   instead on unresolved pthread symbols, this toolchain builds libstdc++
   against posix threads, and "-link" "-l:libwinpthread.a" has to join the
   list below. *)
let mingw_link_flags =
  [ "-link"; "-static-libgcc"; "-link"; "-l:libstdc++.a"; "-ladvapi32"; "-lole32"; "-lshell32"; "-lshlwapi"; "-luser32"; "-lversion" ]

(* Linux: the webview backend is GTK 3 + WebKitGTK. *)
let linux_packages = [ "gtk+-3.0"; "webkit2gtk-4.1" ]

(* Query pkg-config for each package and merge the results. Dies with a message
   that names the actual problem: pkg-config itself missing is a different
   failure from a missing -dev package, and conflating the two sends people
   hunting for the wrong thing. *)
let linux_flags c =
  let pc =
    match C.Pkg_config.get c with
    | Some pc -> pc
    | None ->
        C.die
          "pkg-config was not found, and it is needed to locate the webview \
           native dependencies (%s). Under opam it comes from conf-pkg-config; \
           otherwise install your distribution's pkg-config (or pkgconf) \
           package."
          (String.concat " " linux_packages)
  in
  let results =
    List.map (fun p -> (p, C.Pkg_config.query pc ~package:p)) linux_packages
  in
  match List.filter (fun (_, r) -> r = None) results with
  | _ :: _ as missing ->
      C.die
        "pkg-config is installed but could not find: %s. Install the \
         corresponding development packages (see the package depexts)."
        (String.concat " " (List.map fst missing))
  | [] ->
      let confs = List.filter_map snd results in
      let cflags = List.concat (List.map (fun (c : C.Pkg_config.package_conf) -> c.cflags) confs) in
      let libs = List.concat (List.map (fun (c : C.Pkg_config.package_conf) -> c.libs) confs) in
      (cflags, libs)

let () =
  C.main ~name:"webview" (fun c ->
      let system =
        match C.ocaml_config_var c "system" with Some s -> s | None -> ""
      in
      let cflags, link_flags =
        match system with
        | "macosx" -> (std_flags, macos_link_flags)
        | "mingw64" ->
            (* WebView2.h: see webview2_sdk.ml. *)
            (Webview2_sdk.cflags () @ mingw_flags, mingw_link_flags)
        | _ ->
            (* Assume a Linux system with pkg-config + the -dev packages;
               linux_flags reports precisely what is missing otherwise. *)
            let cflags, libs = linux_flags c in
            (* -lstdc++ links the GNU C++ runtime needed by the stub; on macOS
               this role is played by -lc++ in macos_link_flags. *)
            (std_flags @ cflags, "-lstdc++" :: libs)
      in
      C.Flags.write_sexp "c_flags.sexp" cflags;
      C.Flags.write_sexp "c_library_flags.sexp" link_flags)
