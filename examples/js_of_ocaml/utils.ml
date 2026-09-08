(* Best-effort detection of the host OS. On Unix systems [Sys.os_type] only
   reports "Unix", so we refine it with `uname` to tell macOS from Linux. *)
let detect_os () =
  match Sys.os_type with
  | "Win32" -> "Windows"
  | "Cygwin" -> "Cygwin"
  | _ ->
      let uname =
        try
          let ic = Unix.open_process_in "uname -s" in
          let line = try input_line ic with End_of_file -> "" in
          ignore (Unix.close_process_in ic);
          String.trim line
        with _ -> ""
      in
      (match uname with
       | "Darwin" -> "macOS"
       | "Linux" -> "Linux"
       | "" -> "Unix"
       | other -> other)

(* Quote a string as a JavaScript double-quoted literal.

   [Printf]'s "%S" is deliberately not used here: it escapes bytes >= 0x80 as a
   decimal "\ddd", which JavaScript reads as a legacy *octal* escape — a
   message containing "é" would reach the page mangled. JS source is UTF-8, so
   raw bytes are passed through and only the characters that would close the
   literal or break the line get escaped. *)
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
