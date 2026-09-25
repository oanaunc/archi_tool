// Oanarina Archi Tool — GPL-3.0-or-later
// KML/KMZ geolocation, layered SVG, USDZ textures, raster image headers, world files and two-point image scaling.
import XCTest
@testable import ArchiCore

final class IOGeoImageTests: XCTestCase {
    func tmp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-geo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func png(_ w: Int, _ h: Int) -> Data {
        var b: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
        for v in [w, h] { b += [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
        b += [8, 2, 0, 0, 0, 0, 0, 0, 0]
        return Data(b)
    }

    func testImageHeaders() {
        XCTAssertEqual(ImageHeader.size(Self.png(640, 480)).map { [$0.width, $0.height] }, [640, 480])
        var jpg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] + Array(repeating: 0, count: 14)
        jpg += [0xFF, 0xC0, 0x00, 0x11, 0x08, 0x01, 0x2C, 0x01, 0x90] + Array(repeating: 0, count: 12)   // 400 × 300
        XCTAssertEqual(ImageHeader.size(Data(jpg)).map { [$0.width, $0.height] }, [400, 300])
        let gif: [UInt8] = Array("GIF89a".utf8) + [0x20, 0x03, 0x58, 0x02] + Array(repeating: 0, count: 20)       // 800 × 600
        XCTAssertEqual(ImageHeader.size(Data(gif)).map { [$0.width, $0.height] }, [800, 600])
        var bmp: [UInt8] = Array("BM".utf8) + Array(repeating: 0, count: 16)
        bmp += [0x0A, 0, 0, 0, 0xF6, 0xFF, 0xFF, 0xFF] + Array(repeating: 0, count: 10)                          // 10 × −10 (top-down)
        XCTAssertEqual(ImageHeader.size(Data(bmp)).map { [$0.width, $0.height] }, [10, 10])
        var tif: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0, 2, 0]
        tif += [0, 1, 3, 0, 1, 0, 0, 0, 0x64, 0, 0, 0]      // ImageWidth 100
        tif += [1, 1, 4, 0, 1, 0, 0, 0, 0x32, 0, 0, 0]      // ImageLength 50
        tif += Array(repeating: 0, count: 8)
        XCTAssertEqual(ImageHeader.size(Data(tif)).map { [$0.width, $0.height] }, [100, 50])
        XCTAssertNil(ImageHeader.size(Data("not an image at all, sorry".utf8)))
    }

    func testWorldFileAndTwoPointScaling() throws {
        // 0.5 m pixels, upper-left pixel centre at (100.25, 200.75): a 200 × 100 px image covers x 100…200, y 151…201.
        let w = try XCTUnwrap(WorldFile.parse("0.5\n0\n0\n-0.5\n100.25\n200.75\n"))
        let p = w.placement(width: 200, height: 100)
        XCTAssertEqual(p.origin.x, 100, accuracy: 1e-9); XCTAssertEqual(p.origin.y, 151, accuracy: 1e-9)
        XCTAssertEqual(p.size.x, 100, accuracy: 1e-9); XCTAssertEqual(p.size.y, 50, accuracy: 1e-9)
        XCTAssertEqual(p.rotation, 0, accuracy: 1e-12)
        let im = ImagePlacement.georeferenced(path: "a.png", pixels: (200, 100), world: w, unitMM: 1, worldOrigin: Vec2(100, 150))
        XCTAssertEqual(im.origin, Vec2(0, 1000)); XCTAssertEqual(im.size, Vec2(100_000, 50_000))
        // Rotated world file (30°).
        let c = cos(Double.pi / 6), s = sin(Double.pi / 6)
        let r = WorldFile(a: c, d: s, b: s, e: -c, c: 0, f: 0).placement(width: 10, height: 10)
        XCTAssertEqual(r.rotation, Double.pi / 6, accuracy: 1e-9); XCTAssertEqual(r.size.x, 10, accuracy: 1e-9)
        XCTAssertNil(WorldFile.parse("1\n2\n"))
        XCTAssertEqual(WorldFile.candidates(for: URL(fileURLWithPath: "/x/plan.png")).map(\.lastPathComponent), ["plan.pgw", "plan.pngw", "plan.wld"])
        // Two-point calibration: 100 units measured should be 1000.
        let base = ImageGeom(path: "p", origin: .zero, size: Vec2(1000, 500))
        let sc = try XCTUnwrap(ImagePlacement.scaled(base, p1: Vec2(100, 100), p2: Vec2(200, 100), distance: 1000))
        XCTAssertEqual(sc.size, Vec2(10000, 5000)); XCTAssertEqual(sc.origin, Vec2(-900, -900))
        XCTAssertNil(ImagePlacement.scaled(base, p1: .zero, p2: .zero, distance: 10))
        // Files: with and without a world file.
        let dir = try tmp()
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        try Self.png(200, 100).write(to: a); try Self.png(200, 100).write(to: b)
        try "0.5\n0\n0\n-0.5\n100.25\n200.75\n".write(to: dir.appendingPathComponent("a.pgw"), atomically: true, encoding: .utf8)
        var doc = ArchiDocument()
        doc.setVariable("GEOORIGIN", "100,150")
        let (ga, geo) = try ImagePlacement.load(a, doc: doc)
        XCTAssertTrue(geo); XCTAssertEqual(ga.origin, Vec2(0, 1000)); XCTAssertEqual(ga.size.x, 100_000, accuracy: 1e-6)
        let (gb, geo2) = try ImagePlacement.load(b, doc: doc, origin: Vec2(5, 5), width: 4000)
        XCTAssertFalse(geo2); XCTAssertEqual(gb.size, Vec2(4000, 2000)); XCTAssertEqual(gb.origin, Vec2(5, 5))
        let (imported, summary) = try FileImport.load(a, reference: doc)
        XCTAssertTrue(summary.contains("georeferenced"))
        XCTAssertEqual(imported.entities.count, 1)
    }

    @MainActor
    func testImageCommandsHeadless() async throws {
        let dir = try tmp()
        let a = dir.appendingPathComponent("scan.png")
        try Self.png(300, 150).write(to: a)
        let ed = Editor(document: ArchiDocument())
        var log = await ed.run("IMAGEIMPORT \(a.path) 0,0 3000")
        let e = try XCTUnwrap(ed.doc.entities.first, log.joined(separator: "\n"))
        guard case .image(let im) = e.geometry else { return XCTFail() }
        XCTAssertEqual(im.size, Vec2(3000, 1500))
        log = await ed.run("IMAGESCALE #\(e.id) 0,0 300,0 6000")
        guard case .image(let im2) = ed.doc.entities.first!.geometry else { return XCTFail() }
        XCTAssertEqual(im2.size.x, 60000, accuracy: 1e-6, log.joined(separator: "\n"))
    }

    func testKMLAndKMZPlacement() throws {
        var d = ArchiDocument()
        d.info.name = "Villa"; d.info.latitude = 45; d.info.longitude = 25
        _ = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(10000, 0), thickness: 200, height: 3000)), material: "Brick")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 100), Vec2(10000, 100), Vec2(10000, 5000), Vec2(0, 5000)], name: "Living", number: "1")))
        _ = d.add(.line(LineGeom(Vec2(0, 0), Vec2(10000, 0))))
        let k = KMLExporter.kml(d)
        XCTAssertTrue(XMLParser(data: Data(k.utf8)).parse())
        XCTAssertTrue(k.contains("<extrude>1</extrude>"))
        XCTAssertTrue(k.contains("<name>1 Living</name>"))
        // 10 m east of the origin at 45° N: Δlon = deg(10 / (R cos 45°)).
        let lon10 = 25 + 10 / (6_378_137 * cos(Double.pi / 4)) * 180 / .pi
        XCTAssertTrue(k.contains("\(fmt(lon10, 8)),\(fmt(45, 8))"), "east end of the line")
        let g = KMLExporter.lonLat(Vec2(0, 10000), doc: d)
        XCTAssertEqual(g.lat, 45 + 10 / 6_378_137 * 180 / .pi, accuracy: 1e-10); XCTAssertEqual(g.lon, 25, accuracy: 1e-12)
        // True north turned 90° counter-clockwise from +Y: +Y points east.
        d.info.northAngle = 90
        let g90 = KMLExporter.lonLat(Vec2(0, 10000), doc: d)
        XCTAssertEqual(g90.lat, 45, accuracy: 1e-10); XCTAssertGreaterThan(g90.lon, 25)
        let kmz = KMLExporter.kmz(d)
        let entries = try ZipArchive.read(kmz)
        XCTAssertEqual(entries.first?.name, "doc.kml")
        XCTAssertTrue(entries.contains { $0.name == "models/model.dae" })
        let doc = String(decoding: entries[0].data, as: UTF8.self)
        XCTAssertTrue(doc.contains("<href>models/model.dae</href>")); XCTAssertTrue(doc.contains("<heading>90</heading>"))
    }

    func testLayeredSVG() throws {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "A-WALL", color: RGBA(1, 0, 0)))
        d.layers.append(Layer(name: "Notes & text", color: RGBA(0, 0, 1)))
        _ = d.add(Entity(layer: "Notes & text", geometry: .line(LineGeom(Vec2(0, 0), Vec2(100, 0)))))
        _ = d.add(Entity(layer: "A-WALL", geometry: .circle(CircleGeom(Vec2(50, 50), 20))))
        let entries = DrawListBuilder.entries(doc: d, options: DrawOptions(level: 0))
        let svg = SVGExporter.exportLayered(doc: d, entries: entries, bounds: BBox2(min: Vec2(-10, -10), max: Vec2(110, 80)), background: nil)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
        XCTAssertTrue(svg.contains("xmlns:inkscape="))
        let a = try XCTUnwrap(svg.range(of: "inkscape:label=\"A-WALL\"")), n = try XCTUnwrap(svg.range(of: "inkscape:label=\"Notes &amp; text\""))
        XCTAssertLessThan(a.lowerBound, n.lowerBound, "document layer order")
        let labels = svg.components(separatedBy: "inkscape:label=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
        XCTAssertTrue(Set(labels).isSubset(of: ["A-WALL", "Notes &amp; text", "Plan"]), "\(labels)")
        XCTAssertEqual(labels.count, Set(labels).count, "one group per layer")
        XCTAssertFalse(SVGExporter.export(entries: entries, bounds: BBox2(min: .zero, max: Vec2(1, 1)), background: nil).contains("inkscape"), "plain export unchanged")
    }

    func testUSDZPackagesTextures() throws {
        let dir = try tmp()
        let tex = dir.appendingPathComponent("brick.png")
        try Self.png(64, 64).write(to: tex)
        var d = ArchiDocument()
        let i = d.materials.firstIndex { $0.name == "Brick" }!
        d.materials[i].texture = "brick.png"; d.materials[i].textureScale = 500
        _ = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))), material: "Brick")
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 3000), Vec2(0, 3000)])), material: "Concrete")
        let url = dir.appendingPathComponent("m.usdz")
        XCTAssertTrue(try FileImport.export(d, to: url, format: "usdz"))
        let entries = try ZipArchive.read(try Data(contentsOf: url))
        XCTAssertEqual(entries.first?.name, "model.usda")
        let t = try XCTUnwrap(entries.first { $0.name.hasPrefix("textures/") })
        XCTAssertEqual(t.data, Self.png(64, 64))
        let usda = String(decoding: entries[0].data, as: UTF8.self)
        XCTAssertTrue(usda.contains("UsdUVTexture")); XCTAssertTrue(usda.contains("@\(t.name)@")); XCTAssertTrue(usda.contains("texCoord2f[] primvars:st"))
        XCTAssertEqual(usda.components(separatedBy: "UsdUVTexture").count - 1, 1, "only the textured material")
        // A missing texture file falls back to the plain colour.
        d.materials[i].texture = "missing.png"
        let plain = try ZipArchive.read(USDExporter.usdz(MeshBuilder.build(doc: d), materials: d.materials, metersPerUnit: 0.001, name: "M", textureRoot: dir))
        XCTAssertEqual(plain.count, 1)
    }
}
