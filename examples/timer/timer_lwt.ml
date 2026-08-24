(* Lwt version of the timer, arranged to work on macOS.

   Cocoa requires the webview event loop to run on the process's main thread, so
   here [Webview.run] keeps the main thread and the Lwt event loop
   ([Lwt_main.run]) runs on a separate thread. Webview callbacks fire on the
   main thread and hop onto the Lwt thread via [lwt_bind] (see async.md). *)

open Lwt.Syntax

(* async.md's [lwt_bind]: expose a binding whose handler is an Lwt computation.
   The webview callback runs on the main thread; [run_in_main] hands the work to
   the thread running [Lwt_main.run], and [Lwt.async] runs the handler there
   without blocking the UI event loop. *)
let lwt_bind w name (f : string -> string -> unit Lwt.t) =
  Webview.bind w name (fun id req ->
      Lwt_preemptive.run_in_main (fun () ->
          Lwt.return (Lwt.async (fun () -> f id req))))

(* Terminal driver, on the Lwt thread: each <Enter> toggles the timer. Being off
   the webview thread, the JS call is scheduled with [dispatch]. *)
let terminal_loop w =
  let running = ref true in
  let rec loop () =
    let* line = Lwt_io.read_line_opt Lwt_io.stdin in
    match line with
    | None -> Lwt.return_unit (* EOF: stop listening *)
    | Some _ ->
        let cmd = if !running then "stop()" else "start()" in
        running := not !running;
        let* () =
          Lwt_io.printlf "[Thread %d] timer %s"
            (Thread.id (Thread.self ()))
            (if !running then "resumed" else "paused")
        in
        Webview.dispatch w (fun w -> Webview.eval w cmd);
        loop ()
  in
  loop ()

let () =
  let w = Webview.create () in
  Webview.set_title w "Timer (Lwt)";
  Webview.set_size w ~width:380 ~height:460 Webview.Hint_none;

  let icon = Filename.concat (Webview.Utils.web_dir ()) "timer.png" in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview.set_app_icon w icon);

  (* window.print_time(seconds): its Lwt handler runs on the Lwt thread. It must
     still answer the JS call with [return] (safe from another thread). *)
  lwt_bind w "print_time" (fun id req ->
      (* Wait 2 s before printing. On the Lwt thread this is a cooperative,
         non-blocking sleep, so nothing is frozen while we wait. *)
      let* () = Lwt_unix.sleep 2.0 in
      (match Scanf.sscanf_opt req "[%d]" (fun n -> n) with
      | Some seconds ->
          Printf.printf "[Thread %d] elapsed time: %d s\n%!"
            (Thread.id (Thread.self ()))
            seconds
      | None -> Printf.printf "print_time: unexpected request %s\n%!" req);
      Webview.return w id ~error:false ~result:"null";
      Lwt.return_unit);

  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  Printf.printf
    "[Thread %d] Press <Enter> in this terminal to pause/resume the timer.\n%!"
    (Thread.id (Thread.self ()));
  (* Lwt runs on its own thread; the webview keeps the main thread (Cocoa). *)
  let _ : Thread.t =
    Thread.create (fun () -> Lwt_main.run (terminal_loop w)) ()
  in

  Webview.run w;
  Webview.destroy w
