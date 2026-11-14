(* Filesystem helpers for locating on-disk assets relative to the running
   executable, independently of the current working directory. *)

(* Absolute path to the directory containing the running executable. *)
let exe_dir () =
  let dir = Filename.dirname Sys.executable_name in
  if Filename.is_relative dir then Filename.concat (Sys.getcwd ()) dir else dir

(* Locate a directory of on-disk assets (index.html + style.css + app.js),
   independently of the current working directory.

   [path] says where that directory sits {b relative to the executable}, not
   relative to the cwd: ["web"] for a subdirectory beside the binary,
   ["../web"] for a directory next to the one holding the binary, and so on.
   An absolute [path] is returned unchanged, for assets installed at a fixed
   location.

   Resolving against the executable is what makes a build tree relocatable --
   the assets travel with the binary -- and it is where a build puts them:
   both the files staged from the sources and the {e generated} ones, such as
   a js_of_ocaml bundle, which exist nowhere else.

   The corollary is that the assets must have been built. Under dune that
   means [dune build], which stages them through the [all] alias, and not
   [dune exec <exe>] alone, which builds the executable and nothing beside it.

   No normalisation is performed: the two halves are joined with
   [Filename.concat], so a ["../web"] keeps its [..] in the result. Both the
   filesystem and the [file://] URLs built from it resolve those on their
   own. *)
let assets_dir path =
  if Filename.is_relative path then Filename.concat (exe_dir ()) path else path
