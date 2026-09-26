// Oanarina Archi Tool — GPL-3.0-or-later
// In-place generic models (BIM-103), curtain systems on mass faces (BIM-031), graded regions with cut/fill volumes
// (BIM-113), electrical circuits and panel schedules (BIM-109) and room data sheets that edit back to the model (DOC-050).
import Foundation

// MARK: - In-place models (BIM-103)

public enum InPlaceModels {
    /// World triangles of an in-place component (local mesh → position / rotation / level + base offset).
    public static func worldTriangles(_ g: ComponentGeom, z0: Double) -> [Tri3] {
        guard let m = g.mesh else { return [] }
        let c = cos(g.rotation), s = sin(g.rotation)
        func w(_ p: Vec3) -> Vec3 { Vec3(g.position.x + p.x * c - p.y * s, g.position.y + p.x * s + p.y * c, z0 + p.z) }
        return MeshTools.triangles(MeshTools.mesh(of: m)).map { (w($0.0), w($0.1), w($0.2)) }
    }

    /// Component (in local coordinates, base centred) made from solids in world coordinates.
    public static func component(from solids: [SolidGeom], category: String, levelElevation elev: Double) -> ComponentGeom? {
        var tris: [Tri3] = []
        for s in solids { tris += MeshTools.triangles(MeshTools.mesh(of: s)) }
        guard !tris.isEmpty else { return nil }
        var b = BBox3.empty
        for t in tris { b.add(t.0); b.add(t.1); b.add(t.2) }
        let o = Vec3((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, b.min.z)
        let local = tris.map { ($0.0 - o, $0.1 - o, $0.2 - o) }
        let w = MeshTools.weld(local, tolerance: max(b.size.x, b.size.y, b.size.z, 1) * 1e-9)
        var lb = BBox3.empty; w.vertices.forEach { lb.add($0) }
        var g = ComponentGeom(category: category, position: o.xy, size: Vec3(max(b.size.x, 1), max(b.size.y, 1), max(b.size.z, 1)), baseOffset: b.min.z - elev)
        g.mesh = SolidGeom(kind: .mesh, origin: lb.min, meshVertices: w.vertices, meshTriangles: w.triangles)
        return g
    }

    static func meshGroups(_ el: BIMElement, _ g: ComponentGeom, z0: Double) -> [MeshGroup] {
        let tris = worldTriangles(g, z0: z0)
        guard !tris.isEmpty else { return [] }
        var acc = MeshAcc()
        for t in tris { let n = (t.1 - t.0).cross(t.2 - t.0).normalized; acc.tri(t.0, t.1, t.2, n, n, n) }
        let w = MeshTools.weld(tris, tolerance: 1e-6)
        if w.triangles.count <= 60_000 { acc.edges = MeshTools.featureEdges(vertices: w.vertices, triangles: w.triangles, angle: 25) }
        return [acc.group(el.id, "component", el.material ?? "Concrete")].compactMap { $0 }
    }

    /// Plan outline (projected feature edges) of an in-place component.
    static func planEdges(_ g: ComponentGeom) -> [[Vec2]] {
        let tris = worldTriangles(g, z0: 0)
        let w = MeshTools.weld(tris, tolerance: 1e-6)
        return MeshTools.planEdges(vertices: w.vertices, triangles: w.triangles)
    }
}

// MARK: - Curtain systems by face (BIM-031)

public enum CurtainSystems {
    /// Curtain walls on the vertical planar faces of a mass: each runs along the face's bottom edge (exterior on its
    /// right) and spans the face height.
    public static func walls(on s: SolidGeom, levelElevation elev: Double, gridU: Double, gridV: Double, mullion: Double) -> [CurtainWallGeom] {
        let a = PlanarFaces.analyse(s)
        var out: [CurtainWallGeom] = []
        for f in 0..<a.faceCount {
            let n = a.normals[f]
            guard abs(n.z) < 0.02, a.area(ofFace: f) > 1e-6 else { continue }
            let h = Vec2(-n.y, n.x).normalized
            let vs = a.vertices(ofFace: f).map { a.vertices[$0] }
            guard let p0 = vs.first else { continue }
            let ss = vs.map { ($0.xy - p0.xy).dot(h) }
            let zs = vs.map(\.z)
            guard let s0 = ss.min(), let s1 = ss.max(), let z0 = zs.min(), let z1 = zs.max(), s1 - s0 > 1e-6, z1 - z0 > 1e-6 else { continue }
            let start = p0.xy + h * s0, end = p0.xy + h * s1
            out.append(CurtainWallGeom(start: start, end: end, height: z1 - z0, baseOffset: z0 - elev, gridU: gridU, gridV: gridV, mullionSize: mullion))
        }
        return out
    }
}

// MARK: - Graded regions (BIM-113)

/// Triangulated surface with a bucket grid for fast elevation queries.
public struct TINIndex {
    let v: [Vec3]
    let t: [Int]
    let box: BBox2
    let n: Int
    var cells: [[Int]]
    public init(_ surf: (vertices: [Vec3], triangles: [Int])) {
        v = surf.vertices; t = surf.triangles
        box = BBox2(points: v.map(\.xy))
        n = max(1, min(256, Int(Double(t.count / 3).squareRoot())))
        cells = Array(repeating: [], count: n * n)
        guard !box.isEmpty else { return }
        var k = 0
        while k + 2 < t.count {
            let b = BBox2(points: [v[t[k]].xy, v[t[k + 1]].xy, v[t[k + 2]].xy])
            let (i0, j0) = cell(b.min), (i1, j1) = cell(b.max)
            for i in i0...i1 { for j in j0...j1 { cells[j * n + i].append(k) } }
            k += 3
        }
    }
    func cell(_ p: Vec2) -> (Int, Int) {
        let fx = box.width > 0 ? (p.x - box.min.x) / box.width : 0, fy = box.height > 0 ? (p.y - box.min.y) / box.height : 0
        return (min(n - 1, max(0, Int(fx * Double(n)))), min(n - 1, max(0, Int(fy * Double(n)))))
    }
    /// Elevation at a plan point (nil outside the surface).
    public func elevation(at p: Vec2) -> Double? {
        guard !box.isEmpty, box.expanded(by: 1e-9).contains(p) else { return nil }
        let (i, j) = cell(p)
        for k in cells[j * n + i] {
            let a = v[t[k]], b = v[t[k + 1]], c = v[t[k + 2]]
            let d = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
            guard abs(d) > 1e-18 else { continue }
            let l1 = ((b.x - p.x) * (c.y - p.y) - (c.x - p.x) * (b.y - p.y)) / d
            let l2 = ((c.x - p.x) * (a.y - p.y) - (a.x - p.x) * (c.y - p.y)) / d
            let l3 = 1 - l1 - l2
            let e = -1e-9
            if l1 >= e && l2 >= e && l3 >= e { return l1 * a.z + l2 * b.z + l3 * c.z }
        }
        return nil
    }
}

public enum Grading {
    /// Points of the upper (terrain) surface of a toposurface solid.
    public static func surfacePoints(_ s: SolidGeom) -> [Vec3] {
        let w = SolidOps.welded(s)
        var keep = Set<Int>()
        var i = 0
        while i + 2 < w.triangles.count {
            let a = w.vertices[w.triangles[i]], b = w.vertices[w.triangles[i + 1]], c = w.vertices[w.triangles[i + 2]]
            if (b - a).cross(c - a).normalized.z > 0.05 { keep.formUnion([w.triangles[i], w.triangles[i + 1], w.triangles[i + 2]]) }
            i += 3
        }
        return keep.sorted().map { w.vertices[$0] }
    }

    /// Proposed surface points: flat at `pad` inside the boundary, then daylighting to the existing ground at
    /// `slope` horizontal per vertical (0 = vertical sides).
    public static func graded(points: [Vec3], boundary b0: [Vec2], pad: Double, slope: Double) -> [Vec3] {
        var b = RG.dedupe(b0, closed: true)
        guard b.count >= 3, points.count >= 3 else { return points }
        if GeometryOps.signedArea(b) < 0 { b.reverse() }
        let tin = TINIndex(Terrain.surface(points))
        var box = BBox2(points: points.map(\.xy))
        let size = max(box.width, box.height, 1)
        func old(_ p: Vec2) -> Double? { tin.elevation(at: p) }
        let ring = b + [b[0]]
        func dist(_ p: Vec2) -> Double { GeometryOps.pointInPolygon(p, b) ? 0 : GeometryOps.distance(from: p, toPolyline: ring) }
        func proposed(_ p: Vec2, _ zo: Double) -> Double {
            let d = dist(p)
            if d <= 0 { return pad }
            guard slope > 0 else { return zo }
            return zo > pad ? min(zo, pad + d / slope) : max(zo, pad - d / slope)
        }
        var out: [Vec3] = []
        for p in points where dist(p.xy) > 0 { out.append(Vec3(p.x, p.y, proposed(p.xy, p.z))) }
        // Boundary (densified) at pad level, with a thin step just outside for vertical sides.
        let step = size / 100
        let eps = size * 1e-4
        for k in 0..<b.count {
            let a = b[k], c = b[(k + 1) % b.count]
            let m = max(1, Int(a.distance(to: c) / step))
            let outward = Vec2((c - a).y, -(c - a).x).normalized
            for j in 0..<m {
                let q = a.lerp(c, Double(j) / Double(m))
                out.append(Vec3(q.x, q.y, pad))
                let qo = q + outward * eps
                if slope <= 0, let zo = old(qo) { out.append(Vec3(qo.x, qo.y, zo)) }
            }
        }
        // Grid samples inside the pad and across the daylight band.
        box.add(BBox2(points: b))
        let n = 40
        for i in 0...n {
            for j in 0...n {
                let q = Vec2(box.min.x + box.width * Double(i) / Double(n), box.min.y + box.height * Double(j) / Double(n))
                guard let zo = old(q) else { continue }
                let d = dist(q)
                if d <= 0 || (slope > 0 && abs(zo - pad) * slope >= d) { out.append(Vec3(q.x, q.y, proposed(q, zo))) }
            }
        }
        // Drop coincident plan points (the first one wins: existing points, then the boundary).
        var seen = Set<[Int64]>()
        let q = size * 1e-6
        return out.filter { seen.insert([Int64(($0.x / q).rounded()), Int64(($0.y / q).rounded())]).inserted }
    }

    /// Cut and fill volumes between two surfaces (sampled on a grid of `cells` × `cells` over the existing extents).
    public static func cutFill(existing: [Vec3], proposed: [Vec3], cells: Int = 200) -> (cut: Double, fill: Double) {
        let e = TINIndex(Terrain.surface(existing)), p = TINIndex(Terrain.surface(proposed))
        let box = BBox2(points: existing.map(\.xy))
        guard !box.isEmpty, box.width > 0, box.height > 0 else { return (0, 0) }
        let n = max(10, cells)
        let dx = box.width / Double(n), dy = box.height / Double(n)
        var cut = 0.0, fill = 0.0
        for i in 0..<n {
            for j in 0..<n {
                let q = Vec2(box.min.x + dx * (Double(i) + 0.5), box.min.y + dy * (Double(j) + 0.5))
                guard let ze = e.elevation(at: q), let zp = p.elevation(at: q) else { continue }
                if zp > ze { fill += (zp - ze) * dx * dy } else { cut += (ze - zp) * dx * dy }
            }
        }
        return (cut, fill)
    }
}

// MARK: - Electrical circuits (BIM-109)

public enum Circuits {
    /// Default connected loads (VA) by family.
    public static let defaultLoad: [String: Double] = ["outlet": 180, "light-ceiling": 100, "light-wall": 60, "smoke-detector": 5, "fridge": 400,
                                                       "range": 3000, "washer": 2200, "switch": 0, "data-outlet": 0, "air-supply": 0, "radiator": 0]
    public struct Circuit: Hashable {
        public var panel: EntityID
        public var number: Int
        public var devices: [EntityID]
        public var load: Double
        public var description: String
        public var breaker: Double
        public var phase: String
    }

    public static func isPanel(_ el: BIMElement) -> Bool { if case .component(let g) = el.geometry { return g.family == "panel" }; return false }
    public static func isDevice(_ el: BIMElement) -> Bool {
        guard case .component(let g) = el.geometry, g.family != "panel" else { return false }
        if let f = ComponentLibrary.family(g.family) { return ComponentLibrary.connectors(f, size: g.size).contains { $0.system == "POWER" } }
        return ["Electrical", "Lighting"].contains(g.category)
    }
    public static func panelName(_ el: BIMElement) -> String { el.props["panelName"] ?? (el.name.isEmpty ? "P\(el.id)" : el.name) }
    public static func load(_ el: BIMElement) -> Double {
        if let v = el.props["loadVA"].flatMap(Double.init) { return v }
        if case .component(let g) = el.geometry, let f = g.family { return defaultLoad[f] ?? 0 }
        return 0
    }
    /// Phase of a circuit on a panel (1 or 3 phases): circuits 1–2 on L1, 3–4 on L2, 5–6 on L3, …
    public static func phase(_ n: Int, phases: Int) -> String { phases >= 3 ? "L\(((max(n, 1) - 1) / 2) % 3 + 1)" : "L1" }

    public static func circuits(_ doc: ArchiDocument, panel: EntityID) -> [Circuit] {
        guard let p = doc.element(panel) else { return [] }
        let phases = Int(p.props["phases"] ?? "") ?? 3
        var byNo: [Int: [BIMElement]] = [:]
        for el in doc.elements where el.props["circuitPanel"] == "\(panel)" {
            guard let n = Int(el.props["circuitNo"] ?? "") else { continue }
            byNo[n, default: []].append(el)
        }
        return byNo.keys.sorted().map { n in
            let devs = byNo[n]!
            let meta = (p.props["circuit.\(n)"] ?? "").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let desc = meta.first.flatMap { $0.isEmpty ? nil : $0 } ?? Array(Set(devs.map { d -> String in
                if case .component(let g) = d.geometry, let f = ComponentLibrary.family(g.family) { return f.name }; return d.typeName })).sorted().joined(separator: ", ")
            let breaker = meta.count > 1 ? Double(meta[1]) ?? 16 : 16
            return Circuit(panel: panel, number: n, devices: devs.map(\.id), load: devs.map(load).reduce(0, +), description: desc, breaker: breaker, phase: phase(n, phases: phases))
        }
    }

    public static func nextNumber(_ doc: ArchiDocument, panel: EntityID) -> Int { (circuits(doc, panel: panel).map(\.number).max() ?? 0) + 1 }

    /// Panel schedule rows (header first, totals and phase loads last).
    public static func schedule(_ doc: ArchiDocument, panel: EntityID) -> [[String]] {
        let cs = circuits(doc, panel: panel)
        var rows = [["Circuit", "Description", "Devices", "Load (VA)", "Breaker (A)", "Phase"]]
        for c in cs { rows.append(["\(c.number)", c.description, "\(c.devices.count)", fmt(c.load, 0), fmt(c.breaker, 0), c.phase]) }
        rows.append(["Total", "", "\(cs.map(\.devices.count).reduce(0, +))", fmt(cs.map(\.load).reduce(0, +), 0), "", ""])
        for ph in ["L1", "L2", "L3"] {
            let l = cs.filter { $0.phase == ph }.map(\.load).reduce(0, +)
            if l > 0 || ph == "L1" { rows.append([ph, "", "", fmt(l, 0), "", ""]) }
        }
        return rows
    }

    /// Wiring: the devices of a circuit chained nearest-first from the panel.
    public static func wiring(_ doc: ArchiDocument, _ c: Circuit) -> [Vec2] {
        guard let p = doc.element(c.panel), case .component(let pg) = p.geometry else { return [] }
        var rest = c.devices.compactMap { id -> Vec2? in if case .component(let g)? = doc.element(id)?.geometry { return g.position }; return nil }
        var path = [pg.position]
        while !rest.isEmpty {
            let last = path.last!
            let k = rest.indices.min { rest[$0].distance(to: last) < rest[$1].distance(to: last) }!
            path.append(rest.remove(at: k))
        }
        return path
    }
}

// MARK: - Room data sheets (DOC-050)

public enum RoomDataSheets {
    /// Editable fields and where they live.
    public static let editable = ["Name", "Number", "Department", "Occupancy", "Floor finish", "Base finish", "Wall finish", "Ceiling finish", "Comments"]
    static let propKey: [String: String] = ["Department": "department", "Occupancy": "occupancy", "Floor finish": RoomFinishes.keys[0], "Base finish": RoomFinishes.keys[1],
                                            "Wall finish": RoomFinishes.keys[2], "Ceiling finish": RoomFinishes.keys[3], "Comments": "comments"]
    public static let computed = ["Level", "Area (m²)", "Perimeter (m)", "Height (m)", "Volume (m³)", "Doors", "Windows", "Furniture & equipment"]

    static func openingsAndContents(_ doc: ArchiDocument, _ el: BIMElement, _ g: SpaceGeom) -> (doors: Int, windows: Int, contents: [String]) {
        let u = 1 / doc.units.mm
        let ring = g.boundary + [g.boundary[0]]
        var doors = 0, windows = 0
        var contents: [String: Int] = [:]
        for o in doc.elements where o.level == el.level {
            switch o.geometry {
            case .opening(let op):
                let f = CommandHelpers.footprint(o, doc: doc)
                guard f.count >= 2 else { continue }
                let c = GeometryOps.centroid(f)
                guard GeometryOps.distance(from: c, toPolyline: ring) <= 400 * u else { continue }
                if op.kind == .door { doors += 1 } else if op.kind == .window { windows += 1 }
            case .component(let cg) where cg.path == nil:
                guard GeometryOps.pointInPolygon(cg.position, g.boundary) else { continue }
                let name = ComponentLibrary.family(cg.family)?.name ?? (o.name.isEmpty ? cg.category : o.name)
                contents[name, default: 0] += 1
            default: continue
            }
        }
        return (doors, windows, contents.keys.sorted().map { contents[$0]! > 1 ? "\($0) ×\(contents[$0]!)" : $0 })
    }

    /// Data sheet of one room: (field, value) in display order.
    public static func sheet(_ doc: ArchiDocument, room id: EntityID) -> [(String, String)]? {
        guard let el = doc.element(id), case .space(let g) = el.geometry, g.boundary.count >= 3 else { return nil }
        let row = RoomSchedule.compute(doc, level: el.level).first { $0.id == id }
        let oc = openingsAndContents(doc, el, g)
        var out: [(String, String)] = [("Name", g.name), ("Number", g.number)]
        for f in editable.dropFirst(2) { out.append((f, el.props[propKey[f]!] ?? "")) }
        out += [("Level", doc.level(el.level)?.name ?? "\(el.level)"), ("Area (m²)", fmt(row?.netArea ?? 0, 2)), ("Perimeter (m)", fmt(row?.perimeter ?? 0, 2)),
                ("Height (m)", fmt(row?.height ?? 0, 2)), ("Volume (m³)", fmt(row?.volume ?? 0, 2)), ("Doors", "\(oc.doors)"), ("Windows", "\(oc.windows)"),
                ("Furniture & equipment", oc.contents.joined(separator: "; "))]
        return out
    }

    public static func rooms(_ doc: ArchiDocument) -> [EntityID] {
        doc.elements.compactMap { el -> (EntityID, String, String)? in
            guard case .space(let g) = el.geometry else { return nil }
            return (el.id, doc.level(el.level)?.name ?? "", g.number)
        }.sorted { ($0.1, $0.2, $0.0) < ($1.1, $1.2, $1.0) }.map(\.0)
    }

    public static func text(_ doc: ArchiDocument, rooms ids: [EntityID]) -> String {
        ids.compactMap { id in sheet(doc, room: id).map { s in
            "ROOM DATA SHEET — \(s[1].1) \(s[0].1)\n" + s.map { "  \($0.0): \($0.1)" }.joined(separator: "\n")
        } }.joined(separator: "\n\n")
    }

    public static func csv(_ doc: ArchiDocument, rooms ids: [EntityID]) -> String {
        let header = ["ID"] + editable + computed
        let rows = ids.compactMap { id in sheet(doc, room: id).map { ["\(id)"] + $0.map(\.1) } }
        return CSVText.make([header] + rows)
    }

    static func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }

    public static func html(_ doc: ArchiDocument, rooms ids: [EntityID]) -> String {
        var h = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Room data sheets</title><style>body{font-family:-apple-system,Helvetica,sans-serif;margin:24px}section{page-break-after:always;margin-bottom:32px}h2{border-bottom:3px solid #F5C518;padding-bottom:4px}table{border-collapse:collapse;width:100%}td{border:1px solid #ccc;padding:4px 8px}td:first-child{width:30%;font-weight:600;background:#f6f6f6}</style></head><body>\n"
        for id in ids {
            guard let s = sheet(doc, room: id) else { continue }
            h += "<section><h2>\(esc(s[1].1)) \(esc(s[0].1))</h2><table>\n"
            for (k, v) in s { h += "<tr><td>\(esc(k))</td><td>\(esc(v))</td></tr>\n" }
            h += "</table></section>\n"
        }
        return h + "</body></html>\n"
    }

    /// Sets one editable field of a room. Returns false for unknown fields or non-rooms.
    @discardableResult
    public static func set(_ field: String, _ value: String, room id: EntityID, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.elementIndex(id), case .space(var g) = doc.elements[i].geometry,
              let f = editable.first(where: { $0.caseInsensitiveCompare(field) == .orderedSame }) else { return false }
        switch f {
        case "Name": g.name = value; doc.elements[i].geometry = .space(g)
        case "Number": g.number = value; doc.elements[i].geometry = .space(g)
        default: doc.elements[i].props[propKey[f]!] = value.isEmpty ? nil : value
        }
        return true
    }

    /// Applies an edited data-sheet CSV (as exported) back to the rooms; computed columns are ignored.
    public static func apply(csv text: String, doc: inout ArchiDocument) -> (changed: Int, errors: [String]) {
        let rows = Schedules.parseCSV(text)
        guard let header = rows.first, let idCol = header.firstIndex(of: "ID") else { return (0, ["The file has no ID column."]) }
        var changed = 0, errors: [String] = []
        for r in rows.dropFirst() where r.count > idCol {
            guard let id = EntityID(r[idCol].trimmingCharacters(in: .whitespaces)), let cur = sheet(doc, room: id) else { if !r[idCol].isEmpty { errors.append("Unknown room \(r[idCol])") }; continue }
            var did = false
            for (c, name) in header.enumerated() where c < r.count && editable.contains(name) {
                let old = cur.first { $0.0 == name }?.1 ?? ""
                if r[c] != old { set(name, r[c], room: id, doc: &doc); did = true }
            }
            if did { changed += 1 }
        }
        return (changed, errors)
    }
}

// MARK: - Commands

enum BIMCommands9 {
    static var all: [CommandDef] { [inPlace, curtainSystem, gradedRegion, circuit, panelSchedule, roomDataSheet, graphicDisplay] }

    static var graphicDisplay: CommandDef {
        CommandDef("GRAPHICDISPLAY", aliases: ["GDO", "DISPLAYOPTIONS"], category: "View", summary: "Graphic display options of the current view: Sketchy lines (0–10), Silhouettes (line weight, 0 = off) and cast Shadows in plan; saved with the view.") { ed in
            let o = GraphicDisplay.options(ed.doc)
            let sk = try await ed.getReal("Sketchy lines strength 0–10 (0 = off)", defaultValue: o.sketchy).value ?? o.sketchy
            guard sk >= 0, sk <= 10 else { throw CommandError.invalid("Enter 0 to 10.") }
            let si = try await ed.getReal("Silhouette line weight in mm (0 = off)", defaultValue: o.silhouette).value ?? o.silhouette
            guard si >= 0, si <= 2.11 else { throw CommandError.invalid("Enter a line weight between 0 and 2.11 mm.") }
            let sh = try await ed.getYesNo("Cast shadows in plan?", defaultValue: o.shadows)
            @MainActor func set(_ k: String, _ v: String?) { if let v = v { ed.doc.setVariable(k, v) } else { ed.doc.variables[k] = nil } }
            set(GraphicDisplay.sketchyKey, sk > 0 ? fmt(sk) : nil)
            set(GraphicDisplay.silhouetteKey, si > 0 ? fmt(si) : nil)
            set(GraphicDisplay.shadowKey, sh ? "1" : nil)
            ed.print("Graphic display: sketchy \(sk > 0 ? fmt(sk) : "off"), silhouettes \(si > 0 ? fmt(si) + " mm" : "off"), shadows \(sh ? "on" : "off")" + (ed.doc.currentView.map { " (view \($0.name))" } ?? "") + ".")
        }
    }

    static var inPlace: CommandDef {
        CommandDef("INPLACE", aliases: ["INPLACEMODEL", "GENERICMODEL", "MODELINPLACE"], category: "Architecture", summary: "In-place generic model: turns solids modelled in context into a schedulable component (Create), or back into solids to edit (Edit).") { ed in
            let k = try await ed.getKeyword("In-place model [Create/Edit]", ["Create", "Edit"], defaultValue: "Create") ?? "Create"
            if k == "Edit" {
                guard case .pick(let pk) = try await ed.pickObject("Select an in-place component", filter: { id in
                    if case .component(let g)? = ed.doc.element(id)?.geometry { return g.mesh != nil }; return false }),
                      let el = ed.doc.element(pk.id), case .component(let g) = el.geometry else { return }
                let z0 = (ed.doc.level(el.level)?.elevation ?? 0) + g.baseOffset
                let s = MeshTools.solid(from: InPlaceModels.worldTriangles(g, z0: z0), tolerance: 1e-6)
                var e = Entity(layer: ed.doc.currentLayer, geometry: .solid(s))
                e.props["material"] = el.material; e.props["inPlaceName"] = el.name; e.props["inPlaceCategory"] = g.category
                let id = ed.doc.add(e)
                ed.doc.elements.removeAll { $0.id == pk.id }
                ed.selection = [id]
                ed.print("In-place model \(el.name) opened as solid #\(id); run INPLACE Create again to finish.")
                return
            }
            let ids = try await ModelingCommands.selectSolids(ed, "Select the solids of the in-place model")
            guard !ids.isEmpty else { return }
            let first = ed.doc.entity(ids[0])
            let cat = try await ed.getWord("Category", defaultValue: first?.props["inPlaceCategory"] ?? "Generic Models") ?? "Generic Models"
            let name = try await ed.getString("Name", defaultValue: first?.props["inPlaceName"] ?? "In-place \(ed.doc.elements.filter { $0.props["inPlace"] == "1" }.count + 1)") ?? "In-place"
            let elev = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            guard let g = InPlaceModels.component(from: ids.compactMap { ModelingCommands.solidOf(ed.doc, $0) }, category: cat, levelElevation: elev) else { throw CommandError.invalid("The solids are empty.") }
            let id = ed.doc.addElement(.component(g), material: first?.props["material"] ?? "Concrete", name: name)
            if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["inPlace"] = "1" }
            ed.doc.remove(ids: Set(ids))
            ed.selection = []
            ed.print("In-place model \(name) (\(cat)) created: #\(id).")
        }
    }

    static var curtainSystem: CommandDef {
        CommandDef("CURTAINSYSTEM", aliases: ["CURTAINBYFACE", "CWBYFACE"], category: "Architecture", summary: "Curtain system by face: curtain walls on every vertical face of mass solids (grid spacing and mullion size).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select mass solids")
            guard !ids.isEmpty else { return }
            let gu = try await ed.getPositive("Specify vertical grid spacing", defaultValue: ed.variableDouble("CWGRIDU", 1500))
            let gv = try await ed.getPositive("Specify horizontal grid spacing", defaultValue: ed.variableDouble("CWGRIDV", 1500))
            let ms = try await ed.getPositive("Specify mullion size", defaultValue: 60)
            let del = try await ed.getYesNo("Delete the mass?", defaultValue: false)
            let elev = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            var n = 0
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                for g in CurtainSystems.walls(on: s, levelElevation: elev, gridU: gu, gridV: gv, mullion: ms) {
                    let e = ed.doc.addElement(.curtainWall(g), material: "Glass")
                    if let i = ed.doc.elementIndex(e) { ed.doc.elements[i].props["curtainSystemOf"] = "\(id)" }
                    n += 1
                }
            }
            if del { ed.doc.remove(ids: Set(ids)) }
            ed.doc.setVariable("CWGRIDU", fmt(gu)); ed.doc.setVariable("CWGRIDV", fmt(gv))
            ed.selection = []
            ed.print("\(n) curtain wall(s) created on vertical faces.")
        }
    }

    static var gradedRegion: CommandDef {
        CommandDef("GRADEDREGION", aliases: ["GRADE", "GRADING", "CUTFILL"], category: "Site", summary: "Graded region: copies a toposurface, levels a pad to an elevation with daylighting side slopes, and reports cut and fill volumes (the existing surface is kept on a hidden layer).") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select existing toposurface", filter: { ed.doc.entity($0)?.props["topo"] == "1" }),
                  let topo = ModelingCommands.solidOf(ed.doc, pk.id), let src = ed.doc.entity(pk.id) else { return }
            let a = try await ed.getPoint("Specify first point of the graded area", keywords: ["Select"])
            var boundary: [Vec2]? = nil
            switch a {
            case .point(let p): boundary = try await ArchitectureCommands.polygonInput(ed, first: p)
            case .keyword: boundary = try await ArchitectureCommands.selectBoundary(ed)
            default: return
            }
            guard let b = boundary, b.count >= 3 else { throw CommandError.invalid("The graded area needs a closed boundary.") }
            guard let z = try await ed.getDistance("Specify pad elevation", defaultValue: 0).value else { return }
            let slope = try await ed.getReal("Side slope, horizontal per vertical (0 = vertical)", defaultValue: ed.variableDouble("GRADESLOPE", 2)).value ?? 2
            guard slope >= 0 else { throw CommandError.invalid("The slope must be zero or positive.") }
            ed.doc.setVariable("GRADESLOPE", fmt(slope))
            let pts = Grading.surfacePoints(topo)
            let newPts = Grading.graded(points: pts, boundary: b, pad: z, slope: slope)
            let box = ModelingCommands.bounds(topo)
            guard let s = Terrain.solid(newPts, baseZ: min(box.min.z, z - 1)) else { throw CommandError.invalid("Grading failed.") }
            let cf = Grading.cutFill(existing: pts, proposed: newPts)
            let k = pow(ed.doc.units.mm, 3) / 1e9
            var e = src; e.id = 0; e.geometry = .solid(s)
            e.props["gradedFrom"] = "\(pk.id)"; e.props["cut"] = fmt(cf.cut * k, 3); e.props["fill"] = fmt(cf.fill * k, 3)
            let nid = ed.doc.add(e)
            let hidden = ModelingCommands.topoLayer + "-EXIST"
            if ed.doc.layer(named: hidden) == nil { var l = Layer(name: hidden, color: RGBA(0.5, 0.6, 0.45)); l.visible = false; l.description = "Existing topography (graded)"; ed.doc.layers.append(l) }
            if let i = ed.doc.entityIndex(pk.id) { ed.doc.entities[i].layer = hidden; ed.doc.entities[i].props["gradedBy"] = "\(nid)" }
            ed.print("Graded region #\(nid): cut \(fmt(cf.cut * k, 2)) m³, fill \(fmt(cf.fill * k, 2)) m³, net \(fmt((cf.fill - cf.cut) * k, 2)) m³.")
        }
    }

    @MainActor static func pickPanel(_ ed: Editor, _ msg: String) async throws -> EntityID? {
        guard case .pick(let pk) = try await ed.pickObject(msg, filter: { ed.doc.element($0).map(Circuits.isPanel) ?? false }) else { return nil }
        return pk.id
    }

    static var circuit: CommandDef {
        CommandDef("CIRCUIT", aliases: ["CIRCUITS", "ELCIRCUIT"], category: "MEP", summary: "Electrical circuits: Create (devices on a panel circuit with description and breaker), Remove devices, Show wiring home runs, List circuits.") { ed in
            let k = try await ed.getKeyword("Circuit option [Create/Remove/Show/List]", ["Create", "Remove", "Show", "List"], defaultValue: "Create") ?? "Create"
            switch k {
            case "Remove":
                let ids = try await ArchitectureCommands.elements(ed, "Select devices to disconnect", { _ in true })
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["circuitPanel"] = nil; ed.doc.elements[i].props["circuitNo"] = nil } }
                ed.selection = []
                ed.print("\(ids.count) device(s) disconnected.")
            case "Show", "List":
                guard let p = try await pickPanel(ed, "Select the panel") else { return }
                let cs = Circuits.circuits(ed.doc, panel: p)
                if k == "List" {
                    for c in cs { ed.print("\(c.number)  \(c.description)  \(c.devices.count) device(s)  \(fmt(c.load, 0)) VA  \(fmt(c.breaker, 0)) A  \(c.phase)") }
                    if cs.isEmpty { ed.print("No circuits on that panel.") }
                    return
                }
                let layer = "E-WIRE"
                if ed.doc.layer(named: layer) == nil { ed.doc.layers.append(Layer(name: layer, color: RunFamilies.systemColor("POWER") ?? RGBA(1, 0.6, 0.1), linetype: "Continuous", lineweight: 0.18, description: "Circuit wiring")) }
                ed.doc.entities.removeAll { $0.props["circuitWire"]?.hasPrefix("\(p):") ?? false }
                for c in cs {
                    let w = Circuits.wiring(ed.doc, c)
                    guard w.count >= 2 else { continue }
                    var e = Entity(layer: layer, geometry: .polyline(PolylineGeom(points: w)))
                    e.props["circuitWire"] = "\(p):\(c.number)"; e.props["system"] = "POWER"
                    ed.doc.add(e)
                }
                ed.print("Wiring drawn for \(cs.count) circuit(s).")
            default:
                let ids = try await ArchitectureCommands.elements(ed, "Select devices (outlets, lights, equipment)", { _ in true }).filter { ed.doc.element($0).map(Circuits.isDevice) ?? false }
                guard !ids.isEmpty else { throw CommandError.invalid("Select electrical devices.") }
                ed.selection = []
                guard let p = try await pickPanel(ed, "Select the panel") else { throw CommandError.invalid("Place an electrical panel (COMPONENT Panel) first.") }
                let n = try await ed.getInteger("Circuit number", defaultValue: Circuits.nextNumber(ed.doc, panel: p)) ?? 1
                guard n >= 1 else { throw CommandError.invalid("Circuit numbers start at 1.") }
                let desc = try await ed.getString("Description (Enter = device names)", defaultValue: "") ?? ""
                let br = try await ed.getPositive("Breaker rating (A)", defaultValue: 16)
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["circuitPanel"] = "\(p)"; ed.doc.elements[i].props["circuitNo"] = "\(n)"; ed.doc.elements[i].props["system"] = "POWER" } }
                if let i = ed.doc.elementIndex(p) { ed.doc.elements[i].props["circuit.\(n)"] = desc + "|" + fmt(br, 0) }
                let c = Circuits.circuits(ed.doc, panel: p).first { $0.number == n }
                ed.print("Circuit \(n) on \(ed.doc.element(p).map(Circuits.panelName) ?? "panel"): \(c?.devices.count ?? 0) device(s), \(fmt(c?.load ?? 0, 0)) VA.")
                if let c = c, c.load > c.breaker * 230 * 0.8 { ed.print("Warning: the load exceeds 80% of the breaker rating at 230 V.") }
            }
        }
    }

    static var panelSchedule: CommandDef {
        CommandDef("PANELSCHEDULE", aliases: ["PANELSCHED"], category: "MEP", summary: "Panel schedule of an electrical panel (circuits, loads, breakers, phase balance): List, Place as a table or Export CSV.") { ed in
            guard let p = try await pickPanel(ed, "Select the panel") else { return }
            let rows = Circuits.schedule(ed.doc, panel: p)
            let k = try await ed.getKeyword("Output [List/Place/Export]", ["List", "Place", "Export"], defaultValue: "List") ?? "List"
            switch k {
            case "Place":
                let at = try await ed.requirePoint("Specify insertion point (top left)")
                let u = 1 / ed.doc.units.mm, th = ed.variableDouble("TEXTSIZE", 200 * u)
                let widths = (0..<rows[0].count).map { c in Double(max(6, rows.map { $0[c].count }.max() ?? 6)) * th * 0.75 + th }
                let title = "PANEL " + (ed.doc.element(p).map(Circuits.panelName) ?? "")
                let id = ed.addEntity(.table(TableGeom(origin: at, columnWidths: widths, rowHeight: th * 2, cells: [[title] + Array(repeating: "", count: widths.count - 1)] + rows, textHeight: th)))
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["schedule"] = "panel:\(p)" }
            case "Export":
                guard let path = try await ed.getString("CSV file path") else { return }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                do { try CSVText.make(rows).write(to: url, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(path).") }
                ed.print("Panel schedule written to \(url.path).")
            default:
                for r in rows { ed.print(r.joined(separator: " | ")) }
            }
        }
    }

    static var roomDataSheet: CommandDef {
        CommandDef("ROOMDATASHEET", aliases: ["ROOMDATA", "RDS"], category: "Documentation", summary: "Room data sheets: Show per-room reports, Export (CSV/HTML/text), Import an edited CSV back into the rooms, or Set one field.") { ed in
            let k = try await ed.getKeyword("Room data sheets [Show/Export/Import/Set]", ["Show", "Export", "Import", "Set"], defaultValue: "Show") ?? "Show"
            switch k {
            case "Export":
                guard let path = try await ed.getString("File path (.csv, .html or .txt)") else { return }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let ids = RoomDataSheets.rooms(ed.doc)
                guard !ids.isEmpty else { throw CommandError.invalid("The model has no rooms.") }
                let ext = url.pathExtension.lowercased()
                let text = ext == "csv" ? RoomDataSheets.csv(ed.doc, rooms: ids) : (ext == "html" || ext == "htm" ? RoomDataSheets.html(ed.doc, rooms: ids) : RoomDataSheets.text(ed.doc, rooms: ids))
                do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(path).") }
                ed.print("\(ids.count) room data sheet(s) written to \(url.path).")
            case "Import":
                guard let path = try await ed.getString("Edited CSV file path") else { return }
                guard let text = try? String(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), encoding: .utf8) else { throw CommandError.invalid("Cannot read \(path).") }
                let r = RoomDataSheets.apply(csv: text, doc: &ed.doc)
                for e in r.errors { ed.print(e) }
                ed.print("\(r.changed) room(s) updated.")
            case "Set":
                let ids = try await ArchitectureCommands.elements(ed, "Select rooms", BIMExtCommands.isSpace)
                guard !ids.isEmpty else { return }
                let f = (try await ed.getWord("Field (\(RoomDataSheets.editable.joined(separator: ", ")))") ?? "").replacingOccurrences(of: " ", with: "")
                guard let field = RoomDataSheets.editable.first(where: { $0.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(f) == .orderedSame }) else {
                    throw CommandError.invalid("Unknown field \(f).")
                }
                let v = try await ed.getString("Value", defaultValue: "") ?? ""
                var n = 0
                for id in ids where RoomDataSheets.set(field, v, room: id, doc: &ed.doc) { n += 1 }
                ed.selection = []
                ed.print("\(field) set on \(n) room(s).")
            default:
                var ids = try await ArchitectureCommands.elements(ed, "Select rooms (Enter = all)", BIMExtCommands.isSpace)
                if ids.isEmpty { ids = RoomDataSheets.rooms(ed.doc) }
                ed.print(RoomDataSheets.text(ed.doc, rooms: ids))
                ed.selection = []
            }
        }
    }
}
