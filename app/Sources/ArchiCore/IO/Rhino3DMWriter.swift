// Oanarina Archi Tool — GPL-3.0-or-later
// Rhino 3DM export (IO-044): writes a version 4 archive (read by Rhino 4 to 8 and every openNURBS-based tool) with the
// same table order and record layout as files saved by Rhino: properties (openNURBS version, application), settings
// (unit system, tolerances), layers (name, colour, visibility, lock, id), then one object record per mesh and curve with
// its attributes (id, layer, display colour from the material, name). The 3D model (building elements, solids) is
// written as meshes with vertex normals (zlib-compressed buffers, CRC-32 on every CRC chunk as openNURBS computes it:
// over the bytes written directly in the chunk); drafting curves stay exact — lines, arcs and circles, polylines
// (bulges as arc segments of poly curves), NURBS splines — at their elevation.
import Foundation

enum R3CRC {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    /// zlib-compatible running CRC-32 (ON_CRC32).
    static func update(_ crc: UInt32, _ b: ArraySlice<UInt8>) -> UInt32 {
        var c = ~crc
        for x in b { c = table[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }
}

/// Chunked little-endian writer for a version 4 archive (4-byte chunk lengths).
struct R3Writer {
    var out: [UInt8] = []
    /// Open chunks: header offset, CRC flag, running CRC of the bytes written directly in the chunk.
    var stack: [(start: Int, crc: Bool, value: UInt32)] = []

    mutating func put(_ b: [UInt8]) {
        if let top = stack.last, top.crc { stack[stack.count - 1].value = R3CRC.update(top.value, b[...]) }
        out += b
    }
    mutating func u8(_ v: UInt8) { put([v]) }
    mutating func u16(_ v: UInt16) { put([UInt8(v & 255), UInt8(v >> 8)]) }
    mutating func u32(_ v: UInt32) { put([UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24)]) }
    mutating func i32(_ v: Int) { u32(UInt32(bitPattern: Int32(truncatingIfNeeded: v))) }
    mutating func f32(_ v: Double) { u32(Float(v).bitPattern) }
    mutating func f64(_ v: Double) { let b = v.bitPattern; u32(UInt32(b & 0xFFFF_FFFF)); u32(UInt32(b >> 32)) }
    mutating func vec(_ v: Vec3) { f64(v.x); f64(v.y); f64(v.z) }
    mutating func version(_ major: Int, _ minor: Int) { u8(UInt8(major << 4 | minor)) }
    mutating func string(_ s: String) {
        guard !s.isEmpty else { i32(0); return }
        let units = Array(s.utf16) + [0]
        i32(units.count)
        var b: [UInt8] = []
        b.reserveCapacity(units.count * 2)
        for u in units { b += [UInt8(u & 255), UInt8(u >> 8)] }
        put(b)
    }
    mutating func uuid(_ u: UUID) {
        let t = u.uuid
        put([t.3, t.2, t.1, t.0, t.5, t.4, t.7, t.6, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
    }
    mutating func color(_ c: RGBA) {
        func b(_ x: Double) -> UInt8 { UInt8(max(0, min(255, (x * 255).rounded()))) }
        put([b(c.r), b(c.g), b(c.b), 0])
    }

    private mutating func raw32(_ v: UInt32) { out += [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24)] }

    /// A chunk: header, body, and the CRC of the body's direct bytes when the typecode asks for one.
    mutating func chunk(_ tc: UInt32, _ body: (inout R3Writer) -> Void) {
        let start = out.count
        raw32(tc); raw32(0)
        let crc = tc & TC.crc != 0
        stack.append((start, crc, 0))
        body(&self)
        let top = stack.removeLast()
        if crc { raw32(top.value) }
        let len = UInt32(out.count - start - 8)
        out[start + 4] = UInt8(len & 255); out[start + 5] = UInt8(len >> 8 & 255); out[start + 6] = UInt8(len >> 16 & 255); out[start + 7] = UInt8(len >> 24)
    }
    /// A short chunk: the value is the data.
    mutating func short(_ tc: UInt32, _ v: Int) { raw32(tc); raw32(UInt32(bitPattern: Int32(truncatingIfNeeded: v))) }
    mutating func emptyTable(_ tc: UInt32) { chunk(tc) { $0.short(TC.endOfTable, 0) } }

    /// A class-wrapped object (TCODE_OPENNURBS_CLASS with its UUID and data chunks).
    mutating func object(_ classID: String, _ data: (inout R3Writer) -> Void) {
        chunk(TC.classChunk) { w in
            w.chunk(TC.classUUID) { $0.uuid(UUID(uuidString: classID) ?? UUID()) }
            w.chunk(TC.classData, data)
            w.short(TC.classEnd, 0)
        }
    }

    /// ON_BinaryArchive::WriteCompressedBuffer.
    mutating func buffer(_ b: [UInt8]) {
        u32(UInt32(b.count))
        guard !b.isEmpty else { return }
        u32(R3CRC.update(0, b[...]))
        if b.count > 128, let z = R3Zlib.deflate(b) {
            u8(1)
            chunk(TC.anonymous) { $0.put(z) }
        } else {
            u8(0)
            put(b)
        }
    }
}

extension Rhino3DM {
    public struct ExportOptions {
        /// Write drafting curves (lines, arcs, polylines, splines, hatch boundaries) as well as the 3D meshes.
        public var curves = true
        public var meshes = true
        public init(curves: Bool = true, meshes: Bool = true) { self.curves = curves; self.meshes = meshes }
    }

    /// Counts of what an export wrote.
    public struct ExportReport: Hashable { public var meshes = 0, curves = 0, layers = 0, skipped = 0 }

    static func unitSystem(_ u: Units) -> Int {
        switch u { case .millimeters: return 2; case .centimeters: return 3; case .meters: return 4; case .inches: return 8; case .feet: return 9 }
    }

    /// The drawing as a Rhino 3DM (version 4) file.
    public static func export(_ doc: ArchiDocument, options: ExportOptions = ExportOptions()) -> Data { exportWithReport(doc, options: options).0 }

    public static func exportWithReport(_ doc: ArchiDocument, options: ExportOptions = ExportOptions()) -> (Data, ExportReport) {
        var rep = ExportReport()
        var w = R3Writer()
        w.out = Array((Rhino3DMParser.header + "       4").utf8)
        let comment = "Oanarina Archi Tool 3DM export\n 3DM I/O processor: OpenNURBS toolkit version 201403055 format (Oanarina Archi Tool)\n"
        w.chunk(TC.comment) { $0.put(Array(comment.utf8) + [0x1A, 0x00]) }
        w.chunk(TC.propertiesTable) { t in
            t.short(TC.opennurbsVersion, 201_403_055)
            t.chunk(TC.application) { a in
                a.version(1, 0)
                a.string("Oanarina Archi Tool")
                a.string("https://oanarinaldi.com/archi-tool.html")
                a.string(doc.info.name.isEmpty ? "" : "Project: " + doc.info.name)
            }
            t.short(TC.endOfTable, 0)
        }
        let mmPer = doc.units.mm
        w.chunk(TC.settingsTable) { t in
            t.chunk(TC.unitsAndTolerances) { u in
                u.i32(102)
                u.i32(unitSystem(doc.units))
                u.f64(0.01 / mmPer)                                // absolute tolerance 0.01 mm
                u.f64(Double.pi / 180)
                u.f64(0.01)
                u.i32(0); u.i32(3)
                u.f64(1000 / mmPer)                                // units per metre
                u.string("")
            }
            t.short(0xA000_0038, 0)                                // current layer index
            t.short(TC.endOfTable, 0)
        }
        for tc in [TC.bitmapTable, TC.textureMappingTable, TC.materialTable, TC.linetypeTable] { w.emptyTable(tc) }

        // Layers (at least one), indexed by name.
        var layers = doc.layers
        if layers.isEmpty { layers = [Layer(name: "0")] }
        var layerIndex: [String: Int] = [:]
        for (i, l) in layers.enumerated() { layerIndex[l.name.lowercased()] = i }
        w.chunk(TC.layerTable) { t in
            for (i, l) in layers.enumerated() {
                t.chunk(TC.layerRecord) { r in
                    r.object(ONClass.layer) { d in
                        d.version(1, 6)
                        d.i32(!l.visible ? 1 : (l.locked ? 2 : 0))
                        d.i32(i)
                        d.i32(-1); d.i32(-1); d.i32(0)
                        d.color(l.color)
                        d.u16(0); d.u16(0); d.f64(0); d.f64(1)
                        d.string(l.name.replacingOccurrences(of: "::", with: "_"))
                        d.u8(l.visible && !l.frozen ? 1 : 0)
                        d.i32(-1)
                        d.u32(0xFFFF_FFFF); d.f64(0)
                        d.u8(l.locked ? 1 : 0)
                        d.uuid(UUID())
                        d.put([UInt8](repeating: 0, count: 16))
                        d.u8(1)
                    }
                }
            }
            t.short(TC.endOfTable, 0)
        }
        rep.layers = layers.count
        for tc in [TC.groupTable, TC.fontTable, TC.dimstyleTable, TC.lightTable, TC.hatchTable, TC.idefTable] { w.emptyTable(tc) }

        func lidx(_ name: String) -> Int { layerIndex[name.lowercased()] ?? 0 }
        w.chunk(TC.objectTable) { t in
            func record(type: Int, layer: Int, color: RGBA?, name: String, _ geo: (inout R3Writer) -> Void) {
                t.chunk(TC.objectRecord) { r in
                    r.short(TC.objectType, type)
                    geo(&r)
                    r.chunk(TC.objectAttributes) { a in
                        a.version(1, 2)
                        a.uuid(UUID())
                        a.i32(layer)
                        a.i32(-1)
                        a.color(color ?? RGBA(0, 0, 0))
                        a.u16(0); a.u16(0); a.f64(0); a.f64(1)
                        a.i32(1)
                        a.u8(0)                                    // mode: normal
                        a.u8(color == nil ? 0 : 1)                 // colour source: layer / object
                        a.u8(0); a.u8(0)
                        a.string(name)
                        a.string("")
                        a.i32(0)                                   // groups
                        a.u8(1)                                    // visible
                    }
                    r.short(TC.objectEnd, 0)
                }
            }
            if options.meshes {
                var owner: [EntityID: (String, String)] = [:]
                for e in doc.elements { owner[e.id] = (e.layer, e.name.isEmpty ? e.geometry.typeName : e.name) }
                for e in doc.entities { owner[e.id] = (e.layer, e.props["name"] ?? e.geometry.typeName) }
                for g in MeshBuilder.build(doc: doc) where !g.mesh.positions.isEmpty && g.mesh.indices.count >= 3 {
                    let (ln, nm) = g.id.flatMap { owner[$0] } ?? ("0", g.kind)
                    let col = doc.material(g.material)?.color
                    let label = g.material.isEmpty ? nm : "\(nm) — \(g.material)"
                    record(type: 0x20, layer: lidx(ln), color: col, name: label) { $0.object(ONClass.mesh) { d in writeMesh(&d, g.mesh) } }
                    rep.meshes += 1
                }
            }
            if options.curves {
                func emit(_ e: Entity, _ geo: Geometry, depth: Int) {
                    let z = Double(e.props["elevation"] ?? e.props["z"] ?? "") ?? 0
                    let col: RGBA? = {
                        switch e.color {
                        case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
                        case .aci(let i) where i > 0 && i < 256: return aciColor(i)
                        default: return nil
                        }
                    }()
                    let name = e.props["name"] ?? ""
                    var zs: [Double]? = nil
                    if let vz = e.props["vertexZ"] { zs = vz.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
                    switch geo {
                    case .insert(let ins):
                        guard depth < 8, let b = doc.blocks[ins.block] else { rep.skipped += 1; return }
                        let tr = ins.transform * Transform2D.translation(-b.basePoint)
                        for be in b.entities { emit(be, GeometryOps.transform(be.geometry, tr), depth: depth + 1) }
                        return
                    case .solid, .text, .dimension, .table, .image, .point: rep.skipped += 1; return
                    default: break
                    }
                    for c in curves(geo, z: z, zs: zs, doc: doc) {
                        record(type: 4, layer: lidx(e.layer), color: col, name: name) { c(&$0) }
                        rep.curves += 1
                    }
                }
                for e in doc.entities { emit(e, e.geometry, depth: 0) }
            }
            t.short(TC.endOfTable, 0)
        }
        w.emptyTable(TC.historyTable)
        // End of file: the total file length.
        let total = w.out.count + 12
        w.chunk(TC.endOfFile) { $0.u32(UInt32(truncatingIfNeeded: total)) }
        return (Data(w.out), rep)
    }

    static func writeMesh(_ d: inout R3Writer, _ m: Mesh) {
        let vc = m.positions.count, fc = m.indices.count / 3
        d.version(3, 0)
        d.i32(vc); d.i32(fc)
        for _ in 0..<4 { d.f64(0); d.f64(1) }                     // packed texture and surface domains
        d.f64(0); d.f64(0)                                         // surface scale
        var lo = Vec3(Double.infinity, Double.infinity, Double.infinity), hi = -lo
        for p in m.positions { lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) }
        for v in [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z] { d.f32(v) }
        let hasN = m.normals.count == vc
        var nlo = Vec3(-1, -1, -1), nhi = Vec3(1, 1, 1)
        if hasN, !m.normals.isEmpty {
            nlo = Vec3(Double.infinity, Double.infinity, Double.infinity); nhi = -nlo
            for n in m.normals { nlo = Vec3(min(nlo.x, n.x), min(nlo.y, n.y), min(nlo.z, n.z)); nhi = Vec3(max(nhi.x, n.x), max(nhi.y, n.y), max(nhi.z, n.z)) }
        }
        for v in [nlo.x, nlo.y, nlo.z, nhi.x, nhi.y, nhi.z] { d.f32(v) }
        for _ in 0..<4 { d.f32(0) }                                // texture box
        d.i32(-1)                                                  // closed: unknown
        d.u8(0)                                                    // no mesh parameters
        for _ in 0..<4 { d.u8(0) }                                 // no curvature statistics
        let isz = vc < 256 ? 1 : (vc < 65536 ? 2 : 4)
        d.i32(isz)
        var faces: [UInt8] = []
        faces.reserveCapacity(fc * 4 * isz)
        for f in 0..<fc {
            let a = Int(m.indices[3 * f]), b = Int(m.indices[3 * f + 1]), c = Int(m.indices[3 * f + 2])
            for i in [a, b, c, c] {
                switch isz {
                case 1: faces.append(UInt8(i))
                case 2: faces += [UInt8(i & 255), UInt8(i >> 8 & 255)]
                default: faces += [UInt8(i & 255), UInt8(i >> 8 & 255), UInt8(i >> 16 & 255), UInt8(i >> 24 & 255)]
                }
            }
        }
        d.put(faces)
        func floats(_ v: [Vec3]) -> [UInt8] {
            var b: [UInt8] = []
            b.reserveCapacity(v.count * 12)
            for p in v { for x in [p.x, p.y, p.z] { let u = Float(x).bitPattern; b += [UInt8(u & 255), UInt8(u >> 8 & 255), UInt8(u >> 16 & 255), UInt8(u >> 24)] } }
            return b
        }
        d.buffer(floats(m.positions))
        d.buffer(hasN ? floats(m.normals) : [])
        d.buffer([]); d.buffer([]); d.buffer([])                  // texture coordinates, curvatures, colours
    }

    // MARK: curves

    static func writeLine(_ d: inout R3Writer, _ a: Vec3, _ b: Vec3) {
        d.version(1, 0); d.vec(a); d.vec(b); d.f64(0); d.f64(max((b - a).length, 1e-12)); d.i32(3)
    }

    /// Arc about +Z (sweep > 0, counter-clockwise) or -Z (sweep < 0) from the world start angle.
    static func writeArc(_ d: inout R3Writer, center c: Vec3, radius r: Double, start: Double, sweep: Double) {
        let ccw = sweep >= 0
        let x = Vec3(1, 0, 0), y = ccw ? Vec3(0, 1, 0) : Vec3(0, -1, 0), z = ccw ? Vec3(0, 0, 1) : Vec3(0, 0, -1)
        let a0 = ccw ? start : -start
        let s = abs(sweep)
        d.version(1, 0)
        d.vec(c); d.vec(x); d.vec(y); d.vec(z)
        d.f64(z.x); d.f64(z.y); d.f64(z.z); d.f64(-(z.dot(c)))
        d.f64(r)
        for k in 0..<3 { let a = a0 + s * Double(k) / 2; d.vec(c + x * (r * cos(a)) + y * (r * sin(a))) }
        d.f64(a0); d.f64(a0 + s)
        d.f64(0); d.f64(max(r * s, 1e-12))
        d.i32(3)
    }

    static func writePolyline(_ d: inout R3Writer, _ p: [Vec3]) {
        d.version(1, 0)
        d.i32(p.count)
        for q in p { d.vec(q) }
        d.i32(p.count)
        var t = 0.0
        for (i, q) in p.enumerated() { if i > 0 { t += max((q - p[i - 1]).length, 1e-12) }; d.f64(t) }
        d.i32(3)
    }

    static func writeNurbs(_ d: inout R3Writer, degree: Int, points: [Vec3], weights: [Double]?, knots full: [Double]) {
        let rat = weights != nil
        d.version(1, 0)
        d.i32(3); d.i32(rat ? 1 : 0); d.i32(degree + 1); d.i32(points.count); d.i32(0); d.i32(0)
        var lo = Vec3(Double.infinity, Double.infinity, Double.infinity), hi = -lo
        for p in points { lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) }
        d.vec(lo); d.vec(hi)
        let k = Array(full.dropFirst().dropLast())
        d.i32(k.count)
        for v in k { d.f64(v) }
        d.i32(points.count)
        for (i, p) in points.enumerated() {
            let w = weights?[i] ?? 1
            if rat { d.f64(p.x * w); d.f64(p.y * w); d.f64(p.z * w); d.f64(w) } else { d.vec(p) }
        }
    }

    /// One segment of a poly curve (line or arc between consecutive polyline vertices).
    enum Segment { case line(Vec3, Vec3), arc(Vec3, Double, Double, Double) }

    static func segments(_ v: [PolyVertex], closed: Bool, z: Double) -> [Segment] {
        var out: [Segment] = []
        let n = v.count
        guard n >= 2 else { return [] }
        for i in 0..<(closed ? n : n - 1) {
            let a = v[i], b = v[(i + 1) % n]
            let p = Vec3(a.p.x, a.p.y, z), q = Vec3(b.p.x, b.p.y, z)
            if (q - p).length < 1e-12 { continue }
            if abs(a.bulge) < 1e-12 { out.append(.line(p, q)); continue }
            let chord = b.p - a.p, dl = chord.length
            let u = chord / dl, left = Vec2(-u.y, u.x)
            let c2 = (a.p + b.p) / 2 + left * (dl / 2 * (1 - a.bulge * a.bulge) / (2 * a.bulge))
            let sweep = 4 * atan(a.bulge)
            let r = (a.p - c2).length
            out.append(.arc(Vec3(c2.x, c2.y, z), r, atan2(a.p.y - c2.y, a.p.x - c2.x), sweep))
        }
        return out
    }

    static func writeSegment(_ d: inout R3Writer, _ s: Segment) {
        switch s {
        case .line(let a, let b): writeLine(&d, a, b)
        case .arc(let c, let r, let st, let sw): writeArc(&d, center: c, radius: r, start: st, sweep: sw)
        }
    }

    static func writePolyCurve(_ d: inout R3Writer, _ segs: [Segment]) {
        d.version(1, 0)
        d.i32(segs.count); d.i32(0); d.i32(0)
        var pts: [Vec3] = []
        var t = [0.0]
        for s in segs {
            switch s {
            case .line(let a, let b): pts += [a, b]; t.append(t[t.count - 1] + (b - a).length)
            case .arc(let c, let r, _, let sw): pts += [c - Vec3(r, r, 0), c + Vec3(r, r, 0)]; t.append(t[t.count - 1] + r * abs(sw))
            }
        }
        var lo = Vec3(Double.infinity, Double.infinity, Double.infinity), hi = -lo
        for p in pts { lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) }
        d.vec(lo); d.vec(hi)
        d.i32(t.count)
        for v in t { d.f64(v) }
        for s in segs {
            switch s {
            case .line: d.object(ONClass.lineCurve) { writeSegment(&$0, s) }
            case .arc: d.object(ONClass.arcCurve) { writeSegment(&$0, s) }
            }
        }
    }

    /// Class-wrapped curve objects for a drafting geometry at elevation `z` (per-vertex `zs` for 3D polylines).
    static func curves(_ g: Geometry, z: Double, zs: [Double]?, doc: ArchiDocument) -> [(inout R3Writer) -> Void] {
        func v3(_ p: Vec2, _ i: Int = -1) -> Vec3 { Vec3(p.x, p.y, (zs != nil && i >= 0 && i < zs!.count) ? zs![i] : z) }
        func polyVertices(_ v: [PolyVertex], closed: Bool) -> [(inout R3Writer) -> Void] {
            guard v.count >= 2 else { return [] }
            if zs != nil || v.allSatisfy({ abs($0.bulge) < 1e-12 }) {
                var p = v.enumerated().map { v3($0.element.p, $0.offset) }
                if closed, let f = p.first { p.append(f) }
                return [{ w in w.object(ONClass.polylineCurve) { writePolyline(&$0, p) } }]
            }
            let segs = segments(v, closed: closed, z: z)
            guard !segs.isEmpty else { return [] }
            return [{ w in w.object(ONClass.polyCurve) { writePolyCurve(&$0, segs) } }]
        }
        switch g {
        case .line(let l):
            return [{ w in w.object(ONClass.lineCurve) { writeLine(&$0, v3(l.a), v3(l.b)) } }]
        case .circle(let c):
            return [{ w in w.object(ONClass.arcCurve) { writeArc(&$0, center: v3(c.center), radius: c.radius, start: 0, sweep: 2 * .pi) } }]
        case .arc(let a):
            return [{ w in w.object(ONClass.arcCurve) { writeArc(&$0, center: v3(a.center), radius: a.radius, start: a.start, sweep: a.sweep) } }]
        case .polyline(let p): return polyVertices(p.vertices, closed: p.closed)
        case .hatch(let h): return h.loops.flatMap { polyVertices($0, closed: true) }
        case .leader(let l): return polyVertices(l.points.map { PolyVertex($0) }, closed: false)
        case .spline(let s):
            if s.degree >= 1, s.controlPoints.count > s.degree, s.knots.count == s.controlPoints.count + s.degree + 1,
               s.weights == nil || s.weights!.count == s.controlPoints.count {
                let pts = s.controlPoints.map { v3($0) }
                return [{ w in w.object(ONClass.nurbsCurve) { writeNurbs(&$0, degree: s.degree, points: pts, weights: s.weights, knots: s.knots) } }]
            }
            fallthrough
        default:
            return GeometryOps.tessellate(g, doc: doc).filter { $0.count >= 2 }.map { pl in
                let p = pl.map { v3($0) }
                return { w in w.object(ONClass.polylineCurve) { writePolyline(&$0, p) } }
            }
        }
    }
}
