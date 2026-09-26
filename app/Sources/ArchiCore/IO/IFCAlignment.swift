// Oanarina Archi Tool — GPL-3.0-or-later
// IFC 4.3 alignments (IO-022 / IO-023): the semantic alignment layout — IfcAlignment nesting an IfcAlignmentHorizontal
// with IfcAlignmentSegment / IfcAlignmentHorizontalSegment design parameters (lines, circular arcs, clothoids and the
// other transition curves, approximated with a linear change of curvature) and an IfcAlignmentVertical (constant
// gradients, arcs and parabolic arcs) — is imported as a plan polyline on layer IFC-ALIGNMENT with the elevation along it
// (props "elevations", comma-separated per vertex), its length and the segment types. Radii follow IFC 4.3: positive to
// the left (counter-clockwise), zero for infinite.
import Foundation

public enum AlignmentGeometry {
    public struct Horizontal: Hashable {
        public var kind: String          // LINE, CIRCULARARC, CLOTHOID, CUBIC, …
        public var start: Vec2
        public var direction: Double     // radians from +X
        public var startRadius: Double   // 0 = infinite; positive = left
        public var endRadius: Double
        public var length: Double
        public init(kind: String, start: Vec2, direction: Double, startRadius: Double, endRadius: Double, length: Double) {
            self.kind = kind; self.start = start; self.direction = direction; self.startRadius = startRadius; self.endRadius = endRadius; self.length = length
        }
    }

    /// Points along a horizontal segment (start included, end included), no farther apart than `step` or 5° of turn.
    public static func sample(_ s: Horizontal, step: Double) -> [Vec2] {
        let L = max(s.length, 0)
        guard L > 0 else { return [s.start] }
        let k0 = s.startRadius == 0 ? 0 : 1 / s.startRadius
        var k1 = s.endRadius == 0 ? 0 : 1 / s.endRadius
        if s.kind == "CIRCULARARC" || s.kind == "LINE" { k1 = s.kind == "LINE" ? 0 : k0 }
        let k0e = s.kind == "LINE" ? 0 : k0
        let turn = abs(k0e) * L + abs(k1 - k0e) * L / 2
        let n = max(1, min(4000, Int(max(L / max(step, 1e-9), turn / (5 * .pi / 180)).rounded(.up))))
        if s.kind == "LINE" {
            let d = Vec2(cos(s.direction), sin(s.direction))
            return (0...n).map { s.start + d * (L * Double($0) / Double(n)) }
        }
        if s.kind == "CIRCULARARC", abs(k0e) > 1e-15 {
            let r = 1 / k0e
            let c = s.start + Vec2(-sin(s.direction), cos(s.direction)) * r
            let a0 = s.direction - .pi / 2 * (r > 0 ? 1 : -1)
            return (0...n).map { i in
                let a = a0 + (L * Double(i) / Double(n)) / r
                return c + Vec2(cos(a), sin(a)) * abs(r)
            }
        }
        // Transition curves: curvature linear in the arc length; θ(s) = θ0 + k0 s + (k1 − k0) s² / 2L, integrated
        // with Simpson's rule on sub-steps.
        func theta(_ t: Double) -> Double { s.direction + k0e * t + (k1 - k0e) * t * t / (2 * L) }
        var out = [s.start]
        var p = s.start
        let h = L / Double(n)
        for i in 0..<n {
            let a = Double(i) * h, m = a + h / 2, b = a + h
            let dx = h / 6 * (cos(theta(a)) + 4 * cos(theta(m)) + cos(theta(b)))
            let dy = h / 6 * (sin(theta(a)) + 4 * sin(theta(m)) + sin(theta(b)))
            p = p + Vec2(dx, dy)
            out.append(p)
        }
        return out
    }

    public struct Vertical: Hashable {
        public var start: Double, length: Double, height: Double, g0: Double, g1: Double
        public init(start: Double, length: Double, height: Double, g0: Double, g1: Double) { self.start = start; self.length = length; self.height = height; self.g0 = g0; self.g1 = g1 }
    }
    /// Height at a distance along the alignment (gradients change linearly: parabolic vertical curves).
    public static func height(_ v: [Vertical], at d: Double) -> Double? {
        guard let s = v.last(where: { $0.start <= d + 1e-9 }) ?? v.first else { return nil }
        let x = max(0, min(max(s.length, 0), d - s.start))
        let dg = s.length > 0 ? (s.g1 - s.g0) / s.length : 0
        return s.height + s.g0 * x + dg * x * x / 2 + (d - s.start > s.length ? (d - s.start - s.length) * s.g1 : 0)
    }
}

extension IFCReader {
    /// Nested children of an object in order (IfcRelNests).
    func nested(_ id: Int) -> [StepEntity] {
        f.all("IFCRELNESTS").filter { $0[4].ref == id }.flatMap { $0[5].refs.compactMap { f.entities[$0] } }
    }

    /// Imports IfcAlignment layouts as plan polylines; returns the alignment ids handled.
    func readAlignments() -> Set<Int> {
        let t = IFCSchemaTable.ifc4x3
        guard let hn = t.attributeNames("IFCALIGNMENTHORIZONTALSEGMENT"), let sn = t.attributeNames("IFCALIGNMENTSEGMENT"),
              let vn = t.attributeNames("IFCALIGNMENTVERTICALSEGMENT") else { return [] }
        func ix(_ names: [String], _ n: String) -> Int { names.firstIndex(of: n) ?? 0 }
        var handled = Set<Int>()
        for al in f.all("IFCALIGNMENT") {
            let world = al.args.count > 5 ? placement(al[5]) : .identity
            var horizontal: [AlignmentGeometry.Horizontal] = []
            var vertical: [AlignmentGeometry.Vertical] = []
            for layout in nested(al.id) {
                for seg in nested(layout.id) where seg.type == "IFCALIGNMENTSEGMENT" {
                    guard let dp = e(seg[ix(sn, "DesignParameters")]) else { continue }
                    if dp.type == "IFCALIGNMENTHORIZONTALSEGMENT", let p = point2(dp[ix(hn, "StartPoint")]) {
                        horizontal.append(AlignmentGeometry.Horizontal(kind: dp[ix(hn, "PredefinedType")].enumValue ?? "LINE", start: p,
                                                                       direction: (dp[ix(hn, "StartDirection")].double ?? 0) * angleScale,
                                                                       startRadius: (dp[ix(hn, "StartRadiusOfCurvature")].double ?? 0) * scale,
                                                                       endRadius: (dp[ix(hn, "EndRadiusOfCurvature")].double ?? 0) * scale,
                                                                       length: (dp[ix(hn, "SegmentLength")].double ?? 0) * scale))
                    } else if dp.type == "IFCALIGNMENTVERTICALSEGMENT" {
                        vertical.append(AlignmentGeometry.Vertical(start: (dp[ix(vn, "StartDistAlong")].double ?? 0) * scale, length: (dp[ix(vn, "HorizontalLength")].double ?? 0) * scale,
                                                                   height: (dp[ix(vn, "StartHeight")].double ?? 0) * scale,
                                                                   g0: dp[ix(vn, "StartGradient")].double ?? 0, g1: dp[ix(vn, "EndGradient")].double ?? 0))
                    }
                }
            }
            guard !horizontal.isEmpty else { continue }
            var pts: [Vec2] = [], dist: [Double] = []
            var along = 0.0
            for h in horizontal {
                let sp = AlignmentGeometry.sample(h, step: 1000)
                for (i, q) in sp.enumerated() {
                    let w = world.apply(Vec3(q.x, q.y, 0)).xy
                    if i == 0, let last = pts.last, last.distance(to: w) < 1e-6 { continue }
                    if let last = pts.last { along += last.distance(to: w) }
                    pts.append(w); dist.append(along)
                }
            }
            guard pts.count >= 2 else { continue }
            vertical.sort { $0.start < $1.start }
            var props = ["ifcType": "IFCALIGNMENT", "length": fmt(horizontal.reduce(0) { $0 + $1.length }, 3),
                         "segments": horizontal.map(\.kind).joined(separator: ",")]
            if let g = al[0].string { props["ifcGuid"] = g }
            if let n = al[2].string, !n.isEmpty { props["name"] = n }
            if !vertical.isEmpty { props["elevations"] = dist.map { fmt(AlignmentGeometry.height(vertical, at: $0) ?? 0, 3) }.joined(separator: ",") }
            doc.ensureLayer("IFC-ALIGNMENT")
            _ = doc.add(Entity(layer: "IFC-ALIGNMENT", geometry: .polyline(PolylineGeom(points: pts, closed: false)), props: props))
            bump("alignment")
            handled.insert(al.id)
            for layout in nested(al.id) { handled.insert(layout.id); for s in nested(layout.id) { handled.insert(s.id) } }
        }
        return handled
    }
}

extension IFCBuilder {
    /// Plan polylines that describe alignments: on a layer whose name contains "ALIGNMENT" or with props alignment = 1.
    static func alignmentSources(_ doc: ArchiDocument) -> [Entity] {
        doc.entities.filter { e in
            guard case .polyline(let p) = e.geometry, p.vertices.count >= 2, !p.closed else { return false }
            return e.layer.uppercased().contains("ALIGNMENT") || e.props["alignment"] == "1" || e.props["ifcType"] == "IFCALIGNMENT"
        }
    }

    /// IFC 4.3 alignments: IfcAlignment (aggregated into the project, placed on the site) nesting an IfcAlignmentHorizontal
    /// with one IfcAlignmentSegment per polyline segment (LINE, or CIRCULARARC for bulged segments) and, when the polyline
    /// carries "elevations", an IfcAlignmentVertical of constant-gradient segments; the plan curve is the 'Axis'
    /// representation. Returns the alignments (to aggregate into the project).
    func alignments(sitePlacement: Int) -> [Int] {
        let src = IFCBuilder.alignmentSources(doc)
        guard !src.isEmpty else { return [] }
        var ids: [Int] = []
        for (n, e) in src.enumerated() {
            guard case .polyline(let pl) = e.geometry else { continue }
            let key = "alignment:\(e.id)"
            let name = e.props["name"] ?? "Alignment \(n + 1)"
            let v = pl.vertices
            // Axis representation: the plan curve (arcs sampled).
            var axisPts: [Vec2] = []
            var hsegs: [Int] = []
            var along = 0.0
            var dists: [Double] = [0]
            for i in 0..<(v.count - 1) {
                let a = v[i].p * k, b = v[i + 1].p * k, bulge = v[i].bulge
                let chord = a.distance(to: b)
                guard chord > 1e-9 else { dists.append(along); continue }
                let dirChord = atan2(b.y - a.y, b.x - a.x)
                let seg: Int
                if abs(bulge) < 1e-9 {
                    seg = add("IFCALIGNMENTHORIZONTALSEGMENT($,$,#\(point2(a)),\(r(dirChord)),0.,0.,\(r(chord)),$,.LINE.)")
                    if axisPts.isEmpty { axisPts.append(a) }
                    axisPts.append(b)
                    along += chord
                } else {
                    let theta = 4 * atan(bulge)                   // signed sweep, CCW positive
                    let radius = chord / (2 * sin(abs(theta) / 2))
                    let startDir = dirChord - theta / 2
                    let len = radius * abs(theta)
                    seg = add("IFCALIGNMENTHORIZONTALSEGMENT($,$,#\(point2(a)),\(r(startDir)),\(r(theta > 0 ? radius : -radius)),\(r(theta > 0 ? radius : -radius)),\(r(len)),$,.CIRCULARARC.)")
                    let sp = AlignmentGeometry.sample(AlignmentGeometry.Horizontal(kind: "CIRCULARARC", start: a, direction: startDir, startRadius: theta > 0 ? radius : -radius,
                                                                                  endRadius: theta > 0 ? radius : -radius, length: len), step: max(len / 16, 1))
                    if axisPts.isEmpty { axisPts.append(a) }
                    axisPts += sp.dropFirst()
                    along += len
                }
                dists.append(along)
                hsegs.append(add("IFCALIGNMENTSEGMENT(\(g(key + ":h:\(i)")),#\(oh),$,$,$,$,$,#\(seg))"))
            }
            guard !hsegs.isEmpty else { continue }
            let horizontal = add("IFCALIGNMENTHORIZONTAL(\(g(key + ":h")),#\(oh),$,$,$,$,$)")
            add("IFCRELNESTS(\(g(key + ":nest:h")),#\(oh),$,$,#\(horizontal),\(refs(hsegs)))")
            var layouts = [horizontal]
            let z = (e.props["elevations"] ?? "").split(separator: ",").compactMap { Double($0) }
            if z.count == v.count {
                var vsegs: [Int] = []
                for i in 0..<(v.count - 1) where dists[i + 1] - dists[i] > 1e-9 {
                    let L = dists[i + 1] - dists[i], h0 = z[i] * k, g0 = (z[i + 1] - z[i]) * k / L
                    let seg = add("IFCALIGNMENTVERTICALSEGMENT($,$,\(r(dists[i])),\(r(L)),\(r(h0)),\(r(g0)),\(r(g0)),$,.CONSTANTGRADIENT.)")
                    vsegs.append(add("IFCALIGNMENTSEGMENT(\(g(key + ":v:\(i)")),#\(oh),$,$,$,$,$,#\(seg))"))
                }
                if !vsegs.isEmpty {
                    let vertical = add("IFCALIGNMENTVERTICAL(\(g(key + ":v")),#\(oh),$,$,$,$,$)")
                    add("IFCRELNESTS(\(g(key + ":nest:v")),#\(oh),$,$,#\(vertical),\(refs(vsegs)))")
                    layouts.append(vertical)
                }
            }
            let curve = add("IFCPOLYLINE(\(refs(axisPts.map { point2($0) })))")
            let rep = add("IFCSHAPEREPRESENTATION(#\(axisCtx),'Axis','Curve2D',(#\(curve)))")
            let pds = add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(rep)))")
            let place = add("IFCLOCALPLACEMENT(#\(sitePlacement),#\(add("IFCAXIS2PLACEMENT3D(#\(origin),$,$)")))")
            let al = add("IFCALIGNMENT(\(g(key)),#\(oh),\(s(name)),$,$,#\(place),#\(pds),.NOTDEFINED.)")
            add("IFCRELNESTS(\(g(key + ":nest")),#\(oh),$,$,#\(al),\(refs(layouts)))")
            ids.append(al)
        }
        return ids
    }
}
