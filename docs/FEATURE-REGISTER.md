# Oanarina Archi Tool — Feature Register

> Generated from `docs/features.json` by `docs/gen_feature_register.py`. **Do not edit by hand** — edit the JSON and re-run the script.

This register lists every feature planned for Oanarina Archi Tool, a free (GPL-3.0) native macOS architecture application covering 2D drafting (AutoCAD / LibreCAD), BIM (Revit, ArchiCAD, Allplan, Vectorworks, Bonsai), 3D modelling (SketchUp, FreeCAD, SolveSpace, OpenSCAD), rendering (Enscape, Twinmotion, V-Ray basics), interoperability, analysis and AI-agent automation. See `ROADMAP.md` for what each phase delivers.

## How status is tracked

- Each feature has a stable ID `AREA-NNN` (never reused; new features are appended to their area).
- `status`: **planned** (not started), **partial** (data model or part of the behaviour exists), **done** (meets its acceptance criterion and has a test).
- `priority`: **must** (required for the phase exit), **should** (expected), **could** (nice to have).
- `phase`: 1–8, see the roadmap. `reference`: product(s) whose behaviour we match.
- A feature moves to **done** only when its `acceptance` criterion is covered by an automated test or a scripted check in `archi-cli`.
- Workflow: update `features.json` in the same change that implements the feature, then run `python3 docs/gen_feature_register.py`.

## Summary

**1158 features** — done: 1115, partial: 39, planned: 4. Priority: must 480, should 419, could 259.

| Area | Prefix | Features | Done | Partial | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [Application Shell & UI](#app--application-shell--ui) | APP | 61 | 61 | 0 | 22 | 32 | 2 | · | · | · | · | 5 |
| [Command Line & Input](#cmd--command-line--input) | CMD | 47 | 47 | 0 | 22 | 16 | 1 | 1 | · | · | · | 7 |
| [2D Drafting](#drw--2d-drafting) | DRW | 89 | 89 | 0 | 18 | 66 | 1 | 3 | · | · | · | 1 |
| [2D Modify & Edit](#mod--2d-modify--edit) | MOD | 66 | 66 | 0 | 25 | 36 | 4 | 1 | · | · | · | · |
| [Selection & Grips](#sel--selection--grips) | SEL | 38 | 38 | 0 | 12 | 21 | 5 | · | · | · | · | · |
| [Precision & Coordinates](#prc--precision--coordinates) | PRC | 41 | 41 | 0 | 16 | 17 | 4 | 4 | · | · | · | · |
| [Layers & Properties](#lay--layers--properties) | LAY | 37 | 37 | 0 | 12 | 18 | 5 | · | · | 2 | · | · |
| [Annotation](#ann--annotation) | ANN | 80 | 80 | 0 | 15 | 51 | 12 | · | · | 1 | · | 1 |
| [Blocks & Content](#blk--blocks--content) | BLK | 42 | 41 | 0 | 7 | 26 | 5 | 1 | · | 3 | · | · |
| [Sheets, Layouts & Plotting](#sht--sheets-layouts--plotting) | SHT | 41 | 41 | 0 | 11 | 13 | 15 | 1 | · | · | · | 1 |
| [BIM Building Elements](#bim--bim-building-elements) | BIM | 131 | 131 | 0 | 34 | 3 | 84 | 3 | 1 | 2 | 4 | · |
| [Parametric Families](#par--parametric-families) | PAR | 36 | 36 | 0 | · | · | 32 | 4 | · | · | · | · |
| [Documentation & Views](#doc--documentation--views) | DOC | 55 | 55 | 0 | 7 | 2 | 44 | · | 1 | · | 1 | · |
| [3D Modelling](#m3d--3d-modelling) | M3D | 107 | 107 | 0 | 5 | 1 | · | 97 | · | 1 | 3 | · |
| [Visualization & Rendering](#vis--visualization--rendering) | VIS | 88 | 87 | 1 | 20 | 3 | 2 | · | 61 | · | 1 | 1 |
| [Interoperability](#io--interoperability) | IO | 66 | 42 | 24 | 12 | 5 | · | · | 1 | 44 | 2 | 2 |
| [Analysis](#anl--analysis) | ANL | 42 | 37 | 5 | 4 | 6 | 3 | 1 | · | 1 | 26 | 1 |
| [Collaboration & Versioning](#col--collaboration--versioning) | COL | 22 | 22 | 0 | · | 1 | · | · | · | 20 | · | 1 |
| [Scripting, Automation & AI](#scr--scripting-automation--ai) | SCR | 35 | 34 | 1 | 6 | 3 | · | · | · | · | · | 26 |
| [System & Platform](#sys--system--platform) | SYS | 34 | 23 | 8 | 18 | 8 | 3 | · | 1 | · | · | 4 |
| **Total** | | **1158** | **1115** | **39** | **266** | **328** | **222** | **116** | **65** | **74** | **37** | **50** |

### Phases

| Phase | Theme | Features | Must |
| --- | --- | --- | --- |
| 1 | MVP foundation | 266 | 263 |
| 2 | Drafting & annotation parity | 328 | 64 |
| 3 | Full BIM & documentation | 222 | 88 |
| 4 | Advanced modelling | 116 | 26 |
| 5 | Rendering & visualization | 65 | 21 |
| 6 | Interoperability & collaboration | 74 | 15 |
| 7 | Analysis & simulation | 37 | 3 |
| 8 | Automation, AI & platform polish | 50 | 0 |

## APP — Application Shell & UI

61 features.


### Window & Workspace

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| APP-001 | Main document window | — | 1 | must | ✅ done |
| APP-002 | Multiple open documents | — | 1 | must | ✅ done |
| APP-003 | Native window tabs | — | 2 | should | ✅ done |
| APP-004 | Full-screen and Split View | — | 2 | should | ✅ done |
| APP-005 | Workspaces | WSCURRENT | 2 | should | ✅ done |
| APP-006 | Save custom workspace | WSSAVE | 2 | could | ✅ done |
| APP-007 | Canvas split views | VPORTS | 2 | should | ✅ done |
| APP-008 | Start screen | — | 2 | should | ✅ done |
| APP-009 | Recent files list | — | 1 | must | ✅ done |
| APP-010 | Document templates | NEW | 1 | must | ✅ done |
| APP-011 | Clean screen mode | CLEANSCREENON | 2 | could | ✅ done |
| APP-012 | File tabs bar | FILETAB | 2 | could | ✅ done |
| APP-013 | Model/Layout tabs | — | 1 | must | ✅ done |

### Ribbon & Toolbars

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| APP-014 | Ribbon with tabs | RIBBON | 1 | must | ✅ done |
| APP-015 | Contextual ribbon tabs | — | 2 | should | ✅ done |
| APP-016 | Customisable ribbon | CUI | 8 | could | ✅ done |
| APP-017 | Quick access toolbar | — | 2 | should | ✅ done |
| APP-018 | Tool tips with extended help | — | 2 | should | ✅ done |
| APP-019 | Menu bar parity | — | 1 | must | ✅ done |
| APP-020 | Touch Bar and trackpad gestures | — | 2 | should | ✅ done |
| APP-021 | Toolbar icons SF Symbols style | — | 2 | should | ✅ done |
| APP-022 | Radial/marking menu | — | 8 | could | ✅ done |
| APP-023 | Shortcut menus | — | 1 | must | ✅ done |

### Palettes & Panels

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| APP-024 | Properties palette | PROPERTIES (PR) | 1 | must | ✅ done |
| APP-025 | Quick properties | QP | 2 | could | ✅ done |
| APP-026 | Layer panel | LAYER (LA) | 1 | must | ✅ done |
| APP-027 | Project browser | — | 1 | must | ✅ done |
| APP-028 | Levels panel | — | 1 | must | ✅ done |
| APP-029 | Materials panel | — | 2 | should | ✅ done |
| APP-030 | Tool palettes | TOOLPALETTES | 3 | should | ✅ done |
| APP-031 | Design center / content browser | ADCENTER | 3 | should | ✅ done |
| APP-032 | Navigator / overview map | NAVIGATOR | 2 | could | ✅ done |
| APP-033 | Object info inspector | LIST | 2 | should | ✅ done |
| APP-034 | Command history panel | — | 1 | must | ✅ done |
| APP-035 | Undo history panel | — | 2 | should | ✅ done |
| APP-036 | Panel layouts saved per workspace | — | 2 | could | ✅ done |
| APP-037 | Selection info panel | SELECTIONINFO | 2 | should | ✅ done |
| APP-038 | Notifications centre | NOTIFICATIONS | 2 | should | ✅ done |

### Status Bar

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| APP-039 | Coordinate readout | — | 1 | must | ✅ done |
| APP-040 | Drafting toggles | — | 1 | must | ✅ done |
| APP-041 | Current level and units display | — | 1 | must | ✅ done |
| APP-042 | Annotation scale selector | CANNOSCALE | 2 | must | ✅ done |
| APP-043 | Isolate / hide objects button | — | 2 | should | ✅ done |
| APP-044 | Progress indicator | — | 1 | must | ✅ done |

### Preferences & Themes

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| APP-045 | Settings window | OPTIONS (OP) | 1 | must | ✅ done |
| APP-046 | Dark and light theme | — | 1 | must | ✅ done |
| APP-047 | Canvas background colours | — | 2 | should | ✅ done |
| APP-048 | Crosshair size and style | CURSORSIZE | 2 | should | ✅ done |
| APP-049 | Units and precision settings | UNITS (UN) | 1 | must | ✅ done |
| APP-050 | File locations settings | — | 2 | should | ✅ done |
| APP-051 | Accent colour customisation | — | 8 | could | ✅ done |
| APP-052 | Import/export settings | — | 8 | could | ✅ done |
| APP-053 | Reset to defaults | — | 2 | should | ✅ done |

### Shortcuts & Help

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| APP-054 | Keyboard shortcut editor | — | 2 | should | ✅ done |
| APP-055 | Default AutoCAD-compatible shortcuts | — | 1 | must | ✅ done |
| APP-056 | Command search (Spotlight style) | — | 2 | should | ✅ done |
| APP-057 | Integrated help browser | HELP (F1) | 1 | must | ✅ done |
| APP-058 | Contextual help | — | 2 | should | ✅ done |
| APP-059 | Tutorials and sample projects | — | 2 | should | ✅ done |
| APP-060 | What's new dialog | WHATSNEW | 8 | could | ✅ done |
| APP-061 | Command reference export | — | 2 | should | ✅ done |

## CMD — Command Line & Input

47 features.


### Command Line

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| CMD-001 | Command line with prompts | — | 1 | must | ✅ done |
| CMD-002 | Command registry with categories | — | 1 | must | ✅ done |
| CMD-003 | Command aliases | ALIASEDIT | 1 | must | ✅ done |
| CMD-004 | Command autocomplete | INPUTSEARCHOPTIONS | 1 | must | ✅ done |
| CMD-005 | Repeat last command | Enter / Space | 1 | must | ✅ done |
| CMD-006 | Keyword options by capital letter | — | 1 | must | ✅ done |
| CMD-007 | Clickable keyword options | — | 2 | should | ✅ done |
| CMD-008 | Command history recall | Up/Down | 1 | must | ✅ done |
| CMD-009 | Transparent commands | 'ZOOM, 'PAN | 2 | should | ✅ done |
| CMD-010 | Cancel with Escape | Esc | 1 | must | ✅ done |
| CMD-011 | Unknown command handling | — | 1 | should | ✅ done |
| CMD-012 | Noun-verb and verb-noun selection | PICKFIRST | 1 | must | ✅ done |
| CMD-013 | Command-line text size and transparency | — | 2 | could | ✅ done |
| CMD-014 | Floating/docked command line | — | 2 | could | ✅ done |
| CMD-015 | Headless command execution | editor.run | 1 | must | ✅ done |
| CMD-016 | Quoted string inputs | — | 1 | must | ✅ done |

### Coordinate Entry

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| CMD-017 | Absolute Cartesian coordinates | x,y | 1 | must | ✅ done |
| CMD-018 | Relative coordinates | @dx,dy | 1 | must | ✅ done |
| CMD-019 | Polar coordinates | d<angle / @d<angle | 1 | must | ✅ done |
| CMD-020 | Direct distance entry | number | 1 | must | ✅ done |
| CMD-021 | Arithmetic expressions in input | — | 1 | must | ✅ done |
| CMD-022 | Feet-inch input | 3'6" | 1 | must | ✅ done |
| CMD-023 | Angle units in input | 45d, 0.5r | 2 | should | ✅ done |
| CMD-024 | Absolute override prefix | #x,y | 1 | should | ✅ done |
| CMD-025 | Entity ID references | #12,#15 | 1 | must | ✅ done |
| CMD-026 | 3D coordinate entry | x,y,z | 4 | must | ✅ done |
| CMD-027 | Point filters | .X .Y .XY .Z | 2 | could | ✅ done |
| CMD-028 | From / temporary reference point | FROM | 2 | should | ✅ done |
| CMD-029 | Mid between two points | M2P | 2 | should | ✅ done |
| CMD-030 | Units-suffixed values | 2.5m, 30cm | 2 | should | ✅ done |
| CMD-031 | Unit expressions in fields | — | 2 | should | ✅ done |

### Dynamic Input

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| CMD-032 | Dynamic input tooltips | DYNMODE | 2 | must | ✅ done |
| CMD-033 | Dimensional input fields | DYNDIM | 2 | must | ✅ done |
| CMD-034 | Pointer input | DYNPICOORDS | 2 | should | ✅ done |
| CMD-035 | Temporary dimensions on selection | — | 3 | should | ✅ done |

### System Variables & Scripts

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| CMD-036 | System variables | SETVAR | 1 | must | ✅ done |
| CMD-037 | System variable monitor | SYSVARMONITOR | 8 | could | ✅ done |
| CMD-038 | Script files (.scr) | SCRIPT (SCR) | 1 | must | ✅ done |
| CMD-039 | Script recording | — | 2 | should | ✅ done |
| CMD-040 | Action recorder | ACTRECORD | 8 | should | ✅ done |
| CMD-041 | Macros in buttons | MACROBUTTON | 8 | could | ✅ done |
| CMD-042 | Command-line calculator | CAL / QUICKCALC | 2 | should | ✅ done |
| CMD-043 | Batch processing | — | 8 | should | ✅ done |
| CMD-044 | DIESEL-like expressions in fields | — | 8 | could | ✅ done |
| CMD-045 | Delay / pause in scripts | DELAY | 8 | could | ✅ done |
| CMD-046 | Resume interrupted script | RSCRIPT, RESUME | 8 | could | ✅ done |
| CMD-047 | Command-line parameters on launch | — | 2 | should | ✅ done |

## DRW — 2D Drafting

89 features.


### Lines

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DRW-001 | Line | LINE (L) | 1 | must | ✅ done |
| DRW-002 | Construction line (xline) | XLINE (XL) | 1 | must | ✅ done |
| DRW-003 | Ray | RAY | 2 | should | ✅ done |
| DRW-004 | Line by angle | LINE Angle | 2 | should | ✅ done |
| DRW-005 | Line at relative angle to entity | — | 2 | could | ✅ done |
| DRW-006 | Horizontal/vertical line | — | 2 | could | ✅ done |
| DRW-007 | Parallel line through point | — | 2 | should | ✅ done |
| DRW-008 | Line from point perpendicular to line | — | 2 | should | ✅ done |
| DRW-009 | Bisector line | — | 2 | could | ✅ done |
| DRW-010 | Tangent line from point to circle | — | 2 | should | ✅ done |
| DRW-011 | Tangent line between two circles | — | 2 | should | ✅ done |
| DRW-012 | Orthogonal tangent line | — | 2 | could | ✅ done |
| DRW-013 | Freehand line | SKETCH | 2 | could | ✅ done |
| DRW-014 | Snake line (relative) | — | 2 | could | ✅ done |
| DRW-015 | Multiline | MLINE (ML) | 2 | should | ✅ done |
| DRW-016 | Multiline styles | MLSTYLE | 2 | should | ✅ done |
| DRW-017 | Double line | DLINE | 2 | should | ✅ done |
| DRW-018 | Centre line | CENTERLINE | 2 | should | ✅ done |
| DRW-019 | Centre mark | CENTERMARK | 2 | should | ✅ done |

### Circles & Arcs

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DRW-020 | Circle centre-radius | CIRCLE (C) | 1 | must | ✅ done |
| DRW-021 | Circle centre-diameter | CIRCLE D | 1 | must | ✅ done |
| DRW-022 | Circle 2 points | CIRCLE 2P | 1 | must | ✅ done |
| DRW-023 | Circle 3 points | CIRCLE 3P | 1 | must | ✅ done |
| DRW-024 | Circle tangent-tangent-radius | CIRCLE TTR | 2 | must | ✅ done |
| DRW-025 | Circle tangent-tangent-tangent | CIRCLE TTT | 2 | should | ✅ done |
| DRW-026 | Circle tangent to 1 entity through 2 points | — | 2 | could | ✅ done |
| DRW-027 | Circle tangent to 2 entities through point | — | 2 | could | ✅ done |
| DRW-028 | Circle 2 points and radius | — | 2 | could | ✅ done |
| DRW-029 | Inscribed circle | — | 2 | could | ✅ done |
| DRW-030 | Circle from arc | — | 2 | could | ✅ done |
| DRW-031 | Arc 3 points | ARC (A) | 1 | must | ✅ done |
| DRW-032 | Arc start-centre-end | ARC SCE | 1 | must | ✅ done |
| DRW-033 | Arc start-centre-angle | ARC SCA | 1 | must | ✅ done |
| DRW-034 | Arc start-centre-length | ARC SCL | 2 | should | ✅ done |
| DRW-035 | Arc start-end-angle | ARC SEA | 2 | should | ✅ done |
| DRW-036 | Arc start-end-radius | ARC SER | 2 | should | ✅ done |
| DRW-037 | Arc start-end-direction | ARC SED | 2 | should | ✅ done |
| DRW-038 | Arc 2 points and height | — | 2 | could | ✅ done |
| DRW-039 | Arc 2 points and length | — | 2 | could | ✅ done |
| DRW-040 | Tangential arc continuation | ARC Continue | 1 | must | ✅ done |
| DRW-041 | Donut | DONUT | 2 | could | ✅ done |

### Ellipses & Curves

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DRW-042 | Ellipse axis-end | ELLIPSE (EL) | 1 | must | ✅ done |
| DRW-043 | Ellipse centre | ELLIPSE C | 1 | must | ✅ done |
| DRW-044 | Elliptical arc | ELLIPSE A | 2 | must | ✅ done |
| DRW-045 | Ellipse by 4 points | — | 2 | could | ✅ done |
| DRW-046 | Ellipse by centre and 3 points | — | 2 | could | ✅ done |
| DRW-047 | Ellipse by foci and point | — | 2 | could | ✅ done |
| DRW-048 | Ellipse inscribed in quadrilateral | ELLIPSEQUAD | 2 | could | ✅ done |
| DRW-049 | Parabola | — | 4 | could | ✅ done |
| DRW-050 | Hyperbola | — | 4 | could | ✅ done |
| DRW-051 | Spline fit points | SPLINE (SPL) | 1 | must | ✅ done |
| DRW-052 | Spline control vertices | SPLINE CV | 2 | must | ✅ done |
| DRW-053 | Spline edit | SPLINEDIT | 2 | should | ✅ done |
| DRW-054 | Blend curve | BLEND | 2 | should | ✅ done |
| DRW-055 | Helix | HELIX | 4 | should | ✅ done |
| DRW-056 | Wipeout | WIPEOUT | 2 | should | ✅ done |

### Polylines & Shapes

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DRW-057 | Polyline | PLINE (PL) | 1 | must | ✅ done |
| DRW-058 | Polyline edit | PEDIT (PE) | 2 | must | ✅ done |
| DRW-059 | Add polyline vertex | — | 2 | should | ✅ done |
| DRW-060 | Delete polyline vertex | — | 2 | should | ✅ done |
| DRW-061 | Append polyline segment | — | 2 | should | ✅ done |
| DRW-062 | Change polyline segment type | — | 2 | should | ✅ done |
| DRW-063 | Arcs to line segments | — | 2 | could | ✅ done |
| DRW-064 | Polyline from segments | — | 2 | should | ✅ done |
| DRW-065 | Equidistant polylines | — | 2 | could | ✅ done |
| DRW-066 | Rectangle | RECTANG (REC) | 1 | must | ✅ done |
| DRW-067 | Rectangle by 3 points | — | 2 | should | ✅ done |
| DRW-068 | Rectangle from centre | — | 2 | should | ✅ done |
| DRW-069 | Polygon | POLYGON (POL) | 1 | must | ✅ done |
| DRW-070 | Polygon by side-side | — | 2 | could | ✅ done |
| DRW-071 | Star | — | 2 | could | ✅ done |
| DRW-072 | Boundary | BOUNDARY (BO) | 2 | must | ✅ done |
| DRW-073 | Region | REGION | 2 | should | ✅ done |
| DRW-074 | Bounding box | — | 2 | could | ✅ done |
| DRW-075 | Solid fill 2D | SOLID (SO) | 2 | could | ✅ done |
| DRW-076 | Trace | TRACE | 8 | could | ✅ done |

### Points & Division

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DRW-077 | Point | POINT (PO) | 1 | must | ✅ done |
| DRW-078 | Point style | PTYPE | 2 | should | ✅ done |
| DRW-079 | Divide | DIVIDE (DIV) | 2 | must | ✅ done |
| DRW-080 | Measure | MEASURE (ME) | 2 | must | ✅ done |
| DRW-081 | Points on line | — | 2 | could | ✅ done |
| DRW-082 | Points lattice | — | 2 | could | ✅ done |
| DRW-083 | Slice/divide by lines | — | 2 | could | ✅ done |

### Raster & Misc

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DRW-084 | Image insertion | IMAGEATTACH | 1 | must | ✅ done |
| DRW-085 | Image clip | IMAGECLIP | 2 | should | ✅ done |
| DRW-086 | Image adjust | IMAGEADJUST | 2 | could | ✅ done |
| DRW-087 | GD&T feature control frame | TOLERANCE | 2 | could | ✅ done |
| DRW-088 | Revision stamp/north arrow symbols | — | 2 | should | ✅ done |
| DRW-089 | Scale bar | — | 3 | should | ✅ done |

## MOD — 2D Modify & Edit

66 features.


### Edit

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| MOD-001 | Undo | UNDO (U) | 1 | must | ✅ done |
| MOD-002 | Redo | REDO | 1 | must | ✅ done |
| MOD-003 | Undo marks and groups | UNDO Mark/Back/BEgin/End | 2 | should | ✅ done |
| MOD-004 | Multiple undo with count | UNDO n | 2 | should | ✅ done |
| MOD-005 | Cut | CUTCLIP (Cmd+X) | 1 | must | ✅ done |
| MOD-006 | Copy to clipboard | COPYCLIP (Cmd+C) | 1 | must | ✅ done |
| MOD-007 | Copy with base point | COPYBASE | 2 | should | ✅ done |
| MOD-008 | Paste | PASTECLIP (Cmd+V) | 1 | must | ✅ done |
| MOD-009 | Paste to original coordinates | PASTEORIG | 1 | must | ✅ done |
| MOD-010 | Paste as block | PASTEBLOCK | 2 | could | ✅ done |
| MOD-011 | Paste to points | — | 2 | could | ✅ done |
| MOD-012 | Paste aligned to levels | — | 3 | must | ✅ done |
| MOD-013 | Erase | ERASE (E / Delete) | 1 | must | ✅ done |
| MOD-014 | Oops | OOPS | 2 | could | ✅ done |
| MOD-015 | Match properties | MATCHPROP (MA) | 2 | must | ✅ done |
| MOD-016 | Draw order | DRAWORDER (DR) | 2 | must | ✅ done |
| MOD-017 | Text to front | TEXTTOFRONT | 2 | could | ✅ done |

### Transform

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| MOD-018 | Move | MOVE (M) | 1 | must | ✅ done |
| MOD-019 | Copy | COPY (CO / CP) | 1 | must | ✅ done |
| MOD-020 | Rotate | ROTATE (RO) | 1 | must | ✅ done |
| MOD-021 | Scale | SCALE (SC) | 1 | must | ✅ done |
| MOD-022 | Mirror | MIRROR (MI) | 1 | must | ✅ done |
| MOD-023 | Stretch | STRETCH (S) | 1 | must | ✅ done |
| MOD-024 | Align | ALIGN (AL) | 2 | must | ✅ done |
| MOD-025 | Align reference | — | 2 | could | ✅ done |
| MOD-026 | Move and rotate | — | 2 | could | ✅ done |
| MOD-027 | Rotate twice | — | 2 | could | ✅ done |
| MOD-028 | Nudge | Arrow keys | 2 | should | ✅ done |
| MOD-029 | Rotate 90° shortcut | Space while dragging | 3 | should | ✅ done |

### Arrays

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| MOD-030 | Rectangular array | ARRAYRECT | 2 | must | ✅ done |
| MOD-031 | Polar array | ARRAYPOLAR | 2 | must | ✅ done |
| MOD-032 | Path array | ARRAYPATH | 2 | must | ✅ done |
| MOD-033 | Array edit | ARRAYEDIT | 2 | should | ✅ done |
| MOD-034 | Classic array dialog | ARRAYCLASSIC | 2 | could | ✅ done |
| MOD-035 | Linear array (BIM) | AR | 3 | should | ✅ done |

### Trim & Shape

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| MOD-036 | Trim | TRIM (TR) | 1 | must | ✅ done |
| MOD-037 | Extend | EXTEND (EX) | 1 | must | ✅ done |
| MOD-038 | Trim/extend by amount | — | 2 | should | ✅ done |
| MOD-039 | Lengthen | LENGTHEN (LEN) | 2 | must | ✅ done |
| MOD-040 | Offset | OFFSET (O) | 1 | must | ✅ done |
| MOD-041 | Fillet | FILLET (F) | 1 | must | ✅ done |
| MOD-042 | Chamfer | CHAMFER (CHA) | 1 | must | ✅ done |
| MOD-043 | Break | BREAK (BR) | 1 | must | ✅ done |
| MOD-044 | Break at point | BREAKATPOINT | 1 | must | ✅ done |
| MOD-045 | Break/divide at intersections | — | 2 | should | ✅ done |
| MOD-046 | Line gap | — | 2 | could | ✅ done |
| MOD-047 | Join | JOIN (J) | 1 | must | ✅ done |
| MOD-048 | Explode | EXPLODE (X) | 1 | must | ✅ done |
| MOD-049 | Explode text to letters/lines | TXTEXP | 2 | could | ✅ done |
| MOD-050 | Reverse | REVERSE | 2 | should | ✅ done |
| MOD-051 | Overkill | OVERKILL | 2 | should | ✅ done |
| MOD-052 | Flatten | FLATTEN | 4 | should | ✅ done |
| MOD-053 | Convert to polyline/spline | — | 2 | should | ✅ done |
| MOD-054 | Spline from polyline | — | 2 | could | ✅ done |
| MOD-055 | Weld/merge connected curves | — | 2 | could | ✅ done |
| MOD-056 | Clip with polygon | — | 2 | could | ✅ done |
| MOD-057 | 2D Boolean union/subtract/intersect | — | 2 | should | ✅ done |

### Object Editing

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| MOD-058 | Edit text | TEXTEDIT (ED) | 1 | must | ✅ done |
| MOD-059 | Change properties | CHANGE / CHPROP | 1 | must | ✅ done |
| MOD-060 | Edit hatch | HATCHEDIT | 2 | must | ✅ done |
| MOD-061 | Edit attributes | EATTEDIT | 2 | must | ✅ done |
| MOD-062 | Reset block | RESETBLOCK | 3 | could | ✅ done |
| MOD-063 | Double-click editing | DBLCLKEDIT | 1 | must | ✅ done |
| MOD-064 | Pen/attribute apply | — | 2 | should | ✅ done |
| MOD-065 | Sync entity to by-layer | SETBYLAYER | 2 | should | ✅ done |
| MOD-066 | Revert direction of text reading | — | 2 | could | ✅ done |

## SEL — Selection & Grips

38 features.


### Selection Methods

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SEL-001 | Pick selection | — | 1 | must | ✅ done |
| SEL-002 | Window selection | W | 1 | must | ✅ done |
| SEL-003 | Crossing selection | C | 1 | must | ✅ done |
| SEL-004 | Window polygon | WP | 2 | should | ✅ done |
| SEL-005 | Crossing polygon | CP | 2 | should | ✅ done |
| SEL-006 | Fence selection | F | 2 | should | ✅ done |
| SEL-007 | Lasso selection | — | 2 | should | ✅ done |
| SEL-008 | Select all | Cmd+A / ALL | 1 | must | ✅ done |
| SEL-009 | Select last | L | 1 | must | ✅ done |
| SEL-010 | Select previous | P | 1 | must | ✅ done |
| SEL-011 | Add/remove from selection | Shift | 1 | must | ✅ done |
| SEL-012 | Invert selection | — | 2 | should | ✅ done |
| SEL-013 | Deselect all | Esc | 1 | must | ✅ done |
| SEL-014 | Select by entity ID | #id | 1 | must | ✅ done |
| SEL-015 | Select contour | — | 2 | should | ✅ done |
| SEL-016 | Select intersected | — | 2 | could | ✅ done |
| SEL-017 | Select by layer | — | 2 | should | ✅ done |
| SEL-018 | Cycle overlapping objects | SELECTIONCYCLING | 2 | should | ✅ done |
| SEL-019 | Selection preview highlight | SELECTIONPREVIEW | 1 | must | ✅ done |
| SEL-020 | Select similar | SELECTSIMILAR | 2 | must | ✅ done |
| SEL-021 | Select all instances | — | 3 | must | ✅ done |
| SEL-022 | Select linked/chained BIM elements | Tab | 3 | should | ✅ done |
| SEL-023 | Selection sets (named) | — | 2 | should | ✅ done |

### Filters

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SEL-024 | Quick select | QSELECT | 2 | must | ✅ done |
| SEL-025 | Filter dialog | FILTER | 2 | should | ✅ done |
| SEL-026 | Selection filter by category | — | 2 | must | ✅ done |
| SEL-027 | Select by property value | FILTER | 3 | should | ✅ done |
| SEL-028 | Search query language | — | 3 | should | ✅ done |
| SEL-029 | Isolate objects | ISOLATEOBJECTS | 2 | must | ✅ done |
| SEL-030 | Hide objects | HIDEOBJECTS | 2 | must | ✅ done |
| SEL-031 | Unisolate / end isolation | UNISOLATEOBJECTS | 2 | must | ✅ done |

### Grips

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SEL-032 | Grip display | GRIPS | 1 | must | ✅ done |
| SEL-033 | Grip stretch | — | 1 | must | ✅ done |
| SEL-034 | Grip modes cycle | Space | 2 | should | ✅ done |
| SEL-035 | Multi-functional grips | — | 2 | should | ✅ done |
| SEL-036 | Parametric grips on BIM elements | — | 3 | must | ✅ done |
| SEL-037 | Grips on dimensions and text | — | 2 | must | ✅ done |
| SEL-038 | Hot-grip typed values | — | 2 | should | ✅ done |

## PRC — Precision & Coordinates

41 features.


### Object Snaps

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| PRC-001 | Endpoint snap | END | 1 | must | ✅ done |
| PRC-002 | Midpoint snap | MID | 1 | must | ✅ done |
| PRC-003 | Centre snap | CEN | 1 | must | ✅ done |
| PRC-004 | Geometric centre snap | GCEN | 2 | should | ✅ done |
| PRC-005 | Node snap | NOD | 1 | must | ✅ done |
| PRC-006 | Quadrant snap | QUA | 1 | must | ✅ done |
| PRC-007 | Intersection snap | INT | 1 | must | ✅ done |
| PRC-008 | Apparent intersection snap | APPINT | 4 | could | ✅ done |
| PRC-009 | Extension snap | EXT | 2 | should | ✅ done |
| PRC-010 | Insertion snap | INS | 1 | must | ✅ done |
| PRC-011 | Perpendicular snap | PER | 1 | must | ✅ done |
| PRC-012 | Tangent snap | TAN | 1 | must | ✅ done |
| PRC-013 | Nearest snap | NEA | 1 | must | ✅ done |
| PRC-014 | Parallel snap | PAR | 2 | should | ✅ done |
| PRC-015 | Grid snap | — | 1 | must | ✅ done |
| PRC-016 | Snap to BIM references | — | 3 | must | ✅ done |
| PRC-017 | Manual intersection snap | INTOF | 2 | could | ✅ done |
| PRC-018 | Manual middle snap | M2P | 2 | could | ✅ done |
| PRC-019 | Snap overrides | Shift+right-click | 1 | must | ✅ done |
| PRC-020 | Running snaps settings | OSNAP (OS) | 1 | must | ✅ done |
| PRC-021 | Snap restriction (horizontal/vertical) | RH / RV | 2 | could | ✅ done |
| PRC-022 | 3D object snaps | 3DOSNAP | 4 | should | ✅ done |

### Tracking & Constraints

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| PRC-023 | Ortho mode | ORTHO (F8) | 1 | must | ✅ done |
| PRC-024 | Polar tracking | POLAR (F10) | 1 | must | ✅ done |
| PRC-025 | Object snap tracking | OTRACK (F11) | 2 | must | ✅ done |
| PRC-026 | Temporary track point | TT | 2 | should | ✅ done |
| PRC-027 | Smart alignment guides | — | 2 | should | ✅ done |
| PRC-028 | Axis locking by arrow keys | — | 4 | should | ✅ done |
| PRC-029 | Relative zero | RELZERO | 2 | should | ✅ done |
| PRC-030 | Snap spacing | SNAP (F9) | 2 | should | ✅ done |
| PRC-031 | Grid display | GRID (F7) | 1 | must | ✅ done |
| PRC-032 | Isometric drafting | ISODRAFT | 2 | could | ✅ done |

### UCS & Workplanes

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| PRC-033 | User coordinate system | UCS | 2 | must | ✅ done |
| PRC-034 | UCS icon | UCSICON | 2 | should | ✅ done |
| PRC-035 | Named UCS manager | UCSMAN | 2 | should | ✅ done |
| PRC-036 | Dynamic UCS | DUCS | 4 | should | ✅ done |
| PRC-037 | Plan view of UCS | PLAN | 2 | should | ✅ done |
| PRC-038 | Workplanes/reference planes | RP | 3 | must | ✅ done |
| PRC-039 | Rotated plan / north orientation | — | 3 | must | ✅ done |
| PRC-040 | Survey point and project base point | — | 3 | must | ✅ done |
| PRC-041 | Measurement units conversion | UNITS | 2 | should | ✅ done |

## LAY — Layers & Properties

37 features.


### Layers

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| LAY-001 | Layer data model | — | 1 | must | ✅ done |
| LAY-002 | Layer manager | LAYER (LA) | 1 | must | ✅ done |
| LAY-003 | Layer on/off | LAYON/LAYOFF | 1 | must | ✅ done |
| LAY-004 | Layer freeze/thaw | LAYFRZ/LAYTHW | 1 | must | ✅ done |
| LAY-005 | Layer lock/unlock | LAYLCK/LAYULK | 1 | must | ✅ done |
| LAY-006 | Layer plot toggle | — | 1 | must | ✅ done |
| LAY-007 | Make object's layer current | LAYMCUR | 2 | should | ✅ done |
| LAY-008 | Layer isolate/unisolate | LAYISO/LAYUNISO | 2 | should | ✅ done |
| LAY-009 | Layer walk | LAYWALK | 2 | could | ✅ done |
| LAY-010 | Layer merge | LAYMRG | 2 | should | ✅ done |
| LAY-011 | Layer delete with contents | LAYDEL | 2 | should | ✅ done |
| LAY-012 | Change to current layer | LAYCUR | 2 | should | ✅ done |
| LAY-013 | Layer filters | — | 2 | should | ✅ done |
| LAY-014 | Layer states | LAYERSTATE | 2 | must | ✅ done |
| LAY-015 | Per-viewport layer overrides | VPLAYER | 2 | must | ✅ done |
| LAY-016 | Layer translator/standards | LAYTRANS | 6 | should | ✅ done |
| LAY-017 | Layer transparency | — | 2 | should | ✅ done |
| LAY-018 | Layer descriptions | LAYDESC | 2 | could | ✅ done |
| LAY-019 | Layer tree/hierarchy | — | 2 | should | ✅ done |
| LAY-020 | New layer notification | LAYERNOTIFY | 6 | could | ✅ done |

### Linetypes & Lineweights

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| LAY-021 | Linetype library | LINETYPE (LT) | 1 | must | ✅ done |
| LAY-022 | Complex linetypes | — | 2 | should | ✅ done |
| LAY-023 | Global linetype scale | LTSCALE | 1 | must | ✅ done |
| LAY-024 | Object linetype scale | CELTSCALE | 2 | should | ✅ done |
| LAY-025 | Paper-space linetype scaling | PSLTSCALE | 2 | must | ✅ done |
| LAY-026 | Lineweights | LWEIGHT | 1 | must | ✅ done |
| LAY-027 | Lineweight display scaling | — | 2 | should | ✅ done |

### Colours & Transparency

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| LAY-028 | ACI colours | COLOR | 1 | must | ✅ done |
| LAY-029 | True colour RGB | — | 1 | must | ✅ done |
| LAY-030 | Colour books | COLORBOOK | 2 | could | ✅ done |
| LAY-031 | ByLayer / ByBlock resolution | — | 1 | must | ✅ done |
| LAY-032 | Object transparency | TRANSPARENCY | 2 | should | ✅ done |
| LAY-033 | Object styles (BIM) | OBJECTSTYLES | 3 | must | ✅ done |
| LAY-034 | Line styles (BIM) | LINESTYLES | 3 | must | ✅ done |
| LAY-035 | Lineweight tables by scale | — | 3 | should | ✅ done |
| LAY-036 | Pen sets | — | 3 | could | ✅ done |
| LAY-037 | Graphic overrides by filter | — | 3 | must | ✅ done |

## ANN — Annotation

80 features.


### Text

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANN-001 | Single-line text | TEXT (DT) | 1 | must | ✅ done |
| ANN-002 | Multiline text | MTEXT (T) | 1 | must | ✅ done |
| ANN-003 | In-place text editor | — | 2 | must | ✅ done |
| ANN-004 | Text styles | STYLE (ST) | 1 | must | ✅ done |
| ANN-005 | Bullets and numbering | TEXTLIST | 2 | should | ✅ done |
| ANN-006 | Columns in mtext | MTEXTCOLUMNS | 2 | could | ✅ done |
| ANN-007 | Stacked fractions | AUTOSTACK | 2 | should | ✅ done |
| ANN-008 | Special symbols | %%d %%c %%p | 1 | must | ✅ done |
| ANN-009 | Spell check | SPELL (SP) | 2 | should | ✅ done |
| ANN-010 | Find and replace | FIND | 2 | must | ✅ done |
| ANN-011 | Text justify and align | JUSTIFYTEXT, TEXTALIGN | 2 | should | ✅ done |
| ANN-012 | Scale text | SCALETEXT | 2 | could | ✅ done |
| ANN-013 | Text background mask | — | 2 | should | ✅ done |
| ANN-014 | Arc-aligned text | ARCTEXT | 2 | could | ✅ done |
| ANN-015 | Convert text to mtext | TXT2MTXT | 2 | could | ✅ done |
| ANN-016 | TrueType and SHX-like fonts | — | 1 | must | ✅ done |
| ANN-017 | Text height by annotation scale | — | 2 | must | ✅ done |

### Dimensions

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANN-018 | Linear dimension | DIMLINEAR (DLI) | 1 | must | ✅ done |
| ANN-019 | Aligned dimension | DIMALIGNED (DAL) | 1 | must | ✅ done |
| ANN-020 | Angular dimension | DIMANGULAR (DAN) | 2 | must | ✅ done |
| ANN-021 | Radius dimension | DIMRADIUS (DRA) | 1 | must | ✅ done |
| ANN-022 | Diameter dimension | DIMDIAMETER (DDI) | 1 | must | ✅ done |
| ANN-023 | Jogged radius | DIMJOGGED | 2 | could | ✅ done |
| ANN-024 | Arc length dimension | DIMARC | 2 | should | ✅ done |
| ANN-025 | Ordinate dimension | DIMORDINATE (DOR) | 2 | should | ✅ done |
| ANN-026 | Ordinate re-base | — | 2 | could | ✅ done |
| ANN-027 | Baseline dimension | DIMBASELINE (DBA) | 2 | must | ✅ done |
| ANN-028 | Continued dimension | DIMCONTINUE (DCO) | 1 | must | ✅ done |
| ANN-029 | Quick dimension | QDIM | 2 | must | ✅ done |
| ANN-030 | Smart dimension | DIM | 2 | should | ✅ done |
| ANN-031 | Dimension styles | DIMSTYLE (D) | 1 | must | ✅ done |
| ANN-032 | Dimension style overrides | — | 2 | should | ✅ done |
| ANN-033 | Apply dimension style | — | 2 | should | ✅ done |
| ANN-034 | Dimension space and break | DIMSPACE, DIMBREAK | 2 | could | ✅ done |
| ANN-035 | Dimension jog line | DIMJOGLINE | 2 | could | ✅ done |
| ANN-036 | Inspection dimension | DIMINSPECT | 8 | could | ✅ done |
| ANN-037 | Associative dimensions | DIMREASSOCIATE | 2 | must | ✅ done |
| ANN-038 | Regenerate dimensions | — | 2 | should | ✅ done |
| ANN-039 | Alternate units | DIMALTUNITS | 2 | should | ✅ done |
| ANN-040 | Tolerances in dimensions | DIMTOLERANCE | 2 | could | ✅ done |
| ANN-041 | Text override with <> | — | 2 | should | ✅ done |
| ANN-042 | Wall/opening dimension chains (BIM) | — | 3 | must | ✅ done |
| ANN-043 | Spot elevation | — | 3 | must | ✅ done |
| ANN-044 | Spot coordinate | — | 3 | should | ✅ done |
| ANN-045 | Spot slope | — | 3 | should | ✅ done |
| ANN-046 | Equality constraint dimensions (EQ) | — | 3 | should | ✅ done |

### Leaders & Symbols

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANN-047 | Multileader | MLEADER (MLD) | 2 | must | ✅ done |
| ANN-048 | Multileader styles | MLEADERSTYLE | 2 | should | ✅ done |
| ANN-049 | Simple leader | LEADER | 1 | must | ✅ done |
| ANN-050 | Align/collect multileaders | MLEADERALIGN, MLEADERCOLLECT | 2 | could | ✅ done |
| ANN-051 | Revision cloud | REVCLOUD | 2 | must | ✅ done |
| ANN-052 | Revision schedule link | — | 3 | should | ✅ done |
| ANN-053 | Section/elevation/detail symbols (2D) | — | 2 | should | ✅ done |
| ANN-054 | North arrow | — | 3 | should | ✅ done |
| ANN-055 | Break line symbol | BREAKLINE | 2 | could | ✅ done |
| ANN-056 | Centerlines associative | — | 2 | should | ✅ done |

### Tables

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANN-057 | Table object | TABLE | 2 | must | ✅ done |
| ANN-058 | Table styles | TABLESTYLE | 2 | should | ✅ done |
| ANN-059 | Table formulas | — | 2 | should | ✅ done |
| ANN-060 | Table from CSV/XLSX | — | 6 | should | ✅ done |
| ANN-061 | Data extraction to table | DATAEXTRACTION | 3 | should | ✅ done |

### Hatching

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANN-062 | Hatch | HATCH (H) | 1 | must | ✅ done |
| ANN-063 | Gradient fill | GRADIENT | 2 | should | ✅ done |
| ANN-064 | Solid fill | — | 1 | must | ✅ done |
| ANN-065 | Pattern library (ISO/ANSI/AR) | HATCH | 1 | must | ✅ done |
| ANN-066 | Custom .pat import | — | 2 | should | ✅ done |
| ANN-067 | Associative hatch | — | 2 | must | ✅ done |
| ANN-068 | Hatch origin and alignment | — | 2 | should | ✅ done |
| ANN-069 | Separate hatches | — | 2 | could | ✅ done |
| ANN-070 | Recreate/generate hatch boundary | HATCHGENERATEBOUNDARY | 2 | could | ✅ done |
| ANN-071 | Model (real-size) patterns | — | 3 | must | ✅ done |
| ANN-072 | Fill patterns for materials | — | 3 | must | ✅ done |
| ANN-073 | Filled regions and masking regions | — | 3 | must | ✅ done |
| ANN-074 | Hatch background colour | — | 2 | could | ✅ done |

### Annotative Scaling & Fields

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANN-075 | Annotative objects | ANNOTATIVE | 2 | must | ✅ done |
| ANN-076 | Annotation scale list | SCALELISTEDIT | 2 | must | ✅ done |
| ANN-077 | Add/remove object scales | OBJECTSCALE | 2 | should | ✅ done |
| ANN-078 | Fields | FIELD | 2 | must | ✅ done |
| ANN-079 | Update fields | UPDATEFIELD | 2 | should | ✅ done |
| ANN-080 | Text-linked parameters in tags | — | 3 | must | ✅ done |

## BLK — Blocks & Content

42 features.


### Blocks

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BLK-001 | Block definition | BLOCK (B) | 1 | must | ✅ done |
| BLK-002 | Insert block | INSERT (I) | 1 | must | ✅ done |
| BLK-003 | Write block to file | WBLOCK (W) | 2 | should | ✅ done |
| BLK-004 | Block editor | BEDIT (BE) | 2 | must | ✅ done |
| BLK-005 | Refedit in place | REFEDIT | 2 | should | ✅ done |
| BLK-006 | Nested blocks | — | 1 | must | ✅ done |
| BLK-007 | Block library panel | — | 2 | must | ✅ done |
| BLK-008 | Block base point | BASE | 2 | could | ✅ done |
| BLK-009 | Purge unused | PURGE (PU) | 1 | must | ✅ done |
| BLK-010 | Rename objects | RENAME (REN) | 2 | should | ✅ done |
| BLK-011 | Replace block | BLOCKREPLACE | 2 | should | ✅ done |
| BLK-012 | Redefine block from file | — | 2 | should | ✅ done |
| BLK-013 | Block count | BCOUNT | 2 | should | ✅ done |
| BLK-014 | Explode block | EXPLODE | 1 | must | ✅ done |
| BLK-015 | Groups | GROUP (G) | 1 | must | ✅ done |
| BLK-016 | Ungroup | UNGROUP | 1 | must | ✅ done |

### Attributes

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BLK-017 | Attribute definition | ATTDEF (ATT) | 2 | must | ✅ done |
| BLK-018 | Attribute edit | ATTEDIT | 2 | must | ✅ done |
| BLK-019 | Block attribute manager | BATTMAN | 2 | should | ✅ done |
| BLK-020 | Attribute sync | ATTSYNC | 2 | should | ✅ done |
| BLK-021 | Attribute extraction | ATTEXT / DATAEXTRACTION | 2 | should | ✅ done |

### Dynamic Blocks

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BLK-022 | Dynamic block parameters | BPARAMETER | 3 | should | ✅ done |
| BLK-023 | Dynamic block actions | BACTION | 3 | should | ✅ done |
| BLK-024 | Visibility states | — | 3 | should | ✅ done |
| BLK-025 | Lookup tables | BTABLE | 3 | could | ✅ done |
| BLK-026 | Block properties table | BTABLE | 3 | could | ✅ done |
| BLK-027 | Parametric block constraints | — | 4 | could | ✅ done |

### External References

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BLK-028 | External reference attach | XATTACH / XREF | 2 | must | ✅ done |
| BLK-029 | Overlay vs attach | — | 2 | should | ✅ done |
| BLK-030 | Xref manager | EXTERNALREFERENCES | 2 | must | ✅ done |
| BLK-031 | Xref clip | XCLIP | 2 | should | ✅ done |
| BLK-032 | Bind xrefs | XBIND | 2 | could | ✅ done |
| BLK-033 | Xref layer control | — | 2 | must | ✅ done |
| BLK-034 | Change notification | — | 2 | should | ✅ done |
| BLK-035 | Linked BIM models | RVTLINK | 6 | must | ✅ done |
| BLK-036 | Copy/monitor from links | — | 6 | could | ✅ done |

### Content Library

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BLK-037 | Bundled block library | — | 2 | must | ✅ done |
| BLK-038 | Content browser search | — | 2 | should | ✅ done |
| BLK-039 | User library folders | — | 2 | should | ✅ done |
| BLK-040 | Online open library | — | 6 | could | planned |
| BLK-041 | Favourites and recents | — | 2 | could | ✅ done |
| BLK-042 | Library of symbol-based annotation | — | 2 | should | ✅ done |

## SHT — Sheets, Layouts & Plotting

41 features.


### Layouts & Viewports

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SHT-001 | Layouts (paper space) | LAYOUT | 1 | must | ✅ done |
| SHT-002 | Paper sizes | — | 1 | must | ✅ done |
| SHT-003 | Rectangular viewport | MVIEW (MV) | 1 | must | ✅ done |
| SHT-004 | Polygonal/object viewport | MVIEW Polygonal/Object | 2 | should | ✅ done |
| SHT-005 | Viewport scale | — | 1 | must | ✅ done |
| SHT-006 | Lock viewport | — | 2 | must | ✅ done |
| SHT-007 | Maximise viewport | VPMAX | 2 | should | ✅ done |
| SHT-008 | Viewport clip | VPCLIP | 2 | could | ✅ done |
| SHT-009 | Align views on sheet | MVSETUP | 3 | should | ✅ done |
| SHT-010 | Views on sheets (BIM) | — | 3 | must | ✅ done |
| SHT-011 | Guide grids on sheets | — | 3 | could | ✅ done |
| SHT-012 | Viewport titles | — | 3 | must | ✅ done |
| SHT-013 | Title blocks | — | 1 | must | ✅ done |
| SHT-014 | Title block editor | — | 3 | should | ✅ done |
| SHT-015 | Page setup manager | PAGESETUP | 2 | must | ✅ done |

### Sheet Sets

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SHT-016 | Sheet set manager | SHEETSET | 3 | must | ✅ done |
| SHT-017 | Sheet numbering and renumbering | — | 3 | must | ✅ done |
| SHT-018 | Sheet list/index | — | 3 | must | ✅ done |
| SHT-019 | Revisions table | — | 3 | should | ✅ done |
| SHT-020 | Placeholder sheets | — | 3 | could | ✅ done |
| SHT-021 | Sheet properties custom fields | — | 3 | should | ✅ done |

### Plotting & Output

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SHT-022 | Plot dialog | PLOT (Cmd+P) | 1 | must | ✅ done |
| SHT-023 | Print preview | PREVIEW | 1 | must | ✅ done |
| SHT-024 | PDF export | EXPORTPDF | 1 | must | ✅ done |
| SHT-025 | PDF with layers | — | 2 | should | ✅ done |
| SHT-026 | Multi-sheet PDF | — | 2 | must | ✅ done |
| SHT-027 | Batch plot / publish | PUBLISH | 3 | must | ✅ done |
| SHT-028 | Plot area options | — | 1 | must | ✅ done |
| SHT-029 | Plot scale and fit | — | 1 | must | ✅ done |
| SHT-030 | Plot styles colour-dependent (CTB) | — | 2 | must | ✅ done |
| SHT-031 | Plot styles named (STB) | — | 2 | should | ✅ done |
| SHT-032 | Plot style editor | STYLESMANAGER | 2 | should | ✅ done |
| SHT-033 | Monochrome/greyscale plotting | — | 1 | must | ✅ done |
| SHT-034 | Plot stamp | PLOTSTAMP | 2 | could | ✅ done |
| SHT-035 | Raster export (PNG/JPEG/TIFF) | PNGOUT | 2 | should | ✅ done |
| SHT-036 | SVG export of layouts | — | 2 | should | ✅ done |
| SHT-037 | Plot log | — | 3 | could | ✅ done |
| SHT-038 | Print to large format/plotter | — | 3 | could | ✅ done |
| SHT-039 | Hidden-line plotting of 3D viewports | SHADEPLOT | 4 | should | ✅ done |
| SHT-040 | Page setup import | PSETUPIN | 3 | could | ✅ done |
| SHT-041 | Per-sheet section print graphics | SECTIONSTYLE / SECSTYLE / SSTYLE | 8 | should | ✅ done |

## BIM — BIM Building Elements

131 features.


### Levels & Grids

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-001 | Levels data model | — | 1 | must | ✅ done |
| BIM-002 | Level command | LEVEL | 1 | must | ✅ done |
| BIM-003 | Story settings | — | 3 | should | ✅ done |
| BIM-004 | Level heads and extents | — | 3 | must | ✅ done |
| BIM-005 | Structural grids | GRID | 1 | must | ✅ done |
| BIM-006 | Radial grids | RADIALGRID | 3 | should | ✅ done |
| BIM-007 | Grid system generator | GRIDSYSTEM | 3 | should | ✅ done |
| BIM-008 | Scope boxes | — | 3 | could | ✅ done |

### Walls

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-009 | Wall data model | — | 1 | must | ✅ done |
| BIM-010 | Wall tool | WALL | 1 | must | ✅ done |
| BIM-011 | Walls from lines/polylines | WALL Object | 1 | must | ✅ done |
| BIM-012 | Rectangle/polygon walls | — | 2 | should | ✅ done |
| BIM-013 | Arc/curved walls | — | 2 | must | ✅ done |
| BIM-014 | Wall types (compound) | WALLTYPE | 1 | must | ✅ done |
| BIM-015 | Wall type editor | — | 3 | must | ✅ done |
| BIM-016 | Wall joins | — | 1 | must | ✅ done |
| BIM-017 | Edit wall joins | — | 3 | should | ✅ done |
| BIM-018 | Wall top/base constraints | — | 3 | must | ✅ done |
| BIM-019 | Attach wall to roof/slab | — | 3 | must | ✅ done |
| BIM-020 | Wall profile editing | — | 3 | should | ✅ done |
| BIM-021 | Wall sweeps and reveals | — | 3 | should | ✅ done |
| BIM-022 | Stacked walls | — | 3 | could | ✅ done |
| BIM-023 | Slanted/tapered walls | — | 3 | should | ✅ done |
| BIM-024 | Split wall | SPLITWALL | 3 | must | ✅ done |
| BIM-025 | Wall flip | WALLFLIP | 1 | must | ✅ done |
| BIM-026 | Wall openings (plain) | WALLOPENING | 1 | must | ✅ done |
| BIM-027 | Wall by face/mass | — | 4 | could | ✅ done |
| BIM-028 | Curtain walls | CURTAINWALL | 1 | must | ✅ done |
| BIM-029 | Curtain grid editing | — | 3 | must | ✅ done |
| BIM-030 | Curtain panels and mullion types | — | 3 | must | ✅ done |
| BIM-031 | Curtain systems on faces | — | 4 | could | ✅ done |
| BIM-032 | Storefront/partitions | — | 3 | could | ✅ done |

### Openings: Doors & Windows

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-033 | Opening data model | — | 1 | must | ✅ done |
| BIM-034 | Door tool | DOOR | 1 | must | ✅ done |
| BIM-035 | Window tool | WINDOW | 1 | must | ✅ done |
| BIM-036 | Door styles | — | 1 | must | ✅ done |
| BIM-037 | Window styles | — | 1 | must | ✅ done |
| BIM-038 | Door/window flip | OPENINGFLIP | 1 | must | ✅ done |
| BIM-039 | Frames, casings, sills and lintels | — | 3 | should | ✅ done |
| BIM-040 | Opening in roof/slab (skylights) | — | 3 | should | ✅ done |
| BIM-041 | Corner windows | — | 3 | could | ✅ done |
| BIM-042 | Door/window schedules marks | — | 3 | must | ✅ done |
| BIM-043 | Opening wall cleanup | — | 3 | should | ✅ done |
| BIM-044 | Shaft openings | — | 3 | should | ✅ done |
| BIM-045 | Vertical/face openings | — | 3 | must | ✅ done |
| BIM-046 | Dormer openings | — | 3 | could | ✅ done |

### Slabs, Floors & Ceilings

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-047 | Slab data model | — | 1 | must | ✅ done |
| BIM-048 | Slab/floor tool | SLAB | 1 | must | ✅ done |
| BIM-049 | Floor types (layered) | — | 3 | must | ✅ done |
| BIM-050 | Sloped slabs | — | 3 | should | ✅ done |
| BIM-051 | Slab edges | — | 3 | could | ✅ done |
| BIM-052 | Ceilings | CEILING | 3 | must | ✅ done |
| BIM-053 | Ceiling grids | — | 3 | should | ✅ done |
| BIM-054 | Floor finishes | — | 3 | should | ✅ done |

### Roofs

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-055 | Roof data model | — | 1 | must | ✅ done |
| BIM-056 | Roof by footprint | ROOF | 1 | must | ✅ done |
| BIM-057 | Roof by extrusion | — | 3 | should | ✅ done |
| BIM-058 | Mansard, gambrel, dome, barrel roofs | ROOFSHAPE | 3 | could | ✅ done |
| BIM-059 | Roof join and cut | — | 3 | should | ✅ done |
| BIM-060 | Dormers | — | 3 | could | ✅ done |
| BIM-061 | Fascia, gutters, soffits | — | 3 | should | ✅ done |
| BIM-062 | Roof layers | — | 3 | should | ✅ done |
| BIM-063 | Shape editing of flat roofs | — | 3 | could | ✅ done |

### Stairs, Ramps & Railings

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-064 | Stair data model | — | 1 | must | ✅ done |
| BIM-065 | Stair tool | STAIR | 1 | must | ✅ done |
| BIM-066 | Stair by sketch | — | 3 | should | ✅ done |
| BIM-067 | Winders and landings | — | 3 | should | ✅ done |
| BIM-068 | Stair calculation rules | — | 3 | should | ✅ done |
| BIM-069 | Stair plan cut representation | — | 1 | must | ✅ done |
| BIM-070 | Ramps | RAMP | 3 | must | ✅ done |
| BIM-071 | Railing data model | — | 1 | must | ✅ done |
| BIM-072 | Railings | RAILING | 1 | must | ✅ done |
| BIM-073 | Railing types | — | 3 | should | ✅ done |
| BIM-074 | Escalators/elevators | ESCALATOR | 3 | could | ✅ done |

### Structure

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-075 | Column data model | — | 1 | must | ✅ done |
| BIM-076 | Architectural columns | COLUMN | 1 | must | ✅ done |
| BIM-077 | Structural columns | — | 3 | must | ✅ done |
| BIM-078 | Beam data model | — | 1 | must | ✅ done |
| BIM-079 | Beams | BEAM | 1 | must | ✅ done |
| BIM-080 | Beam systems | — | 3 | should | ✅ done |
| BIM-081 | Braces | — | 3 | could | ✅ done |
| BIM-082 | Trusses | — | 3 | could | ✅ done |
| BIM-083 | Steel profile library | — | 3 | must | ✅ done |
| BIM-084 | Foundations | FOUNDATION | 3 | must | ✅ done |
| BIM-085 | Rebar basics | — | 7 | could | ✅ done |
| BIM-086 | Structural walls/slabs flags | — | 3 | should | ✅ done |
| BIM-087 | Connections (steel) | — | 7 | could | ✅ done |

### Rooms, Spaces & Areas

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-088 | Space data model | — | 1 | must | ✅ done |
| BIM-089 | Room tool | ROOM | 1 | must | ✅ done |
| BIM-090 | Room separation lines | — | 3 | must | ✅ done |
| BIM-091 | Room tags | — | 1 | must | ✅ done |
| BIM-092 | Room finishes parameters | — | 3 | should | ✅ done |
| BIM-093 | Area plans | AREA | 3 | should | ✅ done |
| BIM-094 | Area schemes | — | 3 | should | ✅ done |
| BIM-095 | Zones | ZONE | 3 | should | ✅ done |
| BIM-096 | Colour fill schemes | — | 3 | must | ✅ done |
| BIM-097 | Room volume computation | — | 3 | should | ✅ done |

### Components & Furniture

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-098 | Component placement | COMPONENT | 1 | must | ✅ done |
| BIM-099 | Hosted components | — | 3 | must | ✅ done |
| BIM-100 | Casework/kitchen | — | 3 | should | ✅ done |
| BIM-101 | Sanitary fixtures | — | 2 | must | ✅ done |
| BIM-102 | Lighting fixtures | — | 5 | should | ✅ done |
| BIM-103 | Generic models / in-place | — | 4 | should | ✅ done |

### MEP Basics

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-104 | Ducts | DUCT | 3 | could | ✅ done |
| BIM-105 | Pipes | PIPE | 3 | could | ✅ done |
| BIM-106 | Cable trays/conduits | — | 3 | could | ✅ done |
| BIM-107 | MEP equipment and terminals | — | 3 | could | ✅ done |
| BIM-108 | Systems and connectors | — | 3 | could | ✅ done |
| BIM-109 | Electrical circuits | — | 7 | could | ✅ done |

### Site & Topography

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-110 | Toposurface from points | TOPO | 3 | must | ✅ done |
| BIM-111 | Toposurface from contours (DXF) | — | 3 | should | ✅ done |
| BIM-112 | Building pad | — | 3 | should | ✅ done |
| BIM-113 | Graded region / cut-fill | — | 7 | should | ✅ done |
| BIM-114 | Sub-regions (paths, lawns) | — | 3 | should | ✅ done |
| BIM-115 | Property lines | — | 3 | should | ✅ done |
| BIM-116 | Site components (parking, trees) | — | 3 | should | ✅ done |
| BIM-117 | Contour display | — | 3 | should | ✅ done |
| BIM-118 | Geolocation | GEOLOCATION | 3 | must | ✅ done |

### Phasing, Options & Worksets

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| BIM-119 | Phases | PHASES | 3 | must | ✅ done |
| BIM-120 | Phase filters | — | 3 | must | ✅ done |
| BIM-121 | Renovation filter styles | — | 3 | should | ✅ done |
| BIM-122 | Design options | — | 3 | should | ✅ done |
| BIM-123 | Worksets | — | 6 | could | ✅ done |
| BIM-124 | Assemblies | — | 3 | could | ✅ done |
| BIM-125 | Model groups | GROUP (BIM) | 3 | must | ✅ done |
| BIM-126 | Element aggregation | — | 3 | should | ✅ done |
| BIM-127 | Parts (dividing layers) | — | 3 | could | ✅ done |
| BIM-128 | Classification codes | CLASSIFY | 3 | should | ✅ done |
| BIM-129 | Property sets (Psets) | PSET | 3 | must | ✅ done |
| BIM-130 | Property set templates | PSET Template | 3 | should | ✅ done |
| BIM-131 | bSDD lookup | — | 6 | could | ✅ done |

## PAR — Parametric Families

36 features.


### Family Editor

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| PAR-001 | Family editor | FAMILYEDIT | 3 | must | ✅ done |
| PAR-002 | Family templates | — | 3 | must | ✅ done |
| PAR-003 | Reference planes and lines | FAMILY Ref | 3 | must | ✅ done |
| PAR-004 | Solid forms in families | — | 3 | must | ✅ done |
| PAR-005 | Void forms | — | 3 | must | ✅ done |
| PAR-006 | Nested families | — | 3 | should | ✅ done |
| PAR-007 | Family symbolic lines | — | 3 | must | ✅ done |
| PAR-008 | Visibility by detail level/view | — | 3 | must | ✅ done |
| PAR-009 | Family materials parameters | — | 3 | must | ✅ done |
| PAR-010 | Family preview and flex test | — | 3 | should | ✅ done |
| PAR-011 | Load/reload families into project | — | 3 | must | ✅ done |
| PAR-012 | Family file format (.archifam) | — | 3 | must | ✅ done |
| PAR-013 | Profile families | — | 3 | should | ✅ done |
| PAR-014 | Annotation/tag families | — | 3 | must | ✅ done |
| PAR-015 | Adaptive components | — | 4 | could | ✅ done |
| PAR-016 | GDL-like scripted objects | — | 4 | should | ✅ done |
| PAR-017 | Door/window family builder | — | 3 | should | ✅ done |
| PAR-018 | Stair/railing/wall type builders | — | 3 | must | ✅ done |

### Parameters & Formulas

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| PAR-019 | Type vs instance parameters | — | 3 | must | ✅ done |
| PAR-020 | Parameter types | — | 3 | must | ✅ done |
| PAR-021 | Formulas | — | 3 | must | ✅ done |
| PAR-022 | Shared parameters | — | 3 | should | ✅ done |
| PAR-023 | Project parameters | — | 3 | must | ✅ done |
| PAR-024 | Global parameters | GLOBALPARAM | 3 | should | ✅ done |
| PAR-025 | Reporting parameters | — | 3 | could | ✅ done |
| PAR-026 | Parameter locking/constraints | — | 3 | must | ✅ done |
| PAR-027 | Lookup tables (CSV) | — | 3 | should | ✅ done |
| PAR-028 | Type catalogs | — | 3 | should | ✅ done |
| PAR-029 | Spreadsheet-driven parameters | — | 4 | should | ✅ done |
| PAR-030 | Expressions on any property | — | 4 | should | ✅ done |
| PAR-031 | Parameter validation ranges | — | 3 | could | ✅ done |
| PAR-032 | Transfer project standards | — | 3 | must | ✅ done |
| PAR-033 | Purge unused families/types | FAMILY Purge | 3 | must | ✅ done |
| PAR-034 | Family types table editor | FAMILYPANEL | 3 | should | ✅ done |
| PAR-035 | Conditional geometry | — | 3 | must | ✅ done |
| PAR-036 | Parametric arrays in families | — | 3 | should | ✅ done |

## DOC — Documentation & Views

55 features.


### Views

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DOC-001 | Floor plan views | — | 1 | must | ✅ done |
| DOC-002 | View range | VIEWRANGE | 3 | must | ✅ done |
| DOC-003 | Reflected ceiling plans | — | 3 | must | ✅ done |
| DOC-004 | Section views | SECTION | 1 | must | ✅ done |
| DOC-005 | Elevation views | ELEVATION | 1 | must | ✅ done |
| DOC-006 | Interior elevation markers | — | 3 | should | ✅ done |
| DOC-007 | Callout/detail views | CALLOUT | 3 | must | ✅ done |
| DOC-008 | Drafting views | — | 3 | must | ✅ done |
| DOC-009 | 3D views and axonometrics | — | 1 | must | ✅ done |
| DOC-010 | Perspective camera views | CAMERA | 2 | should | ✅ done |
| DOC-011 | Detail sections through walls | — | 3 | should | ✅ done |
| DOC-012 | Plan regions | — | 3 | should | ✅ done |
| DOC-013 | Dependent views | — | 3 | could | ✅ done |
| DOC-014 | Matchlines | — | 3 | could | ✅ done |
| DOC-015 | Duplicate view (with detailing) | — | 3 | must | ✅ done |
| DOC-016 | Crop regions | — | 3 | must | ✅ done |
| DOC-017 | Section box in 3D views | — | 3 | must | ✅ done |
| DOC-018 | Hidden line in sections/elevations | — | 1 | must | ✅ done |
| DOC-019 | Far clip and depth cueing | — | 3 | could | ✅ done |

### Visibility & Graphics

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DOC-020 | Visibility/graphics overrides | VG | 3 | must | ✅ done |
| DOC-021 | View filters | — | 3 | must | ✅ done |
| DOC-022 | View templates | — | 3 | must | ✅ done |
| DOC-023 | Detail level (coarse/medium/fine) | — | 3 | must | ✅ done |
| DOC-024 | Cut patterns by material | — | 1 | must | ✅ done |
| DOC-025 | Temporary hide/isolate (BIM) | HH/HI | 2 | must | ✅ done |
| DOC-026 | Reveal hidden elements | RH | 3 | should | ✅ done |
| DOC-027 | Linework override | LW | 3 | should | ✅ done |
| DOC-028 | Halftone/underlay levels | UNDERLAY | 3 | must | ✅ done |
| DOC-029 | Graphic display options | — | 5 | could | ✅ done |

### Tags & Annotation (BIM)

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DOC-030 | Tag by category | TAG | 3 | must | ✅ done |
| DOC-031 | Tag all not tagged | — | 3 | must | ✅ done |
| DOC-032 | Material tags | — | 3 | should | ✅ done |
| DOC-033 | Multi-category tags | — | 3 | should | ✅ done |
| DOC-034 | Keynotes | KEYNOTE | 3 | should | ✅ done |
| DOC-035 | Legends | LEGEND | 3 | should | ✅ done |
| DOC-036 | Door/window numbering tools | — | 3 | should | ✅ done |
| DOC-037 | Detail components | — | 3 | should | ✅ done |
| DOC-038 | Repeating detail components | — | 3 | could | ✅ done |
| DOC-039 | Insulation line | — | 3 | should | ✅ done |
| DOC-040 | Auto dimension plans | — | 3 | should | ✅ done |

### Schedules & Quantities

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| DOC-041 | Schedules | SCHEDULE | 3 | must | ✅ done |
| DOC-042 | Schedule editing round-trip | — | 3 | must | ✅ done |
| DOC-043 | Calculated fields | — | 3 | should | ✅ done |
| DOC-044 | Material takeoff schedules | — | 3 | must | ✅ done |
| DOC-045 | Key schedules | — | 3 | could | ✅ done |
| DOC-046 | Sheet and view lists | — | 3 | should | ✅ done |
| DOC-047 | Note block schedules | — | 3 | could | ✅ done |
| DOC-048 | Schedule images | — | 3 | could | ✅ done |
| DOC-049 | Schedule export CSV/XLSX | — | 1 | must | ✅ done |
| DOC-050 | Room data sheets | — | 7 | could | ✅ done |
| DOC-051 | Embedded schedules | — | 3 | could | ✅ done |
| DOC-052 | Conditional formatting | — | 3 | could | ✅ done |
| DOC-053 | Schedules on sheets | — | 3 | must | ✅ done |
| DOC-054 | Door/window/room schedule presets | — | 3 | must | ✅ done |
| DOC-055 | Wall/floor/roof build-up legends | — | 3 | could | ✅ done |

## M3D — 3D Modelling

107 features.


### Primitives

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-001 | Solid data model | — | 1 | must | ✅ done |
| M3D-002 | Box | BOX | 1 | must | ✅ done |
| M3D-003 | Cylinder | CYLINDER (CYL) | 1 | must | ✅ done |
| M3D-004 | Sphere | SPHERE | 1 | must | ✅ done |
| M3D-005 | Cone | CONE | 2 | should | ✅ done |
| M3D-006 | Wedge | WEDGE | 4 | should | ✅ done |
| M3D-007 | Torus | TORUS | 4 | should | ✅ done |
| M3D-008 | Pyramid | PYRAMID | 4 | should | ✅ done |
| M3D-009 | Polysolid | POLYSOLID | 4 | should | ✅ done |
| M3D-010 | Prism/tube | PRISM | 4 | could | ✅ done |
| M3D-011 | Helix-based spring/thread | — | 4 | could | ✅ done |
| M3D-012 | Text 3D | — | 4 | should | ✅ done |
| M3D-013 | Polyhedron | POLYHEDRON | 4 | should | ✅ done |

### Sketch-Based Features

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-014 | Extrude | EXTRUDE (EXT) | 1 | must | ✅ done |
| M3D-015 | Push/pull | PRESSPULL | 4 | must | ✅ done |
| M3D-016 | Revolve | REVOLVE (REV) | 4 | must | ✅ done |
| M3D-017 | Loft | LOFT | 4 | must | ✅ done |
| M3D-018 | Sweep | SWEEP | 4 | must | ✅ done |
| M3D-019 | Pipe | — | 4 | should | ✅ done |
| M3D-020 | Follow-me | FOLLOWME | 4 | should | ✅ done |
| M3D-021 | Helical sweep | — | 4 | could | ✅ done |
| M3D-022 | Pad/pocket (PartDesign) | — | 4 | should | ✅ done |
| M3D-023 | Holes (thread/counterbore) | — | 4 | could | ✅ done |
| M3D-024 | Ribs/grooves | — | 4 | could | ✅ done |
| M3D-025 | Feature tree/history | — | 4 | must | ✅ done |
| M3D-026 | Linear/polar pattern features | — | 4 | should | ✅ done |
| M3D-027 | Mirror feature | — | 4 | should | ✅ done |
| M3D-028 | Datum planes/axes/points | — | 4 | should | ✅ done |
| M3D-029 | Sub-shape binders | — | 4 | could | ✅ done |

### Solid Editing & Booleans

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-030 | Union | UNION (UNI) | 4 | must | ✅ done |
| M3D-031 | Subtract | SUBTRACT (SU) | 4 | must | ✅ done |
| M3D-032 | Intersect | INTERSECT (IN) | 4 | must | ✅ done |
| M3D-033 | General fuse / split | — | 4 | could | ✅ done |
| M3D-034 | Fillet edges 3D | FILLETEDGE | 4 | must | ✅ done |
| M3D-035 | Chamfer edges 3D | CHAMFEREDGE | 4 | must | ✅ done |
| M3D-036 | Shell | SOLIDEDIT Shell | 4 | should | ✅ done |
| M3D-037 | Slice | SLICE | 4 | must | ✅ done |
| M3D-038 | Section plane | SECTIONPLANE | 4 | should | ✅ done |
| M3D-039 | Thicken | THICKEN | 4 | should | ✅ done |
| M3D-040 | Imprint | IMPRINT | 4 | could | ✅ done |
| M3D-041 | Extrude/offset/taper faces | SOLIDEDIT Face | 4 | should | ✅ done |
| M3D-042 | Separate/clean solids | SOLIDEDIT Body | 4 | could | ✅ done |
| M3D-043 | Interfere | INTERFERE | 4 | should | ✅ done |
| M3D-044 | Minkowski sum | — | 4 | could | ✅ done |
| M3D-045 | Hull | HULL | 4 | should | ✅ done |
| M3D-046 | Offset solid | — | 4 | could | ✅ done |
| M3D-047 | Mirror 3D | MIRROR3D | 4 | must | ✅ done |
| M3D-048 | Rotate 3D | ROTATE3D | 4 | must | ✅ done |
| M3D-049 | 3D align | 3DALIGN | 4 | should | ✅ done |
| M3D-050 | 3D array | 3DARRAY | 4 | should | ✅ done |
| M3D-051 | Gizmos (move/rotate/scale) | 3DMOVE | 4 | must | ✅ done |
| M3D-052 | Sub-object selection | Ctrl-click | 4 | must | ✅ done |
| M3D-053 | Solid history | SOLIDHIST | 4 | could | ✅ done |
| M3D-054 | Validate shapes | SOLIDCHECK | 4 | should | ✅ done |

### Mesh Modelling

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-055 | Mesh primitives | MESH | 4 | should | ✅ done |
| M3D-056 | Mesh smooth/refine | MESHSMOOTH | 4 | should | ✅ done |
| M3D-057 | Mesh from solids and back | CONVTOMESH / CONVTOSOLID | 4 | must | ✅ done |
| M3D-058 | Mesh repair | — | 4 | should | ✅ done |
| M3D-059 | Mesh decimation | — | 4 | should | ✅ done |
| M3D-060 | Mesh boolean | — | 4 | could | ✅ done |
| M3D-061 | Mesh cross-sections | — | 4 | could | ✅ done |
| M3D-062 | Edge/face extrude in mesh | — | 4 | could | ✅ done |
| M3D-063 | Wireframe/solidify modifiers | — | 4 | could | ✅ done |
| M3D-064 | Mesh unfold | — | 7 | could | ✅ done |

### Surfaces & NURBS

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-065 | Planar surface | PLANESURF | 4 | should | ✅ done |
| M3D-066 | Network surface | SURFNETWORK | 4 | should | ✅ done |
| M3D-067 | Blend surface | SURFBLEND | 4 | could | ✅ done |
| M3D-068 | Patch surface | SURFPATCH | 4 | could | ✅ done |
| M3D-069 | Surface offset/extend/trim | — | 4 | could | ✅ done |
| M3D-070 | NURBS surface from CVs | — | 4 | could | ✅ done |
| M3D-071 | Ruled surface | RULESURF | 4 | should | ✅ done |
| M3D-072 | Revolved/tabulated surface | REVSURF, TABSURF | 4 | could | ✅ done |
| M3D-073 | Edge surface | EDGESURF | 4 | could | ✅ done |
| M3D-074 | Surface analysis | — | 7 | could | ✅ done |
| M3D-075 | Sculpt/convert to solid | SURFSCULPT | 4 | could | ✅ done |

### Parametric Constraints

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-076 | Sketch environment | SKETCH | 4 | must | ✅ done |
| M3D-077 | Geometric constraints | GEOMCONSTRAINT | 4 | must | ✅ done |
| M3D-078 | Dimensional constraints | DIMCONSTRAINT | 4 | must | ✅ done |
| M3D-079 | Auto-constrain / inference | AUTOCONSTRAIN | 4 | should | ✅ done |
| M3D-080 | Constraint solver (Newton/DogLeg) | — | 4 | must | ✅ done |
| M3D-081 | Reference (driven) dimensions | — | 4 | should | ✅ done |
| M3D-082 | Constraint display and hide | CONSTRAINTBAR | 4 | should | ✅ done |
| M3D-083 | Parameters manager | PARAMETERS | 4 | must | ✅ done |
| M3D-084 | 3D sketches | — | 4 | could | ✅ done |
| M3D-085 | Point-on-curve and ratio constraints | — | 4 | should | ✅ done |
| M3D-086 | Projection of external geometry | — | 4 | should | ✅ done |
| M3D-087 | Solve-based dragging | — | 4 | must | ✅ done |
| M3D-088 | Linkages and mechanism simulation | — | 7 | could | ✅ done |
| M3D-089 | Constraints on 2D drawing entities | — | 4 | should | ✅ done |

### CSG Scripting

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-090 | OpenSCAD-like CSG language | — | 4 | should | ✅ done |
| M3D-091 | Linear/rotate extrude | LINEAREXTRUDE | 4 | should | ✅ done |
| M3D-092 | 2D ops offset/projection | — | 4 | could | ✅ done |
| M3D-093 | Customizer parameters panel | — | 4 | could | ✅ done |
| M3D-094 | Import .scad files | — | 6 | could | ✅ done |
| M3D-095 | BRL-CAD style CSG trees | — | 4 | could | ✅ done |

### Massing & Conceptual

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| M3D-096 | Conceptual masses | MASS | 4 | must | ✅ done |
| M3D-097 | Mass floors | — | 4 | should | ✅ done |
| M3D-098 | Elements from mass faces | — | 4 | should | ✅ done |
| M3D-099 | Sandbox/terrain from contours | — | 4 | could | ✅ done |
| M3D-100 | Intersect faces (SketchUp) | — | 4 | should | ✅ done |
| M3D-101 | Soften/smooth edges | — | 4 | could | ✅ done |
| M3D-102 | Components & groups (SketchUp) | — | 4 | must | ✅ done |
| M3D-103 | Outliner | — | 4 | should | ✅ done |
| M3D-104 | Tape measure and guides | — | 4 | should | ✅ done |
| M3D-105 | Paint bucket | — | 4 | must | ✅ done |
| M3D-106 | Scale tool with gizmo | — | 4 | should | ✅ done |
| M3D-107 | Offset faces tool | — | 4 | should | ✅ done |

## VIS — Visualization & Rendering

88 features.


### 2D Navigation

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-001 | Zoom in/out | ZOOM (Z) | 1 | must | ✅ done |
| VIS-002 | Zoom extents | ZOOM E | 1 | must | ✅ done |
| VIS-003 | Zoom window | ZOOM W | 1 | must | ✅ done |
| VIS-004 | Zoom previous | ZOOM P | 1 | must | ✅ done |
| VIS-005 | Zoom scale | ZOOM nX/nXP | 2 | should | ✅ done |
| VIS-006 | Zoom to selected object | ZOOM O | 1 | must | ✅ done |
| VIS-007 | Pan | PAN (P) | 1 | must | ✅ done |
| VIS-008 | Named views | VIEW | 1 | should | ✅ done |
| VIS-009 | Regenerate display | REGEN (RE) | 1 | must | ✅ done |
| VIS-010 | Redraw | REDRAW | 2 | should | ✅ done |
| VIS-011 | View rotation (2D) | DVIEW Twist | 2 | could | ✅ done |

### 3D Navigation

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-012 | 3D viewport | — | 1 | must | ✅ done |
| VIS-013 | Orbit | 3DORBIT (3DO) | 1 | must | ✅ done |
| VIS-014 | ViewCube | NAVVCUBE | 1 | must | ✅ done |
| VIS-015 | Standard views | — | 1 | must | ✅ done |
| VIS-016 | Perspective/parallel toggle | PERSPECTIVE | 1 | must | ✅ done |
| VIS-017 | Walk mode | 3DWALK | 5 | must | ✅ done |
| VIS-018 | Fly mode | 3DFLY | 5 | should | ✅ done |
| VIS-019 | Steering wheels | NAVSWHEEL | 5 | could | ✅ done |
| VIS-020 | Look around / position camera | — | 5 | should | ✅ done |
| VIS-021 | Zoom to fit/selection in 3D | — | 1 | must | ✅ done |
| VIS-022 | Field of view control | FOV | 5 | should | ✅ done |
| VIS-023 | Two-point perspective | — | 5 | should | ✅ done |
| VIS-024 | Space mouse support | — | 8 | could | ✅ done |

### Visual Styles

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-025 | Wireframe style | — | 1 | must | ✅ done |
| VIS-026 | Hidden line style | — | 1 | must | ✅ done |
| VIS-027 | Shaded style | — | 1 | must | ✅ done |
| VIS-028 | Shaded with edges | — | 1 | must | ✅ done |
| VIS-029 | Realistic/textured | — | 5 | must | ✅ done |
| VIS-030 | Conceptual/consistent colours | — | 5 | should | ✅ done |
| VIS-031 | X-ray | — | 5 | should | ✅ done |
| VIS-032 | Sketchy/hand-drawn style | — | 5 | could | ✅ done |
| VIS-033 | Ambient occlusion | — | 5 | should | ✅ done |
| VIS-034 | Visual styles manager | VISUALSTYLES | 5 | could | ✅ done |
| VIS-035 | Section box 3D | — | 3 | must | ✅ done |
| VIS-036 | Section planes with cap fill | — | 5 | should | ✅ done |
| VIS-037 | Clip planes in 3D | — | 5 | should | ✅ done |
| VIS-038 | Explode/isolate by level in 3D | LEVELVIEW3D | 3 | should | ✅ done |

### Cameras & Animation

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-039 | Camera objects | CAMERA | 5 | must | ✅ done |
| VIS-040 | Scenes (saved views) | — | 5 | must | ✅ done |
| VIS-041 | Walkthrough path animation | ANIPATH | 5 | must | ✅ done |
| VIS-042 | Keyframe camera animation | — | 5 | should | ✅ done |
| VIS-043 | Animated sun (time-lapse) | — | 5 | should | ✅ done |
| VIS-044 | Phasing/construction animation | — | 7 | could | ✅ done |
| VIS-045 | Object animation | — | 5 | could | ✅ done |
| VIS-046 | Video export | — | 5 | must | ✅ done |
| VIS-047 | Panorama export | — | 5 | should | ✅ done |
| VIS-048 | Stereo panoramas | — | 5 | could | ✅ done |

### Sun, Light & Environment

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-049 | Sun position by location/time | SUNPROPERTIES | 5 | must | ✅ done |
| VIS-050 | Shadows in viewport | — | 5 | must | ✅ done |
| VIS-051 | Sky models | — | 5 | should | ✅ done |
| VIS-052 | HDRI environment | — | 5 | must | ✅ done |
| VIS-053 | Artificial lights | — | 5 | must | ✅ done |
| VIS-054 | IES profiles | — | 5 | should | ✅ done |
| VIS-055 | Emissive materials | — | 5 | should | ✅ done |
| VIS-056 | Fog/atmosphere | — | 5 | could | ✅ done |
| VIS-057 | Exposure and white balance | — | 5 | must | ✅ done |
| VIS-058 | Weather and seasons | — | 5 | could | ✅ done |

### Materials

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-059 | Materials data model | — | 1 | must | ✅ done |
| VIS-060 | Materials editor | MATERIALS | 5 | must | ✅ done |
| VIS-061 | PBR textures | — | 5 | must | ✅ done |
| VIS-062 | Texture mapping | — | 5 | must | ✅ done |
| VIS-063 | Texture positioning tool | — | 5 | should | ✅ done |
| VIS-064 | Material library (CC0) | — | 5 | must | ✅ done |
| VIS-065 | Glass/transparency/refraction | — | 5 | must | ✅ done |
| VIS-066 | Procedural materials | — | 5 | could | ✅ done |
| VIS-067 | Material assets from images | — | 5 | could | ✅ done |
| VIS-068 | Material identity/appearance/graphics | — | 5 | should | ✅ done |

### Rendering

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-069 | Real-time renderer | — | 5 | must | ✅ done |
| VIS-070 | Path-traced renderer | RENDER | 5 | must | ✅ done |
| VIS-071 | Denoiser | — | 5 | should | ✅ done |
| VIS-072 | Render region | — | 5 | should | ✅ done |
| VIS-073 | Render presets | — | 5 | should | ✅ done |
| VIS-074 | Render output resolution | — | 5 | must | ✅ done |
| VIS-075 | Render passes | — | 5 | could | ✅ done |
| VIS-076 | Batch rendering | — | 5 | should | ✅ done |
| VIS-077 | Clay/white-model render | — | 5 | should | ✅ done |
| VIS-078 | Light mix | — | 5 | could | ✅ done |
| VIS-079 | Render history | — | 5 | could | ✅ done |
| VIS-080 | Non-photorealistic render | — | 5 | could | ✅ done |

### Entourage & Immersive

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| VIS-081 | Entourage library | — | 5 | should | ✅ done |
| VIS-082 | Scatter vegetation | — | 5 | could | ✅ done |
| VIS-083 | Water surfaces | — | 5 | could | ✅ done |
| VIS-084 | Billboards | — | 5 | could | ✅ done |
| VIS-085 | USDZ AR Quick Look export | — | 5 | must | ✅ done |
| VIS-086 | VR headset viewing | — | 5 | could | 🟡 partial |
| VIS-087 | Web viewer export | — | 5 | should | ✅ done |
| VIS-088 | Image export of viewport | VIEWIMAGE | 1 | must | ✅ done |

## IO — Interoperability

66 features.


### Native Format

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| IO-001 | .archi native format | SAVE (Cmd+S) | 1 | must | ✅ done |
| IO-002 | Save As/versions | SAVEAS | 1 | must | ✅ done |
| IO-003 | Compressed package format | — | 2 | should | ✅ done |
| IO-004 | Schema migrations | — | 1 | must | ✅ done |
| IO-005 | Templates (.architemplate) | — | 1 | must | ✅ done |
| IO-006 | Auto thumbnail/Quick Look | — | 2 | should | 🟡 partial |
| IO-007 | Spotlight importer | — | 8 | could | 🟡 partial |

### CAD Exchange

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| IO-008 | DXF import | DXFIN | 1 | must | ✅ done |
| IO-009 | DXF export | DXFOUT | 1 | must | ✅ done |
| IO-010 | DWG import via LibreDWG | DWGIN | 6 | must | 🟡 partial |
| IO-011 | DWG export via LibreDWG | DWGOUT | 6 | should | 🟡 partial |
| IO-012 | DWF/DWFx import | DWFIMPORT | 6 | could | 🟡 partial |
| IO-013 | DGN import/export | DGNIMPORT | 6 | could | 🟡 partial |
| IO-014 | PDF import (vector) | PDFIMPORT | 6 | should | ✅ done |
| IO-015 | PDF underlay | PDFATTACH | 6 | must | ✅ done |
| IO-016 | SVG import | — | 6 | should | ✅ done |
| IO-017 | SVG export | — | 1 | must | ✅ done |
| IO-018 | HPGL/PLT export | — | 6 | could | ✅ done |
| IO-019 | CNC/laser export (MakerCAM SVG) | LASEREXPORT | 6 | could | ✅ done |

### BIM Exchange

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| IO-020 | IFC4 export | IFCEXPORT | 1 | must | ✅ done |
| IO-021 | IFC2x3 export | — | 6 | must | 🟡 partial |
| IO-022 | IFC4.3 export | — | 6 | should | 🟡 partial |
| IO-023 | IFC import | IFCIMPORT | 6 | must | 🟡 partial |
| IO-024 | IFC export mappings | IFCMAP | 6 | must | 🟡 partial |
| IO-025 | IfcZIP and ifcXML | — | 6 | could | 🟡 partial |
| IO-026 | IDS validation | — | 7 | should | 🟡 partial |
| IO-027 | MVD selection | — | 6 | should | 🟡 partial |
| IO-028 | COBie export | — | 6 | could | ✅ done |
| IO-029 | gbXML export | — | 7 | should | ✅ done |
| IO-030 | IFC round-trip GUIDs | — | 6 | must | 🟡 partial |

### 3D Exchange

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| IO-031 | OBJ export | — | 1 | must | ✅ done |
| IO-032 | OBJ import | — | 6 | must | ✅ done |
| IO-033 | STL export/import | — | 2 | should | ✅ done |
| IO-034 | 3MF export/import | — | 6 | should | ✅ done |
| IO-035 | glTF/GLB export | — | 1 | must | ✅ done |
| IO-036 | glTF/GLB import | — | 6 | must | ✅ done |
| IO-037 | USDZ/USD export | — | 5 | must | ✅ done |
| IO-038 | USD import | — | 6 | should | ✅ done |
| IO-039 | FBX import/export | — | 6 | should | ✅ done |
| IO-040 | STEP import/export | — | 6 | should | 🟡 partial |
| IO-041 | IGES import/export | — | 6 | could | ✅ done |
| IO-042 | BREP import/export | — | 6 | could | ✅ done |
| IO-043 | SketchUp SKP import | — | 6 | should | 🟡 partial |
| IO-044 | Rhino 3DM import/export | — | 6 | should | 🟡 partial |
| IO-045 | Collada DAE | — | 6 | could | ✅ done |
| IO-046 | PLY import/export | — | 6 | could | ✅ done |
| IO-047 | OFF/AMF import | — | 6 | could | ✅ done |

### Point Clouds & Survey

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| IO-048 | E57 import | — | 6 | should | 🟡 partial |
| IO-049 | LAS/LAZ import | — | 6 | should | 🟡 partial |
| IO-050 | PLY/PTS/XYZ point import | — | 6 | could | 🟡 partial |
| IO-051 | Point cloud display and clipping | POINTCLOUDVIEW | 6 | should | 🟡 partial |
| IO-052 | Snapping to point clouds | PCPLANE | 6 | could | 🟡 partial |
| IO-053 | Plane/wall fitting from scans | SCANTOBIM | 8 | could | 🟡 partial |
| IO-054 | Survey data import | — | 6 | could | 🟡 partial |

### GIS & Data

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| IO-055 | Shapefile import | — | 6 | should | ✅ done |
| IO-056 | GeoJSON import/export | — | 6 | should | ✅ done |
| IO-057 | OpenStreetMap buildings/context | — | 6 | should | ✅ done |
| IO-058 | Terrain from elevation data | — | 6 | could | ✅ done |
| IO-059 | CRS/map conversion | — | 6 | should | ✅ done |
| IO-060 | CityGML/CityJSON | — | 6 | could | ✅ done |
| IO-061 | CSV import/export | — | 1 | must | ✅ done |
| IO-062 | XLSX export/import | — | 6 | should | ✅ done |
| IO-063 | Image formats | — | 1 | must | ✅ done |
| IO-064 | Clipboard interoperability | — | 2 | should | ✅ done |
| IO-065 | Drag and drop import | — | 2 | should | ✅ done |
| IO-066 | Batch conversion | — | 6 | could | ✅ done |

## ANL — Analysis

42 features.


### Inquiry

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANL-001 | Distance | DIST (DI) | 1 | must | ✅ done |
| ANL-002 | Measure geometry | MEASUREGEOM (MEA) | 1 | must | ✅ done |
| ANL-003 | Area | AREA | 1 | must | ✅ done |
| ANL-004 | Point ID | ID | 1 | must | ✅ done |
| ANL-005 | Angle between lines | — | 2 | should | ✅ done |
| ANL-006 | Total length | — | 2 | should | ✅ done |
| ANL-007 | Distance point to entity | — | 2 | should | ✅ done |
| ANL-008 | Point inside contour | — | 2 | could | ✅ done |
| ANL-009 | Mass properties | MASSPROP | 4 | should | ✅ done |
| ANL-010 | Drawing status/statistics | STATUS | 2 | could | ✅ done |
| ANL-011 | Time tracking | TIME | 8 | could | ✅ done |

### Quantities & Cost

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANL-012 | Quantity takeoff (QTO) | — | 3 | must | ✅ done |
| ANL-013 | Net/gross area rules | — | 7 | should | ✅ done |
| ANL-014 | Cost estimation | — | 7 | should | ✅ done |
| ANL-015 | Cost database import | — | 7 | could | ✅ done |
| ANL-016 | Area analysis reports | — | 7 | should | ✅ done |
| ANL-017 | Construction sequencing (4D) | WORKSCHEDULE | 7 | could | ✅ done |
| ANL-018 | Resource planning | — | 7 | could | ✅ done |

### Environmental

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANL-019 | Sun study (plan/3D) | — | 7 | must | ✅ done |
| ANL-020 | Solar radiation on surfaces | — | 7 | should | ✅ done |
| ANL-021 | Daylight factor | — | 7 | should | ✅ done |
| ANL-022 | Climate-based daylight (sDA/ASE) | — | 7 | could | 🟡 partial |
| ANL-023 | Energy model generation | — | 7 | should | 🟡 partial |
| ANL-024 | Energy simulation (EnergyPlus) | ENERGYPLUS | 7 | should | 🟡 partial |
| ANL-025 | U-value calculation | — | 7 | must | ✅ done |
| ANL-026 | Thermal bridges hint | THERMALBRIDGES | 7 | could | ✅ done |
| ANL-027 | Embodied carbon (LCA) | — | 7 | should | ✅ done |
| ANL-028 | Wind/CFD basics | — | 7 | could | 🟡 partial |
| ANL-029 | Acoustic basics | — | 7 | could | ✅ done |
| ANL-030 | View analysis / isovist | — | 7 | could | ✅ done |

### Structural

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANL-031 | Analytical model | — | 7 | should | ✅ done |
| ANL-032 | Loads and boundary conditions | STRUCTLOAD / STRUCTSUPPORT | 7 | should | ✅ done |
| ANL-033 | Simple frame analysis | — | 7 | could | ✅ done |
| ANL-034 | Export to structural tools | — | 7 | could | 🟡 partial |

### Model Checking

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| ANL-035 | Clash detection | — | 7 | must | ✅ done |
| ANL-036 | Clash groups and status | — | 7 | should | ✅ done |
| ANL-037 | Model checker/audit | AUDIT | 2 | must | ✅ done |
| ANL-038 | Duplicate/overlap warnings | — | 3 | must | ✅ done |
| ANL-039 | Code checking rules | — | 7 | should | ✅ done |
| ANL-040 | Room/area validation | — | 3 | should | ✅ done |
| ANL-041 | IFC schema validation | — | 6 | should | ✅ done |
| ANL-042 | Drawing standards checker | STANDARDS | 7 | could | ✅ done |

## COL — Collaboration & Versioning

22 features.


### Versions & Compare

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| COL-001 | Version history | — | 6 | must | ✅ done |
| COL-002 | Compare drawings | DWGCOMPARE | 6 | must | ✅ done |
| COL-003 | Model diff (BIM) | — | 6 | should | ✅ done |
| COL-004 | Git-backed projects | GITVERSION | 6 | should | ✅ done |
| COL-005 | Branch and merge models | — | 6 | could | ✅ done |
| COL-006 | Restore previous version | — | 6 | must | ✅ done |

### Markups & Issues

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| COL-007 | Markups | MARKUP | 6 | must | ✅ done |
| COL-008 | Markup import from PDF | PDFMARKUPS | 6 | should | ✅ done |
| COL-009 | BCF import/export | — | 6 | must | ✅ done |
| COL-010 | BCF API server connect | — | 6 | could | ✅ done |
| COL-011 | Issue tracking panel | — | 6 | should | ✅ done |
| COL-012 | Trace/overlay review | TRACE | 6 | could | ✅ done |

### Sharing & Teamwork

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| COL-013 | iCloud Drive sync | — | 6 | should | ✅ done |
| COL-014 | Share read-only view links | SHAREVIEW | 6 | could | ✅ done |
| COL-015 | Element borrowing/locking | — | 6 | could | ✅ done |
| COL-016 | Real-time co-editing | — | 6 | could | ✅ done |
| COL-017 | Central/local model | CENTRAL | 6 | could | ✅ done |
| COL-018 | Project standards templates sharing | — | 6 | should | ✅ done |
| COL-019 | eTransmit / pack and go | ETRANSMIT | 6 | must | ✅ done |
| COL-020 | Share via macOS share sheet | — | 2 | should | ✅ done |
| COL-021 | Presentation mode | — | 8 | could | ✅ done |
| COL-022 | Permissions and signatures | — | 6 | could | ✅ done |

## SCR — Scripting, Automation & AI

35 features.


### Scripting

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SCR-001 | JavaScript console | — | 1 | must | ✅ done |
| SCR-002 | Script editor | — | 2 | should | ✅ done |
| SCR-003 | Script library and startup scripts | — | 2 | should | ✅ done |
| SCR-004 | Python bridge | — | 8 | should | ✅ done |
| SCR-005 | AutoLISP compatibility subset | LISP | 8 | could | ✅ done |
| SCR-006 | Custom commands from scripts | — | 2 | must | ✅ done |
| SCR-007 | Event hooks | — | 8 | should | ✅ done |
| SCR-008 | Script-defined UI panels | — | 8 | could | ✅ done |
| SCR-009 | Scripting API reference docs | — | 1 | must | ✅ done |

### Visual Programming

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SCR-010 | Node editor | — | 8 | should | ✅ done |
| SCR-011 | Geometry nodes | — | 8 | should | ✅ done |
| SCR-012 | List/data nodes | — | 8 | should | ✅ done |
| SCR-013 | BIM nodes | — | 8 | should | ✅ done |
| SCR-014 | Graph player/parameters | — | 8 | could | ✅ done |
| SCR-015 | Custom node packages | — | 8 | could | ✅ done |

### Agent API & Plugins

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SCR-016 | Agent JSON-RPC server | — | 1 | must | ✅ done |
| SCR-017 | Agent API methods | — | 1 | must | ✅ done |
| SCR-018 | MCP server | archi-cli --mcp | 1 | must | ✅ done |
| SCR-019 | Headless CLI | archi-cli | 1 | must | ✅ done |
| SCR-020 | Plugin SDK | — | 8 | should | ✅ done |
| SCR-021 | Plugin manager | — | 8 | should | ✅ done |
| SCR-022 | Recorded actions to script | — | 8 | could | ✅ done |
| SCR-023 | Webhooks/automation triggers | — | 8 | could | ✅ done |
| SCR-024 | Shortcuts app integration | — | 8 | should | 🟡 partial |
| SCR-025 | AppleScript support | — | 8 | could | ✅ done |

### AI Assistant

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SCR-026 | Natural-language commands | ASK | 8 | should | ✅ done |
| SCR-027 | AI chat panel | — | 8 | should | ✅ done |
| SCR-028 | Plan generation from brief | PLANGEN | 8 | could | ✅ done |
| SCR-029 | Auto-dimensioning | AUTODIMPLAN | 8 | should | ✅ done |
| SCR-030 | Auto-tagging and room naming | AUTONAMEROOMS | 8 | could | ✅ done |
| SCR-031 | Sketch/photo to model | — | 8 | could | ✅ done |
| SCR-032 | Render prompts / AI styling | — | 8 | could | ✅ done |
| SCR-033 | Model QA assistant | QAASSIST | 8 | could | ✅ done |
| SCR-034 | Generative design | — | 8 | could | ✅ done |
| SCR-035 | Local model support | — | 8 | could | ✅ done |

## SYS — System & Platform

34 features.


### Core Model

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SYS-001 | Document data model | — | 1 | must | ✅ done |
| SYS-002 | Geometry entity types | — | 1 | must | ✅ done |
| SYS-003 | BIM element types | — | 1 | must | ✅ done |
| SYS-004 | Shared ID space | — | 1 | must | ✅ done |
| SYS-005 | Units model | — | 1 | must | ✅ done |
| SYS-006 | Geometry services | — | 1 | must | ✅ done |
| SYS-007 | Triangulation | — | 1 | must | ✅ done |

### Undo & Recovery

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SYS-008 | Undo history snapshots | — | 1 | must | ✅ done |
| SYS-009 | Transactions | — | 1 | must | 🟡 partial |
| SYS-010 | Autosave | — | 1 | must | ✅ done |
| SYS-011 | Crash recovery | DRAWINGRECOVERY | 1 | must | ✅ done |
| SYS-012 | Backup files | — | 2 | should | ✅ done |
| SYS-013 | Recover damaged file | RECOVER | 2 | should | ✅ done |

### Performance

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SYS-014 | Large drawing performance | — | 2 | must | 🟡 partial |
| SYS-015 | Spatial index | — | 2 | must | ✅ done |
| SYS-016 | Metal 2D renderer | — | 2 | should | planned |
| SYS-017 | Background regeneration | — | 3 | should | 🟡 partial |
| SYS-018 | Level of detail | — | 5 | should | 🟡 partial |
| SYS-019 | Memory limits | — | 3 | should | 🟡 partial |
| SYS-020 | Fast open | — | 3 | should | ✅ done |

### Platform & Distribution

| ID | Feature | Command | Phase | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| SYS-021 | Apple silicon and Intel universal | — | 1 | must | planned |
| SYS-022 | Signed and notarized DMG | — | 1 | must | planned |
| SYS-023 | GPL-3.0 licensing | — | 1 | must | ✅ done |
| SYS-024 | Auto-update | — | 2 | should | 🟡 partial |
| SYS-025 | Crash reporting (opt-in) | — | 2 | could | ✅ done |
| SYS-026 | Localization | — | 8 | should | 🟡 partial |
| SYS-027 | Right-to-left/Unicode | — | 2 | should | ✅ done |
| SYS-028 | Accessibility VoiceOver | — | 8 | should | ✅ done |
| SYS-029 | Keyboard-only operation | — | 8 | should | ✅ done |
| SYS-030 | Colour-blind safe themes | — | 8 | could | ✅ done |
| SYS-031 | Documentation site | — | 1 | must | ✅ done |
| SYS-032 | Telemetry-free by default | — | 1 | must | ✅ done |
| SYS-033 | Automated test suite | — | 1 | must | 🟡 partial |
| SYS-034 | Offline operation | — | 1 | must | ✅ done |

