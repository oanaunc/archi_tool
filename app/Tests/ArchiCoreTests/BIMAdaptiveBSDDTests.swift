// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Adaptive components (PAR-015) and bSDD classification lookup (BIM-131).
@MainActor
final class BIMAdaptiveBSDDTests: XCTestCase {
    func bounds(_ el: BIMElement, _ doc: ArchiDocument) -> BBox3 {
        var b = BBox3.empty
        for g in MeshBuilder.groups(for: el, doc: doc) { g.mesh.positions.forEach { b.add($0) } }
        return b
    }

    func testStrutFollowsPointObjectAndFlexes() async {
        let ed = Editor()
        var pe = Entity(geometry: .point(Vec2(2000, 0))); pe.props["elevation"] = "500"
        let pt = ed.doc.add(pe)
        await ed.run("ADAPTIVE Place Strut 60 0,0,0 O #\(pt) ")
        guard let s = ed.doc.elements.last, s.props["adaptiveKind"] == "Strut" else { return XCTFail("no strut") }
        XCTAssertEqual(Double(s.props["Length"]!)!, (2000.0 * 2000 + 500 * 500).squareRoot(), accuracy: 0.01)
        var b = bounds(s, ed.doc)
        XCTAssertEqual(b.max.x, 2000, accuracy: 31); XCTAssertEqual(b.max.z, 500, accuracy: 31)
        // Moving the point object flexes the strut.
        ed.doc.entities[ed.doc.entityIndex(pt)!].geometry = .point(Vec2(3000, 0))
        BIMUpdaters.run(&ed.doc)
        let s2 = ed.doc.element(s.id)!
        XCTAssertEqual(Double(s2.props["Length"]!)!, (3000.0 * 3000 + 500 * 500).squareRoot(), accuracy: 0.01)
        b = bounds(s2, ed.doc)
        XCTAssertEqual(b.max.x, 3000, accuracy: 31)
        XCTAssertFalse(PlanRepresentation.items(s2, doc: ed.doc).isEmpty)
    }

    func testPanelMovePointAndMoveElement() async {
        let ed = Editor()
        await ed.run("ADAPTIVE Place Panel 30 0,0,0 1000,0,0 1000,1000,0 0,1000,0 ")
        guard let p = ed.doc.elements.last, p.props["adaptiveKind"] == "Panel" else { return XCTFail("no panel") }
        XCTAssertEqual(Double(p.props["Area"]!)!, 1, accuracy: 1e-6)
        var vol = MeshBuilder.groups(for: p, doc: ed.doc).map { MeshTools.signedVolume($0.mesh) }.reduce(0, +)
        XCTAssertEqual(abs(vol), 1e6 * 30, accuracy: 1)
        await ed.run("ADAPTIVE Move #\(p.id) 3 2000,1000,0")
        let p2 = ed.doc.element(p.id)!
        XCTAssertEqual(Double(p2.props["Area"]!)!, 1.5, accuracy: 1e-6)
        vol = MeshBuilder.groups(for: p2, doc: ed.doc).map { MeshTools.signedVolume($0.mesh) }.reduce(0, +)
        XCTAssertEqual(abs(vol), 1.5e6 * 30, accuracy: 1)
        // Moving the element carries its typed points along (no distortion).
        if let i = ed.doc.elementIndex(p.id), case .component(var g) = ed.doc.elements[i].geometry { g.position = g.position + Vec2(5000, 0); ed.doc.elements[i].geometry = .component(g) }
        BIMUpdaters.run(&ed.doc)
        let p3 = ed.doc.element(p.id)!
        XCTAssertEqual(Double(p3.props["Area"]!)!, 1.5, accuracy: 1e-6)
        XCTAssertEqual(bounds(p3, ed.doc).min.x, 5000, accuracy: 1)
        XCTAssertTrue(AdaptiveComponents.parse(p3.props["adaptivePoints"])[0].hasPrefix("5000"))
        // Too few points: refused.
        let n = ed.doc.elements.count
        await ed.run("ADAPTIVE Place Panel 30 0,0,0 1000,0,0 ")
        XCTAssertEqual(ed.doc.elements.count, n)
    }

    func testFamilyDrivenByAdaptivePoints() {
        var doc = ArchiDocument()
        doc.families.append(FamilyDefinition(name: "Brace", category: "Structural Framing", parameters: [FamilyParameter("Size", value: "80")],
                                             forms: [FamilyForm(.sweep, name: "Bar", dims: ["width": "Size", "height": "Size"], profile: "rect", path: [["P1x", "P1y", "P1z"], ["P2x", "P2y", "P2z"]], material: "Steel")]))
        guard let id = AdaptiveComponents.place(kind: "Brace", points: ["0,0,0", "0,4000,3000"], doc: &doc), let el = doc.element(id) else { return XCTFail("not placed") }
        guard case .component(let g) = el.geometry else { return XCTFail() }
        XCTAssertEqual(g.category, "Structural Framing")
        var b = bounds(el, doc)
        XCTAssertEqual(b.max.y, 4000, accuracy: 60); XCTAssertEqual(b.max.z, 3000, accuracy: 60)
        // Changing the family parameter re-flexes the instance.
        doc.families[0].parameters[0].value = "200"
        BIMUpdaters.run(&doc)
        b = bounds(doc.element(id)!, doc)
        XCTAssertGreaterThan(b.max.x - b.min.x, 150)
    }

    let search = """
    {"classes":[{"uri":"https://identifier.buildingsmart.org/uri/buildingsmart/ifc/4.3/class/IfcWall","code":"IfcWall","name":"Wall","dictionaryName":"IFC"},
                {"uri":"https://identifier.buildingsmart.org/uri/nbs/uniclass2015/1/class/Ss_25_10_30","code":"Ss_25_10_30","name":"Timber framing systems","dictionaryName":"Uniclass 2015",
                 "classProperties":[{"name":"FireRating","propertyCode":"FireRating","propertySet":"Pset_WallCommon","dataType":"String","predefinedValue":"REI60"},
                                    {"name":"IsExternal","propertySet":"Pset_WallCommon","allowedValues":[{"code":"TRUE","value":"TRUE"},{"code":"FALSE","value":"FALSE"}]}]}]}
    """

    func testBSDDParseAssignFilterAndSchedule() async throws {
        let cs = BSDD.parse(Data(search.utf8))
        XCTAssertEqual(cs.map(\.code), ["IfcWall", "Ss_25_10_30"])
        XCTAssertEqual(cs[1].properties.count, 2)
        XCTAssertEqual(cs[1].properties[1].allowedValues, ["TRUE", "FALSE"])
        // PascalCase bSDD import file.
        let imp = BSDD.parse(Data(#"{"DictionaryName":"Acme","Classes":[{"Code":"A1","Name":"Alpha","ClassProperties":[{"PropertyCode":"Colour","PredefinedValue":"Red"}]}]}"#.utf8))
        XCTAssertEqual(imp.first?.code, "A1"); XCTAssertEqual(imp.first?.dictionary, "Acme"); XCTAssertEqual(imp.first?.properties.first?.predefinedValue, "Red")
        XCTAssertTrue(BSDD.searchURL("timber wall")!.absoluteString.contains("SearchText=timber%20wall"))
        XCTAssertTrue(BSDD.classURL("https://x/y")!.absoluteString.contains("IncludeClassProperties=true"))

        let ed = Editor()
        let w1 = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let w2 = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 3000), end: Vec2(5000, 3000))))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bsdd-test-\(UUID().uuidString).json")
        try Data(search.utf8).write(to: url)
        await ed.run("BSDD Load \"\(url.path)\"")
        XCTAssertEqual(BSDD.lastResults.count, 2)
        await ed.run("BSDD Assign 2 #\(w1) ")
        let e1 = ed.doc.element(w1)!
        XCTAssertEqual(e1.props["bsdd.Code"], "Ss_25_10_30")
        XCTAssertEqual(e1.props["Pset_WallCommon.FireRating"], "REI60")
        XCTAssertEqual(e1.props[Classification.key("Uniclass 2015")], "Ss_25_10_30")
        // Schedules and view filters see the class.
        XCTAssertEqual(Schedules.value("bsdd.Code", Schedules.Obj(id: w1, element: e1), doc: ed.doc), "Ss_25_10_30")
        await ed.run("BSDD Filter Ss_25_10_30 hide")
        XCTAssertEqual(VisibilityGraphics.override(e1, doc: ed.doc).hidden, true)
        XCTAssertNotEqual(VisibilityGraphics.override(ed.doc.element(w2)!, doc: ed.doc).hidden, true)
        try? FileManager.default.removeItem(at: url)
    }
}
