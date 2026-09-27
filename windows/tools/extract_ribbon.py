#!/usr/bin/env python3
"""Generates windows/src/renderer/data/ribbon-fallback.json from the Mac app's Swift sources.

It reads every `static let <name>: [CmdItem] = [...]` catalog in app/Sources/ArchiApp and lays the ribbon out exactly
like RibbonView.swift (tabs, groups, large buttons, small-button columns, catalog menus, dropdowns). The output uses the
docs/windows-parity.json ribbon shape ({ribbon:[{tab, groups:[{name, items:[{title, symbol, command, args?}]}]}]})
plus optional layout hints (size, rows, kind, sections) that the shell understands. When docs/windows-parity.json
exists the shell uses that instead (see tools/gen-ui-data.mjs).

Usage: python3 tools/extract_ribbon.py <repo root> <output.json>
"""
import json, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "src", "renderer", "data", "ribbon-fallback.json")
src_dir = os.path.join(root, "app", "Sources", "ArchiApp")

def strings(s):
    return [m.encode().decode("unicode_escape") if "\\u" in m else m for m in re.findall(r'"((?:[^"\\]|\\.)*)"', s)]

def split_top(body):
    """Splits the array body into top-level element expressions."""
    out, depth, cur, q = [], 0, "", False
    i = 0
    while i < len(body):
        ch = body[i]
        if q:
            cur += ch
            if ch == "\\": cur += body[i + 1]; i += 1
            elif ch == '"': q = False
        elif ch == '"': q = True; cur += ch
        elif ch in "([{": depth += 1; cur += ch
        elif ch in ")]}": depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        elif ch == "/" and body[i:i + 2] == "//":
            j = body.find("\n", i); i = len(body) if j < 0 else j; continue
        else: cur += ch
        i += 1
    if cur.strip(): out.append(cur.strip())
    return out

catalogs = {}
for fn in sorted(os.listdir(src_dir)):
    if not fn.endswith(".swift"): continue
    text = open(os.path.join(src_dir, fn), encoding="utf-8").read()
    for m in re.finditer(r'static let (\w+): \[CmdItem\] = \[', text):
        name, start = m.group(1), m.end()
        depth, i, q = 1, start, False
        while depth:
            ch = text[i]
            if q:
                if ch == "\\": i += 1
                elif ch == '"': q = False
            elif ch == '"': q = True
            elif ch == "[": depth += 1
            elif ch == "]": depth -= 1
            i += 1
        items = []
        for el in split_top(text[start:i - 1]):
            if el.startswith("CmdItem("):
                t = re.search(r'title:\s*"((?:[^"\\]|\\.)*)"', el); s = re.search(r'symbol:\s*"([^"]*)"', el)
                n = re.search(r'names:\s*\[([^\]]*)\]', el); a = re.search(r'args:\s*"((?:[^"\\]|\\.)*)"', el)
                if not (t and s and n): continue
                it = {"title": t.group(1).replace('\\"', '"'), "symbol": s.group(1), "names": strings(n.group(1))}
                if a: it["args"] = a.group(1).replace('\\"', '"')
                items.append(it)
            elif el.startswith("c("):
                ss = strings(el)
                if len(ss) >= 3: items.append({"title": ss[0], "symbol": ss[1], "names": ss[2:]})
        catalogs.setdefault(name, items)

def item(it, size="small"):
    d = {"title": it["title"], "symbol": it["symbol"], "command": it["names"][0], "size": size}
    if len(it["names"]) > 1: d["names"] = it["names"]
    if it.get("args"): d["args"] = it["args"]
    return d

def cat(name): return catalogs.get(name, [])
def L(name, *idx): return [item(cat(name)[i], "large") for i in idx if i < len(cat(name))]
def S(items, rows=3):
    r = [item(x) for x in items]
    if r: r[0]["rows"] = rows
    return r
def A(title, symbol, command, size="large", **kw):
    d = {"title": title, "symbol": symbol, "command": command, "size": size, "kind": "action"}
    d.update(kw); return d
def M(title, symbol, sections, help=""):
    return {"title": title, "symbol": symbol, "command": "", "size": "large", "kind": "menu", "help": help,
            "sections": [{"name": n, "items": [item(x) for x in cat(c)]} for n, c in sections]}
def CM(title, symbol, items, help=""):
    return {"title": title, "symbol": symbol, "command": "", "size": "large", "kind": "menu", "help": help,
            "sections": [{"name": "", "items": [item(x) for x in items]}]}
def D(kind, width=170, **kw):
    d = {"title": kind, "symbol": "", "command": "", "kind": "dropdown", "dropdown": kind, "width": width}
    d.update(kw); return d
def G(name, *parts):
    items = []
    for p in parts: items += p if isinstance(p, list) else [p]
    return {"name": name, "items": items}

furniture = [("Chair", "chair"), ("Table", "table.furniture"), ("Desk", "desktopcomputer"), ("Sofa", "sofa"), ("Bed", "bed.double"),
             ("Wardrobe", "cabinet"), ("Kitchen", "refrigerator"), ("Sink", "sink"), ("WC", "toilet"), ("Bath", "bathtub"), ("Car", "car")]
component = {"title": "Component", "symbol": "sofa", "command": "", "size": "large", "kind": "menu", "width": 58,
             "sections": [{"name": "", "items": [{"title": n, "symbol": s, "command": "COMPONENT", "args": n, "size": "small"} for n, s in furniture]
                           + [{"title": "Component…", "symbol": "", "command": "COMPONENT", "size": "small"}]}]}
views = [("Top", "square.tophalf.filled"), ("Front", "square.bottomhalf.filled"), ("Right", "square.righthalf.filled"),
         ("Back", "square.tophalf.filled"), ("Left", "square.lefthalf.filled"), ("Iso", "cube")]
exports = [("DXF", "doc.text"), ("SVG", "photo"), ("IFC", "building.columns"), ("OBJ", "cube"), ("STL", "cube.transparent"),
           ("GLB", "shippingbox"), ("PNG", "photo.on.rectangle"), ("CSV", "tablecells")]

ribbon = [
  {"tab": "Home", "groups": [
    G("Draw", L("draw", 0, 1, 2, 3), S(cat("draw")[4:])),
    G("Modify", S(cat("modify"))),
    G("Layers", D("layer", 170), A("Layer Properties", "square.3.layers.3d", "@panel:Layers", "small", help="Open the Layers panel", rows=1),
      A("States", "rectangle.stack", "LAYERSTATE", "small", help="Layer States Manager (LAYERSTATE)", inline=True)),
    G("Properties", D("color", 150), D("linetype", 150), D("lineweight", 150)),
    G("Selection", A("Select All", "checkmark.rectangle.stack", "@selectAll", help="Select all objects (Ctrl+A)"),
      A("Quick Select", "line.3.horizontal.decrease.circle", "QSELECTDIALOG", help="Quick Select dialog (QSELECTDIALOG)"),
      S([{"title": "Match Props", "symbol": "paintbrush.pointed", "names": ["MATCHPROP"]},
         {"title": "Similar", "symbol": "square.on.square.intersection.dashed", "names": ["SELECTSIMILAR"]}]),
      A("Properties", "slider.horizontal.3", "@panel:Properties", "small", help="Show the Properties panel"),
      CM("More", "ellipsis.circle", cat("selection"), "Selection tools: QSELECT, invert, by layer/type, chain, filter, named sets")),
    G("Groups", S(cat("groups"))),
    G("More", M("Draw", "pencil.and.outline", [("Draw More", "drawMore"), ("Construction", "construction")], "More drawing and construction tools"),
      M("Modify", "wand.and.rays", [("Modify More", "modifyMore"), ("Clipboard & Selection", "clipboard"), ("Drafting Extras", "draftingExtra")], "More modify, clipboard and selection tools"),
      M("Layers", "square.3.layers.3d.middle.filled", [("Layer Tools", "layersMore")], "Layer tools (LAYISO, LAYFRZ, LAYMRG…)")),
  ]},
  {"tab": "Insert", "groups": [
    G("Import", L("importItems", 0, 1), S(cat("importItems")[2:])),
    G("Block & Reference", L("referenceItems", 0), S(cat("referenceItems")[1:])),
    G("Content", A("Tool Palettes", "square.grid.3x3.square", "@panel:Tools", help="Blocks, components and tools; drag onto the drawing (TOOLPALETTES)"),
      A("Materials", "paintpalette", "MATBROWSER", help="Material library browser (MATBROWSER)"), component),
    G("Export", S(cat("exportItems"))),
    G("More", M("Blocks", "square.on.square.dashed", [("Blocks & Attributes", "blocksMore"), ("Dynamic Blocks", "blocksExtra")], "Block and attribute tools"),
      M("Exchange", "arrow.left.arrow.right.square", [("Import & Export", "exchange"), ("File", "fileCommands")], "More import/export formats and file commands")),
    G("Images & Geo", L("imagesGeo", 0), S(cat("imagesGeo")[1:])),
    G("Library", A("Block Library", "books.vertical", "BLOCKLIBRARY", help="Browse folders of drawings as a block library (BLOCKLIBRARY)")),
  ]},
  {"tab": "Annotate", "groups": [
    G("Text", L("text", 0, 1)),
    G("Dimensions", L("dimensions", 0), S(cat("dimensions")[1:5])),
    G("Leaders & Tables", L("dimensions", 5, 6)),
    G("More", M("Dims", "ruler", [("Dimensions", "dimMore")], "Baseline, continue, ordinate, QDIM, dimension editing"),
      M("Text", "textformat", [("Text, Leaders & Tables", "textMore"), ("Annotation Extras", "annotateExtra")], "Text editing, spelling, fields, tables, symbols")),
    G("Parametric", M("Constrain", "link.circle", [("Parametric", "parametric")], "Geometric and dimensional constraints"),
      A("Show Constraints", "eye.square", "CONSTRAINTBAR Toggle", help="Show or hide constraint glyphs in the plan (CONSTRAINTBAR)")),
    G("Style", D("dimstyle", 170, label="Dimension style")),
  ]},
  {"tab": "Architecture", "groups": [
    G("Build", L("build", 0, 1, 2), S(cat("build")[3:])),
    G("Build+", S(cat("buildMore")[:6])),
    G("Room & Area", L("spaces", 0, 1), S(cat("roomsMore"))),
    G("Documentation", S(cat("documentation")[:9]), CM("More", "ellipsis.circle", cat("documentation")[9:] + cat("buildMore")[6:], "More BIM tools")),
    G("Model", component, L("spaces", 3)),
    G("More", M("Systems", "square.stack.3d.up.fill", [("BIM Data", "bimMore"), ("BIM Authoring", "bimAuthoring"), ("Structure", "structure"), ("MEP", "mep"), ("Site", "siteMore")], "BIM data, structure, MEP and site tools")),
    G("Level", D("level", 170), A("Levels", "building.2", "@panel:Levels", "small", help="Open the Levels panel", rows=1)),
  ]},
  {"tab": "Modeling", "groups": [
    G("Solids", L("solids", 0, 4), S([cat("solids")[i] for i in (1, 2, 3, 5)], 2)),
    G("Solid Editing", L("modeling", 0), S(cat("modeling")[1:])),
    G("Booleans", L("booleans", 0, 1, 2), S(cat("booleans")[3:], 2)),
    G("3D Operations", S(cat("transform3D"))),
    G("Site", L("site", 0), S(cat("site")[1:], 2)),
    G("Surfaces", M("Surfaces", "square.stack.3d.up", [("Surfaces & Mesh", "surfaces"), ("Solid Features", "solidsExtra")], "Ruled, tabulated, revolved and edge surfaces; mesh repair")),
    G("Visual Programming", A("Node Editor", "point.3.connected.trianglepath.dotted", "NODEEDITOR", help="Visual node editor with live preview (NODEEDITOR)")),
  ]},
  {"tab": "Analyze", "groups": [
    G("Inquiry", L("inquiry", 0, 1), S(cat("inquiry")[2:], 2)),
    G("Quantities", L("analysis", 0, 1), S(cat("analysis")[2:], 2)),
    G("Coordination", [item(x, "large") for x in cat("coordination")]),
    G("Checks", L("checks", 0, 1), S(cat("checks")[2:], 2)),
    G("Measure", S(cat("inquiryExtra"), 2)),
    G("3D Measure", A("Measure 3D", "ruler", "MEASURE3D", help="Pick two points on the 3D model to measure (MEASURE3D)")),
    G("Building Physics", M("More", "ellipsis.circle", [("Analysis & Checks", "analysisMore")], "Energy, daylight, acoustics, carbon and code checks")),
  ]},
  {"tab": "Collaborate", "groups": [
    G("Review", A("Markups", "text.bubble", "MARKUP", help="Markup and comment manager (MARKUP)"),
      A("Compare", "rectangle.on.rectangle.angled", "COMPARE", help="Compare this drawing with another version (COMPARE)"), S(cat("review")[2:])),
    G("Versions & Issues", L("versioning", 0, 1), S(cat("versioning")[2:])),
    G("Share", A("Share", "square.and.arrow.up", "SHARE Both", help="Share the project and a PDF (SHARE)"), L("sharing", 0), S(cat("sharing")[1:])),
    G("Sheets", A("Revision Clouds", "cloud", "REVCLOUDMANAGER", help="Revision clouds of the sheets: list, add, zoom to, delete")),
  ]},
  {"tab": "View", "groups": [
    G("Workspace", A("2D Plan", "square", "@mode:2D", help="2D plan canvas"), A("3D Model", "cube", "@mode:3D", help="3D model viewport"),
      A("Split", "rectangle.split.2x1", "@mode:Split", help="Plan and 3D side by side"), A("Sheet", "doc.richtext", "@mode:Sheet", help="Paper space layouts")),
    G("Navigate", A("Extents", "arrow.up.backward.and.arrow.down.forward", "@zoom:extents", help="Zoom to the drawing extents"),
      A("Window", "plus.magnifyingglass", "@zoom:window", "small", help="Drag a rectangle to zoom into", rows=3),
      A("Zoom In", "plus.magnifyingglass", "@zoom:in", "small", help="Zoom in"), A("Zoom Out", "minus.magnifyingglass", "@zoom:out", "small", help="Zoom out")),
    G("Visual Style", D("visualstyle", 170, note="Applies to the 3D viewport")),
    G("Views", [A(n, s, "VIEW " + n, "small", help=n + " view in the 3D viewport", **({"rows": 3} if i == 0 else {})) for i, (n, s) in enumerate(views)]),
    G("3D Tools", A("Section Box", "cube.transparent", "SECTIONBOX", help="Cut the 3D model with a box (SECTIONBOX)"),
      A("Sun Study", "sun.max", "SUNSTUDY", help="Animate the sun and shadows (SUNSTUDY)"),
      A("View Cube", "cube", "NAVVCUBE", "small", help="Show or hide the view cube (NAVVCUBE)", rows=3),
      A("Orbit Selection", "scope", "ORBITSELECTION", "small", help="Orbit around and zoom to the selection (ORBITSELECTION)"),
      A("Save Camera", "camera", "SAVECAMERA", "small", help="Save the 3D camera (SAVECAMERA)")),
    G("Presentation", A("Render", "camera.aperture", "RENDER", help="Render a photorealistic image"),
      A("Walk", "figure.walk", "WALK", help="Walk through the model (WASD + mouse)"),
      M("Animate", "film", [("Animation & Export", "animationItems")], "Walkthrough path, sun study video, 360° panorama"),
      A("Camera Paths", "point.topleft.down.to.point.bottomright.curvepath", "CAMERAPATHEDIT", "small", help="Keyframe camera paths (CAMERAPATHEDIT)", rows=3),
      A("Render Queue", "square.stack.3d.forward.dottedline", "RENDERQUEUE", "small", help="Queue renders of views and cameras (RENDERQUEUE)"),
      A("Gizmo", "move.3d", "GIZMO3D", "small", help="Move/rotate gizmo on the selection in 3D (GIZMO3D)")),
    G("More", M("View", "eye", [("View", "viewMore"), ("Views & Graphics", "viewsExtra")], "Every view command")),
    G("Interface", {"title": "Workspace", "symbol": "rectangle.3.group", "command": "WSCURRENT", "size": "large", "kind": "action", "width": 58, "help": "Switch workspace (WSCURRENT)"},
      A("Clean Screen", "rectangle.dashed", "@cleanScreen", help="Hide the ribbon and panels (Ctrl+0)")),
  ]},
  {"tab": "Output", "groups": [
    G("Plot", A("Plot / Print", "printer", "PLOT", help="Print the drawing or the active sheet (Ctrl+P)"), A("Preview", "eye", "PREVIEW", help="Plot dialog with live preview (PREVIEW)"),
      A("Print Setup", "printer.filled.and.paper", "PRINTSETUP", help="Print with printer, paper, tray, scale and copies (PRINTSETUP)"),
      A("Page Setup", "doc.badge.gearshape", "PAGESETUP", "small", help="Paper, plot style, lineweights, plot stamp (PAGESETUP)", rows=3),
      A("Export PDF", "doc.richtext", "EXPORTPDF", "small", help="Export the drawing or the active sheet as vector PDF"),
      A("Publish", "doc.on.doc", "PUBLISH", "small", help="All sheets in one PDF (PUBLISH)")),
    G("Sheets", A("Title Block", "list.bullet.rectangle.portrait", "TITLEBLOCK", help="Edit the title block and project info (TITLEBLOCK)"),
      A("Sheet Set", "rectangle.stack", "@panel:Sheets", help="Sheet set manager (SHEETSET)"),
      A("View Titles", "textformat.size", "VIEWTITLE", "small", help="Add or refresh view titles (VIEWTITLE)", rows=3),
      A("Revision", "clock.badge.checkmark", "@panel:Sheets", "small", help="Add a revision to the active sheet (SHEETREVISION)"),
      A("Sheet Index", "list.number", "SHEETINDEX", "small", help="Place or refresh the sheet list table (SHEETINDEX)")),
    G("More", M("Output", "printer.dotmatrix", [("Output", "outputMore"), ("Plot Styles", "plotItems")], "Every output command, plot styles, batch publish")),
    G("Export", [A(e, s, "@export:" + e.lower(), "small", help="Export " + e, **({"rows": 3} if i == 0 else {})) for i, (e, s) in enumerate(exports)]),
    G("Schedules", {"title": "CSV", "symbol": "tablecells", "command": "", "size": "large", "kind": "menu", "sections": [{"name": "", "items": [
        {"title": k.capitalize() + " schedule (CSV)…", "symbol": "", "command": "@export:csv:" + k, "size": "small"} for k in ["doors", "windows", "rooms", "walls", "all"]]}]},
      A("View", "list.bullet.rectangle", "SCHEDULE", help="Show a schedule table")),
  ]},
  {"tab": "Manage", "groups": [
    G("Panels", A("Layers", "square.3.layers.3d", "@panel:Layers", help="Layer properties manager"), A("Browser", "list.bullet.indent", "@panel:Browser", help="Project browser"),
      A("Tools", "square.grid.3x3.square", "@panel:Tools", help="Tool palettes"), A("Materials", "paintpalette", "@panel:Materials", help="Materials")),
    G("Settings", A("Units", "ruler", "UNITS", help="Drawing units"), A("Drafting", "slider.horizontal.3", "DSETTINGS", help="Drafting settings: grid, snap, polar, object snaps"),
      A("Options", "gearshape", "OPTIONS", help="Application settings (OPTIONS, Ctrl+,)")),
    G("History", A("History", "clock.arrow.circlepath", "@panel:History", help="Undo history and command history")),
    G("Cleanup", A("Purge", "trash.slash", "PURGE", help="Remove unused layers, blocks and styles"), A("Audit", "checkmark.shield", "AUDIT", help="Check the drawing for errors and fix them")),
    G("More", M("Settings", "gearshape.2", [("Settings", "settingsMore")], "Settings and system variables"),
      M("Tools", "wrench.and.screwdriver", [("Tools & Scripting", "tools"), ("Help", "helpCommands")], "Action recorder, aliases, scripting, help")),
  ]},
  {"tab": "Script", "groups": [
    G("Scripting", A("JS Console", "terminal", "@scriptConsole", help="JavaScript console with the archi API"),
      A("Run Script", "play.rectangle", "@runScript", help="Run a JavaScript file (.js) or a command script (.scr)"),
      A("Library", "books.vertical", "@scriptLibrary", help="Run a script from the library")),
    G("Automation", M("Tools", "wrench.and.screwdriver", [("Tools & Scripting", "tools"), ("Script Control", "scriptingExtra")], "Action recorder, script recorder, aliases, macros")),
    G("AI Agents", A("Start Server", "antenna.radiowaves.left.and.right", "@agent:toggle", help="Local JSON-RPC agent server"),
      {"title": "agent", "symbol": "", "command": "", "kind": "agentStatus"},
      A("Connect Claude", "sparkles", "@connectClaude", help="How to connect Claude with archi-cli --mcp")),
  ]},
]

menus_src = [("Draw", "draw"), ("Modify", "modify")]
menus = [{"menu": "Draw", "items": [item(x) for x in cat("draw")]},
         {"menu": "Modify", "items": [item(x) for x in cat("modify")]},
         {"menu": "Annotate", "items": [item(x) for x in cat("text") + cat("dimensions")]},
         {"menu": "Architecture", "items": [item(x) for x in cat("build") + cat("spaces")]}]
panels = ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts", "Quick Props", "Inspector", "Content"]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"generatedFrom": "app/Sources/ArchiApp (RibbonView.swift layout, CmdItem catalogs)", "ribbon": ribbon, "menus": menus,
           "panels": panels, "catalogs": {k: [item(x) for x in v] for k, v in catalogs.items()}}, open(out, "w"), indent=1, ensure_ascii=False)
syms = set()
def walk(o):
    if isinstance(o, dict):
        if o.get("symbol"): syms.add(o["symbol"])
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(ribbon); walk(catalogs)
print(f"{len(catalogs)} catalogs, {sum(len(v) for v in catalogs.values())} items, {len(syms)} symbols -> {out}")
