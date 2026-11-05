# Door/window label repair — 1.0.8

Published 5 November 2026: English macOS and Windows applications, both **1.0.8 (build 16)**, are available from [the public download page](https://www.oanarinaldi.com/archi-tool.html?v=20261105a). Both hosted files were downloaded completely and matched their verified checksums. The separate Mac App Store **1.0.8 (17)** submission is **Waiting for Review**; Apple approval remains pending. Nicola received the Italian reply after publication and all verification completed.

## Changes

- Editing a live door/window label's Content creates an explicit annotation override that appears in the drawing and PDF/SVG. Properties, the native in-place editor, TEXTEDIT / ED / DDEDIT, SETPROP and the portable Windows panel use the displayed value. The bubble and leader remain. Editing annotation text does not resize the underlying opening.
- Automatic labels remain live when only formatting changes. Properties exposes Label Mode; setting Automatic, or TAGLABEL / EDITLABEL / TAGFORMAT > Automatic, restores model values. Choosing a new Field/Label or explicitly rerunning OPENINGSIZES refreshes the automatic label.
- TAGALL distinguishes reference labels from size/type labels, so dimensions no longer prevent adding references. TAGLABEL > Field > mark converts existing bubbles to references. Actual door Mark properties can be D1, D2, D3; MARKS Renumber keeps its existing D01/D02 format.
- Undo/Redo and .archi persistence use the existing extensible props dictionary. Document format and compatibility are unchanged. The [English guide](USER-GUIDE.md) and [Italian steps](DOOR-LABELS-IT.md) describe the workflow. The customer's original project was not supplied; regression documents reproduce the reported edit.

## Verification

Fix commit: `b5ca1f51ca03b50d992d54a0020bc6de0eaace48`.

- **14 focused core tests passed**, including manual/automatic rendering, save/reopen, Undo/Redo, aliases, reference conversion and the actual portable panel.set API.
- The native debug app, final universal Developer ID app and app mounted read-only from the final DMG each passed **997 app checks**, with **1053 commands and zero missing UI entries**. Both arm64 and x86_64 binaries declare minimum macOS 14.0. Runtime checks ran on Apple silicon; physical Intel execution was not tested.
- The Windows JSON-RPC client drove external debug and release engine processes successfully: six base protocol checks and four label checks, including persisted panel edits, rendered dimensions, PDF export and restoring automatic values. Extracted PDF text contains `900x2100`.
- [Portable-engine CI 42061721473](https://github.com/oanaunc/archi_tool/actions/runs/42061721473) passed **all 1065 core tests on Windows and all 1065 on Linux**.
- [Windows app CI 42061722441](https://github.com/oanaunc/archi_tool/actions/runs/42061722441) passed release-engine/DLL isolation, Electron shell, Explorer handler builds, NSIS packaging, per-user installation/associations, actual Explorer thumbnails, **22 installed-app smoke checks**, uninstall and **all 19 Chromium UI suites**. No UI suite was skipped.
- The separate sandbox preview passed **997 app checks**, **17 sandbox checks** and **eight packaging regression tests**. Distribution app/installer signatures, profile/certificate matching and both universal dSYM UUID sets passed. Store runtime checks used the local preview on Apple silicon, not an App Store-installed copy.

## Distribution artifacts

Mac: `Oanarina-Archi-Tool-1.0.8.dmg`, **92,098,631 bytes**. SHA-256: `c74103b76de70cf7fb7ff99ab81810aac03d3c76283ff3788446e1c16627edeb`.

Apple notarization accepted the app (`550a485f-ce3e-441a-83f9-a60d7b5ed53e`) and DMG (`df8bc151-e436-403b-be4f-92d1a2c45834`). Both tickets were stapled and Gatekeeper accepted both artifacts as Notarized Developer ID.

Windows: `Oanarina-Archi-Tool-Setup-1.0.8.exe`, **132,787,727 bytes**, file version **1.0.8.16**. SHA-256: `81668aa8abd805c9708ffe27e044fe35186cc6d630af8cedf04a9e45507a89af`. The [immutable release](https://github.com/oanaunc/archi_tool/releases/tag/windows-v1.0.8) download also matched its manifest/checksum. The installer remains unsigned, with the existing website disclosure. This is the Windows 10/11 x64 installer; native arm64 engine execution is not claimed.

## Publication and delivery

Website artifact commit `6031862` deployed in [run 42064587411](https://github.com/oanaunc/oanarina_website/actions/runs/42064587411). Final release page/guide/checksum commit **`2f0fc20`** deployed successfully in [run 42086133785](https://github.com/oanaunc/oanarina_website/actions/runs/42086133785). The live page shows Mac and Windows 1.0.8 with their correct download URLs. Complete HTTPS reads of both website download links matched every byte and SHA-256 above. The English guide, Italian steps and checksum file returned HTTP 200 with the updated content. Visual proof: `build/website-1.0.8-live.jpg`; machine-readable results: `build/door-live-final-verification.json` (both ignored by Git).

Apple upload succeeded at **18:24:24 Europe/Bucharest**. After build 17 became Ready to Submit, the old waiting 1.0.5 (13) submission was replaced. Version 1.0.8, its English description/reviewer notes and build 17 were saved. Add for Review passed; Submit for Review returned **1 Item Submitted** at **18:31**. [Submission 273fc32d-9834-4ddc-8b7c-ab0b45d16379](https://appstoreconnect.apple.com/apps/6823133541/distribution/reviewsubmissions/details/273fc32d-9834-4ddc-8b7c-ab0b45d16379) explicitly confirms **macOS App 1.0.8 (17)** and **Waiting for Review** for both submission and item. Automatic release after approval and the existing sandbox entitlement explanation remain saved. No new reviewer message was sent. Evidence: `build/app-store/evidence/waiting-review-17.jpg`.

After all checks and final website verification, the original support conversation received one Italian reply with the website download link, installation steps, English interface labels, the quote-edit fix and D1/D2/D3 instructions. Gmail returned message **`1a1ad0594f3b2afc`**, thread `1a11ff8507e06936`, with the **SENT** label. No early or partial reply was sent.
