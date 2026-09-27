# Oanarina Archi Tool for Windows (shell)

Electron + TypeScript shell that replicates the Mac window (MainWindow.swift) and drives `archi-engine.exe`
(ArchiCore over newline-delimited JSON-RPC 2.0, one process per window). See `../docs/WINDOWS-PORT.md`.

- `npm install` then `npm start` (needs `resources/engine/archi-engine.exe`, or `ARCHI_ENGINE=<path>`).
- `npm run gen` regenerates the ribbon/menus/icons from `../docs/windows-parity.json` (fallback:
  `src/renderer/data/ribbon-fallback.json`, made by `python3 tools/extract_ribbon.py .. src/renderer/data/ribbon-fallback.json`
  from the Mac Swift sources). Icons: SF Symbol names mapped to Lucide (ISC) in `tools/sf-to-lucide.mjs`.
- Browser/UI test without the engine: `node build.mjs --web && node test/ui-snapshots.mjs` — the renderer uses the
  fixture engine (`src/renderer/fake-engine.ts`) with `test/fixtures/cedar-house` (or `?fixtures=<dir>` with
  `session.jsonl` / `<method>.json` files from build/engine-fixtures). Screenshots go to `test-results/`;
  `python3 test/tools/compare.py test/mac-reference test-results` puts them beside the Mac frames.

Layout: `src/main` (Electron main, engine process + JSON-RPC client), `src/preload` (window.archi bridge),
`src/renderer` (UI: ui/ ribbon, panels, command line, status bar, start screen, title bar; canvas/ DrawList painter).
