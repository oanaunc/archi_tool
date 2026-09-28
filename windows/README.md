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
- **Per-user install, no administrator rights**: installs into `%LOCALAPPDATA%\Programs\Oanarina Archi Tool`
  (`packaging/installer.nsh` forces the current-user mode, so there is no UAC prompt). The folder can be changed.
- **Shortcuts**: Start menu and desktop, both "Oanarina Archi Tool".
- **File associations**: `.archi`, `.dxf` and `.ifc` open in the app (double-click, "Open with", jump list).
- **Explorer thumbnails**: `.archi` files show their plan in Explorer (FILEPREVIEW): archi-engine embeds the picture on
  save and the installer registers the unsigned thumbnail handler `native/` per user (`docs/WINDOWS-FILEPREVIEW.md`).
- **Samples**: Cedar House and Nordic House with their textures (`resources/samples`); the start screen copies a
  sample to `Documents\Oanarina Archi Tool\Samples` before opening it, so it can be edited and saved.
- **Uninstall**: Settings ▸ Apps ▸ Oanarina Archi Tool ▸ Uninstall (or "Uninstall Oanarina Archi Tool.exe" in the
  install folder). Settings, recent files and the documents folder are kept.
- **Jump list**: right-click the taskbar button for the recent projects, New Window and the Cedar House sample.
- **Windows conventions**: Ctrl instead of ⌘ and Alt instead of ⌥ for every shortcut (Ctrl+Y redo, Ctrl+0 clean screen as in
  Windows CAD, so Zoom Extents is double middle-click / Z E;
  AltGr characters still type), Alt+letter opens the menus (unique access keys, underlined while Alt is held: File F, Edit E,
  View V, Draw D, Modify M, Annotate N, Architecture A, Model O, Analyze Y, Tools T, Window W, Help H), floating panels are separate
  windows owned by the drawing window (like the Mac's utility panels), Alt+F4 exits, Ctrl+W closes the window, F1 opens the offline
  help browser at the running command's page (like the Mac), native caption
  buttons with snap layouts, per-monitor DPI scaling, and the Mac's dark theme (Settings ▸ Appearance ▸ Light switches
  the window, native dialogs and caption buttons together).

The CI smoke test (`packaging/smoke-electron.mjs`) installs the app silently, checks shortcuts, associations and the
uninstall entry, then drives the installed app: start screen, Cedar House 2D, 3D Golden hour, LINE in the command line,
save (Ctrl+Shift+S) and reopen from the command line, and a PDF plot; finally it uninstalls. Without Electron,
`npm run test:win` runs the same scenario on the renderer with the fixture engine.

### Version and release files

- The Windows version is the Mac app's: `CFBundleShortVersionString` in `app/Info.plist` (now 1.0.0) is the
  installer name, the product version and the version in Settings ▸ Apps; `CFBundleVersion` (the build, now 3) is the
  fourth number of the file version (1.0.0.3). Bump both in `app/Info.plist` only; `packaging/sync-version.mjs` copies
  them into `package.json` / `-c.buildVersion` on every CI run and `npm run dist`.
- `packaging/release-files.mjs` (run by CI right after packaging, or `node packaging/release-files.mjs` after
  `npm run dist`) writes next to the installer:
  - `SHA256SUMS.txt`: `<sha256>  Oanarina-Archi-Tool-Setup-<version>.exe`, the same format as the Mac download's
    `downloads/archi-tool/SHA256SUMS.txt`, so the two lines go into that one file;
  - `release.json`: version, build, bytes, sha256, signed or not, and the website URL.
  `node packaging/release-files.mjs --verify <folder>` recomputes the checksums (CI runs it too).
- The CI artifact "Oanarina-Archi-Tool-Windows-<version>" holds the installer, `SHA256SUMS.txt` and `release.json`;
  `release/` in the branch ci-windows-app (bridge action `winapp-fetch`, then `build/winapp/release/`) has the two
  small files without the .exe.

### Publishing on the website

The download goes to `https://www.oanarinaldi.com/downloads/archi-tool/Oanarina-Archi-Tool-Setup-<version>.exe`,
next to the Mac .dmg:

1. Take a commit whose "Windows app" run is green (install, smoke test and uninstall passed) and download the artifact
   "Oanarina-Archi-Tool-Windows-<version>" from that run on github.com/oanaunc/archi_tool/actions. Check it:
   `sha256sum -c SHA256SUMS.txt` (macOS: `shasum -a 256 -c SHA256SUMS.txt`; Windows:
   `Get-FileHash .\Oanarina-Archi-Tool-Setup-<version>.exe -Algorithm SHA256`). If possible install it once on a real
   Windows 10/11 PC.
2. **The installer is too big for git**: about 131 MB (125 MiB), and GitHub refuses any file over 100 MiB, so it
   cannot be committed to the website repository the way the .dmg (83 MB) was: the push would be rejected. Upload the
   .exe directly to the web host instead, into `public_html/downloads/archi-tool/` (cPanel File Manager or an FTP
   client with the same account as the `FTP_*` secrets of the website's deploy workflow). The deploy workflow
   (SamKirkland/FTP-Deploy-Action, incremental) only deletes files it uploaded itself, so a file uploaded by hand stays
   through later deploys. Add `downloads/archi-tool/*.exe` to the website's `.gitignore` so it is never committed by
   accident.
3. In the website repository (`oanarina_website`), commit:
   - `downloads/archi-tool/SHA256SUMS.txt` with both lines, the .dmg's and the .exe's;
   - on `archi-tool.html` a "Download for Windows" button next to "Download for Mac":
     `href="downloads/archi-tool/Oanarina-Archi-Tool-Setup-<version>.exe?v=<first 12 hex of its sha256>"` (the same
     cache-busting as the .dmg, needed because a new build with the same version keeps the same file name), label
     "Free · 131 MB · Windows 10 and 11 (64-bit)", and while the installer is unsigned the SmartScreen note below.
4. Check the live file: `curl -sI https://www.oanarinaldi.com/downloads/archi-tool/Oanarina-Archi-Tool-Setup-<version>.exe`
   (200, `Content-Length` = the size in `release.json`), then download it once and compare its SHA-256.

Other ways to host it, if the web host's space or bandwidth is a concern: Git LFS in the website repository (the
deploy's checkout then needs `lfs: true`, and every deploy uses LFS bandwidth), or a GitHub Release asset (2 GB limit)
on a public repository, linked from the website.

### Code signing and the SmartScreen warning

The installer is **not code-signed yet**. Windows SmartScreen therefore shows "Windows protected your PC" the first
time it is run. Until a certificate is in place, tell people to click **More info**, check that the app is
"Oanarina-Archi-Tool-Setup-<version>.exe" (the publisher shows as "Unknown publisher"), and click **Run anyway**. (If
the browser blocks the download itself, choose "Keep" in the downloads list first.) Suggested text for the website:
"Windows may show 'Windows protected your PC' because the installer is not signed yet: click More info, then Run
anyway. The SHA-256 checksum is in SHA256SUMS.txt."

Signing removes "Unknown publisher" (the name on the certificate is shown instead). SmartScreen still warns for a new
certificate or identity until enough people have downloaded the signed file; since 2024 this is true for EV
certificates too, so an EV certificate is not worth its higher price here. Options, prices as of 2026 (check before
buying):

| Option | Cost | Notes |
| --- | --- | --- |
| **Azure Trusted Signing** (Microsoft, now also called Artifact Signing) | Basic about US$10/month (5,000 signatures), Premium about US$100/month | Cheapest paid option and fully automatic in CI (`azure/trusted-signing-action` or electron-builder `win.azureSignOptions`); needs an Azure subscription and Microsoft's identity validation. Individual developers could only be validated in the USA and Canada; elsewhere it needs an organisation with about 3 years of verifiable history. Check eligibility first. |
| **OV code-signing certificate**, individual | about €50–120/year (Certum, incl. its open-source developer certificate), about US$130–250/year (SSL.com, Sectigo resellers), US$400+/year (DigiCert) | Since June 2023 the key must live on a hardware token or cloud HSM. On GitHub Actions use the CA's cloud signing (Certum SimplySign, SSL.com eSigner at about US$20/month extra, DigiCert KeyLocker) through electron-builder's `win.signtoolOptions.sign` hook; a USB token only works for signing on Oana's own Windows PC. Certificates last at most about 15 months, so this is a yearly cost. |
| **SignPath Foundation** | free | For open-source projects: the repository must be public (GPL-3.0 qualifies) and built on GitHub Actions; the publisher then shows as "SignPath Foundation", not Oana Rinaldi. |
| **Microsoft Store** (MSIX) | free for individual developers (check the current fee) | The Store signs the package and installs it without SmartScreen warnings; needs an MSIX target in electron-builder and a Store listing. The website download would stay unsigned. |

Recommendation: Azure Trusted Signing if Oana is eligible (lowest cost, no hardware, automatic); otherwise an OV
certificate with cloud signing (Certum is the cheapest). Wiring it up:

- With a `.pfx` (only where the CA still issues one): repository secrets `CSC_LINK` (base64 of the .pfx) and
  `CSC_KEY_PASSWORD`; the "Package the NSIS installer" step already passes them to electron-builder, which then signs
  `Oanarina Archi Tool.exe`, `archi-engine.exe` (`signExts`), the uninstaller and the installer with SHA-256 and a
  timestamp. With a cloud HSM use `win.signtoolOptions.sign`, with Azure Trusted Signing `win.azureSignOptions`
  (secrets `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`).
- `release.json` then shows `"signed": true`; check with `signtool verify /pa /v Oanarina-Archi-Tool-Setup-<version>.exe`
  and only then describe the download as signed on the website.
