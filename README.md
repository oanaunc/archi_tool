# Oanarina Archi Tool

A free, native Mac application for architectural drawing and building design: 2D drafting, 3D modelling, building information modelling (BIM), rendering, sheets and printing, an AutoCAD-style command line and a scripting interface that AI agents can drive.

Status: early development (1.0 preview). The [user guide](docs/USER-GUIDE.md) describes everything that works today; [docs/FEATURE-REGISTER.md](docs/FEATURE-REGISTER.md) lists the complete planned feature set and the status of each item.

## What it does today

- **Drafting:** AutoCAD-style command line with 440+ commands and aliases, relative/polar/unit-suffixed input, point filters, UCS, object snaps and object snap tracking, grips, transparent commands, command history, scripts (.scr) and action macros; construction variants for lines, tangent circles, arcs and ellipses; parametric geometric and dimensional constraints with a solver and named parameters.
- **Editing and selection:** all the usual modify tools plus OVERKILL, weld, clip, break-all, extend-by and move-rotate, clipboard with base point, window/crossing/fence/polygon selection, quick select, filters, named selection sets, groups and object isolation.
- **Annotation:** text and mtext with fields, dimensions, multileaders, tables with formulas, annotative scaling, GD&T frames, blocks with attributes, visibility states and data extraction.
- **BIM:** levels, walls (straight and curved, clean joins, sweeps, niches), doors and windows with type catalogues, curtain walls, slabs (sloped), roofs (flat, shed, gable, hip on any footprint), ceilings, walls attached to roofs and slabs or spanning levels, stairs and ramps with landings and rule checks, railings, columns, beams, foundations, rooms, area plans, phases, a library of 26 parametric furniture, fixture and site families, copy to levels, toposurfaces and building pads.
- **Documentation:** live plans, sections, elevations, interior elevations and callouts, tags, keynotes, door/window marks, schedules, sheets with viewports, view titles and title blocks, a sheet set manager with numbering, index and revisions, page setup, plot preview and multi-sheet PDF publishing.
- **3D:** solids, extrude/revolve/loft/sweep/pipe/press-pull, booleans, slice and interference, fillet/chamfer edges, shell, 3D mirror/rotate/array, mesh smoothing and a visual node editor; 3D view with view cube, visual styles, section box, sun study, saved cameras, walkthrough, and rendering with presets, HDRI environments, exposure and white balance, clay mode, a material library and turntable video.
- **Exchange:** DXF (including R12 export, contour elevations), IFC import/export with GUID round trip (including ramps, footings, coverings and phases), IfcZIP, IDS checking, DWG through an installed converter, STEP, SVG, OBJ, STL, 3MF, glTF import/export, PLY, OFF, AMF, COLLADA, USD, gbXML, COBie, XLSX, HP-GL/2, point clouds, shapefiles, OpenStreetMap, CityJSON, elevation grids, GeoJSON, CSV survey points and PDF; batch conversion with `archi-cli --convert`.
- **Analysis:** quantity takeoff, cost estimates, room and level area schedules, clash detection, model checking, sun position and sun path, U-values, heat loss, daylight factor, solar radiation, reverberation, embodied carbon, isovists, a structural analytical model with frame analysis, code and drawing-standards checks and IFC validation (simplified estimates, not validated against reference tools).
- **Automation:** JavaScript console and script library, a local JSON-RPC agent server and an MCP server (`archi-cli --mcp`, including analysis tools) for Claude and other AI agents.

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
