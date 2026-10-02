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

val asset_dir : unit -> string
(** Directory to resolve on-disk assets against. When launched via
    [dune exec], the executable lives under [_build/<context>/], where the
    source assets are not copied; this maps such a path back to the matching
    source directory. From an installed location the executable directory is
    used as-is. *)

val web_dir : ?dir:string -> unit -> string
(** Directory to resolve web assets against.

    This is [exe_dir ()/web] when that directory holds an [index.html] —
    which is where a build stages copied assets {e and} generated ones, such
    as a [js_of_ocaml] bundle — and [asset_dir ()/web] otherwise.

    [?dir] names the assets directory for projects that do not call it [web]:
    [web_dir ~dir:"assets" ()] looks for [assets/] in the same two places.
    It is a single directory name, not a path, and defaults to ["web"]. *)
