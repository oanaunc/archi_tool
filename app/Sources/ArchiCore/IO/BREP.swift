// Oanarina Archi Tool — GPL-3.0-or-later
// OpenCASCADE BREP exchange (IO-042), the native ASCII format of OCCT ("CASCADE Topology V1/V2/V3").
// Export: each mesh group becomes a shell of planar faces (one plane surface, one wire of three straight edges per
// triangle; vertices and edges are shared so shells are closed where the mesh is) inside one compound, in millimetres.
// Import: the topology (compounds, solids, shells, faces, wires, edges, vertices with locations) is read; faces with a
// stored triangulation use it (curved faces keep their shape), others are triangulated from their wires (edges on lines,
// circles and ellipses are sampled; other curves use chords). Written from the published format description of
// OCCT's BRepTools_ShapeSet / GeomTools; no OCCT code is used.
import Foundation

public enum BREPExporter {
    public static func export(_ groups: [MeshGroup], unitMM: Double = 1) -> String {
        var curves: [String] = [], surfaces: [String] = [], shapes: [String] = []
        func r(_ v: Double) -> String {
            if v == 0 { return "0" }
            var s = String(format: "%.15g", v)
            if s == "-0" { s = "0" }
            return s
        }
        func v3(_ p: Vec3) -> String { "\(r(p.x)) \(r(p.y)) \(r(p.z))" }
        /// Shapes are referenced by reverse write order (the last written shape is 1): fix up at the end.
        var refs: [[Int]] = []   // per shape: indices (0-based write order) of its sub-shapes, with orientation sign
        var kinds: [String] = []
        var geoms: [String] = []
        var flags: [String] = []
        @discardableResult func addShape(_ kind: String, _ geom: String, _ flag: String, _ subs: [Int]) -> Int {
            kinds.append(kind); geoms.append(geom); flags.append(flag); refs.append(subs); return kinds.count - 1
        }
        var shells: [Int] = []
        for g in groups {
            let m = g.mesh
            let tris = MeshExport.triangles(m)
            guard !tris.isEmpty else { continue }
            let pos = m.positions.map { $0 * unitMM }
            // Weld coincident vertices so neighbouring triangles share edges.
            var weld: [String: Int] = [:], vIndex: [Int] = [], vShape: [Int] = []
            var vPoint: [Vec3] = []
            for p in pos {
                let key = "\(Int((p.x * 1000).rounded())),\(Int((p.y * 1000).rounded())),\(Int((p.z * 1000).rounded()))"
                if let i = weld[key] { vIndex.append(i) } else { weld[key] = vPoint.count; vIndex.append(vPoint.count); vPoint.append(p); vShape.append(-1) }
            }
            var edgeOf: [Int64: Int] = [:]
            var faces: [Int] = []
            var t = 0
            while t + 2 < tris.count {
                let a = vIndex[Int(tris[t])], b = vIndex[Int(tris[t + 1])], c = vIndex[Int(tris[t + 2])]
                t += 3
                let pa = vPoint[a], pb = vPoint[b], pc = vPoint[c]
                let n = (pb - pa).cross(pc - pa)
                guard a != b, b != c, a != c, n.length > 1e-12 else { continue }
                for i in [a, b, c] where vShape[i] < 0 {
                    vShape[i] = addShape("Ve", "1e-07\n\(v3(vPoint[i]))\n0 0\n", "0101101", [])
                }
                var wireSubs: [Int] = []
                for (s, e) in [(a, b), (b, c), (c, a)] {
                    let lo = min(s, e), hi = max(s, e)
                    let key = Int64(lo) << 32 | Int64(hi)
                    let edge: Int
                    if let x = edgeOf[key] { edge = x } else {
                        let p0 = vPoint[lo], p1 = vPoint[hi]
                        let len = (p1 - p0).length
                        curves.append("1 \(v3(p0)) \(v3((p1 - p0) / len))")
                        edge = addShape("Ed", " 1e-07 1 1 0\n1  \(curves.count) 0 0 \(r(len))\n0\n", "0101000", [vShape[lo] + 1, -(vShape[hi] + 1)])
                        edgeOf[key] = edge
                    }
                    wireSubs.append(s == min(s, e) ? edge + 1 : -(edge + 1))
                }
                let wire = addShape("Wi", "", "0101100", wireSubs)
                let nz = n.normalized
                let xd = (pb - pa).normalized
                let yd = nz.cross(xd)
                surfaces.append("1 \(v3(pa)) \(v3(nz)) \(v3(xd)) \(v3(yd))")
                faces.append(addShape("Fa", "0  1e-07 \(surfaces.count) 0\n", "0111000", [wire + 1]))
            }
            guard !faces.isEmpty else { continue }
            shells.append(addShape("Sh", "", "0101100", faces.map { $0 + 1 }))
        }
        let root = addShape("Co", "", "1101100", shells.map { $0 + 1 })
        let n = kinds.count
        func ref(_ s: Int) -> String { (s > 0 ? "+" : "-") + "\(n - (abs(s) - 1))" + " 0" }
        for i in 0..<n {
            shapes.append("\(kinds[i])\n\(geoms[i])\n\(flags[i])\n" + (refs[i].isEmpty ? "" : refs[i].map(ref).joined(separator: " ") + " ") + "*")
        }
        var out = "DBRep_DrawableShape\n\nCASCADE Topology V1, (c) Matra-Datavision\n"
        out += "Locations 0\nCurve2ds 0\nCurves \(curves.count)\n" + curves.map { $0 + "\n" }.joined()
        out += "Polygon3D 0\nPolygonOnTriangulations 0\nSurfaces \(surfaces.count)\n" + surfaces.map { $0 + "\n" }.joined()
        out += "Triangulations 0\n\nTShapes \(n)\n" + shapes.joined(separator: "\n\n") + "\n\n+\(n - root) 0\n"
        return out
    }
}

public enum BREPImporter {
    public struct BREPError: Error, LocalizedError { public let message: String; public var errorDescription: String? { "BREP: " + message } }

    /// 3×4 affine transform (row-major rotation + translation).
    struct Loc {
        var m: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]
        func apply(_ p: Vec3) -> Vec3 {
            Vec3(m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3], m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7], m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11])
        }
        static func * (a: Loc, b: Loc) -> Loc {   // a after b
            var o = Loc()
            for i in 0..<3 {
                for j in 0..<4 {
                    var s = 0.0
                    for k in 0..<3 { s += a.m[i * 4 + k] * b.m[k * 4 + j] }
                    if j == 3 { s += a.m[i * 4 + 3] }
                    o.m[i * 4 + j] = s
                }
            }
            return o
        }
        var inverse: Loc {
            // Rotation part inverse by general 3×3 inverse.
            let a = m[0], b = m[1], c = m[2], d = m[4], e = m[5], f = m[6], g = m[8], h = m[9], i = m[10]
            let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
            guard abs(det) > 1e-15 else { return Loc() }
            let r = [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
                     (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
                     (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
            let t = Vec3(m[3], m[7], m[11])
            var o = Loc()
            for row in 0..<3 {
                o.m[row * 4] = r[row * 3]; o.m[row * 4 + 1] = r[row * 3 + 1]; o.m[row * 4 + 2] = r[row * 3 + 2]
                o.m[row * 4 + 3] = -(r[row * 3] * t.x + r[row * 3 + 1] * t.y + r[row * 3 + 2] * t.z)
            }
            return o
        }
    }

    enum Curve { case line(Vec3, Vec3), circle(Vec3, Vec3, Vec3, Double), ellipse(Vec3, Vec3, Vec3, Double, Double), other
        func point(_ t: Double) -> Vec3? {
            switch self {
            case .line(let p, let d): return p + d * t
            case .circle(let c, let x, let y, let r): return c + x * (r * cos(t)) + y * (r * sin(t))
            case .ellipse(let c, let x, let y, let a, let b): return c + x * (a * cos(t)) + y * (b * sin(t))
            case .other: return nil
            }
        }
    }

    struct Shape {
        var kind = ""
        var point = Vec3.zero                 // vertex
        var curve = 0, curveLoc = 0, first = 0.0, last = 0.0   // edge 3D curve
        var triangulation = 0, faceLoc = 0    // face
        var subs: [(orient: Character, index: Int, loc: Int)] = []
    }

    struct Tri { var nodes: [Vec3]; var tris: [(Int, Int, Int)] }

    struct Tokens {
        var t: [Substring]; var i = 0
        var atEnd: Bool { i >= t.count }
        mutating func next() throws -> Substring { guard i < t.count else { throw BREPError(message: "unexpected end of file") }; defer { i += 1 }; return t[i] }
        mutating func num() throws -> Double { let s = try next(); guard let v = Double(s) else { throw BREPError(message: "expected a number, found '\(s)'") }; return v }
        mutating func int() throws -> Int { Int(try num()) }
        mutating func v3() throws -> Vec3 { Vec3(try num(), try num(), try num()) }
        func peek() -> Substring? { i < t.count ? t[i] : nil }
    }

    /// Reads a BREP file into mesh entities (drawing units = millimetres × 1/unitMM).
    public static func entities(_ text: String, unitMM: Double = 1, layer: String = "IMPORT-BREP") throws -> [Entity] {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let header = lines.first(where: { $0.contains("CASCADE Topology") }) else { throw BREPError(message: "not an OpenCASCADE BREP file") }
        let version = header.contains("V3") ? 3 : header.contains("V2") ? 2 : 1
        var tk = Tokens(t: text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }))
        // Skip to the Locations section.
        while let p = tk.peek(), p != "Locations" { tk.i += 1 }
        guard !tk.atEnd else { throw BREPError(message: "no Locations section") }
        _ = try tk.next()
        // Locations: 1 = elementary (12 numbers), 2 = composed (pairs index power, ending with 0).
        var locs: [Loc] = [Loc()]
        let nl = try tk.int()
        for _ in 0..<nl {
            let type = try tk.int()
            if type == 1 {
                var l = Loc(); for k in 0..<12 { l.m[k] = try tk.num() }; locs.append(l)
            } else {
                var l = Loc()
                while true {
                    let idx = try tk.int(); if idx == 0 { break }
                    let pw = try tk.int()
                    var b = idx < locs.count ? locs[idx] : Loc()
                    if pw < 0 { b = b.inverse }
                    for _ in 0..<abs(pw) { l = l * b }
                }
                locs.append(l)
            }
        }
        // Jump to Curves (Curve2ds are not needed).
        while let p = tk.peek(), p != "Curves" { tk.i += 1 }
        _ = try tk.next()
        var curves: [Curve] = [.other]
        let nc = try tk.int()
        for _ in 0..<nc { curves.append(try curve3D(&tk)) }
        // Triangulations.
        while let p = tk.peek(), p != "Triangulations" { tk.i += 1 }
        _ = try tk.next()
        var tris: [Tri] = [Tri(nodes: [], tris: [])]
        let nt = try tk.int()
        for _ in 0..<nt {
            let nn = try tk.int(), ntr = try tk.int()
            let hasUV = try tk.int() == 1
            var hasNormals = false
            if version >= 3 { hasNormals = try tk.int() == 1 }
            _ = try tk.num()   // deflection
            var nodes: [Vec3] = []; nodes.reserveCapacity(nn)
            for _ in 0..<nn { nodes.append(try tk.v3()) }
            if hasUV { for _ in 0..<(2 * nn) { _ = try tk.num() } }
            var tt: [(Int, Int, Int)] = []
            for _ in 0..<ntr { tt.append((try tk.int() - 1, try tk.int() - 1, try tk.int() - 1)) }
            if hasNormals { for _ in 0..<(3 * nn) { _ = try tk.num() } }
            tris.append(Tri(nodes: nodes, tris: tt))
        }
        while let p = tk.peek(), p != "TShapes" { tk.i += 1 }
        _ = try tk.next()
        let ns = try tk.int()
        var shapes: [Shape] = []
        shapes.reserveCapacity(ns)
        for _ in 0..<ns {
            var s = Shape()
            s.kind = String(try tk.next())
            switch s.kind {
            case "Ve":
                _ = try tk.num(); s.point = try tk.v3()
                while true {
                    let t = try tk.int()
                    if t == 0 { _ = try tk.next(); break }
                    for _ in 0..<(t == 1 ? 3 : 4) { _ = try tk.next() }
                }
            case "Ed":
                for _ in 0..<4 { _ = try tk.next() }
                while true {
                    let t = try tk.int()
                    if t == 0 { break }
                    switch t {
                    case 1: s.curve = try tk.int(); s.curveLoc = try tk.int(); s.first = try tk.num(); s.last = try tk.num()
                    case 2: for _ in 0..<5 { _ = try tk.next() }; if version >= 2 { for _ in 0..<4 { _ = try tk.next() } }
                    case 3: for _ in 0..<7 { _ = try tk.next() }; if version >= 2 { for _ in 0..<8 { _ = try tk.next() } }
                    case 4: for _ in 0..<5 { _ = try tk.next() }
                    case 5: for _ in 0..<2 { _ = try tk.next() }
                    case 6: for _ in 0..<3 { _ = try tk.next() }
                    case 7: for _ in 0..<4 { _ = try tk.next() }
                    default: throw BREPError(message: "unknown edge representation \(t)")
                    }
                }
            case "Fa":
                _ = try tk.next(); _ = try tk.next(); _ = try tk.next(); s.faceLoc = try tk.int()
                if tk.peek() == "2" { _ = try tk.next(); s.triangulation = try tk.int() }
            default: break
            }
            _ = try tk.next()   // flags
            while true {
                let r = try tk.next()
                if r == "*" { break }
                guard let o = r.first, let idx = Int(r.dropFirst()) else { throw BREPError(message: "bad shape reference '\(r)'") }
                let l = try tk.int()
                s.subs.append((o, idx, l))
            }
            shapes.append(s)
        }
        func shape(_ ref: Int) -> Shape? { let i = ns - ref; return i >= 0 && i < ns ? shapes[i] : nil }
        // Root(s).
        var roots: [(Int, Int)] = []
        while !tk.atEnd {
            let r = try tk.next()
            guard let idx = Int(r.dropFirst()) else { break }
            let l = tk.atEnd ? 0 : (Int(try tk.next()) ?? 0)
            roots.append((idx, l))
        }
        if roots.isEmpty, ns > 0 { roots = [(1, 0)] }

        func loc(_ i: Int) -> Loc { i > 0 && i < locs.count ? locs[i] : Loc() }
        func vertexPoint(_ ref: Int, _ l: Loc) -> Vec3? { shape(ref).map { l.apply($0.point) } }
        /// Points along an edge from its start to its end vertex (in the traversal location), reversed for "-".
        func edgePoints(_ ref: Int, orient: Character, _ l: Loc) -> [Vec3] {
            guard let e = shape(ref) else { return [] }
            var start: Vec3?, end: Vec3?
            for sub in e.subs {
                let p = vertexPoint(sub.index, l * loc(sub.loc))
                if sub.orient == "+" { start = p } else if sub.orient == "-" { end = p }
            }
            var pts: [Vec3] = []
            if let s = start { pts.append(s) }
            if e.curve > 0, e.curve < curves.count {
                let c = curves[e.curve]
                switch c {
                case .circle, .ellipse:
                    let segs = max(2, Int((abs(e.last - e.first) / (Double.pi / 16)).rounded(.up)))
                    for k in 1..<segs { if let p = c.point(e.first + (e.last - e.first) * Double(k) / Double(segs)) { pts.append((l * loc(e.curveLoc)).apply(p)) } }
                default: break
                }
            }
            if let en = end { pts.append(en) } else if start != nil, e.curve > 0, e.curve < curves.count, let p = curves[e.curve].point(e.last) { pts.append((l * loc(e.curveLoc)).apply(p)) }
            return orient == "-" ? pts.reversed() : pts
        }

        var positions: [Vec3] = [], indices: [Int] = []
        var groups: [(name: String, verts: [Vec3], tris: [Int])] = []
        func addFace(_ f: Shape, orient: Character, _ lIn: Loc) {
            let l = lIn * loc(f.faceLoc)
            if f.triangulation > 0, f.triangulation < tris.count, !tris[f.triangulation].tris.isEmpty {
                let t = tris[f.triangulation]
                let base = positions.count
                positions += t.nodes.map { l.apply($0) }
                for (a, b, c) in t.tris where a < t.nodes.count && b < t.nodes.count && c < t.nodes.count {
                    indices += orient == "-" ? [base + a, base + c, base + b] : [base + a, base + b, base + c]
                }
                return
            }
            // Loops from the wires.
            var loops: [[Vec3]] = []
            for w in f.subs {
                guard let wire = shape(w.index) else { continue }
                let wl = lIn * loc(w.loc)
                var loop: [Vec3] = []
                for e in wire.subs {
                    let pts = edgePoints(e.index, orient: w.orient == "-" ? (e.orient == "+" ? "-" : "+") : e.orient, wl * loc(e.loc))
                    for p in pts where loop.last.map({ ($0 - p).length > 1e-9 }) ?? true { loop.append(p) }
                }
                if let a = loop.first, let b = loop.last, loop.count > 1, (a - b).length < 1e-9 { loop.removeLast() }
                if loop.count >= 3 { loops.append(loop) }
            }
            guard var outer = loops.first else { return }
            // Newell normal of the largest loop is the face plane.
            func newell(_ p: [Vec3]) -> Vec3 {
                var n = Vec3.zero
                for i in 0..<p.count { let a = p[i], b = p[(i + 1) % p.count]; n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
                return n
            }
            var holes = Array(loops.dropFirst())
            if let bi = loops.indices.max(by: { newell(loops[$0]).length < newell(loops[$1]).length }), bi != 0 {
                outer = loops[bi]; holes = loops.enumerated().filter { $0.offset != bi }.map(\.element)
            }
            var n = newell(outer).normalized
            guard n.length > 0.5 else { return }
            if orient == "-" { n = n * -1 }
            let ax = abs(n.x) > 0.9 ? Vec3(0, 1, 0) : Vec3(1, 0, 0)
            let u = n.cross(ax).normalized, v = n.cross(u)
            func proj(_ p: Vec3) -> Vec2 { Vec2(p.dot(u), p.dot(v)) }
            let r = Triangulator.triangulateWithPoints(outer.map(proj), holes: holes.map { $0.map(proj) })
            // Map 2D points back to 3D via the originals (outer followed by holes).
            let all3 = outer + holes.flatMap { $0 }
            var lookup: [Int] = []
            for p in r.points {
                var best = 0, bd = Double.infinity
                for (i, q) in all3.enumerated() { let d = (proj(q) - p).lengthSquared; if d < bd { bd = d; best = i } }
                lookup.append(best)
            }
            let base = positions.count
            positions += all3
            for (a, b, c) in r.triangles {
                let pa = all3[lookup[a]], pb = all3[lookup[b]], pc = all3[lookup[c]]
                let tn = (pb - pa).cross(pc - pa)
                if tn.dot(n) >= 0 { indices += [base + lookup[a], base + lookup[b], base + lookup[c]] }
                else { indices += [base + lookup[a], base + lookup[c], base + lookup[b]] }
            }
        }
        func flush(_ name: String) {
            guard !indices.isEmpty else { return }
            groups.append((name, positions, indices)); positions = []; indices = []
        }
        func combine(_ a: Character, _ b: Character) -> Character { a == "-" ? (b == "+" ? "-" : b == "-" ? "+" : b) : b }
        var counter = 0
        func walk(_ ref: Int, orient: Character, _ l: Loc, depth: Int, inSolid: Bool) {
            guard depth < 64, let s = shape(ref) else { return }
            switch s.kind {
            case "Fa": addFace(s, orient: orient, l)
            case "So", "CS", "Sh":
                let owns = positions.isEmpty && !inSolid
                for sub in s.subs { walk(sub.index, orient: combine(orient, sub.orient), l * loc(sub.loc), depth: depth + 1, inSolid: inSolid || s.kind != "Sh") }
                if owns { counter += 1; flush("\(s.kind == "Sh" ? "Shell" : "Solid") \(counter)") }
            default:
                for sub in s.subs { walk(sub.index, orient: combine(orient, sub.orient), l * loc(sub.loc), depth: depth + 1, inSolid: inSolid) }
            }
        }
        for (r, l) in roots { walk(r, orient: "+", loc(l), depth: 0, inSolid: false) }
        flush("Faces")
        guard !groups.isEmpty else { throw BREPError(message: "no faces found") }
        let s = 1 / unitMM
        return groups.map { g in
            Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: g.verts.map { $0 * s }, meshTriangles: g.tris)),
                   props: ["name": g.name])
        }
    }

    /// Parses one 3D curve record (GeomTools_CurveSet), keeping lines, circles and ellipses.
    static func curve3D(_ tk: inout Tokens) throws -> Curve {
        let type = try tk.int()
        switch type {
        case 1: return .line(try tk.v3(), try tk.v3())
        case 2:
            let c = try tk.v3(); _ = try tk.v3(); let x = try tk.v3(), y = try tk.v3()
            return .circle(c, x, y, try tk.num())
        case 3:
            let c = try tk.v3(); _ = try tk.v3(); let x = try tk.v3(), y = try tk.v3()
            return .ellipse(c, x, y, try tk.num(), try tk.num())
        case 4: for _ in 0..<13 { _ = try tk.num() }; return .other
        case 5: for _ in 0..<14 { _ = try tk.num() }; return .other
        case 6:
            let rational = try tk.int() == 1, degree = try tk.int()
            for _ in 0...degree { for _ in 0..<(rational ? 4 : 3) { _ = try tk.num() } }
            return .other
        case 7:
            let rational = try tk.int() == 1; _ = try tk.int(); _ = try tk.int()
            let poles = try tk.int(), knots = try tk.int()
            for _ in 0..<poles { for _ in 0..<(rational ? 4 : 3) { _ = try tk.num() } }
            for _ in 0..<knots { _ = try tk.num(); _ = try tk.num() }
            return .other
        case 8: _ = try tk.num(); _ = try tk.num(); return try curve3D(&tk)
        case 9: _ = try tk.num(); _ = try tk.v3(); _ = try curve3D(&tk); return .other
        default: throw BREPError(message: "unknown curve type \(type)")
        }
    }
}
