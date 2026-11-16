(* Display a file the user picks with the system file browser.

   The page (web/app.ml, OCaml compiled by js_of_ocaml) owns the button and
   the display; this file owns the dialog and the filesystem. They meet at one
   binding, window.pick_file(), which resolves with the chosen path and the
   file's contents.

   The binding callback runs on the UI thread, which is where a modal dialog
   has to be shown, so no [Webview.dispatch] is involved. The file is read
   there too: the window is unresponsive while that happens, which is harmless
   at the size cap below but would not be for a backend doing real work --
   see examples/timer for how to move that off the UI thread. *)

(* Files are read into a JSON reply, so a huge one would be paid for three
   times over: read, encoded, then parsed by the page. A megabyte is plenty to
   look at. *)
let max_bytes = 1024 * 1024

(* Quote a string as a JSON string literal.

   [Printf]'s "%S" is deliberately not used: it escapes bytes >= 0x80 as a
   decimal "\ddd", which JSON does not accept, so the page's JSON.parse would
   reject the whole reply for any file containing an accent. JSON strings are
   UTF-8, so raw bytes are passed through and only what would close the
   literal or break the line is escaped. *)
let json_quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c < 0x20 || Char.code c = 0x7f ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

(* Read at most [max_bytes], and say whether anything was left behind. *)
let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let size = in_channel_length ic in
      let len = min size max_bytes in
      (really_input_string ic len, size > max_bytes))

let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "File reader";
  Webview.set_size w ~width:640 ~height:520 Webview.Hint_none;

  (* window.pick_file() -> Promise<{path, content, truncated} | null>
     null means the user cancelled; a rejection carries a message to display. *)
  Webview.bind w "pick_file" (fun id _req ->
      let answer ~error result = Webview.return w id ~error ~result in
      match Webview_desktop.Dialog.open_file w ~title:"Choose a file" () with
      | None -> answer ~error:false "null"
      | Some path -> (
          (* Rejection messages name the file that could not be opened: the
             page keeps showing the previous one, so a bare "not a text file"
             would read as a comment on what is still on screen. *)
          let failed reason =
            answer ~error:true
              (json_quote
                 (Printf.sprintf "Could not display %s: %s"
                    (Filename.basename path) reason))
          in
          match read_file path with
          | exception Sys_error msg -> failed msg
          | content, _ when not (String.is_valid_utf_8 content) ->
              (* The reply travels as JSON, which is UTF-8 only: handing the
                 page the bytes of a PNG would fail in JSON.parse with a
                 message about the reply rather than about the file. *)
              failed "not a UTF-8 text file"
          | content, truncated ->
              answer ~error:false
                (Printf.sprintf {|{"path":%s,"content":%s,"truncated":%b}|}
                   (json_quote path) (json_quote content) truncated)));

  let index =
    Filename.concat (Webview_desktop.Locate_assets.assets_dir "web") "index.html"
  in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
