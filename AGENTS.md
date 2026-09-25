# Project instructions

- This is Oanarina Archi Tool, a native macOS architecture/CAD/BIM application. Accent color: yellow (#F5C518) on a neutral dark workspace.
- Commit and push every step to `git@github.com:oanaunc/archi_tool.git` on `main`.
- Source lives in `app/` (Swift package). `ArchiCore` must stay free of AppKit/SwiftUI/SceneKit so it can be tested headless; UI goes in `ArchiApp`.
- `other_projects/` are reference checkouts: never modify or publish them. License is GPL-3.0-or-later; when adapting code from a reference project, keep its copyright notice in the file header and add it to `docs/THIRD-PARTY.md`. Do not copy code from non-free software.
- Work the backlog in `docs/FEATURE-REGISTER.md` / `docs/features.json`. Mark a feature `done` only when it has a working command, UI entry (menu/ribbon/command line), undo, file persistence where applicable, and a test.
- Every command must be reachable from the command line (AutoCAD-style name and alias) and from the scripting/agent API.
- Preserve `.archi` document compatibility: bump `formatVersion` and add migration when the schema changes.
- The companion website is `/Users/oanarinaldi/Desktop/oanarina_website`, page `archi-tool.html`, linked from the Apps menu on every standard page. List only implemented capabilities there.
- Do not publish a download as notarized unless notarization and Gatekeeper checks succeeded.
