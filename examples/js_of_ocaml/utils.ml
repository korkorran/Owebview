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
