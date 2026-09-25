// Oanarina Archi Tool command-line runner — GPL-3.0-or-later
// Python bridge (SCR-004): a pure-Python module `archi` (standard library only) that drives archi-cli's MCP server over
// stdio and offers the same calls as the JavaScript `archi` object. `archi-cli --python-module DIR` writes archi.py;
// `archi-cli [file.archi] --py script.py [args…]` runs a script with the module on its path (the drawing is saved at the
// end when a file was given).
import Foundation
import ArchiCore

enum PythonBridge {
    static let module = #"""
"""archi — Python bridge to Oanarina Archi Tool.

Drives `archi-cli --mcp` (Model Context Protocol over stdio) and offers the same calls as the JavaScript `archi` object:

    import archi
    doc = archi.open("house.archi")          # or use the module functions on the default document
    doc.run("WALL 0,0 5000,0 ")
    wall = doc.add_element({"type": "wall", "start": [0, 0], "end": [0, 4000]})[0]
    doc.add_element({"type": "door", "hostWall": wall, "offset": 1500})
    print(len(doc.entities()), doc.summary()["counts"])
    doc.save()

Standard library only (Python 3.8+). The archi-cli executable comes from $ARCHI_CLI, the PATH, or the app bundle.
"""
import atexit, json, os, shutil, subprocess

__all__ = ["ArchiError", "Document", "open", "run", "summary", "doc", "entities", "elements", "add", "add_element",
           "update", "remove", "save", "export", "undo", "commands", "call", "get_var", "set_var"]

class ArchiError(RuntimeError):
    pass

def _cli():
    for c in (os.environ.get("ARCHI_CLI"), shutil.which("archi-cli"), "/Applications/Oanarina Archi Tool.app/Contents/MacOS/archi-cli"):
        if c and os.path.exists(c):
            return c
    raise ArchiError("archi-cli not found: set ARCHI_CLI")

class Document:
    def __init__(self, path=None, cli=None):
        self.path = path
        args = [cli or _cli(), "--mcp"] + ([path] if path else [])
        self._proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                      text=True, encoding="utf-8", bufsize=1)
        self._id = 0
        self._request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                     "clientInfo": {"name": "archi.py", "version": "1.0"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, obj):
        self._proc.stdin.write(json.dumps(obj) + "\n")
        self._proc.stdin.flush()

    def _request(self, method, params):
        self._id += 1
        rid = self._id
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            line = self._proc.stdout.readline()
            if not line:
                raise ArchiError("archi-cli exited unexpectedly")
            msg = json.loads(line)
            if msg.get("id") == rid:
                if "error" in msg:
                    raise ArchiError(msg["error"].get("message", "error"))
                return msg.get("result") or {}

    def call(self, tool, **args):
        """Calls any MCP tool of archi-cli (see docs/AGENT-API.md) and returns its JSON result."""
        r = self._request("tools/call", {"name": tool, "arguments": {k: v for k, v in args.items() if v is not None}})
        text = (r.get("content") or [{}])[0].get("text", "")
        if r.get("isError"):
            raise ArchiError(text[7:] if text.startswith("Error: ") else text)
        if "structuredContent" in r:
            return r["structuredContent"]
        try:
            return json.loads(text)
        except ValueError:
            return text

    # Same names as the JavaScript API.
    def run(self, command):
        """Runs command line(s), e.g. run("CIRCLE 0,0 500"); returns the log lines."""
        return self.call("run_command", command=command).get("log", [])
    def summary(self): return self.call("get_document_summary")
    def doc(self): return self.call("get_document")
    def entities(self, type=None, layer=None, limit=None): return self.call("list_entities", type=type, layer=layer, limit=limit)["entities"]
    def elements(self, type=None, level=None): return self.call("list_elements", type=type, level=level)["elements"]
    def add(self, entity): return self.call("add_entity", entity=entity)["ids"]
    def add_element(self, element): return self.call("add_element", element=element)["ids"]
    def update(self, id, patch): return self.call("update_entity", id=id, patch=patch)
    def remove(self, ids): return self.call("delete", ids=list(ids) if isinstance(ids, (list, tuple, set)) else [ids])["deleted"]
    def save(self, path=None): return self.call("save", path=path)["path"]
    def export(self, path, format=None, level=None): return self.call("export", path=path, format=format, level=level)
    def undo(self): return self.call("undo")
    def commands(self, category=None): return self.call("list_commands", category=category)
    def get_var(self, name):
        d = self.doc()
        return ((d.get("document") or d).get("variables") or {}).get(name.upper())
    def set_var(self, name, value): return self.run("SETVAR " + name + " " + str(value))

    def close(self):
        if self._proc and self._proc.poll() is None:
            try:
                self._proc.stdin.close()
                self._proc.wait(timeout=10)
            except Exception:
                self._proc.kill()
        self._proc = None

    def __enter__(self): return self
    def __exit__(self, *exc): self.close()

_default = None

def open(path=None, cli=None):
    """Opens (or starts, if it does not exist yet) a drawing and makes it the default document."""
    global _default
    if _default is not None:
        _default.close()
    _default = Document(path, cli)
    return _default

def _doc():
    global _default
    if _default is None:
        _default = Document(os.environ.get("ARCHI_FILE") or None)
    return _default

@atexit.register
def _finish():
    if _default is not None and _default._proc is not None:
        if os.environ.get("ARCHI_AUTOSAVE") == "1" and os.environ.get("ARCHI_FILE"):
            try:
                _default.save()
            except ArchiError:
                pass
        _default.close()

def run(command): return _doc().run(command)
def summary(): return _doc().summary()
def doc(): return _doc().doc()
def entities(type=None, layer=None, limit=None): return _doc().entities(type, layer, limit)
def elements(type=None, level=None): return _doc().elements(type, level)
def add(entity): return _doc().add(entity)
def add_element(element): return _doc().add_element(element)
def update(id, patch): return _doc().update(id, patch)
def remove(ids): return _doc().remove(ids)
def save(path=None): return _doc().save(path)
def export(path, format=None, level=None): return _doc().export(path, format, level)
def undo(): return _doc().undo()
def commands(category=None): return _doc().commands(category)
def call(tool, **args): return _doc().call(tool, **args)
def get_var(name): return _doc().get_var(name)
def set_var(name, value): return _doc().set_var(name, value)
"""#

    static func writeModule(to dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("archi.py")
        try module.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    static func selfPath() -> String {
        let a = CommandLine.arguments[0]
        if a.hasPrefix("/") { return a }
        if let p = Bundle.main.executablePath { return p }
        return FileManager.default.currentDirectoryPath + "/" + a
    }

    /// Runs `script` with python3: archi.py on PYTHONPATH, ARCHI_CLI = this executable, ARCHI_FILE = the drawing.
    static func run(script: URL, file: URL?, args: [String]) -> Int32 {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-py-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        do { _ = try writeModule(to: dir) } catch { eprint("Cannot write the archi module: \(error.localizedDescription)"); return 1 }
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", script.path] + args
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = dir.path + (env["PYTHONPATH"].map { ":" + $0 } ?? "")
        env["ARCHI_CLI"] = selfPath()
        if let file { env["ARCHI_FILE"] = file.path; env["ARCHI_AUTOSAVE"] = "1" }
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        do { try p.run() } catch { eprint("Cannot start python3: \(error.localizedDescription)"); return 1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
