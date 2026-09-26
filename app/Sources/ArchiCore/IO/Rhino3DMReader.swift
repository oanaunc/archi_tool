// Oanarina Archi Tool — GPL-3.0-or-later
// Rhino 3DM reader (IO-044), written from the openNURBS file layout (chunked binary archive: 32-byte header, typecode +
// length chunks — 4-byte lengths up to version 4, 8-byte lengths from version 5 — CRC-32 on TCODE_CRC chunks, tables of
// properties, settings, materials, layers, instance definitions and objects, class-wrapped objects identified by
// class UUID with a major/minor chunk version). The byte layouts were checked field by field against 3DM files written
// by Rhino 5, 6 and 7 and by openNURBS (V3): every object reader consumes its chunk exactly.
// Supported objects: meshes (compressed or raw vertex/normal buffers), NURBS / line / arc / polyline / poly curves,
// NURBS / plane / revolution / sum surfaces, B-reps (cached render meshes when present, otherwise the trimmed faces are
// tessellated here), lightweight extrusions, points, point clouds and block instances (nested instance definitions).
import Foundation

public struct Rhino3DMError: Error, LocalizedError {
    public let message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}

/// Typecodes of the openNURBS archive (opennurbs_3dm.h).
enum TC {
    static let short: UInt32 = 0x8000_0000, crc: UInt32 = 0x8000
    static let comment: UInt32 = 0x0000_0001, endOfFile: UInt32 = 0x0000_7FFF, endOfTable: UInt32 = 0xFFFF_FFFF
    static let anonymous: UInt32 = 0x4000_8000, componentAttributes: UInt32 = 0x4000_8002
    static let propertiesTable: UInt32 = 0x1000_0014, settingsTable: UInt32 = 0x1000_0015, bitmapTable: UInt32 = 0x1000_0016
    static let textureMappingTable: UInt32 = 0x1000_0025, materialTable: UInt32 = 0x1000_0010, linetypeTable: UInt32 = 0x1000_0023
    static let layerTable: UInt32 = 0x1000_0011, groupTable: UInt32 = 0x1000_0018, fontTable: UInt32 = 0x1000_0019
    static let dimstyleTable: UInt32 = 0x1000_0020, lightTable: UInt32 = 0x1000_0012, hatchTable: UInt32 = 0x1000_0022
    static let idefTable: UInt32 = 0x1000_0021, objectTable: UInt32 = 0x1000_0013, historyTable: UInt32 = 0x1000_0026
    static let opennurbsVersion: UInt32 = 0xA000_0026, notes: UInt32 = 0x2000_8022, application: UInt32 = 0x2000_8024
    static let unitsAndTolerances: UInt32 = 0x2000_8031
    static let materialRecord: UInt32 = 0x2000_8040, layerRecord: UInt32 = 0x2000_8050, objectRecord: UInt32 = 0x2000_8070
    static let idefRecord: UInt32 = 0x2000_8076
    static let objectType: UInt32 = 0x8200_0071, objectAttributes: UInt32 = 0x0200_8072, objectEnd: UInt32 = 0x8200_007F
    static let classChunk: UInt32 = 0x0002_7FFA, classUUID: UInt32 = 0x0002_FFFB, classData: UInt32 = 0x0002_FFFC, classEnd: UInt32 = 0x8002_7FFF
}

/// openNURBS class identifiers (as found in Rhino files).
enum ONClass {
    static let mesh = "4ED7D4E4-E947-11D3-BFE5-0010830122F0"
    static let nurbsCurve = "5EAF1119-0B51-11D4-BFFE-0010830122F0"
    static let nurbsCurveLegacy = "4ED7D4DD-E947-11D3-BFE5-0010830122F0"
    static let lineCurve = "4ED7D4DB-E947-11D3-BFE5-0010830122F0"
    static let arcCurve = "CF33BE2A-09B4-11D4-BFFB-0010830122F0"
    static let polylineCurve = "4ED7D4E6-E947-11D3-BFE5-0010830122F0"
    static let polyCurve = "4ED7D4E0-E947-11D3-BFE5-0010830122F0"
    static let nurbsSurface = "4ED7D4DE-E947-11D3-BFE5-0010830122F0"
    static let nurbsSurface2 = "4760C817-0BE3-11D4-BFFE-0010830122F0"
    static let planeSurface = "4ED7D4DF-E947-11D3-BFE5-0010830122F0"
    static let revSurface = "0A8401B6-4D34-4B99-8615-1B4E723DC4E5"
    static let sumSurface = "665F6331-2A66-4CCE-81D0-B5EEBD9B5417"
    static let brep = "F06FC243-A32A-4608-9DD8-A7D2C4CE2A36"
    static let extrusion = "36F53175-72B8-4D47-BF1F-B4E6FC24F4B9"
    static let instanceRef = "F9CFB638-B9D4-4340-87E3-C56E7865D96A"
    static let instanceDefinition = "26F8BFF6-2618-417F-A158-153D64A94989"
    static let layer = "95809813-E985-11D3-BFE5-0010830122F0"
}

/// Little-endian cursor over a 3DM byte range.
struct R3Reader {
    let d: [UInt8]
    var p: Int
    let end: Int
    /// 8-byte chunk lengths (archive version 5 and later).
    let big: Bool
    init(_ d: [UInt8], big: Bool, from: Int = 0, to: Int? = nil) { self.d = d; self.big = big; p = from; end = to ?? d.count }
    var left: Int { end - p }
    func need(_ n: Int) throws { if n < 0 || p + n > end { throw Rhino3DMError("Truncated 3DM data.") } }
    mutating func u8() throws -> UInt8 { try need(1); defer { p += 1 }; return d[p] }
    mutating func u16() throws -> UInt16 { try need(2); defer { p += 2 }; return UInt16(d[p]) | UInt16(d[p + 1]) << 8 }
    mutating func u32() throws -> UInt32 {
        try need(4); defer { p += 4 }
        return UInt32(d[p]) | UInt32(d[p + 1]) << 8 | UInt32(d[p + 2]) << 16 | UInt32(d[p + 3]) << 24
    }
    mutating func i32() throws -> Int { Int(Int32(bitPattern: try u32())) }
    mutating func u64() throws -> UInt64 { let a = UInt64(try u32()); let b = UInt64(try u32()); return a | b << 32 }
    mutating func f32() throws -> Double { Double(Float(bitPattern: try u32())) }
    mutating func f64() throws -> Double { Double(bitPattern: try u64()) }
    mutating func vec() throws -> Vec3 { Vec3(try f64(), try f64(), try f64()) }
    mutating func interval() throws -> (Double, Double) { (try f64(), try f64()) }
    mutating func skip(_ n: Int) throws { try need(n); p += n }
    /// Chunk version byte: major in the high nibble, minor in the low nibble.
    mutating func version() throws -> (Int, Int) { let b = Int(try u8()); return (b >> 4, b & 15) }
    mutating func uuid() throws -> String {
        try need(16)
        let b = Array(d[p..<(p + 16)]); p += 16
        let h = { (i: Int) in String(format: "%02X", b[i]) }
        return h(3) + h(2) + h(1) + h(0) + "-" + h(5) + h(4) + "-" + h(7) + h(6) + "-" + h(8) + h(9) + "-" + (10..<16).map(h).joined()
    }
    /// ON_wString: UTF-16 code unit count (with the terminating zero), then the code units.
    mutating func string() throws -> String {
        let n = try i32()
        guard n > 0 else { return "" }
        guard n < 1 << 24 else { throw Rhino3DMError("Bad string length in 3DM data.") }
        try need(2 * n)
        var units: [UInt16] = []
        units.reserveCapacity(n)
        for i in 0..<n { units.append(UInt16(d[p + 2 * i]) | UInt16(d[p + 2 * i + 1]) << 8) }
        p += 2 * n
        while units.last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }
    mutating func intArray() throws -> [Int] {
        let n = try i32(); guard n >= 0, n <= left / 4 else { throw Rhino3DMError("Bad array length in 3DM data.") }
        return try (0..<n).map { _ in try i32() }
    }
    mutating func doubleArray() throws -> [Double] {
        let n = try i32(); guard n >= 0, n <= left / 8 else { throw Rhino3DMError("Bad array length in 3DM data.") }
        return try (0..<n).map { _ in try f64() }
    }
    /// Chunk header; returns the typecode, the value and (for non-short chunks) a reader over the body without its CRC.
    mutating func chunk() throws -> (tc: UInt32, value: Int64, body: R3Reader?) {
        let tc = try u32()
        let v: Int64 = big ? Int64(bitPattern: try u64()) : Int64(try i32())
        if tc & TC.short != 0 { return (tc, v, nil) }
        guard v >= 0, v <= Int64(left) else { throw Rhino3DMError("Bad chunk length \(v) in 3DM data (typecode \(String(tc, radix: 16))).") }
        let n = Int(v)
        let hasCRC = tc & TC.crc != 0 && n >= 4
        let body = R3Reader(d, big: big, from: p, to: p + n - (hasCRC ? 4 : 0))
        p += n
        return (tc, v, body)
    }
    /// Peeks the next typecode without moving.
    func peek() -> UInt32? {
        guard p + 4 <= end else { return nil }
        return UInt32(d[p]) | UInt32(d[p + 1]) << 8 | UInt32(d[p + 2]) << 16 | UInt32(d[p + 3]) << 24
    }
}

// MARK: - Parsed geometry

/// A curve of the file, evaluable over its domain.
indirect enum R3Curve {
    case nurbs(StepBSplineCurve)
    case line(Vec3, Vec3, Double, Double)
    /// centre, x axis, y axis (unit), radius, angle interval, parameter interval
    case arc(Vec3, Vec3, Vec3, Double, (Double, Double), (Double, Double))
    case polyline([Vec3], [Double])
    case poly([R3Curve], [Double])

    var domain: (Double, Double) {
        switch self {
        case .nurbs(let c): return c.range
        case .line(_, _, let t0, let t1): return (t0, t1)
        case .arc(_, _, _, _, _, let t): return t
        case .polyline(let p, let t): return t.count == p.count && !t.isEmpty ? (t[0], t[t.count - 1]) : (0, Double(max(0, p.count - 1)))
        case .poly(_, let t): return t.count >= 2 ? (t[0], t[t.count - 1]) : (0, 1)
        }
    }

    func eval(_ t: Double) -> Vec3 {
        switch self {
        case .nurbs(let c): let r = c.range; return c.eval(min(max(t, r.0), r.1))
        case .line(let a, let b, let t0, let t1):
            let s = abs(t1 - t0) < 1e-300 ? 0 : (t - t0) / (t1 - t0)
            return a + (b - a) * s
        case .arc(let c, let x, let y, let r, let ang, let tt):
            let s = abs(tt.1 - tt.0) < 1e-300 ? 0 : (t - tt.0) / (tt.1 - tt.0)
            let a = ang.0 + (ang.1 - ang.0) * s
            return c + x * (r * cos(a)) + y * (r * sin(a))
        case .polyline(let p, let tv):
            guard p.count > 1 else { return p.first ?? .zero }
            let ts = tv.count == p.count ? tv : (0..<p.count).map(Double.init)
            if t <= ts[0] { return p[0] }
            for i in 1..<p.count where t <= ts[i] || i == p.count - 1 {
                let d = ts[i] - ts[i - 1]
                let s = d > 0 ? min(1, (t - ts[i - 1]) / d) : 0
                return p[i - 1] + (p[i] - p[i - 1]) * s
            }
            return p[p.count - 1]
        case .poly(let segs, let ts):
            guard !segs.isEmpty, ts.count == segs.count + 1 else { return .zero }
            var i = segs.count - 1
            for k in 0..<segs.count where t < ts[k + 1] { i = k; break }
            let d = segs[i].domain
            let s = ts[i + 1] - ts[i] > 0 ? (t - ts[i]) / (ts[i + 1] - ts[i]) : 0
            return segs[i].eval(d.0 + (d.1 - d.0) * s)
        }
    }

    /// Points along the sub-domain [t0, t1] (exact vertices for lines and polylines, arcs by angle, NURBS by span).
    func sample(_ t0: Double, _ t1: Double, maxSegments: Int = 256) -> [Vec3] {
        let rev = t1 < t0
        let a = min(t0, t1), b = max(t0, t1)
        var out: [Vec3]
        switch self {
        case .line: out = [eval(a), eval(b)]
        case .polyline(let p, let tv):
            let ts = tv.count == p.count ? tv : (0..<p.count).map(Double.init)
            out = [eval(a)]
            for i in 0..<p.count where ts[i] > a + 1e-12 && ts[i] < b - 1e-12 { out.append(p[i]) }
            out.append(eval(b))
        case .arc(_, _, _, _, let ang, let tt):
            let frac = abs(tt.1 - tt.0) < 1e-300 ? 1 : (b - a) / abs(tt.1 - tt.0)
            let sweep = abs(ang.1 - ang.0) * frac
            let n = max(2, min(maxSegments, Int((sweep / (Double.pi / 24)).rounded(.up))))
            out = (0...n).map { eval(a + (b - a) * Double($0) / Double(n)) }
        case .nurbs(let c):
            if c.degree == 1 {
                // Degree 1: the knots are the corners.
                out = [eval(a)]
                for k in c.knots where k > a + 1e-12 && k < b - 1e-12 { if out.count < 100_000 { out.append(eval(k)) } }
                out.append(eval(b))
                var clean: [Vec3] = []
                for q in out where clean.last.map({ ($0 - q).length > 1e-12 }) ?? true { clean.append(q) }
                out = clean.count >= 2 ? clean : [eval(a), eval(b)]
            } else {
                let spans = Set(c.knots.filter { $0 > a && $0 < b }).count + 1
                let per = c.weights == nil ? max(4, 2 * c.degree) : max(8, 3 * c.degree)
                let n = max(2, min(maxSegments, spans * per))
                out = (0...n).map { eval(a + (b - a) * Double($0) / Double(n)) }
            }
        case .poly(let segs, let ts):
            out = []
            guard ts.count == segs.count + 1 else { return [] }
            for i in 0..<segs.count {
                let lo = max(a, ts[i]), hi = min(b, ts[i + 1])
                guard hi > lo || (segs.count == 1) else { continue }
                let d = segs[i].domain
                let map = { (t: Double) -> Double in ts[i + 1] - ts[i] > 0 ? d.0 + (d.1 - d.0) * (t - ts[i]) / (ts[i + 1] - ts[i]) : d.0 }
                let pts = segs[i].sample(map(lo), map(hi), maxSegments: maxSegments)
                out += out.isEmpty ? pts : Array(pts.dropFirst())
            }
        }
        return rev ? out.reversed() : out
    }

    func sample(maxSegments: Int = 256) -> [Vec3] { let d = domain; return sample(d.0, d.1, maxSegments: maxSegments) }
}

/// A surface of the file, evaluable over its two-parameter domain.
enum R3Surface {
    case nurbs(StepBSplineSurface)
    /// origin, x, y, domains, extents
    case plane(Vec3, Vec3, Vec3, (Double, Double), (Double, Double), (Double, Double), (Double, Double))
    /// axis from/to, angle interval, angle parameter interval, profile curve, transposed
    case rev(Vec3, Vec3, (Double, Double), (Double, Double), R3Curve, Bool)
    /// curve 0, curve 1, base point: P(s, t) = C0(s) + C1(t) + base
    case sum(R3Curve, R3Curve, Vec3)

    var domain: ((Double, Double), (Double, Double)) {
        switch self {
        case .nurbs(let s): return (s.uRange, s.vRange)
        case .plane(_, _, _, let d0, let d1, _, _): return (d0, d1)
        case .rev(_, _, _, let t, let c, let tr): return tr ? (c.domain, t) : (t, c.domain)
        case .sum(let a, let b, _): return (a.domain, b.domain)
        }
    }

    func eval(_ u: Double, _ v: Double) -> Vec3 {
        switch self {
        case .nurbs(let s):
            let ur = s.uRange, vr = s.vRange
            return s.eval(min(max(u, ur.0), ur.1), min(max(v, vr.0), vr.1))
        case .plane(let o, let x, let y, let d0, let d1, let e0, let e1):
            func map(_ t: Double, _ d: (Double, Double), _ e: (Double, Double)) -> Double {
                abs(d.1 - d.0) < 1e-300 ? e.0 : e.0 + (e.1 - e.0) * (t - d.0) / (d.1 - d.0)
            }
            return o + x * map(u, d0, e0) + y * map(v, d1, e1)
        case .rev(let a0, let a1, let ang, let t, let c, let tr):
            let (ua, vc) = tr ? (v, u) : (u, v)
            let s = abs(t.1 - t.0) < 1e-300 ? 0 : (ua - t.0) / (t.1 - t.0)
            let angle = ang.0 + (ang.1 - ang.0) * s
            return R3Math.rotate(c.eval(vc), about: a0, axis: (a1 - a0).normalized, angle: angle)
        case .sum(let c0, let c1, let base): return c0.eval(u) + c1.eval(v) + base
        }
    }

}

enum R3Math {
    /// Rodrigues rotation of `p` about the line through `o` with unit direction `k`.
    static func rotate(_ p: Vec3, about o: Vec3, axis k: Vec3, angle: Double) -> Vec3 {
        let v = p - o, c = cos(angle), s = sin(angle)
        return o + v * c + k.cross(v) * s + k * (k.dot(v) * (1 - c))
    }
}

/// Triangle mesh (render mesh or plain mesh object).
struct R3Mesh {
    var vertices: [Vec3] = []
    var triangles: [Int] = []
    mutating func append(_ m: R3Mesh) {
        let o = vertices.count
        vertices += m.vertices
        triangles += m.triangles.map { $0 + o }
    }
    mutating func transform(_ x: R3Xform) { vertices = vertices.map(x.apply) }
}

/// 4×4 row-major transformation (ON_Xform).
struct R3Xform {
    var m: [Double]
    static let identity = R3Xform(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    func apply(_ p: Vec3) -> Vec3 {
        let x = m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3]
        let y = m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7]
        let z = m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11]
        let w = m[12] * p.x + m[13] * p.y + m[14] * p.z + m[15]
        return abs(w) > 1e-300 && abs(w - 1) > 1e-15 ? Vec3(x / w, y / w, z / w) : Vec3(x, y, z)
    }
    static func * (a: R3Xform, b: R3Xform) -> R3Xform {
        var r = [Double](repeating: 0, count: 16)
        for i in 0..<4 { for j in 0..<4 { r[4 * i + j] = (0..<4).reduce(0) { $0 + a.m[4 * i + $1] * b.m[4 * $1 + j] } } }
        return R3Xform(m: r)
    }
}

struct R3Brep {
    struct Trim { var c2: Int; var d: (Double, Double); var type: Int }
    struct Loop { var trims: [Int]; var type: Int }
    struct Face { var loops: [Int]; var surface: Int; var reversed: Bool }
    var c2: [R3Curve?] = []
    var surfaces: [R3Surface?] = []
    var trims: [Trim] = []
    var loops: [Loop] = []
    var faces: [Face] = []
    var renderMeshes: [R3Mesh?] = []
}

struct R3Extrusion {
    var profiles: [R3Curve]
    var from: Vec3, to: Vec3
    var up: Vec3
    var t: (Double, Double)
    var caps: (Bool, Bool)
}

/// One geometry object read from the file.
indirect enum R3Geometry {
    case mesh(R3Mesh)
    case curve(R3Curve)
    case surface(R3Surface)
    case brep(R3Brep)
    case extrusion(R3Extrusion)
    case point(Vec3)
    case pointCloud([Vec3])
    case instance(String, R3Xform)
    case unsupported(String)
}

struct R3Attributes {
    var uuid = ""
    var layer = 0
    var material = -1
    var color: (UInt8, UInt8, UInt8)? = nil
    /// 0 layer, 1 object, 2 material, 3 parent
    var colorSource = 0
    /// 0 layer, 1 object
    var materialSource = 0
    var name = ""
    var visible = true
    /// 0 normal, 1 hidden, 2 locked, 3 instance definition member
    var mode = 0
}

struct R3Object {
    var type: Int
    var geometry: R3Geometry
    var attributes: R3Attributes
}

struct R3Layer {
    var name: String
    var index: Int
    var color: (UInt8, UInt8, UInt8)
    var visible: Bool
    var locked: Bool
    var id: String
    var parent: String
}

struct R3Material {
    var name: String
    var diffuse: (UInt8, UInt8, UInt8)
    var transparency: Double
    var shine: Double
}

struct R3InstanceDefinition {
    var id: String
    var name: String
    var members: [String]
}

/// Everything read from a 3DM file.
struct R3Model {
    var version = 0
    var openNURBSVersion = 0
    var application = ""
    /// Millimetres per model unit.
    var unitMM = 1.0
    var unitSystem = 2
    var layers: [R3Layer] = []
    var materials: [R3Material] = []
    var idefs: [R3InstanceDefinition] = []
    var objects: [R3Object] = []
    var skipped: [String: Int] = [:]
}
