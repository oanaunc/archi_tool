# Windows port — open gaps after round 5

Parity audit of 29 Sep 2026 (round 5) over the 2904 lines of `docs/WINDOWS-PARITY.md`: **2892 done · 1 partial · 0 todo · 11 n/a**
(round 4: 2882 · 14 · 1 · 7; round 3: 2869 · 21 · 7 · 7; round 2: 2450 · 171 · 275 · 8). "Done" means the Windows entry exists
and runs the same engine code, or a tested shell port, as the Mac. Round 5 is committed (df18551, CI fix 911f239) and has
been built, installed and smoke-tested on Windows by CI.

**Verdict: complete.** todo = 0; the only partial line (Night preset) is cosmetic; Portable engine #28 (df18551, the latest
engine-code commit) green on Windows and Linux; Windows app #22 (911f239, latest commit) green including install, Explorer
thumbnail check, installed-app smoke test and uninstall. Remaining work is release logistics and cosmetic polish (below).

## How the audit was done

- **Script**: `python3 windows/tools/parity_audit.py` re-run by the auditor: same result as the committed file, 0 unmatched rows.
- **Round-5 rows checked against the code**:
  - FILEPREVIEW → done. Engine embeds a 512 px plan picture as envelope key `preview` (`IO/ArchiFile.swift`,
    `IO/RasterExport.swift`); unsigned COM thumbnail handler `windows/native/ArchiThumbnail.cpp`, registered per user by
    `windows/packaging/installer.nsh`; see `docs/WINDOWS-FILEPREVIEW.md`. CI (Windows app #22): handler key → CLSID
    {9D934CB7-4E6D-404F-A240-C5DBE6F0CAC0}, DLL in `resources\shellext` (Apartment), COM returns a 256×256 plan image
    (4887 dark pixels), a file without a picture gives E_FAIL (document icon), uninstall removes the registration.
    Not yet looked at in Explorer on a real PC (the runner's `IShellItemImageFactory` route returns 0x80040154, report-only).
  - F1, Help ▸ Oanarina Archi Tool Help (F1) → done: `ui/windows-conventions.ts` `openContextHelp` =
    `showHelpBrowser(app, contextRoute(app))`, used by the F1 key and `ui/menubar.ts`.
  - Help ▸ Tutorials, Tools ▸ Navigation & Sheets ▸ Tutorials → done: TUTORIALS (mode Open) = `showHelpBrowser(app, "tutorials")`
    (`partb/index.ts`).
  - Ctrl+0 [⌘0] Zoom Extents (2 lines) → n/a, Oana's decision 28 Sep: Ctrl+0 is Clean Screen on Windows (`ui/keys.ts`).
  - TUTORIALRECORD Record / Check → n/a, Oana's decision 28 Sep: Mac-only; Windows prints a note and opens the website tutorials.
  - Roll-ups (Menu Tools, Menu Help, Tools ▸ …) follow their entries.
- **CI** (read with `q.sh ci-fetch` / `winapp-fetch`):
  - Portable engine #28 on df18551: Windows success, Linux success, 1037 tests each. 911f239 touched only
    `windows/packaging/installer.nsh` and `docs/WINDOWS-FILEPREVIEW.md`, outside the workflow's `paths` filter, so #28 is
    the result for the current engine code.
  - Windows app #21 on df18551: failed (silent NSIS installer access violation 0xC0000005 at start-up). Fixed in 911f239 by
    moving the thumbnail-DLL rename-aside from `customInit` to `customUnInstall`; root cause not confirmed.
  - Windows app #22 on 911f239: every job success — package (132.5 MB, unsigned), install per-user to
    `%LOCALAPPDATA%\Programs\Oanarina Archi Tool`, thumbnail, smoke 22 passed / 0 failed / 0 skipped, uninstall, and all 18
    Chromium shell suites (including the new help-browser, F1 and tutorials checks).
- **Mac**: the integrator's `q.sh build` succeeded, `q.sh test` 1039 tests / 0 failures (not re-run by the auditor; docs-only change).

## Remaining gaps

### A. Checklist lines still `todo` (0)

None.

### B. Partial lines (1, cosmetic)

1. **Lighting preset Night**: 1.8 mean levels from the Mac render; bollard and spot-light shadows now match, but the bollard
   light pools are about 20 levels dimmer than the Mac's at their outer edges.

### C. Differences outside the checklist (cosmetic or minor, not re-verified this round unless noted)

2. **Render details**: front-view limestone −4, glass −4 in daylight; the Render window's non-preset environments have no Mac
   reference render.
3. **User guide** (`docs/USER-GUIDE.md`, shown by the help window's User guide page) still says "Requirements: macOS 14 or
   later" (checked this round).
4. **SPELL from scripts / agents** that call the engine directly (main process) bypasses the Windows spell checker.
5. **Shell-polish leftovers**: larger "ByLayer" text in the Mac ribbon Properties pickers; Mac ruler, house and float-button
   icons; Segoe UI renders slightly smaller than SF and may fit a few panel-tab labels differently.
6. **From round 3**: merged windows share one frame, file tabs have no hover thumbnail; the crash-reports toggle is only
   reachable through CRASHREPORTS; engine PNG uses the stroke font and grey images; ZOOMXP assumes 96 dpi; sheet TIFFs are
   uncompressed.
7. **Explorer thumbnails**: only checked through COM on the CI runner; look at a folder of drawings on a real Windows PC.
   Windows search metadata (property handler) is not built (Spotlight part has no Windows counterpart).

Resolved since round 4: offline help routing (F1 / Help / Tutorials), FILEPREVIEW, Ctrl+0 and Tutorial Record/Check decisions,
the engine test fixture (`windows/test/fixtures/engine/hello.json` now lists 1042 commands), CI reporting again, round 4 and 5
committed, installed-app smoke test with this round's code.

## Release items (not in the checklist)

- **Installer size**: 132.5 MB, over GitHub's 100 MiB file limit; publish by FTP to `public_html/downloads/archi-tool/`
  (`windows/README.md`), not through the website repo.
- **Code signing**: none. **Oana decides** (options in `windows/README.md`). Unsigned, users see SmartScreen
  "More info → Run anyway"; the Explorer thumbnail add-on is unsigned too (accepted 28 Sep).
- **Installer crash of Windows app #21**: fixed by 911f239 but the cause was not confirmed; watch the next installer runs.
- **Swift 6 warnings** in `BCFServer.swift` (captured variables) — not rechecked.

## Ready to publish?

**Yes, as a parity replica.** todo = 0; the one partial line is cosmetic; both workflows are green on the latest code
(engine #28 on df18551, Windows app #22 on 911f239); the installed app passed the smoke test on Windows. Before publishing:
decide on code signing and upload the installer to the web host.

## Appendix: every open checklist line

### Rendering and 3D

- **partial** Lighting preset Night — sky=night, sunAltitude=38, sunAzimuth=135, sunColor=[0.62, 0.72, 1.0], sunIntensity=70, shadowRadius=6, shadowAlpha=0.85, envIntensity=1.0 … · _cosmetic: 1.8 levels from the Mac; bollard shadows and spot-light shadows now match, the bollard pools stay about 20 levels dimmer at their outer edges_
