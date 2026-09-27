// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class AnalysisThermalBridgeTests: XCTestCase {
    func house() -> ArchiDocument {
        var d = ArchiDocument()
        d.levels = [Level(id: 0, name: "GF", elevation: 0), Level(id: 1, name: "1F", elevation: 3000)]
        let pts = [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)]
        var firstWall: EntityID = 0
        for lv in [0, 1] {
            for i in 0..<4 {
                let id = d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300, height: 3000)), level: lv)
                d.elements[d.elementIndex(id)!].props["isExternal"] = "1"
                if lv == 0 && i == 0 { firstWall = id }
            }
        }
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: firstWall, offset: 3000, width: 1200, height: 1400, sill: 900)), level: 0)
        d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), level: 1)
        let b = d.addElement(.slab(SlabGeom(boundary: [Vec2(2000, -1500), Vec2(6000, -1500), Vec2(6000, 200), Vec2(2000, 200)], thickness: 200)), level: 1)
        d.elements[d.elementIndex(b)!].props["kind"] = "balcony"
        d.addElement(.column(ColumnGeom(position: Vec2(5000, 8000), width: 300, depth: 300, height: 3000)), level: 0)
        return d
    }

    func testJunctionsLengthsAndPsi() {
        let d = house()
        let s = ThermalBridges.summary(d)
        let byKind = Dictionary(uniqueKeysWithValues: s.byKind.map { ($0.kind, $0.length) })
        XCTAssertEqual(byKind["corner"] ?? 0, 24, accuracy: 1e-6, "4 corners × 2 storeys × 3 m")
        XCTAssertNil(byKind["corner-reentrant"])
        XCTAssertEqual(byKind["ground-floor"] ?? 0, 36, accuracy: 1e-6)
        XCTAssertEqual(byKind["roof-eaves"] ?? 0, 36, accuracy: 1e-6)
        XCTAssertEqual(byKind["intermediate-floor"] ?? 0, 36, accuracy: 0.5)
        XCTAssertEqual(byKind["balcony"] ?? 0, 4, accuracy: 0.5)
        XCTAssertEqual(byKind["window-reveal"] ?? 0, 5.2, accuracy: 1e-9)
        XCTAssertEqual(byKind["column"] ?? 0, 3, accuracy: 1e-9)
        let expected: Double = 24 * 0.10 + 36 * 0.60 + 36 * 0.50 + 36 * 0.40 + 4 * 0.90 + 5.2 * 0.10 + 3 * 0.30
        XCTAssertEqual(s.htb, expected, accuracy: 0.5)
        XCTAssertGreaterThan(s.transmission, 0)
        // Overrides.
        var d2 = d; d2.setVariable("PSI:balcony", "0.1")
        XCTAssertLessThan(ThermalBridges.summary(d2).htb, s.htb - 2.5)
    }

    func testReentrantCorner() {
        var d = ArchiDocument()
        // L-shaped plan: one re-entrant corner.
        let p = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 4000), Vec2(4000, 4000), Vec2(4000, 8000), Vec2(0, 8000)]
        for i in 0..<p.count {
            let id = d.addElement(.wall(WallGeom(start: p[i], end: p[(i + 1) % p.count], thickness: 300, height: 2800)), level: 0)
            d.elements[d.elementIndex(id)!].props["isExternal"] = "1"
        }
        d.addElement(.slab(SlabGeom(boundary: p, thickness: 250)), level: 0)
        let b = ThermalBridges.detect(d)
        XCTAssertEqual(b.filter { $0.kind == "corner" }.count, 5)
        XCTAssertEqual(b.filter { $0.kind == "corner-reentrant" }.count, 1)
        XCTAssertEqual(b.first { $0.kind == "corner-reentrant" }?.location.distance(to: Vec2(4000, 4000)) ?? 1e9, 0, accuracy: 1)
    }

    @MainActor func testCommand() async {
        let ed = Editor()
        ed.doc = house()
        let out = await ed.run("THERMALBRIDGES ")
        XCTAssertTrue(out.joined(separator: "\n").contains("Balcony slab"), out.joined(separator: "\n"))
        XCTAssertFalse(ed.selection.isEmpty)
    }
}
