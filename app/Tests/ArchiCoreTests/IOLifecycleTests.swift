// Oanarina Archi Tool — GPL-3.0-or-later
// File life cycle (IO-001 round trip, IO-002 Save a Copy, IO-004 upgrades, IO-005 templates, IO-007 metadata),
// pasted/dropped content (IO-064/065), PDF underlays (IO-015), OpenCASCADE BREP (IO-042) and E57 (IO-048).
import XCTest
@testable import ArchiCore

final class IOLifecycleTests: XCTestCase {
    func tmp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("archi-life-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A document using most of the model: every entity kind, BIM elements, blocks, sheets, variables, Unicode.
    static func richDocument() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.name = "Casă Ünïcode 住宅 🏠"
        d.info.author = "Oana"
        d.units = .centimeters
        d.layers.append(Layer(name: "Notițe", color: RGBA(0.2, 0.4, 0.6), linetype: "Dashed", lineweight: 0.35, frozen: true, transparency: 0.3, description: "עברית ومرحبا"))
        d.add(.point(Vec2(1.5, -2.25)))
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000.125, 333.333333333))), layer: "Notițe", color: .rgb(12, 34, 56))
        d.add(.circle(CircleGeom(Vec2(5, 5), 0.1)), color: .aci(3))
        d.add(.arc(ArcGeom(Vec2(0, 0), 250, 0.1, 4.5)))
        d.add(.ellipse(EllipseGeom(center: Vec2(10, 10), majorAxis: Vec2(300, 100), ratio: 0.4)))
        d.add(.polyline(PolylineGeom([PolyVertex(Vec2(0, 0), bulge: 0.5), PolyVertex(Vec2(100, 0)), PolyVertex(Vec2(100, 50))], closed: true, width: 2)))
        d.add(.spline(SplineGeom(controlPoints: [Vec2(0, 0), Vec2(10, 20), Vec2(30, 5), Vec2(40, 40)])))
        d.add(.text(TextGeom(position: Vec2(3, 4), height: 25, content: "Living — سلام שלום 你好 😀", rotation: 0.3)))
        d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(100, 0), Vec2(50, 20)])))
        d.add(.hatch(HatchGeom(loops: [[PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(10, 0)), PolyVertex(Vec2(10, 10))]])))
        d.add(.leader(LeaderGeom(points: [Vec2(0, 0), Vec2(5, 5)], text: "Note")))
        d.add(.table(TableGeom(origin: .zero, columnWidths: [10, 20], rowHeight: 5, cells: [["a", "b"], ["ç", "ß"]])))
        d.add(.solid(SolidGeom(kind: .box, origin: Vec3(1, 2, 3), size: Vec3(100, 200, 300), rotation: 0.2)))
        d.blocks["Chair"] = Block(name: "Chair", basePoint: Vec2(1, 1), entities: [Entity(id: 1, geometry: .circle(CircleGeom(.zero, 20)))], description: "chair")
        d.add(.insert(InsertGeom(block: "Chair", position: Vec2(50, 50), scale: Vec2(2, 2), rotation: 1, attributes: ["TAG": "C1"])))
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(400, 0), thickness: 20, height: 280)), material: "Brick")
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 200, width: 120, height: 120, sill: 90)))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(400, 0), Vec2(400, 300), Vec2(0, 300)], name: "Cameră de zi", number: "1")))
        d.variables["LTSCALE"] = "2.5"
        d.keynotes["01"] = "Brick"
        d.namedViews.append(NamedView(name: "V1", center: Vec2(1, 2), height: 100))
        return d
    }

    func testSaveAndReopenIsIdentical() throws {
        let d = Self.richDocument()
        XCTAssertEqual(try ArchiFile.roundTripDifferences(d), [])
        XCTAssertEqual(try ArchiFile.decode(ArchiFile.encode(d)), d)
        // A second save is byte-identical (stable key order).
        let a = try ArchiFile.encode(d)
        XCTAssertEqual(try ArchiFile.encode(ArchiFile.decode(a)), a)
        // Also through a file on disk with a .bak backup.
        let dir = try tmp(), url = dir.appendingPathComponent("r.archi")
        try DocumentIO.write(d, to: url)
        try DocumentIO.write(d, to: url)
        XCTAssertEqual(try DocumentIO.read(url), d)
    }

    func testTemplatesRoundTripLosslessly() throws {
        let d = Self.richDocument()
        let data = try ArchiTemplate.encode(d, info: ArchiTemplate.Info(name: "Office", description: "Layers and styles"))
        let t = try ArchiTemplate.decode(data)
        XCTAssertEqual(t.document, d)
        XCTAssertEqual(t.info.name, "Office"); XCTAssertEqual(t.info.description, "Layers and styles")
        XCTAssertTrue(try ArchiFile.inspect(data).isTemplate)
        XCTAssertEqual(try ArchiFile.decode(data), d, "any .archi reader opens a template")
        let n = ArchiTemplate.newDocument(from: t.document)
        XCTAssertEqual(n.info.name, "Untitled Project")
        XCTAssertEqual(n.entities, d.entities); XCTAssertEqual(n.layers, d.layers); XCTAssertEqual(n.elements, d.elements)
        XCTAssertNotNil(n.variables["TDCREATE"])
        // Through the file layer and the import dispatcher.
        let dir = try tmp(), url = dir.appendingPathComponent("Office.architemplate")
        try DocumentIO.write(d, to: url, format: "architemplate")
        XCTAssertEqual(try FileImport.load(url).0, d)
    }

    @MainActor func testTemplateCommandsAreUndoable() async throws {
        let dir = try tmp(), url = dir.appendingPathComponent("T.architemplate")
        let ed = Editor()
        await ed.run("LINE 0,0 500,0 ")
        await ed.run("TEMPLATEOUT \"\(url.path)\" Standard office")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await ed.run("ERASE ALL ")
        await ed.run("CIRCLE 0,0 10")
        await ed.run("TEMPLATEIN \"\(url.path)\"")
        XCTAssertEqual(ed.doc.entities.count, 1)
        guard case .line = ed.doc.entities[0].geometry else { return XCTFail() }
        await ed.run("UNDO")
        guard case .circle = ed.doc.entities.last?.geometry else { return XCTFail("TEMPLATEIN undone") }
    }

    func testUpgradeOlderFilesKeepsBackup() throws {
        let dir = try tmp(), url = dir.appendingPathComponent("old.archi")
        let v1 = """
        {"app":"Oanarina Archi Tool","formatVersion":1,"document":{"formatVersion":1,"nextID":2,"entities":[
          {"id":1,"layer":"0","color":"bylayer","props":{},"geometry":{"type":"line","a":{"x":0,"y":0},"b":{"x":10,"y":0}}}]}}
        """
        try Data(v1.utf8).write(to: url)
        let info = try ArchiFile.inspect(Data(contentsOf: url))
        XCTAssertEqual(info.formatVersion, 1); XCTAssertTrue(info.needsUpgrade); XCTAssertEqual(info.entities, 1)
        let r = try ArchiFile.upgradeFile(url)
        XCTAssertEqual(r.from, 1); XCTAssertEqual(r.to, ArchiDocument.currentFormatVersion)
        XCTAssertEqual(try ArchiFile.inspect(Data(contentsOf: url)).formatVersion, ArchiDocument.currentFormatVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.backup!.path))
        XCTAssertEqual(try ArchiFile.inspect(Data(contentsOf: r.backup!)).formatVersion, 1)
        XCTAssertEqual(try DocumentIO.read(url).entities.count, 1)
        // Current files are left alone; newer files are refused.
        XCTAssertNil(try ArchiFile.upgradeFile(url).backup)
        let newer = dir.appendingPathComponent("new.archi")
        try Data("{\"app\":\"x\",\"formatVersion\":99,\"document\":{\"entities\":[]}}".utf8).write(to: newer)
        XCTAssertThrowsError(try ArchiFile.upgradeFile(newer))
    }

    @MainActor func testSaveCopyLeavesTheDrawingAlone() async throws {
        let dir = try tmp()
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        ed.isDirty = true
        await ed.run("SAVECOPY \"\(dir.appendingPathComponent("copy.dxf").path)\"")
        await ed.run("SAVECOPY \"\(dir.appendingPathComponent("copy").path)\"")
        XCTAssertNil(ed.fileURL); XCTAssertTrue(ed.isDirty)
        XCTAssertEqual(try DocumentIO.read(dir.appendingPathComponent("copy.archi")), ed.doc)
        XCTAssertEqual(try DocumentIO.read(dir.appendingPathComponent("copy.dxf")).entities.count, 1)
        let out = await ed.run("SAVECHECK")
        XCTAssertTrue(out.joined().contains("Round trip OK"), out.joined())
    }

    func testSpotlightMetadata() throws {
        let a = SpotlightMetadata.attributes(Self.richDocument())
        XCTAssertEqual(a["kMDItemTitle"] as? String, "Casă Ünïcode 住宅 🏠")
        XCTAssertEqual(a["kMDItemAuthors"] as? [String], ["Oana"])
        let text = a["kMDItemTextContent"] as? String ?? ""
        XCTAssertTrue(text.contains("你好")); XCTAssertTrue(text.contains("Cameră de zi")); XCTAssertTrue(text.contains("ß"))
        XCTAssertTrue((a["kMDItemKeywords"] as? [String] ?? []).contains("Notițe"))
        XCTAssertEqual(a["org.oanarina.archi.rooms"] as? [String], ["1 Cameră de zi"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(a))
    }

    func testPastedContentKinds() throws {
        var d = ArchiDocument()
        XCTAssertEqual(ExternalContent.kind(of: Data("<svg xmlns='http://www.w3.org/2000/svg'><line x1='0' y1='0' x2='10' y2='0'/></svg>".utf8), type: nil), .svg)
        XCTAssertEqual(ExternalContent.kind(of: Data("%PDF-1.4".utf8), type: nil), .pdf)
        XCTAssertEqual(ExternalContent.kind(of: Data("hello".utf8), type: "public.utf8-plain-text"), .text)
        XCTAssertEqual(ExternalContent.kind(of: try ArchiFile.encode(ArchiDocument()), type: nil), .archi)
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='100mm' height='100mm' viewBox='0 0 100 100'><line x1='0' y1='0' x2='50' y2='0' stroke='black'/><rect x='10' y='10' width='20' height='20' fill='none' stroke='red'/></svg>"
        let r = try ExternalContent.insert(Data(svg.utf8), type: "public.svg-image", into: &d, at: Vec2(1000, 1000))
        XCTAssertEqual(r.ids.count, 2)
        let b = r.ids.compactMap { d.entity($0) }.reduce(BBox2.empty) { $0.union(GeometryOps.bounds($1.geometry, doc: d)) }
        XCTAssertEqual(b.min.x, 1000, accuracy: 1e-6); XCTAssertEqual(b.min.y, 1000, accuracy: 1e-6)
        let t = try ExternalContent.insert(Data("Pasted note\nline 2".utf8), type: "public.utf8-plain-text", into: &d, at: Vec2(5, 5))
        guard case .text(let tg) = d.entity(t.ids[0])!.geometry else { return XCTFail() }
        XCTAssertEqual(tg.content, "Pasted note\nline 2")
        // A pasted drawing merges with new ids.
        var src = ArchiDocument(); src.add(.line(LineGeom(.zero, Vec2(10, 0))))
        let m = try ExternalContent.insert(try ArchiFile.encode(src), type: "org.oanarina.archi", into: &d)
        XCTAssertEqual(m.ids.count, 1)
        // Images are saved next to the drawing and placed at 96 dpi.
        let dir = try tmp()
        let png = RasterImage(width: 96, height: 48, gray: [UInt8](repeating: 200, count: 96 * 48)).pngData()
        let im = try ExternalContent.insert(png, type: "public.png", into: &d, at: .zero, assetFolder: dir)
        guard case .image(let ig) = d.entity(im.ids[0])!.geometry else { return XCTFail() }
        XCTAssertEqual(ig.size.x, 25.4, accuracy: 1e-6); XCTAssertEqual(ig.size.y, 12.7, accuracy: 1e-6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ig.path))
    }

    func testDroppedFiles() throws {
        let dir = try tmp()
        var src = ArchiDocument(); src.add(.circle(CircleGeom(.zero, 100)))
        let dxf = dir.appendingPathComponent("a.dxf"); try DXFWriter.write(src).write(to: dxf, atomically: true, encoding: .utf8)
        let pdf = dir.appendingPathComponent("b.pdf"); try IOPDFImportTests.samplePDF().write(to: pdf)
        XCTAssertEqual(ExternalContent.dropAction(for: dxf), .importFile)
        XCTAssertEqual(ExternalContent.dropAction(for: pdf), .attachPDF)
        XCTAssertEqual(ExternalContent.dropAction(for: URL(fileURLWithPath: "/x/y.archi")), .open)
        XCTAssertEqual(ExternalContent.dropAction(for: URL(fileURLWithPath: "/x/y.png")), .attachImage)
        XCTAssertEqual(ExternalContent.dropAction(for: URL(fileURLWithPath: "/x/y.scr")), .runScript)
        var d = ArchiDocument()
        let r = ExternalContent.drop([dxf, pdf, URL(fileURLWithPath: "/x/none.archi")], into: &d)
        XCTAssertEqual(r.count, 3)
        XCTAssertNotNil(r[0].result); XCTAssertNotNil(r[1].result); XCTAssertNil(r[2].result)
        XCTAssertEqual(PDFUnderlay.list(d).count, 1)
    }

    @MainActor func testPDFUnderlayAttachReloadDetach() async throws {
        let dir = try tmp(), pdf = dir.appendingPathComponent("plan.pdf")
        try IOPDFImportTests.samplePDF().write(to: pdf)
        let ed = Editor()
        await ed.run("PDFATTACH \"\(pdf.path)\" 1 100 1000,2000")
        let list = PDFUnderlay.list(ed.doc)
        XCTAssertEqual(list.count, 1)
        let u = list[0]
        XCTAssertGreaterThan(u.objects, 3); XCTAssertEqual(u.scale, 100)
        XCTAssertEqual(ed.doc.layer(named: PDFUnderlay.layer)?.locked, true)
        // The page's first line (10,10)–(100,10) pt at 1:100 lands at the insertion point + 100 × pt in mm.
        let k = 25.4 / 72 * 100
        let snap = Snap.find(cursor: Vec2(1000 + 100 * k, 2000 + 10 * k), doc: ed.doc, settings: ed.settings, tolerance: 50, base: nil)
        XCTAssertNotNil(snap, "object snaps work on the underlay")
        if let s = snap { XCTAssertEqual(s.point.distance(to: Vec2(1000 + 100 * k, 2000 + 10 * k)), 0, accuracy: 1) }
        // Reload after the PDF changed on disk, then detach.
        var d = ed.doc
        XCTAssertEqual(try PDFUnderlay.reload(u.id, in: &d), u.objects)
        await ed.run("PDFUNDERLAYS Fade 70")
        XCTAssertEqual(ed.doc.layer(named: PDFUnderlay.layer)?.transparency ?? 0, 0.7, accuracy: 1e-9)
        ed.selection = [u.id]
        await ed.run("PDFUNDERLAYS Detach")
        XCTAssertTrue(PDFUnderlay.list(ed.doc).isEmpty)
        XCTAssertNil(ed.doc.blocks[u.block])
        await ed.run("UNDO")
        XCTAssertEqual(PDFUnderlay.list(ed.doc).count, 1)
    }

    // MARK: BREP

    func testBREPExportImportRoundTrip() throws {
        var d = ArchiDocument()
        d.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 2000, 3000))))
        let text = BREPExporter.export(MeshBuilder.build(doc: d))
        XCTAssertTrue(text.contains("CASCADE Topology V1"))
        XCTAssertTrue(text.hasSuffix("+1 0\n"))
        // 8 shared vertices, 18 edges (12 box edges + 6 diagonals), 12 faces.
        XCTAssertEqual(text.components(separatedBy: "\nVe\n").count - 1 + (text.contains("TShapes") ? 0 : 0), 8)
        XCTAssertEqual(text.components(separatedBy: "\nEd\n").count - 1, 18)
        XCTAssertEqual(text.components(separatedBy: "\nFa\n").count - 1, 12)
        let ents = try BREPImporter.entities(text)
        XCTAssertEqual(ents.count, 1)
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(s.meshTriangles.count / 3, 12)
        let xs = s.meshVertices.map(\.x), zs = s.meshVertices.map(\.z)
        XCTAssertEqual(xs.max()!, 1000, accuracy: 1e-6); XCTAssertEqual(zs.max()!, 3000, accuracy: 1e-6)
        // Outward orientation kept: signed volume positive.
        var vol = 0.0
        for t in stride(from: 0, to: s.meshTriangles.count, by: 3) {
            let a = s.meshVertices[s.meshTriangles[t]], b = s.meshVertices[s.meshTriangles[t + 1]], c = s.meshVertices[s.meshTriangles[t + 2]]
            vol += a.dot(b.cross(c)) / 6
        }
        XCTAssertEqual(abs(vol), 1000 * 2000 * 3000, accuracy: 1)
        // Through the file layer (drawing units: metres).
        let dir = try tmp(), url = dir.appendingPathComponent("box.brep")
        try DocumentIO.write(d, to: url)
        var m = ArchiDocument(); m.units = .meters
        let (doc, summary) = try FileImport.load(url, reference: m)
        XCTAssertTrue(summary.contains("12 triangles"), summary)
        guard case .solid(let s2) = doc.entities[0].geometry else { return XCTFail() }
        XCTAssertEqual(s2.meshVertices.map(\.z).max()!, 3, accuracy: 1e-9)
    }

    /// An OCCT-style file (Draw header, version 2 p-curves with UV points, a location on the face, circle edges).
    func testBREPReadsOCCTStyleTopology() throws {
        let brep = """
        DBRep_DrawableShape

        CASCADE Topology V2, (c) Matra-Datavision
        Locations 1
        1
                      1               0               0               0
                      0               1               0               0
                      0               0               1               5
        Curve2ds 2
        1 0 0 1 0
        2 0 0 1 0 0 1 10
        Curves 2
        1 -10 0 0 1 0 0
        2 0 0 0 0 0 1 1 0 0 -0 1 0 10
        Polygon3D 0
        PolygonOnTriangulations 0
        Surfaces 1
        1 0 0 0 0 0 1 1 0 -0 -0 1 0
        Triangulations 0

        TShapes 6
        Ve
        1e-07
        -10 0 0
        0 0

        0101101
        *
        Ve
        1e-07
        10 0 0
        0 0

        0101101
        *
        Ed
         1e-07 1 1 0
        1  1 0 0 20
        2  1 1 0 0 20
        -10 0 10 0
        0

        0101000
        +6 0 -5 0 *
        Ed
         1e-07 1 1 0
        1  2 0 0 3.14159265358979
        2  2 1 0 0 3.14159265358979
        10 0 -10 0
        0

        0101000
        +5 0 -6 0 *
        Wi

        0101100
        +4 0 +3 0 *
        Fa
        0  1e-07 1 0

        0111000
        +2 1 *

        +1 0
        """
        let ents = try BREPImporter.entities(brep)
        XCTAssertEqual(ents.count, 1)
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        // Half disc of radius 10 lifted by the location to z = 5.
        XCTAssertTrue(s.meshVertices.allSatisfy { abs($0.z - 5) < 1e-9 })
        var area = 0.0
        for t in stride(from: 0, to: s.meshTriangles.count, by: 3) {
            let a = s.meshVertices[s.meshTriangles[t]], b = s.meshVertices[s.meshTriangles[t + 1]], c = s.meshVertices[s.meshTriangles[t + 2]]
            area += (b - a).cross(c - a).z / 2
        }
        XCTAssertEqual(area, .pi * 100 / 2, accuracy: 2.5, "half disc (chords)")
        XCTAssertGreaterThan(area, 0, "counter-clockwise about +Z")
        XCTAssertThrowsError(try BREPImporter.entities("solid x\nendsolid"))
    }

    func testBREPUsesStoredTriangulation() throws {
        let brep = """
        CASCADE Topology V1, (c) Matra-Datavision
        Locations 0
        Curve2ds 0
        Curves 0
        Polygon3D 0
        PolygonOnTriangulations 0
        Surfaces 1
        1 0 0 0 0 0 1 1 0 0 0 1 0
        Triangulations 1
        4 2 0 0
        0 0 0 4 0 0 4 3 0 0 3 0
        1 2 3 1 3 4

        TShapes 2
        Fa
        0  1e-07 1 0
        2  1

        0111000
        *
        Sh

        0101100
        +2 0 *

        +1 0
        """
        let ents = try BREPImporter.entities(brep)
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(s.meshTriangles, [0, 1, 2, 0, 2, 3])
        XCTAssertEqual(ents[0].props["name"], "Shell 1")
    }

    // MARK: E57

    func testE57WriteReadRoundTrip() throws {
        let a: [CloudPoint] = (0..<3000).map { (i: Int) -> CloudPoint in
            let x: Double = Double(i) * 0.01, y: Double = sin(Double(i)), level: Double = Double(i % 100) / 100
            return CloudPoint(Vec3(x, y, -1.5), color: (UInt8(i % 256), 20, 250), intensity: level)
        }
        let b = [CloudPoint(Vec3(1, 2, 3)), CloudPoint(Vec3(-4, 5.5, 6.25))]
        let data = E57.write([E57.Scan(name: "Scan <A>", points: a), E57.Scan(name: "Plain", points: b)])
        XCTAssertEqual(data.count % 1024, 0)
        XCTAssertEqual(String(decoding: data.prefix(8), as: UTF8.self), "ASTM-E57")
        XCTAssertTrue(E57.badPages(data).isEmpty)
        let scans = try E57.read(data)
        XCTAssertEqual(scans.map(\.name), ["Scan <A>", "Plain"])
        XCTAssertEqual(scans[0].points.count, 3000)
        for (p, q) in zip(scans[0].points, a) {
            XCTAssertEqual(p.p, q.p)
            XCTAssertEqual(p.color?.0, q.color?.0); XCTAssertEqual(p.color?.2, 250)
            XCTAssertEqual(p.intensity ?? -1, q.intensity ?? -2, accuracy: 1e-12)
        }
        XCTAssertEqual(scans[1].points.map(\.p), b.map(\.p))
        XCTAssertNil(scans[1].points[0].color)
        XCTAssertEqual(try E57.read(data, maxPoints: 10).flatMap(\.points).count, 10)
        // A damaged page is detected.
        var bad = data; bad[2000] ^= 0xFF
        XCTAssertEqual(E57.badPages(bad), [1])
        XCTAssertThrowsError(try E57.read(Data("not e57 at all, not at all, not at all, nothing".utf8)))
    }

    func testE57PoseAndScaledIntegers() throws {
        // Hand-built CompressedVector with ScaledInteger X/Y/Z (12 bits) and a pose rotating 90° about Z plus a translation.
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        let raw: [[Int]] = [[1000, 2000, 0], [3000, 0, 4095]]  // value = raw * 0.001 + (-1)
        var streams: [[UInt8]] = []
        for axis in 0..<3 {
            var bits: [Bool] = []
            for r in raw { for b in 0..<12 { bits.append((r[axis] >> b) & 1 == 1) } }
            var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
            for (i, bit) in bits.enumerated() where bit { bytes[i / 8] |= 1 << UInt8(i % 8) }
            streams.append(bytes)
        }
        var l = [UInt8](repeating: 0, count: 48)
        let sec = l.count
        l += [1, 0, 0, 0, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 24)
        let dataStart = l.count
        var packet: [UInt8] = [1, 0, 0, 0] + le16(3) + streams.flatMap { le16($0.count) } + streams.flatMap { $0 }
        while packet.count % 4 != 0 { packet.append(0) }
        packet[2] = UInt8((packet.count - 1) & 0xFF); packet[3] = UInt8((packet.count - 1) >> 8)
        l += packet
        func put64(_ v: Int, _ at: Int) { for k in 0..<8 { l[at + k] = UInt8((v >> (8 * k)) & 0xFF) } }
        put64(l.count - sec, sec + 8); put64(dataStart, sec + 16)
        let proto = ["X", "Y", "Z"].map { "<cartesian\($0) type=\"ScaledInteger\" minimum=\"0\" maximum=\"4095\" scale=\"0.001\" offset=\"-1\"/>" }.joined()
        let xml = "<?xml version=\"1.0\"?><e57Root type=\"Structure\" xmlns=\"http://www.astm.org/COMMIT/E57/2010-e57-v1.0\"><data3D type=\"Vector\"><vectorChild type=\"Structure\"><name type=\"String\">S</name><pose type=\"Structure\"><rotation type=\"Structure\"><w type=\"Float\">0.7071067811865476</w><x type=\"Float\">0</x><y type=\"Float\">0</y><z type=\"Float\">0.7071067811865476</z></rotation><translation type=\"Structure\"><x type=\"Float\">10</x><y type=\"Float\">0</y><z type=\"Float\">0</z></translation></pose><points type=\"CompressedVector\" fileOffset=\"\(sec)\" recordCount=\"2\"><prototype type=\"Structure\">\(proto)</prototype><codecs type=\"Vector\"/></points></vectorChild></data3D></e57Root>"
        let xmlStart = l.count
        l += Array(xml.utf8)
        for (k, c) in Array("ASTM-E57".utf8).enumerated() { l[k] = c }
        l[8] = 1
        put64(((l.count + 1019) / 1020) * 1024, 16); put64(E57.physicalOffset(xmlStart), 24); put64(xml.utf8.count, 32); put64(1024, 40)
        let scans = try E57.read(Data(E57.paged(l)))
        XCTAssertEqual(scans[0].points.count, 2)
        // First point: (0, 1, -1) rotated 90° about Z → (-1, 0, -1), + (10, 0, 0).
        let p = scans[0].points[0].p
        XCTAssertEqual(p.x, 9, accuracy: 1e-9); XCTAssertEqual(p.y, 0, accuracy: 1e-9); XCTAssertEqual(p.z, -1, accuracy: 1e-9)
        let q = scans[0].points[1].p   // (2, -1, 3.095) → (1, 2, 3.095) + 10
        XCTAssertEqual(q.x, 11, accuracy: 1e-9); XCTAssertEqual(q.y, 2, accuracy: 1e-9); XCTAssertEqual(q.z, 3.095, accuracy: 1e-9)
    }

    @MainActor func testE57Commands() async throws {
        let dir = try tmp(), url = dir.appendingPathComponent("pts.e57")
        let ed = Editor()
        await ed.run("POINT 1000,2000")
        await ed.run("POINT 3000,500")
        ed.doc.entities[0].props["z"] = "1500"
        ed.doc.entities[0].color = .rgb(255, 0, 0)
        await ed.run("E57OUT \"\(url.path)\"")
        let scans = try E57.read(Data(contentsOf: url))
        XCTAssertEqual(scans[0].points.count, 2)
        XCTAssertEqual(scans[0].points[0].p, Vec3(1, 2, 1.5))
        let ed2 = Editor()
        await ed2.run("E57IN \"\(url.path)\"")
        XCTAssertEqual(ed2.doc.entities.count, 2)
        guard case .point(let p) = ed2.doc.entities[0].geometry else { return XCTFail() }
        XCTAssertEqual(p.x, 1000, accuracy: 1e-6)
        XCTAssertEqual(Double(ed2.doc.entities[0].props["z"] ?? "") ?? 0, 1500, accuracy: 1e-6)
    }
}
