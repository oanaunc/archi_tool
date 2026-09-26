// Oanarina Archi Tool — GPL-3.0-or-later
// Plan view range (DOC-002), underlay levels (DOC-028) and reveal-hidden display (DOC-026).
// View range variables are offsets from the view's level: VRTOP, VRCUT, VRBOTTOM, VRDEPTH (all optional; the range is
// active when VRTOP or VRDEPTH is set). UNDERLAY names a level drawn halftone under the plan. REVEALHIDDEN = 1 draws
// temporarily hidden objects in magenta.
import Foundation

public enum ViewRange {
    public struct Range: Hashable {
        public var top: Double, cut: Double, bottom: Double, depth: Double
        public init(top: Double, cut: Double, bottom: Double, depth: Double) { self.top = top; self.cut = cut; self.bottom = bottom; self.depth = depth }
    }

    /// The active range (offsets from the level), or nil when not set.
    public static func range(_ doc: ArchiDocument) -> Range? {
        let top = doc.variable("VRTOP").flatMap(Double.init), depth = doc.variable("VRDEPTH").flatMap(Double.init)
        guard top != nil || depth != nil else { return nil }
        let u = 1 / doc.units.mm
        let cut = doc.variable("VRCUT").flatMap(Double.init) ?? 1200 * u
        let bottom = doc.variable("VRBOTTOM").flatMap(Double.init) ?? 0
        return Range(top: top ?? 2300 * u, cut: cut, bottom: bottom, depth: min(depth ?? bottom, bottom))
    }

    public static func store(_ r: Range?, in doc: inout ArchiDocument) {
        for k in ["VRTOP", "VRCUT", "VRBOTTOM", "VRDEPTH"] { doc.variables[k] = nil }
        guard let r = r else { return }
        doc.setVariable("VRTOP", fmt(r.top, 6)); doc.setVariable("VRCUT", fmt(r.cut, 6))
        doc.setVariable("VRBOTTOM", fmt(r.bottom, 6)); doc.setVariable("VRDEPTH", fmt(r.depth, 6))
    }

    /// Absolute vertical extent of an element (from its 3D representation); nil for datums and elements without volume.
    public static func extent(_ el: BIMElement, doc: ArchiDocument) -> (min: Double, max: Double)? {
        if case .gridLine = el.geometry { return nil }
        var lo = Double.infinity, hi = -Double.infinity
        for g in MeshBuilder.groups(for: el, doc: doc) { for p in g.mesh.positions { lo = min(lo, p.z); hi = max(hi, p.z) } }
        return lo <= hi ? (lo, hi) : nil
    }

    public enum Visibility { case normal, beyond, hidden }

    /// How an element shows in the plan of `level` under the range.
    public static func visibility(_ el: BIMElement, level: Int, range r: Range, doc: ArchiDocument) -> Visibility {
        guard let e = extent(el, doc: doc) else { return el.level == level ? .normal : .hidden }
        let base = doc.level(level)?.elevation ?? 0
        let top = base + r.top, bottom = base + r.bottom, depth = base + r.depth
        let eps = 1e-6
        if e.min > top + eps { return .hidden }
        if e.max < depth - eps { return .hidden }
        if el.level == level { return e.max < bottom - eps ? .beyond : .normal }
        // Other levels: only what lies in the view depth below the bottom shows (as "beyond").
        return e.max <= bottom + eps && e.max >= depth - eps ? .beyond : .hidden
    }

    /// Halftone "beyond" styling (thin, greyed).
    static func beyond(_ items: [DrawItem]) -> [DrawItem] {
        let gray = RGBA(0.5, 0.5, 0.5)
        return items.compactMap { it in
            switch it {
            case .stroke(let p, let c, var st): st.color = PlanRepresentation.blend(st.color, gray, 0.6); st.lineweight = min(st.lineweight, 0.13); return .stroke(points: p, closed: c, style: st)
            case .fill: return nil
            case .text(let t, let f, let c): return .text(t, font: f, color: PlanRepresentation.blend(c, gray, 0.6))
            case .image: return it
            }
        }
    }

    /// Underlay level id (UNDERLAY variable: level id or name), when different from the plan's level.
    public static func underlay(_ doc: ArchiDocument, plan level: Int) -> Int? {
        guard let v = doc.variable("UNDERLAY"), !v.isEmpty, v.lowercased() != "none" else { return nil }
        let id = Int(v) ?? doc.levels.first { $0.name.caseInsensitiveCompare(v) == .orderedSame }?.id
        return id == level ? nil : id
    }

    /// Halftone draw entries of the underlay level's elements (drawn first, not selectable).
    static func underlayEntries(_ doc: ArchiDocument, level: Int, ctx: BIMContext, options: DrawOptions) -> [DrawEntry] {
        guard let u = underlay(doc, plan: level) else { return [] }
        var o = options; o.level = u; o.showAnnotations = false
        return doc.elements.filter { $0.level == u && DrawListBuilder.layerShown($0.layer, doc, options) }.compactMap { el in
            if case .gridLine = el.geometry { return nil }
            if case .space = el.geometry { return nil }
            let items = beyond(PlanRepresentation.items(el, ctx: ctx, options: o))
            return items.isEmpty ? nil : DrawEntry(id: nil, items: items)
        }
    }

    public static let revealColor = RGBA(0.85, 0.1, 0.75)

    /// Hidden objects drawn in magenta when REVEALHIDDEN = 1.
    static func revealEntries(_ doc: ArchiDocument, options: DrawOptions) -> [DrawEntry] {
        guard doc.variable("REVEALHIDDEN") == "1" else { return [] }
        let h = HiddenObjects.load(doc)
        guard !h.entities.isEmpty || !h.elements.isEmpty else { return [] }
        var d = doc
        d.elements += h.elements.filter { d.element($0.id) == nil }
        let ctx = PlanRepresentation.context(d)
        func magenta(_ items: [DrawItem]) -> [DrawItem] {
            items.map { it in
                switch it {
                case .stroke(let p, let c, var st): st.color = revealColor; return .stroke(points: p, closed: c, style: st)
                case .fill(let l, _): return .fill(loops: l, color: RGBA(revealColor.r, revealColor.g, revealColor.b, 0.25))
                case .text(let t, let f, _): return .text(t, font: f, color: revealColor)
                case .image: return it
                }
            }
        }
        var out: [DrawEntry] = []
        for el in h.elements where options.level == nil || el.level == options.level {
            let items = magenta(PlanRepresentation.items(el, ctx: ctx, options: options))
            if !items.isEmpty { out.append(DrawEntry(id: nil, items: items)) }
        }
        for e in h.entities {
            let items = magenta(DrawListBuilder.items(for: e, doc: d, options: options))
            if !items.isEmpty { out.append(DrawEntry(id: nil, items: items)) }
        }
        return out
    }

    /// Restores the given hidden objects (all when `ids` is nil). Returns the number restored.
    @discardableResult
    public static func unhide(_ ids: Set<EntityID>?, in doc: inout ArchiDocument) -> Int {
        var h = HiddenObjects.load(doc)
        let existing = Set(doc.allIDs)
        let ents = h.entities.filter { ids?.contains($0.id) ?? true }, els = h.elements.filter { ids?.contains($0.id) ?? true }
        for e in ents where !existing.contains(e.id) { doc.ensureLayer(e.layer); doc.entities.append(e) }
        for e in els where !existing.contains(e.id) { doc.ensureLayer(e.layer); doc.elements.append(e) }
        h.entities.removeAll { e in ents.contains { $0.id == e.id } }
        h.elements.removeAll { e in els.contains { $0.id == e.id } }
        h.save(&doc)
        if let m = (ents.map(\.id) + els.map(\.id)).max(), m >= doc.nextID { doc.nextID = m + 1 }
        return ents.count + els.count
    }

    /// Temporarily hides every element of the given type names ("wall", "door", "component"…) on a level (nil = all).
    @discardableResult
    public static func hideCategory(_ types: [String], level: Int?, in doc: inout ArchiDocument) -> Int {
        let ids = doc.elements.filter { el in types.contains { $0.caseInsensitiveCompare(el.typeName) == .orderedSame } && (level == nil || el.level == level) }.map(\.id)
        return HiddenObjects.hide(Set(ids), in: &doc)
    }
}

/// Plan regions (DOC-012): closed boundaries on layer A-PLAN-REGION (props planRegion = "top,cut,bottom,depth", level)
/// with their own view range; elements whose plan centre lies inside use it instead of the view's range.
public enum PlanRegions {
    public static let layer = "A-PLAN-REGION"

    @discardableResult
    public static func add(_ boundary: [Vec2], range r: ViewRange.Range, level: Int, doc: inout ArchiDocument) -> EntityID {
        if doc.layer(named: layer) == nil { doc.layers.append(Layer(name: layer, color: RGBA(0.6, 0.6, 0.9), linetype: "Dashed", lineweight: 0.13, plot: false, description: "Plan regions")) }
        let id = doc.add(.polyline(PolylineGeom(points: boundary, closed: true)), layer: layer)
        if let i = doc.entityIndex(id) {
            doc.entities[i].props["planRegion"] = [r.top, r.cut, r.bottom, r.depth].map { fmt($0, 6) }.joined(separator: ",")
            doc.entities[i].props["level"] = "\(level)"
        }
        return id
    }

    /// Regions of a level: boundary and range.
    public static func regions(_ doc: ArchiDocument, level: Int) -> [(boundary: [Vec2], range: ViewRange.Range)] {
        doc.entities.compactMap { e in
            guard let s = e.props["planRegion"], e.props["level"].flatMap(Int.init).map({ $0 == level }) ?? true,
                  case .polyline(let pl) = e.geometry, pl.vertices.count >= 3 else { return nil }
            let v = s.split(separator: ",").compactMap { Double($0) }
            guard v.count == 4 else { return nil }
            return (pl.vertices.map(\.p), ViewRange.Range(top: v[0], cut: v[1], bottom: v[2], depth: v[3]))
        }
    }

    /// The range of the region containing an element's plan centre.
    static func range(for el: BIMElement, regions: [(boundary: [Vec2], range: ViewRange.Range)], doc: ArchiDocument) -> ViewRange.Range? {
        guard !regions.isEmpty else { return nil }
        let b = PlanRepresentation.bounds(el, doc: doc)
        guard !b.isEmpty else { return nil }
        return regions.first { GeometryOps.pointInPolygon(b.center, $0.boundary) }?.range
    }
}
