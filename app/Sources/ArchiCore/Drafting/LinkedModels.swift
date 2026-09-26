// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// A linked BIM model (BLK-035, RVTLINK): another .archi or IFC model shown in this one, positioned origin-to-origin,
/// by shared coordinates or at a picked point, and reloaded from its file.
public struct ModelLink: Codable, Hashable {
    public enum Placement: String, Codable, CaseIterable { case origin, shared, point }
    public var name: String
    /// Path as attached (absolute, or relative to the host model's folder).
    public var path: String
    public var placement: Placement
    /// Extra offset (point placement: insertion point of the link's origin) and rotation in radians.
    public var offset: Vec2
    public var rotation: Double
    public var zOffset: Double
    public var loaded: Bool
    public var loadedModified: Double?
    public init(name: String, path: String, placement: Placement = .origin, offset: Vec2 = .zero, rotation: Double = 0, zOffset: Double = 0,
                loaded: Bool = true, loadedModified: Double? = nil) {
        self.name = name; self.path = path; self.placement = placement; self.offset = offset; self.rotation = rotation; self.zOffset = zOffset
        self.loaded = loaded; self.loadedModified = loadedModified
    }
    private enum K: String, CodingKey { case name, path, placement, offset, rotation, zOffset, loaded, loadedModified }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name); path = try c.decode(String.self, forKey: .path)
        placement = try c.decodeIfPresent(Placement.self, forKey: .placement) ?? .origin
        offset = try c.decodeIfPresent(Vec2.self, forKey: .offset) ?? .zero
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        zOffset = try c.decodeIfPresent(Double.self, forKey: .zOffset) ?? 0
        loaded = try c.decodeIfPresent(Bool.self, forKey: .loaded) ?? true
        loadedModified = try c.decodeIfPresent(Double.self, forKey: .loadedModified)
    }
}

/// Placement of a linked model in host coordinates: plan transform (units scale, rotation, translation) and Z shift.
public struct LinkPlacement: Equatable {
    public var transform: Transform2D
    public var dz: Double
    /// Host units per link unit.
    public var scale: Double
    public func apply(_ p: Vec3) -> Vec3 { let q = transform.apply(Vec2(p.x, p.y)); return Vec3(q.x, q.y, p.z * scale + dz) }
    public func elevation(_ z: Double) -> Double { z * scale + dz }
}

/// Linked BIM models. The registry is the document variable MODELLINKS; the displayed content is regenerated from the
/// linked file as locked, non-editable objects on layers "LINK|<layer>":
/// - plan linework of every link level (walls with cut fills, doors, windows, stairs, rooms, grids …) as polylines,
///   solid fills and text tagged with the host level of the same elevation, so each host plan shows the matching link
///   level;
/// - one 3D mesh per link element for the 3D view, sections, elevations and renders (hidden in plan views).
/// All generated objects carry the prop `linkOf` = link name. Reload regenerates them; Unload removes them; Detach
/// removes the link.
public enum LinkedModels {
    public static let variable = "MODELLINKS"
    public static let linkProp = "linkOf"
    public static let sourceProp = "linkSource"
    /// Level prop given to link meshes: no plan view shows them.
    public static let meshLevel = -999_999

    public enum LinkError: Error, LocalizedError, Equatable {
        case notFound(String), unreadable(String), duplicate(String), circular(String), empty(String)
        public var errorDescription: String? {
            switch self {
            case .notFound(let n): return "Link \(n) not found."
            case .unreadable(let p): return "Cannot read the model \(p)."
            case .duplicate(let n): return "A link named \(n) already exists."
            case .circular(let n): return "Link \(n) would reference itself."
            case .empty(let p): return "The model \(p) has no building elements."
            }
        }
    }

    public static func all(_ doc: ArchiDocument) -> [ModelLink] { VarJSON.load(doc, variable, as: [ModelLink].self) ?? [] }
    public static func store(_ l: [ModelLink], _ doc: inout ArchiDocument) { VarJSON.save(l.sorted { $0.name < $1.name }, &doc, variable, empty: l.isEmpty) }
    public static func named(_ n: String, _ doc: ArchiDocument) -> ModelLink? { all(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }

    /// Reads a linked model (.archi, .ifc, or any format the importer knows).
    public static func read(_ url: URL) throws -> ArchiDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LinkError.unreadable(url.path) }
        do { return try FileImport.load(url).0 } catch { throw LinkError.unreadable(url.path) }
    }

    /// Where a link sits in the host.
    public static func placement(_ link: ModelLink, source src: ArchiDocument, host: ArchiDocument) -> LinkPlacement {
        let k = src.units.mm / host.units.mm
        var t = Transform2D.scale(k, k)
        var dz = link.zOffset
        if link.placement == .shared {
            // Link point → shared (survey) coordinates of the link → host point.
            let s = SharedCoordinates.current(src), h = SharedCoordinates.current(host)
            let map = { (p: Vec2) -> Vec2 in h.fromShared(s.toShared(p) * k) }
            let o = map(.zero), x = map(Vec2(1, 0))
            t = Transform2D.translation(o) * Transform2D.rotation((x - o).angle) * Transform2D.scale(k, k)
            dz += s.elevation * k - h.elevation
        }
        t = Transform2D.translation(link.offset) * Transform2D.rotation(link.rotation) * t
        return LinkPlacement(transform: t, dz: dz, scale: k)
    }

    /// Host level whose elevation is nearest to a host elevation.
    public static func hostLevel(elevation z: Double, host: ArchiDocument) -> Int? {
        host.levels.min { abs($0.elevation - z) < abs($1.elevation - z) }?.id
    }

    static func layerName(_ link: String, _ layer: String) -> String { link + Xrefs.separator + layer }

    /// Generated objects and layers for a link.
    public static func content(_ link: ModelLink, source full: ArchiDocument, host: ArchiDocument) -> (entities: [Entity], layers: [Layer]) {
        var src = full
        src.entities = []
        let place = placement(link, source: src, host: host)
        let t = place.transform
        var layers: [String: Layer] = [:]
        func layer(for srcLayer: String) -> String {
            let n = layerName(link.name, srcLayer)
            if layers[n] == nil {
                var l = src.layer(named: srcLayer) ?? Layer(name: srcLayer)
                l.name = n; l.locked = true; l.frozen = false; l.visible = true
                layers[n] = l
            }
            return n
        }
        let elementLayer = Dictionary(src.elements.map { ($0.id, $0.layer) }, uniquingKeysWith: { a, _ in a })
        func rgb(_ c: RGBA) -> ColorRef { .rgb(UInt8(max(0, min(255, (c.r * 255).rounded()))), UInt8(max(0, min(255, (c.g * 255).rounded()))), UInt8(max(0, min(255, (c.b * 255).rounded())))) }
        var out: [Entity] = []
        func base(_ g: Geometry, id: EntityID?, level: Int, color: ColorRef = .byLayer, lw: Double? = nil) -> Entity {
            let lay = layer(for: id.flatMap { elementLayer[$0] } ?? "0")
            var props = [linkProp: link.name, "level": "\(level)"]
            if let id = id { props[sourceProp] = "\(id)" }
            return Entity(layer: lay, color: color, lineweight: lw, geometry: g, props: props)
        }
        // Plan linework per link level.
        for lv in src.levels {
            guard let hl = hostLevel(elevation: place.elevation(lv.elevation), host: host) else { continue }
            var opt = DrawOptions(level: lv.id)
            opt.showAnnotations = true
            for entry in DrawListBuilder.entries(doc: src, options: opt) {
                for it in entry.items {
                    switch it {
                    case .stroke(let pts, let closed, let st):
                        guard pts.count >= 2 else { continue }
                        out.append(base(.polyline(PolylineGeom(points: pts.map(t.apply), closed: closed)), id: entry.id, level: hl, color: rgb(st.color), lw: st.lineweight))
                    case .fill(let loops, let c):
                        let ls = loops.filter { $0.count >= 3 }.map { $0.map { PolyVertex(t.apply($0)) } }
                        guard !ls.isEmpty else { continue }
                        out.append(base(.hatch(HatchGeom(loops: ls, pattern: "SOLID")), id: entry.id, level: hl, color: rgb(c)))
                    case .text(let tx, _, let c):
                        var g = tx
                        g.position = t.apply(tx.position); g.height = tx.height * place.scale; g.width = tx.width * place.scale
                        g.rotation = t.applyVector(Vec2.polar(1, tx.rotation)).angle
                        out.append(base(.text(g), id: entry.id, level: hl, color: rgb(c)))
                    case .image: continue
                    }
                }
            }
        }
        // 3D meshes, one per element and material.
        for g in MeshBuilder.build(doc: src) where !g.mesh.isEmpty {
            let verts = g.mesh.positions.map(place.apply)
            let tris = g.mesh.indices.map { Int($0) }
            var e = base(.solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: verts, meshTriangles: tris)), id: g.id, level: meshLevel)
            e.props["material"] = g.material
            out.append(e)
        }
        return (out, Array(layers.values).sorted { $0.name < $1.name })
    }

    /// Removes the generated objects of a link.
    @discardableResult
    public static func clear(_ doc: inout ArchiDocument, name: String) -> Int {
        let n = doc.entities.count
        doc.entities.removeAll { $0.props[linkProp]?.caseInsensitiveCompare(name) == .orderedSame }
        return n - doc.entities.count
    }

    /// Replaces the generated objects of a link with fresh content from its source model.
    static func load(_ link: ModelLink, source src: ArchiDocument, into doc: inout ArchiDocument) {
        clear(&doc, name: link.name)
        let c = content(link, source: src, host: doc)
        for l in c.layers {
            if let i = doc.layers.firstIndex(where: { $0.name == l.name }) { var k = l; k.visible = doc.layers[i].visible; k.frozen = doc.layers[i].frozen; doc.layers[i] = k }
            else { doc.layers.append(l) }
        }
        for m in src.materials where doc.material(m.name) == nil { doc.materials.append(m) }
        for e in c.entities { doc.add(e) }
    }

    static func modified(_ url: URL) -> Double? { Xrefs.modified(url) }

    /// Links a model. Returns the link name.
    @discardableResult
    public static func attach(_ doc: inout ArchiDocument, path: String, name: String? = nil, placement: ModelLink.Placement = .origin,
                              offset: Vec2 = .zero, rotation: Double = 0, base: URL? = nil, host: URL? = nil) throws -> String {
        let url = Xrefs.resolve(path, base: base)
        if let h = host, h.standardizedFileURL.path == url.standardizedFileURL.path { throw LinkError.circular(url.lastPathComponent) }
        let src = try read(url)
        guard !src.elements.isEmpty else { throw LinkError.empty(url.lastPathComponent) }
        let n = (name?.isEmpty == false ? name! : url.deletingPathExtension().lastPathComponent).replacingOccurrences(of: Xrefs.separator, with: "_")
        guard named(n, doc) == nil else { throw LinkError.duplicate(n) }
        let link = ModelLink(name: n, path: path, placement: placement, offset: offset, rotation: rotation, loadedModified: modified(url))
        var list = all(doc); list.append(link); store(list, &doc)
        load(link, source: src, into: &doc)
        return n
    }

    /// Reloads links (all when `names` is nil). Returns the reloaded names.
    @discardableResult
    public static func reload(_ doc: inout ArchiDocument, names: [String]? = nil, base: URL? = nil) throws -> [String] {
        var list = all(doc), done: [String] = []
        for i in list.indices where names.map({ ns in ns.contains { $0.caseInsensitiveCompare(list[i].name) == .orderedSame } }) ?? true {
            let url = Xrefs.resolve(list[i].path, base: base)
            let src = try read(url)
            list[i].loaded = true; list[i].loadedModified = modified(url)
            load(list[i], source: src, into: &doc)
            done.append(list[i].name)
        }
        store(list, &doc)
        return done
    }

    public static func unload(_ doc: inout ArchiDocument, name: String) throws {
        var list = all(doc)
        guard let i = list.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw LinkError.notFound(name) }
        clear(&doc, name: list[i].name)
        list[i].loaded = false
        store(list, &doc)
    }

    public static func detach(_ doc: inout ArchiDocument, name: String) throws {
        var list = all(doc)
        guard let i = list.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw LinkError.notFound(name) }
        let n = list[i].name
        clear(&doc, name: n)
        list.remove(at: i); store(list, &doc)
        let prefix = n + Xrefs.separator
        let used = Set(doc.entities.map(\.layer) + doc.elements.map(\.layer))
        doc.layers.removeAll { $0.name.hasPrefix(prefix) && !used.contains($0.name) }
        MonitorLinks.forget(&doc, link: n)
    }

    /// Moves / rotates a link (point placement) and regenerates it.
    public static func reposition(_ doc: inout ArchiDocument, name: String, offset: Vec2, rotation: Double, base: URL? = nil) throws {
        var list = all(doc)
        guard let i = list.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw LinkError.notFound(name) }
        list[i].offset = offset; list[i].rotation = rotation
        store(list, &doc)
        if list[i].loaded { try reload(&doc, names: [list[i].name], base: base) }
    }

    /// Links whose file changed since they were loaded.
    public static func changed(_ doc: ArchiDocument, base: URL?) -> [String] {
        all(doc).filter { l in
            guard l.loaded, let m = modified(Xrefs.resolve(l.path, base: base)) else { return false }
            return l.loadedModified.map { abs($0 - m) > 1e-3 } ?? true
        }.map(\.name)
    }
    public static func missing(_ doc: ArchiDocument, base: URL?) -> [String] {
        all(doc).filter { !FileManager.default.fileExists(atPath: Xrefs.resolve($0.path, base: base).path) }.map(\.name)
    }
    /// Number of generated objects of a link.
    public static func objectCount(_ doc: ArchiDocument, name: String) -> Int {
        doc.entities.filter { $0.props[linkProp]?.caseInsensitiveCompare(name) == .orderedSame }.count
    }
}

// MARK: - Copy / monitor

/// Copy/monitor (BLK-036): levels and grids copied from a linked model stay associated with their source; after the
/// link is reloaded, `check` lists what moved or was renamed or deleted in the link and `update` applies the changes.
/// Pairs are stored in the document variable LINKMONITOR.
public enum MonitorLinks {
    public static let variable = "LINKMONITOR"

    public struct Pair: Codable, Hashable {
        public enum Kind: String, Codable { case level, grid }
        public var link: String
        public var kind: Kind
        /// Level id / element id in the linked model.
        public var source: Int
        /// Level id / element id in the host.
        public var target: Int
    }

    public struct Difference: Equatable {
        public var pair: Pair
        public var message: String
    }

    public static func pairs(_ doc: ArchiDocument) -> [Pair] { VarJSON.load(doc, variable, as: [Pair].self) ?? [] }
    static func store(_ p: [Pair], _ doc: inout ArchiDocument) { VarJSON.save(p, &doc, variable, empty: p.isEmpty) }
    static func forget(_ doc: inout ArchiDocument, link: String) {
        store(pairs(doc).filter { $0.link.caseInsensitiveCompare(link) != .orderedSame }, &doc)
    }

    /// Copies (or, when a host level of that elevation / a host grid of that label and position exists, monitors)
    /// the levels and/or grids of a linked model. Returns (copied, monitored).
    @discardableResult
    public static func copy(_ doc: inout ArchiDocument, link: ModelLink, source src: ArchiDocument, levels: Bool, grids: Bool, tolerance: Double = 1) -> (copied: Int, monitored: Int) {
        let place = LinkedModels.placement(link, source: src, host: doc)
        var ps = pairs(doc)
        var copied = 0, monitored = 0
        func has(_ k: Pair.Kind, _ s: Int) -> Bool { ps.contains { $0.link == link.name && $0.kind == k && $0.source == s } }
        if levels {
            for lv in src.levels where !has(.level, lv.id) {
                let z = place.elevation(lv.elevation)
                if let h = doc.levels.first(where: { hl in abs(hl.elevation - z) <= tolerance && !ps.contains(where: { p in p.kind == .level && p.target == hl.id }) }) {
                    ps.append(Pair(link: link.name, kind: .level, source: lv.id, target: h.id)); monitored += 1
                } else {
                    let id = (doc.levels.map(\.id).max() ?? -1) + 1
                    var n = Level(id: id, name: lv.name, elevation: z, height: lv.height * place.scale)
                    if doc.levels.contains(where: { $0.name == n.name }) { n.name = lv.name + " (" + link.name + ")" }
                    doc.levels.append(n); doc.levels.sort { $0.elevation < $1.elevation }
                    ps.append(Pair(link: link.name, kind: .level, source: lv.id, target: id)); copied += 1
                }
            }
        }
        if grids {
            let levelMap = Dictionary(ps.filter { $0.link == link.name && $0.kind == .level }.map { ($0.source, $0.target) }, uniquingKeysWith: { a, _ in a })
            for el in src.elements where !has(.grid, el.id) {
                guard case .gridLine = el.geometry, case .gridLine(let g) = CommandHelpers.transform(el.geometry, place.transform) else { continue }
                if let h = doc.elements.first(where: { e in
                    guard case .gridLine(let hg) = e.geometry else { return false }
                    return hg.label == g.label && hg.start.distance(to: g.start) <= tolerance && hg.end.distance(to: g.end) <= tolerance
                }) {
                    ps.append(Pair(link: link.name, kind: .grid, source: el.id, target: h.id)); monitored += 1
                } else {
                    let lvl = levelMap[el.level] ?? LinkedModels.hostLevel(elevation: place.elevation(src.level(el.level)?.elevation ?? 0), host: doc) ?? doc.currentLevel
                    let id = doc.addElement(.gridLine(g), level: lvl, layer: el.layer, name: el.name)
                    ps.append(Pair(link: link.name, kind: .grid, source: el.id, target: id)); copied += 1
                }
            }
        }
        store(ps, &doc)
        return (copied, monitored)
    }

    /// Differences between monitored host items and their link sources.
    public static func check(_ doc: ArchiDocument, link: ModelLink, source src: ArchiDocument, tolerance: Double = 1e-3) -> [Difference] {
        let place = LinkedModels.placement(link, source: src, host: doc)
        var out: [Difference] = []
        for p in pairs(doc) where p.link.caseInsensitiveCompare(link.name) == .orderedSame {
            switch p.kind {
            case .level:
                guard let h = doc.level(p.target) else { out.append(Difference(pair: p, message: "Host level \(p.target) was deleted.")); continue }
                guard let s = src.level(p.source) else { out.append(Difference(pair: p, message: "Level \(h.name) was deleted in \(link.name).")); continue }
                let z = place.elevation(s.elevation)
                if abs(z - h.elevation) > tolerance { out.append(Difference(pair: p, message: "Level \(h.name): elevation \(fmt(h.elevation)) → \(fmt(z)) in \(link.name).")) }
                if s.name != h.name && !h.name.hasPrefix(s.name + " (") { out.append(Difference(pair: p, message: "Level \(h.name) renamed to \(s.name) in \(link.name).")) }
            case .grid:
                guard let he = doc.element(p.target), case .gridLine(let hg) = he.geometry else { out.append(Difference(pair: p, message: "Host grid \(p.target) was deleted.")); continue }
                guard let se = src.element(p.source), case .gridLine(let sg) = CommandHelpers.transform(se.geometry, place.transform) else {
                    out.append(Difference(pair: p, message: "Grid \(hg.label) was deleted in \(link.name).")); continue
                }
                if hg.start.distance(to: sg.start) > tolerance || hg.end.distance(to: sg.end) > tolerance || abs(hg.bulge - sg.bulge) > 1e-9 {
                    out.append(Difference(pair: p, message: "Grid \(hg.label) moved in \(link.name)."))
                }
                if hg.label != sg.label { out.append(Difference(pair: p, message: "Grid \(hg.label) renamed to \(sg.label) in \(link.name).")) }
            }
        }
        return out
    }

    /// Applies the link's current levels and grids to the monitored host items. Returns the number of items changed.
    @discardableResult
    public static func update(_ doc: inout ArchiDocument, link: ModelLink, source src: ArchiDocument) -> Int {
        let place = LinkedModels.placement(link, source: src, host: doc)
        var n = 0
        for d in check(doc, link: link, source: src) {
            let p = d.pair
            switch p.kind {
            case .level:
                guard let i = doc.levels.firstIndex(where: { $0.id == p.target }), let s = src.level(p.source) else { continue }
                doc.levels[i].elevation = place.elevation(s.elevation)
                if !doc.levels[i].name.hasPrefix(s.name + " (") { doc.levels[i].name = s.name }
                n += 1
            case .grid:
                guard let i = doc.elementIndex(p.target), let se = src.element(p.source), case .gridLine(let sg) = CommandHelpers.transform(se.geometry, place.transform) else { continue }
                doc.elements[i].geometry = .gridLine(sg); n += 1
            }
        }
        doc.levels.sort { $0.elevation < $1.elevation }
        return n
    }

    /// Stops monitoring host items (they stay as ordinary levels / grids).
    public static func release(_ doc: inout ArchiDocument, link: String) { forget(&doc, link: link) }
}
