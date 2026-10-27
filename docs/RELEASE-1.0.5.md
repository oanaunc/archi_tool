# Mac release 1.0.5 (build 12)

27 October 2026. Universal Apple silicon / Intel download; minimum macOS 14.

- Fix the in-place text editor's overflowing toolbar: Apply and Cancel now have their own visible row. Preserve editing while the height field uses the window-owned field editor. Validate finite heights, support decimal commas, and commit pending text/font/height when saving the document.
- Revision history can sit above or inside the cartiglio, or be suppressed in favour of cartiglio fields only. Width, row height, independent visibility and offsets are configurable per sheet. Built-in cartigli reserve space for the integrated band. Native and portable plots share the same revision renderer.
- Choose a user's existing drawing block per sheet. Custom blocks support current revision date, description and author, plus indexed history fields. Empty indexed rows clear automatically when revisions are removed. Existing title-block blocks and per-sheet variables remain compatible.
- OPENINGSIZES (DOORWINDOWSIZES, QUOTAINFISSI) places live width × height labels on current-level BIM doors/windows, with configurable units and text height. Repeated commands update rather than duplicate labels. Automatic mode labels future openings; existing mark tags are retained and size labels use a different default position.
- Every document change supports Undo and uses existing extensible metadata, entities or variables. No schema change, format-version bump or migration is needed. Windows 1.0.5 is also built and tested; see the Windows validation below.

Validation:

- All 42 focused headless regression tests passed across OpeningSizeTests, SheetRevisionPresentationTests, SheetCustomizationTests, BIMCommandTests, EngineSheetsRecoveryTests, SectionSheetStyleTests, RenderSheetViewsTests, ViewportFramingTests and CommandRegistryTests. They cover live labels, automatic mode, unit conversion, idempotence, existing marks, command aliases and agent API, Undo, custom fields, revision placement, existing BIM commands, sheet rendering and file round-trip.
- An additional full serial core run recorded 803 passes and no failed test assertions before being interrupted during the existing long-running `IOInteropCorpusTests.testWriteDXFCorpusAndReadBack`. A complete full-suite pass is not claimed; the release regression set above completed independently.
- The signed universal app and the app mounted read-only from the final DMG each passed all **979 in-app checks**, with **1053 commands and zero missing UI entries**. These include actual toolbar bounds, changed font/height, Save with a pending edit, one-step Undo, and exact native/portable revision table geometry in each placement mode.
- Native UI verification: changed text, selected Times New Roman, entered height `325,5`, clicked Apply; the editor closed and the properties showed the new text and height 325.5.
- GUI and CLI contain arm64 and x86_64 slices. The GUI slices declare minimum macOS 14.0. Runtime validation ran on Apple silicon; physical Intel execution was not tested.
- App notarization accepted: `52641f6b-44dd-4f38-bdd4-c9113ac8c109`. DMG notarization accepted: `47e43a03-d659-41ce-b767-36976c2fe6e6`. Both tickets stapled; Gatekeeper accepted the app and DMG as Notarized Developer ID.

DMG: `Oanarina-Archi-Tool-1.0.5.dmg` (91,821,415 bytes).

SHA-256: `57e579f8304313557cad094647b8ecce86eefb2961c800fbe5c76e866c0d2db7`.

Italian guide: [TEXT-REVISIONS-OPENINGS-IT.md](TEXT-REVISIONS-OPENINGS-IT.md). Tutorial source: `tutorials/14-testi-revisioni-misure-it.tut`. Dry run and recorded run each completed with zero problems. The recording is 108.6 seconds, 1440 × 900, captioned in Italian, published as a 3.4 MB web video on the website.

The customer's own project was not provided. Verification and recording use the Cedar House sample and isolated regression documents. Website: https://www.oanarinaldi.com/archi-tool.html.

## Publication verification

Website commit `137bf0010f9061a7f4f1c1f9d18a452c7922b5ba` deployed successfully in [hosting run 40484554463](https://github.com/oanaunc/oanarina_website/actions/runs/40484554463). The live page shows Mac 1.0.5 build 12, the new revision controls, opening size labels and the Italian video. A complete HTTPS read of the live DMG matched the 91,821,415-byte notarized artifact and SHA-256 above. The Italian instructions, video, poster and updated user guide each returned HTTP 200. The original support conversation received an Italian reply with the update link and steps for all three requests after publication verification.

## Windows 1.0.5 (build 12)

The [Windows build 40482871629](https://github.com/oanaunc/archi_tool/actions/runs/40482871629), from fix commit `047fec402c996439df1506080dc59c25d1b9ceb6`, completed successfully. The release engine, isolated bundled-DLL launch, Electron shell, NSIS packaging, per-user installation and file associations, installed Explorer thumbnail handler, installed-app drawing/save/reopen/PDF smoke tests, uninstall, and all 19 Chromium shell test suites passed. The [immutable Windows release](https://github.com/oanaunc/archi_tool/releases/tag/windows-v1.0.5) contains the resulting installer and checksums. Portable engine CI for the same commit also passed on Windows and Linux.

Installer: `Oanarina-Archi-Tool-Setup-1.0.5.exe` (132,729,525 bytes), file version 1.0.5.12. SHA-256: `28c4c6a46f01c5fcdb9bd3bdb93c5fee24ac559e6d26aada87681b4e5917e254`. It remains unsigned. This is the Windows 10/11 x64 build; native arm64 engine execution is not claimed. The shared engine includes configurable revision history and live opening-size commands; Mac-specific in-place text controls remain native Mac UI.

The Windows website update (`846d026`) was included in the subsequent successful [hosting run 40501506053](https://github.com/oanaunc/oanarina_website/actions/runs/40501506053). The live page links Windows 1.0.5, and a complete HTTPS read of the hosted installer matched all 132,729,525 bytes and SHA-256 above. The existing unsigned-installer disclosure is retained.
