// Oanarina Archi Tool — GPL-3.0-or-later
// IFC file validation: STEP syntax, header schema, dangling references, GlobalId format and uniqueness, attribute
// counts of common IFC2x3/IFC4 entities, required project/units/context, and products outside the spatial structure.
// A pragmatic subset of buildingSMART's validation service (schema and "normative rules" basics), not a full
// EXPRESS checker.
import Foundation

public struct IFCValidationIssue: Hashable {
    public var severity: IssueSeverity
    public var code: String
    public var message: String
    /// STEP instance ids (#n) involved.
    public var instances: [Int]
    public var description: String { "[\(severity.rawValue.uppercased())] \(code): \(message)" + (instances.isEmpty ? "" : " (" + instances.prefix(8).map { "#\($0)" }.joined(separator: ", ") + (instances.count > 8 ? ", …" : "") + ")") }
}

public enum IFCValidator {
    /// Explicit attribute counts (IFC4 / IFC2X3) of frequently used entities.
    static let counts4: [String: Int] = [
        "IFCPROJECT": 9, "IFCSITE": 14, "IFCBUILDING": 12, "IFCBUILDINGSTOREY": 10, "IFCSPACE": 11,
        "IFCWALL": 9, "IFCWALLSTANDARDCASE": 9, "IFCSLAB": 9, "IFCCOLUMN": 9, "IFCBEAM": 9, "IFCDOOR": 13, "IFCWINDOW": 13,
        "IFCROOF": 9, "IFCSTAIR": 9, "IFCRAILING": 9, "IFCRAMP": 9, "IFCRAMPFLIGHT": 9, "IFCFOOTING": 9, "IFCCOVERING": 9,
        "IFCCURTAINWALL": 9, "IFCOPENINGELEMENT": 9, "IFCBUILDINGELEMENTPROXY": 9, "IFCFURNISHINGELEMENT": 8,
        "IFCRELAGGREGATES": 6, "IFCRELCONTAINEDINSPATIALSTRUCTURE": 6, "IFCRELVOIDSELEMENT": 6, "IFCRELFILLSELEMENT": 6,
        "IFCRELDEFINESBYPROPERTIES": 6, "IFCRELASSOCIATESMATERIAL": 6, "IFCRELASSIGNSTOGROUP": 7, "IFCGROUP": 5,
        "IFCPROPERTYSET": 5, "IFCPROPERTYSINGLEVALUE": 4, "IFCOWNERHISTORY": 8, "IFCLOCALPLACEMENT": 2, "IFCAXIS2PLACEMENT3D": 3,
        "IFCAXIS2PLACEMENT2D": 2, "IFCCARTESIANPOINT": 1, "IFCDIRECTION": 1, "IFCEXTRUDEDAREASOLID": 4, "IFCSHAPEREPRESENTATION": 4,
        "IFCPRODUCTDEFINITIONSHAPE": 3, "IFCRECTANGLEPROFILEDEF": 5, "IFCARBITRARYCLOSEDPROFILEDEF": 3, "IFCPOLYLINE": 1,
        "IFCMATERIAL": 3, "IFCSIUNIT": 4, "IFCUNITASSIGNMENT": 1, "IFCGEOMETRICREPRESENTATIONCONTEXT": 6,
    ]
    static let counts2x3: [String: Int] = [
        "IFCPROJECT": 9, "IFCSITE": 14, "IFCBUILDING": 12, "IFCBUILDINGSTOREY": 10, "IFCSPACE": 11,
        "IFCWALL": 8, "IFCWALLSTANDARDCASE": 8, "IFCSLAB": 9, "IFCCOLUMN": 8, "IFCBEAM": 8, "IFCDOOR": 10, "IFCWINDOW": 10,
        "IFCROOF": 9, "IFCSTAIR": 9, "IFCRAILING": 9, "IFCOPENINGELEMENT": 8, "IFCBUILDINGELEMENTPROXY": 9,
        "IFCRELAGGREGATES": 6, "IFCRELCONTAINEDINSPATIALSTRUCTURE": 6, "IFCRELVOIDSELEMENT": 6, "IFCRELFILLSELEMENT": 6,
        "IFCPROPERTYSET": 5, "IFCPROPERTYSINGLEVALUE": 4, "IFCLOCALPLACEMENT": 2, "IFCAXIS2PLACEMENT3D": 3, "IFCCARTESIANPOINT": 1,
        "IFCDIRECTION": 1, "IFCEXTRUDEDAREASOLID": 4, "IFCSHAPEREPRESENTATION": 4, "IFCPRODUCTDEFINITIONSHAPE": 3,
    ]
    /// Attribute counts that differ in IFC4.3 (ADD2) from IFC4.
    static let counts4x3: [String: Int] = ["IFCCARTESIANPOINTLIST3D": 2]
    static let extra4: [String: Int] = [
        "IFCTRIANGULATEDFACESET": 5, "IFCPOLYGONALFACESET": 4, "IFCCARTESIANPOINTLIST3D": 1, "IFCMAPCONVERSION": 8, "IFCPROJECTEDCRS": 7,
        "IFCQUANTITYLENGTH": 5, "IFCQUANTITYAREA": 5, "IFCQUANTITYVOLUME": 5, "IFCQUANTITYCOUNT": 5, "IFCELEMENTQUANTITY": 6,
        "IFCMATERIALLAYER": 7, "IFCMATERIALLAYERSET": 3, "IFCMATERIALLAYERSETUSAGE": 5, "IFCDOORTYPE": 13, "IFCWINDOWTYPE": 13,
        "IFCWALLTYPE": 10, "IFCRELDEFINESBYTYPE": 6, "IFCSTYLEDITEM": 3, "IFCFURNITURE": 9, "IFCSANITARYTERMINAL": 9, "IFCLIGHTFIXTURE": 9,
        "IFCELECTRICAPPLIANCE": 9, "IFCMEMBER": 9, "IFCPLATE": 9, "IFCTRANSPORTELEMENT": 9, "IFCGEOGRAPHICELEMENT": 9,
        "IFCWORKSCHEDULE": 14, "IFCTASK": 13, "IFCTASKTIME": 20, "IFCRELSEQUENCE": 9, "IFCRELASSIGNSTOPROCESS": 8, "IFCRELASSIGNSTOCONTROL": 7,
        "IFCRELDECLARES": 6, "IFCLAGTIME": 5,
    ]
    static let extra2x3: [String: Int] = [
        "IFCQUANTITYLENGTH": 4, "IFCQUANTITYAREA": 4, "IFCQUANTITYVOLUME": 4, "IFCQUANTITYCOUNT": 4, "IFCELEMENTQUANTITY": 6,
        "IFCMATERIAL": 1, "IFCMATERIALLAYER": 3, "IFCMATERIALLAYERSET": 2, "IFCMATERIALLAYERSETUSAGE": 4, "IFCDOORSTYLE": 12, "IFCWINDOWSTYLE": 12,
        "IFCWALLTYPE": 10, "IFCRELDEFINESBYTYPE": 6, "IFCSTYLEDITEM": 3, "IFCPRESENTATIONSTYLEASSIGNMENT": 1, "IFCFLOWTERMINAL": 8,
        "IFCFURNISHINGELEMENT": 8, "IFCCURTAINWALL": 8, "IFCRAMPFLIGHT": 8, "IFCMEMBER": 8, "IFCPLATE": 8, "IFCTRANSPORTELEMENT": 11,
        "IFCRELDEFINESBYPROPERTIES": 6, "IFCRELASSOCIATESMATERIAL": 6, "IFCOWNERHISTORY": 8, "IFCSIUNIT": 4, "IFCGEOMETRICREPRESENTATIONCONTEXT": 6,
    ]
    /// Entities that do not exist in a schema (written by mistake for that schema).
    static let notIn2x3: Set<String> = ["IFCDOORTYPE", "IFCWINDOWTYPE", "IFCTRIANGULATEDFACESET", "IFCPOLYGONALFACESET", "IFCCARTESIANPOINTLIST3D",
                                        "IFCMAPCONVERSION", "IFCPROJECTEDCRS", "IFCFURNITURE", "IFCSANITARYTERMINAL", "IFCLIGHTFIXTURE",
                                        "IFCELECTRICAPPLIANCE", "IFCGEOGRAPHICELEMENT", "IFCSHADINGDEVICE", "IFCCHIMNEY", "IFCINDEXEDPOLYCURVE",
                                        "IFCSURFACESTYLEWITHTEXTURES_X", "IFCCIVILELEMENT"]
    static let notIn4x3: Set<String> = ["IFCWALLSTANDARDCASE", "IFCSLABSTANDARDCASE", "IFCCOLUMNSTANDARDCASE", "IFCBEAMSTANDARDCASE", "IFCMEMBERSTANDARDCASE",
                                        "IFCPLATESTANDARDCASE", "IFCDOORSTANDARDCASE", "IFCWINDOWSTANDARDCASE", "IFCOPENINGSTANDARDCASE",
                                        "IFCWALLELEMENTEDCASE", "IFCSLABELEMENTEDCASE", "IFCDOORSTYLE", "IFCWINDOWSTYLE", "IFCPRESENTATIONSTYLEASSIGNMENT"]
    static let notIn4: Set<String> = ["IFCPRESENTATIONSTYLEASSIGNMENT_NONE", "IFCALIGNMENTSEGMENT", "IFCFACILITY", "IFCROAD", "IFCBRIDGE", "IFCRAILWAY",
                                      "IFCFACILITYPART", "IFCCOURSE", "IFCPAVEMENT", "IFCKERB", "IFCEARTHWORKSFILL"]
    static let spatial: Set<String> = ["IFCPROJECT", "IFCSITE", "IFCBUILDING", "IFCBUILDINGSTOREY", "IFCSPACE"]

    public static func validate(_ text: String) -> [IFCValidationIssue] {
        var out: [IFCValidationIssue] = []
        func issue(_ s: IssueSeverity, _ c: String, _ m: String, _ ids: [Int] = []) { out.append(IFCValidationIssue(severity: s, code: c, message: m, instances: ids)) }
        let f: STEPFile
        do { f = try STEPParser.parse(text) } catch {
            issue(.error, "STEP-SYNTAX", (error as? LocalizedError)?.errorDescription ?? "\(error)"); return out
        }
        let schema = f.schema.uppercased()
        if schema.isEmpty { issue(.error, "HEADER-SCHEMA", "FILE_SCHEMA is missing") }
        else if !schema.hasPrefix("IFC") { issue(.error, "HEADER-SCHEMA", "FILE_SCHEMA '\(f.schema)' is not an IFC schema") }
        let is2x3 = schema.hasPrefix("IFC2X3"), is4x3 = schema.hasPrefix("IFC4X3")
        var counts = is2x3 ? counts2x3 : counts4
        counts.merge(is2x3 ? extra2x3 : extra4) { $1 }
        if is4x3 { counts.merge(counts4x3) { $1 } }
        // Entities outside the declared schema.
        let foreign = is2x3 ? notIn2x3 : is4x3 ? notIn4x3 : notIn4
        let wrong = f.entities.values.filter { foreign.contains($0.type) }.map(\.id).sorted()
        if !wrong.isEmpty {
            let names = Set(wrong.compactMap { f.entities[$0]?.type }).sorted().joined(separator: ", ")
            issue(.error, "SCHEMA-ENTITY", "\(wrong.count) instance(s) of entities not defined in \(schema): \(names)", wrong)
        }
        // Model view definition: Reference View geometry is tessellated or swept; faceted B-reps belong to DTV / CV 2.0.
        let header = (text.range(of: "DATA;").map { String(text[..<$0.lowerBound]) } ?? "").uppercased()
        if header.contains("REFERENCEVIEW") {
            let breps = f.all("IFCFACETEDBREP").map(\.id)
            if !breps.isEmpty { issue(.warning, "MVD-REFERENCEVIEW", "\(breps.count) IfcFacetedBrep item(s) in a Reference View file (use IfcTriangulatedFaceSet)", breps) }
        }
        // References
        var dangling: [Int] = []
        func refs(_ v: StepValue) -> [Int] {
            switch v {
            case .ref(let r): return [r]
            case .list(let l): return l.flatMap(refs)
            case .typed(_, let a): return a.flatMap(refs)
            default: return []
            }
        }
        for e in f.entities.values.sorted(by: { $0.id < $1.id }) {
            let rs = e.args.flatMap(refs) + e.parts.values.flatMap { $0.flatMap(refs) }
            if rs.contains(where: { f.entities[$0] == nil }) { dangling.append(e.id) }
            if let n = counts[e.type], e.parts.isEmpty, e.args.count != n {
                issue(.error, "ATTRIBUTE-COUNT", "\(e.type) has \(e.args.count) attributes, \(is2x3 ? "IFC2X3" : is4x3 ? "IFC4X3" : "IFC4") expects \(n)", [e.id])
            }
        }
        if !dangling.isEmpty { issue(.error, "DANGLING-REFERENCE", "\(dangling.count) instance(s) reference undefined instances", dangling) }
        // GlobalIds of rooted entities (first attribute is a 22-character string on IfcRoot subtypes).
        var seen: [String: Int] = [:]
        var dup: [Int] = [], bad: [Int] = []
        let rootPrefixes = ["IFCREL", "IFCPROPERTYSET", "IFCELEMENTQUANTITY", "IFCGROUP"]
        for e in f.entities.values.sorted(by: { $0.id < $1.id }) {
            // IfcRoot subtypes: GlobalId then OwnerHistory (a reference, or $ in IFC4).
            let ownerRef = e[1].ref.map { f.entities[$0]?.type == "IFCOWNERHISTORY" } ?? false
            let rooted = ownerRef || (e[1].isNull && (spatial.contains(e.type) || rootPrefixes.contains { e.type.hasPrefix($0) } || (counts[e.type] ?? 0) >= 8))
            guard rooted, e.args.count >= 4, let g = e[0].string else { continue }
            if !IFCExporter.isValidGuid(g) { bad.append(e.id) }
            if seen[g] != nil { dup.append(e.id) } else { seen[g] = e.id }
        }
        if !bad.isEmpty { issue(.error, "GLOBALID-FORMAT", "\(bad.count) GlobalId(s) are not 22-character IFC base-64 strings", bad) }
        if !dup.isEmpty { issue(.error, "GLOBALID-DUPLICATE", "\(dup.count) GlobalId(s) are used more than once", dup) }
        // Project, units, context
        let projects = f.all("IFCPROJECT")
        if projects.count != 1 { issue(.error, "PROJECT-COUNT", "The file must contain exactly one IfcProject (found \(projects.count))", projects.map(\.id)) }
        if let p = projects.first {
            if f[p[8].ref]?.type != "IFCUNITASSIGNMENT" { issue(.error, "PROJECT-UNITS", "IfcProject has no unit assignment", [p.id]) }
            if (p[7].list ?? []).isEmpty { issue(.warning, "PROJECT-CONTEXT", "IfcProject has no representation context", [p.id]) }
        }
        // Spatial containment of products with a placement.
        var placed = Set<Int>()
        for r in f.all("IFCRELCONTAINEDINSPATIALSTRUCTURE") { placed.formUnion(r[4].refs) }
        for r in f.all("IFCRELAGGREGATES") { placed.formUnion(r[5].refs) }
        var loose: [Int] = []
        for e in f.entities.values where !spatial.contains(e.type) && e.type != "IFCOPENINGELEMENT" && e.args.count >= 8 {
            guard e[0].string != nil, f[e[5].ref]?.type == "IFCLOCALPLACEMENT" || f[e[5].ref]?.type == "IFCGRIDPLACEMENT" else { continue }
            let isFilling = f.all("IFCRELFILLSELEMENT").contains { $0[5].ref == e.id }
            if !placed.contains(e.id) && !isFilling { loose.append(e.id) }
        }
        if !loose.isEmpty { issue(.warning, "SPATIAL-CONTAINMENT", "\(loose.count) product(s) are not contained in a storey/building/site", loose.sorted()) }
        // Openings must void an element.
        let voids = Set(f.all("IFCRELVOIDSELEMENT").compactMap { $0[5].ref })
        let orphan = f.all("IFCOPENINGELEMENT").map(\.id).filter { !voids.contains($0) }
        if !orphan.isEmpty { issue(.warning, "OPENING-ORPHAN", "\(orphan.count) IfcOpeningElement(s) void no element", orphan) }
        return out
    }
}
