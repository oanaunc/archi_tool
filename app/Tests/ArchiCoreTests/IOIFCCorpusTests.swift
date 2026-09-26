// Oanarina Archi Tool — GPL-3.0-or-later
// Runs the IFC validator and importer over the third-party IFC files shipped with the IfcOpenShell / Bonsai checkout in
// other_projects (IFC2X3, IFC4, IFC4X3), writes a report to build/interop/ifc-corpus.tsv and checks the WHERE-rule
// checks against IfcOpenShell's pass-/fail- rule fixtures.
import XCTest
@testable import ArchiCore

final class IOIFCCorpusTests: XCTestCase {
    static func corpus() -> [URL] {
        let root = IOInteropCorpusTests.repoRoot.appendingPathComponent("other_projects/IfcOpenShell/src")
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        var out: [URL] = []
        for case let u as URL in en where u.pathExtension.lowercased() == "ifc" {
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 200, size < 3_000_000 { out.append(u) }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Rule each IfcOpenShell fail-* fixture was generated for (file name fragment → issue code fragment).
    static let expected: KeyValuePairs<String, String> = [
        "extrusion-dir-0.0-0.0-ifc4": "IfcDirection.MagnitudeGreaterZero", "box-alignment": "IfcBoxAlignment", "2-projects": "PROJECT-COUNT", "IfcPostalAddress-USERDEFINED": "IfcAddress.WR1",
        "IfcPostalAddress-all-unset": "IfcPostalAddress.WR1", "IfcTelecomAddress-USERDEFINED": "IfcAddress.WR1",
        "IfcTelecomAddress-all-unset": "IfcTelecomAddress.WR1", "actor-role": "IfcActorRole.WR1", "air-terminal-type": "CorrectPredefinedType",
        "annotation-curve-occurence": "IfcAnnotationCurveOccurrence", "annotation-surface": "IfcAnnotationSurface",
        "profile-with-voids-3d-inner": "IfcArbitraryProfileDefWithVoids.WR2", "profile-with-voids-3d-outer": "IfcArbitraryClosedProfileDef.WR1",
        "profile-with-voids-curve": "IfcArbitraryProfileDefWithVoids.WR1", "profile-with-voids-inner-line": "IfcArbitraryProfileDefWithVoids.WR3",
        "assoc-material": "IfcRelAssociatesMaterial", "axis2": "IfcAxis2Placement3D", "bspline-curve": "SameDim", "conv-unit": "IfcNamedUnit.WR1",
        "cshape-profile": "IfcCShapeProfileDef", "site-latitude": "IfcCompoundPlaneAngleMeasure", "extrusion": "IfcExtrudedAreaSolid",
        "font-": "IfcTextStyleFontModel", "lining-properties": "LiningProperties.WR31", "placement-": "IfcLocalPlacement",
        "poly-curve": "IfcIndexedPolyCurve", "property-list-value": "IfcPropertyListValue", "property-same-same": "UniquePropertyNames",
        "rigid-op": "IfcRigidOperation", "shaperep": "CorrectItemsForType", "wall-2-same-psets": "UniquePropertySetNames",
        "wall-mls": "HasMaterialLayerSetUsage", "wall-no-mls": "HasMaterialLayerSetUsage", "zone-with-IfcWall": "IfcZone.WR1",
    ]

    func testValidatorAndImporterOnThirdPartyFiles() throws {
        let files = Self.corpus()
        try XCTSkipIf(files.isEmpty, "IfcOpenShell checkout not present")
        var rows = ["file\tschema\tparsed\telements\terrors\twarnings\tcodes"]
        var oracleFailures: [String] = []
        var checkedFail = 0
        for u in files {
            guard let text = (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1)) else { continue }
            let rel = u.path.components(separatedBy: "other_projects/").last ?? u.lastPathComponent
            let issues = IFCValidator.validate(text)
            let errs = issues.filter { $0.severity == .error }, warns = issues.filter { $0.severity == .warning }
            var elements = -1
            if let r = try? IFCImporter.importFile(text) { elements = r.doc.elements.count + r.doc.entities.count }
            let schema = (try? STEPParser.parse(text))?.schema ?? "?"
            rows.append("\(rel)\t\(schema)\t\(issues.first?.code == "STEP-SYNTAX" ? "no" : "yes")\t\(elements)\t\(errs.count)\t\(warns.count)\t" +
                        errs.map(\.code).joined(separator: ","))
            // IfcOpenShell's rule fixtures are an oracle: pass-* files must raise no WHERE-rule error, fail-* files the rule
            // they were generated for.
            let name = u.lastPathComponent
            if rel.contains("fixtures/rules/") {
                let wr = errs.filter { $0.code.hasPrefix("WR-") }
                if name.hasPrefix("pass-") && !wr.isEmpty { oracleFailures.append("false positive \(name): " + wr.map(\.code).joined(separator: ",")) }
                if name.hasPrefix("fail-") {
                    if let want = Self.expected.first(where: { name.contains($0.key) })?.value {
                        if !issues.contains(where: { $0.code.contains(want) }) { oracleFailures.append("missed \(want) in \(name): " + issues.map(\.code).joined(separator: ",")) }
                        checkedFail += 1
                    }
                    if name.hasPrefix("fail-expected-"), let n = Int(name.dropFirst("fail-expected-".count).prefix { $0.isNumber }) {
                        let found = issues.filter { $0.code.hasPrefix("WR-") }.count
                        if found != n { oracleFailures.append("\(name): expected \(n) rule violations, found \(found)") }
                    }
                }
            }
        }
        let dir = IOInteropCorpusTests.repoRoot.appendingPathComponent("build/interop", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try rows.joined(separator: "\n").write(to: dir.appendingPathComponent("ifc-corpus.tsv"), atomically: true, encoding: .utf8)
        XCTAssertTrue(oracleFailures.isEmpty, oracleFailures.joined(separator: "\n"))
        XCTAssertGreaterThan(checkedFail, 50)
    }

    /// Round trip of third-party models (IO-023, IO-030): import → export IFC4 → the export validates without errors and
    /// keeps the GlobalIds of the imported building elements.
    func testThirdPartyModelsRoundTripValidAndKeepGlobalIds() throws {
        let files = Self.corpus().filter { $0.path.contains("/bonsai/test/files/") || $0.path.contains("/docs/tutorials/") }
        try XCTSkipIf(files.isEmpty, "IfcOpenShell checkout not present")
        var checked = 0, problems: [String] = []
        for u in files {
            guard let text = try? String(contentsOf: u, encoding: .utf8), let src = try? STEPParser.parse(text), src.all("IFCPROJECT").count == 1,
                  let r = try? IFCImporter.importFile(text), !r.doc.elements.isEmpty else { continue }
            checked += 1
            let out = IFCExporter.export(doc: r.doc, meshes: MeshBuilder.build(doc: r.doc))
            let errs = IFCValidator.validate(out).filter { $0.severity == .error }
            if !errs.isEmpty { problems.append("\(u.lastPathComponent): " + errs.map(\.description).joined(separator: "; ")) }
            // GlobalIds of the source's walls / slabs / doors / windows / columns / beams survive.
            let kinds = ["IFCWALL", "IFCWALLSTANDARDCASE", "IFCSLAB", "IFCDOOR", "IFCWINDOW", "IFCCOLUMN", "IFCBEAM"]
            let srcIds = Set(kinds.flatMap { src.all($0) }.compactMap { $0[0].string })
            guard let back = try? STEPParser.parse(out) else { problems.append("\(u.lastPathComponent): export does not parse"); continue }
            let outIds = Set(back.entities.values.compactMap { $0[0].string })
            let lost = srcIds.subtracting(outIds)
            if !lost.isEmpty { problems.append("\(u.lastPathComponent): \(lost.count) of \(srcIds.count) GlobalIds lost") }
        }
        XCTAssertGreaterThan(checked, 3)
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }
}
