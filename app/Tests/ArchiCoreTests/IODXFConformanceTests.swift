// Oanarina Archi Tool — GPL-3.0-or-later
// DXF export conformance (IO-009): every version the writer produces passes the structural audit, and the audit
// detects the defects strict readers reject.
import XCTest
@testable import ArchiCore

final class IODXFConformanceTests: XCTestCase {
    func document() -> ArchiDocument {
        var d = IOLifecycleTests.richDocument()
        d.units = .millimeters
        d.add(.text(TextGeom(position: Vec2(0, -500), height: 100, content: "Line one\nLine two", width: 2000)))
        d.add(.dimension(DimensionGeom(kind: .aligned, points: [Vec2(0, 0), Vec2(300, 400), Vec2(-50, 60)])))
        d.add(.dimension(DimensionGeom(kind: .radius, points: [Vec2(5, 5), Vec2(5.1, 5), Vec2(6, 6)])))
        return d
    }

    func testEveryVersionPassesTheAudit() {
        let d = document()
        for v in DXFVersion.allCases {
            let text = DXFWriter.write(d, version: v, levels: nil)
            let issues = DXFConformance.audit(text)
            XCTAssertTrue(issues.filter { $0.severity == .error }.isEmpty, "\(v.rawValue): " + issues.prefix(10).map(\.description).joined(separator: "; "))
        }
    }

    /// Export → import keeps the drawing objects (same kinds and counts as the ENTITIES section written).
    func testSameEntitiesAfterRoundTrip() throws {
        let d = document()
        for v in [DXFVersion.r2000, .r2018] {
            let text = DXFWriter.write(d, version: v, levels: nil)
            let written = DXFConformance.entityCounts(text)
            let back = try DXFReader.read(text)
            let again = DXFWriter.write(back, version: v, levels: nil)
            XCTAssertTrue(DXFConformance.audit(again).filter { $0.severity == .error }.isEmpty, v.rawValue)
            let rewritten = DXFConformance.entityCounts(again)
            for (k, n) in written { XCTAssertEqual(rewritten[k], n, "\(v.rawValue) \(k)") }
            XCTAssertGreaterThanOrEqual(written.values.reduce(0, +), d.entities.count - 1)
            // 3D faces come back as a mesh solid with their heights (the box spans z 3…303).
            let zs = back.entities.flatMap { e -> [Double] in if case .solid(let s) = e.geometry, s.kind == .mesh { return s.meshVertices.map(\.z) }; return [] }
            XCTAssertEqual(zs.max() ?? 0, 303, accuracy: 1e-6, v.rawValue)
            XCTAssertEqual(zs.min() ?? 0, 3, accuracy: 1e-6, v.rawValue)
        }
    }

    func testDetectsDefects() {
        var small = ArchiDocument()
        small.add(Entity(layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(100, 0)))))
        small.add(Entity(layer: "0", geometry: .circle(CircleGeom(Vec2(50, 50), 20))))
        let good = DXFWriter.write(small, version: .r2000)
        XCTAssertTrue(DXFConformance.audit(good).isEmpty, DXFConformance.audit(good).map(\.description).joined(separator: "\n"))
        func codes(_ t: String) -> Set<String> { Set(DXFConformance.audit(t).map(\.code)) }
        // Entity on a layer missing from the LAYER table.
        let badLayer = good.replacingOccurrences(of: "LINE\n  5\n", with: "LINE\n  8\nGHOST\n  5\n")
        XCTAssertTrue(codes(badLayer).contains("UNKNOWN_LAYER"))
        // Missing ENDSEC / EOF.
        XCTAssertTrue(codes(String(good.dropLast(8))).contains("NO_EOF"))
        // A real number that is not a number.
        XCTAssertTrue(codes(good.replacingOccurrences(of: " 10\n0.0\n", with: " 10\nabc\n")).contains("BAD_REAL") || codes(good.replacingOccurrences(of: " 10\n0\n", with: " 10\nabc\n")).contains("BAD_REAL"))
        // Duplicate handle.
        if let r = good.range(of: "LINE\n  5\n") {
            let after = good[r.upperBound...].prefix { $0 != "\n" }
            let dup = good.replacingOccurrences(of: "CIRCLE\n  5\n", with: "CIRCLE\n  5\n\(after)\n  5\n")
            XCTAssertFalse(codes(dup).isEmpty)
        }
        XCTAssertTrue(codes("0\nSECTION\n2\nENTITIES\n0\nLINE\n").contains("NO_ENDSEC"))
        XCTAssertEqual(DXFConformance.type(of: 10), .double)
        XCTAssertEqual(DXFConformance.type(of: 70), .int)
        XCTAssertEqual(DXFConformance.type(of: 330), .handle)
    }

    @MainActor func testDXFOutReportsTheAudit() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dxfaudit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ed = Editor()
        ed.doc = document()
        let out = await ed.run("DXFOUTVERSION R2018 \(dir.appendingPathComponent("a.dxf").path)").joined(separator: "\n")
        XCTAssertTrue(out.contains("DXF audit: structure, handles and table references are valid."), out)
    }
}
