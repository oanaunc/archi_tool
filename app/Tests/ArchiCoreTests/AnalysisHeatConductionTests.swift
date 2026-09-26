// Oanarina Archi Tool — GPL-3.0-or-later
// EN ISO 10211 two-dimensional heat conduction and numerical ψ values (ANL-026).
import XCTest
@testable import ArchiCore

final class AnalysisHeatConductionTests: XCTestCase {
    /// Rectangle 1 m × 2 m, λ = 1, top side at 20 °C and the other sides at 0 °C: the analytic Fourier-series
    /// solution is the EN ISO 10211 Annex C benchmark; the standard requires ≤ 0.1 K deviation.
    func testRectangleMatchesAnalyticSolution() {
        let a = 1.0, b = 2.0
        let xs = HeatConduction2D.grid([-0.05, 0, a, a + 0.05], maxStep: 0.02)
        let ys = HeatConduction2D.grid([-0.05, 0, b, b + 0.05], maxStep: 0.02)
        let m = HeatConduction2D.Model(xs: xs, ys: ys, environments: [.init(temperature: 0, surfaceResistance: 0), .init(temperature: 20, surfaceResistance: 0)]) { p in
            if p.x > 0, p.x < a, p.y > 0, p.y < b { return .solid(1) }
            if p.y > b, p.x > 0, p.x < a { return .environment(1) }
            if p.y > b { return .adiabatic }
            return .environment(0)
        }
        let r = HeatConduction2D.solve(m)
        XCTAssertTrue(r.converged)
        func exact(_ x: Double, _ y: Double) -> Double {
            var t = 0.0
            for n in stride(from: 1, through: 199, by: 2) {
                let k = Double(n) * .pi / a
                // sinh(k y)/sinh(k b) computed stably.
                let ratio = exp(k * (y - b)) * (1 - exp(-2 * k * y)) / (1 - exp(-2 * k * b))
                t += 4 * 20 / (Double(n) * .pi) * sin(k * x) * ratio
            }
            return t
        }
        var worst = 0.0
        for px in [0.1, 0.25, 0.5, 0.75, 0.9] {
            for py in [0.25, 0.5, 1.0, 1.5, 1.75, 1.9] {
                let c = r.cellCenter(at: Vec2(px, py))!
                let got = r.temperature(at: c)!
                worst = max(worst, abs(got - exact(c.x, c.y)))
            }
        }
        XCTAssertLessThan(worst, 0.1, "max deviation \(worst) K")
        // Energy balance: heat entering from the hot side leaves through the cold sides.
        XCTAssertEqual(r.heatFlow[0] + r.heatFlow[1], 0, accuracy: 1e-6 * abs(r.heatFlow[1]))
    }

    let brick = [JunctionPsi.Layer(0.30, 0.8)]
    let insulated = [JunctionPsi.Layer(0.015, 0.7), JunctionPsi.Layer(0.12, 0.035), JunctionPsi.Layer(0.20, 2.0), JunctionPsi.Layer(0.015, 0.7)]

    func testPlainWallHasNoThermalBridge() {
        for l in [brick, insulated] {
            let r = JunctionPsi.plainWall(l)
            XCTAssertTrue(r.converged)
            XCTAssertEqual(r.l2d, r.u, accuracy: 1e-6)
            XCTAssertEqual(r.psiExternal, 0, accuracy: 1e-6)
        }
    }

    func testCornerPsi() {
        let c = JunctionPsi.corner(brick)
        XCTAssertTrue(c.converged)
        // External dimensions over-count the corner: ψe < 0; internal dimensions under-count it: ψi > 0.
        XCTAssertLessThan(c.psiExternal, -0.05)
        XCTAssertGreaterThan(c.psiInternal, 0.05)
        XCTAssertEqual(c.psiInternal - c.psiExternal, 2 * c.u * 0.30, accuracy: 1e-9)
        XCTAssertLessThan(c.fRsi, 1); XCTAssertGreaterThan(c.fRsi, 0.5)
        // Leg length beyond 1 m does not change ψ (cut-off planes far enough).
        XCTAssertEqual(JunctionPsi.corner(brick, leg: 1.5, maxCell: 0.015).psiExternal, JunctionPsi.corner(brick, leg: 1.0, maxCell: 0.015).psiExternal, accuracy: 0.005)
        // Re-entrant corner of the same wall: ψe > 0.
        let re = JunctionPsi.corner(brick, reentrant: true)
        XCTAssertGreaterThan(re.psiExternal, 0)
        // Well-insulated walls have small corner ψ values.
        XCTAssertLessThan(abs(JunctionPsi.corner(insulated).psiExternal), 0.1)
    }

    func testFloorEdgeAndBalcony() {
        let edge = JunctionPsi.floorEdge(wall: insulated, slabThickness: 0.2, slabLambda: 2.3)
        let balcony = JunctionPsi.floorEdge(wall: insulated, slabThickness: 0.2, slabLambda: 2.3, balcony: 1.2)
        XCTAssertTrue(edge.converged); XCTAssertTrue(balcony.converged)
        XCTAssertLessThan(abs(edge.psiExternal), 0.15, "continuous external insulation: small ψ")
        XCTAssertGreaterThan(balcony.psiExternal, 0.4, "a cantilevered concrete balcony is a major bridge")
        XCTAssertLessThan(balcony.fRsi, edge.fRsi)
    }

    func testThermalBridgesUseNumericPsiOnRequest() {
        var d = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)]
        for i in 0..<4 {
            let id = d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300, height: 3000)), level: 0)
            d.elements[d.elementIndex(id)!].props["isExternal"] = "1"
            d.elements[d.elementIndex(id)!].material = "Brick"
        }
        d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), level: 0)
        let plain = ThermalBridges.detect(d).first { $0.kind == "corner" }!
        XCTAssertEqual(plain.psi, ThermalBridges.defaults["corner"]!)
        d.setVariable("PSIMETHOD", "ISO10211")
        let num = ThermalBridges.detect(d).first { $0.kind == "corner" }!
        XCTAssertNotEqual(num.psi, plain.psi)
        XCTAssertLessThan(num.psi, 0, "external-dimension corner ψ of a plain masonry wall is negative")
        d.setVariable("PSI:corner", "0.2")
        XCTAssertEqual(ThermalBridges.detect(d).first { $0.kind == "corner" }!.psi, 0.2, "explicit overrides win")
    }
}
