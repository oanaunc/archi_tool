// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class CommandTests: XCTestCase {
    func lines(_ ed: Editor) -> [LineGeom] { ed.doc.entities.compactMap { if case .line(let l) = $0.geometry { return l }; return nil } }
    func walls(_ ed: Editor) -> [(EntityID, WallGeom)] { ed.doc.elements.compactMap { if case .wall(let w) = $0.geometry { return ($0.id, w) }; return nil } }
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }

    func testNoAliasCollisions() {
        let r = CommandRegistry()
        BuiltinCommands.registerAll(r)
        var seen: [String: String] = [:]
        var collisions: [String] = []
        for c in r.sorted {
            for n in [c.name] + c.aliases {
                let key = n.trimmingCharacters(in: CharacterSet(charactersIn: "_.-'"))
                if let o = seen[key], o != c.name { collisions.append("\(n): \(o) / \(c.name)") }
                seen[key] = c.name
            }
        }
        XCTAssertEqual(collisions, [])
        XCTAssertGreaterThan(r.commands.count, 180)
        for n in ["LINE", "PLINE", "WALL", "DOOR", "SLAB", "ROOF", "TRIM", "FILLET", "HATCH", "DIMLINEAR", "LAYER", "BLOCK", "INSERT", "ZOOM", "AREA", "SETPROP", "GRID", "GRIDDISPLAY"] {
            XCTAssertNotNil(r.lookup(n), n)
        }
    }

    func testPlineWithArc() async {
        let ed = Editor()
        await ed.run("PLINE 0,0 1000,0 A 1000,1000 L 0,1000 C")
        guard case .polyline(let p)? = ed.doc.entities.first?.geometry else { return XCTFail("no polyline") }
        XCTAssertTrue(p.closed)
        XCTAssertEqual(p.vertices.count, 4)
        XCTAssertEqual(p.vertices[1].bulge, 1, accuracy: 1e-9)
        XCTAssertEqual(p.vertices[0].bulge, 0)
        // Semicircle bulging to +x: area = square + half disc of radius 500.
        XCTAssertEqual(GeometryOps.area(.polyline(p), doc: nil)!, 1e6 + .pi * 500 * 500 / 2, accuracy: 3000)
    }

    func testRectangAndPolygon() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 2000,1000")
        guard case .polyline(let p)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 4)
        XCTAssertEqual(GeometryOps.area(.polyline(p), doc: nil)!, 2e6, accuracy: 1e-6)
        await ed.run("RECTANG F 100 0,0 2000,1000")
        guard case .polyline(let f)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(f.vertices.count, 8)
        XCTAssertEqual(GeometryOps.area(.polyline(f), doc: nil)!, 2e6 - (4 - .pi) * 100 * 100, accuracy: 600)
        await ed.run("RECTANG F 0 0,0 D 3000 1500 1,1")
        guard case .polyline(let d)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(GeometryOps.area(.polyline(d), doc: nil)!, 4.5e6, accuracy: 1e-6)
        await ed.run("POLYGON 6 0,0 I 1000")
        guard case .polyline(let h)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(h.vertices.count, 6)
        XCTAssertEqual(GeometryOps.area(.polyline(h), doc: nil)!, 3 * 3.squareRoot() / 2 * 1e6, accuracy: 1)
    }

    func testCircleVariants() async {
        let ed = Editor()
        await ed.run("CIRCLE 0,0 500")
        await ed.run("CIRCLE 2P 0,0 1000,0")
        await ed.run("CIRCLE 3P 0,0 1000,0 500,500")
        let cs = ed.doc.entities.compactMap { e -> CircleGeom? in if case .circle(let c) = e.geometry { return c }; return nil }
        XCTAssertEqual(cs.count, 3)
        XCTAssertEqual(cs[0].radius, 500)
        close(cs[1].center, Vec2(500, 0)); XCTAssertEqual(cs[1].radius, 500, accuracy: 1e-9)
        close(cs[2].center, Vec2(500, 0)); XCTAssertEqual(cs[2].radius, 500, accuracy: 1e-9)
        // Tangent-tangent-radius between two perpendicular lines.
        let ed2 = Editor()
        await ed2.run("LINE 0,0 1000,0")
        await ed2.run("LINE 0,0 0,1000")
        await ed2.run("CIRCLE T 500,0 0,500 100")
        guard case .circle(let t)? = ed2.doc.entities.last?.geometry else { return XCTFail("no TTR circle") }
        close(t.center, Vec2(100, 100), 1e-6); XCTAssertEqual(t.radius, 100)
    }

    func testArcAndEllipse() async {
        let ed = Editor()
        await ed.run("ARC 1000,0 0,1000 -1000,0")
        guard case .arc(let a)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(a.center, .zero, 1e-6); XCTAssertEqual(a.radius, 1000, accuracy: 1e-6)
        XCTAssertEqual(a.sweep, .pi, accuracy: 1e-9)
        await ed.run("ARC C 0,0 1000,0 A 90")
        guard case .arc(let b)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(b.sweep, .pi / 2, accuracy: 1e-9)
        await ed.run("ELLIPSE C 0,0 2000,0 1000")
        guard case .ellipse(let e)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(e.ratio, 0.5, accuracy: 1e-12); XCTAssertEqual(e.majorAxis.length, 2000, accuracy: 1e-9)
    }

    func testMoveCopyRotateMirrorScale() async {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0")
        let id = ed.doc.entities[0].id
        ed.selection = [id]
        await ed.run("MOVE 0,0 50,50")
        close(lines(ed)[0].a, Vec2(50, 50)); close(lines(ed)[0].b, Vec2(150, 50))
        XCTAssertTrue(ed.selection.isEmpty)
        ed.selection = [id]
        await ed.run("COPY 0,0 0,100")
        XCTAssertEqual(lines(ed).count, 2)
        close(lines(ed)[1].a, Vec2(50, 150))
        ed.selection = [id]
        await ed.run("ROTATE 50,50 90")
        close(lines(ed)[0].a, Vec2(50, 50), 1e-9); close(lines(ed)[0].b, Vec2(50, 150), 1e-9)
        ed.selection = [id]
        await ed.run("MIRROR 0,0 0,100")
        XCTAssertEqual(lines(ed).count, 3)
        close(lines(ed)[2].a, Vec2(-50, 50), 1e-9)
        ed.selection = [id]
        await ed.run("SCALE 50,50 2")
        XCTAssertEqual(lines(ed)[0].a.distance(to: lines(ed)[0].b), 200, accuracy: 1e-9)
        // Undo restores the pre-scale state.
        ed.undo()
        XCTAssertEqual(lines(ed)[0].a.distance(to: lines(ed)[0].b), 100, accuracy: 1e-9)
    }

    func testMoveWallCarriesOpenings() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0")
        await ed.run("DOOR 2500,0")
        let wid = walls(ed)[0].0
        ed.selection = [wid]
        await ed.run("COPY 0,0 0,3000")
        let openings = ed.doc.elements.compactMap { e -> OpeningGeom? in if case .opening(let o) = e.geometry { return o }; return nil }
        XCTAssertEqual(walls(ed).count, 2)
        XCTAssertEqual(openings.count, 2)
        XCTAssertEqual(Set(openings.map(\.hostWall)).count, 2)
    }

    func testOffsetLine() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0")
        await ed.run("OFFSET 100 500,0 500,300")
        let ls = lines(ed)
        XCTAssertEqual(ls.count, 2)
        if ls.count == 2 { XCTAssertEqual(ls[1].a.y, 100, accuracy: 1e-9); XCTAssertEqual(ls[1].b.y, 100, accuracy: 1e-9) }
        XCTAssertEqual(ed.settings.offsetDistance, 100)
    }

    func testTrimAndExtend() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0")
        await ed.run("LINE 500,-500 500,500")
        await ed.run("TRIM 800,0")
        let h = lines(ed).first { abs($0.a.y) < 1e-9 && abs($0.b.y) < 1e-9 }
        XCTAssertNotNil(h)
        if let h = h { XCTAssertEqual(max(h.a.x, h.b.x), 500, accuracy: 1e-6); XCTAssertEqual(min(h.a.x, h.b.x), 0, accuracy: 1e-6) }
        let ed2 = Editor()
        await ed2.run("LINE 0,0 400,0")
        await ed2.run("LINE 1000,-500 1000,500")
        await ed2.run("EXTEND 350,0")
        let e = lines(ed2).first { abs($0.a.y) < 1e-9 && abs($0.b.y) < 1e-9 }
        if let e = e { XCTAssertEqual(max(e.a.x, e.b.x), 1000, accuracy: 1e-6) } else { XCTFail() }
    }

    func testFillet() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0")
        await ed.run("LINE 1200,200 1200,1000")
        await ed.run("FILLET R 100 500,0 1200,500")
        XCTAssertEqual(ed.settings.filletRadius, 100)
        let arcs = ed.doc.entities.compactMap { e -> ArcGeom? in if case .arc(let a) = e.geometry { return a }; return nil }
        XCTAssertEqual(arcs.count, 1)
        if let a = arcs.first { XCTAssertEqual(a.radius, 100, accuracy: 1e-6); close(a.center, Vec2(1100, 100), 1e-6) }
        let ls = lines(ed)
        XCTAssertEqual(ls.count, 2)
        if ls.count == 2 { XCTAssertEqual(max(ls[0].a.x, ls[0].b.x), 1100, accuracy: 1e-6) }
        // Polyline fillet of all corners.
        let ed2 = Editor()
        await ed2.run("RECTANG 0,0 1000,1000")
        await ed2.run("FILLET R 100")
        await ed2.run("FILLET P 500,0")
        guard case .polyline(let p)? = ed2.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(p.vertices.count, 8)
    }

    func testArrays() async {
        let ed = Editor()
        ed.doc.setVariable("ARRAYASSOCIATIVITY", "0")
        await ed.run("CIRCLE 0,0 100")
        ed.selection = [ed.doc.entities[0].id]
        await ed.run("ARRAY R 3 4 1000 1500")
        XCTAssertEqual(ed.doc.entities.count, 12)
        let xs = Set(ed.doc.entities.compactMap { e -> Double? in if case .circle(let c) = e.geometry { return c.center.x }; return nil })
        XCTAssertEqual(xs, [0, 1500, 3000, 4500])
        let ed2 = Editor()
        ed2.doc.setVariable("ARRAYASSOCIATIVITY", "0")
        await ed2.run("CIRCLE 1000,0 100")
        ed2.selection = [ed2.doc.entities[0].id]
        await ed2.run("ARRAYPOLAR 0,0 4")
        XCTAssertEqual(ed2.doc.entities.count, 4)
        guard ed2.doc.entities.count > 1, case .circle(let c) = ed2.doc.entities[1].geometry else { return XCTFail() }
        close(c.center, Vec2(0, 1000), 1e-9)
    }

    func testWallChainAndJoin() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0 5000,4000 0,4000 C")
        let ws = walls(ed)
        XCTAssertEqual(ws.count, 4)
        for i in 0..<4 { close(ws[i].1.end, ws[(i + 1) % 4].1.start) }
        XCTAssertEqual(ed.doc.element(ws[0].0)?.props["joinEnd"], "\(ws[1].0)")
        XCTAssertEqual(ed.doc.element(ws[0].0)?.props["joinStart"], "\(ws[3].0)")
        XCTAssertEqual(ws[0].1.thickness, ed.settings.wallThickness)
        // Undo removes the whole chain in one step.
        ed.undo()
        XCTAssertEqual(walls(ed).count, 0)
    }

    func testDoorAndWindowHostedInWall() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0")
        let wid = walls(ed)[0].0
        await ed.run("DOOR 2500,0")
        await ed.run("WINDOW 1000,50")
        let ops = ed.doc.elements.compactMap { e -> OpeningGeom? in if case .opening(let o) = e.geometry { return o }; return nil }
        XCTAssertEqual(ops.count, 2)
        guard ops.count == 2 else { return }
        XCTAssertEqual(ops[0].kind, .door); XCTAssertEqual(ops[0].hostWall, wid)
        XCTAssertEqual(ops[0].offset, 2500, accuracy: 1e-9); XCTAssertEqual(ops[0].width, 900); XCTAssertEqual(ops[0].height, 2100)
        XCTAssertEqual(ops[1].kind, .window); XCTAssertEqual(ops[1].offset, 1000, accuracy: 1e-9)
        XCTAssertEqual(ops[1].sill, 900); XCTAssertEqual(ops[1].width, 1200)
        // Overlapping door is refused; a door near the wall end is clamped inside the wall.
        await ed.run("DOOR 1100,0")
        await ed.run("DOOR 4990,0")
        let doors = ed.doc.elements.compactMap { e -> OpeningGeom? in if case .opening(let o) = e.geometry, o.kind == .door { return o }; return nil }
        XCTAssertEqual(doors.count, 2)
        XCTAssertEqual(doors.last!.offset, 5000 - 450, accuracy: 1e-9)
        // Erasing the wall removes hosted openings.
        ed.selection = [wid]
        await ed.run("ERASE")
        XCTAssertTrue(ed.doc.elements.isEmpty)
    }

    func testSlabAreaAndRoom() async {
        let ed = Editor()
        let log = await ed.run("SLAB 0,0 4000,0 4000,3000 0,3000")
        guard case .slab(let s)? = ed.doc.elements.first?.geometry else { return XCTFail("no slab") }
        XCTAssertEqual(abs(GeometryOps.signedArea(s.boundary)), 12e6, accuracy: 1e-6)
        XCTAssertGreaterThan(GeometryOps.signedArea(s.boundary), 0)
        XCTAssertTrue(log.contains { $0.contains("Area = 12.00 m², Perimeter = 14.00 m") }, log.joined(separator: "\n"))
        let ed2 = Editor()
        await ed2.run("WALL 0,0 5000,0 5000,4000 0,4000 C")
        let roomLog = await ed2.run("ROOM 2500,2000")
        guard case .space(let r)? = ed2.doc.elements.last?.geometry else { return XCTFail("no room: " + roomLog.joined(separator: "\n")) }
        XCTAssertEqual(abs(GeometryOps.signedArea(r.boundary)), 4800 * 3800, accuracy: 4800 * 3800 * 0.01)
        XCTAssertEqual(r.number, "101")
        await ed2.run("SLAB W 2500,2000")
        guard case .slab(let s2)? = ed2.doc.elements.last?.geometry else { return XCTFail("no slab from walls") }
        XCTAssertEqual(abs(GeometryOps.signedArea(s2.boundary)), 5200 * 4200, accuracy: 5200 * 4200 * 0.01)
    }

    func testBuildingMassing() async {
        let ed = Editor()
        await ed.run("BUILDING 0,0 10000,8000")
        XCTAssertEqual(walls(ed).count, 4)
        XCTAssertEqual(ed.doc.elements.filter { if case .slab = $0.geometry { return true }; return false }.count, 1)
        XCTAssertEqual(ed.doc.elements.filter { if case .roof = $0.geometry { return true }; return false }.count, 1)
    }

    func testLayerNewSet() async {
        let ed = Editor()
        await ed.run("LAYER New Walls,Doors Set Walls C 1 Walls")
        XCTAssertNotNil(ed.doc.layer(named: "Walls")); XCTAssertNotNil(ed.doc.layer(named: "Doors"))
        XCTAssertEqual(ed.doc.currentLayer, "Walls")
        XCTAssertEqual(ed.doc.layer(named: "Walls")?.color, RGBA(1, 0, 0))
        await ed.run("LINE 0,0 10,0")
        XCTAssertEqual(ed.doc.entities.last?.layer, "Walls")
        await ed.run("LAYER LO Walls")
        XCTAssertEqual(ed.doc.layer(named: "Walls")?.locked, true)
        XCTAssertFalse(ed.isSelectable(ed.doc.entities[0].id))
        await ed.run("LAYER Freeze Walls")
        XCTAssertEqual(ed.doc.layer(named: "Walls")?.frozen, false, "current layer cannot be frozen")
        await ed.run("LAYER Delete Doors")
        XCTAssertNil(ed.doc.layer(named: "Doors"))
    }

    func testBlockAndInsert() async {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0")
        await ed.run("LINE 0,0 0,100")
        ed.selection = Set(ed.doc.entities.map(\.id))
        await ed.run("BLOCK Corner 0,0")
        XCTAssertEqual(ed.doc.blocks["Corner"]?.entities.count, 2)
        XCTAssertEqual(ed.doc.entities.count, 1)
        await ed.run("INSERT Corner 5000,0 2")
        XCTAssertEqual(ed.doc.entities.count, 2)
        guard case .insert(let ins)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.block, "Corner"); close(ins.position, Vec2(5000, 0)); XCTAssertEqual(ins.scale, Vec2(2, 2))
        ed.selection = [ed.doc.entities.last!.id]
        await ed.run("EXPLODE")
        let ls = lines(ed)
        XCTAssertEqual(ls.count, 2)
        XCTAssertTrue(ls.contains { $0.a.isClose(Vec2(5000, 0), tol: 1e-9) && $0.b.isClose(Vec2(5200, 0), tol: 1e-9) })
    }

    func testDimLinear() async {
        let ed = Editor()
        let log = await ed.run("DIMLINEAR 0,0 3000,0 1500,500")
        guard case .dimension(let d)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(d.kind, .linear); XCTAssertEqual(d.rotation, 0)
        XCTAssertEqual(DimensionRenderer.measurement(d), 3000, accuracy: 1e-9)
        XCTAssertTrue(log.contains { $0.contains("Dimension text = 3000") })
        await ed.run("DIMLINEAR 0,0 3000,2000 4000,1000")
        guard case .dimension(let v)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(v.rotation!, .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(DimensionRenderer.measurement(v), 2000, accuracy: 1e-9)
        await ed.run("DIMLINEAR 3000,0 5000,0 4000,-500")
        await ed.run("DIMCONTINUE 7000,0")
        guard case .dimension(let c)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(c.points[0], Vec2(5000, 0)); XCTAssertEqual(c.points[2].y, -500, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.measurement(c), 2000, accuracy: 1e-9)
    }

    func testAreaOutput() async {
        let ed = Editor()
        let log = await ed.run("AREA 0,0 4000,0 4000,3000 0,3000")
        XCTAssertTrue(log.contains { $0.contains("Area = 12.00 m², Perimeter = 14.00 m") }, log.joined(separator: "\n"))
        await ed.run("CIRCLE 0,0 1000")
        let log2 = await ed.run("AREA O 1000,0")
        XCTAssertTrue(log2.contains { $0.contains("Area = 3.14 m²") }, log2.joined(separator: "\n"))
        let log3 = await ed.run("DIST 0,0 3000,4000")
        XCTAssertTrue(log3.contains { $0.contains("Distance = 5000") })
    }

    func testHatchFindsBoundaryWithIsland() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 1000,1000 0,1000 C")
        await ed.run("CIRCLE 500,500 100")
        await ed.run("HATCH 200,200")
        guard case .hatch(let h)? = ed.doc.entities.last?.geometry else { return XCTFail("no hatch") }
        XCTAssertEqual(h.loops.count, 2)
        XCTAssertEqual(GeometryOps.area(.hatch(h), doc: nil)!, 1e6 - .pi * 1e4, accuracy: 600)
        // Picking inside the circle hatches only the circle.
        await ed.run("HATCH 500,500")
        guard case .hatch(let h2)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(GeometryOps.area(.hatch(h2), doc: nil)!, .pi * 1e4, accuracy: 600)
        // Outside everything: nothing is created.
        let n = ed.doc.entities.count
        await ed.run("HATCH 5000,5000")
        XCTAssertEqual(ed.doc.entities.count, n)
    }

    func testSetPropAndPropertyAccess() async {
        let ed = Editor()
        await ed.run("WALL 0,0 4000,0")
        let wid = walls(ed)[0].0
        await ed.run("SETPROP #\(wid) height 2800")
        XCTAssertEqual(walls(ed)[0].1.height, 2800)
        var el = ed.doc.element(wid)!
        XCTAssertTrue(PropertyAccess.propertyNames(of: el).contains("thickness"))
        XCTAssertEqual(PropertyAccess.getProperty(el, "length"), "4000")
        XCTAssertFalse(PropertyAccess.setProperty(&el, "length", "10"))
        XCTAssertFalse(PropertyAccess.setProperty(&el, "thickness", "-5"))
        XCTAssertTrue(PropertyAccess.setProperty(&el, "justification", "left"))
        var c = Entity(geometry: .circle(CircleGeom(.zero, 10)))
        XCTAssertTrue(PropertyAccess.setProperty(&c, "diameter", "50"))
        XCTAssertEqual(PropertyAccess.getProperty(c, "radius"), "25")
        XCTAssertTrue(PropertyAccess.setProperty(&c, "color", "red"))
        XCTAssertEqual(c.color, .aci(1))
    }

    func testCalcAndVariables() async {
        XCTAssertEqual(CommandHelpers.evaluate("2*(3+4)^2"), 98)
        XCTAssertEqual(CommandHelpers.evaluate("sqrt(16)+sin(90)")!, 5, accuracy: 1e-12)
        XCTAssertNil(CommandHelpers.evaluate("2+"))
        let ed = Editor()
        await ed.run("OSMODE 35")
        XCTAssertEqual(ed.settings.snapModes, [.endpoint, .midpoint, .intersection])
        XCTAssertEqual(SystemVariables.osmode(ed.settings), 35)
        await ed.run("TEXTSIZE 350")
        XCTAssertEqual(ed.settings.textHeight, 350)
        await ed.run("ORTHO ON")
        XCTAssertTrue(ed.settings.ortho)
        await ed.run("TEXT 0,0 400 0 Hello world")
        guard case .text(let t)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t.content, "Hello world"); XCTAssertEqual(t.height, 400)
    }

    func testRegionFinderFaces() {
        // Two rooms sharing a wall line: the face containing the point is the right one.
        let pls: [[Vec2]] = [[Vec2(0, 0), Vec2(2000, 0), Vec2(2000, 1000), Vec2(0, 1000), Vec2(0, 0)], [Vec2(1000, -200), Vec2(1000, 1200)]]
        let f = RegionFinder.planarFace(containing: Vec2(1500, 500), polylines: pls)
        XCTAssertNotNil(f)
        XCTAssertEqual(abs(GeometryOps.signedArea(f!.outer)), 1e6, accuracy: 1e-6)
        XCTAssertNil(RegionFinder.planarFace(containing: Vec2(5000, 500), polylines: pls))
    }

    func testAuditFixesDanglingOpening() {
        var d = ArchiDocument()
        d.elements.append(BIMElement(id: 50, geometry: .opening(OpeningGeom(kind: .door, hostWall: 999, offset: 0, width: 900, height: 2100))))
        let issues = SettingsCommands.audit(&d, fix: true)
        XCTAssertFalse(issues.isEmpty)
        XCTAssertTrue(d.elements.isEmpty)
        XCTAssertGreaterThan(d.nextID, 50)
    }

    func testScriptRunsLines() async {
        let ed = Editor()
        await ed.runScript("LINE 0,0 100,0\n; comment\nCIRCLE 0,0 50\n")
        XCTAssertEqual(ed.doc.entities.count, 2)
        let log = await ed.run("HELP LINE")
        XCTAssertTrue(log.contains { $0.contains("LINE (L)") })
    }
}
