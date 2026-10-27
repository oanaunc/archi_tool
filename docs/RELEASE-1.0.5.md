# Mac release 1.0.5 (build 12)

27 October 2026. Universal Apple silicon / Intel download; minimum macOS 14.

- Fix the in-place text editor's overflowing toolbar: Apply and Cancel now have their own visible row. Preserve editing while the height field uses the window-owned field editor. Validate finite heights, support decimal commas, and commit pending text/font/height when saving the document.
- Revision history can sit above or inside the cartiglio, or be suppressed in favour of cartiglio fields only. Width, row height, independent visibility and offsets are configurable per sheet. Built-in cartigli reserve space for the integrated band. Native and portable plots share the same revision renderer.
- Choose a user's existing drawing block per sheet. Custom blocks support current revision date, description and author, plus indexed history fields. Empty indexed rows clear automatically when revisions are removed. Existing title-block blocks and per-sheet variables remain compatible.
- OPENINGSIZES (DOORWINDOWSIZES, QUOTAINFISSI) places live width × height labels on current-level BIM doors/windows, with configurable units and text height. Repeated commands update rather than duplicate labels. Automatic mode labels future openings; existing mark tags are retained and size labels use a different default position.
- Every document change supports Undo and uses existing extensible metadata, entities or variables. No schema change, format-version bump or migration is needed. Windows remains at its separately tested 1.0.4 installer.

Validation and signing evidence will be recorded after release checks finish.
