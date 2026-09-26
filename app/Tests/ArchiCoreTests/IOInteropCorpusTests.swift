// Oanarina Archi Tool — GPL-3.0-or-later
// Writes an interoperability corpus (every drafting geometry type + the demo houses, in every DXF version) to
// build/interop so it can be checked against LibreCAD's libdxfrw reader, and checks each file with our own reader.
import XCTest
@testable import ArchiCore

final class IOInteropCorpusTests: XCTestCase {
    static var repoRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    /// A drawing with one of every drafting entity kind (and a block with attributes).
    static func allKindsDocument() -> ArchiDocument {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "A-WALL", color: RGBA(1, 0, 0)))
        d.layers.append(Layer(name: "Ünïcode 层", color: RGBA(0, 0.5, 1)))
        d.blocks["DOOR-TAG"] = Block(name: "DOOR-TAG", basePoint: .zero, entities: [
            Entity(geometry: .circle(CircleGeom(.zero, 200))),
            Entity(geometry: .line(LineGeom(Vec2(-200, 0), Vec2(200, 0)))),
            Entity(geometry: .text(TextGeom(position: Vec2(-100, 20), height: 80, content: "D")))])
        _ = d.add(.point(Vec2(10, 10)))
        _ = d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))), layer: "A-WALL")
        _ = d.add(.circle(CircleGeom(Vec2(500, 500), 250)))
        _ = d.add(.arc(ArcGeom(Vec2(0, 0), 300, 0, .pi / 2)))
        _ = d.add(.ellipse(EllipseGeom(center: Vec2(2000, 0), majorAxis: Vec2(400, 0), ratio: 0.5)))
        _ = d.add(.ellipse(EllipseGeom(center: Vec2(3000, 0), majorAxis: Vec2(0, 400), ratio: 0.4, start: 0.3, end: 2.5)))
        _ = d.add(.polyline(PolylineGeom([PolyVertex(Vec2(0, 1000)), PolyVertex(Vec2(500, 1000), bulge: 0.5), PolyVertex(Vec2(1000, 1500))], closed: true, width: 10)))
        _ = d.add(.spline(SplineGeom(degree: 3, controlPoints: [Vec2(0, 2000), Vec2(300, 2400), Vec2(700, 1800), Vec2(1000, 2200)])))
        _ = d.add(.spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: [Vec2(0, 2500), Vec2(400, 2700), Vec2(900, 2500)])))
        _ = d.add(.text(TextGeom(position: Vec2(0, 3000), height: 100, content: "Plan — ground floor ü")), layer: "Ünïcode 层")
        _ = d.add(.text(TextGeom(position: Vec2(0, 3300), height: 100, content: "Multi line\nnote with a wrap width", width: 1500)))
        _ = d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(500, -400)])))
        _ = d.add(.dimension(DimensionGeom(kind: .aligned, points: [Vec2(0, 1000), Vec2(1000, 1500), Vec2(400, 1600)])))
        _ = d.add(.dimension(DimensionGeom(kind: .radius, points: [Vec2(500, 500), Vec2(750, 500), Vec2(900, 600)])))
        _ = d.add(.dimension(DimensionGeom(kind: .diameter, points: [Vec2(500, 500), Vec2(250, 500), Vec2(100, 400)])))
        _ = d.add(.dimension(DimensionGeom(kind: .angular, points: [Vec2(0, 0), Vec2(300, 0), Vec2(0, 300), Vec2(250, 250)])))
        _ = d.add(.dimension(DimensionGeom(kind: .ordinate, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, -300)])))
        _ = d.add(.dimension(DimensionGeom(kind: .arcLength, points: [Vec2(0, 0), Vec2(300, 0), Vec2(0, 300), Vec2(350, 350)])))
        _ = d.add(.hatch(HatchGeom(loops: [[PolyVertex(Vec2(4000, 0)), PolyVertex(Vec2(5000, 0)), PolyVertex(Vec2(5000, 1000)), PolyVertex(Vec2(4000, 1000))]], pattern: "ANSI31", scale: 10)))
        _ = d.add(.hatch(HatchGeom(loops: [[PolyVertex(Vec2(6000, 0)), PolyVertex(Vec2(7000, 0), bulge: 0.3), PolyVertex(Vec2(6500, 800))]])))
        _ = d.add(.insert(InsertGeom(block: "DOOR-TAG", position: Vec2(3000, 3000), rotation: 0.3, attributes: ["MARK": "D01"])))
        _ = d.add(.leader(LeaderGeom(points: [Vec2(0, 0), Vec2(300, 300), Vec2(600, 300)], text: "Concrete", textHeight: 80)))
        _ = d.add(.table(TableGeom(origin: Vec2(8000, 3000), columnWidths: [800, 1200], rowHeight: 300, cells: [["Mark", "Width"], ["D01", "900"]], textHeight: 100)))
        _ = d.add(.solid(SolidGeom(kind: .box, origin: Vec3(9000, 0, 0), size: Vec3(500, 500, 500))))
        return d
    }

    func testWriteDXFCorpusAndReadBack() throws {
        let dir = Self.repoRoot.appendingPathComponent("build/interop", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var docs: [(String, ArchiDocument)] = [("all-kinds", Self.allKindsDocument())]
        for name in ["Cedar House", "Nordic House"] {
            let url = Self.repoRoot.appendingPathComponent("assets/demo/\(name).archi")
            if let data = try? Data(contentsOf: url), let doc = try? ArchiFile.decode(data) {
                docs.append((name.replacingOccurrences(of: " ", with: "-").lowercased(), doc))
            }
        }
        for (name, doc) in docs {
            for version in DXFVersion.allCases {
                let text = DXFWriter.write(doc, version: version, levels: nil)
                let back = try DXFReader.read(text)
                XCTAssertFalse(back.entities.isEmpty, "\(name) \(version.rawValue) reads back")
                // Every group code / value pair is complete (even line count, integer group codes).
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                let body = lines.last == "" ? lines.dropLast() : lines[...]
                XCTAssertEqual(body.count % 2, 0, "\(name) \(version.rawValue) has whole group pairs")
                var i = body.startIndex
                while i < body.endIndex {
                    XCTAssertNotNil(Int(body[i].trimmingCharacters(in: .whitespaces)), "\(name) \(version.rawValue) line \(i) is a group code")
                    i += 2
                }
                if name == "all-kinds" && version != .r12 {
                    XCTAssertEqual(text.components(separatedBy: "\n  0\nSPLINE\n").count - 1, 2, "fit-point splines are written as SPLINE")
                    let fitBack = back.entities.compactMap { e -> SplineGeom? in if case .spline(let s) = e.geometry, !s.fitPoints.isEmpty { return s }; return nil }
                    XCTAssertEqual(fitBack.first?.fitPoints.count, 3)
                    XCTAssertGreaterThanOrEqual(fitBack.first?.controlPoints.count ?? 0, 4)
                }
                try Data(text.utf8).write(to: dir.appendingPathComponent("\(name)-\(version.rawValue).dxf"))
            }
        }
    }
}
