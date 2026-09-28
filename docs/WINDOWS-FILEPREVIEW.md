# FILEPREVIEW on Windows — Explorer thumbnails of .archi drawings

Status: **built** (Oana's decision of 28 Sep 2026: build it, an unsigned Explorer add-on is accepted). The checklist line
Tools ▸ Files, Clipboard & Access ▸ File Preview & Spotlight is done in the parity audit. Verified by the ArchiCore tests
(`app/Tests/ArchiCoreTests/FilePreviewTests.swift`) and, on Windows, by the windows-app workflow (below); not yet looked
at in Explorer on a real PC.

## What the Mac does

`FILEPREVIEW` (`FINDERPREVIEW`, `SPOTLIGHTINFO`, `FILEMETADATA`; ArchiApp/AppCommandsRound11.swift, IO-006 / IO-007):

| Option | Mac | Windows (archi-engine, `Host/EngineRecovery.swift`) |
| --- | --- | --- |
| Update (default) | Spotlight attributes as extended attributes + Finder icon = a 512 px picture of the plan | re-renders the plan picture into the saved file: "Explorer thumbnail of <file> updated." |
| Icons On/Off | Finder preview icon on every save | "Explorer thumbnails on save": the picture on every save (preference `finderPreviewIcons`, on by default) |
| Versions On/Off | a macOS version on every save | a copy in `%APPDATA%\Oanarina Archi Tool\Versions` on every save (FILEVERSIONS; preference `fileVersionsOnSave`) |
| Show | the indexed Spotlight metadata | the same metadata keys of the saved file, plus "Explorer thumbnail: 512×512 picture in the file" or "none" |

The preferences are kept by the shell (`localStorage`, `sheets/recovery.ts`) and passed to each window's engine with
`recovery.setup {versionsOnSave, previewOnSave}`. Windows search metadata (a property handler) is not built: Explorer's
own search indexes the file name; the Mac-only Spotlight part has no Windows counterpart in this feature.

## The picture in the file

On every save of an `.archi` file archi-engine adds an optional **envelope** field after the document
(`IO/ArchiFile.swift`, `EngineSession.save`):

```
{ "app" : "Oanarina Archi Tool", "document" : { … }, "formatVersion" : N,
  "preview" : { "height" : 512, "png" : "<base64>", "width" : 512 } }
```

- The picture is `PlanImageExport.thumbnail` (`IO/RasterExport.swift`): the current level on white, square, fitted with a
  5 % margin, lineweights at side/400 px per mm — the Mac's `Artwork.thumbnail` framing, drawn by the portable rasteriser.
  Nothing drawn → no picture. Typical size 20–60 KB of PNG.
- With sorted keys `preview` is the last top-level key, so a reader finds it at the end of the file without parsing the
  document. `ArchiFile.preview(in:)` and the handler use the same rule: the last `"preview"` in the final 16 MB, followed
  by exactly one `{` and two `}` (so a `"preview"` inside the document never matches).
- It is outside `document`: every app version decodes such files unchanged (the fast path's Codable envelope and the
  migrating path both ignore it), so `formatVersion` is **not** bumped (AGENTS.md asks for a bump when the document
  schema changes; this is not a document change). The Mac app neither writes nor keeps the field: a drawing saved on the
  Mac has no Explorer thumbnail until it is saved again on Windows (or FILEPREVIEW Update runs there).

## The Explorer thumbnail handler (`windows/native/`)

- `ArchiThumbnail.cpp` — in-process COM server, `IInitializeWithStream` + `IThumbnailProvider`, CLSID
  `{9D934CB7-4E6D-404F-A240-C5DBE6F0CAC0}`. Explorer runs it in its isolated thumbnail host (`dllhost.exe`).
  `GetThumbnail(cx)`: read the last 16 MB of the stream, find the picture (`ArchiPreview.cpp`), base64-decode, WIC PNG
  decoder → scaler (fit `cx`) → 32-bit BGRA DIB section, `WTSAT_ARGB`. No picture → `E_FAIL` and Explorer shows the
  normal document icon. Also exports `DllRegisterServer` / `DllUnregisterServer` / `DllInstall` (per-user keys, for
  development machines: `regsvr32 /n /i:user ArchiThumbnail-x64.dll`).
- `build.cmd [dll-folder] [test-folder]` — MSVC (vswhere → vcvarsall), static CRT (`/MT`, no VC++ redistributable),
  `ArchiThumbnail-x64.dll` and `ArchiThumbnail-arm64.dll` into `windows/resources/shellext` (not in git), `thumbtest.exe`
  into `build/native`.
- The preview pane (`IPreviewHandler`) is not built: it needs a hosted window and message handling for little gain over
  the thumbnail (the pane shows "No preview available" as today).

## Installer (per user, no administrator)

`windows/packaging/electron-builder.yml` packages `resources/shellext/*.dll` as `resources\shellext`;
`windows/packaging/installer.nsh`:

```
HKCU\Software\Classes\CLSID\{9D934CB7-4E6D-404F-A240-C5DBE6F0CAC0}                (default) = "Oanarina Archi Tool thumbnail handler"
HKCU\Software\Classes\CLSID\{9D934CB7-…}\InprocServer32                            (default) = "$INSTDIR\resources\shellext\ArchiThumbnail-<x64|arm64>.dll"
                                                                                   ThreadingModel = "Apartment"
HKCU\Software\Classes\.archi\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}        (default) = "{9D934CB7-…}"
HKCU\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved            {9D934CB7-…} = "Oanarina Archi Tool thumbnail handler"
```

- The DLL matches **Explorer's** architecture, not the app's: the 32-bit installer reads `PROCESSOR_ARCHITEW6432`
  (ARM64 → the arm64 DLL, else x64). Both DLLs are in every installer. The keys are written in the 64-bit registry view.
- Then `SHChangeNotify(SHCNE_ASSOCCHANGED)`; the uninstaller deletes the keys and notifies again.
- Updates: a DLL still loaded by the thumbnail host cannot be replaced, so the uninstaller (`customUnInstall`, also run by
  an update before the new files are copied) renames the installed DLLs aside in the install folder; a renamed copy still
  in use is removed by the next update or uninstall.
- Unsigned until the app has a code-signing certificate (`signExts` signs `.exe` only). Some antivirus products flag
  unsigned DLLs registered under ShellEx.

## CI (`.github/workflows/windows-app.yml`)

1. **Build the Explorer thumbnail handler** (`build.cmd`, log `08-thumbnail-handler.log`); no arm64 DLL is a warning.
2. **Package**: fails when `resources/shellext/ArchiThumbnail-x64.dll` is not in the package.
3. **Install**: the registry keys exist and `InprocServer32` points into the install folder.
4. **Explorer thumbnail** (log `10b-thumbnail.log`): the installed `archi-engine.exe` saves Cedar House twice (with the
   picture, and with `previewOnSave:false`); `thumbtest.exe` checks the keys, loads the handler through COM
   (`CoCreateInstance` on the registered CLSID, as the thumbnail host does), makes a 256 px bitmap with the plan's dark
   pixels on white (saved as `screenshots/explorer-thumbnail.png`), gets no thumbnail for the drawing without a picture,
   and reports (not required) the shell's own `IShellItemImageFactory` result. Explorer itself cannot be driven on the
   runner.
5. **Uninstall**: the handler keys are gone.

## Checking on a Windows PC

Install, open Cedar House, save it under a new name, then look at the folder in Explorer with Large or Extra large icons:
the file shows the plan. If an old icon sticks, run `FILEPREVIEW Update`, or clear the thumbnail cache (Disk Cleanup ▸
Thumbnails).
