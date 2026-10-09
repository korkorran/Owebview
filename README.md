<p align="center">
  <img src="https://raw.githubusercontent.com/korkorran/Owebview/main/logo.png" width="200" alt="owebview">
</p>
<h1 align=center>Owebview</h1>
<p align="center"><b>An embedded web rendering engine.</b></p>
<br/>

Powered by [webview](https://github.com/webview/webview).
All the power of web technologies in your app. No Electron, no bundler: create a window, drop in some HTML, and you have an app.

## Examples

<table align="center">
  <tr>
    <td align="center"><b>Rainfall (D3.js)</b></td>
    <td align="center"><b>Geometry shapes (three.js)</b></td>
    <td align="center"><b>Timer</b></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/korkorran/Owebview/main/doc/screenshots/d3.png" width="260" alt="Rainfall chart"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/korkorran/Owebview/main/doc/screenshots/three.png" width="260" alt="3D shapes"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/korkorran/Owebview/main/doc/screenshots/timer.png" width="260" alt="Timer"></td>
  </tr>
  <tr>
    <td align="center"><code>dune exec examples/d3/d3.exe</code></td>
    <td align="center"><code>dune exec examples/three/three.exe</code></td>
    <td align="center"><code>dune exec examples/timer/timer_posix.exe</code></td>
  </tr>
</table>

A complete app demonstrating Owebview feature : [Sun notes](https://github.com/korkorran/Sun-notes).
Packages for Debian, Fedora, macOS, Windows available for download.

## Learn about Owebview

Please refer to the [tutorial](./tutorial/README.md)

You can also check the [documentation](https://korkorran.github.io/Owebview/owebview/index.html)

## Minimal code of random number GUI

Build a tiny native desktop window with a web UI, straight from OCaml — 

Here's the whole thing:

```ocaml
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
```

Once HTML rendering works, the fun part is the OCaml ↔ JavaScript bridge: `Webview.bind w random (...)` expose `window.random()` to the page; the result is a JS Promise. All the computation of random numbers is done by the OCaml back-end. While random number generation can be done in JavaScript, it gives an example of how to call native functions from the window.

## Install and use in your own project

If your machine is on *Windows*, you must install the Microsoft Webview2 package before any OPAM installation,  :
```sh
nuget install Microsoft.Web.WebView2
```
Otherwise, on unix system, all the dependancies are installed via OPAM.
```sh
opam install owebview
```

Then depend on it from your `dune` file:

```dune
(executable
 (name main)
 (libraries owebview owebview.desktop))
```

The Owebview package is divided in two seperate libraries :
 - **owebview** itself stays a thin binding to the webview C API. It provides the module `Webview`, which contains webview lifecycle functions.
 - **owebview.desktop** the companion library for the native desktop integration, in the `Webview_desktop` module.
   - `Webview_desktop.Locate_assets` : locating your on-disk assets (finds your `web/` directory
relative to the executable, whatever the working directory),
   - `Webview_desktop.Icon` : setting a dock icon in a dev environnement (can be ignored in production releases)
   - `Webview_desktop.Dialog` : the system's own modal dialogs
   - `Webview_desktop.Menu` : the application window native menu


## See the examples

Clone the repo and launch one of the bundled example, for instance `hellowv`:

```sh
git clone https://github.com/korkorran/Owebview.git
cd Owebview
nuget install Microsoft.Web.WebView2 # on windows only
opam install . --deps-only
```

```sh
dune build
dune exec examples/hellowv/hellowv.exe          # a basic application
dune exec examples/timer/timer_posix.exe        # a timer with threads
dune exec examples/timer/timer_lwt.exe          # the same, driven by Lwt
dune exec examples/d3/d3.exe                    # a D3.js chart
dune exec examples/three/three.exe              # WebGL via three.js

opam install brr                                # you will need brr to compile this example
dune build
dune exec examples/js_of_ocaml/hellowv.exe      # full OCaml application
```


## Native dev dependencies

webview uses the system web engine, so you need its native libraries:

- **macOS** — WebKit / Cocoa, already provided by the system. Nothing to install.
- **Linux** — `gtk+-3.0` and `webkit2gtk-4.1` (the `-dev` packages). They come
  from the `conf-gtk3-webkit` opam package, so `opam install` will offer to
  install them for your distribution.
- **Windows** — WebView2. Compilation works via the MinGW toolchain: install
  the WebView2 SDK with NuGet (`nuget install Microsoft.Web.WebView2`) and the
  `WebView2.h` header is picked up automatically from the NuGet cache (or set
  `MICROSOFT_WEB_WEBVIEW2` to the package directory). At run time the WebView2
  Runtime must be present — it ships with Windows 10/11.

The platform-specific compile/link flags are detected automatically at build
time — via `pkg-config` on Linux, and from the NuGet cache on Windows — so
there's nothing to tweak by hand.

## Contributing

Feedback is very welcome! Reports about building and running it on **Linux distributions** are
especially valuable.

If you give it a try on Linux, please open an issue with your distribution,
what worked and what didn't (build logs welcome). Pull requests improving
cross-platform support are happily accepted.

## License

[MIT](LICENSE).
