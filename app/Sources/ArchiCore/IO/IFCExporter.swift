// Oanarina Archi Tool — GPL-3.0-or-later
// IFC4 (ISO 10303-21 STEP) exporter. Entity attribute orders follow the IFC4 schema (buildingSMART);
// the GUID compression algorithm matches IfcOpenShell's ifcopenshell.guid (LGPL-3.0, © IfcOpenShell contributors).
import Foundation

public enum IFCExporter {
    public static func export(doc: ArchiDocument, meshes: [MeshGroup]) -> String {
        let b = IFCBuilder(doc: doc, meshes: meshes)
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

    init(doc: ArchiDocument, meshes: [MeshGroup]) {
        self.doc = doc; self.meshes = meshes; self.k = doc.units.mm
    }

    @discardableResult
    func add(_ s: String) -> Int { let id = nextId; nextId += 1; lines.append("#\(id)=\(s);"); return id }
    func r(_ v: Double) -> String { IFCExporter.real(v) }
    func s(_ v: String) -> String { IFCExporter.str(v) }
    func g(_ key: String) -> String { s(IFCExporter.guid(key)) }
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

    /// Faceted B-rep of all mesh groups with this element id; `map` converts model coordinates to the local frame (mm).
    func brep(for id: EntityID, map: (Vec3) -> Vec3) -> [Int] {
        var items: [Int] = []
        for grp in meshes where grp.id == id {
            let m = grp.mesh
            let tris = MeshExport.triangles(m)
            guard !tris.isEmpty else { continue }
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
        let sitePl = placement(relTo: nil, .zero)
        func dms(_ v: Double) -> String {
            let sign = v < 0 ? -1.0 : 1.0
            var a = abs(v)
            let d = Int(a); a = (a - Double(d)) * 60
            let m = Int(a); a = (a - Double(m)) * 60
            let sec = Int(a); let micro = Int(((a - Double(sec)) * 1_000_000).rounded())
            return "(\(Int(sign) * d),\(Int(sign) * m),\(Int(sign) * sec),\(Int(sign) * micro))"
        }
        let address = doc.info.address.isEmpty ? "$" : "#\(add("IFCPOSTALADDRESS($,$,$,$,(\(s(doc.info.address))),$,$,$,$,$)"))"
        let site = add("IFCSITE(\(g("site")),#\(oh),'Site',$,$,#\(sitePl),$,$,.ELEMENT.,\(dms(doc.info.latitude)),\(dms(doc.info.longitude)),0.,$,\(address))")
        let bldPl = placement(relTo: sitePl, .zero)
        let building = add("IFCBUILDING(\(g("building")),#\(oh),\(s(doc.info.name)),$,$,#\(bldPl),$,$,.ELEMENT.,$,$,$)")
        add("IFCRELAGGREGATES(\(g("rel:project-site")),#\(oh),$,$,#\(project),(#\(site)))")
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
        for el in doc.elements {
            switch el.geometry {
            case .wall: break
            case .opening: opening(el)
            case .slab: slab(el)
            case .column: column(el)
            case .beam: beam(el)
            case .space: space(el)
            case .gridLine: break
            default: meshElement(el)
            }
        }

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

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var out = "ISO-10303-21;\nHEADER;\n"
        out += "FILE_DESCRIPTION(('ViewDefinition [ReferenceView_V1.2]'),'2;1');\n"
        out += "FILE_NAME(\(s(doc.info.name + ".ifc")),\(s(iso.string(from: Date()))),(\(s(author))),('Oanarina'),'Oanarina Archi Tool','Oanarina Archi Tool','');\n"
        out += "FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n"
        out += lines.joined(separator: "\n")
        out += "\nENDSEC;\nEND-ISO-10303-21;\n"
        return out
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
    func commonProps(_ el: BIMElement, _ entity: Int, pset: String, _ extra: [(String, String)]) {
        var p: [(String, String)] = [("Reference", ident(el.name.isEmpty ? el.typeName : el.name))]
        p += extra
        psets.append((pset, [entity], p))
        let custom = el.props.sorted { $0.key < $1.key }.filter { !$0.key.isEmpty }
        if !custom.isEmpty { psets.append(("Archi_Properties", [entity], custom.map { ($0.key, label($0.value)) })) }
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
        let e = add("IFCWALL(\(g("element:\(el.id)")),#\(oh),\(s(name(el, "Wall"))),$,\(w.wallType.map { s($0) } ?? "$"),#\(pl),#\(rep),\(s("\(el.id)")),.STANDARD.)")
        wallPlacement[el.id] = pl; wallEntity[el.id] = e; elementEntity[el.id] = e
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
        let rep = shape(items, type: usedMesh ? "Brep" : "SweptSolid")
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
            e = add("IFCDOOR(\(g("element:\(el.id)")),#\(oh),\(s(name(el, "Door"))),$,$,#\(fpl),#\(rep),\(s(el.props["mark"] ?? "\(el.id)")),\(r(Hh)),\(r(W)),.DOOR.,\(op),$)")
            commonProps(el, e, pset: "Pset_DoorCommon", [("IsExternal", bool(isExternal(el, default: isExternal(host, default: (w.wallType ?? "").lowercased().contains("exterior")))))])
        } else {
            let part: String
            switch o.windowStyle {
            case .fixed, .casement, .awning: part = ".SINGLE_PANEL."
            case .doubleCasement, .sliding: part = ".DOUBLE_PANEL_VERTICAL."
            case .hung: part = ".DOUBLE_PANEL_HORIZONTAL."
            }
            e = add("IFCWINDOW(\(g("element:\(el.id)")),#\(oh),\(s(name(el, "Window"))),$,$,#\(fpl),#\(rep),\(s(el.props["mark"] ?? "\(el.id)")),\(r(Hh)),\(r(W)),.WINDOW.,\(part),$)")
            commonProps(el, e, pset: "Pset_WindowCommon", [("IsExternal", bool(isExternal(el, default: isExternal(host, default: true))))])
        }
        add("IFCRELFILLSELEMENT(\(g("rel:fills:\(el.id)")),#\(oh),$,$,#\(oe),#\(e))")
        elementEntity[el.id] = e
        contained[lv, default: []].append(e)
        useMaterial(el.material, e)
    }

    func slab(_ el: BIMElement) {
        guard case .slab(let sl) = el.geometry else { return }
        let lv = level(of: el)
        let pl = placement(relTo: storeyPlacement[lv], Vec3(0, 0, (sl.topOffset - sl.thickness) * k))
        guard let prof = arbitraryProfile(sl.boundary, holes: sl.holes) else { return }
        let item = extrusion(profile: prof, depth: sl.thickness * k)
        style(item, material: el.material)
        let rep = shape([item], type: "SweptSolid")
        let e = add("IFCSLAB(\(g("element:\(el.id)")),#\(oh),\(s(name(el, "Slab"))),$,$,#\(pl),#\(rep),\(s("\(el.id)")),.FLOOR.)")
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
        commonProps(el, e, pset: "Pset_SlabCommon", [("IsExternal", bool(isExternal(el, default: false))), ("LoadBearing", bool(true))])
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
        let e = add("IFCCOLUMN(\(g("element:\(el.id)")),#\(oh),\(s(name(el, "Column"))),$,$,#\(pl),#\(rep),\(s("\(el.id)")),.COLUMN.)")
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
        let e = add("IFCBEAM(\(g("element:\(el.id)")),#\(oh),\(s(name(el, "Beam"))),$,$,#\(pl),#\(rep),\(s("\(el.id)")),.BEAM.)")
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
        let e = add("IFCSPACE(\(g("element:\(el.id)")),#\(oh),\(s(sp.number.isEmpty ? "\(el.id)" : sp.number)),$,$,#\(pl),\(rep),\(s(sp.name)),.ELEMENT.,.INTERNAL.,$)")
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
        var repType = "Brep"
        if items.isEmpty, let fb = fallbackSolid(el) { items = [fb]; repType = "SweptSolid"; style(fb, material: el.material) }
        let rep = items.isEmpty ? "$" : "#\(shape(items, type: repType))"
        let gid = g("element:\(el.id)"), nm = s(name(el, el.typeName.capitalized)), tag = s("\(el.id)")
        let e: Int
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
            commonProps(el, e, pset: "Pset_FurnitureTypeCommon", [])
        default:
            e = add("IFCBUILDINGELEMENTPROXY(\(gid),#\(oh),\(nm),$,$,#\(pl),\(rep),\(tag),.NOTDEFINED.)")
        }
        elementEntity[el.id] = e; contained[lv, default: []].append(e); useMaterial(el.material, e)
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
