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
 (synopsis "Native desktop apps with a web UI, through webview bindings")
 (description
  "The package provides two libraries.\n\nowebview is the binding to the webview library\n(https://github.com/webview/webview): create a native desktop window\nrendered by the system web engine, navigate to a URL or to inline HTML,\nand call back and forth between OCaml and JavaScript. It covers the full webview\n0.12 C API and stays deliberately low-level.\n\nowebview.desktop adds what a desktop application needs around that window,\nand which webview itself does not provide: native menu bars and modal\ndialogs, the application icon, and locating the web assets next to the\nexecutable.")
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
