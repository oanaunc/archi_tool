// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftXrefTests: XCTestCase {
    nonisolated(unsafe) var dir: URL!
    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("archi-xref-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    func site() -> ArchiDocument {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "SITE", color: RGBA(0, 1, 0)))
        d.blocks["TREE"] = Block(name: "TREE", entities: [Entity(layer: "SITE", geometry: .circle(CircleGeom(.zero, 500)))])
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(10000, 0))), layer: "SITE")
        d.add(.insert(InsertGeom(block: "TREE", position: Vec2(2000, 2000))), layer: "SITE")
        d.add(.point(Vec2(1, 1)), layer: "0")
        return d
    }
    func write(_ d: ArchiDocument, _ name: String) throws -> URL {
        let u = dir.appendingPathComponent(name)
        try ArchiFile.encode(d).write(to: u)
        return u
    }
    func inserts(_ ed: Editor, _ block: String) -> [InsertGeom] {
        ed.doc.entities.compactMap { if case .insert(let i) = $0.geometry, i.block == block { return i }; return nil }
    }

    func testAttachReloadDetach() async throws {
        let src = try write(site(), "site.archi")
        let ed = Editor()
        await ed.run("XATTACH \(src.path) A 100,200 1 1 0")
        XCTAssertEqual(Xrefs.all(ed.doc).map(\.name), ["site"])
        XCTAssertEqual(inserts(ed, "site").count, 1)
        XCTAssertEqual(inserts(ed, "site").first?.position, Vec2(100, 200))
        let blk = ed.doc.blocks["site"]!
        XCTAssertEqual(blk.entities.count, 3)
        XCTAssertTrue(blk.entities.contains { $0.layer == "site|SITE" })
        XCTAssertTrue(blk.entities.contains { $0.layer == "0" }, "layer 0 is not prefixed")
        XCTAssertNotNil(ed.doc.blocks["site|TREE"], "nested blocks are prefixed")
        XCTAssertTrue(blk.entities.contains { if case .insert(let i) = $0.geometry { return i.block == "site|TREE" }; return false })
        XCTAssertEqual(ed.doc.layer(named: "site|SITE")?.color, RGBA(0, 1, 0))
        // Xref layer control: turning off the xref layer is kept on reload (VISRETAIN).
        await ed.run("LAYER OFF site|SITE ")
        // Change the source file and reload.
        var s2 = site(); s2.add(.line(LineGeom(.zero, Vec2(0, 5000))), layer: "SITE")
        try ArchiFile.encode(s2).write(to: src)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: src.path)
        XCTAssertEqual(Xrefs.changed(ed.doc, base: nil), ["site"], "change notification")
        await ed.run("XREF R site")
        XCTAssertEqual(ed.doc.blocks["site"]?.entities.count, 4)
        XCTAssertFalse(ed.doc.layer(named: "site|SITE")!.visible)
        XCTAssertEqual(Xrefs.changed(ed.doc, base: nil), [])
        // Unload / reload.
        await ed.run("XREF U site")
        XCTAssertEqual(ed.doc.blocks["site"]?.entities.count, 0)
        XCTAssertEqual(Xrefs.named("site", ed.doc)?.loaded, false)
        await ed.run("XREF R *")
        XCTAssertEqual(ed.doc.blocks["site"]?.entities.count, 4)
        // Persistence of the registry.
        let back = try JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        XCTAssertEqual(Xrefs.all(back), Xrefs.all(ed.doc))
        // Detach removes references, blocks and layers.
        await ed.run("XREF D site")
        XCTAssertNil(ed.doc.blocks["site"]); XCTAssertNil(ed.doc.blocks["site|TREE"])
        XCTAssertNil(ed.doc.layer(named: "site|SITE"))
        XCTAssertTrue(inserts(ed, "site").isEmpty)
        XCTAssertTrue(Xrefs.all(ed.doc).isEmpty)
    }

    func testBindAndInsertModes() async throws {
        let src = try write(site(), "site.archi")
        let ed = Editor()
        await ed.run("XATTACH \(src.path) A 0,0 1 1 0")
        await ed.run("XBIND site B")
        XCTAssertTrue(Xrefs.all(ed.doc).isEmpty)
        XCTAssertNotNil(ed.doc.blocks["site"], "the xref becomes an ordinary block")
        XCTAssertNotNil(ed.doc.layer(named: "site$0$SITE"))
        XCTAssertNotNil(ed.doc.blocks["site$0$TREE"])
        XCTAssertTrue(ed.doc.blocks["site"]!.entities.contains { if case .insert(let i) = $0.geometry { return i.block == "site$0$TREE" }; return false })
        // Insert mode merges names.
        let ed2 = Editor()
        await ed2.run("XATTACH \(src.path) A 0,0 1 1 0")
        await ed2.run("XREF B site I")
        XCTAssertNotNil(ed2.doc.layer(named: "SITE")); XCTAssertNotNil(ed2.doc.blocks["TREE"])
        XCTAssertTrue(ed2.doc.blocks["site"]!.entities.contains { $0.layer == "SITE" })
    }

    func testDXFXrefOverlayAndCircular() async throws {
        // DXF source.
        let dxf = dir.appendingPathComponent("plan.dxf")
        try DXFWriter.write(site()).write(to: dxf, atomically: true, encoding: .utf8)
        var host = ArchiDocument()
        let n = try Xrefs.attach(&host, path: dxf.path)
        XCTAssertEqual(n, "plan")
        XCTAssertFalse(host.blocks["plan"]!.entities.isEmpty)
        // A drawing that overlays another does not pass the overlay on.
        var mid = site()
        try Xrefs.attach(&mid, path: dxf.path, name: "ov", overlay: true)
        mid.add(.insert(InsertGeom(block: "ov", position: .zero)))
        let midURL = try write(mid, "mid.archi")
        var top = ArchiDocument()
        try Xrefs.attach(&top, path: midURL.path)
        XCTAssertNil(top.blocks["mid|ov"], "overlay xrefs are not nested")
        XCTAssertFalse(top.blocks["mid"]!.entities.contains { if case .insert(let i) = $0.geometry { return i.block.hasSuffix("ov") }; return false })
        // Attached (not overlaid) nested xrefs are carried.
        var mid2 = site()
        try Xrefs.attach(&mid2, path: dxf.path, name: "att")
        mid2.add(.insert(InsertGeom(block: "att", position: .zero)))
        let mid2URL = try write(mid2, "mid2.archi")
        var top2 = ArchiDocument()
        try Xrefs.attach(&top2, path: mid2URL.path)
        XCTAssertNotNil(top2.blocks["mid2|att"])
        // Self reference is refused; relative paths resolve against the host folder.
        XCTAssertThrowsError(try Xrefs.attach(&top2, path: mid2URL.path, host: mid2URL))
        var rel = ArchiDocument()
        _ = try write(site(), "site.archi")
        XCTAssertEqual(try Xrefs.attach(&rel, path: "site.archi", base: dir), "site")
        XCTAssertThrowsError(try Xrefs.attach(&rel, path: "missing.archi", base: dir))
    }

    func testBlockLibraryScanSearchLoad() async throws {
        let sub = dir.appendingPathComponent("Trees")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = try write(site(), "Trees/oak.archi")
        let items = BlockLibrary.scan(dir)
        XCTAssertEqual(items.map(\.name).sorted(), ["TREE", "oak"])
        XCTAssertEqual(items.first?.folder, "Trees")
        XCTAssertEqual(BlockLibrary.search(items, "tree oak").count, 2, "folder name matches")
        XCTAssertEqual(BlockLibrary.search(items, "TREE").count, 2)
        var doc = ArchiDocument()
        let n = try BlockLibrary.load(items.first { $0.name == "oak" }!, into: &doc)
        XCTAssertEqual(n, "oak")
        XCTAssertNotNil(doc.blocks["TREE"], "nested blocks come along")
        XCTAssertNotNil(doc.layer(named: "SITE"))
        let ed = Editor()
        await ed.run("BLOCKLIBRARY \(dir.path) TREE 10,10 1 1 0")
        XCTAssertEqual(inserts(ed, "TREE").count, 1)
    }
}
