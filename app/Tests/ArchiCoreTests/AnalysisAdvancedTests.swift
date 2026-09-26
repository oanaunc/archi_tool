// Oanarina Archi Tool — GPL-3.0-or-later
// Climate-based daylight (ANL-022), wind study case (ANL-028), editing time (ANL-011), generative design (SCR-034)
// and sketch/photo to model (SCR-031).
import XCTest
@testable import ArchiCore

final class AnalysisAdvancedTests: XCTestCase {
    /// Two 6 × 4 m rooms side by side: the first has a large south window, the second no window.
    static func rooms() -> ArchiDocument {
        var d = ArchiDocument()
        let p = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        var w: [EntityID] = []
        for i in 0..<4 { w.append(d.addElement(.wall(WallGeom(start: p[i], end: p[(i + 1) % 4], thickness: 200, height: 3000)))) }
        let q = [Vec2(6000, 0), Vec2(12000, 0), Vec2(12000, 4000), Vec2(6000, 4000)]
        for i in 0..<3 { _ = d.addElement(.wall(WallGeom(start: q[i], end: q[(i + 1) % 4], thickness: 200, height: 3000))) }
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w[0], offset: 3000, width: 4000, height: 2000, sill: 800)))
        _ = d.addElement(.space(SpaceGeom(boundary: p, name: "Bright", number: "1", height: 2800)))
        _ = d.addElement(.space(SpaceGeom(boundary: q, name: "Dark", number: "2", height: 2800)))
        d.info.latitude = 45; d.info.longitude = 25
        return d
    }

    func testRayEscapesOnlyThroughGlazing() {
        let obs = ClimateDaylight.obstacles(Self.rooms())
        let p = Vec3(3000, 2000, 750)
        // Towards the south window, rising 20°.
        let a = 20 * Double.pi / 180
        XCTAssertEqual(ClimateDaylight.escapes(p, Vec3(0, -cos(a), sin(a)), ceiling: 2800, obstacles: obs), 1)
        // Towards the north wall: blocked.
        XCTAssertNil(ClimateDaylight.escapes(p, Vec3(0, cos(a), sin(a)), ceiling: 2800, obstacles: obs))
        // Steeply up: the ceiling blocks before the window.
        XCTAssertNil(ClimateDaylight.escapes(p, Vec3(0, -0.2, 0.98).normalized, ceiling: 2800, obstacles: obs))
        XCTAssertEqual(ClimateDaylight.skyPatches.count, 145)
        XCTAssertEqual(ClimateDaylight.skyPatches.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    func testAnnualDaylightMetrics() {
        var o = ClimateDaylight.Options()
        o.gridSpacing = 1000
        let c = HourlyClimate.clearSky(latitude: 45, longitude: 25, timeZone: 2)
        XCTAssertEqual(c.hours.count, 8760)
        let r = ClimateDaylight.analyse(Self.rooms(), climate: c, options: o)
        XCTAssertEqual(r.count, 2)
        let bright = r.first { $0.name.contains("Bright") }!, dark = r.first { $0.name.contains("Dark") }!
        XCTAssertGreaterThan(bright.sDA, 30)
        XCTAssertGreaterThan(bright.ASE, 0, "a large south window gives direct sun")
        XCTAssertEqual(dark.sDA, 0); XCTAssertEqual(dark.ASE, 0)
        // Points near the window get more daylight than the back of the room.
        let front = bright.points.filter { $0.p.y < 1500 }.map(\.autonomy).max() ?? 0, back = bright.points.filter { $0.p.y > 3000 }.map(\.autonomy).min() ?? 1
        XCTAssertGreaterThanOrEqual(front, back)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(ClimateDaylight.json(r)))
    }

    func testEPWParsing() throws {
        var text = "LOCATION,Bucharest,-,ROU,IWEC,154200,44.50,26.13,2.0,91.0\n"
        for _ in 0..<7 { text += "HEADER,x\n" }
        for h in 1...48 {
            let day = (h - 1) / 24 + 1, hr = (h - 1) % 24 + 1
            // Illuminance missing (999999) on day 2: derived from irradiance.
            let illum = day == 1 ? "\(hr * 100),\(hr * 1000),\(hr * 10)" : "999999,999999,999999"
            text += "2021,1,\(day),\(hr),60,A7,1,1,50,100000,0,0,300,200,\(hr * 5),\(hr * 2),\(illum),0,0,0\n"
        }
        let c = try HourlyClimate.parseEPW(text)
        XCTAssertEqual(c.city, "Bucharest"); XCTAssertEqual(c.latitude, 44.5); XCTAssertEqual(c.timeZone, 2)
        XCTAssertEqual(c.hours.count, 48)
        XCTAssertEqual(c.hours[9].directNormal, 10000); XCTAssertEqual(c.hours[9].diffuseHorizontal, 100)
        XCTAssertEqual(c.hours[24 + 9].directNormal, 10 * 5 * 100, accuracy: 1e-9)
        XCTAssertEqual(c.hours[24 + 9].diffuseHorizontal, 10 * 2 * 120, accuracy: 1e-9)
        XCTAssertThrowsError(try HourlyClimate.parseEPW("nothing"))
    }

    @MainActor func testDaylightAnnualCommand() async {
        let ed = Editor(document: Self.rooms())
        let out = await ed.run("DAYLIGHTANNUAL  1500 Yes")
        XCTAssertTrue(out.joined(separator: "\n").contains("sDA300/50%"), out.joined(separator: "\n"))
        XCTAssertFalse(ed.doc.entities.filter { $0.layer == "DAYLIGHT-GRID" }.isEmpty)
        XCTAssertNotNil(ed.doc.elements.first { if case .space = $0.geometry { return true }; return false }?.props["sDA300"])
    }

    // MARK: Wind

    func testWindCaseAndResults() throws {
        var d = ArchiDocument()
        d.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(10000, 20000, 6000))))
        var o = WindStudy.Options(); o.direction = 270
        let files = try WindStudy.caseFiles(d, options: o)
        for k in ["system/blockMeshDict", "system/snappyHexMeshDict", "system/controlDict", "0/U", "0/p", "0/k", "0/epsilon", "0/nut", "constant/triSurface/building.stl", "Allrun"] {
            XCTAssertNotNil(files[k], k)
        }
        XCTAssertEqual(files["constant/triSurface/building.stl"]!.components(separatedBy: "facet normal").count - 1, 12)
        XCTAssertTrue(files["0/U"]!.contains("atmBoundaryLayerInletVelocity"))
        let tris = WindStudy.buildingTriangles(d, options: o)
        let dom = WindStudy.domain(for: tris, options: o)!
        XCTAssertEqual(dom.buildingHeight, 6, accuracy: 1e-9)
        XCTAssertEqual(dom.max.z, 36, accuracy: 1e-9)
        XCTAssertEqual(dom.min.x, -30, accuracy: 1e-6); XCTAssertEqual(dom.max.x, 10 + 90, accuracy: 1e-6)
        // Wind from the west blows along +X unrotated; from the south the model turns so +Y becomes +X.
        XCTAssertEqual(WindStudy.flowAngle(o, northAngle: 0).truncatingRemainder(dividingBy: 2 * .pi), 0, accuracy: 1e-9)
        var south = o; south.direction = 180
        XCTAssertEqual(cos(WindStudy.flowAngle(south, northAngle: 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(sin(WindStudy.flowAngle(south, northAngle: 0)), 1, accuracy: 1e-9)
        let dir = try FileManager.default.temporaryDirectory.appendingPathComponent("wind-\(UUID().uuidString)")
        XCTAssertEqual(try WindStudy.writeCase(d, to: dir, options: o).count, files.count)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("Allrun").path))
        // Results: case-frame +X velocity in a southerly wind points north in the drawing.
        let s = WindStudy.parseSamples("# x y z U_x U_y U_z\n0 0 1.5 3 0 0\n2 0 1.5 7 0 0\nbad line\n")
        XCTAssertEqual(s.count, 2)
        let arrows = WindStudy.arrows(s, doc: d, options: south, spacing: 1)
        XCTAssertEqual(arrows.count, 4)
        guard case .polyline(let pl) = arrows[0].geometry else { return XCTFail() }
        let v = pl.vertices[1].p - pl.vertices[0].p
        XCTAssertEqual(v.x, 0, accuracy: 1e-6); XCTAssertGreaterThan(v.y, 0)
        XCTAssertEqual(WindStudy.comfortClass(3), "Standing"); XCTAssertEqual(WindStudy.comfortClass(9), "Uncomfortable")
        XCTAssertThrowsError(try WindStudy.caseFiles(ArchiDocument(), options: o))
    }

    // MARK: Editing time

    func testEditingTimeExcludesIdleGaps() {
        var d = ArchiDocument()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        EditTime.touch(&d, now: t0)
        EditTime.touch(&d, now: t0 + 60)
        EditTime.touch(&d, now: t0 + 120)
        EditTime.touch(&d, now: t0 + 2000)          // idle gap: not counted
        EditTime.touch(&d, now: t0 + 2030)
        XCTAssertEqual(EditTime.report(d).editing, 150, accuracy: 0.01)
        XCTAssertEqual(EditTime.report(d).userTimer, 150, accuracy: 0.01)
        EditTime.setTimer(&d, on: false)
        EditTime.touch(&d, now: t0 + 2090)
        XCTAssertEqual(EditTime.report(d).editing, 210, accuracy: 0.01)
        XCTAssertEqual(EditTime.report(d).userTimer, 150, accuracy: 0.01)
        EditTime.resetTimer(&d)
        XCTAssertEqual(EditTime.report(d).userTimer, 0)
        XCTAssertEqual(EditTime.report(d).created!.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(EditTime.format(3 * 86400 + 3661), "3 days 01:01:01")
        // Survives save and reopen.
        XCTAssertEqual(EditTime.report(try! ArchiFile.decode(ArchiFile.encode(d))).editing, 210, accuracy: 0.01)
    }

    @MainActor func testTimeCommand() async {
        let ed = Editor()
        let out = await ed.run("TIME OFF")
        XCTAssertTrue(out.joined(separator: "\n").contains("Total editing time"))
        XCTAssertEqual(ed.doc.variable("USRTIMER"), "0")
    }

    @MainActor func testModifyingCommandsRecordEditingActivity() async {
        let ed = Editor()
        XCTAssertNil(ed.doc.variables["EDITTIMELAST"])
        _ = await ed.run("LINE 0,0 100,0 ")
        XCTAssertNotNil(ed.doc.variables["EDITTIMELAST"], "the Editor touches the editing-time clock after a modifying command")
        XCTAssertNotNil(ed.doc.variables["TDCREATE"])
        ed.undo()
        XCTAssertTrue(ed.doc.entities.isEmpty)
    }

    // MARK: Generative design

    func testGenerativeDesignIsDeterministicAndMeetsObjectives() {
        let brief = GenerativeDesign.Brief(rooms: PlanGenerator.parseBrief("Living 28, Kitchen 12, Bedroom 14, Bedroom 12, Bath 6, Hall 8"),
                                           adjacent: GenerativeDesign.parseAdjacency("Kitchen-Living, Hall-Bath"), facing: GenerativeDesign.parseFacing("Living:S"))
        XCTAssertEqual(brief.adjacent.count, 2); XCTAssertEqual(brief.facing["Living"], "S")
        var o = GenerativeDesign.Options(); o.seed = 7; o.generations = 40
        let a = GenerativeDesign.run(brief, area: 80e6, unitMM: 1, options: o)
        let b = GenerativeDesign.run(brief, area: 80e6, unitMM: 1, options: o)
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a.map(\.score), b.map(\.score))
        let best = a[0]
        XCTAssertEqual(best.objectives.daylight, 0)
        XCTAssertEqual(best.objectives.adjacency, 0)
        XCTAssertEqual(best.objectives.orientation, 0)
        XCTAssertEqual(best.width * best.depth, 80e6, accuracy: 1)
        XCTAssertEqual(best.option.rooms.reduce(0) { $0 + $1.area }, 80e6, accuracy: 1)
        // Pareto front: nothing dominates anything else.
        for x in a { XCTAssertFalse(a.contains { $0.objectives.dominates(x.objectives) }) }
        XCTAssertEqual(GenerativeDesign.compass(of: Vec2(0, -1), northAngle: 0), "S")
        XCTAssertEqual(GenerativeDesign.compass(of: Vec2(1, 0), northAngle: 90), "S", "north rotated to −X")
    }

    @MainActor func testGenDesignCommandBuildsUndoably() async {
        let ed = Editor()
        let out = await ed.run("GENDESIGN \"Living 25, Kitchen 10, Bed 12, Bath 5\" \"Kitchen-Living\" \"\" 52 0,0 1 Yes")
        let names = ed.doc.elements.compactMap { if case .space(let s) = $0.geometry { return s.name }; return nil }
        XCTAssertEqual(names.sorted(), ["Bath", "Bed", "Kitchen", "Living"], out.joined(separator: "\n"))
        await ed.run("UNDO")
        XCTAssertTrue(ed.doc.elements.isEmpty)
    }

    // MARK: Sketch to model

    /// A 200 × 150 px plan: outer rectangle 6 px thick, one interior vertical wall 4 px thick.
    static func sketch() -> RasterImage {
        let w = 200, h = 150
        var g = [UInt8](repeating: 235, count: w * h)
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) { for y in y0..<y1 { for x in x0..<x1 { g[y * w + x] = 20 } } }
        rect(10, 10, 190, 16); rect(10, 134, 190, 140)     // top / bottom
        rect(10, 10, 16, 140); rect(184, 10, 190, 140)     // left / right
        rect(98, 16, 102, 134)                              // partition
        // Noise: a short scribble and a thin line (text-like) that must be ignored.
        rect(40, 60, 48, 62); rect(120, 70, 170, 71)
        return RasterImage(width: w, height: h, gray: g)
    }

    func testSketchTracesWalls() {
        var o = SketchToModel.Options()
        o.scale = 50; o.minThickness = 3; o.maxThickness = 12; o.minLength = 20
        let walls = SketchToModel.trace(Self.sketch(), options: o)
        XCTAssertEqual(walls.count, 5, "\(walls)")
        let horizontal = walls.filter { abs($0.start.y - $0.end.y) < 1e-6 }, vertical = walls.filter { abs($0.start.x - $0.end.x) < 1e-6 }
        XCTAssertEqual(horizontal.count, 2); XCTAssertEqual(vertical.count, 3)
        // Bottom wall centre: image row 137 → y = (150 − 137) × 50 = 650; thickness 6 px = 300.
        let bottom = horizontal.min { $0.start.y < $1.start.y }!
        XCTAssertEqual(bottom.start.y, 650, accuracy: 1e-6); XCTAssertEqual(bottom.thickness, 300, accuracy: 1e-6)
        // Corners meet at centre lines: the bottom wall spans between the outer walls' centre lines (x 13 and 187 px).
        XCTAssertEqual(min(bottom.start.x, bottom.end.x), 650, accuracy: 1e-6)
        XCTAssertEqual(max(bottom.start.x, bottom.end.x), 9350, accuracy: 1e-6)
        let part = vertical.first { abs($0.start.x - 5000) < 1e-6 }
        XCTAssertNotNil(part, "partition at x = 100 px")
        XCTAssertEqual(part?.thickness ?? 0, 200, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(SketchToModel.otsu(Self.sketch().gray), 20); XCTAssertLessThan(SketchToModel.otsu(Self.sketch().gray), 235)
    }

    func testRasterDecoders() throws {
        let img = Self.sketch()
        XCTAssertEqual(try RasterImage.decode(img.pngData()), img)
        // 24-bit BMP (bottom-up) and binary PGM of a 3 × 2 image.
        var bmp: [UInt8] = Array("BM".utf8) + [UInt8](repeating: 0, count: 52)
        func put32(_ v: Int, _ at: Int) { for k in 0..<4 { bmp[at + k] = UInt8((v >> (8 * k)) & 0xFF) } }
        put32(54, 10); put32(40, 14); put32(3, 18); put32(2, 22); bmp[26] = 1; bmp[28] = 24
        let rows: [[UInt8]] = [[0, 0, 0, 255, 255, 255, 0, 0, 255], [255, 0, 0, 0, 255, 0, 128, 128, 128]]   // bottom row first, BGR
        for r in rows { bmp += r + [0, 0, 0] }
        let b = try RasterImage.decode(Data(bmp))
        XCTAssertEqual(b.width, 3); XCTAssertEqual(b.height, 2)
        XCTAssertEqual(b[0, 1], 0); XCTAssertEqual(b[1, 1], 255); XCTAssertEqual(b[2, 1], 76)   // red
        XCTAssertEqual(b[2, 0], 128)
        let pgm = Data("P5\n# c\n3 2\n255\n".utf8) + Data([0, 50, 100, 150, 200, 250])
        XCTAssertEqual(try RasterImage.decode(pgm).gray, [0, 50, 100, 150, 200, 250])
        let ppm = Data("P3 1 1 255 255 0 0".utf8)
        XCTAssertEqual(try RasterImage.decode(ppm).gray, [76])
        XCTAssertThrowsError(try RasterImage.decode(Data([1, 2, 3])))
    }

    @MainActor func testSketchToWallsCommandAsksAndUndoes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sketch-\(UUID().uuidString).png")
        try Self.sketch().pngData().write(to: url)
        let ed = Editor()
        await ed.run("SKETCHTOWALLS \"\(url.path)\" 50 0,0 0 No")
        XCTAssertTrue(ed.doc.elements.isEmpty, "declined")
        await ed.run("SKETCHTOWALLS \"\(url.path)\" 50 0,0 250 Yes")
        let walls = ed.doc.elements.compactMap { if case .wall(let w) = $0.geometry { return w }; return nil }
        XCTAssertEqual(walls.count, 5)
        XCTAssertTrue(walls.allSatisfy { $0.thickness == 250 })
        await ed.run("UNDO")
        XCTAssertTrue(ed.doc.elements.isEmpty)
    }

    // MARK: Clash groups and status (ANL-036)

    @MainActor func testClashResultsKeepStatusBetweenRuns() async {
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200, height: 3000)))
        let c = d.addElement(.column(ColumnGeom(position: Vec2(2000, 0), height: 3000)))
        let b = d.addElement(.beam(BeamGeom(start: Vec2(1000, -1000), end: Vec2(1000, 1000))))
        var s = ClashManager.run(&d, date: "d1")
        XCTAssertEqual(s.new, ClashManager.all(d).count)
        XCTAssertGreaterThanOrEqual(s.new, 1)
        let first = ClashManager.all(d)[0]
        XCTAssertEqual(first.status, .new)
        XCTAssertEqual(ClashManager.update(&d, numbers: [first.number], status: .reviewed, assignee: "Mihai"), 1)
        ClashManager.group(&d, by: .type)
        XCTAssertFalse(ClashManager.all(d)[0].group.isEmpty)
        ClashManager.group(&d, by: .proximity, distance: 10)
        // Re-run: unchanged clashes keep their status and assignee.
        s = ClashManager.run(&d, date: "d2")
        XCTAssertEqual(ClashManager.all(d).first { $0.number == first.number }?.status, .reviewed)
        XCTAssertEqual(ClashManager.all(d).first { $0.number == first.number }?.assignee, "Mihai")
        // Move the column and the beam away: their clashes are resolved automatically; bring them back: active again.
        let saved = d
        d.elements.removeAll { $0.id == c || $0.id == b }
        s = ClashManager.run(&d, date: "d3")
        XCTAssertEqual(s.total, 0)
        XCTAssertTrue(ClashManager.all(d).allSatisfy { $0.status == .resolved && $0.resolved == "d3" })
        var back = saved
        back.variables["CLASHRESULTS"] = d.variables["CLASHRESULTS"]
        s = ClashManager.run(&back, date: "d4")
        XCTAssertEqual(s.new, 0)
        XCTAssertTrue(ClashManager.all(back).allSatisfy { $0.status == .active })
        // Report rows carry zoom links.
        let rep = ClashManager.report(back)
        XCTAssertEqual(rep.first?["zoomCommand"] as? String, "CLASHMANAGE Zoom \(ClashManager.all(back)[0].number)")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(rep))
        XCTAssertTrue(ClashManager.csv(back).contains("ZOOM W"))
        // Command: zoom selects both elements.
        let ed = Editor(document: back)
        let n = ClashManager.all(back)[0].number
        await ed.run("CLASHMANAGE Zoom \(n)")
        XCTAssertEqual(ed.selection, [ClashManager.all(back)[0].a, ClashManager.all(back)[0].b])
        await ed.run("CLASHMANAGE Status All Approved")
        XCTAssertTrue(ClashManager.all(ed.doc).allSatisfy { $0.status == .approved })
        _ = w
    }
}
