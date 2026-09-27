// Oanarina Archi Tool — GPL-3.0-or-later
// Structural validation of gbXML and COBie exports against the required elements of their schemas:
// gbXML 0.37 XSD (required attributes, enumerations, element order where it matters, id references) and the COBie 2.4
// spreadsheet (BS 1192-4: required sheets and columns, required values, name uniqueness and foreign keys).
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ExchangeIssue: Hashable, CustomStringConvertible {
    public var code: String
    public var message: String
    public var description: String { "\(code): \(message)" }
}

public enum GBXMLValidator {
    public static let surfaceTypes: Set<String> = ["InteriorWall", "ExteriorWall", "Roof", "InteriorFloor", "Shade", "UndergroundWall", "UndergroundSlab",
                                                   "Ceiling", "Air", "UndergroundCeiling", "RaisedFloor", "SlabOnGrade", "FreestandingColumn", "EmbeddedColumn"]
    public static let openingTypes: Set<String> = ["FixedWindow", "OperableWindow", "FixedSkylight", "OperableSkylight", "SlidingDoor", "NonSlidingDoor", "Air"]
    /// Required attributes per element (gbXML 0.37 XSD `use="required"`).
    public static let requiredAttributes: [String: [String]] = [
        "gbXML": ["temperatureUnit", "lengthUnit", "areaUnit", "volumeUnit", "useSIUnitsForResults", "version"],
        "Campus": ["id"], "Building": ["id", "buildingType"], "BuildingStorey": ["id"], "Space": ["id"],
        "Surface": ["id", "surfaceType"], "Opening": ["id", "openingType"], "Construction": ["id"], "WindowType": ["id"],
        "AdjacentSpaceId": ["spaceIdRef"], "ProgramInfo": ["id"], "CreatedBy": ["programId", "date", "personId"], "PersonInfo": ["id"],
    ]
    /// Required children per element.
    public static let requiredChildren: [String: [String]] = [
        "gbXML": ["Campus"], "Campus": ["Building"], "Building": ["Area"], "BuildingStorey": ["Level"],
        "PolyLoop": ["CartesianPoint"], "RectangularGeometry": ["CartesianPoint"], "DocumentHistory": ["CreatedBy"],
    ]
    static let references: [String: String] = ["constructionIdRef": "Construction", "windowTypeIdRef": "WindowType", "spaceIdRef": "Space",
                                               "buildingStoreyIdRef": "BuildingStorey", "programId": "ProgramInfo", "personId": "PersonInfo"]

    final class Node {
        let name: String; let attrs: [String: String]; weak var parent: Node?
        var children: [Node] = []; var text = ""
        init(_ n: String, _ a: [String: String], _ p: Node?) { name = n; attrs = a; parent = p }
    }

    final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: Node?; var stack: [Node] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let n = Node(name, attributes, stack.last)
            stack.last?.children.append(n)
            if root == nil { root = n }
            stack.append(n)
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { stack.last?.text += s }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { stack.removeLast() }
    }

    public static func validate(_ xml: String) -> [ExchangeIssue] {
        var out: [ExchangeIssue] = []
        func issue(_ c: String, _ m: String) { out.append(ExchangeIssue(code: c, message: m)) }
        let tb = TreeBuilder()
        let p = XMLParser(data: Data(xml.utf8)); p.delegate = tb
        // Some XML parsers (the open-source Foundation on Windows/Linux) accept unclosed elements, so check the nesting too.
        guard p.parse(), tb.stack.isEmpty, let root = tb.root else { return [ExchangeIssue(code: "XML-SYNTAX", message: p.parserError?.localizedDescription ?? "not well-formed")] }
        guard root.name == "gbXML" else { return [ExchangeIssue(code: "ROOT", message: "root element is \(root.name), expected gbXML")] }
        if let ns = root.attrs["xmlns"], ns != "http://www.gbxml.org/schema" { issue("NAMESPACE", "gbXML must use the namespace http://www.gbxml.org/schema") }
        var ids: [String: String] = [:]   // id → element name
        var all: [Node] = []
        func walk(_ n: Node) { all.append(n); n.children.forEach(walk) }
        walk(root)
        for n in all {
            for a in requiredAttributes[n.name] ?? [] where (n.attrs[a] ?? "").isEmpty { issue("ATTRIBUTE-MISSING", "\(n.name) lacks required attribute \(a)") }
            for c in requiredChildren[n.name] ?? [] where !n.children.contains(where: { $0.name == c }) { issue("CHILD-MISSING", "\(n.name)\(n.attrs["id"].map { " \($0)" } ?? "") lacks required element \(c)") }
            if let id = n.attrs["id"], ["Campus", "Building", "BuildingStorey", "Space", "Surface", "Opening", "Construction", "WindowType", "ProgramInfo", "PersonInfo", "Layer", "Material"].contains(n.name) {
                if ids[id] != nil { issue("ID-DUPLICATE", "id \(id) is used twice") }
                ids[id] = n.name
            }
            switch n.name {
            case "Surface":
                if let t = n.attrs["surfaceType"], !surfaceTypes.contains(t) { issue("ENUM", "surfaceType \(t) is not in the gbXML enumeration") }
                if !n.children.contains(where: { $0.name == "PlanarGeometry" }) { issue("GEOMETRY-MISSING", "Surface \(n.attrs["id"] ?? "?") has no PlanarGeometry") }
                order(n, ["Name", "Description", "AdjacentSpaceId", "RectangularGeometry", "PlanarGeometry", "Opening", "CADObjectId"], &out)
                if n.attrs["surfaceType"] == "ExteriorWall" || n.attrs["surfaceType"] == "Roof" || n.attrs["surfaceType"] == "SlabOnGrade",
                   n.children.filter({ $0.name == "AdjacentSpaceId" }).count > 1 { issue("ADJACENCY", "exterior Surface \(n.attrs["id"] ?? "?") has more than one adjacent space") }
            case "Opening":
                if let t = n.attrs["openingType"], !openingTypes.contains(t) { issue("ENUM", "openingType \(t) is not in the gbXML enumeration") }
            case "PolyLoop":
                let pts = n.children.filter { $0.name == "CartesianPoint" }
                if pts.count < 3 { issue("POLYLOOP", "PolyLoop with \(pts.count) points (needs 3)") }
                for c in pts {
                    let co = c.children.filter { $0.name == "Coordinate" }
                    if co.count != 3 { issue("COORDINATE", "PolyLoop point with \(co.count) coordinates") }
                    for v in co where Double(v.text.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { issue("NUMBER", "coordinate '\(v.text)' is not a number") }
                }
            case "Construction": order(n, ["U-value", "Absorptance", "Roughness", "Albedo", "Reflectance", "Transmittance", "Name", "Description", "LayerId"], &out)
            case "WindowType": order(n, ["Name", "Description", "U-value", "SolarHeatGainCoeff", "Transmittance"], &out)
            case "RectangularGeometry": order(n, ["Azimuth", "CartesianPoint", "Tilt", "Width", "Height"], &out)
            case "Area", "Volume", "Level", "U-value", "Width", "Height", "Tilt", "Azimuth", "Latitude", "Longitude":
                if Double(n.text.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { issue("NUMBER", "\(n.name) '\(n.text)' is not a number") }
            default: break
            }
        }
        for n in all {
            for (attr, target) in references {
                guard let ref = n.attrs[attr] else { continue }
                if ids[ref] != target { issue("DANGLING-REFERENCE", "\(n.name) \(attr)=\(ref) does not name a \(target)") }
            }
        }
        return out
    }

    /// Children listed in `seq` must appear in that relative order.
    static func order(_ n: Node, _ seq: [String], _ out: inout [ExchangeIssue]) {
        var last = -1
        for c in n.children {
            guard let i = seq.firstIndex(of: c.name) else { continue }
            if i < last { out.append(ExchangeIssue(code: "ORDER", message: "\(n.name) \(n.attrs["id"] ?? ""): \(c.name) out of schema order")); return }
            last = i
        }
    }
}

public enum COBieValidator {
    /// COBie 2.4 required columns per sheet, in order (the first N columns of each sheet).
    public static let columns: [String: [String]] = [
        "Contact": ["Email", "CreatedBy", "CreatedOn", "Category", "Company", "Phone"],
        "Facility": ["Name", "CreatedBy", "CreatedOn", "Category", "ProjectName", "SiteName", "LinearUnits", "AreaUnits", "VolumeUnits", "CurrencyUnit", "AreaMeasurement"],
        "Floor": ["Name", "CreatedBy", "CreatedOn", "Category", "ExtSystem", "ExtObject", "ExtIdentifier", "Description", "Elevation", "Height"],
        "Space": ["Name", "CreatedBy", "CreatedOn", "Category", "FloorName", "Description", "ExtSystem", "ExtObject", "ExtIdentifier", "RoomTag", "UsableHeight", "GrossArea", "NetArea"],
        "Type": ["Name", "CreatedBy", "CreatedOn", "Category", "Description", "AssetType"],
        "Component": ["Name", "CreatedBy", "CreatedOn", "TypeName", "Space", "Description"],
        "Attribute": ["Name", "CreatedBy", "CreatedOn", "Category", "SheetName", "RowName", "Value", "Unit"],
    ]
    /// Columns that must hold a value (not blank) in every row.
    static let required: Set<String> = ["Name", "Email", "CreatedBy", "CreatedOn", "Category", "FloorName", "TypeName", "Space", "SheetName", "RowName", "Value",
                                        "ProjectName", "SiteName", "LinearUnits", "AreaUnits", "VolumeUnits", "CurrencyUnit", "AreaMeasurement", "Description", "AssetType"]

    public static func validate(_ sheets: [XLSX.Sheet]) -> [ExchangeIssue] {
        var out: [ExchangeIssue] = []
        func issue(_ c: String, _ m: String) { out.append(ExchangeIssue(code: c, message: m)) }
        var byName: [String: XLSX.Sheet] = [:]
        for s in sheets { byName[s.name] = s }
        func col(_ s: XLSX.Sheet, _ c: String) -> Int? { s.rows.first?.firstIndex(of: c) }
        func values(_ sheet: String, _ c: String) -> [String] {
            guard let s = byName[sheet], let i = col(s, c) else { return [] }
            return s.rows.dropFirst().map { i < $0.count ? $0[i] : "" }
        }
        let iso = ISO8601DateFormatter()
        for (name, cols) in columns.sorted(by: { $0.key < $1.key }) {
            guard let s = byName[name] else { issue("SHEET-MISSING", "sheet \(name) is missing"); continue }
            let head = s.rows.first ?? []
            if Array(head.prefix(cols.count)) != cols { issue("COLUMNS", "\(name) columns must start with \(cols.joined(separator: ", "))") }
            for (r, row) in s.rows.enumerated().dropFirst() {
                for (i, c) in head.enumerated() where required.contains(c) {
                    let v = i < row.count ? row[i].trimmingCharacters(in: .whitespaces) : ""
                    if v.isEmpty { issue("VALUE-MISSING", "\(name) row \(r + 1): \(c) is empty") }
                    if c == "CreatedOn", !v.isEmpty, iso.date(from: v) == nil { issue("DATE", "\(name) row \(r + 1): CreatedOn '\(v)' is not ISO 8601") }
                }
            }
            if name != "Attribute", name != "Contact", let i = col(s, "Name") {
                var seen = Set<String>()
                for row in s.rows.dropFirst() where i < row.count { if !seen.insert(row[i]).inserted { issue("NAME-DUPLICATE", "\(name) name \(row[i]) is not unique") } }
            }
        }
        if byName["Facility"].map({ $0.rows.count != 2 }) ?? false { issue("FACILITY", "Facility must have exactly one row") }
        let emails = Set(values("Contact", "Email"))
        for e in emails where !(e.contains("@") && e.contains(".")) { issue("EMAIL", "contact \(e) is not an e-mail address") }
        for sheet in columns.keys.sorted() { for v in Set(values(sheet, "CreatedBy")) where !emails.contains(v) { issue("FOREIGN-KEY", "\(sheet).CreatedBy \(v) is not a Contact") } }
        let floors = Set(values("Floor", "Name")), spaces = Set(values("Space", "Name")), types = Set(values("Type", "Name"))
        for v in Set(values("Space", "FloorName")) where !floors.contains(v) { issue("FOREIGN-KEY", "Space.FloorName \(v) is not a Floor") }
        for v in Set(values("Component", "TypeName")) where !types.contains(v) { issue("FOREIGN-KEY", "Component.TypeName \(v) is not a Type") }
        for v in Set(values("Component", "Space")) {
            for part in v.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where part != "n/a" && !spaces.contains(part) {
                issue("FOREIGN-KEY", "Component.Space \(part) is not a Space")
            }
        }
        if let att = byName["Attribute"], let si = col(att, "SheetName"), let ri = col(att, "RowName") {
            for row in att.rows.dropFirst() where si < row.count && ri < row.count {
                let target = values(row[si], "Name")
                if byName[row[si]] == nil || !target.contains(row[ri]) { issue("FOREIGN-KEY", "Attribute \(row.first ?? "") points to missing \(row[si]) row \(row[ri])") }
            }
        }
        return out
    }
}
