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

   A caveat on the second one. -static-libstdc++ is implemented by the *g++*
   driver (g++spec.cc), which swaps the -lstdc++ it adds itself for the static
   archive. OCaml links through the C driver, and the -lstdc++ below is
   explicit, so the option may well be a no-op here. -static-libgcc has no
   such problem: it is handled by the common driver and does take effect.

   The way to find out is to build on Windows and look:

     objdump -p _build/default/<your exe> | grep 'DLL Name'

   If libstdc++-6.dll is still listed, replace "-lstdc++" below with
   "-l:libstdc++.a", which names the static archive outright and does not
   depend on which driver is in use. That is left as a follow-up rather than
   done here because it cannot be tested from a non-Windows host, and a
   toolchain built with posix threads may then also need "-lwinpthread". *)
let mingw_link_flags =
  [ "-link"; "-static-libgcc"; "-link"; "-static-libstdc++"; "-lstdc++"; "-ladvapi32"; "-lole32"; "-lshell32"; "-lshlwapi"; "-luser32"; "-lversion" ]

(* --- WebView2 SDK header discovery (Windows/mingw) --------------------------
   webview.h includes "WebView2.h", which ships in the Microsoft.Web.WebView2
   NuGet package. Its license forbids redistribution, so we do not vendor it;
   instead we locate the copy the user obtained from Microsoft. Search order:
     1. $MICROSOFT_WEB_WEBVIEW2 (explicit override);
     2. the NuGet global packages cache ($NUGET_PACKAGES, else
        %USERPROFILE%\.nuget\packages), newest microsoft.web.webview2\<version>
        that actually contains the header.
   Paths are joined with "/", which mingw's gcc accepts on Windows. *)

let webview2_include_of_base base = base ^ "/build/native/include"
let has_webview2_header inc = Sys.file_exists (inc ^ "/WebView2.h")

(* Compare NuGet versions ("1.0.2739.15") component-wise, numerically. *)
let version_compare a b =
  let ints s =
    List.map
      (fun x -> match int_of_string_opt x with Some n -> n | None -> 0)
      (String.split_on_char '.' s)
  in
  let rec cmp = function
    | x :: xs, y :: ys -> if x = y then cmp (xs, ys) else compare x y
    | [], [] -> 0
    | [], _ -> -1
    | _, [] -> 1
  in
  cmp (ints a, ints b)

let nuget_packages_root () =
  match Sys.getenv_opt "NUGET_PACKAGES" with
  | Some p -> Some p
  | None -> (
      match Sys.getenv_opt "USERPROFILE" with
      | Some home -> Some (home ^ "/.nuget/packages")
      | None -> None)

let nuget_webview2_include () =
  match nuget_packages_root () with
  | None -> None
  | Some root -> (
      let base = root ^ "/microsoft.web.webview2" in
      if not (Sys.file_exists base && Sys.is_directory base) then None
      else
        let with_header =
          Sys.readdir base |> Array.to_list
          |> List.filter_map (fun ver ->
                 let inc = base ^ "/" ^ ver ^ "/build/native/include" in
                 if has_webview2_header inc then Some (ver, inc) else None)
        in
        match
          List.sort (fun (a, _) (b, _) -> version_compare b a) with_header
        with
        | (_, inc) :: _ -> Some inc
        | [] -> None)

(* The WebView2 include directory, from the env override or the NuGet cache. *)
let webview2_include () =
  match Sys.getenv_opt "MICROSOFT_WEB_WEBVIEW2" with
  | Some path -> Some (webview2_include_of_base path)
  | None -> nuget_webview2_include ()

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
        | "mingw64" -> (
            match webview2_include () with
            | Some inc when has_webview2_header inc ->
                ("-isystem" :: inc :: mingw_flags, mingw_link_flags)
            | _ ->
                C.die
                  "could not find the WebView2 SDK header (WebView2.h). Install \
                   the Microsoft.Web.WebView2 NuGet package (e.g. `nuget install \
                   Microsoft.Web.WebView2`) so it lands in the NuGet cache, or \
                   set MICROSOFT_WEB_WEBVIEW2 to the package directory. \
                   Package: %s"
                  "https://www.nuget.org/packages/Microsoft.Web.WebView2")
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
