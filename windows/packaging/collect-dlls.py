#!/usr/bin/env python3
# Oanarina Archi Tool — GPL-3.0-or-later
# Copies an executable plus every non-system DLL it needs (recursively, read from the PE import tables like
# `dumpbin /dependents`) into a folder, so archi-engine.exe runs on a PC without the Swift toolchain.
# DLLs are searched in the executable's folder, the extra --search folders and PATH (the Swift runtime folder
# that gha-setup-swift puts on PATH). Windows DLLs are skipped, except the Visual C++ runtime (app-local copy).
# Usage: python collect-dlls.py <exe> <out dir> [--search DIR ...]      (needs pefile: pip install pefile)
import os, shutil, sys

try:
    import pefile
except ImportError:
    sys.exit("collect-dlls: pefile is missing (pip install pefile)")

args = sys.argv[1:]
if len(args) < 2:
    sys.exit("usage: collect-dlls.py <exe> <out dir> [--search DIR ...]")
exe, out, rest = args[0], args[1], args[2:]
if not os.path.isfile(exe):
    sys.exit(f"collect-dlls: {exe} not found (did the archi-engine build succeed?)")
search = [os.path.dirname(os.path.abspath(exe))]
while rest:
    flag = rest.pop(0)
    if flag == "--search" and rest:
        search.append(rest.pop(0))
search += [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
windir = os.path.normcase(os.environ.get("SystemRoot", r"C:\Windows"))
system = [os.path.join(windir, "System32"), windir]
VC = ("vcruntime", "msvcp", "concrt", "vccorlib", "ucrtbase")  # app-local VC++ runtime (ucrtbase ships with Windows 10+)
VC_BUNDLE = ("vcruntime", "msvcp", "concrt")

def is_system(path):
    return os.path.normcase(os.path.abspath(path)).startswith(windir)

def find(name):
    low = name.lower()
    if low.startswith(("api-ms-win-", "ext-ms-")):
        return None, "apiset"
    for d in search:
        p = os.path.join(d, name)
        if os.path.isfile(p) and not is_system(p):
            return p, "bundle"
    for d in system:
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p, ("bundle" if low.startswith(VC_BUNDLE) else "system")
    return None, "missing"

def imports(path):
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
                                           pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT"]])
    names = [e.dll.decode() for e in getattr(pe, "DIRECTORY_ENTRY_IMPORT", [])]
    names += [e.dll.decode() for e in getattr(pe, "DIRECTORY_ENTRY_DELAY_IMPORT", [])]
    pe.close()
    return names

os.makedirs(out, exist_ok=True)
shutil.copy2(exe, out)
queue, seen, missing, report = [os.path.abspath(exe)], set(), [], []
while queue:
    cur = queue.pop(0)
    for dll in imports(cur):
        key = dll.lower()
        if key in seen:
            continue
        seen.add(key)
        path, kind = find(dll)
        report.append(f"{os.path.basename(cur):40} -> {dll:45} {kind:7} {path or ''}")
        if kind == "bundle":
            shutil.copy2(path, os.path.join(out, os.path.basename(path)))
            queue.append(path)
        elif kind == "missing":
            missing.append(f"{dll} (needed by {os.path.basename(cur)})")
print("\n".join(report))
print("bundled:", ", ".join(sorted(f for f in os.listdir(out) if f.lower().endswith(".dll"))))
if missing:
    sys.exit("collect-dlls: DLLs not found in the Swift runtime, PATH or System32: " + "; ".join(missing))
