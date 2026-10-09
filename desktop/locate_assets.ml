(* Filesystem helpers for locating on-disk assets relative to the running
   executable, independently of the current working directory. *)

(* Absolute path to the directory containing the running executable. *)
let exe_dir () =
  let dir = Filename.dirname Sys.executable_name in
  if Filename.is_relative dir then Filename.concat (Sys.getcwd ()) dir else dir

(* Locate the directory holding the web assets (index.html + style.css +
   app.js), independently of the current working directory. [dir] names that
   directory, for projects that do not call it "web".

   The assets are read from beside the binary, and only from there: that is
   where a build both stages the ones copied from the sources and writes the
   {e generated} ones (an app.js produced by js_of_ocaml, say), which exist
   nowhere else. It also means a relocated copy of the build tree keeps
   working, since the assets travel with the executable.

   The corollary is that the assets must have been built. Under dune that is
   [dune build] -- which stages them through the [all] alias in the examples'
   dune files -- and not [dune exec <exe>] alone, which builds the executable
   and nothing beside it. *)
let web_dir ?(dir = "web") () = Filename.concat (exe_dir ()) dir
