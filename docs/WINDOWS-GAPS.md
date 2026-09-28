# Windows port — open gaps after round 3

Parity audit of 28 Sep 2026 over the 2904 lines of `docs/WINDOWS-PARITY.md`: **2869 done · 21 partial · 7 todo · 7 n/a**
(round 2: 2450 · 171 · 275 · 8). "Done" means the Windows entry exists and runs the same engine code, or a tested shell port,
as the Mac. It does **not** yet mean "verified on real Windows": none of the round-3 work has run in Electron on Windows, and
none of it is committed.

**Verdict: not ready to publish as an exact replica.** 7 checklist lines are still `todo`, 2 of the 21 partial lines are not
cosmetic (Overcast render, 360° panorama), all round-3 work is uncommitted, so it has not been through either CI workflow or
the installed-app smoke test on Windows, and `canvas.mjs` fails on the combined tree. See "Release blockers" below.

## How the audit was done

- **Script**: `python3 windows/tools/parity_audit.py` re-derives every status; the rules are in
  `windows/tools/parity_audit_rules.py`. The round-3 section of the rules removes the stale round-2 overrides. Each row that
  changed status was checked against the code and a Playwright check.
- **Resolver changes**: the audit now resolves entries the way the round-3 shell does.
  - Every menu comes from `docs/windows-parity.json` (`ui/menubar.ts`).
  - `{r}` is resolved to COMPONENT (`gen-ui-data.mjs`).
  - The commands the shell implements itself count (`registerShellCommand`: ABOUT, COMMANDSEARCH, CLEANSCREENON/OFF,
    HISTORYPANEL, STARTSCREEN, SAMPLEHOUSE, WHATSNEW, EXPORTCOMMANDS, FULLSCREEN, BLOCKLIBRARY, FAMILY …).
  - The shell's Mac `ui` targets are read from `ui/shell-commands.ts`.
  - `file.export` accepts `png`, `csv:<kind>` and `xlsx:<kind>` (`IO/BatchRunner.swift`).
- **Engine command list**: every `CommandDef` in the new Host files is in the regenerated `build/engine-fixtures/hello.json`
  (1038 commands).
- **Cross-check in Chromium** (web build with the fixture engine; the Mac's fresh `hello.json` was dropped into the build):
  - The menu bar greys out exactly the 5 unregistered commands the audit lists: APPSELFTEST (twice), HELPWINDOW,
    SPACEMOUSE, FILEPREVIEW and VRVIEW. It also greys out Clear Menu and Delete, which depend on state.
  - No top-level ribbon button is disabled on any tab.
- **New spot check**: `windows/test/audit-spot.mjs` was rewritten for round 3 and passes 30/30. It checks by effect, not by
  label:
  - the menu bar order, Component ▸ Chair running `COMPONENT Chair`;
  - Ctrl+Alt+P, Ctrl+Alt+1-4, Ctrl+Alt+J, F2, Ctrl+Alt+Shift+P (PREVIEW, not PLOT), Ctrl+Shift+A (465 selected → 0),
    Ctrl+Shift+/ (Command Reference window), and F1 during LINE (`archi-tool-guide.html#draw`);
  - selecting a wall shows the MODIFY WALL strip;
  - SELECTIONINFO, SPELLDIALOG, FILEVERSIONS, GRAPHICSTYLES, ASSISTANT, OUTLINERPANEL and TEXTSTYLEDIALOG open their
    windows;
  - NAVIGATOR, NOTIFICATIONS and ADCENTER fill their panels, and FLOATPANEL floats a panel.
- **Engineers' suites re-run by the auditor** on a copy of the Mac tree: menus-keys 96/96, doctools 56/56, sheets 27/27,
  workspace 63/63, standards 29/29, render-extras-ui 15/15, ui-snapshots 30/30, dialogs 49/49, partb-tools 27/27, output 35/35,
  windows-conventions 9/9. **canvas.mjs fails** (see release blockers).
- Not re-verified by the auditor: the render numbers (taken from `windows/test-results/render-match/before-after.json`), the
  A-102 PDF comparison (`build/a102/`), the Swift test totals, and the Windows-only PowerShell/.NET paths (share sheet, print
  ticket, multi-format clipboard).

## Per section

| Section | done | partial | todo | n/a |
| --- | ---: | ---: | ---: | ---: |
| Ribbon | 903 | 3 | 1 | 0 |
| Contextual ribbon tabs (selection) | 11 | 0 | 0 | 0 |
| Menu bar | 1259 | 10 | 6 | 3 |
| Tool palettes | 57 | 0 | 0 | 0 |
| Panels | 108 | 0 | 0 | 0 |
| Dialogs and windows | 366 | 0 | 0 | 0 |
| Status bar | 21 | 0 | 0 | 0 |
| Keyboard shortcuts (Windows keys; Mac in brackets) | 77 | 2 | 0 | 4 |
| Rendering and 3D | 17 | 6 | 0 | 0 |
| Theme | 50 | 0 | 0 | 0 |

The partial ribbon and menu rows are almost all roll-ups: a menu, group or tab is `partial` because one of its entries is
`todo`. Only 2 partial menu lines are entries in their own right, the two Tutorial Videos lines.

## Remaining gaps, by importance

Round 2's 30 gaps are closed in code, except for the parts listed here. The list below is everything that is still open.

### A. Checklist lines still `todo` (7 lines, 5 commands)

1. **APPSELFTEST** (Help ▸ Check Command Coverage, Tools ▸ Help ▸ Self Test, Manage ▸ More ▸ Tools ▸ Help ▸ Self Test; 3 lines).
   Port the command-coverage self test: the parts of `AppSelfTests*.swift` that do not need AppKit, run against the engine.
2. **HELPWINDOW** (Tools ▸ Navigation & Sheets ▸ Help Browser). The offline help browser. On Windows, bundle the guide HTML
   and open it in an app window.
3. **VRVIEW** (Tools ▸ Styles, Patterns & Occlusion ▸ VR Headset View). The Mac exports for a headset. On Windows, WebXR in
   Electron or the same export.
4. **SPACEMOUSE** (Tools ▸ Render, Materials & Environment ▸ SpaceMouse). 3Dconnexion input. On Windows use WebHID in
   Electron, or document it as `n/a` if Oana agrees.
5. **FILEPREVIEW** (Tools ▸ Files, Clipboard & Access ▸ File Preview & Spotlight). The engineer proposes `n/a`. The auditor
   keeps it `todo`, because Windows has an equivalent: an Explorer thumbnail and preview handler, a native COM DLL
   registered by the installer. Oana decides: build it, or mark the line `n/a (Finder/Spotlight extension)`.

### B. Partial lines

6. **Rendering** (6 lines).
   - Overcast is 4.6 levels from the Mac, with limestone +12. This one is not cosmetic.
   - Daylight, Golden hour and Night are 1.7-3.1 levels off, with cedar 5-7 too bright in flat light. These count as
     cosmetic.
   - The 360° panorama and ANIMATE Frame use the photographic look instead of the Mac panorama renderer and path tracer.
     This is not cosmetic.
   - The Render window's Clear Sky, Sunset, Studio, Night and Physical Sky environments approximate the Mac gradient
     environment maps.
   - The compare overlay on the canvas (round-2 gap 21) is still not drawn.
7. **Ctrl+0 for Zoom Extents** (2 lines). This is a documented Windows key conflict: Ctrl+0 is Clean Screen. Accept it as
   the Windows convention, or bind Zoom Extents to another key.
8. **Tutorial Videos ▸ Record and Check** (2 lines). Partial by design, because recording is Mac-only. Accept it or mark it
   `n/a`.

### C. Differences found outside the checklist

9. **Typed-ahead input is lost** (`app.ts` `submitLine`). Input typed before the engine answers is run as a new command:
   "PLOT <file>" in one line reports an unknown command. Queue submissions. The smoke test only works around this.
10. **3D view on Windows** (installed-app smoke test at 162de27; recheck after render-match's changes):
    - the interactive 3D view did not show the Golden hour look after the preset was set;
    - setting the preset marked the drawing as changed (check what the Mac does);
    - the status bar shows "Zoom 1:135290" in 3D.
11. **Panel tab strip.** At 1440×900 on Windows, the right-hand panel tabs wrap into three rows of cut-off labels ("Pro…",
    "Lay…"). The Mac shows a single tab bar.
12. **Start screen.** The Nordic House sample has no thumbnail (`assets/samples/Nordic House.thumb.json` is not packaged).
    The template tiles show a dark strip next to their icons.
13. **Alt+letter menu access.** Alt+A opens only the first of Analyze, Annotate and Architecture. Give each menu its own
    access key (&-mnemonics).
14. **Floating panels and window tabs are emulated.**
    - Floating panels are windows inside the app window, not separate OS windows.
    - Merged windows share one frame; file tabs have no hover thumbnail.
    - The crash-reports toggle is only reachable through CRASHREPORTS, not Settings ▸ General.
15. **Output details.**
    - The engine PNG draws text with the stroke font and images in grey.
    - Plain SPELL on the command line has no spell checker; SPELLDIALOG uses Windows'.
    - ZOOMXP assumes 96 dpi.
    - Sheet TIFFs are uncompressed.
    - The Versions store is `%APPDATA%\Oanarina Archi Tool\Versions`.
16. **Icons.** `gen-ui-data.mjs` has no Lucide mapping for `paperplane.fill` (the Assistant send button),
    `rectangle.righthalf.inset.filled` and `xmark.circle.fill`, so a fallback icon is shown.

## Release blockers (not in the checklist)

- **Nothing from round 3 is committed**, so neither CI workflow has built it. This covers about 20 new ArchiCore Host files,
  two new test files per engineer, and the shell folders `doctools/`, `sheets/`, `standards/`, `workspace/` and `ui/*`.
  - The last green runs are from before round 3's changes: portable engine at 8ff844a, Windows app at 162de27.
  - The new Swift has only been compiled and tested on the Mac: 1028 tests pass, as the last engineer reported.
  - The Linux/Windows Swift 6.1 type checker already failed on similar code in round 3 (f28e53d, 3e1b73b).
- **canvas.mjs fails on the combined tree.**
  - Cause: the contextual strip (`sheets/context-ribbon.ts`) appears when something is selected and pushes the canvas down
    22 px. The Mac `MainWindow` stacks it the same way, so the behaviour is right.
  - The test reads the canvas position once (`const box = …boundingBox()` at line 50), so every grip check after the first
    selection misses.
  - Fix the test: re-read the box after selecting, or re-read it inside `at()`. With that change the grip checks pass, but
    a later step (line 105) still needs attention.
  - canvas.mjs is in the CI shell suites, so the Windows app workflow will fail until this is fixed.
- **The tracked fixture `windows/test/fixtures/engine/hello.json` is stale.**
  - Copy `build/engine-fixtures/hello.json` (1038 commands) and the new `doc-*`, `ws-*`, `render-*` and sheet fixtures into
    `windows/test/fixtures/engine/`.
  - With the old file, the web tests grey out LIGHT, FOG, WATER, SCATTER, MATMAPS and 12 other menu entries that the real
    engine has.
- **CI suites.**
  - `menus-keys`, `sheets`, `standards`, `render-extras-ui` and `audit-spot` must be added to `windows-app.yml`.
  - `doctools` and `workspace` are already listed.
- **The round-3 shell has not run in real Electron or on Windows.** The full Windows app workflow must pass, including the
  installed-app smoke test, the 3D and render checks, and the Windows-only paths: share sheet, print ticket tray/media,
  multi-format clipboard, spell checker, encrypted API key and speech.
- **Documentation.** `windows/README.md` and the `electron-builder.yml` comment still give the install folder as
  `Programs\oanarina-archi-tool`; it is `%LOCALAPPDATA%\Programs\Oanarina Archi Tool`.
- **Swift 6 warnings.** `BCFServer.swift` has two captured-variable warnings that become errors in Swift 6 language mode.
- **No code-signing certificate.**

## Ready to publish?

**No.** The bar is: todo = 0, only cosmetic partial lines, both CI workflows green on the release commit, and the installed
app smoke-tested on Windows. Today:

- todo = 7;
- 2 partial lines are not cosmetic;
- round 3 is uncommitted and has no CI run;
- canvas.mjs is red;
- the smoke-test findings in items 9-11 are open.

## Appendix: every open checklist line

Grouped by checklist section, `todo` first, then `partial`; the note is the audit's reason.

### Ribbon

- **todo** Manage ▸ More ▸ Tools ▸ Help ▸ Self Test — `APPSELFTEST` · _command APPSELFTEST is not registered in archi-engine_
- **partial** Tab Manage — 5 groups
- **partial** Manage ▸ More (group)
- **partial** Manage ▸ More ▸ Tools (menu) — Action recorder, aliases, scripting, help

### Menu bar

- **todo** Tools ▸ Help ▸ Self Test — `APPSELFTEST` · _command APPSELFTEST is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Help Browser — `HELPWINDOW` · _command HELPWINDOW is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ SpaceMouse — `SPACEMOUSE` · _command SPACEMOUSE is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ File Preview & Spotlight — `FILEPREVIEW` · _command FILEPREVIEW is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ VR Headset View — `VRVIEW` · _command VRVIEW is not registered in archi-engine_
- **todo** Help ▸ Check Command Coverage — `APPSELFTEST` · _command APPSELFTEST is not registered in archi-engine_
- **partial** Menu Tools — 73 items
- **partial** Tools ▸ Help
- **partial** Tools ▸ Navigation & Sheets
- **partial** Tools ▸ Render, Materials & Environment
- **partial** Tools ▸ Files, Clipboard & Access
- **partial** Tools ▸ Styles, Patterns & Occlusion
- **partial** Tools ▸ Tutorial Videos
- **partial** Tools ▸ Tutorial Videos ▸ Record Tutorial Videos — `TUTORIALRECORD Record` · _recording is Mac-only; Windows opens the website tutorials_
- **partial** Tools ▸ Tutorial Videos ▸ Check Tutorial Scripts — `TUTORIALRECORD Check` · _only checks that the commands exist_
- **partial** Menu Help — 13 items

### Keyboard shortcuts (Windows keys; Mac in brackets)

- **partial** Ctrl+0 [⌘0] View ▸ Zoom Extents — See ⌃0: Ctrl+0 is Clean Screen on Windows; same Windows keys as: clean screen → (none) · _Windows key conflict (documented): Ctrl+0 is Clean Screen, Zoom Extents has no Ctrl key (double middle-click, ribbon, Z E)_
- **partial** Ctrl+0 [⌘0] Zoom extents — See ⌃0: Ctrl+0 is Clean Screen on Windows; same Windows keys as: clean screen → (none) · _Windows key conflict (documented): Ctrl+0 is Clean Screen, Zoom Extents has no Ctrl key (double middle-click, ribbon, Z E)_

### Rendering and 3D

- **partial** Lighting preset Daylight — sky=daylight, sunAltitude=46, sunAzimuth=222, sunColor=[1.0, 0.955, 0.89], sunIntensity=3300, shadowRadius=2.5, shadowAlpha=0.94, envIntensity=1.05 … · _cosmetic: 2.1-3.1 levels from the Mac; cedar 5-7 levels too bright in flat light_
- **partial** Lighting preset Golden hour — sky=golden, sunAltitude=11, sunAzimuth=228, sunColor=[1.0, 0.66, 0.38], sunIntensity=3400, shadowRadius=5, shadowAlpha=0.9, envIntensity=0.95 … · _cosmetic: 2.0-2.7 levels from the Mac; cedar +5-6. Smoke test on Windows: the interactive 3D view did not show the warm look after the preset was set_
- **partial** Lighting preset Overcast — sky=overcast, sunAltitude=58, sunAzimuth=200, sunColor=[0.93, 0.96, 1.0], sunIntensity=420, shadowRadius=22, shadowAlpha=0.7, envIntensity=1.55 … · _4.6 levels from the Mac; limestone +12_
- **partial** Lighting preset Night — sky=night, sunAltitude=38, sunAzimuth=135, sunColor=[0.62, 0.72, 1.0], sunIntensity=70, shadowRadius=6, shadowAlpha=0.85, envIntensity=1.0 … · _cosmetic: 1.7 levels from the Mac; the Mac's bollard light pools are brighter_
- **partial** Photographic render (RENDER) with presets, supersampling, PNG output · _clay, depth of field and HDRI done; the Clear Sky / Sunset / Studio / Night / Physical Sky environments approximate the Mac gradient maps_
- **partial** 360° panorama · _rendered with the photographic look, not the Mac panorama renderer_
