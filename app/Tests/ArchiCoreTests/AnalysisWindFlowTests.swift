// Oanarina Archi Tool — GPL-3.0-or-later
// Built-in wind flow solver (ANL-028): analytic verification and pedestrian-level study.
import XCTest
@testable import ArchiCore

final class AnalysisWindFlowTests: XCTestCase {
    /// Force-driven channel flow must reproduce the analytic Poiseuille parabola.
    func testPoiseuilleProfileMatchesAnalyticSolution() {
        let h = 21
        var s = WindFlow.Settings()
        s.xBoundary = .periodic; s.yBoundary = .wall
        s.tau = 0.8; s.smagorinsky = 0; s.force = Vec2(1e-6, 0)
        s.maxIterations = 30_000; s.tolerance = 1e-9; s.checkEvery = 50
        let f = WindFlow.solve(WindFlow.Lattice(nx: 4, ny: h), s)
        XCTAssertTrue(f.stable)
        XCTAssertTrue(f.converged, "iterations \(f.iterations)")
        let peak = WindFlow.poiseuille(y: h / 2, height: h, force: 1e-6, tau: 0.8)
        for y in 0..<h {
            let exact = WindFlow.poiseuille(y: y, height: h, force: 1e-6, tau: 0.8)
            XCTAssertEqual(f.velocity(2, y).x, exact, accuracy: 0.01 * peak, "row \(y)")
            XCTAssertEqual(f.velocity(2, y).y, 0, accuracy: 1e-6 * peak + 1e-15)
        }
    }

    /// Uniform flow without obstacles stays uniform; a block produces a sheltered wake and side speed-ups,
    /// and the volume flux is conserved through the channel.
    func testFlowAroundABlock() {
        var lat = WindFlow.Lattice(nx: 100, ny: 50)
        for y in 20..<30 { for x in 25..<35 { lat[x, y] = true } }
        var s = WindFlow.Settings()
        s.inletSpeed = 0.06; s.tau = 0.6; s.smagorinsky = 0.1
        s.averageFrom = 2000; s.maxIterations = 3200; s.checkEvery = 200
        let f = WindFlow.solve(lat, s)
        XCTAssertTrue(f.stable)
        let u = s.inletSpeed
        XCTAssertLessThan(f.speed(39, 25), 0.5 * u, "sheltered wake behind the block")
        var side = 0.0
        for x in 20...40 { for y in 30..<50 { side = max(side, f.speed(x, y)) } }
        XCTAssertGreaterThan(side, 1.05 * u, "speed-up beside the block")
        func flux(_ x: Int) -> Double { (0..<50).reduce(0.0) { $0 + (f.isSolid(x, $1) ? 0 : f.velocity(x, $1).x * f.rho[$1 * 100 + x]) } }
        XCTAssertEqual(flux(70), flux(10), accuracy: 0.05 * flux(10))
        // Empty channel: uniform.
        var e = s; e.averageFrom = nil; e.maxIterations = 400
        let free = WindFlow.solve(WindFlow.Lattice(nx: 40, ny: 20), e)
        XCTAssertEqual(free.speed(20, 10), u, accuracy: 0.02 * u)
        XCTAssertEqual(free.speed(20, 0), u, accuracy: 0.02 * u, "free-slip sides")
    }

    func testEnclosedInteriorsAreFilled() {
        var lat = WindFlow.Lattice(nx: 10, ny: 10)
        for i in 2...7 { lat[i, 2] = true; lat[i, 7] = true; lat[2, i] = true; lat[7, i] = true }
        lat.fillEnclosed()
        XCTAssertTrue(lat[4, 4])
        XCTAssertFalse(lat[0, 0])
        XCTAssertEqual(lat.fluidCount, 100 - 36)
    }

    func block() -> ArchiDocument {
        var d = ArchiDocument()
        let p = [Vec2(0, 0), Vec2(12_000, 0), Vec2(12_000, 8000), Vec2(0, 8000)]
        for i in 0..<4 { d.addElement(.wall(WallGeom(start: p[i], end: p[(i + 1) % 4], thickness: 300, height: 9000)), level: 0) }
        // A door must not let the wind into the building (the wall mass above it closes the gap).
        d.addElement(.opening(OpeningGeom(kind: .door, hostWall: d.elements[0].id, offset: 5000, width: 1000, height: 2100, sill: 0)), level: 0)
        return d
    }

    func testPedestrianStudyOfABuilding() throws {
        var o = WindStudy.Options()
        o.speed = 5; o.direction = 270; o.roughness = 0.3
        let st = try XCTUnwrap(WindFlow.study(block(), options: o, maxCells: 4000, maxIterations: 3000))
        XCTAssertTrue(st.field.stable)
        XCTAssertEqual(st.pedestrianSpeed, 5 * log(1.5 / 0.3) / log(10 / 0.3), accuracy: 1e-9)
        XCTAssertGreaterThan(st.maxAmplification, 1.0)
        XCTAssertFalse(st.samples.isEmpty)
        XCTAssertEqual(st.comfort.values.reduce(0, +), 100, accuracy: 1e-6)
        // The interior of the building is not part of the flow field.
        let insideCell = st.samples.contains { s in s.p.x > 1 && s.p.x < 11 && s.p.y > 1 && s.p.y < 7 }
        XCTAssertFalse(insideCell)
        XCTAssertNil(WindFlow.study(ArchiDocument(), options: o))
    }

    @MainActor func testWindResultsSolveOption() async {
        let ed = Editor()
        ed.doc = block()
        let before = ed.doc.entities.count
        let out = await ed.run("WINDRESULTS S 5 270 1.5 3 ")
        let text = out.joined(separator: "\n")
        XCTAssertTrue(text.contains("lattice Boltzmann"), text)
        XCTAssertGreaterThan(ed.doc.entities.count, before)
        XCTAssertTrue(ed.doc.entities.contains { $0.layer == "WIND" })
        _ = await ed.run("UNDO ")
        XCTAssertEqual(ed.doc.entities.count, before)
    }
}
