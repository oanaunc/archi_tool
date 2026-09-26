// Oanarina Archi Tool — GPL-3.0-or-later
// Co-editing (COL-016): property-level merging of concurrent edits and convergence of several replicas.
import XCTest
@testable import ArchiCore

final class IOCoEditFieldMergeTests: XCTestCase {
    func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("coedit-f-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func strip(_ d: ArchiDocument) -> ArchiDocument { var x = d; x.nextID = 0; return x }

    /// One user moves a line while the other puts it on another layer: both edits survive, no conflict.
    func testConcurrentEditsOfDifferentPropertiesAreBothKept() throws {
        let dir = try folder()
        var a = IOCoEditingTests.base(), b = IOCoEditingTests.base()
        let sa = CoEditSession(site: "a", document: a), sb = CoEditSession(site: "b", document: b)
        a.entities[0].geometry = .line(LineGeom(Vec2(10, 10), Vec2(2000, 10)))
        b.entities[0].layer = "A-WALL"
        b.entities[0].props["fireRating"] = "EI60"
        a = try sa.sync(a, folder: dir).document
        b = try sb.sync(b, folder: dir).document
        a = try sa.sync(a, folder: dir).document
        XCTAssertEqual(strip(a), strip(b))
        XCTAssertEqual(a.entities[0].layer, "A-WALL")
        XCTAssertEqual(a.entities[0].props["fireRating"], "EI60")
        guard case .line(let l) = a.entities[0].geometry else { return XCTFail() }
        XCTAssertEqual(l.b, Vec2(2000, 10))
        XCTAssertTrue(sa.conflicts.isEmpty, "\(sa.conflicts)")
        XCTAssertTrue(sb.conflicts.isEmpty, "\(sb.conflicts)")
    }

    /// Three users edit concurrently and synchronise in different orders: every replica ends with the same document.
    func testThreeReplicasConvergeInAnyOrder() throws {
        let dir = try folder()
        var docs = [IOCoEditingTests.base(), IOCoEditingTests.base(), IOCoEditingTests.base()]
        let sessions = ["anna", "bogdan", "carla"].enumerated().map { CoEditSession(site: $0.element, document: docs[$0.offset]) }
        for i in 0..<3 { sessions[i].claimIDs(&docs[i]) }
        var rng = SystemRandomNumberGenerator()
        for round in 0..<4 {
            for i in 0..<3 {
                // Each user edits: adds a point, changes a property of a shared object, sometimes deletes.
                docs[i].add(.point(Vec2(Double(round * 10 + i), Double(i))))
                if !docs[i].entities.isEmpty {
                    let k = Int.random(in: 0..<docs[i].entities.count, using: &rng)
                    if Bool.random(using: &rng) { docs[i].entities[k].props["note\(i)"] = "r\(round)" } else { docs[i].entities[k].layer = "L\(i)" }
                }
                if round == 2 && i == 1 { docs[i].entities.removeAll { if case .circle = $0.geometry { return true }; return false } }
            }
            for i in [2, 0, 1].shuffled() { docs[i] = try sessions[i].sync(docs[i], folder: dir).document }
        }
        for _ in 0..<2 { for i in 0..<3 { docs[i] = try sessions[i].sync(docs[i], folder: dir).document } }
        XCTAssertEqual(strip(docs[0]), strip(docs[1]))
        XCTAssertEqual(strip(docs[1]), strip(docs[2]))
        XCTAssertEqual(docs[0].entities.filter { if case .point = $0.geometry { return true }; return false }.count, 12, "every added point survives")
    }

    /// Logs written before property-level operations (no "fields") are still applied as whole-object writes.
    func testOlderLogsWithoutFieldsStillApply() throws {
        let s = CoEditSession(site: "me", document: IOCoEditingTests.base())
        var e = IOCoEditingTests.base().entities[1]
        e.layer = "OLD"
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let legacy = #"{"key":"e:\#(e.id)","stamp":{"clock":3,"site":"other"},"value":"\#(try enc.encode(e).base64EncodedString())"}"#
        let op = try JSONDecoder().decode(CoEditOp.self, from: Data(legacy.utf8))
        XCTAssertNil(op.fields)
        XCTAssertEqual(s.apply([op]), ["e:\(e.id)"])
        XCTAssertEqual(s.materialize(local: IOCoEditingTests.base()).entities[1].layer, "OLD")
    }
}
