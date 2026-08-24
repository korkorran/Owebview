/* OCaml C stubs for the webview library.
 *
 * Build assumptions:
 *  - vendor/webview.h is the single-header webview (0.12), which provides the
 *    C API *and* the implementation when included in a translation unit
 *    without WEBVIEW_HEADER defined. The 0.12 C API returns webview_error_t;
 *    these stubs check it and raise [Failure] on any non-OK status.
 *  - On macOS the backend uses the Objective-C runtime C API, so this
 *    compiles as plain C++ (no .mm needed) but must link WebKit/Cocoa/objc.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <utility>
#include <vector>

#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include "webview.h"

/* Platform APIs used by set_app_icon (the window/Dock icon). */
#if defined(__APPLE__)
/* macOS Dock icon: drive Cocoa through the Objective-C runtime C API. */
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#elif defined(__linux__)
#include <gtk/gtk.h> /* GtkWindow icon (GTK3) */
#elif defined(_WIN32)
#include <windows.h>  /* HWND icon via WM_SETICON */
#include <wincodec.h> /* WIC: decodes PNG/JPEG/BMP/GIF/TIFF into an HICON */
#endif

/* ---- pointer <-> OCaml value helpers ---- */

static inline webview_t wv_of_val(value v) {
  return reinterpret_cast<webview_t>(static_cast<intptr_t>(Nativeint_val(v)));
}

static inline value val_of_wv(webview_t w) {
  return caml_copy_nativeint(static_cast<intnat>(reinterpret_cast<intptr_t>(w)));
}

/* ---- error handling ----
 * The 0.12 C API returns webview_error_t (WEBVIEW_ERROR_OK == 0 on success).
 * wv_check raises [Failure] for any non-OK status; it must be called with the
 * OCaml runtime lock held (caml_failwith raises an OCaml exception).
 */

static const char *wv_strerror(webview_error_t err) {
  switch (err) {
    case WEBVIEW_ERROR_MISSING_DEPENDENCY:
      return "missing dependency";
    case WEBVIEW_ERROR_CANCELED:
      return "operation canceled";
    case WEBVIEW_ERROR_INVALID_STATE:
      return "invalid state";
    case WEBVIEW_ERROR_INVALID_ARGUMENT:
      return "invalid argument";
    case WEBVIEW_ERROR_UNSPECIFIED:
      return "unspecified error";
    case WEBVIEW_ERROR_OK:
      return "ok";
    case WEBVIEW_ERROR_DUPLICATE:
      return "already exists";
    case WEBVIEW_ERROR_NOT_FOUND:
      return "not found";
    default:
      return "unknown error";
  }
}

static void wv_check(const char *op, webview_error_t err) {
  if (err != WEBVIEW_ERROR_OK) {
    char msg[128];
    std::snprintf(msg, sizeof(msg), "%s: %s (code %d)", op, wv_strerror(err),
                  static_cast<int>(err));
    caml_failwith(msg);
  }
}

/* ---- binding bookkeeping ----
 * Each binding boxes its OCaml closure in a heap cell registered as a GC root,
 * and that cell is passed to webview as the user-data pointer. We track the
 * cells by (webview, name) so that unbind/destroy can free the cell and
 * unregister the root. The map is touched only by bind/unbind/destroy, which
 * run with the OCaml runtime lock held, so no extra synchronization is needed.
 */

struct ocaml_binding {
  value closure; /* registered global root */
};

static std::map<std::pair<webview_t, std::string>, ocaml_binding *> g_bindings;

static void free_binding(ocaml_binding *b) {
  caml_remove_generational_global_root(&b->closure);
  std::free(b);
}

/* ---- pumping calls ----
 * Some webview entry points pump the platform event loop synchronously, on the
 * calling thread. On Windows add_user_script has to, in order to obtain the
 * script ID -- and bind, unbind and init all go through it -- while destroy
 * depletes the queue. A callback queued by webview_dispatch therefore runs
 * *inside* those calls, on this very thread, and not only inside webview_run
 * as one might expect.
 *
 * The trampolines below re-acquire the runtime lock, so it must be released
 * around such calls: OCaml 5 guards its domain lock with an error-checking
 * mutex, and re-locking it on a thread that already holds it aborts the
 * process with "Fatal error during lock: Resource deadlock avoided".
 *
 * The lock has to be released around the *whole* call, so any OCaml string
 * argument must be copied out beforehand: once the lock is released the GC may
 * run and move the value.
 */

static char *wv_strdup_val(value vs) {
  mlsize_t len = caml_string_length(vs);
  char *s = static_cast<char *>(std::malloc(len + 1));
  if (s == nullptr)
    caml_raise_out_of_memory();
  std::memcpy(s, String_val(vs), len);
  s[len] = '\0';
  return s;
}

#if defined(_WIN32)
/* ---- Windows application icon ----
 * Win32's LoadImage only reads .ico from disk, while the macOS and GTK
 * backends accept any image file. WIC -- the imaging component Explorer itself
 * uses -- decodes PNG, JPEG, BMP, GIF, TIFF and ICO, so we decode through it
 * and build the HICON by hand. That puts Windows on par with the other
 * platforms rather than singling out one format.
 */

/* The icons we created for each window, so a later call frees the ones it
 * replaces instead of leaking them. Touched with the runtime lock held. */
static std::map<HWND, std::pair<HICON, HICON>> g_app_icons;

/* Minimal COM guard: the loader juggles four interfaces and every failure path
 * would otherwise have to release them by hand. */
template <typename T> struct wv_com_ptr {
  T *p{nullptr};
  wv_com_ptr() = default;
  wv_com_ptr(const wv_com_ptr &) = delete;
  wv_com_ptr &operator=(const wv_com_ptr &) = delete;
  ~wv_com_ptr() {
    if (p != nullptr)
      p->Release();
  }
  T **operator&() { return &p; }
  T *operator->() const { return p; }
};

/* Decodes `path`, scales it to width x height and returns an owned HICON, or
 * nullptr if any step fails. */
static HICON wv_icon_from_file(IWICImagingFactory *factory, const wchar_t *path,
                               int width, int height) {
  wv_com_ptr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromFilename(path, nullptr, GENERIC_READ,
                                                WICDecodeMetadataCacheOnDemand,
                                                &decoder)))
    return nullptr;

  wv_com_ptr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame)))
    return nullptr;

  /* Scale first, then convert: the converter yields the pre-multiplied BGRA
   * layout a 32bpp DIB section expects. */
  wv_com_ptr<IWICBitmapScaler> scaler;
  if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
      FAILED(scaler->Initialize(frame.p, static_cast<UINT>(width),
                                static_cast<UINT>(height),
                                WICBitmapInterpolationModeFant)))
    return nullptr;

  wv_com_ptr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(scaler.p, GUID_WICPixelFormat32bppPBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom)))
    return nullptr;

  /* Negative height means a top-down DIB, matching WIC's row order. */
  BITMAPINFO bi;
  std::memset(&bi, 0, sizeof(bi));
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = width;
  bi.bmiHeader.biHeight = -height;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;

  void *bits = nullptr;
  HBITMAP color =
      CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (color == nullptr || bits == nullptr) {
    if (color != nullptr)
      DeleteObject(color);
    return nullptr;
  }

  const UINT stride = static_cast<UINT>(width) * 4;
  if (FAILED(converter->CopyPixels(nullptr, stride,
                                   stride * static_cast<UINT>(height),
                                   static_cast<BYTE *>(bits)))) {
    DeleteObject(color);
    return nullptr;
  }

  /* CreateIconIndirect still wants a mask next to a 32bpp colour bitmap; an
   * all-zero one keeps every pixel and lets the alpha channel decide. Mask rows
   * are DWORD-aligned. */
  std::vector<BYTE> mask_bits(
      ((static_cast<size_t>(width) + 31) / 32) * 4 * static_cast<size_t>(height),
      0);
  HBITMAP mask = CreateBitmap(width, height, 1, 1, mask_bits.data());
  if (mask == nullptr) {
    DeleteObject(color);
    return nullptr;
  }

  ICONINFO ii;
  std::memset(&ii, 0, sizeof(ii));
  ii.fIcon = TRUE;
  ii.hbmColor = color;
  ii.hbmMask = mask;
  HICON icon = CreateIconIndirect(&ii);
  /* CreateIconIndirect copies both bitmaps, so ours go back right away. */
  DeleteObject(color);
  DeleteObject(mask);
  return icon;
}

/* Installs the icon on `hwnd`. Returns nullptr on success, or a message the
 * caller turns into [Failure]. Every C++ object stays inside this function, so
 * the caller can raise without longjmp-ing over a destructor. */
static const char *wv_set_window_icon(HWND hwnd, const char *utf8_path) {
  int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, nullptr, 0);
  if (wlen <= 0)
    return "set_app_icon: invalid path encoding";
  std::vector<wchar_t> wpath(static_cast<size_t>(wlen));
  MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, wpath.data(), wlen);

  /* The UI thread already lives in an apartment (WebView2 needs one), but this
   * may run before that; balance only the call we actually made. */
  HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  bool co_owned = (co == S_OK || co == S_FALSE);

  const char *err = nullptr;
  { /* Scoped so every COM pointer is released before CoUninitialize. */
    wv_com_ptr<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_IWICImagingFactory,
                                reinterpret_cast<void **>(&factory)))) {
      err = "set_app_icon: could not create the WIC imaging factory";
    } else {
      /* Two sizes: the title bar and Alt-Tab use different metrics, and
       * rescaling from the source beats letting Windows stretch one bitmap. */
      HICON icon_big =
          wv_icon_from_file(factory.p, wpath.data(), GetSystemMetrics(SM_CXICON),
                            GetSystemMetrics(SM_CYICON));
      HICON icon_small = wv_icon_from_file(factory.p, wpath.data(),
                                           GetSystemMetrics(SM_CXSMICON),
                                           GetSystemMetrics(SM_CYSMICON));
      if (icon_big == nullptr && icon_small == nullptr) {
        err = "set_app_icon: could not decode the image file";
      } else {
        if (icon_big != nullptr)
          SendMessageW(hwnd, WM_SETICON, ICON_BIG,
                       reinterpret_cast<LPARAM>(icon_big));
        if (icon_small != nullptr)
          SendMessageW(hwnd, WM_SETICON, ICON_SMALL,
                       reinterpret_cast<LPARAM>(icon_small));
        /* Free what this call replaced, then remember the new pair. */
        auto prev = g_app_icons.find(hwnd);
        if (prev != g_app_icons.end()) {
          if (prev->second.first != nullptr)
            DestroyIcon(prev->second.first);
          if (prev->second.second != nullptr)
            DestroyIcon(prev->second.second);
        }
        g_app_icons[hwnd] = std::make_pair(icon_big, icon_small);
      }
    }
  }
  if (co_owned)
    CoUninitialize();
  return err;
}
#endif /* _WIN32 */

extern "C" {

CAMLprim value ocaml_webview_create(value vdebug) {
  CAMLparam1(vdebug);
  /* Window argument is NULL: webview creates and owns the native window. */
  webview_t w = webview_create(Bool_val(vdebug), nullptr);
  if (w == nullptr)
    caml_failwith("webview_create returned NULL");
  CAMLreturn(val_of_wv(w));
}

CAMLprim value ocaml_webview_destroy(value vw) {
  CAMLparam1(vw);
  webview_t w = wv_of_val(vw);
  /* Depletes the event-loop queue, so a dispatched callback that never got to
   * run fires here; release the lock (see "pumping calls" above). */
  caml_release_runtime_system();
  webview_error_t err = webview_destroy(w);
  caml_acquire_runtime_system();
  wv_check("webview_destroy", err);
  /* The webview is gone; free any bindings still registered for it. */
  for (auto it = g_bindings.begin(); it != g_bindings.end();) {
    if (it->first.first == w) {
      free_binding(it->second);
      it = g_bindings.erase(it);
    } else {
      ++it;
    }
  }
  CAMLreturn(Val_unit);
}

/* Returns the library version info as an OCaml record (a tag-0 block whose
 * fields match Webview.version_info, in declaration order). */
CAMLprim value ocaml_webview_version(value vunit) {
  CAMLparam1(vunit);
  CAMLlocal1(vinfo);
  const webview_version_info_t *vi = webview_version();
  vinfo = caml_alloc_tuple(6);
  Store_field(vinfo, 0, Val_int(vi->version.major));
  Store_field(vinfo, 1, Val_int(vi->version.minor));
  Store_field(vinfo, 2, Val_int(vi->version.patch));
  Store_field(vinfo, 3, caml_copy_string(vi->version_number));
  Store_field(vinfo, 4, caml_copy_string(vi->pre_release));
  Store_field(vinfo, 5, caml_copy_string(vi->build_metadata));
  CAMLreturn(vinfo);
}

/* Native handles are returned as nativeint pointers (0n if unavailable); the
 * caller interprets them with platform-specific FFI. */
CAMLprim value ocaml_webview_get_window(value vw) {
  CAMLparam1(vw);
  void *h = webview_get_window(wv_of_val(vw));
  CAMLreturn(caml_copy_nativeint(reinterpret_cast<intnat>(h)));
}

CAMLprim value ocaml_webview_get_native_handle(value vw, value vkind) {
  CAMLparam2(vw, vkind);
  webview_native_handle_kind_t kind;
  switch (Int_val(vkind)) {
    case 1:
      kind = WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET;
      break;
    case 2:
      kind = WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER;
      break;
    default:
      kind = WEBVIEW_NATIVE_HANDLE_KIND_UI_WINDOW;
      break;
  }
  void *h = webview_get_native_handle(wv_of_val(vw), kind);
  CAMLreturn(caml_copy_nativeint(reinterpret_cast<intnat>(h)));
}

/* Set the application/window icon from an image file.
 *  - macOS: the Dock icon, application-global, set on NSApp (the window handle
 *    is ignored).
 *  - Linux (GTK): the window's icon, shown in the taskbar/switcher.
 *  - Windows: the window's icon via WM_SETICON (Win32 loads .ico files).
 * A no-op on any other backend. */
CAMLprim value ocaml_webview_set_app_icon(value vw, value vpath) {
  CAMLparam2(vw, vpath);
  const char *path = String_val(vpath);
#if defined(__APPLE__)
  (void)vw; /* the Dock icon is application-global, not per window */
  id app = ((id (*)(Class, SEL))objc_msgSend)(
      objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
  id nspath = ((id (*)(Class, SEL, const char *))objc_msgSend)(
      objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
      path);
  id image = ((id (*)(Class, SEL))objc_msgSend)(
      objc_getClass("NSImage"), sel_registerName("alloc"));
  image = ((id (*)(id, SEL, id))objc_msgSend)(
      image, sel_registerName("initWithContentsOfFile:"), nspath);
  if (image == nullptr)
    caml_failwith("set_app_icon: could not load image file");
  ((void (*)(id, SEL, id))objc_msgSend)(
      app, sel_registerName("setApplicationIconImage:"), image);
#elif defined(__linux__)
  GtkWindow *win = static_cast<GtkWindow *>(webview_get_native_handle(
      wv_of_val(vw), WEBVIEW_NATIVE_HANDLE_KIND_UI_WINDOW));
#if GTK_MAJOR_VERSION < 4
  GError *error = NULL;
  if (!gtk_window_set_icon_from_file(win, path, &error)) {
    char msg[256];
    std::snprintf(msg, sizeof(msg), "set_app_icon: %s",
                  (error && error->message) ? error->message
                                            : "could not load image");
    if (error)
      g_error_free(error);
    caml_failwith(msg);
  }
#else
  (void)win; /* GTK4 removed per-window icon-from-file; use a .desktop file */
#endif
#elif defined(_WIN32)
  /* Any format WIC can decode, not just .ico -- see "Windows application icon"
   * above. The work happens in a helper so that no C++ destructor is pending
   * when caml_failwith longjmps out. */
  HWND hwnd = static_cast<HWND>(webview_get_native_handle(
      wv_of_val(vw), WEBVIEW_NATIVE_HANDLE_KIND_UI_WINDOW));
  if (hwnd == nullptr)
    caml_failwith("set_app_icon: no native window");
  const char *icon_err = wv_set_window_icon(hwnd, path);
  if (icon_err != nullptr)
    caml_failwith(icon_err);
#else
  (void)vw;
  (void)path;
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_run(value vw) {
  CAMLparam1(vw);
  webview_t w = wv_of_val(vw);
  /* webview_run blocks; release the runtime lock so the GC and other OCaml
   * threads keep working. Bindings re-acquire it (see trampoline below). */
  caml_release_runtime_system();
  webview_error_t err = webview_run(w);
  caml_acquire_runtime_system();
  /* Check only after re-acquiring the lock, since wv_check may raise. */
  wv_check("webview_run", err);
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_terminate(value vw) {
  CAMLparam1(vw);
  wv_check("webview_terminate", webview_terminate(wv_of_val(vw)));
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_set_title(value vw, value vtitle) {
  CAMLparam2(vw, vtitle);
  wv_check("webview_set_title",
           webview_set_title(wv_of_val(vw), String_val(vtitle)));
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_set_size(value vw, value vwidth, value vheight,
                                      value vhint) {
  CAMLparam4(vw, vwidth, vheight, vhint);
  webview_hint_t view_hint;
  switch (Int_val(vhint)) {
    case 1:
      view_hint = WEBVIEW_HINT_MIN;
      break;
    case 2:
      view_hint = WEBVIEW_HINT_MAX;
      break;
    case 3:
      view_hint = WEBVIEW_HINT_FIXED;
      break;
    default:
      view_hint = WEBVIEW_HINT_NONE;
      break;
  }
  wv_check("webview_set_size",
           webview_set_size(wv_of_val(vw), Int_val(vwidth), Int_val(vheight),
                            view_hint));
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_navigate(value vw, value vurl) {
  CAMLparam2(vw, vurl);
  wv_check("webview_navigate",
           webview_navigate(wv_of_val(vw), String_val(vurl)));
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_set_html(value vw, value vhtml) {
  CAMLparam2(vw, vhtml);
  wv_check("webview_set_html",
           webview_set_html(wv_of_val(vw), String_val(vhtml)));
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_init(value vw, value vjs) {
  CAMLparam2(vw, vjs);
  webview_t w = wv_of_val(vw);
  /* Adds a user script, which pumps the event loop on Windows (see "pumping
   * calls" above). */
  char *js = wv_strdup_val(vjs);
  caml_release_runtime_system();
  webview_error_t err = webview_init(w, js);
  caml_acquire_runtime_system();
  std::free(js);
  wv_check("webview_init", err);
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_eval(value vw, value vjs) {
  CAMLparam2(vw, vjs);
  wv_check("webview_eval", webview_eval(wv_of_val(vw), String_val(vjs)));
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_return(value vw, value vid, value vstatus,
                                    value vresult) {
  CAMLparam4(vw, vid, vstatus, vresult);
  wv_check("webview_return",
           webview_return(wv_of_val(vw), String_val(vid), Int_val(vstatus),
                          String_val(vresult)));
  CAMLreturn(Val_unit);
}

/* ---- binding callbacks ----
 * The trampoline receives the heap cell (see "binding bookkeeping" above) as
 * its user-data argument and dispatches to the boxed OCaml closure.
 */

static void binding_trampoline(const char *id, const char *req, void *arg) {
  ocaml_binding *b = static_cast<ocaml_binding *>(arg);

  /* Runs from inside webview_run -- or from any other call that pumps the
   * event loop (see "pumping calls" above); either way the runtime lock was
   * released. Re-acquire before touching any OCaml value or allocating. */
  caml_acquire_runtime_system();
  /* If your webview backend ever invokes this from a thread the OCaml runtime
   * doesn't know about, wrap with caml_c_thread_register/unregister too. */

  CAMLparam0();
  CAMLlocal2(vid, vreq);
  vid = caml_copy_string(id);
  vreq = caml_copy_string(req);
  caml_callback2(b->closure, vid, vreq);

  caml_release_runtime_system();
  CAMLdrop;
}

CAMLprim value ocaml_webview_bind(value vw, value vname, value vclosure) {
  CAMLparam3(vw, vname, vclosure);
  webview_t w = wv_of_val(vw);
  /* Copied up front: the name must outlive the released-lock section below. */
  char *name = wv_strdup_val(vname);

  ocaml_binding *b =
      static_cast<ocaml_binding *>(std::malloc(sizeof(ocaml_binding)));
  if (b == nullptr) {
    std::free(name);
    caml_failwith("out of memory in webview_bind");
  }
  b->closure = vclosure;
  caml_register_generational_global_root(&b->closure);

  /* Installs a user script, which pumps the event loop on Windows (see
   * "pumping calls" above). */
  caml_release_runtime_system();
  webview_error_t err = webview_bind(w, name, binding_trampoline, b);
  caml_acquire_runtime_system();
  if (err != WEBVIEW_ERROR_OK) {
    free_binding(b);
    std::free(name);
    wv_check("webview_bind", err); /* raises (e.g. duplicate name) */
  }
  /* Track for unbind/destroy. Build the std::string key only here, past any
   * point where wv_check could longjmp over its destructor. */
  g_bindings[std::make_pair(w, std::string(name))] = b;
  std::free(name);
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_unbind(value vw, value vname) {
  CAMLparam2(vw, vname);
  webview_t w = wv_of_val(vw);
  /* Copied up front: the name must outlive the released-lock section below. */
  char *name = wv_strdup_val(vname);

  /* Replaces the bind user script, which pumps the event loop on Windows (see
   * "pumping calls" above). No C++ object is alive when wv_check may longjmp
   * on a non-OK status (e.g. WEBVIEW_ERROR_NOT_FOUND). */
  caml_release_runtime_system();
  webview_error_t err = webview_unbind(w, name);
  caml_acquire_runtime_system();
  if (err != WEBVIEW_ERROR_OK) {
    std::free(name);
    wv_check("webview_unbind", err); /* raises */
  }

  /* Removed on the C side; free our tracking cell and unregister the root. */
  auto it = g_bindings.find(std::make_pair(w, std::string(name)));
  std::free(name);
  if (it != g_bindings.end()) {
    free_binding(it->second);
    g_bindings.erase(it);
  }
  CAMLreturn(Val_unit);
}

/* ---- dispatch ----
 * webview_dispatch schedules a function to run once on the UI thread (the
 * thread inside webview_run); it is the thread-safe way to drive the webview
 * from another thread. The closure is one-shot: the trampoline frees its cell
 * and unregisters its GC root right after invoking it.
 */

struct ocaml_dispatch {
  value closure; /* registered global root */
};

static void dispatch_trampoline(webview_t w, void *arg) {
  ocaml_dispatch *d = static_cast<ocaml_dispatch *>(arg);

  /* Runs on the UI thread inside webview_run -- or inside any other call that
   * pumps the event loop (see "pumping calls" above); either way the runtime
   * lock was released. Re-acquire before touching any OCaml value. */
  caml_acquire_runtime_system();

  CAMLparam0();
  CAMLlocal1(vw);
  vw = val_of_wv(w);
  /* caml_callback_exn (not caml_callback): swallow any exception, since there
   * is no OCaml handler on the UI-thread C stack to receive a raise. */
  caml_callback_exn(d->closure, vw);
  caml_remove_generational_global_root(&d->closure);
  std::free(d);

  caml_release_runtime_system();
  CAMLdrop;
}

CAMLprim value ocaml_webview_dispatch(value vw, value vclosure) {
  CAMLparam2(vw, vclosure);
  webview_t w = wv_of_val(vw);
  ocaml_dispatch *d =
      static_cast<ocaml_dispatch *>(std::malloc(sizeof(ocaml_dispatch)));
  if (d == nullptr)
    caml_failwith("out of memory in webview_dispatch");
  d->closure = vclosure;
  caml_register_generational_global_root(&d->closure);
  webview_error_t err = webview_dispatch(w, dispatch_trampoline, d);
  if (err != WEBVIEW_ERROR_OK) {
    caml_remove_generational_global_root(&d->closure);
    std::free(d);
    wv_check("webview_dispatch", err); /* raises */
  }
  CAMLreturn(Val_unit);
}

} /* extern "C" */
