/* OCaml C stubs for the native menu bar.
 *
 * Like the other stubs in this library, nothing here includes
 * vendor/webview.h: the window arrives from OCaml as a nativeint obtained
 * from [Webview.get_window], and on Windows the WebView2 controller as one
 * obtained from [Webview.get_native_handle]. The latter is why this file, and
 * this file alone, includes the WebView2 SDK header on Windows.
 *
 * The menu is built incrementally rather than marshalled as a tree: OCaml
 * walks its own description and calls create_bar / add_submenu / add_item /
 * add_separator, each returning or taking an opaque native handle (an NSMenu,
 * a GtkMenuShell or an HMENU). That keeps the C side free of any knowledge of
 * the OCaml variant type.
 *
 * Activation is routed through a *single* OCaml closure of type [int -> unit],
 * registered once as a GC root. Each item carries an integer command id, and
 * OCaml looks the callback up in its own table. One root instead of one per
 * item, and the C side never holds a per-item closure.
 *
 * The dispatch trampoline runs from inside the platform event loop -- i.e.
 * inside webview_run, which released the OCaml runtime lock -- so it
 * re-acquires it, exactly as the binding trampoline in webview_stubs.cpp
 * does.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#if defined(__APPLE__)
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#elif defined(__linux__)
#include <gtk/gtk.h>
#elif defined(_WIN32)
#include <windows.h>

#include <objbase.h>

#include "WebView2.h"
#endif

/* Modifier bits, mirroring Webview_desktop.Menu.modifier. */
enum {
  WV_MOD_CMD = 1,
  WV_MOD_CTRL = 2,
  WV_MOD_ALT = 4,
  WV_MOD_SHIFT = 8
};

static inline void *wv_ptr_of_val(value v) {
  return reinterpret_cast<void *>(static_cast<intptr_t>(Nativeint_val(v)));
}

static inline value wv_val_of_ptr(void *p) {
  return caml_copy_nativeint(static_cast<intnat>(reinterpret_cast<intptr_t>(p)));
}

/* ---- activation dispatch ----
 * One OCaml closure [int -> unit], kept alive as a generational global root
 * for as long as a menu exists. Replacing it releases the previous root.
 */

static value g_dispatch = Val_unit;
static bool g_has_dispatch = false;

static void wv_menu_activate(int command) {
  if (!g_has_dispatch)
    return;
  /* Called from the platform event loop, which runs inside webview_run with
   * the runtime lock released. Re-acquire before touching any OCaml value. */
  caml_acquire_runtime_system();
  /* caml_callback_exn, not caml_callback: there is no OCaml handler on the
   * native stack below us to receive a raise. */
  caml_callback_exn(g_dispatch, Val_int(command));
  caml_release_runtime_system();
}

#if defined(__APPLE__)
/* ---- macOS ----
 * NSMenu/NSMenuItem through the Objective-C runtime C API. Menu items need a
 * target/action pair, and the C API has no blocks, so the target is an
 * instance of a class synthesised at load time whose single method reads the
 * sender's tag -- our command id -- and hands it to the dispatcher.
 */

static id wv_nsstring(const char *utf8) {
  return ((id(*)(Class, SEL, const char *))objc_msgSend)(
      objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
      utf8);
}

static id wv_alloc_init(const char *class_name) {
  id obj = ((id(*)(Class, SEL))objc_msgSend)(objc_getClass(class_name),
                                             sel_registerName("alloc"));
  return ((id(*)(id, SEL))objc_msgSend)(obj, sel_registerName("init"));
}

static void wv_menu_action_imp(id self, SEL cmd, id sender) {
  (void)self;
  (void)cmd;
  long tag = ((long (*)(id, SEL))objc_msgSend)(sender, sel_registerName("tag"));
  wv_menu_activate(static_cast<int>(tag));
}

static SEL wv_action_sel() { return sel_registerName("owebviewMenuAction:"); }

static id wv_action_target() {
  static id target = nullptr;
  if (target != nullptr)
    return target;
  Class cls = objc_getClass("OwebviewMenuTarget");
  if (cls == nullptr) {
    cls = objc_allocateClassPair(objc_getClass("NSObject"),
                                 "OwebviewMenuTarget", 0);
    if (cls == nullptr)
      return nullptr;
    /* "v@:@": returns void, takes (id self, SEL _cmd, id sender). */
    class_addMethod(cls, wv_action_sel(),
                    reinterpret_cast<IMP>(wv_menu_action_imp), "v@:@");
    objc_registerClassPair(cls);
  }
  id obj = ((id(*)(Class, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
  target = ((id(*)(id, SEL))objc_msgSend)(obj, sel_registerName("init"));
  return target;
}

/* NSEventModifierFlags. */
static unsigned long wv_cocoa_mask(int modifiers) {
  unsigned long mask = 0;
  if (modifiers & WV_MOD_SHIFT)
    mask |= (1UL << 17);
  if (modifiers & WV_MOD_CTRL)
    mask |= (1UL << 18);
  if (modifiers & WV_MOD_ALT)
    mask |= (1UL << 19);
  if (modifiers & WV_MOD_CMD)
    mask |= (1UL << 20);
  return mask;
}
#endif /* __APPLE__ */

#if defined(__linux__) && GTK_MAJOR_VERSION < 4
/* ---- Linux (GTK 3) ----
 * A GtkMenuBar of GtkMenuItems. The accelerator group has to be attached to
 * the window, which only happens at install time, so it is created with the
 * bar and carried on each menu shell as object data.
 */

static const char *WV_ACCEL_KEY = "owebview-accel-group";
/* Marks the GtkBox we insert between the window and the webview widget, so a
 * second install replaces the menu bar instead of nesting another box. */
static const char *WV_BOX_KEY = "owebview-menu-box";

static void wv_gtk_activate(GtkMenuItem *item, gpointer data) {
  (void)item;
  wv_menu_activate(static_cast<int>(GPOINTER_TO_INT(data)));
}

static GdkModifierType wv_gdk_mask(int modifiers) {
  int mask = 0;
  /* There is no Command key here: Cmd means the platform's primary modifier,
   * which on Linux is Control. */
  if (modifiers & (WV_MOD_CMD | WV_MOD_CTRL))
    mask |= GDK_CONTROL_MASK;
  if (modifiers & WV_MOD_ALT)
    mask |= GDK_MOD1_MASK;
  if (modifiers & WV_MOD_SHIFT)
    mask |= GDK_SHIFT_MASK;
  return static_cast<GdkModifierType>(mask);
}
#endif /* __linux__ && GTK 3 */

#if defined(_WIN32)
/* ---- Windows ----
 * CreateMenu/AppendMenuW, installed with SetMenu. Menu activation arrives as
 * WM_COMMAND on the top-level window, whose window procedure belongs to
 * webview, so we subclass it and chain every other message through.
 */

static std::map<HWND, WNDPROC> g_prev_wndproc;

/* ---- accelerators ----
 * Keystrokes reach us by two routes, depending on where the focus is.
 *
 * 1. The web view has the focus -- the usual case. WebView2 renders the page
 *    in its own browser process, and the window that receives the keyboard
 *    belongs to *that* process: its messages never enter our message loop, so
 *    nothing on our side can see them, let alone translate them. WebView2
 *    offers ICoreWebView2Controller::add_AcceleratorKeyPressed for exactly
 *    this, raised on our UI thread for every key-down that combines with a
 *    modifier. We match it against the same ACCEL entries that feed the
 *    Win32 table (g_accel_entries), mark it Handled so the page does not also
 *    see it, and post the WM_COMMAND an accelerator would have sent.
 *
 * 2. The host window has the focus (after clicking the menu bar, say). Then
 *    the keystroke does go through our loop, and Windows runs accelerators
 *    from there, via TranslateAccelerator -- which webview's loop does not
 *    call: run_impl in vendor/webview.h is a bare
 *    GetMessage/TranslateMessage/DispatchMessage with no hook of its own, and
 *    the same is true of the nested pumps it uses while waiting. So we install
 *    a WH_GETMESSAGE hook on *this thread only*. It is handed every message
 *    the loop retrieves, before it is dispatched, which is exactly where
 *    accelerator translation belongs. A handled keystroke is blanked to
 *    WM_NULL so the loop does not also deliver it to the focused control.
 *
 * The two never both fire for one keystroke: each covers the focus the other
 * cannot see.
 */

static std::map<HWND, HACCEL> g_accel_tables;
static HHOOK g_msg_hook = nullptr;

/* Tables a previous install replaced. They are not destroyed on the spot: a
 * menu callback may call Menu.set again, and that callback runs *inside*
 * TranslateAccelerator, which is still using the table that install would be
 * freeing. Retiring them and destroying them at the next install -- by which
 * point no translation can still be in flight -- avoids the use-after-free. */
static std::vector<HACCEL> g_retired_accels;

static void wv_destroy_retired_accels() {
  for (HACCEL retired : g_retired_accels)
    if (retired != nullptr)
      DestroyAcceleratorTable(retired);
  g_retired_accels.clear();
}

/* Accelerators collected while the current bar is being built, consumed by
 * install. Menus are built one at a time on the UI thread, so a single
 * pending list is enough. */
static std::vector<ACCEL> g_pending_accels;

/* The installed entries of each window, kept alongside its HACCEL so that
 * route 1 can match against them without a CopyAcceleratorTable round trip. */
static std::map<HWND, std::vector<ACCEL>> g_accel_entries;

/* The command bound to [vk] under the modifiers currently held, or -1. Like
 * TranslateAccelerator, the modifiers must match exactly: Ctrl+O does not
 * fire on Ctrl+Shift+O. */
static int wv_find_accel(HWND hwnd, UINT vk) {
  auto it = g_accel_entries.find(hwnd);
  if (it == g_accel_entries.end())
    return -1;
  bool ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
  bool alt = (GetKeyState(VK_MENU) & 0x8000) != 0;
  bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
  for (const ACCEL &entry : it->second) {
    if (entry.key == vk && ((entry.fVirt & FCONTROL) != 0) == ctrl &&
        ((entry.fVirt & FALT) != 0) == alt &&
        ((entry.fVirt & FSHIFT) != 0) == shift)
      return entry.cmd;
  }
  return -1;
}

/* Spelled out rather than taken from the SDK, as vendor/webview.h does:
 * WebView2.h only declares its IIDs, and no mingw import library defines
 * them. */
static constexpr IID wv_IID_AcceleratorKeyPressedEventHandler{
    0xb29c7e28,
    0xfa79,
    0x41a8,
    {0x8e, 0x44, 0x65, 0x81, 0x1c, 0x76, 0xdc, 0xb2}};

/* Route 1: the controller's AcceleratorKeyPressed handler, one per window. */
class wv_accelerator_handler final
    : public ICoreWebView2AcceleratorKeyPressedEventHandler {
public:
  explicit wv_accelerator_handler(HWND hwnd) : m_hwnd(hwnd) {}

  ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refs; }

  ULONG STDMETHODCALLTYPE Release() override {
    ULONG refs = --m_refs;
    if (refs == 0)
      delete this;
    return refs;
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
    if (ppv == nullptr)
      return E_POINTER;
    if (IsEqualIID(riid, IID_IUnknown) ||
        IsEqualIID(riid, wv_IID_AcceleratorKeyPressedEventHandler)) {
      *ppv = static_cast<ICoreWebView2AcceleratorKeyPressedEventHandler *>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  HRESULT STDMETHODCALLTYPE
  Invoke(ICoreWebView2Controller *sender,
         ICoreWebView2AcceleratorKeyPressedEventArgs *args) override {
    (void)sender;
    COREWEBVIEW2_KEY_EVENT_KIND kind;
    if (FAILED(args->get_KeyEventKind(&kind)) ||
        (kind != COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN &&
         kind != COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN))
      return S_OK;
    UINT vk = 0;
    if (FAILED(args->get_VirtualKey(&vk)))
      return S_OK;
    int command = wv_find_accel(m_hwnd, vk);
    if (command < 0)
      return S_OK;
    args->put_Handled(TRUE);
    /* Posted, not sent: the menu callback then runs from our own loop, once
     * WebView2 has returned from this event, rather than nested inside it --
     * where a modal dialog or a Menu.set would be reentering the browser. */
    PostMessageW(m_hwnd, WM_COMMAND, MAKEWPARAM(command, 1), 0);
    return S_OK;
  }

private:
  HWND m_hwnd;
  ULONG m_refs = 1;
};

/* The controller each window's handler is registered on, AddRef'd for as long
 * as the registration lasts, and the token to remove it with. */
struct wv_key_subscription {
  ICoreWebView2Controller *controller;
  EventRegistrationToken token;
};
static std::map<HWND, wv_key_subscription> g_key_subscriptions;

static void wv_subscribe_keys(HWND hwnd, ICoreWebView2Controller *controller) {
  if (controller == nullptr ||
      g_key_subscriptions.find(hwnd) != g_key_subscriptions.end())
    return;
  wv_accelerator_handler *handler = new wv_accelerator_handler(hwnd);
  EventRegistrationToken token;
  if (SUCCEEDED(controller->add_AcceleratorKeyPressed(handler, &token))) {
    controller->AddRef();
    g_key_subscriptions[hwnd] = wv_key_subscription{controller, token};
  }
  /* The controller holds its own reference from here on. */
  handler->Release();
}

static void wv_unsubscribe_keys(HWND hwnd) {
  auto it = g_key_subscriptions.find(hwnd);
  if (it == g_key_subscriptions.end())
    return;
  it->second.controller->remove_AcceleratorKeyPressed(it->second.token);
  it->second.controller->Release();
  g_key_subscriptions.erase(it);
}

/* ACCEL entries are virtual-key codes. For letters and digits the VK code is
 * the uppercase ASCII value; anything else goes through the keyboard layout. */
static WORD wv_virtual_key(char c) {
  if (c >= 'a' && c <= 'z')
    return static_cast<WORD>(c - 'a' + 'A');
  if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
    return static_cast<WORD>(c);
  SHORT vk = VkKeyScanW(static_cast<wchar_t>(c));
  return vk == -1 ? 0 : static_cast<WORD>(vk & 0xFF);
}

static LRESULT CALLBACK wv_getmsg_hook(int code, WPARAM wp, LPARAM lp) {
  if (code == HC_ACTION && wp == PM_REMOVE) {
    MSG *msg = reinterpret_cast<MSG *>(lp);
    if (msg != nullptr &&
        (msg->message == WM_KEYDOWN || msg->message == WM_SYSKEYDOWN ||
         msg->message == WM_CHAR || msg->message == WM_SYSCHAR)) {
      /* Snapshot before translating: TranslateAccelerator sends WM_COMMAND
       * synchronously, so a menu callback runs before it returns, and that
       * callback may reinstall the menu -- mutating g_accel_tables under an
       * iterator that is still walking it. */
      std::vector<std::pair<HWND, HACCEL>> tables(g_accel_tables.begin(),
                                                  g_accel_tables.end());
      for (auto &entry : tables) {
        /* TranslateAccelerator matches when msg->hwnd is the window or any
         * descendant of it -- among those owned by this thread, that is; the
         * page's input window is not one of them (route 1 above). */
        if (entry.second != nullptr &&
            TranslateAcceleratorW(entry.first, entry.second, msg)) {
          msg->message = WM_NULL;
          msg->wParam = 0;
          msg->lParam = 0;
          break;
        }
      }
    }
  }
  return CallNextHookEx(g_msg_hook, code, wp, lp);
}

static std::wstring wv_widen(const char *utf8) {
  if (utf8 == nullptr || *utf8 == '\0')
    return std::wstring();
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  if (len <= 0)
    return std::wstring();
  std::wstring out(static_cast<size_t>(len - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &out[0], len);
  return out;
}

static LRESULT CALLBACK wv_menu_wndproc(HWND hwnd, UINT msg, WPARAM wp,
                                        LPARAM lp) {
  auto it = g_prev_wndproc.find(hwnd);
  WNDPROC previous = (it == g_prev_wndproc.end()) ? nullptr : it->second;
  /* HIWORD(wp) is 0 for a menu command and 1 for an accelerator; both are
   * ours and both carry the command id in LOWORD(wp). A control notification
   * has the control's handle in lParam, so a null lParam rules it out. */
  if (msg == WM_COMMAND && lp == 0 && (HIWORD(wp) == 0 || HIWORD(wp) == 1)) {
    wv_menu_activate(static_cast<int>(LOWORD(wp)));
    return 0;
  }
  if (msg == WM_NCDESTROY) {
    auto accel = g_accel_tables.find(hwnd);
    if (accel != g_accel_tables.end()) {
      if (accel->second != nullptr)
        DestroyAcceleratorTable(accel->second);
      g_accel_tables.erase(accel);
    }
    g_accel_entries.erase(hwnd);
    wv_unsubscribe_keys(hwnd);
    wv_destroy_retired_accels();
    if (g_accel_tables.empty() && g_msg_hook != nullptr) {
      UnhookWindowsHookEx(g_msg_hook);
      g_msg_hook = nullptr;
    }
    if (previous != nullptr) {
      SetWindowLongPtrW(hwnd, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(previous));
      g_prev_wndproc.erase(hwnd);
      return CallWindowProcW(previous, hwnd, msg, wp, lp);
    }
  }
  if (previous != nullptr)
    return CallWindowProcW(previous, hwnd, msg, wp, lp);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

/* "Open" + Ctrl+O -> "Open\tCtrl+O". Win32 draws whatever follows the tab
 * right-aligned in the item; see the note in menu.mli about these being
 * labels only. */
static std::string wv_accel_label(const char *label, const char *key,
                                  int modifiers) {
  std::string out(label);
  if (key == nullptr || *key == '\0')
    return out;
  out += '\t';
  if (modifiers & (WV_MOD_CMD | WV_MOD_CTRL))
    out += "Ctrl+";
  if (modifiers & WV_MOD_ALT)
    out += "Alt+";
  if (modifiers & WV_MOD_SHIFT)
    out += "Shift+";
  char upper = static_cast<char>(
      (*key >= 'a' && *key <= 'z') ? *key - 'a' + 'A' : *key);
  out += upper;
  return out;
}
#endif /* _WIN32 */

extern "C" {

/* Register the OCaml closure that every menu activation is routed to. */
CAMLprim value ocaml_webview_menu_set_dispatch(value vf) {
  CAMLparam1(vf);
  if (g_has_dispatch) {
    caml_remove_generational_global_root(&g_dispatch);
    g_has_dispatch = false;
  }
  g_dispatch = vf;
  caml_register_generational_global_root(&g_dispatch);
  g_has_dispatch = true;
  CAMLreturn(Val_unit);
}

/* Create an empty menu bar and return an opaque handle to it. */
CAMLprim value ocaml_webview_menu_create_bar(value vunit) {
  CAMLparam1(vunit);
  void *bar = nullptr;
#if defined(__APPLE__)
  bar = wv_alloc_init("NSMenu");
#elif defined(__linux__) && GTK_MAJOR_VERSION < 4
  GtkWidget *menubar = gtk_menu_bar_new();
  GtkAccelGroup *accel = gtk_accel_group_new();
  g_object_set_data(G_OBJECT(menubar), WV_ACCEL_KEY, accel);
  bar = menubar;
#elif defined(_WIN32)
  g_pending_accels.clear();
  bar = CreateMenu();
#endif
  CAMLreturn(wv_val_of_ptr(bar));
}

/* Append a submenu titled [vlabel] to [vparent], and return a handle to the
 * new submenu so its own items can be added to it. */
CAMLprim value ocaml_webview_menu_add_submenu(value vparent, value vlabel) {
  CAMLparam2(vparent, vlabel);
  void *parent = wv_ptr_of_val(vparent);
  const char *label = String_val(vlabel);
  void *child = nullptr;
  if (parent == nullptr)
    CAMLreturn(wv_val_of_ptr(nullptr));
#if defined(__APPLE__)
  {
    id title = wv_nsstring(label);
    id submenu = ((id(*)(Class, SEL))objc_msgSend)(objc_getClass("NSMenu"),
                                                   sel_registerName("alloc"));
    submenu = ((id(*)(id, SEL, id))objc_msgSend)(
        submenu, sel_registerName("initWithTitle:"), title);
    id item = ((id(*)(Class, SEL))objc_msgSend)(objc_getClass("NSMenuItem"),
                                                sel_registerName("alloc"));
    item = ((id(*)(id, SEL, id, SEL, id))objc_msgSend)(
        item, sel_registerName("initWithTitle:action:keyEquivalent:"), title,
        nullptr, wv_nsstring(""));
    ((void (*)(id, SEL, id))objc_msgSend)(
        item, sel_registerName("setSubmenu:"), submenu);
    ((void (*)(id, SEL, id))objc_msgSend)(
        reinterpret_cast<id>(parent), sel_registerName("addItem:"), item);
    child = submenu;
  }
#elif defined(__linux__) && GTK_MAJOR_VERSION < 4
  {
    GtkWidget *shell = static_cast<GtkWidget *>(parent);
    GtkWidget *item = gtk_menu_item_new_with_label(label);
    GtkWidget *submenu = gtk_menu_new();
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), submenu);
    gtk_menu_shell_append(GTK_MENU_SHELL(shell), item);
    /* Carry the accelerator group down, so add_item can reach it from any
     * depth without knowing which bar it belongs to. */
    g_object_set_data(G_OBJECT(submenu), WV_ACCEL_KEY,
                      g_object_get_data(G_OBJECT(shell), WV_ACCEL_KEY));
    child = submenu;
  }
#elif defined(_WIN32)
  {
    HMENU submenu = CreatePopupMenu();
    std::wstring wlabel = wv_widen(label);
    AppendMenuW(static_cast<HMENU>(parent), MF_POPUP,
                reinterpret_cast<UINT_PTR>(submenu), wlabel.c_str());
    child = submenu;
  }
#endif
  CAMLreturn(wv_val_of_ptr(child));
}

/* Append a clickable item. [vkey] is the accelerator key as a one-character
 * string, or empty for none; [vmodifiers] is the bit mask above; [vcommand]
 * is the id handed back to the dispatch closure. */
CAMLprim value ocaml_webview_menu_add_item(value vparent, value vlabel,
                                           value vkey, value vmodifiers,
                                           value vcommand) {
  CAMLparam5(vparent, vlabel, vkey, vmodifiers, vcommand);
  void *parent = wv_ptr_of_val(vparent);
  const char *label = String_val(vlabel);
  const char *key = String_val(vkey);
  int modifiers = Int_val(vmodifiers);
  int command = Int_val(vcommand);
  if (parent == nullptr)
    CAMLreturn(Val_unit);
#if defined(__APPLE__)
  {
    id item = ((id(*)(Class, SEL))objc_msgSend)(objc_getClass("NSMenuItem"),
                                                sel_registerName("alloc"));
    item = ((id(*)(id, SEL, id, SEL, id))objc_msgSend)(
        item, sel_registerName("initWithTitle:action:keyEquivalent:"),
        wv_nsstring(label), wv_action_sel(), wv_nsstring(key));
    ((void (*)(id, SEL, id))objc_msgSend)(
        item, sel_registerName("setTarget:"), wv_action_target());
    ((void (*)(id, SEL, long))objc_msgSend)(
        item, sel_registerName("setTag:"), static_cast<long>(command));
    if (*key != '\0')
      ((void (*)(id, SEL, unsigned long))objc_msgSend)(
          item, sel_registerName("setKeyEquivalentModifierMask:"),
          wv_cocoa_mask(modifiers));
    ((void (*)(id, SEL, id))objc_msgSend)(
        reinterpret_cast<id>(parent), sel_registerName("addItem:"), item);
  }
#elif defined(__linux__) && GTK_MAJOR_VERSION < 4
  {
    GtkWidget *shell = static_cast<GtkWidget *>(parent);
    GtkWidget *item = gtk_menu_item_new_with_label(label);
    g_signal_connect(item, "activate", G_CALLBACK(wv_gtk_activate),
                     GINT_TO_POINTER(command));
    if (*key != '\0') {
      GtkAccelGroup *accel = static_cast<GtkAccelGroup *>(
          g_object_get_data(G_OBJECT(shell), WV_ACCEL_KEY));
      if (accel != nullptr)
        /* For lowercase ASCII the GDK keyval is the character code. */
        gtk_widget_add_accelerator(item, "activate", accel,
                                   static_cast<guint>(*key),
                                   wv_gdk_mask(modifiers), GTK_ACCEL_VISIBLE);
    }
    gtk_menu_shell_append(GTK_MENU_SHELL(shell), item);
  }
#elif defined(_WIN32)
  {
    std::string text = wv_accel_label(label, key, modifiers);
    std::wstring wtext = wv_widen(text.c_str());
    AppendMenuW(static_cast<HMENU>(parent), MF_STRING,
                static_cast<UINT_PTR>(command), wtext.c_str());
    if (*key != '\0') {
      WORD vk = wv_virtual_key(*key);
      if (vk != 0) {
        ACCEL entry;
        std::memset(&entry, 0, sizeof(entry));
        BYTE flags = FVIRTKEY | FNOINVERT;
        /* No Command key here: Cmd means the primary modifier, Control. */
        if (modifiers & (WV_MOD_CMD | WV_MOD_CTRL))
          flags |= FCONTROL;
        if (modifiers & WV_MOD_ALT)
          flags |= FALT;
        if (modifiers & WV_MOD_SHIFT)
          flags |= FSHIFT;
        entry.fVirt = flags;
        entry.key = vk;
        entry.cmd = static_cast<WORD>(command);
        g_pending_accels.push_back(entry);
      }
    }
  }
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value ocaml_webview_menu_add_separator(value vparent) {
  CAMLparam1(vparent);
  void *parent = wv_ptr_of_val(vparent);
  if (parent == nullptr)
    CAMLreturn(Val_unit);
#if defined(__APPLE__)
  {
    id sep = ((id(*)(Class, SEL))objc_msgSend)(
        objc_getClass("NSMenuItem"), sel_registerName("separatorItem"));
    ((void (*)(id, SEL, id))objc_msgSend)(
        reinterpret_cast<id>(parent), sel_registerName("addItem:"), sep);
  }
#elif defined(__linux__) && GTK_MAJOR_VERSION < 4
  gtk_menu_shell_append(GTK_MENU_SHELL(static_cast<GtkWidget *>(parent)),
                        gtk_separator_menu_item_new());
#elif defined(_WIN32)
  AppendMenuW(static_cast<HMENU>(parent), MF_SEPARATOR, 0, nullptr);
#endif
  CAMLreturn(Val_unit);
}

/* Install the finished bar. On macOS it becomes the application's main menu
 * and the window is ignored; elsewhere it belongs to that one window. */
CAMLprim value ocaml_webview_menu_install(value vwindow, value vcontroller,
                                          value vbar) {
  CAMLparam3(vwindow, vcontroller, vbar);
  void *window = wv_ptr_of_val(vwindow);
  /* The ICoreWebView2Controller on Windows; unused elsewhere. */
  void *controller = wv_ptr_of_val(vcontroller);
  (void)controller;
  void *bar = wv_ptr_of_val(vbar);
  if (bar == nullptr)
    CAMLreturn(Val_unit);

  /* Showing or attaching the bar can pump the platform event loop, which may
   * re-enter a trampoline that re-acquires the runtime lock. Release it
   * around the whole operation, as webview_run does. */
  caml_release_runtime_system();
#if defined(__APPLE__)
  (void)window; /* the menu bar is application-global on macOS */
  {
    id app = ((id(*)(Class, SEL))objc_msgSend)(
        objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    ((void (*)(id, SEL, id))objc_msgSend)(
        app, sel_registerName("setMainMenu:"), reinterpret_cast<id>(bar));
  }
#elif defined(__linux__)
#if GTK_MAJOR_VERSION < 4
  if (window != nullptr) {
    GtkWindow *win = static_cast<GtkWindow *>(window);
    GtkWidget *menubar = static_cast<GtkWidget *>(bar);
    GtkWidget *child = gtk_bin_get_child(GTK_BIN(win));
    GtkAccelGroup *accel = static_cast<GtkAccelGroup *>(
        g_object_get_data(G_OBJECT(menubar), WV_ACCEL_KEY));
    if (accel != nullptr)
      gtk_window_add_accel_group(win, accel);

    if (child != nullptr &&
        g_object_get_data(G_OBJECT(child), WV_BOX_KEY) != nullptr) {
      /* Re-installing: swap the menu bar inside the box we already own,
       * rather than nesting another one. */
      GList *kids = gtk_container_get_children(GTK_CONTAINER(child));
      if (kids != nullptr)
        gtk_container_remove(GTK_CONTAINER(child),
                             GTK_WIDGET(kids->data));
      g_list_free(kids);
      gtk_box_pack_start(GTK_BOX(child), menubar, FALSE, FALSE, 0);
      gtk_box_reorder_child(GTK_BOX(child), menubar, 0);
      gtk_widget_show_all(child);
    } else if (child != nullptr) {
      /* First install: the webview widget is the window's direct child, so
       * move it into a vertical box under the menu bar. */
      GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
      g_object_set_data(G_OBJECT(box), WV_BOX_KEY, box);
      g_object_ref(child);
      gtk_container_remove(GTK_CONTAINER(win), child);
      gtk_box_pack_start(GTK_BOX(box), menubar, FALSE, FALSE, 0);
      gtk_box_pack_start(GTK_BOX(box), child, TRUE, TRUE, 0);
      g_object_unref(child);
      gtk_container_add(GTK_CONTAINER(win), box);
      gtk_widget_show_all(box);
    }
  }
#else
  (void)window; /* GTK 4 replaced GtkMenuBar with the GMenu model */
#endif
#elif defined(_WIN32)
  if (window != nullptr) {
    HWND hwnd = static_cast<HWND>(window);
    if (g_prev_wndproc.find(hwnd) == g_prev_wndproc.end()) {
      WNDPROC previous = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
          hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(wv_menu_wndproc)));
      g_prev_wndproc[hwnd] = previous;
    }
    HMENU old = GetMenu(hwnd);
    SetMenu(hwnd, static_cast<HMENU>(bar));
    if (old != nullptr)
      DestroyMenu(old);
    DrawMenuBar(hwnd);

    /* Replace this window's accelerator table, and arm the message hook that
     * actually runs it (see the note above g_accel_tables). */
    wv_destroy_retired_accels();
    HACCEL accel = nullptr;
    if (!g_pending_accels.empty())
      accel = CreateAcceleratorTableW(
          g_pending_accels.data(), static_cast<int>(g_pending_accels.size()));
    auto previous_accel = g_accel_tables.find(hwnd);
    if (previous_accel != g_accel_tables.end() &&
        previous_accel->second != nullptr)
      g_retired_accels.push_back(previous_accel->second);
    g_accel_tables[hwnd] = accel;
    g_accel_entries[hwnd] = g_pending_accels;
    if (g_msg_hook == nullptr)
      g_msg_hook = SetWindowsHookExW(WH_GETMESSAGE, wv_getmsg_hook, nullptr,
                                     GetCurrentThreadId());
    /* And route 1, for when the page has the focus. The handler reads
     * g_accel_entries at each keystroke, so a reinstall needs no new
     * registration. */
    wv_subscribe_keys(hwnd, static_cast<ICoreWebView2Controller *>(controller));
  }
#endif
  caml_acquire_runtime_system();
  CAMLreturn(Val_unit);
}

} /* extern "C" */
