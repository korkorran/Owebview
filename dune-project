(lang dune 3.0)

(generate_opam_files true)

(name owebview)
(source
 (github korkorran/owebview))
(license MIT)
(authors "Frédéric Lang")
(maintainers "frederic.ln.lang@gmail.com")

(package
 (name owebview)
 (synopsis "OCaml bindings for the webview library")
 (description
  "A small OCaml binding skeleton for the webview library\n(https://github.com/webview/webview): window creation, navigation,\nbidirectional JS <-> OCaml bindings, plus an example application.\n\nOn macOS the native dependencies (WebKit/Cocoa) are provided by the system;\non Linux they are declared as depexts (gtk+-3.0 and webkit2gtk-4.1) for common distributions.")
 (depends
  (ocaml
   (>= 4.08))
  (dune-configurator
   (and
    (>= 3.0)
    :build))
  ; The stubs are compiled as C++ ((language cxx) in lib/dune), so a C++
  ; toolchain is required. On Windows this pulls in conf-mingw-w64-g++-x86_64
  ; (or the MSVC equivalent); without it the build fails late, during
  ; compilation, with the opaque "cannot execute 'cc1plus'".
  conf-c++))
