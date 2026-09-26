// Oanarina Archi Tool — GPL-3.0-or-later
// Cloud-sync conflict copies (COL-013): two users' concurrent edits of one drawing merge without losing work.
import XCTest
@testable import ArchiCore

final class IOConflictCopiesTests: XCTestCase {
    func tmp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    func content(_ d: ArchiDocument, _ id: EntityID) -> String? { if case .text(let t) = d.entity(id)?.geometry { return t.content }; return nil }
    func setText(_ d: inout ArchiDocument, _ id: EntityID, _ s: String) {
        guard let i = d.entities.firstIndex(where: { $0.id == id }), case .text(var t) = d.entities[i].geometry else { return }
        t.content = s; d.entities[i].geometry = .text(t)
    }

    func testFindsCopiesOfEveryCloudService() throws {
        let dir = try tmp()
        let url = dir.appendingPathComponent("House.archi")
        for n in ["House.archi", "House 2.archi", "House (conflicted copy 2026-01-02).archi", "House (Oana's conflicted copy).archi",
                  "House-DESKTOP-1.archi", "House (1).archi", "Houseboat.archi", "House plan.archi", "House 2.dxf"] {
            try Data("{}".utf8).write(to: dir.appendingPathComponent(n))
        }
        XCTAssertEqual(ConflictCopies.find(for: url).map(\.lastPathComponent),
                       ["House (1).archi", "House (Oana's conflicted copy).archi", "House (conflicted copy 2026-01-02).archi", "House 2.archi", "House-DESKTOP-1.archi"])
    }

    func testTwoUsersEditsMergeWithoutLoss() throws {
        try twoUsers(withVersionSnapshot: false)
        try twoUsers(withVersionSnapshot: true)
    }

    func twoUsers(withVersionSnapshot snapshot: Bool) throws {
        let dir = try tmp()
        let url = dir.appendingPathComponent("House.archi")
        var base = ArchiDocument()
        let a = base.add(.text(TextGeom(position: .zero, height: 100, content: "A")))
        let b = base.add(.text(TextGeom(position: Vec2(0, 500), height: 100, content: "B")))
        let gone = base.add(.line(LineGeom(.zero, Vec2(10, 0))))
        try ArchiFile.encode(base).write(to: url)
        if snapshot { _ = try DocumentVersions.save(base, documentURL: url, message: "shared", date: Date().addingTimeInterval(-120), force: true) }

        var ours = base, theirs = base
        setText(&ours, a, "A by Ana")
        let c = ours.add(.text(TextGeom(position: Vec2(0, 1000), height: 100, content: "C by Ana")))
        setText(&theirs, b, "B by Bo")
        let d = theirs.add(.text(TextGeom(position: Vec2(0, 1500), height: 100, content: "D by Bo")))
        theirs.remove(ids: [gone])
        XCTAssertEqual(c, d, "both users got the same new id")
        let copy = dir.appendingPathComponent("House (Bo's conflicted copy).archi")
        try ArchiFile.encode(theirs).write(to: copy)
        try ArchiFile.encode(ours).write(to: url)

        let r = try ConflictCopies.resolve(ours, documentURL: url)
        XCTAssertEqual(r.copies.map(\.lastPathComponent), [copy.lastPathComponent])
        let m = r.merged
        XCTAssertEqual(content(m, a), "A by Ana")
        if snapshot {
            // With the common ancestor (a VERSIONS snapshot) Bo's edit replaces the unchanged original.
            XCTAssertEqual(content(m, b), "B by Bo")
            XCTAssertNil(m.entity(gone), "Bo's deletion applies")
        } else {
            // Without an ancestor, B differs on both sides: ours stays in place and Bo's version is kept as a new object.
            XCTAssertEqual(content(m, b), "B")
        }
        let texts = Set(m.entities.compactMap { if case .text(let t) = $0.geometry { return t.content }; return nil })
        XCTAssertTrue(texts.isSuperset(of: ["A by Ana", "B by Bo", "C by Ana", "D by Bo"]), "\(texts)")
        XCTAssertEqual(Set(m.entities.map(\.id)).count, m.entities.count, "ids stay unique")
        let dirOut = try ConflictCopies.archive(r.copies, documentURL: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirOut.appendingPathComponent(copy.lastPathComponent).path), "copies are kept, not deleted")
    }
}
