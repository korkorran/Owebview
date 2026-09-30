/* OCaml C stubs for the application icon and the application id.
 *
 * These two entry points are not part of the webview C API: they talk to
 * Cocoa, GTK and Win32 directly, to give a plain executable a real icon in the
 * Dock/taskbar. They live here so that webview_stubs.cpp stays dedicated to
 * the API declared in vendor/webview.h.
 *
 * Nothing here includes webview.h. [set_app_icon] needs the native top-level
 * window, and the OCaml side hands it over as a nativeint obtained from
 * [Webview.get_window] (see the wrapper in webview.ml), so this translation
 * unit is independent of the vendored header -- and of the single-header
 * implementation it would otherwise pull in a second time.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <utility>
#include <vector>

#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

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

/* The native window handle, passed from OCaml as a nativeint (0n when the
 * backend could not provide one). Only the backends that install the icon on a
 * window need it: on macOS the Dock icon is application-global, so the handle
 * is ignored there and this would be an unused function. */
#if defined(__linux__) || defined(_WIN32)
static inline void *wv_window_of_val(value v) {
  return reinterpret_cast<void *>(static_cast<intptr_t>(Nativeint_val(v)));
}
#endif

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

/* Set the application/window icon from an image file. [vwin] is the native
 * top-level window, as returned by webview_get_window on the OCaml side.
 *  - macOS: the Dock icon, application-global, set on NSApp (the window handle
 *    is ignored).
 *  - Linux (GTK): the window's icon, shown in the taskbar/switcher.
 *  - Windows: the window's icon via WM_SETICON (decoded with WIC, see above).
 * A no-op on any other backend. */
CAMLprim value ocaml_webview_set_app_icon(value vwin, value vpath) {
  CAMLparam2(vwin, vpath);
  const char *path = String_val(vpath);
#if defined(__APPLE__)
  (void)vwin; /* the Dock icon is application-global, not per window */
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
  GtkWindow *win = static_cast<GtkWindow *>(wv_window_of_val(vwin));
  if (win == nullptr)
    caml_failwith("set_app_icon: no native window");
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
  HWND hwnd = static_cast<HWND>(wv_window_of_val(vwin));
  if (hwnd == nullptr)
    caml_failwith("set_app_icon: no native window");
  const char *icon_err = wv_set_window_icon(hwnd, path);
  if (icon_err != nullptr)
    caml_failwith(icon_err);
#else
  (void)vwin;
  (void)path;
#endif
  CAMLreturn(Val_unit);
}

/* Sets the process-wide application id used by the windowing system to match
 * this process's windows to an installed .desktop file (Linux/GTK only).
 *  - X11: becomes the WM_CLASS class name.
 *  - Wayland: becomes the xdg_toplevel app_id.
 * Desktop shells (e.g. GNOME) use this id -- matched against an installed
 * .desktop file's id or its StartupWMClass= -- to pick which icon to show in
 * the Dock/taskbar; set_app_icon alone has no effect under Wayland, since it
 * only sets the X11 _NET_WM_ICON property, which does not exist there. Call
 * this once, before create, so it applies to the first window realized.
 * A no-op on other backends. */
CAMLprim value ocaml_webview_set_app_id(value vid) {
  CAMLparam1(vid);
  const char *id = String_val(vid);
#if defined(__linux__)
  g_set_prgname(id);
#else
  (void)id;
#endif
  CAMLreturn(Val_unit);
}

} /* extern "C" */
