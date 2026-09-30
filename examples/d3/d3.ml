let () =
  let w = Webview.create () in
  Webview.set_title w "Owebview - D3 chart";
  Webview.set_size w ~width:760 ~height:520 Webview.Hint_none;

  let icon = Filename.concat (Webview.Utils.web_dir ()) "rain.png" in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview_desktop.Icon.set_app_icon w icon);

  (* The chart is rendered entirely in the page with D3.js; no binding is
     needed. The web/ directory (with the vendored d3.v7.min.js) is located
     relative to the executable. *)
  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
