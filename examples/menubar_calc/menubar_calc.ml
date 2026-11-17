(* A calculator with no buttons: every operation is a menu bar item.

   The number and the history of operations live here; the page (web/app.ml,
   OCaml compiled by js_of_ocaml) is a view that the application redraws after
   every change.

   Menu callbacks run on the UI thread, so they may drive the webview
   directly: no [Webview.dispatch] below except around [Menu.set] itself,
   which on macOS has to wait until the application is active. *)

module Menu = Webview_desktop.Menu

(* A string as a JSON literal, ready for [Webview.return]'s result or for
   interpolation into an [eval] snippet. *)
let quote s = Yojson.Safe.to_string (`String s)

(* Integers print without a decimal point; anything else keeps enough digits
   to stay honest (dividing 7 by 2 gives 3.5, not 3). *)
let show_number x =
  if Float.is_integer x && Float.abs x < 1e15 then Printf.sprintf "%.0f" x
  else Printf.sprintf "%.6g" x

let random_number () = float_of_int (1 + Random.int 100)

(* The whole application state. *)
let value = ref 0.
let history = ref [] (* most recent first *)

let render w =
  let entries =
    List.rev_map
      (fun (op, result) ->
        Printf.sprintf {|{"op":%s,"result":%s}|} (quote op)
          (quote (show_number result)))
      !history
  in
  Webview.eval w
    (Printf.sprintf {|render({"value":%s,"history":[%s]});|}
       (quote (show_number !value))
       (String.concat "," entries))

(* Apply one operation, record it, redraw. *)
let apply w op f =
  value := f !value;
  history := (op, !value) :: !history;
  render w

let reset w op n =
  value := n;
  history := (op, n) :: !history;
  render w

let menus w =
  let scaled sign symbol op amounts modifiers =
    List.map
      (fun (amount, key) ->
        Menu.item
          (Printf.sprintf "%s %g" sign amount)
          ~key ~modifiers
          (fun () -> apply w (Printf.sprintf "%s %g" symbol amount) (op amount)))
      amounts
  in
  [
    (* macOS draws the first menu as the application menu, with the process's
       own name whatever title we give it, so that is where Quit belongs —
       anything else put here would be hidden under a name nobody expects. *)
    ( "menubar_calc",
      [ Menu.item "Quit" ~key:'q' ~modifiers:[ Menu.Cmd ] (fun () ->
            Webview.terminate w) ] );
    ( "Number",
      [
        Menu.item "Random number" ~key:'r' ~modifiers:[ Menu.Cmd ] (fun () ->
            reset w "random" (random_number ()));
        (* No native dialog asks for a number, so the page's prompt does. *)
        Menu.item "Set to a number…" ~key:'k' ~modifiers:[ Menu.Cmd ] (fun () ->
            Webview.eval w "askNumber();");
      ] );
    ( "Add",
      scaled "Add" "+"
        (fun amount x -> x +. amount)
        [ (1., '1'); (2., '2'); (5., '5'); (10., '0') ]
        [ Menu.Cmd ] );
    ( "Subtract",
      scaled "Subtract" "−"
        (fun amount x -> x -. amount)
        [ (1., '1'); (2., '2'); (5., '5'); (10., '0') ]
        [ Menu.Cmd; Menu.Shift ] );
    ( "Multiply",
      scaled "Multiply by" "×"
        (fun amount x -> x *. amount)
        [ (2., '2'); (5., '5'); (10., '0') ]
        [ Menu.Cmd; Menu.Alt ] );
    ( "Divide",
      scaled "Divide by" "÷"
        (fun amount x -> x /. amount)
        [ (2., '2'); (5., '5'); (10., '0') ]
        [ Menu.Cmd; Menu.Alt; Menu.Shift ] );
  ]

let () =
  Random.self_init ();
  value := random_number ();

  let w = Webview.create ~debug:true () in
  Webview.set_title w "Menu bar calculator";
  Webview.set_size w ~width:420 ~height:520 Webview.Hint_none;

  (* The page announces itself rather than the application guessing when the
     document has finished loading. *)
  Webview.bind w "ready" (fun id _req ->
      render w;
      Webview.return w id ~error:false ~result:"null");

  (* The number typed into the page's prompt comes back here. *)
  Webview.bind w "set_number" (fun id req ->
      (* A whole number is sent as a JSON integer, not a float: JSON.stringify
         writes 42, never 42.0, so both shapes have to be accepted. *)
      (match Yojson.Safe.from_string req with
      | `List [ `Int n ] -> reset w "set" (float_of_int n)
      | `List [ `Float n ] -> reset w "set" n
      | _ | (exception Yojson.Json_error _) -> ());
      Webview.return w id ~error:false ~result:"null");

  let index =
    Filename.concat (Webview_desktop.Locate_assets.assets_dir "web") "index.html"
  in
  Webview.navigate w ("file://" ^ index);

  (* On macOS the application only has a menu bar once it is active, which
     happens after [run] starts — hence the dispatch. *)
  Webview.dispatch w (fun w -> Menu.set w (menus w));

  Webview.run w;
  Webview.destroy w
