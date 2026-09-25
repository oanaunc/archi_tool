# Oanarina Archi Tool — Roadmap

Eight phases take the app from a working MVP to broad parity with AutoCAD, Revit, ArchiCAD/Allplan/Vectorworks, SketchUp and the open-source tools we study (FreeCAD, LibreCAD, Bonsai, SolveSpace, OpenSCAD, BRL-CAD, Sverchok, CAD Sketcher).

- Every feature, with its phase, priority and acceptance criterion, is in [`features.json`](features.json). A readable version is in [`FEATURE-REGISTER.md`](FEATURE-REGISTER.md).
- A phase is **complete** when all of its `must` features are `done` and its exit criteria below pass in CI (`./scripts/test.sh` plus `archi-cli` scripted checks).
- Phases can overlap. `should`/`could` items may move to a later phase without re-planning.
- Area prefixes: APP shell/UI · CMD command line · DRW draw · MOD modify · SEL selection · PRC precision · LAY layers · ANN annotation · BLK blocks · SHT sheets/plotting · BIM building elements · PAR parametric families · DOC documentation/views · M3D 3D modelling · VIS visualization · IO interoperability · ANL analysis · COL collaboration · SCR scripting & AI · SYS system.

## Overview

| Phase | Theme | Main areas | Depends on |
| --- | --- | --- | --- |
| 1 | MVP foundation | APP, CMD, DRW, MOD, SEL, PRC, LAY, BIM (core), IO (.archi/DXF/PDF/SVG/IFC4 export), SCR (console, agent API), SYS | — |
| 2 | Drafting & annotation parity | DRW, MOD, SEL, PRC, LAY, ANN, BLK, SHT, CMD (dynamic input) | 1 |
| 3 | Full BIM & documentation | BIM, PAR, DOC, SHT (sheet sets), ANL (quantities, warnings) | 1, 2 (annotation, sheets) |
| 4 | Advanced modelling | M3D (solids, NURBS, constraint solver, CSG scripting, massing) | 1; 3 for massing → BIM |
| 5 | Rendering & visualization | VIS (materials, real-time and path-traced rendering, animation, AR) | 1 (3D view), 3 (materials), 4 (meshes) |
| 6 | Interoperability & collaboration | IO (DWG, IFC import, glTF/USD/FBX/STEP, point clouds, GIS), COL | 1–4 (all object types exist to map) |
| 7 | Analysis & simulation | ANL (energy, daylight, sun study, structural, clash, cost/QTO) | 3 (BIM data), 5 (sun/sky), 6 (gbXML/IFC) |
| 8 | Automation, AI & platform polish | SCR (visual programming, plugins, AI assistant), APP/SYS polish, localization, accessibility | all previous |

---

## Phase 1 — MVP foundation

**Goal:** a stable native app in which a user (or an AI agent) can draft in 2D with an AutoCAD-style command line, model a simple house with walls, doors, windows and slabs, see it in 3D, and save/exchange it.

**Areas and scope**
- **CMD** — command line with prompts, keywords, aliases, autocomplete, repeat; full coordinate syntax (absolute, relative, polar, direct distance, arithmetic, feet-inches, entity IDs); system variables; `.scr` scripts.
- **DRW / MOD** — core drawing (line, polyline, circle, arc, ellipse, spline, rectangle, polygon, point, text, hatch) and core modify (move, copy, rotate, scale, mirror, stretch, trim, extend, offset, fillet, chamfer, break, join, explode, erase, undo/redo, clipboard).
- **SEL / PRC** — pick, window, crossing, all/last/previous; grips; object snaps, ortho, polar tracking, grid.
- **LAY** — layer manager with on/off, freeze, lock, plot; ACI and true colour; linetypes, lineweights.
- **BIM (core)** — levels, grids, walls (compound types, joins), doors, windows, openings, slabs, simple roofs, stairs, railings, columns, beams, rooms with area, curtain walls, components.
- **VIS / DOC (minimum)** — 2D plan canvas, 3D viewport with orbit, ViewCube and basic visual styles; plan and section views generated from the model.
- **IO** — `.archi` (JSON), DXF read/write, SVG and PDF output, IFC4 export, OBJ/STL/glTF export, CSV schedules, images.
- **SHT** — layouts with viewports, title block, print and PDF export.
- **SCR** — JavaScript console, local JSON-RPC agent server, `archi-cli` headless runner and MCP server.
- **SYS** — autosave and recovery, undo history, signed universal build, offline operation, test suite.

**Dependencies:** none (foundation). The core model, command engine, LINE, UNDO/REDO and coordinate parsing already exist.

**Exit criteria**
- A scripted test draws a 10 × 8 m house (walls, 1 door, 3 windows, slab, roof, room) purely through `archi-cli`, saves `.archi`, reopens it and gets an identical document.
- DXF round-trip of the LibreCAD sample set keeps all entities; exported IFC4 opens in an open IFC viewer with correct spatial structure.
- PDF of a 1:100 plan measures correctly on paper.
- An MCP client can create and query elements end-to-end.
- No crash in a 1-hour monkey test; autosave restores work after a forced quit.

## Phase 2 — Drafting & annotation parity

**Goal:** a 2D drafter can move from AutoCAD LT / LibreCAD and produce complete, correctly scaled construction drawings.

**Areas:** the remaining DRW and MOD commands (all circle/arc/ellipse variants, multilines, arrays, lengthen, overkill, 2D booleans, polyline/spline editing), SEL (quick select, filters, selection cycling, isolate), PRC (object snap tracking, UCS, smart guides), LAY (layer states, filters, viewport overrides), ANN (mtext editor, all dimension types, associative dims, multileaders, tables with formulas, annotative scaling, fields, hatch/gradient), BLK (blocks, attributes, xrefs, content library), SHT (page setups, CTB/STB plot styles, multi-sheet PDF), CMD (dynamic input, transparent commands, calculator), APP (workspaces, shortcut editor, palettes).

**Dependencies:** Phase 1 command engine, geometry services (intersections, offset) and the draw list renderer.

**Exit criteria**
- Every LibreCAD drawing action has an equivalent command (checked against `librecad/src/actions`).
- A reference sheet (plan, dimensions, hatches, leaders, table, title block) plots identically to the AutoCAD reference PDF within 0.1 mm.
- Annotative text/dimensions display at the right size at 1:50 and 1:100 without duplication.
- 100k-entity drawing pans and zooms at 60 fps on an M1.

## Phase 3 — Full BIM & documentation

**Goal:** Revit/ArchiCAD-class building modelling and a complete, model-driven documentation set.

**Areas:** BIM (wall joins/profiles/sweeps, curtain grids, floor/roof/ceiling types, stairs by sketch, ramps, structure, foundations, rooms/areas/zones, colour schemes, site, phases, design options, groups, property sets and classifications), PAR (family editor, type/instance parameters, formulas, type catalogs, nested families), DOC (views with view range, sections, elevations, callouts, drafting views, view templates, visibility/graphics and filters, tags, keynotes, legends, schedules and material takeoffs), SHT (sheet sets, numbering, revisions, views on sheets), ANL (quantity takeoff, model warnings).

**Dependencies:** Phase 1 BIM core and mesh builder; Phase 2 annotation, blocks and sheets.

**Exit criteria**
- The sample two-storey house produces plans, 4 elevations, 2 sections, a wall detail callout, door/window/room schedules and a sheet set, all updating live after a model change.
- Editing a schedule value updates the element; editing a family parameter flexes geometry.
- Phase filter shows existing/demolished/new correctly.
- Quantities from schedules match hand-calculated takeoff within 1 %.

## Phase 4 — Advanced modelling

**Goal:** freeform and precise 3D modelling comparable to SketchUp, AutoCAD 3D, FreeCAD Part/PartDesign/Sketcher and SolveSpace.

**Areas:** M3D (primitives, extrude/push-pull, revolve, loft, sweep, booleans, 3D fillet/chamfer, shell, slice, mesh editing, NURBS surfaces, feature history, 2D/3D sketches with a geometric/dimensional constraint solver, OpenSCAD-like CSG scripting, massing and elements-from-faces), CMD 3D coordinate entry, PRC 3D snaps and dynamic UCS, PAR expressions and spreadsheet-driven parameters.

**Dependencies:** Phase 1 3D viewport and solid model; a B-rep kernel (OpenCascade, LGPL) or equivalent; Phase 3 for mass → BIM conversion.

**Exit criteria**
- Boolean, fillet and shell operations produce valid closed solids on a 50-case regression set.
- The constraint solver solves the SolveSpace and CAD Sketcher example sketches with matching DOF counts and flags over-constraint.
- An OpenSCAD test corpus evaluates to volumes within 0.1 % of OpenSCAD's output.

## Phase 5 — Rendering & visualization

**Goal:** Enscape/Twinmotion-style real-time visualization plus V-Ray-basics path-traced stills, all native on Metal.

**Areas:** VIS (visual styles, section box and planes, cameras and scenes, walk/fly, PBR materials editor and CC0 library, HDRI and physical sky, sun by location/time, IES lights, real-time renderer with shadows/AO/reflections, path tracer with denoiser, walkthrough and keyframe animation, video/panorama export, entourage, USDZ AR, web viewer).

**Dependencies:** Phase 1 mesh builder; Phase 3 materials and lighting fixtures; Phase 4 meshes/UVs for freeform geometry.

**Exit criteria**
- The sample house renders at 60 fps in real-time mode on an M1 with shadows and AO.
- A 1920×1080 path-traced still converges to a denoised image in under 2 minutes on an M1 Pro.
- Sun position matches NOAA within 0.5°; USDZ export opens in AR Quick Look at true scale.

## Phase 6 — Interoperability & collaboration

**Goal:** work with everyone else's files and with other people.

**Areas:** IO (DWG read/write through LibreDWG, DGN/DWF, PDF import and underlay, IFC2x3/IFC4/IFC4.3 import with mapping to native elements, glTF/USD/FBX/STEP/IGES/3DM/SKP/3MF, point clouds E57/LAS, GIS shapefile/GeoJSON/OSM, XLSX), BLK linked models, COL (version history, drawing compare and model diff, Git-friendly projects, markups, BCF 2.1/3.0, eTransmit, iCloud sync, optional co-editing).

**Dependencies:** all object types from Phases 1–4 (so imports have somewhere to map to); Phase 5 materials for glTF/USD fidelity.

**Exit criteria**
- The LibreDWG test corpus opens with no missing entity types that DXF supports.
- IFC round-trip (export → import) preserves GlobalIds, spatial structure, types, materials and Psets on the buildingSMART sample files.
- BCF topics created here open with the right viewpoint in Bonsai and vice versa.
- Compare shows every change between two versions of the sample project.

## Phase 7 — Analysis & simulation

**Goal:** design-stage performance and coordination analysis without leaving the app.

**Areas:** ANL (mass properties, cost estimation and QTO reports, 4D sequencing, sun and shadow studies, solar radiation, daylight factor, energy model generation and EnergyPlus runs, U-values, embodied carbon, structural analytical model and simple frame analysis, clash detection, code checking and IDS validation), IO gbXML.

**Dependencies:** Phase 3 BIM data (rooms, build-ups, quantities); Phase 5 sun/sky; Phase 6 IFC/gbXML exchange.

**Exit criteria**
- U-values of reference build-ups match hand calculation within 1 %.
- Clash detection finds all seeded clashes in the test model with no false positives on touching elements.
- EnergyPlus runs on the sample house and returns annual heating/cooling loads.
- IDS validation results match IfcOpenShell's `ifctester` on the same files.

## Phase 8 — Automation, AI & platform polish

**Goal:** make the app programmable, intelligent and pleasant for everyone.

**Areas:** SCR (script editor, Python bridge, event hooks, Sverchok/Dynamo-style node editor, plugin SDK and manager, Shortcuts/AppleScript, natural-language commands, AI assistant panel, plan generation, auto-dimensioning and tagging, sketch-to-model, generative design, on-device models), CMD (action recorder, batch processing), APP (ribbon customisation, radial menu, settings import/export), SYS (localization, VoiceOver, keyboard-only use, performance hardening), IO point-cloud plane fitting.

**Dependencies:** a stable agent API and command set from Phases 1–7; everything the AI drives must already exist as commands.

**Exit criteria**
- A node graph and an equivalent JS script generate the same parametric façade.
- The AI assistant completes a 20-task benchmark (e.g. "add a 900 mm door in the north wall of the kitchen") with ≥ 90 % success, every change undoable in one step.
- A third-party plugin installs, registers a command and uninstalls cleanly.
- The UI is fully usable with VoiceOver and ships in at least five languages.
