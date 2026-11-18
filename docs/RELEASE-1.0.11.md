# Door and window tag repair — 1.0.11 (21)

- Bulk opening sizes include openings shown through walls spanning levels, with separate tags on each plan. Existing size tags on another level no longer suppress the displayed plan's labels. `OPENINGSIZES` / `QUOTAINFISSI Reposition` restores default label positions and creates missing tags; All/Doors/Windows retain manual positions.
- COPY and shared mirror/array/grip transforms remap tag references to copied elements. Clipboard selections containing host walls and tags also remap their hosted opening references. Tag-only copies in the same drawing rebind when the transformed leader anchor is within 100 mm of exactly one other opening of the same category on the current level; unmatched or ambiguous destinations retain the source reference.
- `TAGLABEL` / `EDITLABEL` / `TAGFORMAT Rehost` explicitly repairs a previously copied tag. Its native/Windows command UI and agent API retain formatting and position, clear manual text overrides and resume live values from the chosen element.
- Undo/Redo and save/reopen use existing properties. Document format remains 6. [Italian instructions](DOOR-TAG-REPAIR-IT.md).

The customer's original drawing was not supplied. Regression documents reproduce the copy-reference defect and skipped spanning-wall openings; the specific cause of every missing tag in that drawing cannot be confirmed without it. Distribution and publication checks will be recorded after completion.

## Verification

- Thirteen focused opening/label tests passed, including spanning-wall plan coverage, tag-only and opening/tag copies, clipboard wall/tag copies, portable API rehosting, Undo/Redo and file round-trip. The final full-suite run also includes ambiguity and copied upper-plan tag checks.
- The native debug and signed universal release apps each passed **1,002 checks**, including copied-tag live rendering. All **1,053 commands** have a UI entry.
- The actual Windows JSON-RPC client against the final debug and optimized release engines passed six protocol checks and five tag checks: door/tag copy remapping, explicit rehosting, Undo, independent live sizes after save/reopen and Reposition restoring automatic labels.

- All **1,076 local core tests passed**. Both GUI and CLI contain Apple silicon and Intel slices with minimum macOS 14.0. Runtime checks ran on Apple silicon; physical Intel execution was not tested.

## Mac distribution

- Apple accepted the app (`be655a41-b583-4ce3-9837-52bd9b2496a5`) and DMG (`d69359c4-9c29-493b-bdcd-f44531e427d2`). Both tickets are stapled; Gatekeeper accepted both as Notarized Developer ID.
- The app mounted read-only from the final DMG passed **1,002 native checks**, with all **1,053 commands** reachable from the UI.
- `Oanarina-Archi-Tool-1.0.11.dmg`: **92,705,051 bytes**, SHA-256 `1d0b28f74b47cb38ef798720902e8059bcdb80b3ff1af03024de3c11797baf23`.

Windows distribution and publication checks are in progress.
