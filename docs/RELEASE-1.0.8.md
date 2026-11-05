# Door/window label repair — 1.0.8

5 November 2026. English macOS and Windows applications; website builds use build 16, the separate sandboxed Mac App Store candidate uses build 17.

- Editing a live door/window label's Content now creates an explicit annotation override. Properties, the native in-place editor, TEXTEDIT / ED / DDEDIT, SETPROP and the portable Windows panel use the same displayed value. The bubble and leader are retained. Editing annotation text does not resize the underlying opening.
- Automatic labels remain live when their font/height changes. Properties exposes Label Mode; setting Automatic, or TAGLABEL / EDITLABEL / TAGFORMAT > Automatic, restores model values. Choosing a new Field/Label or explicitly rerunning OPENINGSIZES refreshes the automatic label.
- TAGALL now distinguishes mark labels from size/type labels, so existing opening dimensions no longer block adding references. TAGLABEL > Field > mark converts existing bubbles to references; actual door Mark properties can be D1, D2, D3. MARKS Renumber retains its existing D01/D02 convention.
- Undo/Redo and .archi persistence use the existing extensible props dictionary; document format and compatibility are unchanged. Updated English user-guide instructions and existing feature entries.

Initial validation: 14 focused core tests passed, including manual/automatic rendering, save/reopen, Undo/Redo, aliases, mark conversion, and the actual portable panel.set API. Native app checks, release packaging, notarization, Windows CI, hosting and Apple submission results will be recorded after verification. The customer's original project was not supplied; regression documents reproduce the screenshot's edit.
