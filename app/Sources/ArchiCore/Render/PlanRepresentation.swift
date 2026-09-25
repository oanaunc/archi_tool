// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Architectural plan symbols for BIM elements (walls with cut fill and clean joins, doors, windows, stairs, rooms…).
public enum PlanRepresentation {
    // Line weights (mm): cut, projection, hidden (dashed), annotation.
    static let lwCut = 0.5, lwProj = 0.25, lwHidden = 0.18, lwAnno = 0.18, lwFine = 0.13
    static let cutFill = RGBA(0.62, 0.62, 0.62)

    // MARK: Public API

    public static func items(_ el: BIMElement, doc: ArchiDocument) -> [DrawItem] {
        items(el, ctx: context(doc), options: DrawOptions())
    }
    /// Deprecated alias of `items(_:doc:)`.
    public static func entries(_ el: BIMElement, doc: ArchiDocument) -> [DrawItem] { items(el, doc: doc) }

    public static func bounds(_ el: BIMElement, doc: ArchiDocument) -> BBox2 {
        DrawEntry(id: el.id, items: items(el, doc: doc)).bounds
    }

    public static func distance(from p: Vec2, to el: BIMElement, doc: ArchiDocument) -> Double {
        items(el, doc: doc).map { RG.distance(p, $0) }.min() ?? .infinity
    }

    /// Mitred outline polygon of a wall (ignoring openings), CCW. Empty if the id is not a wall.
    public static func wallOutline(_ wallID: EntityID, doc: ArchiDocument) -> [Vec2] {
        let ctx = context(doc)
        guard let f = ctx.frames[wallID] ?? doc.element(wallID).flatMap({ WallFrame($0) }) else { return [] }
        return ctx.outline(f)
    }

    /// Characteristic points for object snaps and grips.
    public static func snapPoints(_ el: BIMElement, doc: ArchiDocument) -> [Vec2] {
        switch el.geometry {
        case .wall(let g):
            var pts = [g.start, g.end]
            if abs(g.bulge) < 1e-9 { pts.append((g.start + g.end) / 2) }
            else if let f = WallFrame(el) { pts.append(f.pos(f.L / 2)) }
            pts += wallOutline(el.id, doc: doc)
            return pts
        case .opening(let o):
            guard let host = doc.element(o.hostWall), let f = WallFrame(host) else { return [] }
            let s0 = o.offset - o.width / 2, s1 = o.offset + o.width / 2
            return [f.pos(o.offset), f.pos(s0), f.pos(s1), f.pt(s0, f.h), f.pt(s0, -f.h), f.pt(s1, f.h), f.pt(s1, -f.h)]
        case .slab(let g): return g.boundary + g.holes.flatMap { $0 }
        case .roof(let g): return g.boundary
        case .space(let g): return g.boundary + [GeometryOps.centroid(g.boundary)]
        case .column(let g): return [g.position] + (g.round ? [] : columnPoly(g))
        case .beam(let g): return [g.start, g.end, (g.start + g.end) / 2]
        case .stair(let g):
            let l = StairShapes.layout(g)
            return [g.start] + (l.walk.last.map { [$0] } ?? [])
        case .railing(let g): return g.path
        case .curtainWall(let g): return [g.start, g.end, (g.start + g.end) / 2]
        case .component(let g): return [g.position] + componentPoly(g)
        case .gridLine(let g): return [g.start, g.end]
        }
    }

    // MARK: Context cache

    private static let lock = NSLock()
    private static var cached: (doc: ArchiDocument, ctx: BIMContext)?

    static func context(_ doc: ArchiDocument) -> BIMContext {
        lock.lock(); defer { lock.unlock() }
        if let c = cached, c.doc == doc { return c.ctx }
        let ctx = BIMContext(doc: doc)
        cached = (doc, ctx)
        return ctx
    }

    // MARK: Helpers

    static func unit(_ doc: ArchiDocument) -> Double { 1 / doc.units.mm }
    static func layerColor(_ el: BIMElement, _ doc: ArchiDocument) -> RGBA {
        if let c = el.props["color"], let ref = ColorRef.parse(c) {
            switch ref { case .aci(let i): return aciColor(i); case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255); default: break }
        }
        return doc.layer(named: el.layer)?.color ?? .white
    }
    static func hiddenDash(_ doc: ArchiDocument, _ o: DrawOptions) -> [Double] { [150, -75].map { $0 * unit(doc) * o.linetypeScale } }
    static func centerDash(_ doc: ArchiDocument, _ o: DrawOptions) -> [Double] { [1200, -200, 150, -200].map { $0 * unit(doc) * o.linetypeScale } }
    static func font(_ doc: ArchiDocument) -> String { doc.textStyles.first { $0.name == "Standard" }?.font ?? "Helvetica" }

    static func blend(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA { RGBA(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t) }

    static func stroke(_ pts: [Vec2], closed: Bool = false, _ c: RGBA, _ lw: Double, _ dash: [Double] = []) -> DrawItem {
        .stroke(points: pts, closed: closed, style: StrokeStyle(color: c, lineweight: lw, dash: dash))
    }

    static func patternScale(_ pattern: String, _ doc: ArchiDocument) -> Double {
        if let v = doc.variable("HPSCALE").flatMap(Double.init), v > 0 { return v * unit(doc) }
        return HatchPatterns.isRealWorld(pattern) ? unit(doc) : 15 * unit(doc)
    }

    static func columnPoly(_ g: ColumnGeom) -> [Vec2] {
        let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
        let w = g.width / 2, d = g.depth / 2
        return [Vec2(-w, -d), Vec2(w, -d), Vec2(w, d), Vec2(-w, d)].map(t.apply)
    }
    static func componentPoly(_ g: ComponentGeom) -> [Vec2] {
        let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
        let w = g.size.x / 2, d = g.size.y / 2
        return [Vec2(-w, -d), Vec2(w, -d), Vec2(w, d), Vec2(-w, d)].map(t.apply)
    }
    static func beamPoly(_ g: BeamGeom) -> [Vec2] {
        let d = (g.end - g.start).normalized.perp * (g.width / 2)
        return [g.start - d, g.end - d, g.end + d, g.start + d]
    }

    /// Offsets an open polyline sideways (positive = left) with mitred joints.
    static func offsetPolyline(_ pts0: [Vec2], _ d: Double) -> [Vec2] {
        let pts = RG.dedupe(pts0, closed: false)
        guard pts.count >= 2 else { return pts }
        var out: [Vec2] = []
        for i in 0..<pts.count {
            if i == 0 { out.append(pts[0] + (pts[1] - pts[0]).normalized.perp * d); continue }
            if i == pts.count - 1 { out.append(pts[i] + (pts[i] - pts[i - 1]).normalized.perp * d); continue }
            let n0 = (pts[i] - pts[i - 1]).normalized.perp, n1 = (pts[i + 1] - pts[i]).normalized.perp
            let a0 = pts[i - 1] + n0 * d, a1 = pts[i] + n0 * d, b0 = pts[i] + n1 * d, b1 = pts[i + 1] + n1 * d
            if let x = GeometryOps.lineIntersection(a0, a1, b0, b1), x.distance(to: pts[i]) < abs(d) * 6 { out.append(x) }
            else { out.append(pts[i] + n0 * d) }
        }
        return out
    }

    static func formatArea(_ a: Double, _ doc: ArchiDocument) -> String {
        switch doc.units {
        case .inches, .feet:
            let ft2 = a * pow(doc.units.mm / 304.8, 2)
            return String(format: "%.1f ft²", ft2)
        default:
            let m2 = a * doc.units.mm * doc.units.mm / 1_000_000
            return String(format: "%.2f m²", m2)
        }
    }

    // MARK: Items

    static func items(_ el: BIMElement, ctx: BIMContext, options: DrawOptions) -> [DrawItem] {
        let doc = ctx.doc
        let color = layerColor(el, doc)
        let u = unit(doc)
        switch el.geometry {
        case .wall: return wallItems(el, ctx: ctx, color: color, options: options)
        case .opening(let o): return openingItems(el, o, ctx: ctx, color: color, options: options)
        case .slab(let g):
            let dash = hiddenDash(doc, options)
            return ([g.boundary] + g.holes).filter { $0.count >= 2 }.map { stroke($0, closed: true, color, lwHidden, dash) }
        case .column(let g):
            let poly = g.round ? RG.circle(g.position, max(g.width, 0) / 2) : columnPoly(g)
            guard poly.count >= 3 else { return [] }
            return [.fill(loops: [poly], color: blend(cutFill, .black, 0.3)), stroke(poly, closed: true, color, lwCut)]
        case .beam(let g):
            guard g.start.distance(to: g.end) > 1e-9 else { return [] }
            let dash = hiddenDash(doc, options)
            return [stroke(beamPoly(g), closed: true, color, lwHidden, dash), stroke([g.start, g.end], color, lwFine, centerDash(doc, options))]
        case .stair(let g): return stairItems(g, doc: doc, color: color, options: options)
        case .railing(let g):
            guard g.path.count >= 2 else { return [] }
            let d = 25 * u
            return [stroke(offsetPolyline(g.path, d), color, lwProj), stroke(offsetPolyline(g.path, -d), color, lwProj)]
        case .roof(let g):
            let r = RoofShapes.faces(g)
            guard r.footprint.count >= 3 else { return [] }
            let dash = hiddenDash(doc, options)
            var out: [DrawItem] = [stroke(r.footprint, closed: true, color, lwHidden, dash)]
            var seen = Set<[Double]>()
            let tol = 1e-6 * max(1, BBox2(points: r.footprint).width)
            for f in r.faces {
                for i in 0..<f.poly.count {
                    let a = f.poly[i], b = f.poly[(i + 1) % f.poly.count]
                    if a.distance(to: b) < tol || RoofShapes.onOutline(a, b, r.footprint, tol: tol * 10 + 1e-6) { continue }
                    let key = a.x < b.x || (a.x == b.x && a.y < b.y) ? [a.x, a.y, b.x, b.y] : [b.x, b.y, a.x, a.y]
                    let rk = key.map { ($0 * 1000).rounded() / 1000 }
                    if seen.insert(rk).inserted { out.append(stroke([a, b], color, lwHidden, dash)) }
                }
            }
            if g.overhang > 0 { out.append(stroke(r.boundary, closed: true, color, lwFine, dash)) }
            return out
        case .space(let g):
            guard g.boundary.count >= 3 else { return [] }
            var out: [DrawItem] = [.fill(loops: [g.boundary], color: RGBA(color.r, color.g, color.b, 0.08))]
            if !options.showAnnotations { return out }
            let c = GeometryOps.centroid(g.boundary)
            let th = 250 * u, th2 = 180 * u
            let f = font(doc)
            out.append(.text(TextGeom(position: c + Vec2(0, th * 0.5), height: th, content: g.name.isEmpty ? el.name : g.name, halign: .center, valign: .bottom), font: f, color: color))
            var line2 = g.number
            let area = formatArea(abs(GeometryOps.signedArea(g.boundary)), doc)
            line2 = line2.isEmpty ? area : line2 + "  " + area
            out.append(.text(TextGeom(position: c - Vec2(0, th2 * 0.3), height: th2, content: line2, halign: .center, valign: .top), font: f, color: color))
            return out
        case .curtainWall(let g):
            let len = g.start.distance(to: g.end)
            guard len > 1e-9 else { return [] }
            let d = (g.end - g.start) / len, n = d.perp
            let m = max(g.mullionSize, 1e-6) / 2
            var out: [DrawItem] = [stroke([g.start + n * m, g.end + n * m], color, lwProj), stroke([g.start - n * m, g.end - n * m], color, lwProj),
                                   stroke([g.start, g.end], color, lwFine)]
            var positions: [Double] = [0]
            if g.gridU > 1e-9 { var x = g.gridU; while x < len - 1e-6 { positions.append(x); x += g.gridU } }
            positions.append(len)
            for x in positions {
                let c = g.start + d * x
                let sq = [c - d * m - n * m, c + d * m - n * m, c + d * m + n * m, c - d * m + n * m]
                out.append(.fill(loops: [sq], color: color))
            }
            return out
        case .component(let g):
            if let b = g.block, doc.blocks[b] != nil {
                let ins = Entity(id: el.id, layer: el.layer, color: .byLayer, geometry: .insert(InsertGeom(block: b, position: g.position, rotation: g.rotation)))
                return DrawListBuilder.items(for: ins, doc: doc, options: options)
            }
            let poly = componentPoly(g)
            var out: [DrawItem] = [stroke(poly, closed: true, color, lwProj), stroke([poly[0], poly[2]], color, lwFine), stroke([poly[1], poly[3]], color, lwFine)]
            let label = el.name.isEmpty ? g.category : el.name
            if options.showAnnotations, !label.isEmpty {
                let th = max(min(min(g.size.x, g.size.y) / 6, 150 * u), 1e-6)
                out.append(.text(TextGeom(position: g.position, height: th, content: label, rotation: DimensionRenderer.readable(g.rotation), halign: .center, valign: .middle), font: font(doc), color: color))
            }
            return out
        case .gridLine(let g):
            let len = g.start.distance(to: g.end)
            guard len > 1e-9 else { return [] }
            let d = (g.end - g.start) / len
            let r = 400 * u
            let c = g.start - d * r
            var out: [DrawItem] = [stroke([g.start, g.end], color, lwFine, centerDash(doc, options)), stroke(RG.circle(c, r, segments: 48), closed: true, color, lwAnno)]
            if options.showAnnotations { out.append(.text(TextGeom(position: c, height: 350 * u, content: g.label, halign: .center, valign: .middle), font: font(doc), color: color)) }
            return out
        }
    }

    // MARK: Walls

    static func splitByGaps(_ pts: [Vec2], side: Double, f: WallFrame, gaps: [(side: Double, s0: Double, s1: Double)]) -> [[Vec2]] {
        let gs = gaps.filter { $0.side == side }
        guard !gs.isEmpty, !f.isCurved, pts.count >= 2 else { return [pts] }
        var out: [[Vec2]] = []
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let sa = f.sOf(a), sb = f.sOf(b)
            guard abs(sb - sa) > 1e-12 else { continue }
            var keep: [(Double, Double)] = [(min(sa, sb), max(sa, sb))]
            for g in gs {
                var next: [(Double, Double)] = []
                for k in keep {
                    if g.s1 <= k.0 || g.s0 >= k.1 { next.append(k); continue }
                    if g.s0 > k.0 { next.append((k.0, g.s0)) }
                    if g.s1 < k.1 { next.append((g.s1, k.1)) }
                }
                keep = next
            }
            for k in keep where k.1 - k.0 > 1e-9 {
                let p = a + (b - a) * ((k.0 - sa) / (sb - sa)), q = a + (b - a) * ((k.1 - sa) / (sb - sa))
                out.append([p, q])
            }
        }
        return out
    }

    static func wallItems(_ el: BIMElement, ctx: BIMContext, color: RGBA, options: DrawOptions) -> [DrawItem] {
        guard let f = ctx.frames[el.id] ?? WallFrame(el) else { return [] }
        let doc = ctx.doc
        let j = ctx.join(f)
        // Ply build-up (left face → right face).
        var plies: [(material: String?, thi: Double, tlo: Double)] = []
        if let tn = f.g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), wt.thickness > 0, !wt.plies.isEmpty {
            let k = 2 * f.h / wt.thickness
            var t = f.h
            for p in wt.plies { let nt = t - p.thickness * k; plies.append((p.material, t, nt)); t = nt }
        } else { plies = [(el.material, f.h, -f.h)] }
        let firstMat = doc.material(plies.first?.material ?? el.material)
        let fill = blend(cutFill, firstMat?.color ?? cutFill, plies.count > 1 ? 0.15 : 0.25)
        var fills: [DrawItem] = [], patterns: [DrawItem] = [], lines: [DrawItem] = []
        let patColor = blend(color, fill, 0.35)
        for pc in ctx.pieces(f) {
            fills.append(.fill(loops: [pc.poly], color: fill))
            if options.cutHatches {
                for ply in plies {
                    let pat = doc.material(ply.material)?.cutPattern ?? "SOLID"
                    guard pat.uppercased() != "SOLID", HatchPatterns.names.contains(pat.uppercased()) else { continue }
                    if f.isCurved && plies.count > 1 { continue }
                    let origin = f.pt(0, ply.tlo)
                    let angle = f.isCurved ? 0 : f.dir.angle
                    var sc = patternScale(pat, doc)
                    if pat.uppercased() == "INSUL" { sc = (ply.thi - ply.tlo) / 100 }
                    let loops = [pc.poly.map { $0 - origin }]
                    let segs = HatchPatterns.lines(loops: loops, pattern: pat, scale: sc, angle: angle).map { $0.map { $0 + origin } }
                    for s in segs where s.count >= 2 {
                        if plies.count == 1 { patterns.append(stroke(s, patColor, lwFine)); continue }
                        // Clip to the ply band (straight walls: t is linear along the segment).
                        let ta = f.project(s[0]).t, tb = f.project(s[s.count - 1]).t
                        var t0 = 0.0, t1 = 1.0
                        if abs(tb - ta) < 1e-12 { if ta < ply.tlo - 1e-9 || ta > ply.thi + 1e-9 { continue } }
                        else {
                            let x0 = (ply.tlo - ta) / (tb - ta), x1 = (ply.thi - ta) / (tb - ta)
                            t0 = max(t0, min(x0, x1)); t1 = min(t1, max(x0, x1))
                        }
                        if t1 - t0 > 1e-9 { patterns.append(stroke([s[0].lerp(s[s.count - 1], t0), s[0].lerp(s[s.count - 1], t1)], patColor, lwFine)) }
                    }
                }
            }
            // Ply boundary lines.
            if plies.count > 1 {
                for ply in plies.dropLast() {
                    let line = f.isCurved ? f.face(ply.tlo, pc.s0, pc.s1) : [f.pt(pc.s0 - 10 * f.h - 1, ply.tlo), f.pt(pc.s1 + 10 * f.h + 1, ply.tlo)]
                    for s in RG.clipPolyline(line, [pc.poly]) { lines.append(stroke(s, color, lwFine)) }
                }
            }
            for s in splitByGaps(pc.faceR, side: -1, f: f, gaps: j.gaps) { lines.append(stroke(s, color, lwCut)) }
            for s in splitByGaps(pc.faceL, side: 1, f: f, gaps: j.gaps) { lines.append(stroke(s, color, lwCut)) }
            if pc.startEdgeVisible { lines.append(stroke([pc.faceL[0], pc.faceR[0]], color, lwCut)) }
            if pc.endEdgeVisible { lines.append(stroke([pc.faceR[pc.faceR.count - 1], pc.faceL[pc.faceL.count - 1]], color, lwCut)) }
        }
        return fills + patterns + lines
    }

    // MARK: Openings

    static func openingItems(_ el: BIMElement, _ o: OpeningGeom, ctx: BIMContext, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let doc = ctx.doc
        guard o.width > 0, let f = ctx.frames[o.hostWall] ?? doc.element(o.hostWall).flatMap({ WallFrame($0) }) else { return [] }
        let u = unit(doc)
        let h = f.h
        let s0 = o.offset - o.width / 2, s1 = o.offset + o.width / 2
        func P(_ s: Double, _ t: Double) -> Vec2 { f.pt(s, t) }
        func rect(_ a: Double, _ b: Double, _ t0: Double, _ t1: Double) -> [Vec2] { [P(a, t0), P(b, t0), P(b, t1), P(a, t1)] }
        let fw = min(max(o.frameWidth, 0), o.width / 4)
        let a = s0 + fw, b = s1 - fw
        var out: [DrawItem] = []
        switch o.kind {
        case .door:
            let side: Double = o.flipFacing ? -1 : 1
            if fw > 0 { out.append(stroke(rect(s0, a, -h, h), closed: true, color, lwProj)); out.append(stroke(rect(b, s1, -h, h), closed: true, color, lwProj)) }
            else { out.append(stroke([P(s0, -h), P(s0, h)], color, lwProj)); out.append(stroke([P(s1, -h), P(s1, h)], color, lwProj)) }
            let lf = b - a
            func leaf(_ hs: Double, _ sg: Double, _ len: Double) {
                guard len > 1e-9 else { return }
                let lt = min(40 * u, len * 0.08)
                out.append(stroke([P(hs, side * h), P(hs + sg * lt, side * h), P(hs + sg * lt, side * (h + len)), P(hs, side * (h + len))], closed: true, color, lwProj))
                let n = 24
                let arc = (0...n).map { i -> Vec2 in
                    let phi = Double.pi / 2 * Double(i) / Double(n)
                    return P(hs + sg * len * sin(phi), side * (h + len * cos(phi)))
                }
                out.append(stroke(arc, color, lwHidden))
            }
            switch o.doorStyle {
            case .single:
                if o.flipHand { leaf(b, -1, lf) } else { leaf(a, 1, lf) }
            case .double:
                leaf(a, 1, lf / 2); leaf(b, -1, lf / 2)
            case .sliding:
                let pt = 30 * u, ov = 50 * u, mid = (a + b) / 2
                out.append(stroke(rect(a, mid + ov, 5 * u, 5 * u + pt), closed: true, color, lwProj))
                out.append(stroke(rect(mid - ov, b, -5 * u - pt, -5 * u), closed: true, color, lwProj))
                let ay = side * (h + 150 * u)
                let from = o.flipHand ? b - lf * 0.1 : a + lf * 0.1, to = o.flipHand ? a + lf * 0.4 : b - lf * 0.4
                out.append(stroke([P(from, ay), P(to, ay)], color, lwFine))
                let dirv = (P(to, ay) - P(from, ay)).normalized
                out.append(.fill(loops: [RG.triangleArrow(tip: P(to, ay), dir: dirv, size: 120 * u)], color: color))
            case .folding:
                let q = lf / 2, th = Double.pi / 6
                for (hs, sg) in [(a, 1.0), (b, -1.0)] {
                    out.append(stroke([P(hs, side * h), P(hs + sg * q / 2 * cos(th), side * (h + q / 2 * sin(th) * 2)), P(hs + sg * q, side * h)], color, lwProj))
                }
            case .revolving:
                let c = P((a + b) / 2, 0), r = lf / 2
                out.append(stroke(RG.circle(c, r), closed: true, color, lwProj))
                let t0 = f.tangent(o.offset)
                for k in 0..<4 { let d = t0.rotated(by: .pi / 4 + Double(k) * .pi / 2); out.append(stroke([c, c + d * r], color, lwProj)) }
            case .garage:
                let dash = hiddenDash(doc, options)
                let depth = min(max(o.height, 0), 2500 * u)
                out.append(stroke(rect(a, b, side * h, side * (h + depth)), closed: true, color, lwHidden, dash))
                out.append(stroke([P(a, 0), P(b, 0)], color, lwProj))
            }
        case .window:
            out.append(stroke([P(s0, h), P(s1, h)], color, lwProj))
            out.append(stroke([P(s0, -h), P(s1, -h)], color, lwProj))
            let fd = min(h, 35 * u)
            if fw > 0 { out.append(stroke(rect(s0, a, -fd, fd), closed: true, color, lwProj)); out.append(stroke(rect(b, s1, -fd, fd), closed: true, color, lwProj)) }
            let g = min(h * 0.3, 8 * u)
            switch o.windowStyle {
            case .sliding:
                let mid = (a + b) / 2, ov = 40 * u
                out.append(stroke([P(a, 2 * g), P(mid + ov, 2 * g)], color, lwHidden))
                out.append(stroke([P(mid - ov, -2 * g), P(b, -2 * g)], color, lwHidden))
            case .doubleCasement:
                let mid = (a + b) / 2
                out.append(stroke(rect(mid - fw / 4, mid + fw / 4, -fd, fd), closed: true, color, lwProj))
                out.append(stroke([P(a, g), P(b, g)], color, lwHidden)); out.append(stroke([P(a, -g), P(b, -g)], color, lwHidden))
            default:
                out.append(stroke([P(a, g), P(b, g)], color, lwHidden)); out.append(stroke([P(a, -g), P(b, -g)], color, lwHidden))
            }
            let ext: Double = o.flipFacing ? 1 : -1
            let so = 40 * u
            out.append(stroke([P(s0 - so, ext * h), P(s0 - so, ext * (h + so)), P(s1 + so, ext * (h + so)), P(s1 + so, ext * h)], color, lwProj))
        case .opening:
            out.append(stroke([P(s0, -h), P(s1, h)], color, lwHidden, hiddenDash(doc, options)))
        }
        return out
    }

    // MARK: Stairs

    static func stairItems(_ g: StairGeom, doc: ArchiDocument, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let l = StairShapes.layout(g)
        guard !l.treads.isEmpty else { return [] }
        let u = unit(doc)
        let dash = hiddenDash(doc, options)
        let rh = max(g.riserHeight, 1e-6)
        let cutStep = Int((1200 * u / rh).rounded(.up))
        var out: [DrawItem] = []
        for t in l.treads {
            if t.step <= cutStep { out.append(stroke(t.poly, closed: true, color, lwProj)) }
            else { out.append(stroke(t.poly, closed: true, color, lwHidden, dash)) }
        }
        // Break line across the cut tread.
        if let ct = l.treads.first(where: { $0.step == cutStep && !$0.landing }), ct.poly.count >= 4, cutStep < l.treads.count {
            let A = ct.poly[1], B = ct.poly[ct.poly.count - 1]
            let d = B - A, n = d.normalized.perp * (d.length * 0.06)
            let ext = d.normalized * (d.length * 0.08)
            out.append(stroke([A - ext, A + d * 0.45, A + d * 0.48 + n, A + d * 0.52 - n, A + d * 0.55, B + ext], color, lwProj))
        }
        // Walk line with arrow.
        if l.walk.count >= 2 {
            let w = l.walk
            let last = w[w.count - 1], prev = w[w.count - 2]
            let dir = (last - prev).normalized
            let size = min(150 * u, g.treadDepth * 0.6)
            out.append(stroke(w, color, lwAnno))
            out.append(stroke(RG.circle(w[0], 40 * u, segments: 20), closed: true, color, lwAnno))
            out.append(.fill(loops: [RG.triangleArrow(tip: last, dir: dir, size: size)], color: color))
            if options.showAnnotations {
                let d0 = (w[1] - w[0]).normalized
                let th = 200 * u
                let rot = DimensionRenderer.readable(d0.angle)
                let flipped = abs(normAngle(rot - d0.angle)) > 1e-6
                out.append(.text(TextGeom(position: w[0] - d0 * (80 * u), height: th, content: "UP", rotation: rot,
                                          halign: flipped ? .left : .right, valign: .middle), font: font(doc), color: color))
            }
        }
        return out
    }
}
