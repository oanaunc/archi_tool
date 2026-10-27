# Mac release 1.0.6 (build 14)

27 October 2026. Website update for the four hatch/sheet/cartiglio support reports.

- MATCHPROP / MA paints each target immediately and supports Remove without losing its original appearance. Hatch-specific origin, pattern type and gradient properties transfer while boundary references remain local. Native picking selects a sparse hatch between its strokes and uses unsnapped object-pick coordinates.
- SCALE / SC and native grip transforms carry implicit hatch origins, remap copied hatch boundary references, and detach independently transformed hatches. Dense line patterns thin their generated lines at the safety limit instead of disappearing.
- SHEETSTYLE Captions hides/moves both automatic captions and stored view-title entities. Customize Sheet provides the same control. SHEETTEXT / PAPERTEXT ListModel/HideModel/ShowModel and the native drawing-text selector hide a chosen model text only on one sheet and its PDF/SVG.
- TITLEBLOCKDESIGN / TBDESIGN Bind and Customize Sheet link existing custom cartiglio texts to automatic revision fields, including nested blocks. `{revision}` shows the revision code; `{revisionCount}` shows the numeric count. Empty manual revisions fall back to the latest code. Native and portable rendering share field resolution.
- Changes retain Undo and persist using existing entity/variable/titleBlock metadata. No document schema change or migration.

Validation before packaging: 97 focused headless tests passed, including six customer-feedback regressions, command aliases and agent API, live property painting, copy/scale association, dense patterns, stored/model-title visibility, nested fields, Undo and file round-trip. The native debug app passed all 988 checks, including sparse-pattern picking, hatch holes, grip scaling and native/portable field and title parity. Command coverage: 1053 commands, zero without a UI entry.

Guide: [HATCH-SHEET-REVISIONS-IT.md](HATCH-SHEET-REVISIONS-IT.md). Recording source: `tutorials/15-retini-titoli-revisioni-it.tut`. Packaging, signing, notarization and publication evidence will be recorded after verification. The customer's project was not provided; tests use isolated documents and samples.
