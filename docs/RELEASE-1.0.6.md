# Mac release 1.0.6 (build 14)

27 October 2026. Website update for the four hatch/sheet/cartiglio support reports.

- MATCHPROP / MA paints each target immediately and supports Remove without losing its original appearance. Hatch-specific origin, pattern type and gradient properties transfer while boundary references remain local. Native picking selects a sparse hatch between its strokes and uses unsnapped object-pick coordinates.
- SCALE / SC and native grip transforms carry implicit hatch origins, remap copied hatch boundary references, and detach independently transformed hatches. Dense line patterns thin their generated lines at the safety limit instead of disappearing.
- SHEETSTYLE Captions hides/moves both automatic captions and stored view-title entities. Customize Sheet provides the same control. SHEETTEXT / PAPERTEXT ListModel/HideModel/ShowModel and the native drawing-text selector hide a chosen model text only on one sheet and its PDF/SVG.
- TITLEBLOCKDESIGN / TBDESIGN Bind and Customize Sheet link existing custom cartiglio texts to automatic revision fields, including nested blocks. `{revision}` shows the revision code; `{revisionCount}` shows the numeric count. Empty manual revisions fall back to the latest code. Native and portable rendering share field resolution.
- Changes retain Undo and persist using existing entity/variable/titleBlock metadata. No document schema change or migration.

Validation before packaging: 97 focused headless tests passed, including six customer-feedback regressions, command aliases and agent API, live property painting, copy/scale association, dense patterns, stored/model-title visibility, nested fields, Undo and file round-trip. The native debug app passed all 988 checks, including sparse-pattern picking, hatch holes, grip scaling and native/portable field and title parity. Command coverage: 1053 commands, zero without a UI entry.

Guide: [HATCH-SHEET-REVISIONS-IT.md](HATCH-SHEET-REVISIONS-IT.md). Recording source: `tutorials/15-retini-titoli-revisioni-it.tut`. Dry run and the final recorded run completed with zero reported problems; the command log also confirms the correct text binding. The Italian video is 94.8 seconds at 1440 × 900. Its exported PDF was rendered and inspected: both hatches remain visible, the hidden plan/title texts are absent, and the cartiglio displays revision B and count 2. Packaging, signing, notarization and publication evidence will be recorded after verification. The customer's project was not provided; tests use isolated documents and samples.

## Signed distribution validation

- The final universal Developer ID app and the app mounted read-only from its DMG each passed **990 checks**, with 1053 commands and zero missing UI entries. Both GUI and CLI contain arm64 and x86_64 slices, each declaring minimum macOS 14.0. Runtime validation ran on Apple silicon; physical Intel execution was not tested.
- App notarization accepted: `f49cdf6e-7f11-4f4b-836a-01315a1cd032`. DMG notarization accepted: `9aa562fb-748c-45c5-8f63-f1c0e62502f4`. Both tickets stapled; Gatekeeper accepted the app and DMG as Notarized Developer ID.
- `Oanarina-Archi-Tool-1.0.6.dmg`: 92,118,660 bytes. SHA-256: `2794462acc2db2d7e9ff61c429f48f207205fbd459e509bc2f62dddee11dfba0`.
- The website video is 94.8 seconds, 1440 × 900, 3,378,335 bytes.
