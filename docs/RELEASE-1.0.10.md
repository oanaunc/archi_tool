# Save and close the block editor — 1.0.10 (19)

- Mac and Windows show **Save and Close Block** above the canvas while editing a block. It applies changes to every instance of the block and returns to the previous drawing view or sheet.
- `BCLOSE Save` or `BC S` does the same from the command line and scripting API. `BCLOSE Discard` discards changes since the last block save. Undo reopens the edit session.
- Use Cmd+S on Mac or Ctrl+S on Windows to write the updated `.archi` file. The document format is unchanged.

## Mac distribution

- The Developer ID app and the app mounted from the DMG each passed 1,000 native checks. All 1,053 commands have a UI entry. Both the Intel and Apple silicon slices declare macOS 14.0. The native desktop test on Apple silicon opened a block from Sheet 1, added geometry, then used the new button while `LINE` was active. The command cancelled, the geometry saved, and Sheet 1 returned.
- Apple accepted and stapled the app (`8df71121-3479-48e9-87fe-103d07d1a0f5`) and DMG (`ef534e26-78f5-4bee-a124-169954e2ae0e`). Gatekeeper accepted both. The DMG is 92,108,613 bytes with SHA-256 `d5b664d7bd73e8deb9f6c62ba60da599b72b8bb99fa2a9ccc0908bb50fb419fc`.
- Mac App Store version **1.0.10 (20)** passed sandbox-preview, packaging, signature, profile and archive-symbol checks. Xcode confirmed upload at 18:08 Europe/Bucharest on 17 November 2026. [Build 20 in TestFlight](https://appstoreconnect.apple.com/teams/54f57056-d9bb-4a38-aad1-31c9a6ba5707/apps/6823133541/testflight/macos/8547c2d6-1883-4f7b-a5e5-f81fb757b100) shows **Ready to Submit**.
- Website commit `ce083aa` deployed through [run 44122891723](https://github.com/oanaunc/oanarina_website/actions/runs/44122891723). The complete DMG retrieved from the [public download page](https://www.oanarinaldi.com/archi-tool.html) matched the verified artifact byte for byte. The Italian instructions and feature catalogue are live.
