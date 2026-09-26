// Oanarina Archi Tool — GPL-3.0-or-later
// Rhino 3DM import/export (IO-044): round trips through the writer and reader, CRC conformance with Rhino's own files,
// and import of Rhino-written files (versions 3–7) from the reference checkouts, comparing the tessellation of trimmed
// B-rep faces with Rhino's cached render meshes. A report goes to build/interop/rhino3dm.txt.
import XCTest
@testable import ArchiCore

final class IORhino3DMTests: XCTestCase {
    static var root: URL { IOInteropCorpusTests.repoRoot }
    static var samples: [URL] {
        let brl = root.appendingPathComponent("other_projects/brlcad")
        return ["db/nist/NIST_MBE_PMI_7-10.3dm", "regress/gcv/rhino/idef_test.3dm", "src/libbrep/tests/ayam_hyperbolid.3dm"].map { brl.appendingPathComponent($0) }
            + [root.deletingLastPathComponent().appendingPathComponent("oanarina_website/wle/model/9.WLE.3dm")]
    }
    static var report: [String] = []

    override class func tearDown() {
        let dir = root.appendingPathComponent("build/interop")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? report.joined(separator: "\n").write(to: dir.appendingPathComponent("rhino3dm.txt"), atomically: true, encoding: .utf8)
        super.tearDown()
    }

    static func sampleDocument() -> ArchiDocument {
        var d = ArchiDocument()
        d.units = .meters
        d.layers.append(Layer(name: "A-CURVES", color: RGBA(1, 0, 0)))
        var hidden = Layer(name: "HIDDEN", color: RGBA(0, 0, 1)); hidden.visible = false
        d.layers.append(hidden)
        d.add(Entity(layer: "A-CURVES", geometry: .line(LineGeom(Vec2(0, 0), Vec2(3, 4))), props: ["elevation": "2.5"]))
        d.add(Entity(layer: "A-CURVES", color: .rgb(10, 200, 30), geometry: .circle(CircleGeom(Vec2(10, 0), 2))))
        d.add(Entity(layer: "A-CURVES", geometry: .arc(ArcGeom(Vec2(0, 10), 3, 0.25, 2.0))))
        d.add(Entity(layer: "A-CURVES", geometry: .polyline(PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(4, 0), bulge: 1), PolyVertex(Vec2(4, 4))], closed: false))))
        d.add(Entity(layer: "A-CURVES", geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: true)), props: ["vertexZ": "0,1,2"]))
        d.add(Entity(layer: "HIDDEN", geometry: .spline(SplineGeom(degree: 3, controlPoints: [Vec2(0, 0), Vec2(1, 2), Vec2(3, 2), Vec2(4, 0)],
                                                                   knots: [0, 0, 0, 0, 1, 1, 1, 1]))))
        d.add(Entity(layer: "0", geometry: .solid(SolidGeom(kind: .box, origin: Vec3(1, 2, 0), size: Vec3(3, 1, 0.5)))))
        d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4, 0), thickness: 0.2, height: 2.8)), material: "Brick")
        return d
    }

    func testExportWritesRhinoLayoutAndReadsBack() throws {
        let d = Self.sampleDocument()
        let (data, rep) = Rhino3DM.exportWithReport(d)
        XCTAssertTrue(data.starts(with: Array("3D Geometry File Format        4".utf8)))
        XCTAssertEqual(rep.curves, 6)
        XCTAssertGreaterThanOrEqual(rep.meshes, 2)
        // Every CRC chunk carries the CRC openNURBS computes.
        let crc = try Rhino3DMParser.checkCRC(data)
        XCTAssertEqual(crc.failures, [])
        XCTAssertGreaterThan(crc.leaves, 10)
        // End-of-file chunk holds the file length.
        let b = [UInt8](data)
        let n = b.count
        XCTAssertEqual(Int(b[n - 4]) | Int(b[n - 3]) << 8 | Int(b[n - 2]) << 16 | Int(b[n - 1]) << 24, n)
        let dir = Self.root.appendingPathComponent("build/interop")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("rhino-export.3dm"))

        let m = try Rhino3DMParser.read(data)
        XCTAssertEqual(m.version, 4)
        XCTAssertEqual(m.unitSystem, 4)
        XCTAssertEqual(m.unitMM, 1000)
        XCTAssertEqual(m.layers.map(\.name), d.layers.map(\.name))
        XCTAssertEqual(m.layers.first { $0.name == "A-CURVES" }?.color.0, 255)
        XCTAssertEqual(m.layers.first { $0.name == "HIDDEN" }?.visible, false)
        XCTAssertEqual(m.objects.count, rep.curves + rep.meshes)

        // Import into a millimetre drawing: scale by 1000, geometry exact.
        var mm = ArchiDocument(); mm.units = .millimeters
        let (imp, summary) = try Rhino3DM.document(data, reference: mm)
        Self.report.append("export round trip: \(summary)")
        let ents = imp.entities
        let line = try XCTUnwrap(ents.compactMap { e -> (LineGeom, String?)? in if case .line(let l) = e.geometry { return (l, e.props["elevation"]) }; return nil }.first)
        XCTAssertEqual(line.0.b.x, 3000, accuracy: 1e-6); XCTAssertEqual(line.0.b.y, 4000, accuracy: 1e-6)
        XCTAssertEqual(Double(line.1 ?? "") ?? 0, 2500, accuracy: 1e-6)
        let circle = try XCTUnwrap(ents.first { if case .circle = $0.geometry { return true }; return false })
        if case .circle(let c) = circle.geometry { XCTAssertEqual(c.radius, 2000, accuracy: 1e-6); XCTAssertEqual(c.center.x, 10000, accuracy: 1e-6) }
        XCTAssertEqual(circle.color, .rgb(10, 200, 30))
        let arc = try XCTUnwrap(ents.compactMap { e -> ArcGeom? in if case .arc(let a) = e.geometry { return a }; return nil }.first { abs($0.radius - 3000) < 1e-6 })
        XCTAssertEqual(arc.start, 0.25, accuracy: 1e-9); XCTAssertEqual(arc.end, 2.0, accuracy: 1e-9)
        // The bulged polyline came back as a poly curve (line + half circle), sampled.
        let spline = try XCTUnwrap(ents.compactMap { e -> SplineGeom? in if case .spline(let s) = e.geometry { return s }; return nil }.first)
        XCTAssertEqual(spline.degree, 3); XCTAssertEqual(spline.knots, [0, 0, 0, 0, 1, 1, 1, 1])
        XCTAssertEqual(spline.controlPoints[1].y, 2000, accuracy: 1e-6)
        let z3 = try XCTUnwrap(ents.first { $0.props["vertexZ"] != nil })
        XCTAssertEqual(z3.props["vertexZ"], "0,1000,2000")
        if case .polyline(let p) = z3.geometry { XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 3) }
        let bulged = ents.filter { e in if case .polyline(let p) = e.geometry { return e.props["vertexZ"] == nil && p.vertices.count > 5 }; return false }
        XCTAssertEqual(bulged.count, 1)
        if case .polyline(let p) = bulged[0].geometry {
            // Half circle of radius 2 m about (4, 2): the rightmost point is at x = 6 m.
            XCTAssertEqual(p.vertices.map(\.p.x).max() ?? 0, 6000, accuracy: 1)
        }
        // Meshes: the box and the wall, in millimetres, coloured by material.
        var box = BBox3.empty
        for e in ents { if case .solid(let s) = e.geometry { s.meshVertices.forEach { box.add($0) } } }
        XCTAssertEqual(box.max.z, 2800, accuracy: 1e-3)
        XCTAssertEqual(box.max.x, 4000, accuracy: 1e-3)
        let brick = d.material("Brick")!.color
        let wall = ents.first { $0.props["name"]?.contains("Brick") == true }
        XCTAssertNotNil(wall)
        if case .rgb(let r, _, _)? = wall?.color { XCTAssertEqual(Double(r), (brick.r * 255).rounded(), accuracy: 1) } else { XCTFail("wall colour") }
        XCTAssertEqual(imp.layer(named: "HIDDEN")?.visible, false)

        // Through the file dispatch.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).3dm")
        XCTAssertTrue(try FileImport.export(d, to: url, format: "3dm"))
        XCTAssertEqual(try FileImport.load(url).0.entities.count, ents.count)
        XCTAssertTrue(FileImport.importFormats.contains("3dm") && FileImport.exportFormats.contains("3dm"))
    }

    func testRhinoFilesCRCMatchesWriterRules() throws {
        let files = Self.samples.filter { FileManager.default.fileExists(atPath: $0.path) }
        try XCTSkipIf(files.isEmpty, "reference 3DM files not present")
        for f in files {
            let r = try Rhino3DMParser.checkCRC(try Data(contentsOf: f))
            Self.report.append("crc \(f.lastPathComponent): leaves \(r.leaves), containers \(r.containers), mixed \(r.mixed), failures \(r.failures)")
            XCTAssertEqual(r.failures, [], f.lastPathComponent)
            XCTAssertGreaterThan(r.leaves, 5)
        }
    }

    static func area(_ v: [Vec3], _ t: [Int]) -> Double {
        var a = 0.0, i = 0
        while i + 2 < t.count { a += (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]]).length / 2; i += 3 }
        return a
    }

    func testImportsRhinoFilesAndTessellatesTrimmedFaces() throws {
        let files = Self.samples.filter { FileManager.default.fileExists(atPath: $0.path) }
        try XCTSkipIf(files.isEmpty, "reference 3DM files not present")
        for f in files {
            let data = try Data(contentsOf: f)
            let m = try Rhino3DMParser.read(data)
            let withMeshes = try Rhino3DM.read(data, unitMM: m.unitMM)
            let tess = try Rhino3DM.read(data, unitMM: m.unitMM, options: Rhino3DM.ImportOptions(useRenderMeshes: false))
            func stats(_ r: Rhino3DM.ImportResult) -> (BBox3, Double, Int) {
                var b = BBox3.empty, a = 0.0, n = 0
                for e in r.entities { if case .solid(let s) = e.geometry { s.meshVertices.forEach { b.add($0) }; a += Self.area(s.meshVertices, s.meshTriangles); n += s.meshTriangles.count / 3 } }
                return (b, a, n)
            }
            let (b1, a1, n1) = stats(withMeshes), (b2, a2, n2) = stats(tess)
            Self.report.append("\(f.lastPathComponent): v\(m.version) units \(m.unitSystem) layers \(m.layers.map(\.name)) objects \(m.objects.count) idefs \(m.idefs.map { "\($0.name):\($0.members.count)" })")
            Self.report.append("  render: \(withMeshes.summary); bbox \(b1.min) … \(b1.max); area \(fmt(a1, 4)); triangles \(n1)")
            Self.report.append("  tessellated: \(tess.summary); bbox \(b2.min) … \(b2.max); area \(fmt(a2, 4)); triangles \(n2)")
            XCTAssertFalse(withMeshes.entities.isEmpty, f.lastPathComponent)
            XCTAssertFalse(b2.isEmpty, f.lastPathComponent)
            // The tessellation of the trimmed faces matches Rhino's render meshes.
            let size = max(b1.size.x, b1.size.y, b1.size.z)
            for (p, q) in [(b1.min, b2.min), (b1.max, b2.max)] {
                XCTAssertEqual(p.x, q.x, accuracy: size * 0.01, f.lastPathComponent)
                XCTAssertEqual(p.y, q.y, accuracy: size * 0.01, f.lastPathComponent)
                XCTAssertEqual(p.z, q.z, accuracy: size * 0.01, f.lastPathComponent)
            }
            XCTAssertEqual(a2, a1, accuracy: a1 * 0.01, f.lastPathComponent)
        }
    }

    /// Worst per-face differences between the tessellation and Rhino's render meshes (report only).
    func testFaceDiagnostics() throws {
        let files = Self.samples.filter { FileManager.default.fileExists(atPath: $0.path) }
        try XCTSkipIf(files.isEmpty, "reference 3DM files not present")
        for f in files {
            let m = try Rhino3DMParser.read(try Data(contentsOf: f))
            var rows: [(Double, String)] = []
            for o in m.objects {
                guard case .brep(let b) = o.geometry else { continue }
                for (fi, face) in b.faces.enumerated() {
                    guard fi < b.renderMeshes.count, let rm = b.renderMeshes[fi] else { continue }
                    let ra = Self.area(rm.vertices, rm.triangles)
                    let t = R3Tessellator.face(b, face)
                    let ta = t.map { Self.area($0.vertices, $0.triangles) } ?? 0
                    let kind: String = {
                        guard face.surface >= 0, face.surface < b.surfaces.count, let s = b.surfaces[face.surface] else { return "nil" }
                        switch s { case .nurbs(let n): return "nurbs\(n.points.count)x\(n.points[0].count)"; case .plane: return "plane"; case .rev: return "rev"; case .sum: return "sum" }
                    }()
                    let loops = face.loops.map { li in li < b.loops.count ? "\(b.loops[li].type):" + b.loops[li].trims.map { $0 < b.trims.count ? "\(b.trims[$0].type)" : "?" }.joined() : "?" }
                    rows.append((abs(ta - ra), "face \(fi) \(kind) rev \(face.reversed) render \(fmt(ra, 4)) tess \(fmt(ta, 4)) loops \(loops)"))
                }
            }
            rows.sort { $0.0 > $1.0 }
            Self.report.append("faces \(f.lastPathComponent): worst")
            for r in rows.prefix(5) { Self.report.append("  " + r.1) }
        }
    }

    func testReferenceFileDetails() throws {
        let brl = Self.root.appendingPathComponent("other_projects/brlcad")
        let nist = brl.appendingPathComponent("db/nist/NIST_MBE_PMI_7-10.3dm"), idef = brl.appendingPathComponent("regress/gcv/rhino/idef_test.3dm")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: nist.path), "reference 3DM files not present")
        let n = try Rhino3DMParser.read(Data(contentsOf: nist))
        XCTAssertEqual(n.version, 4)
        XCTAssertEqual(n.unitMM, 25.4)                               // inches
        XCTAssertEqual(n.objects.count, 4)
        XCTAssertTrue(n.objects.allSatisfy { if case .brep(let b) = $0.geometry { return b.faces.count > 0 && b.renderMeshes.count == b.faces.count }; return false })
        // Into a millimetre drawing: inches scaled by 25.4.
        let (doc, _) = try Rhino3DM.document(Data(contentsOf: nist))
        var inch = ArchiDocument(); inch.units = .inches
        let (docIn, _) = try Rhino3DM.document(Data(contentsOf: nist), reference: inch)
        var b = BBox3.empty, bi = BBox3.empty
        for e in doc.entities { if case .solid(let s) = e.geometry { s.meshVertices.forEach { b.add($0) } } }
        for e in docIn.entities { if case .solid(let s) = e.geometry { s.meshVertices.forEach { bi.add($0) } } }
        XCTAssertEqual(b.max.x, bi.max.x * 25.4, accuracy: 1e-6)
        XCTAssertEqual(bi.max.x, 6.134, accuracy: 0.001)

        let i = try Rhino3DMParser.read(Data(contentsOf: idef))
        XCTAssertEqual(i.version, 70)
        XCTAssertEqual(i.layers.map(\.name), ["Default", "Layer 01", "Layer 02"])
        XCTAssertEqual(i.idefs.count, 3)
        XCTAssertEqual(i.idefs.map(\.name).sorted(), ["box_block", "nested_block", "two_nest"])
        XCTAssertTrue(i.idefs.allSatisfy { !$0.members.isEmpty })
        let r = try Rhino3DM.read(Data(contentsOf: idef))
        XCTAssertGreaterThan(r.entities.count, 0)
        Self.report.append("idef_test: \(r.summary); entities by layer \(Dictionary(grouping: r.entities, by: \.layer).mapValues(\.count))")
    }
}
