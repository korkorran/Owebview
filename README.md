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

Other handy entry points: `Webview.navigate` (load a URL or a local `file://`
page), `Webview.init` / `Webview.eval` (inject JavaScript), and
`Webview.terminate` (close the window from code). The full API lives in
[`lib/webview.mli`](lib/webview.mli).

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
 (libraries owebview))
```

## See it run

Clone the repo and launch one of the bundled example, for instance `hellowv`:

```sh
git clone https://github.com/korkorran/Owebview.git
cd Owebview
```

```sh
opam install . --deps-only
dune exec examples/hellowv/hellowv.exe
```

A window pops up with two buttons wired to OCaml: one adds two numbers, the other
reports your OS. The example loads its UI from real `.html` / `.css` / `.js`
files in [`examples/hellowv/web/`](examples/hellowv/web/) — peek at
[`examples/hellowv/hellowv.ml`](examples/hellowv/hellowv.ml) to see how JavaScript calls back
into OCaml.

> **Linux Dock icon**: on native Wayland (GNOME's default), the Dock ignores
> `Webview.set_app_icon` — it resolves an app's icon from an installed
> `.desktop` file, not from window properties. Run
> `examples/hellowv/install-desktop-entry.sh` once to install one for the
> example (`--uninstall` removes it); see `Webview.set_app_id` in
> [`lib/webview.mli`](lib/webview.mli) for the details.


## Native dependencies

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

> This is a thin binding that covers the **full webview 0.12 C API**. It stays
> low-level on purpose: higher-level conveniences (such as JSON (de)serializing
> binding arguments) are left to you.

## Contributing

Feedback is very welcome! This binding is developed and tested mainly on macOS,
so reports about building and running it on **Linux distributions** are
especially valuable — does it compile, do the `depexts` resolve, does the
`webkit2gtk-4.1` backend behave as expected on your distro?

If you give it a try on Linux, please open an issue with your distribution,
what worked and what didn't (build logs welcome). Pull requests improving
cross-platform support are happily accepted.

## License

[MIT](LICENSE).
