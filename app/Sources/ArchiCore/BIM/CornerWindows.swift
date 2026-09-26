// Oanarina Archi Tool — GPL-3.0-or-later
// Corner windows (BIM-041): a pair of windows hosted in two walls that meet at a corner, each running to the wall
// end. The host walls are cut through their mitred ends (so no masonry is left at the corner between sill and head),
// the glazing of both windows meets at a slim corner post, and the plan shows the glass to the corner with the sill
// lines meeting on the mitre.
import Foundation

public enum CornerWindows {
    public static let endKey = "cornerEnd", partnerKey = "cornerWindow"

    /// Cut range of an opening along its wall; corner windows extend past the wall end through the mitre zone.
    static func range(_ el: BIMElement, _ o: OpeningGeom, _ f: WallFrame) -> (Double, Double) {
        let a = o.offset - o.width / 2, b = o.offset + o.width / 2
        switch el.props[endKey] {
        case "end": return (a, f.L + 4 * f.h + 1)
        case "start": return (-4 * f.h - 1, b)
        default: return (a, b)
        }
    }

    /// Part of a polygon inside the wall outline (largest piece).
    static func clip(_ poly: [Vec2], to outline: [Vec2]) -> [Vec2]? {
        guard poly.count >= 3, outline.count >= 3 else { return nil }
        func ccw(_ p: [Vec2]) -> [Vec2] { GeometryOps.signedArea(p) < 0 ? p.reversed() : p }
        let parts = PolygonBoolean.apply(.intersect, [ccw(poly)], [ccw(outline)]).filter { abs(GeometryOps.signedArea($0)) > 1e-9 }
        return parts.max { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }
    }

    static func isOwner(_ el: BIMElement) -> Bool { (el.props[partnerKey].flatMap(Int.init) ?? Int.max) > el.id }

    // MARK: 3D

    static func meshGroups(_ el: BIMElement, _ o: OpeningGeom, f: WallFrame, ctx: BIMContext, zb: Double, zt: Double, unit u: Double) -> [MeshGroup] {
        let atEnd = el.props[endKey] == "end"
        let fw = min(max(o.frameWidth, 0), o.width / 4, o.height / 4)
        let fd = min(f.h, 35 * u), gt = min(6 * u, fd / 2)
        let sc = atEnd ? f.L : 0
        let s0 = atEnd ? o.offset - o.width / 2 : o.offset + o.width / 2
        let dir: Double = atEnd ? 1 : -1       // from the jamb towards the corner
        var frame = MeshAcc(), glass = MeshAcc()
        func box(_ acc: inout MeshAcc, _ a: Double, _ b: Double, _ ta: Double, _ tb: Double, _ za: Double, _ zc: Double) {
            let lo = min(a, b), hi = max(a, b)
            guard hi - lo > 1e-9, tb - ta > 1e-9, zc - za > 1e-9 else { return }
            acc.prism([f.pt(lo, ta), f.pt(hi, ta), f.pt(hi, tb), f.pt(lo, tb)], z0: za, z1: zc)
        }
        let inner = s0 + dir * fw
        if fw > 0 {
            box(&frame, s0, inner, -fd, fd, zb, zt)                              // outer jamb
            box(&frame, inner, sc + dir * fd, -fd, fd, zb, zb + fw)              // sill frame, into the corner
            box(&frame, inner, sc + dir * fd, -fd, fd, zt - fw, zt)              // head frame
        }
        box(&glass, inner, sc, -gt, gt, zb + fw, zt - fw)
        if isOwner(el) {
            let p = max(fw, 40 * u)
            box(&frame, sc - p / 2, sc + p / 2, -p / 2, p / 2, zb, zt)            // corner post
        }
        let frameMat = el.props["frameMaterial"] ?? "Aluminium"
        return [frame.group(el.id, "window", frameMat), glass.group(el.id, "window", "Glass")].compactMap { $0 }
    }

    // MARK: Plan

    static func planItems(_ el: BIMElement, _ o: OpeningGeom, ctx: BIMContext, color: RGBA) -> [DrawItem] {
        guard let f = ctx.frames[o.hostWall] ?? ctx.doc.element(o.hostWall).flatMap({ WallFrame($0) }) else { return [] }
        let u = PlanRepresentation.unit(ctx.doc)
        let atEnd = el.props[endKey] == "end"
        let fw = min(max(o.frameWidth, 0), o.width / 4)
        let gt = min(6 * u, f.h / 2)
        let sc = atEnd ? f.L : 0
        let s0 = atEnd ? o.offset - o.width / 2 : o.offset + o.width / 2
        let dir: Double = atEnd ? 1 : -1
        let inner = s0 + dir * fw
        let j = ctx.join(f)
        let (faceL, faceR) = atEnd ? (j.endL, j.endR) : (j.startL, j.startR)
        typealias PR = PlanRepresentation
        var out: [DrawItem] = []
        // Jamb, glass to the corner, sill lines to the mitre corners of the faces.
        out.append(PR.stroke([f.pt(s0, -f.h), f.pt(inner, -f.h), f.pt(inner, f.h), f.pt(s0, f.h)], closed: true, color, PR.lwProj))
        out.append(PR.stroke([f.pt(inner, gt), f.pt(sc, gt)], color, PR.lwProj))
        out.append(PR.stroke([f.pt(inner, -gt), f.pt(sc, -gt)], color, PR.lwProj))
        out.append(PR.stroke([f.pt(s0, f.h), faceL], color, PR.lwFine))
        out.append(PR.stroke([f.pt(s0, -f.h), faceR], color, PR.lwFine))
        if isOwner(el) {
            let p = max(fw, 40 * u) / 2
            out.append(PR.stroke([f.pt(sc - p, -p), f.pt(sc + p, -p), f.pt(sc + p, p), f.pt(sc - p, p)], closed: true, color, PR.lwProj))
        }
        return out
    }

    // MARK: Creation

    /// Places a corner window pair in two walls meeting end to end. Returns the two opening ids.
    @discardableResult
    public static func create(wallA: EntityID, wallB: EntityID, widthA: Double, widthB: Double, height: Double, sill: Double, doc: inout ArchiDocument) -> (EntityID, EntityID)? {
        guard wallA != wallB, let ea = doc.element(wallA), let eb = doc.element(wallB), let fa = WallFrame(ea), let fb = WallFrame(eb),
              !fa.isCurved, !fb.isCurved, ea.level == eb.level else { return nil }
        let tol = max(fa.h, fb.h) + 1
        var best: (atEndA: Bool, atEndB: Bool, d: Double)?
        for ae in [false, true] { for be in [false, true] {
            let d = (ae ? fa.ce : fa.cs).distance(to: be ? fb.ce : fb.cs)
            if d <= tol, best == nil || d < best!.d { best = (ae, be, d) }
        } }
        guard let c = best, abs(fa.dir.cross(fb.dir)) > sin(10 * Double.pi / 180) else { return nil }
        guard widthA > 0, widthB > 0, height > 0, widthA < fa.L - 1e-6, widthB < fb.L - 1e-6 else { return nil }
        func add(_ host: BIMElement, _ f: WallFrame, _ atEnd: Bool, _ w: Double) -> EntityID {
            let off = atEnd ? f.L - w / 2 : w / 2
            let o = OpeningGeom(kind: .window, hostWall: host.id, offset: off, width: w, height: height, sill: sill, windowStyle: .fixed, frameWidth: 50)
            return doc.addElement(.opening(o), level: host.level, material: "Glass", name: "Corner window")
        }
        let ia = add(ea, fa, c.atEndA, widthA), ib = add(eb, fb, c.atEndB, widthB)
        for (id, partner, atEnd) in [(ia, ib, c.atEndA), (ib, ia, c.atEndB)] {
            if let i = doc.elementIndex(id) { doc.elements[i].props[endKey] = atEnd ? "end" : "start"; doc.elements[i].props[partnerKey] = "\(partner)" }
        }
        return (ia, ib)
    }

    /// Deleting one window of a pair turns the other into an ordinary window.
    public static func hasContent(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props[endKey] != nil } }
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.elements.indices where doc.elements[i].props[endKey] != nil {
            guard let p = doc.elements[i].props[partnerKey].flatMap(Int.init), doc.element(p) != nil else {
                doc.elements[i].props[endKey] = nil; doc.elements[i].props[partnerKey] = nil; changed = true; continue
            }
        }
        return changed
    }
}

enum CornerWindowCommands {
    static var all: [CommandDef] { [cornerWindow] }

    static var cornerWindow: CommandDef {
        CommandDef("CORNERWINDOW", aliases: ["CORNERWIN", "WRAPWINDOW"], category: "Architecture", summary: "Corner window wrapping the corner of two walls: widths along each wall from the corner, height and sill; the walls are cut through the corner and the glazing meets at a slim post.") { ed in
            let isWall: (EntityID) -> Bool = { id in if case .wall? = ed.doc.element(id)?.geometry { return true }; return false }
            guard case .pick(let a) = try await ed.pickObject("Select the first wall", filter: isWall),
                  case .pick(let b) = try await ed.pickObject("Select the second wall", filter: { isWall($0) && $0 != a.id }) else { return }
            let wa = try await ed.getPositive("Width along the first wall (from the corner)", defaultValue: 1200)
            let wb = try await ed.getPositive("Width along the second wall (from the corner)", defaultValue: wa)
            let h = try await ed.getPositive("Height", defaultValue: 1500)
            let sill = try await ed.getDistance("Sill height", defaultValue: 900).value ?? 900
            guard let (ia, ib) = CornerWindows.create(wallA: a.id, wallB: b.id, widthA: wa, widthB: wb, height: h, sill: sill, doc: &ed.doc) else {
                throw CommandError.invalid("The walls must be straight, on one level, meet at an angle, and be longer than the windows.")
            }
            ed.selection = [ia, ib]
            ed.print("Corner window #\(ia) / #\(ib) placed.")
        }
    }
}
