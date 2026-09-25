# Oanarina Archi Tool

A free, native Mac application for architectural drawing and building design: 2D drafting, 3D modelling, building information modelling (BIM), rendering, sheets and printing, an AutoCAD-style command line and a scripting interface that AI agents can drive.

Status: early development (1.0 preview). The [user guide](docs/USER-GUIDE.md) describes everything that works today; [docs/FEATURE-REGISTER.md](docs/FEATURE-REGISTER.md) lists the complete planned feature set and the status of each item.

## What it does today

- **Drafting:** AutoCAD-style command line with 300+ commands and aliases, relative/polar/unit-suffixed input, point filters, UCS, object snaps, grips, transparent commands, scripts (.scr) and script recording.
- **Editing and selection:** all the usual modify tools plus OVERKILL, clipboard with base point, window/crossing/fence/polygon selection, quick select, filters, named selection sets and groups.
- **Annotation:** text and mtext with fields, dimensions, multileaders, tables with formulas, annotative scaling, blocks with attributes and data extraction.
- **BIM:** levels, walls (straight and curved, clean joins, sweeps, niches), doors and windows with type catalogues, curtain walls, slabs (sloped), roofs (flat, shed, gable, hip on any footprint), ceilings, stairs, ramps, railings, columns, beams, foundations, rooms, area plans, phases, toposurfaces and building pads.
- **Documentation:** live plans, sections and elevations, tags, keynotes, door/window marks, schedules, sheets with viewports and title blocks, page setup, plot preview and multi-sheet PDF publishing.
- **3D:** solids, extrude/revolve/loft/sweep/pipe/press-pull, booleans, slice and interference; 3D view with view cube, visual styles, section box, sun study, saved cameras, walkthrough, and rendering with presets and turntable video.
- **Exchange:** DXF (including R12 export), IFC import/export with GUID round trip, SVG, OBJ, STL, 3MF, glTF, USD, GeoJSON, CSV survey points and PDF.
- **Analysis:** quantity takeoff, cost estimates, room area schedules, clash detection, model checking and sun position.
- **Automation:** JavaScript console and script library, a local JSON-RPC agent server and an MCP server (`archi-cli --mcp`) for Claude and other AI agents.

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
