// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Visibility/graphics overrides, view filters and detail level only change the view they are set on.
@MainActor
final class RenderVisibilityTests: XCTestCase {
    func entry(_ es: [DrawEntry], _ id: EntityID) -> DrawEntry? { es.first { $0.id == id } }
    func colors(_ e: DrawEntry?) -> [RGBA] { (e?.items ?? []).compactMap { if case .stroke(_, _, let st) = $0 { return st.color }; return nil } }

    func testCategoryOverridesAndFilters() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        await ed.run("WALL 0,3000 6000,3000 ")
        await ed.run("DOOR 2000,0 ")
        let (w1, w2, d) = (ed.doc.elements[0].id, ed.doc.elements[1].id, ed.doc.elements[2].id)
        await ed.run("VG Categories door hide")
        var es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertNil(entry(es, d)); XCTAssertNotNil(entry(es, w1))
        await ed.run("VG Categories wall \"color:red;lw:0.7\"")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertTrue(colors(entry(es, w1)).allSatisfy { abs($0.r - 0.9) < 1e-9 && abs($0.g - 0.15) < 1e-9 })
        await ed.run("VG Categories door show")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertNotNil(entry(es, d))
        // Filter: walls with the parameter FireRating = EI60 are drawn halftone blue; others keep the category override.
        ed.transaction("p") { doc in doc.elements[1].props["FireRating"] = "EI60" }
        await ed.run("VG Filters New Fire wall \"FireRating = EI60\" \"color:blue;halftone\"")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        let c2 = colors(entry(es, w2)), c1 = colors(entry(es, w1))
        XCTAssertTrue(c2.allSatisfy { $0.b > $0.r }, "filtered wall")
        XCTAssertTrue(c1.allSatisfy { $0.r > $0.b }, "other wall keeps its override")
        await ed.run("VG Filters Disable Fire")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertTrue(colors(entry(es, w2)).allSatisfy { $0.r > $0.b })
        // Only the targeted view: a view template without the overrides leaves another view unchanged.
        ViewTemplates.save(ViewTemplate(name: "Clean", settings: ["VGCATEGORIES": "", "VIEWFILTERS": ""]), doc: &ed.doc)
        let other = ViewTemplates.applied(ed.doc, template: "Clean")
        let base = ed.doc.variables
        XCTAssertNotNil(base["VGCATEGORIES"])
        let clean = DrawListBuilder.entries(doc: other, options: DrawOptions(level: 0))
        XCTAssertFalse(colors(entry(clean, w1)).contains { abs($0.r - 0.9) < 1e-9 && abs($0.g - 0.15) < 1e-9 })
        // Templates capture the overrides.
        let t = ViewTemplate.capture("With VG", from: ed.doc)
        XCTAssertNotNil(t.settings["VGCATEGORIES"]); XCTAssertNotNil(t.settings["VIEWFILTERS"])
        XCTAssertNil(VisibilityGraphics.parseOverride("colour:nonsense"))
    }

    func testDetailLevelChangesWallAndOpeningGraphics() async throws {
        let ed = Editor()
        await ed.run("WALL Type \"Exterior Brick 365\" 0,0 6000,0 ")
        await ed.run("WINDOW 3000,0 ")
        let w = ed.doc.elements[0].id, win = ed.doc.elements[1].id
        let medium = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        await ed.run("VG Detail Coarse")
        XCTAssertEqual(ed.doc.variable("DETAILLEVEL"), "coarse")
        let coarse = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertLessThan(entry(coarse, w)!.items.count, entry(medium, w)!.items.count, "no ply lines or patterns")
        XCTAssertLessThan(entry(coarse, win)!.items.count, entry(medium, win)!.items.count)
        // 3D and sections: one solid, solid poché.
        XCTAssertEqual(MeshBuilder.groups(for: ed.doc.element(w)!, doc: ed.doc).filter { $0.kind == "wall" }.count, 1)
        let sec = ElevationBuilder.entries(doc: ed.doc, view: .section, sectionLine: (Vec2(1000, -2000), Vec2(1000, 2000)))
        XCTAssertTrue(sec.flatMap(\.items).contains { if case .fill(_, let c) = $0 { return c == ElevationBuilder.pocheColor }; return false })
    }
}
