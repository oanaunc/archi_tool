# Oanarina Archi Tool — GPL-3.0-or-later
# Rules for parity_audit.py (rounds 2-3): windows that exist on Windows (with the files that implement them), menus the Windows shell writes by
# hand (File, Edit, View, Window, Help, app menu), status bar, shortcuts, render features and theme. Evidence from code
# reading of windows/src at the round-2 audit (27 Sep 2026).

W = "renderer/"
WINDOWS = {
    # panels
    "Properties": ("done", [W + "ui/panels.ts"], ""),
    "Layers": ("done", [W + "dialogs/layers-panel.ts"], ""),
    "Levels": ("done", [W + "ui/panels.ts"], ""),
    "Browser": ("partial", [W + "ui/panels.ts"], "only Floor Plans, 3D Views (Front/Aerial/Corner) and Sheets"),
    "Materials": ("done", [W + "partb/materials.ts"], ""),
    "Tools": ("done", [W + "canvas/tool-palette.ts"], ""),
    "Sheets": ("done", [W + "partb/sheets.ts"], ""),
    "History": ("partial", [W + "ui/panels.ts"], "undo list, redo and command history; no page picker, Copy Log or numbered undo steps"),
    "Selection": ("partial", [W + "ui/panels.ts"], "summary and type counts only; no Only / Remove / Zoom buttons"),
    "Navigator": ("todo", [], "placeholder text only"),
    "Alerts": ("todo", [], "placeholder 'No alerts.' only"),
    "Quick Props": ("partial", [W + "ui/panels.ts"], "shows the Properties panel; no floating Quick Properties window"),
    "Inspector": ("partial", [W + "ui/panels.ts"], "shows the Properties panel; no raw inspector / Copy"),
    "Content": ("todo", [], "shows the static tool list, not the DesignCenter content browser"),
    # dialogs
    "UnitsSheet": ("done", [W + "dialogs/units.ts"], ""),
    "DraftingSettingsSheet": ("done", [W + "dialogs/units.ts"], ""),
    "ScheduleSheet": ("todo", [], "SCHEDULE has no schedule sheet on Windows"),
    "CommandReferenceView": ("partial", [W + "dialogs/shortcuts.ts"], "Help ▸ Command Reference runs COMMANDREFERENCE on the command line; no searchable window"),
    "ShortcutsView": ("done", [W + "dialogs/shortcuts.ts"], ""),
    "QuickSelectSheet": ("done", [W + "dialogs/quickselect.ts"], ""),
    "LayerStatesSheet": ("done", [W + "dialogs/layerstates.ts"], ""),
    "PageSetupSheet": ("done", [W + "dialogs/pagesetup.ts"], ""),
    "TitleBlockSheet": ("done", [W + "partb/sheets.ts"], ""),
    "ConnectClaudeSheet": ("done", [W + "partb/agents.ts"], ""),
    "SaveCameraSheet": ("done", [W + "view3d/extras.ts", W + "view3d/view3d.ts"], ""),
    "SpellingSheet": ("todo", [], "SPELLDIALOG not ported"),
    "PlotStyleSheet": ("done", [W + "output/plot.ts", W + "output/publish.ts", W + "output/render.ts"], ""),
    "BatchPublishSheet": ("done", [W + "output/publish.ts"], ""),
    "About": ("todo", [], "ABOUT is not registered in archi-engine and the shell has no About window"),
    "Assistant": ("todo", [], "ASSISTANT (AI assistant window) not ported"),
    "BlockLibrary": ("done", [W + "partb/block-library.ts"], ""),
    "CUI": ("done", [W + "dialogs/cui.ts"], ""),
    "CameraPath": ("done", [W + "output/camera-paths.ts"], ""),
    "Compare": ("done", [W + "partb/review.ts"], ""),
    "Customizer": ("done", [W + "partb/customizer.ts"], ""),
    "FamilyEditor": ("done", [W + "partb/family-editor.ts"], ""),
    "GraphPlayer": ("done", [W + "partb/node-editor.ts"], ""),
    "GraphicStyles": ("todo", [], "GRAPHICSTYLES (line styles, pens, graphic override rules) not ported"),
    "Markup": ("done", [W + "partb/review.ts"], ""),
    "MaterialLibrary": ("done", [W + "partb/materials.ts"], ""),
    "NodeEditor": ("done", [W + "partb/node-editor.ts"], ""),
    "Outliner": ("todo", [], "OUTLINERPANEL not ported"),
    "PathTrace": ("done", [W + "output/path-trace.ts"], ""),
    "PlotPreview": ("done", [W + "output/plot.ts"], ""),
    "Preferences": ("done", [W + "dialogs/preferences.ts"], ""),
    "PrintSetup": ("done", [W + "output/plot.ts"], ""),
    "RenderQueue": ("done", [W + "output/render-queue.ts"], ""),
    "RevisionCloud": ("done", [W + "partb/review.ts"], ""),
    "Versions": ("todo", [], "FILEVERSIONS not ported"),
    "Start Screen": ("done", [W + "ui/start.ts"], ""),
    "Command Search": ("done", [W + "main.ts"], ""),
}

# A panel whose tab exists but shows a placeholder.
_orig_cmd_ok = cmd_ok
def cmd_ok(c, names=(), ui=None):
    if c and c.startswith("@panel:") and c[7:] in ("Navigator", "Alerts", "Content"): return "partial", "panel tab opens a placeholder"
    return _orig_cmd_ok(c, names, ui)

# ---- ribbon chrome ----
CHROME = [
    ("Tab bar ▸ app icon (About)", ("todo", "runs ABOUT, which archi-engine does not register (no About window)")),
    ("Tab bar ▸ quick access toolbar", ("done", "")),
    ("Tab bar ▸ Search commands (Ctrl+K)", ("done", "")),
    ("Tab bar ▸ Clean screen (Ctrl+0)", ("done", "")),
    ("Tab bar ▸ Hide panels / Show panels", ("done", "")),
    ("Tab bar ▸ Collapse the ribbon", ("done", "")),
]

# Ribbon labels and views (RibbonView custom items)
for p_, s_ in [("Annotate ▸ Style ▸ Dimension style (label)", "done"), ("Annotate ▸ Style ▸ Text height: {fmt(model.editor.settings.textHeight, 2)} (label)", "done"),
               ("View ▸ Visual Style ▸ Applies to the 3D viewport (label)", "done"), ("Script ▸ AI Agents ▸ Listening / Stopped (label)", "done"),
               ("Script ▸ AI Agents ▸ 127.0.0.1:{AgentServer.shared.port} (label)", "done")]:
    ov(p_, s_)
ov("Annotate ▸ Style ▸ {model.doc.currentDimStyle}", "done")  # the dim-style drop-down
ov("Script ▸ AI Agents ▸ Copy token", "done")

# ---- hand-written Windows menus (titlebar.ts): File, Edit, View, Window, Help; no app menu ----
MISSING = "partial: works from the ribbon / command line, but the Windows %s menu has no such entry"
def mis(p_, menu): ov(p_, "partial", "command works from the ribbon / command line; the Windows %s menu has no entry" % menu)

A = "Oanarina Archi Tool ▸ "
ov("Menu Oanarina Archi Tool", "partial", "no app menu on Windows (by convention); Settings is Edit ▸ Options, Quit is File ▸ Exit, About is under Help")
ov(A + "About Oanarina Archi Tool", "todo", "Help ▸ About runs ABOUT, which archi-engine does not register")
ov(A + "Settings…", "done")
ov(A + "Agent Server…", "partial", "AGENTSETTINGS works (Settings ▸ Agents) but no Windows menu entry")
ov(A + "Hide Oanarina Archi Tool", "n/a (macOS only)")
ov(A + "Hide Others", "n/a (macOS only)")
ov(A + "Quit Oanarina Archi Tool", "done")

F = "File ▸ "
ov("Menu File", "partial", "hand-written Windows File menu: New/Open/Save/Import/Export/Page Setup/Print/Close/Exit only")
for t_ in ["New Drawing", "New from Template", "New from Template ▸ Metric Drawing (mm)", "New from Template ▸ Imperial Drawing (in)",
           "New from Template ▸ Building (levels, grid, sheets)", "New from Template ▸ {TemplateLibrary.all().filter() {…}}",
           "New from Template ▸ Save Drawing as Template…", "New from Template ▸ Show Templates Folder", "New from Template ▸ Sample House",
           "Open…", "Close", "Save", "Save As…", "Import…", "Export", "Export ▸ PDF…", "Export ▸ DXF…", "Export ▸ SVG…", "Export ▸ OBJ + MTL…",
           "Export ▸ STL…", "Export ▸ glTF Binary (GLB)…", "Export ▸ IFC4…", "Page Setup…", "Plot / Print…"]:
    ov(F + t_, "done")
ov("File ▸ Export", "partial", "PDF/DXF/SVG/IFC/OBJ/STL/GLB only; PNG fails and GeoJSON, Points, 3MF, USDZ, DXF R12, Schedules are missing")
ov(F + "Open Recent", "todo", "no Open Recent submenu (recent files only on the start screen and the taskbar jump list)")
ov(F + "Open Recent ▸ Clear Menu", "todo", "")
for t_ in ["Import File", "IFC", "SVG", "Mesh (OBJ/STL)", "GeoJSON", "Points (CSV)", "Insert Block", "Create Block", "Xref", "Image", "Attribute", "Paste Special"]:
    mis(F + "Insert ▸ " + t_, "File")
ov(F + "Insert", "partial", "no File ▸ Insert submenu on Windows; the commands work from the Insert ribbon tab")
ov(F + "Export ▸ PNG (300 dpi)…", "todo", "Windows File ▸ Export ▸ PNG calls file.export png, which the engine rejects (no raster writer)")
for t_ in ["GeoJSON", "Points", "3MF", "USDZ", "DXF R12"]: mis(F + "Export ▸ " + t_, "File ▸ Export")
ov(F + "Export ▸ Schedules (CSV)", "todo", "@export:csv:<kind> is not accepted by engine file.export and the submenu is missing")
for t_ in ["Walls…", "Doors…", "Windows…", "Rooms…", "Slabs…", "All…"]: ov(F + "Export ▸ Schedules (CSV) ▸ " + t_, "todo", "engine file.export does not accept csv:<kind>")
for t_ in ["Plot Preview…", "Publish All Sheets to PDF…", "Batch Publish…", "Plot Style Tables…", "Title Block…"]: mis(F + t_, "File")

E_ = "Edit ▸ "
ov("Menu Edit", "partial", "hand-written Windows Edit menu lacks Deselect All, Selection Tools, Groups & Isolation, Match Properties")
for t_ in ["Undo", "Redo", "Cut", "Copy", "Paste", "Delete", "Select All", "Quick Select…"]: ov(E_ + t_, "done")
ov(E_ + "Deselect All", "partial", "no menu entry; Ctrl+Shift+A selects all instead (main.ts ignores Shift)")
ov(E_ + "Selection Tools", "partial", "submenu missing; the commands work from the ribbon")
for t_ in ["Quick Select", "Select Similar", "Invert", "By Layer", "By Type", "Chain", "Intersecting", "Filter", "Named Sets"]: mis(E_ + "Selection Tools ▸ " + t_, "Edit")
ov(E_ + "Groups & Isolation", "partial", "submenu missing; the commands work from the ribbon")
for t_ in ["Group", "Ungroup", "Isolate", "Hide", "End Isolation"]: mis(E_ + "Groups & Isolation ▸ " + t_, "Edit")
mis(E_ + "Match Properties", "Edit")

V = "View ▸ "
ov("Menu View", "partial", "hand-written Windows View menu: modes, Workspace, Layer States, zoom, panels, Clean Screen, Command Search only")
for t_ in ["Workspace", "Workspace ▸ 2D Plan", "Workspace ▸ 3D Model", "Workspace ▸ Split", "Workspace ▸ Sheet", "2D Plan", "3D Model", "Split View",
           "Sheets", "Zoom Extents", "Zoom In", "Zoom Out", "Hide Panels", "Layer States…", "Workspace ▸ {Workspaces.all}",
           "Workspace ▸ Save Current Workspace…", "Clean Screen"]:
    ov(V + t_, "done")
mis(V + "Zoom Window", "View")
ov(V + "Visual Style", "partial", "submenu missing; the ribbon visual-style drop-down works")
for t_ in ["Wireframe", "Hidden Line", "Shaded", "Shaded with Edges", "Conceptual", "Realistic", "X-Ray", "Sketchy"]: mis(V + "Visual Style ▸ " + t_, "View")
ov(V + "3D View", "partial", "submenu missing; the view commands work from the ribbon and view cube")
for t_ in ["Top", "Front", "Right", "Back", "Left", "Iso"]: mis(V + "3D View ▸ " + t_, "View")
for t_ in ["Layers Panel", "Properties Panel", "Levels Panel", "Project Browser", "Materials Panel", "History Panel", "Sheet Set Manager", "Tool Palettes"]:
    ov(V + t_, "partial", "no View-menu entry; the panel opens from its panel tab / ribbon")
ov(V + "Float Panel", "todo", "FLOATPANEL (floating panel windows) not ported")
for t_ in ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts", "Quick Props", "Inspector", "Content"]:
    ov(V + "Float Panel ▸ " + t_, "todo", "FLOATPANEL not registered in archi-engine")
mis(V + "Material Library…", "View")
ov(V + "3D Tools", "partial", "submenu missing; the commands work from the View ribbon tab")
for t_ in ["View Cube", "Section Box", "Sun Study", "Orbit Around Selection", "Save Camera…"]: mis(V + "3D Tools ▸ " + t_, "View")
mis(V + "Show Script Console", "View")
ov(V + "Enter Full Screen", "n/a (macOS system item)")

ov("Menu Window", "done", "Windows Window menu: Minimize, Maximize, New Window")
ov("Window ▸ Minimize", "done"); ov("Window ▸ Zoom", "done"); ov("Window ▸ Bring All to Front", "n/a (macOS only)")

H = "Help ▸ "
ov("Menu Help", "partial", "hand-written Windows Help menu")
ov(H + "Oanarina Archi Tool Help (F1)", "partial", "F1 opens the online guide, not the running command's page; Help ▸ Command Help runs HELP")
mis(H + "Tutorials", "Help")
ov(H + "Open Sample House", "partial", "not in the Help menu; File ▸ New from Template ▸ Sample House and the start screen open it")
ov(H + "Search Commands…", "done")
ov(H + "Command Reference", "partial", "runs COMMANDREFERENCE on the command line; no Command Reference window")
ov(H + "User Guide", "done"); ov(H + "Keyboard Shortcuts", "done"); ov(H + "Customize Shortcuts…", "done")
ov(H + "Start Screen", "done")
ov(H + "Check Command Coverage", "todo", "APPSELFTEST not ported")
ov(H + "Export Command Reference…", "todo", "EXPORTCOMMANDS not ported")
mis(H + "Connect Claude…", "Help")
ov(H + "Oana Rinaldi Website", "done")

# ---- status bar ----
for p_, s_, n_ in [
    ("view CoordinateReadout", "done", ""), ("menu ucsIndicator", "done", ""), ("view MacroButtonBar", "todo", "macro buttons not in the Windows status bar"),
    ("toggle GRID", "done", ""), ("toggle SNAP", "done", ""), ("toggle ORTHO", "done", ""), ("toggle POLAR", "done", ""), ("toggle OTRACK", "done", ""),
    ("toggle OSNAP", "done", ""), ("toggle DYN", "done", ""), ("toggle LWT", "done", ""), ("dropdown Level", "done", ""), ("dropdown Layer", "done", ""),
    ("label {sel} selected", "done", ""), ("view ProgressStatusView", "todo", "no progress indicator for long commands"), ("menu isolateMenu", "done", ""),
    ("view AnnotationScaleMenu", "done", ""), ("button slider.horizontal.below.rectangle", "partial", "opens the Quick Props tab; tooltip does not follow the on/off state"),
    ("menu {model.doc.units.abbreviation}", "done", ""), ("view ZoomReadout", "done", ""),
    ("button agentIndicator", "partial", "static 'Agent: off' label; runs AGENTSERVER but does not show the server state")]:
    ov(p_, s_, n_)

# ---- shortcuts (main.ts, windows-conventions.ts, dialogs/index.ts) ----
SC = {
    "Ctrl+, [⌘,] Oanarina Archi Tool ▸ Settings…": "done",
    "Ctrl+H [⌘H] Oanarina Archi Tool ▸ Hide Oanarina Archi Tool": "n/a (macOS only)",
    "Ctrl+Alt+H [⌥⌘H] Oanarina Archi Tool ▸ Hide Others": "n/a (macOS only)",
    "Ctrl+Q [⌘Q] Oanarina Archi Tool ▸ Quit Oanarina Archi Tool": "done",
    "Ctrl+N [⌘N] File ▸ New Drawing": "done", "Ctrl+O [⌘O] File ▸ Open…": "done", "Ctrl+W [⌘W] File ▸ Close": "done",
    "Ctrl+S [⌘S] File ▸ Save": "done", "Ctrl+Shift+S [⇧⌘S] File ▸ Save As…": "done",
    "Ctrl+Shift+I [⇧⌘I] File ▸ Import…": ("todo", "not bound on Windows"),
    "Ctrl+Shift+P [⇧⌘P] File ▸ Page Setup…": "done",
    "Ctrl+Alt+Shift+P [⌥⇧⌘P] File ▸ Plot Preview…": ("todo", "bug: main.ts maps any Ctrl+P combination to PLOT"),
    "Ctrl+P [⌘P] File ▸ Plot / Print…": "done", "Ctrl+Z [⌘Z] Edit ▸ Undo": "done", "Ctrl+Shift+Z [⇧⌘Z] Edit ▸ Redo": "done",
    "Ctrl+X [⌘X] Edit ▸ Cut": "done", "Ctrl+C [⌘C] Edit ▸ Copy": "done", "Ctrl+V [⌘V] Edit ▸ Paste": "done", "Ctrl+A [⌘A] Edit ▸ Select All": "done",
    "Ctrl+Shift+A [⇧⌘A] Edit ▸ Deselect All": ("todo", "bug: Ctrl+Shift+A selects all (main.ts ignores Shift)"),
    "Ctrl+Alt+1 [⌥⌘1] View ▸ 2D Plan": ("todo", "not bound"), "Ctrl+Alt+2 [⌥⌘2] View ▸ 3D Model": ("todo", "not bound"),
    "Ctrl+Alt+3 [⌥⌘3] View ▸ Split View": ("todo", "not bound"), "Ctrl+Alt+4 [⌥⌘4] View ▸ Sheets": ("todo", "not bound"),
    "Ctrl+0 [⌘0] View ▸ Zoom Extents": ("partial", "Ctrl+0 toggles Clean Screen on Windows (the Mac binds both)"),
    "Ctrl+= [⌘=] View ▸ Zoom In": "done", "Ctrl+- [⌘-] View ▸ Zoom Out": "done",
    "Ctrl+Alt+P [⌥⌘P] View ▸ Hide Panels": ("todo", "bug: runs PLOT (main.ts ignores Alt)"),
    "Ctrl+Alt+J [⌥⌘J] View ▸ Show Script Console": ("todo", "not bound"),
    "Ctrl+F [⌃⌘F] View ▸ Enter Full Screen": "n/a (macOS system item)",
    "Ctrl+M [⌘M] Window ▸ Minimize": "n/a (Windows uses Win+Down)",
    "Ctrl+K [⌘K] Help ▸ Search Commands…": "done",
    "Ctrl+Shift+/ [⇧⌘/] Help ▸ Command Reference": ("todo", "not bound"),
    "Type anywhere [Type anywhere] Start a command on the command line": "done",
    "Enter / Space [Enter / Space] Finish input · repeat the last command": "done",
    "Esc [Esc] Cancel the command · clear the selection": "done",
    "Right-click [Right-click] Enter while a command runs · context menu when idle": "done",
    "Tab [Tab] Accept autocomplete": "done", "↑ / ↓ [↑ / ↓] Command history / suggestions": "done",
    "F1 [F1] Help for the running command": ("partial", "F1 opens the guide, not the running command's section"),
    "F2 [F2] Command history panel": ("todo", "F2 is swallowed (main.ts) and opens nothing"),
    "F3 [F3] Object snap on/off": "done", "F7 [F7] Grid display": "done", "F8 [F8] Ortho mode": "done", "F9 [F9] Grid snap": "done",
    "F10 [F10] Polar tracking": "done", "F11 [F11] Object snap tracking": "done", "F12 [F12] Dynamic input": "done",
    "Scroll wheel / pinch [Scroll wheel / pinch] Zoom about the cursor": "done", "Two-finger scroll [Two-finger scroll] Pan": "done",
    "Middle-drag · Space+drag [Middle-drag · Space+drag] Pan": "done", "Double middle-click [Double middle-click] Zoom extents": "done",
    "Ctrl+0 [Ctrl+0] Zoom extents": ("partial", "Ctrl+0 is Clean Screen on Windows"),
    "Ctrl+= / Ctrl+- [Ctrl+= / Ctrl+-] Zoom in / out": "done",
    "Drag left → right [Drag left → right] Window selection (fully inside)": "done",
    "Drag right → left [Drag right → left] Crossing selection (touching)": "done", "Shift-click [Shift-click] Toggle an object in the selection": "done",
    "Click a grip [Click a grip] Stretch the object (wall ends move joined walls)": "done", "Double-click text [Double-click text] Edit text": "done",
    "Del [Del] Erase the selection": "done", "Ctrl+Z / Ctrl+Shift+Z [Ctrl+Z / Ctrl+Shift+Z] Undo / Redo": "done",
    "Ctrl+C / Ctrl+X / Ctrl+V [Ctrl+C / Ctrl+X / Ctrl+V] Copy / Cut / Paste objects (paste at cursor)": "done",
    "Ctrl+A [Ctrl+A] Select all": "done",
    "Ctrl+Alt+1 … Ctrl+Alt+4 [Ctrl+Alt+1 … Ctrl+Alt+4] 2D · 3D · Split · Sheets": ("todo", "not bound"),
    "Ctrl+Alt+P [Ctrl+Alt+P] Show / hide panels": ("todo", "bug: runs PLOT"),
    "Ctrl+Alt+J [Ctrl+Alt+J] Script console": ("todo", "not bound"),
    "Ctrl+N / Ctrl+O / Ctrl+S / Ctrl+Shift+S [Ctrl+N / Ctrl+O / Ctrl+S / Ctrl+Shift+S] New · Open · Save · Save As": "done",
    "Ctrl+P [Ctrl+P] Plot / Print": "done", "Ctrl+Shift+P [Ctrl+Shift+P] Page setup": "done",
    "Ctrl+Alt+Shift+P [Ctrl+Alt+Shift+P] Plot preview": ("todo", "bug: runs PLOT"),
    "Ctrl+K [Ctrl+K] Search commands": "done", "Ctrl+0 [Ctrl+0] Clean screen": "done",
    "Ctrl+, [Ctrl+,] Settings (custom shortcuts, colors, autosave…)": "done",
    "Ctrl+Shift+/ [Ctrl+Shift+/] Command reference": ("todo", "not bound"),
    "F7 [F7] Toggle GRID": "done", "F9 [F9] Toggle SNAP": "done", "F8 [F8] Toggle ORTHO": "done", "F10 [F10] Toggle POLAR": "done",
    "F11 [F11] Toggle OTRACK": "done", "F3 [F3] Toggle OSNAP": "done", "F12 [F12] Toggle DYN": "done",
    "Ctrl+K [Ctrl+K] Search commands (Ctrl+K)": "done", "Ctrl+0 [Ctrl+0] Clean screen (Ctrl+0)": "done",
}
for k_, v_ in SC.items():
    if isinstance(v_, tuple): ov(k_, *v_)
    else: ov(k_, v_)

# ---- render ----
for n_ in ["Daylight", "Overcast"]: ov("Lighting preset " + n_, "partial", "within ~5 levels of the Mac, but lawn/meadow render darker (view3d calib)")
ov("Lighting preset Golden hour", "partial", "lawn and paving darker than the Mac (mean diff 5.7-9.4)")
ov("Lighting preset Night", "partial", "about 25% darker than the Mac; bollard light pools too wide")
for v_ in J["render"]["visualStyles"]: ov("Visual style " + v_, "done")
for f_ in ["Photographic render (RENDER) with presets, supersampling, PNG output", "Walk mode (WASD + mouse)", "Section box", "Sun study (animated sun and shadows)",
           "View cube", "3D gizmo (move/rotate)", "Camera paths and walkthrough video", "Render queue", "Measure 3D", "Split view (plan + 3D)"]:
    ov(f_, "done")
ov("Photographic render (RENDER) with presets, supersampling, PNG output", "partial", "no clay mode, depth of field or HDRI environment in the WebGL renderer")
ov("360° panorama", "partial", "rendered with the photographic look, not the Mac panorama renderer")

# ---- theme fonts and sizes (styles.css / dialogs.css / canvas.css) ----
for k_ in J["theme"]["fonts"]: ov("Font " + k_, "done")
for k_ in J["theme"]["sizes"]: ov("Size " + k_, "done")

# ---- round-2 audit corrections (evidence: code reading) ----
COMP = "bug: menu items carry command '{r}' (the Mac resolves it to COMPONENT at run time); Windows resolves nothing so the menu is disabled"
for base in ["Insert ▸ Content ▸ Component", "Architecture ▸ Model ▸ Component"]:
    ov(base + " (menu)", "todo", COMP)
    for t_ in ["Chair", "Table", "Desk", "Sofa", "Bed", "Wardrobe", "Kitchen", "Sink", "WC", "Bath", "Car", "Component…"]: ov(base + " ▸ " + t_, "todo", COMP)
ov("Annotate ▸ Style ▸ {model.doc.currentDimStyle} (menu)", "done")
ov("Annotate ▸ Style ▸ {model.doc.currentDimStyle} ▸ {model.doc.dimStyles}", "done")
ov("View ▸ Visual Style ▸ {model.viewStyle} (menu)", "done")
ov("View ▸ Visual Style ▸ {model.viewStyle} ▸ {VisualStyleDef.menuNames(model.doc)}", "done")
ov("Script ▸ Scripting ▸ Library ▸ No scripts in the library yet", "done")
for p_, c_ in [("View ▸ More ▸ View ▸ View ▸ Clean Screen On", "CLEANSCREENON"), ("View ▸ More ▸ View ▸ View ▸ Clean Screen Off", "CLEANSCREENOFF"),
               ("View ▸ More ▸ View ▸ View ▸ History Panel", "HISTORYPANEL"), ("Manage ▸ More ▸ Tools ▸ Help ▸ Search Commands", "COMMANDSEARCH")]:
    ov(p_, "todo", "the shell has the feature but %s is not registered, so the entry is disabled (map it to the shell action)" % c_)
ov("Levels ▸ Button Add Level", "done"); ov("Levels ▸ Button Delete level", "done")
ov("Materials ▸ Button Procedural… ", "done")
ov("History ▸ Button {c}", "done")
ov("UnitsSheet ▸ Stepper Precision: 2 decimals", "done"); ov("UnitsSheet ▸ Stepper Precision: 0", "done")
ov("Preferences ▸ display ▸ Picker Interface", "done")
ov("PageSetupSheet ▸ TextField {project}  ·  {sheet}  ·  plotted {date} {time}  ·  Oanarina Archi Tool", "done")
ov("Properties ▸ Menu {\"\\(types.count) objects (\" + counts.sorted() {…}.map() {…}.joined(separator: \", \") + \")\"}", "partial", "type summary shown, not a per-type filter menu")

# Shortcut rows: match by Windows keys + action (the Mac column differs between menu and Keyboard & Mouse rows).
_SC2 = {}
for k_, v_ in SC.items():
    m_ = re.match(r"(.*?) \[.*?\] (.*)$", k_)
    _SC2[(m_.group(1), m_.group(2))] = v_
for s_ in J["shortcuts"]:
    v_ = _SC2.get((s_["keys"], s_["action"]))
    if v_ is None: continue
    p_ = "%s [%s] %s" % (s_["keys"], s_["mac"], s_["action"])
    if isinstance(v_, tuple): ov(p_, *v_)
    else: ov(p_, v_)
ov("Color windowBlue", "partial", "window-selection blue is #4D80FF in plan-canvas.ts (Mac #4073F2)")
for p_ in ["Insert ▸ More ▸ Blocks ▸ Blocks & Attributes ▸ Block Library", "Tools ▸ Blocks & Attributes ▸ Block Library"]:
    ov(p_, "partial", "runs the command-line BLOCKLIBRARY instead of opening the Block Library window")
for p_ in ["Architecture ▸ More ▸ Systems ▸ BIM Authoring ▸ Family Editor", "Tools ▸ BIM Authoring ▸ Family Editor"]:
    ov(p_, "partial", "runs the command-line FAMILY instead of opening the Family Editor window")
ov("Tools ▸ Tutorial Videos ▸ Record Tutorial Videos", "partial", "recording is Mac-only; Windows opens the website tutorials")
ov("Tools ▸ Tutorial Videos ▸ Check Tutorial Scripts", "partial", "only checks that the commands exist")
ov("PrintSetup ▸ Picker Tray", "partial", "placeholder list (Electron cannot list trays)")
ov("PrintSetup ▸ Picker Media", "partial", "placeholder list (Electron cannot list media types)")
ov("Tools ▸ Navigate, Light & Publish ▸ Shade Plot", "partial", "SHADEPLOT Rendered falls back to As Displayed for engine-only plots")
ov("Preferences ▸ general ▸ Toggle Run startup.js from the script library in every new window", "partial", "startup.js runs with a reduced archi API (not partb runScriptFile)")

# ======================================================================================================================
# ---- round-3 audit (28 Sep 2026). Evidence: code reading of windows/src + ArchiCore, the engine's hello.json
# (build/engine-fixtures, 1038 commands, every new CommandDef present) and windows/test/audit-spot.mjs (30/30 in Chromium
# with the fixture engine) plus the engineers' suites re-run by the auditor (menus-keys 96, doctools 56, sheets 27,
# workspace 63, standards 29, render-extras-ui 15, ui-snapshots 30, dialogs 49, partb-tools 27, output 35,
# windows-conventions 9). Nothing here has run in real Electron on Windows yet unless noted.
# ======================================================================================================================

# Panels no longer placeholders: NAVIGATOR / NOTIFICATIONS / ADCENTER fill them (workspace/panels.ts; audit-spot).
cmd_ok = _orig_cmd_ok

# Windows now implemented, with the files whose labels the audit checks.
WINDOWS.update({
    "Browser": ("done", [W + "doctools/panels.ts", W + "ui/panels.ts"], ""),
    "History": ("done", [W + "doctools/panels.ts", W + "ui/panels.ts"], ""),
    "Selection": ("done", [W + "doctools/panels.ts", W + "ui/panels.ts"], ""),
    "Navigator": ("done", [W + "workspace/panels.ts"], ""),
    "Alerts": ("done", [W + "workspace/panels.ts"], ""),
    "Quick Props": ("done", [W + "doctools/panels.ts", W + "ui/panels.ts"], ""),
    "Inspector": ("done", [W + "doctools/panels.ts"], ""),
    "Content": ("done", [W + "workspace/panels.ts"], ""),
    "ScheduleSheet": ("done", [W + "doctools/schedule.ts"], ""),
    "CommandReferenceView": ("done", [W + "ui/help.ts"], ""),
    "SpellingSheet": ("done", [W + "doctools/spelling.ts"], ""),
    "About": ("done", [W + "ui/help.ts"], ""),
    "Assistant": ("done", [W + "workspace/assistant.ts"], ""),
    "GraphicStyles": ("done", [W + "standards/graphic-styles.ts"], ""),
    "Outliner": ("done", [W + "workspace/outliner.ts"], ""),
    "Versions": ("done", [W + "sheets/versions.ts"], ""),
    "PrintSetup": ("done", [W + "output/plot.ts", W + "standards/native.ts", "main/output.ts", "main/standards.ts"], ""),
})

# Round-2 overrides that the round-3 work made stale: the hand-written File / Edit / View / Help menus (ui/menubar.ts now
# builds every menu from docs/windows-parity.json), the {r} Component bug, the unregistered shell commands, the shortcut
# bugs (ui/keys.ts), the panel placeholders, the Block Library / Family Editor "More" entries (shell commands open the
# windows), startup.js, the tray/media pickers and SHADEPLOT Rendered.
_STALE = ("Windows %s menu", "Windows File menu", "Windows Edit menu", "Windows View menu", "Windows Help menu", "File ▸ Export menu",
          "no View-menu entry", "submenu missing", "hand-written", "not in the Help menu", "Open Recent", "bug: menu items carry",
          "the shell has the feature", "not bound", "bug: ", "F2 is swallowed", "F1 opens the guide", "command-line BLOCKLIBRARY",
          "command-line FAMILY", "reduced archi API", "placeholder list", "falls back to As Displayed", "Help ▸ About runs ABOUT",
          "runs ABOUT", "AGENTSETTINGS works", "APPSELFTEST not ported", "EXPORTCOMMANDS not ported", "FLOATPANEL", "file.export",
          "COMMANDREFERENCE on the command line", "Help ▸ Command Help", "no Open Recent", "no File ▸ Insert", "#4D80FF",
          "no contextual", "type summary shown", "PDF/DXF/SVG/IFC/OBJ/STL/GLB only")
for _k in list(OVERRIDE):
    if any(s_ in OVERRIDE[_k][1] for s_ in _STALE): del OVERRIDE[_k]
for _k in ["Menu File", "Menu Edit", "Menu View", "Menu Help", "Menu Oanarina Archi Tool"]: OVERRIDE.pop(_k, None)
for _k in list(OVERRIDE):
    if _k.startswith(("File ▸ ", "Edit ▸ ", "Help ▸ ")) and OVERRIDE[_k][0] == "done": del OVERRIDE[_k]   # let the resolver decide

# Windows conventions of the generated menu bar (ui/menubar.ts header comment; audit-spot: 12 menus, About last in Help,
# Options… / Agent Server… at the end of Edit, File ▸ Exit Alt+F4).
ov("Menu Oanarina Archi Tool", "done", "folded into the Windows menus: About → Help, Settings → Edit ▸ Options…, Agent Server → Edit, Quit → File ▸ Exit")
ov(A + "Hide Oanarina Archi Tool", "n/a (macOS only)"); ov(A + "Hide Others", "n/a (macOS only)")
ov(A + "Quit Oanarina Archi Tool", "done")
ov("Window ▸ Minimize", "done"); ov("Window ▸ Zoom", "done"); ov("Window ▸ Bring All to Front", "n/a (macOS only)")
ov("View ▸ Enter Full Screen", "done")                         # menubar.ts system item → windowControl("fullscreen")
ov("File ▸ Open Recent", "done"); ov("File ▸ Open Recent ▸ Clear Menu", "done")   # recentMenu()
ov("Help ▸ Oanarina Archi Tool Help (F1)", "done")             # openContextHelp: guide#<section> (audit-spot: LINE → #draw)
ov("Help ▸ Open Sample House", "done")                         # @ui:WindowRouter.open → @newWindow:sample
ov("Help ▸ User Guide", "done"); ov("Help ▸ Oana Rinaldi Website", "done")   # @openURL
ov("Help ▸ Tutorials", "done")                                 # TUTORIALS
ov("Tab bar ▸ app icon (About)", "done")                       # ABOUT (shell + engine), About window in ui/help.ts
CHROME = [(p_, (("done", "") if p_.startswith("Tab bar ▸ app icon") else v_)) for p_, v_ in CHROME]

# Contextual tabs: EngineContextRibbon.swift (ribbon.context) + sheets/context-ribbon.ts; sheets.mjs checks Wall, Window,
# mixed and empty selections, audit-spot a wall ("MODIFY WALL").
for c_ in J["contextualTabs"]:
    ov("Selection %s → tab \"%s\"" % (c_["selection"], c_["tab"]), "done")

# Status bar (workspace/progress.ts, statusbar.ts; workspace.mjs).
for p_ in ["view MacroButtonBar", "view ProgressStatusView", "button slider.horizontal.below.rectangle", "button agentIndicator"]: ov(p_, "done")

# Shortcuts: ui/keys.ts maps every Mac menu key (⌘→Ctrl, ⌥→Alt) with all modifiers counted; audit-spot checks Ctrl+Alt+P,
# Ctrl+Alt+1-4, Ctrl+Alt+J, F2, Ctrl+Alt+Shift+P (PREVIEW), Ctrl+Shift+A, Ctrl+Shift+/ and F1 by their effect.
_SC3 = {"Ctrl+Shift+I": "done", "Ctrl+Alt+Shift+P": "done", "Ctrl+Shift+A": "done", "Ctrl+Alt+1": "done", "Ctrl+Alt+2": "done",
        "Ctrl+Alt+3": "done", "Ctrl+Alt+4": "done", "Ctrl+Alt+P": "done", "Ctrl+Alt+J": "done", "Ctrl+Shift+/": "done", "F1": "done",
        "F2": "done", "Ctrl+Alt+1 … Ctrl+Alt+4": "done"}
for s_ in J["shortcuts"]:
    if s_["keys"] in _SC3: ov("%s [%s] %s" % (s_["keys"], s_["mac"], s_["action"]), _SC3[s_["keys"]])
for s_ in J["shortcuts"]:
    if s_["keys"] == "Ctrl+0" and "Zoom" in s_["action"]:
        ov("%s [%s] %s" % (s_["keys"], s_["mac"], s_["action"]), "partial", "Windows key conflict (documented): Ctrl+0 is Clean Screen, Zoom Extents has no Ctrl key (double middle-click, ribbon, Z E)")

# Render (windows/test-results/render-match/before-after.json: mean per-region difference 5.0 → 2.69 levels).
ov("Lighting preset Daylight", "partial", "cosmetic: 2.1-3.1 levels from the Mac; cedar 5-7 levels too bright in flat light")
ov("Lighting preset Golden hour", "partial", "cosmetic: 2.0-2.7 levels from the Mac; cedar +5-6. Smoke test on Windows: the interactive 3D view did not show the warm look after the preset was set")
ov("Lighting preset Overcast", "partial", "4.6 levels from the Mac; limestone +12")
ov("Lighting preset Night", "partial", "cosmetic: 1.7 levels from the Mac; the Mac's bollard light pools are brighter")
ov("Photographic render (RENDER) with presets, supersampling, PNG output", "partial", "clay, depth of field and HDRI done; the Clear Sky / Sunset / Studio / Night / Physical Sky environments approximate the Mac gradient maps")
ov("360° panorama", "partial", "rendered with the photographic look, not the Mac panorama renderer")

# Theme: the Mac canvas draws window selection in (0.3, 0.5, 1) = #4D80FF (CanvasView.swift 1314/1323), like Windows;
# Theme.windowBlue #4073F2 is referenced nowhere in ArchiApp.
ov("Color windowBlue", "done")

# Kept as they are: Tutorials Record (Mac-only screen recording) and Check (command existence only).
ov("Tools ▸ Tutorial Videos ▸ Record Tutorial Videos", "partial", "recording is Mac-only; Windows opens the website tutorials")
ov("Tools ▸ Tutorial Videos ▸ Check Tutorial Scripts", "partial", "only checks that the commands exist")
for _k in list(OVERRIDE):
    if "main.ts ignores Shift" in OVERRIDE[_k][1]: del OVERRIDE[_k]
# Properties: the per-type filter menu of a mixed selection is doctools/panels.ts typeFilterHeader (doctools.mjs).
WINDOWS["Properties"] = ("done", [W + "ui/panels.ts", W + "doctools/panels.ts"], "")
ov("Properties ▸ Menu {\"\\(types.count) objects (\" + counts.sorted() {…}.map() {…}.joined(separator: \", \") + \")\"}", "done")
# The Mac shows Done only when the reference is a sheet (onClose); Windows opens it as a window like Help ▸ Command
# Reference on the Mac, closed with its title-bar ×.
ov("CommandReferenceView ▸ Button Done", "done")

# ---------------- Round 4 (auditor) ----------------
# Render (windows/test-results/render-match-r4/before-after.json: 8 Mac renders at 1.8-2.7 mean levels; render-r4.mjs 26/26).
ov("Lighting preset Daylight", "done")
ov("Lighting preset Overcast", "done")          # 4.7 → 2.3 levels, limestone +12 → +3
ov("Lighting preset Golden hour", "done")       # render.preset switches the 3D view to Realistic (EngineSession.swift, render-r4.mjs)
ov("Lighting preset Night", "partial", "cosmetic: 1.8 levels from the Mac; the Mac's bollards cast shadows inside their own light pools")
ov("Photographic render (RENDER) with presets, supersampling, PNG output", "done")   # view3d/render-scene.ts ports RenderController.Environment maps
ov("360° panorama", "done")                     # cube faces with the Render window scene (render-r4.mjs PANORAMA checks)
# Help: the Mac opens the offline HelpBrowser for F1, Help ▸ Help (F1), Help ▸ Tutorials and TUTORIALS (ArchiApp.swift 107/488/489,
# AppCommandsNav.swift TUTORIALS); Windows has the help browser now (system/help-browser.ts) but these still open the website.
_HW = "opens the website guide; the Mac opens the offline help browser (system/help-browser.ts showHelpBrowser exists)"
ov("Help ▸ Oanarina Archi Tool Help (F1)", "partial", _HW)
ov("Help ▸ Tutorials", "partial", _HW)
ov("Tools ▸ Navigation & Sheets ▸ Tutorials", "partial", _HW)
for s_ in J["shortcuts"]:
    if s_["keys"] == "F1": ov("%s [%s] %s" % (s_["keys"], s_["mac"], s_["action"]), "partial", _HW)

# ---------------- Round 5: Oana's decisions of 28 Sep ----------------
# Help: F1 / Help ▸ Oanarina Archi Tool Help (F1) open the offline help browser at HelpPages.contextRoute (ui/windows-conventions.ts
# openContextHelp → system/help-browser.ts showHelpBrowser), TUTORIALS (Help ▸ Tutorials, Tools ▸ Navigation & Sheets ▸ Tutorials)
# opens its tutorials page (partb/index.ts tutorials); menus-keys.mjs, windows-conventions.mjs, audit-spot.mjs, partb-tools.mjs.
ov("Help ▸ Oanarina Archi Tool Help (F1)", "done")
ov("Help ▸ Tutorials", "done")
ov("Tools ▸ Navigation & Sheets ▸ Tutorials", "done")
for s_ in J["shortcuts"]:
    if s_["keys"] == "F1": ov("%s [%s] %s" % (s_["keys"], s_["mac"], s_["action"]), "done")
# Ctrl+0 is Clean Screen on Windows (ui/keys.ts); Zoom Extents keeps its non-Ctrl keys (double middle-click, Z E, ribbon, View menu).
for s_ in J["shortcuts"]:
    if s_["keys"] == "Ctrl+0" and "Zoom" in s_["action"]:
        ov("%s [%s] %s" % (s_["keys"], s_["mac"], s_["action"]), "n/a (Oana's decision 28 Sep: Windows CAD convention)")
# Recording and checking the tutorial videos is Mac-only; on Windows Record and Check open the website tutorials.
ov("Tools ▸ Tutorial Videos ▸ Record Tutorial Videos", "n/a (Oana's decision 28 Sep: recording tool is Mac-only; Windows opens the website tutorials)")
ov("Tools ▸ Tutorial Videos ▸ Check Tutorial Scripts", "n/a (Oana's decision 28 Sep: recording tool is Mac-only; Windows opens the website tutorials)")
# Night: placed lamp light falls under the moon's shadow (renderer.ts LAMP_SUN_SHADOW, bollard shadow streaks in their pools) and up to
# four spot lights cast shadow maps (test/view3d/night-lights.mjs); the pools stay dimmer than the Mac's at their outer edges.
ov("Lighting preset Night", "partial", "cosmetic: 1.8 levels from the Mac; bollard shadows and spot-light shadows now match, the bollard pools stay about 20 levels dimmer at their outer edges")
