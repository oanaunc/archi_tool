// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// STEP import of curved B-reps, tessellated AP242 geometry and assemblies (IO-040).
final class IOSTEPBRepTests: XCTestCase {
    func mesh(_ e: Entity) -> SolidGeom? { if case .solid(let s) = e.geometry { return s }; return nil }
    func volume(_ s: SolidGeom) -> Double {
        var v = 0.0, i = 0
        let p = s.meshVertices, t = s.meshTriangles
        while i + 2 < t.count { v += p[t[i]].dot(p[t[i + 1]].cross(p[t[i + 2]])) / 6; i += 3 }
        return v
    }
    /// Number of edges not shared by exactly two triangles in opposite directions.
    func openEdges(_ s: SolidGeom) -> Int {
        var count: [String: Int] = [:]
        let t = s.meshTriangles
        var i = 0
        while i + 2 < t.count {
            for k in 0..<3 { let a = t[i + k], b = t[i + (k + 1) % 3]; count["\(a),\(b)", default: 0] += 1 }
            i += 3
        }
        return count.keys.filter { key in
            let ab = key.split(separator: ","); return count["\(ab[1]),\(ab[0])"] != 1 || count[key] != 1
        }.count
    }
    let head = "ISO-10303-21;HEADER;FILE_SCHEMA(('AUTOMOTIVE_DESIGN'));ENDSEC;DATA;\n#1=(LENGTH_UNIT()NAMED_UNIT(*)SI_UNIT(.MILLI.,.METRE.));\n"
    let tail = "\nENDSEC;END-ISO-10303-21;"

    func testClosedCylinderWithSeam() throws {
        let body = """
        #2=CARTESIAN_POINT('',(0.,0.,0.));#3=CARTESIAN_POINT('',(0.,0.,20.));#4=CARTESIAN_POINT('',(10.,0.,0.));#5=CARTESIAN_POINT('',(10.,0.,20.));
        #6=DIRECTION('',(0.,0.,1.));#7=DIRECTION('',(1.,0.,0.));#8=DIRECTION('',(0.,0.,-1.));
        #10=AXIS2_PLACEMENT_3D('',#2,#6,#7);#11=AXIS2_PLACEMENT_3D('',#3,#6,#7);#12=AXIS2_PLACEMENT_3D('',#2,#8,#7);
        #20=CIRCLE('',#10,10.);#21=CIRCLE('',#11,10.);#22=LINE('',#4,#23);#23=VECTOR('',#6,1.);
        #30=VERTEX_POINT('',#4);#31=VERTEX_POINT('',#5);
        #40=EDGE_CURVE('',#30,#30,#20,.T.);#41=EDGE_CURVE('',#31,#31,#21,.T.);#42=EDGE_CURVE('',#30,#31,#22,.T.);
        #50=ORIENTED_EDGE('',*,*,#40,.F.);#51=EDGE_LOOP('',(#50));#52=FACE_OUTER_BOUND('',#51,.T.);#53=PLANE('',#12);#54=ADVANCED_FACE('',(#52),#53,.T.);
        #60=ORIENTED_EDGE('',*,*,#41,.T.);#61=EDGE_LOOP('',(#60));#62=FACE_OUTER_BOUND('',#61,.T.);#63=PLANE('',#11);#64=ADVANCED_FACE('',(#62),#63,.T.);
        #70=ORIENTED_EDGE('',*,*,#40,.T.);#71=ORIENTED_EDGE('',*,*,#42,.T.);#72=ORIENTED_EDGE('',*,*,#41,.F.);#73=ORIENTED_EDGE('',*,*,#42,.F.);
        #74=EDGE_LOOP('',(#70,#71,#72,#73));#75=FACE_OUTER_BOUND('',#74,.T.);#76=CYLINDRICAL_SURFACE('',#10,10.);#77=ADVANCED_FACE('',(#75),#76,.T.);
        #80=CLOSED_SHELL('',(#54,#64,#77));#81=MANIFOLD_SOLID_BREP('Rod',#80);
        """
        let ents = try STEPImporter.entities(head + body + tail)
        XCTAssertEqual(ents.count, 1)
        let s = try XCTUnwrap(mesh(ents[0]))
        XCTAssertEqual(ents[0].props["name"], "Rod")
        XCTAssertEqual(volume(s), .pi * 100 * 20, accuracy: .pi * 100 * 20 * 0.01, "outward, closed")
        XCTAssertEqual(openEdges(s), 0, "watertight after welding")
        for v in s.meshVertices { XCTAssertLessThanOrEqual((v.x * v.x + v.y * v.y).squareRoot(), 10 + 1e-6) }
        // Metres → millimetres.
        let m = try STEPImporter.entities((head + body + tail).replacingOccurrences(of: "SI_UNIT(.MILLI.,.METRE.)", with: "SI_UNIT($,.METRE.)"))
        XCTAssertEqual(volume(try XCTUnwrap(mesh(m[0]))), .pi * 100 * 20 * 1e9, accuracy: .pi * 100 * 20 * 1e9 * 0.01)
    }

    func testWholeSphereAroundItsSeam() throws {
        let body = """
        #2=CARTESIAN_POINT('',(0.,0.,0.));#3=CARTESIAN_POINT('',(0.,0.,10.));#4=CARTESIAN_POINT('',(0.,0.,-10.));
        #6=DIRECTION('',(0.,0.,1.));#7=DIRECTION('',(1.,0.,0.));#8=DIRECTION('',(0.,-1.,0.));
        #10=AXIS2_PLACEMENT_3D('',#2,#6,#7);#11=AXIS2_PLACEMENT_3D('',#2,#8,#7);
        #20=CIRCLE('',#11,10.);#30=VERTEX_POINT('',#3);#31=VERTEX_POINT('',#4);
        #40=EDGE_CURVE('',#31,#30,#20,.T.);
        #50=ORIENTED_EDGE('',*,*,#40,.T.);#51=ORIENTED_EDGE('',*,*,#40,.F.);#52=EDGE_LOOP('',(#50,#51));#53=FACE_OUTER_BOUND('',#52,.T.);
        #54=SPHERICAL_SURFACE('',#10,10.);#55=ADVANCED_FACE('',(#53),#54,.T.);#56=CLOSED_SHELL('',(#55));#57=MANIFOLD_SOLID_BREP('Ball',#56);
        """
        let ents = try STEPImporter.entities(head + body + tail)
        let s = try XCTUnwrap(ents.first.flatMap(mesh))
        let exact = 4.0 / 3 * .pi * 1000
        XCTAssertEqual(volume(s), exact, accuracy: exact * 0.03)
        for v in s.meshVertices { XCTAssertEqual(v.length, 10, accuracy: 1e-6) }
        XCTAssertGreaterThan(s.meshTriangles.count / 3, 100)
    }

    func testTorusBandAndConeCap() throws {
        // A full torus face bounded by its two seams, and a cone from a circle to its apex (vertex loop).
        let body = """
        #2=CARTESIAN_POINT('',(0.,0.,0.));#3=CARTESIAN_POINT('',(40.,0.,0.));#6=DIRECTION('',(0.,0.,1.));#7=DIRECTION('',(1.,0.,0.));#8=DIRECTION('',(0.,-1.,0.));
        #10=AXIS2_PLACEMENT_3D('',#2,#6,#7);#11=AXIS2_PLACEMENT_3D('',#9,#8,#7);#9=CARTESIAN_POINT('',(30.,0.,0.));
        #20=CIRCLE('',#10,40.);#21=CIRCLE('',#11,10.);#30=VERTEX_POINT('',#3);
        #40=EDGE_CURVE('',#30,#30,#20,.T.);#41=EDGE_CURVE('',#30,#30,#21,.T.);
        #50=ORIENTED_EDGE('',*,*,#40,.T.);#51=ORIENTED_EDGE('',*,*,#41,.T.);#52=ORIENTED_EDGE('',*,*,#40,.F.);#53=ORIENTED_EDGE('',*,*,#41,.F.);
        #54=EDGE_LOOP('',(#50,#51,#52,#53));#55=FACE_OUTER_BOUND('',#54,.T.);#56=TOROIDAL_SURFACE('',#10,30.,10.);#57=ADVANCED_FACE('',(#55),#56,.T.);
        #58=CLOSED_SHELL('',(#57));#59=MANIFOLD_SOLID_BREP('Ring',#58);
        #100=CARTESIAN_POINT('',(100.,0.,0.));#101=CARTESIAN_POINT('',(110.,0.,0.));#102=CARTESIAN_POINT('',(100.,0.,20.));
        #103=AXIS2_PLACEMENT_3D('',#100,#6,#7);#104=CIRCLE('',#103,10.);#105=VERTEX_POINT('',#101);#106=VERTEX_POINT('',#102);
        #107=EDGE_CURVE('',#105,#105,#104,.T.);#108=ORIENTED_EDGE('',*,*,#107,.T.);#109=EDGE_LOOP('',(#108));#110=FACE_OUTER_BOUND('',#109,.T.);
        #111=VERTEX_LOOP('',#106);#112=FACE_BOUND('',#111,.T.);#113=CONICAL_SURFACE('',#103,10.,-0.463647609);
        #114=ADVANCED_FACE('',(#110,#112),#113,.T.);#115=OPEN_SHELL('',(#114));
        """
        let ents = try STEPImporter.entities(head + body + tail)
        XCTAssertEqual(ents.count, 2)
        let ring = try XCTUnwrap(ents.first { $0.props["name"] == "Ring" }.flatMap(mesh))
        let exact = 2 * Double.pi * Double.pi * 30 * 100
        XCTAssertEqual(volume(ring), exact, accuracy: exact * 0.03)
        for v in ring.meshVertices {
            let rho = (v.x * v.x + v.y * v.y).squareRoot()
            XCTAssertEqual(((rho - 30) * (rho - 30) + v.z * v.z).squareRoot(), 10, accuracy: 1e-6)
        }
        let cone = try XCTUnwrap(ents.first { $0.props["name"] != "Ring" }.flatMap(mesh))
        // Lateral area π r s with s = √(10² + 20²).
        var area = 0.0, i = 0
        let p = cone.meshVertices, t = cone.meshTriangles
        while i + 2 < t.count { area += (p[t[i + 1]] - p[t[i]]).cross(p[t[i + 2]] - p[t[i]]).length / 2; i += 3 }
        XCTAssertEqual(area, .pi * 10 * (500.0).squareRoot(), accuracy: 12)
        XCTAssertTrue(p.contains { ($0 - Vec3(100, 0, 20)).length < 1e-6 }, "reaches the apex")
    }

    func testBSplineSurfaceAndRationalCircle() throws {
        // Rational quadratic quarter circle: every point at radius 5.
        let w = 0.5.squareRoot()
        let c = StepBSplineCurve(degree: 2, points: [Vec3(5, 0, 0), Vec3(5, 5, 0), Vec3(0, 5, 0)], weights: [1, w, 1], knots: [0, 0, 0, 1, 1, 1])
        for i in 0...10 { XCTAssertEqual(c.eval(Double(i) / 10).length, 5, accuracy: 1e-9) }
        // Curved B-spline patch (degree 2 × 1) bounded by B-spline and line edges.
        let body = """
        #2=CARTESIAN_POINT('',(0.,0.,0.));#3=CARTESIAN_POINT('',(10.,0.,10.));#4=CARTESIAN_POINT('',(20.,0.,0.));
        #5=CARTESIAN_POINT('',(0.,30.,0.));#6=CARTESIAN_POINT('',(10.,30.,10.));#7=CARTESIAN_POINT('',(20.,30.,0.));
        #10=B_SPLINE_SURFACE_WITH_KNOTS('',2,1,((#2,#5),(#3,#6),(#4,#7)),.UNSPECIFIED.,.F.,.F.,.F.,(3,3),(2,2),(0.,1.),(0.,1.),.UNSPECIFIED.);
        #20=B_SPLINE_CURVE_WITH_KNOTS('',2,(#2,#3,#4),.UNSPECIFIED.,.F.,.F.,(3,3),(0.,1.),.UNSPECIFIED.);
        #21=B_SPLINE_CURVE_WITH_KNOTS('',2,(#5,#6,#7),.UNSPECIFIED.,.F.,.F.,(3,3),(0.,1.),.UNSPECIFIED.);
        #22=LINE('',#2,#24);#23=LINE('',#4,#24);#24=VECTOR('',#25,1.);#25=DIRECTION('',(0.,1.,0.));
        #30=VERTEX_POINT('',#2);#31=VERTEX_POINT('',#4);#32=VERTEX_POINT('',#7);#33=VERTEX_POINT('',#5);
        #40=EDGE_CURVE('',#30,#31,#20,.T.);#41=EDGE_CURVE('',#31,#32,#23,.T.);#42=EDGE_CURVE('',#33,#32,#21,.T.);#43=EDGE_CURVE('',#30,#33,#22,.T.);
        #50=ORIENTED_EDGE('',*,*,#40,.T.);#51=ORIENTED_EDGE('',*,*,#41,.T.);#52=ORIENTED_EDGE('',*,*,#42,.F.);#53=ORIENTED_EDGE('',*,*,#43,.F.);
        #54=EDGE_LOOP('',(#50,#51,#52,#53));#55=FACE_OUTER_BOUND('',#54,.T.);#56=ADVANCED_FACE('',(#55),#10,.T.);#57=OPEN_SHELL('',(#56));
        """
        let ents = try STEPImporter.entities(head + body + tail)
        let s = try XCTUnwrap(ents.first.flatMap(mesh))
        // The arch peaks at z = 5 (quadratic Bézier with middle control point at 10).
        XCTAssertEqual(s.meshVertices.map(\.z).max() ?? 0, 5, accuracy: 0.05)
        var area = 0.0, i = 0
        let p = s.meshVertices, t = s.meshTriangles
        while i + 2 < t.count { area += (p[t[i + 1]] - p[t[i]]).cross(p[t[i + 2]] - p[t[i]]).length / 2; i += 3 }
        // Arc length of the parabola z = x(20 − x)/20 over 0…20 is ≈ 22.956; area = 30 × that.
        XCTAssertEqual(area, 30 * 22.956, accuracy: 30 * 22.956 * 0.01)
        // Upward-facing normals (surface normal ∂u × ∂v points to +z at the crest: (1,0,·) × (0,1,0)).
        var up = 0
        i = 0
        while i + 2 < t.count { if (p[t[i + 1]] - p[t[i]]).cross(p[t[i + 2]] - p[t[i]]).z > 0 { up += 1 }; i += 3 }
        XCTAssertEqual(up, t.count / 3)
    }

    func testTessellatedAP242AndMappedAssembly() throws {
        let tess = """
        #2=COORDINATES_LIST('',4,((0.,0.,0.),(10.,0.,0.),(0.,10.,0.),(0.,0.,10.)));
        #3=TRIANGULATED_FACE('',#2,4,(),$,(),((1,3,2),(1,2,4),(1,4,3),(2,3,4)));
        #4=TESSELLATED_SOLID('tetra',(#3),$);
        #5=COORDINATES_LIST('',4,((20.,0.,0.),(30.,0.,0.),(20.,10.,0.),(30.,10.,0.)));
        #6=COMPLEX_TRIANGULATED_SURFACE_SET('strip',#5,4,((0.,0.,1.)),(1,2,3,4),((1,2,3,4)),());
        #7=COORDINATES_LIST('',4,((0.,20.,0.),(10.,20.,0.),(0.,30.,0.),(10.,30.,0.)));
        #8=COMPLEX_TRIANGULATED_FACE('fan',#7,4,((0.,0.,1.)),$,(),(),((1,2,4,3)));
        #9=TESSELLATED_SHELL('shell',(#8),$);
        #10=COLOUR_RGB('',0.9,0.35,0.1);#11=FILL_AREA_STYLE_COLOUR('',#10);#12=FILL_AREA_STYLE('',(#11));#13=SURFACE_STYLE_FILL_AREA(#12);
        #14=SURFACE_SIDE_STYLE('',(#13));#15=SURFACE_STYLE_USAGE(.BOTH.,#14);#16=PRESENTATION_STYLE_ASSIGNMENT((#15));#17=STYLED_ITEM('',(#16),#4);
        """
        let ents = try STEPImporter.entities(head + tess + tail)
        XCTAssertEqual(ents.count, 3)
        let tet = try XCTUnwrap(ents.first { $0.props["name"] == "tetra" })
        XCTAssertEqual(volume(try XCTUnwrap(mesh(tet))), 1000.0 / 6, accuracy: 1e-6)
        XCTAssertEqual(tet.color, .rgb(230, 89, 26))
        XCTAssertEqual(ents.first { $0.props["name"] == "strip" }.flatMap(mesh)?.meshTriangles.count, 6)
        XCTAssertEqual(ents.first { $0.props["name"] == "shell" }.flatMap(mesh)?.meshTriangles.count, 6)

        let asm = """
        #13=PRODUCT_DEFINITION('design','',#12,#14);#22=PRODUCT_DEFINITION('design','',#21,#14);
        #25=NEXT_ASSEMBLY_USAGE_OCCURRENCE('near','','',#13,#22,'N');
        #30=SHAPE_REPRESENTATION('pair',(#31,#32),#40);
        #31=MAPPED_ITEM('near',#50,#60);#32=MAPPED_ITEM('far',#50,#61);
        #50=REPRESENTATION_MAP(#51,#70);
        #51=AXIS2_PLACEMENT_3D('',#52,#53,#54);#52=CARTESIAN_POINT('',(0.,0.,0.));#53=DIRECTION('',(0.,0.,1.));#54=DIRECTION('',(1.,0.,0.));#55=DIRECTION('',(0.,1.,0.));
        #60=AXIS2_PLACEMENT_3D('',#62,#53,#54);#61=AXIS2_PLACEMENT_3D('',#63,#53,#55);
        #62=CARTESIAN_POINT('',(0.,0.,0.));#63=CARTESIAN_POINT('',(0.,32.,5.));
        #70=FACETED_BREP_SHAPE_REPRESENTATION('wedge',(#71,#51),#40);
        #71=FACETED_BREP('wedge',#72);#72=CLOSED_SHELL('',(#73,#74,#75,#76));
        #73=FACE_SURFACE('',(#80),#100,.T.);#74=FACE_SURFACE('',(#81),#100,.T.);#75=FACE_SURFACE('',(#82),#100,.T.);#76=FACE_SURFACE('',(#83),#100,.T.);
        #80=FACE_OUTER_BOUND('',#90,.T.);#81=FACE_OUTER_BOUND('',#91,.T.);#82=FACE_OUTER_BOUND('',#92,.T.);#83=FACE_OUTER_BOUND('',#93,.T.);
        #90=POLY_LOOP('',(#110,#112,#111));#91=POLY_LOOP('',(#110,#111,#113));#92=POLY_LOOP('',(#110,#113,#112));#93=POLY_LOOP('',(#111,#112,#113));
        #100=PLANE('',#51);
        #110=CARTESIAN_POINT('',(0.,0.,0.));#111=CARTESIAN_POINT('',(12.,0.,0.));#112=CARTESIAN_POINT('',(2.,9.,0.));#113=CARTESIAN_POINT('',(3.,2.,14.));
        """
        let a = try STEPImporter.entities(head + asm + tail)
        XCTAssertEqual(a.count, 2, "one wedge per mapped occurrence")
        let far = try XCTUnwrap(a.first { $0.props["name"] == "wedge [2]" }.flatMap(mesh))
        XCTAssertTrue(far.meshVertices.contains { ($0 - Vec3(0, 32 + 12, 5)).length < 1e-6 }, "rotated 90° about z and moved")
        XCTAssertTrue(far.meshVertices.contains { ($0 - Vec3(-2, 32 + 3, 19)).length < 1e-6 })
    }

    /// Real-world files from the BRL-CAD regression set (NIST MBE PMI models), when the reference checkout is present.
    func testReferenceModels() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("other_projects/brlcad")
        guard FileManager.default.fileExists(atPath: root.path) else { throw XCTSkip("reference models not present") }
        var files = (1...6).map { root.appendingPathComponent("db/nist/NIST_MBE_PMI_\($0).stp") } + [root.appendingPathComponent("db/nist/NIST_MBE_PMI_11.stp")]
        let tests = root.appendingPathComponent("src/conv/step")
        if let e = FileManager.default.enumerator(atPath: tests.path) { for case let p as String in e where p.hasSuffix(".stp") { files.append(tests.appendingPathComponent(p)) } }
        var report: [String] = []
        for url in files where FileManager.default.fileExists(atPath: url.path) {
            let text = try FileImport.readText(url)
            let t0 = Date()
            let ents = (try? STEPImporter.entities(text)) ?? []
            let meshes = ents.compactMap(mesh)
            let tris = meshes.reduce(0) { $0 + $1.meshTriangles.count / 3 }
            let open = meshes.reduce(0) { $0 + openEdges($1) }
            let vol = meshes.reduce(0.0) { $0 + volume($1) }
            report.append("\(url.lastPathComponent): \(ents.count) solids, \(tris) triangles, \(open) open edges, volume \(fmt(vol, 1)), \(fmt(Date().timeIntervalSince(t0), 2)) s")
            if url.lastPathComponent.hasPrefix("NIST") {
                XCTAssertGreaterThan(tris, 2000, url.lastPathComponent)
                XCTAssertGreaterThan(vol, 0, url.lastPathComponent)
                XCTAssertLessThan(Double(open), Double(tris) * 0.01, "\(url.lastPathComponent): nearly watertight")
            }
        }
        print("STEP reference import:\n" + report.joined(separator: "\n"))
    }
}
