// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMRound4Tests: XCTestCase {
    func bounds(_ groups: [MeshGroup]) -> BBox3 { groups.reduce(BBox3.empty) { var b = $0; if !$1.mesh.isEmpty { b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max) }; return b } }
    func volume(_ groups: [MeshGroup]) -> Double { groups.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) } }

    // MARK: PAR-004 blend / swept blend

    func testBlendAndSweptBlendFormsFlex() async {
        let ed = Editor()
        await ed.run("FAMILY New Vase Generic")
        var def = ed.doc.family(named: "Vase")!
        def.parameters.append(FamilyParameter("Top", value: "400"))
        def.profiles = [FamilyProfile(name: "Base", points: [["0", "0"], ["Width", "0"], ["Width", "Width"], ["0", "Width"]]),
                        FamilyProfile(name: "Head", points: [["(Width-Top)/2", "(Width-Top)/2"], ["(Width+Top)/2", "(Width-Top)/2"], ["(Width+Top)/2", "(Width+Top)/2"], ["(Width-Top)/2", "(Width+Top)/2"]])]
        def.forms = [FamilyForm(.blend, name: "Body", dims: ["height": "Height"], profile: "Base", material: "Concrete", profile2: "Head")]
        ed.doc.families[ed.doc.familyIndex("Vase")!] = def
        // Frustum of a square pyramid: V = h/3 (A1 + A2 + sqrt(A1 A2)).
        func frustum(_ a: Double, _ b: Double, _ h: Double) -> Double { h / 3 * (a * a + b * b + a * b) }
        var r = FamilyEngine.evaluate(ed.doc.family(named: "Vase")!, doc: ed.doc)
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        var mesh = r.parts["Concrete"]!.mesh
        XCTAssertEqual(MeshTools.signedVolume(mesh), frustum(600, 400, 750), accuracy: frustum(600, 400, 750) * 0.01)
        XCTAssertTrue(PlaneClipper.isClosedManifold(MeshTools.triangles(mesh)))
        XCTAssertEqual(r.bounds.max.z, 750, accuracy: 1e-6)
        // Flex: top parameter drives the top profile.
        r = FamilyEngine.evaluate(ed.doc.family(named: "Vase")!, doc: ed.doc, props: ["fp.Top": "200", "fp.Height": "1000"])
        mesh = r.parts["Concrete"]!.mesh
        XCTAssertEqual(MeshTools.signedVolume(mesh), frustum(600, 200, 1000), accuracy: frustum(600, 200, 1000) * 0.01)
        // Swept blend along an L path from a 100 square to a 40 square.
        ed.doc.families[ed.doc.familyIndex("Vase")!].forms = [
            FamilyForm(.sweptBlend, name: "Horn", dims: ["width": "100", "height": "100", "width2": "40", "height2": "40"], profile: "rect",
                       path: [["0", "0", "500"], ["0", "1000", "500"], ["1000", "1000", "500"]], material: "Steel"),
        ]
        r = FamilyEngine.evaluate(ed.doc.family(named: "Vase")!, doc: ed.doc)
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        let horn = r.parts["Steel"]!.mesh
        XCTAssertGreaterThan(MeshTools.signedVolume(horn), 2000 * 40 * 40 * 0.9)
        XCTAssertLessThan(MeshTools.signedVolume(horn), 2000 * 100 * 100)
        XCTAssertEqual(r.bounds.max.x, 1000, accuracy: 1)
        XCTAssertFalse(r.outlines.isEmpty)
        // Command-line form creation and persistence.
        await ed.run("FAMILY Form Vase BLend ; ; ; Base Head ; ; ; ; ; No Wood ; ;")
        let f = ed.doc.family(named: "Vase")!.forms.last!
        XCTAssertEqual(f.kind, .blend); XCTAssertEqual(f.profile2, "Head")
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.family(named: "Vase")?.forms, ed.doc.family(named: "Vase")?.forms)
    }

    // MARK: PAR-020 URL and family-type parameters

    func testURLAndFamilyTypeParameters() async {
        let ed = Editor()
        await ed.run("FAMILY New Leg Generic")
        await ed.run("FAMILY New Table Furniture")
        var leg = ed.doc.family(named: "Leg")!
        leg.forms = [FamilyForm(.box, dims: ["width": "40", "depth": "40", "height": "Height"], material: "Steel")]
        leg.types = ["Tall": ["Height": "1000"]]
        ed.doc.families[ed.doc.familyIndex("Leg")!] = leg
        await ed.run("FAMILY Param Table Maker Url https://example.com/table")
        await ed.run("FAMILY Param Table LegType FamilyType Leg:Tall")
        let t = ed.doc.family(named: "Table")!
        XCTAssertEqual(t.parameter("Maker")?.kind, .url)
        XCTAssertEqual(t.parameter("LegType")?.kind, .familyType)
        XCTAssertEqual(t.parameter("LegType")?.value, "Leg:Tall")
        // Invalid values are refused on entry.
        await ed.run("FAMILY Param Table Bad Url notaurl")
        XCTAssertNil(ed.doc.family(named: "Table")!.parameter("Bad"))
        await ed.run("FAMILY Param Table Bad2 FamilyType Missing")
        XCTAssertNil(ed.doc.family(named: "Table")!.parameter("Bad2"))
        XCTAssertNotNil(FamilyParameterKind.url.validate("ftp//x", families: []))
        XCTAssertNil(FamilyParameterKind.url.validate("mailto:a@b.c", families: []))
        // A nested form driven by the family-type parameter: switching the type changes the geometry.
        ed.doc.families[ed.doc.familyIndex("Table")!].forms = [FamilyForm(.nested, family: "=LegType")]
        var r = FamilyEngine.evaluate(ed.doc.family(named: "Table")!, doc: ed.doc)
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertEqual(r.bounds.max.z, 1000, accuracy: 1e-6)
        r = FamilyEngine.evaluate(ed.doc.family(named: "Table")!, doc: ed.doc, props: ["fp.LegType": "Leg"])
        XCTAssertEqual(r.bounds.max.z, 750, accuracy: 1e-6)
        r = FamilyEngine.evaluate(ed.doc.family(named: "Table")!, doc: ed.doc, props: ["fp.LegType": "Nope"])
        XCTAssertTrue(r.errors.contains { $0.contains("not found") })
        // Text-valued: resolve keeps them as text (schedules read them).
        let res = FamilyExpr.resolve(ed.doc.family(named: "Table")!)
        XCTAssertEqual(res.text["maker"], "https://example.com/table")
        XCTAssertNil(res.values["maker"])
    }

    // MARK: BIM-074 escalators

    func testEscalatorRulesPlacementAndPlan() async {
        XCTAssertTrue(Escalators.check(rise: 4500, angleDeg: 30, stepWidth: 1000, speed: 0.5).isEmpty)
        XCTAssertTrue(Escalators.check(rise: 5000, angleDeg: 35, stepWidth: 800, speed: 0.5).isEmpty)
        XCTAssertFalse(Escalators.check(rise: 7000, angleDeg: 35, stepWidth: 800, speed: 0.5).isEmpty, "35° only up to 6 m")
        XCTAssertFalse(Escalators.check(rise: 4000, angleDeg: 35, stepWidth: 800, speed: 0.65).isEmpty, "35° only at 0.5 m/s")
        XCTAssertFalse(Escalators.check(rise: 4000, angleDeg: 30, stepWidth: 1200).isEmpty)
        XCTAssertFalse(Escalators.check(rise: 4000, angleDeg: 40, stepWidth: 1000).isEmpty)
        XCTAssertFalse(Escalators.check(rise: 4000, angleDeg: 30, stepWidth: 1000, speed: 0.9).isEmpty)
        XCTAssertEqual(Escalators.length(rise: 3000, angleDeg: 30), 3000 / tan(Double.pi / 6) + 4000, accuracy: 1e-6)

        let ed = Editor()
        await ed.run("SLAB 0,0 20000,0 20000,20000 0,20000")
        ed.doc.currentLevel = 1
        await ed.run("SLAB 0,0 20000,0 20000,20000 0,20000")
        ed.doc.currentLevel = 0
        await ed.run("ESCALATOR 5000,2000 90 3000 30 1000 0.5")
        guard let esc = ed.doc.elements.first(where: { if case .component(let g) = $0.geometry { return g.family == "escalator" }; return false }),
              case .component(let g) = esc.geometry else { return XCTFail("no escalator") }
        XCTAssertEqual(esc.props["escalatorCheck"], "OK")
        XCTAssertEqual(g.size.y, Escalators.length(rise: 3000, angleDeg: 30), accuracy: 1e-6)
        XCTAssertEqual(g.size.x, 1600, accuracy: 1e-9)
        XCTAssertEqual(g.position.x, 5000, accuracy: 1e-6)
        XCTAssertEqual(g.position.y, 2000 + g.size.y / 2, accuracy: 1e-6)
        XCTAssertEqual(Escalators.check(esc), [])
        // 3D: steps, decks, balustrades; the top reaches the upper floor plus the handrail.
        let groups = MeshBuilder.build(doc: ed.doc).filter { $0.id == esc.id }
        XCTAssertTrue(Set(groups.map(\.material)).isSuperset(of: ["Aluminium", "Steel", "Glass"]))
        let b = bounds(groups)
        XCTAssertEqual(b.max.z, 4000, accuracy: 1e-6)
        XCTAssertEqual(b.max.y, 2000 + g.size.y, accuracy: 1e-6)
        // Upper floor cut above the flight.
        let shaft = ed.doc.entities.first { Shafts.isShaft($0) && $0.props["escalator"] == "\(esc.id)" }
        XCTAssertNotNil(shaft)
        let upper = ed.doc.elements.first { $0.level == 1 }!
        XCTAssertFalse(Shafts.holes(for: upper, doc: ed.doc).isEmpty)
        // Plan: continuous lines below the cut, dashed lines beyond, a cut line.
        let items = PlanRepresentation.items(esc, doc: ed.doc)
        let strokes = items.compactMap { if case .stroke(let p, _, let st) = $0 { return (p, st) }; return nil }
        XCTAssertTrue(strokes.contains { !$0.1.dash.isEmpty })
        XCTAssertTrue(strokes.contains { $0.1.dash.isEmpty && $0.0.count == 5 }, "zig-zag cut line")
        let cutY = Escalators.Section(width: 1600, length: g.size.y, rise: 3000).y(atHeight: Escalators.planCutHeight) + g.position.y
        XCTAssertTrue(strokes.filter { !$0.1.dash.isEmpty }.allSatisfy { $0.0.allSatisfy { $0.y >= cutY - 1e-6 } })
        // Check option flags a non-compliant (steepened) escalator.
        if let i = ed.doc.elementIndex(esc.id), case .component(var g2) = ed.doc.elements[i].geometry {
            g2.size.z = 9000; ed.doc.elements[i].geometry = .component(g2)
        }
        await ed.run("ESCALATOR Check")
        XCTAssertNotEqual(ed.doc.element(esc.id)?.props["escalatorCheck"], "OK")
    }

    // MARK: M3D-038 section plane objects

    func testPlaneClipperKeepsSolidsClosed() {
        let box = SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))
        let half = PlaneClipper.clip(box, point: Vec3(500, 0, 0), normal: Vec3(1, 0, 0))!
        let m = MeshTools.mesh(of: half)
        XCTAssertEqual(MeshTools.signedVolume(m), 5e8, accuracy: 1)
        XCTAssertTrue(PlaneClipper.isClosedManifold(MeshTools.triangles(m)))
        // Oblique cut through a cylinder.
        let cyl = SolidGeom(kind: .cylinder, origin: .zero, size: Vec3(500, 0, 1000))
        let t = PlaneClipper.clip(MeshTools.triangles(MeshTools.mesh(of: cyl)), point: Vec3(0, 0, 500), normal: Vec3(0.3, 0.2, 1))
        XCTAssertTrue(PlaneClipper.isClosedManifold(t))
        XCTAssertEqual(MeshTools.signedVolume(MeshTools.solid(from: t).meshMesh), CSG.volume(cyl) / 2, accuracy: CSG.volume(cyl) * 0.02)
        // A cut through a hollow solid: the cap has a hole.
        var tube = MeshAcc()
        tube.prism([Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)], holes: [[Vec2(250, 250), Vec2(250, 750), Vec2(750, 750), Vec2(750, 250)]], z0: 0, z1: 1000)
        XCTAssertTrue(PlaneClipper.isClosedManifold(MeshTools.triangles(tube.mesh)))
        let tt = PlaneClipper.clip(MeshTools.triangles(tube.mesh), point: Vec3(0, 0, 400), normal: Vec3(0, 0, 1))
        XCTAssertTrue(PlaneClipper.isClosedManifold(tt))
        XCTAssertEqual(MeshTools.signedVolume(MeshTools.solid(from: tt).meshMesh), 400 * (1e6 - 250_000), accuracy: 10)
        // Plane touching a face exactly and a plane missing the solid.
        XCTAssertEqual(MeshTools.signedVolume(MeshTools.mesh(of: PlaneClipper.clip(box, point: Vec3(1000, 0, 0), normal: Vec3(1, 0, 0))!)), 1e9, accuracy: 1)
        XCTAssertNil(PlaneClipper.clip(box, point: Vec3(-1, 0, 0), normal: Vec3(1, 0, 0)))
    }

    func testSectionPlaneObjectsLiveGenerateSliceAndFollow() async {
        let ed = Editor()
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(2000, 1000, 1000))))
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(3000, 0, 0), size: Vec3(1000, 1000, 500))))
        await ed.run("SECTIONOBJECT Add 1000,-500 1000,2000 Cut1")
        guard let p = SectionPlaneObjects.named("Cut1", ed.doc) else { return XCTFail() }
        XCTAssertEqual(p.normal.x, 1, accuracy: 1e-12, "removes the right side of the trace")
        // Live: viewport variable and clipped model.
        await ed.run("SECTIONOBJECT Live")
        XCTAssertTrue(ed.doc.variable("SECTIONPLANE")?.hasPrefix("on;1000,-500,0;1,") ?? false, ed.doc.variable("SECTIONPLANE") ?? "nil")
        let clipped = SectionPlaneObjects.clippedModel(ed.doc)
        XCTAssertEqual(bounds(clipped).max.x, 1000, accuracy: 1e-6)
        XCTAssertEqual(volume(clipped), 1000 * 1000 * 1000, accuracy: 10)
        // Generate a 2D section block; moving the plane regenerates it.
        await ed.run("SECTIONOBJECT Generate 0,-5000")
        guard let bn = SectionPlaneObjects.named("Cut1", ed.doc)?.block, let blk = ed.doc.blocks[bn] else { return XCTFail("no block") }
        XCTAssertFalse(blk.entities.isEmpty)
        let before = blk.description
        ed.selection = [p.id]
        await ed.run("MOVE 0,0 500,0")
        XCTAssertNotEqual(ed.doc.blocks[bn]?.description, before, "block follows the moved plane")
        XCTAssertTrue(ed.doc.variable("SECTIONPLANE")?.hasPrefix("on;1500,") ?? false, "live plane follows too")
        // Flip, then slice: keeps the right side as closed solids; the far box on that side is untouched.
        await ed.run("SECTIONOBJECT Flip")
        XCTAssertEqual(SectionPlaneObjects.named("Cut1", ed.doc)!.normal.x, -1, accuracy: 1e-12)
        ed.selection = []
        await ed.run("SECTIONOBJECT Slice ")
        let solids = ed.doc.entities.compactMap { e -> SolidGeom? in if case .solid(let s) = e.geometry { return s }; return nil }
        XCTAssertEqual(solids.count, 2)
        for s in solids { XCTAssertTrue(PlaneClipper.isClosedManifold(MeshTools.triangles(MeshTools.mesh(of: s)))) }
        XCTAssertEqual(solids.reduce(0) { $0 + CSG.volume($1) }, 500 * 1000 * 1000 + 5e8, accuracy: 10)
        // Off, persistence, delete.
        await ed.run("SECTIONOBJECT Off")
        XCTAssertTrue(ed.doc.variable("SECTIONPLANE")?.hasPrefix("off") ?? false)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(SectionPlaneObjects.all(back).map(\.name), ["Cut1"])
        await ed.run("SECTIONOBJECT Delete")
        XCTAssertTrue(SectionPlaneObjects.all(ed.doc).isEmpty)
    }
}

private extension SolidGeom {
    var meshMesh: Mesh { MeshTools.mesh(of: self) }
}
