# Door/window label repair — 1.0.8

5 November 2026. English macOS and Windows applications; website builds use build 16, the separate sandboxed Mac App Store candidate uses build 17.

- Editing a live door/window label's Content now creates an explicit annotation override. Properties, the native in-place editor, TEXTEDIT / ED / DDEDIT, SETPROP and the portable Windows panel use the same displayed value. The bubble and leader are retained. Editing annotation text does not resize the underlying opening.
- Automatic labels remain live when their font/height changes. Properties exposes Label Mode; setting Automatic, or TAGLABEL / EDITLABEL / TAGFORMAT > Automatic, restores model values. Choosing a new Field/Label or explicitly rerunning OPENINGSIZES refreshes the automatic label.
- TAGALL now distinguishes mark labels from size/type labels, so existing opening dimensions no longer block adding references. TAGLABEL > Field > mark converts existing bubbles to references; actual door Mark properties can be D1, D2, D3. MARKS Renumber retains its existing D01/D02 convention.
- Undo/Redo and .archi persistence use the existing extensible props dictionary; document format and compatibility are unchanged. Updated English user-guide instructions, [Italian customer steps](DOOR-LABELS-IT.md), and existing feature entries.

Initial validation: 14 focused core tests passed, including manual/automatic rendering, save/reopen, Undo/Redo, aliases, mark conversion, and the actual portable panel.set API. Native app checks, release packaging, notarization, Windows CI, hosting and Apple submission results will be recorded after verification. The customer's original project was not supplied; regression documents reproduce the screenshot's edit.


Local native validation passed all **997 app checks** with **1053 commands and zero missing UI entries**. This includes the actual in-place tag editor, displayed-value initialization, formatting without freezing automatic labels, manual dimensions, shared render output and one-step Undo. An external process driven by the Windows JSON-RPC client passed its six base checks and four label checks: panel edit persistence, rendered dimensions, portable PDF export and restoring automatic values. Extracted PDF text contains `900x2100`. Eight App Store packaging regression tests passed. Local runtime tests ran on Apple silicon; Windows CI and release-channel results remain pending.


## Mac distribution verified

The universal Developer ID app and the app mounted read-only from the final DMG each passed **997 checks**, with 1053 commands and zero missing UI entries. Both arm64 and x86_64 binaries declare minimum macOS 14.0. Apple notarization accepted the app (`550a485f-ce3e-441a-83f9-a60d7b5ed53e`) and DMG (`df8bc151-e436-403b-be4f-92d1a2c45834`); both tickets were stapled and Gatekeeper accepted both artifacts as Notarized Developer ID.

`Oanarina-Archi-Tool-1.0.8.dmg`: **92,098,631 bytes**, SHA-256 `c74103b76de70cf7fb7ff99ab81810aac03d3c76283ff3788446e1c16627edeb`.

The separate sandbox preview **1.0.8 (17)** passed all 997 app checks and 17 sandbox checks. Distribution app/installer signatures, profile/certificate matching and both universal dSYM UUID sets passed. Xcode reported **Upload succeeded** / **EXPORT SUCCEEDED** on 5 November 2026 at 18:24 Europe/Bucharest. Processing and review selection remain pending; upload alone is not review submission. The release engine also passed the external Windows-client label/PDF checks. Website artifact staging commit: `6031862`; hosting and public-file verification are still pending.


## Verified hosting and Apple submission

Website artifact commit `6031862` deployed successfully in [hosting run 42064587411](https://github.com/oanaunc/oanarina_website/actions/runs/42064587411). A complete HTTPS read of the public DMG matched all 92,098,631 bytes and its SHA-256. The Italian door-label/reference instructions returned HTTP 200. The release page still advertises the previous downloads pending Windows validation and the final page update.

Apple processed **1.0.8 (17)** as Ready to Submit. The old waiting 1.0.5 (13) submission was cancelled, version/English description/reviewer notes were saved, build 17 was selected and saved, and Add for Review passed. **Submit for Review** returned **1 Item Submitted** at **18:31 Europe/Bucharest**. [Submission 273fc32d-9834-4ddc-8b7c-ab0b45d16379](https://appstoreconnect.apple.com/apps/6823133541/distribution/reviewsubmissions/details/273fc32d-9834-4ddc-8b7c-ab0b45d16379) visibly confirms **Waiting for Review** for both the submission and **macOS App 1.0.8 (17)**. Automatic release after approval and the existing sandbox entitlement explanation remain selected/saved. No new reviewer message was sent. Approval and public App Store availability remain pending.


The Windows portable-engine job in [CI run 42061721473](https://github.com/oanaunc/archi_tool/actions/runs/42061721473) completed successfully from fix commit `b5ca1f51ca03b50d992d54a0020bc6de0eaace48`: **all 1065 core tests passed on Windows**, including the new opening-label regressions. The Linux job and the separate Windows installer workflow are still running.
