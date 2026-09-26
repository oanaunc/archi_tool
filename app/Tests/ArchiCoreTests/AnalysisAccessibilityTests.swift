// Oanarina Archi Tool — GPL-3.0-or-later
// Colour-blind safety (SYS-030): CVD simulation, CIEDE2000, layer checks and the Okabe–Ito fix.
import XCTest
@testable import ArchiCore

final class AnalysisAccessibilityTests: XCTestCase {
    func testCIEDE2000ReferenceValues() {
        // Sharma, Wu & Dalal (2005) test data, pairs 1, 7 and 17.
        XCTAssertEqual(ColourAccessibility.deltaE2000((50, 2.6772, -79.7751), (50, 0, -82.7485)), 2.0425, accuracy: 1e-4)
        XCTAssertEqual(ColourAccessibility.deltaE2000((50, 0, 0), (50, -1, 2)), 2.3669, accuracy: 1e-4)
        XCTAssertEqual(ColourAccessibility.deltaE2000((50, 2.5, 0), (73, 25, -18)), 27.1492, accuracy: 1e-4)
        let white = ColourAccessibility.lab(RGBA(1, 1, 1))
        XCTAssertEqual(white.L, 100, accuracy: 1e-3); XCTAssertEqual(white.a, 0, accuracy: 1e-3); XCTAssertEqual(white.b, 0, accuracy: 1e-3)
    }

    func testSimulationMergesRedAndGreenForDeuteranopia() {
        let red = RGBA(0.8, 0.2, 0.1), green = RGBA(0.45, 0.55, 0.1)
        XCTAssertGreaterThan(ColourAccessibility.difference(red, green), 25)
        XCTAssertLessThan(ColourAccessibility.difference(red, green, .deuteranopia), ColourAccessibility.difference(red, green) / 2)
        // Greys are unchanged by every deficiency.
        for d in ColourAccessibility.Deficiency.allCases {
            let g = ColourAccessibility.simulate(RGBA(0.5, 0.5, 0.5), d)
            XCTAssertEqual(g.r, 0.5, accuracy: 0.01); XCTAssertEqual(g.g, 0.5, accuracy: 0.01); XCTAssertEqual(g.b, 0.5, accuracy: 0.01)
        }
    }

    func testLayerCheckAndFix() async {
        var d = ArchiDocument()
        d.layers = [Layer(name: "0", color: RGBA(1, 1, 1)), Layer(name: "Existing", color: RGBA(1, 0, 0)), Layer(name: "New", color: RGBA(0, 0.8, 0)),
                    Layer(name: "Dim", color: RGBA(0.13, 0.13, 0.15))]
        let bg = RGBA(0.12, 0.12, 0.13)
        let issues = ColourAccessibility.check(d, background: bg)
        XCTAssertTrue(issues.contains { Set($0.layers) == ["Existing", "New"] && $0.deficiency != nil }, issues.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(issues.contains { $0.layers == ["Dim"] && $0.deficiency == nil })
        let changes = ColourAccessibility.fix(&d, background: bg)
        XCTAssertFalse(changes.isEmpty)
        XCTAssertEqual(d.layer(named: "0")?.color, RGBA(1, 1, 1), "layers without conflicts keep their colour")
        XCTAssertTrue(ColourAccessibility.check(d, background: bg).isEmpty, ColourAccessibility.check(d, background: bg).map(\.message).joined(separator: "\n"))
        // Command with undo.
        let ed = await Editor()
        await MainActor.run { ed.doc.layers = [Layer(name: "A", color: RGBA(1, 0, 0)), Layer(name: "B", color: RGBA(0, 0.8, 0))] }
        await ed.run("COLORBLINDCHECK Dark Yes")
        let fixed = await MainActor.run { ed.doc.layer(named: "A")?.color != RGBA(1, 0, 0) || ed.doc.layer(named: "B")?.color != RGBA(0, 0.8, 0) }
        XCTAssertTrue(fixed)
        await MainActor.run { ed.undo() }
        let restored = await MainActor.run { ed.doc.layer(named: "A")?.color }
        XCTAssertEqual(restored, RGBA(1, 0, 0))
    }
}
