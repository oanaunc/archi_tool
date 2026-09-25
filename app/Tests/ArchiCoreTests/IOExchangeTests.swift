// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// IFC export of sloped slabs, ramps, footings and phases; DXF contours with elevation.
final class IOExchangeTests: XCTestCase {
    func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vec2] { [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)] }

    func testIFCSlopedSlabRoundTrip() throws {
        var d = ArchiDocument()
        let id = d.addElement(.slab(SlabGeom(boundary: rect(0, 0, 6000, 2000), thickness: 200, topOffset: 0, slope: 5, slopeDirection: 0, slopeOrigin: Vec2(0, 0))))
        let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        XCTAssertTrue(text.contains("PitchAngle"))
        XCTAssertTrue(text.contains("IFCSLAB("))
        let b = try IFCImporter.importFile(text).doc
        let el = try XCTUnwrap(b.elements.first { $0.props["ifcGuid"] == IFCExporter.guid("element:\(id)") })
        guard case .slab(let g) = el.geometry else { return XCTFail("not a slab") }
        XCTAssertEqual(g.slope, 5, accuracy: 1e-6)
        XCTAssertEqual(g.thickness, 200, accuracy: 1e-6)
        XCTAssertEqual(g.slopeDirection, 0, accuracy: 1e-9)
        // Same top surface: height at the far end = tan(5°)·6000.
        XCTAssertEqual(g.topHeight(at: Vec2(6000, 1000)), tan(5 * Double.pi / 180) * 6000, accuracy: 1e-3)
        XCTAssertEqual(g.topHeight(at: Vec2(0, 500)), 0, accuracy: 1e-3)
        XCTAssertEqual(abs(GeometryOps.signedArea(g.boundary)), 12_000_000, accuracy: 1)
    }

    func testIFCRampFootingCeilingAndPhases() throws {
        var d = ArchiDocument()
        let wall = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(8000, 0))))
        let f1 = d.addElement(.slab(SlabGeom(boundary: rect(0, 0, 4000, 1200), thickness: 200, topOffset: 0, slope: atan(1.0 / 12) * 180 / .pi, slopeDirection: 0, slopeOrigin: Vec2(0, 0))), name: "Ramp")
        let l1 = d.addElement(.slab(SlabGeom(boundary: rect(4000, 0, 5500, 1200), thickness: 200, topOffset: 4000.0 / 12)), name: "Ramp Landing")
        let foot = d.addElement(.slab(SlabGeom(boundary: rect(-300, -300, 8300, 300), thickness: 400, topOffset: -500)))
        let ceil = d.addElement(.slab(SlabGeom(boundary: rect(0, 0, 3000, 3000), thickness: 20, topOffset: 2700)))
        for (id, kind) in [(f1, "ramp"), (l1, "landing"), (foot, "foundation"), (ceil, "ceiling")] {
            let i = d.elementIndex(id)!
            d.elements[i].props["kind"] = kind
            if kind == "ramp" || kind == "landing" { d.elements[i].props["rampGroup"] = "\(f1)" }
            if kind == "foundation" { d.elements[i].props["host"] = "\(wall)" }
        }
        d.phases = ["Existing", "New Construction"]
        d.elements[d.elementIndex(wall)!].props["phaseCreated"] = "Existing"
        d.elements[d.elementIndex(wall)!].props["phaseDemolished"] = "New Construction"
        d.elements[d.elementIndex(f1)!].props["phaseCreated"] = "New Construction"
        let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        XCTAssertTrue(text.contains("IFCRAMP("), "ramp container")
        XCTAssertTrue(text.contains(".TWO_STRAIGHT_RUN_RAMP.") == false)
        XCTAssertTrue(text.contains(".STRAIGHT_RUN_RAMP."))
        XCTAssertTrue(text.contains("IFCRAMPFLIGHT("))
        XCTAssertTrue(text.contains(".LANDING."))
        XCTAssertTrue(text.contains("IFCFOOTING(") && text.contains(".STRIP_FOOTING."))
        XCTAssertTrue(text.contains("IFCCOVERING(") && text.contains(".CEILING."))
        XCTAssertTrue(text.contains("'HandicapAccessible',$,IFCBOOLEAN(.T.)"))
        XCTAssertTrue(text.contains("IFCLABEL('DEMOLISH')"), "demolished wall status")
        XCTAssertTrue(text.contains("IFCLABEL('NEW')"))
        XCTAssertTrue(text.contains("IFCGROUP(") && text.contains("'Phase: Existing'") && text.contains("'Demolished: New Construction'"))
        // Ramp parts are aggregated by the ramp, not contained in the storey twice.
        let lines = text.split(separator: "\n")
        let rampLine = try XCTUnwrap(lines.first { $0.contains("=IFCRAMP(") })
        let rampRef = String(rampLine.split(separator: "=")[0])
        XCTAssertTrue(lines.contains { $0.contains("IFCRELAGGREGATES(") && $0.contains(",\(rampRef),(") })
        // Round trip: kinds and references survive.
        let b = try IFCImporter.importFile(text).doc
        let kinds = Dictionary(grouping: b.elements.compactMap { $0.props["kind"] }, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(kinds["ramp"], 1); XCTAssertEqual(kinds["landing"], 1); XCTAssertEqual(kinds["foundation"], 1); XCTAssertEqual(kinds["ceiling"], 1)
        let bf = try XCTUnwrap(b.elements.first { $0.props["kind"] == "foundation" })
        let bw = try XCTUnwrap(b.elements.first { if case .wall = $0.geometry { return true }; return false })
        XCTAssertEqual(bf.props["host"], "\(bw.id)")
        let br = try XCTUnwrap(b.elements.first { $0.props["kind"] == "ramp" })
        XCTAssertEqual(b.elements.first { $0.props["kind"] == "landing" }?.props["rampGroup"], "\(br.id)")
        guard case .slab(let rg) = br.geometry else { return XCTFail() }
        XCTAssertEqual(rg.slope, atan(1.0 / 12) * 180 / .pi, accuracy: 1e-6)
        XCTAssertEqual(bw.props["phaseDemolished"], "New Construction")
    }

    func testDXFContourElevationRoundTrip() throws {
        var d = ArchiDocument()
        let c1 = d.add(Entity(layer: "C-TOPO", geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 200), Vec2(2000, 0)])), props: ["elevation": "1500"]))
        let c2 = d.add(Entity(layer: "C-TOPO", geometry: .polyline(PolylineGeom(points: rect(0, 0, 500, 500), closed: true)), props: ["elevation": "-250.5"]))
        _ = d.add(Entity(layer: "SURVEY", geometry: .point(Vec2(10, 20)), props: ["z": "123.25"]))
        _ = d.add(Entity(layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(1, 1)))))
        let text = DXFWriter.write(d)
        XCTAssertTrue(text.contains(" 38\n1500.0"))
        let b = try DXFReader.read(text)
        let polys = b.entities.filter { if case .polyline = $0.geometry { return true }; return false }
        XCTAssertEqual(Set(polys.compactMap { $0.props["elevation"] }), ["1500", "-250.5"])
        XCTAssertEqual(b.entities.first { if case .point = $0.geometry { return true }; return false }?.props["z"], "123.25")
        XCTAssertNil(b.entities.first { if case .line = $0.geometry { return true }; return false }?.props["elevation"])
        _ = (c1, c2)
        // R12: POLYLINE header elevation.
        let r12 = DXFWriter.write(d, version: .r12)
        let b12 = try DXFReader.read(r12)
        XCTAssertEqual(Set(b12.entities.compactMap { $0.props["elevation"] }), ["1500", "-250.5"])
    }

    func testDXF3DPolylineAndTopoContours() throws {
        // 3D polyline with a constant z becomes a contour; varying z keeps per-vertex z.
        let dxf = """
        0\nSECTION\n2\nENTITIES\n0\nPOLYLINE\n8\nC\n66\n1\n70\n8\n0\nVERTEX\n8\nC\n10\n0\n20\n0\n30\n5\n70\n32\n0\nVERTEX\n8\nC\n10\n10\n20\n0\n30\n5\n70\n32\n0\nSEQEND\n0\nPOLYLINE\n8\nC\n66\n1\n70\n8\n0\nVERTEX\n8\nC\n10\n0\n20\n0\n30\n1\n70\n32\n0\nVERTEX\n8\nC\n10\n10\n20\n0\n30\n2\n70\n32\n0\nSEQEND\n0\nENDSEC\n0\nEOF\n
        """
        let d = try DXFReader.read(dxf)
        XCTAssertEqual(d.entities.count, 2)
        XCTAssertEqual(d.entities[0].props["elevation"], "5")
        XCTAssertEqual(d.entities[1].props["vertexZ"], "1,2")
        // Toposurface exports its contours at their elevations.
        var t = ArchiDocument()
        let pts = [Vec3(0, 0, 0), Vec3(10000, 0, 0), Vec3(10000, 10000, 3000), Vec3(0, 10000, 3000), Vec3(5000, 5000, 1500)]
        let s = try XCTUnwrap(Terrain.solid(pts))
        _ = t.add(Entity(layer: "C-TOPO", geometry: .solid(s), props: ["topo": "1", "contourInterval": "1000"]))
        let back = try DXFReader.read(DXFWriter.write(t))
        let zs = Set(back.entities.compactMap { $0.props["elevation"] })
        XCTAssertEqual(zs, ["1000", "2000"])
    }
}
