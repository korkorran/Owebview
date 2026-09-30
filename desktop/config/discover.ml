module C = Configurator.V1

(* Compile/link flags for icon_stubs.cpp and dialog_stubs.cpp.

   Nothing in this library includes vendor/webview.h, so it needs none of the
   web engines the core library links: no WebKit framework on macOS, no
   webkit2gtk-4.1 on Linux, and no WebView2 SDK header on Windows. What is left
   is the plain desktop toolkit of each platform. *)

(* C++ standard required to compile the stubs, on every platform. *)
let std_flags = [ "-std=c++11" ]

(* macOS: NSApplication/NSImage, NSAlert and NSOpenPanel are all AppKit,
   reached through the Objective-C runtime C API, so Cocoa (which re-exports
   AppKit) is what this library adds.

   -lobjc and -lc++ are equally required, but they are deliberately left out:
   this library depends on owebview, whose own link flags already carry them,
   and repeating them makes ld warn "ignoring duplicate libraries" on every
   executable that links both. *)
let macos_link_flags = [ "-framework"; "Cocoa" ]

let mingw_flags = [ "-std=c++14" ]

(* Windows: the icon is decoded with WIC (windowscodecs) through COM (ole32),
   turned into bitmaps with GDI (gdi32), and installed with SendMessage
   (user32). The dialogs add MessageBoxW (user32 again) and IFileOpenDialog,
   another COM component. uuid supplies the CLSID/IID symbols both of them
   reference; shell32 is listed alongside it because mingw-w64 distributions
   have not always agreed on which of the two archives carries the shell
   GUIDs, and an unused import library costs nothing.

   -static-libgcc and -static-libstdc++ mirror the core library: they fold the
   GCC runtime into the executable instead of leaving it to find
   libgcc_s_seh-1.dll and friends beside itself at startup. See the longer note
   in lib/config/discover.ml, including the caveat about -static-libstdc++
   being a g++-driver option. *)
let mingw_link_flags =
  [
    "-link";
    "-static-libgcc";
    "-link";
    "-static-libstdc++";
    "-lstdc++";
    "-lole32";
    "-luser32";
    "-lwindowscodecs";
    "-lgdi32";
    "-luuid";
    "-lshell32";
  ]

(* Linux: the window icon and the dialogs are GTK 3 calls, and the application
   id is GLib, which gtk+-3.0 pulls in. WebKitGTK is not involved. *)
let linux_packages = [ "gtk+-3.0" ]

(* Query pkg-config for each package and merge the results. Dies with a message
   that names the actual problem: pkg-config itself missing is a different
   failure from a missing -dev package. *)
let linux_flags c =
  let pc =
    match C.Pkg_config.get c with
    | Some pc -> pc
    | None ->
        C.die
          "pkg-config was not found, and it is needed to locate the desktop \
           native dependencies (%s). Under opam it comes from \
           conf-pkg-config; otherwise install your distribution's pkg-config \
           (or pkgconf) package."
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
      let cflags =
        List.concat
          (List.map (fun (c : C.Pkg_config.package_conf) -> c.cflags) confs)
      in
      let libs =
        List.concat
          (List.map (fun (c : C.Pkg_config.package_conf) -> c.libs) confs)
      in
      (cflags, libs)

let () =
  C.main ~name:"webview_desktop" (fun c ->
      let system =
        match C.ocaml_config_var c "system" with Some s -> s | None -> ""
      in
      let cflags, link_flags =
        match system with
        | "macosx" -> (std_flags, macos_link_flags)
        | "mingw64" -> (mingw_flags, mingw_link_flags)
        | _ ->
            let cflags, libs = linux_flags c in
            (* -lstdc++ links the GNU C++ runtime needed by the stub; on macOS
               this role is played by -lc++ in macos_link_flags. *)
            (std_flags @ cflags, "-lstdc++" :: libs)
      in
      C.Flags.write_sexp "c_flags.sexp" cflags;
      C.Flags.write_sexp "c_library_flags.sexp" link_flags)
