// Oanarina Archi Tool — GPL-3.0-or-later
// Windows File Explorer thumbnails of .archi drawings (FILEPREVIEW; the Mac sets a Finder preview icon).
// An in-process COM server implementing IInitializeWithStream + IThumbnailProvider. Explorer loads it in its isolated
// thumbnail host (dllhost.exe) for the .archi type (HKCU\Software\Classes\.archi\ShellEx\{e357fccd-…}, registered per
// user by the NSIS installer, packaging/installer.nsh). It never runs the engine: archi-engine embeds a PNG plan
// picture at the end of every saved .archi file (ArchiCore IO/ArchiFile.swift, envelope key "preview"):
//   { "app" : …, "document" : {…}, "formatVersion" : N, "preview" : { "height" : 512, "png" : "<base64>", "width" : 512 } }
// The handler reads the last 16 MB of the file, takes the last "preview" key (it must be the last top-level value: one
// '{' and two '}' after it, the same rule as ArchiFile.preview(in:)), base64-decodes the PNG and scales it with WIC.
// A file without a picture returns E_FAIL, so Explorer shows the normal document icon.
// Build (windows/native/build.cmd, .github/workflows/windows-app.yml): MSVC, static CRT (/MT), no dependencies beyond
// the Windows SDK. Unsigned until the app has a code-signing certificate.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <propsys.h>
#include <thumbcache.h>
#include <wincodec.h>
#include <new>
#include <string>
#include <vector>

#include "ArchiThumbnail.h"

static HMODULE g_module = nullptr;
static volatile LONG g_objects = 0;
static volatile LONG g_locks = 0;

// MARK: - The thumbnail provider

class ArchiThumbnailProvider final : public IInitializeWithStream, public IThumbnailProvider {
 public:
  ArchiThumbnailProvider() { InterlockedIncrement(&g_objects); }

  IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IInitializeWithStream)) *ppv = static_cast<IInitializeWithStream*>(this);
    else if (riid == __uuidof(IThumbnailProvider)) *ppv = static_cast<IThumbnailProvider*>(this);
    else return E_NOINTERFACE;
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }
  IFACEMETHODIMP_(ULONG) Release() override {
    const LONG r = InterlockedDecrement(&ref_);
    if (r == 0) delete this;
    return static_cast<ULONG>(r);
  }

  // IInitializeWithStream
  IFACEMETHODIMP Initialize(IStream* stream, DWORD) override {
    if (!stream) return E_INVALIDARG;
    if (stream_) return HRESULT_FROM_WIN32(ERROR_ALREADY_INITIALIZED);
    return stream->QueryInterface(IID_PPV_ARGS(&stream_));
  }

  // IThumbnailProvider
  IFACEMETHODIMP GetThumbnail(UINT cx, HBITMAP* phbmp, WTS_ALPHATYPE* alpha) override {
    if (!phbmp || !alpha) return E_POINTER;
    *phbmp = nullptr;
    *alpha = WTSAT_ARGB;
    if (!stream_) return E_UNEXPECTED;
    std::vector<unsigned char> png;
    HRESULT hr = ArchiReadPreviewPNG(stream_, png);
    if (FAILED(hr)) return hr;
    return ArchiDecodeToBitmap(png, cx, phbmp);
  }

 private:
  ~ArchiThumbnailProvider() {
    if (stream_) stream_->Release();
    InterlockedDecrement(&g_objects);
  }
  volatile LONG ref_ = 1;
  IStream* stream_ = nullptr;
};

class ArchiClassFactory final : public IClassFactory {
 public:
  IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IClassFactory)) { *ppv = static_cast<IClassFactory*>(this); AddRef(); return S_OK; }
    return E_NOINTERFACE;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { InterlockedIncrement(&g_locks); return 2; }
  IFACEMETHODIMP_(ULONG) Release() override { InterlockedDecrement(&g_locks); return 1; }
  IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    ArchiThumbnailProvider* p = new (std::nothrow) ArchiThumbnailProvider();
    if (!p) return E_OUTOFMEMORY;
    const HRESULT hr = p->QueryInterface(riid, ppv);
    p->Release();
    return hr;
  }
  IFACEMETHODIMP LockServer(BOOL lock) override {
    if (lock) InterlockedIncrement(&g_locks); else InterlockedDecrement(&g_locks);
    return S_OK;
  }
};

static ArchiClassFactory g_factory;

// MARK: - DLL exports (ArchiThumbnail.def)

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) { g_module = module; DisableThreadLibraryCalls(module); }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void** ppv) {
  if (!ppv) return E_POINTER;
  *ppv = nullptr;
  if (clsid != CLSID_ArchiThumbnailProvider) return CLASS_E_CLASSNOTAVAILABLE;
  return g_factory.QueryInterface(riid, ppv);
}

STDAPI DllCanUnloadNow() { return (g_objects == 0 && g_locks == 0) ? S_OK : S_FALSE; }

// regsvr32 /n /i:user ArchiThumbnail-x64.dll (or DllRegisterServer): the same per-user keys the installer writes, for
// development machines; the installer does not call it (a 32-bit installer cannot load a 64-bit DLL).
static LSTATUS SetKey(const wchar_t* key, const wchar_t* name, const wchar_t* value) {
  HKEY h = nullptr;
  LSTATUS s = RegCreateKeyExW(HKEY_CURRENT_USER, key, 0, nullptr, 0, KEY_WRITE, nullptr, &h, nullptr);
  if (s != ERROR_SUCCESS) return s;
  s = RegSetValueExW(h, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value), static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t)));
  RegCloseKey(h);
  return s;
}

STDAPI DllRegisterServer() {
  wchar_t path[MAX_PATH];
  if (!GetModuleFileNameW(g_module, path, MAX_PATH)) return HRESULT_FROM_WIN32(GetLastError());
  const std::wstring clsid = kArchiThumbnailClsidString;
  const std::wstring k = L"Software\\Classes\\CLSID\\" + clsid;
  LSTATUS s = SetKey(k.c_str(), nullptr, L"Oanarina Archi Tool thumbnail handler");
  if (s == ERROR_SUCCESS) s = SetKey((k + L"\\InprocServer32").c_str(), nullptr, path);
  if (s == ERROR_SUCCESS) s = SetKey((k + L"\\InprocServer32").c_str(), L"ThreadingModel", L"Apartment");
  if (s == ERROR_SUCCESS) s = SetKey(kArchiThumbnailShellExKey, nullptr, clsid.c_str());
  if (s != ERROR_SUCCESS) return HRESULT_FROM_WIN32(s);
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return S_OK;
}

STDAPI DllUnregisterServer() {
  const std::wstring k = std::wstring(L"Software\\Classes\\CLSID\\") + kArchiThumbnailClsidString;
  RegDeleteTreeW(HKEY_CURRENT_USER, k.c_str());
  RegDeleteTreeW(HKEY_CURRENT_USER, kArchiThumbnailShellExKey);
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return S_OK;
}

STDAPI DllInstall(BOOL install, LPCWSTR) { return install ? DllRegisterServer() : DllUnregisterServer(); }
