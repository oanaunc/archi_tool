# Door and window tag repair — 1.0.11 (21)

- Bulk opening sizes include openings shown through walls spanning levels, with separate tags on each plan. Existing size tags on another level no longer suppress the displayed plan's labels. `OPENINGSIZES` / `QUOTAINFISSI Reposition` restores default label positions and creates missing tags; All/Doors/Windows retain manual positions.
- COPY and shared mirror/array/grip transforms remap tag references to copied elements. Clipboard selections containing host walls and tags also remap their hosted opening references. Tag-only copies in the same drawing rebind when the transformed leader anchor is within 100 mm of exactly one other opening of the same category on the current level; unmatched or ambiguous destinations retain the source reference.
- `TAGLABEL` / `EDITLABEL` / `TAGFORMAT Rehost` explicitly repairs a previously copied tag. Its native/Windows command UI and agent API retain formatting and position, clear manual text overrides and resume live values from the chosen element.
- Undo/Redo and save/reopen use existing properties. Document format remains 6. [Italian instructions](DOOR-TAG-REPAIR-IT.md).

The customer's original drawing was not supplied. Regression documents reproduce the copy-reference defect and skipped spanning-wall openings; the specific cause of every missing tag in that drawing cannot be confirmed without it. Distribution and publication checks will be recorded after completion.

Initial verification: 13 focused opening/label tests passed, including spanning-wall plan coverage, tag-only and opening/tag copies, clipboard wall/tag copies, portable API rehosting, Undo/Redo and file round-trip. Full-suite and distribution checks are in progress.
