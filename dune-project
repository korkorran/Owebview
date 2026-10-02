(lang dune 3.0)

(generate_opam_files true)

(name owebview)
(source
 (github korkorran/Owebview))
(license MIT)
(authors "Frédéric Lang")
(maintainers "frederic.ln.lang@gmail.com")

(package
 (name owebview)
 (synopsis "OCaml bindings for the webview library")
 (description
  "OCaml bindings for the webview library (https://github.com/webview/webview):\ncreate a native desktop window rendered by the system web engine, navigate to a\nURL or to inline HTML, and call back and forth between OCaml and JavaScript.\nThe binding covers the full webview 0.12 C API and stays deliberately\nlow-level; the C header is vendored, so nothing is fetched at build time.\n\nThe native dependencies are the ones of the system web engine: WebKit and Cocoa\non macOS (provided by the system, nothing to install), gtk+-3.0 and\nwebkit2gtk-4.1 on Linux (pulled in by the conf-gtk3-webkit package), and\nWebView2 on Windows (the runtime ships with Windows 10 and 11; the SDK headers\nare located through the NuGet cache at build time).")
 (documentation "https://korkorran.github.io/Owebview")
 (tags
  ("webview" "gui" "desktop" "webkit" "html" "javascript" "bindings"))
 (depends
  (ocaml
   (>= 4.08))
  (dune-configurator
   (and
    (>= 3.0)
    :build))
  ; The stubs are compiled as C++ ((language cxx) in webview/dune), so a C++
  ; toolchain is required. On Windows this pulls in conf-mingw-w64-g++-x86_64
  ; (or the MSVC equivalent); without it the build fails late, during
  ; compilation, with the opaque "cannot execute 'cc1plus'".
  conf-c++))
