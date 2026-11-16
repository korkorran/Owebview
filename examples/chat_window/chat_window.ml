(* A chat window whose messages are typed in the terminal.

   The page (web/app.ml, OCaml compiled by js_of_ocaml) displays the list and
   exposes a [post] function on the global object. This file reads the
   terminal and calls it.

   The interesting part is the threading. [input_line] blocks, so the reader
   loop cannot run on the thread that owns the webview event loop -- it would
   freeze the window. It runs on its own thread instead, and because a webview
   may only be driven from the thread that called [run], the JavaScript call
   is handed over with [Webview.dispatch] rather than evaluated on the spot. *)

(* Quote a string as a JavaScript double-quoted literal.

   [Printf]'s "%S" is deliberately not used here: it escapes bytes >= 0x80 as
   a decimal "\ddd", which JavaScript reads as a legacy *octal* escape, so a
   pseudonym or a message containing "é" would reach the page mangled. JS
   source is UTF-8, so raw bytes are passed through and only the characters
   that would close the literal or break the line get escaped. *)
let js_quote s =
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

(* Read one line, prompting for it. Raises [End_of_file] on Ctrl-D. *)
let ask prompt =
  print_string prompt;
  flush stdout;
  String.trim (input_line stdin)

(* Post one message into the page. [post] only exists once app.js has run its
   DOMContentLoaded handler, so guard against a message typed before the page
   has finished loading. *)
let post w ~author ~text =
  let js =
    Printf.sprintf "if (typeof post === 'function') post(%s, %s);"
      (js_quote author) (js_quote text)
  in
  Webview.dispatch w (fun w -> Webview.eval w js)

(* Pseudonym, then message, over and over, until end of input. *)
let rec terminal_loop w =
  let author = ask "\npseudonym> " in
  let text = ask "message> " in
  let author = if author = "" then "anonymous" else author in
  if text <> "" then post w ~author ~text;
  terminal_loop w

let () =
  let w = Webview.create ~debug:true () in
  Webview.set_title w "Chat window";
  Webview.set_size w ~width:420 ~height:520 Webview.Hint_none;

  let index =
    Filename.concat (Webview_desktop.Locate_assets.assets_dir "web") "index.html"
  in
  Webview.navigate w ("file://" ^ index);

  print_endline
    "Type a pseudonym, then a message, to post it in the window. Ctrl-D stops \
     listening.";
  let _ : Thread.t =
    Thread.create
      (fun () -> try terminal_loop w with End_of_file -> print_newline ())
      ()
  in

  Webview.run w;
  Webview.destroy w
