// Oanarina Archi Tool — GPL-3.0-or-later
// One entry point to validate exchange files (archi-cli --validate, the validate_file agent tool): IFC STEP / IfcZIP /
// ifcXML against the IFC schema and its WHERE rules (IFCValidator), DXF against the group-code conformance audit
// (DXFConformance) plus a read-back, gbXML against its XSD requirements, and .archi drawings by a save/reopen round trip
// plus the validation of their own IFC (chosen schema) and DXF exports. Any other readable format is reported as read.
import Foundation

public enum FileValidation {
    public struct Issue: Hashable {
        public var severity: String
        public var code: String
        public var message: String
        /// Where: "#12, #15" (STEP instances), "line 40" (DXF) or the export checked ("IFC4 export").
        public var location: String
        public var json: [String: Any] { ["severity": severity, "code": code, "message": message, "location": location] }
    }
    public struct Report {
        public var file: String
        public var format: String
        public var issues: [Issue]
        public var summary: String
        public var valid: Bool { !issues.contains { $0.severity == "error" } }
        public var json: [String: Any] {
            ["file": file, "format": format, "valid": valid, "summary": summary,
             "errors": issues.filter { $0.severity == "error" }.count, "warnings": issues.filter { $0.severity == "warning" }.count,
             "issues": issues.map(\.json)]
        }
    }

    static func ifcIssues(_ text: String, label: String = "") -> [Issue] {
        IFCValidator.validate(text).map { i in
            Issue(severity: i.severity.rawValue, code: i.code, message: i.message,
                  location: (label.isEmpty ? "" : label + " ") + i.instances.prefix(8).map { "#\($0)" }.joined(separator: ", "))
        }
    }
    static func dxfIssues(_ text: String, label: String = "") -> [Issue] {
        var out = DXFConformance.audit(text).map { Issue(severity: $0.severity.rawValue, code: $0.code, message: $0.message, location: (label.isEmpty ? "" : label + " ") + "line \($0.line)") }
        do { _ = try DXFReader.read(text) } catch {
            out.append(Issue(severity: "error", code: "DXF-READ", message: (error as? LocalizedError)?.errorDescription ?? "\(error)", location: label))
        }
        return out
    }

    /// Validates one file. `ifcSchema` chooses the IFC export checked for .archi drawings (default IFC4).
    public static func validate(_ url: URL, ifcSchema: IFCExportOptions.Schema = .ifc4) throws -> Report {
        let f = FileImport.format(for: url)
        let name = url.lastPathComponent
        switch f {
        case "ifc":
            let text = try FileImport.readText(url)
            let issues = ifcIssues(text)
            return Report(file: name, format: "IFC " + ((try? STEPParser.parse(text))?.schema ?? "?"), issues: issues, summary: "\(issues.count) issue(s)")
        case "ifczip":
            let text = try IFCZip.read(try Data(contentsOf: url))
            let issues = ifcIssues(text)
            return Report(file: name, format: "IfcZIP", issues: issues, summary: "\(issues.count) issue(s)")
        case "ifcxml":
            let text = try IFCXML.toSTEP(try Data(contentsOf: url))
            let issues = ifcIssues(text)
            return Report(file: name, format: "ifcXML", issues: issues, summary: "\(issues.count) issue(s)")
        case "dxf":
            let text = try FileImport.readText(url)
            let issues = dxfIssues(text)
            return Report(file: name, format: "DXF", issues: issues, summary: "\(issues.count) issue(s)")
        case "archi":
            let doc = try ArchiFile.decode(Data(contentsOf: url))
            var issues: [Issue] = []
            for d in try ArchiFile.roundTripDifferences(doc) {
                issues.append(Issue(severity: "error", code: "ROUND-TRIP", message: "\(d) changes when saved and reopened", location: ".archi"))
            }
            let o = IFCExportOptions(schema: ifcSchema, modelView: .referenceView)
            issues += ifcIssues(IFCExporter.export(doc: doc, meshes: MeshBuilder.build(doc: doc), options: o), label: "\(ifcSchema.rawValue) export")
            issues += dxfIssues(DXFWriter.write(doc, version: .r2018, levels: nil), label: "DXF export")
            return Report(file: name, format: "Archi drawing", issues: issues,
                          summary: "\(doc.entities.count) objects, \(doc.elements.count) elements; round trip, \(ifcSchema.rawValue) and DXF exports checked")
        default:
            if url.pathExtension.lowercased() == "xml", let text = try? FileImport.readText(url), text.contains("<gbXML") {
                let issues = GBXMLValidator.validate(text).map { Issue(severity: "error", code: $0.code, message: $0.message, location: "") }
                return Report(file: name, format: "gbXML", issues: issues, summary: "\(issues.count) issue(s)")
            }
            let (d, s) = try FileImport.load(url, format: nil)
            return Report(file: name, format: f.uppercased(), issues: [], summary: "read: \(s) (\(d.entities.count) objects, \(d.elements.count) elements)")
        }
    }
}
