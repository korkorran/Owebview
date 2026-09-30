let () =
  let w = Webview.create () in
  Webview.set_title w "Timer (Posix)";
  Webview.set_size w ~width:380 ~height:460 Webview.Hint_none;

  let icon = Filename.concat (Webview.Utils.web_dir ()) "timer.png" in
  if Sys.file_exists icon then
    Webview.dispatch w (fun w -> Webview.Icon.set_app_icon w icon);

  (* Expose window.print_time(seconds): the page's button calls it and we print
     the elapsed time on the main process's console (stdout). [req] is a JSON
     array of the JS arguments, e.g. "[42]". *)
  Webview.bind w "print_time" (fun id req ->
      (* Wait 2 s before printing. The callback runs on the UI thread, so the
         wait is delegated to a background thread to avoid freezing the window
         (a blocking sleep here would stall the webview event loop). *)
      ignore
        (Thread.create
           (fun () ->
             Thread.delay 2.0;
             (match Scanf.sscanf_opt req "[%d]" (fun n -> n) with
             | Some seconds ->
                 Printf.printf "[Thread %d] elapsed time: %d s\n%!"
                   (Thread.id (Thread.self ()))
                   seconds
             | None -> Printf.printf "print_time: unexpected request %s\n%!" req);
             Webview.return w id ~error:false ~result:"null")
           ()));

  (* The timer itself lives in the page (HTML/CSS/JS). The web/ directory is
     located relative to the executable. *)
  let index = Filename.concat (Webview.Utils.web_dir ()) "index.html" in
  Webview.navigate w ("file://" ^ index);

  (* Listen on the terminal: every time the user presses <Enter>, toggle the
     timer. Reading stdin happens on a background thread, so we must NOT call
     the webview directly from there — [dispatch] runs the JS call on the UI
     thread, which is the whole point of this example. *)
  Printf.printf
    "[Thread %d] Press <Enter> in this terminal to pause/resume the timer.\n%!"
    (Thread.id (Thread.self ()));
  let running = ref true in
  let _ =
    Thread.create
      (fun () ->
        try
          while true do
            ignore (input_line stdin);
            (* [input_line] blocks until <Enter>; [dispatch] fires here. *)
            let cmd = if !running then "stop()" else "start()" in
            running := not !running;
            Printf.printf "[Thread %d] timer %s\n%!"
              (Thread.id (Thread.self ()))
              (if !running then "resumed" else "paused");
            Webview.dispatch w (fun w -> Webview.eval w cmd)
          done
        with End_of_file -> ())
      ()
  in

  Webview.run w;
  Webview.destroy w
