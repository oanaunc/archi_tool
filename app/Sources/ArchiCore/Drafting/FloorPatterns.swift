// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Surface patterns of floors in plan (ANN-072). A floor pattern is a hatch entity bound to a slab (prop
/// `floorPatternOf`) and to the slab's finish material (prop `material`, pattern kind surface). A document updater
/// keeps it in step after every edit: its loops are the slab boundary and holes minus the cut outlines of the walls
/// on the slab's level (so tiles never run through walls), its pattern and scale are the material's current surface
/// pattern, its pattern origin is the slab's first boundary corner (tiles stay aligned when the slab moves), and it
/// is deleted with its slab. When the material has no surface pattern the hatch has no loops and draws nothing. The
/// result is an ordinary hatch, so screen, PDF, SVG and DXF all show the same pattern.
public enum FloorPatterns {
    public static let prop = "floorPatternOf"
    public static let layer = "A-FLOR-PATT"
    /// Optional finish material on a slab (otherwise the slab's own material).
    public static let finishProp = "finishMaterial"

    public static func isFloorPattern(_ e: Entity) -> Bool { e.props[prop] != nil }

    /// Material whose surface pattern a slab shows.
    public static func material(of el: BIMElement) -> String? {
        if let f = el.props[finishProp], !f.isEmpty { return f }
        return el.material
    }

    /// Loops the pattern covers: slab region minus wall cut outlines on the same level.
    public static func loops(for el: BIMElement, doc: ArchiDocument) -> [[Vec2]] {
        guard case .slab(let s) = el.geometry, s.boundary.count >= 3 else { return [] }
        var region = PolygonBoolean.normalize([s.boundary] + s.holes.filter { $0.count >= 3 })
        guard !region.isEmpty else { return [] }
        let box = BBox2(points: s.boundary)
        var walls: [[Vec2]] = []
        for w in doc.elements where w.level == el.level {
            guard case .wall = w.geometry else { continue }
            var o = PlanRepresentation.wallOutline(w.id, doc: doc)
            if o.count > 3, o.first!.isClose(o.last!, tol: 1e-9) { o.removeLast() }
            guard o.count >= 3, BBox2(points: o).intersects(box) else { continue }
            walls.append(o)
        }
        if !walls.isEmpty {
            region = PolygonBoolean.apply(.subtract, region, PolygonBoolean.normalize(walls)).filter { $0.count >= 3 }
        }
        return region
    }

    /// The hatch the floor pattern entity should currently be; nil when its slab is gone.
    public static func resolved(_ e: Entity, doc: ArchiDocument) -> (HatchGeom, props: [String: String])? {
        guard let id = e.props[prop].flatMap(Int.init), let el = doc.element(id), case .slab(let s) = el.geometry,
              case .hatch(var h) = e.geometry else { return nil }
        var props = e.props
        props["level"] = String(el.level)
        let matName = material(of: el)
        let m = doc.material(matName)
        props[MaterialPatterns.prop] = m?.name ?? matName
        props[MaterialPatterns.kindProp] = MaterialPatterns.Kind.surface.rawValue
        if let o = s.boundary.first { props[DraftRendering.hatchOriginProp] = "\(fmt(o.x, 6)),\(fmt(o.y, 6))" }
        if let m, let pat = MaterialPatterns.surfacePattern(m.name, doc: doc), pat.uppercased() != "SOLID" {
            h.pattern = pat.uppercased()
            h.scale = MaterialPatterns.scale(pat, doc: doc) * (e.props[MaterialPatterns.scaleProp].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? 1)
            h.fill = nil
            h.loops = loops(for: el, doc: doc).map { $0.map { PolyVertex($0) } }
        } else {
            h.pattern = "SOLID"; h.fill = nil; h.loops = []
        }
        return (h, props)
    }

    /// Creates (or returns the existing) floor pattern of a slab.
    @discardableResult
    public static func create(for slabID: EntityID, doc: inout ArchiDocument) -> EntityID? {
        guard let el = doc.element(slabID), case .slab = el.geometry else { return nil }
        if let existing = doc.entities.first(where: { $0.props[prop] == String(slabID) }) { return existing.id }
        doc.ensureLayer(layer)
        var e = Entity(id: doc.allocateID(), layer: layer, geometry: .hatch(HatchGeom(loops: [])))
        e.props[prop] = String(slabID)
        if let (h, p) = resolved(e, doc: doc) { e.geometry = .hatch(h); e.props = p }
        doc.entities.append(e)
        return e.id
    }

    /// Keeps floor patterns in step with slabs, walls and materials; removes patterns of deleted slabs.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard doc.entities.contains(where: isFloorPattern) else { return false }
        var changed = false
        var remove: Set<EntityID> = []
        for i in doc.entities.indices where isFloorPattern(doc.entities[i]) {
            guard let (h, p) = resolved(doc.entities[i], doc: doc) else { remove.insert(doc.entities[i].id); continue }
            if case .hatch(let old) = doc.entities[i].geometry, old == h, doc.entities[i].props == p { continue }
            doc.entities[i].geometry = .hatch(h); doc.entities[i].props = p; changed = true
        }
        if !remove.isEmpty { doc.entities.removeAll { remove.contains($0.id) }; changed = true }
        return changed
    }
}
