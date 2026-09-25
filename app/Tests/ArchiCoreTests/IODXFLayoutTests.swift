// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class IODXFLayoutTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }

    func testPaperSpaceLayoutsAndViewportsRoundTrip() throws {
        var doc = ArchiDocument()
        doc.add(.line(LineGeom(Vec2(0, 0), Vec2(10000, 0))))
        doc.add(.dimension(DimensionGeom(kind: .aligned, points: [Vec2(0, 0), Vec2(10000, 0), Vec2(5000, 800)])))
        let plans = Layout(name: "Plans", paper: PaperSize(name: "A3", width: 420, height: 297),
                           viewports: [Viewport(origin: Vec2(20, 20), size: Vec2(200, 150), viewCenter: Vec2(5000, 300), scale: 50, view: .plan, level: 0, title: "Ground floor"),
                                       Viewport(origin: Vec2(240, 20), size: Vec2(160, 120), viewCenter: Vec2(1000, 2000), scale: 100, view: .elevationSouth, title: "South")],
                           entities: [Entity(id: 900, layer: "TITLE", geometry: .text(TextGeom(position: Vec2(300, 10), height: 3.5, content: "Plans sheet"))),
                                      Entity(id: 901, layer: "TITLE", geometry: .dimension(DimensionGeom(kind: .aligned, points: [Vec2(20, 200), Vec2(220, 200), Vec2(120, 210)])))],
                           titleBlock: ["Project": "Cedar House", "Drawn": "OR"])
        let details = Layout(name: "Details", paper: PaperSize(name: "A1", width: 841, height: 594),
                             viewports: [Viewport(origin: Vec2(10, 10), size: Vec2(400, 300), viewCenter: Vec2(-50, 75), scale: 5, level: 1)],
                             entities: [Entity(id: 902, layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(841, 594))))])
        let empty = Layout(name: "Spare")
        doc.layouts = [plans, details, empty]
        let text = DXFWriter.write(doc)
        XCTAssertTrue(text.contains("ACAD_LAYOUT"))
        XCTAssertTrue(text.contains("*Paper_Space0"))
        XCTAssertTrue(text.contains("AcDbViewport"))

        let back = try DXFReader.read(text)
        XCTAssertEqual(back.layouts.map(\.name), ["Plans", "Details", "Spare"])
        // Model space keeps only the model objects.
        XCTAssertEqual(back.entities.count, 2)
        let p = back.layouts[0]
        XCTAssertEqual(p.paper.width, 420, accuracy: 1e-9); XCTAssertEqual(p.paper.height, 297, accuracy: 1e-9); XCTAssertEqual(p.paper.name, "A3")
        XCTAssertEqual(p.viewports.count, 2)
        let v0 = try XCTUnwrap(p.viewports.first { $0.title == "Ground floor" })
        close(v0.origin, Vec2(20, 20)); close(v0.size, Vec2(200, 150)); close(v0.viewCenter, Vec2(5000, 300))
        XCTAssertEqual(v0.scale, 50, accuracy: 1e-9)
        XCTAssertEqual(v0.view, .plan); XCTAssertEqual(v0.level, 0)
        let v1 = try XCTUnwrap(p.viewports.first { $0.title == "South" })
        XCTAssertEqual(v1.view, .elevationSouth); XCTAssertNil(v1.level); XCTAssertEqual(v1.scale, 100, accuracy: 1e-9)
        XCTAssertEqual(p.entities.count, 2)
        XCTAssertTrue(p.entities.contains { if case .text(let t) = $0.geometry { return t.content == "Plans sheet" }; return false })
        XCTAssertTrue(p.entities.contains { if case .dimension = $0.geometry { return true }; return false })
        XCTAssertEqual(p.titleBlock["Project"], "Cedar House"); XCTAssertEqual(p.titleBlock["Drawn"], "OR")
        let d = back.layouts[1]
        XCTAssertEqual(d.paper.width, 841, accuracy: 1e-9)
        XCTAssertEqual(d.viewports.count, 1)
        XCTAssertEqual(d.viewports[0].scale, 5, accuracy: 1e-9); XCTAssertEqual(d.viewports[0].level, 1)
        close(d.viewports[0].viewCenter, Vec2(-50, 75))
        XCTAssertEqual(d.entities.count, 1)
        XCTAssertTrue(back.layouts[2].entities.isEmpty && back.layouts[2].viewports.isEmpty)
        // Paper-space entities get IDs of their own.
        let ids = back.entities.map(\.id) + back.layouts.flatMap { $0.entities.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testBlockAttributesRoundTrip() throws {
        var doc = ArchiDocument()
        var tag = Entity(layer: "0", geometry: .text(TextGeom(position: Vec2(0, -300), height: 150, content: "ROOM", halign: .center)))
        tag.props = ["attdef": "ROOM", "prompt": "Room name", "default": "-"]
        var num = Entity(layer: "0", geometry: .text(TextGeom(position: Vec2(0, -500), height: 100, content: "NUM")))
        num.props = ["attdef": "NUM", "prompt": "Number", "default": "0", "invisible": "1"]
        doc.blocks["ROOMTAG"] = Block(name: "ROOMTAG", basePoint: .zero, entities: [Entity(layer: "0", geometry: .circle(CircleGeom(.zero, 400))), tag, num])
        doc.add(.insert(InsertGeom(block: "ROOMTAG", position: Vec2(1000, 2000), scale: Vec2(2, 2), rotation: 0, attributes: ["ROOM": "Kitchen", "NUM": "12"])))
        let text = DXFWriter.write(doc)
        XCTAssertTrue(text.contains("AcDbAttributeDefinition"))
        let back = try DXFReader.read(text)
        let blk = try XCTUnwrap(back.blocks["ROOMTAG"])
        let defs = blk.entities.filter { $0.props["attdef"] != nil }
        XCTAssertEqual(Set(defs.compactMap { $0.props["attdef"] }), ["ROOM", "NUM"])
        let room = try XCTUnwrap(defs.first { $0.props["attdef"] == "ROOM" })
        XCTAssertEqual(room.props["prompt"], "Room name"); XCTAssertEqual(room.props["default"], "-")
        if case .text(let t) = room.geometry { XCTAssertEqual(t.halign, .center); close(t.position, Vec2(0, -300)); XCTAssertEqual(t.height, 150, accuracy: 1e-9) } else { XCTFail() }
        XCTAssertEqual(defs.first { $0.props["attdef"] == "NUM" }?.props["invisible"], "1")
        guard case .insert(let ins) = back.entities.first?.geometry else { return XCTFail("insert missing") }
        XCTAssertEqual(ins.attributes["ROOM"], "Kitchen"); XCTAssertEqual(ins.attributes["NUM"], "12")
        // ATTRIB placed where the definition sits in the scaled insert, visible unless the definition is invisible.
        let lines = text.components(separatedBy: "\n")
        let attribIdx = lines.indices.filter { lines[$0] == "ATTRIB" }
        XCTAssertEqual(attribIdx.count, 2)
        let k = try XCTUnwrap(lines.firstIndex(of: "Kitchen"))
        let kitchen = try XCTUnwrap(attribIdx.last { $0 < k })
        let xi = try XCTUnwrap(lines[kitchen...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "10" })
        XCTAssertEqual(Double(lines[xi + 1])!, 1000, accuracy: 1e-6)
        XCTAssertEqual(Double(lines[xi + 3])!, 2000 - 600, accuracy: 1e-6)
    }

    func testCustomHatchPatternDefinitionRoundTrip() throws {
        var doc = ArchiDocument()
        doc.setVariable("HPPAT:MYSTRIPES", "30,0,0,0,5,2,-1\n120,1,0,0,8")
        doc.add(.hatch(HatchGeom(loops: [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)].map { PolyVertex($0) }], pattern: "MYSTRIPES", scale: 2, angle: 0.3)))
        let text = DXFWriter.write(doc)
        let back = try DXFReader.read(text)
        guard case .hatch(let h) = back.entities.first?.geometry else { return XCTFail() }
        XCTAssertEqual(h.pattern, "MYSTRIPES"); XCTAssertEqual(h.scale, 2, accuracy: 1e-9); XCTAssertEqual(h.angle, 0.3, accuracy: 1e-9)
        let def = try XCTUnwrap(back.variable("HPPAT:MYSTRIPES"))
        let rows = def.components(separatedBy: "\n").map { $0.split(separator: ",").compactMap { Double($0) } }
        let want: [[Double]] = [[30, 0, 0, 0, 5, 2, -1], [120, 1, 0, 0, 8]]
        XCTAssertEqual(rows.count, 2)
        for (r, w) in zip(rows, want) {
            XCTAssertEqual(r.count, w.count)
            for (a, b) in zip(r, w) { XCTAssertEqual(a, b, accuracy: 1e-6) }
        }
        // Standard patterns are not copied into the drawing.
        var d2 = ArchiDocument()
        d2.add(.hatch(HatchGeom(loops: [[Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)].map { PolyVertex($0) }], pattern: "ANSI31")))
        XCTAssertNil(try DXFReader.read(DXFWriter.write(d2)).variables.keys.first { $0.hasPrefix("HPPAT:") })
    }

    static let mlineAndTable = """
    0
    SECTION
    2
    ENTITIES
    0
    MLINE
    8
    WALLS
    40
    1.0
    70
    0
    71
    0
    72
    3
    73
    2
    10
    0
    20
    0
    30
    0
    11
    0
    21
    0
    31
    0
    12
    1
    22
    0
    32
    0
    13
    0
    23
    1
    33
    0
    74
    2
    41
    0.5
    41
    0
    75
    0
    74
    2
    41
    -0.5
    41
    0
    75
    0
    11
    100
    21
    0
    31
    0
    12
    0
    22
    1
    32
    0
    13
    -1
    23
    1
    33
    0
    74
    1
    41
    0.5
    75
    0
    74
    1
    41
    -0.5
    75
    0
    11
    100
    21
    100
    31
    0
    12
    0
    22
    1
    32
    0
    13
    -1
    23
    0
    33
    0
    74
    1
    41
    0.5
    75
    0
    74
    1
    41
    -0.5
    75
    0
    0
    ACAD_TABLE
    8
    0
    100
    AcDbBlockReference
    2
    *T1
    10
    10
    20
    50
    30
    0
    100
    AcDbTable
    91
    2
    92
    2
    141
    8
    141
    8
    142
    30
    142
    40
    171
    1
    140
    2.5
    1
    Name
    171
    1
    1
    Area
    171
    1
    1
    Kitchen
    171
    1
    1
    12.5
    0
    ENDSEC
    0
    EOF
    """

    func testMLineAndTableRead() throws {
        let doc = try DXFReader.read(Self.mlineAndTable)
        let polys = doc.entities.compactMap { e -> PolylineGeom? in if case .polyline(let p) = e.geometry { return p }; return nil }
        XCTAssertEqual(polys.count, 2)
        let a = polys[0].vertices.map(\.p), b = polys[1].vertices.map(\.p)
        XCTAssertEqual(a.count, 3); XCTAssertEqual(b.count, 3)
        close(a[0], Vec2(0, 0.5)); close(b[0], Vec2(0, -0.5))
        let s = 0.5 / sqrt(2)
        close(a[1], Vec2(100 - s, s)); close(b[1], Vec2(100 + s, -s))
        close(a[2], Vec2(99.5, 100)); close(b[2], Vec2(100.5, 100))
        XCTAssertTrue(doc.entities.filter { if case .polyline = $0.geometry { return true }; return false }.allSatisfy { $0.layer == "WALLS" })
        guard let t = doc.entities.compactMap({ e -> TableGeom? in if case .table(let t) = e.geometry { return t }; return nil }).first else { return XCTFail("table missing") }
        close(t.origin, Vec2(10, 50))
        XCTAssertEqual(t.columnWidths, [30, 40]); XCTAssertEqual(t.rowHeight, 8, accuracy: 1e-9); XCTAssertEqual(t.textHeight, 2.5, accuracy: 1e-9)
        XCTAssertEqual(t.cells, [["Name", "Area"], ["Kitchen", "12.5"]])
    }
}
