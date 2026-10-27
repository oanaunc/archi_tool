# Windows 1.0.7 (build 15)

27 October 2026. Follow-up to Mac 1.0.6 for hatch property matching/scaling, sheet titles and revision fields in custom cartigli.

- Retains the shared 1.0.6 engine corrections: immediate MATCHPROP painting, hatch-specific styles, transform origins and copied boundary references, dense patterns, sheet/model title controls and nested cartiglio fields.
- Windows source-object clicks bypass running snaps, matching the Mac object-pick behaviour. Destination selection queries the engine's region even between hatch strokes. Idle selection also falls back to the engine for sparse patterns, while empty-space clicks retain window selection.
- Portable grip scaling now uses the same transform service as SCALE and native Mac grips. This carries implicit hatch origins and remaps copied associative boundaries for the Windows grip API.
- Repair a regression test that assumed a particular order for copies returned from an unordered selection set. Copy assertions identify objects by geometry and still check boundary association, source preservation and visible strokes. The previous Windows/Linux CI failures were this order-dependent assertion; the Windows 1.0.6 installer workflow itself passed.

Local validation: 24 focused core tests passed, including seven customer-feedback regressions and the actual portable grips.typed API; the Windows Chromium canvas suite passed all 66 checks, including mouse-driven raw source picks and sparse target/idle selection. Installer, Windows/Linux CI and publication results will be recorded after verification. Mac website download remains the notarized 1.0.6 build 14; this release targets Windows.

An external-process check using the Windows JSON-RPC client and the updated portable engine passed all six base protocol checks and six customer-feedback checks: MA hatch transfer, SCALE origin, copied-boundary remapping through grips.typed, persisted sheet/model title suppression, custom cartiglio binding and PDF export. The exported PDF was extracted and rendered: the hidden title is absent and revision B / count 2 are present. This local check ran on macOS; the Windows installer and Windows/Linux CI results remain separate validation gates.

## Release validation

Source commit `272c82d4f90fe250deec9080176f93f4507a02f4` passed Windows app workflow [40532114080](https://github.com/oanaunc/archi_tool/actions/runs/40532114080) and portable engine workflow [40532115405](https://github.com/oanaunc/archi_tool/actions/runs/40532115405). All 1062 core tests passed on Windows and Linux. The Windows logs confirm per-user installation, file associations, Explorer thumbnail registration and rendering, all 22 installed-app smoke checks (including save/reopen and PDF), clean uninstallation and all 19 Chromium renderer suites. The installed file version is 1.0.7.15.

The published GitHub installer was read in full and checked against its release manifest and SHA256SUMS.txt: `Oanarina-Archi-Tool-Setup-1.0.7.exe`, 132,774,785 bytes, SHA-256 `b82bd1b5881e6b7d4b67f2ca4d206445f9cace14e0f319e28a349f10680fbda9`. It is unsigned. Public website publication and support reply are pending their separate checks.
