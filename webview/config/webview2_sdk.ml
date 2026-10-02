(* --- WebView2 SDK header discovery (Windows/mingw) --------------------------
   webview.h includes "WebView2.h", which ships in the Microsoft.Web.WebView2
   NuGet package. Its license forbids redistribution, so we do not vendor it;
   instead we locate the copy the user obtained from Microsoft. Search order:
     1. $MICROSOFT_WEB_WEBVIEW2 (explicit override);
     2. the NuGet global packages cache ($NUGET_PACKAGES, else
        %USERPROFILE%\.nuget\packages), newest microsoft.web.webview2\<version>
        that actually contains the header.
   Paths are joined with "/", which mingw's gcc accepts on Windows.

   This module is shared: desktop/config copies it in with copy_files, because
   the menu stubs need the same header (see desktop/menu_stubs.cpp). *)

module C = Configurator.V1

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

(* The compile flags that put WebView2.h on the include path, or a build
   failure that says where to get it. *)
let cflags () =
  match webview2_include () with
  | Some inc when has_webview2_header inc -> [ "-isystem"; inc ]
  | _ ->
      C.die
        "could not find the WebView2 SDK header (WebView2.h). Install the \
         Microsoft.Web.WebView2 NuGet package (e.g. `nuget install \
         Microsoft.Web.WebView2`) so it lands in the NuGet cache, or set \
         MICROSOFT_WEB_WEBVIEW2 to the package directory. Package: %s"
        "https://www.nuget.org/packages/Microsoft.Web.WebView2"
