let () =
  let w = Webview.create () in
  Webview.set_title w "My first owebview app";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;

  Webview.bind w "random" (fun id req ->
      Printf.printf "binding called <random>: id=%s req=%s\n%!" id req;
      let result = string_of_int (Random.int 100)
      in
      Webview.return w id ~error:false ~result);

  Webview.set_html w
    {|<!doctype html>
      <html>
        <body style="font-family: system-ui; text-align: center">
          <h1>Hello from OCaml 👋</h1>
          <p>Click the button to get a random number:</p>
          <button id="btn">Get random number</button>
          <p id="result"></p>
          <script>
            const btn = document.getElementById("btn");
            const result = document.getElementById("result");
            btn.addEventListener("click", () => {
              window.random().then((n) => {
                result.textContent = `Random number: ${n}`;
              });
            });
          </script>
        </body>
      </html>|};
    
  Webview.run w;
  Webview.destroy w