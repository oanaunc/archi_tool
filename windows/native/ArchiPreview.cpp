// Oanarina Archi Tool — GPL-3.0-or-later
// The embedded plan picture of an .archi file: finding it at the end of the file and decoding it into a bitmap.
// Used by the Explorer thumbnail handler (ArchiThumbnail.cpp) and its CI test (thumbtest.cpp).
#include <windows.h>
#include <objbase.h>
#include <wincodec.h>
#include <cstring>
#include <vector>

#include "ArchiThumbnail.h"

static int Base64Value(unsigned char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

bool ArchiDecodeBase64(const char* s, size_t n, std::vector<unsigned char>& out) {
  out.clear();
  out.reserve(n / 4 * 3);
  unsigned int acc = 0;
  int bits = 0;
  for (size_t i = 0; i < n; i++) {
    unsigned char c = static_cast<unsigned char>(s[i]);
    if (c == '=') break;
    if (c == '\\' || c == '\r' || c == '\n' || c == ' ') continue;  // JSON "\/" escapes, line breaks
    int v = Base64Value(c);
    if (v < 0) return false;
    acc = (acc << 6) | static_cast<unsigned int>(v);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push_back(static_cast<unsigned char>((acc >> bits) & 0xFF));
    }
  }
  return out.size() > 8;
}

bool ArchiFindPreviewPNG(const char* data, size_t n, std::vector<unsigned char>& png) {
  static const char key[] = "\"preview\"";
  const size_t keyLen = sizeof(key) - 1;
  if (n < keyLen) return false;
  size_t k = n - keyLen + 1;
  bool found = false;
  while (k-- > 0) {
    if (memcmp(data + k, key, keyLen) == 0) { found = true; break; }
  }
  if (!found) return false;
  const char* rest = data + k + keyLen;
  const size_t restLen = n - k - keyLen;
  size_t open = 0, close = 0;
  for (size_t i = 0; i < restLen; i++) {
    if (rest[i] == '{') open++;
    else if (rest[i] == '}') close++;
  }
  if (open != 1 || close != 2) return false;  // not the last top-level value of the envelope
  static const char pngKey[] = "\"png\"";
  const size_t pngLen = sizeof(pngKey) - 1;
  size_t p = 0;
  for (; p + pngLen <= restLen; p++) if (memcmp(rest + p, pngKey, pngLen) == 0) break;
  if (p + pngLen > restLen) return false;
  size_t q1 = p + pngLen;
  while (q1 < restLen && rest[q1] != '"') q1++;
  if (q1 >= restLen) return false;
  size_t q2 = q1 + 1;
  while (q2 < restLen && rest[q2] != '"') q2++;
  if (q2 >= restLen) return false;
  if (!ArchiDecodeBase64(rest + q1 + 1, q2 - q1 - 1, png)) return false;
  static const unsigned char magic[] = {0x89, 'P', 'N', 'G'};
  return png.size() > 8 && memcmp(png.data(), magic, 4) == 0;
}

HRESULT ArchiReadPreviewPNG(IStream* stream, std::vector<unsigned char>& png) {
  STATSTG st = {};
  HRESULT hr = stream->Stat(&st, STATFLAG_NONAME);
  if (FAILED(hr)) return hr;
  const ULONGLONG size = st.cbSize.QuadPart;
  const ULONGLONG tail = size < kArchiPreviewTailBytes ? size : kArchiPreviewTailBytes;
  if (tail < 16) return E_FAIL;
  LARGE_INTEGER pos;
  pos.QuadPart = static_cast<LONGLONG>(size - tail);
  hr = stream->Seek(pos, STREAM_SEEK_SET, nullptr);
  if (FAILED(hr)) return hr;
  std::vector<char> buf(static_cast<size_t>(tail));
  size_t got = 0;
  while (got < buf.size()) {
    ULONG n = 0;
    hr = stream->Read(buf.data() + got, static_cast<ULONG>(buf.size() - got), &n);
    if (FAILED(hr)) return hr;
    if (n == 0) break;
    got += n;
  }
  return ArchiFindPreviewPNG(buf.data(), got, png) ? S_OK : E_FAIL;
}

HRESULT ArchiDecodeToBitmap(const std::vector<unsigned char>& png, UINT cx, HBITMAP* phbmp) {
  *phbmp = nullptr;
  IWICImagingFactory* factory = nullptr;
  IWICStream* wstream = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  IWICBitmapFrameDecode* frame = nullptr;
  IWICBitmapScaler* scaler = nullptr;
  IWICFormatConverter* converter = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (SUCCEEDED(hr)) hr = factory->CreateStream(&wstream);
  if (SUCCEEDED(hr)) hr = wstream->InitializeFromMemory(const_cast<BYTE*>(png.data()), static_cast<DWORD>(png.size()));
  if (SUCCEEDED(hr)) hr = factory->CreateDecoderFromStream(wstream, nullptr, WICDecodeMetadataCacheOnDemand, &decoder);
  if (SUCCEEDED(hr)) hr = decoder->GetFrame(0, &frame);
  UINT w = 0, h = 0;
  if (SUCCEEDED(hr)) hr = frame->GetSize(&w, &h);
  if (SUCCEEDED(hr) && (w == 0 || h == 0)) hr = E_FAIL;
  UINT tw = w, th = h;
  if (SUCCEEDED(hr) && cx > 0 && (w > cx || h > cx)) {
    const double s = static_cast<double>(cx) / static_cast<double>(w > h ? w : h);
    tw = static_cast<UINT>(w * s + 0.5); th = static_cast<UINT>(h * s + 0.5);
    if (tw < 1) tw = 1;
    if (th < 1) th = 1;
  }
  if (SUCCEEDED(hr)) hr = factory->CreateBitmapScaler(&scaler);
  if (SUCCEEDED(hr)) hr = scaler->Initialize(frame, tw, th, WICBitmapInterpolationModeFant);
  if (SUCCEEDED(hr)) hr = factory->CreateFormatConverter(&converter);
  if (SUCCEEDED(hr)) hr = converter->Initialize(scaler, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom);
  if (SUCCEEDED(hr)) {
    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = static_cast<LONG>(tw);
    bmi.bmiHeader.biHeight = -static_cast<LONG>(th);  // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP bmp = CreateDIBSection(nullptr, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bmp || !bits) hr = E_OUTOFMEMORY;
    if (SUCCEEDED(hr)) hr = converter->CopyPixels(nullptr, tw * 4, tw * 4 * th, static_cast<BYTE*>(bits));
    if (SUCCEEDED(hr)) *phbmp = bmp;
    else if (bmp) DeleteObject(bmp);
  }
  if (converter) converter->Release();
  if (scaler) scaler->Release();
  if (frame) frame->Release();
  if (decoder) decoder->Release();
  if (wstream) wstream->Release();
  if (factory) factory->Release();
  return hr;
}

