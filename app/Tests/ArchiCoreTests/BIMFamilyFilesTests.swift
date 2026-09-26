// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Family templates, symbolic lines, visibility by detail level/view, material parameters, tag families and .archifam files.
@MainActor
final class BIMFamilyFilesTests: XCTestCase {
    func strokes(_ items: [DrawItem]) -> [[Vec2]] { items.compactMap { if case .stroke(let p, _, _) = $0 { return p }; return nil } }

    func testTemplatesFlexAndSymbolicLinesByDetailLevel() async throws {
        let ed = Editor()
        for c in FamilyTemplates.categories { await ed.run("FAMILY New T\(c) \(c)") }
        XCTAssertEqual(ed.doc.families.count, FamilyTemplates.categories.count)
        XCTAssertEqual(ed.doc.family(named: "TDoor")?.category, "Door")
        XCTAssertEqual(ed.doc.family(named: "TTag")?.label, "{Mark}")
        // Generic template: a box that flexes, a coarse-only symbolic outline.
        await ed.run("FAMILY Place TGeneric 0,0 0")
        let inst = try XCTUnwrap(ed.doc.elements.last)
        guard case .component(let g0) = inst.geometry else { return XCTFail() }
        XCTAssertEqual(g0.size.x, 600, accuracy: 1e-6)
        ed.transaction("flex") { doc in doc.elements[doc.elementIndex(inst.id)!].props["fp.Width"] = "900" }
        guard case .component(let g1)? = ed.doc.element(inst.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(g1.size.x, 900, accuracy: 1e-6)
        let medium = strokes(PlanRepresentation.items(ed.doc.element(inst.id)!, doc: ed.doc))
        ed.doc.setVariable("DETAILLEVEL", "coarse")
        let coarse = strokes(PlanRepresentation.items(ed.doc.element(inst.id)!, doc: ed.doc))
        XCTAssertEqual(medium.count, 1, "box cut outline")
        XCTAssertEqual(coarse.count, 2, "box outline + coarse symbolic rectangle")
        XCTAssertEqual(BBox2(points: coarse.flatMap { $0 }).width, 900, accuracy: 1e-6)
    }

    func testFormVisibilityByViewAndDetailAndMaterialParameter() async throws {
        var doc = ArchiDocument()
        var def = FamilyTemplates.template(name: "Table", category: "Furniture")
        def.forms[0].views = "model"          // body only in 3D; plan uses symbolic lines
        def.symbolic = [FamilySymbolic(points: [["0", "0"], ["Width", "Depth"]])]
        var leg = FamilyForm(.box, name: "Leg", dims: ["width": "50", "depth": "50", "height": "Height"], material: "Steel")
        leg.detail = "fine"
        def.forms.append(leg)
        doc.families.append(def)
        let id = doc.addElement(.component(ComponentGeom(category: "Furniture", position: .zero, size: Vec3(600, 600, 750), family: "Table")))
        let el = doc.element(id)!
        let plan = PlanRepresentation.items(el, doc: doc)
        XCTAssertEqual(strokes(plan).count, 1, "only the symbolic diagonal in plan")
        var mats = Set(MeshBuilder.groups(for: el, doc: doc).map(\.material))
        XCTAssertEqual(mats, ["Wood"], "leg hidden below fine; material from the =Material parameter")
        doc.setVariable("DETAILLEVEL", "fine")
        mats = Set(MeshBuilder.groups(for: el, doc: doc).map(\.material))
        XCTAssertEqual(mats, ["Wood", "Steel"])
        // Material parameter bound to geometry (PAR-009).
        doc.elements[doc.elementIndex(id)!].props["fp.Material"] = "Glass"
        XCTAssertTrue(MeshBuilder.groups(for: doc.element(id)!, doc: doc).map(\.material).contains("Glass"))
        let back = try JSONDecoder().decode(FamilyDefinition.self, from: JSONEncoder().encode(def))
        XCTAssertEqual(back.forms[1].detail, "fine"); XCTAssertEqual(back.symbolic.count, 1)
    }

    func testTagFamilyReadsParameters() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        await ed.run("DOOR 2000,0 ")
        await ed.run("FAMILY New DoorTag Tag")
        await ed.run("FAMILY Label DoorTag \"{Mark} {Width}x{Height}\"")
        await ed.run("TAG Field DoorTag #\(ed.doc.elements[1].id) 2000,1000")
        let tag = try XCTUnwrap(ed.doc.entities.last { $0.props["tagOf"] != nil })
        XCTAssertEqual(tag.props["tagField"], "family:DoorTag")
        let door = ed.doc.elements.last!
        XCTAssertEqual(Annotations.tagText(door, field: "family:DoorTag", doc: ed.doc), "D01 900x2100")
        // Live: the tag follows the door width, and draws the family's symbolic box.
        ed.transaction("w") { doc in if case .opening(var o) = doc.elements[1].geometry { o.width = 1000; doc.elements[1].geometry = .opening(o) } }
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).first { $0.id == tag.id }?.items ?? []
        XCTAssertTrue(items.contains { if case .text(let t, _, _) = $0 { return t.content == "D01 1000x2100" }; return false }, "\(items)")
        XCTAssertTrue(items.contains { if case .stroke(let p, true, _) = $0 { return p.count == 4 }; return false })
        // Multi-category tags: any parameter name.
        await ed.run("TAG Field thickness 3000,0 3000,-800")
        XCTAssertEqual(ed.doc.entities.last?.props["tagField"], "thickness")
        XCTAssertEqual(Annotations.tagText(ed.doc.elements[0], field: "thickness", doc: ed.doc), "200")
    }

    func testArchifamSaveLoadReload() async throws {
        let ed = Editor()
        await ed.run("FAMILY New Chair Furniture")
        await ed.run("FAMILY New Seat Generic")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Nest Seat into Chair, then save.
        if let i = ed.doc.familyIndex("Chair") { ed.doc.families[i].forms.append(FamilyForm(.nested, name: "SeatN", dims: ["Height": "Height/2"], family: "Seat")) }
        let url = dir.appendingPathComponent("chair.archifam")
        await ed.run("FAMILY Save Chair \"\(url.path)\"")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let (f, nested, _) = try FamilyFiles.decode(Data(contentsOf: url))
        XCTAssertEqual(f.name, "Chair"); XCTAssertEqual(nested.map(\.name), ["Seat"])
        // Load into a new project: the nested family comes along.
        let ed2 = Editor()
        await ed2.run("FAMILY Load \"\(url.path)\"")
        XCTAssertNotNil(ed2.doc.family(named: "Chair")); XCTAssertNotNil(ed2.doc.family(named: "Seat"))
        XCTAssertEqual(ed2.doc.family(named: "Chair")?.source, url.path)
        await ed2.run("FAMILY Place Chair 0,0 0")
        // Project changes its value; the file changes its geometry; reload keeping project values.
        if let i = ed2.doc.familyIndex("Chair"), let j = ed2.doc.families[i].parameters.firstIndex(where: { $0.name == "Height" }) { ed2.doc.families[i].parameters[j].value = "900" }
        var edited = try FamilyFiles.decode(Data(contentsOf: url)).family
        edited.parameters.append(FamilyParameter("Arms", .yesNo, value: "1"))
        edited.parameters[edited.parameters.firstIndex { $0.name == "Height" }!].value = "700"
        try FamilyFiles.encode(edited, doc: ed.doc).write(to: url)
        await ed2.run("FAMILY Reload Chair No")
        let re = try XCTUnwrap(ed2.doc.family(named: "Chair"))
        XCTAssertNotNil(re.parameter("Arms"))
        XCTAssertEqual(re.parameter("Height")?.value, "900", "project value kept")
        await ed2.run("FAMILY Reload Chair Yes")
        XCTAssertEqual(ed2.doc.family(named: "Chair")?.parameter("Height")?.value, "700", "values overwritten")
        guard case .component(let g)? = ed2.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(g.size.z, 700, accuracy: 1e-6, "instances flex after reload")
        XCTAssertThrowsError(try FamilyFiles.decode(Data("{}".utf8)))
    }
}
