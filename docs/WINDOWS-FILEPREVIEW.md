# FILEPREVIEW on Windows — Explorer thumbnails, preview and search metadata (design, decision needed)

Status: **not implemented; Oana decides** (build it as below, or mark the checklist line
`n/a (Finder/Spotlight extension)`). Everything else of the last round (APPSELFTEST, HELPWINDOW, VRVIEW, SPACEMOUSE,
SPELL) is done; `FILEPREVIEW` is the only Mac command that archi-engine does not register, and APPSELFTEST on Windows
names it as "Not on Windows yet".

## What the Mac does

`FILEPREVIEW` (`FINDERPREVIEW`, `SPOTLIGHTINFO`, `FILEMETADATA`; ArchiApp/AppCommandsRound11.swift, IO-006 / IO-007):

| Option | Mac |
| --- | --- |
| Update (default) | writes the Spotlight attributes (title, keywords, authors, levels, rooms, entity and element counts) as extended attributes and sets the Finder icon to a picture of the plan |
| Icons On/Off | Finder preview icon on every save |
| Versions On/Off | keep a macOS version on every save |
| Show | prints the indexed metadata of the saved file |

## The Windows equivalent

Explorer has no "custom icon per file". The same result needs **shell extension handlers**: in-process COM DLLs that
Explorer (through its isolated thumbnail host, `dllhost.exe`) loads for the `.archi` type.

| Mac | Windows | Interface |
| --- | --- | --- |
| Finder preview icon | Explorer thumbnail (large icons, tiles, Alt+P) | `IThumbnailProvider` + `IInitializeWithStream` |
| Quick Look | Preview pane (optional) | `IPreviewHandler` |
| Spotlight attributes | Details pane, search, Properties ▸ Details | property handler `IPropertyStore` (+ a `.propdesc` schema for the Archi-specific keys) |

### Where the picture comes from

The handler must be small, fast and must never run the engine (Explorer asks for hundreds of thumbnails). Options:

1. **Embed a PNG preview in the `.archi` file (recommended).** On save the app writes an optional top-level field
   `"preview": {"png": "<base64>", "width": 256, "height": 256}` (a 256 px plan picture, 15–40 KB; the engine already
   renders PNG: `file.export {format:"png"}` / `EngineSheetImage`). The handler reads the stream, finds the field and
   decodes the PNG with WIC. It survives copying, zipping, e-mail, OneDrive and USB sticks. Old app versions ignore the
   unknown key (Codable skips it), but AGENTS.md requires a `formatVersion` bump and a migration note, and the Mac should
   write the same field (it could then also feed Quick Look). **This is a document-format decision for both platforms.**
2. NTFS alternate data stream `drawing.archi:Oanarina.Preview` (the closest thing to the Mac's extended attributes). No
   format change, but it is lost on FAT/exFAT drives, in zip files, e-mail and most cloud sync, and a stream-based
   handler cannot read it: the handler would need `IInitializeWithFile`, which Windows only allows when process
   isolation is disabled for the handler (`DisableProcessIsolation`), i.e. running inside Explorer itself. Not robust.
3. The handler draws the plan itself from the JSON (walls, lines, rooms). A second renderer in C++ that must follow every
   geometry type of ArchiCore. Not maintainable.

### The native handler (option 1)

- `windows/shellext/ArchiShellExt.cpp` (~300 lines C++17, no dependencies beyond Windows SDK):
  `DllGetClassObject`, `DllCanUnloadNow`, a class factory and one class implementing `IInitializeWithStream` and
  `IThumbnailProvider::GetThumbnail(cx, &hbmp, &alpha)`: read at most 64 MB from the stream, locate `"preview"` at the
  top level of the JSON (a streaming scan, no JSON library), base64-decode, `IWICImagingFactory` →
  `IWICBitmapScaler` to `cx` → 32-bit DIB section, `WTSAT_ARGB`. Files without a preview return `E_FAIL`, so Explorer
  shows the normal document icon (the app icon from the file association) — the same as today.
- Build in `.github/workflows/windows-app.yml` with MSVC (`cl /LD /O2 /EHsc … windowscodecs.lib ole32.lib`) for x64 and
  arm64, output `resources/shellext/ArchiShellExt-<arch>.dll` (~60 KB) packaged by electron-builder (`extraResources`).
- A CI test: a tiny test executable (same workflow) that `CoCreateInstance`s the handler through the registered CLSID,
  feeds it `Cedar House.archi` saved with a preview, and checks a 256×256 bitmap with non-background pixels; plus a
  file without a preview → `E_FAIL`. (Explorer itself cannot be driven on the CI runner.)

### Registration by the NSIS installer (per user, no admin)

`packaging/installer.nsh`, in `customInstall` / `customUnInstall`:

```
HKCU\Software\Classes\CLSID\{<new GUID>}                          (default) = "Oanarina Archi Tool thumbnail handler"
HKCU\Software\Classes\CLSID\{<new GUID>}\InprocServer32            (default) = "$INSTDIR\resources\shellext\ArchiShellExt-x64.dll"
                                                                   ThreadingModel = "Apartment"
HKCU\Software\Classes\.archi\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}   (default) = "{<new GUID>}"
```

then `SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, 0, 0)` (System::Call) so Explorer picks it up without a restart.
The uninstaller deletes the three keys and notifies again. The handler must be the DLL matching the OS architecture
(x64 Explorer on x64, arm64 on arm64), which the per-arch installers already decide.

### The command on Windows

Same names, prompts and messages as the Mac, with Windows words:

| Option | Windows |
| --- | --- |
| Update | re-renders the preview into the saved file and tells Explorer (`SHChangeNotify(SHCNE_UPDATEITEM)`) — "Explorer preview updated" |
| Icons On/Off | write the preview on every save (preference) |
| Versions On/Off | keep a copy in the app's Versions store on every save (FILEVERSIONS already browses `%APPDATA%\Oanarina Archi Tool\Versions`) |
| Show | prints the file's metadata (title, keywords, authors, levels, rooms, counts) |

Search metadata (property handler, phase 2): `System.Title`, `System.Keywords`, `System.Author` need no schema; the
Archi-specific counts need a registered `.propdesc` schema (`PSRegisterPropertySchema`, admin rights on older Windows) —
propose to ship only the three system properties.

## Risks and cost

- Native code loaded by Explorer's thumbnail host: a bug crashes `dllhost.exe` (isolated; Explorer survives) and shows
  no thumbnail. The DLL is unsigned until the app has a code-signing certificate; unsigned shell extensions load, but
  some antivirus products flag unsigned DLLs registered under `ShellEx`.
- Cannot be verified interactively from the development setup; only the CI test above and a manual check on a Windows
  PC (thumbnail view of a folder of `.archi` files).
- Effort: handler + CI build + test ≈ 1 day; installer registration ≈ ½ day; format field on both platforms and the
  command ≈ 1 day.

## Decision needed from Oana

1. Accept the optional `preview` field in `.archi` (format version bump on Mac and Windows)? Without it there is no
   robust thumbnail source.
2. Ship an unsigned native shell extension in the Windows installer?

If both are yes, build it as above. If not, mark `Tools ▸ Files, Clipboard & Access ▸ File Preview & Spotlight` as
`n/a (Finder/Spotlight extension)` in the parity checklist.
