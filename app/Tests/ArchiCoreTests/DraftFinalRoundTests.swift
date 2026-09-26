// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Floor surface patterns in plan (ANN-072) and exact image contrast above 50 (DRW-086).
@MainActor
final class DraftFinalRoundTests: XCTestCase {
    func floorDoc() -> (ArchiDocument, EntityID) {
        var d = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        let slab = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 200)), material: "Stone")
        return (d, slab)
    }
    func hatch(_ ed: Editor) -> (Entity, HatchGeom)? {
        guard let e = ed.doc.entities.first(where: FloorPatterns.isFloorPattern), case .hatch(let h) = e.geometry else { return nil }
        return (e, h)
    }

    func testFloorPatternFollowsSlabWallsAndMaterial() async {
        let ed = Editor()
        let (d, slab) = floorDoc()
        ed.doc = d
        XCTAssertTrue(MaterialPatterns.setPattern("Stone", kind: .surface, pattern: "SQUARE", doc: &ed.doc))
        await ed.run("FLOORPATTERN A ")
        guard let (e, h) = hatch(ed) else { return XCTFail("no floor pattern") }
        XCTAssertEqual(e.props[FloorPatterns.prop], String(slab))
        XCTAssertEqual(e.props["level"], String(ed.doc.element(slab)!.level))
        XCTAssertEqual(h.pattern, "SQUARE")
        XCTAssertEqual(GeometryOps.area(.hatch(h), doc: nil)!, 24_000_000, accuracy: 1)
        // Draws pattern lines inside the slab only.
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel)).first { $0.id == e.id }?.items ?? []
        XCTAssertGreaterThan(items.count, 10)
        XCTAssertTrue(items.allSatisfy { if case .stroke(let p, _, _) = $0 { return p.allSatisfy { $0.x > -1 && $0.x < 6001 && $0.y > -1 && $0.y < 4001 } }; return true })
        // A wall across the floor is cut out of the pattern.
        ed.transaction("wall") { $0.addElement(.wall(WallGeom(start: Vec2(3000, 0), end: Vec2(3000, 4000), thickness: 200, height: 3000))) }
        let (_, h2) = hatch(ed)!
        XCTAssertEqual(GeometryOps.area(.hatch(h2), doc: nil)!, 24_000_000 - 200 * 4000, accuracy: 2000)
        // Changing the slab boundary updates the pattern area.
        ed.transaction("grow") { doc in
            guard let i = doc.elementIndex(slab), case .slab(var s) = doc.elements[i].geometry else { return }
            s.boundary = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 4000), Vec2(0, 4000)]; doc.elements[i].geometry = .slab(s)
        }
        XCTAssertEqual(GeometryOps.area(.hatch(hatch(ed)!.1), doc: nil)!, 32_000_000 - 200 * 4000, accuracy: 2000)
        // Changing the material's surface pattern updates it; removing the pattern hides it.
        ed.transaction("pat") { _ = MaterialPatterns.setPattern("Stone", kind: .surface, pattern: "AR-PARQ1", doc: &$0) }
        XCTAssertEqual(hatch(ed)!.1.pattern, "AR-PARQ1")
        ed.transaction("none") { _ = MaterialPatterns.setPattern("Stone", kind: .surface, pattern: nil, doc: &$0) }
        XCTAssertTrue(hatch(ed)!.1.loops.isEmpty)
        // Survives a save / reopen and is removed with its slab.
        let data = try! JSONEncoder().encode(ed.doc)
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertTrue(back.entities.contains(where: FloorPatterns.isFloorPattern))
        ed.transaction("delete") { $0.remove(ids: [slab]) }
        XCTAssertNil(hatch(ed))
    }

    func testFloorPatternRemoveOption() async {
        let ed = Editor()
        let (d, slab) = floorDoc()
        ed.doc = d
        _ = MaterialPatterns.setPattern("Stone", kind: .surface, pattern: "NET", doc: &ed.doc)
        await ed.run("FLOORPATTERN S #\(slab) \n")
        XCTAssertNotNil(hatch(ed))
        await ed.run("FLOORPATTERN S #\(slab) \n")
        XCTAssertEqual(ed.doc.entities.filter(FloorPatterns.isFloorPattern).count, 1, "no duplicates")
        await ed.run("FLOORPATTERN R #\(slab) \n")
        XCTAssertNil(hatch(ed))
    }

    func testImageContrastAboveFiftyLookupTables() {
        let a = ImageDisplay.Adjustment(brightness: 60, contrast: 75, fade: 10)
        let bg = RGBA(1, 1, 1)
        XCTAssertTrue(ImageDisplay.needsPixelProcessing(a))
        XCTAssertFalse(ImageDisplay.needsPixelProcessing(ImageDisplay.Adjustment(contrast: 40)))
        let lut = ImageDisplay.lookupTables(a, background: bg)
        XCTAssertEqual(lut.count, 3); XCTAssertEqual(lut[0].count, 256)
        for v in [0, 40, 128, 200, 255] {
            let x = Double(v) / 255
            let ref = ImageDisplay.adjusted(RGBA(x, x, x), a, background: bg)
            XCTAssertEqual(Double(lut[0][v]) / 255, ref.r, accuracy: 0.5 / 255 + 1e-9)
        }
        // Contrast 75 stretches around mid grey: dark gets darker, light gets lighter (before brightness/fade).
        let c = ImageDisplay.lookupTables(ImageDisplay.Adjustment(contrast: 75), background: bg)[0]
        XCTAssertLessThan(c[64], 64); XCTAssertGreaterThan(c[192], 192); XCTAssertEqual(c[0], 0); XCTAssertEqual(c[255], 255)
        // Pixel buffers: RGBA straight and premultiplied.
        var px: [UInt8] = [64, 128, 192, 255, 10, 20, 30, 0]
        ImageDisplay.apply(ImageDisplay.Adjustment(contrast: 75), background: bg, to: &px)
        XCTAssertEqual(Array(px[0..<4]), [c[64], c[128], c[192], 255])
        var pm: [UInt8] = [32, 64, 96, 128]
        ImageDisplay.apply(ImageDisplay.Adjustment(contrast: 75), background: bg, to: &pm, premultiplied: true)
        XCTAssertEqual(pm[3], 128); XCTAssertEqual(Double(pm[0]), Double((Int(c[64]) * 128 + 127) / 255), accuracy: 1)
        // Renderers with pixel access switch off the veils so the adjustment is not applied twice.
        var doc = ArchiDocument()
        var e = Entity(id: 1, layer: "0", geometry: .image(ImageGeom(path: "/tmp/a.png", origin: .zero, size: Vec2(100, 50))))
        ImageDisplay.setAdjustment(ImageDisplay.Adjustment(brightness: 70, contrast: 80), on: &e)
        doc.entities.append(e)
        guard case .image(let im) = e.geometry else { return XCTFail() }
        XCTAssertEqual(ImageDisplay.adjustment(for: im, doc: doc)?.contrast, 80)
        XCTAssertGreaterThan(ImageDisplay.items(e, im, doc: doc, options: DrawOptions(), color: RGBA(1, 1, 1)).count, 1)
        ImageDisplay.rendererAppliesPixels = true
        defer { ImageDisplay.rendererAppliesPixels = false }
        XCTAssertEqual(ImageDisplay.items(e, im, doc: doc, options: DrawOptions(), color: RGBA(1, 1, 1)).count, 1)
    }
}
