# Mac release 1.0.3 (build 8)

Released 22 October 2026. Universal Intel and Apple silicon application; minimum macOS 14. No document schema or format-version change.

New rectangular and polygonal sheet viewports, and views dragged from the browser onto a sheet, centre on the content actually plotted in that level/view. Previously, whole-document plan extents could centre the viewport far from its displayed content when other levels or non-printing objects extended the drawing bounds. Existing 3D viewport framing is preserved.

For existing plan, ceiling, elevation or section viewports, choose **Viewports → the viewport → Fit Content (VPFIT)**, or run `VPFIT 1` (`VPF`, `FITVIEWPORT`). It centres and scales plotted content inside the existing paper frame, respects viewport layer freezes and locks, supports undo, and saves through the existing `.archi` fields. An empty view reports that its level and layer visibility/Plot settings need checking. This does not change a viewport to another level.

Validation completed:

- 23 focused core tests passed: `ViewportFramingTests`, `RenderSheetViewsTests`, `EngineSheetsRecoveryTests`, `SectionSheetStyleTests`, and `AnalysisAgentAPITests`. Coverage includes rectangular/polygonal creation, per-level and non-plotting extents, viewport freezes, fit, undo, locks, empty levels and file round-trip.
- 958 in-app checks passed on the signed universal app, and again on the app inside the read-only mounted final DMG. Sheet regression checks count rendered plan pixels at standard and Retina backing scales.
- Both executable architectures declare macOS 14.0 minimum. Runtime checks ran on Apple silicon. Intel execution could not be exercised on this machine because Rosetta is unavailable; the x86_64 binary is present.
- The earlier broad core-suite attempts were stopped during expensive debug texture decoding / optimized test compilation. The test results above describe the completed focused suites, not a completed full core-suite run.
- Bundle signatures verified; all regular bundle files are readable by installed users. Bundle packaging now normalizes resource read permissions before signing.
- The license-header check now reads four header lines, including the existing GPL remainder notice after the preserved ezdxf MIT attribution.
- Apple notarization accepted the app (`9ce5e33d-3561-48ef-a57c-cb97b21d9b0a`) and DMG (`abf4656a-79c9-467f-92a6-42caa3e55a25`). Tickets were stapled; Gatekeeper accepted both as Notarized Developer ID.

Final DMG: `Oanarina-Archi-Tool-1.0.3.dmg` (91,432,721 bytes).

SHA-256: `85ac4180a12c4a1c47cffdbde8ce019ca44b3cbfdbb45d9cf3b0d53293e31806`.

Implementation commit: `4fabf57d31706c30a2bacc86e3fe2d5cfd0e1767`. Download page: https://www.oanarinaldi.com/archi-tool.html. The website's Windows download remains 1.0.2.

This fixes a reproduced framing defect. The reported user's project was unavailable, so confirmation against that specific drawing remains outstanding.
