(* Filesystem helpers for locating on-disk assets relative to the running
   executable, independently of the current working directory. *)

(* Absolute path to the directory containing the running executable. *)
let exe_dir () =
  let dir = Filename.dirname Sys.executable_name in
  if Filename.is_relative dir then Filename.concat (Sys.getcwd ()) dir else dir

(* Directory to resolve on-disk assets against, independently of the cwd.

   When launched via [dune exec], the executable lives under
   [<root>/_build/<context>/...] but the source assets are not copied there.
   We map such a path back to the matching source directory so the assets are
   found. When run from an installed location (no [_build] segment) the
   executable directory is used as-is. *)
let asset_dir () =
  let rec strip = function
    | "_build" :: _context :: rest -> rest (* drop "_build/<context>/" *)
    | x :: rest -> x :: strip rest
    | [] -> []
  in
  String.concat Filename.dir_sep
    (strip (String.split_on_char '/' (exe_dir ())))

(* Locate the directory holding the web assets (index.html + style.css +
   app.js), independently of the current working directory. [dir] names that
   directory, for projects that do not call it "web".

   We read from the {b target} directory next to the binary ([exe_dir/dir]),
   because it holds both the staged source assets and any {e generated} ones
   (e.g. an app.js produced by js_of_ocaml) — the source tree has only the
   former. [dune build] stages/generates them there (see the [all] alias in the
   examples' dune files); a [_build] copy relocated elsewhere keeps working
   since the assets sit beside the binary. Falling back to the source tree
   ([asset_dir/dir]) only covers the case where nothing was staged yet. *)
let web_dir ?(dir = "web") () =
  let has_index d = Sys.file_exists (Filename.concat d "index.html") in
  let beside_binary = Filename.concat (exe_dir ()) dir in
  if has_index beside_binary then beside_binary
  else Filename.concat (asset_dir ()) dir
