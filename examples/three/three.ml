let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "three.js - geometry shapes";
  Webview.set_size w ~width:960 ~height:600 Webview.Hint_none;

  let icon = Filename.concat (Webview.Utils.web_dir ()) "3D.png" in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview.set_app_icon w icon);

  (* The 3D scene is rendered entirely in the page with the vendored three.js
     (WebGL); no binding is needed. The web/ directory (with three.min.js) is
     located relative to the executable. *)
  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
