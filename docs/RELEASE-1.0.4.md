# Mac release 1.0.4 (build 10)

26 October 2026. Universal Apple silicon / Intel download, minimum macOS 14.

- **Customize Sheet** is a persistent side panel below the horizontally scrolling sheet toolbar. It exposes per-sheet visibility of the border, title block, automatic North, scale bar and automatic view captions, plus paper offsets for the title block, North and scale bar.
- **VPEDIT** (`VPE`, `VIEWPORTEDIT`) edits paper position, size, model centre and print scale independently. Centre Content preserves scale; Centre Frame on Page centres the frame on the whole page. Locked viewports reject edits. Choosing a scale from the existing Viewports menu now preserves its paper frame.
- **SHEETSTYLE** (`SHTSTYLE`, `SHEETCUSTOMIZE`) exposes Show/Hide/Move/Reset to the command line and scripting/agent command API.
- **SHEETTEXT** (`SHTTEXT`, `PAPERTEXT`) and the side panel add, edit, position and delete arbitrary multiline paper text, including text in the space left by the hidden North. These are paper entities, independent of model framing.
- **Edit Title Block** includes Office / studio to replace the standard app branding. **Redesign Cartiglio Drawing** creates a block for the current sheet when needed and opens its drawing in 2D; normal drawing tools and `BCLOSE Save` finish the edit. An existing shared block continues to update all sheets using it.
- Presentation is shared across native screen/PDF/SVG and portable plot output. Editing supports Undo and existing `.archi` persistence. The schema is unchanged: presentation uses the existing titleBlock dictionary, free text uses existing paper entities, and custom cartigli use existing block definitions/variables. No format-version bump or migration is needed.
- Universal distribution builds now explicitly retain macOS 14 in their linker flags by default, including website builds. This artifact was built with the standard `scripts/package.sh` command; universal builds now apply the explicit macOS 14 linker flags automatically.

Validation:

- 20 focused tests passed: SheetCustomizationTests, ViewportFramingTests, RenderSheetViewsTests, EngineSheetsRecoveryTests and SectionSheetStyleTests. They cover API commands/aliases, edits, locks, undo, file round-trip, free text and decoration output.
- 966 in-app checks passed on the signed universal app and on the app mounted read-only from the DMG, including native/portable decoration parity and standard/Retina sheet rendering. Command coverage: 1051 commands, zero missing UI entries.
- Both the GUI executable and archi-cli contain arm64 and x86_64 slices declaring macOS 14.0. Runtime checks ran on Apple silicon; Intel hardware execution was not tested here.
- App notarization accepted: `22151bdc-e59b-4aa1-8e2d-225944bd7805`. DMG notarization accepted: `8c47a036-9f33-418a-b6fa-98619ae60fc8`. Both tickets stapled; Gatekeeper accepted app and DMG as Notarized Developer ID.

DMG: `Oanarina-Archi-Tool-1.0.4.dmg` (91,750,221 bytes).

SHA-256: `8ed26337af32f37dbdff0f15dc4242deefc1626263d7708215f73a3d91783f2b`.

Italian instructions: [SHEET-CUSTOMIZATION-IT.md](SHEET-CUSTOMIZATION-IT.md). Tutorial source: `tutorials/13-personalizzare-sheet-it.tut`. Website: https://www.oanarinaldi.com/archi-tool.html.

The user's own project was not provided; the guide and recording use the Cedar House sample. The website's Windows download remains 1.0.2.

Video guide: https://youtu.be/7runIxmvS-E. Native GUI verification confirmed multiline text creation, persistent controls after edits, per-sheet cartiglio block editing and full sheet visibility with the panel open.
