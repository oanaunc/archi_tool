#!/usr/bin/env python3
# Oanarina Archi Tool — GPL-3.0-or-later
# Parity auditor (python3 windows/tools/parity_audit.py): decides a status for every row of docs/WINDOWS-PARITY.md from the Windows shell source (windows/src)
# and the engine (ArchiCore + archi-engine command registrations). Writes statuses back into the checklist.
import json, os, re, sys, glob, collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
J = json.load(open(os.path.join(ROOT, "docs/windows-parity.json")))
SRC = os.path.join(ROOT, "windows/src")

def read(p):
    try: return open(p, encoding="utf-8").read()
    except Exception: return ""

SHELL_FILES = {os.path.relpath(p, SRC): read(p) for p in glob.glob(SRC + "/**/*.ts", recursive=True)}
SHELL_ALL = "\n".join(SHELL_FILES.values())

# ---------------- engine command set ----------------
E = set()
EDEF = {}
for root in ["app/Sources/ArchiCore", "app/Sources/archi-engine"]:
    for p in glob.glob(os.path.join(ROOT, root, "**/*.swift"), recursive=True):
        t = read(p)
        for m in re.finditer(r'CommandDef\(\s*(?:name:\s*)?"([^"]+)"(?:\s*,\s*aliases:\s*\[([^\]]*)\])?', t):
            E.add(m.group(1).upper()); EDEF[m.group(1).upper()] = p
            for a in re.findall(r'"([^"]+)"', m.group(2) or ""): E.add(a.upper())
hello = os.path.join(ROOT, "build/engine-fixtures/hello.json")
if os.path.exists(hello):
    for c in json.load(open(hello))["response"]["result"]["commands"]:
        E.add(c["name"].upper()); [E.add(a.upper()) for a in c.get("aliases", [])]
# Subcommands excluded in the Mac catalogue too.
APPONLY = {c["name"]: c for c in J["commands"]}

PANELS_WIN = {"Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator",
              "Alerts", "Quick Props", "Inspector", "Content"}
EXPORT_OK = {"pdf", "dxf", "svg", "ifc", "obj", "stl", "glb"}  # DocumentIO.write / EnginePDF; png and csv:<kind> fail
UI_OK = {"window:PreferencesWindow", "window:PreferencesWindow.shortcuts", "window:keyboard-shortcuts", "window:CUIWindow", "sheet:units",
         "sheet:drafting", "sheet:quickSelect", "sheet:layerStates", "sheet:pageSetup", "FileManager.default.createDirectory",
         "ScriptLibrary.revealFolder", "window:BlockLibraryWindow", "window:MaterialLibraryWindow", "window:NodeEditorWindow",
         "window:MarkupWindow", "window:CompareWindow", "window:RevisionCloudWindow", "sheet:titleBlock", "sheet:connectClaude",
         "Workspaces.apply"}

def cmd_ok(c, names=(), ui=None):
    """(ok, note) for a command reference as the Windows ribbon / menu resolves it."""
    if ui and ui in UI_OK: return True, ""
    if not c: return None, ""
    if c.startswith("@"):
        k, _, v = c[1:].partition(":")
        if k == "panel": return (v in PANELS_WIN), ""
        if k in ("mode", "selectAll", "deselectAll", "cleanScreen", "scriptConsole", "runScript", "panels", "openURL"): return True, ""
        if k == "zoom": return v in ("extents", "in", "out", "window"), ""
        if k == "newWindow": return v in ("start", "sample", "blankMetric", "blankImperial", "building"), ""
        if k == "export":
            if v in EXPORT_OK: return True, ""
            if v == "png": return False, "engine file.export has no PNG writer"
            return False, "engine file.export does not accept %s" % v
        if k == "agent": return "AGENTSERVER" in E, ""
        if k == "ui": return (v in UI_OK), ""
        if k == "view": return (v.upper() + "VIEW") in E, ""
        return k.upper() in E, ""
    for n in [c] + list(names or []):
        if n.split(" ")[0].upper() in E: return True, ""
    return False, "command %s is not registered in archi-engine" % c.split(" ")[0]

def st(ok, note=""):
    if ok is True: return "done"
    if ok is False: return "todo"
    return ok

# ---------------- dynamic ribbon/menu lists the shell fills ----------------
DYN = {"Workspaces.all", "scripts"}  # dialogs/index.ts dynamicMenu, partb/index.ts script library

# ---------------- rows ----------------
ROWS = collections.OrderedDict()   # item path -> (status, note)
ORDER = []
def put(path, status, note=""):
    path = str(path).replace("|", "\\|").replace("\n", " ")
    ORDER.append(path)
    if path in ROWS and ROWS[path][0] != status:
        # duplicate item text (same path twice): keep the weaker status
        rank = {"todo": 0, "partial": 1, "done": 2}
        a = ROWS[path][0].split(" ")[0].rstrip(":"); b = status.split(" ")[0].rstrip(":")
        if rank.get(b, 3) >= rank.get(a, 3): return
    ROWS[path] = (status, note)

def agg(sts):
    s = [x for x in sts if x in ("done", "todo", "partial")]
    if not s: return "todo"
    if all(x == "done" for x in s): return "done"
    if all(x == "todo" for x in s): return "todo"
    return "partial"

OVERRIDE = {}      # exact path -> (status, note)
def ov(path, status, note=""): OVERRIDE[path] = (status, note)

exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "parity_audit_rules.py")).read())

def item_status(x):
    names = x.get("names", [])
    if x.get("dynamic"):
        return ("done", "") if (x["dynamic"] in DYN or any(x["dynamic"].startswith(d) for d in DYN)) else ("todo", "run-time list not filled on Windows")
    if x.get("kind") == "label" or (x.get("title") and re.search(r"\{[^}]+\}", x["title"]) and not x.get("command")):
        return ("todo", "run-time label not shown on Windows")
    ok, note = cmd_ok(x.get("command", ""), names, x.get("ui"))
    if ok is None: return ("todo", "no action")
    return (st(ok), note)

# Ribbon
for t in J["ribbon"]:
    tab_st = []
    grows = []
    for g in t["groups"]:
        g_st = []
        for it in g["items"]:
            kind = it.get("kind", "button")
            if kind == "menu":
                sub = []
                for s in it["sections"]:
                    for x in s["items"]:
                        if x.get("separator") or x.get("header"): continue
                        p = "%s ▸ %s ▸ %s ▸ %s%s" % (t["tab"], g["name"], it["title"], (s["name"] + " ▸ ") if s["name"] else "", x.get("title") or "{%s}" % x.get("dynamic", ""))
                        s2, n = OVERRIDE.get(p, item_status(x))
                        put(p, s2, n); sub.append(s2)
                p = "%s ▸ %s ▸ %s (menu)" % (t["tab"], g["name"], it["title"])
                s2, n = OVERRIDE.get(p, (agg(sub), ""))
                put(p, s2, n); g_st.append(s2)
            elif kind in ("label", "view"):
                p = "%s ▸ %s ▸ %s (%s)" % (t["tab"], g["name"], it.get("title", ""), kind)
                s2, n = OVERRIDE.get(p, ("todo", "custom ribbon view not ported"))
                put(p, s2, n); g_st.append(s2)
            elif kind == "dropdown":
                p = "%s ▸ %s ▸ %s (dropdown)" % (t["tab"], g["name"], it.get("title", ""))
                ok = it.get("dropdown") in ("layer", "level", "color", "linetype", "lineweight", "dimstyle", "visualstyle")
                s2, n = OVERRIDE.get(p, ("done" if ok else "todo", "" if ok else "dropdown kind %s not ported" % it.get("dropdown")))
                put(p, s2, n); g_st.append(s2)
            else:
                p = "%s ▸ %s ▸ %s" % (t["tab"], g["name"], it.get("title", ""))
                s2, n = OVERRIDE.get(p, item_status(it))
                put(p, s2, n); g_st.append(s2)
        p = "%s ▸ %s (group)" % (t["tab"], g["name"])
        grows.append((p, OVERRIDE.get(p, (agg(g_st), ""))))
        tab_st.append(grows[-1][1][0])
    p = "Tab " + t["tab"]
    put(p, *OVERRIDE.get(p, (agg(tab_st), "")))
    for p, v in grows: put(p, *v)

for p, v in CHROME: put(p, *v)
for c in J["contextualTabs"]:
    p = "Selection %s → tab \"%s\"" % (c["selection"], c["tab"])
    put(p, *OVERRIDE.get(p, ("todo", "no contextual (selection) ribbon tabs on Windows")))

# Menus
SPECIAL = {"Oanarina Archi Tool", "File", "Edit", "View", "Window", "Help"}
def mwalk(items, path, special):
    out = []
    for it in items:
        if it.get("separator") or it.get("header"): continue
        t = it.get("title") or ("{%s}" % it["dynamic"] if it.get("dynamic") else "")
        p = " ▸ ".join(path + [t])
        sub = mwalk(it["submenu"], path + [t], special) if it.get("submenu") else None
        if p in OVERRIDE: s2, n = OVERRIDE[p]
        elif special: s2, n = ("todo", "not in the Windows %s menu" % path[0])
        elif sub is not None: s2, n = agg(sub), ""
        elif it.get("system"): s2, n = ("n/a (macOS system item)", "")
        else: s2, n = item_status(it)
        put(p, s2, n); out.append(s2)
    return out
for m in J["menus"]:
    sub = mwalk(m["items"], [m["title"]], m["title"] in SPECIAL)
    p = "Menu " + m["title"]
    put(p, *OVERRIDE.get(p, (agg(sub), "")))

# Palettes
PAL = json.load(open(os.path.join(ROOT, "windows/src/renderer/data/palettes.generated.json")))
PALTXT = json.dumps(PAL)
for p_ in J["palettes"]:
    sub = []
    for x in p_.get("items", []):
        p = "%s ▸ %s" % (p_["name"], x["title"])
        s2, n = OVERRIDE.get(p, item_status(x))
        if s2 == "done" and ('"%s"' % x["title"]) not in PALTXT: s2, n = "todo", "tile missing from palettes.generated.json"
        put(p, s2, n); sub.append(s2)
    p = "Palette " + p_["name"]
    put(p, *OVERRIDE.get(p, (agg(sub) if sub else ("done" if ('"%s"' % p_["name"]) in PALTXT else "todo"), "")))

# Panels and dialogs: control labels searched in the shell files that implement each window
def literals(label):
    s = re.sub(r"\{[^}]*\}", "\x00", label or "")
    s = re.sub(r"\[[a-z.]+\]", "\x00", s)
    parts = []
    for alt in re.split(r" / ", s):
        for chunk in alt.split("\x00"):
            c = chunk.strip(" ·:…%.")
            if len(re.sub(r"[^A-Za-z]", "", c)) >= 3: parts.append(c)
    return parts

def found(lit, files):
    txt = "\n".join(SHELL_FILES.get(f, "") for f in files)
    cands = [lit, re.sub(r"\s*\([^)]*\)", "", lit).strip(), lit.replace("…", "")]
    return any(c and c.lower() in txt.lower() for c in cands)

def window_rows(kind, w):
    name = w["name"]
    impl, files, wnote = WINDOWS.get(name, ("todo", [], "not ported"))
    head = ("Panel %s (%s)" % (name, w.get("view", ""))) if kind == "panel" else ("%s (%s %s)" % (name, w.get("kind", ""), w.get("view", "")))
    sub = []
    rows = []
    for c in w.get("controls", []):
        p = "%s ▸ %s%s %s" % (name, (c["tab"] + " ▸ ") if c.get("tab") else "", c["kind"], c.get("label", ""))
        if p in OVERRIDE: s2, n = OVERRIDE[p]
        elif impl == "todo": s2, n = "todo", ""
        else:
            lits = literals(c.get("label", ""))
            if c.get("command") and not lits:
                ok, n = cmd_ok(c["command"]); s2 = st(ok)
            elif lits:
                hit = [found(l, files) for l in lits]
                s2 = "done" if all(hit) else ("partial" if any(hit) else "todo")
                n = "" if s2 == "done" else "label not found in %s" % ", ".join(os.path.basename(f) for f in files)
                if s2 == "done" and c.get("command"):
                    ok, n2 = cmd_ok(c["command"])
                    if not ok: s2, n = "partial", n2
            else:
                s2, n = ("done" if impl == "done" else "partial"), ""
        rows.append((p, s2, n)); sub.append(s2)
    hs = OVERRIDE.get(head, (impl if impl != "done" else (agg(sub) if sub else "done"), wnote))
    if hs[0] == "partial" and not hs[1]: hs = ("partial", wnote)
    put(head, *hs)
    for r in rows: put(*r)

for w in J["panels"]: window_rows("panel", w)
for w in J["dialogs"]: window_rows("dialog", w)

for s in J["statusBar"]:
    if s["kind"] in ("spacer", "separator"): continue
    p = "%s %s" % (s["kind"], s.get("title", s.get("symbol", "")))
    put(p, *OVERRIDE.get(p, ("todo", "")))
for s in J["shortcuts"]:
    p = "%s [%s] %s" % (s["keys"], s["mac"], s["action"])
    put(p, *OVERRIDE.get(p, ("todo", "")))
for p_ in J["render"]["presets"]:
    p = "Lighting preset " + p_["name"]; put(p, *OVERRIDE.get(p, ("todo", "")))
for v in J["render"]["visualStyles"]:
    p = "Visual style " + v; put(p, *OVERRIDE.get(p, ("todo", "")))
for f in ["Photographic render (RENDER) with presets, supersampling, PNG output", "Walk mode (WASD + mouse)", "Section box", "Sun study (animated sun and shadows)",
          "View cube", "3D gizmo (move/rotate)", "Camera paths and walkthrough video", "Render queue", "360° panorama", "Measure 3D", "Split view (plan + 3D)"]:
    put(f, *OVERRIDE.get(f, ("todo", "")))
CSS = "\n".join(read(p) for p in glob.glob(SRC + "/**/*.css", recursive=True)) + SHELL_ALL
for k, v in J["theme"]["colors"].items():
    p = "Color " + k
    if p in OVERRIDE: put(p, *OVERRIDE[p]); continue
    d, l = v["dark"].lower(), v["light"].lower()
    hd, hl = d in CSS.lower(), l in CSS.lower()
    put(p, "done" if hd and hl else ("partial" if hd or hl else "todo"), "" if hd and hl else "value %s not found in the shell CSS/TS" % (l if hd else d))
for k, v in J["theme"]["fonts"].items():
    p = "Font " + k; put(p, *OVERRIDE.get(p, ("todo", "")))
for k, v in J["theme"]["sizes"].items():
    p = "Size " + k; put(p, *OVERRIDE.get(p, ("todo", "")))

# ---------------- write back ----------------
md_path = os.path.join(ROOT, "docs/WINDOWS-PARITY.md")
lines = open(md_path, encoding="utf-8").read().split("\n")
out, missing, cnt = [], [], collections.Counter()
seen = set()
for line in lines:
    m = re.match(r"\| (todo[^|]*|done[^|]*|partial[^|]*|n/a[^|]*|wip[^|]*) \| (.*?) \| (.*)$", line)
    if m and m.group(2) in ROWS:
        s, n = ROWS[m.group(2)]
        cell = s if not n or s == "done" else "%s: %s" % (s, n.replace("|", "/"))
        if s.startswith("n/a"): cell = s
        line = "| %s | %s | %s" % (cell, m.group(2), m.group(3))
        cnt[s.split(" ")[0].rstrip(":")] += 1
        seen.add(m.group(2))
    elif m:
        missing.append(m.group(2)); cnt["unmatched"] += 1
    out.append(line)
text = "\n".join(out)
nontodo = sum(v for k, v in cnt.items() if k not in ("todo", "unmatched"))
summary = ("Items not `todo`: %d — **done %d · partial %d · todo %d · n/a %d** (parity audit; open items in docs/WINDOWS-GAPS.md)"
           % (nontodo, cnt["done"], cnt["partial"], cnt["todo"] + cnt["unmatched"], cnt["n/a"]))
text = re.sub(r"Items not `todo`: .*", summary, text, count=1)
open(md_path, "w", encoding="utf-8").write(text)
print(summary)
print("unmatched rows:", len(missing), missing[:20])
json.dump({p: ROWS[p] for p in ROWS}, open(os.path.join(ROOT, "build/parity-audit.json"), "w"), ensure_ascii=False, indent=0)
