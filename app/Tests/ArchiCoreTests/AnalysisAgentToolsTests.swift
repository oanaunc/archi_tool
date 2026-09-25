// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Agent analysis tools (library) and an end-to-end run of the `archi-cli --mcp` server and batch conversion.
final class AnalysisAgentToolsTests: XCTestCase {
    func sample() -> ArchiDocument {
        var d = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 6000), Vec2(0, 6000)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300)), material: "Brick")) }
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 4000, width: 1500, height: 1200, sill: 900)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: walls[1], offset: 3000, width: 1000, height: 2100)))
        _ = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), material: "Concrete")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(150, 150), Vec2(7850, 150), Vec2(7850, 5850), Vec2(150, 5850)], name: "Studio", number: "1")))
        _ = d.addElement(.column(ColumnGeom(position: Vec2(4000, 3000), height: 3000)), material: "Concrete")
        return d
    }

    func testAgentToolsReturnJSON() throws {
        let d = sample()
        for def in AgentTools.definitions {
            let name = def["name"] as! String
            var args: [String: Any] = [:]
            if name == "ids_check" { continue } // needs an .ids file (covered by IOIDSTests)
            if name == "schedule" { args["kind"] = "walls" }
            if name == "sun_path" { args["date"] = "2025-06-21" }
            let r = try AgentTools.call(name, args, doc: d)
            if name == "plan_svg" { XCTAssertTrue((r as? String)?.contains("<svg") ?? false); continue }
            XCTAssertTrue(JSONSerialization.isValidJSONObject(r), "\(name) result is not JSON")
        }
        let hl = try AgentTools.call("heat_loss", ["indoor": 21, "outdoor": -12], doc: d) as! [String: Any]
        XCTAssertEqual(hl["deltaT_K"] as? Double, 33)
        XCTAssertGreaterThan(hl["designLoad_W"] as? Double ?? 0, 0)
        let cc = try AgentTools.call("code_check", ["rules": ["minRoomArea": 100]], doc: d) as! [String: Any]
        XCTAssertEqual(cc["count"] as? Int, 1)
        let csv = try AgentTools.call("schedule", ["kind": "walls", "format": "csv"], doc: d) as! String
        XCTAssertTrue(csv.hasPrefix("id,type"))
        XCTAssertThrowsError(try AgentTools.call("schedule", ["kind": "chairs"], doc: d))
        XCTAssertThrowsError(try AgentTools.call("nope", [:], doc: d))
        let sm = try AgentTools.call("structural_model", ["solve": true], doc: d) as! [String: Any]
        XCTAssertNotNil(sm["analysis"])
    }

    /// Path of the archi-cli executable built next to the test bundle (skips when the product is not built).
    func cli() throws -> URL {
        let dir = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let url = dir.appendingPathComponent("archi-cli")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("archi-cli is not built at \(url.path)") }
        return url
    }

    func run(_ exe: URL, _ args: [String], input: String) throws -> (out: String, status: Int32) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        try inPipe.fileHandleForWriting.close()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }

    func testMCPServerIntegration() throws {
        let exe = try cli()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("m.archi")
        try ArchiFile.encode(sample()).write(to: file)
        func req(_ id: Int, _ method: String, _ params: [String: Any]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]), as: UTF8.self)
        }
        let input = [
            req(1, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]]),
            "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
            req(2, "tools/list", [:]),
            req(3, "tools/call", ["name": "run_command", "arguments": ["command": "LINE 0,0 1000,0 \nCIRCLE 500,500 200"], "_meta": ["progressToken": "p1"]]),
            req(4, "tools/call", ["name": "heat_loss", "arguments": [:]]),
            req(5, "tools/call", ["name": "plan_svg", "arguments": ["width": 400, "path": dir.appendingPathComponent("plan.svg").path]]),
            req(6, "tools/call", ["name": "code_check", "arguments": ["rules": ["minRoomArea": 100]]]),
            req(7, "tools/call", ["name": "export", "arguments": ["path": dir.appendingPathComponent("m.step").path, "format": "step"]]),
            req(8, "logging/setLevel", ["level": "info"]),
            req(9, "tools/call", ["name": "run_command", "arguments": ["command": "LINE 0,0 0,1000 ", "maxLines": 1]]),
        ].joined(separator: "\n") + "\n"
        let (out, status) = try run(exe, ["--mcp", file.path], input: input)
        XCTAssertEqual(status, 0)
        let msgs = out.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        func result(_ id: Int) -> [String: Any]? { msgs.first { ($0["id"] as? Int) == id }?["result"] as? [String: Any] }
        XCTAssertNotNil((result(1)?["capabilities"] as? [String: Any])?["logging"])
        let names = ((result(2)?["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        for n in ["run_command", "heat_loss", "daylight", "code_check", "structural_model", "plan_svg", "schedule", "level_areas"] { XCTAssertTrue(names.contains(n), n) }
        // Streaming: progress notifications with the token arrive before the result.
        let progress = msgs.filter { ($0["method"] as? String) == "notifications/progress" }
        XCTAssertFalse(progress.isEmpty)
        XCTAssertTrue(progress.allSatisfy { (($0["params"] as? [String: Any])?["progressToken"] as? String) == "p1" })
        let resultIndex = msgs.firstIndex { ($0["id"] as? Int) == 3 }!, firstProgress = msgs.firstIndex { ($0["method"] as? String) == "notifications/progress" }!
        XCTAssertLessThan(firstProgress, resultIndex)
        XCTAssertEqual(result(3)?["isError"] as? Bool, false)
        XCTAssertNotNil((result(4)?["structuredContent"] as? [String: Any])?["designLoad_W"])
        let svgText = ((result(5)?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(svgText.contains("<svg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("plan.svg").path))
        XCTAssertEqual((result(6)?["structuredContent"] as? [String: Any])?["count"] as? Int, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.step").path))
        // Logging notifications after logging/setLevel; the log is capped to maxLines.
        XCTAssertTrue(msgs.contains { ($0["method"] as? String) == "notifications/message" })
        let sc9 = result(9)?["structuredContent"] as? [String: Any]
        XCTAssertEqual((sc9?["log"] as? [Any])?.count, 1)
    }

    func testBatchConversion() throws {
        let exe = try cli()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-conv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.archi"), b = dir.appendingPathComponent("b.archi"), bad = dir.appendingPathComponent("c.archi")
        try ArchiFile.encode(sample()).write(to: a)
        try ArchiFile.encode(ArchiDocument()).write(to: b)
        try Data("not json".utf8).write(to: bad)
        let outDir = dir.appendingPathComponent("out")
        let (out, status) = try run(exe, ["--convert", "dxf", a.path, b.path, bad.path, "--outdir", outDir.path], input: "")
        XCTAssertEqual(status, 1, "one file fails")
        XCTAssertTrue(out.contains("Converted 2 of 3"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("a.dxf").path))
        let back = try DXFReader.read(try String(contentsOf: outDir.appendingPathComponent("a.dxf"), encoding: .utf8))
        XCTAssertFalse(back.entities.isEmpty)
    }
}
