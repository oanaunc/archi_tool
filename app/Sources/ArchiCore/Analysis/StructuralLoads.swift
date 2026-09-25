// Oanarina Archi Tool — GPL-3.0-or-later
// Loads and boundary conditions (ANL-032): point, line and area loads and supports drawn on layer S-LOADS (props
// structLoad / structSupport) are attached to the analytical model — point loads to the nearest node (or split to a
// beam's end nodes by the lever rule), line loads to collinear beams as uniform member loads, area loads to the nodes
// inside their outline (else to the slab under them), supports to the nearest node. The model exports to OpenSees
// (Tcl: nodes, fixities, elasticBeamColumn elements, a load pattern and a linear static analysis).
import Foundation

public enum StructuralLoads {
    public static let layer = "S-LOADS"

    /// Support codes: fixed, pinned, roller (vertical only) or six 0/1 digits (ux uy uz rx ry rz).
    public static func supportFlags(_ code: String) -> [Bool]? {
        switch code.lowercased() {
        case "fixed", "fix", "f": return Array(repeating: true, count: 6)
        case "pinned", "pin", "p", "hinge": return [true, true, true, false, false, false]
        case "roller", "r": return [false, false, true, false, false, false]
        case "free": return Array(repeating: false, count: 6)
        default:
            let c = Array(code)
            guard c.count == 6, c.allSatisfy({ $0 == "0" || $0 == "1" }) else { return nil }
            return c.map { $0 == "1" }
        }
    }

    /// Global load vector of an entity (props fx, fy, fz; gravity is negative z).
    static func vector(_ e: Entity) -> Vec3 {
        Vec3(Double(e.props["fx"] ?? "") ?? 0, Double(e.props["fy"] ?? "") ?? 0, Double(e.props["fz"] ?? "") ?? 0)
    }

    /// Attaches the drawing's loads and supports to the model. Distances in metres.
    public static func apply(_ doc: ArchiDocument, to m: inout AnalyticalModel, tolerance: Double = 0.3) {
        let u = doc.units.mm / 1000
        func zRange(_ e: Entity) -> ClosedRange<Double> {
            let lv = Int(e.props["level"] ?? "").flatMap { doc.level($0) } ?? doc.level(doc.currentLevel) ?? doc.levels.first
            let z0 = (lv?.elevation ?? 0) * u
            let z1 = z0 + (lv?.height ?? 3000) * u
            return (z0 - tolerance)...(z1 + tolerance)
        }
        func nodes(in r: ClosedRange<Double>) -> [AnalyticalNode] { m.nodes.filter { r.contains($0.p.z) } }
        func beams(in r: ClosedRange<Double>) -> [AnalyticalMember] {
            m.members.filter { mem in
                let a = m.nodes[mem.start - 1].p, b = m.nodes[mem.end - 1].p
                return r.contains(a.z) && r.contains(b.z) && Vec2(a.x - b.x, a.y - b.y).length > 1e-6
            }
        }
        func plan(_ p: Vec3) -> Vec2 { Vec2(p.x, p.y) }
        /// Inside or on the outline (within the snap tolerance).
        func within(_ q: Vec2, _ loop: [Vec2]) -> Bool {
            GeometryOps.pointInPolygon(q, loop) || GeometryOps.distance(from: q, toPolyline: loop + [loop[0]]) <= tolerance
        }

        for e in doc.entities {
            if let code = e.props["structSupport"], case .point(let p0) = e.geometry {
                guard let flags = supportFlags(code) else { m.warnings.append("Support #\(e.id): unknown code \(code)."); continue }
                let p = p0 * u, r = zRange(e)
                // Nearest node in plan; among equals the lowest in the level band.
                let cand = m.nodes.filter { plan($0.p).distance(to: p) <= tolerance && $0.p.z <= r.upperBound }
                guard let n = cand.min(by: { a, b in
                    let da = plan(a.p).distance(to: p), db = plan(b.p).distance(to: p)
                    return abs(da - db) > 1e-9 ? da < db : a.p.z < b.p.z
                }) else { m.warnings.append("Support #\(e.id) is not at a node of the frame."); continue }
                m.nodes[n.id - 1].support = zip(m.nodes[n.id - 1].support, flags).map { $0 || $1 }
                continue
            }
            guard let kind = e.props["structLoad"] else { continue }
            let w = vector(e)
            guard w.length > 0 else { continue }
            let r = zRange(e)
            let lc = e.props["loadCase"] ?? ""
            switch (kind, e.geometry) {
            case ("point", .point(let p0)):
                let p = p0 * u
                if let n = nodes(in: r).filter({ plan($0.p).distance(to: p) <= tolerance }).max(by: { $0.p.z < $1.p.z }) {
                    m.nodeLoads.append(NodeLoad(node: n.id, force: w, moment: .zero, loadCase: lc))
                } else if let (mem, t) = beams(in: r).compactMap({ mem -> (AnalyticalMember, Double)? in
                    let a = plan(m.nodes[mem.start - 1].p), b = plan(m.nodes[mem.end - 1].p)
                    let d = b - a, t = max(0, min(1, (p - a).dot(d) / d.dot(d)))
                    return (a + d * t).distance(to: p) <= tolerance ? (mem, t) : nil
                }).first {
                    // Lever rule: statically equivalent end forces.
                    m.nodeLoads.append(NodeLoad(node: mem.start, force: w * (1 - t), moment: .zero, loadCase: lc))
                    m.nodeLoads.append(NodeLoad(node: mem.end, force: w * t, moment: .zero, loadCase: lc))
                } else { m.warnings.append("Point load #\(e.id) is not on a node or beam; ignored.") }
            case ("line", .line), ("line", .polyline):
                let pts: [Vec2]
                if case .line(let l) = e.geometry { pts = [l.a * u, l.b * u] } else { pts = GeometryOps.tessellate(e.geometry, doc: doc).first?.map { $0 * u } ?? [] }
                var unattached = 0.0
                for i in 0..<max(pts.count - 1, 0) {
                    let s0 = pts[i], s1 = pts[i + 1]
                    let segL = s0.distance(to: s1)
                    guard segL > 1e-9 else { continue }
                    var covered = 0.0
                    for mem in beams(in: r) {
                        let a = plan(m.nodes[mem.start - 1].p), b = plan(m.nodes[mem.end - 1].p)
                        let d = b - a, L = d.length
                        let dir = d * (1 / L)
                        // Collinear: both segment ends on the beam's line.
                        func off(_ q: Vec2) -> Double { abs((q - a).cross(dir)) }
                        guard off(s0) <= tolerance, off(s1) <= tolerance else { continue }
                        let t0 = (s0 - a).dot(dir), t1 = (s1 - a).dot(dir)
                        let overlap = max(0, min(max(t0, t1), L) - max(min(t0, t1), 0))
                        guard overlap > 1e-9 else { continue }
                        // Equivalent uniform load over the whole member (same total).
                        m.memberLoads[mem.id] = (m.memberLoads[mem.id] ?? .zero) + w * (overlap / L)
                        m.memberLoadCases[mem.id, default: []].append(lc)
                        covered += overlap
                    }
                    unattached += max(0, segL - covered)
                }
                if unattached > tolerance { m.warnings.append("Line load #\(e.id): \(fmt(unattached, 2)) m are not over a beam; that part is ignored.") }
            case ("area", _):
                guard let loop = GeometryOps.tessellate(e.geometry, doc: doc).first?.map({ $0 * u }), loop.count >= 3 else { continue }
                let area = abs(GeometryOps.signedArea(loop))
                guard area > 1e-9 else { continue }
                let total = w * area
                var targets = nodes(in: r).filter { !$0.isSupported && within(plan($0.p), loop) }
                if targets.isEmpty {
                    // The slab panel under the load: its nodes inside the slab outline.
                    let c = GeometryOps.centroid(loop)
                    if let pi = m.panels.firstIndex(where: { $0.kind == "slab" && r.contains($0.outline.first?.z ?? -1e9) && GeometryOps.pointInPolygon(c, $0.outline.map(plan)) }) {
                        m.panels[pi].areaLoad += -w.z
                        targets = nodes(in: r).filter { !$0.isSupported && within(plan($0.p), m.panels[pi].outline.map(plan)) }
                    }
                }
                guard !targets.isEmpty else { m.warnings.append("Area load #\(e.id) (\(fmt(total.length, 1)) kN) has no frame nodes under it; ignored."); continue }
                for n in targets { m.nodeLoads.append(NodeLoad(node: n.id, force: total * (1 / Double(targets.count)), moment: .zero, loadCase: lc)) }
            default:
                m.warnings.append("Load #\(e.id): a \(kind) load must be a \(kind == "point" ? "point" : kind == "line" ? "line or polyline" : "closed outline").")
            }
        }
    }

    /// Sum of all applied loads (kN): nodal forces plus uniform member loads × length.
    public static func totalLoad(_ m: AnalyticalModel) -> Vec3 {
        var t = m.nodeLoads.reduce(Vec3.zero) { $0 + $1.force }
        for mem in m.members {
            guard let w = m.memberLoads[mem.id] else { continue }
            t = t + w * m.nodes[mem.start - 1].p.distance(to: m.nodes[mem.end - 1].p)
        }
        return t
    }

    /// OpenSees Tcl input (units m, kN, kPa): nodes, fix, geomTransf + elasticBeamColumn per member, one load pattern with
    /// nodal loads and beamUniform element loads (local axes), a linear static analysis and reaction / displacement recorders.
    public static func openSeesTcl(_ m: AnalyticalModel, name: String = "Model") -> String {
        func n(_ v: Double) -> String { let s = fmt(v, 9); return s == "-0" ? "0" : s }
        var out = "# \(name) — analytical model from Oanarina Archi Tool (OpenSees Tcl). Units: m, kN, kPa.\n"
        out += "wipe\nmodel BasicBuilder -ndm 3 -ndf 6\n\n# Nodes\n"
        for node in m.nodes { out += "node \(node.id) \(n(node.p.x)) \(n(node.p.y)) \(n(node.p.z))\n" }
        out += "\n# Supports (ux uy uz rx ry rz)\n"
        for node in m.nodes where node.isSupported { out += "fix \(node.id) " + node.support.map { $0 ? "1" : "0" }.joined(separator: " ") + "\n" }
        // Nodes not connected to any member would make the system singular: fix them.
        let used = Set(m.members.flatMap { [$0.start, $0.end] })
        for node in m.nodes where !used.contains(node.id) && !node.isSupported { out += "fix \(node.id) 1 1 1 1 1 1 ;# not connected\n" }
        out += "\n# Members: geomTransf Linear tag vecxz; element elasticBeamColumn tag i j A E G J Iy Iz transf\n"
        var valid: [AnalyticalMember] = []
        for mem in m.members {
            let a = m.nodes[mem.start - 1].p, b = m.nodes[mem.end - 1].p
            guard a.distance(to: b) > 1e-9 else { continue }
            let ax = StructuralAnalysis.axes(a, b)
            out += "geomTransf Linear \(mem.id) \(n(ax[2].x)) \(n(ax[2].y)) \(n(ax[2].z))\n"
            out += "element elasticBeamColumn \(mem.id) \(mem.start) \(mem.end) \(n(mem.area)) \(n(mem.material.e * 1000)) \(n(mem.material.g * 1000)) \(n(mem.j)) \(n(mem.iy)) \(n(mem.iz)) \(mem.id) ;# \(mem.kind) #\(mem.element) \(mem.material.name)\n"
            valid.append(mem)
        }
        out += "\n# Loads\ntimeSeries Linear 1\npattern Plain 1 1 {\n"
        var byNode: [Int: (Vec3, Vec3)] = [:]
        for l in m.nodeLoads { let c = byNode[l.node] ?? (.zero, .zero); byNode[l.node] = (c.0 + l.force, c.1 + l.moment) }
        for (id, f) in byNode.sorted(by: { $0.key < $1.key }) {
            out += "    load \(id) \(n(f.0.x)) \(n(f.0.y)) \(n(f.0.z)) \(n(f.1.x)) \(n(f.1.y)) \(n(f.1.z))\n"
        }
        for mem in valid {
            guard let w = m.memberLoads[mem.id], w.length > 0 else { continue }
            let ax = StructuralAnalysis.axes(m.nodes[mem.start - 1].p, m.nodes[mem.end - 1].p)
            out += "    eleLoad -ele \(mem.id) -type -beamUniform \(n(w.dot(ax[1]))) \(n(w.dot(ax[2]))) \(n(w.dot(ax[0])))\n"
        }
        out += "}\n\n# Analysis\n"
        let supported = m.nodes.filter(\.isSupported).map { "\($0.id)" }.joined(separator: " ")
        if !supported.isEmpty { out += "recorder Node -file reactions.out -node \(supported) -dof 1 2 3 4 5 6 reaction\n" }
        out += "recorder Node -file displacements.out -nodeRange 1 \(max(m.nodes.count, 1)) -dof 1 2 3 disp\n"
        out += "constraints Plain\nnumberer RCM\nsystem BandGeneral\ntest NormDispIncr 1.0e-8 6\nalgorithm Linear\nintegrator LoadControl 1.0\nanalysis Static\nanalyze 1\nreactions\n"
        if !supported.isEmpty { out += "foreach n {\(supported)} { puts \"node $n reaction: [nodeReaction $n]\" }\n" }
        out += "puts \"done\"\n"
        return out
    }
}
