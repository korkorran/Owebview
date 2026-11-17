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

(* A string as a JSON literal, ready for [Webview.return]'s result or for
   interpolation into an [eval] snippet. *)
let quote s = Yojson.Safe.to_string (`String s)

(* Files are read into a JSON reply, so a huge one would be paid for three
   times over: read, encoded, then parsed by the page. A megabyte is plenty to
   look at. *)
let max_bytes = 1024 * 1024

(* Read at most [max_bytes], and say whether anything was left behind. *)
let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let size = in_channel_length ic in
      let len = min size max_bytes in
      (really_input_string ic len, size > max_bytes))

(* The file currently on screen, so that "Save as" knows what to copy. *)
let current = ref None

(* Copy through a temporary file in the destination's own directory, then
   rename over it. The detour matters: saving onto the source itself would
   otherwise truncate it at [open_out] and the copy would read back nothing.
   The rename also makes the replacement atomic. *)
let copy_file src dst =
  let tmp = Filename.temp_file ~temp_dir:(Filename.dirname dst) "owebview" ".tmp" in
  match
    let ic = open_in_bin src in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        let oc = open_out_bin tmp in
        Fun.protect
          ~finally:(fun () -> close_out_noerr oc)
          (fun () ->
            let buf = Bytes.create 65536 in
            let rec loop () =
              let n = input ic buf 0 (Bytes.length buf) in
              if n > 0 then (
                output oc buf 0 n;
                loop ())
            in
            loop ();
            flush oc))
  with
  | () -> Sys.rename tmp dst
  | exception e ->
      (try Sys.remove tmp with Sys_error _ -> ());
      raise e

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
              (quote
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
              current := Some path;
              answer ~error:false
                (Printf.sprintf {|{"path":%s,"content":%s,"truncated":%b}|}
                   (quote path) (quote content) truncated)));

  (* window.save_as() -> Promise<string | null>
     The displayed file is copied, not the bytes the page holds: those are
     capped at max_bytes, and writing them back would silently produce a
     truncated file. *)
  Webview.bind w "save_as" (fun id _req ->
      let answer ~error result = Webview.return w id ~error ~result in
      match !current with
      | None -> answer ~error:true (quote "No file to save — pick one first")
      | Some src -> (
          let name = Filename.basename src in
          match
            Webview_desktop.Dialog.save_file w ~title:"Save a copy of the file"
              ~name ()
          with
          | None -> answer ~error:false "null"
          | Some dst -> (
              match copy_file src dst with
              | () -> answer ~error:false (quote dst)
              | exception Sys_error msg ->
                  answer ~error:true
                    (quote (Printf.sprintf "Could not save: %s" msg)))));

  let index =
    Filename.concat (Webview_desktop.Locate_assets.assets_dir "web") "index.html"
  in
  Webview.navigate w ("file://" ^ index);

  Webview.run w;
  Webview.destroy w
