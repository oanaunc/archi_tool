// Oanarina Archi Tool — GPL-3.0-or-later
// Explorer thumbnail handler for .archi files (ArchiThumbnail.cpp); shared with the CI test thumbtest.cpp.
#pragma once
#include <windows.h>
#include <objidl.h>
#include <vector>

// {9D934CB7-4E6D-404F-A240-C5DBE6F0CAC0}: the handler's CLSID (also in packaging/installer.nsh).
static const CLSID CLSID_ArchiThumbnailProvider = {0x9d934cb7, 0x4e6d, 0x404f, {0xa2, 0x40, 0xc5, 0xdb, 0xe6, 0xf0, 0xca, 0xc0}};
#define kArchiThumbnailClsidString L"{9D934CB7-4E6D-404F-A240-C5DBE6F0CAC0}"
// IThumbnailProvider handler key of the .archi type.
#define kArchiThumbnailShellExKey L"Software\\Classes\\.archi\\ShellEx\\{e357fccd-a995-4576-b01f-234630154e96}"
// The picture is at the end of the file: only this many bytes are read (ArchiFile.preview(in:) reads the same).
static const unsigned long long kArchiPreviewTailBytes = 16ull << 20;

bool ArchiDecodeBase64(const char* s, size_t n, std::vector<unsigned char>& out);
bool ArchiFindPreviewPNG(const char* data, size_t n, std::vector<unsigned char>& png);
HRESULT ArchiReadPreviewPNG(IStream* stream, std::vector<unsigned char>& png);
HRESULT ArchiDecodeToBitmap(const std::vector<unsigned char>& png, UINT cx, HBITMAP* phbmp);
