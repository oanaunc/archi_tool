// Oanarina Archi Tool — GPL-3.0-or-later
// eTransmit packages (references rewritten, transmittal report) and batch jobs run in-process (BATCH command).
import XCTest
@testable import ArchiCore

final class IOTransmitBatchTests: XCTestCase {
    func tmp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-tx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testETransmitPacksReferencesAndReopensElsewhere() throws {
        let src = try tmp()
        let img = src.appendingPathComponent("site plan.png"), tex = src.appendingPathComponent("oak.jpg")
        let png = IOGeoImageTests.png(20, 10)
        try png.write(to: img); try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: tex)
        var x = ArchiDocument(); _ = x.add(.line(LineGeom(.zero, Vec2(100, 0))))
        try ArchiFile.encode(x).write(to: src.appendingPathComponent("survey.archi"))
        var d = ArchiDocument()
        _ = d.add(.image(ImageGeom(path: img.path, origin: .zero, size: Vec2(2000, 1000))))
        _ = d.add(.image(ImageGeom(path: "site plan.png", origin: Vec2(5000, 0), size: Vec2(2000, 1000))))   // relative to the drawing
        _ = d.add(.image(ImageGeom(path: "/nowhere/missing.png", origin: .zero, size: Vec2(1, 1))))
        let i = d.materials.firstIndex { $0.name == "Wood" }!
        d.materials[i].texture = tex.path
        let xn = try Xrefs.attach(&d, path: "survey.archi", overlay: false, base: src, host: src.appendingPathComponent("house.archi"))
        d.textStyles.append(TextStyle(name: "Notes", font: "Georgia"))
        let (zip, rep) = ETransmit.pack(d, documentURL: src.appendingPathComponent("house.archi"), name: "house")
        XCTAssertEqual(rep.files.count, 3, "image once, texture, xref")
        XCTAssertEqual(rep.missing, ["/nowhere/missing.png"])
        XCTAssertEqual(rep.fonts, ["Georgia", "Helvetica"])
        // Unpack on "another machine".
        let dst = try tmp()
        let drawing = try ETransmit.unpack(zip, to: dst)
        XCTAssertEqual(drawing.lastPathComponent, "house.archi")
        let back = try ArchiFile.decode(Data(contentsOf: drawing))
        let paths = back.entities.compactMap { e -> String? in if case .image(let im) = e.geometry { return im.path }; return nil }
        XCTAssertEqual(paths.filter { $0 == "files/site plan.png" }.count, 2)
        XCTAssertEqual(try Data(contentsOf: drawing.deletingLastPathComponent().appendingPathComponent("files/site plan.png")), png)
        XCTAssertEqual(back.materials[i].texture, "files/oak.jpg")
        let xi = try XCTUnwrap(Xrefs.named(xn, back))
        XCTAssertEqual(xi.path, "files/survey.archi")
        XCTAssertTrue(FileManager.default.fileExists(atPath: Xrefs.resolve(xi.path, base: drawing.deletingLastPathComponent()).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: drawing.deletingLastPathComponent().appendingPathComponent("transmittal.txt").path))
        XCTAssertThrowsError(try ETransmit.unpack(ZipArchive.write([.init(name: "a.txt", data: Data())]), to: dst))
    }

    func testDocumentIOWritesEveryFormat() throws {
        let dir = try tmp()
        var d = ArchiDocument()
        _ = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))), material: "Brick")
        _ = d.add(.line(LineGeom(.zero, Vec2(1000, 1000))))
        for f in ["archi", "dxf", "svg", "ifc", "obj", "stl", "glb", "csv", "dae", "kml", "kmz", "usdz", "gbxml", "step"] {
            let u = dir.appendingPathComponent("m.\(f == "gbxml" ? "xml" : f)")
            try DocumentIO.write(d, to: u, format: f)
            XCTAssertGreaterThan((try? Data(contentsOf: u).count) ?? 0, 0, f)
        }
        // PDF is plotted headless (PDFWriter).
        try DocumentIO.write(d, to: dir.appendingPathComponent("m.pdf"))
        XCTAssertTrue((try Data(contentsOf: dir.appendingPathComponent("m.pdf"))).starts(with: Array("%PDF".utf8)))
        XCTAssertThrowsError(try DocumentIO.write(d, to: dir.appendingPathComponent("m.nope")))
        XCTAssertEqual(try DocumentIO.read(dir.appendingPathComponent("m.archi")).elements.count, 1)
        XCTAssertFalse(try DocumentIO.read(dir.appendingPathComponent("m.dxf")).entities.isEmpty)
    }

    @MainActor
    func testBatchCommandRunsJobs() async throws {
        let dir = try tmp()
        var d = ArchiDocument(); _ = d.add(.line(LineGeom(.zero, Vec2(100, 0))))
        try ArchiFile.encode(d).write(to: dir.appendingPathComponent("a.archi"))
        try "; setup\nCIRCLE 0,0 50\n".write(to: dir.appendingPathComponent("s.scr"), atomically: true, encoding: .utf8)
        let jobs = """
        {"jobs": [{"name": "A", "input": "a.archi", "script": "s.scr", "commands": ["LINE 0,0 0,100 "], "outputs": ["out/a.dxf"],
                   "reports": [{"tool": "check_model", "path": "out/check.json"}, {"tool": "takeoff", "path": "out/q.csv"}], "save": "out/a.archi"},
                  {"name": "B", "commands": ["WALL 0,0 3000,0 "], "outputs": [{"path": "out/b.ifc"}]}]}
        """
        try jobs.write(to: dir.appendingPathComponent("jobs.json"), atomically: true, encoding: .utf8)
        let ed = Editor(document: ArchiDocument())
        let log = await ed.run("BATCH \(dir.appendingPathComponent("jobs.json").path)")
        XCTAssertTrue(log.contains("Batch: 2 succeeded, 0 failed."), log.joined(separator: "\n"))
        let a = try ArchiFile.decode(Data(contentsOf: dir.appendingPathComponent("out/a.archi")))
        XCTAssertEqual(a.entities.count, 3, "line + script circle + command line")
        for f in ["out/a.dxf", "out/check.json", "out/q.csv", "out/b.ifc"] { XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path), f) }
        XCTAssertTrue(try String(contentsOf: dir.appendingPathComponent("out/b.ifc"), encoding: .utf8).contains("IFCWALL"))
        XCTAssertTrue(ed.doc.entities.isEmpty, "the open drawing is untouched")
    }
}
