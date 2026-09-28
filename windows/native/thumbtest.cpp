// Oanarina Archi Tool — GPL-3.0-or-later
// CI test of the installed Explorer thumbnail handler (.github/workflows/windows-app.yml, after the per-user install):
//   thumbtest.exe <drawing-with-picture.archi> <drawing-without-picture.archi> <out.bmp>
// 1. the registry keys the installer wrote: HKCU .archi ShellEx {e357fccd-…} → our CLSID → InprocServer32 = an existing DLL;
// 2. COM loads that DLL (CoCreateInstance through the registration, the way Explorer's thumbnail host does), the provider
//    makes a 256 px bitmap from the first file (a plan: dark pixels on white), written to out.bmp for the logs;
// 3. the second file (no embedded picture) gives no thumbnail (Explorer then shows the document icon);
// 4. best effort, reported but not failing: the shell's own path, IShellItemImageFactory::GetImage(SIIGBF_THUMBNAILONLY).
// Also checks the picture finder on in-memory samples (the rules ArchiFile.preview(in:) follows in Swift).
// Exit code 0 = every required check passed.
#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <propsys.h>
#include <thumbcache.h>
#include <cstdio>
#include <string>
#include <vector>

#include "ArchiThumbnail.h"

static int g_fail = 0;
static void Check(bool ok, const char* name, const std::string& detail = "") {
  std::printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name, detail.empty() ? "" : "  ", detail.c_str());
  if (!ok) g_fail = 1;
}
static std::string Narrow(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string s(static_cast<size_t>(n > 0 ? n - 1 : 0), '\0');
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
  return s;
}
static std::string Hex(HRESULT hr) { char b[16]; std::snprintf(b, sizeof b, "0x%08lX", static_cast<unsigned long>(hr)); return b; }
static std::wstring RegString(const wchar_t* key, const wchar_t* value) {
  wchar_t buf[1024];
  DWORD size = sizeof(buf);
  if (RegGetValueW(HKEY_CURRENT_USER, key, value, RRF_RT_REG_SZ, nullptr, buf, &size) != ERROR_SUCCESS) return L"";
  return buf;
}

struct BitmapInfo { int width = 0, height = 0, dark = 0; std::vector<unsigned char> bgra; };
static BitmapInfo Inspect(HBITMAP bmp) {
  BitmapInfo r;
  BITMAP bm = {};
  if (!GetObjectW(bmp, sizeof(bm), &bm)) return r;
  r.width = bm.bmWidth; r.height = bm.bmHeight < 0 ? -bm.bmHeight : bm.bmHeight;
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = r.width; bi.bmiHeader.biHeight = -r.height; bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
  r.bgra.resize(static_cast<size_t>(r.width) * r.height * 4);
  HDC dc = GetDC(nullptr);
  const int lines = GetDIBits(dc, bmp, 0, static_cast<UINT>(r.height), r.bgra.data(), &bi, DIB_RGB_COLORS);
  ReleaseDC(nullptr, dc);
  if (lines != r.height) { r.bgra.clear(); return r; }
  for (size_t i = 0; i + 3 < r.bgra.size(); i += 4)
    if (r.bgra[i] < 200 || r.bgra[i + 1] < 200 || r.bgra[i + 2] < 200) r.dark++;
  return r;
}
static bool WriteBMP(const wchar_t* path, const BitmapInfo& b) {
  if (b.bgra.empty()) return false;
  BITMAPFILEHEADER fh = {};
  BITMAPINFOHEADER ih = {};
  ih.biSize = sizeof(ih); ih.biWidth = b.width; ih.biHeight = -b.height; ih.biPlanes = 1; ih.biBitCount = 32; ih.biCompression = BI_RGB;
  fh.bfType = 0x4D42;
  fh.bfOffBits = sizeof(fh) + sizeof(ih);
  fh.bfSize = fh.bfOffBits + static_cast<DWORD>(b.bgra.size());
  FILE* f = nullptr;
  if (_wfopen_s(&f, path, L"wb") != 0 || !f) return false;
  std::fwrite(&fh, sizeof(fh), 1, f); std::fwrite(&ih, sizeof(ih), 1, f); std::fwrite(b.bgra.data(), 1, b.bgra.size(), f);
  std::fclose(f);
  return true;
}

static HRESULT Thumbnail(const wchar_t* file, UINT cx, HBITMAP* bmp) {
  *bmp = nullptr;
  IThumbnailProvider* provider = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ArchiThumbnailProvider, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&provider));
  if (FAILED(hr)) { std::printf("      CoCreateInstance: %s\n", Hex(hr).c_str()); return hr; }
  IInitializeWithStream* init = nullptr;
  IStream* stream = nullptr;
  hr = provider->QueryInterface(IID_PPV_ARGS(&init));
  if (SUCCEEDED(hr)) hr = SHCreateStreamOnFileEx(file, STGM_READ | STGM_SHARE_DENY_NONE, FILE_ATTRIBUTE_NORMAL, FALSE, nullptr, &stream);
  if (SUCCEEDED(hr)) hr = init->Initialize(stream, STGM_READ);
  WTS_ALPHATYPE alpha = WTSAT_UNKNOWN;
  if (SUCCEEDED(hr)) hr = provider->GetThumbnail(cx, bmp, &alpha);
  if (stream) stream->Release();
  if (init) init->Release();
  provider->Release();
  return hr;
}

static void FinderChecks() {
  std::vector<unsigned char> png;
  const std::string good = "{\n  \"app\" : \"Oanarina Archi Tool\",\n  \"document\" : {\n    \"props\" : { \"preview\" : \"x\" }\n  },\n"
                           "  \"formatVersion\" : 3,\n  \"preview\" : {\n    \"height\" : 1,\n    \"png\" : \"iVBORw0KGgoAAAANSUhEUg==\",\n    \"width\" : 1\n  }\n}";
  Check(ArchiFindPreviewPNG(good.data(), good.size(), png) && png.size() == 16, "finder: envelope picture found", std::to_string(png.size()) + " bytes");
  const std::string inner = "{\n  \"app\" : \"Oanarina Archi Tool\",\n  \"document\" : {\n    \"props\" : { \"preview\" : { \"png\" : \"iVBORw0KGgoAAAANSUhEUg==\" } }\n  },\n  \"formatVersion\" : 3\n}";
  Check(!ArchiFindPreviewPNG(inner.data(), inner.size(), png), "finder: a \"preview\" inside the document is ignored");
  const std::string escaped = "{\"preview\":{\"png\":\"iVBORw0KGgoAAAANSUhEUg\\/\\/\"}}";
  Check(ArchiFindPreviewPNG(escaped.data(), escaped.size(), png), "finder: JSON \\/ escapes are decoded");
}

int wmain(int argc, wchar_t** argv) {
  if (argc < 4) { std::printf("usage: thumbtest <with-picture.archi> <without-picture.archi> <out.bmp>\n"); return 2; }
  FinderChecks();

  const std::wstring clsid = RegString(kArchiThumbnailShellExKey, nullptr);
  Check(_wcsicmp(clsid.c_str(), kArchiThumbnailClsidString) == 0, "HKCU .archi ShellEx {e357fccd-...} = handler CLSID", Narrow(clsid));
  const std::wstring clsidKey = std::wstring(L"Software\\Classes\\CLSID\\") + kArchiThumbnailClsidString + L"\\InprocServer32";
  const std::wstring dll = RegString(clsidKey.c_str(), nullptr);
  Check(!dll.empty() && GetFileAttributesW(dll.c_str()) != INVALID_FILE_ATTRIBUTES, "HKCU CLSID InprocServer32 = installed DLL", Narrow(dll));
  Check(_wcsicmp(RegString(clsidKey.c_str(), L"ThreadingModel").c_str(), L"Apartment") == 0, "ThreadingModel = Apartment");

  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(hr)) { Check(false, "CoInitializeEx", Hex(hr)); return 1; }
  HBITMAP bmp = nullptr;
  hr = Thumbnail(argv[1], 256, &bmp);
  Check(SUCCEEDED(hr) && bmp, "COM loads the handler and makes a thumbnail", Hex(hr));
  if (bmp) {
    const BitmapInfo b = Inspect(bmp);
    const bool fits = (b.width == 256 && b.height <= 256) || (b.height == 256 && b.width <= 256);
    Check(fits, "thumbnail fits 256 px", std::to_string(b.width) + "x" + std::to_string(b.height));
    Check(b.dark > 100 && b.dark < b.width * b.height / 2, "thumbnail shows the plan (dark pixels on white)", std::to_string(b.dark) + " dark pixels");
    Check(WriteBMP(argv[3], b), "thumbnail written", Narrow(argv[3]));
    DeleteObject(bmp);
  }
  bmp = nullptr;
  hr = Thumbnail(argv[2], 256, &bmp);
  Check(FAILED(hr) && !bmp, "a drawing without a picture gives no thumbnail (document icon)", Hex(hr));
  if (bmp) DeleteObject(bmp);

  // The shell's path (thumbnail cache, isolated host): informational only, hosted runners have no interactive shell.
  IShellItemImageFactory* f = nullptr;
  hr = SHCreateItemFromParsingName(argv[1], nullptr, IID_PPV_ARGS(&f));
  if (SUCCEEDED(hr)) {
    SIZE sz = {256, 256};
    HBITMAP sb = nullptr;
    hr = f->GetImage(sz, SIIGBF_THUMBNAILONLY, &sb);
    if (SUCCEEDED(hr) && sb) {
      const BitmapInfo b = Inspect(sb);
      std::printf("INFO  shell IShellItemImageFactory thumbnail %dx%d, %d dark pixels\n", b.width, b.height, b.dark);
      DeleteObject(sb);
    } else {
      std::printf("INFO  shell IShellItemImageFactory: %s (not required)\n", Hex(hr).c_str());
    }
    f->Release();
  } else {
    std::printf("INFO  SHCreateItemFromParsingName: %s (not required)\n", Hex(hr).c_str());
  }
  CoUninitialize();
  std::printf(g_fail ? "thumbtest: FAILED\n" : "thumbtest: all required checks passed\n");
  return g_fail;
}
