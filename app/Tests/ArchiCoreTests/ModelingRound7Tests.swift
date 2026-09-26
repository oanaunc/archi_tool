// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Round 7 modelling: 3D align, face extrude, wireframe, unfold, sections, Minkowski, springs, 3D text, CV surfaces
/// and the OpenSCAD interpreter.
@MainActor
final class ModelingRound7Tests: XCTestCase {
    func box(_ o: Vec3, _ s: Vec3) -> SolidGeom { SolidGeom(kind: .box, origin: o, size: s) }
    func closed(_ s: SolidGeom?) -> Bool { s.map { PlaneClipper.isClosedManifold(MeshTools.triangles(MeshTools.mesh(of: $0))) } ?? false }
    func vol(_ s: SolidGeom?) -> Double { s.map { CSG.volume($0) } ?? 0 }
    func tvol(_ t: [Tri3]) -> Double { SolidPrimitives.signedVolume(t) }

    // MARK: M3D-049

    func testAlign3D() async {
        let s = [Vec3(0, 0, 0), Vec3(1000, 0, 0), Vec3(0, 1000, 0)]
        let d = [Vec3(5000, 5000, 1000), Vec3(5000, 6000, 1000), Vec3(4000, 5000, 1000)]
        let f = MeshOps.alignment(source: s, dest: d)!
        for (a, b) in zip(s, d) { XCTAssertEqual(f(a).distance(to: b), 0, accuracy: 1e-9) }
        // Two points with scaling.
        let g = MeshOps.alignment(source: Array(s.prefix(2)), dest: [Vec3(0, 0, 0), Vec3(0, 0, 2000)], scale: true)!
        XCTAssertEqual(g(Vec3(1000, 0, 0)).distance(to: Vec3(0, 0, 2000)), 0, accuracy: 1e-9)
        // Command: move a box so its corner lands on a point, rigidly.
        let ed = Editor()
        let id = ed.doc.add(.solid(box(.zero, Vec3(1000, 500, 300))))
        ed.selection = [id]
        await ed.run("3DALIGN 0,0 0 1000,0 0  2000,2000 500 2000,3000 500 N")
        let r = ModelingCommands.solidOf(ed.doc, id)!
        XCTAssertTrue(closed(r)); XCTAssertEqual(vol(r), 1000 * 500 * 300, accuracy: 1)
        let b = MeshTools.mesh(of: r).bounds
        XCTAssertEqual(b.min.z, 500, accuracy: 1e-6)
        XCTAssertEqual(b.max.y, 3000, accuracy: 1e-6)
        XCTAssertEqual(b.size.x, 500, accuracy: 1e-6)
    }

    // MARK: M3D-062

    func testExtrudeFacesKeepsManifold() async {
        let s = box(.zero, Vec3(1000, 1000, 1000))
        let top = MeshOps.faces(s, facing: Vec3(0, 0, 1))
        XCTAssertEqual(top.count, 2)
        let r = MeshOps.extrudeFaces(s, faces: top, distance: 500)
        XCTAssertTrue(closed(r)); XCTAssertEqual(vol(r), 1.5e9, accuracy: 1)
        // Push the front face in.
        let front = MeshOps.faces(s, facing: Vec3(0, -1, 0))
        XCTAssertEqual(vol(MeshOps.extrudeFaces(s, faces: front, distance: -250)), 0.75e9, accuracy: 1)
        // Command with a picked point limits the faces to one region.
        let ed = Editor()
        let u = CSG.apply(.union, box(.zero, Vec3(1000, 1000, 1000)), box(Vec3(2000, 0, 0), Vec3(1000, 1000, 500)))!
        let id = ed.doc.add(.solid(u))
        ed.selection = [id]
        await ed.run("MESHEXTRUDE Top 2500,500 200")
        let rr = ModelingCommands.solidOf(ed.doc, id)!
        XCTAssertTrue(closed(rr))
        XCTAssertEqual(vol(rr), 1e9 + 1000 * 1000 * 700, accuracy: 10)
    }

    // MARK: M3D-063 / M3D-064 / M3D-061

    func testWireframeUnfoldAndSections() {
        let s = box(.zero, Vec3(1000, 1000, 1000))
        let w = MeshOps.wireframe(s, thickness: 20)!
        let parts = SolidCheck.separate(w)
        XCTAssertEqual(parts.count, 12 + 8)
        for p in parts { XCTAssertTrue(closed(p)); XCTAssertGreaterThan(vol(p), 0) }
        let net = MeshOps.unfold(s, gap: 100)!
        XCTAssertEqual(net.faces.count, 12)
        XCTAssertEqual(net.faces.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }, 6e6, accuracy: 1)
        for i in net.faces.indices { for j in net.faces.indices where j > i { XCTAssertFalse(MeshOps.trianglesOverlap(net.faces[i], net.faces[j]), "faces \(i) \(j) overlap") } }
        XCTAssertEqual(net.folds.count, 5, "a cube net has five folds")
        XCTAssertEqual(net.cuts.count, 14, "and fourteen cut edges")
        let sec = MeshOps.section(SolidGeom(kind: .sphere, origin: Vec3(0, 0, 0), size: Vec3(1000, 1000, 1000)), z: 0)
        XCTAssertEqual(sec.count, 1)
        let r = sec[0].map { $0.length }
        XCTAssertEqual(r.max()!, 1000, accuracy: 20); XCTAssertEqual(r.min()!, 1000, accuracy: 30)
        XCTAssertTrue(MeshOps.section(s, z: 2000).isEmpty)
    }

    // MARK: M3D-044 / M3D-011 / M3D-012

    func testMinkowskiSpringText() async {
        let a = box(.zero, Vec3(1000, 1000, 1000)), b = box(Vec3(-50, -50, -50), Vec3(100, 100, 100))
        let m = MeshOps.minkowski(a, b)!
        XCTAssertTrue(closed(m)); XCTAssertEqual(vol(m), 1100 * 1100 * 1100, accuracy: 10)
        let sp = MeshOps.spring(center: .zero, coilRadius: 50, wireRadius: 5, pitch: 20, turns: 5)!
        XCTAssertTrue(closed(sp))
        let wireLen = 5 * ((2 * Double.pi * 50) * (2 * Double.pi * 50) + 20 * 20).squareRoot()
        XCTAssertEqual(vol(sp), .pi * 25 * wireLen, accuracy: .pi * 25 * wireLen * 0.04)
        XCTAssertNil(MeshOps.spring(center: .zero, coilRadius: 50, wireRadius: 5, pitch: 8, turns: 5))
        let ed = Editor()
        await ed.run("TEXT3D \"HI\" 0,0 300 60 0")
        guard case .solid(let t)? = ed.doc.entities.last?.geometry else { return XCTFail("no text") }
        for p in SolidCheck.separate(t) { XCTAssertTrue(closed(p)) }
        let tb = MeshTools.mesh(of: t).bounds
        XCTAssertEqual(tb.size.z, 60, accuracy: 1e-6); XCTAssertEqual(tb.max.y, 300, accuracy: 30)
    }

    // MARK: M3D-070

    func testCVSurfaceFollowsControlPoints() async {
        let ed = Editor()
        await ed.run("SURFCV New 0,0 3000,3000 4 4")
        let id = ed.doc.entities.last!.id
        guard case .solid(let s0)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(s0.meshVertices.map(\.z).max()!, 0, accuracy: 1e-9)
        ed.selection = [id]
        await ed.run("SURFCV Edit 2 2 1200  ")
        guard case .solid(let s1)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        let peak = s1.meshVertices.map(\.z).max()!
        XCTAssertGreaterThan(peak, 100); XCTAssertLessThan(peak, 1200)
        // Corners stay interpolated; the surface point at the corner is the corner CV.
        XCTAssertTrue(s1.meshVertices.contains { $0.distance(to: Vec3(0, 0, 0)) < 1e-6 })
        XCTAssertTrue(s1.meshVertices.contains { $0.distance(to: Vec3(3000, 3000, 0)) < 1e-6 })
        // Partition of unity of the basis.
        for u in stride(from: 0.0, through: 1.0, by: 0.1) { XCTAssertEqual(MeshOps.basis(5, 3, u).reduce(0, +), 1, accuracy: 1e-9) }
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.entity(id)?.props["cvGrid"], ed.doc.entity(id)?.props["cvGrid"])
    }

    // MARK: M3D-090 / M3D-092 / M3D-094

    func testSCADPrimitivesMatchOpenSCAD() {
        var r = SCAD.evaluate("cube([10, 20, 30]);")
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertEqual(tvol(r.triangles), 6000, accuracy: 1e-6)
        // OpenSCAD cylinder with $fn = 6 is a hexagonal prism: area 3√3/2 r².
        r = SCAD.evaluate("cylinder(h = 10, r = 5, $fn = 6);")
        XCTAssertEqual(tvol(r.triangles), 3 * 3.0.squareRoot() / 2 * 25 * 10, accuracy: 1e-6)
        // Default fragments: r = 10 → max(min(360/12, 2π·10/2), 5) = 30 sides.
        r = SCAD.evaluate("cylinder(h = 1, r = 10);")
        XCTAssertEqual(tvol(r.triangles), 0.5 * 30 * 100 * sin(2 * .pi / 30), accuracy: 1e-6)
        // Sphere with $fn = 8: 4 rings at 22.5°, 67.5°… — volume of OpenSCAD's polyhedron, less than the ideal sphere.
        r = SCAD.evaluate("sphere(r = 10, $fn = 8);")
        let v = tvol(r.triangles)
        XCTAssertLessThan(v, 4.0 / 3 * .pi * 1000); XCTAssertGreaterThan(v, 0.6 * 4.0 / 3 * .pi * 1000)
        XCTAssertTrue(PlaneClipper.isClosedManifold(r.triangles))
        // Cone (r2 = 0).
        r = SCAD.evaluate("cylinder(h = 30, r1 = 10, r2 = 0, $fn = 4);")
        XCTAssertEqual(tvol(r.triangles), 200 * 30 / 3, accuracy: 1e-6)
    }

    func testSCADLanguageAndBooleans() {
        let src = """
        // A plate with holes, built from a module and a loop.
        size = 100;
        function half(x) = x / 2;
        module plate(t = 10) { cube([size, size, t]); }
        difference() {
            plate(t = 10);
            for (i = [0 : 1]) for (j = [0 : 1])
                translate([25 + i * 50, 25 + j * 50, -1]) cylinder(h = 12, r = half(10), $fn = 4);
        }
        echo("area", size * size, [for (k = [1:3]) k * k]);
        """
        let r = SCAD.evaluate(src)
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertEqual(tvol(r.triangles), 100 * 100 * 10 - 4 * (2 * 25) * 10, accuracy: 1e-3)
        XCTAssertEqual(r.echo.first, "\"area\", 10000, [1, 4, 9]")
        // intersection, hull, rotate, mirror, scale, union overlap.
        XCTAssertEqual(tvol(SCAD.evaluate("intersection() { cube(10); translate([5,5,5]) cube(10); }").triangles), 125, accuracy: 1e-6)
        XCTAssertEqual(tvol(SCAD.evaluate("union() { cube(10); translate([5,0,0]) cube(10); }").triangles), 1500, accuracy: 1e-6)
        XCTAssertEqual(tvol(SCAD.evaluate("hull() { cube(1); translate([9,0,0]) cube(1); }").triangles), 10, accuracy: 1e-6)
        let m = SCAD.evaluate("mirror([1,0,0]) scale([2,1,1]) rotate([0,0,90]) cube([1,2,3]);")
        XCTAssertEqual(tvol(m.triangles), 12, accuracy: 1e-9)
        var bb = BBox3.empty; for t in m.triangles { bb.add(t.0); bb.add(t.1); bb.add(t.2) }
        XCTAssertEqual(bb.min.x, 0, accuracy: 1e-9); XCTAssertEqual(bb.max.x, 4, accuracy: 1e-9)
        // Minkowski of a cube with a cube.
        XCTAssertEqual(tvol(SCAD.evaluate("minkowski() { cube(10); cube(2, center = true); }").triangles), 1728, accuracy: 1e-6)
        // Recursion, if/else, ternary, let, children().
        let rec = SCAD.evaluate("""
        function fact(n) = n <= 1 ? 1 : n * fact(n - 1);
        module stack(n) { if (n > 0) { cube([1, 1, 1]); translate([0, 0, 1]) stack(n - 1); } }
        module twice() { children(); translate([5, 0, 0]) children(); }
        echo(fact(5), let(a = 2, b = a * 3) b);
        twice() stack(3);
        """)
        XCTAssertEqual(rec.echo.first, "120, 6")
        XCTAssertEqual(tvol(rec.triangles), 6, accuracy: 1e-6)
    }

    func testSCAD2DExtrudesOffsetProjectionAndFiles() async throws {
        // linear_extrude of a square with a hole; twist keeps the volume.
        var r = SCAD.evaluate("linear_extrude(height = 10) difference() { square(10); translate([2,2]) square(6); }")
        XCTAssertEqual(tvol(r.triangles), (100 - 36) * 10, accuracy: 1e-6)
        r = SCAD.evaluate("linear_extrude(height = 10, twist = 90, slices = 20) square(4, center = true);")
        XCTAssertEqual(tvol(r.triangles), 160, accuracy: 1)
        // rotate_extrude of a square ring → annular cylinder.
        r = SCAD.evaluate("rotate_extrude($fn = 64) translate([10, 0]) square([5, 10]);")
        let ideal = Double.pi * (15 * 15 - 10 * 10) * 10
        XCTAssertEqual(tvol(r.triangles), ideal, accuracy: ideal * 0.01)
        XCTAssertTrue(PlaneClipper.isClosedManifold(r.triangles))
        // offset(delta) grows a square; projection(cut) slices a solid.
        r = SCAD.evaluate("offset(delta = 1) square(10);")
        XCTAssertEqual(abs(GeometryOps.signedArea(r.loops[0])), 144, accuracy: 1e-6)
        r = SCAD.evaluate("projection(cut = true) translate([0,0,-5]) cube([10, 20, 10]);")
        XCTAssertEqual(r.loops.count, 1)
        XCTAssertEqual(abs(GeometryOps.signedArea(Array(r.loops[0].dropLast()))), 200, accuracy: 1e-6)
        r = SCAD.evaluate("projection() rotate([0,0,0]) cube([10, 20, 5]);")
        XCTAssertEqual(r.loops.reduce(0) { $0 + GeometryOps.signedArea($1) }, 200, accuracy: 1e-6)
        // Errors are reported, not thrown.
        XCTAssertFalse(SCAD.evaluate("cube(;").errors.isEmpty)
        // Files with use<>.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "module block(s) { cube(s); }\nblock(100);".write(to: dir.appendingPathComponent("lib.scad"), atomically: true, encoding: .utf8)
        try "use <lib.scad>\nblock(2);".write(to: dir.appendingPathComponent("main.scad"), atomically: true, encoding: .utf8)
        let ed = Editor()
        await ed.run("SCADFILE \(dir.appendingPathComponent("main.scad").path)")
        guard case .solid(let s)? = ed.doc.entities.last?.geometry else { return XCTFail("no solid") }
        XCTAssertEqual(CSG.volume(s), 8, accuracy: 1e-6, "use<> imports modules only, not the library's top-level objects")
        await ed.run("SCAD difference() { cube(20, center = true); sphere(r = 12, $fn = 24); }")
        guard case .solid(let s2)? = ed.doc.entities.last?.geometry else { return XCTFail("no solid") }
        XCTAssertGreaterThan(CSG.volume(s2), 0); XCTAssertLessThan(CSG.volume(s2), 8000)
    }
}
