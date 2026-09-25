# Architecture

Oanarina Archi Tool is a Swift package in `app/`:

| Target | Role |
| --- | --- |
| `ArchiCore` | Platform-independent model and logic (Foundation only — no AppKit/SwiftUI/SceneKit/Combine). Testable headless. |
| `ArchiApp` | macOS interface: SwiftUI + AppKit, Core Graphics 2D canvas, SceneKit 3D viewport, PDFKit/Core Graphics printing, JavaScriptCore scripting, local agent server. |
| `archi-cli` | Headless runner: reads command lines / scripts on stdin, runs them against a document, can serve the agent protocol over stdio. |
| `ArchiCoreTests` | XCTest suite (`./scripts/test.sh`). |

Build: `./scripts/build.sh` (debug, creates `build/Oanarina Archi Tool.app`), `CONFIG=release ./scripts/build.sh` (universal), `./scripts/package.sh` (signed/notarized DMG). Swift language mode 5; minimum macOS 14.

Agents developing in the Linux VM cannot compile. They queue work on the Mac with `scripts/q.sh build|test|push` (see `scripts/bridge-actions.sh`). Builds are serialized; `build.sh` prints only `file:line: error:` lines.

## Core model (`ArchiCore/Model`)

- `ArchiDocument` (value type, Codable) — units, layers, linetypes, text/dim styles, blocks, `entities: [Entity]` (2D/3D drafting objects), `elements: [BIMElement]` (building elements), levels, materials, wall types, layouts (sheets with viewports), named views, AutoCAD-style `variables`, `nextID`. **Never name a type `Document` (collides with SwiftUI).**
- `Entity` — `id`, `layer`, `color: ColorRef`, `linetype?`, `lineweight?`, `geometry: Geometry`, `props`.
- `Geometry` enum — point, line, circle, arc (CCW radians), ellipse, polyline (bulge vertices), spline, text (single & multiline via `width`), dimension, hatch, insert (block reference), leader, image, table, solid (3D primitive/extrusion/mesh).
- `BIMElement` — `id` (shared ID space), `level`, `name`, `layer`, `material`, `geometry: BIMGeometry` (wall, slab, column, beam, opening = door/window/opening hosted in a wall, roof, stair, railing, space/room, curtainWall, component, gridLine), `props`.
- Units are millimetres by default. Angles in radians internally, degrees on the command line.
- `UndoHistory` stores whole-document snapshots (cheap: copy-on-write arrays).

## Command engine (`ArchiCore/Commands`)

`Editor` (@MainActor) owns the document, selection, undo, settings and the running command. Commands are `async` functions that ask for input, AutoCAD-style:

```swift
CommandDef("CIRCLE", aliases: ["C"], category: "Draw", summary: "Draws a circle.") { ed in
    let c = try await ed.requirePoint("Specify center point")
    guard let r = try await ed.getDistance("Specify radius", base: c, preview: { p in [.circle(CircleGeom(c, c.distance(to: p)))] }).value else { return }
    ed.doc.add(.circle(CircleGeom(c, r)))
}
```

- Input helpers: `requirePoint`, `getPoint` (point/keyword/none), `getDistance`, `getAngle` (returns radians), `getInteger`, `getString`, `getKeyword`, `getSelection` (uses pre-selection — noun/verb), `getEntity`. Escape throws `CommandError.cancelled`; `throw CommandError.invalid("message")` for user errors.
- `preview` closures return `[Geometry]` drawn as rubber-band by the canvas.
- The whole command becomes one undo step automatically (if `modifies`). Non-command edits use `editor.transaction("Label") { doc in ... }`.
- Command line syntax: `x,y` absolute, `@dx,dy` relative, `@d<angle` polar, `d<angle`, a bare number = direct distance along the cursor direction, arithmetic (`2400/2`), feet-inches (`3'6"`), keywords by capital letter (`C` for Close), `#12,#15` entity IDs. Spaces separate inputs except for text prompts. Empty line repeats the last command.
- `ed.host?.perform(HostAction)` asks the UI to zoom, switch 2D/3D, open/save/export/plot, render.
- Scripts and agents call `await editor.run("LINE 0,0 1000,0 ")`; unanswered prompts get Enter.
- Register commands in `BuiltinCommands.registerAll`, one file per category: `DrawCommands.swift`, `ModifyCommands.swift`, `AnnotateCommands.swift`, `ArchitectureCommands.swift`, `InquiryCommands.swift`, `SettingsCommands.swift`, `BlockCommands.swift`, `FileViewCommands.swift`, each exposing `static var all: [CommandDef]`.

## Geometry services (`ArchiCore/Geometry`)

- `GeometryOps`: tessellation, bounds, distance, pick/crossing tests, area/length/centroid, `transform(_:_:)` with `Transform2D`, grips.
- `Intersections.of(_ a: Geometry, _ b: Geometry, doc:) -> [Vec2]` (all curve pairs; infinite-extension variant `extended:`).
- `Modify`: `trim(_:at:boundaries:doc:) -> [Geometry]?`, `extend(_:at:boundaries:doc:) -> Geometry?`, `offset(_:distance:towards:) -> Geometry?`, `fillet(_:pickA:_:pickB:radius:) -> FilletResult?`, `chamfer(...)`, `breakAt(_:_:_:) -> [Geometry]?`, `join(_:) -> [Geometry]`, `explode(_:doc:) -> [Geometry]?`, `stretch(_:window:by:) -> Geometry`, `lengthen(_:at:delta:) -> Geometry?`, `divide(_:count:) -> [Vec2]`, `measure(_:segmentLength:) -> [Vec2]`, `reverse(_:)`.
- `Snap.find(cursor:doc:settings:tolerance:base:) -> SnapResult?` (object snaps) and `Snap.constrain(base:cursor:settings:) -> Vec2` (ortho/polar).

## Rendering (`ArchiCore/Render`, `ArchiCore/BIM`)

- 2D: `DrawListBuilder.entries(doc:level:options:) -> [DrawEntry]` resolves colors/linetypes/lineweights, text, dimensions (`DimensionRenderer`), hatches (`HatchPatterns`), block inserts, and BIM plan symbols (`PlanRepresentation`: walls with cut fill and clean joins, door swings, windows, stairs with arrow, rooms with name/area tags, grids with bubbles). Screen, PDF and SVG all consume `DrawEntry`.
- Sections/elevations: `ElevationBuilder` projects `MeshGroup`s to 2D hidden-line entries.
- 3D: `MeshBuilder.build(doc:) -> [MeshGroup]` turns BIM elements and solids into triangle meshes (walls cut by openings, slabs with holes, roofs, stairs, door/window frames and glass).

## File formats (`ArchiCore/IO`)

`.archi` (JSON, `ArchiFile`), DXF R2000 ASCII read/write, SVG export, OBJ+MTL / STL / glTF export, IFC4 STEP export, CSV schedules. PDF output lives in the app (Core Graphics).

## App (`ArchiApp`)

`AppModel` (ObservableObject) wraps one `Editor`. Main window: ribbon (Home, Insert, Annotate, Architecture, Structure, View, Output, Manage, Script) → canvas area (2D plan canvas, 3D viewport, split, sheet view) → docked panels (Layers, Properties, Levels, Project Browser, Materials) → command line with history and autocomplete → status bar (coordinates, GRID/SNAP/ORTHO/POLAR/OSNAP/LWT toggles, level, units). Dark neutral UI with yellow `#F5C518` accent.

## Scripting and AI agents

- JavaScript console (JavaScriptCore) with an `archi` object: `archi.run("LINE 0,0 100,0 ")`, `archi.add({...})`, `archi.entities()`, `archi.select()`, `archi.doc()`.
- Local agent server (off by default, Settings → Agents): JSON-RPC 2.0 over HTTP on `127.0.0.1:47800` with a per-session token; methods `run_command`, `get_document`, `list_entities`, `add_entity`, `update_entity`, `delete_entities`, `add_element`, `export`, `screenshot`.
- `archi-cli --mcp` is a Model Context Protocol server (stdio) exposing the same tools, so Claude and other agents can drive the app or edit `.archi` files headless.
