# Door and window tag repair — 1.0.11 (21)

- Bulk opening sizes include openings shown through walls spanning levels, with separate tags on each plan. Existing size tags on another level no longer suppress the displayed plan's labels. `OPENINGSIZES` / `QUOTAINFISSI Reposition` restores default label positions and creates missing tags; All/Doors/Windows retain manual positions.
- COPY and shared mirror/array/grip transforms remap tag references to copied elements. Clipboard selections containing host walls and tags also remap their hosted opening references. Tag-only copies in the same drawing rebind when the transformed leader anchor is within 100 mm of exactly one other opening of the same category on the current level; unmatched or ambiguous destinations retain the source reference.
- `TAGLABEL` / `EDITLABEL` / `TAGFORMAT Rehost` explicitly repairs a previously copied tag. Its native/Windows command UI and agent API retain formatting and position, clear manual text overrides and resume live values from the chosen element.
- Undo/Redo and save/reopen use existing properties. Document format remains 6. [Italian instructions](DOOR-TAG-REPAIR-IT.md).

The customer's original drawing was not supplied. Regression documents reproduce the copy-reference defect and skipped spanning-wall openings; the specific cause of every missing tag in that drawing cannot be confirmed without it.

## Verification

- Thirteen focused opening/label tests passed, including spanning-wall plan coverage, tag-only and opening/tag copies, clipboard wall/tag copies, portable API rehosting, Undo/Redo and file round-trip. The final full-suite run also includes ambiguity and copied upper-plan tag checks.
- The native debug and signed universal release apps each passed **1,002 checks**, including copied-tag live rendering. All **1,053 commands** have a UI entry.
- The actual Windows JSON-RPC client against the final debug and optimized release engines passed six protocol checks and five tag checks: door/tag copy remapping, explicit rehosting, Undo, independent live sizes after save/reopen and Reposition restoring automatic labels.
- All **1,076 local core tests passed**. Both GUI and CLI contain Apple silicon and Intel slices with minimum macOS 14.0. Runtime checks ran on Apple silicon; physical Intel execution was not tested.

## Mac distribution

- Apple accepted the app (`be655a41-b583-4ce3-9837-52bd9b2496a5`) and DMG (`d69359c4-9c29-493b-bdcd-f44531e427d2`). Both tickets are stapled; Gatekeeper accepted both as Notarized Developer ID.
- The app mounted read-only from the final DMG passed **1,002 native checks**, with all **1,053 commands** reachable from the UI.
- `Oanarina-Archi-Tool-1.0.11.dmg`: **92,705,051 bytes**, SHA-256 `1d0b28f74b47cb38ef798720902e8059bcdb80b3ff1af03024de3c11797baf23`.

## Windows and portable engine

- [Windows installer workflow 44346373566](https://github.com/oanaunc/archi_tool/actions/runs/44346373566) succeeded for source commit `4918470`. Release-engine bundling and DLL isolation, Electron shell, Explorer thumbnail handler, NSIS packaging, per-user installation and associations, Explorer thumbnails, **23 installed-app smoke checks**, uninstall and **all 19 Chromium UI suites** passed. No UI suite was skipped.
- [Portable engine workflow 44345872893](https://github.com/oanaunc/archi_tool/actions/runs/44345872893) passed **1,074 core tests on Windows and 1,074 on Linux**. It tested commit `674b8ef`, whose ArchiCore and core test sources are identical to the delivered Windows source commit.
- The [Windows release](https://github.com/oanaunc/archi_tool/releases/tag/windows-v1.0.11) is unsigned, file version **1.0.11.21**, **132,812,526 bytes**, SHA-256 `64ffac516075c9680ee6369c5b27ba265c50e230ba977b81e9498fc58c0b3231`.

## Publication

The notarized Mac artifact was staged in website commit `59ed605` and deployed successfully in [hosting run 44349817171](https://github.com/oanaunc/oanarina_website/actions/runs/44349817171). A complete HTTPS download matched its verified byte count and SHA-256. The final [release page](https://www.oanarinaldi.com/archi-tool.html), English guide, Italian repair instructions and Windows checksum were published in website commit **`0b90383`**, deployed successfully in [hosting run 44366552900](https://github.com/oanaunc/oanarina_website/actions/runs/44366552900). Complete HTTPS reads of both live download links matched every verified byte and SHA-256 above. The guide, checksum file and implemented-feature explorer data also passed live verification. Local browser checks confirmed both new download links and working feature search.

After publication and verification, Nicola received one Italian reply in his original support conversation, with the download link, installation steps, `QUOTAINFISSI Reposition Centimetres 10`, explicit `TAGLABEL` → Rehost instructions and project saving. Gmail confirmed message **`1a1efdd14616acc5`**, thread `1a11ff8507e06936`, with the **SENT** label. The reply asks for a small `.archi` example if any opening still lacks a tag, since the original drawing was not supplied.

## Mac App Store update — 25 November 2026

Apple’s public US listing still reports 1.0.8. The new store candidate **1.0.11 (22)** passed 1,002 native checks, all 17 sandbox checks and eight packaging tests. App/installer distribution signatures, profile/certificate matching and universal preview/distribution/debug-symbol UUIDs passed. Xcode upload is in progress; final review submission requires restored App Store Connect browser sign-in.
