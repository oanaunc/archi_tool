// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMFamilyTests: XCTestCase {
    func testFamilyExpressionsFormulasAndRanges() {
        XCTAssertEqual(FamilyExpr.evaluate("if(w > 1000, 2, 1) * 10", ["W": 1200]), 20)
        XCTAssertEqual(FamilyExpr.evaluate("min(a, b) + max(a, b)", ["a": 3, "b": 5]), 8)
        XCTAssertEqual(FamilyExpr.evaluate("a >= 3 && b < 4", ["a": 3, "b": 5]), 0)
        XCTAssertEqual(FamilyExpr.evaluate("cos(60) * 2", [:])!, 1, accuracy: 1e-12)
        XCTAssertNil(FamilyExpr.evaluate("unknown + 1", [:]))
        var def = FamilyDefinition(name: "T", parameters: [
            FamilyParameter("Width", value: "900", min: 400, max: 1000),
            FamilyParameter("Half", value: "0", formula: "Width / 2"),
            FamilyParameter("A", value: "0", formula: "B + 1"), FamilyParameter("B", value: "0", formula: "A + 1"),
        ])
        var r = FamilyExpr.resolve(def, overrides: ["width": "1500"])
        XCTAssertEqual(r.values["width"], 1000, "clamped to the validation range")
        XCTAssertEqual(r.values["half"], 500)
        XCTAssertTrue(r.errors.contains { $0.contains("circular") })
        def.types["Small"] = ["Width": "500"]
        r = FamilyExpr.resolve(def, type: "Small")
        XCTAssertEqual(r.values["half"], 250)
    }

    func testFamilyInstancesRegenerateWhenTheDefinitionChanges() async {
        let ed = Editor()
        await ed.run("FAMILY New Stool Furniture")
        XCTAssertNotNil(ed.doc.family(named: "Stool"))
        // Seat box and four legs as an array; a void cut through the seat; conditional back rest.
        var def = ed.doc.family(named: "Stool")!
        def.parameters.append(FamilyParameter("Legs", .integer, value: "2"))
        def.parameters.append(FamilyParameter("Back", .yesNo, value: "0"))
        def.forms = [
            FamilyForm(.box, name: "Seat", z: "Height - 40", dims: ["width": "Width", "depth": "Depth", "height": "40"], material: "Wood"),
            FamilyForm(.box, name: "Legs", dims: ["width": "40", "depth": "40", "height": "Height - 40"], material: "Steel", arrayCount: "Legs", arrayDX: "Width - 40"),
            FamilyForm(.box, name: "Back", y: "Depth - 30", z: "Height", dims: ["width": "Width", "depth": "30", "height": "400"], visible: "Back"),
        ]
        ed.doc.families[ed.doc.familyIndex("Stool")!] = def
        await ed.run("FAMILY Place Stool 1000,1000 0 ")
        guard let inst = ed.doc.elements.last, case .component(let g) = inst.geometry else { return XCTFail() }
        XCTAssertEqual(g.family, "Stool")
        let groups = MeshBuilder.build(doc: ed.doc).filter { $0.id == inst.id }
        XCTAssertEqual(Set(groups.map(\.material)), ["Wood", "Steel"])
        let b0 = groups.reduce(BBox3.empty) { var b = $0; b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max); return b }
        XCTAssertEqual(b0.max.z - b0.min.z, 750, accuracy: 1e-6)
        // Instance parameter: back rest on → taller; the instance size follows (FamilyInstances).
        ed.selection = []
        await ed.run("FAMILY Set #\(inst.id) Back 1")
        guard case .component(let g2) = ed.doc.element(inst.id)!.geometry else { return XCTFail() }
        XCTAssertEqual(g2.size.z, 1150, accuracy: 1e-6)
        // Editing the definition regenerates every instance.
        ed.doc.families[ed.doc.familyIndex("Stool")!].parameters[2].value = "1000"   // Height
        let b1 = MeshBuilder.build(doc: ed.doc).filter { $0.id == inst.id }.reduce(BBox3.empty) { var b = $0; b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max); return b }
        XCTAssertEqual(b1.max.z - b1.min.z, 1400, accuracy: 1e-6)
        // Plan symbol from the forms.
        XCTAssertFalse(PlanRepresentation.items(ed.doc.element(inst.id)!, doc: ed.doc).isEmpty)
        // Persistence.
        let data = try! ArchiFile.encode(ed.doc)
        let back = try! ArchiFile.decode(data)
        XCTAssertEqual(back.families, ed.doc.families)
    }

    func testVoidsNestedFamiliesSweepsAndRevolves() {
        var doc = ArchiDocument()
        doc.families.append(FamilyDefinition(name: "Knob", parameters: [FamilyParameter("R", value: "20")],
                                             forms: [FamilyForm(.cylinder, dims: ["radius": "R", "height": "30"], material: "Aluminium")]))
        doc.families.append(FamilyDefinition(name: "Panel", parameters: [FamilyParameter("Width", value: "1000"), FamilyParameter("Height", value: "500")],
            profiles: [FamilyProfile(name: "Rail", points: [["0", "0"], ["20", "0"], ["20", "40"], ["0", "40"]])],
            forms: [
                FamilyForm(.box, dims: ["width": "Width", "depth": "100", "height": "Height"], material: "Wood"),
                FamilyForm(.box, x: "100", y: "-10", z: "100", dims: ["width": "200", "depth": "120", "height": "200"], void: true),
                FamilyForm(.nested, x: "Width/2", y: "-30", z: "Height/2", dims: ["R": "Height/10"], family: "Knob"),
                FamilyForm(.sweep, profile: "Rail", path: [["0", "0", "Height"], ["Width", "0", "Height"]], material: "Steel"),
                FamilyForm(.revolve, x: "Width", dims: ["angle": "360"], profile: "Rail", material: "Steel"),
            ]))
        let r = FamilyEngine.evaluate(doc.family(named: "Panel")!, doc: doc)
        XCTAssertTrue(r.errors.isEmpty, r.errors.joined(separator: "; "))
        XCTAssertEqual(Set(r.parts.keys), ["Wood", "Aluminium", "Steel"])
        // The void removed 200×100×200 from the panel.
        let v = MeshTools.signedVolume(r.parts["Wood"]!.mesh)
        let expected83_1: Double = 1000 * 100 * 500 - 200 * 100 * 200
        XCTAssertEqual(v, expected83_1, accuracy: 1)
        // Nested knob radius bound to Height/10 = 50.
        let kb = r.parts["Aluminium"]!.mesh.bounds
        XCTAssertEqual(kb.max.x - kb.min.x, 100, accuracy: 1)
    }

    func testDoorAndWindowFamilyBuilderFlexWithTheOpening() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let wall = ed.doc.elements[0].id
        await ed.run("FAMILY Builder Door Glazed \"Glass Door\" 900 2100")
        await ed.run("FAMILY Builder Window Grid \"Grid Window\" 1200 1200 3 2")
        XCTAssertEqual(ed.doc.families.map(\.name), ["Glass Door", "Grid Window"])
        let door = ed.doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: wall, offset: 1500, width: 900, height: 2100)))
        let win = ed.doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: wall, offset: 4000, width: 1200, height: 1200, sill: 900)))
        ed.selection = [door]
        await ed.run("FAMILY Assign \"Glass Door\" ")
        ed.selection = [win]
        await ed.run("FAMILY Assign \"Grid Window\" ")
        XCTAssertEqual(ed.doc.element(door)?.props["family"], "Glass Door")
        func bounds(_ id: EntityID) -> BBox3 { MeshBuilder.build(doc: ed.doc).filter { $0.id == id }.reduce(BBox3.empty) { var b = $0; b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max); return b } }
        let wb = bounds(win)
        XCTAssertEqual(wb.max.x - wb.min.x, 1280, accuracy: 1, "frame + sill projection")
        XCTAssertEqual(wb.min.z, 870, accuracy: 1, "sill board under the frame")
        let groups = MeshBuilder.build(doc: ed.doc).filter { $0.id == door }
        XCTAssertTrue(groups.contains { $0.material == "Glass" }, "glazed door has glass")
        // Resizing the opening flexes the family.
        if let i = ed.doc.elementIndex(win), case .opening(var o) = ed.doc.elements[i].geometry { o.width = 2000; ed.doc.elements[i].geometry = .opening(o) }
        XCTAssertEqual(bounds(win).max.x - bounds(win).min.x, 2080, accuracy: 1)
        // The 3×2 grid: 2 mullions + 1 transom.
        let def = ed.doc.family(named: "Grid Window")!
        let res = FamilyExpr.resolve(def)
        XCTAssertEqual(res.values["columns"], 3); XCTAssertEqual(res.values["rows"], 2)
    }

    func testProfileFamiliesFlexInSweepsAndRailings() async {
        let ed = Editor()
        await ed.run("PLINE 0,0 100,0 100,20 50,60 0,60 C")
        let pl = ed.doc.entities.last!.id
        await ed.run("PROFILE New #\(pl) Moulding")
        guard let fam = ed.doc.family(named: "Moulding") else { return XCTFail() }
        XCTAssertEqual(fam.category, "Profile")
        let small = ProfileLibrary.outline("Moulding", width: 50, height: 30, doc: ed.doc)!
        let b = BBox2(points: small)
        XCTAssertEqual(b.width, 50, accuracy: 1e-6); XCTAssertEqual(b.height, 30, accuracy: 1e-6)
        // Every built-in profile is a valid closed outline of the requested size.
        for (n, _) in ProfileLibrary.builtins {
            guard let p = ProfileLibrary.builtin(n, width: 120, height: 80) else { return XCTFail(n) }
            XCTAssertGreaterThan(GeometryOps.signedArea(p), 0, n)
            let bb = BBox2(points: p)
            XCTAssertLessThanOrEqual(bb.width, 120 + 1e-6, n); XCTAssertLessThanOrEqual(bb.height, 80 + 1e-6, n)
        }
        // A wall sweep and a railing use the profile family.
        var r = RailingGeom(path: [Vec2(0, 0), Vec2(3000, 0)])
        r.railProfile = "Moulding"; r.railSize = 60; r.infill = "none"
        let id = ed.doc.addElement(.railing(r))
        let g = MeshBuilder.build(doc: ed.doc).filter { $0.id == id }
        XCTAssertFalse(g.isEmpty)
    }
}
