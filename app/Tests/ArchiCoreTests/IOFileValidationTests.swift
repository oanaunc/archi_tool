// Oanarina Archi Tool — GPL-3.0-or-later
// FileValidation (archi-cli --validate, validate_file tool): IFC, DXF and .archi files.
import XCTest
@testable import ArchiCore

final class IOFileValidationTests: XCTestCase {
    func tmp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-validate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testValidatesIFCDXFAndDrawings() throws {
        let dir = try tmp()
        let d = IOIFCSchemaTests().model()
        let archi = dir.appendingPathComponent("m.archi")
        try ArchiFile.encode(d).write(to: archi)
        for sc in IFCExportOptions.Schema.allCases {
            let r = try FileValidation.validate(archi, ifcSchema: sc)
            XCTAssertTrue(r.valid, "\(sc): " + r.issues.filter { $0.severity == "error" }.map { "\($0.code) \($0.location) \($0.message)" }.joined(separator: "; "))
            XCTAssertEqual(r.format, "Archi drawing")
        }
        let ifc = dir.appendingPathComponent("m.ifc")
        try IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d)).write(to: ifc, atomically: true, encoding: .utf8)
        XCTAssertTrue(try FileValidation.validate(ifc).valid)
        let bad = dir.appendingPathComponent("bad.ifc")
        try AnalysisIFCWhereRulesTests.broken.write(to: bad, atomically: true, encoding: .utf8)
        let rb = try FileValidation.validate(bad)
        XCTAssertFalse(rb.valid)
        XCTAssertTrue(rb.issues.contains { $0.code == "WR-IfcAxis2Placement3D.AxisToRefDirPosition" && $0.location == "#15" })
        let dxf = dir.appendingPathComponent("m.dxf")
        try DXFWriter.write(d, version: .r2013, levels: nil).write(to: dxf, atomically: true, encoding: .utf8)
        let rd = try FileValidation.validate(dxf)
        XCTAssertTrue(rd.valid, rd.issues.map(\.message).joined(separator: "; "))
        let broken = dir.appendingPathComponent("broken.dxf")
        try "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n 10\nabc\n  0\nENDSEC\n  0\nEOF\n".write(to: broken, atomically: true, encoding: .utf8)
        XCTAssertFalse(try FileValidation.validate(broken).valid)
        let json = try FileValidation.validate(bad).json
        XCTAssertTrue(JSONSerialization.isValidJSONObject(json))
        // Agent tool.
        let t = try XCTUnwrap(AgentTools.call("validate_file", ["path": bad.path], doc: ArchiDocument()) as? [String: Any])
        XCTAssertEqual(t["valid"] as? Bool, false)
        XCTAssertThrowsError(try AgentTools.call("validate_file", [:], doc: ArchiDocument()))
    }

    func testCLIValidateExitCodes() throws {
        let tools = AnalysisAgentToolsTests()
        let exe = try tools.cli()
        let dir = try tmp()
        let good = dir.appendingPathComponent("good.dxf"), bad = dir.appendingPathComponent("bad.ifc")
        var doc = ArchiDocument(); doc.add(.line(LineGeom(.zero, Vec2(100, 0))))
        try DXFWriter.write(doc).write(to: good, atomically: true, encoding: .utf8)
        try AnalysisIFCWhereRulesTests.broken.write(to: bad, atomically: true, encoding: .utf8)
        let ok = try tools.run(exe, ["--validate", good.path], input: "")
        XCTAssertEqual(ok.status, 0, ok.out)
        XCTAssertTrue(ok.out.contains("VALID"))
        let no = try tools.run(exe, ["--validate", good.path, bad.path, "--json"], input: "")
        XCTAssertEqual(no.status, 1, no.out)
        let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(no.out.utf8)) as? [[String: Any]])
        XCTAssertEqual(arr.map { $0["valid"] as? Bool }, [true, false])
        XCTAssertEqual(try tools.run(exe, ["--validate", dir.appendingPathComponent("missing.ifc").path], input: "").status, 2)
    }
}
