// Oanarina Archi Tool — GPL-3.0-or-later
// Legend views (symbols of the types used in the project: wall types in plan, door/window types, floor/roof
// build-ups, components) and drafting views (2D-only views stored as blocks, edited in isolation).
import Foundation

public enum Legends {
    public static let kinds = ["walls", "openings", "slabs", "components", "materials"]

    /// Draw entries of a legend (drawing units, origin at the lower left).
    public static func entries(doc: ArchiDocument, kind: String) -> [DrawEntry] {
        let u = 1 / doc.units.mm
        var d = ArchiDocument()
        d.units = doc.units; d.materials = doc.materials; d.wallTypes = doc.wallTypes; d.openingTypes = doc.openingTypes
        d.slabTypes = doc.slabTypes; d.layers = doc.layers; d.textStyles = doc.textStyles; d.families = doc.families
        d.levels = [Level(id: 0, name: "Legend", elevation: 0)]; d.currentLevel = 0
        var labels: [(Vec2, String)] = []
        let rowH = 1500 * u, th = 180 * u
        var extra: [DrawEntry] = []
        switch kind.lowercased() {
        case "walls":
            for (i, wt) in doc.wallTypes.enumerated() {
                let y = -Double(i) * rowH
                let id = d.addElement(.wall(WallGeom(start: Vec2(0, y), end: Vec2(2000 * u, y), thickness: wt.thickness, wallType: wt.name)))
                _ = id
                labels.append((Vec2(2400 * u, y - th / 2), "\(wt.name)  (\(fmt(wt.thickness * doc.units.mm)) mm: " + wt.plies.map { "\($0.material) \(fmt($0.thickness * doc.units.mm))" }.joined(separator: " / ") + ")"))
            }
        case "openings":
            for (i, t) in doc.openingTypes.enumerated() {
                let y = -Double(i) * (rowH + 1200 * u)
                let w = d.addElement(.wall(WallGeom(start: Vec2(-200 * u, y), end: Vec2(t.width + 600 * u, y), thickness: 200 * u)))
                var o = OpeningGeom(kind: t.kind, hostWall: w, offset: t.width / 2 + 200 * u, width: t.width, height: t.height, sill: t.sill)
                t.apply(to: &o)
                d.addElement(.opening(o))
                labels.append((Vec2(t.width + 1000 * u, y - th / 2), "\(t.name)  \(t.kind.rawValue) \(fmt(t.width * doc.units.mm))×\(fmt(t.height * doc.units.mm))"))
            }
        case "slabs", "floors", "roofs":
            // Build-up legend: plies as stacked bands with material hatch and a description.
            var y = 0.0
            let w = 2000 * u, scale = 5.0
            for t in doc.slabTypes {
                var items: [DrawItem] = []
                var z = y
                for p in t.plies {
                    let h = max(p.thickness * scale, 20 * u)
                    let r = [Vec2(0, z - h), Vec2(w, z - h), Vec2(w, z), Vec2(0, z)]
                    let c = doc.material(p.material)?.color ?? RGBA(0.8, 0.8, 0.8)
                    items.append(.fill(loops: [r], color: c))
                    items.append(.stroke(points: r, closed: true, style: StrokeStyle(color: RGBA(0.1, 0.1, 0.1), lineweight: 0.25)))
                    items.append(.text(TextGeom(position: Vec2(w + 200 * u, z - h / 2), height: min(th, max(h * 0.6, 60 * u)), content: "\(p.material) \(fmt(p.thickness * doc.units.mm)) mm (\(p.function))", valign: .middle), font: "Helvetica", color: RGBA(0.1, 0.1, 0.1)))
                    z -= h
                }
                items.append(.text(TextGeom(position: Vec2(0, y + 120 * u), height: th, content: "\(t.name) — \(fmt(t.thickness * doc.units.mm)) mm, \(t.usage)"), font: "Helvetica", color: RGBA(0.1, 0.1, 0.1)))
                extra.append(DrawEntry(id: nil, items: items))
                y = z - 800 * u
            }
        case "components":
            var ids: [String] = []
            for el in doc.elements { if case .component(let g) = el.geometry, g.path == nil, let f = g.family, !ids.contains(f) { ids.append(f) } }
            for (i, f) in ids.enumerated() {
                let y = -Double(i) * 2500 * u
                let fam = ComponentLibrary.family(f)
                let size = fam?.size ?? Vec3(600, 600, 750)
                d.addElement(.component(ComponentGeom(category: fam?.category ?? "Generic", position: Vec2(size.x / 2 * u, y), size: Vec3(size.x * u, size.y * u, size.z * u), family: f)))
                labels.append((Vec2(size.x * u + 600 * u, y), (fam?.name ?? doc.family(named: f)?.name ?? f)))
            }
        case "materials":
            var y = 0.0
            var items: [DrawItem] = []
            for m in doc.materials {
                let r = [Vec2(0, y - 400 * u), Vec2(800 * u, y - 400 * u), Vec2(800 * u, y), Vec2(0, y)]
                items.append(.fill(loops: [r], color: m.color))
                items.append(.stroke(points: r, closed: true, style: StrokeStyle(color: RGBA(0.1, 0.1, 0.1), lineweight: 0.18)))
                if m.cutPattern.uppercased() != "SOLID", HatchPatterns.names.contains(m.cutPattern.uppercased()) {
                    for seg in HatchPatterns.lines(loops: [r], pattern: m.cutPattern, scale: 15 * u, angle: 0) where seg.count >= 2 {
                        items.append(.stroke(points: seg, closed: false, style: StrokeStyle(color: RGBA(0.15, 0.15, 0.15), lineweight: 0.13)))
                    }
                }
                items.append(.text(TextGeom(position: Vec2(1000 * u, y - 200 * u), height: th, content: "\(m.name)  (cut: \(m.cutPattern))", valign: .middle), font: "Helvetica", color: RGBA(0.1, 0.1, 0.1)))
                y -= 600 * u
            }
            extra.append(DrawEntry(id: nil, items: items))
        default: return []
        }
        var o = DrawOptions(level: 0)
        o.showAnnotations = false
        var out = d.elements.isEmpty ? [] : DrawListBuilder.entries(doc: d, options: o)
        out += extra
        if !labels.isEmpty {
            out.append(DrawEntry(id: nil, items: labels.map { .text(TextGeom(position: $0.0, height: th, content: $0.1, valign: .middle), font: "Helvetica", color: RGBA(0.1, 0.1, 0.1)) }))
        }
        return out
    }

    /// (Re)builds a legend block "LEGEND-<KIND>"; returns its name.
    @discardableResult
    public static func makeBlock(_ doc: inout ArchiDocument, kind: String) -> String? {
        let entries = entries(doc: doc, kind: kind)
        guard !entries.isEmpty else { return nil }
        var box = BBox2.empty
        for e in entries { box.add(e.bounds) }
        let name = "LEGEND-" + kind.uppercased()
        doc.blocks[name] = Block(name: name, basePoint: box.min, entities: ArchitectureCommands.entities(from: entries), description: "view:legend:" + kind.lowercased())
        return name
    }
}

/// Drafting views: named 2D-only views stored as blocks "DRAFT-<name>". Editing moves the content into model space
/// in isolation (DRAFTINGEDIT = name, DRAFTINGSTART = first new id); closing collects it back into the block.
public enum DraftingViews {
    public static func blockName(_ n: String) -> String { "DRAFT-" + n.uppercased().replacingOccurrences(of: " ", with: "_") }
    public static func names(_ doc: ArchiDocument) -> [String] {
        doc.blocks.values.filter { $0.description.hasPrefix("drafting:") }.map { String($0.description.dropFirst(9)) }.sorted()
    }

    public static func create(_ name: String, doc: inout ArchiDocument) -> Bool {
        let bn = blockName(name)
        guard doc.blocks[bn] == nil else { return false }
        doc.blocks[bn] = Block(name: bn, basePoint: .zero, entities: [], description: "drafting:" + name)
        return true
    }

    public static var editing: String { "DRAFTINGEDIT" }

    /// Starts editing: the block content is placed in model space (tagged) and everything else is hidden.
    public static func beginEdit(_ name: String, doc: inout ArchiDocument) -> Bool {
        let bn = blockName(name)
        guard let b = doc.blocks[bn], doc.variable(editing) == nil else { return false }
        doc.setVariable("DRAFTINGSTART", "\(doc.nextID)")
        for var e in b.entities { e.id = 0; e.props["draftingView"] = name; doc.add(e) }
        doc.setVariable(editing, name)
        return true
    }

    /// Ends editing: every tagged entity and every entity created since editing began goes back into the block.
    @discardableResult
    public static func endEdit(doc: inout ArchiDocument) -> Int {
        guard let name = doc.variable(editing) else { return 0 }
        let start = doc.variable("DRAFTINGSTART").flatMap(Int.init) ?? Int.max
        let bn = blockName(name)
        let mine = doc.entities.filter { $0.props["draftingView"] == name || $0.id >= start }
        var ents = mine
        for i in ents.indices { ents[i].props["draftingView"] = nil }
        doc.blocks[bn] = Block(name: bn, basePoint: .zero, entities: ents, description: "drafting:" + name)
        doc.remove(ids: Set(mine.map(\.id)))
        doc.variables[editing] = nil; doc.variables["DRAFTINGSTART"] = nil
        return ents.count
    }

    /// While a drafting view is edited, only its content is shown.
    public static func isolated(_ doc: ArchiDocument) -> ArchiDocument {
        guard let name = doc.variable(editing) else { return doc }
        let start = doc.variable("DRAFTINGSTART").flatMap(Int.init) ?? Int.max
        var d = doc
        d.elements = []
        d.entities = doc.entities.filter { $0.props["draftingView"] == name || $0.id >= start }
        return d
    }
}
