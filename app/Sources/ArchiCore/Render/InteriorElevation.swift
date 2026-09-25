// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Interior elevations of a room: four views (A–D) looking at its walls, cut at the room outline and limited to
/// the room's width and height.
public enum InteriorElevation {
    public struct View {
        /// Viewing direction in plan.
        public var direction: Vec2
        /// Section line (viewing to its left), just inside the room behind the viewer.
        public var a: Vec2, b: Vec2
        public var width: Double
        public var z0: Double, z1: Double
        public var label: String
    }

    /// Views A–D, turning counter-clockwise from the view facing away from the room's longest wall's left side.
    public static func views(room el: BIMElement, doc: ArchiDocument) -> [View] {
        guard case .space(let sp) = el.geometry, sp.boundary.count >= 3 else { return [] }
        let b = sp.boundary
        var theta = 0.0, longest = -1.0
        for i in 0..<b.count { let l = b[i].distance(to: b[(i + 1) % b.count]); if l > longest + 1e-9 { longest = l; theta = (b[(i + 1) % b.count] - b[i]).angle } }
        let z0 = doc.level(el.level)?.elevation ?? 0
        let inset = 10 / doc.units.mm
        return (0..<4).map { k in
            let f = Vec2.polar(1, theta + .pi / 2 + Double(k) * .pi / 2)
            let u = Vec2(f.y, -f.x)
            let back = b.map { $0.dot(f) }.min()!
            let lat = b.map { $0.dot(u) }
            let lo = lat.min()!, hi = lat.max()!
            let a = f * (back + inset) + u * lo
            return View(direction: f, a: a, b: a + u * (hi - lo), width: hi - lo, z0: z0, z1: z0 + sp.height, label: String("ABCD"[String.Index(utf16Offset: k, in: "ABCD")]))
        }
    }

    /// Hidden-line drawing of one view; x runs 0…width along the view, y is absolute height.
    public static func entries(doc: ArchiDocument, room el: BIMElement, index: Int) -> [DrawEntry] {
        let vs = views(room: el, doc: doc)
        guard index >= 0, index < vs.count, case .space(let sp) = el.geometry else { return [] }
        let v = vs[index]
        guard let proj = ElevationBuilder.projection(.section, section: (v.a, v.b)) else { return [] }
        let margin = 600 / doc.units.mm
        let box = BBox2(points: sp.boundary).expanded(by: margin)
        let groups = MeshBuilder.build(doc: doc).filter { g in
            let bb = g.mesh.bounds
            guard !bb.isEmpty else { return false }
            if bb.max.z < v.z0 - 1e-6 || bb.min.z > v.z1 + 1e-6 { return false }
            return BBox2(min: bb.min.xy, max: bb.max.xy).intersects(box)
        }
        let es = ElevationBuilder.entries(groups: groups, doc: doc, proj: proj, cut: true)
        let pad = 150 / doc.units.mm
        let win = BBox2(min: Vec2(-1e-6, v.z0 - pad), max: Vec2(v.width + 1e-6, v.z1 + pad))
        var out = ArchitectureCommands.clip(es, to: win).filter { !$0.items.isEmpty }
        // Room outline of the view (floor, ceiling and the two side walls).
        out.append(DrawEntry(id: el.id, items: [.stroke(points: [Vec2(0, v.z0), Vec2(v.width, v.z0), Vec2(v.width, v.z1), Vec2(0, v.z1)], closed: true,
                                                          style: StrokeStyle(color: ElevationBuilder.edgeColor, lineweight: 0.5))]))
        return out
    }
}
