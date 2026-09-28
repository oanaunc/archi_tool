# Windows port — open gaps after round 4

Parity audit of 28 Sep 2026 (round 4) over the 2904 lines of `docs/WINDOWS-PARITY.md`: **2882 done · 14 partial · 1 todo · 7 n/a**
(round 3: 2869 · 21 · 7 · 7; round 2: 2450 · 171 · 275 · 8). "Done" means the Windows entry exists and runs the same engine
code, or a tested shell port, as the Mac. It does **not** mean "verified on real Windows": none of the round-4 work has run in
Electron on Windows, and none of it is committed.

**Verdict: not ready to publish as an exact replica.** FILEPREVIEW (the last `todo`) is now built, not yet verified by CI; 4 partial
lines are not cosmetic (F1 / Help / Tutorials open the website instead of the offline help browser, a small fix); round 4 is
uncommitted, so neither CI workflow has built it and the installed app has not been smoke-tested with it; and no CI run has
reported since 9885fb9 (Windows engine red there). See "Release blockers" and "Ready to publish?".

## How the audit was done

- **Script**: `python3 windows/tools/parity_audit.py` re-derives every status; rules in `windows/tools/parity_audit_rules.py`.
  Round 4 adds a section at the end of the rules file: the render lines the evidence now supports, and the help lines that
  regressed relative to the Mac once Windows had its own help browser.
- **Rows that changed, and the evidence**:
  - APPSELFTEST (3 lines), HELPWINDOW, VRVIEW, SPACEMOUSE → done. Registered in
    `app/Sources/ArchiCore/Host/EngineSystemCommands.swift` (in the regenerated `build/engine-fixtures/hello.json`), shell side in
    `windows/src/renderer/system/`. `test/system.mjs` 30/30 in Chromium, including the Mac report "Command coverage: 1042 in
    ribbon/menus … 20 check(s) passed, 0 failed", DOCS / MANUAL / HELPBROWSER routes, and VRVIEW Save.
    SpaceMouse and the VR window are code-and-maths verified only (no device, no Windows run).
  - Lighting presets Daylight, Golden hour, Overcast → done. `windows/test-results/render-match-r4/before-after.json`: all 8
    Mac renders are 1.8-2.7 mean levels off (Overcast 4.7 → 2.3, limestone +12 → +3, cedar now +0 to +4). The auditor viewed
    the corner-overcast comparison. The Golden hour interactive look (round-3 gap 10) is fixed in the engine: `render.preset`
    now switches the viewport to Realistic like the Mac RENDERPRESET (render-r4.mjs checks it, and `smoke-electron.mjs` now
    asserts it on Windows).
  - Night stays **partial (cosmetic)**: 1.8 levels, but the Mac's bollards cast shadows inside their own light pools.
  - Photographic render (Render window environments) → done. `view3d/render-scene.ts` holds the Mac
    `RenderController.Environment` gradient colours verbatim (spot-checked: Sunset zenith/horizon/ground/glow match
    `RenderController.swift:105`). There is no Mac reference image of a non-preset render, so brightness is unverified; it is
    listed under C.
  - 360° panorama → done (Render window scene, 90° faces, w/4, 4× MSAA; render-r4.mjs: 2:1, zenith is the Clear Sky map).
  - Help ▸ Oanarina Archi Tool Help (F1), Help ▸ Tutorials, Tools ▸ Navigation & Sheets ▸ Tutorials, the F1 shortcut →
    **partial** (were done). The Mac opens the offline `HelpBrowser` for all of them (`ArchiApp.swift` 107, 488, 489;
    TUTORIALS in `AppCommandsNav.swift`); Windows still opens the website guide although `showHelpBrowser` now exists.
  - Roll-ups (Tab Manage, Manage ▸ More, Tools ▸ Help, Menu Help …) follow their entries.
- **Suites re-run by the auditor** on a copy of the merged Mac tree (web build + fixture engine, Chromium): system 30/30,
  shell-polish all pass, render-r4 26/26, menus-keys 96/96, audit-spot all pass, windows-conventions 9/9, workspace 65/65,
  canvas 61/61 (round-3 blocker fixed), view3d/ui pass, doctools 56/56, sheets 27/27, standards 29/29, render-extras-ui 15/15,
  ui-snapshots 30/30, dialogs 49/49, partb-tools 27/27, output 35/35, icons pass, view3d/tools 37 PASS.
  `tsc` for the renderer and view3d configs is clean; the main/preload config could not be checked here (no Electron types
  in the sandbox), so the new Electron main-process code (floating OS windows, help / VR windows, `--selftest`) has had no
  real type check.
- **Auditor finding, fixed**: the web smoke test (`packaging/smoke-electron.mjs --web`) failed "3D view shows Realistic with
  the Golden hour look" (got Daylight, explicit) on the merged tree, twice. Cause: `view3d/engine-bridge.ts` `load()` read
  `render.settings` in parallel with `model.meshes` and applied it after the mesh load, so a preset set while the model was
  loading (the smoke test sets it 1 s after entering 3D; on Windows the real mesh load takes seconds) was overwritten by the
  stale settings. This is the likely cause of the round-3 screenshot-03 symptom as well. The auditor moved the
  `render.settings` read after the mesh load (read together with `view3d.info`); smoke-web then passes 14/14 (2 skipped
  as web-only), render-r4 26/26, renderer and view3d `tsc` clean. Patch: `build/xfer-audit/engine-bridge-race.patch`.
- **Swift**: the engineers report 1036 tests / 0 failures on the Mac for the merged tree. The auditor's own `q.sh test`
  (queued 14:30 UTC) had produced no output an hour later (the Mac bridge was offline part of that time), so the Swift total
  for the final tree, including the auditor's shell-only patch, is the engineers' figure, not re-verified.
- **Not re-verified by the auditor**: Windows-only paths (Electron main process, WebHID, the Windows spell checker for SPELL,
  floating panels as OS windows) — these need the windows-app workflow.

## Remaining gaps, by importance

### A. Checklist line still `todo` (1)

1. **FILEPREVIEW** (Tools ▸ Files, Clipboard & Access ▸ File Preview & Spotlight) — **built** after Oana's decision of
   28 Sep (build it, unsigned accepted); the audit now marks the line done. archi-engine embeds a 512 px plan picture in
   every saved `.archi` (optional envelope key `preview`), the unsigned Explorer thumbnail handler `windows/native/` is
   built by MSVC in windows-app.yml and registered per user by the installer; see `docs/WINDOWS-FILEPREVIEW.md`. Open:
   the first windows-app run (thumbnail check after install), and a look at a folder of drawings on a real Windows PC.

### B. Partial lines (14; 4 not cosmetic)

2. **Offline help not used by F1 / Help / Tutorials** (4 lines, not cosmetic). Point `openContextHelp` (F1 and
   Help ▸ … Help (F1)) at `showHelpBrowser(app, contextRoute(app))`, and Help ▸ Tutorials / TUTORIALS at
   `showHelpBrowser(app, "tutorials")`; update the three tests that assert the website URL (`windows-conventions.mjs`,
   `menus-keys.mjs`, `audit-spot.mjs`).
3. **Night preset** (1 line, cosmetic): the Mac's bollards cast shadows inside their own light pools.
4. **Ctrl+0 for Zoom Extents** (2 lines, convention): Ctrl+0 is Clean Screen on Windows. **Oana decides**: accept, or give
   Zoom Extents another key.
5. **Tutorial Videos ▸ Record and Check** (2 lines, by design): recording is Mac-only. **Oana decides**: accept or mark `n/a`.
6. Roll-ups of the above (Menu Tools, Tools ▸ Navigation & Sheets, Tools ▸ Files, Clipboard & Access, Tools ▸ Tutorial
   Videos, Menu Help).

### C. Differences outside the checklist

7. **Render details (cosmetic)**: front-view limestone −4 (regressed from −1), glass −4 in daylight; the Render window's
   non-preset environments have no Mac reference render (the `render-cedar` bridge action only renders presets).
8. **User guide** still says "Requirements: macOS 14 or later" (shown by the Windows help window's User guide page).
9. **SPELL from scripts / agents** that call the engine directly (main process) bypasses the Windows spell checker.
10. **Shell-polish leftovers (cosmetic)**: the Mac's larger "ByLayer" text in the ribbon Properties pickers; the Mac ruler,
    house and float-button icons; label fitting in the panel tab grid is measured with Segoe UI on Windows and may shrink a
    few labels differently from the Chromium run; Segoe UI renders slightly smaller than SF at the same size.
11. **Still open from round 3**: merged windows share one frame, file tabs have no hover thumbnail; the crash-reports toggle
    is only reachable through CRASHREPORTS; engine PNG uses the stroke font and grey images; ZOOMXP assumes 96 dpi; sheet
    TIFFs are uncompressed. (Resolved since round 3: typed-ahead input is queued (`app.ts` `inputQueue`), the README install
    folder, the three missing icons, panel tab strip, Nordic House thumbnail, template strip, Alt menu keys, floating panels
    as OS windows, plain SPELL, the canvas.mjs failure, 3D zoom readout and preset look.)
12. **Test fixture**: `windows/test/fixtures/engine/hello.json` lists 1038 commands; the engine now has 1042 (the four
    system commands come from `system/fake-system.ts` in web tests). Refresh it from `build/engine-fixtures/hello.json`.

## Release blockers (not in the checklist)

- **CI has not reported since 9885fb9.** There: Linux engine green, Windows app green, **Windows engine red**
  (`IOAutomationTests.testRulesProcessNewAndChangedFilesOnce`, fixed by a4d2233 but unconfirmed). No run appeared for
  a4d2233 three hours after the push, so runs are probably queued or blocked by used-up Actions minutes. **Oana**: check
  github.com/oanaunc/archi_tool/actions and Settings ▸ Billing, then re-run both workflows on the latest `main`.
- **Nothing from round 4 is committed** (EngineSystemCommands, EnginePathTraceAnimation, render-scene, system/, floating OS
  windows, release-files …). It has to go through both workflows: the new Swift has only been compiled on the Mac, and the
  Linux/Windows Swift 6.1 type checker has rejected Mac-green code before.
- **Installed-app smoke test** with round-4 code (new screenshot 03 Golden hour, 07 floating panel, thumbnails) has not run.
  `--selftest` exists but is not yet called by the CI smoke test; wiring it in is cheap and recommended.
- **Installer size**: 131 MB, over GitHub's 100 MiB file limit; publish by FTP to `public_html/downloads/archi-tool/`
  (documented in `windows/README.md`), not through the website repo.
- **Code signing**: none. **Oana decides** (options and costs in `windows/README.md`; recommended: Azure Trusted Signing if
  eligible, else a Certum OV certificate). Unsigned, users see SmartScreen "More info → Run anyway".
- **Swift 6 warnings** in `BCFServer.swift` (captured variables) — not rechecked this round.

## Ready to publish?

**No.** The bar is: todo = 0, only cosmetic partial lines, both CI workflows green on the release commit, and the installed
app smoke-tested on Windows with this round's code. Today:

- todo = 0 (FILEPREVIEW built; its CI check has not run yet);
- 4 partial lines are not cosmetic (offline help routing; a small shell fix);
- round 4 is uncommitted; no CI result since 9885fb9, where the Windows engine workflow was red;
- the installed app has not been smoke-tested with round-4 code.

What Oana must decide (FILEPREVIEW decided 28 Sep: built): Ctrl+0 and Tutorial
Record/Check (accept as Windows conventions / n/a); code signing; and unblock GitHub Actions (minutes/queue).

## Appendix: every open checklist line

Grouped by checklist section, `todo` first, then `partial`; the note is the audit's reason.

### Menu bar

- **partial** Menu Tools — 73 items
- **partial** Tools ▸ Navigation & Sheets
- **partial** Tools ▸ Navigation & Sheets ▸ Tutorials — `TUTORIALS` · _opens the website guide; the Mac opens the offline help browser (system/help-browser.ts showHelpBrowser exists)_
- **partial** Tools ▸ Files, Clipboard & Access
- **partial** Tools ▸ Tutorial Videos
- **partial** Tools ▸ Tutorial Videos ▸ Record Tutorial Videos — `TUTORIALRECORD Record` · _recording is Mac-only; Windows opens the website tutorials_
- **partial** Tools ▸ Tutorial Videos ▸ Check Tutorial Scripts — `TUTORIALRECORD Check` · _only checks that the commands exist_
- **partial** Menu Help — 13 items
- **partial** Help ▸ Oanarina Archi Tool Help (F1) — `HELP` · _opens the website guide; the Mac opens the offline help browser (system/help-browser.ts showHelpBrowser exists)_
- **partial** Help ▸ Tutorials — `HELP` · _opens the website guide; the Mac opens the offline help browser (system/help-browser.ts showHelpBrowser exists)_

### Keyboard shortcuts (Windows keys; Mac in brackets)

- **partial** Ctrl+0 [⌘0] View ▸ Zoom Extents — See ⌃0: Ctrl+0 is Clean Screen on Windows; same Windows keys as: clean screen → (none) · _Windows key conflict (documented): Ctrl+0 is Clean Screen, Zoom Extents has no Ctrl key (double middle-click, ribbon, Z E)_
- **partial** F1 [F1] Help for the running command — Windows help key: matches the Mac (context help) → F1 · _opens the website guide; the Mac opens the offline help browser (system/help-browser.ts showHelpBrowser exists)_
- **partial** Ctrl+0 [⌘0] Zoom extents — See ⌃0: Ctrl+0 is Clean Screen on Windows; same Windows keys as: clean screen → (none) · _Windows key conflict (documented): Ctrl+0 is Clean Screen, Zoom Extents has no Ctrl key (double middle-click, ribbon, Z E)_

### Rendering and 3D

- **partial** Lighting preset Night — sky=night, sunAltitude=38, sunAzimuth=135, sunColor=[0.62, 0.72, 1.0], sunIntensity=70, shadowRadius=6, shadowAlpha=0.85, envIntensity=1.0 … · _cosmetic: 1.8 levels from the Mac; the Mac's bollards cast shadows inside their own light pools_
