// Oanarina Archi Tool — GPL-3.0-or-later
// MCP resources, prompt templates, extra agent tools and batch jobs (library and archi-cli end to end).
import XCTest
@testable import ArchiCore

final class AnalysisAgentResourcesTests: XCTestCase {
    func sample() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.name = "Studio"
        let pts = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 6000), Vec2(0, 6000)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300)), material: "Brick")) }
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 4000, width: 1500, height: 1200, sill: 900)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: walls[1], offset: 3000, width: 1000, height: 2100)))
        _ = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), material: "Concrete")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(150, 150), Vec2(7850, 150), Vec2(7850, 5850), Vec2(150, 5850)], name: "Studio", number: "1")))
        return d
    }

    func testResourcesAndPrompts() throws {
        var d = sample()
        Markups.add(&d, rect: (Vec2(0, 0), Vec2(1000, 1000)), comment: "Check the corner", author: "Oana")
        let uris = AgentResources.list(d).compactMap { $0["uri"] as? String }
        for u in ["archi://document/summary", "archi://document", "archi://takeoff", "archi://markups", "archi://schedules/rooms", "archi://plan/0"] { XCTAssertTrue(uris.contains(u), u) }
        let s = try AgentResources.read("archi://document/summary", doc: d)
        XCTAssertEqual(s.mimeType, "application/json")
        let js = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.text.utf8)) as? [String: Any])
        XCTAssertEqual(js["name"] as? String, "Studio"); XCTAssertEqual(js["markups"] as? Int, 1)
        XCTAssertNoThrow(try ArchiFile.decode(Data(try AgentResources.read("archi://document", doc: d).text.utf8)))
        XCTAssertTrue(try AgentResources.read("archi://schedules/rooms", doc: d).text.contains("Studio"))
        XCTAssertTrue(try AgentResources.read("archi://plan/0", doc: d).text.contains("inkscape:groupmode"))
        XCTAssertTrue(try AgentResources.read("archi://markups", doc: d).text.contains("Check the corner"))
        XCTAssertTrue(try AgentResources.read("archi://element/1", doc: d).text.contains("wall"))
        XCTAssertTrue(try AgentResources.read("archi://takeoff/phases", doc: d).text.hasPrefix("phase,work,level"))
        XCTAssertThrowsError(try AgentResources.read("archi://nope", doc: d))
        XCTAssertThrowsError(try AgentResources.read("archi://schedules/cars", doc: d))
        XCTAssertEqual(AgentResources.templates.count, 3)
        // Prompts.
        let names = AgentPrompts.definitions.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["review_model", "quantity_report", "energy_advice", "draw_room", "resolve_markups"])
        for n in ["review_model", "quantity_report", "energy_advice", "resolve_markups"] {
            let p = try AgentPrompts.get(n, arguments: [:], doc: d)
            let text = (((p["messages"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["text"] as? String) ?? ""
            XCTAssertTrue(text.contains("Studio"), n)
        }
        let room = try AgentPrompts.get("draw_room", arguments: ["name": "Office", "width": "4000", "depth": "3000", "origin": "100,200"], doc: d)
        XCTAssertTrue(((room["messages"] as? [[String: Any]])?.first.map { "\($0)" } ?? "").contains("4000 × 3000 mm"))
        XCTAssertThrowsError(try AgentPrompts.get("draw_room", arguments: ["name": "X"], doc: d))
        XCTAssertThrowsError(try AgentPrompts.get("nope", arguments: [:], doc: d))
    }

    func testExtraToolsAndMutations() throws {
        var d = sample()
        d.info.latitude = 45
        for n in ["egress", "accessibility", "energy_balance", "bill_of_quantities", "takeoff_by_phase", "compare", "markups", "validate_exchange"] {
            XCTAssertTrue(AgentTools.names.contains(n), n)
        }
        let eg = try AgentTools.call("egress", ["level": 0], doc: d) as! [String: Any]
        XCTAssertEqual((eg["rooms"] as? [[String: Any]])?.first?["ok"] as? Bool, true)
        let eb = try AgentTools.call("energy_balance", [:], doc: d) as! [String: Any]
        XCTAssertEqual(eb["degreeDays"] as? Double, 2900)
        XCTAssertNotNil((eb["solarByOrientation"] as? [[String: Any]])?.first { $0["orientation"] as? String == "S" })
        let boq = try AgentTools.call("bill_of_quantities", ["prices": ["wall:area": 40, "currency": "RON"], "vat": 19], doc: d) as! [String: Any]
        XCTAssertEqual(boq["currency"] as? String, "RON")
        XCTAssertGreaterThan(boq["total"] as? Double ?? 0, 0)
        XCTAssertThrowsError(try AgentTools.call("bill_of_quantities", [:], doc: d))
        XCTAssertTrue((try AgentTools.call("takeoff_by_phase", ["format": "csv"], doc: d) as! String).hasPrefix("phase,"))
        let v = try AgentTools.call("validate_exchange", ["format": "gbxml"], doc: d) as! [String: Any]
        XCTAssertEqual(v["valid"] as? Bool, true, "\(v["issues"] ?? "")")
        XCTAssertEqual((try AgentTools.call("validate_exchange", ["format": "cobie"], doc: d) as! [String: Any])["valid"] as? Bool, true)
        let acc = try AgentTools.call("accessibility", [:], doc: d) as! [String: Any]
        XCTAssertNotNil(acc["issues"])
        // Compare with an older file on disk.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var old = d; old.remove(ids: [d.elements.last!.id])
        try ArchiFile.encode(old).write(to: dir.appendingPathComponent("old.archi"))
        let cmp = try AgentTools.call("compare", ["path": dir.appendingPathComponent("old.archi").path, "overlayPath": dir.appendingPathComponent("ov.archi").path], doc: d) as! [String: Any]
        XCTAssertEqual(cmp["added"] as? Int, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ov.archi").path))
        // Mutating tools.
        let add = try AgentExtraTools.mutate("markup_add", ["comment": "Window too small", "elements": [5]], doc: &d, resolve: { URL(fileURLWithPath: $0) }) as! [String: Any]
        let mid = try XCTUnwrap(add["id"] as? String)
        XCTAssertEqual(add["elements"] as? [Int], [5])
        _ = try AgentExtraTools.mutate("markup_update", ["id": mid, "status": "resolved", "reply": "Enlarged", "author": "Bot"], doc: &d, resolve: { URL(fileURLWithPath: $0) })
        XCTAssertEqual(Markups.find(d, mid)?.status, "resolved"); XCTAssertEqual(Markups.find(d, mid)?.replies.first?.author, "Bot")
        let list = try AgentTools.call("markups", ["status": "resolved"], doc: d) as! [String: Any]
        XCTAssertEqual((list["markups"] as? [Any])?.count, 1)
        let bcf = dir.appendingPathComponent("x.bcfzip")
        try BCF.export(d).write(to: bcf)
        _ = try AgentExtraTools.mutate("markup_update", ["id": mid, "delete": true], doc: &d, resolve: { URL(fileURLWithPath: $0) })
        XCTAssertTrue(Markups.list(d).isEmpty)
        let imp = try AgentExtraTools.mutate("bcf_import", ["path": bcf.path], doc: &d, resolve: { URL(fileURLWithPath: $0) }) as! [String: Any]
        XCTAssertEqual(imp["imported"] as? Int, 1)
        XCTAssertThrowsError(try AgentExtraTools.mutate("markup_update", ["id": "zzz"], doc: &d, resolve: { URL(fileURLWithPath: $0) }))
    }

    func testBatchJobParsing() throws {
        let ok = """
        {"stopOnError": true, "jobs": [
          {"name": "plan", "input": "a.archi", "commands": ["LINE 0,0 100,0 "], "outputs": ["a.dxf", {"path": "a.ifc", "format": "ifc", "level": 0}],
           "reports": [{"tool": "takeoff", "path": "q.csv"}, {"tool": "egress", "path": "e.json", "arguments": {"level": 0}}], "save": "b.archi"},
          {"commands": "CIRCLE 0,0 50", "output": "c.svg"}]}
        """
        let (jobs, stop) = try BatchJob.parse(Data(ok.utf8))
        XCTAssertTrue(stop); XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].outputs, [.init(path: "a.dxf", format: nil, level: nil), .init(path: "a.ifc", format: "ifc", level: 0)])
        XCTAssertEqual(jobs[0].reports.map(\.tool), ["takeoff", "egress"]); XCTAssertEqual(jobs[0].reports[1].arguments["level"], "0")
        XCTAssertEqual(jobs[1].name, "job 2"); XCTAssertEqual(jobs[1].commands, ["CIRCLE 0,0 50"]); XCTAssertEqual(jobs[1].outputs.first?.path, "c.svg")
        XCTAssertEqual(try BatchJob.parse(Data("[{\"commands\":[\"U\"]}]".utf8)).jobs.count, 1, "a bare array is a job list")
        XCTAssertThrowsError(try BatchJob.parse(Data("{\"jobs\":[{}]}".utf8)))
        XCTAssertThrowsError(try BatchJob.parse(Data("{\"jobs\":[{\"commands\":[\"U\"],\"reports\":[{\"tool\":\"nope\",\"path\":\"x\"}]}]}".utf8)))
        XCTAssertThrowsError(try BatchJob.parse(Data("nope".utf8)))
        XCTAssertEqual(BatchJob.scriptLines("; comment\nLINE 0,0 1,1 \n\n  CIRCLE 0,0 5"), ["LINE 0,0 1,1", "CIRCLE 0,0 5"])
    }

    // MARK: archi-cli end to end

    func cli() throws -> URL {
        let url = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("archi-cli")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("archi-cli is not built at \(url.path)") }
        return url
    }

    func run(_ exe: URL, _ args: [String], input: String) throws -> (out: String, status: Int32) {
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

    func testMCPResourcesPromptsAndBatchEndToEnd() throws {
        let exe = try cli()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-mcp2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("m.archi")
        try ArchiFile.encode(sample()).write(to: file)
        func req(_ id: Int, _ method: String, _ params: [String: Any]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]), as: UTF8.self)
        }
        let input = [
            req(1, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "t", "version": "1"]]),
            req(2, "resources/list", [:]),
            req(3, "resources/read", ["uri": "archi://schedules/rooms"]),
            req(4, "resources/templates/list", [:]),
            req(5, "prompts/list", [:]),
            req(6, "prompts/get", ["name": "review_model", "arguments": ["focus": "doors"]]),
            req(7, "tools/call", ["name": "markup_add", "arguments": ["comment": "Fix the door", "elements": [6]]]),
            req(8, "resources/read", ["uri": "archi://markups"]),
            req(9, "tools/call", ["name": "run_batch", "arguments": ["jobs": [["input": file.path, "commands": ["LINE 0,0 1000,0 "], "outputs": [dir.appendingPathComponent("b.dxf").path],
                                                                                    "reports": [["tool": "takeoff", "path": dir.appendingPathComponent("q.csv").path]]]]]]),
            req(10, "resources/read", ["uri": "archi://nope"]),
            req(11, "tools/call", ["name": "undo", "arguments": [:]]),
            req(12, "resources/read", ["uri": "archi://markups"]),
        ].joined(separator: "\n") + "\n"
        let (out, status) = try run(exe, ["--mcp", file.path], input: input)
        XCTAssertEqual(status, 0)
        let msgs = out.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        func result(_ id: Int) -> [String: Any]? { msgs.first { ($0["id"] as? Int) == id }?["result"] as? [String: Any] }
        let caps = result(1)?["capabilities"] as? [String: Any]
        XCTAssertNotNil(caps?["resources"]); XCTAssertNotNil(caps?["prompts"])
        XCTAssertTrue(((result(2)?["resources"] as? [[String: Any]]) ?? []).contains { $0["uri"] as? String == "archi://document/summary" })
        let rooms = ((result(3)?["contents"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(rooms.contains("Studio"))
        XCTAssertEqual((result(4)?["resourceTemplates"] as? [Any])?.count, 3)
        XCTAssertEqual((result(5)?["prompts"] as? [Any])?.count, 5)
        XCTAssertTrue("\(result(6) ?? [:])".contains("Focus on: doors"))
        XCTAssertEqual(result(7)?["isError"] as? Bool, false)
        XCTAssertTrue((((result(8)?["contents"] as? [[String: Any]])?.first?["text"] as? String) ?? "").contains("Fix the door"))
        let batch = result(9)?["structuredContent"] as? [String: Any]
        XCTAssertEqual(batch?["failed"] as? Int, 0, "\(result(9) ?? [:])")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("b.dxf").path))
        XCTAssertTrue(((try? String(contentsOf: dir.appendingPathComponent("q.csv"), encoding: .utf8)) ?? "").hasPrefix("category,"))
        XCTAssertNotNil(msgs.first { ($0["id"] as? Int) == 10 }?["error"])
        XCTAssertFalse((((result(12)?["contents"] as? [[String: Any]])?.first?["text"] as? String) ?? "x").contains("Fix the door"), "markup_add is undoable")

        // --batch with a jobs file; relative paths resolve against its folder.
        let jobs = """
        {"jobs": [{"name": "one", "input": "m.archi", "commands": ["CIRCLE 0,0 500"], "outputs": ["one.dxf", "one.kml"], "save": "one.archi"},
                  {"name": "bad", "input": "missing.archi", "outputs": ["x.dxf"]}]}
        """
        let jf = dir.appendingPathComponent("jobs.json")
        try jobs.write(to: jf, atomically: true, encoding: .utf8)
        let (bout, bstatus) = try run(exe, ["--batch", jf.path], input: "")
        XCTAssertEqual(bstatus, 1, bout)
        XCTAssertTrue(bout.contains("one: ok")); XCTAssertTrue(bout.contains("bad: FAILED"))
        for f in ["one.dxf", "one.kml", "one.archi"] { XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path), f) }
        let saved = try ArchiFile.decode(Data(contentsOf: dir.appendingPathComponent("one.archi")))
        XCTAssertTrue(saved.entities.contains { if case .circle = $0.geometry { return true }; return false })
    }
}
