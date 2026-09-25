// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Cross-area fixes made while integrating round 3 (run mirroring and footprints, CONSTRAINTBAR, LAYERSTATE options).
@MainActor
final class IntegrationRound3Tests: XCTestCase {
    func testMirrorFlipsRunPath() {
        let run = ComponentGeom(category: "MEP", position: Vec2(1000, 0), rotation: .pi / 2, size: Vec3(100, 100, 100),
                                family: "pipe", path: [.zero, Vec2(2000, 0), Vec2(2000, 1000)])
        let before = run.worldPath
        let t = Transform2D.mirror(Vec2(0, 0), Vec2(0, 1)) // mirror about the Y axis
        guard case .component(let m) = CommandHelpers.transform(.component(run), t) else { return XCTFail() }
        let after = m.worldPath
        XCTAssertEqual(after.count, before.count)
        for (a, b) in zip(after, before) {
            XCTAssertEqual(a.x, -b.x, accuracy: 1e-6); XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
        }
        // A plain move still carries the path.
        guard case .component(let mv) = CommandHelpers.transform(.component(run), .translation(Vec2(10, 20))) else { return XCTFail() }
        for (a, b) in zip(mv.worldPath, before) { XCTAssertEqual(a.x, b.x + 10, accuracy: 1e-6); XCTAssertEqual(a.y, b.y + 20, accuracy: 1e-6) }
    }

    func testRunFootprintFollowsPath() {
        var doc = ArchiDocument()
        let run = ComponentGeom(category: "MEP", position: Vec2(0, 0), size: Vec3(100, 100, 100), family: "duct", path: [.zero, Vec2(5000, 0)])
        doc.addElement(.component(run))
        let f = CommandHelpers.footprint(doc.elements[0], doc: doc)
        XCTAssertEqual(f.count, 2); XCTAssertEqual(f.last?.x ?? 0, 5000, accuracy: 1e-9)
    }

    func testConstraintBarToggles() async {
        let ed = Editor()
        await ed.run("CONSTRAINTBAR Show")
        XCTAssertTrue(ConstraintGlyphs.isOn(ed.doc))
        await ed.run("CONSTRAINTBAR Toggle")
        XCTAssertFalse(ConstraintGlyphs.isOn(ed.doc))
        XCTAssertNotNil(CommandRegistry.shared.commands["CONSTRAINTLIST"])
    }

    func testLayerStateOptionsShared() async {
        let ed = Editor()
        await ed.run("LAYER New A-WALL ;")
        try? await LayerToolCommands.runLayerState("?", ed)
        await ed.run("LAYERSTATE Save S1 ;")
        XCTAssertNotNil(LayerStates.named("S1", ed.doc))
    }
}
