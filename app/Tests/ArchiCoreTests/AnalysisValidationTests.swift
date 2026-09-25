// Oanarina Archi Tool — GPL-3.0-or-later
// Analysis figures checked against reference hand calculations (ANL-020 solar radiation, ANL-021 daylight factor,
// ANL-027 embodied carbon, ANL-029 Sabine reverberation, ANL-030 isovist).
import XCTest
@testable import ArchiCore

final class AnalysisValidationTests: XCTestCase {
    func sun(_ az: Double, _ alt: Double) -> SunPosition { SunPosition(azimuth: az, altitude: alt, declination: 0, equationOfTime: 0, hourAngle: 0) }

    // ANL-020: Meinel clear-sky model evaluated by hand.
    func testSolarIrradianceMatchesHandCalculation() {
        // Sun at the zenith: AM = 1/(1 + 0.50572·96.07995^-1.6364) = 0.99971, DNI = 1353·0.7^(AM^0.678) = 947.17 W/m²,
        // horizontal = DNI + 0.1·DNI = 1041.88 W/m².
        XCTAssertEqual(SolarRadiation.irradiance(sun: sun(180, 90), azimuth: 180, tilt: 0), 1041.88, accuracy: 0.05)
        // Altitude 30°, south: AM = 1.99431, DNI = 765.50; south façade: beam 765.50·cos30 = 662.94, sky diffuse 76.55·½ = 38.28,
        // ground 0.2·(765.50·½ + 76.55)·½ = 45.93 → 747.15 W/m².
        XCTAssertEqual(SolarRadiation.irradiance(sun: sun(180, 30), azimuth: 180, tilt: 90), 747.15, accuracy: 0.05)
        // East façade with the sun due south: no beam, only diffuse + ground = 84.21 W/m².
        XCTAssertEqual(SolarRadiation.irradiance(sun: sun(180, 30), azimuth: 90, tilt: 90), 84.21, accuracy: 0.05)
        // 30° roof facing the sun at 30° altitude: incidence 30° → 740.52 W/m².
        XCTAssertEqual(SolarRadiation.irradiance(sun: sun(180, 30), azimuth: 180, tilt: 30), 740.52, accuracy: 0.05)
        // Sun below the horizon: nothing; a north façade with the sun south gets no beam.
        XCTAssertEqual(SolarRadiation.irradiance(sun: sun(180, -5), azimuth: 180, tilt: 0), 0)
        XCTAssertEqual(SolarRadiation.irradiance(sun: sun(180, 30), azimuth: 0, tilt: 90), 84.21, accuracy: 0.05)
        // Daily integration converges (2 min vs 10 min steps within 1 %) and stays below the extraterrestrial bound
        // (H0 = 24/π·1.353·(cosφ cosδ sinωs + ωs sinφ sinδ) ≈ 11.6 kWh/m² at 45° N on 21 June).
        let a = SolarRadiation.daily(day: "2025-06-21", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 180, tilt: 0, stepMinutes: 2)
        let b = SolarRadiation.daily(day: "2025-06-21", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 180, tilt: 0, stepMinutes: 10)
        XCTAssertEqual(a, b, accuracy: a * 0.01)
        let phi = 45.0 * .pi / 180, dec = 23.44 * .pi / 180, ws = acos(-tan(phi) * tan(dec))
        let h0 = 24 / Double.pi * 1.353 * (cos(phi) * cos(dec) * sin(ws) + ws * sin(phi) * sin(dec))
        XCTAssertLessThan(a, h0)
        XCTAssertGreaterThan(a, 0.6 * h0)
    }

    // ANL-021: BRE average daylight factor DF = T·Aw·θ·M / (A·(1 − R²)).
    func testDaylightFactorMatchesHandCalculation() throws {
        var d = ArchiDocument()
        let s = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(6000, 0), thickness: 200)))
        let e = d.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 5000), thickness: 200)))
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: s, offset: 3000, width: 2000, height: 1500, sill: 900, frameWidth: 0)))
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: e, offset: 2500, width: 1000, height: 1500, sill: 900, frameWidth: 0)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: e, offset: 800, width: 900, height: 2100)))   // doors do not count
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 100), Vec2(5900, 100), Vec2(5900, 5000), Vec2(0, 5000)], name: "Studio", number: "2", height: 3000)))
        var o = DaylightOptions(); o.transmittance = 0.6; o.skyAngle = 80; o.reflectance = 0.4; o.maintenance = 0.8
        let r = try XCTUnwrap(Daylight.compute(d, options: o).first)
        // Floor 5.9 × 4.9 = 28.91 m², perimeter 21.6 m, height 3 m → A = 2·28.91 + 64.8 = 122.62 m²; Aw = 3 + 1.5 = 4.5 m².
        XCTAssertEqual(r.floorArea, 28.91, accuracy: 1e-9)
        XCTAssertEqual(r.glazedArea, 4.5, accuracy: 1e-9)
        XCTAssertEqual(r.daylightFactor, 0.6 * 4.5 * 80 * 0.8 / (122.62 * (1 - 0.16)), accuracy: 1e-9)   // 1.677 %
        XCTAssertEqual(r.daylightFactor, 1.677, accuracy: 0.001)
        XCTAssertEqual(r.rating, "poor")
        // A windowless room reads 0 %.
        var bare = ArchiDocument()
        _ = bare.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(3000, 0), Vec2(3000, 3000), Vec2(0, 3000)])))
        XCTAssertEqual(Daylight.compute(bare).first?.daylightFactor, 0)
    }

    // ANL-027: cradle-to-gate carbon = volume × density × factor (ICE values).
    func testEmbodiedCarbonMatchesHandCalculation() throws {
        var d = ArchiDocument()
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 10000), Vec2(0, 10000)], thickness: 200)), material: "Concrete")
        _ = d.addElement(.column(ColumnGeom(position: Vec2(5000, 5000), width: 300, depth: 300, height: 3000)), material: "Steel")
        _ = d.addElement(.beam(BeamGeom(start: Vec2(0, 0), end: Vec2(5000, 0), width: 200, depth: 400)), material: "Glulam")
        let rows = EmbodiedCarbon.compute(d)
        let concrete = try XCTUnwrap(rows.first { $0.material == "Concrete" })
        XCTAssertEqual(concrete.volume, 20, accuracy: 1e-9)                // 10 × 10 × 0.2
        XCTAssertEqual(concrete.carbon, 20 * 2400 * 0.13, accuracy: 1e-6)  // 6240 kgCO2e
        let steel = try XCTUnwrap(rows.first { $0.material == "Steel" })
        XCTAssertEqual(steel.carbon, 0.27 * 7850 * 1.55, accuracy: 1e-6)   // 3285.2 kgCO2e
        let glulam = try XCTUnwrap(rows.first { $0.material == "Glulam" })
        XCTAssertEqual(glulam.carbon, 0.4 * 500 * 0.51, accuracy: 1e-6)    // 5 × 0.2 × 0.4 m³ → 102 kgCO2e
        XCTAssertEqual(rows.map(\.material), ["Concrete", "Steel", "Glulam"], "sorted by carbon")
        let table = EmbodiedCarbon.table(rows)
        XCTAssertEqual(table.last?[4], fmt(6240 + 3285.225 + 102, 0))
        // EPD override.
        d.setVariable("CARBON:Concrete", "0.1")
        XCTAssertEqual(EmbodiedCarbon.compute(d).first { $0.material == "Concrete" }!.carbon, 4800, accuracy: 1e-6)
    }

    // ANL-029: Sabine RT60 = 0.161·V / ΣSα.
    func testReverberationMatchesHandCalculation() throws {
        var d = ArchiDocument()
        let pts = [Vec2(-100, -100), Vec2(6100, -100), Vec2(6100, 5100), Vec2(-100, 5100)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 200)))) }
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 3100, width: 2000, height: 1500, sill: 900, frameWidth: 0)))
        let room = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 5000), Vec2(0, 5000)], name: "Class", number: "1", height: 3000)))
        d.setVariable("ALPHA:floor", "0.3"); d.setVariable("ALPHA:ceiling", "0.7"); d.setVariable("ALPHA:wall", "0.05")
        // V = 90 m³; floor 30·0.3 = 9, ceiling 30·0.7 = 21, walls (66 − 3)·0.05 = 3.15, glass 3·0.04 = 0.12 → A = 33.27 m².
        var r = try XCTUnwrap(Acoustics.reverberation(d).first)
        XCTAssertEqual(r.volume, 90, accuracy: 1e-9)
        XCTAssertEqual(r.absorption, 33.27, accuracy: 1e-9)
        XCTAssertEqual(r.rt60, 0.161 * 90 / 33.27, accuracy: 1e-9)   // 0.4355 s
        // Furniture and people as extra Sabine area.
        d.elements[d.elementIndex(room)!].props["absorption"] = "10"
        r = try XCTUnwrap(Acoustics.reverberation(d).first)
        XCTAssertEqual(r.rt60, 0.161 * 90 / 43.27, accuracy: 1e-9)
    }

    // ANL-030: visibility polygon against analytic areas.
    func testIsovistMatchesAnalyticArea() {
        // A 2 m wall 2 m in front of the eye shadows the sector beyond it:
        // visible = πR² − (½R²·2·atan(1/2) − ½·2·2) with R = 10 m.
        let R = 10000.0
        let wall: [(Vec2, Vec2)] = [(Vec2(-1000, 2000), Vec2(1000, 2000))]
        let poly = Isovist.polygon(from: .zero, obstacles: wall, maxDistance: R, rays: 7200)
        let theta = 2 * atan(0.5)
        let expected = Double.pi * R * R - (0.5 * R * R * theta - 0.5 * 2000 * 2000)
        XCTAssertEqual(abs(GeometryOps.signedArea(poly)), expected, accuracy: expected * 0.002)
        // Inside a closed 4 × 3 m box the whole floor is visible from any interior point.
        let box: [(Vec2, Vec2)] = [(Vec2(0, 0), Vec2(4000, 0)), (Vec2(4000, 0), Vec2(4000, 3000)), (Vec2(4000, 3000), Vec2(0, 3000)), (Vec2(0, 3000), Vec2(0, 0))]
        for eye in [Vec2(2000, 1500), Vec2(500, 400), Vec2(3900, 2900)] {
            XCTAssertEqual(abs(GeometryOps.signedArea(Isovist.polygon(from: eye, obstacles: box, maxDistance: 1e6, rays: 7200))), 12e6, accuracy: 12e6 * 0.003)
        }
        // A door gap lets the view out of the room.
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 100)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 2000, width: 1000, height: 2100)))
        let obs = Isovist.obstacles(d, level: 0, eyeHeight: 1600)
        XCTAssertEqual(obs.count, 8, "two wall runs of four faces each")
        let p = Isovist.polygon(from: Vec2(2000, 1000), obstacles: obs, maxDistance: 5000, rays: 720)
        XCTAssertTrue(p.contains { $0.y < -3900 }, "the view reaches through the door")
    }
}
