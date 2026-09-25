# Oanarina Archi Tool — User Guide

Oanarina Archi Tool is a free (GPL-3.0) native Mac application for architectural drawing and building design. It combines
AutoCAD-style 2D drafting and a command line, Revit-style building elements (walls, doors, rooms, levels, schedules), a
3D model view with rendering, sheets and printing, many exchange formats, and scripting that people and AI agents can use.

This guide describes what the app does today. The full backlog, with the status of every feature, is in
[FEATURE-REGISTER.md](FEATURE-REGISTER.md).

## Contents

1. [Getting started](#getting-started)
2. [The interface](#the-interface)
3. [The command line](#the-command-line)
4. [Selecting objects](#selecting-objects)
5. [Drawing](#drawing)
6. [Modifying](#modifying)
7. [Annotation](#annotation)
8. [Layers and properties](#layers-and-properties)
9. [Blocks, attributes and groups](#blocks-attributes-and-groups)
10. [BIM: building elements and levels](#bim-building-elements-and-levels)
11. [Documentation: views, tags and schedules](#documentation-views-tags-and-schedules)
12. [Site and terrain](#site-and-terrain)
13. [3D modelling](#3d-modelling)
14. [3D view and rendering](#3d-view-and-rendering)
15. [Sheets, plotting and PDF](#sheets-plotting-and-pdf)
16. [Analysis](#analysis)
17. [Import and export](#import-and-export)
18. [Scripting and AI agents](#scripting-and-ai-agents)
19. [Settings and customisation](#settings-and-customisation)
20. [Keyboard and mouse](#keyboard-and-mouse)
21. [Command reference](#command-reference)

## Getting started

**Requirements:** macOS 14 or later, on Apple silicon or Intel.

When the app starts it shows the **start screen**:

- **New Drawing (Metric)**: an empty drawing in millimetres.
- **New Drawing (Imperial)**: an empty drawing in inches.
- **New Building**: a project with levels, a structural grid and sheets that are ready to use.
- **Open…**: opens `.archi` projects and DXF drawings.
- **Sample House**: a small house built with commands, useful for exploring the app.
- **Recent**: recently opened documents. You can remove entries from the list and set its length in Settings.
- **Recovered documents**: if the app quit unexpectedly with unsaved changes, the autosaved copies appear here and you
  can restore or discard them. Autosave runs every few minutes; set the interval with `SAVETIME` (0 turns it off).

You don't need to click into a command field. Start typing a command such as `LINE`, `WALL`, `DOOR` or `ROOM` and it
goes to the command line. Space or Enter repeats the last command.

A quick first model:

```
WALL 0,0 6000,0 6000,4000 0,4000 C
DOOR          (pick a wall, then the position)
ROOM          (click inside the walls)
SHOW3D
```

Documents are saved as `.archi` files, a readable JSON format. Files from older versions of the app open and are
upgraded automatically.

## The interface

- **Ribbon** at the top, with the tabs **Home**, **Annotate**, **Architecture**, **View**, **Output**, **Manage** and
  **Script**. Every button runs the same command you could type. The **quick access toolbar** can be customised in
  Settings; each of its buttons runs a typed command.
- **Workspace modes**: **2D** plan, **3D** model, **Split** (plan and 3D side by side) and **Sheet** (paper layouts),
  switched with ⌥⌘1 to ⌥⌘4 or the `SHOW2D`, `SHOW3D`, `SPLIT` and `LAYOUT` commands.
- **Side panels**, shown and hidden with ⌥⌘P: **Properties**, **Layers**, **Levels**, **Browser** (project browser:
  levels, views, sheets), **Materials** (material editor), **Tools** (tool palettes) and **History** (undo and command
  history). In the History panel, clicking an undo step undoes or redoes to that step.
- **Command line** at the bottom, with autocomplete, history and suggestions.
- **Status bar** toggles for object snap, grid, ortho, polar tracking and dynamic input (also F3, F7, F8, F10, F12).
- **Workspaces**: five built-in arrangements (Drafting & Annotation, Building Design, 3D Modeling, Sheets & Plotting,
  Scripting) and any you save yourself. They are switched with `WSCURRENT` and saved with `WSSAVE`. **Clean screen**
  (⌃0, `CLEANSCREENON`/`CLEANSCREENOFF`) hides the ribbon and panels.
- **Command search** (⌘K, `COMMANDSEARCH`): type part of a name, such as "wal", to find and run any command.
- **About** (`ABOUT`, or the app menu): version, licence and credits.

Each document opens in its own window, and native macOS tabs are supported.

## The command line

The command line works like AutoCAD's. Type a command name or alias and press Enter or Space. The command then asks
for input step by step. Options appear in square brackets. Type the capital letters of an option, for example `C` for
`Close`, or click it.

| Input | Meaning |
| --- | --- |
| `100,200` | Absolute point in the current UCS |
| `@500,0` | Point relative to the last point |
| `@1000<30` | Polar: distance 1000 at 30° from the last point |
| `*100,200` | World coordinates, ignoring the UCS |
| `1500` | Direct distance entry along the cursor direction (follows ortho) |
| `2.5m`, `30cm`, `3'6"`, `12in` | Values with units, converted to drawing units (2.5m is 2500 in a mm drawing) |
| `2400/2`, `1000+250` | Arithmetic in any number field |
| `45`, `45d`, `0.5r`, `50g`, `45d30'15"`, `N45d30'E` | Angles: degrees, radians, grads, degrees-minutes-seconds, surveyor bearings |
| `#12,#13` | Select objects by ID |
| `FROM`, `M2P`, `TT` | Point modifiers: offset from a base point, midpoint between two points, temporary tracking point |
| `.X`, `.Y`, `.XY`, `.Z` … | Point filters: take some coordinates from one point and the rest from another |
| Enter, Space or right-click | Finish the current input or repeat the last command |
| Two spaces | Also Enter, useful when typing a whole command on one line |
| Esc | Cancel |
| `'ZOOM` | Transparent command: runs inside another command, which then continues |

A whole command can go on one line: `LINE 0,0 1000,0 1000,1000 C`. A quoted token is taken as one value. Text
prompts take the rest of the line up to the next Enter.

If you type something that isn't a command, the app suggests similar names. `ALIAS` defines your own aliases and
macros (`;` in a macro means Enter). `UCS` and `UCSMAN` set and name user coordinate systems for typed input.
`CAL` evaluates expressions such as `CAL dist(0,0;3,4)`, and `SETVAR` lists and changes system variables, which are
saved in the drawing.

**Undo:** every command is one undo step (⌘Z / ⇧⌘Z, or `U`, `UNDO`, `REDO`). `UNDO` also accepts a count and the
options `Mark`/`Back` and `BEgin`/`End` to group several commands into one step. `OOPS` brings back the last erased
objects.

## Selecting objects

- **Click** an object to add it to the selection. **Shift-click** toggles it.
- **Drag from left to right** for a window selection (objects fully inside). **Drag from right to left** for a
  crossing selection (objects that touch).
- At a "Select objects" prompt you can also type `All`, `Last`, `Previous`, `Window`, `Crossing`, `WPolygon`,
  `CPolygon`, `Fence`, `Add`, `Remove` or `Group`, or object IDs.
- Commands: `SELECTALL`, `SELECTINVERT`, `SELECTSIMILAR`, `SELECTLAYER`, `SELECTTYPE` (by type or category),
  `SELECTCHAIN` (connected contour), `SELECTINTERSECTING`, `QSELECT` (for example `QSELECT Circle radius > 50`), the
  **Quick Select** dialog (`QSELECTDIALOG`, with a live match count), `FILTER` (expressions such as
  `type=circle & radius>50 | layer=A-*`, which can be saved) and `SELSET` (named selection sets stored in the drawing).
- Objects on locked or hidden layers are not selected.

## Drawing

**2D objects:** `LINE`, `PLINE`, `ARC`, `CIRCLE`, `ELLIPSE`, `SPLINE`, `RECTANG` (also from the centre, by three points,
filleted or chamfered), `POLYGON`, `STAR`, `DONUT`, `POINT` (display style with `PTYPE`), `XLINE`, `RAY`, `DLINE` (double
lines), `SOLID` (filled triangles and quadrilaterals), `WIPEOUT`, `REVCLOUD`, `HATCH` (patterns and solid fills),
`BOUNDARY`, `REGION` and `BOUNDINGBOX`.

**Centre lines and marks:** `CENTERLINE` and `CENTERMARK` are associative, so they follow when their lines, circles
or arcs move.

**Precision:** running object snaps (`OSNAP`: endpoint, midpoint, centre, node, quadrant, intersection, extension,
insertion, perpendicular, tangent, nearest, parallel), grid snap (`SNAP`, F9), grid (`GRIDDISPLAY`, F7), ortho (F8),
polar tracking (F10) and dynamic input (F12). Settings are in `DSETTINGS`.

**Polylines:** `PEDIT` closes, opens, joins, sets width, fits splines, removes curves and reverses. You can also add
and remove vertices and turn arcs into line segments.

## Modifying

`MOVE`, `COPY`, `ROTATE`, `SCALE`, `MIRROR`, `STRETCH`, `OFFSET`, `TRIM`, `EXTEND`, `FILLET`, `CHAMFER`, `BREAK`,
`BREAKATPOINT`, `JOIN`, `LENGTHEN`, `EXPLODE`, `ALIGN`, `ARRAY` (`ARRAYRECT`, `ARRAYPOLAR`, `ARRAYPATH`), `DIVIDE`,
`MEASURE`, `REVERSE`, `ERASE`, `OVERKILL` (removes duplicates and merges overlapping lines), `DRAWORDER`, `MATCHPROP`,
`CHPROP` and `SETBYLAYER`.

**Grips:** select an object and drag a grip to stretch it. Moving the end of a wall also moves the walls joined to it.

**Clipboard:** ⌘C, ⌘X and ⌘V copy, cut and paste objects, pasting at the cursor. The same clipboard is used by
`COPYCLIP`, `CUTCLIP`, `COPYBASE` (with a base point), `PASTECLIP`, `PASTEORIG` (at the original coordinates) and
`PASTEBLOCK` (as a block). You can paste between open drawings, and the block definitions and layers the objects use
are copied with them.

## Annotation

- **Text:** `TEXT`, `MTEXT`, `TEXTEDIT`, `TEXTSTYLE`, `SCALETEXT`, `JUSTIFYTEXT`, `TXT2MTXT` and `FIND` (find and
  replace). Special symbols: `%%d` (°), `%%c` (⌀), `%%p` (±).
- **Fields:** `FIELD` inserts text that updates automatically, such as an object's area or length, a property, a
  variable, a count or a date. `UPDATEFIELD` refreshes fields.
- **Dimensions:** `DIM` (smart), `DIMLINEAR`, `DIMALIGNED`, `DIMANGULAR`, `DIMARC`, `DIMRADIUS`, `DIMDIAMETER`,
  `DIMORDINATE`, `DIMBASELINE`, `DIMCONTINUE`, `QDIM`, `DIMSPACE`, `DIMEDIT`, `DIMTEDIT` and `DIMSTYLE`.
- **Leaders:** `LEADER`, `MLEADER`, `MLEADERSTYLE` (text height, annotative, layer) and `MLEADERALIGN`.
- **Tables:** `TABLE`, then `TABLEEDIT` to edit cells, add formulas (`=SUM(...)`, `AVERAGE`…), insert or delete rows and
  columns and set column widths. `TABLEEXPORT` writes a table to CSV.
- **Annotative scaling:** `ANNOTATIVE` makes text, leaders and tables follow the annotation scale (`CANNOSCALE`). For
  example, switching from 1:50 to 1:100 doubles their model height. Edit the list of scales with `SCALELISTEDIT`.

## Layers and properties

- The **Layers** panel and the `LAYER` command create layers and set them current, on/off, frozen/thawed,
  locked/unlocked, and set colour, linetype and lineweight. The shortcuts `LAYISO`, `LAYUNISO`, `LAYOFF`, `LAYON`,
  `LAYFRZ`, `LAYTHW`, `LAYLCK`, `LAYULK`, `LAYMCUR` and `LAYDEL` do the same from a selected object.
- **Layer filters** (`LAYERFILTER`): wildcards such as `A-*`, plus filters for on, used or unlocked layers. Named
  filters are saved in the drawing.
- **Layer states** (`LAYERSTATE`, or the manager dialog): save and restore the visibility and properties of all
  layers.
- `COLOR`, `LINETYPE`, `LTSCALE` and `LWEIGHT` set the defaults for new objects. `PURGE` removes unused definitions and
  `RENAME` renames them.
- The **Properties** panel shows and edits the selected objects. `PROPERTIES`/`LIST` print their properties and
  `SETPROP` sets any property from the command line, for example `SETPROP #12 height 2800`.

## Blocks, attributes and groups

- `BLOCK` defines a block and `INSERT` places it. Blocks can be nested. `WBLOCK` writes a block to a file, `BASE` sets
  the drawing's insertion point and `BLOCKBASE` moves a block's base point.
- `BLOCKREPLACE` swaps one block for another, `BCOUNT` counts references and `BFLIP` flips a reference.
  `INSERT` can also redefine a block from a file.
- **Attributes:** `ATTDEF`, `ATTEDIT`, `BATTMAN` (edits definitions from the command line), `ATTSYNC`, `ATTEXT` and
  `DATAEXTRACTION` (into a table or a CSV file).
- **Groups:** `GROUP` (Create/Add/Remove/Explode/Rename/List) and `UNGROUP`. Clicking a member selects the whole group.
  Set `PICKSTYLE` to 0 to pick members on their own.
- `XREF` attaches another drawing and `IMAGEATTACH` places a raster image.

## BIM: building elements and levels

Building elements are real objects with parameters. They appear in plan with cut lines and hatching, in 3D, in sections
and elevations, and in schedules.

- **Levels:** `LEVEL` creates, lists, renames and deletes levels and sets the current one, with elevations and heights.
  The Levels panel does the same. Each element belongs to a level.
- **Walls:** `WALL` draws chains of joined walls, straight or curved, with a thickness, height, justification and type.
  `WALLBYLINES` turns lines into walls and `WALLJOIN` cleans up corners. Walls join at L, T and X junctions, including
  T-joins into curved walls. `WALLSWEEP` adds cornices and skirting boards, and `NICHE` cuts recesses. Walls under
  gable, shed or hip roofs fill up to the roof underside automatically.
- **Openings:** `DOOR`, `WINDOW` and `OPENING` place hosted openings that move with their wall. `OPENINGTYPE` manages a
  door/window type catalogue: changing a type's parameters updates every instance, and types can be imported from CSV.
  `MARKS` renumbers doors and windows (D01, W01…).
- **Curtain walls:** `CURTAINWALL`, with `CWGRID` to add or remove grid lines and set panels to glass, solid or empty.
- **Floors, roofs and ceilings:** `SLAB` (from points, a closed object or the walls around a point), `SLABSLOPE` (slope
  by arrow or angle), `ROOF` (flat, shed, gable or hip, including hip roofs on L-, T- and U-shaped footprints) and
  `CEILING` (hidden in views with the `CEILINGS` variable).
- **Circulation:** `STAIR`, `RAMP` (warns when steeper than 1:12) and `RAILING`.
- **Structure:** `COLUMN`, `BEAM`, `GRID` (auto-labelled grid lines) and `FOUNDATION` (strip footings under walls,
  isolated footings under columns, or pads).
- **Rooms:** `ROOM` (click inside walls or give points) reports area and volume. `ROOMSEPARATOR` draws virtual
  boundaries, and `ROOMUPDATE` recomputes rooms after walls change. Room tags sit at the most open point of the room and
  size themselves to fit.
- **Area plans:** `AREAPLAN` draws gross, rentable or custom area boundaries and reports totals per scheme.
- **Other:** `COMPONENT` places furniture and fixtures, and `BUILDING` creates quick massing (walls, floors and a roof
  from a rectangle).
- **Phases:** `PHASE` creates phases, sets the current phase, sets when objects are created or demolished, and sets the
  view filter. Existing work is shown half-tone and demolished work dashed.

## Documentation: views, tags and schedules

- **Sections and elevations:** `SECTION` places a section line in plan. Sheet viewports can show plans, ceiling plans,
  elevations, sections and 3D views, which are always generated from the current model. `VIEWDRAW` places an elevation,
  section or detail as 2D linework in model space, with level heads and grid bubbles. `VIEWUPDATE` regenerates these
  views.
- **Tags:** `TAG` labels a door, window, room or element with live values (mark, type, name, area, keynote), and
  `TAGALL` tags everything not yet tagged on a level.
- **Keynotes:** `KEYNOTE` defines keys, assigns them to elements and places a keynote legend.
- **Schedules:** `SCHEDULE` creates tables of walls, doors and windows (with mark and type), rooms (with volume), slabs,
  areas and keynotes. Schedules can be exported to CSV.

## Site and terrain

- `TOPO` builds a toposurface from points with elevations, contour polylines, an XYZ/CSV file or typed x,y,z values.
- `CONTOURS` sets the contour interval and major lines.
- `BUILDINGPAD` levels the terrain inside a boundary to a pad elevation.
- `POINTSIMPORT` reads survey point files (CSV/TSV/TXT, including P,N,E,Z,D).

## 3D modelling

- **Solids:** `BOX`, `CYLINDER`, `CONE`, `SPHERE`, `EXTRUDE`, `REVOLVE`, `PRESSPULL` (extrudes the area around a picked
  point, with holes), `LOFT`, `SWEEP` and `PIPE`.
- **Booleans:** `UNION`, `SUBTRACT` and `INTERSECT` produce closed meshes. `SLICE` cuts solids with a vertical or
  horizontal plane, and `INTERFERE` finds overlapping volumes and can create them as solids.
- Loft, sweep, pipe and press/pull results are independent solids. They don't update when the source profile changes.

## 3D view and rendering

- **Navigation:** orbit, pan and zoom with the trackpad or mouse. Use the **view cube** (`NAVVCUBE`) to click a face,
  edge or corner. Standard views are `TOPVIEW`, `FRONTVIEW`, `ISOVIEW` and so on, and `ORBITSELECTION` zooms and orbits
  around the selection. `WALK` starts a first-person walkthrough.
- **Visual styles** (`VSCURRENT`): wireframe, hidden, shaded, shaded with edges, realistic, conceptual, X-ray, sketchy.
- **Saved cameras:** `SAVECAMERA` and `CAMERA`.
- **Section box** (`SECTIONBOX`): cuts the model live. It can be fitted to the selection or a level, is adjusted with
  sliders, and is saved with the drawing.
- **Sun study** (`SUNSTUDY`): date and time sliders and a day animation, using the project location.
- **Materials** (`MATERIALS`): the material editor sets colour, roughness, metalness, transparency and texture.
- **Render** (`RENDER`): renders the model at a chosen size, with sun date and time, exposure and a sky, white or
  transparent background. Built-in presets range from Draft 720p to Print 4K, and you can save your own. Renders save
  as images, and **Export Video** makes a turntable MP4.

## Sheets, plotting and PDF

- **Sheets:** `LAYOUT` creates and manages sheets and their paper size. `MVIEW` places viewports (plan, elevation,
  section, 3D) at a scale such as 1:100, and `VPLOCK` locks a viewport's scale and position.
- **Title blocks:** `TITLEBLOCK` edits the sheet's title block fields (sheet title and number, scale, date, revision)
  and the project information shared by all sheets.
- **Page setup** (`PAGESETUP`, ⇧⌘P): paper, scale, lineweights, colour/monochrome/greyscale plotting and a plot
  stamp.
- **Plot** (`PLOT`, ⌘P) and **Preview** (`PREVIEW`, ⌥⇧⌘P): the plot dialog shows a live preview, and printing or
  saving uses exactly the previewed PDF.
- **Publish** (`PUBLISH`): writes all sheets to one multi-page PDF.

## Analysis

- `TAKEOFF`: quantity takeoff of walls (net of openings, per type and material), slabs, roofs, columns, beams,
  doors, windows and rooms. It can also be written to CSV.
- `COSTESTIMATE` with `UNITPRICE`: a cost estimate from unit rates stored in the drawing or loaded from a JSON price
  table.
- `ROOMSCHEDULE`: rooms with net area (columns deducted), gross area (to wall centre lines), perimeter and volume.
- `CLASHDETECT`: hard clashes between elements and 3D solids, with select and zoom-to. Touching, hosted and joined
  elements are ignored.
- `CHECKMODEL`: a model audit that reports walls without height, openings wider than or outside their host,
  overlapping or duplicate walls and rooms, unnamed or duplicate rooms and missing levels. `AUDIT` checks and repairs
  the drawing's data.
- `SUNPOSITION`: sun azimuth and altitude, sunrise and sunset for a date and time at the project location.
- Inquiry: `DIST`, `AREA`, `ID`, `LIST`, `MASSPROP`, `MEASUREGEOM`, `COUNT`, `STATUS`.

## Import and export

| Format | Import | Export | Notes |
| --- | --- | --- | --- |
| `.archi` | Open, `IMPORT` | Save | Native JSON project format |
| DXF | Open, `IMPORT` | `EXPORT`, `DXFR12OUT` | Lines, arcs, polylines, text, hatches, blocks, attributes, images, multileaders and paper-space layouts with viewports. `DXFR12OUT` writes R12 for older software |
| IFC 2x3 / IFC4 | `IFCIMPORT` | `EXPORT` | Walls, slabs, columns, beams, doors, windows, openings and spaces become native elements, with storeys, units, materials, wall types and property sets. Other products come in as meshes. GUIDs are kept on re-export |
| SVG | `SVGIMPORT` | `EXPORT` | Paths, shapes and text |
| OBJ, STL | `MESHIMPORT` | `EXPORT` | STL in ASCII and binary |
| 3MF | `MESHIMPORT` | `EXPORT3MF` | |
| glTF (GLB) | | `EXPORT` | |
| USD | | `USDEXPORT` | `.usda` text or `.usdz` package |
| GeoJSON | `GEOJSONIMPORT` | `GEOJSONEXPORT` | WGS84 is converted around the project location |
| CSV/TSV/XYZ points | `POINTSIMPORT` | `POINTSEXPORT` | Survey points, including PNEZD |
| CSV | | `EXPORT`, `TABLEEXPORT`, `ATTEXT` | Schedules, tables, attributes |
| PDF | | `PLOT`, `PUBLISH`, `EXPORT` | Vector, true scale |
| PNG | | `EXPORT`, `RENDER` | |

**File ▸ Import…** (⇧⌘I) and `IMPORTFILE` accept any of the importable formats and merge the file into the current
drawing, scaled to its units.

## Scripting and AI agents

- **Script files:** `SCRIPT` runs a `.scr` file of command lines, as in AutoCAD. A blank line or `;` is Enter.
  `SCRIPTTEXT` runs lines given as text. `SCRIPTRECORD` records what you type and pick as a script.
- **JavaScript console** (Script ribbon tab, ⌥⌘J or `SCRIPTCONSOLE`/`JS`): the `archi` API reads and edits the document, runs commands and creates
  building elements. Each change is one undo step. The **script library** (`SCRIPTLIBRARY`) keeps your scripts, and
  `startup.js` runs in every new window if enabled in Settings. See [SCRIPTING.md](SCRIPTING.md).
- **Agent server:** a local JSON-RPC server in the running app (off by default, on 127.0.0.1 only, token-protected)
  lets AI agents drive the open document live. Configure it with `AGENTSETTINGS`.
- **MCP:** `archi-cli --mcp project.archi` is a Model Context Protocol server for Claude Desktop, Claude Code and other
  clients. It provides tools for commands, documents, import, takeoff, cost, schedules, clashes, model checking and sun
  position. `CONNECTCLAUDE` explains the setup. See [AGENT-API.md](AGENT-API.md).
- **Command-line tool:** `archi-cli` also converts files, runs scripts headless and has a REPL.

## Settings and customisation

`OPTIONS` (⌘,) opens Settings, where you can change:

- units, grid and snaps
- autosave interval
- canvas background and crosshair size (`CURSORSIZE`)
- accent colour
- quick access toolbar
- recent files limit
- agent server and scripts

**Keyboard shortcuts** can be assigned to any command. For example, record ⇧⌘W for `WALL`. Your shortcuts take
priority over menu shortcuts. **Reset to defaults** restores every setting. All changes apply without a restart.

## Keyboard and mouse

| Keys | Action |
| --- | --- |
| Type anywhere | Start a command on the command line |
| Enter / Space | Finish input, repeat the last command |
| Esc | Cancel the command, clear the selection |
| Right-click | Enter while a command runs, context menu when idle |
| Tab | Accept autocomplete |
| ↑ / ↓ | Command history / suggestions |
| F3 · F7 · F8 · F9 · F10 · F12 | Object snap · grid · ortho · grid snap · polar tracking · dynamic input |
| Scroll wheel / pinch | Zoom about the cursor |
| Two-finger scroll, middle-drag, Space+drag | Pan |
| Double middle-click, ⌘0 | Zoom extents |
| ⌘= / ⌘- | Zoom in / out |
| Drag left → right / right → left | Window / crossing selection |
| Shift-click | Toggle an object in the selection |
| Double-click text | Edit text |
| Delete | Erase the selection |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| ⌘C / ⌘X / ⌘V | Copy / Cut / Paste objects |
| ⌘A / ⇧⌘A | Select all / deselect all |
| ⌥⌘1 … ⌥⌘4 | 2D · 3D · Split · Sheets |
| ⌥⌘P | Show / hide panels |
| ⌥⌘J | Script console |
| ⌘N / ⌘O / ⌘S / ⇧⌘S / ⌘W | New · Open · Save · Save As · Close |
| ⇧⌘I | Import |
| ⌘P / ⇧⌘P / ⌥⇧⌘P | Plot · Page setup · Plot preview |
| ⌘K | Search commands |
| ⌃0 | Clean screen |
| ⌘, | Settings |
| ⇧⌘/ | Command reference |

## Command reference

Every command can be typed on the command line, used in scripts and called by agents. Aliases are alternative names.
Any system variable can also be typed as a command (for example `TEXTSIZE 350`), and `HELP <command>` describes a
command inside the app. This table is generated from the command definitions in the source
(`python3 docs/gen_command_reference.py`).

<!-- BEGIN COMMAND REFERENCE -->
312 commands.

### Draw

| Command | Aliases | Description |
| --- | --- | --- |
| `ARC` | `A` | Draws an arc (3 points, start-center-end, start-end-radius, center-start-angle, continue). |
| `BOUNDARY` | `BO`, `BPOLY` | Creates closed polylines from the area enclosed around a picked point. |
| `BOUNDINGBOX` | `BBOX` | Draws the rectangle bounding the selected objects. |
| `BOX` |  | Creates a 3D solid box. |
| `CENTERLINE` | `CL` | Creates an associative centre line between two lines. |
| `CENTERMARK` | `CM`, `DIMCENTER`, `DCE` | Adds associative centre marks to circles and arcs. |
| `CIRCLE` | `C` | Draws a circle (center/radius, diameter, 2P, 3P, tangent-tangent-radius). |
| `CONE` |  | Creates a 3D solid cone or frustum. |
| `CYLINDER` | `CYL` | Creates a 3D solid cylinder. |
| `DLINE` | `DL`, `DOUBLELINE` | Draws double lines (two parallel polylines with end caps). |
| `DONUT` | `DO`, `DOUGHNUT` | Draws filled rings or solid dots. |
| `ELLIPSE` | `EL` | Draws an ellipse or elliptical arc. |
| `EXTRUDE` | `EXT` | Extrudes closed 2D objects into 3D solids. |
| `HATCH` | `H`, `BHATCH`, `BH` | Fills an enclosed area or selected objects with a hatch pattern or solid fill. |
| `LINE` | `L` | Draws straight line segments. |
| `PLINE` | `PL` | Draws a 2D polyline of line and arc segments. |
| `POINT` | `PO` | Creates point objects (style: PDMODE/PDSIZE). |
| `POLYGON` | `POL` | Draws an equilateral closed polyline. |
| `PTYPE` | `DDPTYPE` | Sets the point display style (PDMODE) and size (PDSIZE). |
| `RAY` |  | Draws a semi-infinite construction line. |
| `RECTANG` | `REC`, `RECTANGLE` | Draws a rectangular polyline (optionally filleted or chamfered). |
| `REGION` | `REG` | Converts closed chains of lines/arcs into closed polylines (regions). |
| `REVCLOUD` |  | Draws a revision cloud (polygonal, rectangular or from an object). |
| `REVOLVE` | `REV` | Revolves closed 2D objects about an axis into 3D solids. |
| `SOLID` | `SO` | Creates solid-filled triangles and quadrilaterals (AutoCAD point order 1-2-3-4). |
| `SPHERE` |  | Creates a 3D solid sphere. |
| `SPLINE` | `SPL` | Draws a smooth curve through fit points. |
| `STAR` |  | Draws a star-shaped closed polyline. |
| `TABLE` | `TB` | Inserts an empty table. |
| `WIPEOUT` |  | Creates a masking area (solid background fill) that covers objects beneath. |
| `XLINE` | `XL` | Draws construction lines of (practically) infinite length. |

### Modify

| Command | Aliases | Description |
| --- | --- | --- |
| `ALIGN` | `AL` | Aligns objects with other objects using source/destination point pairs. |
| `ARRAY` | `AR` | Creates copies of objects in a rectangular, polar or path pattern. |
| `ARRAYPATH` |  | Array of objects evenly spaced along a path. |
| `ARRAYPOLAR` |  | Polar array of objects around a center point. |
| `ARRAYRECT` |  | Rectangular array of objects in rows and columns. |
| `BREAK` | `BR` | Breaks an object between two points. |
| `BREAKATPOINT` | `BRP` | Breaks an object into two at a single point. |
| `CHAMFER` | `CHA` | Bevels the corner between two lines (distance or length/angle method). |
| `CHPROP` | `CHANGE`, `CH`, `-CH` | Changes color, layer, linetype, lineweight or material of objects. |
| `COPY` | `CO`, `CP` | Copies objects (multiple copies, or a linear array). |
| `DIVIDE` | `DIV` | Places points or blocks at equal intervals along an object. |
| `DRAWORDER` | `DR` | Changes the draw order of objects (front, back, above, under). |
| `ERASE` | `E`, `DELETE` | Removes objects from the drawing. |
| `EXPLODE` | `X` | Breaks compound objects (polylines, blocks, hatches, dimensions) into their parts. |
| `EXTEND` | `EX` | Extends objects to meet boundary edges (all objects by default). |
| `FILLET` | `F` | Rounds the corner between two objects (radius 0 = sharp corner). |
| `HATCHTOBACK` |  | Sends all hatches behind other objects. |
| `JOIN` | `J` | Joins lines, arcs and polylines at their end points. |
| `LENGTHEN` | `LEN` | Changes the length of lines, arcs and open polylines (Delta/Percent/Total). |
| `MATCHPROP` | `MA`, `PAINTER` | Applies the properties of a source object to other objects. |
| `MEASURE` | `ME` | Places points or blocks at measured intervals along an object. |
| `MIRROR` | `MI` | Creates a mirrored copy of objects. |
| `MOVE` | `M` | Moves objects a specified distance in a specified direction. |
| `OFFSET` | `O` | Creates parallel copies of lines, arcs, circles and polylines. |
| `OOPS` |  | Restores the objects removed by the last ERASE. |
| `OVERKILL` | `-OVERKILL` | Removes duplicate objects and merges overlapping collinear lines. |
| `PEDIT` | `PE` | Edits polylines: close/open, join, width, spline, decurve, reverse. |
| `REVERSE` |  | Reverses the vertex order of lines, polylines, splines and arcs. |
| `ROTATE` | `RO` | Rotates objects around a base point. |
| `SCALE` | `SC` | Enlarges or reduces objects around a base point. |
| `SELECT` |  | Selects objects and keeps them as the current selection. |
| `SELECTALL` | `AI_SELALL` | Selects all selectable objects on unlocked layers (current level). |
| `SETBYLAYER` | `SBL` | Sets color, linetype and lineweight of objects (and block contents) to ByLayer. |
| `STRETCH` | `S` | Stretches objects crossed by a window; objects fully inside are moved. |
| `TEXTTOFRONT` |  | Brings all text, dimensions and leaders in front of other objects. |
| `TRIM` | `TR` | Trims objects at cutting edges (all objects are cutting edges by default). |

### Edit

| Command | Aliases | Description |
| --- | --- | --- |
| `COPYBASE` |  | Copies objects to the clipboard with a base point. |
| `COPYCLIP` |  | Copies objects to the clipboard. |
| `CUTCLIP` |  | Moves objects to the clipboard (removes them from the drawing). |
| `PASTEBLOCK` |  | Pastes the clipboard as a block reference. |
| `PASTECLIP` |  | Pastes the clipboard at an insertion point. |
| `PASTEORIG` |  | Pastes the clipboard at its original coordinates. |
| `REDO` | `MREDO` | Reverses the last undo. |
| `U` |  | Reverses the most recent action. |
| `UNDO` |  | Reverses actions: a count, or Mark/Back (to a mark) and BEgin/End (group several commands into one step). |

### Select

| Command | Aliases | Description |
| --- | --- | --- |
| `FILTER` | `FI`, `SELECTFILTER` | Selects objects matching a filter expression (type=circle & radius>50 \| layer=A-*); filters can be saved by name. |
| `QSELECT` | `QSEL` | Quick select: objects of a type whose property matches a value (e.g. QSELECT Circle radius > 50). |
| `QSELECTDIALOG` | `QSD`, `QUICKSELECT` | Quick Select dialog: type, property, operator and value with a live match count. *(app)* |
| `SELECTCHAIN` | `SELCHAIN`, `SELECTCONTOUR` | Selects the chain (contour) of curves connected end-to-end with the picked one. |
| `SELECTINTERSECTING` | `SELINT` | Selects every object that intersects the picked one. |
| `SELECTINVERT` | `INVSEL`, `SELINV` | Inverts the selection (selects every other selectable object). |
| `SELECTLAYER` | `SELLAYER`, `LAYSEL` | Selects every object on the given layer(s) (wildcards allowed) or on the layer of a picked object. |
| `SELECTSIMILAR` | `SELSIM` | Selects all objects similar to the selected ones (type, plus the properties in SELECTSIMILARMODE). |
| `SELECTTYPE` | `SELTYPE` | Selects objects by type or category (Line, Circle, Text, Annotation, Curve, Wall, Door, Element…); several types separated by commas. |
| `SELSET` | `NAMEDSELECTION` | Saves, restores, lists and deletes named selection sets (stored in the drawing). |

### Annotate

| Command | Aliases | Description |
| --- | --- | --- |
| `ANNOTATIVE` | `ANNO` | Makes text, leaders and tables annotative (height follows CANNOSCALE) or turns it off. |
| `DIM` |  | Smart dimension: picks an object (line → linear/aligned, arc → radius, circle → diameter) or two points. |
| `DIMALIGNED` | `DAL`, `DIMALI` | Creates a dimension aligned with its extension line origins. |
| `DIMANGULAR` | `DAN`, `DIMANG` | Dimensions the angle between lines, of an arc, or of three points. |
| `DIMARC` | `DAR` | Dimensions the length of an arc. |
| `DIMBASELINE` | `DBA`, `DIMBASE` | Creates dimensions from the baseline of the last dimension. |
| `DIMCONTINUE` | `DCO`, `DIMCONT` | Continues a chain of dimensions from the last one. |
| `DIMDIAMETER` | `DDI`, `DIMDIA` | Dimensions the diameter of a circle or arc. |
| `DIMEDIT` | `DED`, `DIMED` | Edits dimension text: Home (measured value), New text (<> = measurement). |
| `DIMLINEAR` | `DLI`, `DIMLIN` | Creates a horizontal, vertical or rotated linear dimension. |
| `DIMORDINATE` | `DOR`, `DIMORD` | Creates X or Y ordinate dimensions from the origin (0,0). |
| `DIMRADIUS` | `DRA`, `DIMRAD` | Dimensions the radius of an arc or circle. |
| `DIMSPACE` |  | Evenly spaces parallel linear/aligned dimensions from a base dimension (0 aligns them). |
| `DIMSTYLE` | `D`, `DST`, `DDIM`, `-DIMSTYLE` | Creates, edits, lists and sets dimension styles. |
| `DIMTEDIT` | `DIMTED` | Moves the text / dimension line of a dimension to a new location. |
| `FIELD` |  | Inserts text containing a field (area, length, property, variable, count, date) that updates automatically. |
| `FIND` |  | Finds (and optionally replaces) text in texts, leaders, dimensions, tables and attributes. |
| `JUSTIFYTEXT` | `TEXTALIGN` | Changes the justification of text without moving it. |
| `KEYNOTE` | `KN` | Keynotes: define keys, assign them to elements with a keynote tag, and place a keynote legend table. |
| `LEADER` | `LE`, `LEAD`, `QLEADER` | Creates a leader line with annotation text. |
| `MARKS` | `RENUMBER`, `NUMBEROPENINGS` | Renumbers door and window marks per level in reading order (D01…, W01…), or sets a mark. |
| `MLEADER` | `MLD` | Creates a multileader (arrowhead, landing, text). |
| `MLEADERALIGN` | `MLA` | Aligns the landings (text) of leaders with a reference leader, vertically or horizontally. |
| `MLEADERSTYLE` | `MLS` | Creates, edits, lists and sets multileader styles (text height, annotative, layer). |
| `MTEXT` | `MT`, `T` | Creates paragraph (multiline) text inside a width. |
| `QDIM` |  | Quickly dimensions the end points of selected objects (continuous or baseline). |
| `SCALELISTEDIT` | `SCALELIST` | Edits the list of annotation scales (Add/Delete/Reset/List). |
| `SCALETEXT` |  | Changes the height of text objects (new height or scale factor) keeping their insertion points. |
| `TABLEEDIT` | `TABEDIT`, `TABLEDIT` | Edits a table: cell text or =formula (SUM, AVERAGE…), insert/delete rows and columns, column widths. |
| `TABLEEXPORT` | `TABLEEXP` | Exports a table to a CSV file. |
| `TAG` | `TAGBYCATEGORY`, `ELEMENTTAG` | Tags a door, window, room or element with a live label (mark, type, name, area, keynote…). |
| `TAGALL` | `TAGALLNOTTAGGED` | Tags every untagged door, window and/or room on the current level. |
| `TEXT` | `DT`, `DTEXT` | Creates single-line text objects. |
| `TEXTEDIT` | `ED`, `DDEDIT` | Edits text, leader, dimension text, table cells or attribute values. |
| `TEXTSTYLE` | `STYLE`, `ST`, `-STYLE` | Creates or modifies a text style and makes it current. |
| `TXT2MTXT` | `TEXTTOMTEXT` | Combines single-line texts into one multiline text (top to bottom). |
| `UPDATEFIELD` | `UPDFIELD` | Updates fields (including date fields) in the selected text. |

### Blocks

| Command | Aliases | Description |
| --- | --- | --- |
| `ATTDEF` | `ATT`, `-ATTDEF` | Defines an attribute (tag, prompt, default) to include in a block. |
| `ATTEDIT` | `ATE`, `-ATTEDIT`, `EATTEDIT` | Changes attribute values of a block reference. |
| `ATTEXT` | `-ATTEXT`, `ATTEXTRACT` | Extracts block reference attributes to a CSV file (or the command line). |
| `ATTSYNC` |  | Updates block references with the current attribute definitions of their block. |
| `BASE` |  | Sets the drawing's insertion base point (INSBASE), used when it is inserted as a block. |
| `BATTMAN` | `-BATTMAN` | Edits the attribute definitions of a block (prompt, default, tag, delete) and syncs references. |
| `BCOUNT` | `BLOCKCOUNT` | Counts block references (including nested ones) in the drawing or a selection. |
| `BFLIP` | `FLIP`, `BLOCKFLIP` | Flips block references about their insertion point (dynamic flip parameter, state kept in the reference). |
| `BLOCK` | `B`, `-BLOCK`, `BMAKE` | Creates a block definition from selected objects. |
| `BLOCKBASE` | `BBASE`, `BASEPOINT` | Changes a block definition's base point; references stay where they are. |
| `BLOCKREPLACE` | `BREPLACE` | Replaces all references of one block with another (keeps attributes with matching tags). |
| `DATAEXTRACTION` | `DX`, `EATTEXT` | Extracts block counts or attributes into a table in the drawing (or a CSV file). |
| `GROUP` | `G`, `-GROUP` | Creates and manages named groups (Create/Add/Remove/Explode/REName/List); picking a member selects the group (PICKSTYLE). |
| `IMAGEATTACH` | `IAT`, `IMAGE` | Places a raster image reference (path, insertion point, width, rotation). |
| `INSERT` | `I`, `-INSERT`, `DDINSERT` | Inserts a block reference (scale, rotation, attributes). |
| `UNGROUP` | `UNG` | Dissolves the groups of the selected objects. |
| `WBLOCK` | `W`, `-WBLOCK` | Writes a block, selected objects or the whole drawing to a new .archi file. |
| `XREF` | `XR`, `ATTACH`, `XATTACH` | Attaches an external drawing (the host imports it). |

### Layers

| Command | Aliases | Description |
| --- | --- | --- |
| `LAYERFILTER` | `LFILTER` | Filters the Layers panel (A-*, ~*TEXT*, #on #used); Save/Delete/List named filters kept in the drawing. *(app)* |
| `LAYERSTATE` | `LAS`, `LMAN`, `-LAYERSTATE` | Saves, restores, deletes or lists named layer states (saved in the drawing). *(app)* |

### Settings

| Command | Aliases | Description |
| --- | --- | --- |
| `AUDIT` |  | Checks the drawing for errors (duplicate IDs, dangling openings, missing layers/blocks) and fixes them. |
| `COLOR` | `COL`, `COLOUR` | Sets the color for new objects (CECOLOR). |
| `CURSORSIZE` |  | Sets the crosshair size as a percentage of the view (1–100). *(app)* |
| `DSETTINGS` | `DS`, `SE`, `DDRMODES` | Opens the drafting settings (snap, grid, polar, object snap). |
| `GRIDDISPLAY` | `DGRID`, `F7` | Shows/hides the drawing grid or sets its spacing. |
| `LAYDEL` |  | Deletes a layer and all objects on it. |
| `LAYER` | `LA`, `-LAYER`, `-LA` | Manages layers: make, set, new, rename, on/off, freeze/thaw, lock/unlock, color, linetype, lineweight, delete. |
| `LAYFRZ` |  | Freezes the layer of each selected object. |
| `LAYISO` |  | Isolates the layers of selected objects (turns the other layers off or locks them). |
| `LAYLCK` | `LAYLOCK` | Locks the layer of each selected object. |
| `LAYMCUR` |  | Makes the layer of a selected object current. |
| `LAYOFF` |  | Turns off the layer of each selected object. |
| `LAYON` |  | Turns on all layers. |
| `LAYTHW` |  | Thaws all layers. |
| `LAYULK` | `LAYUNLOCK` | Unlocks the layer of a selected object. |
| `LAYUNISO` |  | Restores the layers hidden or locked by LAYISO. |
| `LIMITS` |  | Sets the drawing limits (LIMMIN/LIMMAX). |
| `LINETYPE` | `LT`, `-LINETYPE`, `LTYPE` | Lists, loads, creates and sets the current linetype. |
| `LTSCALE` | `LTS` | Sets the global linetype scale factor. |
| `LWEIGHT` | `LW`, `LINEWEIGHT` | Sets the current lineweight and lineweight display. |
| `OPTIONS` | `OP`, `PREFERENCES`, `SETTINGS`, `CONFIG` | Opens Settings: units, grid and snaps, autosave, colors, shortcuts, toolbar, agents. *(app)* |
| `ORTHO` |  | Constrains cursor movement to horizontal/vertical (F8). |
| `OSNAP` | `OS`, `-OSNAP`, `DDOSNAP` | Sets running object snap modes (END,MID,CEN,NOD,QUA,INT,EXT,INS,PER,TAN,NEA,PAR, ON/OFF). |
| `PURGE` | `PU`, `-PURGE` | Removes unused blocks, layers, linetypes, text styles and dimension styles. |
| `RENAME` | `REN`, `-RENAME` | Renames blocks, layers, linetypes, text styles, dimension styles, levels, views and wall types. |
| `SAVETIME` | `AUTOSAVE` | Sets the autosave interval in minutes (0 turns autosave off). *(app)* |
| `SETVAR` | `SET` | Lists or changes system variables. |
| `SNAP` | `SN` | Turns grid snap on/off or sets the snap spacing (F9). |
| `UCS` |  | Sets the user coordinate system: World, Origin, Z rotation, 3point, Object, Previous, Named save/restore. |
| `UCSMAN` | `UC`, `DDUCS` | Lists named user coordinate systems and restores one. |
| `UNITS` | `UN`, `-UNITS` | Sets drawing units (mm, cm, m, in, ft) and optionally scales the drawing. |

### Inquiry

| Command | Aliases | Description |
| --- | --- | --- |
| `AREA` | `AA` | Calculates area and perimeter of points or objects (with Add/Subtract). |
| `CAL` | `QUICKCALC`, `QC` | Evaluates an arithmetic expression (+ - * / ^, sqrt, sin, cos, pi…). |
| `COUNT` |  | Counts objects by type, block and element type (selection or whole drawing). |
| `DIST` | `DI` | Measures the distance and angle between two points. |
| `ID` |  | Displays the coordinates of a location. |
| `LIST` | `LI`, `LS` | Lists the properties of selected objects. |
| `MASSPROP` |  | Reports area, perimeter, centroid, bounding box and volume of objects. |
| `MEASUREGEOM` | `MEA` | Measures distance, radius, angle, area or volume. |
| `STATUS` |  | Displays drawing statistics, modes and extents. |

### Architecture

| Command | Aliases | Description |
| --- | --- | --- |
| `AREAPLAN` | `AREABOUNDARY`, `GROSSAREA` | Creates area plan boundaries (Gross, Rentable or custom schemes) and reports totals per scheme. |
| `BEAM` |  | Draws structural beams between points. |
| `BUILDING` | `MASS`, `QUICKBUILDING` | Quick massing: a rectangle becomes walls, floor slabs and a roof on one or more storeys. |
| `CEILING` | `CEIL` | Creates a ceiling from points, a closed object or the walls around a point. |
| `COLUMN` | `COLUMNS` | Places structural columns (rectangular or round). |
| `COMPONENT` | `FURNITURE`, `COMP`, `FURN` | Places furniture, fixtures and other components from presets or custom sizes. |
| `CURTAINWALL` | `CW`, `CURTAIN` | Draws glazed curtain walls with mullion grids. |
| `CWGRID` | `CURTAINGRID` | Edits a curtain wall grid: add/remove grid lines, set panels (glass, solid, empty), uniform spacing. |
| `DOOR` | `DOORS` | Places doors in walls (default 900×2100). |
| `GRID` | `GRIDLINE`, `GR` | Places structural grid lines, auto-labelled 1,2,3 (vertical) and A,B,C (horizontal). |
| `LEVEL` | `LEVELS`, `LV` | Lists, creates, sets, renames and deletes levels; sets elevation and height. |
| `NICHE` | `RECESS` | Cuts a recess of a given depth into one face of a wall. |
| `OPENING` | `WALLOPENING` | Cuts empty openings in walls. |
| `OPENINGTYPE` | `DOORTYPE`, `WINDOWTYPE`, `TYPECATALOG` | Door/window type catalog: list, new, set type parameters (updates all instances), apply to openings, delete, import CSV. |
| `PHASE` | `PHASES`, `PHASING` | Manages construction phases: list, new, current phase, filter, created/demolished phase of objects. |
| `PROPERTIES` | `PR`, `PROPS`, `GETPROP` | Shows the properties of the selected object(s). |
| `RAILING` | `RAIL` | Draws a railing along a path. |
| `RAMP` |  | Creates a sloped ramp from its bottom to its top (width, rise); warns above 1:12. |
| `ROOF` | `RF` | Creates a flat, shed, gable or hip roof from a footprint. |
| `ROOM` | `SPACE`, `RM` | Places rooms bounded by walls (pick inside) or by points; reports area. |
| `ROOMSEPARATOR` | `ROOMSEP`, `RSL` | Draws room separation lines (virtual room boundaries used by ROOM, SLAB Walls, ROOMUPDATE). |
| `ROOMUPDATE` | `UPDATEROOMS`, `RU` | Recomputes the boundaries and areas of rooms placed by picking, after walls or separation lines changed. |
| `SCHEDULE` | `SCH` | Creates a schedule table (walls, doors, windows, rooms, slabs) or prints it. |
| `SETPROP` | `SP`, `SETPROPERTY` | Sets any property of objects: SETPROP #12 height 2800. |
| `SLAB` | `FLOOR`, `SB` | Creates a floor slab from points, a closed object or the walls around a point. |
| `SLABSLOPE` | `SLOPEARROW`, `SLOPE` | Slopes a slab by a slope arrow (low point, high point, rise) or angle; Flat resets. |
| `STAIR` | `STAIRS` | Creates a straight stair (width, rise, risers, tread). |
| `WALL` | `WA` | Draws a chain of joined walls (thickness, height, justification, type, arcs). |
| `WALLBYLINES` | `WALLFROMLINES`, `WBL` | Converts selected lines, arcs and polylines into walls. |
| `WALLJOIN` | `WJ`, `WALLCLEANUP` | Joins wall ends that nearly meet (extends/trims them to their intersection). |
| `WALLSWEEP` | `SWEEPWALL`, `CORNICE`, `SKIRTING` | Adds cornices, skirting boards or string courses along wall faces (or removes them). |
| `WINDOW` | `WIN` | Places windows in walls (default 1200×1200, sill 900). |

### Structure

| Command | Aliases | Description |
| --- | --- | --- |
| `FOUNDATION` | `FOOTING`, `FNDN` | Creates strip footings under walls, isolated footings under columns, or pads from points. |

### Site

| Command | Aliases | Description |
| --- | --- | --- |
| `BUILDINGPAD` | `PAD`, `SITEPAD` | Levels a toposurface inside a boundary to a pad elevation (cut and fill). |
| `CONTOURS` | `CONTOUR` | Sets the contour interval and major-line spacing of toposurfaces (0 = hide contours). |
| `TOPO` | `TOPOSURFACE`, `TERRAIN` | Creates a toposurface from points (with elevations), contour polylines, an XYZ/CSV file or typed x,y,z values. |

### 3D

| Command | Aliases | Description |
| --- | --- | --- |
| `INTERFERE` | `INF`, `CLASH` | Finds overlapping volumes between two sets of solids and can create them as new solids. |
| `INTERSECT` | `INTERSECTSOLIDS` | Keeps only the common volume of the selected solids. |
| `LOFT` |  | Creates a solid through closed cross-sections at given heights (in selection order). |
| `PIPE` | `TUBE` | Creates a round pipe (optionally hollow) along a path. |
| `PRESSPULL` | `PP`, `PUSHPULL` | Extrudes the area around a picked point (with islands as holes), a closed object, or changes an extrusion's height. |
| `SLICE` | `SL3D` | Cuts solids with a vertical plane through two points or a horizontal plane (XY) at a height. |
| `SUBTRACT` | `SU` | Subtracts solids from other solids. |
| `SWEEP` |  | Sweeps closed profiles along a path (profile X to the left of travel, Y up). |
| `UNION` | `UNI` | Combines selected 3D solids into one. |

### View

| Command | Aliases | Description |
| --- | --- | --- |
| `BACKVIEW` | `BACK` | Sets the 3D view to back. |
| `BOTTOMVIEW` | `BOTTOM` | Sets the 3D view to bottom. |
| `CAMERA` | `CAM`, `RESTORECAMERA` | Restores a saved 3D camera (or lists them). *(app)* |
| `CLEANSCREENOFF` |  | Restores the ribbon and panels after CLEANSCREENON. *(app)* |
| `CLEANSCREENON` | `CLEANSCREEN` | Clean screen: hides the ribbon and panels (Ctrl+0 toggles). *(app)* |
| `FRONTVIEW` | `FRONT` | Sets the 3D view to front. |
| `HISTORYPANEL` | `UNDOHISTORY`, `HISTORY` | Shows the undo history and command history panel. *(app)* |
| `ISOVIEW` | `ISO`, `SWISO` | Sets the 3D view to swiso. |
| `LAYOUT` | `LO`, `-LAYOUT`, `SHEET` | Creates, sets, renames and deletes sheets (layouts); sets paper size and title block. |
| `LEFTVIEW` | `LEFT` | Sets the 3D view to left. |
| `MATERIALS` | `MAT`, `RMAT`, `MATEDITOR`, `MATBROWSEROPEN` | Opens the material editor panel (color, roughness, metalness, transparency, texture). *(app)* |
| `MVIEW` | `MV`, `VIEWPORT` | Places a viewport on the current sheet (corners in paper mm, scale 1:n, view kind, level). |
| `NAVVCUBE` | `VIEWCUBE` | Shows or hides the view cube in 3D. |
| `NEISO` |  | Sets the 3D view to neiso. |
| `NWISO` |  | Sets the 3D view to nwiso. |
| `ORBITSELECTION` | `ORBITSEL`, `3DORBITSEL`, `ZOOMSELECTED3D` | Orbits around (and zooms to) the selected elements in 3D. *(app)* |
| `PAN` | `P`, `-PAN` | Moves the view by a displacement. |
| `REGEN` | `RE`, `REGENALL`, `REA`, `REDRAW`, `R` | Regenerates the display. |
| `RENDER` | `RR` | Renders the 3D model. |
| `RIGHTVIEW` | `RIGHT`, `SIDE` | Sets the 3D view to right. |
| `SAVECAMERA` | `CAMSAVE`, `NEWCAMERA` | Saves the current 3D camera by name (restored with CAMERA). *(app)* |
| `SECTION` | `SECTIONLINE`, `SECTIONMARK` | Places a section line (A–A…) in plan; section views and sheets use the current section. |
| `SECTIONBOX` | `SBOX`, `3DSECTIONBOX` | Section box in 3D: On/Off/Selection/Level/Reset; the box is saved with the drawing. *(app)* |
| `SEISO` |  | Sets the 3D view to seiso. |
| `SHOW2D` | `2D`, `PLAN` | Shows the 2D plan view. |
| `SHOW3D` | `3D`, `3DVIEW`, `MODEL3D` | Shows the 3D model view. |
| `SPLIT` | `SPLITVIEW`, `VPORTS` | Shows the plan and 3D views side by side. |
| `SUNSTUDY` | `SUN`, `SUNPROPERTIES` | Sun study panel in the 3D view: date and time sliders with a day animation. *(app)* |
| `TOOLPALETTES` | `TP`, `TOOLPALETTE` | Shows the tool palettes panel (grouped tools and My Tools). *(app)* |
| `TOOLPALETTESCLOSE` |  | Hides the tool palettes panel. *(app)* |
| `TOPVIEW` | `TOP`, `PLANVIEW` | Sets the 3D view to top. |
| `VIEW` | `V`, `-VIEW` | Saves, restores, lists and deletes named views. |
| `VIEWDRAW` | `DRAWINGVIEW`, `SECTIONVIEW`, `ELEVATIONVIEW` | Places an elevation or section of the model as a 2D drawing (with level heads and grid bubbles) in model space. |
| `VIEWUPDATE` | `UPDATEVIEWS` | Regenerates all placed elevation/section drawing views from the current model. |
| `VSCURRENT` | `VS`, `SHADEMODE` | Sets the visual style of the 3D view. |
| `WALK` | `3DWALK`, `WALKTHROUGH`, `3DFLY` | Starts a first-person walkthrough of the 3D model. |
| `WSCURRENT` | `WS`, `WORKSPACE` | Switches workspace (panels, views and ribbon tab), e.g. WSCURRENT 3D Modeling. *(app)* |
| `WSSAVE` |  | Saves the current window arrangement as a named workspace. *(app)* |
| `ZOOM` | `Z` | Zooms: All/Extents, Window, Previous, Center, Object, or a scale (2, 0.5x). |

### Output

| Command | Aliases | Description |
| --- | --- | --- |
| `PAGESETUP` | `PSETUP`, `PAGESETUPMANAGER` | Page setup of the active sheet or model: paper, plot style, lineweights, plot stamp, scale. *(app)* |
| `PREVIEW` | `PRE`, `PRINTPREVIEW`, `PLOTPREVIEW`, `PLOTDIALOG` | Plot dialog with a live preview: prints or saves exactly what is shown. *(app)* |
| `PUBLISH` | `BATCHPLOT`, `EXPORTSHEETS`, `PUBLISHPDF` | Publishes all sheets to one multi-page PDF (PUBLISH path.pdf, or Enter for a dialog). *(app)* |
| `TITLEBLOCK` | `TBEDIT`, `TITLEBLOCKEDIT` | Edits the active sheet's title block and the project information shown on all sheets. *(app)* |
| `VPLOCK` | `VPORTLOCK`, `LOCKVIEWPORT` | Locks or unlocks sheet viewports so their scale and position cannot change. *(app)* |

### File

| Command | Aliases | Description |
| --- | --- | --- |
| `CLOSE` |  | Closes the current drawing. |
| `DRAWINGRECOVERY` | `DRM`, `RECOVER` | Shows documents recovered from autosave after a crash. *(app)* |
| `DXFR12OUT` | `DXFOUTR12`, `SAVEASR12`, `DXF12` | Writes a DXF R12 (AC1009) file for older CAD/CAM software (splines, ellipses, hatches and MText are converted). |
| `EXPORT` | `EXP` | Exports the drawing (PDF, DXF, SVG, OBJ, STL, GLB, IFC, CSV, PNG). |
| `EXPORT3MF` | `3MFOUT`, `3MFEXPORT` | Exports the 3D model as a 3MF package (millimetres, one object per element). |
| `GEOJSONEXPORT` | `GEOJSONOUT` | Exports 2D entities (selection or all) as GeoJSON in WGS84 or local metres. |
| `GEOJSONIMPORT` | `GEOJSONIN` | Imports GeoJSON features (WGS84 lon/lat are projected around the project location; projected metres are used as-is). |
| `IFCIMPORT` | `IFCIN`, `-IFCIMPORT` | Imports an IFC (IFC2x3/IFC4) model: walls, slabs, columns, beams, doors, windows and spaces become BIM elements; other products become meshes. |
| `IMPORT` | `IMP` | Imports a DXF, SVG or .archi file into the drawing. |
| `IMPORTFILE` | `FILEIMPORT`, `IMPORTANY` | Imports a file by extension: .archi, .dxf, .ifc, .svg, .obj, .stl, .3mf, .geojson, .csv/.txt/.xyz points. |
| `MESHIMPORT` | `OBJIMPORT`, `STLIMPORT`, `3MFIMPORT`, `OBJIN`, `STLIN` | Imports an OBJ, STL or 3MF file as mesh solids (choose the file's units). |
| `NEW` | `QNEW` | Creates a new drawing. |
| `OPEN` |  | Opens a drawing (.archi, .dxf). |
| `PLOT` | `PRINT` | Plots the current sheet or view to PDF or a printer. |
| `POINTSEXPORT` | `PTEXPORT`, `EXPORTPOINTS` | Writes point entities (selection or all) to CSV: name,x,y,z,code,layer. |
| `POINTSIMPORT` | `CSVPOINTS`, `PTIMPORT`, `IMPORTPOINTS` | Imports survey points from CSV/TSV/TXT (X,Y[,Z][,name] with or without header, or P,N,E,Z,D). |
| `QUIT` | `EXIT` | Quits the application. |
| `SAVE` | `QSAVE` | Saves the drawing. |
| `SAVEAS` | `SA` | Saves the drawing under a new name. |
| `SCRIPT` | `SCR` | Runs a script file of command lines. |
| `SCRIPTTEXT` | `RUNSCRIPT` | Runs command lines given as text (lines separated by newlines, \n or \|). |
| `SVGIMPORT` | `SVGIN`, `-SVGIMPORT` | Imports SVG paths, lines, polylines, polygons, circles, ellipses, rectangles and text as drawing entities. |
| `USDEXPORT` | `USDZEXPORT`, `USDAEXPORT`, `USDZOUT`, `USDOUT` | Exports the 3D model as USD: .usda text or .usdz package (UsdPreviewSurface materials). |

### Analysis

| Command | Aliases | Description |
| --- | --- | --- |
| `CHECKMODEL` | `MODELCHECK`, `AUDITMODEL`, `BIMAUDIT` | Checks the model: walls without height, openings wider than or outside their host, overlapping/duplicate walls and rooms, unnamed or duplicate rooms, missing levels. |
| `CLASHDETECT` | `CLASHES`, `CLASHTEST` | Finds hard clashes between elements and 3D solids (touching and hosted/joined elements are ignored); lists, selects and zooms. |
| `COSTESTIMATE` | `COST`, `ESTIMATE` | Cost estimate from the takeoff and unit rates (UNITPRICE drawing rates or a JSON table); optional CSV. |
| `ROOMSCHEDULE` | `ROOMAREAS`, `AREASCHEDULE` | Room area schedule with net (minus columns) and gross (to wall centre lines) areas, perimeter and volume; optional CSV. |
| `SUNPOSITION` | `SUNPOS`, `SUNCALC` | Sun azimuth/altitude, sunrise and sunset for a date, time and the project location; stores SUNAZIMUTH/SUNALTITUDE. |
| `TAKEOFF` | `QTO`, `QUANTITIES` | Quantity takeoff: wall areas/volumes (net of openings) per type and material, slabs, roofs, columns, beams, door/window counts; optional CSV. |
| `UNITPRICE` | `COSTRATE`, `RATE` | Stores a unit rate in the drawing (COST:<category>[:<type>]:<measure>) used by COSTESTIMATE. |

### Scripting

| Command | Aliases | Description |
| --- | --- | --- |
| `AGENTSETTINGS` | `AGENTS`, `AGENTSERVER` | Agent server settings: port, start/stop, token, auto-start. *(app)* |
| `CONNECTCLAUDE` | `MCPHELP`, `CLAUDE` | Explains how to connect Claude (archi-cli --mcp or the local agent server). *(app)* |
| `SCRIPTCONSOLE` | `JS`, `JSCONSOLE`, `CONSOLE` | Shows or hides the JavaScript console (⌥⌘J). *(app)* |
| `SCRIPTLIBRARY` | `SCRIPTS` | Opens the script library folder (startup.js runs in every new window). *(app)* |

### Tools

| Command | Aliases | Description |
| --- | --- | --- |
| `ALIAS` | `ALIASEDIT` | Defines command aliases and macros (Define/Delete/List/Global/Load/Save); ";" in a macro is Enter. |
| `SCRIPTRECORD` | `ACTRECORD`, `RECSCRIPT` | Records typed commands and picks as a script (Start/Stop); saved to a .scr file. |

### Help

| Command | Aliases | Description |
| --- | --- | --- |
| `ABOUT` |  | About Oanarina Archi Tool: version, license and credits. *(app)* |
| `COMMANDS` | `CMDLIST` | Lists every command with its aliases and summary. |
| `COMMANDSEARCH` | `CMDSEARCH`, `SEARCHCOMMANDS` | Opens the command search palette (⌘K). *(app)* |
| `HELP` | `?`, `F1` | Lists commands by category, or describes one command. |

*(app)*: available in the Mac app (command line, menus, scripts and the agent server), not in headless `archi-cli`.

<!-- END COMMAND REFERENCE -->
