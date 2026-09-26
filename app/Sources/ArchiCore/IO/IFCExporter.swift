// Oanarina Archi Tool — GPL-3.0-or-later
// IFC4 (ISO 10303-21 STEP) exporter. Entity attribute orders follow the IFC4 schema (buildingSMART);
// the GUID compression algorithm matches IfcOpenShell's ifcopenshell.guid (LGPL-3.0, © IfcOpenShell contributors).
import Foundation

/// IFC export settings. Defaults come from the document variables IFCSCHEMA (IFC4 / IFC4X3), IFCMVD
/// (ReferenceView / DesignTransferView) and IFCQUANTITIES (1/0), so every export path honours IFCOPTIONS.
public struct IFCExportOptions: Hashable {
    public enum Schema: String, CaseIterable { case ifc2x3 = "IFC2X3", ifc4 = "IFC4", ifc4x3 = "IFC4X3_ADD2" }
    public enum ModelView: String, CaseIterable {
        case referenceView = "ReferenceView_V1.2", designTransferView = "DesignTransferView_V1.0", coordinationView = "CoordinationView_V2.0"
        public var shortName: String { self == .referenceView ? "ReferenceView" : self == .designTransferView ? "DesignTransferView" : "CoordinationView" }
    }
    /// Model view written in the header: IFC2x3 files always use Coordination View 2.0; IFC4/IFC4.3 use RV or DTV.
    public var effectiveView: ModelView {
        if schema == .ifc2x3 { return .coordinationView }
        return modelView == .coordinationView ? .referenceView : modelView
    }
    /// Reference View geometry is tessellated (IfcTriangulatedFaceSet); DTV and IFC2x3 use faceted B-reps.
    public var tessellated: Bool { schema != .ifc2x3 && effectiveView == .referenceView }
    /// Writes IfcMapConversion + IfcProjectedCRS (IFC4/IFC4.3) from the project location (drawing variable IFCGEOREF=0 turns it off).
    public var georeference = true
    public var schema: Schema = .ifc4
    public var modelView: ModelView = .referenceView
    /// Writes Qto_*BaseQuantities (IfcElementQuantity) for walls, slabs, columns, beams, spaces, doors and windows.
    public var quantities = true
    public init(schema: Schema = .ifc4, modelView: ModelView = .referenceView, quantities: Bool = true) {
        self.schema = schema; self.modelView = modelView; self.quantities = quantities
    }
    public static func parseSchema(_ s: String) -> Schema? {
        switch s.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "_", with: "") {
        case "IFC4", "IFC4ADD2", "4": return .ifc4
        case "IFC4X3", "IFC43", "IFC4X3ADD2", "43", "4X3": return .ifc4x3
        case "IFC2X3", "IFC2X3TC1", "2X3", "IFC23", "23": return .ifc2x3
        default: return nil
        }
    }
    public static func parseView(_ s: String) -> ModelView? {
        let u = s.uppercased()
        if u.hasPrefix("REF") { return .referenceView }
        if u.hasPrefix("DES") || u.hasPrefix("DTV") { return .designTransferView }
        if u.hasPrefix("COORD") || u.hasPrefix("CV") { return .coordinationView }
        return nil
    }
    public static func from(_ doc: ArchiDocument) -> IFCExportOptions {
        var o = IFCExportOptions()
        if let v = doc.variable("IFCSCHEMA"), let sc = parseSchema(v) { o.schema = sc }
        if let v = doc.variable("IFCMVD"), let mv = parseView(v) { o.modelView = mv }
        if let v = doc.variable("IFCQUANTITIES") { o.quantities = !["0", "no", "off", "false"].contains(v.lowercased()) }
        if let v = doc.variable("IFCGEOREF") { o.georeference = !["0", "no", "off", "false"].contains(v.lowercased()) }
        return o
    }
}

public enum IFCExporter {
    public static func export(doc: ArchiDocument, meshes: [MeshGroup]) -> String {
        export(doc: doc, meshes: meshes, options: IFCExportOptions.from(doc))
    }
    public static func export(doc: ArchiDocument, meshes: [MeshGroup], options: IFCExportOptions) -> String {
        // Writes the model selected by EXPORTFILTER (worksets, design options, phases); meshes are matched by id.
        let b = IFCBuilder(doc: ModelSets.exportModel(doc), meshes: meshes)
        b.options = options
        return b.build()
    }

    static let guidChars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$")

    /// Deterministic 22-character IFC GlobalId derived from a key (e.g. "element:42").
    public static func guid(_ key: String) -> String {
        func fnv(_ s: String, _ seed: UInt64) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325 ^ seed
            for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            // final avalanche
            h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33; h = h &* 0xc4ceb9fe1a85ec53; h ^= h >> 33
            return h
        }
        let a = fnv(key, 0x9E3779B97F4A7C15), c = fnv(key, 0xD1B54A32D192ED03)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8((a >> (56 - 8 * UInt64(i))) & 0xFF); bytes[8 + i] = UInt8((c >> (56 - 8 * UInt64(i))) & 0xFF) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return compress(bytes)
    }

    /// True for a 22-character IFC GlobalId in the IFC base-64 alphabet (first character 0-3).
    public static func isValidGuid(_ s: String) -> Bool {
        guard s.count == 22, let f = s.first, "0123".contains(f) else { return false }
        return s.allSatisfy { guidChars.contains($0) }
    }

    /// Compresses 16 bytes into the IFC base-64 GUID form.
    static func compress(_ bs: [UInt8]) -> String {
        func b64(_ v: Int, _ len: Int) -> String {
            var out = [Character](repeating: "0", count: len)
            var x = v
            for i in stride(from: len - 1, through: 0, by: -1) { out[i] = guidChars[x % 64]; x /= 64 }
            return String(out)
        }
        var s = b64(Int(bs[0]), 2)
        var i = 1
        while i < 16 { s += b64(Int(bs[i]) << 16 | Int(bs[i + 1]) << 8 | Int(bs[i + 2]), 4); i += 3 }
        return s
    }

    /// STEP string literal with ISO 10303-21 escaping.
    static func str(_ s: String) -> String {
        var out = "'"
        for u in s.unicodeScalars {
            switch u {
            case "'": out += "''"
            case "\\": out += "\\\\"
            default:
                if u.value >= 32 && u.value < 127 { out.unicodeScalars.append(u) }
                else if u.value < 32 { out += " " }
                else if u.value <= 0xFFFF { out += String(format: "\\X2\\%04X\\X0\\", u.value) }
                else { out += String(format: "\\X4\\%08X\\X0\\", u.value) }
            }
        }
        return out + "'"
    }

    static func real(_ v: Double) -> String {
        guard v.isFinite else { return "0." }
        var s = fmt(v, 6)
        if s == "-0" { s = "0" }
        return s.contains(".") ? s : s + "."
    }
}

final class IFCBuilder {
    let doc: ArchiDocument
    let meshes: [MeshGroup]
    let k: Double // model units → mm
    var lines: [String] = []
    var nextId = 1
    var oh = 0
    var bodyCtx = 0, axisCtx = 0
    var zDir = 0, xDir = 0, origin = 0
    var storeyPlacement: [Int: Int] = [:]
    var storeyEntity: [Int: Int] = [:]
    var storeyElevation: [Int: Double] = [:]
    var contained: [Int: [Int]] = [:]   // level → element entities
    var spaces: [Int: [Int]] = [:]
    var materialUse: [String: [Int]] = [:]
    var materialEntity: [String: Int] = [:]
    var surfaceStyle: [String: Int] = [:]
    var wallPlacement: [EntityID: Int] = [:]
    var wallEntity: [EntityID: Int] = [:]
    var elementEntity: [EntityID: Int] = [:]
    var psets: [(String, [Int], [(String, String)])] = []
    var layerSetUsage: [String: Int] = [:]
    var usedGuids = Set<String>()
    var options = IFCExportOptions()
    /// Quantity sets: (Qto name, element entity, [(quantity name, IFC entity, value)]).
    var qtos: [(String, Int, [(String, String, Double)])] = []
    /// Type objects: "wall|door|window" + ":" + type name → occurrence entities (in first-use order).
    var typeUse: [String: [Int]] = [:]
    var typeOrder: [String] = []
    func useType(_ kind: String, _ name: String?, _ entity: Int) {
        guard let n = name, !n.isEmpty else { return }
        let key = kind + ":" + n
        if typeUse[key] == nil { typeOrder.append(key) }
        typeUse[key, default: []].append(entity)
    }
    /// IfcWallType / IfcDoorType / IfcWindowType with IfcRelDefinesByType; opening type parameters as a type property set.
    func writeTypes() {
        for key in typeOrder {
            guard let occ = typeUse[key], let cut = key.firstIndex(of: ":") else { continue }
            let kind = String(key[..<cut]), name = String(key[key.index(after: cut)...])
            var psets = "$"
            if kind != "wall", let ot = doc.openingType(name), !ot.params.isEmpty {
                let props = ot.params.sorted { $0.key < $1.key }.filter { !$0.key.isEmpty && !$0.value.isEmpty }.map { add("IFCPROPERTYSINGLEVALUE(\(s($0.key)),$,\(typedValue($0.key, $0.value)),$)") }
                if !props.isEmpty { psets = "(#\(add("IFCPROPERTYSET(\(g("typepset:\(key)")),#\(oh),'Archi_TypeProperties',$,\(refs(props)))")))" }
            }
            let t: Int
            switch kind {
            case "wall": t = add("IFCWALLTYPE(\(g("type:\(key)")),#\(oh),\(s(name)),$,$,\(psets),$,$,$,.STANDARD.)")
            case "door": t = add("IFCDOORTYPE(\(g("type:\(key)")),#\(oh),\(s(name)),$,$,\(psets),$,$,$,.DOOR.,.NOTDEFINED.,$,$)")
            default: t = add("IFCWINDOWTYPE(\(g("type:\(key)")),#\(oh),\(s(name)),$,$,\(psets),$,$,$,.WINDOW.,.NOTDEFINED.,$,$)")
            }
            add("IFCRELDEFINESBYTYPE(\(g("rel:type:\(key)")),#\(oh),$,$,\(refs(occ)),#\(t))")
        }
    }

    init(doc: ArchiDocument, meshes: [MeshGroup]) {
        self.doc = doc; self.meshes = meshes; self.k = doc.units.mm
    }

    @discardableResult
    func add(_ s: String) -> Int { let id = nextId; nextId += 1; lines.append("#\(id)=\(s);"); return id }
    func r(_ v: Double) -> String { IFCExporter.real(v) }
    func s(_ v: String) -> String { IFCExporter.str(v) }
    func g(_ key: String) -> String { s(IFCExporter.guid(key)) }
    /// Element GlobalId: the one it was imported with (props "ifcGuid") when valid, else a deterministic id.
    func eg(_ el: BIMElement) -> String {
        if let v = el.props["ifcGuid"], IFCExporter.isValidGuid(v), !usedGuids.contains(v) { usedGuids.insert(v); return s(v) }
        return g("element:\(el.id)")
    }
    func refs(_ ids: [Int]) -> String { "(" + ids.map { "#\($0)" }.joined(separator: ",") + ")" }

    func point3(_ x: Double, _ y: Double, _ z: Double) -> Int { add("IFCCARTESIANPOINT((\(r(x)),\(r(y)),\(r(z))))") }
    func point2(_ p: Vec2) -> Int { add("IFCCARTESIANPOINT((\(r(p.x)),\(r(p.y))))") }
    func dir3(_ x: Double, _ y: Double, _ z: Double) -> Int { add("IFCDIRECTION((\(r(x)),\(r(y)),\(r(z))))") }
    func axis3(_ loc: Vec3, xAxis: Vec2? = nil) -> Int {
        let p = point3(loc.x, loc.y, loc.z)
        if let xa = xAxis, xa.length > geomEpsilon, !(abs(xa.x - 1) < 1e-12 && abs(xa.y) < 1e-12) {
            let n = xa.normalized
            return add("IFCAXIS2PLACEMENT3D(#\(p),#\(zDir),#\(dir3(n.x, n.y, 0)))")
        }
        return add("IFCAXIS2PLACEMENT3D(#\(p),$,$)")
    }
    func placement(relTo: Int?, _ loc: Vec3, xAxis: Vec2? = nil) -> Int {
        let a = axis3(loc, xAxis: xAxis)
        return add("IFCLOCALPLACEMENT(\(relTo.map { "#\($0)" } ?? "$"),#\(a))")
    }
    func polyline2(_ pts: [Vec2], closed: Bool) -> Int {
        var ids = pts.map { point2($0 * k) }
        if closed, let f = ids.first { ids.append(f) }
        return add("IFCPOLYLINE(\(refs(ids)))")
    }
    func cleanLoop(_ pts: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where out.last.map({ !$0.isClose(p, tol: 1e-6) }) ?? true { out.append(p) }
        if out.count > 1, out[0].isClose(out[out.count - 1], tol: 1e-6) { out.removeLast() }
        return out
    }
    func extrusion(profile: Int, depth: Double, at: Vec3 = .zero) -> Int {
        let pos = axis3(at)
        return add("IFCEXTRUDEDAREASOLID(#\(profile),#\(pos),#\(zDir),\(r(max(depth, 0.001))))")
    }
    func rectangle(center: Vec2, x: Double, y: Double) -> Int {
        let p = add("IFCAXIS2PLACEMENT2D(#\(point2(center)),$)")
        return add("IFCRECTANGLEPROFILEDEF(.AREA.,$,#\(p),\(r(max(x, 0.001))),\(r(max(y, 0.001))))")
    }
    func arbitraryProfile(_ outer: [Vec2], holes: [[Vec2]] = []) -> Int? {
        var o = cleanLoop(outer)
        guard o.count >= 3 else { return nil }
        if GeometryOps.signedArea(o) < 0 { o.reverse() }
        let oc = polyline2(o, closed: true)
        let hs = holes.map(cleanLoop).filter { $0.count >= 3 }.map { h -> Int in
            var hh = h
            if GeometryOps.signedArea(hh) > 0 { hh.reverse() }
            return polyline2(hh, closed: true)
        }
        if hs.isEmpty { return add("IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#\(oc))") }
        return add("IFCARBITRARYPROFILEDEFWITHVOIDS(.AREA.,$,#\(oc),\(refs(hs)))")
    }
    func shape(_ items: [Int], type: String, axis: [Vec2]? = nil) -> Int {
        var reps = [add("IFCSHAPEREPRESENTATION(#\(bodyCtx),'Body',\(s(type)),\(refs(items)))")]
        if let ax = axis, ax.count >= 2 {
            let pl = add("IFCPOLYLINE(\(refs(ax.map { point2($0 * k) })))")
            reps.insert(add("IFCSHAPEREPRESENTATION(#\(axisCtx),'Axis','Curve2D',(#\(pl)))"), at: 0)
        }
        return add("IFCPRODUCTDEFINITIONSHAPE($,$,\(refs(reps)))")
    }

    /// Representation type of the items `brep(for:map:)` writes.
    var meshRepType: String { options.tessellated ? "Tessellation" : "Brep" }

    /// Mesh body of all mesh groups with this element id; `map` converts model coordinates to the local frame (mm).
    /// Reference View (IFC4/IFC4.3): IfcTriangulatedFaceSet; Design Transfer View and IFC2x3: IfcFacetedBrep.
    func brep(for id: EntityID, map: (Vec3) -> Vec3) -> [Int] {
        var items: [Int] = []
        for grp in meshes where grp.id == id {
            let m = grp.mesh
            let tris = MeshExport.triangles(m)
            guard !tris.isEmpty else { continue }
            if options.tessellated {
                // Welded coordinate list + 1-based triangle indices.
                var index: [String: Int] = [:]
                var coords: [String] = []
                var remap: [Int: Int] = [:]
                func vid(_ i: Int) -> Int {
                    if let e = remap[i] { return e }
                    let p = map(m.positions[i])
                    let key = "\(Int((p.x * 100).rounded())),\(Int((p.y * 100).rounded())),\(Int((p.z * 100).rounded()))"
                    if let e = index[key] { remap[i] = e; return e }
                    coords.append("(\(r(p.x)),\(r(p.y)),\(r(p.z)))"); index[key] = coords.count; remap[i] = coords.count
                    return coords.count
                }
                var triIdx: [String] = []
                var t = 0
                while t + 2 < tris.count {
                    let a = vid(Int(tris[t])), b = vid(Int(tris[t + 1])), c = vid(Int(tris[t + 2]))
                    t += 3
                    if a == b || b == c || a == c { continue }
                    triIdx.append("(\(a),\(b),\(c))")
                }
                guard !triIdx.isEmpty else { continue }
                let item: Int
                if options.schema == .ifc4x3 {
                    // IFC4.3: Closed moved to IfcTessellatedFaceSet; IfcCartesianPointList3D gained TagList.
                    let pl = add("IFCCARTESIANPOINTLIST3D((\(coords.joined(separator: ","))),$)")
                    item = add("IFCTRIANGULATEDFACESET(#\(pl),$,$,(\(triIdx.joined(separator: ","))),$)")
                } else {
                    let pl = add("IFCCARTESIANPOINTLIST3D((\(coords.joined(separator: ","))))")
                    item = add("IFCTRIANGULATEDFACESET(#\(pl),$,$,(\(triIdx.joined(separator: ","))),$)")
                }
                style(item, material: grp.material)
                items.append(item)
                continue
            }
            var ptIds: [Int: Int] = [:]
            var weld: [String: Int] = [:]
            func pid(_ i: Int) -> Int {
                if let e = ptIds[i] { return e }
                let p = map(m.positions[i])
                let key = "\(Int((p.x * 100).rounded())),\(Int((p.y * 100).rounded())),\(Int((p.z * 100).rounded()))"
                if let e = weld[key] { ptIds[i] = e; return e }
                let e = point3(p.x, p.y, p.z); ptIds[i] = e; weld[key] = e; return e
            }
            var faces: [Int] = []
            var t = 0
            while t + 2 < tris.count {
                let a = pid(Int(tris[t])), b = pid(Int(tris[t + 1])), c = pid(Int(tris[t + 2]))
                t += 3
                if a == b || b == c || a == c { continue }
                let loop = add("IFCPOLYLOOP((#\(a),#\(b),#\(c)))")
                let bound = add("IFCFACEOUTERBOUND(#\(loop),.T.)")
                faces.append(add("IFCFACE((#\(bound)))"))
            }
            guard !faces.isEmpty else { continue }
            let shell = add("IFCCLOSEDSHELL(\(refs(faces)))")
            let item = add("IFCFACETEDBREP(#\(shell))")
            style(item, material: grp.material)
            items.append(item)
        }
        return items
    }

    func style(_ item: Int, material: String?) {
        guard let name = material, let m = doc.material(name) else { return }
        let key = m.name.lowercased()
        let ss: Int
        if let e = surfaceStyle[key] { ss = e } else {
            let col = add("IFCCOLOURRGB($,\(r(m.color.r)),\(r(m.color.g)),\(r(m.color.b)))")
            let rend = add("IFCSURFACESTYLERENDERING(#\(col),\(r(max(0, min(1, m.transparency)))),$,$,$,$,$,$,.NOTDEFINED.)")
            ss = add("IFCSURFACESTYLE(\(s(m.name)),.BOTH.,(#\(rend)))")
            surfaceStyle[key] = ss
        }
        add("IFCSTYLEDITEM(#\(item),(#\(ss)),$)")
    }

    func useMaterial(_ name: String?, _ entity: Int) {
        guard let n = name, !n.isEmpty else { return }
        materialUse[n, default: []].append(entity)
    }

    func level(of el: BIMElement) -> Int { storeyPlacement[el.level] != nil ? el.level : (doc.levels.first?.id ?? 0) }
    func elevation(_ lv: Int) -> Double { storeyElevation[lv] ?? 0 }

    // MARK: build

    func build() -> String {
        let now = Int(Date().timeIntervalSince1970)
        let author = doc.info.author.isEmpty ? "Architect" : doc.info.author
        let person = add("IFCPERSON($,\(s(author)),$,$,$,$,$,$)")
        let org = add("IFCORGANIZATION($,'Oanarina',$,$,$)")
        let po = add("IFCPERSONANDORGANIZATION(#\(person),#\(org),$)")
        let app = add("IFCAPPLICATION(#\(org),'1.0','Oanarina Archi Tool','OanarinaArchiTool')")
        oh = add("IFCOWNERHISTORY(#\(po),#\(app),$,.ADDED.,$,$,$,\(now))")

        let u1 = add("IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.)")
        let u2 = add("IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.)")
        let u3 = add("IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.)")
        let u4 = add("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.)")
        let units = add("IFCUNITASSIGNMENT((#\(u1),#\(u2),#\(u3),#\(u4)))")

        origin = point3(0, 0, 0)
        zDir = dir3(0, 0, 1)
        xDir = dir3(1, 0, 0)
        let wcs = add("IFCAXIS2PLACEMENT3D(#\(origin),#\(zDir),#\(xDir))")
        let na = rad(doc.info.northAngle)
        let north = add("IFCDIRECTION((\(r(-sin(na))),\(r(cos(na)))))")
        let ctx = add("IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#\(wcs),#\(north))")
        bodyCtx = add("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#\(ctx),$,.MODEL_VIEW.,$)")
        axisCtx = add("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Axis','Model',*,*,*,*,#\(ctx),$,.GRAPH_VIEW.,$)")

        let project = add("IFCPROJECT(\(g("project")),#\(oh),\(s(doc.info.name)),\(doc.info.number.isEmpty ? "$" : s(doc.info.number)),$,$,$,(#\(ctx)),#\(units))")
        if options.georeference && options.schema != .ifc2x3 { georeference(context: ctx) }
        let sitePl = placement(relTo: nil, .zero)
        func dms(_ v: Double) -> String {
            // Whole microseconds first, so rounding carries into seconds/minutes/degrees (microseconds stay < 10⁶).
            let sign = v < 0 ? -1 : 1
            let total = Int64((abs(v) * 3_600_000_000).rounded())
            let d = total / 3_600_000_000, m = (total / 60_000_000) % 60, sec = (total / 1_000_000) % 60, micro = total % 1_000_000
            return "(\(Int64(sign) * d),\(Int64(sign) * m),\(Int64(sign) * sec),\(Int64(sign) * micro))"
        }
        let address = doc.info.address.isEmpty ? "$" : "#\(add("IFCPOSTALADDRESS($,$,$,$,(\(s(doc.info.address))),$,$,$,$,$)"))"
        let site = add("IFCSITE(\(g("site")),#\(oh),'Site',$,$,#\(sitePl),$,$,.ELEMENT.,\(dms(doc.info.latitude)),\(dms(doc.info.longitude)),0.,$,\(address))")
        let bldPl = placement(relTo: sitePl, .zero)
        let building = add("IFCBUILDING(\(g("building")),#\(oh),\(s(doc.info.name)),$,$,#\(bldPl),$,$,.ELEMENT.,$,$,$)")
        // IFC 4.3 alignments are aggregated into the project with the site (one decomposition per object).
        let aligned = options.schema == .ifc4x3 ? alignments(sitePlacement: sitePl) : []
        add("IFCRELAGGREGATES(\(g("rel:project-site")),#\(oh),$,$,#\(project),\(refs([site] + aligned)))")
        add("IFCRELAGGREGATES(\(g("rel:site-building")),#\(oh),$,$,#\(site),(#\(building)))")

        var levels = doc.levels.sorted { $0.elevation < $1.elevation }
        if levels.isEmpty { levels = [Level(id: 0, name: "Level 0", elevation: 0)] }
        var storeys: [Int] = []
        for lv in levels {
            let pl = placement(relTo: bldPl, Vec3(0, 0, lv.elevation * k))
            let st = add("IFCBUILDINGSTOREY(\(g("storey:\(lv.id)")),#\(oh),\(s(lv.name)),$,$,#\(pl),$,$,.ELEMENT.,\(r(lv.elevation * k)))")
            storeyPlacement[lv.id] = pl; storeyEntity[lv.id] = st; storeyElevation[lv.id] = lv.elevation * k
            storeys.append(st)
        }
        add("IFCRELAGGREGATES(\(g("rel:building-storeys")),#\(oh),$,$,#\(building),\(refs(storeys)))")

        // Walls first (openings reference them), then the rest.
        for el in doc.elements { if case .wall = el.geometry { wall(el) } }
        var rampGroups: [String: [BIMElement]] = [:]
        var rampOrder: [String] = []
        for el in doc.elements {
            switch el.geometry {
            case .wall: break
            case .opening: opening(el)
            case .slab:
                switch el.props["kind"] ?? "" {
                case "ramp", "landing":
                    if el.props["kind"] == "landing" && el.props["rampGroup"] == nil { slab(el); continue }
                    let key = el.props["rampGroup"] ?? "\(el.id)"
                    if rampGroups[key] == nil { rampOrder.append(key) }
                    rampGroups[key, default: []].append(el)
                case "foundation": footing(el)
                case "ceiling": covering(el)
                default: slab(el)
                }
            case .column: column(el)
            case .beam: beam(el)
            case .space: space(el)
            case .gridLine: break
            default: meshElement(el)
            }
        }
        for key in rampOrder { ramp(key, rampGroups[key] ?? []) }
        // Imported IFC products kept as meshes (furniture, MEP terminals, assemblies' parts…) go back out as their class.
        for e in doc.entities where e.props["ifcType"] != nil || e.props["ifcGuid"] != nil { if case .solid = e.geometry { importedProduct(e) } }
        phaseGroups()
        writeTypes()
        if options.schema != .ifc2x3, let ws = Scheduler.load(doc) { writeSchedule(ws, project: project) }

        for lv in levels {
            if let els = contained[lv.id], !els.isEmpty, let st = storeyEntity[lv.id] {
                add("IFCRELCONTAINEDINSPATIALSTRUCTURE(\(g("rel:contains:\(lv.id)")),#\(oh),$,$,\(refs(els)),#\(st))")
            }
            if let sp = spaces[lv.id], !sp.isEmpty, let st = storeyEntity[lv.id] {
                add("IFCRELAGGREGATES(\(g("rel:spaces:\(lv.id)")),#\(oh),$,$,#\(st),\(refs(sp)))")
            }
        }
        for (name, ents) in materialUse.sorted(by: { $0.key < $1.key }) {
            let m: Int
            if let e = materialEntity[name.lowercased()] { m = e } else {
                m = add("IFCMATERIAL(\(s(name)),$,$)"); materialEntity[name.lowercased()] = m
            }
            add("IFCRELASSOCIATESMATERIAL(\(g("rel:material:\(name)")),#\(oh),$,$,\(refs(ents)),#\(m))")
        }
        for (i, p) in psets.enumerated() {
            let props = p.2.map { add("IFCPROPERTYSINGLEVALUE(\(s($0.0)),$,\($0.1),$)") }
            guard !props.isEmpty else { continue }
            let ps = add("IFCPROPERTYSET(\(g("pset:\(i):\(p.0):\(p.1.first ?? 0)")),#\(oh),\(s(p.0)),$,\(refs(props)))")
            add("IFCRELDEFINESBYPROPERTIES(\(g("rel:pset:\(i):\(p.0)")),#\(oh),$,$,\(refs(p.1)),#\(ps))")
        }
        for (i, q) in qtos.enumerated() where !q.2.isEmpty {
            let items = q.2.map { add("\($0.1)(\(s($0.0)),$,$,\(r($0.2)),$)") }
            let eq = add("IFCELEMENTQUANTITY(\(g("qto:\(i):\(q.0):\(q.1)")),#\(oh),\(s(q.0)),$,'BaseQuantities',\(refs(items)))")
            add("IFCRELDEFINESBYPROPERTIES(\(g("rel:qto:\(i):\(q.0)")),#\(oh),$,$,(#\(q.1)),#\(eq))")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var out = "ISO-10303-21;\nHEADER;\n"
        out += "FILE_DESCRIPTION(('ViewDefinition [\(options.effectiveView.rawValue)]'),'2;1');\n"
        out += "FILE_NAME(\(s(doc.info.name + ".ifc")),\(s(iso.string(from: Date()))),(\(s(author))),('Oanarina'),'Oanarina Archi Tool','Oanarina Archi Tool','');\n"
        out += "FILE_SCHEMA(('\(options.schema.rawValue)'));\nENDSEC;\nDATA;\n"
        out += (options.schema == .ifc2x3 ? IFCSchemaConvert.toIFC2X3(lines, nextId: nextId) : lines).joined(separator: "\n")
        out += "\nENDSEC;\nEND-ISO-10303-21;\n"
        return out
    }

    /// IfcMapConversion + IfcProjectedCRS (IO-022): the model origin sits at the project latitude/longitude in the CRS of
    /// the drawing variable GEOCRS (EPSG code; default the UTM zone of the site), rotated by the project north angle.
    func georeference(context ctx: Int) {
        let lat = doc.info.latitude, lon = doc.info.longitude
        guard lat.isFinite, lon.isFinite, abs(lat) <= 84 else { return }
        var crs = GeoCRS.utmZone(lon: lon, lat: lat)
        if let v = doc.variable("GEOCRS"), let c = GeoCRS.parse(v) { crs = c }
        let name: String, zone: String, projection: String
        switch crs {
        case .utm(let z, let n): name = crs.description; zone = "\(z)\(n ? "N" : "S")"; projection = "UTM zone \(z)\(n ? "N" : "S")"
        case .webMercator: name = crs.description; zone = ""; projection = "Popular Visualisation Pseudo-Mercator"
        default: return
        }
        let en = crs.fromLonLat(lon, lat)
        guard en.x.isFinite, en.y.isFinite else { return }
        let na = rad(doc.info.northAngle)
        let metre = add("IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)")
        let pcrs = add("IFCPROJECTEDCRS(\(s(name)),\(s("WGS 84 / " + projection)),'WGS84',$,\(s(projection)),\(zone.isEmpty ? "$" : s(zone)),#\(metre))")
        add("IFCMAPCONVERSION(#\(ctx),#\(pcrs),\(r(en.x)),\(r(en.y)),\(r(doc.info.elevation)),\(r(cos(na))),\(r(-sin(na))),1.)")
    }

    /// 4D work schedule (IFC4): IfcWorkSchedule declared by the project, IfcTask with IfcTaskTime (dates, float, critical),
    /// IfcRelSequence (finish-to-start with lag), IfcRelAssignsToProcess (elements built by a task) and
    /// IfcRelAssignsToControl (tasks controlled by the schedule).
    func writeSchedule(_ ws: WorkSchedule, project: Int) {
        guard !ws.tasks.isEmpty, let tm = try? Scheduler.cpm(ws) else { return }
        let f = Scheduler.dayFormatter()
        func dt(_ day: Int, end: Bool) -> String { s(f.string(from: Scheduler.date(ws, workday: day)) + (end ? "T17:00:00" : "T08:00:00")) }
        let finish = tm.values.map(\.ef).max() ?? 0
        let sched = add("IFCWORKSCHEDULE(\(g("schedule")),#\(oh),\(s(ws.name)),$,$,$,\(dt(0, end: false)),$,$,'P\(finish)D',$,\(dt(0, end: false)),\(dt(max(0, finish - 1), end: true)),.PLANNED.)")
        add("IFCRELDECLARES(\(g("rel:declares:schedule")),#\(oh),$,$,#\(project),(#\(sched)))")
        var taskEnt: [Int: Int] = [:]
        for t in ws.tasks {
            guard let x = tm[t.id] else { continue }
            let time = add("IFCTASKTIME($,$,$,.WORKTIME.,'P\(t.duration)D',\(dt(x.es, end: false)),\(dt(max(x.es, x.ef - 1), end: true)),\(dt(x.es, end: false)),\(dt(max(x.es, x.ef - 1), end: true)),\(dt(x.ls, end: false)),\(dt(max(x.ls, x.lf - 1), end: true)),$,'P\(x.totalFloat)D',\(x.critical ? ".T." : ".F."),$,$,$,$,$,$)")
            let e = add("IFCTASK(\(g("task:\(t.id)")),#\(oh),\(s(t.name)),$,\(s(t.trade)),\(s("\(t.id)")),$,$,$,.F.,$,#\(time),.CONSTRUCTION.)")
            taskEnt[t.id] = e
            let objs = t.elements.compactMap { elementEntity[$0] }
            if !objs.isEmpty { add("IFCRELASSIGNSTOPROCESS(\(g("rel:process:\(t.id)")),#\(oh),$,$,\(refs(objs)),.PRODUCT.,#\(e),$)") }
        }
        for t in ws.tasks {
            guard let b = taskEnt[t.id] else { continue }
            for p in t.predecessors {
                guard let a = taskEnt[p] else { continue }
                let lag = t.lag == 0 ? "$" : "#\(add("IFCLAGTIME($,$,$,IFCDURATION('P\(t.lag)D'),.WORKTIME.)"))"
                add("IFCRELSEQUENCE(\(g("rel:seq:\(p):\(t.id)")),#\(oh),$,$,#\(a),#\(b),\(lag),.FINISH_START.,$)")
            }
        }
        let all = ws.tasks.compactMap { taskEnt[$0.id] }
        if !all.isEmpty { add("IFCRELASSIGNSTOCONTROL(\(g("rel:control:schedule")),#\(oh),$,$,\(refs(all)),.PROCESS.,#\(sched))") }
    }

    // MARK: property helpers
    func bool(_ b: Bool) -> String { "IFCBOOLEAN(\(b ? ".T." : ".F."))" }
    func label(_ v: String) -> String { "IFCLABEL(\(s(v)))" }
    func ident(_ v: String) -> String { "IFCIDENTIFIER(\(s(v)))" }
    func length(_ v: Double) -> String { "IFCPOSITIVELENGTHMEASURE(\(r(max(v, 0.001))))" }
    func isExternal(_ el: BIMElement, default d: Bool) -> Bool {
        if let v = el.props["isExternal"] ?? el.props["IsExternal"] { return ["1", "true", "yes"].contains(v.lowercased()) }
        return d
    }
    /// Typed IFC value for a property written from element props ("Pset_WallCommon.FireRating" = "EI 60").
    func typedValue(_ name: String, _ v: String) -> String {
        let t = v.trimmingCharacters(in: .whitespaces)
        switch t.lowercased() {
        case "true", ".t.", "yes": return bool(true)
        case "false", ".f.", "no": return bool(false)
        default: break
        }
        if let d = Double(t), d.isFinite {
            switch name {
            case "ThermalTransmittance": return "IFCTHERMALTRANSMITTANCEMEASURE(\(r(d)))"
            case "AcousticRating", "FireRating", "Reference", "Status", "SurfaceSpreadOfFlame": return label(t)
            case "Slope", "Pitch": return "IFCPLANEANGLEMEASURE(\(r(d * .pi / 180)))"
            default: return "IFCREAL(\(r(d)))"
            }
        }
        return label(t)
    }

    func commonProps(_ el: BIMElement, _ entity: Int, pset: String, _ extra: [(String, String)]) {
        var p: [(String, String)] = [("Reference", ident(el.name.isEmpty ? el.typeName : el.name))]
        p += extra
        if let st = phaseStatus(el) { p.append(("Status", label(st))) }
        // Props named "<Set>.<Property>" go to that property set (the element's common set is merged, props win);
        // quantities ("Qto_…") are recomputed from the geometry; everything else stays in Archi_Properties.
        var named: [String: [(String, String)]] = [:]
        var custom: [(String, String)] = []
        for (key, v) in el.props.sorted(by: { $0.key < $1.key }) where !key.isEmpty && key != "ifcGuid" {
            if let dot = key.firstIndex(of: "."), dot != key.startIndex, key.index(after: dot) != key.endIndex {
                let set = String(key[..<dot]), prop = String(key[key.index(after: dot)...])
                if set.hasPrefix("Qto_") { continue }
                named[set, default: []].append((prop, typedValue(prop, v)))
            } else { custom.append((key, label(v))) }
        }
        if let mine = named.removeValue(forKey: pset) {
            for (n, v) in mine { if let i = p.firstIndex(where: { $0.0 == n }) { p[i].1 = v } else { p.append((n, v)) } }
        }
        psets.append((pset, [entity], p))
        for (set, props) in named.sorted(by: { $0.key < $1.key }) { psets.append((set, [entity], props)) }
        if !custom.isEmpty { psets.append(("Archi_Properties", [entity], custom)) }
        if options.quantities, let q = baseQuantities(el) { qtos.append((q.0, entity, q.1)) }
    }

    /// Qto_*BaseQuantities from the element geometry: lengths in mm (the file's length unit), areas in m², volumes in m³.
    func baseQuantities(_ el: BIMElement) -> (String, [(String, String, Double)])? {
        let mm = k, m = k / 1000
        func L(_ n: String, _ v: Double) -> (String, String, Double) { (n, "IFCQUANTITYLENGTH", v * mm) }
        func A(_ n: String, _ v: Double) -> (String, String, Double) { (n, "IFCQUANTITYAREA", v * m * m) }
        func V(_ n: String, _ v: Double) -> (String, String, Double) { (n, "IFCQUANTITYVOLUME", v * m * m * m) }
        switch el.geometry {
        case .wall(let w):
            let len = w.length, gross = len * w.height
            var openings = 0.0
            for o in doc.elements { if case .opening(let op) = o.geometry, op.hostWall == el.id { openings += op.width * min(op.height, max(w.height - op.sill, 0)) } }
            let net = max(gross - openings, 0)
            return ("Qto_WallBaseQuantities", [L("Length", len), L("Width", w.thickness), L("Height", w.height), A("GrossSideArea", gross),
                                               A("NetSideArea", net), V("GrossVolume", gross * w.thickness), V("NetVolume", net * w.thickness)])
        case .slab(let sl):
            let gross = abs(GeometryOps.signedArea(sl.boundary))
            let net = max(gross - sl.holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }, 0)
            var per = 0.0
            for i in sl.boundary.indices { per += sl.boundary[i].distance(to: sl.boundary[(i + 1) % sl.boundary.count]) }
            return ("Qto_SlabBaseQuantities", [L("Width", sl.thickness), L("Perimeter", per), A("GrossArea", gross), A("NetArea", net),
                                               V("GrossVolume", gross * sl.thickness), V("NetVolume", net * sl.thickness)])
        case .column(let c):
            let a = c.round ? Double.pi * c.width * c.width / 4 : c.width * c.depth
            return ("Qto_ColumnBaseQuantities", [L("Length", c.height), A("CrossSectionArea", a), V("GrossVolume", a * c.height), V("NetVolume", a * c.height)])
        case .beam(let b):
            let len = b.start.distance(to: b.end), a = b.width * b.depth
            return ("Qto_BeamBaseQuantities", [L("Length", len), A("CrossSectionArea", a), V("GrossVolume", a * len), V("NetVolume", a * len)])
        case .space(let sp):
            let a = abs(GeometryOps.signedArea(sp.boundary))
            var per = 0.0
            for i in sp.boundary.indices { per += sp.boundary[i].distance(to: sp.boundary[(i + 1) % sp.boundary.count]) }
            return ("Qto_SpaceBaseQuantities", [L("Height", sp.height), L("GrossPerimeter", per), A("GrossFloorArea", a), A("NetFloorArea", a),
                                                V("GrossVolume", a * sp.height), V("NetVolume", a * sp.height)])
        case .opening(let o):
            guard o.kind != .opening else { return nil }
            return (o.kind == .door ? "Qto_DoorBaseQuantities" : "Qto_WindowBaseQuantities", [L("Width", o.width), L("Height", o.height), A("Area", o.width * o.height)])
        default: return nil
        }
    }
    func name(_ el: BIMElement, _ fallback: String) -> String { el.name.isEmpty ? "\(fallback) \(el.id)" : el.name }

    // MARK: elements

    func wall(_ el: BIMElement) {
        guard case .wall(let w) = el.geometry else { return }
        let lv = level(of: el)
        let L = w.length * k, T = w.thickness * k, H = w.height * k
        guard L > 0.001 else { return }
        let dir = w.direction
        var items: [Int] = []
        let pl: Int
        if abs(w.bulge) < 1e-9 {
            pl = placement(relTo: storeyPlacement[lv], Vec3(w.centerStart.x * k, w.centerStart.y * k, w.baseOffset * k), xAxis: dir)
            let prof = rectangle(center: Vec2(L / 2, 0), x: L, y: T)
            items = [extrusion(profile: prof, depth: H)]
        } else {
            pl = placement(relTo: storeyPlacement[lv], Vec3(0, 0, w.baseOffset * k))
            if let prof = arbitraryProfile(DXFWriter.wallOutline(w)) { items = [extrusion(profile: prof, depth: H)] }
        }
        items.forEach { style($0, material: el.material) }
        let axis: [Vec2] = abs(w.bulge) < 1e-9 ? [Vec2(0, 0), Vec2(w.length, 0)] : [w.centerStart, w.centerEnd]
        let rep = shape(items, type: "SweptSolid", axis: axis)
        let e = add("IFCWALL(\(eg(el)),#\(oh),\(s(name(el, "Wall"))),$,\(w.wallType.map { s($0) } ?? "$"),#\(pl),#\(rep),\(s("\(el.id)")),.STANDARD.)")
        wallPlacement[el.id] = pl; wallEntity[el.id] = e; elementEntity[el.id] = e
        useType("wall", w.wallType, e)
        contained[lv, default: []].append(e)
        // Material: layer set for typed walls.
        if let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), !wt.plies.isEmpty {
            let usage: Int
            if let u = layerSetUsage[tn] { usage = u } else {
                let layers = wt.plies.map { ply -> Int in
                    let m: Int
                    if let x = materialEntity[ply.material.lowercased()] { m = x } else { m = add("IFCMATERIAL(\(s(ply.material)),$,$)"); materialEntity[ply.material.lowercased()] = m }
                    return add("IFCMATERIALLAYER(#\(m),\(r(ply.thickness * k)),$,\(s(ply.function)),$,$,$)")
                }
                let set = add("IFCMATERIALLAYERSET(\(refs(layers)),\(s(tn)),$)")
                usage = add("IFCMATERIALLAYERSETUSAGE(#\(set),.AXIS2.,.POSITIVE.,\(r(-wt.thickness * k / 2)),$)")
                layerSetUsage[tn] = usage
            }
            add("IFCRELASSOCIATESMATERIAL(\(g("rel:layerset:\(el.id)")),#\(oh),$,$,(#\(e)),#\(usage))")
        } else { useMaterial(el.material, e) }
        let ext = isExternal(el, default: (w.wallType ?? "").lowercased().contains("exterior"))
        commonProps(el, e, pset: "Pset_WallCommon", [("IsExternal", bool(ext)), ("LoadBearing", bool(w.thickness >= 200 && !((w.wallType ?? "").lowercased().contains("partition")))), ("ExtendToStructure", bool(false))])
    }

    func opening(_ el: BIMElement) {
        guard case .opening(let o) = el.geometry, let host = doc.element(o.hostWall), case .wall(let w) = host.geometry,
              let wpl = wallPlacement[o.hostWall], let wallE = wallEntity[o.hostWall] else { return }
        let lv = level(of: host)
        let W = o.width * k, Hh = o.height * k, T = w.thickness * k
        let depth = T + 40
        // Opening placement in wall coordinates (x along the wall, y across, z up from wall base).
        let curved = abs(w.bulge) > 1e-9
        let along = w.centerStart + w.direction * o.offset
        let local = curved ? Vec3(along.x * k, along.y * k, o.sill * k) : Vec3(o.offset * k, 0, o.sill * k)
        let localAxis: Vec2? = curved ? w.direction : nil
        let opl = placement(relTo: wpl, local, xAxis: localAxis)
        let prof = rectangle(center: .zero, x: W, y: depth)
        let orep = shape([extrusion(profile: prof, depth: Hh)], type: "SweptSolid")
        let oe = add("IFCOPENINGELEMENT(\(g("opening:\(el.id)")),#\(oh),\(s("Opening \(el.id)")),$,$,#\(opl),#\(orep),$,.OPENING.)")
        add("IFCRELVOIDSELEMENT(\(g("rel:voids:\(el.id)")),#\(oh),$,$,#\(wallE),#\(oe))")
        guard o.kind != .opening else { return }
        // Filling element: mesh from the model if available, else a frame-thick panel.
        let fpl = placement(relTo: wpl, local, xAxis: localAxis)
        var items: [Int] = []
        var usedMesh = false
        if meshes.contains(where: { $0.id == el.id }) {
            // Mesh coordinates are absolute; express them relative to the filling placement.
            let d = w.direction
            let base = w.centerStart + d * o.offset
            let zAbs = elevation(lv) + (w.baseOffset + o.sill) * k
            // Rotate into wall frame: brep points are computed relative to origin then rotated.
            let o3 = Vec3(base.x * k, base.y * k, zAbs), kk = k
            items = brep(for: el.id) { p in
                let q = p * kk - o3
                return Vec3(q.x * d.x + q.y * d.y, -q.x * d.y + q.y * d.x, q.z)
            }
            usedMesh = !items.isEmpty
        }
        if items.isEmpty {
            let fw = max(o.frameWidth * k, 20)
            let pr = rectangle(center: .zero, x: W, y: min(fw, T))
            let item = extrusion(profile: pr, depth: Hh)
            style(item, material: el.material)
            items = [item]
        }
        let rep = shape(items, type: usedMesh ? meshRepType : "SweptSolid")
        let e: Int
        if o.kind == .door {
            let op: String
            switch o.doorStyle {
            case .single: op = o.flipHand ? ".SINGLE_SWING_RIGHT." : ".SINGLE_SWING_LEFT."
            case .double: op = ".DOUBLE_DOOR_SINGLE_SWING."
            case .sliding: op = ".SLIDING_TO_LEFT."
            case .folding: op = ".FOLDING_TO_LEFT."
            case .revolving: op = ".REVOLVING."
            case .garage: op = ".ROLLINGUP."
            }
            e = add("IFCDOOR(\(eg(el)),#\(oh),\(s(name(el, "Door"))),$,$,#\(fpl),#\(rep),\(s(el.props["mark"] ?? "\(el.id)")),\(r(Hh)),\(r(W)),.DOOR.,\(op),$)")
            commonProps(el, e, pset: "Pset_DoorCommon", [("IsExternal", bool(isExternal(el, default: isExternal(host, default: (w.wallType ?? "").lowercased().contains("exterior")))))])
        } else {
            let part: String
            switch o.windowStyle {
            case .fixed, .casement, .awning: part = ".SINGLE_PANEL."
            case .doubleCasement, .sliding: part = ".DOUBLE_PANEL_VERTICAL."
            case .hung: part = ".DOUBLE_PANEL_HORIZONTAL."
            }
            e = add("IFCWINDOW(\(eg(el)),#\(oh),\(s(name(el, "Window"))),$,$,#\(fpl),#\(rep),\(s(el.props["mark"] ?? "\(el.id)")),\(r(Hh)),\(r(W)),.WINDOW.,\(part),$)")
            commonProps(el, e, pset: "Pset_WindowCommon", [("IsExternal", bool(isExternal(el, default: isExternal(host, default: true))))])
        }
        add("IFCRELFILLSELEMENT(\(g("rel:fills:\(el.id)")),#\(oh),$,$,#\(oe),#\(e))")
        useType(o.kind == .door ? "door" : "window", o.typeName, e)
        elementEntity[el.id] = e
        contained[lv, default: []].append(e)
        useMaterial(el.material, e)
    }

    /// Placement and body of a slab-like element: a vertical extrusion, or for a sloped slab an extrusion whose profile
    /// lies in the tilted soffit plane and whose direction stays vertical (exactly the sheared prism MeshBuilder draws).
    func slabBody(_ el: BIMElement, _ sl: SlabGeom, relTo parent: Int?) -> (placement: Int, item: Int)? {
        guard sl.isSloped else {
            let pl = placement(relTo: parent, Vec3(0, 0, (sl.topOffset - sl.thickness) * k))
            guard let prof = arbitraryProfile(sl.boundary, holes: sl.holes) else { return nil }
            let item = extrusion(profile: prof, depth: sl.thickness * k)
            style(item, material: el.material)
            return (pl, item)
        }
        let a = sl.slope * .pi / 180
        let ca = cos(a), sa = sin(a)
        guard abs(ca) > 0.05 else { return nil }
        let d = Vec2(cos(sl.slopeDirection), sin(sl.slopeDirection)), n2 = d.perp
        let o = sl.slopeOrigin ?? sl.boundary.first ?? .zero
        let tv = sl.thickness / max(abs(ca), 0.05)
        // Frame on the soffit plane: x up the slope, y horizontal, z normal to the slab.
        let loc = point3(o.x * k, o.y * k, (sl.topOffset - tv) * k)
        // Directions with full precision (the slope is recovered from them on import).
        func pdir(_ x: Double, _ y: Double, _ z: Double) -> Int {
            func q(_ v: Double) -> String { var t = fmt(v, 15); if t == "-0" { t = "0" }; return t.contains(".") || t.contains("E") || t.contains("e") ? t : t + "." }
            return add("IFCDIRECTION((\(q(x)),\(q(y)),\(q(z))))")
        }
        let zAxis = pdir(-sa * d.x, -sa * d.y, ca), xAxis = pdir(ca * d.x, ca * d.y, sa)
        let ax = add("IFCAXIS2PLACEMENT3D(#\(loc),#\(zAxis),#\(xAxis))")
        let pl = add("IFCLOCALPLACEMENT(\(parent.map { "#\($0)" } ?? "$"),#\(ax))")
        func local(_ p: Vec2) -> Vec2 { let q = p - o; return Vec2(q.dot(d) / ca, q.dot(n2)) }
        guard let prof = arbitraryProfile(sl.boundary.map(local), holes: sl.holes.map { $0.map(local) }) else { return nil }
        // World up in the local frame.
        let up = pdir(sa, 0, ca)
        let pos = axis3(.zero)
        let item = add("IFCEXTRUDEDAREASOLID(#\(prof),#\(pos),#\(up),\(r(max(tv * k, 0.001))))")
        style(item, material: el.material)
        return (pl, item)
    }

    func slopeProps(_ sl: SlabGeom) -> [(String, String)] {
        sl.isSloped ? [("PitchAngle", "IFCPLANEANGLEMEASURE(\(r(sl.slope * .pi / 180)))")] : []
    }

    func slab(_ el: BIMElement) {
        guard case .slab(let sl) = el.geometry else { return }
        let lv = level(of: el)
        guard let body = slabBody(el, sl, relTo: storeyPlacement[lv]) else { return }
        let rep = shape([body.item], type: "SweptSolid")
        let t = el.props["kind"] == "landing" ? ".LANDING." : ".FLOOR."
        let e = add("IFCSLAB(\(eg(el)),#\(oh),\(s(name(el, "Slab"))),$,$,#\(body.placement),#\(rep),\(s("\(el.id)")),\(t))")
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
        commonProps(el, e, pset: "Pset_SlabCommon", [("IsExternal", bool(isExternal(el, default: false))), ("LoadBearing", bool(true))] + slopeProps(sl))
    }

    /// Strip footing (host is a wall) or pad footing (host is a column, or none).
    func footing(_ el: BIMElement) {
        guard case .slab(let sl) = el.geometry else { return }
        let lv = level(of: el)
        guard let body = slabBody(el, sl, relTo: storeyPlacement[lv]) else { return }
        let rep = shape([body.item], type: "SweptSolid")
        var strip = false
        if let h = el.props["host"].flatMap(Int.init), let host = doc.element(h), case .wall = host.geometry { strip = true }
        let t = strip ? ".STRIP_FOOTING." : ".PAD_FOOTING."
        let e = add("IFCFOOTING(\(eg(el)),#\(oh),\(s(name(el, "Footing"))),$,$,#\(body.placement),#\(rep),\(s("\(el.id)")),\(t))")
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
        commonProps(el, e, pset: "Pset_FootingCommon", [("LoadBearing", bool(true))])
    }

    /// Ceiling slabs become IfcCovering (CEILING).
    func covering(_ el: BIMElement) {
        guard case .slab(let sl) = el.geometry else { return }
        let lv = level(of: el)
        guard let body = slabBody(el, sl, relTo: storeyPlacement[lv]) else { return }
        let rep = shape([body.item], type: "SweptSolid")
        let e = add("IFCCOVERING(\(eg(el)),#\(oh),\(s(name(el, "Ceiling"))),$,$,#\(body.placement),#\(rep),\(s("\(el.id)")),.CEILING.)")
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
        commonProps(el, e, pset: "Pset_CoveringCommon", [("IsExternal", bool(false))])
    }

    /// A ramp (IfcRamp) aggregating its sloped flights (IfcRampFlight) and landings (IfcSlab LANDING).
    func ramp(_ key: String, _ parts: [BIMElement]) {
        guard let first = parts.first else { return }
        let lv = level(of: first)
        let rpl = placement(relTo: storeyPlacement[lv], .zero)
        var partEntities: [Int] = []
        var flightDirs: [Double] = []
        var rise = 0.0, run = 0.0, width = Double.infinity
        for el in parts {
            guard case .slab(let sl) = el.geometry, let body = slabBody(el, sl, relTo: rpl) else { continue }
            let rep = shape([body.item], type: "SweptSolid")
            let e: Int
            if el.props["kind"] == "landing" || !sl.isSloped {
                e = add("IFCSLAB(\(eg(el)),#\(oh),\(s(name(el, "Ramp Landing"))),$,$,#\(body.placement),#\(rep),\(s("\(el.id)")),.LANDING.)")
                commonProps(el, e, pset: "Pset_SlabCommon", [("IsExternal", bool(isExternal(el, default: false))), ("LoadBearing", bool(true))])
            } else {
                flightDirs.append(sl.slopeDirection)
                let d = Vec2(cos(sl.slopeDirection), sin(sl.slopeDirection))
                let ext = sl.boundary.map { $0.dot(d) }, across = sl.boundary.map { $0.dot(d.perp) }
                let fr = (ext.max() ?? 0) - (ext.min() ?? 0)
                run += fr; rise += fr * tan(sl.slope * .pi / 180)
                width = min(width, (across.max() ?? 0) - (across.min() ?? 0))
                e = add("IFCRAMPFLIGHT(\(eg(el)),#\(oh),\(s(name(el, "Ramp Flight"))),$,$,#\(body.placement),#\(rep),\(s("\(el.id)")),.STRAIGHT.)")
                commonProps(el, e, pset: "Pset_RampFlightCommon", [("Slope", "IFCPLANEANGLEMEASURE(\(r(sl.slope * .pi / 180)))"),
                                                                     ("ClearWidth", length(width.isFinite ? width * k : 0))])
            }
            elementEntity[el.id] = e; useMaterial(el.material, e)
            partEntities.append(e)
        }
        guard !partEntities.isEmpty else { return }
        let type: String
        if flightDirs.count <= 1 { type = ".STRAIGHT_RUN_RAMP." }
        else {
            var turn = 0.0
            for i in 1..<flightDirs.count { var t = flightDirs[i] - flightDirs[i - 1]; while t > .pi { t -= 2 * .pi }; while t < -.pi { t += 2 * .pi }; turn += abs(t) }
            let deg90 = turn / (.pi / 2)
            if flightDirs.count == 2 && abs(deg90) < 0.1 { type = ".TWO_STRAIGHT_RUN_RAMP." }
            else if flightDirs.count == 2 && abs(deg90 - 1) < 0.1 { type = ".QUARTER_TURN_RAMP." }
            else if flightDirs.count == 2 && abs(deg90 - 2) < 0.1 { type = ".HALF_TURN_RAMP." }
            else if flightDirs.count == 3 && abs(deg90 - 2) < 0.1 { type = ".TWO_QUARTER_TURN_RAMP." }
            else { type = ".NOTDEFINED." }
        }
        let rampName = parts.count == 1 ? name(first, "Ramp") : "Ramp \(key)"
        let re = add("IFCRAMP(\(g("ramp:\(key)")),#\(oh),\(s(rampName)),$,$,#\(rpl),$,\(s(key)),\(type))")
        contained[lv, default: []].append(re)
        add("IFCRELAGGREGATES(\(g("rel:ramp:\(key)")),#\(oh),$,$,#\(re),\(refs(partEntities)))")
        let gradient = run > 1e-9 ? rise / run : 0
        psets.append(("Pset_RampCommon", [re], [("Reference", ident(rampName)), ("RequiredSlope", "IFCPLANEANGLEMEASURE(\(r(atan(gradient))))"),
                                                ("HandicapAccessible", bool(gradient <= 1.0 / 12 + 1e-9)), ("IsExternal", bool(isExternal(first, default: false)))]))
    }

    // MARK: phases

    /// IFC4 "Status" of an element from its phases (as of the current phase): NEW, EXISTING or DEMOLISH.
    func phaseStatus(_ el: BIMElement) -> String? {
        guard !doc.phases.isEmpty, el.props["phaseCreated"] != nil || el.props["phaseDemolished"] != nil else { return nil }
        switch Phasing.status(el.props, doc: doc) {
        case .existing: return "EXISTING"
        case .new: return "NEW"
        case .demolished, .gone: return "DEMOLISH"
        case .future: return "NEW"
        }
    }

    /// One IfcGroup per phase ("Phase: <name>") holding the elements created in it; demolished elements also go into
    /// "Demolished: <name>" groups.
    func phaseGroups() {
        guard !doc.phases.isEmpty else { return }
        for (i, ph) in doc.phases.enumerated() {
            for (prefix, key) in [("Phase", "phaseCreated"), ("Demolished", "phaseDemolished")] {
                let members = doc.elements.filter { Phasing.phaseIndex($0.props[key], doc) == i }.compactMap { elementEntity[$0.id] }
                guard !members.isEmpty else { continue }
                let grp = add("IFCGROUP(\(g("group:\(key):\(i)")),#\(oh),\(s("\(prefix): \(ph)")),\(s(key == "phaseCreated" ? "Construction phase" : "Demolition phase")),\(s("Phase")))")
                add("IFCRELASSIGNSTOGROUP(\(g("rel:group:\(key):\(i)")),#\(oh),$,$,\(refs(members)),$,#\(grp))")
            }
        }
    }

    func column(_ el: BIMElement) {
        guard case .column(let c) = el.geometry else { return }
        let lv = level(of: el)
        let pl = placement(relTo: storeyPlacement[lv], Vec3(c.position.x * k, c.position.y * k, c.baseOffset * k), xAxis: Vec2.polar(1, c.rotation))
        let prof: Int
        if c.round {
            let p = add("IFCAXIS2PLACEMENT2D(#\(point2(.zero)),$)")
            prof = add("IFCCIRCLEPROFILEDEF(.AREA.,$,#\(p),\(r(max(c.width * k / 2, 0.001))))")
        } else { prof = rectangle(center: .zero, x: c.width * k, y: c.depth * k) }
        let item = extrusion(profile: prof, depth: c.height * k)
        style(item, material: el.material)
        let rep = shape([item], type: "SweptSolid")
        let e = add("IFCCOLUMN(\(eg(el)),#\(oh),\(s(name(el, "Column"))),$,$,#\(pl),#\(rep),\(s("\(el.id)")),.COLUMN.)")
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
        commonProps(el, e, pset: "Pset_ColumnCommon", [("LoadBearing", bool(true)), ("IsExternal", bool(isExternal(el, default: false)))])
    }

    func beam(_ el: BIMElement) {
        guard case .beam(let b) = el.geometry else { return }
        let lv = level(of: el)
        let L = b.start.distance(to: b.end) * k
        guard L > 0.001 else { return }
        let pl = placement(relTo: storeyPlacement[lv], Vec3(b.start.x * k, b.start.y * k, (b.topOffset - b.depth) * k), xAxis: b.end - b.start)
        let item = extrusion(profile: rectangle(center: Vec2(L / 2, 0), x: L, y: b.width * k), depth: b.depth * k)
        style(item, material: el.material)
        let rep = shape([item], type: "SweptSolid", axis: [Vec2(0, 0), Vec2(L / k, 0)])
        let e = add("IFCBEAM(\(eg(el)),#\(oh),\(s(name(el, "Beam"))),$,$,#\(pl),#\(rep),\(s("\(el.id)")),.BEAM.)")
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
        commonProps(el, e, pset: "Pset_BeamCommon", [("LoadBearing", bool(true)), ("Span", length(L))])
    }

    func space(_ el: BIMElement) {
        guard case .space(let sp) = el.geometry else { return }
        let lv = level(of: el)
        let pl = placement(relTo: storeyPlacement[lv], .zero)
        var rep = "$"
        if let prof = arbitraryProfile(sp.boundary) {
            rep = "#\(shape([extrusion(profile: prof, depth: sp.height * k)], type: "SweptSolid"))"
        }
        let e = add("IFCSPACE(\(eg(el)),#\(oh),\(s(sp.number.isEmpty ? "\(el.id)" : sp.number)),$,$,#\(pl),\(rep),\(s(sp.name)),.ELEMENT.,.INTERNAL.,$)")
        elementEntity[el.id] = e
        spaces[lv, default: []].append(e)
        let area = abs(GeometryOps.signedArea(sp.boundary)) * k * k / 1_000_000
        commonProps(el, e, pset: "Pset_SpaceCommon", [("IsExternal", bool(false)), ("NetPlannedArea", "IFCAREAMEASURE(\(r(area)))")])
    }

    func meshElement(_ el: BIMElement) {
        let lv = level(of: el)
        let elev = elevation(lv)
        let pl = placement(relTo: storeyPlacement[lv], Vec3(0, 0, 0))
        // Mesh coordinates are absolute model coordinates; the storey placement already lifts by its elevation.
        let kk = k
        var items = brep(for: el.id) { p in p * kk - Vec3(0, 0, elev) }
        var repType = meshRepType
        if items.isEmpty, let fb = fallbackSolid(el) { items = [fb]; repType = "SweptSolid"; style(fb, material: el.material) }
        let rep = items.isEmpty ? "$" : "#\(shape(items, type: repType))"
        let gid = eg(el), nm = s(name(el, el.typeName.capitalized)), tag = s("\(el.id)")
        let e: Int
        if let m = IFCClassMap.resolve(el, doc: doc) {
            // Mapped class (IfcExportAs / IFCMAP / category defaults).
            let lit = IFCClassMap.literal(m)
            var objType = lit.objectType
            if objType == nil, case .component(let c) = el.geometry { objType = c.category }
            e = add("\(lit.entity)(\(gid),#\(oh),\(nm),$,\(objType.map { s($0) } ?? "$"),#\(pl),\(rep),\(tag),\(lit.pdt))")
            commonProps(el, e, pset: IFCClassMap.supported[lit.entity]?.pset ?? "Pset_BuildingElementProxyCommon", [])
            elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
            return
        }
        switch el.geometry {
        case .roof(let rf):
            let t: String
            switch rf.kind { case .flat: t = ".FLAT_ROOF."; case .shed: t = ".SHED_ROOF."; case .gable: t = ".GABLE_ROOF."; case .hip: t = ".HIP_ROOF." }
            e = add("IFCROOF(\(gid),#\(oh),\(nm),$,$,#\(pl),\(rep),\(tag),\(t))")
            commonProps(el, e, pset: "Pset_RoofCommon", [("IsExternal", bool(true))])
        case .stair(let st):
            let t: String
            switch st.kind { case .straight: t = ".STRAIGHT_RUN_STAIR."; case .lShape: t = ".QUARTER_TURN_STAIR."; case .uShape: t = ".HALF_TURN_STAIR."; case .spiral: t = ".SPIRAL_STAIR." }
            e = add("IFCSTAIR(\(gid),#\(oh),\(nm),$,$,#\(pl),\(rep),\(tag),\(t))")
            commonProps(el, e, pset: "Pset_StairCommon", [("NumberOfRiser", "IFCCOUNTMEASURE(\(st.riserCount))"), ("RiserHeight", length(st.riserHeight * k)), ("TreadLength", length(st.treadDepth * k))])
        case .railing(let rl):
            e = add("IFCRAILING(\(gid),#\(oh),\(nm),$,$,#\(pl),\(rep),\(tag),.GUARDRAIL.)")
            commonProps(el, e, pset: "Pset_RailingCommon", [("Height", length(rl.height * k))])
        case .curtainWall:
            e = add("IFCCURTAINWALL(\(gid),#\(oh),\(nm),$,$,#\(pl),\(rep),\(tag),.NOTDEFINED.)")
            commonProps(el, e, pset: "Pset_CurtainWallCommon", [("IsExternal", bool(isExternal(el, default: true)))])
        case .component(let c):
            e = add("IFCFURNISHINGELEMENT(\(gid),#\(oh),\(nm),$,\(s(c.category)),#\(pl),\(rep),\(tag))")
            commonProps(el, e, pset: "Archi_ComponentCommon", [])   // Pset_FurnitureTypeCommon applies to IfcFurniture only
        default:
            e = add("IFCBUILDINGELEMENTPROXY(\(gid),#\(oh),\(nm),$,$,#\(pl),\(rep),\(tag),.NOTDEFINED.)")
        }
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
    }

    /// IFC class a drawing object imported from IFC can be written as in the target schema: its original class when that
    /// is a non-abstract element class whose attributes after Tag are all optional, else IfcBuildingElementProxy.
    func productClass(_ ifcType: String?) -> (entity: String, count: Int) {
        let table = IFCSchemaTable.forSchema(options.schema.rawValue)
        let proxy = ("IFCBUILDINGELEMENTPROXY", options.schema == .ifc2x3 ? 9 : 9)
        guard let t = ifcType?.uppercased(), let table, table.contains(t), !table.isAbstract(t), table.isSubtype(t, of: "IFCELEMENT"),
              !table.isSubtype(t, of: "IFCFEATUREELEMENT"), let attrs = table.attributes(t), attrs.count >= 8 else { return proxy }
        if attrs.dropFirst(8).contains(where: { !$0.attr.optional && !$0.derived }) { return proxy }
        return (t, attrs.count)
    }

    /// A solid drawing object that came from an IFC file (props ifcType / ifcGuid), written with its GlobalId, name and
    /// class, contained in its storey (props "level").
    func importedProduct(_ en: Entity) {
        let lvID = doc.levels.first { $0.name == en.props["level"] }?.id ?? (doc.levels.first?.id ?? 0)
        let lv = storeyPlacement[lvID] != nil ? lvID : (storeyPlacement.keys.sorted().first ?? 0)
        let elev = storeyElevation[lv] ?? 0
        let pl = placement(relTo: storeyPlacement[lv], Vec3(0, 0, 0))
        let kk = k
        let items = brep(for: en.id) { p in p * kk - Vec3(0, 0, elev) }
        guard !items.isEmpty else { return }
        let rep = "#\(shape(items, type: meshRepType))"
        var gid = g("entity:\(en.id)")
        if let v = en.props["ifcGuid"], IFCExporter.isValidGuid(v), !usedGuids.contains(v) { usedGuids.insert(v); gid = s(v) }
        let (cls, count) = productClass(en.props["ifcType"])
        let original = en.props["ifcType"].flatMap { IFCSchemaTable.forSchema(options.schema.rawValue)?.className($0) ?? $0 }
        let objType = cls == "IFCBUILDINGELEMENTPROXY" && original != nil && original?.uppercased() != cls ? s(original!) : "$"
        var args = [gid, "#\(oh)", s(en.props["name"] ?? "Object \(en.id)"), "$", objType, "#\(pl)", rep, s("\(en.id)")]
        while args.count < count { args.append("$") }
        let e = add("\(cls)(\(args.joined(separator: ",")))")
        contained[lv, default: []].append(e)
        useMaterial(en.props["material"], e)
    }

    /// Simple extruded solid (storey-relative) for elements without a mesh.
    func fallbackSolid(_ el: BIMElement) -> Int? {
        func rectPts(_ c: Vec2, _ w: Double, _ d: Double, _ rot: Double) -> [Vec2] {
            let t = Transform2D.translation(c) * Transform2D.rotation(rot)
            return [Vec2(-w / 2, -d / 2), Vec2(w / 2, -d / 2), Vec2(w / 2, d / 2), Vec2(-w / 2, d / 2)].map(t.apply)
        }
        switch el.geometry {
        case .roof(let rf):
            guard let p = arbitraryProfile(rf.boundary) else { return nil }
            return extrusion(profile: p, depth: rf.thickness * k, at: Vec3(0, 0, rf.baseOffset * k))
        case .stair(let st):
            let dir = Vec2.polar(1, st.direction)
            let len = max(st.runLength, st.treadDepth)
            guard let p = arbitraryProfile(rectPts(st.start + dir * (len / 2), len, st.width, st.direction)) else { return nil }
            return extrusion(profile: p, depth: st.totalRise * k)
        case .component(let c):
            guard let p = arbitraryProfile(rectPts(c.position, c.size.x, c.size.y, c.rotation)) else { return nil }
            return extrusion(profile: p, depth: c.size.z * k, at: Vec3(0, 0, c.baseOffset * k))
        case .curtainWall(let cw):
            let d = cw.end - cw.start
            guard d.length > geomEpsilon, let p = arbitraryProfile(rectPts((cw.start + cw.end) / 2, d.length, max(cw.mullionSize, 20), d.angle)) else { return nil }
            return extrusion(profile: p, depth: cw.height * k, at: Vec3(0, 0, cw.baseOffset * k))
        case .railing(let rl):
            guard rl.path.count >= 2 else { return nil }
            var left: [Vec2] = [], right: [Vec2] = []
            for i in 0..<rl.path.count {
                let a = rl.path[max(0, i - 1)], b = rl.path[min(rl.path.count - 1, i + 1)]
                let n = (b - a).normalized.perp * 25
                left.append(rl.path[i] + n); right.append(rl.path[i] - n)
            }
            guard let p = arbitraryProfile(left + right.reversed()) else { return nil }
            return extrusion(profile: p, depth: rl.height * k, at: Vec3(0, 0, rl.baseOffset * k))
        default: return nil
        }
    }
}
