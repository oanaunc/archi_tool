# Windows port — open gaps after round 2

Parity audit of 27 Sep 2026 over the 2904 lines of `docs/WINDOWS-PARITY.md`: **2450 done · 171 partial · 275 todo · 8 n/a** (macOS-only items).
Round 3 should start at the top of the list below. "Done" means the Windows entry exists and runs the same engine code (or a tested
shell port) as the Mac; it does not yet mean "verified on real Windows".

## How the audit was done

- **Commands**: every ribbon, menu and palette entry was resolved the way the Windows shell resolves it (`resolveCommand` in
  `ui/ribbon.ts`, `conv` in `ui/titlebar.ts`, `app.action` for `@…` actions, `openUI` for window/sheet targets) against the commands
  archi-engine registers (static scan of every `CommandDef` in `ArchiCore` + `archi-engine`, plus `build/engine-fixtures/hello.json`).
  Mac UI-layer commands count only where a portable version exists in `ArchiCore/Host` and the shell handles its `host` action
  (all 39 action/dialog names the portable commands emit have a handler in `windows/src`).
- **Menu bar**: on Windows the File, Edit, View, Window and Help menus are written by hand in `ui/titlebar.ts`; only Draw, Modify,
  Annotate, Architecture, Model, Analyze and Tools come from `windows-parity.json`. Mac entries that the hand-written menus lack are
  `partial` when the command works elsewhere (ribbon, command line), `todo` when it does not work at all.
- **Panels and dialogs**: each control label was looked up in the shell file that implements that window, then reviewed by hand.
- **Shortcuts, status bar, render, theme**: read from `main.ts`, `ui/windows-conventions.ts`, `dialogs/index.ts`, `ui/statusbar.ts`,
  the CSS, and the view3d calibration numbers.
- **Playwright** (web build + fixture engine): all shell suites pass — ui-snapshots 30/30, dialogs 49/49, partb-tools 27/27,
  canvas 60/60, output 35/35, windows-conventions 9/9, icons OK. The new spot check `windows/test/audit-spot.mjs` confirmed these
  findings: the Component menus are disabled, the Windows File menu has 13 entries, Ctrl+Alt+P and Ctrl+Alt+Shift+P run PLOT, and
  Ctrl+Shift+A selects everything.
- The auditor's statuses can be re-derived with `windows/tools/parity_audit.py` (rules in `windows/tools/parity_audit_rules.py`).

## Per section

| Section | done | partial | todo | n/a |
| --- | ---: | ---: | ---: | ---: |
| Ribbon | 827 | 31 | 49 | 0 |
| Contextual ribbon tabs (selection) | 0 | 0 | 11 | 0 |
| Menu bar | 1052 | 108 | 114 | 4 |
| Tool palettes | 57 | 0 | 0 | 0 |
| Panels | 72 | 14 | 22 | 0 |
| Dialogs and windows | 299 | 6 | 61 | 0 |
| Status bar | 17 | 2 | 2 | 0 |
| Keyboard shortcuts (Windows keys; Mac in brackets) | 60 | 3 | 16 | 4 |
| Rendering and 3D | 17 | 6 | 0 | 0 |
| Theme | 49 | 1 | 0 | 0 |

## Top 30 gaps, by importance to an architect

Each entry names the checklist lines it closes. "Quick" marks fixes of an hour or less.

### A. Broken things in what already exists (fix first)

1. **Furniture menus are disabled** (quick). Insert ▸ Content ▸ Component and Architecture ▸ Model ▸ Component carry the command
   `{r}` (the Mac resolves it to `COMPONENT` at run time); `gen-ui-data.mjs` copies it literally, so all 12 entries in both menus are
   greyed out. Resolve `{r}` to `COMPONENT` in the generator. 26 lines.
2. **Keyboard shortcut bugs** (quick). `main.ts` ignores Alt and Shift in its Ctrl map: Ctrl+Alt+P (Hide Panels) and
   Ctrl+Alt+Shift+P (Plot Preview) run PLOT, Ctrl+Shift+A (Deselect All) selects everything. Unbound: Ctrl+Alt+1…4 (2D/3D/Split/
   Sheets), Ctrl+Alt+J (Script Console), Ctrl+Shift+I (Import), Ctrl+Shift+/ (Command Reference); F2 is swallowed instead of opening
   the History panel. 19 lines.
3. **Schedule CSV exports fail**. Output ▸ Schedules ▸ CSV and File ▸ Export ▸ Schedules send `file.export` with format
   `csv:walls|doors|windows|rooms|slabs|all`, which `DocumentIO.write` rejects; the Schedule sheet (SCHEDULE window with kind picker
   and Export CSV) does not exist. Accept `csv:<kind>` in the engine (`ScheduleExporter.csv(doc:kind:)`) and port ScheduleSheet. 17 lines.
4. **PNG export fails**. File ▸ Export ▸ PNG (300 dpi) and Output ▸ Export ▸ PNG call `file.export png`; the engine has no raster
   writer. Rasterise the plan in the shell (the canvas already paints the DrawList) like the Mac does, or add SHEETIMAGE. 3 lines.
5. **Features the shell has but the command name is not wired** (quick). COMMANDSEARCH, CLEANSCREENON, CLEANSCREENOFF,
   HISTORYPANEL, STARTSCREEN, SAMPLEHOUSE are not registered, so their ribbon "More" / Tools-menu entries are disabled although the
   shell implements each one. Map them to the shell actions in `resolveCommand` / `conv`. ~10 lines.
6. **About** (quick). The app icon, Help ▸ About and Tools ▸ Help ▸ About run ABOUT, which is not registered; add the About window
   (version, GPL licence link, https://www.oanarinaldi.com). 6 lines.

### B. Everyday modelling and drafting workflow

7. **Contextual ribbon tabs**. Selecting a wall, door, window, room, text, hatch, dimension, block, polyline or table shows its
   "Modify …" tab on the Mac (DOOR/WINDOW/OPENING/AUTODIMWALLS on walls, OPENINGPARTS on openings, ROOMFINISH/COLORFILL on rooms,
   HATCHEDIT, DIMEDIT, ATTEDIT, PEDIT, TABLEEDIT …). Windows has none. 11 lines, but the most visible difference while modelling.
8. **Menu bar parity**. Build File, Edit, View and Help from `windows-parity.json` like the other menus (keeping the Windows-only
   entries: New Window, Exit, Alt+letter access). Missing today: Open Recent (+ Clear Menu), File ▸ Insert (12 import/block entries),
   the export formats GeoJSON/Points/3MF/USDZ/DXF R12, Plot Preview, Publish All Sheets, Batch Publish, Plot Style Tables,
   Title Block; Edit ▸ Deselect All, Selection Tools (9), Groups & Isolation (5), Match Properties; View ▸ Zoom Window,
   Visual Style (8), 3D View (6), the eight panel entries, Material Library, 3D Tools (5), Show Script Console; Help ▸ Tutorials,
   Open Sample House, Connect Claude, Command Reference window. ~110 partial + 6 todo lines.
9. **Project Browser**. Only Floor Plans, three fixed 3D views and Sheets; the Mac also lists Project Views (saved views),
   Elevations & Sections, Schedules, Families, Groups and Links, and the 3D views come from the document's saved cameras. 6 lines.
10. **Text tools**. Spelling dialog (SPELLDIALOG, 10 lines), TEXTSTYLEDIALOG, TEXTEDITINPLACE as a command, HYPERLINK; canvas text
    ignores bold/italic/underline (the draw list does not carry them).
11. **Selection and properties panels**. Selection panel (SELECTIONINFO: Only / Remove / Zoom, lengths and areas), floating
    Quick Properties (QUICKPROPS, "Dock / Float / Hide" buttons), Inspector (INSPECT, raw values + Copy), History panel pages,
    numbered undo steps and Copy Log, Properties per-type filter menu, SELECTWALLCHAIN. ~15 lines.

### C. Sheets, documentation and output

12. **Sheet tools still missing in the engine**: MVIEWPOLY (polygonal viewport), MVSETUP (align viewports), SHEETRENUMBER and
    SHEETVIEWTITLES as commands (the Sheet Set panel already does both through `sheetset.edit`), SHEETGRID, SHEETFIELD,
    SHEETIMAGE, SHEETPLACEHOLDER, TITLEBLOCKDESIGN, PSETUPIN (import page setup), LAYOUTTABS, ZOOMXP. ~14 lines.
13. **Graphic standards**: Graphic Styles manager (GRAPHICSTYLES: line styles, lineweights by scale, pen sets, override rules;
    26 lines), Object Styles (OBJECTSTYLESDIALOG), Visual Styles manager (VISUALSTYLES), Material Fill Patterns
    (MATPATTERNDIALOG), LWDISPLAYSCALE.
14. **Plot details**: printer Tray and Media pickers are placeholders (Electron cannot list them); SHADEPLOT Rendered falls back
    to As Displayed for engine-only plots; the page-for-page A-102 check against a Mac PDF is still open (export A-102 on the Mac).

### D. Data safety

15. **Crash recovery**: autosave writes recovery files but DRAWINGRECOVERY (recovered documents on the start screen) is not ported.
16. **Versions**: FILEVERSIONS (browse / restore / open a copy / save a version now) has no Windows equivalent yet. 4 lines.

### E. Rendering, materials and environment

17. **Render look vs the Mac**: lawn and meadow darker in every preset, paving darker at golden hour, Night ~25% darker, bollard
    light pools too wide; mean differences 4.3-9.4 (Aerial worst). Continue with `windows/test/view3d/calib.mjs`. 4 preset lines.
18. **Renderer features**: no clay mode, depth of field or HDRI environment (Render window, Render Queue approximate them);
    360° panorama and ANIMATE Frame use the photographic look instead of the Mac panorama renderer / path tracer. 2 lines.
19. **Lighting and site**: LIGHT (point/spot/area/IES lights), FOG, WATER, SCATTER (grass/trees), BILLBOARD (people/trees
    cut-outs), AODIALOG, RENDERPROMPT. 7 lines.
20. **Material commands**: MATASSET, MATEMISSIVE, MATMAPS, MATMAPPING, MATFROMIMAGE, PROCMATERIAL (the Procedural… and From
    Photo… buttons work in the Materials panel, the commands do not). 6 lines.
21. **4D and mechanisms**: PHASEANIMATION (construction sequence video), MECHANISMPLAY; the mechanism-playback and compare
    overlays are not drawn on the canvas.

### F. Panels, windows and views

22. **Alerts / model warnings** (NOTIFICATIONS: overlaps, unhosted openings, family errors — click to zoom), **Navigator**
    (NAVIGATOR overview map), **Content** (ADCENTER DesignCenter: blocks, layers, styles from another drawing), **Outliner**
    (OUTLINERPANEL). Tabs exist but show placeholders. ~12 lines.
23. **Floating panels** (FLOATPANEL, 17 lines) and the status-bar macro buttons and progress indicator; the agent indicator and
    Quick Props button do not show their state.
24. **Views**: TILEDVIEWS (2-4 tiled views), DVIEW (twist), PERSPECTIVE toggle command, KEYBOARDNAV (keyboard crosshair),
    SPACEMOUSE, VRVIEW (WebXR export).
25. **Block Library / Family Editor from the "More" menus** run the command-line BLOCKLIBRARY / FAMILY instead of opening their
    windows (Insert ▸ More ▸ Blocks, Architecture ▸ More ▸ Systems, Tools menu). 4 lines.

### G. Help, settings and app chrome

26. **Help**: F1 opens the guide, not the running command's section; no offline help (HELPWINDOW); Command Reference is a
    command-line listing, not the searchable window; EXPORTCOMMANDS, APPSELFTEST, WHATSNEW; Tools ▸ All Commands is empty
    (the `{groups}` list is not filled).
27. **AI Assistant** window (ASSISTANT: provider, model, key, chat, confirm bulk changes). 12 lines.
28. **Settings**: LANGUAGE (ribbon language), IMPORTSETTINGS / EXPORTSETTINGS, CMDLINEOPTIONS, CRASHREPORTS; startup.js runs with a
    reduced `archi` API (switch to partb `runScriptFile`).
29. **Windows and tabs**: FILETAB / FILETABCLOSE, WINDOWTABS, SYSWINDOWS (arrange windows), FULLSCREEN.
30. **Clipboard and sharing**: PASTESPECIAL (SVG/PDF/pictures from other apps), COPYPICTURE, SHARE (Windows share sheet),
    IMAGEADJUSTDIALOG, NODEPACKAGE, SPEAKDRAWING (Narrator). Apple-only, decide an equivalent or mark `n/a`: ARQUICKLOOK
    (AR Quick Look), FILEPREVIEW (Finder preview → Windows thumbnail handler).

Small items not in the list: the plan's window-selection blue is #4D80FF (Mac #4073F2); `windows/src/renderer/data/ui.generated.json`
is older than `docs/windows-parity.json` (268 vs 274 ribbon items — CI regenerates it, but local builds use the stale copy);
Tutorials Record/Check are partial by design (recording is Mac-only).

## Not in the checklist, but blocking a release

- Nothing has run in real Electron or on Windows yet: every shell test ran in headless Chromium with the fixture engine.
- `windows/package-lock.json` is missing (npm registry blocked here); the first Windows CI run publishes one.
- The Linux and Windows Swift builds of the new Host files (about 20 new files this round) have not been compiled yet.
- `canvas.mjs`, `dialogs.mjs`, `partb-tools.mjs`, `output.mjs`, `view3d/tools.mjs` and `audit-spot.mjs` are not in CI.
- The fixture engine (`build/engine-fixtures/hello.json`, 914 commands) predates the canvas, 3D and output commands; regenerate it
  with `./scripts/q.sh engine` so the web tests see the real command list.
- No code-signing certificate.

## Appendix: every open checklist line

Grouped by checklist section, `todo` first, then `partial`; the note is the audit's reason.

### Ribbon

- **todo** Insert ▸ Content ▸ Component (menu) — Components are not available in this build / Place furniture and fixtures · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Chair — `{r} Chair` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Table — `{r} Table` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Desk — `{r} Desk` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Sofa — `{r} Sofa` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Bed — `{r} Bed` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Wardrobe — `{r} Wardrobe` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Kitchen — `{r} Kitchen` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Sink — `{r} Sink` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ WC — `{r} WC` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Bath — `{r} Bath` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Car — `{r} Car` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ Content ▸ Component ▸ Component… — `{r}` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Insert ▸ More ▸ Exchange ▸ File ▸ Drawing Recovery — `DRAWINGRECOVERY` · _command DRAWINGRECOVERY is not registered in archi-engine_
- **todo** Annotate ▸ More ▸ Text ▸ Text, Leaders & Tables ▸ Spelling Dialog — `SPELLDIALOG` · _command SPELLDIALOG is not registered in archi-engine_
- **todo** Architecture ▸ Model ▸ Component (menu) — Components are not available in this build / Place furniture and fixtures · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Chair — `{r} Chair` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Table — `{r} Table` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Desk — `{r} Desk` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Sofa — `{r} Sofa` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Bed — `{r} Bed` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Wardrobe — `{r} Wardrobe` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Kitchen — `{r} Kitchen` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Sink — `{r} Sink` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ WC — `{r} WC` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Bath — `{r} Bath` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Car — `{r} Car` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Architecture ▸ Model ▸ Component ▸ Component… — `{r}` · _bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled_
- **todo** Collaborate ▸ Share ▸ Share — `SHARE Both` · _command SHARE is not registered in archi-engine_
- **todo** Collaborate ▸ Share ▸ Share… — `SHARE` · _command SHARE is not registered in archi-engine_
- **todo** View ▸ More ▸ View ▸ View ▸ Clean Screen On — `CLEANSCREENON` · _the shell has the feature but CLEANSCREENON is not registered, so the entry is disabled (map it to the shell action)_
- **todo** View ▸ More ▸ View ▸ View ▸ Clean Screen Off — `CLEANSCREENOFF` · _the shell has the feature but CLEANSCREENOFF is not registered, so the entry is disabled (map it to the shell action)_
- **todo** View ▸ More ▸ View ▸ View ▸ Float Panel — `FLOATPANEL` · _command FLOATPANEL is not registered in archi-engine_
- **todo** View ▸ More ▸ View ▸ View ▸ History Panel — `HISTORYPANEL` · _the shell has the feature but HISTORYPANEL is not registered, so the entry is disabled (map it to the shell action)_
- **todo** Output ▸ More ▸ Output ▸ Output ▸ Renumber Sheets — `SHEETRENUMBER` · _command SHEETRENUMBER is not registered in archi-engine_
- **todo** Output ▸ More ▸ Output ▸ Output ▸ Editable View Titles — `SHEETVIEWTITLES` · _command SHEETVIEWTITLES is not registered in archi-engine_
- **todo** Output ▸ Export ▸ PNG — `@export:png` · _engine file.export has no PNG writer_
- **todo** Output ▸ Schedules ▸ CSV (menu) — Export schedules as CSV
- **todo** Output ▸ Schedules ▸ CSV ▸ Walls schedule (CSV)… — `@export:csv:walls` · _engine file.export does not accept csv:walls_
- **todo** Output ▸ Schedules ▸ CSV ▸ Doors schedule (CSV)… — `@export:csv:doors` · _engine file.export does not accept csv:doors_
- **todo** Output ▸ Schedules ▸ CSV ▸ Windows schedule (CSV)… — `@export:csv:windows` · _engine file.export does not accept csv:windows_
- **todo** Output ▸ Schedules ▸ CSV ▸ Rooms schedule (CSV)… — `@export:csv:rooms` · _engine file.export does not accept csv:rooms_
- **todo** Output ▸ Schedules ▸ CSV ▸ Slabs schedule (CSV)… — `@export:csv:slabs` · _engine file.export does not accept csv:slabs_
- **todo** Output ▸ Schedules ▸ CSV ▸ All schedule (CSV)… — `@export:csv:all` · _engine file.export does not accept csv:all_
- **todo** Manage ▸ More ▸ Tools ▸ Help ▸ Search Commands — `COMMANDSEARCH` · _the shell has the feature but COMMANDSEARCH is not registered, so the entry is disabled (map it to the shell action)_
- **todo** Manage ▸ More ▸ Tools ▸ Help ▸ About — `ABOUT` · _command ABOUT is not registered in archi-engine_
- **todo** Manage ▸ More ▸ Tools ▸ Help ▸ Self Test — `APPSELFTEST` · _command APPSELFTEST is not registered in archi-engine_
- **todo** Manage ▸ More ▸ Tools ▸ Help ▸ Export Command Reference — `EXPORTCOMMANDS` · _command EXPORTCOMMANDS is not registered in archi-engine_
- **todo** Tab bar ▸ app icon (About) — `ABOUT` · _runs ABOUT, which archi-engine does not register (no About window)_
- **partial** Tab Insert — 7 groups
- **partial** Insert ▸ Content (group)
- **partial** Insert ▸ More (group)
- **partial** Insert ▸ More ▸ Blocks (menu) — Block and attribute tools
- **partial** Insert ▸ More ▸ Blocks ▸ Blocks & Attributes ▸ Block Library — `BLOCKLIBRARY` · _runs the command-line BLOCKLIBRARY instead of opening the Block Library window_
- **partial** Insert ▸ More ▸ Exchange (menu) — More import/export formats and file commands
- **partial** Tab Annotate — 6 groups
- **partial** Annotate ▸ More (group)
- **partial** Annotate ▸ More ▸ Text (menu) — Text editing, spelling, fields, tables, symbols
- **partial** Tab Architecture — 7 groups
- **partial** Architecture ▸ Model (group)
- **partial** Architecture ▸ More (group)
- **partial** Architecture ▸ More ▸ Systems (menu) — BIM data, structure, MEP and site tools
- **partial** Architecture ▸ More ▸ Systems ▸ BIM Authoring ▸ Family Editor — `FAMILY` · _runs the command-line FAMILY instead of opening the Family Editor window_
- **partial** Tab Collaborate — 4 groups
- **partial** Collaborate ▸ Share (group)
- **partial** Tab View — 8 groups
- **partial** View ▸ 3D Tools (group)
- **partial** View ▸ 3D Tools ▸ Section Box — `SECTIONBOX` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools ▸ Sun Study — `SUNSTUDY` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools ▸ View Cube — `NAVVCUBE` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ More (group)
- **partial** View ▸ More ▸ View (menu) — Every view command
- **partial** Tab Output — 5 groups
- **partial** Output ▸ More (group)
- **partial** Output ▸ More ▸ Output (menu) — Every output command, plot styles, batch publish
- **partial** Output ▸ Export (group)
- **partial** Output ▸ Schedules (group)
- **partial** Tab Manage — 5 groups
- **partial** Manage ▸ More (group)
- **partial** Manage ▸ More ▸ Tools (menu) — Action recorder, aliases, scripting, help

### Contextual ribbon tabs (selection)

- **todo** Selection Wall → tab "Modify Wall" · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Door → tab "Modify Door" — PROPERTIES, SETPROP, OPENINGPARTS, MOVE, COPY, ROTATE, MIRROR, MATCHPROP, SELECTSIMILAR · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Window → tab "Modify Window" — PROPERTIES, SETPROP, OPENINGPARTS, MOVE, COPY, ROTATE, MIRROR, MATCHPROP, SELECTSIMILAR · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Text → tab "Text Editor" · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Hatch → tab "Hatch Editor" · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Dimension → tab "Dimension" · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Block Reference → tab "Block Reference" · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Polyline → tab "Polyline" — PEDIT, JOIN, REVERSE, EXPLODE, MOVE, COPY, ROTATE, MIRROR, MATCHPROP, SELECTSIMILAR · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Table → tab "Table Cell" — TABLEEDIT, TABLEEXPORT, MOVE, COPY, ROTATE, MIRROR, MATCHPROP, SELECTSIMILAR · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection Room → tab "Modify Room" — ROOMFINISH, COLORFILL, PROPERTIES, MOVE, COPY, ROTATE, MIRROR, MATCHPROP, SELECTSIMILAR · _no contextual (selection) ribbon tabs on Windows_
- **todo** Selection (other) → tab "Modify (other)" — PROPERTIES, MOVE, COPY, ROTATE, MIRROR, MATCHPROP, SELECTSIMILAR · _no contextual (selection) ribbon tabs on Windows_

### Menu bar

- **todo** Oanarina Archi Tool ▸ About Oanarina Archi Tool — `ABOUT` · _Help ▸ About runs ABOUT, which archi-engine does not register_
- **todo** File ▸ Open Recent · _no Open Recent submenu (recent files only on the start screen and the taskbar jump list)_
- **todo** File ▸ Open Recent ▸ Clear Menu — `@ui:RecentFiles.clear`
- **todo** File ▸ Export ▸ PNG (300 dpi)… — `@export:png` · _Windows File ▸ Export ▸ PNG calls file.export png, which the engine rejects (no raster writer)_
- **todo** File ▸ Export ▸ Schedules (CSV) · _@export:csv:<kind> is not accepted by engine file.export and the submenu is missing_
- **todo** File ▸ Export ▸ Schedules (CSV) ▸ Walls… — `@export:csv:walls` · _engine file.export does not accept csv:<kind>_
- **todo** File ▸ Export ▸ Schedules (CSV) ▸ Doors… — `@export:csv:doors` · _engine file.export does not accept csv:<kind>_
- **todo** File ▸ Export ▸ Schedules (CSV) ▸ Windows… — `@export:csv:windows` · _engine file.export does not accept csv:<kind>_
- **todo** File ▸ Export ▸ Schedules (CSV) ▸ Rooms… — `@export:csv:rooms` · _engine file.export does not accept csv:<kind>_
- **todo** File ▸ Export ▸ Schedules (CSV) ▸ Slabs… — `@export:csv:slabs` · _engine file.export does not accept csv:<kind>_
- **todo** File ▸ Export ▸ Schedules (CSV) ▸ All… — `@export:csv:all` · _engine file.export does not accept csv:<kind>_
- **todo** View ▸ Float Panel · _FLOATPANEL (floating panel windows) not ported_
- **todo** View ▸ Float Panel ▸ Properties — `FLOATPANEL Properties` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Layers — `FLOATPANEL Layers` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Levels — `FLOATPANEL Levels` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Browser — `FLOATPANEL Browser` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Materials — `FLOATPANEL Materials` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Tools — `FLOATPANEL Tools` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Sheets — `FLOATPANEL Sheets` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ History — `FLOATPANEL History` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Selection — `FLOATPANEL Selection` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Navigator — `FLOATPANEL Navigator` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Alerts — `FLOATPANEL Alerts` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Quick Props — `FLOATPANEL Quick Props` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Inspector — `FLOATPANEL Inspector` · _FLOATPANEL not registered in archi-engine_
- **todo** View ▸ Float Panel ▸ Content — `FLOATPANEL Content` · _FLOATPANEL not registered in archi-engine_
- **todo** Tools ▸ Text & Tables ▸ Spelling Dialog — `SPELLDIALOG` · _command SPELLDIALOG is not registered in archi-engine_
- **todo** Tools ▸ File ▸ Drawing Recovery — `DRAWINGRECOVERY` · _command DRAWINGRECOVERY is not registered in archi-engine_
- **todo** Tools ▸ View ▸ Clean Screen On — `CLEANSCREENON` · _command CLEANSCREENON is not registered in archi-engine_
- **todo** Tools ▸ View ▸ Clean Screen Off — `CLEANSCREENOFF` · _command CLEANSCREENOFF is not registered in archi-engine_
- **todo** Tools ▸ View ▸ Float Panel — `FLOATPANEL` · _command FLOATPANEL is not registered in archi-engine_
- **todo** Tools ▸ View ▸ History Panel — `HISTORYPANEL` · _command HISTORYPANEL is not registered in archi-engine_
- **todo** Tools ▸ Output ▸ Renumber Sheets — `SHEETRENUMBER` · _command SHEETRENUMBER is not registered in archi-engine_
- **todo** Tools ▸ Output ▸ Editable View Titles — `SHEETVIEWTITLES` · _command SHEETVIEWTITLES is not registered in archi-engine_
- **todo** Tools ▸ Start & Templates ▸ Start Screen — `STARTSCREEN` · _command STARTSCREEN is not registered in archi-engine_
- **todo** Tools ▸ Help ▸ Search Commands — `COMMANDSEARCH` · _command COMMANDSEARCH is not registered in archi-engine_
- **todo** Tools ▸ Help ▸ About — `ABOUT` · _command ABOUT is not registered in archi-engine_
- **todo** Tools ▸ Help ▸ Self Test — `APPSELFTEST` · _command APPSELFTEST is not registered in archi-engine_
- **todo** Tools ▸ Help ▸ Export Command Reference — `EXPORTCOMMANDS` · _command EXPORTCOMMANDS is not registered in archi-engine_
- **todo** Tools ▸ Sharing & Exchange ▸ Share… — `SHARE` · _command SHARE is not registered in archi-engine_
- **todo** Tools ▸ Families, Views & Panels ▸ Sheet to Image — `SHEETIMAGE` · _command SHEETIMAGE is not registered in archi-engine_
- **todo** Tools ▸ Families, Views & Panels ▸ Selection Info — `SELECTIONINFO` · _command SELECTIONINFO is not registered in archi-engine_
- **todo** Tools ▸ Families, Views & Panels ▸ Notifications — `NOTIFICATIONS` · _command NOTIFICATIONS is not registered in archi-engine_
- **todo** Tools ▸ Families, Views & Panels ▸ Navigator — `NAVIGATOR` · _command NAVIGATOR is not registered in archi-engine_
- **todo** Tools ▸ Families, Views & Panels ▸ What's New — `WHATSNEW` · _command WHATSNEW is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ File Tabs — `FILETAB` · _command FILETAB is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Hide File Tabs — `FILETABCLOSE` · _command FILETABCLOSE is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Model/Layout Tabs — `LAYOUTTABS` · _command LAYOUTTABS is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Quick Properties — `QUICKPROPS` · _command QUICKPROPS is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Inspector — `INSPECT` · _command INSPECT is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Design Center — `ADCENTER` · _command ADCENTER is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Help Browser — `HELPWINDOW` · _command HELPWINDOW is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Sample House — `SAMPLEHOUSE` · _command SAMPLEHOUSE is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Select Wall Chain — `SELECTWALLCHAIN` · _command SELECTWALLCHAIN is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Twist View — `DVIEW` · _command DVIEW is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Perspective — `PERSPECTIVE` · _command PERSPECTIVE is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Polygonal Viewport — `MVIEWPOLY` · _command MVIEWPOLY is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Align Viewports — `MVSETUP` · _command MVSETUP is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Sheet Guide Grid — `SHEETGRID` · _command SHEETGRID is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Placeholder Sheet — `SHEETPLACEHOLDER` · _command SHEETPLACEHOLDER is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Custom Fields — `SHEETFIELD` · _command SHEETFIELD is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Import Page Setup — `PSETUPIN` · _command PSETUPIN is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Lineweight Display Scale — `LWDISPLAYSCALE` · _command LWDISPLAYSCALE is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Visual Styles Manager — `VISUALSTYLES` · _command VISUALSTYLES is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Tiled Views — `TILEDVIEWS` · _command TILEDVIEWS is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Export Settings — `EXPORTSETTINGS` · _command EXPORTSETTINGS is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Window Tabs — `WINDOWTABS` · _command WINDOWTABS is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Full Screen — `FULLSCREEN` · _command FULLSCREEN is not registered in archi-engine_
- **todo** Tools ▸ Navigation & Sheets ▸ Import Settings — `IMPORTSETTINGS` · _command IMPORTSETTINGS is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Arrange Windows — `SYSWINDOWS` · _command SYSWINDOWS is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Lights — `LIGHT` · _command LIGHT is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Fog — `FOG` · _command FOG is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Emissive Material — `MATEMISSIVE` · _command MATEMISSIVE is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Texture Mapping — `MATMAPPING` · _command MATMAPPING is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Billboard — `BILLBOARD` · _command BILLBOARD is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Title Block Design — `TITLEBLOCKDESIGN` · _command TITLEBLOCKDESIGN is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Construction Sequence (4D) — `PHASEANIMATION` · _command PHASEANIMATION is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Hyperlink — `HYPERLINK` · _command HYPERLINK is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ AI Assistant — `ASSISTANT` · _command ASSISTANT is not registered in archi-engine_
- **todo** Tools ▸ Navigate, Light & Publish ▸ Render Prompt — `RENDERPROMPT` · _command RENDERPROMPT is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ PBR Maps — `MATMAPS` · _command MATMAPS is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Material Assets — `MATASSET` · _command MATASSET is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Procedural Material — `PROCMATERIAL` · _command PROCMATERIAL is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Material from Photo — `MATFROMIMAGE` · _command MATFROMIMAGE is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Water — `WATER` · _command WATER is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Scatter Plants — `SCATTER` · _command SCATTER is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ SpaceMouse — `SPACEMOUSE` · _command SPACEMOUSE is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Node Packages — `NODEPACKAGE` · _command NODEPACKAGE is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Graphic Styles — `GRAPHICSTYLES` · _command GRAPHICSTYLES is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ AR Quick Look — `ARQUICKLOOK` · _command ARQUICKLOOK is not registered in archi-engine_
- **todo** Tools ▸ Render, Materials & Environment ▸ Command Line Options — `CMDLINEOPTIONS` · _command CMDLINEOPTIONS is not registered in archi-engine_
- **todo** Tools ▸ Components & Surfaces ▸ Outliner Window — `OUTLINERPANEL` · _command OUTLINERPANEL is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access
- **todo** Tools ▸ Files, Clipboard & Access ▸ Browse Versions — `FILEVERSIONS` · _command FILEVERSIONS is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ File Preview & Spotlight — `FILEPREVIEW` · _command FILEPREVIEW is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Paste from Other App — `PASTESPECIAL` · _command PASTESPECIAL is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Copy as Picture — `COPYPICTURE` · _command COPYPICTURE is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Zoom to Paper Scale — `ZOOMXP` · _command ZOOMXP is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Describe Drawing — `SPEAKDRAWING` · _command SPEAKDRAWING is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Keyboard Navigation — `KEYBOARDNAV` · _command KEYBOARDNAV is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Play Mechanism — `MECHANISMPLAY` · _command MECHANISMPLAY is not registered in archi-engine_
- **todo** Tools ▸ Files, Clipboard & Access ▸ Language — `LANGUAGE` · _command LANGUAGE is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Object Styles… — `OBJECTSTYLESDIALOG` · _command OBJECTSTYLESDIALOG is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Text Styles… — `TEXTSTYLEDIALOG` · _command TEXTSTYLEDIALOG is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Image Adjust… — `IMAGEADJUSTDIALOG` · _command IMAGEADJUSTDIALOG is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Ambient Occlusion… — `AODIALOG` · _command AODIALOG is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Crash Reports — `CRASHREPORTS` · _command CRASHREPORTS is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ VR Headset View — `VRVIEW` · _command VRVIEW is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Edit Text In Place — `TEXTEDITINPLACE` · _command TEXTEDITINPLACE is not registered in archi-engine_
- **todo** Tools ▸ Styles, Patterns & Occlusion ▸ Material Fill Patterns… — `MATPATTERNDIALOG` · _command MATPATTERNDIALOG is not registered in archi-engine_
- **todo** Tools ▸ All Commands
- **todo** Tools ▸ All Commands ▸ {groups} · _run-time list not filled on Windows_
- **todo** Help ▸ Check Command Coverage — `APPSELFTEST` · _APPSELFTEST not ported_
- **todo** Help ▸ Export Command Reference… — `EXPORTCOMMANDS` · _EXPORTCOMMANDS not ported_
- **partial** Menu Oanarina Archi Tool — 6 items · _no app menu on Windows (by convention); Settings is Edit ▸ Options, Quit is File ▸ Exit, About is under Help_
- **partial** Oanarina Archi Tool ▸ Agent Server… — `AGENTSETTINGS` · _AGENTSETTINGS works (Settings ▸ Agents) but no Windows menu entry_
- **partial** Menu File — 17 items · _hand-written Windows File menu: New/Open/Save/Import/Export/Page Setup/Print/Close/Exit only_
- **partial** File ▸ Insert · _no File ▸ Insert submenu on Windows; the commands work from the Insert ribbon tab_
- **partial** File ▸ Insert ▸ Import File — `IMPORTFILE` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ IFC — `IFCIMPORT` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ SVG — `SVGIMPORT` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Mesh (OBJ/STL) — `MESHIMPORT` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ GeoJSON — `GEOJSONIMPORT` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Points (CSV) — `POINTSIMPORT` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Insert Block — `INSERT` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Create Block — `BLOCK` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Xref — `XREF` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Image — `IMAGEATTACH` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Attribute — `ATTDEF` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Insert ▸ Paste Special — `PASTEORIG` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Export · _PDF/DXF/SVG/IFC/OBJ/STL/GLB only; PNG fails and GeoJSON, Points, 3MF, USDZ, DXF R12, Schedules are missing_
- **partial** File ▸ Export ▸ GeoJSON — `GEOJSONEXPORT` · _command works from the ribbon / command line; the Windows File ▸ Export menu has no entry_
- **partial** File ▸ Export ▸ Points — `POINTSEXPORT` · _command works from the ribbon / command line; the Windows File ▸ Export menu has no entry_
- **partial** File ▸ Export ▸ 3MF — `EXPORT3MF` · _command works from the ribbon / command line; the Windows File ▸ Export menu has no entry_
- **partial** File ▸ Export ▸ USDZ — `USDEXPORT` · _command works from the ribbon / command line; the Windows File ▸ Export menu has no entry_
- **partial** File ▸ Export ▸ DXF R12 — `DXFR12OUT` · _command works from the ribbon / command line; the Windows File ▸ Export menu has no entry_
- **partial** File ▸ Plot Preview… — `PREVIEW` · Ctrl+Alt+Shift+P · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Publish All Sheets to PDF… — `PUBLISH` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Batch Publish… — `BATCHPUBLISH` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Plot Style Tables… — `PLOTSTYLE` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** File ▸ Title Block… — `TITLEBLOCK` · _command works from the ribbon / command line; the Windows File menu has no entry_
- **partial** Menu Edit — 12 items · _hand-written Windows Edit menu lacks Deselect All, Selection Tools, Groups & Isolation, Match Properties_
- **partial** Edit ▸ Deselect All — `@deselectAll` · Ctrl+Shift+A · _no menu entry; Ctrl+Shift+A selects all instead (main.ts ignores Shift)_
- **partial** Edit ▸ Selection Tools · _submenu missing; the commands work from the ribbon_
- **partial** Edit ▸ Selection Tools ▸ Quick Select — `QSELECT` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ Select Similar — `SELECTSIMILAR` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ Invert — `SELECTINVERT` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ By Layer — `SELECTLAYER` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ By Type — `SELECTTYPE` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ Chain — `SELECTCHAIN` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ Intersecting — `SELECTINTERSECTING` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ Filter — `FILTER` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Selection Tools ▸ Named Sets — `SELSET` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Groups & Isolation · _submenu missing; the commands work from the ribbon_
- **partial** Edit ▸ Groups & Isolation ▸ Group — `GROUP` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Groups & Isolation ▸ Ungroup — `UNGROUP` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Groups & Isolation ▸ Isolate — `ISOLATEOBJECTS` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Groups & Isolation ▸ Hide — `HIDEOBJECTS` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Groups & Isolation ▸ End Isolation — `UNISOLATEOBJECTS` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Edit ▸ Match Properties — `MATCHPROP` · _command works from the ribbon / command line; the Windows Edit menu has no entry_
- **partial** Menu View — 28 items · _hand-written Windows View menu: modes, Workspace, Layer States, zoom, panels, Clean Screen, Command Search only_
- **partial** View ▸ Zoom Window — `@zoom:window` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style · _submenu missing; the ribbon visual-style drop-down works_
- **partial** View ▸ Visual Style ▸ Wireframe — `VSCURRENT Wireframe` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ Hidden Line — `VSCURRENT Hidden Line` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ Shaded — `VSCURRENT Shaded` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ Shaded with Edges — `VSCURRENT Shaded with Edges` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ Conceptual — `VSCURRENT Conceptual` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ Realistic — `VSCURRENT Realistic` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ X-Ray — `VSCURRENT X-Ray` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Visual Style ▸ Sketchy — `VSCURRENT Sketchy` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D View · _submenu missing; the view commands work from the ribbon and view cube_
- **partial** View ▸ 3D View ▸ Top — `TOPVIEW` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D View ▸ Front — `FRONTVIEW` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D View ▸ Right — `RIGHTVIEW` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D View ▸ Back — `BACKVIEW` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D View ▸ Left — `LEFTVIEW` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D View ▸ Iso — `ISOVIEW` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Layers Panel — `@panel:Layers` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Properties Panel — `@panel:Properties` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Levels Panel — `@panel:Levels` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Project Browser — `@panel:Browser` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Materials Panel — `@panel:Materials` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ History Panel — `@panel:History` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Sheet Set Manager — `@panel:Sheets` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Tool Palettes — `@panel:Tools` · _no View-menu entry; the panel opens from its panel tab / ribbon_
- **partial** View ▸ Material Library… — `MATBROWSER` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools · _submenu missing; the commands work from the View ribbon tab_
- **partial** View ▸ 3D Tools ▸ View Cube — `NAVVCUBE` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools ▸ Section Box — `SECTIONBOX` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools ▸ Sun Study — `SUNSTUDY` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools ▸ Orbit Around Selection — `ORBITSELECTION` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ 3D Tools ▸ Save Camera… — `SAVECAMERA` · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** View ▸ Show Script Console — `@scriptConsole` · Ctrl+Alt+J · _command works from the ribbon / command line; the Windows View menu has no entry_
- **partial** Menu Tools — 73 items
- **partial** Tools ▸ Text & Tables
- **partial** Tools ▸ Blocks & Attributes
- **partial** Tools ▸ Blocks & Attributes ▸ Block Library — `BLOCKLIBRARY` · _runs the command-line BLOCKLIBRARY instead of opening the Block Library window_
- **partial** Tools ▸ File
- **partial** Tools ▸ View
- **partial** Tools ▸ Output
- **partial** Tools ▸ Start & Templates
- **partial** Tools ▸ Help
- **partial** Tools ▸ Sharing & Exchange
- **partial** Tools ▸ BIM Authoring
- **partial** Tools ▸ BIM Authoring ▸ Family Editor — `FAMILY` · _runs the command-line FAMILY instead of opening the Family Editor window_
- **partial** Tools ▸ Families, Views & Panels
- **partial** Tools ▸ Navigation & Sheets
- **partial** Tools ▸ Navigate, Light & Publish
- **partial** Tools ▸ Navigate, Light & Publish ▸ Shade Plot — `SHADEPLOT` · _SHADEPLOT Rendered falls back to As Displayed for engine-only plots_
- **partial** Tools ▸ Render, Materials & Environment
- **partial** Tools ▸ Components & Surfaces
- **partial** Tools ▸ Styles, Patterns & Occlusion
- **partial** Tools ▸ Tutorial Videos
- **partial** Tools ▸ Tutorial Videos ▸ Record Tutorial Videos — `TUTORIALRECORD Record` · _recording is Mac-only; Windows opens the website tutorials_
- **partial** Tools ▸ Tutorial Videos ▸ Check Tutorial Scripts — `TUTORIALRECORD Check` · _only checks that the commands exist_
- **partial** Menu Help — 13 items · _hand-written Windows Help menu_
- **partial** Help ▸ Oanarina Archi Tool Help (F1) — `HELP` · _F1 opens the online guide, not the running command's page; Help ▸ Command Help runs HELP_
- **partial** Help ▸ Tutorials — `HELP` · _command works from the ribbon / command line; the Windows Help menu has no entry_
- **partial** Help ▸ Open Sample House — `@ui:WindowRouter.open` · _not in the Help menu; File ▸ New from Template ▸ Sample House and the start screen open it_
- **partial** Help ▸ Command Reference — `@ui:window:command-reference` · Ctrl+Shift+/ · _runs COMMANDREFERENCE on the command line; no Command Reference window_
- **partial** Help ▸ Connect Claude… — `CONNECTCLAUDE` · _command works from the ribbon / command line; the Windows Help menu has no entry_

### Panels

- **todo** Browser ▸ Button Project Views · _label not found in panels.ts_
- **todo** Browser ▸ Button Elevations & Sections · _label not found in panels.ts_
- **todo** Browser ▸ Button Schedules · _label not found in panels.ts_
- **todo** Browser ▸ Button Families · _label not found in panels.ts_
- **todo** Browser ▸ Button Links · _label not found in panels.ts_
- **todo** History ▸ Button Copy Log · _label not found in panels.ts_
- **todo** Selection ▸ Button Remove — (repeated) · _label not found in panels.ts_
- **todo** Selection ▸ Button Zoom to Selection · _label not found in panels.ts_
- **todo** Panel Navigator (NavigatorPanel) — sections: · _placeholder text only_
- **todo** Panel Alerts (NotificationsPanel) — sections: · _placeholder 'No alerts.' only_
- **todo** Alerts ▸ Toggle Info — showInfo
- **todo** Alerts ▸ Button Restore dismissed
- **todo** Alerts ▸ Button Dismiss
- **todo** Quick Props ▸ Button Dock in the panels (Quick Props tab) — `@panel:Quick Props` · _label not found in panels.ts_
- **todo** Quick Props ▸ Button Float in a window — `FLOATPANEL` · _label not found in panels.ts_
- **todo** Quick Props ▸ Button Hide Quick Properties (QP) — `QUICKPROPS` · _label not found in panels.ts_
- **todo** Inspector ▸ Button Copy — (repeated) · _label not found in panels.ts_
- **todo** Panel Content (DesignCenterPanel) — sections: · _shows the static tool list, not the DesignCenter content browser_
- **todo** Content ▸ Menu Choose Drawing
- **todo** Content ▸ Picker  — kind
- **todo** Content ▸ Button Add to Drawing
- **todo** Content ▸ Button Add All
- **partial** Panel Properties (PropertiesPanel) — sections: Project, Drawing, General, Geometry & Parameters
- **partial** Properties ▸ Menu {"\(types.count) objects (" + counts.sorted() {…}.map() {…}.joined(separator: ", ") + ")"} · _type summary shown, not a per-type filter menu_
- **partial** Panel Browser (ProjectBrowserPanel) — sections: · _only Floor Plans, 3D Views (Front/Aerial/Corner) and Sheets_
- **partial** Panel Materials (MaterialsPanel) — sections: Identity, graphics & physical
- **partial** Materials ▸ Button Procedural… — `PROCMATERIAL` · _command PROCMATERIAL is not registered in archi-engine_
- **partial** Panel History (HistoryPanel) — sections: · _undo list, redo and command history; no page picker, Copy Log or numbered undo steps_
- **partial** History ▸ Picker  — page
- **partial** History ▸ Button 0
- **partial** History ▸ Button {index} — (repeated)
- **partial** History ▸ Button {index} — (repeated)
- **partial** Panel Selection (SelectionInfoPanel) — sections: · _summary and type counts only; no Only / Remove / Zoom buttons_
- **partial** Panel Quick Props (QuickPropertiesView) — sections: · _shows the Properties panel; no floating Quick Properties window_
- **partial** Quick Props ▸ TextField  — text (repeated)
- **partial** Panel Inspector (InspectorPanel) — sections: · _shows the Properties panel; no raw inspector / Copy_

### Dialogs and windows

- **todo** ScheduleSheet (sheet ScheduleSheet) — `SCHEDULE` · _SCHEDULE has no schedule sheet on Windows_
- **todo** ScheduleSheet ▸ Picker Schedule — kind
- **todo** ScheduleSheet ▸ Button Export CSV… — `@export:csv:{kind}`
- **todo** CommandReferenceView ▸ TextField Search commands, aliases, descriptions — query · _label not found in shortcuts.ts_
- **todo** SpellingSheet (sheet SpellingSheet) — `SPELLDIALOG` · _SPELLDIALOG not ported_
- **todo** SpellingSheet ▸ Button Zoom To
- **todo** SpellingSheet ▸ TextField  — replacement
- **todo** SpellingSheet ▸ Button {s}
- **todo** SpellingSheet ▸ Button Change
- **todo** SpellingSheet ▸ Button Change All
- **todo** SpellingSheet ▸ Button Ignore
- **todo** SpellingSheet ▸ Button Ignore All
- **todo** SpellingSheet ▸ Button Add to Dictionary
- **todo** SpellingSheet ▸ Button Done
- **todo** About (window AboutView) — `ABOUT` · _ABOUT is not registered in archi-engine and the shell has no About window_
- **todo** About ▸ Button View License — `@openURL`
- **todo** About ▸ Link www.oanarinaldi.com
- **todo** Assistant (window AssistantPanel) — `ASSISTANT` · _ASSISTANT (AI assistant window) not ported_
- **todo** Assistant ▸ Button Provider, model and key
- **todo** Assistant ▸ Picker Provider — session.config.provider
- **todo** Assistant ▸ TextField Model — session.config.model
- **todo** Assistant ▸ TextField Endpoint (localhost) — session.config.endpoint
- **todo** Assistant ▸ SecureField Anthropic API key (stored in the keychain) — key
- **todo** Assistant ▸ Stepper Confirm above {session.config.bulkLimit} changes — session.config.bulkLimit
- **todo** Assistant ▸ Button Save
- **todo** Assistant ▸ Button Discard
- **todo** Assistant ▸ Button Apply
- **todo** Assistant ▸ TextField Ask or describe a change (e.g. “add a 5 m wall from 0,0 to the east”) — input
- **todo** Assistant ▸ Button [paperplane.fill]
- **todo** GraphicStyles (window GraphicStylesView) — `GRAPHICSTYLES` · _GRAPHICSTYLES (line styles, pens, graphic override rules) not ported_
- **todo** GraphicStyles ▸ Picker  — page
- **todo** GraphicStyles ▸ 0 ▸ TextField New line style name — newStyle
- **todo** GraphicStyles ▸ 0 ▸ Button Add
- **todo** GraphicStyles ▸ 1 ▸ Picker  — Binding(get: {…}, set: {…})
- **todo** GraphicStyles ▸ 2 ▸ TextField  — lwText
- **todo** GraphicStyles ▸ 2 ▸ Button Apply
- **todo** GraphicStyles ▸ 3 ▸ Picker  — Binding(get: {…}, set: {…})
- **todo** GraphicStyles ▸ 3 ▸ Toggle Show on screen — Binding(get: {…}, set: {…})
- **todo** GraphicStyles ▸ 3 ▸ Button Edit
- **todo** GraphicStyles ▸ 3 ▸ Button Delete
- **todo** GraphicStyles ▸ 3 ▸ TextField Name — penName
- **todo** GraphicStyles ▸ 3 ▸ TextField Pens — penText
- **todo** GraphicStyles ▸ 3 ▸ Button Save
- **todo** GraphicStyles ▸ Toggle  — Binding(get: {…}, set: {…})
- **todo** GraphicStyles ▸ Button Higher priority
- **todo** GraphicStyles ▸ Button Delete
- **todo** GraphicStyles ▸ TextField Name — rule.name
- **todo** GraphicStyles ▸ Picker  — rule.field
- **todo** GraphicStyles ▸ Picker  — rule.op
- **todo** GraphicStyles ▸ TextField Value — rule.value
- **todo** GraphicStyles ▸ TextField Colour #RRGGBB — ruleColor
- **todo** GraphicStyles ▸ TextField Lineweight — ruleWeight
- **todo** GraphicStyles ▸ Toggle Halftone — Binding(get: {…}, set: {…})
- **todo** GraphicStyles ▸ Toggle Hide — Binding(get: {…}, set: {…})
- **todo** GraphicStyles ▸ Button Add Rule
- **todo** Outliner (window OutlinerView) — `OUTLINERPANEL` · _OUTLINERPANEL not ported_
- **todo** Outliner ▸ TextField Filter by name — filter
- **todo** Versions (window VersionsBrowser) — `FILEVERSIONS` · _FILEVERSIONS not ported_
- **todo** Versions ▸ Button Open Copy
- **todo** Versions ▸ Button Restore…
- **todo** Versions ▸ Button Save Version Now
- **partial** CommandReferenceView (sheet CommandReferenceView) — `COMMANDS` · _Help ▸ Command Reference runs COMMANDREFERENCE on the command line; no searchable window_
- **partial** Preferences (window PreferencesView) — `OPTIONS`
- **partial** Preferences ▸ general ▸ Toggle Run startup.js from the script library in every new window — prefs.runStartupScript · _startup.js runs with a reduced archi API (not partb runScriptFile)_
- **partial** PrintSetup (window PrintSetupView) — `PRINTSETUP`
- **partial** PrintSetup ▸ Picker Tray — o.tray · _placeholder list (Electron cannot list trays)_
- **partial** PrintSetup ▸ Picker Media — o.mediaType · _placeholder list (Electron cannot list media types)_

### Status bar

- **todo** view MacroButtonBar · _macro buttons not in the Windows status bar_
- **todo** view ProgressStatusView · _no progress indicator for long commands_
- **partial** button slider.horizontal.below.rectangle — Quick Properties (QP) {model.showQuickProperties ? "on" : "off"} · _opens the Quick Props tab; tooltip does not follow the on/off state_
- **partial** button agentIndicator · _static 'Agent: off' label; runs AGENTSERVER but does not show the server state_

### Keyboard shortcuts (Windows keys; Mac in brackets)

- **todo** Ctrl+Shift+I [⇧⌘I] File ▸ Import… · _not bound on Windows_
- **todo** Ctrl+Alt+Shift+P [⌥⇧⌘P] File ▸ Plot Preview… — Ctrl+Alt = AltGr → Ctrl+Alt+Shift+P · _bug: main.ts maps any Ctrl+P combination to PLOT_
- **todo** Ctrl+Shift+A [⇧⌘A] Edit ▸ Deselect All · _bug: Ctrl+Shift+A selects all (main.ts ignores Shift)_
- **todo** Ctrl+Alt+1 [⌥⌘1] View ▸ 2D Plan · _not bound_
- **todo** Ctrl+Alt+2 [⌥⌘2] View ▸ 3D Model — Ctrl+Alt = AltGr → Ctrl+Alt+2 · _not bound_
- **todo** Ctrl+Alt+3 [⌥⌘3] View ▸ Split View — Ctrl+Alt = AltGr → Ctrl+Alt+3 · _not bound_
- **todo** Ctrl+Alt+4 [⌥⌘4] View ▸ Sheets — Ctrl+Alt = AltGr → Ctrl+Alt+4 · _not bound_
- **todo** Ctrl+Alt+P [⌥⌘P] View ▸ Hide Panels · _bug: runs PLOT (main.ts ignores Alt)_
- **todo** Ctrl+Alt+J [⌥⌘J] View ▸ Show Script Console — Ctrl+Alt = AltGr on European layouts → Ctrl+Alt+J · _not bound_
- **todo** Ctrl+Shift+/ [⇧⌘/] Help ▸ Command Reference — Ctrl+? on US layouts; fine → Ctrl+Shift+/ · _not bound_
- **todo** F2 [F2] Command history panel · _F2 is swallowed (main.ts) and opens nothing_
- **todo** Ctrl+Alt+1 … Ctrl+Alt+4 [⌥⌘1 … ⌥⌘4] 2D · 3D · Split · Sheets · _not bound_
- **todo** Ctrl+Alt+P [⌥⌘P] Show / hide panels · _bug: runs PLOT_
- **todo** Ctrl+Alt+J [⌥⌘J] Script console — Ctrl+Alt = AltGr on European layouts → Ctrl+Alt+J · _not bound_
- **todo** Ctrl+Alt+Shift+P [⌥⇧⌘P] Plot preview — Ctrl+Alt = AltGr → Ctrl+Alt+Shift+P · _bug: runs PLOT_
- **todo** Ctrl+Shift+/ [⇧⌘/] Command reference — Ctrl+? on US layouts; fine → Ctrl+Shift+/ · _not bound_
- **partial** Ctrl+0 [⌘0] View ▸ Zoom Extents — See ⌃0: Ctrl+0 is Clean Screen on Windows; same Windows keys as: clean screen → (none) · _Ctrl+0 toggles Clean Screen on Windows (the Mac binds both)_
- **partial** F1 [F1] Help for the running command — Windows help key: matches the Mac (context help) → F1 · _F1 opens the guide, not the running command's section_
- **partial** Ctrl+0 [⌘0] Zoom extents — See ⌃0: Ctrl+0 is Clean Screen on Windows; same Windows keys as: clean screen → (none) · _Ctrl+0 is Clean Screen on Windows_

### Rendering and 3D

- **partial** Lighting preset Daylight · _within ~5 levels of the Mac, but lawn/meadow render darker (view3d calib)_
- **partial** Lighting preset Golden hour · _lawn and paving darker than the Mac (mean diff 5.7-9.4)_
- **partial** Lighting preset Overcast · _within ~5 levels of the Mac, but lawn/meadow render darker (view3d calib)_
- **partial** Lighting preset Night · _about 25% darker than the Mac; bollard light pools too wide_
- **partial** Photographic render (RENDER) with presets, supersampling, PNG output · _no clay mode, depth of field or HDRI environment in the WebGL renderer_
- **partial** 360° panorama · _rendered with the photographic look, not the Mac panorama renderer_

### Theme

- **partial** Color windowBlue — dark #4073F2 · light #4073F2 · _window-selection blue is #4D80FF in plan-canvas.ts (Mac #4073F2)_
