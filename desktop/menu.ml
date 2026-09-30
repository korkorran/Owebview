(* The native side builds the menu incrementally through opaque handles (an
   NSMenu, a GtkMenuShell or an HMENU) rather than receiving the tree below,
   so the tree walk lives here -- see menu_stubs.cpp.

   Activation goes through a single closure registered once with the stub: it
   receives the integer command id of the chosen item, and looks the real
   callback up in [callbacks]. One GC root for the whole menu, instead of one
   per item. *)

external raw_set_dispatch : (int -> unit) -> unit
  = "ocaml_webview_menu_set_dispatch"

external raw_create_bar : unit -> nativeint = "ocaml_webview_menu_create_bar"

external raw_add_submenu : nativeint -> string -> nativeint
  = "ocaml_webview_menu_add_submenu"

external raw_add_item : nativeint -> string -> string -> int -> int -> unit
  = "ocaml_webview_menu_add_item"

external raw_add_separator : nativeint -> unit
  = "ocaml_webview_menu_add_separator"

external raw_install : nativeint -> nativeint -> unit
  = "ocaml_webview_menu_install"

type modifier = Cmd | Ctrl | Alt | Shift

type item =
  | Item of {
      label : string;
      key : char option;
      modifiers : modifier list;
      on_click : unit -> unit;
    }
  | Separator
  | Submenu of { label : string; items : item list }

let item ?key ?(modifiers = []) label on_click =
  Item { label; key; modifiers; on_click }

let separator = Separator
let submenu label items = Submenu { label; items }

(* Command ids are never reused, so a stale id left over in a menu that is
   being replaced can never reach a new callback. *)
let callbacks : (int, unit -> unit) Hashtbl.t = Hashtbl.create 16
let next_command = ref 0
let dispatch_registered = ref false

(* Keep in sync with the WV_MOD_* enum in menu_stubs.cpp. *)
let mask_of_modifiers modifiers =
  List.fold_left
    (fun acc m ->
      acc lor match m with Cmd -> 1 | Ctrl -> 2 | Alt -> 4 | Shift -> 8)
    0 modifiers

let rec add_items parent items = List.iter (add_item_to parent) items

and add_item_to parent = function
  | Separator -> raw_add_separator parent
  | Submenu { label; items } -> add_items (raw_add_submenu parent label) items
  | Item { label; key; modifiers; on_click } ->
      incr next_command;
      let command = !next_command in
      Hashtbl.replace callbacks command on_click;
      let key = match key with None -> "" | Some c -> String.make 1 c in
      raw_add_item parent label key (mask_of_modifiers modifiers) command

let dispatch command =
  match Hashtbl.find_opt callbacks command with Some f -> f () | None -> ()

let set w menus =
  if not !dispatch_registered then begin
    raw_set_dispatch dispatch;
    dispatch_registered := true
  end;
  (* The previous bar is about to be replaced, so its callbacks go with it. *)
  Hashtbl.reset callbacks;
  let bar = raw_create_bar () in
  List.iter (fun (label, items) -> add_items (raw_add_submenu bar label) items)
    menus;
  raw_install (Webview.get_window w) bar
