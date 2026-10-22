// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class ViewportFramingTests: XCTestCase {
    func drawing() -> ArchiDocument {
        var doc = ArchiDocument()
        doc.levels.append(Level(id: 99, name: "Remote storey", elevation: 10000))
        doc.levels.append(Level(id: 98, name: "Empty storey", elevation: 20000))
        _ = doc.addElement(.wall(WallGeom(start: Vec2(100000, 200000), end: Vec2(105000, 200000), thickness: 200, height: 3000)))
        _ = doc.addElement(.wall(WallGeom(start: Vec2(-500000, -500000), end: Vec2(-495000, -500000), thickness: 200, height: 3000)), level: 99)
        doc.ensureLayer("NoPlot")
        let index = doc.layers.firstIndex { $0.name == "NoPlot" }!
        doc.layers[index].plot = false
        _ = doc.add(.line(LineGeom(Vec2(-900000, 0), .zero)), layer: "NoPlot")
        return doc
    }

    func testBoundsUsePlottedLevelInsteadOfWholeDrawing() {
        let doc = drawing()
        let vp = Viewport(origin: Vec2(24, 62), size: Vec2(382, 221), viewCenter: .zero, scale: 200, level: doc.currentLevel)
        let bounds = ViewportFraming.bounds(doc: doc, viewport: vp)
        XCTAssertEqual(bounds.center.x, 102500, accuracy: 1)
        XCTAssertEqual(bounds.center.y, 200000, accuracy: 1)
        XCTAssertGreaterThan(bounds.center.distance(to: GeometryOps.bounds(of: doc).center), 100000)
        let fitted = ViewportFraming.fitted(vp, bounds: bounds)!
        XCTAssertEqual(fitted.origin, vp.origin)
        XCTAssertEqual(fitted.size, vp.size)
        XCTAssertEqual(fitted.level, vp.level)
        XCTAssertLessThanOrEqual(bounds.width / fitted.scale, vp.size.x * 0.9 + 1e-6)
        XCTAssertLessThanOrEqual(bounds.height / fitted.scale, vp.size.y * 0.9 + 1e-6)
        XCTAssertNil(ViewportFraming.fitted(vp, bounds: .empty))
    }

    func testBoundsRespectViewportFreeze() {
        var doc = drawing()
        doc.ensureLayer("Distant")
        _ = doc.add(.line(LineGeom(.zero, Vec2(5000, 5000))), layer: "Distant")
        let vp = Viewport(origin: .zero, size: Vec2(100, 100), viewCenter: .zero, level: doc.currentLevel)
        doc.layouts[0].viewports = [vp]
        _ = ViewportLayers.set(&doc, patterns: "Distant", frozen: true, layout: doc.layouts[0].name, viewports: [0])
        let bounds = ViewportFraming.bounds(doc: doc, viewport: vp, layoutIndex: 0, index: 0)
        XCTAssertEqual(bounds.center.x, 102500, accuracy: 1)
    }

    @MainActor private func feed(_ session: EngineSession, _ line: String, _ answers: [String]) async throws {
        func params(_ key: String, _ value: String) -> EngineJSON {
            var p = EngineObject(); p.set(key, .string(value)); return p.json
        }
        var state = try await session.call("command.run", params("line", line))
        for answer in answers where state["active"]?.boolValue == true {
            state = try await session.call("input.text", params("text", answer))
        }
        if state["active"]?.boolValue == true { _ = try await session.call("input.key", params("key", "Escape")) }
    }

    @MainActor func testMviewFitCommandUndoPersistenceAndLock() async throws {
        // Construct the engine directly: XCTestCase's no-argument initializer is macOS-only.
        let registry = CommandRegistry()
        EngineSession.registerPortableAppCommands(registry)
        EngineSession.registerToolCommands(registry)
        let session = EngineSession(editor: Editor(registry: registry), emit: { _ in })
        session.editor.doc = drawing()
        try await feed(session, "MVIEW", ["24,62", "406,283", "1:200", "Plan", "Plan"])
        XCTAssertEqual(session.editor.doc.layouts[0].viewports.count, 1)
        let created = session.editor.doc.layouts[0].viewports[0]
        XCTAssertEqual(created.viewCenter.x, 102500, accuracy: 1)
        XCTAssertEqual(created.scale, 200)
        try await feed(session, "MVIEWPOLY", ["24,62", "406,62", "406,283", "", "200"])
        XCTAssertEqual(session.editor.doc.layouts[0].viewports.count, 2)
        XCTAssertEqual(session.editor.doc.layouts[0].viewports[1].viewCenter.x, 102500, accuracy: 1)
        session.editor.doc.layouts[0].viewports[0].viewCenter = .zero
        let before = session.editor.doc.layouts[0].viewports[0]
        try await feed(session, "VPF", ["1"])
        let fitted = session.editor.doc.layouts[0].viewports[0]
        XCTAssertEqual(fitted.viewCenter.x, 102500, accuracy: 1)
        XCTAssertNotEqual(fitted.scale, before.scale)
        let restored = try ArchiFile.decode(ArchiFile.encode(session.editor.doc))
        XCTAssertEqual(restored.layouts[0].viewports[0], fitted)
        session.editor.undo()
        XCTAssertEqual(session.editor.doc.layouts[0].viewports[0], before)
        EngineViewports.setLocked(&session.editor.doc, 0, 0, true)
        try await feed(session, "VPFIT", ["1"])
        XCTAssertEqual(session.editor.doc.layouts[0].viewports[0], before)
        XCTAssertTrue(session.editor.log.contains { $0.contains("locked") })
        EngineViewports.setLocked(&session.editor.doc, 0, 0, false)
        session.editor.doc.layouts[0].viewports[0].level = 98
        let empty = session.editor.doc.layouts[0].viewports[0]
        try await feed(session, "VPFIT", ["1"])
        XCTAssertEqual(session.editor.doc.layouts[0].viewports[0], empty)
        XCTAssertTrue(session.editor.log.contains { $0.contains("No plotted content") })
    }
}
