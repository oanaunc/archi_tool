// Oanarina Archi Tool — GPL-3.0-or-later
// Agent/scripting API: generated reference with executed samples (SCR-009), end-to-end tests of every core MCP method
// of archi-cli (SCR-017), CLI file options, licensing headers (SYS-023) and the no-telemetry / offline policy
// (SYS-032, SYS-034), Unicode text through the exchange formats (SYS-027).
import XCTest
@testable import ArchiCore

final class AnalysisAgentAPITests: XCTestCase {
    static var appRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    func cli() throws -> URL {
        let url = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("archi-cli")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("archi-cli is not built at \(url.path)") }
        return url
    }

    func run(_ exe: URL, _ args: [String], input: String = "") throws -> (out: String, status: Int32) {
        let p = Process()
        p.executableURL = exe; p.arguments = args
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        try inPipe.fileHandleForWriting.close()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }

    func tmp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("archi-api-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: SCR-009

    @MainActor func testAPIReferenceDocumentsEverythingAndSamplesRun() async {
        let md = APIReference.markdown()
        CommandRegistry.shared.ensureBuiltins()
        for c in CommandRegistry.shared.sorted { XCTAssertTrue(md.contains("| `\(c.name)` |"), c.name) }
        for t in AgentTools.definitions { XCTAssertTrue(md.contains("### `\(t["name"] as! String)`")) }
        XCTAssertTrue(md.contains("`.e57`")); XCTAssertTrue(md.contains("## Sample scripts"))
        let r = await APIReference.runSamples()
        XCTAssertEqual(r.count, APIReference.samples.count)
        for x in r { XCTAssertTrue(x.passed, "\(x.title): \(x.log.joined(separator: " | "))") }
        // Expected outcomes of the samples.
        let ed = Editor()
        for l in APIReference.samples[1].script { await ed.run(l) }
        XCTAssertEqual(ed.doc.elements.filter { if case .wall = $0.geometry { return true }; return false }.count, 4)
        XCTAssertTrue(ed.doc.elements.contains { if case .space = $0.geometry { return true }; return false })
        let ed2 = Editor()
        for l in APIReference.samples[2].script { await ed2.run(l) }
        XCTAssertEqual(ed2.doc.entities.last?.layer, "NOTES")
    }

    // MARK: SCR-017

    func testEveryCoreMCPMethodEndToEnd() throws {
        let exe = try cli()
        let dir = try tmp()
        let file = dir.appendingPathComponent("m.archi")
        try ArchiFile.encode(AnalysisAgentToolsTests().sample()).write(to: file)
        var dxf = ArchiDocument(); dxf.add(.circle(CircleGeom(.zero, 50)))
        try DXFWriter.write(dxf).write(to: dir.appendingPathComponent("in.dxf"), atomically: true, encoding: .utf8)
        var id = 0
        var lines: [String] = []
        func call(_ name: String, _ args: [String: Any]) -> Int {
            id += 1
            lines.append(String(decoding: try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": name, "arguments": args]]), as: UTF8.self))
            return id
        }
        lines.append("{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"1\"}}}")
        let cRun = call("run_command", ["command": "LINE 0,0 1000,0 "])
        let cSummary = call("get_document_summary", [:])
        let cDoc = call("get_document", [:])
        let cAddE = call("add_entity", ["entity": ["type": "circle", "center": [0, 0], "radius": 300, "layer": "NEW"]])
        let cAddEl = call("add_element", ["element": ["type": "wall", "start": [0, 0], "end": [3000, 0], "thickness": 200]])
        let cList = call("list_entities", ["type": "circle"])
        let cListEl = call("list_elements", ["type": "wall"])
        let cUpd = call("update_entity", ["id": 1, "patch": ["name": "North wall"]])
        let cDel = call("delete", ["ids": [5]])
        let cUndo = call("undo", [:])
        let cImp = call("import_file", ["path": dir.appendingPathComponent("in.dxf").path])
        let cExp = call("export", ["path": dir.appendingPathComponent("out.ifc").path, "format": "ifc"])
        let cCmds = call("list_commands", [:])
        let cTake = call("takeoff", [:])
        let cCost = call("cost_estimate", ["prices": ["currency": "EUR", "wall:area": 45, "door:count": 350]])
        let cRooms = call("room_schedule", [:])
        let cClash = call("clash", [:])
        let cCheck = call("check_model", [:])
        let cSun = call("sun_position", ["datetime": "2026-06-21T12:00:00+03:00"])
        let cBatch = call("run_batch", ["jobs": [["input": file.path, "outputs": [dir.appendingPathComponent("b.dxf").path]]]])
        let cFile = call("file_check", [:])
        let cGen = call("generative_design", ["program": "Living 20, Kitchen 10, Bath 5", "generations": 5, "limit": 2])
        let cWind = call("wind_case", ["path": dir.appendingPathComponent("wind").path, "speed": 6])
        let cSave = call("save", ["path": dir.appendingPathComponent("saved.archi").path])
        let (out, status) = try run(exe, ["--mcp", file.path], input: lines.joined(separator: "\n") + "\n")
        XCTAssertEqual(status, 0)
        let msgs = out.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        func res(_ i: Int, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
            guard let m = msgs.first(where: { ($0["id"] as? Int) == i }) else { XCTFail("no response \(i)", file: file, line: line); return [:] }
            XCTAssertNil(m["error"], "protocol error for call \(i)", file: file, line: line)
            let r = m["result"] as? [String: Any] ?? [:]
            XCTAssertEqual(r["isError"] as? Bool, false, "\(((r["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "") (call \(i))", file: file, line: line)
            return r
        }
        func sc(_ i: Int) -> Any? { res(i)["structuredContent"] }
        for i in [cRun, cSummary, cDoc, cAddE, cAddEl, cList, cListEl, cUpd, cDel, cUndo, cImp, cExp, cCmds, cTake, cCost, cRooms, cClash, cCheck, cSun, cBatch, cFile, cGen, cWind, cSave] { _ = res(i) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("out.ifc").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("b.dxf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("wind/system/blockMeshDict").path))
        XCTAssertEqual((sc(cFile) as? [String: Any])?["lossless"] as? Bool, true)
        XCTAssertFalse(((sc(cGen) as? [String: Any])?["designs"] as? [Any] ?? []).isEmpty)
        // The saved file has the edits: the line, the circle, the wall, the imported DXF circle, the renamed element.
        let saved = try DocumentIO.read(dir.appendingPathComponent("saved.archi"))
        XCTAssertTrue(saved.entities.contains { if case .line = $0.geometry { return true }; return false })
        XCTAssertEqual(saved.entities.filter { if case .circle = $0.geometry { return true }; return false }.count, 2)
        XCTAssertEqual(saved.elements.filter { if case .wall = $0.geometry { return true }; return false }.count, 5)
        XCTAssertEqual(saved.element(1)?.name, "North wall")
        XCTAssertNotNil(saved.element(5), "delete was undone")
    }

    // MARK: CLI file options

    func testCLIFileOptions() throws {
        let exe = try cli()
        let dir = try tmp()
        let lic = try run(exe, ["--license"])
        XCTAssertEqual(lic.status, 0); XCTAssertTrue(lic.out.contains("GPL-3.0-or-later")); XCTAssertTrue(lic.out.contains("no telemetry"))
        let doc = IOLifecycleTests.richDocument()
        let f = dir.appendingPathComponent("d.archi")
        try ArchiFile.encode(doc).write(to: f)
        let v = try run(exe, ["--verify", f.path])
        XCTAssertEqual(v.status, 0, v.out); XCTAssertTrue(v.out.contains("round trip OK"))
        let m = try run(exe, ["--metadata", f.path])
        XCTAssertEqual(m.status, 0)
        let meta = try JSONSerialization.jsonObject(with: Data(m.out.utf8)) as? [String: Any]
        XCTAssertEqual(meta?["kMDItemTitle"] as? String, doc.info.name)
        let old = dir.appendingPathComponent("old.archi")
        try Data("{\"app\":\"Oanarina Archi Tool\",\"formatVersion\":2,\"document\":{\"formatVersion\":2,\"entities\":[]}}".utf8).write(to: old)
        let u = try run(exe, ["--upgrade", old.path, f.path])
        XCTAssertEqual(u.status, 0); XCTAssertTrue(u.out.contains("format 2 → \(ArchiDocument.currentFormatVersion)")); XCTAssertTrue(u.out.contains("already format"))
        let refURL = dir.appendingPathComponent("API.md")
        XCTAssertEqual(try run(exe, ["--api-reference", refURL.path]).status, 0)
        let ref = try String(contentsOf: refURL, encoding: .utf8)
        XCTAssertTrue(ref.contains("### `run_command`"), "CLI tools included"); XCTAssertTrue(ref.contains("`BREPOUT`"))
        let s = try run(exe, ["--run-samples"])
        XCTAssertEqual(s.status, 0, s.out)
        // A new drawing from a template, written out.
        let t = dir.appendingPathComponent("office.architemplate")
        try ArchiTemplate.save(doc, to: t, description: "office")
        let outF = dir.appendingPathComponent("new.archi")
        let n = try run(exe, ["--template", t.path, "--out", outF.path], input: "LINE 0,0 10,10 \n")
        XCTAssertEqual(n.status, 0)
        let nd = try DocumentIO.read(outF)
        XCTAssertEqual(nd.info.name, "Untitled Project")
        XCTAssertEqual(nd.entities.count, doc.entities.count + 1)
        XCTAssertEqual(nd.layers, doc.layers)
    }

    // MARK: SYS-023 / SYS-032 / SYS-034

    func testEverySourceFileCarriesTheGPLHeader() throws {
        let root = Self.appRoot
        let licence = try String(contentsOf: root.deletingLastPathComponent().appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(licence.contains("GNU GENERAL PUBLIC LICENSE") && licence.contains("Version 3"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("docs/THIRD-PARTY.md").path))
        var missing: [String] = []
        let e = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)
        var count = 0
        while let u = e?.nextObject() as? URL {
            guard u.pathExtension == "swift" else { continue }
            count += 1
            let head = (try? String(contentsOf: u, encoding: .utf8))?.split(separator: "\n", maxSplits: 3).prefix(3).joined(separator: "\n") ?? ""
            if !head.contains("GPL-3.0-or-later") { missing.append(u.lastPathComponent) }
        }
        XCTAssertGreaterThan(count, 100)
        XCTAssertEqual(missing, [], "source files without the GPL-3.0-or-later header")
    }

    func testNoTelemetryAndOfflineByDefault() throws {
        // Network APIs are only used by features the user starts explicitly.
        let allowed: Set<String> = ["BCFServer.swift", "Automation.swift", "AgentServer.swift", "AppSelfTestsNav.swift"]
        let patterns = ["URLSession", "NSURLConnection", "import Network", "CFSocketCreate", "CFStreamCreatePairWithSocket"]
        var offenders: [String] = []
        let e = FileManager.default.enumerator(at: Self.appRoot.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)
        while let u = e?.nextObject() as? URL {
            guard u.pathExtension == "swift", let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            if patterns.contains(where: { text.contains($0) }), !allowed.contains(u.lastPathComponent) { offenders.append(u.lastPathComponent) }
            for w in ["telemetry", "analytics", "crashlytics", "sentry"] where text.lowercased().contains("import \(w)") { offenders.append(u.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [])
        // The core works without a network: a full model round trip, exports and analyses need no connection.
        let d = AnalysisAgentToolsTests().sample()
        XCTAssertNoThrow(try ArchiFile.decode(ArchiFile.encode(d)))
        XCTAssertFalse(IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d)).isEmpty)
        XCTAssertNoThrow(try AgentTools.call("heat_loss", [:], doc: d))
    }

    // MARK: SYS-027

    func testUnicodeAndRightToLeftTextThroughFormats() throws {
        let samples = ["שלום עולם", "مرحبا بالعالم", "你好，世界", "Ünïcödé ßçă", "😀 🏠 emoji", "Mixed עברית and English 123"]
        var d = ArchiDocument()
        for (i, s) in samples.enumerated() { d.add(.text(TextGeom(position: Vec2(0, Double(i) * 500), height: 250, content: s))) }
        d.layers.append(Layer(name: "طبقة"))
        // .archi
        XCTAssertEqual(try ArchiFile.decode(ArchiFile.encode(d)), d)
        // DXF (R2000 escapes \U+XXXX; characters outside the BMP as surrogate pairs)
        let back = try DXFReader.read(DXFWriter.write(d))
        let texts = back.entities.compactMap { e -> String? in if case .text(let t) = e.geometry { return t.content }; return nil }
        XCTAssertEqual(texts, samples)
        XCTAssertNotNil(back.layer(named: "طبقة"))
        // SVG keeps the characters (UTF-8) and marks right-to-left runs.
        let svg = SVGExporter.exportLayered(doc: d, entries: DrawListBuilder.entries(doc: d, options: DrawOptions(level: 0)), bounds: BBox2(min: Vec2(-1000, -1000), max: Vec2(10000, 5000)), background: nil, pixelsPerUnit: 1)
        for s in samples.prefix(3) { XCTAssertTrue(svg.contains(s), s) }
        XCTAssertEqual(svg.components(separatedBy: "direction=\"rtl\"").count - 1, 2, "the Hebrew and Arabic lines")
        // Bidirectional classification used by exporters and text measurement.
        XCTAssertEqual(TextDirection.base(of: "שלום"), .rightToLeft)
        XCTAssertEqual(TextDirection.base(of: "Hello שלום"), .leftToRight)
        XCTAssertEqual(TextDirection.base(of: "123 مرحبا"), .rightToLeft)
        XCTAssertEqual(TextDirection.base(of: "123"), .neutral)
    }
}
