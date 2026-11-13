# Opening dimensions and tag scale — 1.0.9 (18)

- `DOOR`, `WINDOW` and `OPENING` convert stock dimensions and frame thickness to the drawing's units. Prompts show the current unit and accept explicit suffixes such as `900mm`. Use `DOOR ReSet` to clear dimensions remembered from older versions. The scripting helpers also use drawing units for defaults.
- Stock opening types use the same dimensions as placement. Legacy stock catalog entries in non-mm files are corrected when opened. Existing door geometry and custom catalog entries are preserved. The `.archi` format remains version 6.
- New door/window tags use a compact text height equivalent to 100 mm in the model (10 cm in a cm drawing). Size labels default to Drawing units; explicit units and custom text heights remain available. Existing tags can be updated with `QUOTAINFISSI` or Properties.

See the [Italian instructions](DOOR-UNITS-IT.md) for existing drawings and the [user guide](USER-GUIDE.md) for commands.

## Release verification

- Fix: [`e1d4f8d`](https://github.com/oanaunc/archi_tool/commit/e1d4f8d3eef103a1f9f7fb5e0d971cb2d40a44ee). The debug and release engine verified centimeter placement, compact mark and size tags, editing width in Properties, live PDF output and save/reopen.
- The universal Developer ID app and the app mounted from the final DMG each passed 997 native checks. All 1053 commands have a UI entry. Both Apple silicon and Intel slices declare macOS 14.0; the runtime checks ran on Apple silicon.
- Apple accepted and stapled both the app (`3d87b971-d0f9-4d55-84c5-cacdf586446e`) and DMG (`5cb895b0-c2b9-4242-b674-0a68e21107d4`), and Gatekeeper accepted both. `Oanarina-Archi-Tool-1.0.9.dmg`: 92,139,844 bytes, SHA-256 `d87fb655b7b849b2968a78f5707fec68a8730e4156a441b89e941e3620d29c33`.
- [Windows installer workflow](https://github.com/oanaunc/archi_tool/actions/runs/43447847913) and [Windows/Linux core workflow](https://github.com/oanaunc/archi_tool/actions/runs/43447847905) cover the same fix commit.
- The Windows installer passed packaging, per-user installation, Explorer thumbnails, installed app smoke checks, uninstall, and the Chromium UI suites. The release step succeeded before the job was superseded during the final log publishing step. The [Windows release](https://github.com/oanaunc/archi_tool/releases/tag/windows-v1.0.9) installer is unsigned, file version 1.0.9.18, 132,795,875 bytes, SHA-256 `96e01754d2e67e86699d746ed135e49689d486e15102db4cceccde34f06b8ccb`.
- Local macOS: 1,070 core tests and nine focused release tests passed. Linux: all 1,069 core tests passed. On Windows the nine opening tests passed; the first portable run had one failure in the independent script pause/resume test. A [test-only timing correction](https://github.com/oanaunc/archi_tool/commit/7537aaeb3b07896323bda08653f6a1240189f84a) passed with the nine opening tests locally and triggered a [portable rerun](https://github.com/oanaunc/archi_tool/actions/runs/43456973708). The shipped app sources are identical.

## Publication and delivery

Both installers were published on 13 November 2026 at [the public download page](https://www.oanarinaldi.com/archi-tool.html). Website commit `b776a06` deployed successfully in [run 43457988322](https://github.com/oanaunc/oanarina_website/actions/runs/43457988322). Complete HTTPS reads of both public installers matched the verified byte counts and SHA-256 values. The English and Italian instructions and public checksum file were verified before sending the Italian reply in the original support thread. Gmail confirmed message `1a1d5a483de0ff04` as sent.
