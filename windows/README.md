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

## Windows installer

`.github/workflows/windows-app.yml` builds `Oanarina-Archi-Tool-Setup-<version>.exe` on every push (artifact
"Oanarina-Archi-Tool-Windows-<version>"); locally on Windows: `npm ci` then `npm run dist` (needs
`resources/engine/archi-engine.exe` with its DLLs, see `packaging/collect-dlls.py`, and Python with Pillow for the icon).

- **Version**: the Mac app's `CFBundleShortVersionString` from `app/Info.plist` (`npm run version:sync` writes it into
  `package.json`; the build number `CFBundleVersion` becomes the fourth number of the .exe file version).
- **App id**: `com.oanarina.architool`, the Mac bundle identifier; also the Windows AppUserModelID (taskbar grouping,
  jump list) set in `src/main/main.ts`.
- **Per-user install, no administrator rights**: installs into `%LOCALAPPDATA%\Programs\oanarina-archi-tool`
  (`packaging/installer.nsh` forces the current-user mode, so there is no UAC prompt). The folder can be changed.
- **Shortcuts**: Start menu and desktop, both "Oanarina Archi Tool".
- **File associations**: `.archi`, `.dxf` and `.ifc` open in the app (double-click, "Open with", jump list).
- **Samples**: Cedar House and Nordic House with their textures (`resources/samples`); the start screen copies a
  sample to `Documents\Oanarina Archi Tool\Samples` before opening it, so it can be edited and saved.
- **Uninstall**: Settings ▸ Apps ▸ Oanarina Archi Tool ▸ Uninstall (or "Uninstall Oanarina Archi Tool.exe" in the
  install folder). Settings, recent files and the documents folder are kept.
- **Jump list**: right-click the taskbar button for the recent projects, New Window and the Cedar House sample.
- **Windows conventions**: Ctrl instead of ⌘ for every shortcut, Alt+letter opens the menus, Alt+F4 exits, Ctrl+W
  closes the window, F1 opens the user guide (https://www.oanarinaldi.com/archi-tool-guide.html), native caption
  buttons with snap layouts, per-monitor DPI scaling, and the Mac's dark theme (Settings ▸ Appearance ▸ Light switches
  the window, native dialogs and caption buttons together).

The CI smoke test (`packaging/smoke-electron.mjs`) installs the app silently, checks shortcuts, associations and the
uninstall entry, then drives the installed app: start screen, Cedar House 2D, 3D Golden hour, LINE in the command line,
save (Ctrl+Shift+S) and reopen from the command line, and a PDF plot; finally it uninstalls. Without Electron,
`npm run test:win` runs the same scenario on the renderer with the fixture engine.

### Code signing and the SmartScreen warning

The installer is **not code-signed yet**. Windows SmartScreen therefore shows "Windows protected your PC" the first
time it is run. Until a certificate is in place, tell people to click **More info**, check that the app is
"Oanarina-Archi-Tool-Setup-<version>.exe" (the publisher shows as "Unknown publisher"), and click **Run anyway**. (If the download itself is blocked in the browser,
choose "Keep" in the downloads list first.)

To remove the warning the installer and the app must be signed with a code-signing certificate issued to Oana Rinaldi:

- An **EV or OV code-signing certificate** from a certificate authority (DigiCert, Sectigo, GlobalSign, SSL.com …);
  since 2023 these keys live on a hardware token or a cloud HSM, so the practical CI options are a cloud signing
  service (SSL.com eSigner, DigiCert KeyLocker, Azure Trusted Signing) or a `.pfx` exported where the CA allows it.
  OV certificates build SmartScreen reputation over the first downloads; Azure Trusted Signing is the cheapest option
  for an individual developer where it is available.
- With a `.pfx`: add the repository secrets `CSC_LINK` (base64 of the .pfx) and `CSC_KEY_PASSWORD`; the "Package the
  NSIS installer" step already passes them to electron-builder, which then signs `Oanarina Archi Tool.exe`,
  `archi-engine.exe`, the uninstaller and the installer with SHA-256 and a timestamp. With a cloud HSM, use
  electron-builder's `win.signtoolOptions.sign` hook (or `azureSignOptions` for Azure Trusted Signing).
- Check the result with `signtool verify /pa /v Oanarina-Archi-Tool-Setup-<version>.exe`, and only then describe the
  download as signed on the website.
