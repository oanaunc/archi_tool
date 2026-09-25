# Oanarina Archi Tool

A free, native Mac application for architectural drawing and building design: 2D drafting, 3D modelling, building information modelling (BIM), rendering, sheets and printing, an AutoCAD-style command line and a scripting interface that AI agents can drive.

Status: early development. See [docs/FEATURE-REGISTER.md](docs/FEATURE-REGISTER.md) for the complete planned feature list and what is already implemented.

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
