# Oanarina Archi Tool

A free, native Mac application for architectural drawing and building design: 2D drafting, 3D modelling, building information modelling (BIM), rendering, sheets and printing, an AutoCAD-style command line and a scripting interface that AI agents can drive.

Status: early development (1.0 preview). The [user guide](docs/USER-GUIDE.md) describes everything that works today; [docs/FEATURE-REGISTER.md](docs/FEATURE-REGISTER.md) lists the complete planned feature set and the status of each item.

## What it does today

- **Drafting:** AutoCAD-style command line with 880+ commands and aliases, a catalog of 219 system variables, relative/polar/unit-suffixed input, point filters, UCS, object snaps and object snap tracking, grips, transparent commands, command history, scripts (.scr) and action macros; construction variants for lines, tangent circles, arcs and ellipses; parametric geometric and dimensional constraints (including ratio and difference) with a solver that runs live while dragging, constraint glyphs and named parameters; multilines, isometric drafting, freehand sketch, conics and drafting symbols; associative rectangular, polar and path arrays, helices, custom macro buttons and a system variable monitor.
- **Editing and selection:** all the usual modify tools plus OVERKILL, weld, clip, break-all, extend-by and move-rotate, clipboard with base point, 2D region booleans, window/crossing/fence/polygon selection, quick select, filters, named selection sets, groups and object isolation.
- **Annotation:** text and mtext with fields and spell checking, associative dimensions with breaks and overrides, associative hatches, multileaders, lists, text columns, stacked fractions, dimension tolerances, alternate units and inspection dimensions, tables with formulas and CSV data links, annotative scaling, GD&T frames, blocks with attributes, visibility states and data extraction, external references (attach/overlay, bind, notification) and layer tools (walk, merge, translate, states, filters, per-viewport freeze).
- **BIM:** levels, walls (straight and curved, clean joins, sweeps, niches), doors and windows with type catalogues, curtain walls, slabs (sloped), roofs (flat, shed, gable, hip on any footprint), ceilings, walls attached to roofs and slabs or spanning levels, stairs (with winders) and ramps with landings and rule checks, curtain walls with mullion types and spandrel/louvre panels, railings, columns, beams with steel profiles, beam systems, braces and trusses, foundations, MEP pipes, ducts, cable trays and conduits, rooms, area plans, phases, worksets, design options, room finishes and colour fill schemes, a library of 26 parametric furniture, fixture and site families, a family editor (`FAMILY` and the Family Editor panel) with formulas, voids, nested families, blends, reference planes, global parameters and flex tests, rectangular and radial grid systems, mansard, gambrel, dome and barrel roofs, escalators, zones, classification codes and property sets, layered floors and roofs, skylights, shafts, dormers, railing types, elevators, lighting fixtures, MEP systems, area schemes and model groups, copy to levels, toposurfaces, building pads, site sub-regions, paths, parking, retaining walls and property lines.
- **Documentation:** live plans, sections, elevations, interior elevations and callouts, reflected ceiling plans, automatic wall dimensions, spot elevations and slopes, tags, keynotes, door/window marks, schedules, sheets with viewports, view titles and title blocks, a sheet set manager with numbering, index and revisions, page setup, CTB plot styles, plot log, plot preview and multi-sheet PDF publishing.
- **3D:** solids, extrude/revolve/loft/sweep/pipe/press-pull, booleans, slice and interference, fillet/chamfer edges, shell, 3D mirror/rotate/array, wedge, torus, pyramid, prism, polyhedron and polysolid primitives, thicken, hull and separate, mesh conversion, mesh smoothing, mesh repair and decimation, revolved/tabulated/ruled/edge surfaces and a visual node editor; 3D view with view cube, visual styles, section box, live section planes with caps, sun study, saved cameras, walkthrough, and rendering with presets, HDRI environments, exposure and white balance, clay mode, a physical sky model, a material library, turntable, walkthrough and sun-study video and 360° panoramas.
- **Exchange:** DXF (including R12 export, contour elevations), IFC2x3/IFC4/IFC4.3 import/export with georeferencing, class mapping and GUID round trip (including ramps, footings, coverings and phases), IfcZIP, IDS checking, DWG through an installed converter, STEP, SVG, OBJ, STL, 3MF, glTF import/export, PLY, OFF, AMF, COLLADA, USD, gbXML, COBie, XLSX, HP-GL/2, point clouds, shapefiles, OpenStreetMap, CityJSON, elevation grids, GeoJSON, CSV survey points, georeferenced images, KML/KMZ, layered SVG, PDF import and export, DWFx and DGN V7 import, IGES, FBX, LAS point clouds with scan-to-BIM, laser-cutter SVG; BCF issues, drawing compare, markups and eTransmit packages; batch conversion and batch jobs with `archi-cli --convert` and `--batch`.
- **Analysis:** quantity takeoff, cost estimates, room and level area schedules, clash detection, model checking, sun position and sun path, U-values, heat loss, daylight factor, solar radiation, reverberation, embodied carbon, isovists, energy balance, egress and accessibility checks, bills of quantities, a structural analytical model with frame analysis, structural loads and supports with OpenSees export, thermal bridge hints, EnergyPlus export, 4D construction scheduling, code and drawing-standards checks and IFC validation (simplified models; the main ones are checked against hand calculations).
- **Collaboration:** version history with compare and restore, three-way model merge, standards packages, `.bak` backups, crash-recovery journal, `RECOVER` for damaged files, an issue and markup panel, PDF markup import, central/local models with element borrowing, Git-friendly project files, read-only viewer pages and sharing through the macOS share sheet.
- **Automation:** JavaScript console and script library, a local JSON-RPC agent server and an MCP server (`archi-cli --mcp`, with analysis tools, resources and prompts) for Claude and other AI agents, JavaScript plugins and script-registered commands, event hooks and script panels, Python and AutoLISP bridges, folder-watch automation, and assistants that auto-dimension plans, name rooms, generate plans from a brief and check the model.

Round 6 added snap overrides and grip editing on the canvas, wall types, schedules that edit the model, visibility/graphics
overrides, families saved as `.archifam`, window and file tabs, sheet viewports (polygonal, clipped, aligned), 3D visual
styles, BREP and E57 exchange, PDF underlays, co-editing through a shared folder, annual daylight (sDA/ASE) and OpenFOAM wind
cases. The feature register now lists 871 of 1157 features as done and 73 as partial.

Round 7 added dynamic input, temporary dimensions and alignment guides; the block editor and in-place reference editing;
revision clouds, table styles and detailing tools; stacked and storefront walls, assemblies and parts, type builders and
project views with crops, dependent views and matchlines; mesh tools and an OpenSCAD-like CSG language; walk/fly navigation,
lights, fog and render passes; layered PDF and shade plots; shadow diagrams, Radiance and EnergyPlus exchange, ifcXML, STEP
B-rep import, digital signatures and an AI assistant. The feature register now lists 987 of 1157 features as done and 71 as partial.

## Build and run

Requires macOS 14 or later and Xcode 16 or later (Swift 5.10+).

```sh
./scripts/build.sh          # builds build/Oanarina Archi Tool.app
./scripts/test.sh           # runs the core test suite
./scripts/package.sh        # universal signed DMG in dist/
```

## Project layout

- `app/` — Swift package. `ArchiCore` holds the platform-independent drawing and building model, geometry, commands and file formats. `ArchiApp` is the macOS interface (SwiftUI/AppKit, SceneKit 3D).
- `docs/` — feature register, user guide, scripting and agent API.
- `scripts/` — build, test, package and the Mac bridge used by development agents.
- `other_projects/` — local reference checkouts (FreeCAD, LibreCAD, IfcOpenShell, SolveSpace, OpenSCAD, BRL-CAD, Sverchok, CAD Sketcher). Not part of this repository.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). Code adapted from GPL reference projects keeps its attribution in the source file header and in `docs/THIRD-PARTY.md`.

Project remote: `git@github.com:oanaunc/archi_tool.git`.
