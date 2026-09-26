// Oanarina Archi Tool — GPL-3.0-or-later
// IFC file validation (ANL-041): STEP syntax, header schema, dangling references, GlobalId format and uniqueness,
// schema conformance of every instance against the full IFC2X3 / IFC4 / IFC4X3 ADD2 entity tables (unknown and abstract
// classes, attribute counts, DERIVED redeclarations written as *, required attributes left unset, attribute value kinds:
// references, enumerations, booleans, numbers, strings, lists, typed values of defined types), required
// project/units/context, and products outside the spatial structure. Issues on the model's own export map back to the
// drawing's elements (zoom-to). WHERE rules of the common resource/product entities are evaluated in IFCWhereRules.swift;
// global rules and functions of the EXPRESS schemas are not.
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

    /// Instance-level conformance to the schema's entity definitions (issues grouped by kind, class and attribute).
    static func schemaIssues(_ f: STEPFile, _ t: IFCSchemaTable, skip: Set<String> = []) -> [IFCValidationIssue] {
        var groups: [String: (sev: IssueSeverity, code: String, msg: String, ids: [Int])] = [:]
        var order: [String] = []
        func add(_ sev: IssueSeverity, _ code: String, _ msg: String, _ id: Int) {
            let k = code + "|" + msg
            if groups[k] == nil { groups[k] = (sev, code, msg, []); order.append(k) }
            groups[k]!.ids.append(id)
        }
        func simpleOK(_ v: StepValue, _ k: Character) -> Bool {
            switch k {
            case "s": if case .string = v { return true }; return false
            case "r", "u": switch v { case .real, .int: return true; default: return false }
            case "i": if case .int = v { return true }; return false
            case "b": if case .enumeration(let e) = v { return ["T", "F", "U"].contains(e) }; return false
            case "n": if case .enumeration = v { return true }; return false
            case "x": if case .ref = v { return false }; return true
            default: return true
            }
        }
        func kindOK(_ v: StepValue, _ kind: String) -> Bool {
            guard let k = kind.first else { return true }
            switch k {
            case "e": if case .ref = v { return true }; return false
            case "v":
                switch v {
                case .ref: return true
                case .typed(let n, _): return t.types[n.uppercased()] != nil
                default: return false
                }
            case "E":
                guard let l = v.list else { return false }
                return l.allSatisfy { x in if case .ref = x { return true }; if case .typed(let n, _) = x { return t.types[n.uppercased()] != nil }; return false }
            case "L":
                guard let l = v.list, let ik = kind.dropFirst().first else { return false }
                return l.allSatisfy { simpleOK($0, ik) }
            case "M":
                guard let l = v.list, let ik = kind.dropFirst().first else { return false }
                return l.allSatisfy { row in (row.list ?? []).allSatisfy { simpleOK($0, ik) } && row.list != nil }
            default: return simpleOK(v, k)
            }
        }
        func kindName(_ kind: String) -> String {
            switch kind.first {
            case "s": return "a string"; case "r": return "a real number"; case "u": return "a number"; case "i": return "an integer"
            case "b": return "a boolean/logical (.T./.F./.U.)"; case "n": return "an enumeration"; case "e": return "an instance reference"
            case "v": return "a reference or a typed value"; case "E": return "a list of references or typed values"
            case "L": return "a list of simple values"; case "M": return "a list of lists"; default: return "a value"
            }
        }
        for e in f.entities.values.sorted(by: { $0.id < $1.id }) where e.parts.isEmpty && !skip.contains(e.type) {
            guard let attrs = t.attributes(e.type) else { add(.error, "SCHEMA-ENTITY", "\(e.type) is not an entity of \(t.name)", e.id); continue }
            if t.isAbstract(e.type) { add(.error, "ABSTRACT-INSTANCE", "\(t.className(e.type) ?? e.type) is abstract and cannot be instantiated", e.id) }
            guard e.args.count == attrs.count else {
                add(.error, "ATTRIBUTE-COUNT", "\(e.type) has \(e.args.count) attributes, \(t.name) expects \(attrs.count)", e.id); continue
            }
            let cls = t.className(e.type) ?? e.type
            for (i, a) in attrs.enumerated() {
                let v = e.args[i]
                if a.derived {
                    if case .derived = v { continue }
                    add(.error, "ATTRIBUTE-DERIVED", "\(cls).\(a.attr.name) is derived and must be written as *", e.id); continue
                }
                switch v {
                case .derived: add(.error, "ATTRIBUTE-DERIVED", "\(cls).\(a.attr.name) is not derived: * is not allowed", e.id)
                case .null: if !a.attr.optional { add(.error, "ATTRIBUTE-REQUIRED", "\(cls).\(a.attr.name) is required but not set ($)", e.id) }
                default:
                    if !kindOK(v, a.attr.kind) { add(.error, "ATTRIBUTE-TYPE", "\(cls).\(a.attr.name) must be \(kindName(a.attr.kind))", e.id) }
                }
            }
        }
        return order.map { k in
            let g = groups[k]!
            return IFCValidationIssue(severity: g.sev, code: g.code, message: g.ids.count > 1 ? "\(g.msg) (\(g.ids.count) instances)" : g.msg, instances: g.ids)
        }
    }

    /// Normative rules (after buildingSMART's validation service): spatial structure decomposition, resource instances
    /// not used by any rooted object, and closed shells / face sets that are not closed (every edge twice, opposite).
    static func normativeIssues(_ f: STEPFile, _ t: IFCSchemaTable) -> [IFCValidationIssue] {
        var out: [IFCValidationIssue] = []
        func refs(_ v: StepValue) -> [Int] {
            switch v { case .ref(let r): return [r]; case .list(let l): return l.flatMap(refs); case .typed(_, let a): return a.flatMap(refs); default: return [] }
        }
        // Spatial structure: storeys in buildings, buildings in sites (or the project), sites in the project.
        var parentOf: [Int: Int] = [:]
        for r in f.all("IFCRELAGGREGATES") { if let p = r[4].ref { for c in r[5].refs { parentOf[c] = p } } }
        func type(_ id: Int?) -> String { id.flatMap { f[$0]?.type } ?? "" }
        var bad: [Int] = []
        for e in f.all("IFCBUILDINGSTOREY") where !(type(parentOf[e.id]) == "IFCBUILDING" || t.isSubtype(type(parentOf[e.id]), of: "IFCBUILDING")) { bad.append(e.id) }
        for e in f.all("IFCBUILDING") where !["IFCSITE", "IFCPROJECT"].contains(type(parentOf[e.id])) { bad.append(e.id) }
        for e in f.all("IFCSITE") where !["IFCPROJECT", "IFCSITE"].contains(type(parentOf[e.id])) { bad.append(e.id) }
        if !bad.isEmpty { out.append(IFCValidationIssue(severity: .error, code: "SPATIAL-STRUCTURE", message: "\(bad.count) spatial element(s) are not decomposed from the project → site → building → storey hierarchy", instances: bad)) }
        // Resource instances not connected (directly or through other resources) to any rooted object.
        var parent: [Int: Int] = [:]
        func find(_ x: Int) -> Int { var x = x; while let p = parent[x], p != x { parent[x] = parent[p] ?? p; x = p }; return x }
        for e in f.entities.values {
            for r in e.args.flatMap(refs) + e.parts.values.flatMap({ $0.flatMap(refs) }) where f[r] != nil {
                let a = find(e.id), b = find(r); if a != b { parent[a] = b }
            }
        }
        var rootedComponents = Set<Int>()
        for e in f.entities.values where e.parts.isEmpty && t.isSubtype(e.type, of: "IFCROOT") { rootedComponents.insert(find(e.id)) }
        let orphan = rootedComponents.isEmpty ? [] : f.entities.values.filter { !rootedComponents.contains(find($0.id)) }.map(\.id)
        if !orphan.isEmpty { out.append(IFCValidationIssue(severity: .warning, code: "RESOURCE-UNUSED", message: "\(orphan.count) resource instance(s) are not used by any rooted object", instances: orphan.sorted())) }
        // Closed shells.
        var open: [Int] = []
        func closed(_ faces: [[Int]]) -> Bool {
            var count: [Int64: Int] = [:]
            for fc in faces where fc.count >= 3 {
                for i in 0..<fc.count { let a = fc[i], b = fc[(i + 1) % fc.count]; if a != b { count[Int64(a) << 32 | Int64(b), default: 0] += 1 } }
            }
            for (k, n) in count { let a = k >> 32, b = k & 0xffff_ffff; if n != 1 || count[b << 32 | a] != 1 { return false } }
            return !count.isEmpty
        }
        for sh in f.all("IFCCLOSEDSHELL") {
            // Faces by their outer bound's polyloop points (points compared by instance, then by coordinates).
            var key: [String: Int] = [:]
            func pid(_ r: Int) -> Int {
                guard let p = f[r], let c = p[0].list?.compactMap({ $0.double }) else { return r }
                let k = c.map { String(format: "%.6g", $0) }.joined(separator: ",")
                if let i = key[k] { return i }; key[k] = r; return r
            }
            var faces: [[Int]] = []
            for fr in sh[0].refs {
                guard let face = f[fr] else { continue }
                for b in face[0].refs {
                    guard let bound = f[b], let loop = f[bound[0].ref], loop.type == "IFCPOLYLOOP" else { continue }
                    var pts = loop[0].refs.map(pid)
                    if bound[1].enumValue == "F" { pts.reverse() }
                    faces.append(pts)
                }
            }
            if !faces.isEmpty && !closed(faces) { open.append(sh.id) }
        }
        let tn = t.attributeNames("IFCTRIANGULATEDFACESET") ?? [], pn = t.attributeNames("IFCPOLYGONALFACESET") ?? []
        if let ci = tn.firstIndex(of: "Closed"), let ii = tn.firstIndex(of: "CoordIndex") {
            for fs in f.all("IFCTRIANGULATEDFACESET") where fs[ci].enumValue == "T" {
                let idx = (fs[ii].list ?? []).map { ($0.list ?? []).compactMap { $0.double.map { Int($0) } } }
                if !closed(idx) { open.append(fs.id) }
            }
        }
        if let ci = pn.firstIndex(of: "Closed"), let fi = pn.firstIndex(of: "Faces") {
            for fs in f.all("IFCPOLYGONALFACESET") where fs[ci].enumValue == "T" {
                let faces = fs[fi].refs.compactMap { f[$0]?[0].list?.compactMap { $0.double.map { Int($0) } } }
                if !closed(faces) { open.append(fs.id) }
            }
        }
        if !open.isEmpty { out.append(IFCValidationIssue(severity: .warning, code: "SHELL-NOT-CLOSED", message: "\(open.count) closed shell(s) / face set(s) have edges not shared by exactly two faces", instances: open)) }
        return out
    }

    /// Standard property and quantity sets: reserved Pset_/Qto_ names, their properties, value types, enumeration values
    /// and the classes they apply to.
    static func propertySetIssues(_ f: STEPFile, _ t: IFCSchemaTable, _ ps: IFCPsetTable) -> [IFCValidationIssue] {
        var groups: [String: (IssueSeverity, String, String, [Int])] = [:]
        var order: [String] = []
        func add(_ s: IssueSeverity, _ c: String, _ m: String, _ id: Int) {
            let k = c + m
            if groups[k] == nil { groups[k] = (s, c, m, []); order.append(k) }
            groups[k]!.3.append(id)
        }
        var definedFor: [Int: [Int]] = [:]
        for r in f.all("IFCRELDEFINESBYPROPERTIES") {
            for d in (r[5].ref.map { [$0] } ?? r[5].refs) { definedFor[d, default: []] += r[4].refs }
        }
        for tp in f.entities.values where t.isSubtype(tp.type, of: "IFCTYPEOBJECT") {
            for d in tp[5].refs { definedFor[d, default: []].append(tp.id) }
        }
        let quantityKind = ["IFCQUANTITYLENGTH": "QL", "IFCQUANTITYAREA": "QA", "IFCQUANTITYVOLUME": "QV", "IFCQUANTITYCOUNT": "QC", "IFCQUANTITYWEIGHT": "QW", "IFCQUANTITYTIME": "QT"]
        for e in f.entities.values.sorted(by: { $0.id < $1.id }) where e.type == "IFCPROPERTYSET" || e.type == "IFCELEMENTQUANTITY" {
            guard let name = e[2].string else { continue }
            let isQ = e.type == "IFCELEMENTQUANTITY"
            let prefix = isQ ? "Qto_" : "Pset_"
            guard name.hasPrefix(prefix) else { continue }
            guard let tpl = ps.sets[name] else { add(.error, "PSET-UNKNOWN", "\(name) uses the reserved \(prefix) prefix but is not a standard \(ps === IFCPsetTable.ifc2x3 ? "IFC2X3" : t.name) set", e.id); continue }
            for pr in (isQ ? e[5].refs : e[4].refs) {
                guard let p = f[pr], let pn = p[0].string else { continue }
                guard let pt = tpl.props[pn] else { add(.error, "PSET-PROPERTY", "\(name).\(pn) is not a property of the standard set", p.id); continue }
                if isQ {
                    if let k = quantityKind[p.type], pt.kind.hasPrefix("Q"), k != pt.kind { add(.error, "PSET-VALUE-TYPE", "\(name).\(pn) must be \(pt.kind == "QL" ? "IfcQuantityLength" : pt.kind == "QA" ? "IfcQuantityArea" : pt.kind == "QV" ? "IfcQuantityVolume" : pt.kind == "QC" ? "IfcQuantityCount" : pt.kind == "QW" ? "IfcQuantityWeight" : "IfcQuantityTime")", p.id) }
                    continue
                }
                switch p.type {
                case "IFCPROPERTYSINGLEVALUE":
                    if pt.kind == "E" { add(.warning, "PSET-VALUE-TYPE", "\(name).\(pn) is an enumerated property (IfcPropertyEnumeratedValue)", p.id); continue }
                    if case .typed(let tn, _) = p[2], !pt.type.isEmpty, tn.uppercased() != pt.type.uppercased() {
                        add(.error, "PSET-VALUE-TYPE", "\(name).\(pn) must be \(pt.type), not \(t.types[tn.uppercased()]?.name ?? tn)", p.id)
                    }
                case "IFCPROPERTYENUMERATEDVALUE":
                    let vals = (p[2].list ?? []).compactMap { $0.string?.uppercased() }
                    if !pt.values.isEmpty, let bad = vals.first(where: { v in !pt.values.contains { $0.uppercased() == v } }) {
                        add(.error, "PSET-ENUMERATION", "\(name).\(pn) value \(bad) is not one of \(pt.values.joined(separator: ", "))", p.id)
                    }
                default: break
                }
            }
            // Applicability.
            let objs = definedFor[e.id] ?? []
            let apps = tpl.applicable
            if !apps.isEmpty {
                for o in objs {
                    guard let ot = f[o]?.type else { continue }
                    let ok = apps.contains { a in t.isSubtype(ot, of: a) || t.isSubtype(ot, of: a + "Type") || t.isSubtype(ot, of: a.replacingOccurrences(of: "Type", with: "")) }
                    if !ok { add(.warning, "PSET-APPLICABILITY", "\(name) applies to \(apps.joined(separator: ", ")), not \(t.className(ot) ?? ot)", o) }
                }
            }
        }
        return order.map { k in let g = groups[k]!; return IFCValidationIssue(severity: g.0, code: g.1, message: g.3.count > 1 ? "\(g.2) (\(g.3.count) instances)" : g.2, instances: g.3) }
    }

    /// Drawing elements behind an issue on the model's own IFC export: instances whose GlobalId is an element's, found
    /// from the issue's instances and the instances that reference them (a geometry item leads to its product).
    public static func elements(for issue: IFCValidationIssue, in f: STEPFile, doc: ArchiDocument) -> [EntityID] {
        var byGuid: [String: EntityID] = [:]
        for el in doc.elements {
            if let g = el.props["ifcGuid"], IFCExporter.isValidGuid(g) { byGuid[g] = el.id }
            byGuid[IFCExporter.guid("element:\(el.id)")] = el.id
        }
        var parents: [Int: [Int]] = [:]
        func refs(_ v: StepValue) -> [Int] {
            switch v { case .ref(let r): return [r]; case .list(let l): return l.flatMap(refs); case .typed(_, let a): return a.flatMap(refs); default: return [] }
        }
        for e in f.entities.values { for r in e.args.flatMap(refs) { parents[r, default: []].append(e.id) } }
        var out: [EntityID] = [], seen: Set<Int> = []
        func take(_ id: Int) -> Bool {
            guard let e = f[id], let g = e[0].string, let el = byGuid[g] else { return false }
            if !out.contains(el) { out.append(el) }
            return true
        }
        for start in issue.instances.prefix(200) {
            var queue = [start], depth = 0
            if let e = f[start], e.type.hasPrefix("IFCREL") { for r in e.args.flatMap(refs) { _ = take(r) } }
            while !queue.isEmpty && depth < 12 {
                var next: [Int] = []
                for id in queue where seen.insert(id).inserted {
                    if take(id) { continue }
                    next += parents[id] ?? []
                }
                queue = next; depth += 1
            }
        }
        return out
    }

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
            if IFCSchemaTable.forSchema(schema) == nil, let n = counts[e.type], e.parts.isEmpty, e.args.count != n {
                issue(.error, "ATTRIBUTE-COUNT", "\(e.type) has \(e.args.count) attributes, \(is2x3 ? "IFC2X3" : is4x3 ? "IFC4X3" : "IFC4") expects \(n)", [e.id])
            }
        }
        if !dangling.isEmpty { issue(.error, "DANGLING-REFERENCE", "\(dangling.count) instance(s) reference undefined instances", dangling) }
        if let table = IFCSchemaTable.forSchema(schema) {
            out += schemaIssues(f, table, skip: foreign)
            out += normativeIssues(f, table)
            out += whereRuleIssues(f, table)
            if let psets = IFCPsetTable.forSchema(schema) { out += propertySetIssues(f, table, psets) }
        }
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
        // Global rule IfcSingleProjectInstance: at most one project; a file without one is only a model fragment.
        if projects.count > 1 { issue(.error, "PROJECT-COUNT", "The file must contain exactly one IfcProject (found \(projects.count))", projects.map(\.id)) }
        if projects.isEmpty { issue(.warning, "PROJECT-MISSING", "The file contains no IfcProject (a model fragment)") }
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
