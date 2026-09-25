#!/usr/bin/env python3
"""Generates docs/FEATURE-REGISTER.md from docs/features.json (the JSON is the source of truth).

Usage: python3 docs/gen_feature_register.py   (run from the repository root)
"""
import json, os
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "features.json")
OUT = os.path.join(HERE, "FEATURE-REGISTER.md")

PHASES = {1: "MVP foundation", 2: "Drafting & annotation parity", 3: "Full BIM & documentation",
          4: "Advanced modelling", 5: "Rendering & visualization", 6: "Interoperability & collaboration",
          7: "Analysis & simulation", 8: "Automation, AI & platform polish"}
STATUS_MARK = {"done": "✅ done", "partial": "🟡 partial", "planned": "planned"}

def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")

def main():
    feats = json.load(open(SRC, encoding="utf-8"))
    areas = OrderedDict()
    for f in feats:
        areas.setdefault((f["id"].split("-")[0], f["area"]), []).append(f)
    st = Counter(f["status"] for f in feats)
    pr = Counter(f["priority"] for f in feats)
    L = []
    w = L.append
    w("# Oanarina Archi Tool — Feature Register\n")
    w("> Generated from `docs/features.json` by `docs/gen_feature_register.py`. **Do not edit by hand** — edit the JSON and re-run the script.\n")
    w("This register lists every feature planned for Oanarina Archi Tool, a free (GPL-3.0) native macOS "
      "architecture application covering 2D drafting (AutoCAD / LibreCAD), BIM (Revit, ArchiCAD, Allplan, "
      "Vectorworks, Bonsai), 3D modelling (SketchUp, FreeCAD, SolveSpace, OpenSCAD), rendering (Enscape, "
      "Twinmotion, V-Ray basics), interoperability, analysis and AI-agent automation. "
      "See `ROADMAP.md` for what each phase delivers.\n")
    w("## How status is tracked\n")
    w("- Each feature has a stable ID `AREA-NNN` (never reused; new features are appended to their area).")
    w("- `status`: **planned** (not started), **partial** (data model or part of the behaviour exists), **done** (meets its acceptance criterion and has a test).")
    w("- `priority`: **must** (required for the phase exit), **should** (expected), **could** (nice to have).")
    w("- `phase`: 1–8, see the roadmap. `reference`: product(s) whose behaviour we match.")
    w("- A feature moves to **done** only when its `acceptance` criterion is covered by an automated test or a scripted check in `archi-cli`.")
    w("- Workflow: update `features.json` in the same change that implements the feature, then run `python3 docs/gen_feature_register.py`.\n")
    w("## Summary\n")
    w(f"**{len(feats)} features** — done: {st['done']}, partial: {st['partial']}, planned: {st['planned']}. "
      f"Priority: must {pr['must']}, should {pr['should']}, could {pr['could']}.\n")
    hdr = "| Area | Prefix | Features | Done | Partial | " + " | ".join(f"P{p}" for p in PHASES) + " |"
    w(hdr); w("|" + " --- |" * (5 + len(PHASES)))
    tot = Counter()
    for (pfx, name), fs in areas.items():
        ph = Counter(f["phase"] for f in fs); tot.update(ph)
        s = Counter(f["status"] for f in fs)
        w(f"| [{name}](#{pfx.lower()}--{slug(name)}) | {pfx} | {len(fs)} | {s['done']} | {s['partial']} | "
          + " | ".join(str(ph.get(p, 0) or "·") for p in PHASES) + " |")
    w(f"| **Total** | | **{len(feats)}** | **{st['done']}** | **{st['partial']}** | "
      + " | ".join(f"**{tot.get(p, 0)}**" for p in PHASES) + " |\n")
    w("### Phases\n")
    w("| Phase | Theme | Features | Must |"); w("| --- | --- | --- | --- |")
    for p, t in PHASES.items():
        fs = [f for f in feats if f["phase"] == p]
        w(f"| {p} | {t} | {len(fs)} | {sum(f['priority'] == 'must' for f in fs)} |")
    w("")
    for (pfx, name), fs in areas.items():
        w(f"## {pfx} — {name}\n")
        w(f"{len(fs)} features.\n")
        group = None
        for f in fs:
            if f["group"] != group:
                group = f["group"]
                w(f"\n### {group}\n")
                w("| ID | Feature | Command | Phase | Priority | Status |"); w("| --- | --- | --- | --- | --- | --- |")
            w(f"| {f['id']} | {cell(f['name'])} | {cell(f['command'])} | {f['phase']} | {f['priority']} | {STATUS_MARK[f['status']]} |")
        w("")
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"wrote {OUT}: {len(feats)} features")

def slug(s):
    return "".join(c for c in s.lower().replace(" ", "-") if c.isalnum() or c == "-")

if __name__ == "__main__":
    main()
