// Oanarina Archi Tool — GPL-3.0-or-later
// Work sharing (COL-015, COL-017): two users with local copies of one central model.
import XCTest
@testable import ArchiCore

final class IOCentralModelTests: XCTestCase {
    func dir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-central-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testTwoUsersSyncWithoutDataLossAndBorrowingIsEnforced() throws {
        let d = try dir()
        let central = d.appendingPathComponent("Central.archi")
        var start = ArchiDocument()
        let w1 = start.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let w2 = start.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000))))
        let note = start.add(.text(TextGeom(position: .zero, height: 250, content: "Note")))
        try CentralModel.createCentral(start, at: central)
        let la = d.appendingPathComponent("Ana.archi"), lb = d.appendingPathComponent("Bo.archi")
        var a = try CentralModel.createLocal(central: central, local: la, user: "Ana")
        var b = try CentralModel.createLocal(central: central, local: lb, user: "Bo")

        // Ana borrows wall 1; Bo cannot.
        XCTAssertEqual(try CentralModel.borrow([w1], user: "Ana", central: central).granted, [w1])
        let denied = try CentralModel.borrow([w1, w2], user: "Bo", central: central)
        XCTAssertEqual(denied.granted, [w2]); XCTAssertEqual(denied.denied.first?.owner, "Ana")

        // Both edit: Ana thickens wall 1 and adds a circle; Bo also edits wall 1 (not allowed), edits wall 2, adds a line.
        func setThickness(_ doc: inout ArchiDocument, _ id: EntityID, _ t: Double) {
            let i = doc.elementIndex(id)!; guard case .wall(var w) = doc.elements[i].geometry else { return }; w.thickness = t; doc.elements[i].geometry = .wall(w)
        }
        setThickness(&a, w1, 300)
        let aCircle = a.add(.circle(CircleGeom(Vec2(100, 100), 50)))
        setThickness(&b, w1, 999)
        setThickness(&b, w2, 250)
        let bLine = b.add(.line(LineGeom(Vec2(0, 500), Vec2(900, 500))))
        XCTAssertEqual(aCircle, bLine, "both users allocated the same new id")
        b.remove(ids: [note])

        let ra = try CentralModel.sync(local: a, localURL: la, user: "Ana", relinquishAll: false)
        XCTAssertTrue(ra.rejected.isEmpty); XCTAssertTrue(ra.conflicts.isEmpty)
        a = ra.doc
        let rb = try CentralModel.sync(local: b, localURL: lb, user: "Bo")
        XCTAssertEqual(rb.rejected.map(\.id), [w1], "Bo's edit of Ana's wall is rejected")
        XCTAssertEqual(rb.rejected.first?.owner, "Ana")
        XCTAssertEqual(rb.renumbered[bLine].map { $0 > bLine }, true, "Bo's new line got a fresh id")
        b = rb.doc

        // Central has everything: Ana's wall edit and circle, Bo's wall 2 edit, his line and his deletion.
        let c = try ArchiFile.decode(Data(contentsOf: central))
        func thickness(_ doc: ArchiDocument, _ id: EntityID) -> Double? { if case .wall(let w) = doc.element(id)?.geometry { return w.thickness }; return nil }
        XCTAssertEqual(thickness(c, w1), 300)
        XCTAssertEqual(thickness(c, w2), 250)
        XCTAssertEqual(c.entities.filter { $0.typeName == "circle" }.count, 1)
        XCTAssertEqual(c.entities.filter { $0.typeName == "line" }.count, 1)
        XCTAssertNil(c.entity(note))
        XCTAssertNil(c.variable("USERNAME"), "user settings stay local")
        XCTAssertEqual(b.variable("USERNAME"), "Bo")
        XCTAssertEqual(b, { var x = c; x.setVariable("USERNAME", "Bo"); x.setVariable("CENTRALFILE", central.path); return x }(), "Bo's local equals central after sync")

        // Ana syncs again: receives Bo's work, keeps her circle; ownership kept by Ana until she relinquishes.
        let ra2 = try CentralModel.sync(local: a, localURL: la, user: "Ana")
        XCTAssertEqual(ra2.doc.entities.count, c.entities.count)
        XCTAssertTrue(CentralModel.owners(central: central).isEmpty, "relinquished on sync")
        // After relinquishing, Bo may edit wall 1.
        var b2 = b
        setThickness(&b2, w1, 350)
        XCTAssertTrue(try CentralModel.sync(local: b2, localURL: lb, user: "Bo").rejected.isEmpty)
        XCTAssertEqual(thickness(try ArchiFile.decode(Data(contentsOf: central)), w1), 350)
    }

    func testConcurrentEditsOfUnownedObjectKeepFirstSyncAndReport() throws {
        let d = try dir()
        let central = d.appendingPathComponent("C.archi")
        var s = ArchiDocument()
        let t = s.add(.text(TextGeom(position: .zero, height: 250, content: "A")))
        try CentralModel.createCentral(s, at: central)
        var a = try CentralModel.createLocal(central: central, local: d.appendingPathComponent("a.archi"), user: "a")
        var b = try CentralModel.createLocal(central: central, local: d.appendingPathComponent("b.archi"), user: "b")
        a.entities[0].layer = "X"; b.entities[0].layer = "Y"
        _ = try CentralModel.sync(local: a, localURL: d.appendingPathComponent("a.archi"), user: "a")
        let r = try CentralModel.sync(local: b, localURL: d.appendingPathComponent("b.archi"), user: "b")
        XCTAssertEqual(r.conflicts.map(\.key), ["#\(t)"])
        XCTAssertEqual(r.doc.entity(t)?.layer, "X")
        XCTAssertFalse(FileManager.default.fileExists(atPath: CentralModel.lockURL(central).path), "lock released")
    }

    @MainActor func testCentralCommands() async throws {
        let d = try dir()
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 ")
        let c = d.appendingPathComponent("Office.archi"), l = d.appendingPathComponent("Me.archi")
        await ed.run("CENTRAL Create \(c.path)")
        await ed.run("CENTRAL Local \(c.path) \(l.path) Me")
        XCTAssertEqual(ed.doc.variable("CENTRALFILE"), c.path)
        await ed.run("CIRCLE 0,0 50")
        await ed.run("SELECT ALL ")
        let out = await ed.run("CENTRAL Borrow")
        XCTAssertTrue(out.joined().contains("Borrowed 2"), out.joined(separator: "\n"))
        let s = await ed.run("CENTRAL Sync N")
        XCTAssertTrue(s.joined().contains("Synchronised"), s.joined(separator: "\n"))
        XCTAssertEqual(try ArchiFile.decode(Data(contentsOf: c)).entities.count, 2)
    }
}
