#!/usr/bin/env python3
"""Regenerates the command reference table in docs/USER-GUIDE.md from the CommandDef declarations in app/Sources.

Usage: python3 docs/gen_command_reference.py   (run from the repository root)
It reads every `CommandDef("NAME", aliases: [...], category: "...", summary: "...")` literal plus the generated
3D view commands, and replaces the text between the BEGIN/END COMMAND REFERENCE markers.
App-only commands (Settings, workspaces, plotting UI) are marked "app"; they are not available in headless archi-cli.
"""
import glob, os, re
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, "docs", "USER-GUIDE.md")
ORDER = ["Draw", "Modify", "Edit", "Select", "Annotate", "Blocks", "Layers", "Settings", "Inquiry", "Architecture",
         "Structure", "Site", "3D", "View", "Output", "File", "Analysis", "Scripting", "Tools", "Help"]

def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")

def collect():
    cmds = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "app", "Sources", "**", "*.swift"), recursive=True)):
        src = open(f, encoding="utf-8").read()
        app = "/ArchiApp/" in f
        for m in re.finditer(r'CommandDef\(\s*"([^"]+)"(.*?)summary:\s*"((?:[^"\\]|\\.)*)"', src, re.S):
            name, mid, summary = m.groups()
            if len(mid) > 600 or "\\(" in summary:
                continue
            al = re.search(r'aliases:\s*\[([^\]]*)\]', mid)
            aliases = re.findall(r'"([^"]+)"', al.group(1)) if al else []
            cat = re.search(r'category:\s*"([^"]+)"', mid)
            cmds[name] = (cat.group(1) if cat else "Other", aliases, unescape(summary), app)
        # 3D standard views: ("TOPVIEW", ["TOP", "PLANVIEW"], "top")
        for m in re.finditer(r'\("([A-Z]+VIEW|[A-Z]{2}ISO)",\s*\[([^\]]*)\],\s*"([a-z]+)"\)', src):
            name, al, v = m.groups()
            cmds.setdefault(name, ("View", re.findall(r'"([^"]+)"', al), f"Sets the 3D view to {v}.", app))
    return cmds

def table(cmds):
    groups = OrderedDict((c, []) for c in ORDER)
    for n, (c, a, s, app) in cmds.items():
        groups.setdefault(c, []).append((n, a, s, app))
    out = [f"{len(cmds)} commands.\n"]
    for c, rows in groups.items():
        if not rows:
            continue
        out.append(f"### {c}\n")
        out.append("| Command | Aliases | Description |")
        out.append("| --- | --- | --- |")
        for n, a, s, app in sorted(rows):
            desc = s.replace("|", "\\|") + (" *(app)*" if app else "")
            out.append(f"| `{n}` | {', '.join('`%s`' % x for x in a)} | {desc} |")
        out.append("")
    out.append("*(app)*: available in the Mac app (command line, menus, scripts and the agent server), not in headless `archi-cli`.\n")
    return "\n".join(out)

def main():
    g = open(GUIDE, encoding="utf-8").read()
    b, e = "<!-- BEGIN COMMAND REFERENCE -->", "<!-- END COMMAND REFERENCE -->"
    i, j = g.index(b) + len(b), g.index(e)
    cmds = collect()
    g = g[:i] + "\n" + table(cmds) + "\n" + g[j:]
    open(GUIDE, "w", encoding="utf-8").write(g)
    print(f"wrote {GUIDE}: {len(cmds)} commands")

if __name__ == "__main__":
    main()
