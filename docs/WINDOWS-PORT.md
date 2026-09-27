# Oanarina Archi Tool for Windows — port plan

Goal (Oana, 27 Sep 2026): a Windows version that is an exact replica of the Mac app, every feature.
It is published on the website only when complete: a second yellow "Download for Windows" button beside
"Download for Mac", and the menu entry becomes just "Archi Tool".

## Architecture

```
┌────────────────────────── Oanarina Archi Tool.exe (Electron shell, TypeScript) ──────────────────────────┐
│ ribbon · tool palettes · panels (Properties, Layers, Levels, Browser, Materials, Sheets, History …)       │
│ 2D canvas: paints the engine's DrawList (same items the Mac CanvasView paints)                           │
│ 3D view + photographic renderer: three.js (WebGL2/WebGPU), meshes from the engine's MeshBuilder,         │
│   lighting presets Daylight / Golden hour / Overcast / Night mirroring BeautyLighting                    │
│ command line · dynamic input · grips · start screen · dialogs · printing to PDF (engine) and Windows print│
└───────────────▲──────────────────────────────────────────────────────────────────────────────────────────┘
                │ JSON-RPC over stdio (newline-delimited JSON), one engine process per window
┌───────────────┴──────── archi-engine.exe (Swift, ArchiCore) ────────────────────────────────────────────┐
│ Editor + CommandRegistry (all 1044 commands), documents, undo, snaps, grips, prompts and previews,        │
│ DrawListBuilder for plan/sheet views, MeshBuilder for 3D, IO (DXF, IFC, PDF, glTF …), analysis, scripting │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Why: the command logic, geometry, 2D display lists and all file formats already live in ArchiCore, which is
plain Swift + Foundation and builds on Windows. Only the Apple UI layer (ArchiApp: SwiftUI, AppKit, SceneKit,
JavaScriptCore) has to be rebuilt. Painting the same DrawList keeps plans pixel-compatible with the Mac.
The Mac app is unchanged.

## Phases
1. **Engine on Windows** — ArchiCore builds and its tests pass on windows-latest (CI: portable-engine.yml).
2. **archi-engine** — portable executable target: JSON-RPC session host for Editor (open/new/save, run command
   line, pointer and key input, prompt state, selection, preview geometry, DrawList for a view rectangle,
   meshes for 3D, panel data, undo/redo, system variables). Script console: JavaScriptCore is Mac-only, so on
   Windows the `archi` API runs in the shell's own JavaScript (V8) and calls the engine.
3. **Shell** — Electron + TypeScript + three.js: layout and theme copied from the Mac app (dark UI, yellow
   accent #F5C518), ribbon generated from the same command catalogue (CommandCoverage), panels, canvas, 3D.
4. **Parity** — feature-by-feature checklist generated from the Mac catalogue (every ribbon/menu/palette entry,
   panel, dialog, render preset); the 12 tutorial scripts replayed on Windows as the click-through test.
5. **Package** — NSIS installer (x64 + arm64), bundled Cedar House sample, code signing (certificate needed;
   until then unsigned with a SmartScreen note), website download.

## Testing
- Every push: engine tests on Windows + Linux (GitHub Actions), logs on branches ci-log-windows / ci-log-linux.
- Shell: Playwright-for-Electron tests on windows-latest, screenshots compared with the Mac app's.
