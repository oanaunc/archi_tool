// Oanarina Archi Tool — GPL-3.0-or-later
// Door/window trim: casings (architraves) on both wall faces, an interior window board, and a lintel over the opening
// with bearings into the wall. Parameters are element props (or the opening type's params):
// casing / casingDepth (mm), sillBoard (projection, mm), lintel (height, mm), lintelBearing (mm), lintelMaterial.
import Foundation

public enum OpeningTrim {
    public struct Params: Hashable {
        public var casing: Double, casingDepth: Double, sillBoard: Double, lintel: Double, lintelBearing: Double, lintelMaterial: String
    }

    public static func params(_ el: BIMElement, doc: ArchiDocument) -> Params {
        let u = 1 / doc.units.mm
        var p = el.props
        if case .opening(let o) = el.geometry, let t = doc.openingType(o.typeName) { for (k, v) in t.params where p[k] == nil { p[k] = v } }
        func d(_ k: String, _ def: Double) -> Double { p[k].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? def }
        return Params(casing: max(d("casing", 0), 0) * u, casingDepth: max(d("casingDepth", 20), 1) * u, sillBoard: max(d("sillBoard", 0), 0) * u,
                      lintel: max(d("lintel", 0), 0) * u, lintelBearing: max(d("lintelBearing", 150), 0) * u, lintelMaterial: p["lintelMaterial"] ?? "Concrete")
    }

    static func meshGroups(_ el: BIMElement, _ o: OpeningGeom, f: WallFrame, zb: Double, zt: Double, unit u: Double) -> [MeshGroup] {
        // Parameters are in model units already scaled by `u` through params(); recompute from props with u.
        var p = el.props
        func d(_ k: String, _ def: Double) -> Double { p[k].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? def }
        p = el.props
        let casing = max(d("casing", 0), 0) * u, cd = max(d("casingDepth", 20), 1) * u
        let sill = max(d("sillBoard", 0), 0) * u, lin = max(d("lintel", 0), 0) * u, bear = max(d("lintelBearing", 150), 0) * u
        guard casing > 0 || sill > 0 || lin > 0, !f.isCurved else { return [] }
        let s0 = o.offset - o.width / 2, s1 = o.offset + o.width / 2, h = f.h
        func box(_ acc: inout MeshAcc, _ sa: Double, _ sb: Double, _ ta: Double, _ tb: Double, _ za: Double, _ zc: Double) {
            guard sb - sa > 1e-9, abs(tb - ta) > 1e-9, zc - za > 1e-9 else { return }
            acc.prism([f.pt(sa, min(ta, tb)), f.pt(sb, min(ta, tb)), f.pt(sb, max(ta, tb)), f.pt(sa, max(ta, tb))], z0: za, z1: zc)
        }
        var trim = MeshAcc(), lintel = MeshAcc()
        if casing > 0 {
            for side in [1.0, -1.0] {
                let ta = side * h, tb = side * (h + cd)
                let bottom = o.kind == .door ? zb : zb - casing
                box(&trim, s0 - casing, s0, ta, tb, bottom, zt + casing)
                box(&trim, s1, s1 + casing, ta, tb, bottom, zt + casing)
                box(&trim, s0, s1, ta, tb, zt, zt + casing)
                if o.kind == .window && !(sill > 0 && side == (o.flipFacing ? -1.0 : 1.0)) { box(&trim, s0, s1, ta, tb, zb - casing, zb) }
            }
        }
        if sill > 0 && o.kind == .window {
            // Interior window board on the room side (flipFacing = room on the right).
            let side: Double = o.flipFacing ? -1 : 1
            box(&trim, s0 - casing - 20 * u, s1 + casing + 20 * u, side * (h * 0.2), side * (h + sill), zb - 25 * u, zb)
        }
        if lin > 0 {
            // Inset 1 mm from the wall faces: seen in sections as its own material, hidden inside the wall in 3D.
            let e = 1 * u
            box(&lintel, s0 - bear, s1 + bear, -h + e, h - e, zt + e, zt + lin)
        }
        let mat = el.props["trimMaterial"] ?? "Wood"
        return [trim.group(el.id, "trim", mat), lintel.group(el.id, "lintel", el.props["lintelMaterial"] ?? "Concrete")].compactMap { $0 }
    }

    /// Plan: casings as small rectangles beside the jambs on both faces; the lintel (above the cut plane) dashed.
    static func planItems(_ el: BIMElement, _ o: OpeningGeom, ctx: BIMContext, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let doc = ctx.doc
        guard o.kind != .opening, let f = ctx.frames[o.hostWall] ?? doc.element(o.hostWall).flatMap({ WallFrame($0) }), !f.isCurved else { return [] }
        let p = params(el, doc: doc)
        guard p.casing > 0 || p.lintel > 0 || p.sillBoard > 0 else { return [] }
        let s0 = o.offset - o.width / 2, s1 = o.offset + o.width / 2, h = f.h
        func rect(_ a: Double, _ b: Double, _ t0: Double, _ t1: Double) -> [Vec2] { [f.pt(a, t0), f.pt(b, t0), f.pt(b, t1), f.pt(a, t1)] }
        var out: [DrawItem] = []
        if p.casing > 0 {
            for side in [1.0, -1.0] {
                out.append(PlanRepresentation.stroke(rect(s0 - p.casing, s0, side * h, side * (h + p.casingDepth)), closed: true, color, PlanRepresentation.lwFine))
                out.append(PlanRepresentation.stroke(rect(s1, s1 + p.casing, side * h, side * (h + p.casingDepth)), closed: true, color, PlanRepresentation.lwFine))
            }
        }
        if p.sillBoard > 0 && o.kind == .window {
            let side: Double = o.flipFacing ? -1 : 1
            let u = 1 / doc.units.mm
            out.append(PlanRepresentation.stroke(rect(s0 - p.casing - 20 * u, s1 + p.casing + 20 * u, side * h, side * (h + p.sillBoard)), closed: true, color, PlanRepresentation.lwFine))
        }
        if p.lintel > 0 {
            out.append(PlanRepresentation.stroke(rect(s0 - p.lintelBearing, s1 + p.lintelBearing, -h, h), closed: true, color, PlanRepresentation.lwHidden,
                                                 PlanRepresentation.hiddenDash(doc, options)))
        }
        return out
    }
}
