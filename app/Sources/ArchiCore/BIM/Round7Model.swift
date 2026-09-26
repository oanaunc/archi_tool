// Oanarina Archi Tool — GPL-3.0-or-later
// Model services for round 7: storey settings (BIM-003), project standards transfer (PAR-032), assemblies (BIM-124),
// wall loops (BIM-012), storefront presets (BIM-032), detail components / repeating details / batt insulation
// (DOC-037/038/039), material tags (DOC-032) and family parameter locks and EQ constraints (PAR-026).
import Foundation

// MARK: - BIM-003 storey settings

public enum StoreySettings {
    /// Elevation shown on level heads: project (default), "survey" (+ project base elevation) or "relative" (to the
    /// level named by LEVELELEVREF, default the lowest level).
    public static func displayElevation(_ l: Level, doc: ArchiDocument) -> Double {
        switch doc.variable("LEVELELEVBASE")?.lowercased() {
        case "survey", "absolute": return l.elevation + doc.info.elevation
        case "relative":
            let ref = doc.levels.first { $0.name.caseInsensitiveCompare(doc.variable("LEVELELEVREF") ?? "") == .orderedSame }?.elevation
                ?? doc.levels.map(\.elevation).min() ?? 0
            return l.elevation - ref
        default: return l.elevation
        }
    }

    /// Sets a storey height; with `propagate`, every level above moves by the change (their elements move with them).
    @discardableResult
    public static func setHeight(_ id: Int, _ h: Double, propagate: Bool, doc: inout ArchiDocument) -> Bool {
        guard h > 0, let i = doc.levels.firstIndex(where: { $0.id == id }) else { return false }
        let old = doc.levels[i].height, e = doc.levels[i].elevation
        doc.levels[i].height = h
        if propagate {
            let delta = h - old
            for k in doc.levels.indices where doc.levels[k].elevation > e + 1e-9 { doc.levels[k].elevation += delta }
        }
        return true
    }

    /// Inserts a storey above (or below) a level; the levels above the insertion point move up by its height.
    @discardableResult
    public static func insert(relativeTo id: Int, above: Bool, height h: Double, name: String?, doc: inout ArchiDocument) -> Int? {
        guard h > 0, let ref = doc.level(id) else { return nil }
        let elev = above ? ref.elevation + ref.height : ref.elevation
        for k in doc.levels.indices where doc.levels[k].elevation >= elev - 1e-9 && !(doc.levels[k].id == id && above) { doc.levels[k].elevation += h }
        let nid = (doc.levels.map(\.id).max() ?? 0) + 1
        var n = name ?? "Level \(nid)"
        var j = 2
        while doc.levels.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { n = "\(name ?? "Level \(nid)") (\(j))"; j += 1 }
        doc.levels.append(Level(id: nid, name: n, elevation: elev, height: h))
        doc.levels.sort { $0.elevation < $1.elevation }
        return nid
    }

    /// Deletes a storey and its elements; the levels above move down by its height.
    @discardableResult
    public static func delete(_ id: Int, doc: inout ArchiDocument) -> Bool {
        guard doc.levels.count > 1, let l = doc.level(id) else { return false }
        doc.remove(ids: Set(doc.elements.filter { $0.level == id }.map(\.id)))
        doc.levels.removeAll { $0.id == id }
        for k in doc.levels.indices where doc.levels[k].elevation > l.elevation + 1e-9 { doc.levels[k].elevation -= l.height }
        if doc.currentLevel == id { doc.currentLevel = doc.levels.first?.id ?? 0 }
        return true
    }
}

// MARK: - PAR-032 transfer project standards

public enum ProjectStandards {
    public static let categories = ["materials", "wallTypes", "slabTypes", "openingTypes", "stairTypes", "railingTypes", "layers", "linetypes",
                                    "textStyles", "dimStyles", "viewTemplates", "families", "globalParameters", "projectParameters",
                                    "psetTemplates", "schedules", "keynotes", "phases", "units"]

    /// Category name from user input (any case, singular or plural); nil when unknown.
    public static func category(_ s: String) -> String? {
        let k = s.lowercased()
        return categories.first { $0.lowercased() == k || $0.lowercased() == k + "s" || $0.lowercased().hasPrefix(k) }
    }

    /// Copies the chosen categories from `src` into `doc`. Existing items with the same name are replaced only with
    /// `overwrite`. Materials used by copied types come along. Returns the number of items copied per category.
    @discardableResult
    public static func transfer(from src: ArchiDocument, into doc: inout ArchiDocument, categories cats: Set<String>, overwrite: Bool) -> [String: Int] {
        var counts: [String: Int] = [:]
        func merge<T>(_ items: [T], _ into: inout [T], key: (T) -> String, _ cat: String) {
            for it in items {
                if let i = into.firstIndex(where: { key($0).caseInsensitiveCompare(key(it)) == .orderedSame }) {
                    guard overwrite else { continue }
                    into[i] = it
                } else { into.append(it) }
                counts[cat, default: 0] += 1
            }
        }
        var neededMaterials = Set<String>()
        if cats.contains("wallTypes") { merge(src.wallTypes, &doc.wallTypes, key: \.name, "wallTypes"); src.wallTypes.forEach { $0.plies.forEach { neededMaterials.insert($0.material) } } }
        if cats.contains("slabTypes") { merge(src.slabTypes, &doc.slabTypes, key: \.name, "slabTypes"); src.slabTypes.forEach { $0.plies.forEach { neededMaterials.insert($0.material) } } }
        if cats.contains("openingTypes") { merge(src.openingTypes, &doc.openingTypes, key: \.name, "openingTypes"); src.openingTypes.compactMap(\.material).forEach { neededMaterials.insert($0) } }
        if cats.contains("stairTypes") { merge(src.stairTypes, &doc.stairTypes, key: \.name, "stairTypes") }
        if cats.contains("railingTypes") { merge(src.railingTypes, &doc.railingTypes, key: \.name, "railingTypes") }
        if cats.contains("materials") { merge(src.materials, &doc.materials, key: \.name, "materials") }
        else {
            let extra = src.materials.filter { m in neededMaterials.contains { $0.caseInsensitiveCompare(m.name) == .orderedSame } && doc.material(m.name) == nil }
            if !extra.isEmpty { doc.materials += extra; counts["materials", default: 0] += extra.count }
        }
        if cats.contains("layers") { merge(src.layers, &doc.layers, key: \.name, "layers") }
        if cats.contains("linetypes") { merge(src.linetypes, &doc.linetypes, key: \.name, "linetypes") }
        if cats.contains("textStyles") { merge(src.textStyles, &doc.textStyles, key: \.name, "textStyles") }
        if cats.contains("dimStyles") { merge(src.dimStyles, &doc.dimStyles, key: \.name, "dimStyles") }
        if cats.contains("viewTemplates") { merge(src.viewTemplates, &doc.viewTemplates, key: \.name, "viewTemplates") }
        if cats.contains("families") { merge(src.families, &doc.families, key: \.name, "families") }
        if cats.contains("globalParameters") { merge(src.globalParameters, &doc.globalParameters, key: \.name, "globalParameters") }
        if cats.contains("projectParameters") { merge(src.projectParameters, &doc.projectParameters, key: \.name, "projectParameters") }
        if cats.contains("psetTemplates") { merge(src.psetTemplates, &doc.psetTemplates, key: \.name, "psetTemplates") }
        if cats.contains("schedules") { merge(src.schedules, &doc.schedules, key: \.name, "schedules") }
        if cats.contains("keynotes") {
            for (k, v) in src.keynotes where overwrite || doc.keynotes[k] == nil { doc.keynotes[k] = v; counts["keynotes", default: 0] += 1 }
        }
        if cats.contains("phases") {
            for p in src.phases where !doc.phases.contains(p) { doc.phases.append(p); counts["phases", default: 0] += 1 }
        }
        if cats.contains("units"), overwrite || doc.entities.isEmpty && doc.elements.isEmpty { doc.units = src.units; counts["units"] = 1 }
        return counts
    }
}

// MARK: - BIM-124 assemblies

public enum Assemblies {
    public static func names(_ doc: ArchiDocument) -> [String] {
        Array(Set(doc.elements.compactMap { $0.props["assembly"] })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    public static func members(_ name: String, doc: ArchiDocument) -> [BIMElement] {
        doc.elements.filter { $0.props["assembly"]?.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Groups elements into an assembly (an element belongs to at most one). Returns the number added.
    @discardableResult
    public static func create(_ name: String, ids: [EntityID], type: String? = nil, doc: inout ArchiDocument) -> Int {
        var n = 0
        for id in ids { if let i = doc.elementIndex(id), doc.elements[i].props["assembly"] != name { doc.elements[i].props["assembly"] = name; n += 1 } }
        if let t = type, !t.isEmpty { doc.setVariable("ASSEMBLYTYPE." + name, t) }
        return n
    }

    public static func disassemble(_ name: String, doc: inout ArchiDocument) -> Int {
        var n = 0
        for i in doc.elements.indices where doc.elements[i].props["assembly"]?.caseInsensitiveCompare(name) == .orderedSame { doc.elements[i].props["assembly"] = nil; n += 1 }
        doc.variables["ASSEMBLYTYPE." + name.uppercased()] = nil
        return n
    }

    /// Assembly views: a plan view and a 3D view showing only the members (ISOLATEASSEMBLY), cropped around them.
    @discardableResult
    public static func createViews(_ name: String, doc: inout ArchiDocument) -> [String] {
        let ms = members(name, doc: doc)
        guard !ms.isEmpty else { return [] }
        var box = BBox2.empty
        for el in ms { box.add(PlanRepresentation.bounds(el, doc: doc)) }
        let pad = max(box.width, box.height, 1) * 0.15
        let plan = "Assembly \(name) - Plan", iso = "Assembly \(name) - 3D"
        doc.views.removeAll { $0.name == plan || $0.name == iso }
        var pv = ProjectView(name: plan, kind: "plan", level: ms[0].level, settings: ["ISOLATEASSEMBLY": name], crop: box.expanded(by: pad).corners, cropActive: !box.isEmpty)
        pv.settings["VIEWANNOTATIONS"] = "1"
        doc.views.append(pv)
        doc.views.append(ProjectView(name: iso, kind: "3d", settings: ["ISOLATEASSEMBLY": name], axonometric: "SW"))
        return [plan, iso]
    }

    /// Whether an element is shown with the ISOLATEASSEMBLY view setting.
    public static func shown(_ el: BIMElement, doc: ArchiDocument) -> Bool {
        guard let a = doc.variable("ISOLATEASSEMBLY"), !a.isEmpty else { return true }
        if el.props["assembly"]?.caseInsensitiveCompare(a) == .orderedSame { return true }
        if case .opening(let o) = el.geometry, let h = doc.element(o.hostWall) { return h.props["assembly"]?.caseInsensitiveCompare(a) == .orderedSame }
        return false
    }
}

// MARK: - BIM-012 walls along closed loops

public enum WallLoops {
    /// Corners of a regular polygon (inscribed: vertices on the radius; circumscribed: edge midpoints on it).
    public static func regularPolygon(center c: Vec2, sides n: Int, radius r: Double, inscribed: Bool = true, rotation: Double = 0) -> [Vec2] {
        guard n >= 3, r > 0 else { return [] }
        let R = inscribed ? r : r / cos(.pi / Double(n))
        let a0 = rotation + (inscribed ? 0 : .pi / Double(n))
        return (0..<n).map { c + Vec2.polar(R, a0 + 2 * .pi * Double($0) / Double(n)) }
    }

    /// Creates a closed chain of joined walls along a loop (counter-clockwise); returns the wall ids.
    @discardableResult
    public static func create(_ loop0: [Vec2], template: WallGeom, level: Int? = nil, material: String? = nil, doc: inout ArchiDocument) -> [EntityID] {
        var loop = RG.dedupe(loop0, closed: true)
        guard loop.count >= 3, abs(GeometryOps.signedArea(loop)) > 1e-9 else { return [] }
        if GeometryOps.signedArea(loop) < 0 { loop.reverse() }
        var ids: [EntityID] = []
        for i in loop.indices {
            var w = template
            w.start = loop[i]; w.end = loop[(i + 1) % loop.count]; w.bulge = 0
            ids.append(doc.addElement(.wall(w), level: level, material: material))
        }
        for (k, id) in ids.enumerated() {
            guard let i = doc.elementIndex(id) else { continue }
            doc.elements[i].props["joinStart"] = "\(ids[(k - 1 + ids.count) % ids.count])"
            doc.elements[i].props["joinEnd"] = "\(ids[(k + 1) % ids.count])"
        }
        return ids
    }
}

// MARK: - BIM-032 storefront and partition presets

public enum Storefronts {
    /// Storefront curtain wall: bays of about `bay` width, a transom at `transom`, doors in the given bays (0-based;
    /// -1 = middle bay). Partition preset: slim mullions, no transom.
    public static func make(start: Vec2, end: Vec2, height: Double, bay: Double, transom: Double?, doorBays: [Int], doubleDoor: Bool, partition: Bool) -> CurtainWallGeom? {
        let len = start.distance(to: end)
        guard len > 1e-6, height > 1e-6, bay > 1e-6 else { return nil }
        let n = max(1, Int((len / bay).rounded()))
        let w = len / Double(n)
        let ms = partition ? 40.0 : 50.0
        var g = CurtainWallGeom(start: start, end: end, height: height, gridU: w, gridV: 0, mullionSize: ms,
                                uLines: (1..<n).map { Double($0) * w }, vLines: (transom.map { $0 > ms * 2 && $0 < height - ms * 2 } ?? false) ? [transom!] : [],
                                mullionProfile: partition ? "rect" : "capped", mullionDepth: partition ? 60 : 150)
        for b in doorBays {
            let i = b < 0 ? n / 2 : min(b, n - 1)
            g.panels["\(i),0"] = doubleDoor ? "doubledoor" : "door"
        }
        return g
    }
}

// MARK: - DOC-037/038/039 detail components, repeating details, batt insulation

public enum DetailComponents {
    /// Catalogue: name → (width, height, kind). Sizes in millimetres.
    public static let catalogue: [(name: String, w: Double, h: Double, kind: String)] = [
        ("Lumber 38x89", 38, 89, "lumber"), ("Lumber 38x140", 38, 140, "lumber"), ("Lumber 38x184", 38, 184, "lumber"),
        ("Lumber 38x235", 38, 235, "lumber"), ("Lumber 89x89", 89, 89, "lumber"), ("Stud 38x89", 89, 38, "lumber"),
        ("Brick 215x65", 215, 65, "brick"), ("Brick 102x65", 102, 65, "brick"), ("CMU 390x190", 390, 190, "cmu"), ("CMU 190x190", 190, 190, "cmu"),
        ("Plywood 12", 1200, 12, "sheet"), ("Plywood 18", 1200, 18, "sheet"), ("Gypsum 12.5", 1200, 12.5, "sheet"),
        ("Steel IPE100", 55, 100, "steel"), ("Steel IPE200", 100, 200, "steel"),
    ]

    public static func find(_ n: String) -> (name: String, w: Double, h: Double, kind: String)? {
        let k = n.lowercased().replacingOccurrences(of: " ", with: "")
        return catalogue.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == k }
            ?? catalogue.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(k) }
    }

    /// Block name for a component (created in the document on first use; drawing units from millimetres).
    @discardableResult
    public static func ensureBlock(_ name: String, doc: inout ArchiDocument) -> String? {
        guard let c = find(name) else { return nil }
        let bn = "DC-" + c.name.replacingOccurrences(of: " ", with: "-")
        if doc.blocks[bn] != nil { return bn }
        let u = 1 / doc.units.mm
        let w = c.w * u, h = c.h * u
        var ents: [Entity] = []
        func pl(_ p: [Vec2], closed: Bool = true) { ents.append(Entity(layer: "0", geometry: .polyline(PolylineGeom(points: p, closed: closed)))) }
        let rect = [Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)]
        switch c.kind {
        case "lumber":
            pl(rect)
            ents.append(Entity(layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(w, h)))))
            ents.append(Entity(layer: "0", geometry: .line(LineGeom(Vec2(w, 0), Vec2(0, h)))))
        case "brick":
            pl(rect)
            ents.append(Entity(layer: "0", geometry: .hatch(HatchGeom(loops: [rect.map { PolyVertex($0) }], pattern: "ANSI31", scale: max(h / 3, 1e-6) / 3.175))))
        case "cmu":
            pl(rect)
            let t = min(w, h) * 0.18
            let cells = w > h * 1.5 ? 2 : 1
            let cw = (w - t * Double(cells + 1)) / Double(cells)
            for k in 0..<cells {
                let x0 = t + Double(k) * (cw + t)
                pl([Vec2(x0, t), Vec2(x0 + cw, t), Vec2(x0 + cw, h - t), Vec2(x0, h - t)])
            }
        case "sheet":
            pl(rect)
        case "steel":
            let sec = StructuralProfiles.section(c.name.replacingOccurrences(of: "Steel ", with: ""))
            if let o = sec?.outline() { pl(o.outer.map { $0 * u + Vec2(w / 2, h / 2) }) } else { pl(rect) }
        default: pl(rect)
        }
        doc.blocks[bn] = Block(name: bn, basePoint: .zero, entities: ents, description: "Detail component \(c.name)")
        return bn
    }

    /// Insertion points of a repeating detail from a to b every `spacing` (the component's width by default).
    public static func repeatPositions(a: Vec2, b: Vec2, spacing: Double, inside: Bool = true) -> [Vec2] {
        let len = a.distance(to: b)
        guard len > 1e-9, spacing > 1e-9 else { return [] }
        let d = (b - a) / len
        let n = inside ? Int((len / spacing + 1e-9).rounded(.down)) : Int((len / spacing).rounded(.up))
        return (0..<max(n, 0)).map { a + d * (Double($0) * spacing) }
    }

    /// Batt insulation symbol between a and b, `width` wide, centred on the line (a prolate cycloid of loops).
    public static func insulation(a: Vec2, b: Vec2, width: Double) -> [Vec2] {
        let len = a.distance(to: b)
        guard len > 1e-9, width > 1e-9 else { return [] }
        let d = (b - a) / len, n = d.perp
        let r = width / 2, pitch = width / 2
        let loops = max(1, Int((len / pitch).rounded()))
        let p = len / Double(loops)
        let k = p / (2 * .pi)
        var out: [Vec2] = []
        let steps = loops * 24
        for i in 0...steps {
            let t = 2 * .pi * Double(i) / 24
            let x = k * t - r * 0.55 * sin(t)
            let y = r * (1 - cos(t)) - r
            let xc = min(max(x, 0), len)
            out.append(a + d * xc + n * y)
        }
        return out
    }
}

// MARK: - DOC-032 material tags

public enum MaterialTags {
    /// Material at a plan point of an element: the wall ply under the point (compound walls), else the element's material.
    public static func material(at p: Vec2, of el: BIMElement, doc: ArchiDocument) -> String? {
        if case .wall(let g) = el.geometry, let f = WallFrame(el) {
            let t = f.project(p).t
            for b in WallPlies.bands(g, doc: doc, halfThickness: f.h) where t <= b.thi + 1e-9 && t >= b.tlo - 1e-9 {
                if let m = b.material { return m }
            }
            if let tn = g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), let m = wt.plies.first?.material, wt.plies.count == 1 { return m }
        }
        if let st = el.props["slabType"], let t = doc.slabType(st), let top = t.plies.first { return top.material }
        return el.material
    }

    /// Material tags (leaders with props materialTagOf / materialTagAt) re-read their material after every edit.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices {
            guard let sid = doc.entities[i].props["materialTagOf"].flatMap(Int.init), case .leader(var l) = doc.entities[i].geometry else { continue }
            guard let el = doc.element(sid) else { if l.text != "?" { l.text = "?"; doc.entities[i].geometry = .leader(l); changed = true }; continue }
            let at = doc.entities[i].props["materialTagAt"].flatMap { s -> Vec2? in let c = s.split(separator: ",").compactMap { Double($0) }; return c.count == 2 ? Vec2(c[0], c[1]) : nil } ?? l.points[0]
            let m = material(at: at, of: el, doc: doc) ?? "?"
            if l.text != m { l.text = m; doc.entities[i].geometry = .leader(l); changed = true }
        }
        return changed
    }
}

// MARK: - PAR-026 parameter locks and EQ constraints in families

public enum FamilyConstraints {
    /// Locks a reference plane to a parameter (its offset becomes the parameter, optionally measured from another plane).
    public static func lock(_ plane: String, to param: String, from base: String? = nil, family: inout FamilyDefinition) -> Bool {
        guard let i = family.referencePlanes.firstIndex(where: { $0.name.caseInsensitiveCompare(plane) == .orderedSame }),
              family.parameter(param) != nil else { return false }
        family.referencePlanes[i].offset = base.map { "\($0) + \(param)" } ?? param
        return true
    }

    /// EQ: the planes between `first` and `last` (in the given order) are spaced equally; their offsets become
    /// formulas over the two outer planes, so they stay equal when parameters flex. Planes must share an axis.
    public static func equalize(_ planes: [String], family: inout FamilyDefinition) -> Bool {
        guard planes.count >= 3 else { return false }
        let idx = planes.compactMap { n in family.referencePlanes.firstIndex { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
        guard idx.count == planes.count, Set(idx.map { family.referencePlanes[$0].axis.lowercased() }).count == 1 else { return false }
        let a = family.referencePlanes[idx.first!].name, b = family.referencePlanes[idx.last!].name
        let n = planes.count - 1
        for (k, i) in idx.enumerated() where k > 0 && k < n {
            family.referencePlanes[i].offset = "\(a) + (\(b) - \(a)) * \(k) / \(n)"
        }
        // Formulas may only reference planes evaluated before them: keep the outer planes first.
        let inner = idx.dropFirst().dropLast().map { family.referencePlanes[$0] }
        family.referencePlanes.removeAll { p in inner.contains { $0.name == p.name } }
        family.referencePlanes += inner
        return true
    }
}
