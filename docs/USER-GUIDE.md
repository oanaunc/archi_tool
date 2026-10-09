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
7. [Parametric constraints](#parametric-constraints)
8. [Annotation](#annotation)
9. [Layers and properties](#layers-and-properties)
10. [Blocks, attributes and groups](#blocks-attributes-and-groups)
11. [BIM: building elements and levels](#bim-building-elements-and-levels)
12. [Documentation: views, tags and schedules](#documentation-views-tags-and-schedules)
13. [Site and terrain](#site-and-terrain)
14. [3D modelling](#3d-modelling)
15. [3D view and rendering](#3d-view-and-rendering)
16. [Sheets, plotting and PDF](#sheets-plotting-and-pdf)
17. [Analysis](#analysis)
18. [Import and export](#import-and-export)
19. [Scripting and AI agents](#scripting-and-ai-agents)
20. [Settings and customisation](#settings-and-customisation)
21. [Keyboard and mouse](#keyboard-and-mouse)
22. [Tutorial videos](#tutorial-videos)
23. [Command reference](#command-reference)

## Getting started

**Requirements:** macOS 14 or later, on Apple silicon or Intel, or Windows 10 or 11 (64-bit). The Windows version has the same tools and commands; where this guide says ⌘ (Command), use Ctrl on Windows, and ⌥ (Option) is Alt.

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

- **Ribbon** at the top, with the tabs **Home**, **Insert**, **Annotate**, **Architecture**, **Modeling**, **Analyze**,
  **View**, **Output**, **Manage** and **Script**. Every button runs the same command you could type. The menu bar has
  matching **Model** and **Analyze** menus. The **quick access toolbar** can be customised in
  Settings; each of its buttons runs a typed command.
- **Workspace modes**: **2D** plan, **3D** model, **Split** (plan and 3D side by side) and **Sheet** (paper layouts),
  switched with ⌥⌘1 to ⌥⌘4 or the `SHOW2D`, `SHOW3D`, `SPLIT` and `LAYOUT` commands.
- **Side panels**, shown and hidden with ⌥⌘P: **Properties**, **Layers**, **Levels**, **Browser** (project browser:
  levels, views, sheets), **Materials** (material editor), **Tools** (tool palettes) and **History** (undo and command
  history). In the History panel, clicking an undo step undoes or redoes to that step. Drag the panel edge to resize
  it, and use `FLOATPANEL` (or the panel's float button) to move a panel into its own window; floating panels are
  restored the next time the app opens.
- **Command line** at the bottom, with autocomplete, history and suggestions.
- **Status bar** toggles for object snap, grid, ortho, polar tracking, object snap tracking and dynamic input (also F3,
  F7, F8, F10, F11, F12). It shows the cursor coordinates in the current UCS, the current level and units, and a
  WCS/UCS switch menu. The UCS icon on the canvas follows the UCS origin and rotation.
- **Workspaces**: five built-in arrangements (Drafting & Annotation, Building Design, 3D Modeling, Sheets & Plotting,
  Scripting) and any you save yourself. They are switched with `WSCURRENT` and saved with `WSSAVE`. **Clean screen**
  (⌃0, `CLEANSCREENON`/`CLEANSCREENOFF`) hides the ribbon and panels.
- **Command search** (⌘K, `COMMANDSEARCH`): type part of a name, such as "wal", to find and run any command. Matches
  are fuzzy, recent commands come first, and each result shows where the command sits in the ribbon.
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

**History:** ↑ and ↓ recall earlier lines. `HISTORY` lists the last commands and recent input values, runs a previous
line again (`!n`), and saves or loads a history file, so the same history is available in the app, scripts and
`archi-cli`.

**Action macros:** `ACTRECORD` starts recording typed commands and picks, `ACTSTOP` saves the recording in the drawing
under a name, `ACTPLAY` plays it back and `ACTMANAGER` lists, renames, deletes, exports (.scr) or imports macros.
`SCRIPTRECORD` still records straight to a .scr file.

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
- Groups are expanded when you pick a member or window-select inside a command, as well as when idle.
- **Isolate and hide:** `ISOLATEOBJECTS` hides everything except the selection (on the current level for building
  elements), `HIDEOBJECTS` hides the selection, and `UNISOLATEOBJECTS` shows everything again. Hidden objects are kept
  with the drawing until you end isolation, but they are left out of DXF and IFC exports while hidden.

## Drawing

**2D objects:** `LINE`, `PLINE`, `ARC`, `CIRCLE`, `ELLIPSE`, `SPLINE`, `RECTANG` (also from the centre, by three points,
filleted or chamfered), `POLYGON`, `STAR`, `DONUT`, `POINT` (display style with `PTYPE`), `XLINE`, `RAY`, `DLINE` (double
lines), `SOLID` (filled triangles and quadrilaterals), `WIPEOUT`, `REVCLOUD`, `HATCH` (patterns and solid fills),
`BOUNDARY`, `REGION` and `BOUNDINGBOX`.

**Construction variants:**

| Task | Commands |
| --- | --- |
| Lines | `LINEANG` (fixed angle and length), `LINEREL` (angle relative to a line), `LINEHV` (horizontal/vertical), `LINEPAR` (parallel through a point), `LINEPERP` (perpendicular to a line), `LINEBISECT` (angle bisector), `LINETAN` (tangent from a point), `LINETAN2` (common tangent of two circles), `LINETANORTHO` (tangent and perpendicular to a line), `SNAKE` (relative moves such as `R500 U300 L500 Close`) |
| Circles | `CIRCLE TTT` / `CIRCLETTT` (tangent to three objects), `CIRCLETPP`, `CIRCLETTP`, `CIRCLE2PR` (two points and radius), `INCIRCLE` (inscribed in three lines), `ARCTOCIRCLE` |
| Arcs and ellipses | `ARC2PH` (two points and height), `ARC2PL` (two points and arc length), `ELLIPSEFOCI`, `ELLIPSEC3P` (centre and three points), `ELLIPSE4P` (four points, axes at a given angle) |
| Polygons and points | `POLYGONSS` (side to opposite side), `OFFSETMULTI` (several equidistant offsets), `POINTSLINE`, `POINTLATTICE`, `CUTBYLINE` |
| GD&T | `TOLERANCE` creates a feature control frame: characteristic symbol, tolerance value and datums |

**Centre lines and marks:** `CENTERLINE` and `CENTERMARK` are associative, so they follow when their lines, circles
or arcs move.

**Precision:** running object snaps (`OSNAP`: endpoint, midpoint, centre, node, quadrant, intersection, extension,
insertion, perpendicular, tangent, nearest, parallel), grid snap (`SNAP`, F9), grid (`GRIDDISPLAY`, F7), ortho (F8),
polar tracking (F10), object snap tracking (`OTRACK`, F11) and dynamic input (F12). Settings are in `DSETTINGS`.
With object snap tracking on, hovering over a snap point acquires it (a small cross), and the cursor then locks to
horizontal, vertical or polar alignment with it, shown as a dotted tracking line. With the parallel snap (`PAR`) on,
hovering a straight segment acquires its direction.

**Polylines:** `PEDIT` closes, opens, joins, sets width, fits splines, removes curves and reverses. You can also add
and remove vertices and turn arcs into line segments.

**More drawing tools:** `MLINE` draws multilines using styles from `MLSTYLE` (element offsets, colours, caps and
fill). `SKETCH` draws freehand as polylines or lines. `PARABOLA` and `HYPERBOLA` draw exact conics as polylines.
`NORTHARROW`, `SCALEBAR` and `BREAKLINE` place drafting symbols, and `ARCTEXT` writes text along an arc.
`ISODRAFT` switches to isometric drafting (with `ISOPLANE` Left/Top/Right): ortho and the crosshair follow the current
isoplane.

**More drawing tools.** `SPLINE` has a control-vertex method and `SPLINEDIT` edits fit and control points; `BLEND` draws a
tangent curve between two open curves; `PEDIT` can edit single vertices, append segments and change a segment to a line or
arc; `TRACE` draws wide lines; `ELLIPSEQUAD` inscribes an ellipse in a parallelogram. `REVSTAMP` places revision triangles and
a revision table that fill the sheet's revision field.

**More drawing tools.** `ELLIPSEQUAD` fits the largest ellipse inside a convex quadrilateral (four corners, a 4-sided
polyline or four lines). `HELIX` draws a 3D helix. Point modifiers: `INTOF` (intersection of two picked objects),
`M2P` (midpoint between two points), `RH`/`RV` (keep only the horizontal or vertical part of the next point) and
`RELZERO` (lock the relative-zero point used by `@` input).

**Snap overrides and grips.** At any point prompt, type `END`, `MID`, `CEN`, `GCEN`, `INT`, `EXT`, `PER`, `TAN`, `NEA`, `NON` and
the other snap names for a one-shot snap (scripts can write `MID 480,5`), or Shift+right-click on the canvas for the same list.
`OSNAP GCEN` turns the geometric-centre snap on. Grips snap while you drag; press Space to cycle Stretch, Move, Rotate, Scale
and Mirror, type `C` for Copy, or type a distance or point for an exact grip edit. Doors, windows and walls show flip arrows,
slabs show edge grips and roofs show slope grips. Drag with Option held for a lasso selection.

## Modifying

`MOVE`, `COPY`, `ROTATE`, `SCALE`, `MIRROR`, `STRETCH`, `OFFSET`, `TRIM`, `EXTEND`, `FILLET`, `CHAMFER`, `BREAK`,
`BREAKATPOINT`, `JOIN`, `LENGTHEN`, `EXPLODE`, `ALIGN`, `ARRAY` (`ARRAYRECT`, `ARRAYPOLAR`, `ARRAYPATH`), `DIVIDE`,
`MEASURE`, `REVERSE`, `ERASE`, `OVERKILL` (removes duplicates and merges overlapping lines), `DRAWORDER`, `MATCHPROP`,
`CHPROP` and `SETBYLAYER`.

**More modify tools:** `MOVEROTATE` (move, then rotate), `ROTATE2` (rotate about two centres in turn), `ALIGNREF`
(rotate so a reference direction lines up with a target), `EXTENDBY` (extend or trim by an amount), `BREAKALL` (break
at every intersection), `LINEGAP` (gaps where objects cross), `CLIPPOLY` (clip with a closed boundary), `WELD` (merge
touching curves into polylines), `CONVERTTOPLINE`, `PLINETOSPLINE` and `PASTETOPOINTS` (paste the clipboard at several
points in one undo step).

**Regions and text:** `REGIONUNION`, `REGIONSUBTRACT` and `REGIONINTERSECT` combine closed shapes in 2D, keeping
holes. `TEXTREADABLE` flips text that reads upside down. `NUDGE` (and `Editor.nudgeSelection`) moves the selection by
a small step; the arrow keys are not bound to it yet. `HATCHEDIT` changes a hatch's pattern, scale, angle,
background colour and associativity.

**Grips:** select an object and drag a grip to stretch it. On constrained geometry the constraints are solved live
while you drag; the whole drag is one undo step and Esc cancels it. Moving the end of a wall also moves the walls joined to it.

**Clipboard:** ⌘C, ⌘X and ⌘V copy, cut and paste objects, pasting at the cursor. The same clipboard is used by
`COPYCLIP`, `CUTCLIP`, `COPYBASE` (with a base point), `PASTECLIP`, `PASTEORIG` (at the original coordinates) and
`PASTEBLOCK` (as a block). You can paste between open drawings, and the block definitions and layers the objects use
are copied with them.

**More modify tools.** `FLATTEN` sets Z to 0 on 3D lines, arcs, polylines and splines; `ROTATE90` turns the selection by a
quarter turn; `TXTEXP` explodes text into outlined letters; `LENGTHEN` has a dynamic mode; `ALIGN` mirrors when a third point
pair asks for it; `RESETBLOCK` returns dynamic blocks to their defaults; `CHSPACE` moves objects between model and paper
space. The arrow keys nudge the selection (Shift ×10, or the grid step when snap is on), and clicking the same spot again
cycles through overlapping objects.

**Arrays.** `ARRAYRECT`, `ARRAYPOLAR` and `ARRAYPATH` create one associative array object (variable `ARRAYASSOCIATIVITY`,
on by default). `ARRAYEDIT` changes its count, spacing or source; a path array follows its path when the path is edited;
`EXPLODE` turns it back into separate objects. `ARRAYCLASSIC` makes separate copies. Press Space while moving,
copying or placing a block or component to turn it 90° (Shift+Space turns it back). `TEXTTOFRONT` has Text, Dimensions,
Leaders and All options. `TXTEXP` turns text into lines with a built-in single-stroke font (`Letters` keeps one text per letter).

**Curves and transparency.** `FILLET`, `CHAMFER` and `EXTEND` work on ellipses and splines too. `CHPROP` with the
`TR` option, `CETRANSPARENCY`, `TRANSPARENCYDISPLAY` and `PLOTTRANSPARENCY` control object and layer transparency (ByLayer,
ByBlock or 0–90 %). `XLINE` and `RAY` round-trip through DXF.

**Round 7 drafting input.** Dynamic input (`DYNMODE`) shows pointer and dimension fields next to the cursor; type
`x,y,z` for 3D points. Selecting an element shows temporary dimensions you can click and edit, smart alignment guides appear while
drawing, arrow keys lock the drawing axis (`AXISLOCK`), and `DBLCLKEDIT` controls what double-clicking an object opens. Command
options are clickable in the command line. `ARRAY` also arrays building elements.

## Parametric constraints

Constraints keep 2D geometry in relation while you edit it, as in AutoCAD's parametric drawing.

- **Geometric:** `GEOMCONSTRAINT` (or the single commands `GCHORIZONTAL`, `GCVERTICAL`, `GCPARALLEL`,
  `GCPERPENDICULAR`, `GCCOINCIDENT`, `GCCOLLINEAR`, `GCCONCENTRIC`, `GCTANGENT`, `GCEQUAL`, `GCSYMMETRIC`, `GCFIX`,
  `GCMIDPOINT`, `GCPOINTONCURVE`) on lines, polylines, circles, arcs and points.
- **Dimensional:** `DIMCONSTRAINT` (or `DCLINEAR`, `DCHORIZONTAL`, `DCVERTICAL`, `DCALIGNED`, `DCANGULAR`, `DCRADIUS`,
  `DCDIAMETER`, `DCRATIO` for a length ratio, `DCDIFFERENCE` for a length difference) drives a distance, angle or
  radius. A value can be an expression of named parameters such as
  `d1*0.5`, and a constraint can be a reference (driven) value that only reports. `DCCONVERT` turns existing
  dimensions into constraints.
- **Parameters:** `PARAMETERS` creates, edits and deletes named parameters; the geometry updates when they change.
- **Inference:** `AUTOCONSTRAIN` adds constraints to the selection within distance and angle tolerances. Set
  `CONSTRAINTINFER 1` to add them automatically while you draw.
- **Managing:** `CONSTRAINTLIST` lists constraints and the remaining degrees of freedom, and `DELCONSTRAINT` removes
  them.

The solver is a weighted Newton–Raphson iteration that keeps the object you just edited in place and moves the others.
A constraint that would over-constrain the sketch is reported and not added. Constraints are solved live while you drag a grip
and again after every edit, and they are saved with the drawing. `CONSTRAINTBAR` (Show/Hide/Toggle, or the ribbon
button) draws constraint glyphs next to constrained objects.

## Annotation

- **Text:** `TEXT`, `MTEXT`, `TEXTEDIT`, `TEXTSTYLE`, `SCALETEXT`, `JUSTIFYTEXT`, `TXT2MTXT` and `FIND` (find and
  replace). Special symbols: `%%d` (°), `%%c` (⌀), `%%p` (±).
- **Fields:** `FIELD` inserts text that updates automatically, such as an object's area or length, a property, a
  variable, a count or a date. `UPDATEFIELD` refreshes fields.
- **Dimensions:** `DIM` (smart), `DIMLINEAR`, `DIMALIGNED`, `DIMANGULAR`, `DIMARC`, `DIMRADIUS`, `DIMDIAMETER`,
  `DIMORDINATE`, `DIMBASELINE`, `DIMCONTINUE`, `QDIM`, `DIMSPACE`, `DIMEDIT`, `DIMTEDIT` and `DIMSTYLE`.
  Dimensions placed on object snaps are associative: they follow the geometry when it moves. `DIMREASSOCIATE` and
  `DIMDISASSOCIATE` change that, and `DIMREGEN` updates them all. `DIMBREAK` breaks extension and dimension lines where
  other objects cross (Auto, chosen objects, Manual or Remove), `DIMOVERRIDE` overrides style values on single
  dimensions, and in a text override `<>` stands for the measured value. `DIM*` system variables change the current
  dimension style.
- **Hatches:** hatches created by picking inside a boundary are associative and follow it. `HATCH` can create
  separate hatches for several areas, and `HATCHGENERATEBOUNDARY` recreates a boundary polyline. A hatch loses
  associativity (but keeps its shape) if its boundary is erased.
- **Spelling:** `SPELL` checks text, leaders, tables and attributes with the macOS spell checker. `SPELLDIALOG` opens
  the spelling dialog with suggestions (Change, Ignore, Add).
- **Leaders:** `LEADER`, `MLEADER`, `MLEADERSTYLE` (text height, annotative, layer), `MLEADERALIGN` and
  `MLEADERCOLLECT` (gathers several leaders' texts onto one leader, stacked or in a row).
- **GD&T:** `TOLERANCE` places feature control frames.
- **Tables:** `TABLE`, then `TABLEEDIT` to edit cells, add formulas (`=SUM(...)`, `AVERAGE`…), insert or delete rows and
  columns and set column widths. `TABLEEXPORT` writes a table to CSV. `TABLELINK` creates a table linked to a CSV
  file and `DATALINKUPDATE` reloads it or writes changes back (XLSX links are not supported).
- **Annotative scaling:** `ANNOTATIVE` makes text, leaders and tables follow the annotation scale (`CANNOSCALE`). For
  example, switching from 1:50 to 1:100 doubles their model height. Edit the list of scales with `SCALELISTEDIT`.

**More annotation.** `DIMJOGGED` and `DIMJOGLINE` add jogged radius dimensions and jog lines; `DIMREBASE` moves the datum of
ordinate dimensions; `QDIM` also makes ordinate, staggered, radius and diameter dimensions; `SPOTCOORD` labels a point's
coordinates and follows it. `GRADIENT` fills areas with two-colour gradients, `HATCHSETORIGIN` moves a hatch's pattern origin
and `PATLOAD` loads patterns from `.pat` files (the patterns are saved in the drawing). `TEXTMASK` and `TEXTFRAME` put a
background mask or a frame behind text (masks and wipeouts print white). `OBJECTSCALE` adds and removes annotation scales,
and `PTYPE` point styles are drawn on screen and on paper. Fields accept `Expr` formulas and sheet number, name, count,
revision, author and plot date.

**More text and dimension options.** `TEXTLIST` adds bullets or numbering, `MTEXTCOLUMNS` flows multiline text into
columns and `AUTOSTACK` controls stacked fractions (drawn with a bar). `DIMTOLERANCE`, `DIMALTUNITS` and `DIMINSPECT`
add tolerances, alternate units and inspection frames to dimensions. Text background masks are written to DXF as MTEXT
background fill, and WIPEOUTs placed behind text are read back as masks. `HATCH` includes the standard acad/acadiso
pattern names and ISO 02–15 line patterns.

**Round 7 annotation.** `REVCLOUD` draws revision clouds and `REVCLOUDLIST` links them to the revision schedule.
`TABLESTYLE` manages table styles. `FILLEDREGION`, `MASKINGREGION`, `HATCHTYPE` (model or drafting patterns), `DETAILCOMPONENT`,
`REPEATDETAIL` and `INSULATION` cover detailing. `DETAILMARK`, `ELEVATIONMARK`, `SECTIONSYMBOL` and `MATERIALTAG` place
symbols and tags. Annotative text takes its height from the annotation scale.

**Round 8 annotation.** Dimension styles support decimal, architectural, engineering, fractional and scientific units,
rounding, zero suppression, tolerances, alternate units, fit options and a text style. Tables can link to an `.xlsx`
sheet (`book.xlsx!Sheet`), update from it and write back to it. Single-stroke fonts (txt, simplex, `*.shx`, "Archi Stroke")
are drawn as vectors with width factor and oblique, and look the same on screen, in PDF and SVG. `EQDIM` keeps three or
more objects equally spaced.

**Round 9 annotation.** `TAGLABEL` sets a tag's label template (for example `{Name}\n{Finish}`) or a single field and can
make tags annotative; labels follow changes to the element's data and the annotation scale. `MATPATTERN` gives each
material a cut and a surface fill pattern, and `MATHATCH` ties a hatch to a material so it follows pattern changes
(also in DXF).

**Round 10 annotation.** Double-click text (or run `TEXTEDITINPLACE`) to edit it on the canvas with bold, italic,
underline, font, height and colour; the formatting prints to PDF and survives DXF. `TEXTSTYLEDIALOG` manages text
styles; width factor and oblique angle now show on screen and in PDF. `FLOORPATTERN` shows a slab's material surface
pattern in plan, cut around holes and walls, following slab, wall and material changes; `MATPATTERNDIALOG` edits the
cut and surface patterns of every material. `IMAGEADJUSTDIALOG` adjusts raster images, applied exactly on screen and in plots.

## Layers and properties

- The **Layers** panel and the `LAYER` command create layers and set them current, on/off, frozen/thawed,
  locked/unlocked, and set colour, linetype and lineweight. The shortcuts `LAYISO`, `LAYUNISO`, `LAYOFF`, `LAYON`,
  `LAYFRZ`, `LAYTHW`, `LAYLCK`, `LAYULK`, `LAYMCUR` and `LAYDEL` do the same from a selected object.
- **Layer filters** (`LAYERFILTER`): wildcards such as `A-*`, plus filters for on, used or unlocked layers. Named
  filters are saved in the drawing.
- **Layer states** (`LAYERSTATE`, or the manager dialog): save, restore, rename, import and export the visibility and
  properties of all layers. States can be imported from a `.las.json` file, a drawing or a DXF file.
- `LAYFILTER` defines property filters (`name=A-* on=yes color=1`) and group filters, which can be inverted.
- `LAYWALK` shows the objects on chosen layers one at a time, `LAYMRG` merges layers into one, `LAYCUR` moves objects
  to the current layer and `LAYTRANS` maps layers to a standard (with wildcards or a mapping file).
- `VPLAYER` freezes layers in individual sheet viewports; sheets and plots show the change.
- `COLOR`, `LINETYPE`, `LTSCALE` and `LWEIGHT` set the defaults for new objects. `PURGE` removes unused definitions and
  `RENAME` renames them.
- The **Properties** panel shows and edits the selected objects. `PROPERTIES`/`LIST` print their properties and
  `SETPROP` sets any property from the command line, for example `SETPROP #12 height 2800`. Building elements also
  expose phase created and demolished, keynote and mark; walls their top attachment and joins; slabs their slope,
  slope direction and gradient (`8.33%` or `1:12`) and kind (floor, ramp, foundation, ceiling, landing); openings their
  type, mark and niche depth; rooms their tag position and area scheme.

`LAYDESC` sets a layer description; `COLORBOOK` picks colours from open colour books.

**Line styles, lineweight tables, pen sets and filters.** `LINESTYLES` defines named line styles for objects or layers,
`LWTABLE` maps lineweights by view scale, `PENSETS` sets pen tables for plotting and `GFILTERS` applies graphic
overrides to objects that match a filter. `GRAPHICSTYLES` opens a dialog for all four. They apply to drafting objects,
not yet to BIM plan graphics.

**Object styles.** `OBJECTSTYLES` (or the `OBJECTSTYLESDIALOG` window) sets cut and projection line weight, line
colour, cut fill and cut pattern per BIM category; every plan and section follows, and view overrides still win.

## Blocks, attributes and groups

- `BLOCK` defines a block and `INSERT` places it. Blocks can be nested. `WBLOCK` writes a block to a file, `BASE` sets
  the drawing's insertion point and `BLOCKBASE` moves a block's base point.
- `BLOCKREPLACE` swaps one block for another, `BCOUNT` counts references and `BFLIP` flips a reference.
  `INSERT` can also redefine a block from a file.
- **Attributes:** `ATTDEF`, `ATTEDIT`, `BATTMAN` (edits definitions from the command line), `ATTSYNC`, `ATTEXT` and
  `DATAEXTRACTION` (into a table or a CSV file).
- **Groups:** `GROUP` (Create/Add/Remove/Explode/Rename/List) and `UNGROUP`. Clicking a member selects the whole group.
  Set `PICKSTYLE` to 0 to pick members on their own.
- **Visibility states:** `BVSTATE` gives a block named visibility states (New, Set, Hide/Show objects, List, Delete,
  Rename). Each reference keeps its state when saved. Internally each state is a generated `Block$State` definition, so
  those extra blocks appear in the block list.
- **External references:** `XATTACH` attaches `.archi` and `.dxf` drawings, as an attachment or an overlay (overlays
  are not carried into drawings that reference this one; circular references are refused). `XREF` lists, reloads,
  unloads, detaches and binds references, and `XREF Notify` reports references whose files changed. `XBIND` binds
  single definitions. Xref layers appear as `file|layer` and can be switched on, off and frozen.
- `BLOCKLIBRARY` scans and searches folders of block drawings and inserts from them (the library panel is still to
  come).
- `IMAGEATTACH` and `IMAGEIMPORT` place raster images; `IMAGESCALE` calibrates an image from a known distance.

**Blocks and attributes.** `ATTDEF` supports Invisible, Constant, Verify, Preset and Lock modes (invisible attributes are
hidden unless ATTMODE is 2); `BATTMAN` reorders attributes and changes their modes; `BPARAMETER` adds stretch and array
parameters to dynamic blocks and `DYNPROP` changes them. The **Block library** panel browses folders of drawings with
thumbnails, search, favourites and recents; drag a block onto the plan or the 3D view to insert it.

`XCLIP` clips the display of a block reference (the clip moves with the block) and `BTABLE` stores named parameter sets
for dynamic blocks.

**Round 7 blocks.** `BEDIT` opens the block editor (`BSAVE`, `BCLOSE`), and `REFEDIT`, `REFSET` and
`REFCLOSE` edit blocks and references in place. Blocks that would contain themselves are refused. Groups can contain building
elements. `LIBRARYINSTALL` installs the bundled block and annotation symbol library. `LAYERNOTIFY` and `LAYRECONCILE` warn
about new layers and mark them as reviewed.

**Parametric blocks.** Constraints drawn in the block editor are saved with the block, and named length constraints
become per-reference parameters that you set with `DYNPROP`.

**Round 9 images and links.** `IMAGECLIP` clips an image to a rectangle or polygon (On/Off, Delete, Invert);
the boundary moves with the image, is saved in the drawing and shows on screen, in PDF and SVG. `IMAGEFRAME` (0/1/2)
controls frames and `IMAGEADJUST` sets brightness, contrast and fade. `RVTLINK` links another `.archi` or IFC model
(origin to origin, shared coordinates or a picked point, with unit scaling); its levels show in the matching host plans,
in 3D, sections and renders, on locked layers, with Reload, Unload, Detach, Position and Notify. `COPYMONITOR` copies
or monitors the linked model's levels and grids and reports what moved, was renamed or was deleted on reload.

## BIM: building elements and levels

Building elements are real objects with parameters. They appear in plan with cut lines and hatching, in 3D, in sections
and elevations, and in schedules.

- **Levels:** `LEVEL` creates, lists, renames and deletes levels and sets the current one, with elevations and heights.
  The Levels panel does the same. Each element belongs to a level.
- **Walls:** `WALL` draws chains of joined walls, straight or curved, with a thickness, height, justification and type.
  Its `Top` option (or `WALLTOP` afterwards) makes the wall rise to a named level with an offset, or to the next
  level; such walls also appear on the upper floor plans. `WALLATTACH` attaches wall tops to a roof or slab soffit
  (including sloped slabs, for straight walls), attaches bases to a slab top, or detaches them.
  `WALLBYLINES` turns lines into walls and `WALLJOIN` cleans up corners. Walls join at L, T and X junctions, including
  T-joins into curved walls. `WALLSWEEP` adds cornices and skirting boards, and `NICHE` cuts recesses. Walls under
  gable, shed or hip roofs fill up to the roof underside automatically.
- **Openings:** `DOOR`, `WINDOW` and `OPENING` place hosted openings that move with their wall. Openings stacked at
  different heights (a window above a door) each cut their own hole. `OPENINGTYPE` manages a
  door/window type catalogue: changing a type's parameters updates every instance, and types can be imported from CSV.
  `MARKS` renumbers doors and windows (D01, W01…).
- **Curtain walls:** `CURTAINWALL`, with `CWGRID` to add or remove grid lines, choose mullion types (rectangular,
  circular, L, T, trapezoid) and set panels to glass, solid, empty, door, double door, spandrel or louvre.
- **Door and window parts:** `OPENINGTYPE` types can use formulas (such as `width = height / 2`) and sub-parts;
  `OPENINGPARTS` adds mullions, transoms, glazing bars, fanlights and thresholds.
- **Floors, roofs and ceilings:** `SLAB` (from points, a closed object or the walls around a point), `SLABSLOPE` (slope
  by arrow or angle), `ROOF` (flat, shed, gable or hip, including hip roofs on L-, T- and U-shaped footprints) and
  `CEILING` (from points or, with the `Room` option, a room outline; hidden in views with the `CEILINGS` variable).
- **Circulation:** `STAIR` (straight, L, U or spiral, with winders instead of landings, left or right turn, and a
  central column for spirals; `Top` runs it to a level, `Landing` adds an intermediate
  landing) warns about rule problems, and shows with a "DN" arrow on the level it arrives at. `STAIRCHECK` checks
  risers, goings, 2R+G, width, flight length and landings. `RAMP` runs straight or along a path with turns, with
  landings at corners and between flights, and warns when steeper than 1:12. `RAILING` adds railings.
- **Structure:** `COLUMN`, `BEAM`, `GRID` (auto-labelled grid lines, shown on every level's plan) and `FOUNDATION` (strip footings under walls,
  isolated footings under columns, or pads). `STEELPROFILE` gives beams and columns a steel section (IPE, HEA/HEB,
  UPN, RHS, SHS, CHS, angles, tees or custom I, H and C shapes), `BEAMSYSTEM` fills a bay with evenly spaced beams, `BRACE` places
  sloped braces and `TRUSS` builds Pratt, Howe, Warren or Fink trusses.
- **MEP:** `MEPPIPE`, `DUCT`, `CABLETRAY` and `CONDUIT` draw runs along a path, coloured by system (cold and hot water,
  waste, air, power, data…). `MEPCONNECTORS` lists fixture connection points. Lighting fixtures are in the component
  library.
- **Room finishes and colours:** `ROOMFINISH` sets floor, wall, ceiling and base finishes and places a finish
  schedule. `COLORFILL` colours rooms or areas by a parameter with a legend.
- **Worksets and design options:** `WORKSET` and `DESIGNOPTION` group elements; hidden worksets and non-primary
  options are hidden in plan, 3D and the room finish schedule (not yet in other schedules and exports).
- **Rooms:** `ROOM` (click inside walls or give points) reports area and volume. `ROOMSEPARATOR` draws virtual
  boundaries, and `ROOMUPDATE` recomputes rooms after walls change. `ROOMBOUNDING` sets whether walls, curtain walls
  and columns bound rooms; walls rising from lower levels bound rooms on the upper levels too. Room tags sit at the most open point of the room and
  size themselves to fit.
- **Area plans:** `AREAPLAN` draws gross, rentable or custom area boundaries and reports totals per scheme.
- **Components:** `COMPONENT` places parametric families (including people, bicycles and other entourage) from a library of 26: beds, sofas, tables, chairs, kitchen
  units and appliances, WC, basin, shower, bath, a car, trees, shrubs and parking spaces. Each has a 3D mesh and a plan
  symbol that resize with the component, and components are listed in the element schedules.
- **Multi-storey:** `COPYTOLEVEL` copies elements to other levels aligned in plan (doors and windows follow their
  copied walls). `DATUMS3D` shows levels and grids in the 3D view.
- **Other:** `BUILDING` creates quick massing (walls, floors and a roof from a rectangle).
- **Phases:** `PHASE` creates phases, sets the current phase, sets when objects are created or demolished, and sets the
  view filter. Existing work is shown half-tone and demolished work dashed.

**More building elements.** Layered floor types with finishes; wall join overrides; openings in roofs and slabs (skylights),
shafts through several floors, face openings and dormers; fascias, gutters and soffits; roof layers; railing types; elevators;
opening trim (frames, casings, sills and lintels); model groups; lighting fixtures with photometry; MEP systems with connected
networks; area schemes that follow wall changes. **Families:** the `FAMILY` command builds parametric families with
formulas, value ranges, conditional geometry, arrays, voids and nested families, door/window and profile families, and a flex
test. Worksets and design options filter views, schedules (SCHEDULEFILTER) and exports (EXPORTFILTER). Associative content
(area boundaries, automatic dimensions, sweeps, family instances) regenerates after every edit.

**More BIM tools.** `GRIDSYSTEM` and `RADIALGRID` create rectangular and radial grids; `SPLITWALL`, `WALLFLIP` and
`OPENINGFLIP` edit walls and openings; `ROOFSHAPE` makes mansard, gambrel, dome and barrel roofs; `ESCALATOR` places an
escalator with EN 115 checks and a floor opening; `ZONE` groups rooms; `CLASSIFY` assigns Uniformat II, NL-SfB,
Uniclass or OmniClass codes; `PSET` manages property sets and templates; `GLOBALPARAM` defines project-wide parameters;
`GEOLOCATION` sets the project's latitude, longitude and true north. The **Family Editor** panel (`FAMILYPANEL`) edits a
family's parameters, forms (including blend and swept blend), types table and reference planes with a live 3D preview;
`FAMILY Purge` removes unused families and types.

**Round 6 BIM.** `WALL` has a Type option and a wall type editor (layers and core), `WALLTOP` attaches walls to
roofs or levels, and walls can be slanted or tapered and have edited elevation profiles. Grids can be radial or have several
segments, and radial grid arcs take snaps. `COLUMN`, `BEAM`, `RAILING` (stair railings), `CURTAINWALL` (embedded in a host wall),
`DOOR`/`WINDOW` styles, `LEVEL` heads, `BUILDING`, `TOPO` and `COMPONENT` (hosted components) gained options.
`GLOBALPARAM` handles shared and project parameters, and `FAMILY` loads, reloads and saves `.archifam` families with
templates, symbolic lines, detail-level visibility and material parameters.

**Round 7 BIM.** `WALLRECT` and `WALLPOLYGON` draw closed runs of walls, `STACKEDWALL` stacks wall types,
and `STOREFRONT` builds storefront and partition walls. `STORY` sets story settings, including the room computation height.
`STRUCTCOLUMN` and `STRUCTURAL` handle structural columns and structural flags on walls and slabs. `SLABEDGE`, `ROOFEXTRUSION`,
`ROOFSHAPEPOINTS` (shape editing of flat roofs) and `STAIRSKETCH` add more hosts. `ASSEMBLY` and `PARTS` group elements and divide
them into their layers. `STAIRTYPE` and `RAILTYPEDEF` are type builders. `EXPRESSION`, `REPORTPARAM`, `FAMILYLOCK`, `PARAMCELL`
(parameters driven by a spreadsheet) and `TRANSFERSTANDARDS` extend parameters. `TYPEIMAGE` sets images shown in schedules.
Workplanes and reference planes (`RP`), `PROJECTBASEPOINT`, `SURVEYPOINT`, `TRUENORTH` and `PLANORIENT` set up coordinates;
`PLAN` shows the plan of the current UCS and `UCSICON` controls the UCS icon. Files are now format version 6 (older files upgrade on open).

**Round 8 BIM.** `CURTAINSYSTEM` places curtain systems on mass faces. `INPLACE` creates in-place (generic) models.
Supply and return air terminals, radiators and data outlets connect to systems and are coloured by system in plan.
`CIRCUIT` and `PANELSCHEDULE` build electrical circuits and panel schedules, and `GRADEDREGION` reports cut and fill
volumes. `GRAPHICDISPLAY` sets sketchy lines, silhouettes and plan shadows per view, and `ROOMDATASHEET` exports room
data sheets as CSV, HTML or text; importing an edited CSV writes the changes back to the rooms.

**Round 9 BIM.** `WALLWRAP Ends` wraps wall layers at free ends and at inserts, in plan and 3D. Curtain walls meet at
corners with one shared corner post. `CORNERWINDOW` places a window that turns a wall corner, `ROOFJOIN` joins and
trims roofs, `REBAR` places reinforcement in beams, columns and slabs (shape codes 00/11/51, weights) and
`STEELCONNECTION` adds base, cap and end plates with bolts; both follow their host. `ADAPTIVE` places adaptive
components driven by points, and `SCRIPTCOMPONENT` places OpenSCAD-scripted components with range-checked parameters
that the Customizer edits. `BSDD` loads a bSDD dictionary (or searches bSDD online when you ask it to) and assigns
classes and properties that view filters and schedules can use.

## Documentation: views, tags and schedules

- **Sections and elevations:** `SECTION` places a section line in plan. Sheet viewports can show plans, ceiling plans,
  elevations, sections and 3D views, which are always generated from the current model. `VIEWDRAW` places an elevation,
  section or detail as 2D linework in model space, with level heads and grid bubbles. `VIEWUPDATE` regenerates these
  views.
- **Interior elevations:** `INTERIORELEV` places a 4-way marker in a room and draws views A–D of its walls.
- **Callouts:** `CALLOUT` draws the callout boundary, leader and numbered bubble in plan and places the enlarged detail
  view it refers to.
- **Reflected ceiling plans:** `RCP` switches the plan to a reflected ceiling plan with ceiling grids (set per
  ceiling) and ceiling fixtures. Ceiling viewports on sheets use it too.
- **Automatic dimensions:** `AUTODIMWALLS` dimensions the openings and overall lengths of selected walls in one step.
  The dimensions are ordinary dimensions and do not update when the walls change.
- **Spot elevations and slopes:** `SPOTELEV` shows a live height (of a slab, terrain or level) and `SPOTSLOPE` the
  slope of a slab or roof.
- **Tags:** `TAG` labels a door, window, room or element with live values (mark, type, name, area, keynote), and
  `TAGALL` tags everything not yet tagged on a level.
- **Keynotes:** `KEYNOTE` defines keys, assigns them to elements and places a keynote legend.
- **Schedules:** `SCHEDULE` creates tables of walls, doors and windows (with mark and type), rooms (with volume), slabs,
  areas and keynotes. Schedules can be exported to CSV, or with `XLSXOUT` to an Excel workbook (one sheet per
  schedule).

**Views.** Sections and elevations draw hidden lines, line weights, depth cueing and a far clip; view templates update every
view they are assigned to; legends list wall, floor and roof build-ups; drafting views hold 2D detail.

`VIEWRANGE` sets a plan view's cut plane and view depth; `TEMPHIDE`, `TEMPISOLATE` and `REVEALHIDDEN` hide or show
elements temporarily; `UNDERLAY` shows another level halftone under the current one.

**Schedules and graphics.** `SCHEDULE` has Define, Edit and Export options: schedules for any category, key and
note-block schedules, sheet and view lists, material takeoffs, calculated fields and conditional highlight rules. Edits in a
schedule write back to the model, and placed schedules update when the model changes. `VIEWGRAPHICS` (alias `VG`) sets
per-view visibility and graphics overrides, filters, detail level and cut patterns by material; `VIEWRANGE` also defines plan
regions. Rooms update automatically when walls change.

**Round 7 views.** `PROJECTVIEW` saves plan, ceiling and 3D views, duplicates them (with or without detailing) and
splits them into dependent views with `MATCHLINE`s. `VIEWCROP` sets crop regions, `SCOPEBOX` controls crops and grid extents,
`LINEWORK` overrides individual lines, `AXONVIEW` and `CAMERAVIEW` create axonometric and perspective views, and
`VIEWSECTIONBOX` adds a section box to 3D views. `SCHEDULECELLS` highlights schedule cells by condition.
The project browser opens views, cameras and sheets.

## Site and terrain

- `TOPO` builds a toposurface from points with elevations, contour polylines, an XYZ/CSV file or typed x,y,z values.
- `CONTOURS` sets the contour interval and major lines.
- `SUBREGION` marks paths, lawns and paved areas on the terrain, `SITEPATH` draws a path of a given width,
  `PARKINGLOT` lays out rows of parking spaces, `RETAININGWALL` draws a retaining wall along a path, and
  `PROPERTYLINE` draws property lines from points or bearings and distances, with their area.
- `BUILDINGPAD` levels the terrain inside a boundary to a pad elevation.
- `POINTSIMPORT` reads survey point files (CSV/TSV/TXT, including P,N,E,Z,D).
- `DEMIMPORT` builds a toposurface from an ESRI ASCII elevation grid. Contour polylines exported to and imported from
  DXF keep their elevation, so `TOPO` can use them directly.
- `SHPIMPORT` (shapefiles with attributes and CRS), `OSMIMPORT` (OpenStreetMap buildings, roads and water) and
  `CITYJSONIMPORT` place GIS context around the project location, so set the location close to the data first.

## 3D modelling

- **Solids:** `BOX`, `CYLINDER`, `CONE`, `SPHERE`, `EXTRUDE`, `REVOLVE`, `PRESSPULL` (extrudes the area around a picked
  point, with holes), `LOFT`, `SWEEP` and `PIPE`.
- **Booleans:** `UNION`, `SUBTRACT` and `INTERSECT` produce closed meshes. `SLICE` cuts solids with a vertical or
  horizontal plane, and `INTERFERE` finds overlapping volumes and can create them as solids.
- **Solid editing:** `FILLETEDGE` and `CHAMFEREDGE` round or bevel all, vertical, top or bottom edges of boxes and
  extrusions. `SHELL` hollows them to a wall thickness, optionally open at the top. `MIRROR3D`, `ROTATE3D` (about an
  axis parallel to X, Y or Z) and `3DARRAY` (rectangular or polar) transform solids and drawing objects, and
  `MESHSMOOTH` smooths meshes by Loop subdivision. Mirrored, rotated and filleted solids become plain meshes and lose
  their box or extrusion parameters.
- **Node editor** (`NODEEDITOR`, Modeling tab): a visual graph of number, range, series, point, curve, extrude,
  transform and array nodes with a live plan or 3D preview. Graph numbers can be exposed as sliders, and the result is
  baked into the drawing.
- **Surfaces and meshes:** `REVSURF` (revolved), `TABSURF` (tabulated), `RULESURF` (ruled between two curves) and
  `EDGESURF` (Coons patch from four edges) create mesh surfaces. `MESHREPAIR` welds vertices, removes degenerate and
  duplicate faces and fixes orientation, and `MESHDECIMATE` reduces the face count. `SWEEP` can twist the profile and
  scale its end.
- Loft, sweep, pipe and press/pull results are independent solids. They don't update when the source profile changes.

**Solid history.** With `SOLIDHIST` on, booleans are recorded; `SOLIDHISTORY` lists, suppresses, moves and deletes features and
the solid regenerates. Sweeps stay associative with their path, `PRESSPULL` works on faces of any solid and `SECTIONSOLIDS`
makes 2D section blocks.

**More solids.** `WEDGE`, `TORUS`, `PYRAMID`, `PRISM` (also tubes), `POLYHEDRON`, `POLYSOLID`, `PLANESURF` and `MESH` create
primitives. `THICKEN`, `HULL`, `SEPARATE`, `SOLIDCHECK`, `CONVTOMESH`/`CONVTOSOLID` and `LINEAREXTRUDE` (with twist and
scale) edit and check them. `SECTIONOBJECT` places live section planes that cap clipped solids. `LOFT` and `PIPE` rebuild
when their source curves change.

**Round 7 modelling.** `3DALIGN`, `MESHEXTRUDE`, `MESHSECTION`, `UNFOLD`, `WIREFRAME` (lattice/solidify),
`MINKOWSKI`, `SPRING` (helical springs and threads), `TEXT3D` and `SURFCV` (NURBS surfaces from control vertices). `SCAD` runs an
OpenSCAD-like CSG script (including 2D offset and projection) and `SCADFILE` imports `.scad` files.

**Round 8 modelling (parametric features).** `CYLINDER` now takes centre, 3P, 2P or Elliptical bases and an axis
endpoint; `EXTRUDE` supports Taper, Direction, Path and Both sides; `REVOLVE` is associative and regenerates when the
profile changes. PartDesign-style features follow their sketches: `PAD`, `POCKET`, `HOLE` (simple, counterbore,
countersink), `GROOVE`, `REVOLUTION`, `FOLLOWME`, `SWEEP3D`/`HELIXSWEEP`, `PATTERNFEATURE`, `MIRRORFEATURE` and
`SHAPEBINDER`. `SPLITSOLID`, `GFUSE`, `SOLIDEDIT` (face extrude, move, offset, taper, copy; body offset, separate),
`OFFSETSOLID`, `CSGTREE` (BRL-CAD style `u #1 - #2 + #3`) and `PROJECTGEOMETRY` complete the set. Surfaces: `SURFNETWORK`,
`SURFPATCH`, `SURFOFFSET`, `SURFEXTEND`, `SURFTRIM` and `SURFSCULPT`. SketchUp-style tools: `INTERSECTFACES`, `SOFTEN`,
`TAPEMEASURE` (measure, guides, protractor), `PAINT` and `SCALE3D` (non-uniform). `SCADOBJECT` keeps an OpenSCAD script
with Customizer parameters, edited in `CUSTOMIZERPANEL`. `3DOSNAP` sets 3D object snaps, `APPINT` snaps to apparent
intersections, and `DUCS` places points on the face under the cursor.

**Round 9 modelling.** `DATUM` places datum planes, axes and points; `IMPRINT` imprints edges on faces; `SUBOBJECT`
edits a face, edge or vertex (Ctrl-click in the 3D view starts it on the part under the cursor); `SURFBLEND` blends
surfaces with G0/G1/G2 continuity and `SURFANALYSIS` shows zebra, curvature, draft and continuity. `SKETCHPLANE` and
`SKETCHPAD` sketch on any 3D work plane. `MECHANISM` steps a named driving dimension through a range and traces the
motion (`MECHANISMPLAY` animates it). `SANDBOX` builds terrain from contours or a grid (smoove, stamp, drape, convert
to BIM). `MAKECOMPONENT`, `MAKEGROUP`, `MAKEUNIQUE` and `COMPONENTTOBIM` work like SketchUp components and groups;
`OUTLINER` and the `OUTLINERPANEL` window show their tree. `OFFSETFACE` offsets solid faces. Dynamic UCS: the first
point picked on a solid face becomes the working plane for that command, and typed coordinates use the face's axes.

**Round 10 modelling.** Slanted and tapered walls join cleanly with the walls around them in plan, 3D and sections.
A sketch drawn on a solid's face follows the face when the solid moves or is pushed/pulled. `SCALE3D Handles` scales a
solid by dragging a bounding-box handle (corner, edge midpoint, Top/Bottom) with Center and Uniform options; the result
converts to BIM with `BUILDING Mass`.

## 3D view and rendering

- **Navigation:** orbit, pan and zoom with the trackpad or mouse. Use the **view cube** (`NAVVCUBE`) to click a face,
  edge or corner. Standard views are `TOPVIEW`, `FRONTVIEW`, `ISOVIEW` and so on, and `ORBITSELECTION` zooms and orbits
  around the selection. `WALK` starts a first-person walkthrough.
- **Visual styles** (`VSCURRENT`): wireframe, hidden, shaded, shaded with edges, realistic, conceptual, X-ray, sketchy.
- **Saved cameras:** `SAVECAMERA` and `CAMERA`.
- **Section box** (`SECTIONBOX`): cuts the model live. It can be fitted to the selection or a level, is adjusted with
  sliders, and is saved with the drawing.
- **Section plane** (`SECTIONPLANE`): a live horizontal or vertical cut through the 3D model with filled cap faces
  (Flip, Off).
- **Sun study** (`SUNSTUDY`): date and time sliders and a day animation, using the project location.
- **Materials** (`MATERIALS`): the material editor sets colour, roughness, metalness, transparency and texture.
  `MATBROWSER` opens a library of CC0-style materials with rendered thumbnails to add to the drawing or assign to the
  selection. Pattern textures are stored in Application Support by absolute path, so they don't travel with the file
  to another Mac.
- **Render** (`RENDER`): renders the model at a chosen size, with sun date and time, exposure and white balance,
  ambient occlusion, soft-shadow quality and an environment (clear sky, overcast, sunset, studio, night or your own
  HDRI file), or a white or transparent background. **Clay** mode renders everything in a white material. Ambient
  occlusion, soft shadows and sky settings apply to renders, not yet to the live viewport. Built-in presets range from Draft 720p to Print 4K, and you can save your own. Renders save
  as images, and **Export Video** makes a turntable MP4. `WALKTHROUGHVIDEO` renders a video along a camera path,
  `SUNSTUDYVIDEO` a shadow study over a day, and `PANORAMA` a 360° equirectangular image. The render sky is a
  physically based model; glass reflects the environment (no refraction yet), and textures can drive bump.

**Photographic lighting presets.** `RENDERPRESET` (aliases `LIGHTINGPRESET`, `PHOTOLOOK`) gives the Realistic view and
renders one of four looks, and switches the 3D view to Realistic:

| Preset | Look |
| --- | --- |
| `Daylight` | High sun, blue sky with clouds, crisp soft shadows |
| `Goldenhour` | Low warm sun, long shadows, warm sky |
| `Overcast` | Diffuse light from a cloudy sky, very soft shadows |
| `Night` | Dark sky with stars and a moon; windows glow from inside |

Each preset sets its own sun position, a sky generated at run time, soft shadows, exposure, bloom and ambient occlusion;
glass is tinted and reflects the sky, and the ground becomes a large meadow that fades into haze at the horizon.
`RENDERPRESET Off` returns to the default Realistic look. The preset is stored in the drawing. The Render window has the
same choice under **Look**, and a **Supersampling** picker (off, 2× or 3×): the image is rendered larger and filtered down for
smoother edges and foliage.

**Rendering to a file without the window.** `RENDERSAVE <preset> <camera> <width> <height> <path>` (aliases `RENDERPNG`,
`RSAVE`) renders offscreen and writes a PNG, for example

```
RENDERSAVE Goldenhour Front 2560 1440 ~/Desktop/cedar-front.png
```

The camera is a saved camera (`SAVECAMERA`) or `Current` for the current 3D view. The size can be 16 × 16 up to the
renderer's maximum; images up to 1920 × 1080 are supersampled 3×, larger ones 2×, on top of 4× multisampling. Eye-level
cameras keep vertical lines vertical (two-point perspective); aerial cameras keep their natural perspective. A relative
path is saved next to the drawing (or in your home folder for an unsaved drawing); `.png` is added when missing. White balance is applied to the finished image.

The Cedar House sample on the start screen has three saved cameras, Front, Corner and Aerial, and textured materials
with bump and roughness maps, so it is a good place to try the presets.

**More 3D view tools.** `MEASURE3D` measures in the 3D view, `GIZMO3D` moves and rotates objects in plan directions,
`CLIPPLANES` manages clipping planes, and materials can be dropped onto elements. A camera path editor with keys, timeline,
playback and MP4 export saves paths in the drawing; the render queue writes PNGs and keeps a render history.

The 3D gizmo moves along X, Y and Z (also `MOVEZ`), rotates, and scales uniformly in plan. `LEVELVIEW3D` isolates or
explodes levels, `FOV` sets the field of view or lens length and `VIEWIMAGE` saves the 3D view as PNG, JPEG or TIFF
(optionally with a transparent background).

**Round 7 3D view.** Walk mode (with collisions and gravity), `FLY`, `LOOKAROUND`, `POSITIONCAMERA`,
`TWOPOINT` perspective and the `NAVSWHEEL` steering wheel. `LIGHT` places artificial lights, with IES profiles; `MATEMISSIVE`,
`FOG`, `MATMAPPING` (texture mapping and positioning) and `BILLBOARD` extend rendering. `RENDERTOFILE` renders a region or the
whole view at up to 8K as beauty, alpha, depth, normal or material-ID passes. There is a sketchy (hand-drawn) visual style. `STEREOPANORAMA` writes stereo 360°
panoramas, `PHASEANIMATION` animates the construction sequence and `WEBVIEWEREXPORT` writes a web viewer. The sun position uses
the NOAA solar calculator.

**Round 8 rendering.** `PATHTRACE` renders with a CPU path tracer (glass refraction, PBR textures, denoiser) and
`LIGHTMIX` rebalances light groups after rendering. `PROCMATERIAL` generates procedural materials, `MATFROMIMAGE` turns a
photo into a seamless PBR material and `MATASSET` edits identity, appearance and graphics assets. `WEATHER` and `SEASON`
add rain, snow, fog and seasonal foliage; `SCATTER` places vegetation, `WATER` creates animated water surfaces, and
`ANIMATE` animates objects (doors swing about their hinges). `ARQUICKLOOK` exports USDZ at real-world scale. `REGEN`
rebuilds the display and `REDRAW` repaints from the cache. `SPACEMOUSE` configures a 3D mouse.

**Round 9 view.** `ZOOM 1/100XP` (or `ZOOMXP`) sets the selected sheet viewport to 1:100, or on the plan shows the
drawing at that paper scale at true size on the screen. The 3D viewport casts sun shadows that follow the solar position.

**Ambient occlusion and VR.** `AMBIENTOCCLUSION` (or `AODIALOG`) sets intensity, radius and samples; the 3D viewport,
renders and shaded elevations, sections and axonometric/perspective views (and their PDF/SVG exports) follow it.
`VRVIEW` writes a WebXR page with an Enter VR button for headsets (not yet tested on a real headset).

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
- **Sheet set manager** (`SHEETSET`, Sheets panel): orders, duplicates and numbers sheets. `SHEETRENUMBER` numbers them
  with a prefix and start number, `SHEETINDEX` places a sheet list table, and `SHEETREVISION` adds a row to the
  sheet's revision table.
- **View titles:** `VIEWTITLE` (core) and `SHEETVIEWTITLES` (app, editable) place a number bubble, title and scale under
  each viewport. Sheets with editable titles no longer draw the automatic captions.
- **Plot styles** (`PLOTSTYLE`, also `STYLESMANAGER`): colour-dependent (CTB) tables with pen colour, lineweight and
  screening; custom tables are stored in the drawing and chosen in the page setup. `PLOTLOG` lists past plots and
  `BATCHPUBLISH` publishes several sheets or drawings.
- `HPGLOUT` writes the current plan as HP-GL/2 for plotters and cutters.

`SHEETIMAGE` exports a sheet or the model view as an image at a chosen dpi.

**Round 7 sheets.** `EXPORTPDF` writes vector PDF with one PDF layer per drawing layer, searchable text and clickable `HYPERLINK`s. `SHADEPLOT` plots 3D viewports with
hidden lines or shading. `TITLEBLOCKDESIGN` designs your own title block from a block with `{field}` placeholders. Page setup
supports large-format custom pages and roll paper.

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
- **Building physics:** `UVALUE` (EN ISO 6946 from element layers), `HEATLOSS` (steady-state envelope and ventilation
  heat loss with annual demand), `DAYLIGHT` (average daylight factor, BRE formula), `SOLARRADIATION` (clear-sky
  irradiation on walls, windows and roofs), `SUNPATH` (polar sun path diagram), `REVERB` (Sabine RT60) and `CARBON`
  (embodied carbon A1–A3). Solar radiation, daylight factor, embodied carbon,
  reverberation time and isovists are checked by tests against hand calculations; they are still simplified models.
- **More analysis:** `ENERGYBALANCE` (heating need with solar and internal gains; set degree days with the `HDD`
  variable for accurate climate data), `EGRESS` (escape travel distances, measured on a grid, can read up to about 8%
  long), `ACCESSIBILITY` (door clear widths and wheelchair turning circles), `BOQ` (bill of quantities) and `TAKEOFFPHASE`
  (quantities by phase or level).
- **Spaces:** `LEVELAREAS` (gross and net area by level) and `ISOVIST` (area visible from a point).
- **Structure:** `ANALYTICALMODEL` writes the analytical model (nodes, members, panels, supports, loads) as JSON, and
  `FRAMEANALYSIS` solves the column and beam frame for displacements and reactions (up to 300 nodes; walls and slabs
  only add load).
- **Checking:** `CODECHECK` checks rooms, stairs, ramps and doors against JSON rules (`CODERULES`), `STANDARDSCHECK`
  checks layers, properties, text and linetypes against a drawing standard, `IFCVALIDATE` checks an IFC file and
  `IDSCHECK` checks the model against an IDS specification. Code and standards issues can be selected and zoomed to.
- **Review and collaboration:** `COMPARE` finds added, removed and modified objects against another version (with a colour-coded overlay), `MARKUP` adds review
  comments linked to a view and objects, and `BCFOUT`/`BCFIN` exchange issues as BCF with viewpoints and selection.
- Inquiry: `DIST`, `AREA`, `ID`, `LIST`, `MASSPROP`, `MEASUREGEOM`, `COUNT`, `STATUS`.

**More checks.** `ANGLEBETWEEN`, `TLEN` (total length), `DISTTOOBJECT` and `POINTINSIDE`; `LOADTAKEDOWN` (loads down the
structure), `RAINWATER`, `PARKINGCHECK` and `FIRECOMPARTMENTS`; `ISSUETRACKER` and the markup/issue panel keep issues in the
drawing.

**Round 5 analysis and design tools.** `STRUCTLOAD` and `STRUCTSUPPORT` add loads and supports (with OpenSees export),
`THERMALBRIDGES` flags likely thermal bridges, `ENERGYPLUS` exports an EnergyPlus IDF, `WORKSCHEDULE` links elements to
construction tasks (4D) and resources, `AUTODIMPLAN` dimensions a plan, `AUTONAMEROOMS` names rooms, `PLANGEN` lays out
rooms from a brief, `QAASSIST` reviews the model and `ASK` runs plain-language requests as commands.

**Round 6 analysis.** `DAYLIGHTANNUAL` computes spatial daylight autonomy and annual sunlight exposure (sDA/ASE)
from a climate file. `CFDEXPORT` writes an OpenFOAM wind case and `WINDRESULTS` reads the results back. `GENDESIGN` generates
room layouts from a brief and ranks them. `SKETCHTOWALLS` traces a plan image (PNG, BMP, PGM/PPM) into walls. `TIME` reports
editing time, and `CLASHMANAGE` groups clashes and tracks their status. The daylight and wind results have not yet been checked
against Radiance or a reference CFD tool.

**Round 7 analysis.** `SHADOWDIAGRAM` draws ground shadows for a date and a series of times and can export an animated
HTML shadow study. `DAYLIGHTRADIANCE` exports the model to Radiance for sDA/ASE when Radiance is installed. `ENERGYPLUS` writes
richer thermal models and reads the results back. The structural analytical model exports to analysis programs, and IFC
validation checks more rules. `COLORBLINDCHECK` checks layer colours for colour-blind viewers (and can re-colour conflicts from the Okabe–Ito palette), and `MEMORYREPORT`
shows the drawing's memory use. The 3D view builds meshes in the background and uses levels of detail. Radiance, EnergyPlus and
structural results have not yet been checked against the reference tools by us.

**Round 8 analysis.** `SUNPOSITION Validate` checks the solar calculator against the NREL SPA and Meeus reference
examples. With `PSIMETHOD=ISO10211`, `THERMALBRIDGES` computes ψ values with a 2D heat-conduction solver (EN ISO 10211)
from wall build-ups. `WINDRESULTS Solve` runs a built-in 2D flow solver (verified on a channel flow; it underestimates
corner speed-ups on tall buildings).

## Import and export

| Format | Import | Export | Notes |
| --- | --- | --- | --- |
| `.archi` | Open, `IMPORT` | Save | Native JSON project format |
| DXF | Open, `IMPORT` | `EXPORT`, `DXFR12OUT` | Lines, arcs, polylines, text, hatches, blocks, attributes, images, multileaders and paper-space layouts with viewports. `DXFR12OUT` writes R12 for older software |
| IFC 2x3 / IFC4 | `IFCIMPORT` | `EXPORT` | Walls, slabs, columns, beams, doors, windows, openings and spaces become native elements, with storeys, units, materials, wall types and property sets. Sloped slabs, ramps (IfcRamp with flights and landings), footings, ceilings (IfcCovering) and phases round-trip. Other products come in as meshes. GUIDs are kept on re-export |
| SVG | `SVGIMPORT` | `EXPORT`, `SVGLAYERSOUT` | Paths, shapes and text; `SVGLAYERSOUT` writes one SVG group per layer |
| KML/KMZ | | `KMLOUT` | Walls, slabs, roofs and rooms placed at the project location for Google Earth; KMZ also carries the 3D model |
| Images (PNG, JPEG, GIF, BMP, TIFF, WebP) | `IMAGEIMPORT` | | World files (`.pgw`, `.jgw`, `.tfw`) georeference the image |
| OBJ, STL | `MESHIMPORT` | `EXPORT` | STL in ASCII and binary |
| 3MF | `MESHIMPORT` | `EXPORT3MF` | |
| glTF (GLB) | `MESHIMPORT` | `EXPORT` | Binary and embedded glTF |
| PLY, OFF, AMF | `MESHIMPORT` | `PLYOUT` (PLY) | |
| COLLADA | `MESHIMPORT` | `DAEOUT` | Meshes only |
| STEP | `STEPIN` | `STEPOUT` | AP214 faceted export; import reads planar faces only |
| DWG | `DWGIN` | `DWGOUT` | Through an installed ODA File Converter or LibreDWG (`DWGCONVERTER`) |
| IfcZIP | | `IFCZIPOUT` | |
| gbXML | | `GBXMLOUT` | Energy model with constructions and U-values |
| COBie | | `COBIEOUT` | COBie 2.4 workbook |
| XLSX | `XLSXIN` (as tables) | `XLSXOUT` | Schedules |
| HP-GL/2 | | `HPGLOUT` | |
| Point clouds (XYZ, PTS, PLY) | `POINTCLOUDIMPORT` | | Thinned to a point budget |
| Shapefile, OSM, CityJSON, ASCII grid | `SHPIMPORT`, `OSMIMPORT`, `CITYJSONIMPORT`, `DEMIMPORT` | | Placed around the project location |
| USD | | `USDEXPORT` | `.usda` text or `.usdz` package |
| GeoJSON | `GEOJSONIMPORT` | `GEOJSONEXPORT` | WGS84 is converted around the project location |
| CSV/TSV/XYZ points | `POINTSIMPORT` | `POINTSEXPORT` | Survey points, including PNEZD |
| CSV | | `EXPORT`, `TABLEEXPORT`, `ATTEXT` | Schedules, tables, attributes |
| PDF | | `PLOT`, `PUBLISH`, `EXPORT` | Vector, true scale |
| PNG | | `EXPORT`, `RENDER` | |

DXF keeps exact ACI colours, true colour, transparency, text fonts, formatted MTEXT, dimension arrows and extended data
through a round trip. OBJ and glTF exports are scaled correctly for any drawing unit. `EXCHANGECHECK` validates gbXML
and COBie exports against their schema rules. `ETRANSMIT` packs a drawing with its xrefs, images and material
textures into a ZIP with a transmittal report.

**File ▸ Import…** (⇧⌘I) and `IMPORTFILE` accept any of the importable formats and merge the file into the current
drawing, scaled to its units.

**Versions and collaboration.** `VERSIONS` saves, lists, compares, restores and prunes versions of a drawing; `MODELMERGE`
does a three-way merge; `STANDARDS` exports, imports and checks a standards package; `.archiz` is a compressed package. The app
keeps a `.bak` of the previous file when saving (ISAVEBAK), `JOURNAL` and `RECOVERYFILES` recover work after a crash and
`RECOVER` repairs damaged files. DXF now round-trips layouts with viewports, block attributes and hatch pattern definitions;
IFC export writes property and quantity sets and types, with IFC4.3 and model view options in `IFCOPTIONS`; USD (text
and USDZ) and OBJ with materials can be imported. `SHARE` opens the macOS share sheet.

**More formats.** `PDFIMPORT` (vector PDF), `PDFMARKUPS` (PDF comments as review markups), `DWFIMPORT` (DWFx),
`DGNIMPORT`/`DGNEXPORT` (DGN V7), IGES and FBX import and export, LAS point clouds (`POINTCLOUDVIEW` for thinning and
section boxes, `PCPLANE` for plane snapping, `SCANTOBIM` for walls from scans) and `LASEREXPORT` (SVG for laser and CNC
cutters). IFC export writes IFC2x3 as well as IFC4/4.3 with georeferencing (`IFCGEOREF=0` turns it off); `IFCMAP` maps
element types to IFC classes. `CENTRAL` works with a central model (borrowing and synchronising), `GITVERSION` stores a
drawing in a diff-friendly form for Git, `SHAREVIEW` exports a read-only viewer page and `TRACEREVIEW` overlays another
version for review. `IMPORTFILE` also accepts .pdf, .dwfx, .dgn, .las, .igs and .fbx.

**Round 6 file handling.** `SAVECOPY`, `SAVECHECK` and `UPGRADEFILE` (older `.archi` files open and upgrade; the
format is now version 5). `TEMPLATEOUT`/`TEMPLATEIN` handle templates, and `FILEMETADATA` shows the metadata used for
Spotlight. `PDFATTACH` and `PDFUNDERLAYS` add PDF underlays. `BREPIN`/`BREPOUT` exchange OpenCASCADE BREP, and `E57IN`/`E57OUT`
exchange point clouds. `COEDIT` shares a model through a folder; changes sync when you run `COEDIT Sync`. `RESOLVECONFLICTS` merges
sync-conflict copies and `BCFSERVER` connects to a BCF API server. DXF MTEXT keeps stacked fractions, lists and columns. DXF and
SVG keep Unicode and right-to-left text.

**Round 7 exchange.** `DXFOUTVERSION` picks the DXF version (R12 to 2018). `IFCXMLOUT` writes ifcXML, IFC
schemas 2x3, 4 and 4.3 have property set tables, and IFC 4.3 alignments export and import. STEP import reads curved B-reps
(cylinders, spheres, tori, cones, B-spline surfaces) and tessellated AP242 geometry with assemblies. `LAZCONVERTER` sets the
LAZ decompressor used to open `.laz` point clouds. `SURVEYLINES` turns coded survey points into linework ("field to finish").
`PRESENTOUT` writes sheets and views as an HTML slide show and `DOCSITE` writes this documentation as a searchable HTML site.
`SIGNKEY`, `SIGNFILE`, `VERIFYSIGNATURE` and `TRUSTSIGNER` create Ed25519 signing keys, sign files, verify signatures and manage
trusted signers.

**Round 8 exchange.** DXF exports are checked for structure and references (`DXFOUTVERSION` prints the result), 3DFACE
imports keep their heights, ByBlock lineweight and linetype round-trip, and large point clouds (LAS, XYZ/PTS/TXT, PLY) are
sampled without loading the whole file. Co-editing merges per property, so two people editing different properties of
the same object both keep their edits.

**Round 9 exchange.** DXF exports are checked against LibreCAD's libdxfrw reader for R12 to R2018, and fit-point
splines are written as SPLINE entities. IFC validation checks about 80 EXPRESS WHERE rules (`WR-<Entity>.<Rule>`) and each
issue lists the elements to zoom to. `PASTESPECIAL` pastes SVG, PDF, images, DXF or text from other apps, and copied
objects also go on the clipboard as a vector PDF and a PNG (`COPYPICTURE`). Dropping files on the plan or 3D view imports
them; GeoJSON, shapefiles, OSM, CityJSON, terrain grids, point clouds and world-file images keep their map position.
Every save keeps a macOS version (`FILEVERSIONS` opens or restores one), writes Spotlight metadata and a Finder preview
icon (`FILEPREVIEW` turns the extras off). A drawing changed on disk (for example by iCloud Drive) reloads, or is merged
into unsaved edits; iCloud conflict copies are merged. `CENTRAL Permissions` adds signed viewer/editor/admin roles and
protected layers that Sync enforces. `archi-cli --out x.pdf` writes PDF without the app and `archi-cli --validate`
checks exchange files.

**Rhino and SketchUp.** `RHINOIN` imports Rhino .3dm files (versions 2–8) with units, layers, meshes, B-reps and
blocks; `RHINOOUT` writes a version 4 .3dm with layers, meshes and exact curves (materials go out as object colours).
SketchUp .skp files open through a converter you install yourself, set in `SKPCONVERTER`; without one, the app shows
the preview image and explains how to export from SketchUp.

## Scripting and AI agents

- **Script files:** `SCRIPT` runs a `.scr` file of command lines, as in AutoCAD. A blank line or `;` is Enter.
  `SCRIPTTEXT` runs lines given as text. `SCRIPTRECORD` records what you type and pick as a script.
- **JavaScript console** (Script ribbon tab, ⌥⌘J or `SCRIPTCONSOLE`/`JS`): the `archi` API reads and edits the document, runs commands and creates
  building elements. Each change is one undo step. The **script library** (`SCRIPTLIBRARY`) keeps your scripts, and
  `startup.js` runs in every new window if enabled in Settings. The console has autocomplete (⌃Space) and a snippets
  library. See [SCRIPTING.md](SCRIPTING.md).
- **Agent server:** a local JSON-RPC server in the running app (off by default, on 127.0.0.1 only, token-protected)
  lets AI agents drive the open document live. Configure it with `AGENTSETTINGS`.
- **MCP:** `archi-cli --mcp project.archi` is a Model Context Protocol server for Claude Desktop, Claude Code and other
  clients. It provides tools for commands, documents, import, takeoff, cost, schedules, clashes, model checking and sun
  position. `CONNECTCLAUDE` explains the setup. See [AGENT-API.md](AGENT-API.md).
- **Batch jobs:** `BATCH` (and `archi-cli --batch jobs.json`) runs a script or commands over many drawings and saves
  or exports the results.
- The MCP server offers resources (the open document, schedules, the command list) and prompt templates.
- **Command-line tool:** `archi-cli` also converts files, runs scripts headless and has a REPL. `archi-cli --convert
  FMT files… [--outdir DIR]` batch-converts files.
- The MCP server also offers analysis tools (heat loss, U-values, daylight, code check, level areas, schedules,
  structural model, sun path, plan SVG, IFC and IDS validation). Long command logs stream as progress
  notifications and can be capped with `maxLines`.

**Plugins.** Put a plugin folder (a `plugin.json` manifest plus a JavaScript file) in the plugins folder; `PLUGINS` lists,
enables, disables and creates plugins, and their commands appear on the command line and run in the script engine.
`SCRIPT2JS` turns a recorded script into JavaScript. `DELAY` pauses scripts and `RESUME` continues a script stopped with
Escape.

**Round 5 scripting.** `archi.registerCommand(name, fn, {aliases, summary})` turns a script function into a command,
in the app console and in `archi-cli`. `archi.on`/`archi.off` subscribe to selectionChanged, documentChanged,
elementAdded/Removed, saved and commandEnded, and `archi.panel` shows a script-defined panel. `archi-cli` runs JavaScript
(`--js`) and Python (`--py`, `--python-module`) and watches folders for automation (`--watch`). `LISP` and `LISPLOAD`
run an AutoLISP subset, including `C:` commands. `MACROBUTTON` creates buttons that run AutoCAD-style macros; they
appear in the status bar. `SYSVARMONITOR` warns when watched variables change.

**Round 6 app.** Window tabs, file tabs, canvas split views and tiled views; `FULLSCREEN`; Model/Layout tabs;
contextual ribbon tabs; a design center; object info and quick properties panels; an annotation scale selector; import/export
of settings; an integrated help browser with contextual help, tutorials and sample projects. On sheets, viewports can be
rectangular or polygonal (`MVIEWPOLY`, `VPCLIP`), maximised and aligned. You can drag views onto sheets, add guide grids,
placeholder sheets and custom sheet fields, give title blocks a logo, and export layouts to SVG. The 3D view has orbit, standard
views, perspective/parallel projection and wireframe, hidden, shaded, shaded-with-edges, conceptual and X-ray styles, plus a
visual styles manager.

**Round 7 assistant.** `ASSISTANT` opens an AI chat panel that uses the Anthropic API or a local model
(Ollama or another compatible server). Its edits run as normal undoable commands, and bulk changes ask for confirmation first.
`RENDERPROMPT` styles renders from a text prompt, `GRAPHPLAYER` runs saved node graphs with their inputs, `RADIALMENU` opens a
radial menu, `HYPERLINK` attaches links and `SYSWINDOWS` arranges open drawings side by side.

**Automation and node packages.** Shortcuts and other apps can drive the app with `oanarina-archi://run?command=…`,
`open?path=…` and `export?format=…&path=…` URLs, and AppleScript can send commands with `do script`. `NODEPACKAGE`
saves node-editor groups as reusable packages (Packages menu in the node editor).

## Settings and customisation

`OPTIONS` (⌘,) opens Settings, where you can change:

- units, grid and snaps
- autosave interval
- canvas background and crosshair size (`CURSORSIZE`)
- accent colour and light/dark theme (`THEME`)
- file locations (templates, exports, scripts)
- quick access toolbar
- recent files limit
- agent server and scripts

**Start screen and templates:** `STARTSCREEN` shows recent drawings with thumbnails and templates.
`NEWFROMTEMPLATE` starts a drawing from a `.architemplate` (such as Metric Architectural, with its layers and dimension
styles) and `SAVEASTEMPLATE` saves the current drawing as one. `EXPORTCOMMANDS` writes the full command reference with
where each command is in the menus. Every command is on the ribbon, a menu or a palette; the Tools menu and each tab's
**More** menu hold the rest, and system variables have their own menu.

**Keyboard shortcuts** can be assigned to any command. For example, record ⇧⌘W for `WALL`. Your shortcuts take
priority over menu shortcuts. The shortcut list can be searched, warns about conflicts, and can be exported to and
imported from JSON. **Reset to defaults** restores every setting. All changes apply without a restart.

New side-panel tabs: **Navigator** (mini-map), **Selection Info** and **Notifications** (click a warning to zoom to it).
`WHATSNEW` shows what changed after an update.

**Command line and ribbon.** `CMDLINEOPTIONS` sets the command line's text size, number of lines, opacity and whether it
floats. The app accepts launch arguments: files to open, `-t`/`--template`, `-s`/`--script` and `-c`/`--command`. `CUI` customises the ribbon
(reorder panels and buttons, export and import). Full-screen state survives relaunch and windows fit a Split View half.

**Round 9 accessibility.** VoiceOver reads the canvas, 3D view, sheet view, status toggles and icon buttons, and
speaks new prompts; `SPEAKDRAWING` describes the drawing. Keyboard-only drawing: arrow keys move the crosshair at
prompts, Return picks the point and Tab selects under it (`KEYBOARDNAV` sets the step). `LANGUAGE` translates the
ribbon and the menu bar into Romanian, German, French, Spanish and Italian (dialogs are still English).

**Crash reports and menus.** `CRASHREPORTS On` turns on opt-in crash reports (off by default). Reports have file
names and home paths removed, and the next launch offers to open a GitHub issue or copy the report; nothing is sent
automatically. The menu bar titles and common menu items now follow `LANGUAGE`.

## Keyboard and mouse

| Keys | Action |
| --- | --- |
| Type anywhere | Start a command on the command line |
| Enter / Space | Finish input, repeat the last command |
| Esc | Cancel the command, clear the selection |
| Right-click | Enter while a command runs, context menu when idle |
| Tab | Accept autocomplete |
| ↑ / ↓ | Command history / suggestions |
| F3 · F7 · F8 · F9 · F10 · F11 · F12 | Object snap · grid · ortho · grid snap · polar tracking · object snap tracking · dynamic input |
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

## Tutorial videos

The app can record its own tutorial videos. The tutorial series (twelve scripts, from a first look at the interface to
scripting and AI agents) builds the Cedar House from an empty drawing:

| # | Tutorial |
| --- | --- |
| 01 | Getting started: start screen, interface tour, 2D/3D/Split/Sheet |
| 02 | The command line: commands, aliases, coordinates, options, repeat and undo |
| 03 | Drawing basics: rectangles, circles, polylines, snaps, fillet, trim, offset |
| 04 | Levels and walls |
| 05 | Doors and windows |
| 06 | Floors, roofs and stairs |
| 07 | Rooms and annotation |
| 08 | 3D view and materials |
| 09 | Rendering |
| 10 | Sheets and PDF |
| 11 | Import and export |
| 12 | Scripting and AI agents |

**Tools ▸ Tutorial Videos** (`TUTORIALRECORD`, aliases `TUTORIALVIDEOS`, `TUTREC`) has three options:

- **List** prints each bundled tutorial with its number of steps and estimated length.
- **Check** plays every step against the real editor without recording and reports failed commands or buttons that
  could not be found (a dry run).
- **Record** asks which tutorials to record (numbers or names separated by spaces; Enter records all) and an output
  folder, then opens a new window at 1440 × 900 and plays each script there: it types into the command line, presses
  ribbon and panel buttons, clicks on the plan and orbits the 3D view, and records the window as an H.264 MP4 at 30 fps
  with an animated cursor, click ripples, captions and keystroke pills. A `.log` file next to each video lists what was
  typed and what the app answered. The Finder shows the folder when it has finished.

Leave the recording window alone until the recorder closes it: real mouse and keyboard input still reaches it, and
closing it stops the recording. Recording takes about as long as the videos. The window is captured with the app's own
drawing, so it needs no screen-recording permission and works while the screen is locked. Videos follow the display's
resolution (2880 × 1800 on a Retina display).

The scripts are plain text files (`.tut`, one step per line: `type`, `click`, `pick`, `orbit`, `camera`, `note`,
`wait` and others); the format is described in `tutorials/README.md` in the source repository. From the Terminal,
`scripts/make-tutorials.sh record [numbers…]` records them, and the app accepts `--record-tutorials DIR` to record and
quit.

## Command reference

Every command can be typed on the command line, used in scripts and called by agents. Aliases are alternative names.
Any system variable can also be typed as a command (for example `TEXTSIZE 350`), and `HELP <command>` describes a
command inside the app. This table is generated from the command definitions in the source
(`python3 docs/gen_command_reference.py`).

<!-- BEGIN COMMAND REFERENCE -->
994 commands.

### Draw

| Command | Aliases | Description |
| --- | --- | --- |
| `ARC` | `A` | Draws an arc (3 points, start-center-end, start-end-radius, center-start-angle, continue). |
| `ARC2PH` | `ARCHEIGHT` | Draws an arc through two end points with a given height (sagitta); pick or type the height. |
| `ARC2PL` | `ARCBYLENGTH` | Draws an arc through two end points with a given arc length (longer than the chord). |
| `ARCTOCIRCLE` | `CIRCLEFROMARC`, `ARC2CIRCLE` | Completes arcs into full circles (keeps layer and properties). |
| `BLEND` | `BLENDCURVES`, `BL` | Creates a tangent (or smooth) spline joining the ends of two open curves. |
| `BOUNDARY` | `BO`, `BPOLY` | Creates closed polylines from the area enclosed around a picked point. |
| `BOUNDINGBOX` | `BBOX` | Draws the rectangle bounding the selected objects. |
| `BOX` |  | Creates a 3D solid box (on the face under the first corner when DUCS is on). |
| `CENTERLINE` | `CL` | Creates an associative centre line between two lines. |
| `CENTERMARK` | `CM`, `DIMCENTER`, `DCE` | Adds associative centre marks to circles and arcs. |
| `CIRCLE` | `C` | Draws a circle (center/radius, diameter, 2P, 3P, tangent-tangent-radius, tangent-tangent-tangent). |
| `CIRCLE2PR` | `C2PR` | Draws a circle through two points with a given radius (pick the side of the centre). |
| `CIRCLETPP` | `CTPP` | Draws a circle tangent to one object through two points. |
| `CIRCLETTP` | `CTTP` | Draws a circle tangent to two objects through one point. |
| `CIRCLETTT` | `CTTT` | Draws a circle tangent to three objects (lines, circles, arcs). |
| `CONE` |  | Creates a 3D solid cone or frustum. |
| `CYLINDER` | `CYL` | Creates a 3D solid cylinder: centre, 3P, 2P or Elliptical base; height, 2Point or Axis endpoint. |
| `DLINE` | `DL`, `DOUBLELINE` | Draws double lines (two parallel polylines with end caps). |
| `DONUT` | `DO`, `DOUGHNUT` | Draws filled rings or solid dots. |
| `ELLIPSE` | `EL` | Draws an ellipse or elliptical arc. |
| `ELLIPSE4P` | `EL4P` | Draws an ellipse through four points with its axes at a given angle (default 0). |
| `ELLIPSEC3P` | `ELC3P` | Draws an ellipse from its centre and three points on the curve. |
| `ELLIPSEFOCI` | `ELFOCI` | Draws an ellipse from its two foci and a point on the curve. |
| `ELLIPSEQUAD` | `ELQ`, `ELLIPSEPARALLELOGRAM`, `ISOCIRCLE`, `ELLIPSE4` | Draws the largest ellipse inscribed in a quadrilateral (tangent to its four sides): four corners, a 4-sided closed polyline, or four lines. |
| `EXTRUDE` | `EXT` | Extrudes closed 2D objects into 3D solids: height, Direction (oblique), Path, Taper angle, Both sides (symmetric). |
| `GRADIENT` | `GD` | Fills an enclosed area or selected objects with a gradient fill (linear, cylinder, spherical, curved; one or two colours). |
| `HATCH` | `H`, `BHATCH`, `BH` | Fills an enclosed area or selected objects with a hatch pattern or solid fill. |
| `HELIX` |  | Draws a 2D/3D helix or spiral: base and top radius, turns, height and twist direction. |
| `HYPERBOLA` |  | Draws a hyperbola branch from centre, vertex, conjugate semi-axis and half-height (as a smooth polyline). |
| `INCIRCLE` | `CIRCLEINSCRIBED` | Draws the circle inscribed in the triangle formed by three lines. |
| `LINE` | `L` | Draws straight line segments. |
| `LINEANG` | `LANG`, `LINEBYANGLE` | Draws a line from a point at a fixed angle and length. |
| `LINEBISECT` | `LBIS`, `BISECTOR` | Draws the bisector of the angle between two lines from their intersection. |
| `LINEHV` | `HVLINE`, `LHV` | Draws horizontal or vertical lines (end points are projected). |
| `LINEPAR` | `LPAR`, `PARALLELLINE` | Draws a line parallel to a picked line through a point. |
| `LINEPERP` | `LPERP`, `PERPLINE` | Draws a line from a point perpendicular to a picked line (to its foot). |
| `LINEREL` | `LREL`, `LINERELANGLE` | Draws a line at an angle relative to a picked line or segment. |
| `LINETAN` | `LTAN`, `TANLINE` | Draws a line from a point tangent to a circle or arc. |
| `LINETAN2` | `LTAN2`, `TANGENTLINE2` | Draws a common tangent of two circles (Outer or Inner), picked near the tangent points. |
| `LINETANORTHO` | `LTANO` | Draws a line tangent to a circle and perpendicular to a line (from the tangent point to the line). |
| `MLINE` | `ML` | Draws multiple parallel lines (multiline style, scale, Top/Zero/Bottom justification), grouped. |
| `MLSTYLE` | `-MLSTYLE` | Multiline styles: New (element offsets, caps), Set current, List, Delete. |
| `PARABOLA` |  | Draws a parabola from its vertex, focus and half-width (as a smooth polyline). |
| `PATLOAD` | `HATCHPATLOAD`, `LOADPAT` | Loads hatch patterns from an AutoCAD .pat file into the drawing (saved with it). |
| `PLINE` | `PL` | Draws a 2D polyline of line and arc segments. |
| `POINT` | `PO` | Creates point objects (style: PDMODE/PDSIZE). |
| `POINTLATTICE` | `PTLATTICE`, `POINTGRID` | Places a lattice of points (columns × rows at given spacings, optional angle). |
| `POINTSLINE` | `PTLINE`, `POINTSONLINE` | Places a number of evenly spaced points between two points (both ends included). |
| `POLYGON` | `POL` | Draws an equilateral closed polyline. |
| `POLYGONSS` | `POLSS`, `POLYGONSIDES` | Draws a regular polygon from the midpoint of one side and the opposite side (odd sides: opposite vertex). |
| `PTYPE` | `DDPTYPE` | Sets the point display style (PDMODE) and size (PDSIZE). |
| `RAY` |  | Draws semi-infinite construction lines from a start point through each given point. |
| `RECTANG` | `REC`, `RECTANGLE` | Draws a rectangular polyline (optionally filleted or chamfered). |
| `REGION` | `REG` | Converts closed chains of lines/arcs into closed polylines (regions). |
| `REVCLOUD` |  | Draws a revision cloud: polygonal, rectangular, freehand, from an object or enclosing objects (attached: it moves with them); tagged with the current revision. |
| `REVOLVE` | `REV` | Revolves closed 2D objects about an axis into 3D solids (associative: the solid regenerates when the profile is edited; DELOBJ 1 deletes profiles). |
| `SKETCH` |  | Freehand sketch: records the points of a drag (record increment, Type polyline/line/spline) until Enter. |
| `SNAKE` | `SNAKELINE` | Draws a polyline from relative moves: R500 L200 U300 D100 (right/left/up/down), @dx,dy or @d<angle; Close/Undo. |
| `SOLID` | `SO` | Creates solid-filled triangles and quadrilaterals (AutoCAD point order 1-2-3-4). |
| `SPHERE` |  | Creates a 3D solid sphere. |
| `SPLINE` | `SPL` | Draws a smooth curve through fit points, or by control vertices (Method CV, Degree 1-5). |
| `STAR` |  | Draws a star-shaped closed polyline. |
| `TABLE` | `TB` | Inserts an empty table. |
| `TRACE` |  | Draws solid lines of a given width (a wide polyline). |
| `WIPEOUT` |  | Creates a masking area (solid background fill) that covers objects beneath. |
| `XLINE` | `XL` | Draws infinite construction lines: through two points, Horizontal, Vertical, at an Angle (or relative to a Reference line), Bisecting an angle, or Offset from a line. |

### Modify

| Command | Aliases | Description |
| --- | --- | --- |
| `ALIGN` | `AL` | Aligns objects with other objects using source/destination point pairs. |
| `ALIGNREF` | `ALIGNTO`, `ROTATETOREF` | Rotates objects about a base point so a reference direction (line or two points) aligns with a target line or angle. |
| `ARRAY` | `AR` | Creates copies of objects in a rectangular, polar or path pattern. |
| `ARRAYCLASSIC` | `-ARRAYCLASSIC`, `ARRAYNONASSOC` | Creates a non-associative (separate copies) rectangular, polar or path array. |
| `ARRAYEDIT` | `ARRAYED` | Edits an associative array: rows, columns, spacing, items, fill angle, rotation, alignment. |
| `ARRAYPATH` |  | Array of objects evenly spaced along a path. |
| `ARRAYPOLAR` |  | Polar array of objects around a center point. |
| `ARRAYRECT` |  | Rectangular array of objects in rows and columns. |
| `BREAK` | `BR` | Breaks an object between two points. |
| `BREAKALL` | `BREAKATINTERSECTIONS`, `DIVIDEATINTERSECTIONS` | Breaks the selected objects at every intersection with each other. |
| `BREAKATPOINT` | `BRP` | Breaks an object into two at a single point. |
| `CHAMFER` | `CHA` | Bevels the corner between two lines (distance or length/angle method). |
| `CHPROP` | `CHANGE`, `CH`, `-CH` | Changes color, layer, linetype, lineweight or material of objects. |
| `CHSPACE` | `CHANGESPACE` | Moves objects between model space and a layout's paper space through a viewport, keeping their size on the sheet. |
| `CLIPPOLY` | `CLIPWITHPOLYGON`, `CLIPBOUNDARY` | Clips the selected curves with a closed boundary, keeping the parts Inside or Outside. |
| `CONVERTTOPLINE` | `TOPLINE`, `SPLINETOPLINE`, `CONVTOPL` | Converts lines, arcs, circles, ellipses and splines to polylines (curves sampled within a tolerance). |
| `COPY` | `CO`, `CP` | Copies objects (multiple copies, or a linear array). |
| `CUTBYLINE` | `SLICELINE`, `DIVIDEBYLINE` | Divides the selected objects where a cutting line crosses them. |
| `DIVIDE` | `DIV` | Places points or blocks at equal intervals along an object. |
| `DRAWORDER` | `DR` | Changes the draw order of objects (front, back, above, under). |
| `ERASE` | `E`, `DELETE` | Removes objects from the drawing. |
| `EXPLODE` | `X` | Breaks compound objects (polylines, blocks, hatches, dimensions) into their parts. |
| `EXTEND` | `EX` | Extends objects to meet boundary edges (all objects by default). |
| `EXTENDBY` | `TRIMBY`, `LENGTHENBY` | Extends (positive) or trims (negative) curves by an amount at the picked end: lines, arcs, polylines, ellipses, splines. |
| `FILLET` | `F` | Rounds the corner between two objects (radius 0 = sharp corner). |
| `FLATTEN` |  | Converts objects to flat 2D geometry at elevation 0 (3D solids become their plan outlines). |
| `HATCHEDIT` | `HE`, `-HATCHEDIT` | Edits hatches: Properties (pattern, scale, angle), Color/background, Associate, DIsassociate, ADd/Remove boundaries, recreate Boundary, separate Hatches. |
| `HATCHGENERATEBOUNDARY` | `HGB` | Creates closed polylines around selected hatches and makes the hatches associative to them. |
| `HATCHSETORIGIN` | `HATCHORIGIN` | Sets the pattern origin of hatches: a point, a corner or the centre of the hatch extents, or the default (0,0). |
| `HATCHTOBACK` |  | Sends all hatches behind other objects. |
| `IMAGESCALE` | `SCALEIMAGE`, `IMAGECALIBRATE`, `CALIBRATE` | Calibrates an image: pick two points on it and enter their real distance; the image is scaled about the first point. |
| `JOIN` | `J` | Joins lines, arcs and polylines at their end points. |
| `LENGTHEN` | `LEN` | Changes the length of lines, arcs and open polylines (Delta/Percent/Total). |
| `LINEGAP` | `GAPS`, `CROSSINGGAP` | Cuts gaps in the selected objects where other objects cross them (crossing display). |
| `MATCHPROP` | `MA`, `PAINTER` | Applies the properties of a source object to other objects. |
| `MEASURE` | `ME` | Places points or blocks at measured intervals along an object. |
| `MIRROR` | `MI` | Creates a mirrored copy of objects. |
| `MOVE` | `M` | Moves objects a specified distance in a specified direction. |
| `MOVEROTATE` | `MOVROT`, `MR` | Moves objects from a base point to a destination, then rotates them about it. |
| `NUDGE` |  | Moves the selection by small steps: Left/Right/Up/Down (× count), or a vector dx,dy (arrow-key nudging). |
| `OFFSET` | `O` | Creates parallel copies of lines, arcs, circles and polylines. |
| `OFFSETMULTI` | `EQUIDISTANT`, `OFFSETM` | Creates several equidistant offset copies of an object on one side. |
| `OOPS` |  | Restores the objects removed by the last ERASE. |
| `OVERKILL` | `-OVERKILL` | Removes duplicate objects and merges overlapping collinear lines. |
| `PEDIT` | `PE` | Edits polylines: close/open, join, width, spline, decurve, reverse. |
| `PLINETOSPLINE` | `TOSPLINE`, `CONVTOSPLINE` | Converts polylines (and lines) to splines fitted through their vertices. |
| `REGIONINTERSECT` | `INTERSECT2D`, `PINTERSECT` | Keeps the common area of closed 2D regions (as closed polylines). |
| `REGIONSUBTRACT` | `SUBTRACT2D`, `PSUBTRACT` | Subtracts closed 2D regions from others (result as closed polylines; holes become separate polylines). |
| `REGIONUNION` | `UNION2D`, `PUNION` | Unites closed 2D regions (closed polylines, circles, ellipses, hatches) into closed polylines. |
| `REVERSE` |  | Reverses the vertex order of lines, polylines, splines and arcs. |
| `ROTATE` | `RO` | Rotates objects around a base point. |
| `ROTATE2` | `ROTATETWICE`, `RO2` | Rotates objects about a first centre, then about a second centre. |
| `ROTATE90` | `R90`, `ROT90` | Rotates the selection 90° counter-clockwise (or [Clockwise]) about its centre or a base point. |
| `SCALE` | `SC` | Enlarges or reduces objects around a base point. |
| `SELECT` |  | Selects objects and keeps them as the current selection. |
| `SELECTALL` | `AI_SELALL` | Selects all selectable objects on unlocked layers (current level). |
| `SETBYLAYER` | `SBL` | Sets color, linetype and lineweight of objects (and block contents) to ByLayer. |
| `SPLINEDIT` | `SPE` | Edits splines: Close/Open, Fit data (Add/Delete/Move), control vertices, Convert to CV form or Polyline, Reverse, Undo. |
| `STRETCH` | `S` | Stretches objects crossed by a window; objects fully inside are moved. |
| `TEXTTOFRONT` |  | Brings text, dimensions and/or leaders in front of other objects (options: Text/Dimensions/Leaders/All). |
| `TRIM` | `TR` | Trims objects at cutting edges (all objects are cutting edges by default). |
| `TXTEXP` | `TEXTEXPLODE`, `EXPLODETEXT` | Explodes text into line geometry drawn with the built-in stroke font (or [Letters]: single-letter text objects). |
| `WELD` | `MERGECURVES` | Merges curves touching end to end (lines, arcs, polylines, splines, ellipse arcs) into polylines. |

### Parametric

| Command | Aliases | Description |
| --- | --- | --- |
| `AUTOCONSTRAIN` | `AUTOC` | Infers and applies constraints (coincident, tangent, horizontal, vertical, parallel, perpendicular) to the selected objects within tolerances. |
| `CONSTRAINTBAR` | `CBAR`, `CONSTRAINTGLYPHS`, `SHOWCONSTRAINTS` | Shows or hides constraint glyphs next to constrained objects in the plan [Show/Hide/Toggle] (CONSTRAINTBAR variable). |
| `CONSTRAINTLIST` | `LISTCONSTRAINTS` | Lists the constraints (of the selected objects, or all) with their values and the remaining degrees of freedom. |
| `DCALIGNED` |  | Applies the aligned dimensional constraint. |
| `DCANGULAR` |  | Applies the angular dimensional constraint. |
| `DCCONVERT` |  | Converts dimensions into dimensional constraints. |
| `DCDIAMETER` |  | Applies the diameter dimensional constraint. |
| `DCDIFFERENCE` |  | Applies the difference dimensional constraint. |
| `DCHORIZONTAL` |  | Applies the horizontal dimensional constraint. |
| `DCLINEAR` |  | Applies the linear dimensional constraint. |
| `DCRADIUS` |  | Applies the radius dimensional constraint. |
| `DCRATIO` |  | Applies the ratio dimensional constraint. |
| `DCVERTICAL` |  | Applies the vertical dimensional constraint. |
| `DELCONSTRAINT` | `DELCON` | Removes all geometric and dimensional constraints from the selected objects (or All). |
| `DIMCONSTRAINT` | `DCON` | Applies a dimensional (driving) constraint: LInear/Horizontal/Vertical/Aligned distance, ANgular, Radius, Diameter, or Convert dimensions; values may be expressions of parameters. |
| `GCCOINCIDENT` |  | Applies the coincident geometric constraint. |
| `GCCOLLINEAR` |  | Applies the collinear geometric constraint. |
| `GCCONCENTRIC` |  | Applies the concentric geometric constraint. |
| `GCEQUAL` |  | Applies the equal geometric constraint. |
| `GCFIX` |  | Applies the fixed geometric constraint. |
| `GCHORIZONTAL` |  | Applies the horizontal geometric constraint. |
| `GCMIDPOINT` |  | Applies the midpoint geometric constraint. |
| `GCPARALLEL` | `GCPAR` | Applies the parallel geometric constraint. |
| `GCPERPENDICULAR` | `GCPERP` | Applies the perpendicular geometric constraint. |
| `GCPOINTONCURVE` | `GCONCURVE` | Applies the point on curve geometric constraint. |
| `GCSYMMETRIC` |  | Applies the symmetric geometric constraint. |
| `GCTANGENT` |  | Applies the tangent geometric constraint. |
| `GCVERTICAL` |  | Applies the vertical geometric constraint. |
| `GEOMCONSTRAINT` | `GCON`, `GC` | Applies a geometric constraint: Horizontal, Vertical, Perpendicular, PArallel, Tangent, COincident, CONcentric, COLlinear, Symmetric, Equal, Fix, Midpoint, OnCurve. |
| `MECHANISM` | `LINKAGE`, `ANIMATEDIM`, `DRIVEDIM` | Mechanism simulation: steps a named driving dimension (angles in degrees) through a range, re-solving the constraints each step; draws the path of a traced point, optional ghost poses, reports lock-up and the range of other dimensions. |
| `MECHANISMPLAY` | `ANIMATEMECHANISM`, `PLAYMECHANISM`, `MECHANISMANIMATE` | Animates a mechanism on the plan: steps a named driving dimension through a range (re-solving the constraints) and plays the poses Once, in a Loop or Bounce; Stop ends it. The drawing is not changed. *(app)* |
| `PARAMETERS` | `PARAM`, `PARAMETERSMANAGER`, `PARAMS` | Parameters manager: New/Edit/Delete/List user parameters and dimensional constraint expressions; geometry updates. |
| `SKETCHPLANE` | `SKETCHER`, `NEWSKETCH`, `SKETCHON`, `SKETCH3D` | Sketch environment: New sketch on a work plane (XY at an elevation, a solid Face, or vertical through a Line), Add objects drawn in sketch coordinates, Status (degrees of freedom — constrain with the geometric/dimensional constraints), List, Delete. |

### Edit

| Command | Aliases | Description |
| --- | --- | --- |
| `COPYBASE` |  | Copies objects to the clipboard with a base point. |
| `COPYCLIP` |  | Copies objects to the clipboard. |
| `COPYPICTURE` | `COPYASPDF`, `COPYIMAGE`, `COPYPDF` | Copies the selected objects (or the whole drawing) to the clipboard as a vector PDF and a PNG picture for other apps. *(app)* |
| `CUTCLIP` |  | Moves objects to the clipboard (removes them from the drawing). |
| `PASTEBLOCK` |  | Pastes the clipboard as a block reference. |
| `PASTECLIP` |  | Pastes the clipboard at an insertion point. |
| `PASTEORIG` |  | Pastes the clipboard at its original coordinates. |
| `PASTESPECIAL` | `PASTESPEC`, `PASTEEXTERNAL`, `PASTEFROMAPP` | Pastes what another app copied — SVG or PDF vectors, pictures, DXF text, plain text or Finder files — at an insertion point. *(app)* |
| `PASTETOPOINTS` | `COPYTOPOINTS`, `PASTEMULTI` | Pastes the clipboard at several picked points (one undo step). |
| `REDO` | `MREDO` | Reverses the last undo. |
| `U` |  | Reverses the most recent action. |
| `UNDO` |  | Reverses actions: a count, or Mark/Back (to a mark) and BEgin/End (group several commands into one step). |

### Select

| Command | Aliases | Description |
| --- | --- | --- |
| `DESELECT` | `SELECTNONE`, `DESELECTALL` | Clears the selection (keeps it as the previous selection). |
| `FILTER` | `FI`, `SELECTFILTER` | Selects objects matching a filter expression (type=circle & radius>50 \| layer=A-*); filters can be saved by name. |
| `HIDEOBJECTS` | `HIDEOBJ` | Temporarily hides the selected objects (kept with the drawing until UNISOLATEOBJECTS). |
| `ISOLATEOBJECTS` | `ISOLATEOBJ`, `ISOLATE` | Temporarily hides every object except the selected ones (on the current level for building elements). |
| `QSELECT` | `QSEL` | Quick select: objects of a type whose property matches a value (e.g. QSELECT Circle radius > 50). |
| `QSELECTDIALOG` | `QSD`, `QUICKSELECT` | Quick Select dialog: type, property, operator and value with a live match count. *(app)* |
| `SELECTCHAIN` | `SELCHAIN`, `SELECTCONTOUR` | Selects the chain (contour) of curves connected end-to-end with the picked one. |
| `SELECTINSTANCES` | `SELINST`, `SELECTALLINSTANCES` | Selects every instance of the same block, opening type, wall type or element type as the picked object. |
| `SELECTINTERSECTING` | `SELINT` | Selects every object that intersects the picked one. |
| `SELECTINVERT` | `INVSEL`, `SELINV` | Inverts the selection (selects every other selectable object). |
| `SELECTLAYER` | `SELLAYER`, `LAYSEL` | Selects every object on the given layer(s) (wildcards allowed) or on the layer of a picked object. |
| `SELECTPREVIOUS` | `SELPREV`, `PSELECT` | Selects the previous selection set again (only objects still selectable). |
| `SELECTSIMILAR` | `SELSIM` | Selects all objects similar to the selected ones (type, plus the properties in SELECTSIMILARMODE). |
| `SELECTTYPE` | `SELTYPE` | Selects objects by type or category (Line, Circle, Text, Annotation, Curve, Wall, Door, Element…); several types separated by commas. |
| `SELECTWALLCHAIN` | `WALLCHAIN` | Selects the chain of walls joined to a picked wall (Tab over a wall does the same). *(app)* |
| `SELSET` | `NAMEDSELECTION` | Saves, restores, lists and deletes named selection sets (stored in the drawing). |
| `UNISOLATEOBJECTS` | `UNISOLATE`, `UNHIDE`, `ENDISOLATION` | Shows all objects hidden by HIDEOBJECTS or ISOLATEOBJECTS. |

### Annotate

| Command | Aliases | Description |
| --- | --- | --- |
| `ANNOTATIVE` | `ANNO` | Makes text, leaders and tables annotative (height follows CANNOSCALE) or turns it off. |
| `ARCTEXT` |  | Places text along an arc (convex or concave side, height, offset), one character per text object, grouped. |
| `AUTODIMGRIDS` | `GRIDDIMS`, `DIMGRIDS` | Associative dimension string across parallel grid lines (bay dimensions and overall), updated when grids move. |
| `AUTODIMPLAN` | `DIMPLAN`, `PLANDIMS`, `AUTODIMOVERALL` | Dimensions the current level's plan automatically: exterior chains on all four sides (openings, walls, overall) on layer A-ANNO-DIMS; asks before adding them (one undo step). |
| `AUTODIMWALLS` | `AUTODIMENSION`, `WALLDIMS`, `DIMWALLS` | Automatic dimension strings along wall faces through wall ends and openings, with an overall dimension. |
| `AUTOSTACK` | `TEXTSTACK`, `STACK` | Stacks typed fractions in text (1/2, 3#4, 1^2) or unstacks them. |
| `BREAKLINE` | `BREAKLINESYMBOL` | Draws a break line with a zig-zag symbol (size, extension). |
| `DATALINKUPDATE` | `DLU` | Updates linked tables from their CSV/XLSX files (Update) or writes table cells back to the files (Write). |
| `DETAILCOMPONENT` | `DETAILCOMP`, `DC`, `COMPONENT2D` | Places a 2D detail component (lumber, studs, brick, CMU, plywood, gypsum, steel sections) in the current view. |
| `DETAILMARK` | `DETMARK`, `DETAILSYMBOL` | Places a 2D detail bubble (number / sheet attributes) with an optional leader to the detail. |
| `DIM` |  | Smart dimension: picks an object (line → linear/aligned, arc → radius, circle → diameter) or two points. |
| `DIMALIGNED` | `DAL`, `DIMALI` | Creates a dimension aligned with its extension line origins. |
| `DIMALTUNITS` | `DIMALTU`, `DUALUNITS` | Shows alternate units on dimensions, e.g. mm [in]: factor, decimals, suffix (Off removes them). |
| `DIMANGULAR` | `DAN`, `DIMANG` | Dimensions the angle between lines, of an arc, or of three points. |
| `DIMARC` | `DAR` | Dimensions the length of an arc. |
| `DIMBASELINE` | `DBA`, `DIMBASE` | Creates dimensions from the baseline of the last dimension. |
| `DIMBREAK` |  | Breaks dimension and extension lines where objects cross them (Auto, chosen objects or Manual gaps; associative). |
| `DIMCONTINUE` | `DCO`, `DIMCONT` | Continues a chain of dimensions from the last one. |
| `DIMDIAMETER` | `DDI`, `DIMDIA` | Dimensions the diameter of a circle or arc. |
| `DIMDISASSOCIATE` | `DDA` | Removes associativity from selected dimensions. |
| `DIMEDIT` | `DED`, `DIMED` | Edits dimension text: Home (measured value), New text (<> = measurement). |
| `DIMINSPECT` | `INSPECTDIM` | Adds or removes an inspection frame (label \| value \| rate, round or angular ends) on dimensions. |
| `DIMJOGGED` | `DJO`, `JOG` | Creates a jogged radius dimension for large arcs and circles (overridden centre, jog). |
| `DIMJOGLINE` | `DJL` | Adds or removes a jog line on a linear or aligned dimension (the value is not to scale). |
| `DIMLINEAR` | `DLI`, `DIMLIN` | Creates a horizontal, vertical or rotated linear dimension. |
| `DIMORDINATE` | `DOR`, `DIMORD` | Creates X or Y ordinate dimensions from the origin (0,0). |
| `DIMOVERRIDE` | `DOV`, `-DIMOVERRIDE` | Overrides dimension style variables (DIMTXT, DIMASZ, DIMDEC, DIMSCALE, DIMPOST…) on selected dimensions, or Clear overrides. |
| `DIMRADIUS` | `DRA`, `DIMRAD` | Dimensions the radius of an arc or circle. |
| `DIMREASSOCIATE` | `DRE` | Associates dimensions with the objects at their definition points (automatic within a tolerance) so they follow edits. |
| `DIMREBASE` | `ORDINATEREBASE`, `ORDREBASE` | Changes the datum (origin) of ordinate dimensions. |
| `DIMREGEN` |  | Updates associative dimensions, dimension breaks and overrides. |
| `DIMSPACE` |  | Evenly spaces parallel linear/aligned dimensions from a base dimension (0 aligns them). |
| `DIMSTYLE` | `D`, `DST`, `DDIM`, `-DIMSTYLE` | Creates, edits, lists and sets dimension styles. |
| `DIMTEDIT` | `DIMTED` | Moves the text / dimension line of a dimension to a new location. |
| `DIMTOLERANCE` | `DIMTOLS`, `DTOL` | Adds tolerances to dimensions: Symmetrical ±t, Deviation +u/−l, Limits (upper/lower values), Basic (boxed) or None. |
| `ELEVATIONMARK` | `ELEVMARK`, `ELEVATIONSYMBOL` | Places a 2D elevation marker (bubble with a pointer in the view direction; 4 for an interior elevation set). |
| `EQDIM` | `EQUALITYDIM`, `EQCONSTRAINT` | Equality dimensions: a chain of EQ dimensions that keeps three or more objects equally spaced (Create/Toggle EQ-value/Remove). |
| `FIELD` |  | Inserts text containing a field (area, length, property, variable, count, date) that updates automatically. |
| `FILLEDREGION` | `FR`, `REGIONFILL` | View-specific filled region on the current level: solid colour or a drafting / model pattern, with optional boundary lines; associative to its boundary. |
| `FIND` |  | Finds (and optionally replaces) text in texts, leaders, dimensions, tables and attributes. |
| `FLOORPATTERN` | `FLOORPAT`, `SURFACEPATTERN` | Shows the surface pattern of floor materials in plan: select slabs (or All on the current level); Remove deletes the patterns. The patterns follow slab, wall and material changes. |
| `HATCHTYPE` | `HPTYPE`, `PATTERNTYPE` | Sets hatches to Model patterns (real size, scale with the model) or Drafting patterns (fixed size on paper at the annotation scale). |
| `HYPERLINK` | `LINK`, `URL`, `-HYPERLINK` | Attaches a URL (web page or file) to objects; exported PDFs make them clickable. Empty removes the link. *(app)* |
| `INSULATION` | `BATT`, `INSUL`, `BATTINSULATION` | Draws the batt insulation symbol along a line at a given width (associative: stretch the line to extend it). |
| `JUSTIFYTEXT` | `TEXTALIGN` | Changes the justification of text without moving it. |
| `KEYNOTE` | `KN` | Keynotes: define keys, assign them to elements with a keynote tag, and place a keynote legend table. |
| `LEADER` | `LE`, `LEAD`, `QLEADER` | Creates a leader line with annotation text. |
| `MARKS` | `RENUMBER`, `NUMBEROPENINGS` | Renumbers door and window marks per level in reading order (D01…, W01…), or sets a mark. |
| `MASKINGREGION` | `MASKREGION` | View-specific masking region on the current level: hides the model and drafting beneath it. |
| `MATERIALTAG` | `MATTAG`, `TAGMATERIAL` | Tags the material under a picked point (the layer of a compound wall, a slab's finish, or the element material); the tag follows material changes. |
| `MATHATCH` | `MATERIALHATCH`, `HATCHMATERIAL` | Binds hatches to a material: they show its cut or surface pattern (and optionally its colour) and follow later pattern changes. |
| `MATPATTERN` | `MATERIALPATTERN`, `FILLPATTERNS` | Sets the cut or surface fill pattern of a material; walls and bound hatches update everywhere. |
| `MATPATTERNDIALOG` | `MATERIALPATTERNSDIALOG`, `FILLPATTERNSDIALOG` | Material Fill Patterns dialog: cut and surface pattern of every material; bound hatches and floor patterns update. *(app)* |
| `MLEADER` | `MLD` | Creates a multileader (arrowhead, landing, text). |
| `MLEADERALIGN` | `MLA` | Aligns the landings (text) of leaders with a reference leader, vertically or horizontally. |
| `MLEADERCOLLECT` | `MLC` | Collects several leaders into one: the first leader's arrow with all texts stacked (Vertical) or in a row (Horizontal) at a new landing. |
| `MLEADERSTYLE` | `MLS` | Creates, edits, lists and sets multileader styles (text height, annotative, layer, arrowhead, landing, text frame). |
| `MTEXT` | `MT`, `T` | Creates paragraph (multiline) text inside a width. |
| `MTEXTCOLUMNS` | `TEXTCOLUMNS` | Sets columns on multiline text: Static (count, balanced), Dynamic (fixed column height) or No columns. |
| `NORTHARROW` | `NORTH` | Places a north arrow symbol (defaults to project north). |
| `OBJECTSCALE` | `-OBJECTSCALE`, `AISCALEADD` | Adds or deletes annotation scales of annotative objects (shown only at their scales when ANNOALLVISIBLE is 0). |
| `QDIM` |  | Quickly dimensions selected objects: Continuous, Staggered, Baseline, Ordinate, Radius, Diameter, datumPoint. |
| `REPEATDETAIL` | `REPEATINGDETAIL`, `RDETAIL` | Repeating detail: a component arrayed along a path (brick courses, blocking); editing the path or spacing regenerates it. |
| `REVCLOUDLIST` | `REVISIONCLOUDS` | Lists revision clouds by revision, selects the clouds of one revision, and adds missing revisions to the revision table. |
| `REVSTAMP` | `REVTRIANGLE`, `REVTAG`, `REVISION` | Revision stamps: a numbered revision triangle, or a new row in the revision table; advances the drawing revision (REVNUMBER). |
| `SCALEBAR` |  | Places a graphic scale bar (segments, segment length, labels in m or drawing units). |
| `SCALELISTEDIT` | `SCALELIST` | Edits the list of annotation scales (Add/Delete/Reset/List). |
| `SCALETEXT` |  | Changes the height of text objects (new height or scale factor) keeping their insertion points. |
| `SCHEDULECELLS` | `SCHEDULEHIGHLIGHT`, `CONDITIONALFORMAT` | Conditional formatting of schedules: highlight the Row or only the Cell of a field when "field op value" holds (shown in placed schedules); Clear. |
| `SECTIONSYMBOL` | `SECMARK`, `SECTIONHEAD` | Draws a 2D section symbol: cut line with section heads (number / sheet attributes) looking to the picked side. |
| `SPELL` | `SPELLCHECK` | Checks the spelling of text, leaders, tables, dimension text and attributes (Change / Ignore / Add to the drawing dictionary). |
| `SPELLDIALOG` | `SPELLING`, `CHECKSPELLING` | Spelling dialog: lists misspelled words in text, leaders, tables and attributes with suggestions (Change / Ignore / Add). *(app)* |
| `SPOTCOORD` | `SPOTCOORDINATE`, `COORDLABEL` | Labels the coordinates (N/E) of a point with a leader that updates when it is moved. |
| `SPOTELEV` | `SPOTELEVATION`, `SPOTLEVEL` | Places live spot elevations (slab tops, roofs, toposurface) with a leader. |
| `SPOTSLOPE` | `SLOPELABEL` | Places live spot slopes (arrow pointing downhill with % and 1:n) on sloped slabs, ramps, roofs and toposurfaces. |
| `TABLEEDIT` | `TABEDIT`, `TABLEDIT` | Edits a table: cell text or =formula (SUM, AVERAGE…), insert/delete rows and columns, column widths. |
| `TABLEEXPORT` | `TABLEEXP` | Exports a table to a CSV file. |
| `TABLELINK` | `DATALINK`, `TABLEFROMCSV` | Inserts a table linked to a CSV or Excel (.xlsx) file (update with DATALINKUPDATE when the file changes). |
| `TABLESTYLE` | `TS` | Table styles: New / Edit title, header and data cells (height, alignment, colour, fill), Current, Apply to tables, List, Delete. |
| `TAG` | `TAGBYCATEGORY`, `ELEMENTTAG` | Tags a door, window, room or element with a live label (mark, type, name, area, keynote…). |
| `TAGALL` | `TAGALLNOTTAGGED` | Tags every untagged door, window and/or room on the current level. |
| `TAGLABEL` | `EDITLABEL`, `TAGFORMAT` | Tag labels linked to element parameters: Label template with {Parameter} fields, single Field, Annotative paper height, List. |
| `TEXT` | `DT`, `DTEXT` | Creates single-line text objects. |
| `TEXTEDIT` | `ED`, `DDEDIT` | Edits text, leader, dimension text, table cells or attribute values. |
| `TEXTEDITINPLACE` | `MTEDIT`, `INPLACETEXT`, `TEXTFORMAT` | In-place text editor on the canvas: bold, italic, underline, font, height and colour (also opened by double-clicking text); exported to PDF and DXF MTEXT. *(app)* |
| `TEXTFRAME` | `TFRAME`, `TEXTBORDER` | Draws or removes a frame around text. |
| `TEXTLIST` | `BULLETS`, `NUMBERING`, `MTEXTLIST` | Adds bullets, numbers or letters to the paragraphs of multiline text (or removes them). |
| `TEXTMASK` | `BACKGROUNDMASK`, `TMASK` | Hides objects behind text with a background mask (offset factor, background or a colour). |
| `TEXTREADABLE` | `TEXTFLIP` | Turns upside-down text (rotated between 90° and 270°) by 180° so it reads left-to-right, keeping its position. |
| `TEXTSTYLE` | `STYLE`, `ST`, `-STYLE` | Creates or modifies a text style and makes it current. |
| `TEXTSTYLEDIALOG` | `TEXTSTYLEMANAGER`, `STYLEDIALOG` | Text Style manager: font, height, width factor and oblique angle with a live preview; renaming a style updates its text. *(app)* |
| `TEXTUNMASK` | `TUNMASK` | Removes background masks from text. |
| `TOLERANCE` | `TOL`, `GDT` | Creates a GD&T feature control frame: characteristic symbol, tolerance value, datums. |
| `TXT2MTXT` | `TEXTTOMTEXT` | Combines single-line texts into one multiline text (top to bottom). |
| `UPDATEFIELD` | `UPDFIELD` | Updates fields (including date fields) in the selected text. |

### Blocks

| Command | Aliases | Description |
| --- | --- | --- |
| `ATTDEF` | `ATT`, `-ATTDEF` | Defines an attribute (modes Invisible/Constant/Verify/Preset/Lock, tag, prompt, default) to include in a block. |
| `ATTEDIT` | `ATE`, `-ATTEDIT`, `EATTEDIT` | Changes attribute values of a block reference. |
| `ATTEXT` | `-ATTEXT`, `ATTEXTRACT` | Extracts block reference attributes to a CSV file (or the command line). |
| `ATTSYNC` |  | Updates block references with the current attribute definitions of their block. |
| `BASE` |  | Sets the drawing's insertion base point (INSBASE), used when it is inserted as a block. |
| `BATTMAN` | `-BATTMAN` | Edits the attribute definitions of a block (prompt, default, tag, modes, order, delete) and syncs references. |
| `BCLOSE` |  | Closes the block editor, saving or discarding the changes. |
| `BCOUNT` | `BLOCKCOUNT` | Counts block references (including nested ones) in the drawing or a selection. |
| `BEDIT` | `BE`, `BLOCKEDITOR` | Opens a block definition in the block editor (only its objects are shown; new objects join the block). BCLOSE saves. |
| `BFLIP` | `FLIP`, `BLOCKFLIP` | Flips block references about their insertion point (dynamic flip parameter, state kept in the reference). |
| `BLOCK` | `B`, `-BLOCK`, `BMAKE` | Creates a block definition from selected objects. |
| `BLOCKBASE` | `BBASE`, `BASEPOINT` | Changes a block definition's base point; references stay where they are. |
| `BLOCKLIBRARY` | `BLIB`, `CONTENTBROWSER` | Browses a folder of drawings as a block library: List, Search, Insert (files and the blocks inside them). |
| `BLOCKPALETTE` | `BLOCKSPANEL`, `CONTENTLIBRARY` | Block library panel: library folders with thumbnails, search, favourites and recents; drag blocks onto the drawing. *(app)* |
| `BLOCKREPLACE` | `BREPLACE` | Replaces all references of one block with another (keeps attributes with matching tags). |
| `BPARAMETER` | `BPARAM`, `DYNPARAM` | Adds dynamic parameters to a block: Stretch (a length that stretches the objects in a frame) or Array (a count repeating objects); List, Delete. |
| `BSAVE` |  | Saves the block editor content into the block definition. |
| `BTABLE` | `BLOCKTABLE`, `BLOOKUP`, `LOOKUPTABLE` | Block properties table: named sets of dynamic parameter values (Add/Delete/List) applied to references by name (Apply). |
| `BVSTATE` | `BVISIBILITY`, `VISIBILITYSTATE` | Dynamic block visibility states: New, Set (on references), Hide/Show objects in a state, List, Delete, Rename. |
| `COPYMONITOR` | `COPYMON`, `COORDINATIONREVIEW` | Copy/monitor levels and grids from a linked model: Copy, Check (coordination review), Update, Release. |
| `DATAEXTRACTION` | `DX`, `EATTEXT` | Extracts block counts or attributes into a table in the drawing (or a CSV file). |
| `DYNPROP` | `BDYNSET`, `DYNVALUE` | Sets dynamic parameter values of block references (stretch lengths, array counts). |
| `GROUP` | `G`, `-GROUP` | Creates and manages named groups (Create/Add/Remove/Explode/REName/List); picking a member selects the group (PICKSTYLE). |
| `IMAGEADJUST` | `IAD`, `-IMAGEADJUST` | Adjusts the brightness, contrast and fade (0–100) of images; Reset restores the defaults. |
| `IMAGEADJUSTDIALOG` | `IMAGEADJUSTDLG`, `IADDIALOG` | Image Adjust dialog: brightness, contrast and fade of the selected raster images with a preview (exact on screen and in PDF plots). *(app)* |
| `IMAGEATTACH` | `IAT`, `IMAGE` | Places a raster image reference (path, insertion point, width, rotation). |
| `IMAGECLIP` | `ICL`, `CLIPIMAGE` | Clips an image to a rectangular or polygonal boundary: ON/OFF, Delete, New boundary, Invert. |
| `IMAGEFRAME` |  | Image clip frames: 0 hidden, 1 shown and plotted, 2 shown but not plotted. |
| `INSERT` | `I`, `-INSERT`, `DDINSERT` | Inserts a block reference (scale, rotation, attributes). |
| `LIBRARYINSTALL` | `BUNDLEDLIBRARY`, `INSTALLLIBRARY` | Installs the free bundled block library (furniture, sanitary, kitchen, vehicles, people, trees, annotation symbols) into a folder and makes it the block library. |
| `REFCLOSE` |  | Ends in-place reference editing: Save writes the changes to the block definition, Discard restores it. |
| `REFEDIT` | `-REFEDIT` | Edits a block reference in place; REFSET adds or removes objects, REFCLOSE saves or discards. |
| `REFSET` |  | Adds drawing objects to, or removes objects from, the in-place reference working set. |
| `RESETBLOCK` | `BRESET` | Resets block references to their block definition (dynamic values and visibility state). |
| `RVTLINK` | `LINKMODEL`, `LINKIFC`, `MANAGELINKS`, `MODELLINK` | Linked BIM models (.archi/IFC): list, Attach (origin-to-origin, shared coordinates or a point), Reload, Unload, Detach, Position, Notify. |
| `UNGROUP` | `UNG` | Dissolves the groups of the selected objects. |
| `WBLOCK` | `W`, `-WBLOCK` | Writes a block, selected objects or the whole drawing to a new .archi file. |
| `XATTACH` | `ATTACH`, `XA` | Attaches a drawing (.archi/.dxf) as an external reference and places it. |
| `XBIND` | `-XBIND` | Binds external references into the drawing as ordinary blocks (Bind: X$0$name, Insert: merged names). |
| `XCLIP` | `XC`, `CLIPBLOCK`, `BCLIP` | Clips block references and xrefs to a rectangular or polygonal boundary (New/ON/OFF/Delete/Polyline). |
| `XREF` | `XR`, `-XREF`, `EXTERNALREFERENCES`, `ERHIGHLIGHT` | External references: list, Attach/Overlay a drawing (.archi/.dxf), Reload, Unload, Detach, Bind, Path, Notify (changed files). |

### Layers

| Command | Aliases | Description |
| --- | --- | --- |
| `LAYDESC` | `LAYERDESCRIPTION`, `LAYERDESC` | Sets or lists layer descriptions. |
| `LAYERFILTER` | `LFILTER` | Filters the Layers panel (A-*, ~*TEXT*, #on #used); Save/Delete/List named filters kept in the drawing. *(app)* |
| `LAYERNOTIFY` | `LAYEREVAL` | Notifies when unreconciled new layers appear (On/Off) or lists them. |
| `LAYRECONCILE` | `RECONCILELAYERS` | Marks unreconciled layers as reconciled (all, or the named ones). |

### Settings

| Command | Aliases | Description |
| --- | --- | --- |
| `3DOSNAP` | `-3DOSNAP`, `3DOSMODE` | Sets 3D object snap modes on solids: ZVertex, ZMidpoint, ZCenter (face), ZKnot, ZPerpendicular, ZNearest, ALL, NONE. |
| `AUDIT` |  | Checks the drawing for errors (duplicate IDs, dangling openings, missing layers/blocks) and fixes them. |
| `AXISLOCK` | `LOCKAXIS` | Locks point input to the UCS X or Y axis, an angle, or turns the lock Off (arrow keys while drawing). |
| `CMDLINEOPTIONS` | `CLISETTINGS`, `COMMANDLINEOPTIONS`, `CLIFLOAT` | Command line appearance: text Size, history Lines shown, background Opacity; Float it over the canvas or Dock it at the bottom. *(app)* |
| `COLOR` | `COL`, `COLOUR` | Sets the color for new objects (CECOLOR). |
| `CRASHREPORTS` | `CRASHREPORT`, `CRASHLOG` | Opt-in crash reports: On, Off, Status, Show the saved reports (reviewed and sent only by you), Clear. *(app)* |
| `CUI` | `CUSTOMIZE`, `RIBBONCUSTOMIZE`, `-CUI` | Customizes the ribbon: Dialog, Add a panel of commands to a tab, Remove, Hide/Show a built-in panel, List, Export/Import a customisation file, Reset. *(app)* |
| `CURSORSIZE` |  | Sets the crosshair size as a percentage of the view (1–100). *(app)* |
| `DBLCLKEDIT` |  | Turns double-click editing of objects on or off; with an object, runs its double-click editor. |
| `DSETTINGS` | `DS`, `SE`, `DDRMODES` | Opens the drafting settings (snap, grid, polar, object snap). |
| `DUCS` | `UCSDETECT`, `DYNUCS` | Turns the dynamic UCS on or off: points picked over a 3D solid land on the face under the cursor. |
| `EXPORTSETTINGS` | `SETTINGSOUT` | Exports all preferences (theme, shortcuts, toolbar, workspaces, snippets…) to a .plist file for another Mac. *(app)* |
| `GFILTERS` | `GRAPHICFILTERS`, `DRAFTFILTERS` | Rule-based graphic overrides for drafting objects: Add/Remove/Enable/Disable/List (field layer/type/color/linetype/lineweight/property). |
| `GRAPHICSTYLES` | `STYLESMANAGER`, `GSTYLES` | Graphic styles manager: line styles and their layers, lineweights by view scale, pen sets and graphic override filters in one dialog. *(app)* |
| `GRIDDISPLAY` | `DGRID`, `F7` | Shows/hides the drawing grid or sets its spacing. |
| `IMPORTSETTINGS` | `SETTINGSIN` | Imports preferences exported by EXPORTSETTINGS (restart to apply everything). *(app)* |
| `ISODRAFT` |  | Isometric drafting: Orthographic (off), isoLeft, isoTop, isoRight — ortho and grid snap follow the isometric axes. |
| `ISOPLANE` |  | Sets the current isometric plane: Left, Top, Right or Toggle to the next. |
| `LANGUAGE` | `UILANGUAGE`, `LIMBA`, `SPRACHE`, `LANGUE`, `IDIOMA`, `LINGUA` | Interface language of the ribbon: Auto (macOS), English, Română, Deutsch, Français, Español, Italiano. Commands stay English. *(app)* |
| `LAYCUR` |  | Changes the layer of selected objects to the current layer. |
| `LAYDEL` |  | Deletes a layer and all objects on it. |
| `LAYER` | `LA`, `-LAYER`, `-LA` | Manages layers: make, set, new, rename, on/off, freeze/thaw, lock/unlock, color, linetype, lineweight, delete. |
| `LAYERP` | `LAYP` | Undoes the last change to layer settings (on/off, freeze, lock, color, current layer…) without undoing drawing edits. |
| `LAYERSTATE` | `LAS`, `-LAYERSTATE`, `LMAN` | Saves, restores, deletes, imports and exports named layer states (on/off, freeze, lock, plot, color, linetype, lineweight). |
| `LAYFILTER` | `-LAYFILTER` | Named layer filters: New property filter (name=A-* on=yes color=1 used=no…), Group filter, Invert, Delete, List, Select, Current. |
| `LAYFRZ` |  | Freezes the layer of each selected object. |
| `LAYISO` |  | Isolates the layers of selected objects (turns the other layers off or locks them). |
| `LAYLCK` | `LAYLOCK` | Locks the layer of each selected object. |
| `LAYMCUR` |  | Makes the layer of a selected object current. |
| `LAYMRG` | `-LAYMRG`, `LAYMERGE` | Merges layers into a target layer (objects move, the source layers are deleted). |
| `LAYOFF` |  | Turns off the layer of each selected object. |
| `LAYON` |  | Turns on all layers. |
| `LAYTHW` |  | Thaws all layers. |
| `LAYTRANS` | `-LAYTRANS` | Layer translator: maps layers to standard layers (mappings FROM=TO with wildcards, or a mapping file; standards from a drawing). |
| `LAYULK` | `LAYUNLOCK` | Unlocks the layer of a selected object. |
| `LAYUNISO` |  | Restores the layers hidden or locked by LAYISO. |
| `LAYWALK` |  | Walks through layers showing only the chosen ones (name, pattern, Next/Previous, Filter), then restores them. |
| `LIMITS` |  | Sets the drawing limits (LIMMIN/LIMMAX). |
| `LINESTYLES` | `LSTYLES`, `-LINESTYLES` | Named line styles (weight, colour, pattern): New/Edit/Delete/List, Apply to objects, set a Layer's line style. |
| `LINETYPE` | `LT`, `-LINETYPE`, `LTYPE` | Lists, loads, creates and sets the current linetype. |
| `LTSCALE` | `LTS` | Sets the global linetype scale factor. |
| `LWDISPLAYSCALE` | `LWSCALE` | Screen display scale of lineweights (0.1–5, default 1); plotted widths are never changed. *(app)* |
| `LWEIGHT` | `LW`, `LINEWEIGHT` | Sets the current lineweight and lineweight display. |
| `LWTABLE` | `LWSCALETABLE` | Lineweight table by view scale: lineweights are multiplied by the factor of the current annotation scale (Set/Clear/List). |
| `OPTIONS` | `OP`, `PREFERENCES`, `SETTINGS`, `CONFIG` | Opens Settings: units, grid and snaps, autosave, colors, shortcuts, toolbar, agents. *(app)* |
| `ORTHO` |  | Constrains cursor movement to horizontal/vertical (F8). |
| `OSNAP` | `OS`, `-OSNAP`, `DDOSNAP` | Sets running object snap modes (END,MID,CEN,NOD,QUA,INT,EXT,INS,PER,TAN,NEA,PAR,APP,GCEN, ON/OFF). |
| `PENSETS` | `PENSET`, `PENTABLE` | Pen sets mapping pen numbers (colour indexes) to plotted weights and colours: New/Pen/Current/Display/Delete/List. |
| `PROJECTBASEPOINT` | `PBP`, `SHAREDCOORDINATES` | Project base point: its location, shared coordinates (easting/northing) and elevation; List or Reset. |
| `PURGE` | `PU`, `-PURGE` | Removes unused blocks, layers, linetypes, text styles and dimension styles. |
| `RENAME` | `REN`, `-RENAME` | Renames blocks, layers, linetypes, text styles, dimension styles, levels, views and wall types. |
| `RP` | `REFPLANE`, `REFERENCEPLANE` | Draws a named reference plane (work plane) or lists, renames, deletes one or makes it the current UCS. |
| `SAVETIME` | `AUTOSAVE` | Sets the autosave interval in minutes (0 turns autosave off). *(app)* |
| `SETVAR` | `SET` | Lists or changes system variables. |
| `SNAP` | `SN` | Turns grid snap on/off or sets the snap spacing (F9). |
| `SURVEYPOINT` | `SURVEY` | Places the survey point: a location and its shared coordinates (the base point's shared coordinates follow). |
| `THEME` | `COLORTHEME`, `APPEARANCE` | Switches the interface theme [Dark/Light]. *(app)* |
| `TRUENORTH` | `NORTHROTATION`, `ROTATETRUENORTH` | Sets true north relative to project north (angle counter-clockwise from up, or Align to a picked direction). |
| `UCS` |  | Sets the user coordinate system: World, Origin, Z rotation, 3point, Object, Previous, Named save/restore. |
| `UCSICON` |  | Controls the UCS icon: ON, OFF, Noorigin (lower-left corner) or ORigin (at the UCS origin when visible). |
| `UCSMAN` | `UC`, `DDUCS` | Named UCS manager: lists the saved user coordinate systems and restores, saves, renames or deletes them (World and Previous too). |
| `UNITS` | `UN`, `-UNITS` | Sets drawing units (mm, cm, m, in, ft) and optionally scales the drawing. |
| `VPLAYER` | `VPFREEZE` | Freezes/thaws layers in individual sheet viewports: Freeze, Thaw, Reset, List (layout and viewport numbers or All). |

### Inquiry

| Command | Aliases | Description |
| --- | --- | --- |
| `ANGLEBETWEEN` | `ANGBETWEEN`, `LINEANGLE` | Angle between two lines (or vertex + two points). |
| `AREA` | `AA` | Calculates area and perimeter of points or objects (with Add/Subtract). |
| `CAL` | `QUICKCALC`, `QC` | Evaluates an arithmetic expression (+ - * / ^, sqrt, sin, cos, pi…). |
| `COUNT` |  | Counts objects by type, block and element type (selection or whole drawing). |
| `DIST` | `DI` | Measures the distance and angle between two points. |
| `DISTTOOBJECT` | `DISTOBJ`, `DISTTOENTITY` | Shortest distance from a point to an object. |
| `ID` |  | Displays the coordinates of a location. |
| `INSPECT` | `OBJECTINFO`, `LISTPANEL` | Opens the Inspector panel: every stored value of the selected objects, with ID and GUID. *(app)* |
| `LIST` | `LI`, `LS` | Lists the properties of selected objects. |
| `MASSPROP` |  | Reports area, perimeter, centroid, bounding box and volume of objects. |
| `MEASURE3D` | `3DMEASURE`, `DIST3D` | Measures in the 3D view: click two points on the model for distance and ΔX/ΔY/ΔZ. *(app)* |
| `MEASUREGEOM` | `MEA` | Measures distance, radius, angle, area or volume. |
| `NOTIFICATIONS` | `WARNINGS`, `NOTIFYCENTER` | Notifications centre: model warnings (overlaps, unhosted openings, family errors, missing blocks) — click one to zoom to it. *(app)* |
| `POINTINSIDE` | `INSIDECHECK`, `PTINSIDE` | Tells whether a point is inside, outside or on a closed contour (polyline, circle, ellipse, hatch, room, slab). |
| `SELECTIONINFO` | `SELINFO`, `SELECTIONPANEL` | Selection info panel: count and types of the selected objects, layers, total length/area, keep-only/remove filters. *(app)* |
| `STATUS` |  | Displays drawing statistics, modes and extents. |
| `TIME` | `EDITTIME`, `DRAWINGTIME` | Shows the drawing's creation and last-update dates, total editing time (idle gaps over 5 minutes excluded) and the user elapsed timer; ON/OFF/Reset control the timer. |
| `TLEN` | `TOTALLENGTH`, `TOTLEN` | Total length of the selected lines, arcs, circles, polylines, splines and ellipses (and wall lengths). |

### Architecture

| Command | Aliases | Description |
| --- | --- | --- |
| `ADAPTIVE` | `ADAPTIVECOMPONENT`, `ADAPTIVEPOINTS` | Adaptive components driven by placement points: Place a Strut, Panel, Frame or a family using P1x…P1z, P2x… values (points typed x,y,z or picked point objects the component follows); Move a point to flex it. |
| `AREAPLAN` | `AREABOUNDARY`, `GROSSAREA` | Creates area plan boundaries (Gross, Rentable or custom schemes) and reports totals per scheme. |
| `AREASCHEME` | `AREASCHEMES`, `GIA`, `NIA`, `GEA`, `DIN277` | Area schemes (GEA, GIA, NIA, DIN 277 BGF/NRF, Gross, Rentable): places associative area boundaries that follow the walls, lists schemes and reports totals. |
| `ASSEMBLY` | `ASSEMBLIES`, `CREATEASSEMBLY`, `AGGREGATE` | Assemblies (element aggregation): Create from selected elements, Add, Remove, Disassemble, Views (isolated plan and 3D views), List. |
| `AUTONAMEROOMS` | `ROOMNAMING`, `AUTOTAGROOMS`, `NAMEROOMS` | Names and numbers rooms of the current level from their fixtures (toilet, bath, bed, kitchen…), shape, windows and doors; Unnamed only or All; lists the suggestions and asks before applying (one undo step). |
| `BEAM` |  | Draws structural beams between points, or between picked columns (Columns: top of beam at the column tops). |
| `BIMUPDATE` | `REGENASSOC`, `UPDATEASSOCIATIVE` | Regenerates associative content: area boundaries, automatic dimensions, associative sweeps and family instances. |
| `BUILDING` | `MASS`, `QUICKBUILDING` | Quick massing: a rectangle becomes walls, floor slabs and a roof on one or more storeys; Mass turns 3D solids (conceptual masses) into mass floors or walls/floors/roofs by face. |
| `CEILING` | `CEIL` | Creates a ceiling from points, a closed object or the walls around a point. |
| `COLORFILL` | `COLORSCHEME`, `ROOMCOLORS`, `AREACOLORS` | Colours rooms/areas by a parameter (name, department, area range, level, any property) and places a colour legend. |
| `COLUMN` | `COLUMNS` | Places structural columns (rectangular or round); Grids places one at every grid intersection, hosted so it follows the grids. |
| `COMPONENT` | `FURNITURE`, `COMP`, `FURN` | Places parametric furniture, fixtures, casework, cars and plants from the library (or a custom box); size flexes the family. |
| `COPYTOLEVEL` | `PASTEALIGNED`, `COPYLEVELS`, `CTL` | Copies selected building elements to other levels, aligned in plan (hosted doors and windows follow their walls). |
| `CORNERWINDOW` | `CORNERWIN`, `WRAPWINDOW` | Corner window wrapping the corner of two walls: widths along each wall from the corner, height and sill; the walls are cut through the corner and the glazing meets at a slim post. |
| `CURTAINSYSTEM` | `CURTAINBYFACE`, `CWBYFACE` | Curtain system by face: curtain walls on every vertical face of mass solids (grid spacing and mullion size). |
| `CURTAINWALL` | `CW`, `CURTAIN` | Draws glazed curtain walls with mullion grids. |
| `CWGRID` | `CURTAINGRID` | Edits a curtain wall grid: add/remove grid lines, panels (glass, solid, spandrel, louvre, empty, door, double door), mullion types, uniform spacing. |
| `DOOR` | `DOORS` | Places doors in walls (default 900×2100). |
| `DORMER` | `DORMERS`, `ROOFDORMER` | Builds a dormer on a sloped roof: front and cheek walls, a gable or shed dormer roof, and the opening in the main roof. |
| `ELEVATOR` | `LIFT`, `ELEVATORSHAFT` | Places an elevator: car, shaft walls up to a top level and a shaft opening through the floors. |
| `ESCALATOR` | `ESCALATORS`, `MOVINGSTAIR` | Places an escalator from its bottom comb in a travel direction up to the level above (30°/35°, step width 600/800/1000), checks EN 115 rise/inclination/speed rules and cuts the upper floor; Check re-validates existing escalators. |
| `FAMILY` | `FAMILYEDIT`, `FAMILIES`, `FAM` | Family editor: new family, parameters and formulas, forms (box, cylinder, extrusion, sweep, revolve, void, nested, arrays), types, place instances, set instance values, flex, door/window builder, assign to openings. |
| `FAMILYPANEL` | `FAMPANEL`, `FAMILYWINDOW` | Family Editor panel: families list, parameters and formulas, forms, types table, reference planes, profiles, live 3D preview and flex; Apply is one undo step. *(app)* |
| `FLOORFINISH` | `FINISHFLOOR`, `TILEFLOOR` | Places a floor finish layer in rooms (material, thickness, tile pattern in plan). |
| `GENDESIGN` | `GENERATIVEDESIGN`, `OPTIMIZELAYOUT`, `LAYOUTOPT` | Generative design: optimises floor layouts for a room programme and gross area with a genetic algorithm (daylight, proportions, adjacencies, orientation, compactness); lists the Pareto-optimal designs and builds the chosen one after confirmation. |
| `GRID` | `GRIDLINE`, `GR` | Places structural grid lines (straight, Arc through 3 points or Multi-segment), auto-labelled 1,2,3 (vertical) and A,B,C (horizontal). |
| `GRIDSYSTEM` | `GRIDGEN`, `RECTGRID`, `GRIDARRAY` | Creates a rectangular grid system from spacing lists (e.g. 3*6000 4500): numbered grids along X, lettered along Y. |
| `INPLACE` | `INPLACEMODEL`, `GENERICMODEL`, `MODELINPLACE` | In-place generic model: turns solids modelled in context into a schedulable component (Create), or back into solids to edit (Edit). |
| `LEVEL` | `LEVELS`, `LV` | Lists, creates, sets, renames and deletes levels; sets elevation and height. |
| `MODELGROUP` | `BIMGROUP`, `FURNITUREGROUP`, `GROUPBIM` | Model groups: create a named group of elements, place instances, update all instances from an edited one, list, or ungroup. |
| `NICHE` | `RECESS` | Cuts a recess of a given depth into one face of a wall. |
| `OPENING` | `WALLOPENING` | Cuts empty openings in walls. |
| `OPENINGFLIP` | `FLIPDOOR`, `FLIPWINDOW`, `DOORFLIP`, `FLIPOPENING` | Flips doors and windows: Hand (hinge side), Facing (swing / exterior side) or Both. |
| `OPENINGPARTS` | `GLAZINGBARS`, `WINDOWPARTS`, `DOORPARTS` | Sets window mullions/transoms and door fanlights/thresholds on selected openings. |
| `OPENINGTRIM` | `CASING`, `ARCHITRAVE`, `LINTEL`, `SILLBOARD` | Sets door/window casings (architraves), an interior window board and a lintel with bearings on selected openings. |
| `OPENINGTYPE` | `DOORTYPE`, `WINDOWTYPE`, `TYPECATALOG` | Door/window type catalog: list, new, set type parameters and sub-parts (mullions, transoms, threshold), formulas, apply to openings, delete, import CSV. |
| `PARTS` | `CREATEPARTS`, `DIVIDEPARTS` | Divides compound walls into parts (one per layer, cut by the host's openings), Merge restores the wall, Material overrides a part, Show Parts/Original. |
| `PHASE` | `PHASES`, `PHASING` | Manages construction phases: list, new, current phase, filter, created/demolished phase of objects. |
| `PLANGEN` | `PLANFROMBRIEF`, `GENERATEPLAN`, `SPACEPLAN` | Generates floor plan options from a room programme ("Living 25, Kitchen 12, Bedroom 14 x2, Bath 6, Hall 8" in m²) inside a W × D footprint: lists scored options, builds the chosen one (walls, rooms, doors, windows) after confirmation, one undo step. |
| `PROFILE` | `PROFILES`, `PROFILEFAMILY` | Profile families for sweeps, handrails, gutters and mullions: list, create from a closed polyline (flexes with Width/Height), or delete. |
| `PROPERTIES` | `PR`, `PROPS`, `GETPROP` | Shows the properties of the selected object(s). |
| `RADIALGRID` | `GRIDRADIAL`, `POLARGRID` | Creates a radial grid system: centre, start angle, angular spacings (e.g. 6*15), inner radius and radial spacings; numbered radial grids and lettered arc grids. |
| `RAILING` | `RAIL` | Draws a railing along a path, or on both sides of a Stair's flights (sloped, following the stair). |
| `RAILINGTYPE` | `RAILTYPE`, `BALUSTERS`, `HANDRAIL` | Sets the railing type of selected railings: preset (Balusters, Glass, Cable, Bars, Wooden, Handrail) or handrail profile, baluster spacing and extensions. |
| `RAILTYPEDEF` | `RAILINGTYPES`, `RAILTYPEBUILDER` | Named railing types (height, handrail profile and size, infill, balusters, posts, extensions): New / Edit (railings of the type follow), Assign, List, Delete. |
| `RAMP` |  | Creates a sloped ramp (straight or along a path with turns), with landings between flights; warns above 1:12. |
| `ROOF` | `RF` | Creates a flat, shed, gable or hip roof from a footprint. |
| `ROOFEDGE` | `FASCIA`, `GUTTER`, `SOFFIT`, `ROOFEDGES` | Adds fascia boards, gutters (profile) and soffits along the eaves of roofs. |
| `ROOFEXTRUSION` | `ROOFBYEXTRUSION`, `EXTRUDEDROOF`, `ROOFEXTRUDE` | Roof by extrusion: pick an open polyline drawn as the roof profile (x = across, y = height), then the start, direction and length of the extrusion and the eave height. |
| `ROOFJOIN` | `JOINROOF`, `UNJOINROOF`, `ROOFJOINS` | Joins a roof to another: the picked edge is extended until the roof meets the other roof and the part below it is cut away (Unjoin restores it). |
| `ROOFSHAPE` | `ROOFFORM`, `MANSARD`, `GAMBREL`, `DOMEROOF`, `BARRELROOF` | Changes roofs into Mansard or Gambrel (two pitches with a break) forms, a Dome or a Barrel vault, or back to Plain. |
| `ROOFSHAPEPOINTS` | `SHAPEEDIT`, `DRAINAGEPOINTS`, `ROOFFALLS`, `SUBELEMENTS` | Shape editing of flat roofs: Add points with a height (drainage falls, ridges) or raise the corners, List, Reset; the roof top becomes a triangulated surface. |
| `ROOM` | `SPACE`, `RM` | Places rooms bounded by walls (pick inside) or by points; reports area. |
| `ROOMBOUNDING` | `ROOMBOUND`, `RBOUND` | Sets whether walls, curtain walls and columns bound rooms (used by ROOM, ROOMUPDATE and SLAB Walls). |
| `ROOMFINISH` | `ROOMFINISHES`, `FINISHSCHEDULE` | Sets room floor/base/wall/ceiling finishes and places the room finish schedule. |
| `ROOMSEPARATOR` | `ROOMSEP`, `RSL` | Draws room separation lines (virtual room boundaries used by ROOM, SLAB Walls, ROOMUPDATE). |
| `ROOMUPDATE` | `UPDATEROOMS`, `RU` | Recomputes the boundaries and areas of rooms placed by picking, after walls or separation lines changed. |
| `SCANTOBIM` | `PCFITWALLS`, `PLANEFIT`, `SCANFIT` | Detects planes in the point cloud (RANSAC) and creates walls from vertical planes and floor slabs from horizontal planes. |
| `SCATTER` | `SCATTERPLANTS`, `VEGETATION`, `GRASSSCATTER` | Scatters Grass, Flowers, Shrubs or Trees over closed boundaries with Poisson-disk spacing at a density per m² (reproducible seed); shown in the viewport and renders. *(app)* |
| `SCHEDULE` | `SCH` | Creates a schedule table (walls, doors, windows, rooms, slabs…) or prints it; Define/Edit/Export/Import/Place manage stored schedules (fields, filters, sorting, grouping, totals, round-trip editing, CSV/XLSX, sheets). |
| `SCHEDULEDEF` | `SCHEDULES`, `SCHEDDEF`, `NEWSCHEDULE` | Defines schedules: New (category), Fields (incl. calculated Cost=Area*350 and percentage Share%Area), Filter, Sort, Group, Totals, Itemize, Highlight, Key (key schedules), Embed, Show, List, Delete. |
| `SCHEDULEEDIT` | `EDITSCHEDULE`, `SCHEDEDIT` | Edits a schedule cell (row number from SCHEDULEDEF Show, field, value); the change goes to the element. |
| `SCHEDULEEXPORT` | `SCHEDULEOUT`, `EXPORTSCHEDULE` | Exports a schedule to .csv or .xlsx (with an ElementID column so edits can be read back by SCHEDULEIMPORT). |
| `SCHEDULEIMPORT` | `SCHEDULEIN`, `IMPORTSCHEDULE` | Reads an edited schedule (.csv or .xlsx exported by SCHEDULEEXPORT) and applies changed values to the elements. |
| `SCHEDULEPLACE` | `PLACESCHEDULE`, `SCHEDULESHEET` | Places a schedule as an associative table on a sheet (or in model space), split into columns of at most n rows. |
| `SCRIPTCOMPONENT` | `SCRIPTFAMILY`, `SCRIPTEDOBJECT`, `SCRIPTOBJ`, `GDLCOMPONENT` | GDL-like scripted BIM objects: Place a component from an OpenSCAD script (file, or a script solid) whose Customizer parameters become instance parameters; Set a parameter (range-checked) to flex it; List its parameters. |
| `SETPROP` | `SP`, `SETPROPERTY` | Sets any property of objects: SETPROP #12 height 2800. |
| `SHAFT` | `SHAFTOPENING`, `VERTICALSHAFT` | Creates a shaft that cuts every floor and roof between a base and a top level (associative: move it and the holes follow). |
| `SKETCHTOWALLS` | `IMAGETOWALLS`, `TRACEWALLS`, `PHOTOTOMODEL` | Converts a scanned or photographed plan image (PNG/BMP/PGM) into walls: dark strokes within a thickness range become wall centre lines at a given scale; asks for confirmation before creating them (one undo step). |
| `SKYLIGHT` | `ROOFWINDOW`, `ROOFLIGHT` | Places a skylight / roof window in a roof: framed glazing in the roof plane that cuts the roof. |
| `SLAB` | `FLOOR`, `SB` | Creates a floor slab from points, a closed object or the walls around a point. |
| `SLABEDGE` | `SLABEDGES`, `CURB`, `UPSTAND`, `BALCONYEDGE` | Slab edges: an Upstand (curb, balcony upstand) or Fascia profile along a picked slab edge or All edges; Clear removes them. |
| `SLABOPENING` | `FLOOROPENING`, `ROOFOPENING`, `VERTICALOPENING` | Cuts a vertical opening in one floor or roof (sketched outline; associative with its host). |
| `SLABSLOPE` | `SLOPEARROW`, `SLOPE` | Slopes a slab by a slope arrow (low point, high point, rise) or angle; Flat resets. |
| `SLABTYPE` | `FLOORTYPE`, `ROOFTYPE`, `FLOORTYPES` | Layered floor/roof types: list, create (plies top-down), assign to slabs and roofs (thickness follows the build-up), or delete. |
| `SPLITWALL` | `WALLSPLIT`, `SPLITELEMENT` | Splits a wall at a picked point (repeatable) or by Levels into one wall per storey; hosted openings follow their piece. |
| `STACKEDWALL` | `STACKWALL`, `WALLSTACK` | Makes walls stacked walls: segments of wall types bottom-up ("Type:height; Type:*"), regenerated when the base wall changes; Off removes the stack. |
| `STAIR` | `STAIRS` | Creates straight, L, U or spiral stairs between levels (width, rise or top level, risers, tread, landings). |
| `STAIRCHECK` | `CHECKSTAIRS`, `STAIRRULES` | Checks stairs against riser, going, 2R+G, width, flight-length and landing rules. |
| `STAIRSKETCH` | `STAIRBYSKETCH`, `SKETCHSTAIR` | Stair by sketch: select riser lines (bottom to top by the walking line), give the total rise; the riser/going rules are checked (max riser, min going, 2R+G). |
| `STAIRTYPE` | `STAIRTYPES` | Stair types (max riser, min going, width, landing, material, railing type): New / Edit (every stair of the type follows), Assign to stairs, List, Delete. |
| `STOREFRONT` | `SHOPFRONT`, `GLAZEDPARTITION`, `PARTITIONGLASS` | Storefront curtain walls (bays, transom, capped mullions, entrance door) or glazed Partitions (slim mullions, full-height door). |
| `STORY` | `STOREY`, `STORYSETTINGS`, `STOREYSETTINGS` | Storey settings: Height (moves the storeys above), Insert above / below, Delete, Computation height (walls that bound rooms), Elevation display (project / survey / relative), List. |
| `WALL` | `WA` | Draws a chain of joined walls (thickness, height, justification, type, arcs). |
| `WALLATTACH` | `ATTACHWALL`, `WALLDETACH` | Attaches the top of walls to a roof or slab soffit, or the base to a slab top; Detach removes the attachment. |
| `WALLBYLINES` | `WALLFROMLINES`, `WBL` | Converts selected lines, arcs, polylines, splines and ellipses into walls (curves become chains of arc walls). |
| `WALLFLIP` | `FLIPWALL`, `WALLREVERSE` | Flips walls: swaps the interior and exterior faces (layer order) keeping the wall, its openings and door swings in place. |
| `WALLJOIN` | `WJ`, `WALLCLEANUP` | Joins wall ends that nearly meet (extends/trims them to their intersection). |
| `WALLJOINEDIT` | `EDITWALLJOINS`, `JOINTYPE`, `WALLJOINTYPE` | Edits a wall join: pick near a wall end, then Miter, Butt (this wall stops at the other), Square off, or Disallow the join. |
| `WALLPOLYGON` | `POLYWALL`, `WALLPOLY`, `WALLLOOP` | Draws a closed loop of joined walls: a regular polygon (centre, sides, radius), points, or a picked closed polyline. |
| `WALLRECT` | `WALLRECTANGLE`, `RECTWALL`, `WALLBOX` | Draws four joined walls around a rectangle (two corners; Justify sets whether the rectangle is the inside, centre or outside face). |
| `WALLSWEEP` | `SWEEPWALL`, `CORNICE`, `SKIRTING` | Adds cornices, skirting boards or string courses along wall faces, Reveals (grooves cut into the faces), or removes them. |
| `WALLTOP` | `WALLCONSTRAINT`, `TOPCONSTRAINT`, `WT` | Sets the top constraint of walls (a level with offset, the next level, or an unconnected height) and their shape: elevation Profile or Gable, Slant, Taper, Reset. |
| `WALLWRAP` | `LAYERWRAP`, `WRAPINSERTS` | Wraps the finish layers of compound walls into door/window openings (all walls or selected walls) and around free wall Ends. |
| `WATER` | `WATERSURFACE`, `POND`, `POOLWATER` | Water surface with animated waves (viewport and renders) inside a closed polyline or picked points, at a surface elevation and depth. *(app)* |
| `WINDOW` | `WIN` | Places windows in walls (default 1200×1200, sill 900). |
| `ZONE` | `ZONES`, `ROOMZONE` | Zones: Assign rooms to a named fire/HVAC/department/security zone, Remove, List zone areas, or draw zone Outlines (rooms merged across the walls). |

### Structure

| Command | Aliases | Description |
| --- | --- | --- |
| `ANALYTICALMODEL` | `STRUCTMODEL`, `ANALYTICAL`, `ANALYTICALOUT` | Builds the structural analytical model (nodes, members, wall/slab panels, supports, loads) from columns, beams, walls and slabs and writes it as JSON, OpenSees Tcl, SAF (.xlsx) or an IFC4 structural analysis view (.ifc). |
| `BEAMSYSTEM` | `BEAMSYS`, `JOISTS` | Fills a boundary with parallel beams at a spacing (direction, size or profile, top elevation). |
| `BRACE` | `BRACING`, `DIAGONALBRACE` | Places a diagonal brace between two plan points at a bottom and a top elevation (profile, default CHS). |
| `FOUNDATION` | `FOOTING`, `FNDN` | Creates strip footings under walls, isolated footings under columns, or pads from points. |
| `FRAMEANALYSIS` | `FRAMESOLVE`, `STRUCTANALYSIS` | Linear static analysis of the column/beam frame (self weight + slab loads lumped to columns): displacements and support reactions. |
| `REBAR` | `REINFORCEMENT`, `RB`, `REBARSET` | Reinforcement in a concrete beam (Bottom/Top bars, Links), column (Vertical bars, Links) or slab (X/Y mesh): cover, bar diameter, count or spacing, BS 8666 shape codes; List prints the bar schedule. |
| `STEELCONNECTION` | `CONNECTION`, `BASEPLATE`, `ENDPLATE`, `STEELCONN` | Steel connections sized from the member section: Base plate with anchor bolts or Cap plate on a column, End plate with bolts on a beam end; they follow the member. |
| `STEELPROFILE` | `STRUCTPROFILE`, `SECTIONPROFILE` | Applies structural profiles (IPE, HEA, HEB, UPN, I/H/C/L/T, RHS/SHS/CHS, rectangular, round) to beams and columns, or lists them. |
| `STRUCTCOLUMN` | `STRUCTURALCOLUMN`, `SCOLUMN`, `STEELCOLUMN` | Places structural columns with a profile (HEA/IPE/RHS/CHS… or RECT / ROUND concrete), from the level to the next level (or a height), at points or at every grid intersection. |
| `STRUCTLOAD` | `LOADADD`, `STRUCTURALLOAD` | Adds a structural load on layer S-LOADS for the analytical model: Point (kN at a node or on a beam), Line (kN/m along beams) or Area (kN/m² over an outline); vertical downward by default, optional horizontal components and load case. |
| `STRUCTSUPPORT` | `SUPPORTADD`, `BOUNDARYCONDITION` | Adds a support (boundary condition) for the analytical model at a node: Fixed, Pinned, Roller or a custom ux uy uz rx ry rz code (e.g. 111000). |
| `STRUCTURAL` | `STRUCTURALUSAGE`, `LOADBEARING` | Structural usage of walls, slabs, columns and beams: Bearing, Shear, Combined or Non-bearing (drives the analytical model and schedules). |
| `TRUSS` | `TRUSSES` | Places a Pratt, Howe, Warren or Fink truss between two bearing points (height, member width, bearing elevation). |

### Site

| Command | Aliases | Description |
| --- | --- | --- |
| `BUILDINGPAD` | `SITEPAD` | Levels a toposurface inside a boundary to a pad elevation (cut and fill). |
| `CONTOURS` | `CONTOUR` | Sets the contour interval and major-line spacing of toposurfaces (0 = hide contours). |
| `DEMIMPORT` | `ASCIIGRID`, `GRIDTERRAIN`, `ELEVATIONIMPORT`, `ASCIMPORT` | Creates a toposurface from an ESRI ASCII elevation grid (.asc, metres), subsampled to a point budget. |
| `GRADEDREGION` | `GRADE`, `GRADING`, `CUTFILL` | Graded region: copies a toposurface, levels a pad to an elevation with daylighting side slopes, and reports cut and fill volumes (the existing surface is kept on a hidden layer). |
| `PARKINGLOT` | `PARKINGROW`, `CARPARK` | Lays out a row (or double row with aisle) of parking bays at 90°, 60° or 45° with paving. |
| `PROPERTYLINE` | `PROPLINE`, `BOUNDARYLINE` | Draws property lines by points or bearings and distances; labels bearings, distances and the enclosed area. |
| `RETAININGWALL` | `RETWALL` | Draws a cantilever retaining wall (battered stem on a footing) along points; retained side on the right of travel. |
| `SANDBOX` | `SMOOVE`, `STAMP`, `DRAPE`, `TERRAINGRID`, `SANDBOXTOOLS` | Sandbox terrain tools: Grid (terrain from scratch), Smoove (raise/lower with falloff), Stamp (flat pad with side slopes), Drape (project curves onto the terrain), ToBIM (toposurface → BIM topography element). |
| `SITEPATH` | `FOOTPATH`, `WALKWAY` | Draws a path of a given width along points as a site sub-region (draped on the toposurface). |
| `SUBREGION` | `SITEREGION`, `LAWN` | Creates a site sub-region (lawn, gravel, paving) from points or a closed object, draped on the toposurface. |
| `TOPO` | `TOPOSURFACE`, `TERRAIN` | Creates a toposurface from points (with elevations), contour polylines (picked, or every object on contour Layers of an imported DXF), an XYZ/CSV file or typed x,y,z values. |

### 3D

| Command | Aliases | Description |
| --- | --- | --- |
| `3DALIGN` | `ALIGN3D`, `3DAL` | Aligns solids in 3D by up to three source and destination points (translation, then direction, then plane); optional scaling. |
| `3DARRAY` | `ARRAY3D`, `3A` | Creates rectangular (rows × columns × levels) or polar 3D arrays of objects. |
| `CHAMFEREDGE` | `CHAMFER3D`, `CHE` | Bevels the edges of boxes and extruded solids (all, vertical, top or bottom edges). |
| `COMPONENTTOBIM` | `GROUPTOBIM`, `TOBIM`, `CONVERTTOBIM` | Converts component / group instances or solids into schedulable BIM component elements (category and name). |
| `CONVTOMESH` | `TOMESH`, `SOLIDTOMESH` | Converts parametric solids (box, cylinder, extrusion, revolve…) into editable triangle meshes. |
| `CONVTOSOLID` | `TOSOLID`, `MESHTOSOLID` | Converts closed meshes into solids (cleaned and oriented); open meshes are refused (MESHREPAIR can close them). |
| `CSGTREE` | `COMB`, `REGION3D`, `CSGCOMB` | BRL-CAD style combination: 'u #1 - #2 + #3 u #4' (u union, - subtract, + intersect); the result regenerates when a member changes. List / Edit existing trees. |
| `CUSTOMIZERPANEL` | `PARAMPANEL`, `SCADPANEL` | Customizer panel: sliders, check boxes and choices for the parameters of the selected scripted object (OpenSCAD customizer comments), regenerating it on change. *(app)* |
| `DATUM` | `DATUMPLANE`, `DATUMAXIS`, `DATUMPOINT`, `REFGEOMETRY`, `WORKPLANEREF` | Reference geometry that follows its source: datum Plane (through a line, offset from a solid Face, or at a Level), Axis (along a line, through a circle centre or a cylinder) or Point (centre, start, end or midpoint). |
| `EDGESURF` | `EDGESURFACE`, `COONS` | Coons patch mesh bounded by four edge curves that touch end to end (SURFTAB1 × SURFTAB2). |
| `FILLETEDGE` | `FILLET3D`, `FE` | Rounds the edges of boxes and extruded solids (all, vertical, top or bottom edges). |
| `FOLLOWME` | `FOLLOW` | SketchUp-style follow me: sweeps a profile along a path keeping its position relative to the path start (x = offset left of the path, y = height); associative. |
| `GFUSE` | `GENERALFUSE`, `FRAGMENT` | General fuse: cuts overlapping solids into non-overlapping pieces (overlaps become their own solids). |
| `GIZMO3D` | `GIZMO`, `3DGIZMO` | Shows a move (X/Y/Z arrows), rotate (ring) or uniform scale gizmo on the selection in the 3D view; drag it to transform (one undo step). *(app)* |
| `HOLE` | `HOLEFEATURE`, `DRILL` | Hole features at sketch points or circles: diameter, depth or Through, Simple / Counterbore / Countersink, optional thread designation; follow their sketch. |
| `HULL` | `CONVEXHULL`, `HULL3D` | Convex hull solid of the selected solids (and points/curves at their elevation), like OpenSCAD hull(). |
| `IMPRINT` | `IMPRINTEDGES` | Imprints curves (lines, polylines, arcs, circles, 3D polylines) onto a planar face of a solid: the face is split along them, the solid stays closed. |
| `INTERFERE` | `INF`, `CLASH` | Finds overlapping volumes between two sets of solids and can create them as new solids. |
| `INTERSECT` | `INTERSECTSOLIDS` | Keeps only the common volume of the selected solids. |
| `INTERSECTFACES` | `INTERSECTWITHMODEL`, `INTERSECTEDGES` | SketchUp intersect faces: draws 3D edges (polylines) where the selected solids cut each other, or cut the rest of the Model. |
| `LINEAREXTRUDE` | `TWISTEXTRUDE`, `LEXTRUDE` | OpenSCAD-style linear extrude of closed profiles: height, twist angle and top scale (slices follow the twist). |
| `LOFT` |  | Creates a solid through closed cross-sections at given heights (in selection order). |
| `MAKECOMPONENT` | `COMPONENTMAKE`, `SKCOMPONENT`, `MAKECOMP` | SketchUp-style component: the selected objects become a named definition and are replaced by an instance; every instance updates when the definition is edited (BEDIT/REFEDIT). |
| `MAKEGROUP` | `SKGROUP`, `GROUP3D`, `GROUPSOLIDS` | SketchUp-style group: the selected objects become one unique (unnamed) object that moves and copies as a whole. |
| `MAKEUNIQUE` | `UNIQUECOMPONENT` | Gives a component or group instance its own copy of the definition so it can be edited without changing the other instances. |
| `MESH` | `MESHPRIMITIVE`, `MESHBOX` | Faceted mesh primitives with divisions (MESHDIVISIONS): Box, Cylinder, Cone, Sphere, Torus, Wedge, Pyramid. |
| `MESHDECIMATE` | `DECIMATE`, `MESHREDUCE`, `SIMPLIFYMESH` | Reduces the triangle count of meshes/solids to a percentage (vertex clustering). |
| `MESHEXTRUDE` | `EXTRUDEFACE`, `FACEEXTRUDE`, `MESHFACEEXTRUDE` | Extrudes faces of a solid or mesh (the faces facing Top/Bottom/Front/Back/Left/Right under a picked point, or All facing that way) by a distance along their normal; the result stays closed. |
| `MESHREPAIR` | `REPAIRMESH`, `FIXMESH`, `MESHCLEAN` | Repairs meshes/solids: welds vertices, removes degenerate and duplicate faces, fixes orientation, fills holes. |
| `MESHSECTION` | `CROSSSECTIONS`, `SLICESECTIONS`, `SECTIONCURVES` | Cross-sections of solids and meshes: section curves at one elevation or every interval between two elevations (for contours, ribs, waffle models). |
| `MESHSMOOTH` | `SMOOTHMESH`, `SUBDIVIDE`, `MESHREFINE` | Smooths solids and meshes by Loop subdivision (1–4 levels). |
| `MINKOWSKI` | `MINKOWSKISUM` | Minkowski sum of two solids (e.g. a box and a sphere for rounded edges); exact for convex solids. |
| `MIRROR3D` | `3DMIRROR` | Mirrors solids about the XY, YZ or ZX plane through a point, or a vertical plane through two points. |
| `MIRRORFEATURE` | `FEATUREMIRROR`, `MIRRORED` | Mirrors a feature (or the whole body) about a vertical plane through two points or the XY plane at a height; stays parametric. |
| `MOVEZ` | `ZMOVE`, `MOVEUP` | Moves objects up or down: element base/top offsets and door/window sills change, solids move (one undo step). *(app)* |
| `OFFSETFACE` | `OFFSETEDGES`, `FACEOFFSET`, `INSETFACE` | SketchUp-style Offset: imprints a copy of a planar face's edges offset into the face (then SUBOBJECT Extrude pushes or pulls the inner face). |
| `OFFSETSOLID` | `SOLIDOFFSET`, `OFFSETBODY` | Offsets solids: every face moves outwards (or inwards, negative) by the distance. |
| `OUTLINER` | `OUTLINE`, `HIERARCHY` | Outliner: lists the hierarchy of groups, components and model groups; Select instances by name (wildcards), Rename an instance, or Convert it to a BIM element. |
| `OUTLINERPANEL` | `OUTLINERWINDOW`, `SHOWOUTLINER` | Outliner window: the tree of groups, components, blocks and model groups; click selects, double-click zooms, filter by name. *(app)* |
| `PAD` | `BOSS`, `PADFEATURE` | PartDesign pad: extrudes a sketch profile (optionally tapered) and adds it to a solid, or creates a new body; regenerates when the sketch changes. |
| `PAINT` | `PAINTBUCKET`, `APPLYMATERIAL` | Paint bucket: applies a material to objects and building elements by clicking them; Sample picks up an object's material; List shows the materials. |
| `PATTERNFEATURE` | `LINEARPATTERN`, `POLARPATTERN`, `FEATUREPATTERN` | Repeats a feature (or the whole body) in a Linear (columns × rows) or Polar pattern; instances follow the feature's sketch. |
| `PIPE` | `TUBE` | Creates a round pipe (optionally hollow) along a path. |
| `PLANESURF` | `PLANARSURFACE`, `PSURF` | Planar surface from a closed boundary (Object, with inner loops as holes) or from two corners of a rectangle. |
| `POCKET` | `POCKETFEATURE`, `CUTEXTRUDE` | PartDesign pocket: cuts a sketch profile into a solid by a depth (downwards from the sketch) or Through all; regenerates when the sketch changes. |
| `POLYHEDRON` | `POLYHEDRA` | Solid from points (x,y,z) and faces (point numbers from 1, e.g. 1,2,3,4) like OpenSCAD polyhedron(). |
| `POLYSOLID` | `PSOLID` | Draws a wall-like solid along points or converts a line/polyline/arc (Object); Height, Width, Justify. |
| `PRESSPULL` | `PP`, `PUSHPULL` | Extrudes the area around a picked point (with islands as holes), a closed object, or changes an extrusion's height. |
| `PRESSPULLFACE` | `PPFACE`, `PUSHPULLFACE`, `FACEPULL` | Pushes or pulls a planar face (top, bottom or side) of any 3D solid along its normal. |
| `PRISM` | `REGULARPRISM`, `HOLLOWPRISM` | Regular prism (N sides) or tube (inner radius > 0): centre, circumradius, height. |
| `PROJECTGEOMETRY` | `PROJECTEDGES`, `EXTERNALGEOMETRY`, `FLATOUTLINE` | Projects the outline of solids onto the sketch plane as closed polylines that follow the solids when they change (use them as sketch profiles). |
| `PYRAMID` | `PYR` | Creates a pyramid or frustum with N sides: base centre, base radius, height (Top radius for a frustum). |
| `REVSURF` | `REVOLVEDSURFACE` | Revolved mesh surface: rotates a path curve about an axis line (start angle, included angle; SURFTAB1 segments). |
| `ROTATE3D` | `3DROTATE` | Rotates solids about an axis parallel to X, Y or Z through a point. |
| `RULESURF` | `RULEDSURFACE` | Ruled mesh surface between two curves (SURFTAB1 rulings). |
| `SCAD` | `OPENSCAD`, `CSGSCRIPT` | Evaluates an OpenSCAD-language script (cube, sphere, cylinder, polyhedron, extrudes, transforms, union/difference/intersection/hull/minkowski, modules, loops) into a solid. |
| `SCADFILE` | `SCADIN`, `IMPORTSCAD` | Imports an OpenSCAD .scad file (with include / use of neighbouring files) as a solid. |
| `SCADOBJECT` | `SCRIPTOBJECT`, `CUSTOMIZER`, `GDLOBJECT` | Scripted parametric objects (OpenSCAD language, GDL-like): New from a script or File, list Params (Customizer ranges and choices), Set a parameter to regenerate. |
| `SCALE3D` | `SCALENU`, `SCALEXYZ` | Non-uniform scale of solids about a base point: separate X, Y and Z factors (negative factors mirror), or Handles: drag a bounding-box handle (corner, edge midpoint, Top/Bottom) about the opposite side or the Center, optionally Uniform. |
| `SECTIONOBJECT` | `SECTIONPLANEOBJ`, `SPOBJECT`, `SECTIONPLANES` | Section plane objects: Add a named vertical plane (its plan trace can be moved), make it Live (clips the 3D view with caps), Flip, Generate/update its 2D section block, Slice solids into closed halves, List, Off, Delete. |
| `SECTIONSOLIDS` | `GENERATESECTION`, `SECTIONBLOCK`, `SOLIDSECTION` | Cuts 3D solids with a vertical section plane (two points) and places the 2D section (cut poché + projection) as a block; Plan cuts them horizontally. |
| `SEPARATE` | `SOLIDSEPARATE`, `SOLIDCLEAN` | Separates solids into their disjoint bodies and cleans them (duplicate/degenerate faces, consistent outward orientation). |
| `SHAPEBINDER` | `BINDER`, `SUBSHAPEBINDER` | Sub-shape binder: an associative copy of another body (Solid) or of one of its faces (Face, as a surface), optionally displaced; it follows the source when that changes. |
| `SHELL` | `SOLIDSHELL`, `HOLLOW` | Hollows boxes and extrusions to a wall thickness, optionally removing the top face (SOLIDEDIT Shell). |
| `SKETCHPAD` | `PADSKETCH`, `SKETCHEXTRUDE` | Pads a sketch: its closed profile (with holes) extruded along the work-plane normal; the solid follows every change of the sketch. |
| `SLICE` | `SL3D` | Cuts solids with a vertical plane through two points or a horizontal plane (XY) at a height. |
| `SOFTEN` | `SOFTENEDGES`, `SMOOTHEDGES` | Softens and smooths the edges of solids/meshes whose faces meet at less than an angle (0 = sharp again); display only. |
| `SOLIDCHECK` | `CHECKSOLID`, `VALIDATESOLID`, `CHECKGEOMETRY` | Validates solids: open or non-manifold edges, inconsistent orientation, degenerate faces, volume and bodies. |
| `SOLIDEDIT` | `SOLED` | Edits solid faces: Extrude, Move, Offset, Taper or Copy a face (picked Top/Bottom/Side in plan); Body Offset or Separate. |
| `SOLIDHIST` | `RECORDHISTORY` | Turns recording of the CSG feature history of solids on or off (booleans on solids with a history always record). |
| `SOLIDHISTORY` | `FEATURES`, `FEATURETREE`, `SHISTORY` | Feature list of a solid: list, suppress/unsuppress, delete or move a boolean feature (the solid regenerates), or flatten the history. |
| `SPLITSOLID` | `SPLITBODY`, `BOOLEANFRAGMENTS` | Splits solids by other solids into the parts inside and outside the tools (separate bodies). |
| `SPRING` | `COILSPRING`, `HELIXSOLID` | Creates a helical coil spring solid (coil radius, wire radius, pitch, turns). |
| `SUBOBJECT` | `SUBSELECT`, `SOEDIT`, `SUBOBJ` | Sub-object editing (Ctrl-click in the viewport): pick a Face, Edge or Vertex of a solid and Move it, Extrude a face, or list Info. |
| `SUBTRACT` | `SU` | Subtracts solids from other solids. |
| `SURFANALYSIS` | `ANALYSISZEBRA`, `ANALYSISCURVATURE`, `ANALYSISDRAFT`, `SURFACEANALYSIS`, `ZEBRA` | Surface analysis: Zebra stripes, Curvature (Gaussian or mean, colour bands), Draft angle against a pull direction, Continuity between two surfaces, or Clear the analysis overlays. |
| `SURFBLEND` | `BLENDSURFACE`, `BLENDSRF` | Blend surface between the edges of two surfaces with G0 (position), G1 (tangent) or G2 (curvature) continuity and a bulge factor. |
| `SURFCV` | `NURBSSURF`, `CVSURFACE`, `SURFCVEDIT` | B-spline (NURBS) surface from a grid of control vertices: New over a rectangle, Edit moves a CV (row, column, height), Display the CV grid. |
| `SURFEXTEND` | `EXTENDSURFACE` | Extends the outer edges of surfaces tangentially by a distance. |
| `SURFNETWORK` | `NETWORKSURFACE`, `GORDON` | Network surface through curves in the U and V directions (Gordon surface: passes through every curve). |
| `SURFOFFSET` | `OFFSETSURFACE` | Offset copy of surfaces along their normals. |
| `SURFPATCH` | `PATCHSURFACE`, `FILLSURFACE` | Patch surface filling a closed boundary (one closed curve or curves meeting end to end; 3D polylines with vertexZ or elevations): planar boundaries exactly, others as a Coons patch. |
| `SURFSCULPT` | `SCULPT`, `SURFTOSOLID` | Joins surfaces that enclose a watertight volume into a solid (the surfaces are replaced). |
| `SURFTRIM` | `TRIMSURFACE` | Trims surfaces with a closed plan curve (projected vertically), keeping the part Inside or Outside. |
| `SWEEP` |  | Sweeps closed profiles along a path (profile X to the left of travel, Y up). |
| `SWEEP3D` | `HELIXSWEEP`, `SWEEPHELIX` | Sweeps a closed profile (centred on the path) along a 3D path such as a helix (or a new Helix); associative with profile and path. |
| `TABSURF` | `TABULATEDSURFACE` | Tabulated mesh surface: sweeps a path curve along a direction vector (a line) or straight up by a height. |
| `TAPEMEASURE` | `TAPE`, `GUIDE`, `PROTRACTOR` | Tape measure: Measure between two points, create a Guide parallel to an edge at a distance or through a point, or a Protractor guide at an angle. |
| `TEXT3D` | `3DTEXT`, `EXTRUDETEXT` | Creates extruded 3D text (single-line font strokes as solid bars). |
| `THICKEN` | `THICK` | Turns surfaces into solids by offsetting them along their normals (negative = other side). |
| `TORUS` | `TOR` | Creates a torus: centre, radius of the torus, radius of the tube. |
| `UNFOLD` | `MESHUNFOLD`, `FLATTENMESH`, `PAPERMODEL` | Unfolds a solid or mesh into a flat net for fabrication (cut lines solid, fold lines dashed), placed at a point. |
| `UNION` | `UNI` | Combines selected 3D solids into one. |
| `WEDGE` | `WE` | Creates a wedge solid: base rectangle by two corners (or Length), height; the top slopes down along X. |
| `WIREFRAME` | `MESHWIREFRAME`, `WIREFRAMEMOD`, `LATTICE` | Wireframe modifier: turns the edges of a solid or mesh into struts of a given thickness (Solidify: THICKEN). |

### View

| Command | Aliases | Description |
| --- | --- | --- |
| `AMBIENTOCCLUSION` | `AOCCLUSION`, `AOBAKE`, `AOSETTINGS` | Ambient occlusion baked on the model: Intensity (0 = off … 2), Radius and Samples; shaded elevations, sections, axonometrics and perspectives (and their PDF/SVG exports) darken corners and overhangs; Report prints the average occlusion. |
| `ANIMATE` | `OBJANIMATE`, `OBJECTANIMATION`, `DOORANIMATE` | Object animation saved in the drawing: Door swings, Rotate about a pivot, Move by a vector (start time, duration, there and back); Play/Stop in 3D, List, Delete, Clear, Render a frame. *(app)* |
| `AODIALOG` | `AMBIENTOCCLUSIONDIALOG`, `AOPANEL` | Ambient Occlusion dialog: intensity, radius and rays per point for the 3D viewport, renders and shaded views. *(app)* |
| `ARQUICKLOOK` | `ARVIEW`, `USDZPREVIEW`, `ARPREVIEW` | AR Quick Look: exports the model as a real-scale USDZ and Previews it or Shares it to an iPhone/iPad (AirDrop) to place it in AR. *(app)* |
| `AXONVIEW` | `AXONVIEWSAVE`, `SAVE3DVIEW`, `AXONOMETRIC` | Saves a 3D axonometric view (SW / SE / NE / NW isometric, Top, or Custom azimuth/elevation) that refits to the model after every change. |
| `BACKVIEW` | `BACK` | Sets the 3D view to back. |
| `BILLBOARD` | `CUTOUT`, `IMAGECUTOUT`, `ENTOURAGE` | Places a 2D cutout that always faces the camera in 3D and renders: Person, Tree, Shrub or an image file (PNG with transparency). *(app)* |
| `BOTTOMVIEW` | `BOTTOM` | Sets the 3D view to bottom. |
| `CALLOUT` | `DETAILCALLOUT`, `CALL` | Draws a callout (boundary, leader and numbered bubble) in plan and places the enlarged detail view it refers to. |
| `CAMERA` | `CAM`, `RESTORECAMERA` | Restores a saved 3D camera (or lists them). *(app)* |
| `CAMERAPATHEDIT` | `ANIMPATH`, `CAMPATHS` | Camera path editor: keys from the 3D view or saved cameras at times, timeline scrubbing and playback, video export. *(app)* |
| `CAMERAVIEW` | `PLACECAMERA`, `CAMERAOBJ`, `PERSPECTIVEVIEW` | Places a camera object (eye, target, heights, lens) saved as a perspective 3D view; cameras show in plan with their field of view. |
| `CLEANSCREENOFF` |  | Restores the ribbon and panels after CLEANSCREENON. *(app)* |
| `CLEANSCREENON` | `CLEANSCREEN` | Clean screen: hides the ribbon and panels (Ctrl+0 toggles). *(app)* |
| `CLIPPLANES` | `CLIPPLANE`, `CLIPPINGPLANE` | Clipping plane panel in the 3D view: horizontal or vertical cut, live offset slider, flip, remove. *(app)* |
| `DATUMS3D` | `SHOWDATUMS`, `LEVELS3D`, `GRIDS3D` | Shows or hides levels and grids (with heads) in the 3D view. |
| `DRAFTINGVIEW` | `DRAFTING`, `DRAFTVIEW`, `DETAILVIEW2D` | Drafting views (2D only, not tied to the model): new, edit in isolation, close (store), place in the drawing, list. |
| `DVIEW` | `DV`, `PLANTWIST` | Rotates (twists) the 2D plan display; model coordinates are unchanged. DVIEW TWist 30, DVIEW Off. *(app)* |
| `FILETAB` |  | Shows the file tab bar with one tab per open drawing. *(app)* |
| `FILETABCLOSE` |  | Hides the file tab bar. *(app)* |
| `FLOATPANEL` | `UNDOCKPANEL`, `PANELFLOAT` | Floats a panel (Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History) in its own window. *(app)* |
| `FLY` | `FLYMODE`, `3DFLYMODE` | Free flight in 3D: W A S D along the view direction, Q/E down/up, drag to look (no gravity or collisions). *(app)* |
| `FOG` | `ATMOSPHERE`, `HAZE`, `RENDERENVIRONMENT` | Fog / atmospheric haze in the 3D view and renders: On/Off, start and end distance, colour and falloff (saved in the drawing). *(app)* |
| `FOV` | `FIELDOFVIEW`, `LENS` | Sets the 3D camera field of view in degrees (15–120), or a Lens length in mm (35 mm equivalent). *(app)* |
| `FRONTVIEW` | `FRONT` | Sets the 3D view to front. |
| `FULLSCREEN` | `FS` | Enters or leaves full screen for this drawing window (⌃⌘F). *(app)* |
| `GRAPHICDISPLAY` | `GDO`, `DISPLAYOPTIONS` | Graphic display options of the current view: Sketchy lines (0–10), Silhouettes (line weight, 0 = off) and cast Shadows in plan; saved with the view. |
| `HISTORYPANEL` | `UNDOHISTORY`, `HISTORY` | Shows the undo history and command history panel. *(app)* |
| `INTERIORELEV` | `INTERIORELEVATION`, `IELEV`, `ROOMELEVATIONS` | Places a 4-way interior elevation marker in a room and draws its four interior elevations (A–D). |
| `ISOVIEW` | `ISO`, `SWISO` | Sets the 3D view to swiso. |
| `LAYOUT` | `LO`, `-LAYOUT`, `SHEET` | Creates, sets, renames and deletes sheets (layouts); sets paper size and title block. |
| `LAYOUTTABS` | `LAYOUTTAB`, `MODELTAB` | Shows or hides the Model / layout tabs under the drawing area. *(app)* |
| `LEFTVIEW` | `LEFT` | Sets the 3D view to left. |
| `LEGEND` | `LEGENDS`, `LEGENDVIEW`, `BUILDUPLEGEND` | Places a legend view: wall types, door/window types, floor/roof build-ups, components or materials (VIEWUPDATE refreshes it). |
| `LEVELVIEW3D` | `ISOLATELEVEL3D`, `EXPLODELEVELS` | 3D view by level: show All levels, Isolate one level, or Explode levels apart by a gap. *(app)* |
| `LIGHT` | `LIGHTS`, `POINTLIGHT`, `SPOTLIGHT`, `ARTIFICIALLIGHT` | Places point, spot, area, line or IES lights (lumens, colour temperature, beam) that light the 3D view and renders; List, On/Off. *(app)* |
| `LIGHTMIX` | `LIGHTGROUPS`, `RENDERLIGHTMIX` | Light mix of path-traced renders: weights of the Sun, Sky and Artificial light groups, changeable after rendering (saved in the drawing). *(app)* |
| `LINEWORK` | `LINEWORKOVERRIDE`, `LWO` | Overrides the line style of individual element edges in the current project view (Invisible, Hidden, Thin, Wide, Medium, Color, or Reset). |
| `LOOKAROUND` | `LOOK`, `LOOKAROUNDTOOL` | Looks around from the current eye point (drag or arrow keys turn the head; the camera does not move). *(app)* |
| `MATASSET` | `MATERIALASSETS`, `MATIDENTITY`, `MATPHYSICAL` | Material assets kept apart from the render appearance: Identity (description, manufacturer, mark, cost), Graphics (shading colour, surface pattern) and Physical/thermal (density, conductivity, specific heat); List. *(app)* |
| `MATBROWSER` | `MATLIB`, `MATERIALLIBRARY` | Material library browser with rendered thumbnails: add to the drawing or assign to the selection. *(app)* |
| `MATCHLINE` | `MATCHLINES` | Matchlines between dependent views: On / Off / List. |
| `MATEMISSIVE` | `EMISSIVE`, `SELFILLUM`, `MATEMIT` | Makes a material self-illuminated (luminance factor 0–20; 0 turns it off): screens, lamps, signs glow in 3D and renders. *(app)* |
| `MATERIALS` | `MAT`, `RMAT`, `MATEDITOR`, `MATBROWSEROPEN` | Opens the material editor panel (color, roughness, metalness, transparency, texture). *(app)* |
| `MATFROMIMAGE` | `MATPHOTO`, `PHOTOMATERIAL`, `IMAGETOMATERIAL` | Creates a seamless PBR material from a photo: de-lit albedo, normal, roughness and AO maps derived from the image, at a real-world tile size. *(app)* |
| `MATMAPPING` | `TEXTUREMAPPING`, `UVMAPPING`, `MATERIALMAPPING`, `POSITIONTEXTURE` | Texture mapping of a material: Box, Planar, Cylindrical, Spherical or UV, and texture positioning (offset, rotation, scale) on its faces; Reset. *(app)* |
| `MATMAPS` | `PBRMAPS`, `MATERIALMAPS` | PBR texture maps of a material: Normal, Roughness, Metallic, AO and Displacement images, normal strength and displacement height; List/Clear. *(app)* |
| `MVIEW` | `MV`, `VIEWPORT` | Places a viewport on the current sheet (corners in paper mm, scale 1:n, view kind, level). |
| `MVIEWPOLY` | `MVPOLY`, `POLYVIEWPORT` | Creates a polygonal sheet viewport from paper points (x,y in mm) showing the current level. *(app)* |
| `MVSETUP` |  | Aligns sheet viewports: pans one viewport so a model point lines up horizontally or vertically with a point in another. *(app)* |
| `NAVIGATOR` | `OVERVIEW`, `MINIMAP` | Navigator: overview map of the whole drawing with the visible area; drag the rectangle to pan. *(app)* |
| `NAVSWHEEL` | `STEERINGWHEEL`, `WHEEL`, `SWHEEL` | Steering wheel in 3D: Zoom, Orbit, Pan, Rewind (outer ring), Center, Walk, Up/Down, Look (inner ring). *(app)* |
| `NAVVCUBE` | `VIEWCUBE` | Shows or hides the view cube in 3D. |
| `NEISO` |  | Sets the 3D view to neiso. |
| `NWISO` |  | Sets the 3D view to nwiso. |
| `ORBITSELECTION` | `ORBITSEL`, `3DORBITSEL`, `ZOOMSELECTED3D` | Orbits around (and zooms to) the selected elements in 3D. *(app)* |
| `PAN` | `P`, `-PAN` | Moves the view by a displacement. |
| `PANORAMA` | `360`, `PANO`, `RENDER360` | Renders a 360° equirectangular panorama (PNG/JPEG) from the 3D camera position or a picked plan point. *(app)* |
| `PATHTRACE` | `PTRENDER`, `RENDERPT`, `PATHTRACER`, `RAYTRACE` | Progressive path-traced render of the 3D view (GGX materials, glass refraction, PBR maps, sun, sky, lights): Window, or File with size, samples and denoising. *(app)* |
| `PERSPECTIVE` | `PROJECTION` | 3D projection: 1 = perspective, 0 = parallel (orthographic). *(app)* |
| `PHASEANIMATION` | `PHASEVIDEO`, `4DVIDEO`, `4DANIMATION` | Construction sequence (4D) video from the phases (new elements appear bottom-up, demolished ones disappear) or from the work schedule (day by day), captioned (MP4). *(app)* |
| `PLAN` |  | Shows the plan view of the current UCS, a named UCS or the world (rotates the 2D display so the UCS X axis is horizontal). |
| `PLANORIENT` | `ORIENTATION` | Orients the plan to Project north (up) or True north (display rotation only). |
| `POSITIONCAMERA` | `POSCAM`, `EYEPOINT` | Places the camera at a plan point at eye height looking towards a second point, then looks around (SketchUp style). *(app)* |
| `PROCMATERIAL` | `PROCEDURALMATERIAL`, `PROCTEXTURE`, `MATPROCEDURAL` | Procedural seamless material (Wood, Brick, Tile, Marble, Stone, Concrete, Terrazzo) with albedo, normal and roughness maps from colours, courses, joint width and a seed. *(app)* |
| `PROJECTVIEW` | `PVIEW`, `VIEWS`, `VIEWBROWSER` | Project views: New (plan / ceiling / 3D), Open, Close, Duplicate (plain, with detailing, as dependent), Split into dependent views, Rename, Delete, List. |
| `QUICKPROPS` | `QP`, `QUICKPROPERTIES` | Quick Properties: a compact editor of the selection's key properties over the drawing. *(app)* |
| `RADIALMENU` | `MARKINGMENU`, `PIEMENU` | Right-drag marking menu with the 8 most used commands for the context (On/Off/List). *(app)* |
| `RCP` | `REFLECTEDCEILING`, `CEILINGPLAN` | Reflected ceiling plan on/off (ceilings with grids and heights, ceiling fixtures), and ceiling grid settings. |
| `REDRAW` | `REDRAWALL`, `RA` | Refreshes the screen from the display cache (fast; REGEN rebuilds the cache). *(app)* |
| `REGEN` | `RE`, `REGENALL`, `REA`, `REDRAW`, `R` | Regenerates the display. |
| `RENDER` | `RR` | Renders the 3D model. |
| `RENDERPROMPT` | `AIRENDER`, `RENDERSTYLE`, `PROMPTRENDER` | Styles the render from a description (e.g. “golden hour, soft shadows, warm, 4K”): saves it as the “Prompt” render preset and opens the render window. *(app)* |
| `RENDERQUEUE` | `BATCHRENDER`, `RENDERHISTORY` | Render queue: add the current view or saved cameras, render them in turn to PNG files; render history with thumbnails. *(app)* |
| `RENDERTOFILE` | `RENDERFILE`, `RENDEROUT`, `RENDERPASS` | Renders to an image file: any size up to 7680×4320 (tiled), a pass (Beauty, Alpha, Depth, Normal, Material ID), a style (Photographic, Sketch, Watercolour) and an optional region of the frame. *(app)* |
| `REVEALHIDDEN` | `REVEAL`, `SHOWHIDDEN` | Reveal hidden elements: On draws temporarily hidden objects in magenta, Off stops, Unhide restores objects by id (#12,#15) or All. |
| `RIGHTVIEW` | `RIGHT`, `SIDE` | Sets the 3D view to right. |
| `SAVECAMERA` | `CAMSAVE`, `NEWCAMERA` | Saves the current 3D camera by name (restored with CAMERA). *(app)* |
| `SCOPEBOX` | `SCOPEBOXES` | Scope boxes: New (two corners, rotation), Grids (assign grids — they are trimmed to the box), View (crop a project view by the box), Delete, List. |
| `SEASON` | `SEASONS` | Season of the vegetation in the 3D view and renders: Spring, Summer, Autumn or Winter colours for grass, trees and plants. *(app)* |
| `SECTION` | `SECTIONLINE`, `SECTIONMARK` | Places a section line (A–A…) in plan; section views and sheets use the current section. |
| `SECTIONBOX` | `SBOX`, `3DSECTIONBOX` | Section box in 3D: On/Off/Selection/Level/Reset; the box is saved with the drawing. *(app)* |
| `SECTIONPLANE` | `SPLANE`, `CUTPLANE`, `LIVESECTION` | Live section plane in 3D with cap faces: Horizontal at a height, Vertical through two plan points, Flip, Off. *(app)* |
| `SEISO` |  | Sets the 3D view to seiso. |
| `SHOW2D` | `2D` | Shows the 2D plan view. |
| `SHOW3D` | `3D`, `3DVIEW`, `MODEL3D` | Shows the 3D model view. |
| `SPACEMOUSE` | `3DMOUSE`, `NDOF`, `3DCONNEXION` | 3Dconnexion SpaceMouse: On/Off, Object (orbit) or Fly mode, Sensitivity, Status. Axes move the 3D camera; button 1 fits the view. *(app)* |
| `SPLIT` | `SPLITVIEW`, `VPORTS` | Shows the plan and 3D views side by side. |
| `STEREOPANORAMA` | `STEREO360`, `ODSPANORAMA`, `VRPANORAMA` | Stereo 360° panorama for VR viewers: left and right eye equirectangular images over-under (omni-directional stereo), from the 3D camera or a plan point. *(app)* |
| `SUNSTUDY` | `SUN`, `SUNPROPERTIES` | Sun study panel in the 3D view: date and time sliders with a day animation. *(app)* |
| `SUNSTUDYVIDEO` | `SUNVIDEO`, `SHADOWSTUDY` | Exports an MP4 sun-study time-lapse (shadows through the day) from the current 3D camera. *(app)* |
| `SYSWINDOWS` | `ARRANGEWINDOWS`, `TILEWINDOWS`, `WINDOWS` | Arranges the open drawing windows: Vertical (side by side), Horizontal, Cascade, Tabs or Separate windows. *(app)* |
| `TEMPHIDE` | `HH`, `HIDECATEGORY`, `HC` | Temporarily hides the selected elements, or a whole Category (wall, door, component…) on the current level; UNISOLATEOBJECTS or REVEALHIDDEN Unhide restores them. |
| `TEMPISOLATE` | `HI`, `ISOLATECATEGORY`, `IC` | Temporarily isolates element categories on the current level: every other category is hidden until UNISOLATEOBJECTS. |
| `TILEDVIEWS` | `VPTILE`, `TILEVIEWS` | Tiled model views: 2, 3 or 4 views (plan, 3D, section, elevations), each with its own zoom and pan. *(app)* |
| `TOOLPALETTES` | `TP`, `TOOLPALETTE` | Shows the tool palettes panel (grouped tools and My Tools). *(app)* |
| `TOOLPALETTESCLOSE` |  | Hides the tool palettes panel. *(app)* |
| `TOPVIEW` | `TOP`, `PLANVIEW` | Sets the 3D view to top. |
| `TWOPOINT` | `TWOPOINTPERSPECTIVE`, `2PT`, `VERTICALS` | Two-point perspective: levels the 3D camera so vertical lines stay vertical, shifting the lens to keep the framing (On/Off). *(app)* |
| `UNDERLAY` | `UNDERLAYLEVEL`, `HALFTONELEVEL` | Shows another level halftone under the current plan (None to turn off). |
| `VIEW` | `V`, `-VIEW` | Saves, restores, lists and deletes named views. |
| `VIEWCROP` | `CROPREGION`, `CROPVIEW`, `ANNOTATIONCROP` | Crop region of the current project view: Window, Polygon, On, Off, Annotation crop offset, Show / Hide the crop boundary. |
| `VIEWDRAW` | `DRAWINGVIEW`, `SECTIONVIEW`, `ELEVATIONVIEW` | Places an elevation or section of the model as a 2D drawing (with level heads and grid bubbles) in model space. |
| `VIEWGRAPHICS` | `SECTIONGRAPHICS`, `ELEVGRAPHICS`, `DEPTHCUE`, `HIDDENLINES`, `VG`, `VISGRAPHICS` | View graphics: Categories (visibility/graphics overrides per category), Filters (rule-based view filters), Detail level, and Section/elevation graphics (line weights by depth, hidden lines, depth cueing, far clip, dimensions). |
| `VIEWIMAGE` | `VIEWPORTIMAGE`, `SAVEIMG3D` | Saves the 3D view as a PNG, JPEG or TIFF at a chosen size, optionally with a transparent background. *(app)* |
| `VIEWRANGE` | `VR`, `PLANRANGE` | Plan view range relative to the level: Top, Cut plane, Bottom and View depth; elements above the top are left out and those below the bottom (down to the view depth, also from lower levels) are drawn as beyond. Off restores the default. |
| `VIEWSECTIONBOX` | `SECTIONBOXVIEW`, `CROP3D` | Section box of the current 3D view: Fit (selection, level or model), Box (two corners and heights), On, Off. |
| `VIEWTEMPLATE` | `VIEWTEMPLATES`, `VT` | View templates: list, apply to the current view, capture the current settings as a template, set a template value, apply to a placed drawing view, or delete. |
| `VIEWUPDATE` | `UPDATEVIEWS` | Regenerates all placed elevation/section drawing views from the current model. |
| `VISUALSTYLES` | `VSM`, `VISUALSTYLEMANAGER` | Visual styles manager: New/Edit a custom style from a base (edges, edge colour, face opacity, shadows, background), Delete, List, Current. *(app)* |
| `VPCLIP` |  | Clips a sheet viewport to a polygon of paper points (x,y in mm), or Deletes the clip. *(app)* |
| `VPMAX` | `VPMAXIMIZE` | Maximises a sheet viewport: edits the model through it at full window size (VPMIN returns). *(app)* |
| `VPMIN` | `VPMINIMIZE` | Returns from a maximised viewport to its sheet, keeping the new view centre (unless the viewport is locked). *(app)* |
| `VRVIEW` | `WEBXR`, `VREXPORT`, `HEADSETVIEW` | VR headset viewing: writes the model as a WebXR page (life-size, floor on the room floor, pinch/trigger steps forward) for Apple Vision Pro, Meta Quest or OpenXR browsers; Open, Reveal (AirDrop) or just Save. *(app)* |
| `VSCURRENT` | `VS`, `SHADEMODE` | Sets the visual style of the 3D view. |
| `WALK` | `3DWALK`, `WALKTHROUGH`, `3DFLY` | Starts a first-person walkthrough of the 3D model. |
| `WALKTHROUGHVIDEO` | `WALKVIDEO`, `ANIPATH`, `CAMERAPATH` | Exports an MP4 walkthrough along a smooth path through the saved cameras (in order). *(app)* |
| `WEATHER` | `RAIN`, `SNOW`, `WEATHERFX` | Weather in the 3D view and renders: Clear, Rain, Snow or Fog with an intensity, snow cover on up-facing faces and wet surfaces. *(app)* |
| `WINDOWTABS` | `DOCTABS` | Native window tabs: Merge all drawing windows into tabs, or open new drawings in Tabs / Windows. *(app)* |
| `WSCURRENT` | `WS`, `WORKSPACE` | Switches workspace (panels, views and ribbon tab), e.g. WSCURRENT 3D Modeling. *(app)* |
| `WSSAVE` |  | Saves the current window arrangement as a named workspace. *(app)* |
| `ZOOM` | `Z` | Zooms: All/Extents, Window, Previous, Center, Object, or a scale (2, 0.5x). |
| `ZOOMXP` | `ZXP`, `ZOOMPAPER`, `ZOOMSCALEXP` | ZOOM nXP: in a sheet sets the selected viewport to 1:n (1/100XP); on the plan shows the drawing at that paper scale at true size on the screen. *(app)* |

### Output

| Command | Aliases | Description |
| --- | --- | --- |
| `BATCHPUBLISH` | `PUBLISHSET`, `BATCHPLOTPDF` | Publishes chosen sheets to one PDF with bookmarks (sheet number and name) and optional sheet index. *(app)* |
| `EXPORTPDF` | `PDFEXPORT`, `PDFOUT`, `LAYEREDPDF` | Vector PDF with one PDF layer (OCG) per drawing layer, searchable text and hyperlinks: current sheet, model or all sheets, at true scale. *(app)* |
| `PAGESETUP` | `PSETUP`, `PAGESETUPMANAGER` | Page setup of the active sheet or model: paper, plot style, lineweights, plot stamp, scale. *(app)* |
| `PLOTAREA` | `PLOTWINDOW` | Model-space plot area (Extents/Display/Limits/Window) and fit (Standard scale or Exact) for PLOT, PREVIEW and PDF export. *(app)* |
| `PLOTLOG` | `PLOTHISTORY` | Shows the plot log (every plot, PDF export and publish with date, sheets and plot style) [List/Open/Clear]. *(app)* |
| `PLOTSTYLE` | `CTB`, `PLOTSTYLES`, `STYLESMANAGER` | Plot style tables (colour → pen colour, lineweight, screening): Edit, Set for the sheet/model, List. *(app)* |
| `PLOTSTYLENAME` | `NAMEDPLOTSTYLE`, `STB` | Named plot styles (STB): assign a style to a Layer or to Objects, choose the Table used by the current sheet (or model), or List styles. *(app)* |
| `PREVIEW` | `PRE`, `PRINTPREVIEW`, `PLOTPREVIEW`, `PLOTDIALOG` | Plot dialog with a live preview: prints or saves exactly what is shown. *(app)* |
| `PRINTSETUP` | `PRINTOPTIONS`, `QUICKPRINT` | Prints with printer, paper, tray (input slot), media, scaling (fit, 1:1, percent) and copies. *(app)* |
| `PSETUPIN` |  | Imports a page setup (plot style, colour mode, lineweights, stamp, paper) from another drawing into the current sheet or all sheets. *(app)* |
| `PUBLISH` | `BATCHPLOT`, `EXPORTSHEETS`, `PUBLISHPDF` | Publishes all sheets to one multi-page PDF (PUBLISH path.pdf, or Enter for a dialog). *(app)* |
| `REVCLOUDPANEL` | `SHEETCLOUDS` | Sheet revision clouds: add a cloud with a revision triangle around a viewport or an area of a sheet, list, open, delete. *(app)* |
| `SHADEPLOT` | `VPSHADEPLOT`, `VIEWPORTSHADE` | Shade plot of a 3D (axonometric / perspective) sheet viewport: As Displayed, Wireframe, Hidden or Rendered, and the saved 3D view it shows. *(app)* |
| `SHEETFIELD` | `PROJECTFIELD`, `CUSTOMFIELD` | Custom title block fields: Project fields appear on every sheet, Sheet fields override them on one sheet. *(app)* |
| `SHEETGRID` | `LAYOUTGRID`, `GUIDEGRID` | Guide grid on the current sheet (spacing in paper mm, 0 = off); viewports snap to it when moved. *(app)* |
| `SHEETIMAGE` | `LAYOUTIMAGE`, `SHEETPNG` | Exports a sheet (layout) or the Model view of the current level as a PNG, JPEG or TIFF image at a chosen resolution (dpi). *(app)* |
| `SHEETINDEX` | `SHEETLIST`, `DRAWINGLIST` | Places or refreshes the sheet list table (number, title, paper, revision) on the active sheet. *(app)* |
| `SHEETPLACEHOLDER` | `PLACEHOLDERSHEET` | Adds a placeholder sheet (listed in the sheet set and index, never plotted) or toggles the current one. *(app)* |
| `SHEETRENUMBER` | `RENUMBERSHEETS` | Numbers all sheets in order with a prefix and start number (e.g. A- 101). *(app)* |
| `SHEETREVISION` | `REVISION`, `REVTABLE`, `ADDREVISION` | Adds a revision (next code, date, description, by) to the active sheet's revision table. *(app)* |
| `SHEETSET` | `SSM`, `SHEETSETMANAGER`, `SHEETS` | Sheet set manager: numbering, order, duplicate, revisions, sheet index. *(app)* |
| `SHEETSVG` | `LAYOUTSVG`, `EXPORTSHEETSVG` | Exports the current sheet (or All sheets) as true-size vector SVG with one layer per drawing layer. *(app)* |
| `SHEETVIEWTITLES` | `VPTITLES`, `EDITABLEVIEWTITLES` | Editable view titles (number bubble, title, scale) under every viewport of the active sheet; keeps edited titles. *(app)* |
| `TITLEBLOCK` | `TBEDIT`, `TITLEBLOCKEDIT` | Edits the active sheet's title block and the project information shown on all sheets. *(app)* |
| `TITLEBLOCKDESIGN` | `TBDESIGN`, `CUSTOMTITLEBLOCK`, `TITLEBLOCKBLOCK` | Custom title blocks: Create a starter block (edit it with BEDIT: lines, logo images, {field} texts or attributes), Use a block on all or the current sheet, or go back to the Builtin one. *(app)* |
| `VPLOCK` | `VPORTLOCK`, `LOCKVIEWPORT` | Locks or unlocks sheet viewports so their scale and position cannot change. *(app)* |
| `WEBVIEWEREXPORT` | `WEBEXPORT`, `EXPORTWEB`, `WEBVIEWER` | Exports the 3D model as one standalone HTML file with a WebGL viewer (orbit, pan, zoom, views) that opens in any browser. *(app)* |

### Layout

| Command | Aliases | Description |
| --- | --- | --- |
| `VIEWTITLE` | `VIEWTITLES`, `VPTITLE` | Adds or refreshes view titles (number bubble, name, scale) under every viewport of a sheet. |

### File

| Command | Aliases | Description |
| --- | --- | --- |
| `BREPIN` | `BREPIMPORT`, `IMPORTBREP`, `OCCTIN` | Imports an OpenCASCADE BREP file (FreeCAD .brep/.brp) as mesh solids: stored triangulations are used, other faces are triangulated from their edges. |
| `BREPOUT` | `BREPEXPORT`, `EXPORTBREP`, `OCCTOUT` | Exports the 3D model as an OpenCASCADE BREP file (shells of planar faces, millimetres) for FreeCAD, Salome and other OCCT tools. |
| `CITYJSONIMPORT` | `CITYJSONIN`, `CITYMODELIMPORT`, `IMPORTCITYJSON` | Imports a CityJSON city model (buildings, terrain, roads … at their highest LoD) as mesh solids per city object with attributes. |
| `CLOSE` |  | Closes the current drawing. |
| `COBIEOUT` | `COBIEEXPORT`, `EXPORTCOBIE`, `COBIE` | Exports a COBie 2.4 spreadsheet (.xlsx): contact, facility, floors, spaces, types, components (doors, windows, equipment) and attributes. |
| `DAEOUT` | `COLLADAOUT`, `COLLADAEXPORT`, `EXPORTDAE` | Exports the 3D model as COLLADA 1.4.1 (.dae, metres, Z up, Phong materials). |
| `DGNEXPORT` | `DGNOUT`, `EXPORTDGN` | Exports the drawing's 2D objects as a MicroStation V7 .dgn file (one level per layer, master units m, resolution 0.1 mm). |
| `DRAWINGRECOVERY` | `DRM` | Shows documents recovered from autosave after a crash. *(app)* |
| `DWGCONVERTER` | `DWGSETUP`, `ODACONVERTER` | Shows or sets the DWG converter used by DWGIN/DWGOUT (path to ODAFileConverter or dwg2dxf; stored in the drawing). |
| `DWGIN` | `DWGIMPORT`, `IMPORTDWG` | Imports a DWG drawing through an installed converter (ODA File Converter or LibreDWG); explains how to get one if none is installed. |
| `DWGOUT` | `DWGEXPORT`, `SAVEASDWG` | Writes a DWG file (DXF converted by the installed ODA File Converter or LibreDWG). |
| `DXFOUTVERSION` | `DXFSAVEAS`, `DXFVERSIONOUT`, `DXF2018OUT` | Writes an ASCII DXF of a chosen version: R12, R2000, R2004, R2007, R2010, R2013 or R2018 (AC1032, UTF-8 text). |
| `DXFR12OUT` | `DXFOUTR12`, `SAVEASR12`, `DXF12` | Writes a DXF R12 (AC1009) file for older CAD/CAM software (splines, ellipses, hatches and MText are converted). |
| `E57IN` | `E57IMPORT`, `IMPORTE57` | Imports an ASTM E57 point cloud (all scans, poses applied, colour and intensity) as points. |
| `E57OUT` | `E57EXPORT`, `EXPORTE57` | Exports the drawing's points (with their z, colour and intensity) as an ASTM E57 point cloud. |
| `ETRANSMIT` | `PACKANDGO`, `TRANSMIT`, `ARCHIVEPACKAGE` | Packs the drawing with its referenced images, material textures and external references (paths rewritten) and a transmittal report into a ZIP. |
| `EXCHANGECHECK` | `GBXMLCHECK`, `COBIECHECK`, `VALIDATEEXPORT` | Checks the gbXML or COBie export (or a given file) against the schema's required elements, enumerations and references. |
| `EXPORT` | `EXP` | Exports the drawing (PDF, DXF, SVG, OBJ, STL, GLB, IFC, CSV, PNG). |
| `EXPORT3MF` | `3MFOUT`, `3MFEXPORT` | Exports the 3D model as a 3MF package (millimetres, one object per element). |
| `FILEMETADATA` | `SPOTLIGHTINFO`, `MDITEMS` | Lists the Spotlight metadata of the drawing or a file (title, authors, layers, levels, rooms, searchable text). |
| `FILEPREVIEW` | `FINDERPREVIEW`, `SPOTLIGHTINFO`, `FILEMETADATA` | Finder preview icon and Spotlight metadata of the saved drawing: Update now, Icons on/off, Versions on/off, Show the indexed metadata. *(app)* |
| `FILEVERSIONS` | `BROWSEVERSIONS`, `MACVERSIONS`, `REVERTTO` | macOS Versions of the saved file (every save keeps one): Browse window, List, Restore a version, Open a copy, Save a version now, Keep count. *(app)* |
| `GBXMLOUT` | `GBXMLEXPORT`, `EXPORTGBXML`, `ENERGYMODELOUT` | Exports the energy model as gbXML 0.37: spaces, exterior/interior walls with windows and doors, roofs, floors, constructions with U-values. |
| `GEOJSONEXPORT` | `GEOJSONOUT` | Exports 2D entities (selection or all) as GeoJSON in WGS84 or local metres. |
| `GEOJSONIMPORT` | `GEOJSONIN` | Imports GeoJSON features (WGS84 lon/lat are projected around the project location; projected metres are used as-is). |
| `HPGLOUT` | `PLTOUT`, `HPGLEXPORT`, `HPGL` | Writes the current level's plan as HP-GL/2 (.plt) for plotters and cutters, at a plot scale. |
| `IDSCHECK` | `IDSVALIDATE`, `CHECKIDS` | Checks the model's IFC export (or an IFC file) against an Information Delivery Specification (.ids): entity, attribute, property and material requirements. |
| `IFCIMPORT` | `IFCIN`, `-IFCIMPORT` | Imports an IFC (IFC2x3/IFC4) model: walls, slabs, columns, beams, doors, windows and spaces become BIM elements; other products become meshes. |
| `IFCMAP` | `IFCMAPPING`, `IFCCLASSMAP` | IFC class mapping for export: Set a component category or element type to an IFC class and predefined type (e.g. Plumbing → IfcSanitaryTerminal.WASHHANDBASIN), List, Remove, Clear. Element props IfcExportAs override the table. |
| `IFCOPTIONS` | `IFCEXPORTOPTIONS`, `IFCSETTINGS` | IFC export settings saved in the drawing: schema (IFC2X3 Coordination View 2.0, IFC4 or IFC4X3), model view definition (ReferenceView = tessellated or DesignTransferView), base quantities (Qto_*) and georeferencing (IfcMapConversion). |
| `IFCXMLOUT` | `IFCXMLEXPORT`, `EXPORTIFCXML` | Exports the building model as ifcXML (IFC4, ISO 10303-28 XML encoding); a .zip or .ifczip name writes an IfcZIP holding the ifcXML. |
| `IFCZIPOUT` | `IFCZIPEXPORT`, `EXPORTIFCZIP` | Exports the model as IfcZIP (compressed IFC4). |
| `IMPORT` | `IMP` | Imports a DXF, SVG or .archi file into the drawing. |
| `IMPORTFILE` | `FILEIMPORT`, `IMPORTANY` | Imports a file by extension: .archi, .dxf, .ifc, .svg, .obj, .stl, .3mf, .geojson, .csv/.txt/.xyz points. |
| `JOURNAL` | `AUTOSAVEJOURNAL`, `CHANGEJOURNAL` | Change journal for crash recovery: On (record every change every n seconds to the recovery folder), Off, Now (record immediately), Status. |
| `KMLOUT` | `KMZOUT`, `KMLEXPORT`, `KMZEXPORT`, `GOOGLEEARTH` | Exports KML or KMZ placed at the project location (GEOGRAPHICLOCATION / project latitude, longitude, north angle): extruded walls, slabs, roofs and rooms by level, linework by layer; KMZ also carries the 3D model (COLLADA). |
| `LASEREXPORT` | `CNCSVG`, `LASERSVG`, `MAKERCAM` | Exports outlines for laser cutters / CNC as a true-size SVG in mm: joined continuous paths, red = cut, blue = engrave (layers *ENGRAV*/*SCORE*/*ETCH* or blue objects), optional model scale and kerf compensation. |
| `LAZCONVERTER` | `LAZSETUP`, `LASZIP` | Shows or sets the LAZ decompressor used to import .laz point clouds (laszip, pdal or las2las; stored in the drawing). |
| `MESHIMPORT` | `OBJIMPORT`, `STLIMPORT`, `3MFIMPORT`, `OBJIN`, `STLIN`, `GLTFIMPORT`, `GLBIMPORT`, `PLYIMPORT`, `OFFIMPORT`, `AMFIMPORT`, `DAEIMPORT`, `COLLADAIMPORT` | Imports an OBJ, STL, 3MF, glTF/GLB, PLY, OFF, AMF or COLLADA (.dae) file as mesh solids (choose the file's units where the format has none). |
| `NEW` | `QNEW` | Creates a new drawing. |
| `NEWFROMTEMPLATE` | `NEWTEMPLATE`, `QNEW` | Starts a new drawing from a template (built-in or from the templates folder). *(app)* |
| `OPEN` |  | Opens a drawing (.archi, .dxf). |
| `OSMIMPORT` | `OPENSTREETMAP`, `IMPORTOSM`, `OSMIN` | Imports an OpenStreetMap .osm extract around the project location: building outlines (optionally extruded to their height), roads, water and areas. |
| `PLOT` | `PRINT` | Plots the current sheet or view to PDF or a printer. |
| `PLYOUT` | `PLYEXPORT`, `EXPORTPLY` | Exports the 3D model as an ASCII PLY mesh (millimetres, Z up, vertex colours from materials). |
| `POINTCLOUDIMPORT` | `PCIMPORT`, `IMPORTCLOUD`, `XYZIMPORT`, `PTSIMPORT`, `POINTCLOUD` | Imports a point cloud (XYZ, PTS or PLY ASCII/binary) as point entities with colours, decimated to a point budget and/or a voxel grid. |
| `POINTSEXPORT` | `PTEXPORT`, `EXPORTPOINTS` | Writes point entities (selection or all) to CSV: name,x,y,z,code,layer. |
| `POINTSIMPORT` | `CSVPOINTS`, `PTIMPORT`, `IMPORTPOINTS` | Imports survey points from CSV/TSV/TXT (X,Y[,Z][,name] with or without header, or P,N,E,Z,D). |
| `PRESENTOUT` | `PRESENTATION`, `SLIDESHOW`, `PRESENTEXPORT` | Writes the sheets and saved views as a self-contained HTML slide show (full screen with F, arrow keys, speaker notes from the sheet field 'notes'). |
| `QUIT` | `EXIT` | Quits the application. |
| `RECOVER` | `RECOVERFILE`, `OPENRECOVER` | Opens a damaged .archi drawing, repairing it: truncated files are closed after the last complete object, undecodable objects and settings are dropped, and the model is audited. |
| `RECOVERYFILES` | `JOURNALRECOVERY`, `RECOVERJOURNAL` | Lists the autosave copies and change journals left by a crash or forced quit, and opens one (Open n) or deletes them (Clear). |
| `RHINOIN` | `3DMIN`, `3DMIMPORT`, `IMPORT3DM`, `RHINOIMPORT` | Imports a Rhino .3dm file (versions 2–8): meshes, B-reps (render meshes or tessellated trimmed faces), extrusions, surfaces, curves, points and blocks, with layers, colours, materials and units. |
| `RHINOOUT` | `3DMOUT`, `3DMEXPORT`, `EXPORT3DM`, `RHINOEXPORT` | Exports a Rhino .3dm (version 4) file in the drawing units: the 3D model as meshes coloured by material, drafting curves as exact lines, arcs, polylines and NURBS, with layers. |
| `SAVE` | `QSAVE` | Saves the drawing. |
| `SAVEAS` | `SA` | Saves the drawing under a new name. |
| `SAVEASTEMPLATE` | `SAVETEMPLATE`, `TEMPLATESAVE` | Saves the drawing's settings, layers, styles and content as a template in the templates folder. *(app)* |
| `SAVECHECK` | `ROUNDTRIPCHECK`, `CHECKSAVE` | Verifies that saving and reopening the drawing gives an identical document (lists any section that would change). |
| `SAVECOPY` | `SAVEACOPY`, `COPYSAVE` | Saves a copy of the drawing under another name or format (.archi, .architemplate, .dxf, .ifc, …); the open drawing keeps its name and unsaved state. |
| `SCRIPT` | `SCR` | Runs a script file of command lines. |
| `SCRIPTTEXT` | `RUNSCRIPT` | Runs command lines given as text (lines separated by newlines, \n or \|). |
| `SHPIMPORT` | `SHAPEFILEIMPORT`, `IMPORTSHP`, `SHPIN` | Imports an ESRI shapefile (.shp with .dbf attributes and .prj CRS: WGS84, UTM, Web Mercator) as points/polylines; elevation attributes become contour elevations. |
| `STARTSCREEN` | `START`, `WELCOME` | Shows the start screen: templates, samples and recent drawings. *(app)* |
| `STEPIN` | `STEPIMPORT`, `STPIN`, `IMPORTSTEP` | Imports polyhedral geometry from a STEP (AP203/AP214/AP242) file as mesh solids (planar faces; curved B-rep surfaces are skipped). |
| `STEPOUT` | `STEPEXPORT`, `STPOUT`, `EXPORTSTEP` | Exports the 3D model as STEP AP214 faceted B-reps (one solid per element, millimetres, with colours). |
| `SVGIMPORT` | `SVGIN`, `-SVGIMPORT` | Imports SVG paths, lines, polylines, polygons, circles, ellipses, rectangles and text as drawing entities. |
| `SVGLAYERSOUT` | `SVGOUTLAYERS`, `SVGEXPORTLAYERS`, `LAYEREDSVG` | Exports the current level's plan as SVG with one group (Inkscape/Illustrator layer) per drawing layer. |
| `TEMPLATEIN` | `LOADTEMPLATE`, `STARTFROMTEMPLATE` | Replaces the drawing with a new untitled drawing started from a template file (undoable). |
| `TEMPLATEOUT` | `EXPORTTEMPLATE`, `WRITETEMPLATE` | Writes the drawing as a template file (.architemplate) with a name and description; everything in the drawing is kept. |
| `UPGRADEFILE` | `FILEUPGRADE`, `MIGRATEFILE` | Upgrades older .archi / .architemplate files (a file or every file in a folder) to the current format, keeping the originals as .vN.archi.bak. |
| `USDEXPORT` | `USDZEXPORT`, `USDAEXPORT`, `USDZOUT`, `USDOUT` | Exports the 3D model as USD: .usda text or .usdz package (UsdPreviewSurface materials). |
| `XLSXIN` | `XLSXIMPORT`, `IMPORTXLSX`, `EXCELIN` | Places the sheets of an .xlsx workbook as table entities. |
| `XLSXOUT` | `XLSXEXPORT`, `SCHEDULEXLSX`, `EXPORTXLSX` | Writes the schedules (walls, doors, windows, rooms, slabs, takeoff, areas by level) to an Excel .xlsx workbook. |

### Analysis

| Command | Aliases | Description |
| --- | --- | --- |
| `ACCESSIBILITY` | `A11Y`, `ACCESSCHECK`, `ADACHECK` | Accessibility check: door clear widths (A11YDOORWIDTH, default 850 mm) and Ø1500 mm wheelchair turning circles in bathrooms clear of fixtures (A11YTURNING). |
| `BOQ` | `BILLOFQUANTITIES`, `BILLQ` | Bill of quantities: takeoff items priced with unit rates (UNITPRICE rates or a JSON table), numbered by trade with subtotals, contingency (BOQCONTINGENCY %) and VAT (BOQVAT %); CSV or XLSX. |
| `CARBON` | `EMBODIEDCARBON`, `LCA`, `CO2` | Embodied carbon (A1–A3, kgCO2e) of the model's materials from takeoff volumes, densities and carbon factors (CARBON:/DENSITY: overrides); optional CSV. |
| `CFDEXPORT` | `WINDCASE`, `OPENFOAMOUT`, `WINDSTUDY` | Writes an OpenFOAM wind-study case (simpleFoam, atmospheric boundary layer inlet, snappyHexMesh around the building, pedestrian-level sampling) for the given wind speed and direction. |
| `CHECKMODEL` | `MODELCHECK`, `AUDITMODEL`, `BIMAUDIT` | Checks the model: walls without height, openings wider than or outside their host, overlapping/duplicate walls and rooms, unnamed or duplicate rooms, missing levels. |
| `CLASHDETECT` | `CLASHES`, `CLASHTEST` | Finds hard clashes between elements and 3D solids (touching and hosted/joined elements are ignored); lists, selects and zooms. |
| `CLASHMANAGE` | `CLASHMANAGER`, `CLASHGROUPS`, `CLASHSTATUS` | Manages clash results kept in the drawing: Run (detect; disappeared clashes become resolved), List, Group (Type/Level/Proximity), Status, Assign, Zoom to a clash (selects both elements), Csv export. |
| `CODECHECK` | `CHECKCODE`, `COMPLIANCE`, `RULECHECK` | Checks rooms (area, height, width, window-to-floor ratio), stairs (riser, tread, 2R+T, width, flight), ramps and doors against JSON code rules (CODERULES or a file); lists, selects and zooms. |
| `CODERULES` | `RULES` | Stores code rules in the drawing from a JSON file (Load), writes the current rules to a file (Save) or restores the defaults. |
| `COLORBLINDCHECK` | `CVDCHECK`, `COLOURBLINDCHECK`, `ACCESSIBLECOLORS` | Checks layer colours for colour-blind safety (protanopia, deuteranopia, tritanopia; CIEDE2000) against the background; Fix re-colours the conflicting layers from the Okabe–Ito palette. |
| `COSTESTIMATE` | `COST`, `ESTIMATE` | Cost estimate from the takeoff and unit rates (UNITPRICE drawing rates or a JSON table); optional CSV. |
| `DAYLIGHT` | `DAYLIGHTFACTOR`, `DF` | Average daylight factor of each room from its windows (BRE formula: T·Aw·θ·M / A(1−R²)) and the window-to-floor ratio; optional CSV. |
| `DAYLIGHTANNUAL` | `SDA`, `ASE`, `CLIMATEDAYLIGHT`, `LM83` | Climate-based daylight per room from an EPW weather file (or a clear-sky year): spatial daylight autonomy sDA300/50% and annual sunlight exposure ASE1000,250h (IES LM-83), optionally drawing the work-plane grid coloured by autonomy. |
| `DAYLIGHTRADIANCE` | `RADIANCEDAYLIGHT`, `RADIANCEEXPORT`, `SDARADIANCE` | Climate-based daylight with Radiance: Export a Radiance study (scene, materials, room sensors, sky, run.sh for the daylight-coefficient method with an EPW) or Import its results as sDA300/50% and ASE1000,250h per room (IES LM-83). |
| `EGRESS` | `TRAVELDISTANCE`, `ESCAPEROUTES`, `EGRESSCHECK` | Egress check: longest walking distance from each room to the nearest exit (exterior or exit=1 doors, stairs on upper levels) around walls and columns, against the limit (EGRESSMAX, m). Draws the routes on EGRESS-ROUTES. |
| `ENERGYBALANCE` | `HEATINGNEED`, `ENERGYNEED`, `SOLARGAINS` | Seasonal heating energy balance: losses from degree days (latitude table or HDD), solar gains per window orientation, internal gains, utilisation factor; optional CSV. |
| `FIRECOMPARTMENTS` | `FIRECHECK`, `COMPARTMENTS` | Fire compartments: room areas grouped by prop fireCompartment (else per level) against FIREMAXAREA (doubled with FIRESPRINKLERS=1), and walls between compartments below FIRERATINGREQ minutes; selects failing walls. |
| `HEATLOSS` | `HEATLOAD`, `ENERGY`, `ENERGYCALC` | Design heat loss of the envelope (U·A·ΔT of exterior walls, windows, doors, roofs, ground floor) plus ventilation, and annual heating demand; optional CSV. |
| `IFCVALIDATE` | `IFCCHECK`, `VALIDATEIFC` | Validates an IFC file (or the model's own IFC export): syntax, schema header, references, GlobalIds, attribute counts, project/units, spatial containment. |
| `ISOVIST` | `VIEWSHED`, `VISIBILITY` | Draws the isovist (area visible from a point at eye height, walls block, doors and openings are see-through) and reports its area. |
| `LEVELAREAS` | `AREABYLEVEL`, `GFA`, `FLOORAREAS` | Area schedule by level: gross floor area (slabs, a 'gross' area plan or rooms) and net room area with the net/gross ratio; optional CSV. |
| `LOADTAKEDOWN` | `TAKEDOWN`, `COLUMNLOADS` | Structural load takedown per column: tributary slab areas, dead (self weight + LOADSDL) and imposed loads by room usage, accumulated down the stacked columns, ULS 1.35G+1.5Q, SLS and axial stress; optional CSV. |
| `PARKINGCHECK` | `PARKINGCOUNT`, `PARKINGREQ` | Parking provision check: required spaces from room usage and area (PARKINGRULES, e.g. office=35;apartment=unit:1) against the parking spaces placed, including accessible spaces. |
| `RAINWATER` | `RAINCALC`, `DOWNPIPES` | Rainwater from roofs: plan area incl. overhangs, runoff coefficient, design flow Q = C·i·A, downpipes (EN 12056-3 capacities), gutter length and annual harvest; optional CSV. |
| `REVERB` | `RT60`, `REVERBERATION`, `ACOUSTICS` | Reverberation time (Sabine RT60 at 500 Hz) of each room from its volume and surface absorption; optional CSV. |
| `ROOMSCHEDULE` | `ROOMAREAS`, `AREASCHEDULE` | Room area schedule with net (minus columns) and gross (to wall centre lines) areas, perimeter and volume; optional CSV. |
| `SHADOWDIAGRAM` | `SHADOWPLAN`, `SHADOWANALYSIS`, `PLANSHADOWS` | Shadow study for a date and times at the project location: hatched ground shadows per time on A-SHADOW-hhmm layers and/or an SVG image sequence with an animated HTML page; prints the shadow areas. |
| `SOLARRADIATION` | `INSOLATION`, `IRRADIATION`, `SOLARGAIN` | Clear-sky solar irradiation (kWh/m² per day) on exterior walls, windows and roofs for a date at the project location; optional CSV. |
| `STANDARDSCHECK` | `CHECKSTANDARDS`, `DRAWINGSTANDARDS`, `CADSTANDARDS` | Checks layers (naming pattern, required layers, objects on layer 0), ByLayer properties, text heights/styles and linetypes against a JSON drawing standard (DRAWINGSTANDARDS variable or a file); lists, selects and zooms. |
| `SUNPATH` | `SUNPATHDIAGRAM`, `SUNCHART` | Draws a polar sun path diagram (altitude rings, compass, the day's path with hours, solstices/equinox) for a date at the project location. |
| `SUNPOSITION` | `SUNPOS`, `SUNCALC` | Sun azimuth/altitude, sunrise and sunset for a date, time and the project location; stores SUNAZIMUTH/SUNALTITUDE. |
| `TAKEOFF` | `QTO`, `QUANTITIES` | Quantity takeoff: wall areas/volumes (net of openings) per type and material, slabs, roofs, columns, beams, door/window counts; optional CSV. |
| `TAKEOFFPHASE` | `QTOPHASE`, `PHASEQUANTITIES`, `TAKEOFFLEVEL` | Quantity takeoff split by construction phase (new work and demolition) and level; optional CSV. |
| `UNITPRICE` | `COSTRATE`, `RATE` | Stores a unit rate in the drawing (COST:<category>[:<type>]:<measure>) used by COSTESTIMATE. |
| `UVALUE` | `UVAL`, `THERMAL`, `LAMBDA` | U-value (EN ISO 6946) of selected walls, slabs, roofs and openings from their layers; Lambda sets a material's conductivity, Set a type's U-value. |
| `WINDRESULTS` | `CFDRESULTS`, `WINDIMPORT` | Imports an OpenFOAM pedestrian-level velocity sample (raw x y z Ux Uy Uz) as wind arrows coloured by speed with Lawson comfort classes (the case's wind direction is taken from WINDDIRECTION); the Solve option runs the built-in 2D lattice Boltzmann solver instead (no external CFD needed). |

### Scripting

| Command | Aliases | Description |
| --- | --- | --- |
| `AGENTSETTINGS` | `AGENTS`, `AGENTSERVER` | Agent server settings: port, start/stop, token, auto-start. *(app)* |
| `ASK` | `NLCOMMAND`, `SAY`, `NATURAL` | Natural-language request, e.g. "draw a 4 m wall north of grid A", "add a door 900 wide in the middle of the last wall", "move the selection 2 m east": shows what was understood and asks before applying (one undo step). |
| `ASSISTANT` | `AI`, `AICHAT`, `CHAT`, `ASKAI` | AI assistant panel: Claude or a local model (Ollama) edits the drawing with commands; bulk changes ask for confirmation; everything is undoable. *(app)* |
| `CONNECTCLAUDE` | `MCPHELP`, `CLAUDE` | Explains how to connect Claude (archi-cli --mcp or the local agent server). *(app)* |
| `GRAPHPLAYER` | `PLAYER`, `RUNGRAPH`, `PLAYGRAPH` | Graph player: runs a saved node graph with its exposed Number inputs (clamped to their ranges) and bakes the result; Window opens the player panel. *(app)* |
| `LISP` | `LISPEVAL`, `EVALLISP` | Evaluates an AutoLISP expression, e.g. LISP "(command \"CIRCLE\" '(0 0) 500)"; the result is printed. |
| `LISPLOAD` | `LOADLISP`, `LSPLOAD` | Loads an AutoLISP (.lsp) file: its (defun c:NAME …) functions become commands; runs after this command, each (command …) its own undo step. |
| `NODEEDITOR` | `NODES`, `VISUALSCRIPT`, `GRAPH` | Visual node editor (number, point, line, circle, extrude, array…) with live preview; bakes geometry into the drawing. *(app)* |
| `SCRIPTCONSOLE` | `JS`, `JSCONSOLE`, `CONSOLE` | Shows or hides the JavaScript console (⌥⌘J). *(app)* |
| `SCRIPTLIBRARY` | `SCRIPTS` | Opens the script library folder (startup.js runs in every new window). *(app)* |

### Tools

| Command | Aliases | Description |
| --- | --- | --- |
| `ACTMANAGER` | `ACTLIST`, `ACTIONMANAGER` | Lists, shows, deletes, renames, exports (.scr) or imports action macros. |
| `ACTPLAY` | `ACTIONPLAY` | Plays back a recorded action macro. |
| `ACTRECORD` | `ACTIONRECORD` | Starts recording an action macro (typed commands and picks); ACTSTOP saves it in the drawing. |
| `ACTSTOP` | `ACTIONSTOP` | Stops recording and saves the action macro under a name (stored in the drawing). |
| `ALIAS` | `ALIASEDIT` | Defines command aliases and macros (Define/Delete/List/Global/Load/Save); ";" in a macro is Enter. |
| `BATCH` | `BATCHJOBS`, `SCRIPTPRO`, `RUNBATCH` | Runs a JSON batch job file over many drawings: open/import, command lines or a script, outputs in any export format, analysis reports and save (the open drawing is not changed). |
| `DELAY` |  | Pauses a script for the given number of milliseconds (up to 32767). |
| `HISTORY` | `CMDHISTORY`, `HIST` | Command history: List (last N), Recent input values, Save/Load a history file, Clear, or run a previous line (!n). |
| `MACRO` | `RUNMACRO` | Runs a menu macro: spaces or ; = Enter, \ = pause for your input, ^C^C = cancel first (e.g. ^C^CLINE \ @1000,0 ;). |
| `MACROBUTTON` | `MBUTTON`, `-CUI`, `CUIBUTTON` | Creates, edits, lists, runs and deletes custom macro buttons (saved in the drawing or in your profile). |
| `MEMORYREPORT` | `MEMUSAGE`, `MEMSTATS`, `MEMINFO` | Memory estimate of the drawing by kind, the app's memory footprint and the budget (MEMORYBUDGET MB) with advice; POINTLIMIT follows the budget. |
| `NODEPACKAGE` | `NODEPACKAGES`, `NODEPKG` | Custom node packages (.archinodes): Create one from the drawing's node graph (a snippet per group), Install a file, Insert a snippet into the graph, List, Remove. *(app)* |
| `RELZERO` | `RELATIVEZERO`, `SETRELZERO` | Sets the relative zero (the point @ input is measured from), or locks / unlocks it. |
| `RESUME` |  | Continues a script that was interrupted with Escape. |
| `SCRIPTRECORD` | `RECSCRIPT` | Records typed commands and picks as a script (Start/Stop); saved to a .scr file. |
| `SYSVARMONITOR` | `SYSMON`, `-SYSVARMONITOR` | Watch list of system variables: you are notified when a command changes one of them. |

### Help

| Command | Aliases | Description |
| --- | --- | --- |
| `ABOUT` |  | About Oanarina Archi Tool: version, license and credits. *(app)* |
| `APPSELFTEST` | `SELFTEST` | Runs the app's built-in regression checks (node graph, sheet set, presets, clipboard, ribbon). *(app)* |
| `COMMANDS` | `CMDLIST` | Lists every command with its aliases and summary. |
| `COMMANDSEARCH` | `CMDSEARCH`, `SEARCHCOMMANDS` | Opens the command search palette (⌘K). *(app)* |
| `DOCSITE` | `DOCUMENTATIONSITE`, `HELPSITE`, `MANUALHTML` | Writes the documentation (user guide, scripting, agent API, command reference) as an offline HTML site with search. |
| `EXPORTCOMMANDS` | `COMMANDREFEXPORT`, `CMDEXPORT` | Exports the command reference (every registered command: name, aliases, category, summary, where it is in the UI) as Markdown or CSV. *(app)* |
| `HELP` | `?`, `F1` | Lists commands by category, or describes one command. |
| `HELPWINDOW` | `DOCS`, `HELPBROWSER`, `MANUAL` | Opens the offline help browser (command pages, tutorials, shortcuts); F1 opens the running command's page. *(app)* |
| `KEYBOARDNAV` | `KEYCURSOR`, `KEYBOARDHELP` | Keyboard-only drawing: arrow keys move the crosshair at prompts (Shift ×10, Option ÷10; Option-arrows when idle), Return picks, Tab selects under the crosshair; sets the step. *(app)* |
| `SAMPLEHOUSE` | `SAMPLE`, `OPENSAMPLE` | Opens the bundled sample house project in a new window. *(app)* |
| `SPEAKDRAWING` | `DESCRIBEDRAWING`, `VOICEOVERSUMMARY`, `A11YSUMMARY` | Describes the drawing, the selection and the current prompt (spoken by VoiceOver, printed on the command line). *(app)* |
| `TUTORIALS` | `TUTORIAL`, `LEARN` | Opens the step-by-step tutorials and the sample project in the help browser. *(app)* |
| `WHATSNEW` | `RELEASENOTES` | Shows what is new in this version (also shown once after an update). *(app)* |

### Insert

| Command | Aliases | Description |
| --- | --- | --- |
| `ADCENTER` | `DESIGNCENTER`, `ADC` | Design Center: browses another drawing's blocks, layers, linetypes, styles and materials and adds them here. *(app)* |
| `DGNIMPORT` | `DGNIN`, `IMPORTDGN` | Imports a MicroStation V7 .dgn file (lines, line strings, shapes, curves, circles, ellipses, arcs, text; levels become layers). |
| `DROPIMPORT` | `IMPORTDROPPED`, `PASTEFILE` | Imports files as if dropped on the canvas: images and PDFs are attached, vector/3D exchange formats merged, side by side from a point. |
| `DWFIMPORT` | `DWFXIMPORT`, `IMPORTDWF` | Imports the sheets of a DWFx file (XPS paths, colours, line weights and text; one sheet after the other) as drawing objects. |
| `IMAGEIMPORT` | `IMPORTIMAGE`, `RASTERIMPORT`, `GEOIMAGE` | Inserts a PNG/JPEG/GIF/BMP/TIFF/WebP image at its pixel aspect ratio; with a world file (.pgw/.jgw/.tfw/.wld) it is georeferenced (world units WORLDUNITMM, local origin GEOORIGIN). |
| `PCPLANE` | `POINTCLOUDSNAP`, `SCANPLANE`, `PCSNAP` | Snaps to the scan point nearest a picked location and fits the plane through its neighbours: reports the point, normal, slope and fit error; a vertical plane is drawn as a line along its trace in plan. |
| `PDFATTACH` | `ATTACHPDF`, `PDFUNDERLAY` | Attaches a PDF page as an underlay (by reference, faded and locked, with object snaps on its geometry) at a drawing scale and insertion point. |
| `PDFIMPORT` | `IMPORTPDF`, `PDFIN` | Imports the vectors and text of a PDF page as drawing objects: paths with their colours and line widths, fills as solid hatches, text (ToUnicode aware), PDF layers (optional content) as layers; at a drawing scale and insertion point. |
| `PDFUNDERLAYS` | `PDFRELOAD`, `PDFDETACH`, `PDFADJUST` | Manages PDF underlays: List, Reload (re-read changed PDFs), Detach, Fade (0–90 %). |
| `POINTCLOUDVIEW` | `PCVIEW`, `POINTCLOUDCLIP`, `PCCLIP` | Point cloud display: Clip to a section box (min/max corners with Z range), Density (octree level of detail: keep at most N points shown, evenly over the cloud), Reset (show all). Hidden points move to layer POINTCLOUD-HIDDEN. |
| `SURVEYLINES` | `FIELDTOFINISH`, `SURVEYLINEWORK` | Survey field-to-finish: joins survey points into polylines by their codes (EP1 B … EP1 E, C to close) and moves points to the feature layers of the description keys (variable SURVEYCODES: EP=V-ROAD-EDGE:line; TREE=V-TREE:point). |

### Collaborate

| Command | Aliases | Description |
| --- | --- | --- |
| `BCFIN` | `BCFIMPORT`, `IMPORTBCF` | Imports BCF 2.x topics (.bcfzip) as markups: comments, status, viewpoint camera and selection mapped to elements by IFC GlobalId. |
| `BCFOUT` | `BCFEXPORT`, `EXPORTBCF` | Exports the markups as BCF 2.1 topics (.bcfzip) with comments, status, camera and selected elements by IFC GlobalId. |
| `BCFSERVER` | `BCFAPI`, `OPENCDE`, `BCFCONNECT` | Connects to a BCF API (OpenCDE) server: Connect (URL, bearer token), Projects, Pull (topics → markups with comments, cameras and selections) and Push (markups → topics, comments and viewpoints). The server URL and project are saved in the drawing (BCFSERVER, BCFPROJECT); the token is kept only for the session. |
| `CENTRAL` | `WORKSHARING`, `SYNCCENTRAL`, `STC` | Work sharing with a central model: Create (make this drawing the central file), Local (open a local copy of a central file), Sync (synchronise with central, optionally keeping borrowed elements), Borrow / Relinquish selected elements, Owners (who owns what), Permissions (signed access policy: viewer/editor/admin roles and protected layers, enforced on Sync; refused changes are saved beside the local copy). |
| `COEDIT` | `COLLABORATE`, `LIVESHARE`, `COEDITSYNC` | Co-editing through a shared folder: Join (folder, your name), Sync (send your edits, receive the others'; also after each command with AUTOSYNC), Status, Leave. Edits of different objects merge; concurrent edits of one object keep the latest and are reported. |
| `COMPARE` | `DWGCOMPARE`, `DRAWINGCOMPARE`, `MODELDIFF` | Compares the drawing with another version (.archi, .dxf, .ifc…) by object id and geometry: added, removed and modified objects; optional colour-coded overlay file (green added, red removed, yellow modified) and CSV report. |
| `COMPAREPANEL` | `COMPAREOVERLAY` | Compares with another version and draws the differences over the plan (added green, removed red, modified yellow). *(app)* |
| `GITVERSION` | `GIT`, `GITCOMMIT`, `GITLOG` | Git versioning of the drawing as a line-per-object .archit file next to it: Commit (with message), Log, Diff two revisions (or a revision and the drawing) object by object, Checkout a revision (undoable). |
| `ISSUETRACKER` | `ISSUELIST`, `TRACKISSUES` | Issue tracker stored in the drawing: Add (linked to the selection), List, Show, Status, Assign, Priority, Comment, Zoom, Delete and Csv export. |
| `MARKUP` | `MARKUPS`, `REVCOMMENT`, `COMMENT`, `ISSUE` | Review markups stored in the drawing: Add (cloud + comment with author/date, linked to selected elements and the view), List, Resolve, Reopen, Reply, Zoom, Delete. |
| `MARKUPPANEL` | `ISSUES`, `MARKUPMANAGER` | Opens the markup/issue panel: filter open/resolved, reply, resolve, zoom to, link to the selection, BCF. *(app)* |
| `MODELMERGE` | `MERGE3`, `MERGEBRANCH` | Three-way merge: combines another branch of the drawing (theirs) into this one using their common ancestor (base); non-conflicting changes of both sides are kept, conflicts keep ours and are listed. |
| `PDFMARKUPS` | `MARKUPIMPORT`, `PDFCOMMENTS` | Imports the comments of a PDF page (notes, clouds/rectangles, ink, lines, highlights) as review markups with author and date, placed with the plot scale and origin and linked to the elements under them. |
| `RESOLVECONFLICTS` | `SYNCCONFLICTS`, `MERGECONFLICTS`, `CONFLICTCOPIES` | Finds the sync-conflict copies of the drawing (iCloud Drive, Dropbox, OneDrive…) and merges them in (three-way, nothing lost; true conflicts keep yours and are listed); merged copies move to <name>.archi-conflicts/. |
| `SHARE` | `SHAREDRAWING`, `SENDTO` | Shares the drawing through the macOS share sheet (Mail, Messages, AirDrop, Notes…): Project (.archi), Pdf of the drawing or active sheet, or Both. *(app)* |
| `SHAREVIEW` | `VIEWEREXPORT`, `EXPORTVIEWER`, `HTMLVIEWER` | Exports a read-only, self-contained HTML viewer (all level plans as vectors with pan/zoom, element info on click, room schedule, layer toggles) to share with people without the app. |
| `SIGNFILE` | `SIGNDOC`, `DIGITALSIGN`, `SIGN` | Signs a file (PDF, DWG, IFC, the drawing…) with your key: writes a detached <file>.sig with the signer, time, SHA-256 and Ed25519 signature. |
| `SIGNKEY` | `SIGNINGKEY`, `NEWSIGNKEY` | Creates (or shows) your Ed25519 signing key, kept in Application Support; prints the public key others add to TRUSTEDSIGNERS. |
| `STANDARDS` | `STANDARDSPACKAGE`, `OFFICESTANDARDS` | Office standards package (.archistd): Export this drawing's layers, linetypes, styles, materials, types, view templates and hatch patterns; Import (add, optionally overwrite); Check deviations. |
| `TRACEREVIEW` | `TRACES`, `TRACEOVERLAY`, `REVIEWTRACE` | Trace review overlays: New (named overlay layer over the drawing, linked to the view and selected elements), Enter/Exit (draw on it), Show/Hide, Zoom (restores its view and selects its elements), List, Close, Import (merge its sketches into the drawing), Delete. |
| `TRUSTSIGNER` | `TRUSTKEY`, `TRUSTEDSIGNERS` | Adds a signer's public key (or the key of a .sig file) to the drawing's trusted signers. |
| `VERIFYSIGNATURE` | `CHECKSIGNATURE`, `SIGVERIFY` | Checks a file against its <file>.sig: valid signature, unchanged content, and whether the signer is trusted (TRUSTEDSIGNERS). |
| `VERSIONS` | `CHECKPOINT`, `DOCVERSIONS`, `VERSIONHISTORY` | Version history saved next to the drawing: Save a named checkpoint, List, Restore a version (undoable), Diff two versions (or a version and the current drawing), Delete, Prune. |

### Manage

| Command | Aliases | Description |
| --- | --- | --- |
| `BSDD` | `BSDDLOOKUP`, `DATADICTIONARY` | buildingSMART Data Dictionary: Search classes online (or Load a saved bSDD JSON), Assign a class and its properties to elements, add a view Filter on a class, List assigned classes. |
| `CLASSIFY` | `CLASSIFICATION`, `CLASSCODE` | Classification codes: Auto-classify by element kind (Uniformat II, NL-SfB), Set a code in any system (Uniclass 2015, OmniClass…), List, Clear. |
| `DESIGNOPTION` | `DESIGNOPTIONS`, `DOPT` | Design options: new set/option, add selection to an option, edit (new elements join it), view, primary, accept primary, list. |
| `EXPRESSION` | `EXPR`, `PROPEXPR`, `SETEXPR` | Binds a property of selected objects to an expression over their own properties, other objects (id12.height, Name.length) and global parameters; Clear removes it; List shows them. |
| `FAMILYLOCK` | `FAMLOCK`, `FAMILYEQ`, `PARAMLOCK` | Family constraints: Lock a reference plane to a parameter (dimension label), EQ planes equally spaced, Plane (add a reference plane). |
| `GEOLOCATION` | `GEOLOC`, `LOCATION`, `SITELOCATION` | Project geolocation: City preset, or Set latitude, longitude, site elevation, time zone and true north (used by sun studies, energy and exports); List shows it. |
| `GLOBALPARAM` | `GLOBALPARAMS`, `GLOBALPARAMETERS`, `PROJECTPARAM` | Global parameters: New/Set a value or =formula, Bind element dimensions (wall height, thickness, opening width…) to an expression, Unbind, List, Delete; bound elements and family formulas update when a value changes. |
| `OBJECTSTYLES` | `OBJSTYLES`, `OBJECTSTYLE`, `CATEGORYSTYLES` | Object styles: project-wide projection/cut line weights, line colour, cut fill and cut pattern per BIM category (wall, door, window, slab, column…); every plan and section follows. List, Reset, or set e.g. "cut:0.7;proj:0.35;color:red;fill:0.3,0.3,0.3;pattern:ANSI31". |
| `OBJECTSTYLESDIALOG` | `OBJECTSTYLESDLG`, `OSTYLESDIALOG` | Object Styles dialog: projection/cut line weights, line colour, cut fill and cut pattern per BIM category for every plan and section. *(app)* |
| `PARAMCELL` | `PARAMLINK`, `SPREADSHEETPARAM`, `BINDCELL` | Drives a global parameter from a spreadsheet cell (a table in the drawing, e.g. Params!B3 or #12!B3); None removes the link. |
| `PLUGINS` | `PLUGINMANAGER`, `APPLOAD` | Plugin manager: List plugins (folders with plugin.json + JavaScript), Reload and register their commands, Enable/Disable, Info, New (scaffold a plugin, optionally from a recorded script), Folder. |
| `PSET` | `PSETS`, `PROPERTYSET`, `PROPERTYSETS` | Property sets (IFC Psets): Set Pset.Property values (typed by templates), Apply a template's defaults, List an element's sets, Remove, Check values, and custom Templates (New/Add/Delete/List). |
| `REPORTPARAM` | `REPORTINGPARAM`, `REPORTINGPARAMETER` | Makes a family parameter a reporting parameter measured from the model (host.thickness, host.height, host.length, level.elevation, level.height, self.rotation…). |
| `SCRIPT2JS` | `SCRTOJS`, `RECORDTOJS` | Converts a command script (.scr, or the running SCRIPTRECORD recording) into JavaScript calling archi.run() per command. |
| `TRANSFERSTANDARDS` | `TRANSFERPROJECTSTANDARDS`, `COPYSTANDARDS`, `TPS` | Copies types, styles and settings (wall/slab/opening/stair/railing types, materials, layers, linetypes, text and dimension styles, view templates, families, parameters, schedules, keynotes) from another .archi file. |
| `TYPEIMAGE` | `SCHEDULEIMAGE`, `TYPEPICTURE` | Assigns an image file to a type (wall/opening/family type); schedules with an Image field show it in placed tables. |
| `WORKSET` | `WORKSETS` | Worksets (named element sets): list, new, current, assign selection, hide/show, select members. |

### Analyze

| Command | Aliases | Description |
| --- | --- | --- |
| `ENERGYPLUS` | `EPLUS`, `IDFEXPORT`, `ENERGYSIM` | EnergyPlus simulation: Export an IDF (rooms as zones, envelope surfaces, windows, layered constructions, ideal-loads HVAC, location) or Run an installed EnergyPlus on it with an EPW weather file: site energy, EUI, end uses, unmet hours and per-room heating/cooling energy and peak loads (written to the rooms). |
| `QAASSIST` | `MODELQA`, `EXPLAINWARNINGS`, `FIXMODEL` | Model QA assistant: explains each model-checker finding (why it matters, what to do), Zoom to one, or Fix one / all fixable issues automatically after confirmation (one undo step). |
| `THERMALBRIDGES` | `THERMALBRIDGE`, `PSIVALUES`, `TBHINT` | Finds geometric linear thermal bridges of the envelope (wall corners, ground and intermediate floor edges, balconies, eaves, window/door reveals, columns in exterior walls) with lengths, ψ values (PSI:<kind> overrides) and H_TB = Σψ·L; selects the elements. |
| `WORKSCHEDULE` | `SCHEDULE4D`, `4D`, `GANTT`, `CONSTRUCTIONSEQUENCE` | Construction sequencing (4D) and resources: Generate tasks from the model (by level and trade, quantity-based durations, crews), List with dates and critical path, Duration/Link to edit tasks, Simulate a date (selects the elements built by then), Resources (histogram, over-allocation, cost), Level (resource levelling), Gantt (SVG), Csv. |

### MEP

| Command | Aliases | Description |
| --- | --- | --- |
| `CABLETRAY` | `TRAYRUN` | Draws cable trays (open U-channel with rungs in plan) along points. |
| `CIRCUIT` | `CIRCUITS`, `ELCIRCUIT` | Electrical circuits: Create (devices on a panel circuit with description and breaker), Remove devices, Show wiring home runs, List circuits. |
| `CONDUIT` | `CONDUITRUN` | Draws electrical conduit along points with elbows. |
| `DUCT` | `DUCTRUN`, `DUCTWORK` | Draws rectangular ducts along points with flanged bends. |
| `LIGHTDATA` | `PHOTOMETRY`, `LUMINAIRE`, `LIGHTFIXTURE` | Sets photometric data of light fixtures (lumens, watts, colour temperature, beam angle) used by schedules and rendering. |
| `LIGHTSCHEDULE` | `FIXTURESCHEDULE`, `LIGHTINGSCHEDULE`, `LUX` | Lighting fixture schedule (mark, type, level, room, position, rotation, lm, W, K) and average illuminance per room. |
| `MEPCONNECTORS` | `CONNECTORS`, `FIXTURECONNECTORS` | Lists plumbing/electrical connection points of fixtures and shows or hides them in plan. |
| `MEPPIPE` | `PIPERUN`, `PIPING` | Draws pipes along points with elbow fittings at bends; can start at a plumbing fixture connector, slope and rise. |
| `MEPSYSTEM` | `SYSTEMS`, `MEPSYSTEMS`, `SYSTEMBROWSER` | Connector-based systems: list connected networks, assign a system to a whole network, show only some systems, or check open ends. |
| `PANELSCHEDULE` | `PANELSCHED` | Panel schedule of an electrical panel (circuits, loads, breakers, phase balance): List, Place as a table or Export CSV. |

### Documentation

| Command | Aliases | Description |
| --- | --- | --- |
| `ROOMDATASHEET` | `ROOMDATA`, `RDS` | Room data sheets: Show per-room reports, Export (CSV/HTML/text), Import an edited CSV back into the rooms, or Set one field. |

### Properties

| Command | Aliases | Description |
| --- | --- | --- |
| `COLORBOOK` | `COLOURBOOK`, `COLORBOOKS` | Colour books (open palettes): list books and colours, apply a colour to objects or set it current (Book$Colour). |

*(app)*: available in the Mac app (command line, menus, scripts and the agent server), not in headless `archi-cli`.

<!-- END COMMAND REFERENCE -->


## Mac display recovery and section print styles (1.0.1)

The top ribbon repaints after activation, resizing, display changes and full-screen transitions.
The 2D canvas paints its own opaque backing surface. If you have hidden or collapsed the
ribbon, type `RIBBON` (alias `RB`, also `CLEANSCREENOFF`) and press Return to restore and expand it.

Open a sheet containing a section viewport and click **Section Style**, or open **Page Setup**.
Enable **Customize section graphics on this sheet**, choose section line and cut fill colours,
set cut and projection weights in millimetres, and switch **Shaded surfaces** off for linework.
Use **Color** in Plot style to preserve the selected colours, or Monochrome/Grayscale for those
outputs. A selected plot style table can override colours and weights. Click **Preview** to
inspect the final output, then print or export PDF. These settings are saved in the drawing,
are undoable, and apply only to section viewports on that sheet. Disable customization to
return to project defaults.

The command line, scripts and agent API use the same command:

```text
SECTIONSTYLE Set "Sheet 1" "color:black;fill:0.7,0.7,0.7;cut:0.5;proj:0.25;shading:off"
SECTIONSTYLE List "Sheet 1"
SECTIONSTYLE Reset "Sheet 1"
```

Aliases: `SECSTYLE`, `SSTYLE`. Existing `.archi` files open unchanged; the style uses the
existing sheet metadata dictionary, with no format change.

### Reusable page setups (PAGEPRESET)

Page Setup includes **Named Page Setups**. Set paper, orientation, plot pens and section appearance, enter a name and click **Save**. **Load** brings a preset into the current form. Choose target sheets and **Apply to Selected**, or **Apply to All**. **Import…** reads setups saved in another `.archi` project. Imported pen tables with conflicting names receive a unique name so other sheets keep their output. Each operation can be undone; presets persist in the drawing.

Commands (quote each preset name when another argument follows, and sheet names containing spaces):

```text
PAGEPRESET Save "Presentation" "Sheet 1"
PAGEPRESET Apply "Presentation" "Sheet 1|Sheet 2"
PAGEPRESET Apply "Presentation" All
PAGEPRESET Import "/path/to/project.archi"
PAGEPRESET List
PAGEPRESET Delete "Presentation"
```

Aliases: `PSPRESET`, `NAMEDPAGESETUP`. Viewport positions/scales, geometry and title-block text stay intact. Presets include section graphics when present; use **Customize section graphics on this sheet** to edit those settings.
