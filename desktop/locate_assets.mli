(** Locating on-disk assets.

    Filesystem helpers for finding an application's HTML, CSS, JavaScript and
    images relative to the running executable, independently of the current
    working directory — so that a page loads the same whether the program was
    started by [dune exec], from a Dock icon, or from another directory.

    {[
      let index =
        Filename.concat (Webview_desktop.Locate_assets.web_dir ()) "index.html"
      in
      Webview.navigate w ("file://" ^ index)
    ]} *)

val exe_dir : unit -> string
(** Absolute path to the directory containing the running executable. *)

val web_dir : ?dir:string -> unit -> string
(** Directory to resolve web assets against: [exe_dir ()/web].

    Beside the executable is where a build puts them — both the ones staged
    from your sources and any {e generated} ones, such as a [js_of_ocaml]
    bundle, which exist nowhere else. It is also what lets a copied build tree
    keep working, since the assets travel with the binary.

    So the assets have to have been built. With dune that means [dune build];
    [dune exec <exe>] on its own builds the executable and nothing beside it,
    and the page will not be found. Staging them is a matter of attaching a
    [glob_files] dependency on the directory to the [all] alias, next to the
    [executable] stanza.

    [?dir] names the assets directory for projects that do not call it [web]:
    [web_dir ~dir:"assets" ()] returns [exe_dir ()/assets]. It is a single
    directory name, not a path, and defaults to ["web"]. *)
