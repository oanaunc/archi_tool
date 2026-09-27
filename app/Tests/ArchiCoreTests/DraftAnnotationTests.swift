// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftAnnotationTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func dim(_ ed: Editor, _ id: EntityID) -> DimensionGeom? { if case .dimension(let d)? = ed.doc.entity(id)?.geometry { return d }; return nil }

    // MARK: DIMBREAK

    func testClipRemovesGapFromPolyline() async {
        let out = DimensionRenderer.clip([[Vec2(0, 0), Vec2(100, 0)]], gaps: [DimensionRenderer.DimBreak(center: Vec2(50, 0), radius: 5)])
        XCTAssertEqual(out.count, 2)
        close(out[0].last!, Vec2(45, 0)); close(out[1].first!, Vec2(55, 0)); close(out[1].last!, Vec2(100, 0))
        // A gap covering an end shortens the line; one away from it leaves it whole.
        XCTAssertEqual(DimensionRenderer.clip([[Vec2(0, 0), Vec2(100, 0)]], gaps: [.init(center: Vec2(0, 0), radius: 10)]).first?.first?.x ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.clip([[Vec2(0, 0), Vec2(100, 0)]], gaps: [.init(center: Vec2(50, 50), radius: 10)]).count, 1)
    }

    func testBreaksDoNotChangeMeasurementOrGrips() async {
        let st = DimStyle(name: "Standard")
        let d = DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(500, 300)])
        let b = DimensionRenderer.withBreaks(d, [.init(center: Vec2(500, 300), radius: 20)], style: st)
        XCTAssertEqual(b.points.count, 5)
        XCTAssertEqual(DimensionRenderer.measurement(b), 1000, accuracy: 1e-9)
        XCTAssertEqual(GeometryOps.grips(.dimension(b)).count, 3)
        XCTAssertEqual(DimensionRenderer.breaks(b).count, 1)
        // Angular with only 3 points: padding keeps the rendering identical.
        let a = DimensionGeom(kind: .angular, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(0, 1000)])
        let pa = DimensionRenderer.padded(a, style: st)
        XCTAssertEqual(pa.points.count, 4)
        XCTAssertEqual(DimensionRenderer.primitives(pa, style: st).lines, DimensionRenderer.primitives(a, style: st).lines)
        XCTAssertEqual(DimensionRenderer.measurement(DimensionRenderer.withBreaks(a, [.init(center: Vec2(1, 1), radius: 1)], style: st)), .pi / 2, accuracy: 1e-9)
    }

    func testDimbreakAutoIsAssociative() async {
        let ed = Editor()
        await ed.run("DIMLINEAR 0,0 1000,0 500,300")
        guard let did = ed.doc.entities.last?.id else { return XCTFail() }
        let lid = ed.doc.add(.line(LineGeom(Vec2(400, -100), Vec2(400, 500))))   // crosses the dimension line at (400,300)
        await ed.run("DIMBREAK #\(did) A")
        guard let d = dim(ed, did) else { return XCTFail() }
        let gaps = DimensionRenderer.breaks(d)
        XCTAssertEqual(gaps.count, 1)
        close(gaps.first?.center ?? .zero, Vec2(400, 300), 1e-6)
        let st = ed.doc.dimStyle(d.style)
        XCTAssertEqual(gaps.first?.radius ?? 0, DimBreaks.defaultSize(st) / 2, accuracy: 1e-9)
        // The dimension line is drawn in two pieces around the crossing.
        let pieces = DimensionRenderer.primitives(d, style: st).lines.filter { $0.allSatisfy { abs($0.y - 300) < 1e-6 } }
        XCTAssertEqual(pieces.count, 2)
        // Moving the crossing line moves the break (associative).
        await ed.run("MOVE #\(lid)  0,0 200,0")
        close(DimensionRenderer.breaks(dim(ed, did)!).first?.center ?? .zero, Vec2(600, 300), 1e-6)
        // Moving the line away removes the break; moving the dimension keeps the measured value.
        await ed.run("MOVE #\(lid)  0,0 5000,0")
        XCTAssertEqual(DimensionRenderer.breaks(dim(ed, did)!).count, 0)
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, did)!), 1000, accuracy: 1e-9)
        // Undo restores the previous state including the break.
        ed.undo()
        close(DimensionRenderer.breaks(dim(ed, did)!).first?.center ?? .zero, Vec2(600, 300), 1e-6)
        // Remove clears the breaks and the property.
        await ed.run("DIMBREAK #\(did) R")
        XCTAssertNil(ed.doc.entity(did)?.props[DimBreaks.prop])
        XCTAssertEqual(dim(ed, did)?.points.count, 3)
    }

    func testDimbreakChosenObjectsManualAndPersistence() async throws {
        let ed = Editor()
        await ed.run("DIMLINEAR 0,0 1000,0 500,300")
        let did = ed.doc.entities.last!.id
        let l1 = ed.doc.add(.line(LineGeom(Vec2(200, -100), Vec2(200, 500))))
        _ = ed.doc.add(.line(LineGeom(Vec2(800, -100), Vec2(800, 500))))
        await ed.run("DIMBREAK #\(did) #\(l1) ")
        XCTAssertEqual(ed.doc.entity(did)?.props[DimBreaks.prop], "\(l1)")
        XCTAssertEqual(DimensionRenderer.breaks(dim(ed, did)!).count, 1, "only the chosen object breaks the dimension")
        // Extension line crossing: a horizontal line through both extension lines.
        _ = ed.doc.add(.line(LineGeom(Vec2(-100, 150), Vec2(1100, 150))))
        await ed.run("DIMBREAK #\(did) A")
        XCTAssertEqual(DimensionRenderer.breaks(dim(ed, did)!).count, 4)
        // Round trip through JSON keeps the breaks.
        let data = try JSONEncoder().encode(ed.doc)
        let back = try JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(back.entity(did), ed.doc.entity(did))
        // Manual gap between two picked points.
        let ed2 = Editor()
        await ed2.run("DIMALIGNED 0,0 1000,0 500,300")
        let d2 = ed2.doc.entities.last!.id
        await ed2.run("DIMBREAK #\(d2) M 300,300 360,300")
        let g = DimensionRenderer.breaks(dim(ed2, d2)!)
        XCTAssertEqual(g.count, 1); close(g[0].center, Vec2(330, 300)); XCTAssertEqual(g[0].radius, 30, accuracy: 1e-9)
        XCTAssertEqual(ed2.doc.entity(d2)?.props[DimBreaks.prop], "manual")
        // Manual breaks move with the dimension.
        await ed2.run("MOVE #\(d2)  0,0 0,100")
        close(DimensionRenderer.breaks(dim(ed2, d2)!)[0].center, Vec2(330, 400))
    }
}

@MainActor
final class DraftDimAssociationTests: XCTestCase {
    func dim(_ ed: Editor, _ id: EntityID) -> DimensionGeom? { if case .dimension(let d)? = ed.doc.entity(id)?.geometry { return d }; return nil }

    func testDimensionsFollowGeometry() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        let l = ed.doc.entities.last!.id
        await ed.run("DIMALIGNED 0,0 1000,0 500,300")
        let d = ed.doc.entities.last!.id
        XCTAssertNotNil(ed.doc.entity(d)?.props[DimAssociation.prop], "auto-associated when snapped")
        // Stretch the line end: the dimension measures the new length.
        ed.transaction("grip") { doc in doc.entities[doc.entityIndex(l)!].geometry = .line(LineGeom(Vec2(0, 0), Vec2(1500, 0))) }
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, d)!), 1500, accuracy: 1e-9)
        // Moving the line moves the whole dimension (dimension line keeps its offset).
        await ed.run("MOVE #\(l)  0,0 0,1000")
        XCTAssertEqual(dim(ed, d)!.points[2].y, 1300, accuracy: 1e-9)
        // Radius dimension keeps its direction when the radius changes.
        await ed.run("CIRCLE 5000,0 500")
        let c = ed.doc.entities.last!.id
        let dr = ed.doc.add(.dimension(DimensionGeom(kind: .radius, points: [Vec2(5000, 0), Vec2(5000, 500), Vec2(5000, 800)])))
        await ed.run("DIMREASSOCIATE #\(dr)  1")
        ed.transaction("r") { doc in doc.entities[doc.entityIndex(c)!].geometry = .circle(CircleGeom(Vec2(6000, 0), 800)) }
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, dr)!), 800, accuracy: 1e-9)
        XCTAssertTrue(dim(ed, dr)!.points[1].isClose(Vec2(6000, 800), tol: 1e-6))
        // Erasing the object drops the attachment, disassociate removes it.
        await ed.run("DIMDISASSOCIATE #\(d) ")
        XCTAssertNil(ed.doc.entity(d)?.props[DimAssociation.prop])
        await ed.run("ERASE #\(c) ")
        XCTAssertNil(ed.doc.entity(dr)?.props[DimAssociation.prop])
        // DIMASSOC 0 turns automatic association off.
        ed.doc.setVariable("DIMASSOC", "0")
        await ed.run("DIMALIGNED 0,1000 1500,1000 500,1300")
        XCTAssertNil(ed.doc.entities.last?.props[DimAssociation.prop])
    }

    func testTextOverrideWithMeasurement() async {
        let d = DimensionGeom(kind: .aligned, points: [.zero, Vec2(2500, 0), Vec2(0, 100)], textOverride: "<> TYP.")
        XCTAssertEqual(DimensionRenderer.formatted(d, style: DimStyle(name: "S")), "2500 TYP.")
    }
}
