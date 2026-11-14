(** Locating on-disk assets.

    Filesystem helpers for finding an application's HTML, CSS, JavaScript and
    images relative to the running executable, independently of the current
    working directory — so that a page loads the same whether the program was
    started by [dune exec], from a Dock icon, or from another directory.

    {[
      let index =
        Filename.concat (Webview_desktop.Locate_assets.assets_dir "web")
          "index.html"
      in
      Webview.navigate w ("file://" ^ index)
    ]} *)

val exe_dir : unit -> string
(** Absolute path to the directory containing the running executable. *)

val assets_dir : string -> string
(** [assets_dir path] is the assets directory [path] names, resolved against
    {!exe_dir} rather than against the current working directory.

    [path] therefore says where the assets sit {b relative to the
    executable}, and nothing is assumed about their name or depth:

    - [assets_dir "web"] — a [web/] directory beside the binary, the usual
      layout;
    - [assets_dir "../web"] — a directory next to the one holding the binary,
      for instance when several executables share one set of assets;
    - [assets_dir "/opt/myapp/web"] — an absolute path, returned unchanged.

    Resolving against the executable is what lets a build tree be copied or
    moved and keep working, and it is where a build puts the assets: both the
    files staged from your sources and any {e generated} ones, such as a
    [js_of_ocaml] bundle, which exist nowhere else.

    So the assets have to have been built. With dune that means [dune build];
    [dune exec <exe>] on its own builds the executable and nothing beside it,
    and the page will not be found. Staging them is a matter of attaching a
    [glob_files] dependency on the directory to the [all] alias, next to the
    [executable] stanza.

    The result is not normalised: it is {!exe_dir} and [path] joined with
    [Filename.concat], so ["../web"] keeps its [..]. Both the filesystem and
    the [file://] URLs built from it resolve that on their own. *)
