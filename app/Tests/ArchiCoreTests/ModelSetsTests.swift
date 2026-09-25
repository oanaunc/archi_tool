// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class ModelSetsTests: XCTestCase {
    @MainActor
    func testFormulaWidthFollowsHeightThroughCommands() async {
        let ed = Editor()
        let w = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(8000, 0), thickness: 200, height: 3000)))
        var o = OpeningGeom(kind: .window, hostWall: w, offset: 3000, width: 1, height: 1)
        ed.doc.openingType("Fixed 600x1800")!.apply(to: &o)
        let win = ed.doc.addElement(.opening(o))
        await ed.run("OPENINGTYPE Formula \"Fixed 600x1800\" width \"height / 2\"")
        guard case .opening(let a)? = ed.doc.element(win)?.geometry else { return XCTFail() }
        XCTAssertEqual(a.width, 900, accuracy: 1e-9)
        await ed.run("OPENINGTYPE Set \"Fixed 600x1800\" height 2400")
        guard case .opening(let b)? = ed.doc.element(win)?.geometry else { return XCTFail() }
        XCTAssertEqual(b.height, 2400, accuracy: 1e-9); XCTAssertEqual(b.width, 1200, accuracy: 1e-9)
        // A cycle is rejected and leaves the type unchanged.
        let log = await ed.run("OPENINGTYPE Formula \"Fixed 600x1800\" height \"width * 2\"")
        XCTAssertTrue(log.contains { $0.contains("circular") }, log.joined(separator: "\n"))
        XCTAssertNil(ed.doc.openingType("Fixed 600x1800")?.formulas["height"])
    }

    func testTypeFormulasResolveInOrderAndDetectCycles() {
        var t = OpeningType(name: "W", kind: .window, width: 1200, height: 1000, sill: 900, params: ["Rate": "350"])
        t.formulas = ["height": "width * 1.5", "sill": "2400 - height", "mullions": "floor(width / 600) - 1", "Cost": "width * height / 1e6 * rate"]
        let r = t.resolved()
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertEqual(r.type.height, 1800, accuracy: 1e-9)
        XCTAssertEqual(r.type.sill, 600, accuracy: 1e-9)
        XCTAssertEqual(r.type.mullions, 1)
        XCTAssertEqual(Double(r.type.params["Rate"]!)!, 350)
        XCTAssertEqual(Double(r.type.params["Cost"]!)!, 756, accuracy: 1e-6)
        var o = OpeningGeom(kind: .window, hostWall: 1, offset: 0, width: 1, height: 1)
        t.apply(to: &o)
        XCTAssertEqual(o.height, 1800, accuracy: 1e-9); XCTAssertEqual(o.mullions, 1)
        var c = t; c.formulas = ["width": "height + 1", "height": "width - 1"]
        XCTAssertEqual(c.resolved().errors.count, 2)
        var u = t; u.formulas = ["height": "depth * 2"]
        XCTAssertTrue(u.resolved().errors[0].contains("unknown"))
        XCTAssertEqual(TypeFormulas.identifiers("sqrt(width)+2*Height-pi"), ["width", "height"])
        // Old type JSON without the new keys still decodes.
        let old = #"{"name":"X","kind":"door","width":900,"height":2100,"sill":0,"doorStyle":"single","windowStyle":"casement","frameWidth":50,"params":{}}"#
        let d = try! JSONDecoder().decode(OpeningType.self, from: Data(old.utf8))
        XCTAssertTrue(d.formulas.isEmpty); XCTAssertEqual(d.mullions, 0)
    }

    func testWorksetsHideElements() {
        var doc = ArchiDocument()
        doc.setVariable(Worksets.currentVariable, "Core")
        let a = doc.addElement(.column(ColumnGeom(position: .zero)))
        doc.variables[Worksets.currentVariable] = nil
        let b = doc.addElement(.column(ColumnGeom(position: Vec2(2000, 0))))
        XCTAssertEqual(doc.element(a)?.props["workset"], "Core")
        XCTAssertEqual(Worksets.name(of: doc.element(b)!.props), Worksets.defaultName)
        XCTAssertEqual(Worksets.all(doc), [Worksets.defaultName, "Core"])
        Worksets.setHidden("core", true, doc: &doc)
        let ids = DrawListBuilder.entries(doc: doc, options: DrawOptions()).compactMap(\.id)
        XCTAssertFalse(ids.contains(a)); XCTAssertTrue(ids.contains(b))
        XCTAssertEqual(Set(MeshBuilder.build(doc: doc).compactMap(\.id)), [b])
        Worksets.setHidden("Core", false, doc: &doc)
        XCTAssertEqual(Set(MeshBuilder.build(doc: doc).compactMap(\.id)), [a, b])
    }

    func testDesignOptionsShowPrimaryAndAccept() {
        var doc = ArchiDocument()
        DesignOptions.save([DesignOptionSet(name: "Entrance", options: ["Canopy", "Recess"], primary: "Canopy")], doc: &doc)
        let main = doc.addElement(.column(ColumnGeom(position: .zero)))
        doc.setVariable(DesignOptions.editingVariable, "Entrance:Canopy")
        let c = doc.addElement(.column(ColumnGeom(position: Vec2(1000, 0))))
        doc.setVariable(DesignOptions.editingVariable, "Entrance:Recess")
        let r = doc.addElement(.column(ColumnGeom(position: Vec2(2000, 0))))
        XCTAssertEqual(Set(MeshBuilder.build(doc: doc).compactMap(\.id)), [main, c])
        doc.setVariable(DesignOptions.viewVariable, "Entrance:Recess")
        XCTAssertEqual(Set(DrawListBuilder.entries(doc: doc, options: DrawOptions()).compactMap(\.id)), [main, r])
        let res = DesignOptions.acceptPrimary("entrance", doc: &doc)
        XCTAssertEqual(res?.kept, 1); XCTAssertEqual(res?.removed, 1)
        XCTAssertNil(doc.element(r)); XCTAssertNil(doc.element(c)?.props["designOption"])
        XCTAssertTrue(DesignOptions.sets(doc).isEmpty)
        XCTAssertNil(doc.variable(DesignOptions.editingVariable))
    }
}
