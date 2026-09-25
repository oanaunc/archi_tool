// Oanarina Archi Tool — GPL-3.0-or-later
// End-to-end tests of the archi-cli JavaScript runner (SCR-006, SCR-020): the built archi-cli binary loads a plugin
// folder, runs plugin commands from a script, runs a JavaScript file that registers a command, and writes the result.
import XCTest
@testable import ArchiCore

final class IOPluginCLITests: XCTestCase {
    /// The archi-cli executable built next to the test bundle (swift test builds every product), else the app bundle's copy.
    static func cliBinary() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        for b in Bundle.allBundles where b.bundleURL.pathExtension == "xctest" {
            candidates.append(b.bundleURL.deletingLastPathComponent().appendingPathComponent("archi-cli"))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(root.appendingPathComponent(".build/debug/archi-cli"))
        candidates.append(root.deletingLastPathComponent().appendingPathComponent("build/Oanarina Archi Tool.app/Contents/MacOS/archi-cli"))
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    func run(_ args: [String], stdin: String = "") throws -> (status: Int32, out: String, err: String) {
        guard let bin = Self.cliBinary() else { throw XCTSkip("archi-cli binary not built") }
        let p = Process()
        p.executableURL = bin
        p.arguments = args
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8)); try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile(), err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    func tmp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-cli-js-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testPluginCommandsRunFromScriptThroughArchiCLI() throws {
        let dir = try tmp()
        let plug = dir.appendingPathComponent("plugins/roomtools", isDirectory: true)
        try FileManager.default.createDirectory(at: plug, withIntermediateDirectories: true)
        try """
        {"id": "test.roomtools", "name": "Room Tools", "main": "main.js",
         "commands": [{"name": "ROOMBOX", "aliases": ["RBX"], "function": "roomBox", "summary": "Room outline"},
                      {"name": "COUNTLINES", "function": "countLines", "modifies": false}]}
        """.write(to: plug.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try """
        function roomBox() {
          const id = archi.add({type: "polyline", vertices: [[0,0],[4000,0],[4000,3000],[0,3000]], closed: true, layer: "A-AREA"});
          archi.addElement({type: "wall", start: [0, 0], end: [4000, 0], thickness: 200, height: 2800});
          archi.setVar("LASTROOM", String(id));
          archi.print("Room outline #" + id);
          archi.run("CIRCLE 2000,1500 500");
        }
        function countLines() { archi.print("objects=" + archi.entities().length + " walls=" + archi.elements("wall").length); }
        """.write(to: plug.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        let scr = dir.appendingPathComponent("run.scr")
        try "ROOMBOX\nRBX\nCOUNTLINES\n".write(to: scr, atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("out.archi")
        let r = try run(["--plugins", dir.appendingPathComponent("plugins").path, "--script", scr.path, "--out", out.path])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.contains("Room outline #"), r.out)
        let doc = try ArchiFile.decode(Data(contentsOf: out))
        XCTAssertEqual(doc.entities.filter { $0.layer == "A-AREA" }.count, 2, "ROOMBOX and its alias RBX both ran")
        XCTAssertEqual(doc.entities.filter { $0.typeName == "circle" }.count, 2, "queued archi.run lines ran after each command")
        XCTAssertEqual(doc.elements.count, 2)
        XCTAssertNotNil(doc.variable("LASTROOM"))
        XCTAssertTrue(r.out.contains("objects=4 walls=2"), r.out)
    }

    func testJavaScriptFileRegistersCommandsAndEdits() throws {
        let dir = try tmp()
        let js = dir.appendingPathComponent("tools.js")
        try """
        function grid() {
          const n = Number(archi.getVar("GRIDN") || 3);
          for (let i = 0; i < n; i++) archi.add({type: "line", a: [i * 1000, 0], b: [i * 1000, 5000], layer: "S-GRID"});
          archi.print("grid " + n);
        }
        function builtinClash() {}
        archi.registerCommand("JSGRID", grid, {aliases: ["JG"], summary: "Draws grid lines"});
        archi.registerCommand("LINE", "builtinClash");
        if (archi.mode === "load") { archi.add({type: "circle", center: [0, 0], radius: 100}); archi.setVar("GRIDN", "4"); }
        console.log({mode: archi.mode});
        """.write(to: js, atomically: true, encoding: .utf8)
        let scr = dir.appendingPathComponent("s.scr")
        try "JSGRID\nJG\n".write(to: scr, atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("grid.archi")
        let r = try run(["--js", js.path, "--script", scr.path, "--out", out.path])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.contains("Registered command JSGRID"), r.out)
        XCTAssertTrue(r.out.contains("LINE is a built-in command"), r.out)
        XCTAssertTrue(r.out.contains("{\"mode\":\"load\"}"), r.out)
        let doc = try ArchiFile.decode(Data(contentsOf: out))
        XCTAssertEqual(doc.entities.filter { $0.layer == "S-GRID" }.count, 8, "JSGRID and alias JG each drew 4 lines")
        XCTAssertEqual(doc.entities.filter { $0.typeName == "circle" }.count, 1, "top-level code guarded by archi.mode ran once")
    }

    func testJavaScriptErrorsFailTheRun() throws {
        let dir = try tmp()
        let js = dir.appendingPathComponent("bad.js")
        try "archi.add({type: 'nonsense'}); undefinedFunction();".write(to: js, atomically: true, encoding: .utf8)
        let r = try run(["--js", js.path])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertTrue(r.err.contains("bad.js"), r.err)
    }

    @MainActor func testScriptCommandRegistryRules() throws {
        let reg = CommandRegistry()
        reg.ensureBuiltins()
        let plugins = PluginRegistry(folders: [])
        let src = URL(fileURLWithPath: "/tmp/tools.js")
        XCTAssertEqual(try plugins.registerScriptCommand(PluginCommand(name: "myCmd", aliases: ["MC", "L"], function: "f"), source: "function f(){}", sourceURL: src, into: reg), "MYCMD")
        XCTAssertNotNil(reg.lookup("MC"))
        XCTAssertEqual(reg.lookup("L")?.name, "LINE", "aliases of built-ins are not taken over")
        XCTAssertThrowsError(try plugins.registerScriptCommand(PluginCommand(name: "CIRCLE", function: "f"), source: "", sourceURL: src, into: reg))
        XCTAssertThrowsError(try plugins.registerScriptCommand(PluginCommand(name: "bad name", function: "f"), source: "", sourceURL: src, into: reg))
        // Re-registering from the same script updates it; another script cannot take it.
        XCTAssertNoThrow(try plugins.registerScriptCommand(PluginCommand(name: "MYCMD", summary: "v2", function: "g"), source: "function g(){}", sourceURL: src, into: reg))
        XCTAssertEqual(reg.lookup("MYCMD")?.summary, "v2")
        XCTAssertThrowsError(try plugins.registerScriptCommand(PluginCommand(name: "MYCMD", function: "g"), source: "", sourceURL: URL(fileURLWithPath: "/tmp/other.js"), into: reg))
        XCTAssertEqual(plugins.plugins.first?.id, "script.tools")
        plugins.reload()
        XCTAssertEqual(plugins.plugins.count, 1, "script commands survive a plugin rescan")
        plugins.unregisterScriptCommands(script: src, registry: reg)
        XCTAssertTrue(plugins.plugins.isEmpty)
    }
}

final class IOPythonBridgeTests: XCTestCase {
    func python() -> String? {
        for p in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"] where FileManager.default.isExecutableFile(atPath: p) {
            // /usr/bin/python3 is a stub without the command line tools: check it runs.
            let t = Process(); t.executableURL = URL(fileURLWithPath: p); t.arguments = ["-c", "import json"]
            t.standardOutput = Pipe(); t.standardError = Pipe()
            if (try? t.run()) != nil { t.waitUntilExit(); if t.terminationStatus == 0 { return p } }
        }
        return nil
    }

    func testPythonScriptDrivesTheDocument() throws {
        guard python() != nil else { throw XCTSkip("python3 not available") }
        guard let bin = IOPluginCLITests.cliBinary() else { throw XCTSkip("archi-cli binary not built") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-py-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("build.py")
        try """
        import sys, archi
        log = archi.run("LINE 0,0 1000,0 ")
        assert any("LINE" in l for l in log), log
        w = archi.add_element({"type": "wall", "start": [0, 0], "end": [5000, 0], "thickness": 200, "height": 2800})[0]
        archi.add_element({"type": "door", "hostWall": w, "offset": 1500})
        ids = archi.add([{"type": "circle", "center": [0, 0], "radius": 250}, {"type": "text", "position": [0, -500], "height": 250, "content": sys.argv[1]}])
        archi.update(ids[0], {"radius": 400})
        assert len(archi.entities(type="circle")) == 1
        assert archi.elements(type="door")[0]["geometry"]["hostWall"] == w
        try:
            archi.update(99999, {"radius": 1})
            raise SystemExit("expected an error")
        except archi.ArchiError:
            pass
        print("counts", sorted(archi.summary().keys()))
        """.write(to: script, atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("house.archi")
        let p = Process()
        p.executableURL = bin
        p.arguments = [out.path, "--py", script.path, "Hello from Python"]
        let pipe = Pipe(), err = Pipe()
        p.standardOutput = pipe; p.standardError = err
        try p.run()
        let stdout = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, stdout + stderr)
        XCTAssertTrue(stdout.contains("counts"), stdout)
        let doc = try ArchiFile.decode(Data(contentsOf: out))
        XCTAssertEqual(doc.entities.count, 3)
        XCTAssertEqual(doc.elements.count, 2)
        XCTAssertTrue(doc.entities.contains { if case .text(let t) = $0.geometry { return t.content == "Hello from Python" }; return false })
        XCTAssertTrue(doc.entities.contains { if case .circle(let c) = $0.geometry { return c.radius == 400 }; return false })
        // --python-module writes the module.
        let q = Process(); q.executableURL = bin; q.arguments = ["--python-module", dir.path]; q.standardOutput = Pipe()
        try q.run(); q.waitUntilExit()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("archi.py").path))
    }
}

final class IOAutomationTests: XCTestCase {
    func testWildcards() {
        XCTAssertTrue(AutomationWatcher.matches("Plan A.DXF", "*.dxf"))
        XCTAssertTrue(AutomationWatcher.matches("a1.ifc", "a?.ifc"))
        XCTAssertFalse(AutomationWatcher.matches("a12.ifc", "a?.ifc"))
        XCTAssertFalse(AutomationWatcher.matches("x.dxf.bak", "*.dxf"))
    }

    @MainActor func testRulesProcessNewAndChangedFilesOnce() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var d = ArchiDocument(); d.add(.line(LineGeom(.zero, Vec2(1000, 0))))
        try DXFWriter.write(d).write(to: dir.appendingPathComponent("site.dxf"), atomically: true, encoding: .utf8)
        try "ignore".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let rules = """
        {"interval": 1, "rules": [{"name": "convert", "pattern": "*.dxf",
          "job": {"input": "{file}", "commands": ["CIRCLE 0,0 100"], "outputs": ["out/{name}.archi"]}, "webhook": "http://127.0.0.1:9/none"}]}
        """
        let w = try AutomationWatcher(folder: dir, rulesData: Data(rules.utf8))
        XCTAssertEqual(w.pending().map(\.file.lastPathComponent), ["site.dxf"])
        let r = await w.runOnce()
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0]["ok"] as? Bool, true, "\(r)")
        XCTAssertEqual(r[0]["webhook"] as? Int, 0, "unreachable webhook reports 0, the job still succeeds")
        let out = try ArchiFile.decode(Data(contentsOf: dir.appendingPathComponent("out/site.archi")))
        XCTAssertEqual(out.entities.count, 2)
        // Remembered: nothing pending, also for a new watcher (state file).
        XCTAssertTrue(w.pending().isEmpty)
        XCTAssertTrue(try AutomationWatcher(folder: dir, rulesData: Data(rules.utf8)).pending().isEmpty)
        // A changed file is processed again.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: dir.appendingPathComponent("site.dxf").path)
        XCTAssertEqual(w.pending().count, 1)
        // Through archi-cli --watch --once.
        if let bin = IOPluginCLITests.cliBinary() {
            let rf = dir.appendingPathComponent("rules.json")
            try rules.write(to: rf, atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = bin; p.arguments = ["--watch", dir.path, "--rules", rf.path, "--once"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            try p.run()
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0, text)
            XCTAssertTrue(text.contains("\"ok\":true"), text)
        }
    }
}

final class IORollPlotTests: XCTestCase {
    func testRollLayoutRotatesToFitAndSetsPageSize() {
        let roll = HPGLExporter.RollMedia(width: 914, margin: 10)
        // A 1200 × 600 mm plot: fits across the roll in normal orientation (600 ≤ 894) → length 1220.
        var l = roll.layout(paperWidth: 1200, paperHeight: 600)
        XCTAssertFalse(l.rotated); XCTAssertEqual(l.length, 1220); XCTAssertTrue(l.fits)
        // 600 × 1200: rotated so the long side runs along the roll.
        l = roll.layout(paperWidth: 600, paperHeight: 1200)
        XCTAssertTrue(l.rotated); XCTAssertEqual(l.length, 1220); XCTAssertTrue(l.fits)
        XCTAssertFalse(roll.layout(paperWidth: 2000, paperHeight: 1500).fits)
        var d = ArchiDocument()
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(60_000, 120_000))))
        let entries = DrawListBuilder.entries(doc: d, options: DrawOptions(level: 0))
        let b = BBox2(min: .zero, max: Vec2(60_000, 120_000))
        let plt = HPGLExporter.export(entries, bounds: b, scale: 100, roll: roll)
        XCTAssertTrue(plt.hasPrefix("IN;\nPS48800,36560;"), String(plt.prefix(40)))
        // Rotated: the far corner (600, 1200 mm) lands at x = 1200 mm + margin, y = margin.
        XCTAssertTrue(plt.contains("48400,400"), plt)
    }
}
