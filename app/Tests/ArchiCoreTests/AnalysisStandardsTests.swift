// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class AnalysisStandardsTests: XCTestCase {
    func testDrawingStandards() throws {
        var d = ArchiDocument()
        d.ensureLayer("A-WALL"); d.ensureLayer("walls old")
        let a = d.add(Entity(layer: "0", geometry: .line(LineGeom(.zero, Vec2(100, 0)))))
        let b = d.add(Entity(layer: "A-WALL", color: .aci(1), geometry: .line(LineGeom(.zero, Vec2(0, 100)))))
        let t1 = d.add(Entity(layer: "A-WALL", geometry: .text(TextGeom(position: .zero, height: 250, content: "ok"))))       // 2.5 mm at 1:100
        let t2 = d.add(Entity(layer: "A-WALL", geometry: .text(TextGeom(position: .zero, height: 300, content: "bad", style: "Comic"))))
        var s = DrawingStandards()
        s.layerPattern = "^[A-Z]-[A-Z0-9-]+$"; s.requiredLayers = ["Z-REQUIRED"]; s.textStyles = ["Standard"]
        let issues = StandardsCheck.check(d, standards: s)
        func ids(_ c: String) -> [EntityID] { issues.first { $0.code == c }?.ids ?? [-1] }
        XCTAssertNotNil(issues.first { $0.code == "STD-LAYER-NAME" && $0.message.contains("walls old") })
        XCTAssertNotNil(issues.first { $0.code == "STD-LAYER-MISSING" && $0.message.contains("Z-REQUIRED") })
        XCTAssertEqual(ids("STD-LAYER-0"), [a])
        XCTAssertEqual(ids("STD-COLOR-BYLAYER"), [b])
        XCTAssertEqual(ids("STD-TEXT-HEIGHT"), [t2])
        XCTAssertEqual(ids("STD-TEXT-STYLE"), [t2])
        XCTAssertFalse(ids("STD-TEXT-HEIGHT").contains(t1))
        XCTAssertFalse(issues.first { $0.code == "STD-LAYER-0" }!.bounds.isEmpty)
        let j = try DrawingStandards.fromJSON("{\"name\":\"Min\",\"requiredLayers\":[\"X\"]}")
        XCTAssertEqual(StandardsCheck.check(d, standards: j).map(\.code), ["STD-LAYER-MISSING"])
        XCTAssertEqual(try DrawingStandards.fromJSON(s.json), s)
    }

    func testSolarRadiation() throws {
        // 45° N on 21 June: horizontal clear-sky ≈ 7–9 kWh/m²; in December a south façade gets more than the roof.
        let hJune = SolarRadiation.daily(day: "2025-06-21", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 180, tilt: 0)
        XCTAssertGreaterThan(hJune, 6.5); XCTAssertLessThan(hJune, 9.5)
        let southDec = SolarRadiation.daily(day: "2025-12-21", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 180, tilt: 90)
        let northDec = SolarRadiation.daily(day: "2025-12-21", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 0, tilt: 90)
        let roofDec = SolarRadiation.daily(day: "2025-12-21", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 180, tilt: 0)
        XCTAssertGreaterThan(southDec, roofDec)
        XCTAssertGreaterThan(southDec, 3 * northDec)
        // East and west façades are symmetric about solar noon.
        let e = SolarRadiation.daily(day: "2025-03-20", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 90, tilt: 90, stepMinutes: 2)
        let w = SolarRadiation.daily(day: "2025-03-20", latitude: 45, longitude: 0, utcOffset: 0, azimuth: 270, tilt: 90, stepMinutes: 2)
        XCTAssertEqual(e, w, accuracy: e * 0.05)
        // Surfaces of a box: the south wall gets the south value.
        var d = ArchiDocument(); d.info.latitude = 45; d.info.longitude = 0
        let pts = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4])))) }
        let rows = SolarRadiation.surfaces(d, day: "2025-12-21", utcOffset: 0)
        let south = try XCTUnwrap(rows.first { $0.id == walls[0] })
        XCTAssertEqual(south.azimuth, 180, accuracy: 1e-9)
        XCTAssertEqual(south.kWhPerM2, southDec, accuracy: 1e-9)
        XCTAssertEqual(south.area, 6 * 3, accuracy: 1e-9)
    }

    @MainActor
    func testBuildingAnalysisCommandsHeadless() async throws {
        var d = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 6000), Vec2(0, 6000)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300)), material: "Brick")) }
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 4000, width: 1500, height: 1200, sill: 900)))
        _ = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), material: "Concrete")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(150, 150), Vec2(7850, 150), Vec2(7850, 5850), Vec2(150, 5850)], name: "Studio", number: "1")))
        _ = d.addElement(.column(ColumnGeom(position: Vec2(4000, 3000), height: 3000)), material: "Concrete")
        let ed = Editor(document: d)
        var log = await ed.run("HEATLOSS 20 -10 0.5 ")
        XCTAssertTrue(log.contains { $0.contains("Design heat loss at ΔT 30 K") }, log.joined(separator: "\n"))
        log = await ed.run("DAYLIGHT All ")
        XCTAssertTrue(log.contains { $0.contains("1 Studio: DF") }, log.joined(separator: "\n"))
        let before = ed.doc.entities.count
        log = await ed.run("SUNPATH 2025-06-21 20000,0 5000")
        XCTAssertGreaterThan(ed.doc.entities.count, before + 20, log.joined(separator: "\n"))
        log = await ed.run("LEVELAREAS ")
        XCTAssertTrue(log.contains { $0.contains("TOTAL") }, log.joined(separator: "\n"))
        log = await ed.run("UVALUE Select #\(walls[0]) ")
        XCTAssertTrue(log.contains { $0.contains("U = ") }, log.joined(separator: "\n"))
        log = await ed.run("CODECHECK ")
        XCTAssertTrue(log.contains { $0.contains("issue") || $0.contains("No code issues") }, log.joined(separator: "\n"))
        log = await ed.run("FRAMEANALYSIS")
        XCTAssertTrue(log.contains { $0.contains("Largest displacement") }, log.joined(separator: "\n"))
        log = await ed.run("ANALYTICALMODEL 1.5 2 ")
        XCTAssertTrue(log.contains { $0.contains("Analytical model: 2 nodes") }, log.joined(separator: "\n"))
        log = await ed.run("REVERB All ")
        XCTAssertTrue(log.contains { $0.contains("RT60") }, log.joined(separator: "\n"))
        log = await ed.run("CARBON All ")
        XCTAssertTrue(log.contains { $0.contains("TOTAL") }, log.joined(separator: "\n"))
        log = await ed.run("ISOVIST 4000,1500 30000 N")
        XCTAssertTrue(log.contains { $0.contains("visible area") }, log.joined(separator: "\n"))
        log = await ed.run("IFCVALIDATE ")
        XCTAssertTrue(log.contains { $0.contains("IFC is valid") || $0.contains("issue") }, log.joined(separator: "\n"))
        log = await ed.run("SOLARRADIATION 2025-06-21 ")
        XCTAssertTrue(log.contains { $0.contains("Total on 2025-06-21") }, log.joined(separator: "\n"))
        log = await ed.run("STANDARDSCHECK ")
        XCTAssertFalse(log.isEmpty)
        // Export commands write files headless.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-cmd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (cmd, file) in [("STEPOUT", "m.step"), ("PLYOUT", "m.ply"), ("HPGLOUT", "m.plt"), ("XLSXOUT", "m.xlsx"), ("IFCZIPOUT", "m.ifczip"), ("GBXMLOUT", "m.xml"), ("COBIEOUT", "c.xlsx"), ("DAEOUT", "m.dae")] {
            let url = dir.appendingPathComponent(file)
            log = await ed.run("\(cmd) \(url.path)" + (cmd == "HPGLOUT" ? " 100" : ""))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(cmd): " + log.joined(separator: "\n"))
        }
        // …and read back through the import commands.
        let n0 = ed.doc.entities.count
        log = await ed.run("STEPIN \(dir.appendingPathComponent("m.step").path)")
        XCTAssertGreaterThan(ed.doc.entities.count, n0, log.joined(separator: "\n"))
        log = await ed.run("MESHIMPORT \(dir.appendingPathComponent("m.dae").path)")
        XCTAssertTrue(log.contains { $0.contains("Imported") }, log.joined(separator: "\n"))
        log = await ed.run("DWGOUT \(dir.appendingPathComponent("x.dwg").path)")
        XCTAssertTrue(log.contains { $0.contains("converter") || $0.contains("Wrote") }, log.joined(separator: "\n"))
    }
}
