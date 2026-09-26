// Oanarina Archi Tool — GPL-3.0-or-later
// Real-time co-editing through shared op logs (COL-016) and the BCF API client (COL-010).
import XCTest
@testable import ArchiCore

final class IOCoEditingTests: XCTestCase {
    func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("coedit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func base() -> ArchiDocument {
        var d = ArchiDocument()
        d.add(.line(LineGeom(.zero, Vec2(1000, 0))))
        d.add(.circle(CircleGeom(Vec2(500, 500), 100)))
        return d
    }
    /// Replicas are equal except for their id counters (each in its own range).
    func same(_ a: ArchiDocument, _ b: ArchiDocument, file: StaticString = #filePath, line: UInt = #line) {
        var x = a, y = b; x.nextID = 0; y.nextID = 0
        XCTAssertTrue(x == y, "replicas differ: \(CoEditSession.objects(x).filter { CoEditSession.objects(y)[$0.key] != $0.value }.keys.sorted())", file: file, line: line)
    }

    func testTwoUsersConvergeWithoutLosingEdits() throws {
        let dir = try folder()
        var a = Self.base(), b = Self.base()
        let sa = CoEditSession(site: "anna", document: a), sb = CoEditSession(site: "bogdan", document: b)
        sa.claimIDs(&a); sb.claimIDs(&b)
        XCTAssertNotEqual(sa.idBase, sb.idBase)
        // Anna draws a line and moves the circle; Bogdan adds a wall with a door, a layer and deletes the first line.
        let la = a.add(.line(LineGeom(Vec2(0, 100), Vec2(0, 900))))
        if case .circle(var c) = a.entities[1].geometry { c.radius = 250; a.entities[1].geometry = .circle(c) }
        let w = b.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        _ = b.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 900, height: 2100)))
        b.layers.append(Layer(name: "B-NOTES"))
        b.entities.removeAll { $0.id == 1 }
        XCTAssertTrue(la >= sa.idBase && w >= sb.idBase, "ids from each site's own range")
        // Sync in any order.
        a = try sa.sync(a, folder: dir).document
        b = try sb.sync(b, folder: dir).document
        a = try sa.sync(a, folder: dir).document
        same(a, b)
        XCTAssertNil(a.entity(1), "deletion propagated")
        XCTAssertNotNil(a.entity(la))
        guard case .circle(let c) = a.entities.first(where: { if case .circle = $0.geometry { return true }; return false })?.geometry else { return XCTFail() }
        XCTAssertEqual(c.radius, 250)
        XCTAssertNotNil(a.layer(named: "B-NOTES"))
        guard case .opening(let o) = a.elements.first(where: { if case .opening = $0.geometry { return true }; return false })!.geometry else { return XCTFail() }
        XCTAssertEqual(o.hostWall, w, "references survive")
        // Ids keep coming from each user's range after merging.
        XCTAssertEqual(a.nextID, la + 1)
        XCTAssertEqual(b.nextID, w + 2)
        XCTAssertTrue(sa.conflicts.isEmpty && sb.conflicts.isEmpty)
        // Idempotent: syncing again changes nothing.
        XCTAssertEqual(try sa.sync(a, folder: dir).document, a)
        XCTAssertEqual(try sb.sync(b, folder: dir).received, 0)
    }

    func testConcurrentEditOfOneObjectKeepsTheLaterAndReports() throws {
        let dir = try folder()
        var a = Self.base(), b = Self.base()
        let sa = CoEditSession(site: "a", document: a), sb = CoEditSession(site: "b", document: b)
        a.entities[0].layer = "A-WALL"
        b.entities[0].layer = "A-DOOR"
        a = try sa.sync(a, folder: dir).document
        let rb = try sb.sync(b, folder: dir)
        b = rb.document
        a = try sa.sync(a, folder: dir).document
        same(a, b)
        XCTAssertEqual(a.entities[0].layer, "A-DOOR", "same clock: the higher site name wins deterministically")
        XCTAssertEqual(rb.conflicts, ["e:1"])
        XCTAssertEqual(sa.conflicts, ["e:1"])
    }

    func testPartialLogLinesAreNotRead() throws {
        let dir = try folder()
        var a = Self.base()
        let sa = CoEditSession(site: "a", document: a), sb = CoEditSession(site: "b", document: Self.base())
        a.add(.point(Vec2(1, 1)))
        _ = try sa.sync(a, folder: dir)
        // A writer is mid-append: an incomplete line at the end of b's view of a's log.
        let h = try FileHandle(forWritingTo: dir.appendingPathComponent("a.ops.jsonl"))
        try h.seekToEnd(); try h.write(contentsOf: Data("{\"key\":\"e:9".utf8)); try h.close()
        let r = try sb.sync(Self.base(), folder: dir)
        XCTAssertEqual(r.received, 1)
        XCTAssertEqual(r.document.entities.count, 3)
    }

    @MainActor func testCoEditCommand() async throws {
        let dir = try folder()
        let e1 = Editor(document: Self.base()), e2 = Editor(document: Self.base())
        await e1.run("COEDIT Join \"\(dir.path)\" oana")
        await e2.run("COEDIT Join \"\(dir.path)\" mihai")
        await e1.run("LINE 0,0 0,2000 ")
        await e2.run("CIRCLE 3000,3000 400")
        await e1.run("COEDIT Sync")
        await e2.run("COEDIT Sync")
        await e1.run("COEDIT Sync")
        XCTAssertEqual(e1.doc.entities.count, 4)
        XCTAssertEqual(e1.doc.entities.map(\.id), e2.doc.entities.map(\.id))
        let st = await e1.run("COEDIT Status")
        XCTAssertTrue(st.joined().contains("as oana"))
        await e1.run("COEDIT Leave")
        XCTAssertNil(CoEdit.session(of: e1))
        CoEdit.leave(e2)
    }

    // MARK: BCF API

    /// In-memory BCF API 3.0 server.
    final class MockServer {
        var topics: [[String: Any]] = [["guid": "0b1c4c8e-6f7a-4a52-9d3a-2d4a3b1c9e01", "title": "Door clash", "topic_status": "Open", "topic_type": "Clash", "creation_author": "srv@x", "creation_date": "2026-01-02T10:00:00Z", "description": "Door hits column"]]
        var comments: [String: [[String: Any]]] = ["0b1c4c8e-6f7a-4a52-9d3a-2d4a3b1c9e01": [["guid": "c-1", "author": "srv@x", "date": "2026-01-02T10:00:00Z", "comment": "Door hits column"], ["guid": "c-2", "author": "eng@x", "date": "2026-01-03T10:00:00Z", "comment": "Move the door 300 mm"]]]
        var viewpoints: [String: [[String: Any]]] = ["0b1c4c8e-6f7a-4a52-9d3a-2d4a3b1c9e01": [["guid": "v-1", "perspective_camera": ["camera_view_point": ["x": 1, "y": 2, "z": 3], "camera_direction": ["x": 0, "y": 1, "z": 0], "camera_up_vector": ["x": 0, "y": 0, "z": 1], "field_of_view": 55]]]]
        var selections: [String: [String]] = [:]
        var authHeaders: Set<String> = []
        var next = 1
        func handle(_ r: URLRequest) throws -> (status: Int, body: Data) {
            authHeaders.insert(r.value(forHTTPHeaderField: "Authorization") ?? "")
            let path = Array(r.url!.path.split(separator: "/").map(String.init).drop { $0 == "api" })   // e.g. [bcf, 3.0, projects, p1, topics, t-1, comments]
            let body = r.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            func ok(_ o: Any) -> (Int, Data) { (200, try! JSONSerialization.data(withJSONObject: o)) }
            switch (r.httpMethod ?? "GET", path.count) {
            case ("GET", 2) where path[1] == "versions": return ok(["versions": [["version_id": "2.1"], ["version_id": "3.0"]]])
            case ("GET", 3): return ok([["project_id": "p1", "name": "House"]])
            case ("GET", 5): return ok(topics)
            case ("POST", 5):
                var t = body; t["guid"] = "srv-\(next)"; next += 1; topics.append(t); return (201, try! JSONSerialization.data(withJSONObject: t))
            case ("PUT", 6):
                guard let i = topics.firstIndex(where: { $0["guid"] as? String == path[5] }) else { return (404, Data()) }
                for (k, v) in body { topics[i][k] = v }; return ok(topics[i])
            case ("GET", 7) where path[6] == "comments": return ok(comments[path[5]] ?? [])
            case ("POST", 7) where path[6] == "comments":
                var c = body; c["author"] = "me"; comments[path[5], default: []].append(c); return (201, try! JSONSerialization.data(withJSONObject: c))
            case ("GET", 7) where path[6] == "viewpoints": return ok(viewpoints[path[5]] ?? [])
            case ("POST", 7) where path[6] == "viewpoints":
                viewpoints[path[5], default: []].append(body); return (201, try! JSONSerialization.data(withJSONObject: body))
            case ("GET", 9) where path[8] == "selection": return ok(["selection": (selections[path[7]] ?? []).map { ["ifc_guid": $0] }])
            default: return (404, Data("{\"message\":\"no route\"}".utf8))
            }
        }
    }

    func testBCFClientPullAndPush() throws {
        let server = MockServer()
        var d = ArchiDocument()
        let col = d.addElement(.column(ColumnGeom(position: Vec2(1000, 1000))))
        server.selections["v-1"] = [BCF.ifcGuid(col, doc: d)]
        let c = BCFAPIClient(baseURL: URL(string: "https://cde.example.com/api/")!, token: "tok", transport: server.handle)
        try c.negotiate()
        XCTAssertEqual(c.version, "3.0")
        XCTAssertEqual(try c.projects().map(\.name), ["House"])
        let ts = try c.topics(project: "p1")
        XCTAssertEqual(ts.count, 1)
        XCTAssertEqual(ts[0].comments.count, 2)
        XCTAssertEqual(ts[0].viewpoint?.fieldOfView, 55)
        XCTAssertEqual(ts[0].viewpoint?.selection, [BCF.ifcGuid(col, doc: d)], "selection fetched from the selection endpoint")
        XCTAssertEqual(server.authHeaders, ["Bearer tok"])
        // Import → markups linked to the column; reply and close locally, then push back.
        BCF.importTopics(ts, into: &d)
        var mk = Markups.list(d)
        XCTAssertEqual(mk.count, 1); XCTAssertEqual(mk[0].elements, [col]); XCTAssertEqual(mk[0].replies.count, 1)
        _ = Markups.reply(&d, mk[0].id, text: "Done, moved.", author: "oana", date: "2026-01-04T10:00:00Z")
        _ = Markups.update(&d, mk[0].id) { $0["status"] = "resolved" }
        _ = Markups.add(&d, rect: (Vec2(0, 0), Vec2(100, 100)), title: "New issue", comment: "Check stair headroom", author: "oana")
        mk = Markups.list(d)
        let r = try c.push(BCF.topics(d), project: "p1")
        XCTAssertEqual(r.updated, 1); XCTAssertEqual(r.created, 1)
        XCTAssertEqual(server.topics.count, 2)
        XCTAssertEqual(server.topics[0]["topic_status"] as? String, "Closed")
        XCTAssertTrue((server.comments["0b1c4c8e-6f7a-4a52-9d3a-2d4a3b1c9e01"] ?? []).contains { $0["comment"] as? String == "Done, moved." })
        XCTAssertEqual((server.comments["0b1c4c8e-6f7a-4a52-9d3a-2d4a3b1c9e01"] ?? []).count, 3, "existing comments are not duplicated")
        XCTAssertEqual(server.topics[1]["title"] as? String, "New issue")
        XCTAssertEqual(r.assigned.count, 1)
        XCTAssertEqual(server.viewpoints["srv-1"]?.count, 1)
        // Errors carry the HTTP status.
        XCTAssertThrowsError(try c.topics(project: "p1/missing/x")) { e in XCTAssertTrue((e as? LocalizedError)?.errorDescription?.contains("404") ?? false) }
    }

    @MainActor func testBCFServerCommand() async throws {
        let server = MockServer()
        BCFServerCommands.transport = server.handle
        defer { BCFServerCommands.transport = nil }
        let ed = Editor()
        await ed.run("BCFSERVER Connect https://cde.example.com/api/ secret")
        XCTAssertEqual(ed.doc.variable("BCFPROJECT"), "p1")
        await ed.run("BCFSERVER Pull")
        XCTAssertEqual(Markups.list(ed.doc).count, 1)
        _ = Markups.add(&ed.doc, rect: (Vec2(0, 0), Vec2(10, 10)), title: "Local", comment: "Local issue")
        let out = await ed.run("BCFSERVER Push")
        XCTAssertTrue(out.joined().contains("1 new"), out.joined(separator: "\n"))
        XCTAssertTrue(ed.doc.entities.contains { $0.props["bcfGuid"] == "srv-1" }, "server guid remembered")
        let again = await ed.run("BCFSERVER Push")
        XCTAssertTrue(again.joined().contains("0 new, 2 updated"), again.joined(separator: "\n"))
        XCTAssertEqual(server.authHeaders, ["Bearer secret"])
    }

    // MARK: Sync conflict copies (COL-013)

    @MainActor func testSyncConflictCopiesMergeWithoutLoss() async throws {
        let dir = try folder()
        let url = dir.appendingPathComponent("House.archi")
        var base = Self.base()
        try DocumentIO.write(base, to: url)
        _ = try DocumentVersions.save(base, documentURL: url, message: "base", date: Date(timeIntervalSinceNow: -3600))
        // Machine 1 (ours) adds a line; machine 2 (the conflict copy) moves the circle and adds a wall.
        var ours = base; ours.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 500))))
        var theirs = base
        if case .circle(var c) = theirs.entities[1].geometry { c.center = Vec2(900, 900); theirs.entities[1].geometry = .circle(c) }
        let w = theirs.addElement(.wall(WallGeom(start: .zero, end: Vec2(3000, 0))))
        try DocumentIO.write(ours, to: url)
        try ArchiFile.encode(theirs).write(to: dir.appendingPathComponent("House 2.archi"))
        try ArchiFile.encode(theirs).write(to: dir.appendingPathComponent("House (Oana's conflicted copy 2026-01-02).archi"))
        try Data().write(to: dir.appendingPathComponent("Houseboat.archi"))
        XCTAssertEqual(ConflictCopies.find(for: url).map(\.lastPathComponent), ["House (Oana's conflicted copy 2026-01-02).archi", "House 2.archi"])
        let r = try ConflictCopies.resolve(ours, documentURL: url)
        XCTAssertEqual(r.merged.entities.count, 3)
        guard case .circle(let c) = r.merged.entities[1].geometry else { return XCTFail() }
        XCTAssertEqual(c.center, Vec2(900, 900))
        XCTAssertEqual(r.merged.elements.count, 1, "the second identical copy adds nothing")
        guard case .wall(let wg) = r.merged.elements[0].geometry else { return XCTFail() }
        XCTAssertEqual(wg.end, Vec2(3000, 0))
        XCTAssertEqual(Set(r.merged.entities.map(\.id) + r.merged.elements.map(\.id)).count, 4, "the wall was renumbered away from our line (same id)")
        _ = w
        XCTAssertTrue(r.conflicts.isEmpty)
        // Without a version snapshot the synthetic ancestor keeps both sides' additions.
        let s = ConflictCopies.shared(ours, theirs)
        XCTAssertEqual(s.entities.count, 1)
        let m = ThreeWayMerge.merge(base: s, ours: ours, theirs: theirs)
        XCTAssertEqual(m.doc.entities.count, 4, "the circle changed on one side only is kept in both versions (no ancestor to decide)")
        XCTAssertEqual(m.doc.elements.count, 1)
        // The command merges and archives the copies.
        let ed = Editor(document: ours); ed.fileURL = url
        await ed.run("RESOLVECONFLICTS Yes")
        XCTAssertEqual(ed.doc.elements.count, 1)
        XCTAssertTrue(ConflictCopies.find(for: url).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("House.archi-conflicts/House 2.archi").path))
        base = ed.doc
        await ed.run("UNDO")
        XCTAssertTrue(ed.doc.elements.isEmpty)
    }
}
