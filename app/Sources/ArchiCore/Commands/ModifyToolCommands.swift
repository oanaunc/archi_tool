// Oanarina Archi Tool — GPL-3.0-or-later
// More modify tools: break at all intersections, line gaps at crossings, clip by polygon, weld, curve conversions,
// extend/trim by an amount (including ellipses and splines), paste to points, move-and-rotate, rotate twice,
// align to a reference entity.
import Foundation

enum ModifyToolCommands {
    /// Lengthens/shortens any open curve at the end nearest `pick` by `delta` (ellipse arcs and splines included).
    static func extendBy(_ g: Geometry, at pick: Vec2, delta: Double, doc: ArchiDocument?) -> Geometry? {
        if let r = Modify.lengthen(g, at: pick, delta: delta) { return r }
        guard delta > 0, let path = CurvePath.make(g), !path.closed else { return nil }
        let atEnd = path.closest(pick).s >= path.count / 2
        let target = GeometryOps.length(g, doc: nil) + delta
        switch g {
        case .ellipse(let e):
            // Grow the parameter range until the arc length matches (bisection on the added parameter).
            let sweep = normAngle(e.end - e.start)
            var lo = 0.0, hi = 2 * .pi - sweep - 1e-9
            guard hi > 0 else { return nil }
            func make(_ dt: Double) -> EllipseGeom { var x = e; if atEnd { x.end = normAngle(e.end + dt) } else { x.start = normAngle(e.start - dt) }; return x }
            guard GeometryOps.length(.ellipse(make(hi)), doc: nil) >= target else { return nil }
            for _ in 0..<80 { let m = (lo + hi) / 2; if GeometryOps.length(.ellipse(make(m)), doc: nil) < target { lo = m } else { hi = m } }
            return .ellipse(make((lo + hi) / 2))
        case .spline(let s):
            // Add a fit point along the end tangent; adjust its distance so the length grows by `delta`.
            var fit = s.fitPoints.isEmpty ? GeometryOps.splinePoints(s, samplesPerSpan: 4) : s.fitPoints
            guard fit.count >= 2 else { return nil }
            if !atEnd { fit.reverse() }
            let tan = (path.tangent(atEnd ? path.count : 0) * (atEnd ? 1 : -1)).normalized
            guard tan != .zero else { return nil }
            let endP = fit.last!
            func make(_ d: Double) -> SplineGeom {
                var pts = fit + [endP + tan * d]
                if !atEnd { pts.reverse() }
                return SplineGeom(degree: 3, controlPoints: [], fitPoints: pts, closed: false)
            }
            // Bisection on the extension distance (length grows monotonically with it).
            var lo = 0.0, hi = delta * 2
            var guardN = 0
            while GeometryOps.length(.spline(make(hi)), doc: nil) < target && guardN < 20 { hi *= 2; guardN += 1 }
            for _ in 0..<80 {
                let m = (lo + hi) / 2
                if GeometryOps.length(.spline(make(m)), doc: nil) < target { lo = m } else { hi = m }
            }
            let d = (lo + hi) / 2
            return .spline(make(d))
        default: return nil
        }
    }

    static var all: [CommandDef] { [
        CommandDef("EXTENDBY", aliases: ["TRIMBY", "LENGTHENBY"], category: "Modify", summary: "Extends (positive) or trims (negative) curves by an amount at the picked end: lines, arcs, polylines, ellipses, splines.") { ed in
            let delta = try await ed.getDistance("Enter amount (negative trims)", defaultValue: ed.variableDouble("EXTENDBYAMOUNT", 100)).value ?? 100
            guard abs(delta) > 1e-12 else { return }
            ed.doc.setVariable("EXTENDBYAMOUNT", fmt(delta))
            while case .pick(let pk) = try await ed.pickObject("Select object near the end to change", filter: { ed.doc.entity($0) != nil }) {
                guard let e = ed.doc.entity(pk.id), let r = extendBy(e.geometry, at: pk.point, delta: delta, doc: ed.doc) else { ed.print("This object cannot be changed by that amount."); continue }
                ed.replaceEntity(pk.id, with: [r])
            }
        },
        CommandDef("BREAKALL", aliases: ["BREAKATINTERSECTIONS", "DIVIDEATINTERSECTIONS"], category: "Modify", summary: "Breaks the selected objects at every intersection with each other.") { ed in
            let ids = try await ed.getEntitySelection("Select objects")
            let geos = ids.compactMap { id in ed.doc.entity(id).map { (id, $0.geometry) } }
            var created = 0
            for (id, g) in geos {
                var xs: [Vec2] = []
                for (oid, og) in geos where oid != id { xs += Intersections.of(g, og, doc: ed.doc) }
                guard !xs.isEmpty else { continue }
                let parts = Construct.split(g, at: xs)
                if parts.count > 1 { created += parts.count - 1; ed.replaceEntity(id, with: parts) }
            }
            ed.print("\(created) new piece(s) created.")
        },
        CommandDef("LINEGAP", aliases: ["GAPS", "CROSSINGGAP"], category: "Modify", summary: "Cuts gaps in the selected objects where other objects cross them (crossing display).") { ed in
            let ids = try await ed.getEntitySelection("Select objects to interrupt")
            let w = try await ed.getPositive("Specify gap width", defaultValue: ed.variableDouble("LINEGAPWIDTH", 100))
            ed.doc.setVariable("LINEGAPWIDTH", fmt(w))
            let set = Set(ids)
            let others = ed.doc.entities.filter { !set.contains($0.id) && ed.doc.isVisible(layer: $0.layer) }
            var n = 0
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                var xs: [Vec2] = []
                for o in others { xs += Intersections.of(e.geometry, o.geometry, doc: ed.doc) }
                guard !xs.isEmpty else { continue }
                let parts = Construct.gaps(e.geometry, at: xs, width: w)
                n += xs.count
                ed.replaceEntity(id, with: parts)
            }
            ed.print("\(n) gap(s) created.")
        },
        CommandDef("CLIPPOLY", aliases: ["CLIPWITHPOLYGON", "CLIPBOUNDARY"], category: "Modify", summary: "Clips the selected curves with a closed boundary, keeping the parts Inside or Outside.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select closed boundary (polyline, circle, ellipse, spline)", filter: { ed.doc.entity($0) != nil }),
                  let b = ed.doc.entity(pk.id) else { return }
            guard let poly = GeometryOps.tessellate(b.geometry, doc: ed.doc).first, poly.count >= 3,
                  (CurvePath.make(b.geometry)?.closed ?? false) else { throw CommandError.invalid("The boundary must be closed.") }
            let ids = try await ed.getEntitySelection("Select objects to clip").filter { $0 != pk.id }
            let keep = try await ed.getKeyword("Keep", ["Inside", "Outside"], defaultValue: "Inside") ?? "Inside"
            var removed = 0, kept = 0
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                if case .point(let p) = e.geometry {
                    if GeometryOps.pointInPolygon(p, poly) != (keep == "Inside") { ed.doc.remove(ids: [id]); removed += 1 } else { kept += 1 }
                    continue
                }
                guard CurvePath.make(e.geometry) != nil else { continue }
                let parts = Construct.clip(e.geometry, polygon: poly, keepInside: keep == "Inside", doc: ed.doc)
                if parts.isEmpty { ed.doc.remove(ids: [id]); removed += 1 } else { ed.replaceEntity(id, with: parts); kept += parts.count }
            }
            ed.print("\(kept) piece(s) kept, \(removed) object(s) removed.")
        },
        CommandDef("WELD", aliases: ["MERGECURVES"], category: "Modify", summary: "Merges curves touching end to end (lines, arcs, polylines, splines, ellipse arcs) into polylines.") { ed in
            let ids = try await ed.getEntitySelection("Select curves to weld")
            let tol = try await ed.getDistance("Specify fuzz distance", defaultValue: ed.variableDouble("WELDFUZZ", 0.01)).value ?? 0.01
            ed.doc.setVariable("WELDFUZZ", fmt(tol))
            let ents = ids.compactMap { ed.doc.entity($0) }
            guard ents.count >= 2 else { return }
            let res = Construct.weld(ents.map(\.geometry), tol: max(tol, 1e-9), sampling: ed.variableDouble("CONVERTTOL", 1), doc: ed.doc)
            guard res.count < ents.count else { ed.print("Nothing to weld."); return }
            let proto = ents[0]
            ed.doc.remove(ids: Set(ids))
            for g in res { var e = proto; e.geometry = g; ed.doc.add(e) }
            ed.print("\(ents.count) object(s) welded into \(res.count).")
        },
        CommandDef("CONVERTTOPLINE", aliases: ["TOPLINE", "SPLINETOPLINE", "CONVTOPL"], category: "Modify", summary: "Converts lines, arcs, circles, ellipses and splines to polylines (curves sampled within a tolerance).") { ed in
            let ids = try await ed.getEntitySelection("Select objects to convert")
            let tol = try await ed.getPositive("Specify maximum deviation", defaultValue: ed.variableDouble("CONVERTTOL", 1))
            ed.doc.setVariable("CONVERTTOL", fmt(tol))
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                let g = ed.doc.entities[i].geometry
                if case .polyline = g { continue }
                guard let (v, closed) = Construct.polylineVertices(g, tolerance: tol, doc: ed.doc), v.count >= 2 else { continue }
                ed.doc.entities[i].geometry = .polyline(PolylineGeom(v, closed: closed)); n += 1
            }
            ed.print("\(n) object(s) converted to polylines.")
        },
        CommandDef("PLINETOSPLINE", aliases: ["TOSPLINE", "CONVTOSPLINE"], category: "Modify", summary: "Converts polylines (and lines) to splines fitted through their vertices.") { ed in
            let ids = try await ed.getEntitySelection("Select polylines")
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                switch ed.doc.entities[i].geometry {
                case .polyline(let p):
                    guard let s = Construct.splineFromPolyline(p) else { continue }
                    ed.doc.entities[i].geometry = .spline(s); n += 1
                case .line(let l):
                    ed.doc.entities[i].geometry = .spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: [l.a, l.b])); n += 1
                default: continue
                }
            }
            ed.print("\(n) object(s) converted to splines.")
        },
        CommandDef("PASTETOPOINTS", aliases: ["COPYTOPOINTS", "PASTEMULTI"], category: "Edit", summary: "Pastes the clipboard at several picked points (one undo step).") { ed in
            guard let clip = DraftClipboard.current, !clip.isEmpty else { throw CommandError.invalid("The clipboard is empty.") }
            let prev = clip.entities.map(\.geometry).prefix(300)
            var n = 0
            var all: [EntityID] = []
            while let p = try await ed.getPoint("Specify insertion point", preview: { c in prev.map { GeometryOps.transform($0, .translation(c - clip.base)) } }).point {
                all += clip.paste(into: &ed.doc, offset: p - clip.base, level: ed.doc.currentLevel)
                n += 1
            }
            ed.selection = Set(all)
            ed.print("Pasted \(n) time(s).")
        },
        CommandDef("MOVEROTATE", aliases: ["MOVROT", "MR"], category: "Modify", summary: "Moves objects from a base point to a destination, then rotates them about it.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let b = try await ed.requirePoint("Specify base point")
            let d = try await ed.requirePoint("Specify destination point", base: b) { c in ed.transformedPreview(ids, .translation(c - b)) }
            let t0 = Transform2D.translation(d - b)
            let a = try await ed.getAngle("Specify rotation angle", base: d, defaultValue: 0) { c in ed.transformedPreview(ids, Transform2D.rotation((c - d).angle, around: d) * t0) }.value ?? 0
            ed.transformObjects(ids, Transform2D.rotation(a, around: d) * t0, copy: false)
            ed.selection = []
        },
        CommandDef("ROTATE2", aliases: ["ROTATETWICE", "RO2"], category: "Modify", summary: "Rotates objects about a first centre, then about a second centre.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let c1 = try await ed.requirePoint("Specify first centre")
            let a1 = try await ed.getAngle("Specify first rotation angle", base: c1, defaultValue: 0) { c in ed.transformedPreview(ids, .rotation((c - c1).angle, around: c1)) }.value ?? 0
            let r1 = Transform2D.rotation(a1, around: c1)
            let c2 = try await ed.requirePoint("Specify second centre")
            let a2 = try await ed.getAngle("Specify second rotation angle", base: c2, defaultValue: 0) { c in ed.transformedPreview(ids, Transform2D.rotation((c - c2).angle, around: c2) * r1) }.value ?? 0
            ed.transformObjects(ids, Transform2D.rotation(a2, around: c2) * r1, copy: false)
            ed.selection = []
        },
        CommandDef("ALIGNREF", aliases: ["ALIGNTO", "ROTATETOREF"], category: "Modify", summary: "Rotates objects about a base point so a reference direction (line or two points) aligns with a target line or angle.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let base = try await ed.requirePoint("Specify base point")
            @MainActor func direction(_ msg: String, angleOK: Bool) async throws -> Double? {
                let r = try await ed.pickObject(msg, keywords: angleOK ? ["Points", "Angle"] : ["Points"], filter: { id in
                    switch ed.doc.entity(id)?.geometry { case .line?, .polyline?: return true; default: return false } })
                switch r {
                case .pick(let pk):
                    guard let g = ed.doc.entity(pk.id)?.geometry, let part = Constraints.segmentPart(g, near: pk.point), let s = Constraints.segment(g, part: part) else { return nil }
                    var d = s.1 - s.0
                    // Orient the direction away from the end nearest the pick.
                    if pk.point.distance(to: s.1) < pk.point.distance(to: s.0) { d = -d }
                    return d.angle
                case .keyword("Points"):
                    let a = try await ed.requirePoint("Specify first point")
                    let b = try await ed.requirePoint("Specify second point", base: a)
                    return (b - a).angle
                case .keyword("Angle"): return try await ed.getAngle("Specify angle", base: base, defaultValue: 0).value
                default: return nil
                }
            }
            guard let src = try await direction("Select reference line (source direction)", angleOK: false),
                  let dst = try await direction("Select target line (destination direction)", angleOK: true) else { return }
            ed.transformObjects(ids, .rotation(dst - src, around: base), copy: false)
            ed.print("Rotated by \(fmt(deg(normAngle(dst - src)), 4))°.")
            ed.selection = []
        },
    ] }
}
