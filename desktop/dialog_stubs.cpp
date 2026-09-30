/* OCaml C stubs for the native dialogs.
 *
 * Like icon_stubs.cpp, this translation unit talks to Cocoa, GTK and Win32
 * directly and includes no part of vendor/webview.h: the parent window
 * arrives from OCaml as a nativeint obtained from [Webview.get_window].
 *
 * Every entry point here runs a *modal* dialog, which pumps the platform
 * event loop on the calling thread until the user dismisses it. Two
 * consequences drive the shape of the code below:
 *
 *  - The OCaml runtime lock must be released around the modal call. These
 *    stubs are meant to be called from a binding or dispatch callback, i.e.
 *    from inside webview's own event loop, and the nested loop can therefore
 *    re-enter a webview trampoline -- which re-acquires the lock. Holding it
 *    across the modal call would abort the process on OCaml 5 with "Fatal
 *    error during lock: Resource deadlock avoided".
 *
 *  - Any OCaml string argument must be copied out *before* the lock is
 *    released: once it is, the GC may run and move the value.
 */

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

#define CAML_NAME_SPACE
#include <caml/alloc.h>
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
#include <shobjidl.h> /* IFileOpenDialog */
#include <windows.h>  /* MessageBoxW */
#endif

/* The parent window, passed from OCaml as a nativeint (0n when the backend
 * could not provide one -- the dialog is then simply unparented). macOS runs
 * these app-modally and ignores it, so it is only needed elsewhere. */
#if defined(__linux__) || defined(_WIN32)
static inline void *wv_window_of_val(value v) {
  return reinterpret_cast<void *>(static_cast<intptr_t>(Nativeint_val(v)));
}
#endif

/* Copy an OCaml string to the C heap, so it survives the released-lock
 * section. The empty string means "no title": let the platform pick. */
static char *wv_strdup_val(value vs) {
  mlsize_t len = caml_string_length(vs);
  char *s = static_cast<char *>(std::malloc(len + 1));
  if (s == nullptr)
    caml_raise_out_of_memory();
  std::memcpy(s, String_val(vs), len);
  s[len] = '\0';
  return s;
}

#if defined(__APPLE__)
/* Wrap the Objective-C runtime C API, as icon_stubs.cpp does, so that this
 * compiles as plain C++ without a .mm file. */
static id wv_nsstring(const char *utf8) {
  return ((id(*)(Class, SEL, const char *))objc_msgSend)(
      objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
      utf8);
}

static id wv_send(id target, const char *selector) {
  return ((id(*)(id, SEL))objc_msgSend)(target, sel_registerName(selector));
}

static void wv_send_id(id target, const char *selector, id arg) {
  ((void (*)(id, SEL, id))objc_msgSend)(target, sel_registerName(selector),
                                        arg);
}

static void wv_send_bool(id target, const char *selector, bool arg) {
  ((void (*)(id, SEL, BOOL))objc_msgSend)(target, sel_registerName(selector),
                                          arg ? YES : NO);
}

static long wv_run_modal(id target) {
  return ((long (*)(id, SEL))objc_msgSend)(target,
                                           sel_registerName("runModal"));
}
#endif /* __APPLE__ */

#if defined(_WIN32)
/* UTF-8 -> UTF-16, for the wide Win32 entry points. Returns an empty vector
 * on a conversion failure, which the callers treat as "no text". */
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

static std::string wv_narrow(const wchar_t *w) {
  if (w == nullptr)
    return std::string();
  int len = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr,
                                nullptr);
  if (len <= 0)
    return std::string();
  std::string out(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w, -1, &out[0], len, nullptr, nullptr);
  return out;
}
#endif /* _WIN32 */

extern "C" {

/* Ask the user to confirm, with the platform's standard OK and Cancel
 * buttons. Returns true for OK, false for Cancel or for a dialog dismissed
 * any other way (Escape, the window's close button).
 *
 *  - macOS: an NSAlert, run app-modally. The parent window is ignored:
 *    attaching it as a sheet needs a completion block, which the Objective-C
 *    runtime C API cannot express.
 *  - Linux (GTK 3): a GtkMessageDialog, modal and transient for the parent.
 *  - Windows: MessageBoxW with MB_OKCANCEL, owned by the parent.
 *
 * A no-op returning false on any other backend. */
CAMLprim value ocaml_webview_dialog_confirm(value vwin, value vtitle,
                                            value vmessage) {
  CAMLparam3(vwin, vtitle, vmessage);
  char *title = wv_strdup_val(vtitle);
  char *message = wv_strdup_val(vmessage);
  bool ok = false;

#if defined(__linux__) || defined(_WIN32)
  void *parent = wv_window_of_val(vwin);
#else
  (void)vwin;
#endif

  caml_release_runtime_system();
#if defined(__APPLE__)
  {
    id alert = wv_send(reinterpret_cast<id>(objc_getClass("NSAlert")), "alloc");
    alert = wv_send(alert, "init");
    /* NSAlert shows messageText as the bold headline. With no title the
     * message takes that slot, which is what a one-line question wants. */
    if (*title != '\0') {
      wv_send_id(alert, "setMessageText:", wv_nsstring(title));
      wv_send_id(alert, "setInformativeText:", wv_nsstring(message));
    } else {
      wv_send_id(alert, "setMessageText:", wv_nsstring(message));
    }
    ((id(*)(id, SEL, id))objc_msgSend)(
        alert, sel_registerName("addButtonWithTitle:"), wv_nsstring("OK"));
    ((id(*)(id, SEL, id))objc_msgSend)(
        alert, sel_registerName("addButtonWithTitle:"), wv_nsstring("Cancel"));
    /* NSAlertFirstButtonReturn == 1000: the OK we added first. */
    ok = (wv_run_modal(alert) == 1000);
    wv_send(alert, "release");
  }
#elif defined(__linux__)
#if GTK_MAJOR_VERSION < 4
  {
    GtkWindow *win = static_cast<GtkWindow *>(parent);
    GtkWidget *dialog = gtk_message_dialog_new(
        win, static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL |
                                         GTK_DIALOG_DESTROY_WITH_PARENT),
        GTK_MESSAGE_QUESTION, GTK_BUTTONS_OK_CANCEL, "%s", message);
    if (*title != '\0')
      gtk_window_set_title(GTK_WINDOW(dialog), title);
    ok = (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_OK);
    gtk_widget_destroy(dialog);
  }
#else
  (void)parent; /* GTK 4 removed gtk_dialog_run; see the note in dialog.mli */
#endif
#elif defined(_WIN32)
  {
    std::wstring wmessage = wv_widen(message);
    std::wstring wtitle = wv_widen(title);
    int r = MessageBoxW(static_cast<HWND>(parent), wmessage.c_str(),
                        wtitle.empty() ? nullptr : wtitle.c_str(),
                        MB_OKCANCEL | MB_ICONQUESTION);
    ok = (r == IDOK);
  }
#endif
  caml_acquire_runtime_system();

  std::free(title);
  std::free(message);
  CAMLreturn(Val_bool(ok));
}

/* Open the system file browser and let the user pick one existing file, or
 * one existing directory when [vdirectory] is true. Returns the selected
 * path, or the empty string when the user cancelled (the OCaml side maps that
 * to [None]).
 *
 *  - macOS: NSOpenPanel, run app-modally.
 *  - Linux (GTK 3): a GtkFileChooserDialog, modal and transient for the
 *    parent.
 *  - Windows: IFileOpenDialog, with FOS_PICKFOLDERS for a directory.
 *
 * A no-op returning the empty string on any other backend. */
CAMLprim value ocaml_webview_dialog_open(value vwin, value vtitle,
                                         value vdirectory) {
  CAMLparam3(vwin, vtitle, vdirectory);
  char *title = wv_strdup_val(vtitle);
  bool directory = Bool_val(vdirectory);
  std::string path;

#if defined(__linux__) || defined(_WIN32)
  void *parent = wv_window_of_val(vwin);
#else
  (void)vwin;
#endif

  caml_release_runtime_system();
#if defined(__APPLE__)
  {
    id panel = ((id(*)(Class, SEL))objc_msgSend)(
        objc_getClass("NSOpenPanel"), sel_registerName("openPanel"));
    wv_send_bool(panel, "setCanChooseFiles:", !directory);
    wv_send_bool(panel, "setCanChooseDirectories:", directory);
    wv_send_bool(panel, "setAllowsMultipleSelection:", false);
    /* setMessage: is the text shown above the browser; setTitle: is ignored
     * by modern panels. */
    if (*title != '\0')
      wv_send_id(panel, "setMessage:", wv_nsstring(title));
    /* NSModalResponseOK == 1. */
    if (wv_run_modal(panel) == 1) {
      id url = wv_send(panel, "URL");
      if (url != nullptr) {
        id nspath = wv_send(url, "path");
        if (nspath != nullptr) {
          const char *utf8 = ((const char *(*)(id, SEL))objc_msgSend)(
              nspath, sel_registerName("UTF8String"));
          if (utf8 != nullptr)
            path = utf8;
        }
      }
    }
  }
#elif defined(__linux__)
#if GTK_MAJOR_VERSION < 4
  {
    GtkWindow *win = static_cast<GtkWindow *>(parent);
    const char *heading =
        *title != '\0' ? title : (directory ? "Select Folder" : "Open File");
    GtkWidget *dialog = gtk_file_chooser_dialog_new(
        heading, win,
        directory ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
                  : GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Cancel", GTK_RESPONSE_CANCEL, "_Open", GTK_RESPONSE_ACCEPT,
        static_cast<const char *>(NULL));
    gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
      char *chosen =
          gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
      if (chosen != nullptr) {
        path = chosen;
        g_free(chosen);
      }
    }
    gtk_widget_destroy(dialog);
  }
#else
  (void)parent;
  (void)directory; /* GTK 4: see the note in dialog.mli */
#endif
#elif defined(_WIN32)
  {
    /* The UI thread already lives in an apartment (WebView2 needs one), but
     * this may run before that; balance only the call we actually made. */
    HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    bool co_owned = (co == S_OK || co == S_FALSE);
    IFileOpenDialog *dialog = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_IFileOpenDialog,
                                   reinterpret_cast<void **>(&dialog)))) {
      if (directory) {
        DWORD options = 0;
        if (SUCCEEDED(dialog->GetOptions(&options)))
          dialog->SetOptions(options | FOS_PICKFOLDERS);
      }
      std::wstring wtitle = wv_widen(title);
      if (!wtitle.empty())
        dialog->SetTitle(wtitle.c_str());
      if (SUCCEEDED(dialog->Show(static_cast<HWND>(parent)))) {
        IShellItem *item = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item)) && item != nullptr) {
          PWSTR chosen = nullptr;
          if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &chosen))) {
            path = wv_narrow(chosen);
            CoTaskMemFree(chosen);
          }
          item->Release();
        }
      }
      dialog->Release();
    }
    if (co_owned)
      CoUninitialize();
  }
#endif
  caml_acquire_runtime_system();

  std::free(title);
  CAMLreturn(caml_copy_string(path.c_str()));
}

} /* extern "C" */
