// Oanarina Archi Tool — GPL-3.0-or-later
// Git-friendly projects (COL-004): lossless .archit round trip, object-level diffs, git commit/log/diff/checkout.
import XCTest
@testable import ArchiCore

final class IOGitFormatTests: XCTestCase {
    func sample() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.name = "Git House"
        d.add(.line(LineGeom(.zero, Vec2(1000.25, 0))), layer: "A-WALL")
        d.add(.text(TextGeom(position: Vec2(1, 2), height: 250, content: "Hello \"quoted\"\nsecond line")))
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 200, height: 3000)))
        d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 900, height: 2100)))
        d.blocks["Chair 1"] = Block(name: "Chair 1", entities: [Entity(geometry: .circle(CircleGeom(.zero, 200)))])
        d.setVariable("USERNAME", "Ana")
        return d
    }

    func testRoundTripIsLosslessAndOneLinePerObject() throws {
        let d = sample()
        let t = try ArchiText.encode(d)
        XCTAssertTrue(t.hasPrefix(ArchiText.magic))
        let lines = t.split(separator: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("entity ") }.count, 2)
        XCTAssertEqual(lines.filter { $0.hasPrefix("element ") }.count, 2)
        XCTAssertEqual(lines.filter { $0.hasPrefix("block Chair%201 ") }.count, 1)
        XCTAssertEqual(try ArchiText.decode(t), d)
        XCTAssertEqual(try ArchiText.encode(ArchiText.decode(t)), t, "stable output")
        XCTAssertThrowsError(try ArchiText.decode(t.replacingOccurrences(of: "header ", with: "<<<<<<< HEAD\nheader ")))
    }

    func testDiffIdentifiesEveryChange() throws {
        var a = sample()
        let before = try ArchiText.encode(a)
        let lineID = a.entities[0].id
        a.entities[0].layer = "0"                                  // modified entity
        let added = a.add(.circle(CircleGeom(Vec2(5, 5), 10)))      // added entity
        let wall = a.elements[0].id
        a.remove(ids: [a.elements[1].id])                           // removed element (door)
        a.ensureLayer("NEW")                                        // added layer
        a.blocks["Chair 1"] = nil                                   // removed block
        a.setVariable("USERNAME", "Bo")                             // modified variable
        let changes = ArchiText.diff(before, try ArchiText.encode(a))
        let set = Set(changes.map(\.description))
        XCTAssertTrue(set.contains("modified entity \(lineID)"))
        XCTAssertTrue(set.contains("added entity \(added)"))
        XCTAssertTrue(set.contains("removed element \(wall + 1)"))
        XCTAssertTrue(set.contains("added layer NEW"))
        XCTAssertTrue(set.contains("removed block Chair 1"))
        XCTAssertTrue(set.contains("modified var USERNAME"))
        XCTAssertFalse(set.contains { $0.contains("element \(wall)") }, "untouched wall is not reported")
        XCTAssertTrue(set.contains("modified header ") || set.contains { $0.hasPrefix("modified header") }, "nextID changed")
        XCTAssertEqual(changes.count, 7)
    }

    @MainActor func testGitCommitLogDiffCheckout() async throws {
        guard GitVersioning.gitPath() != nil else { throw XCTSkip("git not installed") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ed = Editor()
        ed.fileURL = dir.appendingPathComponent("House.archi")
        ed.doc.setVariable("USERNAME", "Ana")
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("GITVERSION Commit \"first line\"")
        await ed.run("CIRCLE 0,0 300")
        let out = await ed.run("GITVERSION Commit \"circle\"")
        XCTAssertTrue(out.joined().contains("Committed"), out.joined(separator: "\n"))
        let file = dir.appendingPathComponent("House.archit")
        let log = try GitVersioning.log(file: file)
        XCTAssertEqual(log.map(\.message), ["circle", "first line"])
        XCTAssertEqual(log.first?.author, "Ana")
        let changes = try GitVersioning.diff(file: file, from: "HEAD~1", to: "HEAD")
        XCTAssertEqual(changes.filter { $0.object == "entity" }.map(\.description), ["added entity 2"])
        await ed.run("GITVERSION Checkout HEAD~1")
        XCTAssertEqual(ed.doc.entities.count, 1)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 2)
        let none = await ed.run("GITVERSION Commit again")
        XCTAssertTrue(none.joined().contains("No changes"))
        // The .archit file opens like any drawing.
        XCTAssertEqual(try DocumentIO.read(file).entities.count, 2)
    }
}
