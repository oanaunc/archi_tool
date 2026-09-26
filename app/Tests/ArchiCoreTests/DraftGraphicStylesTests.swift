// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Line styles (LAY-034), lineweight tables by scale (LAY-035), pen sets (LAY-036), graphic override filters (LAY-037).
@MainActor
final class DraftGraphicStylesTests: XCTestCase {
    func strokes(_ doc: ArchiDocument, _ id: EntityID, paper: Bool = false) -> [StrokeStyle] {
        var o = DrawOptions(); o.forPaper = paper
        return DrawListBuilder.entries(doc: doc, options: o).filter { $0.id == id }.flatMap(\.items).compactMap { if case .stroke(_, _, let s) = $0 { return s }; return nil }
    }

    func testLineStylesByObjectAndByLayer() async throws {
        let ed = Editor()
        await ed.run("-LAYER N Walls ")
        ed.doc.ensureLayer("Walls")
        await ed.run("LINESTYLES N Heavy red 0.7 Dashed")
        XCTAssertEqual(GraphicStyles.lineStyle("Heavy", doc: ed.doc)?.lineweight, 0.7)
        await ed.run("LINE 0,0 1000,0 ")
        let a = ed.doc.entities.last!.id
        await ed.run("LINESTYLES A Heavy #\(a) ")
        XCTAssertEqual(ed.doc.entity(a)?.props["lineStyle"], "Heavy")
        let s = strokes(ed.doc, a)
        XCTAssertEqual(s.first?.lineweight, 0.7)
        XCTAssertEqual(s.first?.color, aciColor(1))
        XCTAssertFalse(s.first?.dash.isEmpty ?? true)
        // ByLayer: objects on a layer with a line style use it; the style's ByLayer parts fall back to the layer.
        await ed.run("LINESTYLES N Thin ByLayer 0.13 ByLayer")
        await ed.run("LINESTYLES LA Walls Thin")
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 100), Vec2(1000, 100))), layer: "Walls")
        let sb = strokes(ed.doc, b)
        XCTAssertEqual(sb.first?.lineweight, 0.13)
        XCTAssertEqual(sb.first?.color, ed.doc.layer(named: "Walls")?.color)
        // Layer 0 objects inside a block follow the insert's layer.
        ed.doc.blocks["B"] = Block(name: "B", entities: [Entity(layer: "0", geometry: .line(LineGeom(.zero, Vec2(10, 0))))])
        let ins = ed.doc.add(.insert(InsertGeom(block: "B", position: Vec2(0, 500))), layer: "Walls")
        XCTAssertEqual(strokes(ed.doc, ins).first?.lineweight, 0.13)
        // Persisted in .archi, removed on delete.
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(strokes(back, a).first?.lineweight, 0.7)
        await ed.run("LINESTYLES D Heavy")
        XCTAssertNil(ed.doc.entity(a)?.props["lineStyle"])
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight, 0.25)
    }

    func testLineweightTableByScale() async {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 ")
        let a = ed.doc.entities.last!.id
        ed.doc.entities[ed.doc.entityIndex(a)!].lineweight = 0.5
        await ed.run("LWTABLE S 50=1;100=0.7;200=0.5")
        ed.doc.setVariable("CANNOSCALE", "1:50")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight ?? 0, 0.5, accuracy: 1e-12)
        ed.doc.setVariable("CANNOSCALE", "1:100")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight ?? 0, 0.35, accuracy: 1e-12)
        ed.doc.setVariable("CANNOSCALE", "1:500")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight ?? 0, 0.25, accuracy: 1e-12)
        ed.doc.setVariable("CANNOSCALE", "1:20")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight ?? 0, 0.5, accuracy: 1e-12, "below the first row the first factor applies")
        await ed.run("LWTABLE C")
        ed.doc.setVariable("CANNOSCALE", "1:500")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight ?? 0, 0.5, accuracy: 1e-12)
    }

    func testPenSetsApplyToPlotsAndResolveByLayer() async {
        let ed = Editor()
        await ed.run("PENSETS N Office")
        await ed.run("PENSETS P Office 1 0.6 blue")
        await ed.run("PENSETS C Office")
        let red = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))), color: .aci(1))
        let yellow = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))), color: .aci(2))
        // Screen unchanged, plot uses pens.
        XCTAssertEqual(strokes(ed.doc, red).first?.lineweight, 0.25)
        let p = strokes(ed.doc, red, paper: true).first
        XCTAssertEqual(p?.lineweight, 0.6)
        XCTAssertEqual(p?.color.b ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(strokes(ed.doc, yellow, paper: true).first?.lineweight, 0.25)
        // ByLayer objects use the pen of their layer colour (nearest index).
        ed.doc.layers.append(Layer(name: "R", color: aciColor(1)))
        let byl = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))), layer: "R")
        XCTAssertEqual(strokes(ed.doc, byl, paper: true).first?.lineweight, 0.6)
        // ByBlock children use the insert's colour.
        ed.doc.blocks["B"] = Block(name: "B", entities: [Entity(layer: "0", color: .byBlock, geometry: .line(LineGeom(.zero, Vec2(10, 0))))])
        let ins = ed.doc.add(.insert(InsertGeom(block: "B", position: .zero)), color: .aci(1))
        XCTAssertEqual(strokes(ed.doc, ins, paper: true).first?.lineweight, 0.6)
        await ed.run("PENSETS D Y")
        XCTAssertEqual(strokes(ed.doc, red).first?.lineweight, 0.6)
        await ed.run("PENSETS C None")
        XCTAssertEqual(strokes(ed.doc, red, paper: true).first?.lineweight, 0.25)
    }

    func testGraphicOverridesByFilter() async {
        let ed = Editor()
        ed.doc.ensureLayer("Existing")
        let a = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))), layer: "Existing")
        let b = ed.doc.add(.circle(CircleGeom(.zero, 50)), layer: "Existing")
        let c = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))))
        await ed.run("GFILTERS A Demolished line layer = existing color:red;lw:0.7")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight, 0.7)
        XCTAssertEqual(strokes(ed.doc, a).first?.color, RGBA(0.9, 0.15, 0.15))
        XCTAssertEqual(strokes(ed.doc, b).first?.lineweight, 0.25, "type restriction")
        XCTAssertEqual(strokes(ed.doc, c).first?.lineweight, 0.25)
        // Property rules and hiding.
        ed.doc.entities[ed.doc.entityIndex(c)!].props["phase"] = "demo"
        await ed.run("GFILTERS A HideDemo * phase = demo hide")
        XCTAssertTrue(strokes(ed.doc, c).isEmpty)
        await ed.run("GFILTERS D HideDemo")
        XCTAssertFalse(strokes(ed.doc, c).isEmpty)
        await ed.run("GFILTERS R Demolished")
        XCTAssertEqual(strokes(ed.doc, a).first?.lineweight, 0.25)
        XCTAssertEqual(GraphicStyles.filters(ed.doc).count, 1)
        // Numeric comparison.
        ed.doc.entities[ed.doc.entityIndex(b)!].lineweight = 0.5
        GraphicStyles.setFilters([GraphicStyles.FilterRule(name: "Heavy", field: "lineweight", op: ">=", value: "0.5", override: GraphicOverride(halftone: true))], doc: &ed.doc)
        XCTAssertEqual(strokes(ed.doc, b).first?.lineweight ?? 1, 0.18, "halftone thins lines")
        XCTAssertNotEqual(strokes(ed.doc, b).first?.color, ed.doc.layer(named: "Existing")?.color)
    }
}

/// Equality constraint dimensions (ANN-046).
@MainActor
final class DraftEqualityDimensionTests: XCTestCase {
    func x(_ ed: Editor, _ id: EntityID) -> Double { if case .line(let l)? = ed.doc.entity(id)?.geometry { return (l.a.x + l.b.x) / 2 }; return .nan }

    func testEQChainKeepsEqualSpacing() async throws {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 1000))))
        let b = ed.doc.add(.line(LineGeom(Vec2(300, 0), Vec2(300, 1000))))
        let c = ed.doc.add(.line(LineGeom(Vec2(1000, 0), Vec2(1000, 1000))))
        await ed.run("EQDIM C #\(a),#\(b),#\(c)  H 0,1500")
        XCTAssertEqual(x(ed, b), 500, accuracy: 1e-9)
        let dims = ed.doc.entities.filter { $0.props[EqualityDimensions.groupProp] != nil }
        XCTAssertEqual(dims.count, 2)
        func texts() -> [String] {
            DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).filter { e in dims.contains { $0.id == e.id } }.flatMap(\.items)
                .compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        }
        XCTAssertEqual(texts(), ["EQ", "EQ"])
        // Moving an anchor re-spaces the middle object and the dimensions follow.
        await ed.run("MOVE #\(c)  0,0 1000,0")
        XCTAssertEqual(x(ed, c), 2000, accuracy: 1e-9)
        XCTAssertEqual(x(ed, b), 1000, accuracy: 1e-9)
        for d in ed.doc.entities where d.props[EqualityDimensions.groupProp] != nil {
            if case .dimension(let g) = d.geometry { XCTAssertEqual(DimensionRenderer.measurement(g), 1000, accuracy: 1e-9) }
        }
        // Moving the middle object snaps it back.
        await ed.run("MOVE #\(b)  0,0 200,0")
        XCTAssertEqual(x(ed, b), 1000, accuracy: 1e-9)
        // Toggle shows values; persisted in .archi.
        await ed.run("EQDIM T #\(dims[0].id)")
        XCTAssertEqual(texts(), ["1000", "1000"])
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(EqualityDimensions.groups(back).count, 1)
        // Remove the constraint: the middle object is free again.
        await ed.run("EQDIM R #\(dims[0].id)")
        await ed.run("MOVE #\(b)  0,0 200,0")
        XCTAssertEqual(x(ed, b), 1200, accuracy: 1e-9)
        // Deleting a member dissolves a chain.
        ed.undo(); ed.undo()
        XCTAssertEqual(EqualityDimensions.groups(ed.doc).count, 1)
        await ed.run("ERASE #\(a) ")
        XCTAssertTrue(EqualityDimensions.groups(ed.doc).isEmpty)
    }
}

/// Parametric block constraints (BLK-027).
@MainActor
final class DraftBlockConstraintTests: XCTestCase {
    func testBlockConstraintsDriveReferencesAndPersist() async throws {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 ")
        await ed.run("BLOCK BAR 0,0 ALL ")
        let insID = ed.doc.entities.last!.id
        await ed.run("BEDIT BAR")
        guard let line = BlockEditing.blockEditContent(ed.doc).first?.id else { return XCTFail("block editor empty") }
        var cs = ConstraintSet.load(ed.doc)
        cs.constraints.append(GeoConstraint(id: cs.nextID, kind: .fixed, refs: [CRef(line, 0)], anchor: Vec2(0, 0))); cs.nextID += 1
        cs.constraints.append(GeoConstraint(id: cs.nextID, kind: .horizontal, refs: [CRef(line)])); cs.nextID += 1
        cs.constraints.append(GeoConstraint(id: cs.nextID, kind: .length, refs: [CRef(line)], value: 100, name: "d1")); cs.nextID += 1
        cs.save(&ed.doc)
        await ed.run("BCLOSE S")
        XCTAssertNil(BlockEditing.editingBlock(ed.doc))
        XCTAssertTrue(ConstraintSet.load(ed.doc).constraints.isEmpty, "block constraints leave the drawing")
        XCTAssertEqual(BlockConstraints.load("BAR", doc: ed.doc)?.constraints.count, 3)
        let ps = DynamicBlocks.params("BAR", ed.doc)
        XCTAssertEqual(ps.map(\.name), ["d1"]); XCTAssertEqual(ps.first?.kind, .constraint)
        XCTAssertEqual(ps.first?.base ?? 0, 100, accuracy: 1e-9)
        // Setting the parameter on a reference re-solves the block for that reference only.
        await ed.run("INSERT BAR 0,500 1 1 0")
        let other = ed.doc.entities.last!.id
        await ed.run("DYNPROP #\(insID)  250")
        func length(_ id: EntityID) -> Double {
            let pts = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).filter { $0.id == id }.flatMap(\.items)
                .flatMap { i -> [Vec2] in if case .stroke(let p, _, _) = i { return p }; return [] }
            guard let a = pts.first, let b = pts.last else { return 0 }
            return a.distance(to: b)
        }
        XCTAssertEqual(length(insID), 250, accuracy: 1e-4)
        XCTAssertEqual(length(other), 100, accuracy: 1e-4)
        // Explode gives the solved geometry.
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(DynamicBlocks.params("BAR", back).first?.name, "d1")
        await ed.run("EXPLODE #\(insID) ")
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("not exploded") }
        XCTAssertEqual(l.a.distance(to: l.b), 250, accuracy: 1e-4)
        XCTAssertEqual(l.a.y, l.b.y, accuracy: 1e-6)
        // Editing again restores the constraints on the editor objects.
        await ed.run("BEDIT BAR")
        let restored = ConstraintSet.load(ed.doc)
        XCTAssertEqual(restored.constraints.count, 3)
        let ids = Set(BlockEditing.blockEditContent(ed.doc).map(\.id))
        XCTAssertTrue(restored.constraints.allSatisfy { $0.refs.allSatisfy { ids.contains($0.entity) } })
        await ed.run("BCLOSE D")
    }
}
