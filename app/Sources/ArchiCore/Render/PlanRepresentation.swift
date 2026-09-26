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
        case .component(let g): return g.path != nil ? g.worldPath : [g.position] + componentPoly(g)
        case .gridLine(let g): return g.points
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
        // Profiled beams keep width/depth in step with their section (set when the profile is applied).
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
        case .opening(let o):
            // Reflected ceiling plans show door openings as gaps only (no leaves or swings).
            if options.reflectedCeiling && o.kind == .door { return [] }
            return openingItems(el, o, ctx: ctx, color: color, options: options)
        case .slab(let g) where options.reflectedCeiling && el.props["kind"] == "ceiling":
            return ReflectedCeiling.ceilingItems(el, g, doc: doc, color: color, options: options)
        case .slab(let g):
            let dash = hiddenDash(doc, options)
            var out = ([g.boundary] + g.holes).filter { $0.count >= 2 }.map { stroke($0, closed: true, color, lwHidden, dash) }
            if g.isSloped && g.boundary.count >= 3 { out += slopeArrow(g, el: el, doc: doc, color: color, options: options) }
            if let tile = el.props["finishTile"], g.boundary.count >= 3 { out += tileGrid(tile, boundary: g.boundary, holes: g.holes, doc: doc, color: color) }
            return out
        case .column(let g):
            if let sec = StructuralProfiles.section(g.profile) {
                let o = StructuralProfiles.outline(sec, unit: u)
                let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
                let outer = o.outer.map(t.apply), holes = o.holes.map { $0.map(t.apply) }
                return [.fill(loops: [outer] + holes, color: blend(cutFill, .black, 0.3)), stroke(outer, closed: true, color, lwCut)] + holes.map { stroke($0, closed: true, color, lwCut) }
            }
            let poly = g.round ? RG.circle(g.position, max(g.width, 0) / 2) : columnPoly(g)
            guard poly.count >= 3 else { return [] }
            return [.fill(loops: [poly], color: blend(cutFill, .black, 0.3)), stroke(poly, closed: true, color, lwCut)]
        case .beam(let g):
            guard g.start.distance(to: g.end) > 1e-9 else { return [] }
            let dash = hiddenDash(doc, options)
            return [stroke(beamPoly(g), closed: true, color, lwHidden, dash), stroke([g.start, g.end], color, lwFine, centerDash(doc, options))]
        case .stair(let g):
            if let l = options.level, l != el.level { return upperStairItems(g, doc: doc, color: color, options: options) }
            return stairItems(g, doc: doc, color: color, options: options)
        case .railing(let g):
            guard g.path.count >= 2 else { return [] }
            let d = 25 * u
            guard g.isSloped, let zs = g.pathZ, zs.count == g.path.count else {
                return [stroke(offsetPolyline(g.path, d), color, lwProj), stroke(offsetPolyline(g.path, -d), color, lwProj)]
            }
            // Railings on stairs/ramps: drawn up to the plan cut plane, dashed beyond it (with a cut mark), like the stair.
            let cut = BIMConstraints.cutHeight(doc)
            var below: [Vec2] = [g.path[0]], above: [Vec2] = []
            var cutPoint: Vec2? = nil
            for i in 0..<(g.path.count - 1) {
                let a = g.path[i], b = g.path[i + 1], za = zs[i], zb = zs[i + 1]
                if above.isEmpty {
                    if zb <= cut || abs(zb - za) < 1e-12 { below.append(b); continue }
                    let t = za >= cut ? 0 : (cut - za) / (zb - za)
                    let c = a.lerp(b, t)
                    below.append(c); cutPoint = c; above = [c, b]
                } else { above.append(b) }
            }
            var out: [DrawItem] = []
            if below.count >= 2 && RG.dedupe(below, closed: false).count >= 2 {
                out += [stroke(offsetPolyline(below, d), color, lwProj), stroke(offsetPolyline(below, -d), color, lwProj)]
            }
            if above.count >= 2 && RG.dedupe(above, closed: false).count >= 2 {
                let dash = hiddenDash(doc, options)
                out += [stroke(offsetPolyline(above, d), color, lwHidden, dash), stroke(offsetPolyline(above, -d), color, lwHidden, dash)]
            }
            if let c = cutPoint, let k = g.path.indices.dropLast().first(where: { i in
                let a = g.path[i], b = g.path[i + 1]; return GeometryOps.distance(from: c, toPolyline: [a, b]) < 1e-6 }) {
                let dir = (g.path[k + 1] - g.path[k]).normalized, n = dir.perp
                out.append(stroke([c - n * (3 * d) - dir * d, c + n * (3 * d) + dir * d], color, lwProj))
            }
            return out
        case .roof(let g):
            let r = RoofShapes.faces(g)
            guard r.footprint.count >= 3 else { return [] }
            let dash = hiddenDash(doc, options)
            var out: [DrawItem] = [stroke(r.footprint, closed: true, color, lwHidden, dash)]
            var seen = Set<[Double]>()
            let tol = 1e-6 * max(1, BBox2(points: r.footprint).width)
            for f in r.faces where !(g.profile?.isCurved ?? false) {
                for i in 0..<f.poly.count {
                    let a = f.poly[i], b = f.poly[(i + 1) % f.poly.count]
                    if a.distance(to: b) < tol || RoofShapes.onOutline(a, b, r.footprint, tol: tol * 10 + 1e-6) { continue }
                    let key = a.x < b.x || (a.x == b.x && a.y < b.y) ? [a.x, a.y, b.x, b.y] : [b.x, b.y, a.x, a.y]
                    let rk = key.map { ($0 * 1000).rounded() / 1000 }
                    if seen.insert(rk).inserted { out.append(stroke([a, b], color, lwHidden, dash)) }
                }
            }
            if g.overhang > 0 { out.append(stroke(r.boundary, closed: true, color, lwFine, dash)) }
            if let pr = g.profile, pr.isCurved, let top = r.faces.max(by: { $0.height(GeometryOps.centroid($0.poly)) < $1.height(GeometryOps.centroid($1.poly)) }) {
                // Curved roofs: crown line (barrel) or crown circle (dome) instead of facet lines.
                if pr.form == .dome { out.append(stroke(RG.circle(GeometryOps.centroid(r.boundary), 150 * u, segments: 24), closed: true, color, lwHidden, dash)) }
                else { out.append(stroke(top.poly, closed: true, color, lwHidden, dash)) }
            } else if options.showAnnotations && doc.variable("ROOFSLOPEARROWS") != "0" { out += roofSlopeArrows(g, faces: r.faces, doc: doc, color: color) }
            return out
        case .space(let g):
            guard g.boundary.count >= 3 else { return [] }
            return spaceItems(el, g, ctx: ctx, color: color, options: options)
        case .curtainWall(let g):
            let len = g.start.distance(to: g.end)
            guard len > 1e-9 else { return [] }
            let d = (g.end - g.start) / len, n = d.perp
            let m = max(g.mullionSize, 1e-6) / 2
            var out: [DrawItem] = [stroke([g.start + n * m, g.end + n * m], color, lwProj), stroke([g.start - n * m, g.end - n * m], color, lwProj),
                                   stroke([g.start, g.end], color, lwFine)]
            let positions: [Double] = [0] + g.uPositions + [len]
            for (xi, x) in positions.enumerated() {
                let sec = CurtainMullion.planSection(g, x: x, border: xi == 0 || xi == positions.count - 1)
                guard sec.count >= 3 else { continue }
                out.append(.fill(loops: [sec], color: color))
                out.append(stroke(sec, closed: true, color, lwFine))
            }
            // Door panels (bottom row): leaf and 90° swing on the +normal side.
            for i in 0..<(positions.count - 1) {
                guard let kind = g.panels["\(i),0"], kind == "door" || kind == "doubledoor" else { continue }
                let x0 = positions[i] + m, x1 = positions[i + 1] - m
                guard x1 > x0 else { continue }
                let leaves = kind == "doubledoor" ? 2 : 1
                let lw = (x1 - x0) / Double(leaves)
                for k in 0..<leaves {
                    let hinge = k == 0 ? x0 : x1, dirSign: Double = k == 0 ? 1 : -1
                    let h = g.start + d * hinge + n * m
                    let open = h + n * lw
                    out.append(stroke([h, open], color, lwProj))
                    let a0 = (d * dirSign).angle, sweep = (n.angle - a0)
                    let sw = normAngle(sweep + .pi) - .pi
                    out.append(stroke(GeometryOps.arcPoints(center: h, radius: lw, start: a0, sweep: sw), color, lwFine))
                }
            }
            return out
        case .component(let g):
            if el.props["kind"] == "skylight" { return RoofDetails.skylightPlan(g, color: color, unit: u) }
            if let b = g.block, doc.blocks[b] != nil {
                let ins = Entity(id: el.id, layer: el.layer, color: .byLayer, geometry: .insert(InsertGeom(block: b, position: g.position, rotation: g.rotation)))
                return DrawListBuilder.items(for: ins, doc: doc, options: options)
            }
            if g.path == nil, let def = doc.family(named: g.family) {
                let r = FamilyEngine.evaluate(def, doc: doc, props: el.props, origin: Vec3(g.position.x, g.position.y, 0), rotation: g.rotation)
                let dash = hiddenDash(doc, options)
                let items = r.outlines.map { stroke($0, closed: true, color, lwProj) }
                    + r.symbols.map { stroke($0.points, closed: $0.closed, color, lwFine, $0.dashed ? dash : []) }
                if !items.isEmpty { return items }
            }
            if let rf = ComponentLibrary.runFamily(g.family) {
                let dash = hiddenDash(doc, options)
                // Runs display in their system colour (unless the element has an explicit colour).
                let c = el.props["color"] == nil ? (RunFamilies.systemColor(el.props["system"]) ?? color) : color
                return RunFamilies.symbol(rf, g).filter { $0.points.count >= 2 }.map {
                    stroke($0.points, closed: $0.closed, c, $0.outline ? lwProj : lwFine, $0.hidden ? dash : [])
                }
            }
            if let fam = ComponentLibrary.family(g.family) {
                let dash = hiddenDash(doc, options)
                var out = ComponentLibrary.worldSymbol(fam, g).filter { $0.points.count >= 2 }.map {
                    stroke($0.points, closed: $0.closed, color, $0.outline ? lwProj : lwFine, $0.hidden ? dash : [])
                }
                // MEP connection points (MEPCONNECTORS = 1): small circles tagged with the system.
                if doc.variable("MEPCONNECTORS") == "1" {
                    for k in ComponentLibrary.worldConnectors(fam, g, z0: 0) {
                        let c = k.position.xy, r = 35 * u
                        out.append(stroke(RG.circle(c, r, segments: 12), closed: true, RGBA(0.3, 0.7, 1.0), lwFine))
                        if options.showAnnotations { out.append(.text(TextGeom(position: c + Vec2(r * 1.3, 0), height: 60 * u, content: k.system, valign: .middle), font: font(doc), color: RGBA(0.3, 0.7, 1.0))) }
                    }
                }
                return out
            }
            let poly = componentPoly(g)
            var out: [DrawItem] = [stroke(poly, closed: true, color, lwProj), stroke([poly[0], poly[2]], color, lwFine), stroke([poly[1], poly[3]], color, lwFine)]
            let label = el.name.isEmpty ? g.category : el.name
            if options.showAnnotations, !label.isEmpty, let th = componentLabelHeight(g, label: label, unit: u) {
                out.append(.text(TextGeom(position: g.position, height: th, content: label, rotation: DimensionRenderer.readable(g.rotation), halign: .center, valign: .middle),
                                 font: font(doc), color: blend(color, RGBA(0.55, 0.55, 0.55, color.a), 0.45)))
            }
            return out
        case .gridLine(let g):
            let len = g.start.distance(to: g.end)
            guard len > 1e-9 else { return [] }
            let pts = g.points
            let r = 400 * u
            var out: [DrawItem] = [stroke(pts, color, lwFine, centerDash(doc, options))]
            let ends = g.headEnds
            var heads: [Vec2] = []
            if ends.start { heads.append(g.start - (pts[1] - pts[0]).normalized * r) }
            if ends.end, pts.count >= 2 { let n = pts.count; heads.append(g.end + (pts[n - 1] - pts[n - 2]).normalized * r) }
            for c in heads {
                out.append(stroke(RG.circle(c, r, segments: 48), closed: true, color, lwAnno))
                if options.showAnnotations { out.append(.text(TextGeom(position: c, height: 350 * u, content: g.label, halign: .center, valign: .middle), font: font(doc), color: color)) }
            }
            return out
        }
    }

    /// Label height for a component: fits inside the footprint (width along the rotation), never larger than
    /// 120 mm on plan; nil when the label would be too small to read.
    static func componentLabelHeight(_ g: ComponentGeom, label: String, unit u: Double) -> Double? {
        let chars = Double(max(label.count, 1))
        let w = abs(g.size.x), d = abs(g.size.y)
        let th = min(d * 0.28, 0.85 * w / (0.62 * chars), 120 * u)
        return th >= 35 * u ? th : nil
    }

    /// Slope arrow across a sloped slab or ramp: from the low side to the high side through the most open point,
    /// labelled with the gradient ("UP 1:12  8.3%" for ramps).
    static func slopeArrow(_ g: SlabGeom, el: BIMElement, doc: ArchiDocument, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let u = unit(doc)
        let d = Vec2(cos(g.slopeDirection), sin(g.slopeDirection)) * (g.slope >= 0 ? 1 : -1)
        let c = LabelPlacement.pole(of: g.boundary).point
        // Extent of the slab along the arrow through c.
        var t0 = 0.0, t1 = 0.0
        let far = BBox2(points: g.boundary).width + BBox2(points: g.boundary).height
        for (a, b) in RG.clipSegment(c - d * far, c + d * far, [g.boundary]) {
            let ta = (a - c).dot(d), tb = (b - c).dot(d)
            if min(ta, tb) <= 1e-9 && max(ta, tb) >= -1e-9 { t0 = min(ta, tb); t1 = max(ta, tb) }
        }
        let len = t1 - t0
        guard len > 1e-9 else { return [] }
        let a = c + d * (t0 + len * 0.1), b = c + d * (t1 - len * 0.1)
        var out: [DrawItem] = [stroke([a, b], color, lwAnno), .fill(loops: [RG.triangleArrow(tip: b, dir: d, size: min(200 * u, len * 0.15))], color: color)]
        if options.showAnnotations {
            let gr = abs(tan(rad(g.slope)))
            let label = (el.props["kind"] == "ramp" ? "UP " : "") + (gr > 1e-9 ? "1:\(fmt(1 / gr, 1))  " : "") + String(format: "%.1f%%", gr * 100)
            let rot = DimensionRenderer.readable(d.angle)
            out.append(.text(TextGeom(position: (a + b) / 2 + d.perp * (60 * u), height: 150 * u, content: label, rotation: rot, halign: .center, valign: .bottom), font: font(doc), color: color))
        }
        return out
    }

    /// Slope arrows on sloped roof faces (pointing up-slope, labelled with the pitch).
    static func roofSlopeArrows(_ g: RoofGeom, faces: [RoofFace], doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        let u = unit(doc)
        var out: [DrawItem] = []
        for f in faces where f.grad.length > 1e-9 && f.poly.count >= 3 {
            let d = f.grad.normalized
            let pole = LabelPlacement.pole(of: f.poly)
            let len = min(1200 * u, max(pole.radius * 1.4, 300 * u))
            guard pole.radius > 150 * u else { continue }
            let a = pole.point - d * (len / 2), b = pole.point + d * (len / 2)
            out.append(stroke([a, b], color, lwAnno))
            out.append(.fill(loops: [RG.triangleArrow(tip: b, dir: d, size: min(180 * u, len * 0.25))], color: color))
            let rot = DimensionRenderer.readable(d.angle)
            let pitch = atan(f.grad.length) * 180 / .pi
            out.append(.text(TextGeom(position: pole.point + d.perp * (90 * u), height: 140 * u, content: fmt(pitch, 1) + "°", rotation: rot, halign: .center, valign: .bottom), font: font(doc), color: color))
        }
        return out
    }

    /// Footprints on the same level that room tags should avoid (furniture, columns, stairs).
    static func tagObstacles(level: Int, near box: BBox2, doc: ArchiDocument) -> [[Vec2]] {
        var out: [[Vec2]] = []
        for el in doc.elements where el.level == level {
            switch el.geometry {
            case .component(let c): out.append(componentPoly(c))
            case .column(let c): out.append(c.round ? RG.circle(c.position, max(c.width, 0) / 2, segments: 16) : columnPoly(c))
            case .stair(let st): out += StairShapes.layout(st).treads.map(\.poly)
            default: continue
            }
        }
        return out.filter { $0.count >= 3 && BBox2(points: $0).intersects(box) }
    }

    /// Room fill (subtle tint), and a name/number/area tag at the room's most open point, clear of furniture.
    static func spaceItems(_ el: BIMElement, _ g: SpaceGeom, ctx: BIMContext, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let doc = ctx.doc
        let u = unit(doc)
        let tint = blend(color, RGBA(1, 1, 1), 0.3)
        var out: [DrawItem]
        if let c = AreaColors.color(el, doc: doc) { out = [.fill(loops: [g.boundary], color: RGBA(c.r, c.g, c.b, 0.45))] }
        else if options.reflectedCeiling { out = [] }
        else { out = [.fill(loops: [g.boundary], color: RGBA(tint.r, tint.g, tint.b, 0.06))] }
        if el.props["areaScheme"] != nil { out.append(stroke(g.boundary, closed: true, color, lwFine, hiddenDash(doc, options))) }
        guard options.showAnnotations, el.props["tag"] != "0" else { return out }
        let name = g.name.isEmpty ? el.name : g.name
        var line2 = g.number
        let area = formatArea(abs(GeometryOps.signedArea(g.boundary)), doc)
        line2 = line2.isEmpty ? area : line2 + "  " + area
        let box = BBox2(points: g.boundary)
        let placed: (point: Vec2, radius: Double)
        if let x = el.props["tagX"].flatMap(Double.init), let y = el.props["tagY"].flatMap(Double.init) {
            placed = (Vec2(x, y), LabelPlacement.signedDistance(Vec2(x, y), g.boundary))
        } else {
            placed = labelPole(g.boundary, obstacles: tagObstacles(level: el.level, near: box, doc: doc))
        }
        let th = LabelPlacement.fittedTextHeight(lines: [name.count, line2.count], lineSpacing: 1.5, radius: max(placed.radius, 1e-6),
                                                 maxHeight: 220 * u, minHeight: 60 * u)
        let th2 = th * 0.72
        let tagColor = blend(color, RGBA(0.72, 0.74, 0.78, color.a), 0.65)
        let f = font(doc)
        let c = placed.point
        out.append(.text(TextGeom(position: c + Vec2(0, th * 0.15), height: th, content: name, halign: .center, valign: .bottom), font: f, color: tagColor))
        out.append(.text(TextGeom(position: c - Vec2(0, th * 0.15), height: th2, content: line2, halign: .center, valign: .top), font: f, color: tagColor))
        return out
    }

    private static let poleLock = NSLock()
    private static var poleCache: [[Double]: (Vec2, Double)] = [:]

    /// Cached pole of inaccessibility (room tags are rebuilt on every redraw).
    static func labelPole(_ boundary: [Vec2], obstacles: [[Vec2]]) -> (point: Vec2, radius: Double) {
        var key: [Double] = []
        for p in boundary { key += [p.x, p.y] }
        key.append(.nan)
        for o in obstacles { for p in o { key += [p.x, p.y] }; key.append(.infinity) }
        let k2 = key.map { $0.isNaN ? -9.87654321e300 : $0 }
        poleLock.lock()
        if let hit = poleCache[k2] { poleLock.unlock(); return hit }
        poleLock.unlock()
        let inside = obstacles.filter { o in o.contains { GeometryOps.pointInPolygon($0, boundary) } }
        var r = LabelPlacement.pole(of: boundary, avoiding: inside)
        if r.radius <= 0 { r = LabelPlacement.pole(of: boundary) }
        poleLock.lock()
        if poleCache.count > 4000 { poleCache.removeAll() }
        poleCache[k2] = (r.point, r.radius)
        poleLock.unlock()
        return r
    }

    // MARK: Walls

    static func splitByGaps(_ pts: [Vec2], side: Double, f: WallFrame, gaps: [(side: Double, s0: Double, s1: Double)]) -> [[Vec2]] {
        let gs = gaps.filter { $0.side == side }
        guard !gs.isEmpty, pts.count >= 2 else { return [pts] }
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
        // Detail level (DOC-023): coarse views show walls as a solid poché without layers or patterns.
        let coarse = FamilyVisibility.level(doc) == "coarse"
        if coarse {
            plies = [(el.material, f.h, -f.h)]
        } else if let tn = f.g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), wt.thickness > 0, !wt.plies.isEmpty {
            let k = 2 * f.h / wt.thickness
            var t = f.h
            for p in wt.plies { let nt = t - p.thickness * k; plies.append((p.material, t, nt)); t = nt }
        } else { plies = [(el.material, f.h, -f.h)] }
        let firstMat = doc.material(plies.first?.material ?? el.material)
        let fill = coarse ? blend(color, cutFill, 0.35) : blend(cutFill, firstMat?.color ?? cutFill, plies.count > 1 ? 0.15 : 0.25)
        var fills: [DrawItem] = [], patterns: [DrawItem] = [], lines: [DrawItem] = []
        let patColor = blend(color, fill, 0.35)
        // Seen from another level (a wall rising through it), only openings crossing that level's cut plane break the wall.
        var only: Set<EntityID>? = nil
        if let l = options.level, l != el.level {
            only = Set((ctx.openings[el.id] ?? []).filter { BIMConstraints.shown($0, onLevel: l, doc: doc) }.map(\.id))
        }
        let cuts = ctx.cuts(f, only: only)
        let cutStarts = cuts.map(\.s0), cutEnds = cuts.map(\.s1)
        let wrap = layerWrap(el, plies: plies, doc: doc, h: f.h)
        for pc in ctx.pieces(f, only: only) {
            fills.append(.fill(loops: [pc.poly], color: fill))
            if options.cutHatches && !coarse {
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
            // Ply boundary lines; with layer wrapping at inserts (WALLWRAP = 1 or props wrapInserts = 1) the finish layers
            // return into the opening jambs and the inner ply lines stop short of them.
            if plies.count > 1 {
                let w = wrap.enabled && !f.isCurved ? wrap.width : 0
                let cutStart = w > 0 && cutEnds.contains { abs($0 - pc.s0) < 1e-6 }, cutEnd = w > 0 && cutStarts.contains { abs($0 - pc.s1) < 1e-6 }
                let lo = pc.s0 + (cutStart ? w : 0), hi = pc.s1 - (cutEnd ? w : 0)
                for ply in plies.dropLast() {
                    let line = f.isCurved ? f.face(ply.tlo, pc.s0, pc.s1) : [f.pt(pc.s0 - 10 * f.h - 1, ply.tlo), f.pt(pc.s1 + 10 * f.h + 1, ply.tlo)]
                    for s in RG.clipPolyline(line, [pc.poly]) {
                        guard w > 0, s.count == 2 else { lines.append(stroke(s, color, lwFine)); continue }
                        let sa = f.sOf(s[0]), sb = f.sOf(s[1])
                        let a = max(min(sa, sb), lo), b = min(max(sa, sb), hi)
                        if b - a > 1e-9 { lines.append(stroke([f.pt(a, ply.tlo), f.pt(b, ply.tlo)], color, lwFine)) }
                    }
                }
                if cutStart && hi > lo { lines.append(stroke([f.pt(lo, wrap.top), f.pt(lo, wrap.bottom)], color, lwFine)) }
                if cutEnd && hi > lo { lines.append(stroke([f.pt(hi, wrap.top), f.pt(hi, wrap.bottom)], color, lwFine)) }
            }
            for s in splitByGaps(pc.faceR, side: -1, f: f, gaps: j.gaps) { lines.append(stroke(s, color, lwCut)) }
            for s in splitByGaps(pc.faceL, side: 1, f: f, gaps: j.gaps) { lines.append(stroke(s, color, lwCut)) }
            if pc.startEdgeVisible { lines.append(stroke([pc.faceL[0], pc.faceR[0]], color, lwCut)) }
            if pc.endEdgeVisible { lines.append(stroke([pc.faceR[pc.faceR.count - 1], pc.faceL[pc.faceL.count - 1]], color, lwCut)) }
        }
        var all = fills + patterns + lines
        // Slanted/tapered walls (BIM-023) are drawn where the plan cut plane passes through them.
        if f.g.isSlantedOrTapered {
            let range = BIMConstraints.wallRange(el, doc: doc)
            let zc = (doc.level(options.level ?? el.level)?.elevation ?? 0) + BIMConstraints.cutHeight(doc)
            if let m = WallShapes.mapper(f.g, f: f, zBase: range.z0, height: range.z1 - range.z0) {
                let z = min(max(zc, range.z0), range.z1)
                all = all.map { it in
                    switch it {
                    case .stroke(let p, let c, let st): return .stroke(points: p.map { m($0, z) }, closed: c, style: st)
                    case .fill(let l, let c): return .fill(loops: l.map { $0.map { m($0, z) } }, color: c)
                    default: return it
                    }
                }
            }
        }
        return all
    }

    /// Floor finish tile grid ("600x600") clipped to the finish outline, starting from the boundary's lower-left corner.
    static func tileGrid(_ spec: String, boundary: [Vec2], holes: [[Vec2]], doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return [] }
        let u = unit(doc)
        let tx = parts[0] * u, ty = parts[1] * u
        let b = BBox2(points: boundary)
        guard b.width / tx < 400, b.height / ty < 400 else { return [] }
        let loops = [boundary] + holes
        var out: [DrawItem] = []
        let c = blend(color, RGBA(0.6, 0.6, 0.6, color.a), 0.5)
        var x = b.min.x + tx
        while x < b.max.x - 1e-9 { for (p, q) in RG.clipSegment(Vec2(x, b.min.y), Vec2(x, b.max.y), loops) { out.append(stroke([p, q], c, lwFine)) }; x += tx }
        var y = b.min.y + ty
        while y < b.max.y - 1e-9 { for (p, q) in RG.clipSegment(Vec2(b.min.x, y), Vec2(b.max.x, y), loops) { out.append(stroke([p, q], c, lwFine)) }; y += ty }
        return out
    }

    /// Layer wrapping at inserts: the finish plies on each face return into opening jambs. `width` = wrap depth into
    /// the jamb (the exterior finish thickness), `top`/`bottom` = the core band the return line spans (wall t offsets).
    static func layerWrap(_ el: BIMElement, plies: [(material: String?, thi: Double, tlo: Double)], doc: ArchiDocument, h: Double)
        -> (enabled: Bool, width: Double, top: Double, bottom: Double) {
        let on = el.props["wrapInserts"] == "1" || (el.props["wrapInserts"] != "0" && doc.variable("WALLWRAP") == "1")
        guard on, plies.count > 1, case .wall(let g) = el.geometry, let tn = g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), wt.thickness > 0 else {
            return (false, 0, 0, 0)
        }
        let k = 2 * h / wt.thickness
        let lead = wt.plies.prefix { $0.function == "Finish" }.reduce(0) { $0 + $1.thickness } * k
        let trail = wt.plies.reversed().prefix { $0.function == "Finish" }.reduce(0) { $0 + $1.thickness } * k
        guard lead + trail > 1e-9, lead + trail < 2 * h - 1e-9 else { return (false, 0, 0, 0) }
        return (true, max(lead, trail), h - lead, -h + trail)
    }

    // MARK: Openings

    static func openingItems(_ el: BIMElement, _ o: OpeningGeom, ctx: BIMContext, color: RGBA, options: DrawOptions) -> [DrawItem] {
        openingSymbol(el, o, ctx: ctx, color: color, options: options) + OpeningTrim.planItems(el, o, ctx: ctx, color: color, options: options)
    }

    static func openingSymbol(_ el: BIMElement, _ o: OpeningGeom, ctx: BIMContext, color: RGBA, options: DrawOptions) -> [DrawItem] {
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
            let coarse = FamilyVisibility.level(doc) == "coarse"
            if fw > 0 && !coarse { out.append(stroke(rect(s0, a, -h, h), closed: true, color, lwProj)); out.append(stroke(rect(b, s1, -h, h), closed: true, color, lwProj)) }
            else { out.append(stroke([P(s0, -h), P(s0, h)], color, lwProj)); out.append(stroke([P(s1, -h), P(s1, h)], color, lwProj)) }
            let lf = b - a
            if o.threshold && !coarse { out.append(stroke(rect(a, b, -h, h), closed: true, color, lwFine)) }
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
            if o.variant == .pocket {
                // Pocket door: the leaf slides into a cavity inside the wall beside the opening (dashed pocket).
                let dash = hiddenDash(doc, options)
                let pt = min(40 * u, h * 0.6)
                let (p0, p1) = o.flipHand ? (s1, s1 + lf) : (s0 - lf, s0)
                out.append(stroke(rect(p0, p1, -pt / 2 - 5 * u, pt / 2 + 5 * u), closed: true, color, lwHidden, dash))
                out.append(stroke(rect(a, b, -pt / 2, pt / 2), closed: true, color, lwProj))
                let ay = side * (h + 150 * u)
                let from = o.flipHand ? a + lf * 0.2 : b - lf * 0.2, to = o.flipHand ? b + lf * 0.2 : a - lf * 0.2
                out.append(stroke([P(from, ay), P(to, ay)], color, lwFine))
                out.append(.fill(loops: [RG.triangleArrow(tip: P(to, ay), dir: (P(to, ay) - P(from, ay)).normalized, size: 120 * u)], color: color))
                return out
            }
            if o.variant == .biFold {
                // Bi-fold: panels folded open in a zig-zag, stacking towards the hinge jamb(s).
                let n = max(2, min(8, Int((lf / (450 * u)).rounded())))
                let panels = n % 2 == 0 ? n : n + 1
                let q = lf / Double(panels), th = Double.pi / 3
                var zig: [Vec2] = []
                for k in 0...panels {
                    let x = a + lf * Double(k) / Double(panels)
                    zig.append(P(x, side * (h + (k % 2 == 1 ? q * sin(th) : 0))))
                }
                out.append(stroke(zig, color, lwProj))
                out.append(stroke([P(a, side * h), P(b, side * h)], color, lwHidden, hiddenDash(doc, options)))
                return out
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
            if FamilyVisibility.level(doc) == "coarse" {
                // Coarse: the wall faces and one glazing line.
                out.append(stroke([P(s0, 0), P(s1, 0)], color, lwHidden))
                return out
            }
            let fd = min(h, 35 * u)
            if fw > 0 { out.append(stroke(rect(s0, a, -fd, fd), closed: true, color, lwProj)); out.append(stroke(rect(b, s1, -fd, fd), closed: true, color, lwProj)) }
            let g = min(h * 0.3, 8 * u)
            if o.mullions > 0 {
                let bw = max(fw * 0.6, 20 * u) / 2
                for k in 0..<o.mullions {
                    let x = a + (b - a) * Double(k + 1) / Double(o.mullions + 1)
                    out.append(stroke(rect(x - bw, x + bw, -fd * 0.8, fd * 0.8), closed: true, color, lwProj))
                }
            }
            if o.variant == .pivot {
                // Centre-pivot sash: the sash drawn turned about its middle, with dashed arcs of the swing.
                let c = P((a + b) / 2, 0), half = (b - a) / 2, ang = Double.pi / 6
                let t0 = f.tangent(o.offset), n0 = t0.perp
                let d = t0 * cos(ang) + n0 * sin(ang)
                out.append(stroke([c - d * half, c + d * half], color, lwProj))
                for sgn in [1.0, -1.0] {
                    let arc = (0...12).map { i -> Vec2 in let phi = ang * Double(i) / 12; return c + (t0 * cos(phi) + n0 * sin(phi)) * (sgn * half) }
                    out.append(stroke(arc, color, lwHidden))
                }
            } else if o.variant == .tiltTurn {
                // Tilt-turn: casement swing towards the room plus a tilt mark (dashed chevron) on the sash.
                let room: Double = o.flipFacing ? -1 : 1
                let (hs, sg): (Double, Double) = o.flipHand ? (b, -1) : (a, 1)
                let len = b - a
                let arc = (0...24).map { i -> Vec2 in let phi = Double.pi / 2 * Double(i) / 24; return P(hs + sg * len * sin(phi), room * (h + len * cos(phi))) }
                out.append(stroke([P(hs, room * h), P(hs, room * (h + len))], color, lwProj))
                out.append(stroke(arc, color, lwHidden))
                out.append(stroke([P(a, room * g), P((a + b) / 2, room * (g + min(h, 60 * u))), P(b, room * g)], color, lwHidden, hiddenDash(doc, options)))
            }
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
            if o.isNiche && o.depth < 2 * h - 1e-9 {
                // Recess: the back of the wall stays cut (filled), the recess outline is drawn.
                let fromLeft = o.flipFacing
                let t0 = fromLeft ? -h : -h + o.depth, t1 = fromLeft ? h - o.depth : h
                let back = f.face(t0, s0, s1) + f.face(t1, s0, s1).reversed()
                let tr = fromLeft ? t1 : t0
                out.append(.fill(loops: [back], color: blend(cutFill, color, 0.2)))
                out.append(stroke(f.face(tr, s0, s1), color, lwCut))
                out.append(stroke(f.face(fromLeft ? t0 : t1, s0, s1), color, lwCut))
                let front = fromLeft ? h : -h
                out.append(stroke([P(s0, front), P(s0, tr)], color, lwCut))
                out.append(stroke([P(s1, front), P(s1, tr)], color, lwCut))
            } else {
                out.append(stroke([P(s0, -h), P(s1, h)], color, lwHidden, hiddenDash(doc, options)))
            }
        }
        return out
    }

    // MARK: Stairs

    /// A stair seen from the level it arrives at: every tread in projection and a "DN" walk line.
    static func upperStairItems(_ g: StairGeom, doc: ArchiDocument, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let l = StairShapes.layout(g)
        guard !l.treads.isEmpty else { return [] }
        let u = unit(doc)
        var out: [DrawItem] = l.treads.map { stroke($0.poly, closed: true, color, lwProj) }
        for nw in l.newels {
            let s = 50 * u
            out.append(stroke([nw + Vec2(-s, -s), nw + Vec2(s, -s), nw + Vec2(s, s), nw + Vec2(-s, s)], closed: true, color, lwProj))
        }
        let w = Array(l.walk.reversed())
        if w.count >= 2 {
            let last = w[w.count - 1], prev = w[w.count - 2]
            out.append(stroke(w, color, lwAnno))
            out.append(.fill(loops: [RG.triangleArrow(tip: last, dir: (last - prev).normalized, size: min(150 * u, g.treadDepth * 0.6))], color: color))
            if options.showAnnotations {
                let d0 = (w[1] - w[0]).normalized
                let rot = DimensionRenderer.readable(d0.angle)
                let flipped = abs(normAngle(rot - d0.angle)) > 1e-6
                out.append(.text(TextGeom(position: w[0] - d0 * (80 * u), height: 200 * u, content: "DN", rotation: rot,
                                          halign: flipped ? .left : .right, valign: .middle), font: font(doc), color: color))
            }
        }
        return out
    }

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
        for nw in l.newels {
            let s = 50 * u
            out.append(stroke([nw + Vec2(-s, -s), nw + Vec2(s, -s), nw + Vec2(s, s), nw + Vec2(-s, s)], closed: true, color, lwProj))
        }
        if g.kind == .spiral { out.append(stroke(RG.circle(g.start, max(40 * u, g.spiralInnerRadius * 0.6), segments: 32), closed: true, color, lwProj)) }
        // Break line across the cut tread (winders: along their riser, the ray from the newel).
        if let ct = l.treads.first(where: { $0.step == cutStep && !$0.landing }), ct.poly.count >= (ct.winder ? 3 : 4), cutStep < l.treads.count {
            let A = ct.winder ? ct.poly[0] : ct.poly[1], B = ct.winder ? ct.poly[1] : ct.poly[ct.poly.count - 1]
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
