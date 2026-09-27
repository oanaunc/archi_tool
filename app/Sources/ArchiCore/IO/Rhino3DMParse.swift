// Oanarina Archi Tool — GPL-3.0-or-later
// Rhino 3DM archive parsing (IO-044): tables and class-wrapped objects (see Rhino3DMReader.swift for the layout notes).
import Foundation

enum R3Zlib {
    /// Inflates a zlib stream (2-byte header, DEFLATE data, Adler-32).
    static func inflate(_ b: ArraySlice<UInt8>) -> [UInt8]? {
        guard b.count > 2 else { return nil }
        let start = b.startIndex + 2
        for trim in [4, 0] where b.count - 2 - trim > 0 {
            let raw = Data(b[start..<(b.endIndex - trim)])
            if let d = try? RawDeflate.decompress(raw) { return [UInt8](d) }
        }
        return nil
    }

    /// zlib stream of `d` (header 0x78 0x9C, raw DEFLATE from Foundation, Adler-32).
    static func deflate(_ d: [UInt8]) -> [UInt8]? {
        let raw = RawDeflate.compress(Data(d))
        var a: UInt32 = 1, b: UInt32 = 0
        var i = 0
        while i < d.count {
            let end = min(d.count, i + 5552)
            while i < end { a += UInt32(d[i]); b += a; i += 1 }
            a %= 65521; b %= 65521
        }
        let adler = b << 16 | a
        return [0x78, 0x9C] + [UInt8](raw) + [UInt8(adler >> 24), UInt8(adler >> 16 & 255), UInt8(adler >> 8 & 255), UInt8(adler & 255)]
    }
}

enum Rhino3DMParser {
    static let header = "3D Geometry File Format "

    /// Millimetres per unit of an ON::LengthUnitSystem value (custom: `perMeter` units per metre).
    static func unitMM(_ system: Int, perMeter: Double) -> Double {
        switch system {
        case 1: return 0.001
        case 2: return 1
        case 3: return 10
        case 4: return 1000
        case 5: return 1_000_000
        case 6: return 2.54e-5
        case 7: return 0.0254
        case 8: return 25.4
        case 9: return 304.8
        case 10: return 1_609_344
        case 11: return perMeter > 0 ? 1000 / perMeter : 1
        case 12: return 1e-7
        case 13: return 1e-6
        case 14: return 100
        case 15: return 10_000
        case 16: return 100_000
        case 17: return 1e9
        case 18: return 1e12
        case 19: return 914.4
        case 20: return 25.4 / 72
        case 21: return 25.4 / 6
        case 22: return 1_852_000
        case 23: return 1.495978707e14
        case 24: return 9.4607304725808e18
        case 25: return 3.08567758149137e19
        default: return 1
        }
    }

    static func read(_ data: Data) throws -> R3Model {
        let bytes = [UInt8](data)
        guard bytes.count >= 32, String(decoding: bytes[0..<24], as: UTF8.self) == header,
              let ver = Int(String(decoding: bytes[24..<32], as: UTF8.self).trimmingCharacters(in: .whitespaces)) else {
            throw Rhino3DMError("Not a Rhino 3DM file.")
        }
        guard ver >= 2 else { throw Rhino3DMError("Rhino 1.x (3DM version \(ver)) files are not supported; save as a newer version.") }
        var m = R3Model()
        m.version = ver
        var r = R3Reader(bytes, big: ver >= 50, from: 32)
        var modernIdefs: [(Int, R3Reader)] = []
        while r.left >= (r.big ? 12 : 8) {
            let (tc, _, body) = try r.chunk()
            if tc == TC.endOfFile { break }
            guard var b = body else { continue }
            switch tc {
            case TC.propertiesTable: try properties(&b, &m)
            case TC.settingsTable: try settings(&b, &m)
            case TC.materialTable:
                try records(&b, TC.materialRecord) { rec in
                    if let (_, d) = try classChunk(&rec) { var dd = d; if let mat = try? material(&dd) { m.materials.append(mat) } }
                }
            case TC.layerTable:
                try records(&b, TC.layerRecord) { rec in
                    if let (_, d) = try classChunk(&rec) { var dd = d; if let l = try? layer(&dd) { m.layers.append(l) } }
                }
            case TC.idefTable:
                try records(&b, TC.idefRecord) { rec in
                    guard let (_, d) = try classChunk(&rec) else { return }
                    var dd = d
                    if dd.peek() == TC.anonymous {
                        modernIdefs.append((m.idefs.count, dd))
                        m.idefs.append(modernIdef(dd))
                    } else if let i = try? legacyIdef(&dd) { m.idefs.append(i) }
                }
            case TC.objectTable:
                try records(&b, TC.objectRecord) { rec in
                    if let o = try object(&rec, &m) { m.objects.append(o) }
                }
            default: break
            }
        }
        // Instance definitions of version 6+ list their member objects by id near the end of their chunk.
        if !modernIdefs.isEmpty {
            let ids = Set(m.objects.map { $0.attributes.uuid })
            for (i, rd) in modernIdefs { m.idefs[i].members = memberList(rd, known: ids) }
        }
        return m
    }

    /// Iterates the records with typecode `tc` of a table body.
    static func records(_ b: inout R3Reader, _ tc: UInt32, _ body: (inout R3Reader) throws -> Void) throws {
        while b.left >= (b.big ? 12 : 8) {
            let (t, _, rb) = try b.chunk()
            if t == TC.endOfTable { break }
            guard t == tc, var rec = rb else { continue }
            try body(&rec)
        }
    }

    static func properties(_ b: inout R3Reader, _ m: inout R3Model) throws {
        while b.left >= (b.big ? 12 : 8) {
            let (t, v, body) = try b.chunk()
            if t == TC.endOfTable { break }
            if t == TC.opennurbsVersion { m.openNURBSVersion = Int(v) }
            if t == TC.application, var a = body {
                _ = try? a.version()
                m.application = (try? a.string()) ?? ""
            }
        }
    }

    static func settings(_ b: inout R3Reader, _ m: inout R3Model) throws {
        while b.left >= (b.big ? 12 : 8) {
            let (t, _, body) = try b.chunk()
            if t == TC.endOfTable { break }
            guard t == TC.unitsAndTolerances, var u = body else { continue }
            let v = try u.i32()
            var system = v, perMeter = 0.0
            if v >= 100 {
                system = try u.i32()
                _ = try u.f64(); _ = try u.f64(); _ = try u.f64()
                if v >= 101 { _ = try u.i32(); _ = try u.i32() }
                if v >= 102 { perMeter = try u.f64() }
            }
            m.unitSystem = system
            m.unitMM = unitMM(system, perMeter: perMeter)
        }
    }

    /// Reads a class chunk (TCODE_OPENNURBS_CLASS): its class UUID and a reader over its data.
    static func classChunk(_ r: inout R3Reader) throws -> (String, R3Reader)? {
        while r.left >= (r.big ? 12 : 8) {
            let (tc, _, body) = try r.chunk()
            guard tc == TC.classChunk, var c = body else { continue }
            var uuid = "", data: R3Reader?
            while c.left >= (c.big ? 12 : 8) {
                let (t, _, cb) = try c.chunk()
                if t == TC.classUUID, var u = cb { uuid = try u.uuid() }
                else if t == TC.classData { data = cb }
                else if t == TC.classEnd { break }
            }
            guard let d = data else { return nil }
            return (uuid, d)
        }
        return nil
    }

    static func color(_ r: inout R3Reader) throws -> (UInt8, UInt8, UInt8) {
        let c = try r.u32()
        return (UInt8(c & 255), UInt8(c >> 8 & 255), UInt8(c >> 16 & 255))
    }

    // MARK: tables

    static func layer(_ r: inout R3Reader) throws -> R3Layer {
        let (_, minor) = try r.version()
        let mode = try r.i32()
        let index = try r.i32()
        _ = try r.i32(); _ = try r.i32(); _ = try r.i32()       // IGES level, material, obsolete
        let col = try color(&r)
        try r.skip(20)                                          // obsolete line style
        let name = try r.string()
        var visible = mode != 1, locked = mode == 2, id = "", parent = ""
        if minor >= 1 { visible = try r.u8() != 0 && mode != 1 }
        if minor >= 2 { _ = try r.i32() }
        if minor >= 3 { _ = try r.u32(); _ = try r.f64() }
        if minor >= 4 { locked = try r.u8() != 0 || mode == 2 }
        if minor >= 5 { id = try r.uuid() }
        if minor >= 6 { parent = try r.uuid() }
        return R3Layer(name: name, index: index, color: col, visible: visible, locked: locked, id: id, parent: parent)
    }

    /// ON_Material (V4/V5 layout: chunk version 2.0 wrapping 1.x fields).
    static func material(_ r: inout R3Reader) throws -> R3Material {
        let (major, _) = try r.version()
        if major == 2 {
            _ = try r.version()
            _ = try r.uuid(); _ = try r.i32()
            let name = try r.string()
            _ = try r.uuid()
            _ = try color(&r)
            let diffuse = try color(&r)
            _ = try color(&r); _ = try color(&r); _ = try color(&r); _ = try color(&r)
            _ = try r.f64(); _ = try r.f64()
            let shine = try r.f64(), transparency = try r.f64()
            return R3Material(name: name, diffuse: diffuse, transparency: max(0, min(1, transparency)), shine: shine)
        }
        if major == 1 {
            // V2/V3 layout.
            _ = try color(&r)
            let diffuse = try color(&r)
            _ = try color(&r); _ = try color(&r)
            let shine = try r.f64(), transparency = try r.f64()
            try r.skip(4 + 4 + 20)
            for _ in 0..<3 { _ = try r.string() }
            _ = try r.i32(); _ = try r.uuid(); _ = try r.string()
            let name = try r.string()
            return R3Material(name: name, diffuse: diffuse, transparency: max(0, min(1, transparency)), shine: shine)
        }
        throw Rhino3DMError("Unsupported material version.")
    }

    static func legacyIdef(_ r: inout R3Reader) throws -> R3InstanceDefinition {
        _ = try r.version()
        let id = try r.uuid()
        let n = try r.i32()
        guard n >= 0, n <= r.left / 16 else { throw Rhino3DMError("Bad instance definition.") }
        let members = try (0..<n).map { _ in try r.uuid() }
        let name = try r.string()
        return R3InstanceDefinition(id: id, name: name, members: members)
    }

    /// Version 6+ instance definition: id and name from the model component attributes.
    static func modernIdef(_ rd: R3Reader) -> R3InstanceDefinition {
        var r = rd
        var out = R3InstanceDefinition(id: "", name: "", members: [])
        guard let (_, _, b) = try? r.chunk(), var body = b else { return out }
        _ = try? body.skip(8)
        if body.peek() == TC.componentAttributes, let (_, _, cb) = try? body.chunk(), let c = cb {
            let (id, name) = componentIDName(c)
            out.id = id; out.name = name
        }
        return out
    }

    /// Id and name of an ON_ModelComponent attributes chunk: flagged fields (1 = present) after the chunk version.
    static func componentIDName(_ c: R3Reader) -> (String, String) {
        var r = c
        var id = "", name = ""
        guard (try? r.skip(8)) != nil else { return ("", "") }
        // The id is the first present 16-byte field; the name is the string that ends the chunk.
        var q = r
        while q.left >= 17 {
            guard let f = try? q.u8() else { break }
            if f == 1, let u = try? q.uuid() { id = u; break }
        }
        // Name: the last field, an ON_wString running to the end of the chunk.
        var p = c.end - 4
        while p >= c.p {
            let n = Int(Int32(bitPattern: UInt32(c.d[p]) | UInt32(c.d[p + 1]) << 8 | UInt32(c.d[p + 2]) << 16 | UInt32(c.d[p + 3]) << 24))
            if n > 0, p + 4 + 2 * n == c.end {
                var s = R3Reader(c.d, big: c.big, from: p, to: c.end)
                name = (try? s.string()) ?? ""
                break
            }
            if c.end - p > 4 + 2 * 4096 { break }
            p -= 2
        }
        return (id, name)
    }

    /// Member object ids of a version 6+ instance definition: an int count followed by that many known object ids.
    static func memberList(_ rd: R3Reader, known: Set<String>) -> [String] {
        let d = rd.d
        var p = rd.p
        var best: [String] = []
        while p + 20 <= rd.end {
            let n = Int(Int32(bitPattern: UInt32(d[p]) | UInt32(d[p + 1]) << 8 | UInt32(d[p + 2]) << 16 | UInt32(d[p + 3]) << 24))
            if n > 0, p + 4 + 16 * n <= rd.end {
                var r = R3Reader(d, big: rd.big, from: p + 4, to: rd.end)
                if let first = try? r.uuid(), known.contains(first) {
                    var ids = [first]
                    var ok = true
                    for _ in 1..<max(1, n) where n > 1 {
                        guard let u = try? r.uuid(), known.contains(u) else { ok = false; break }
                        ids.append(u)
                    }
                    if ok && ids.count > best.count { best = ids }
                }
            }
            p += 1
        }
        return best
    }

    // MARK: objects

    static func attributes(_ r: inout R3Reader) throws -> R3Attributes {
        var a = R3Attributes()
        let (major, minor) = try r.version()
        a.uuid = try r.uuid()
        a.layer = try r.i32()
        if major == 1 {
            a.material = try r.i32()
            let c = try color(&r)
            try r.skip(20)
            _ = try r.i32()
            a.mode = Int(try r.u8())
            a.colorSource = Int(try r.u8())
            _ = try r.u8()
            a.materialSource = Int(try r.u8())
            a.name = try r.string()
            _ = try r.string()
            if minor >= 1 { _ = try r.intArray() }
            if minor >= 2 { a.visible = try r.u8() != 0 }
            if a.colorSource == 1 { a.color = c }
            if a.mode == 1 { a.visible = false }
            return a
        }
        // Version 2 (Rhino 5+): non-default values tagged with item codes, 0 ends the list.
        var c: (UInt8, UInt8, UInt8)?
        loop: while r.left > 0 {
            let code = try r.u8()
            switch code {
            case 0: break loop
            case 1: a.name = try r.string()
            case 2: _ = try r.string()
            case 3: _ = try r.i32()
            case 4: a.material = try r.i32()
            case 5: _ = try r.chunk()
            case 6: c = try color(&r)
            case 7: _ = try r.u32()
            case 8: _ = try r.f64()
            case 9: _ = try r.u8()
            case 10: _ = try r.i32()
            case 11: a.visible = try r.u8() != 0
            case 12: a.mode = Int(try r.u8())
            case 13: a.colorSource = Int(try r.u8())
            case 14, 15: _ = try r.u8()
            case 16: a.materialSource = Int(try r.u8())
            case 17: _ = try r.u8()
            case 18: _ = try r.intArray()
            default: break loop
            }
        }
        if a.colorSource == 1 { a.color = c }
        if a.mode == 1 { a.visible = false }
        return a
    }

    static func object(_ rec: inout R3Reader, _ m: inout R3Model) throws -> R3Object? {
        var type = 0
        var geo: R3Geometry?
        var attrs = R3Attributes()
        while rec.left >= (rec.big ? 12 : 8) {
            guard let tc = rec.peek() else { break }
            if tc == TC.classChunk {
                if let (uuid, d) = try classChunk(&rec) {
                    var dd = d
                    do { geo = try geometry(uuid, &dd, type: type) } catch { geo = .unsupported("damaged " + uuid) }
                }
                continue
            }
            let (t, v, body) = try rec.chunk()
            if t == TC.objectType { type = Int(v) }
            else if t == TC.objectAttributes, var b = body { attrs = (try? attributes(&b)) ?? attrs }
            else if t == TC.objectEnd { break }
        }
        guard let g = geo else { return nil }
        return R3Object(type: type, geometry: g, attributes: attrs)
    }

    /// Geometry of a class-wrapped object.
    static func geometry(_ uuid: String, _ r: inout R3Reader, type: Int) throws -> R3Geometry {
        switch uuid {
        case ONClass.mesh: return .mesh(try mesh(&r))
        case ONClass.brep: return .brep(try brep(&r))
        case ONClass.extrusion: return .extrusion(try extrusion(&r))
        case ONClass.instanceRef:
            _ = try r.version()
            let id = try r.uuid()
            return .instance(id, R3Xform(m: try (0..<16).map { _ in try r.f64() }))
        default: break
        }
        if let c = try curve(uuid, &r) { return .curve(c) }
        if let s = try surface(uuid, &r) { return .surface(s) }
        // Points and point clouds by object type (ON::point_object = 1, pointset_object = 2).
        if type == 1 {
            _ = try r.version()
            return .point(try r.vec())
        }
        if type == 2 {
            _ = try r.version()
            let n = try r.i32()
            guard n >= 0, n <= r.left / 24 else { throw Rhino3DMError("Bad point cloud.") }
            return .pointCloud(try (0..<n).map { _ in try r.vec() })
        }
        return .unsupported(typeName(type))
    }

    static func typeName(_ t: Int) -> String {
        switch t {
        case 0x200: return "annotation"
        case 0x400: return "text dot"
        case 0x10000: return "hatch"
        case 0x80000: return "light"
        case 0x4000_0000: return "extrusion"
        case Int(Int32.min), 0x8000_0000: return "SubD"
        case 0x20000: return "morph control"
        case 0x1000: return "block instance"
        case 0x100: return "clipping plane"
        default: return "object type \(t)"
        }
    }

    /// Reads a class chunk and returns its curve.
    static func curveObject(_ r: inout R3Reader) throws -> R3Curve? {
        guard let (uuid, d) = try classChunk(&r) else { return nil }
        var dd = d
        return try curve(uuid, &dd)
    }

    static func curve(_ uuid: String, _ r: inout R3Reader) throws -> R3Curve? {
        switch uuid {
        case ONClass.nurbsCurve, ONClass.nurbsCurveLegacy:
            _ = try r.version()
            let dim = try r.i32(), rat = try r.i32(), order = try r.i32(), cvCount = try r.i32()
            _ = try r.i32(); _ = try r.i32()
            try r.skip(48)
            let knots = try r.doubleArray()
            let n = try r.i32()
            guard dim >= 1, dim <= 3, order >= 2, n == cvCount, n >= order, knots.count == order + n - 2, n <= r.left / 8 else { throw Rhino3DMError("Bad NURBS curve.") }
            var pts: [Vec3] = [], w: [Double] = []
            for _ in 0..<n {
                let c = try (0..<(dim + (rat != 0 ? 1 : 0))).map { _ in try r.f64() }
                let wt = rat != 0 ? c[dim] : 1
                let s = abs(wt) > 1e-300 ? 1 / wt : 1
                pts.append(Vec3(c[0] * s, dim > 1 ? c[1] * s : 0, dim > 2 ? c[2] * s : 0))
                w.append(wt)
            }
            let full = [knots[0]] + knots + [knots[knots.count - 1]]
            let b = StepBSplineCurve(degree: order - 1, points: pts, weights: rat != 0 ? w : nil, knots: full)
            guard b.isValid else { throw Rhino3DMError("Bad NURBS curve.") }
            return .nurbs(b)
        case ONClass.lineCurve:
            _ = try r.version()
            let a = try r.vec(), b = try r.vec()
            let t = try r.interval()
            return .line(a, b, t.0, t.1)
        case ONClass.arcCurve:
            _ = try r.version()
            let o = try r.vec(), x = try r.vec(), y = try r.vec()
            try r.skip(56)                                     // z axis and plane equation
            let rad = try r.f64()
            try r.skip(72)                                     // three obsolete points
            let ang = try r.interval(), t = try r.interval()
            return .arc(o, x.normalized, y.normalized, rad, ang, t)
        case ONClass.polylineCurve:
            _ = try r.version()
            let n = try r.i32()
            guard n >= 0, n <= r.left / 24 else { throw Rhino3DMError("Bad polyline.") }
            let p = try (0..<n).map { _ in try r.vec() }
            let t = try r.doubleArray()
            return .polyline(p, t)
        case ONClass.polyCurve:
            _ = try r.version()
            let n = try r.i32()
            _ = try r.i32(); _ = try r.i32()
            try r.skip(48)
            let t = try r.doubleArray()
            guard n >= 0, n < 1_000_000 else { throw Rhino3DMError("Bad polycurve.") }
            var segs: [R3Curve] = []
            for _ in 0..<n { if let c = try curveObject(&r) { segs.append(c) } else { throw Rhino3DMError("Bad polycurve segment.") } }
            return .poly(segs, t.count == segs.count + 1 ? t : (0...segs.count).map(Double.init))
        default: return nil
        }
    }

    static func surface(_ uuid: String, _ r: inout R3Reader) throws -> R3Surface? {
        switch uuid {
        case ONClass.nurbsSurface, ONClass.nurbsSurface2:
            _ = try r.version()
            let dim = try r.i32(), rat = try r.i32()
            let o0 = try r.i32(), o1 = try r.i32(), c0 = try r.i32(), c1 = try r.i32()
            _ = try r.i32(); _ = try r.i32()
            try r.skip(48)
            let k0 = try r.doubleArray(), k1 = try r.doubleArray()
            let n = try r.i32()
            guard dim == 3 || dim == 2, o0 >= 2, o1 >= 2, c0 >= o0, c1 >= o1, n == c0 * c1, k0.count == o0 + c0 - 2, k1.count == o1 + c1 - 2,
                  n <= r.left / 8 else { throw Rhino3DMError("Bad NURBS surface.") }
            let size = dim + (rat != 0 ? 1 : 0)
            var pts = [[Vec3]](repeating: [], count: c0), w = [[Double]](repeating: [], count: c0)
            for i in 0..<c0 {
                for _ in 0..<c1 {
                    let c = try (0..<size).map { _ in try r.f64() }
                    let wt = rat != 0 ? c[dim] : 1
                    let s = abs(wt) > 1e-300 ? 1 / wt : 1
                    pts[i].append(Vec3(c[0] * s, c[1] * s, dim > 2 ? c[2] * s : 0))
                    w[i].append(wt)
                }
            }
            let s = StepBSplineSurface(du: o0 - 1, dv: o1 - 1, points: pts, weights: rat != 0 ? w : nil,
                                       ku: [k0[0]] + k0 + [k0[k0.count - 1]], kv: [k1[0]] + k1 + [k1[k1.count - 1]])
            guard s.isValid else { throw Rhino3DMError("Bad NURBS surface.") }
            return .nurbs(s)
        case ONClass.planeSurface:
            let (_, minor) = try r.version()
            let o = try r.vec(), x = try r.vec(), y = try r.vec()
            try r.skip(56)
            let d0 = try r.interval(), d1 = try r.interval()
            var e0 = d0, e1 = d1
            if minor >= 1 { e0 = try r.interval(); e1 = try r.interval() }
            return .plane(o, x, y, d0, d1, e0, e1)
        case ONClass.revSurface:
            let (major, _) = try r.version()
            guard major == 2 else { throw Rhino3DMError("Unsupported revolution surface version.") }
            let a0 = try r.vec(), a1 = try r.vec()
            let ang = try r.interval(), t = try r.interval()
            try r.skip(48)
            let tr = try r.i32() != 0
            guard try r.u8() != 0, let c = try curveObject(&r) else { throw Rhino3DMError("Revolution surface without a profile.") }
            return .rev(a0, a1, ang, t, c, tr)
        case ONClass.sumSurface:
            _ = try r.version()
            let base = try r.vec()
            try r.skip(48)
            guard let c0 = try curveObject(&r), let c1 = try curveObject(&r) else { throw Rhino3DMError("Bad sum surface.") }
            return .sum(c0, c1, base)
        default: return nil
        }
    }

    /// ON_Mesh (chunk version 3.x: float vertices in compressed buffers).
    static func mesh(_ r: inout R3Reader) throws -> R3Mesh {
        let (major, _) = try r.version()
        guard major == 3 else { throw Rhino3DMError("Unsupported mesh version \(major).") }
        let vc = try r.i32(), fc = try r.i32()
        guard vc >= 0, fc >= 0 else { throw Rhino3DMError("Bad mesh.") }
        try r.skip(80 + 64)                                    // texture/surface domains, scale, boxes
        _ = try r.i32()                                        // closed
        if try r.u8() != 0 { _ = try r.chunk() }               // mesh parameters
        for _ in 0..<4 { if try r.u8() != 0 { _ = try r.chunk() } }   // curvature statistics
        let isz = try r.i32()
        guard [1, 2, 4].contains(isz), fc <= r.left / (4 * isz) else { throw Rhino3DMError("Bad mesh faces.") }
        var faces = [Int](repeating: 0, count: 4 * fc)
        for i in 0..<(4 * fc) {
            switch isz {
            case 1: faces[i] = Int(try r.u8())
            case 2: faces[i] = Int(try r.u16())
            default: faces[i] = try r.i32()
            }
        }
        let vbytes = try buffer(&r)
        guard vbytes.count >= 12 * vc else { throw Rhino3DMError("Mesh vertices missing.") }
        var m = R3Mesh()
        m.vertices.reserveCapacity(vc)
        var vr = R3Reader(vbytes, big: false)
        for _ in 0..<vc { m.vertices.append(Vec3(try vr.f32(), try vr.f32(), try vr.f32())) }
        m.triangles.reserveCapacity(6 * fc)
        for f in 0..<fc {
            let a = faces[4 * f], b = faces[4 * f + 1], c = faces[4 * f + 2], d = faces[4 * f + 3]
            guard a < vc, b < vc, c < vc, d < vc, a >= 0, b >= 0, c >= 0, d >= 0 else { continue }
            if a != b && b != c && a != c { m.triangles += [a, b, c] }
            if c != d && a != d && a != c { m.triangles += [a, c, d] }
        }
        return m
    }

    /// ON_BinaryArchive compressed buffer: size, CRC, method (0 raw, 1 zlib in an anonymous chunk).
    static func buffer(_ r: inout R3Reader) throws -> [UInt8] {
        let size = Int(try r.u32())
        guard size > 0 else { return [] }
        _ = try r.u32()
        let method = try r.u8()
        if method == 0 {
            try r.need(size)
            defer { r.p += size }
            return Array(r.d[r.p..<(r.p + size)])
        }
        let (_, _, body) = try r.chunk()
        guard let b = body, let out = R3Zlib.inflate(b.d[b.p..<b.end]), out.count >= size else { throw Rhino3DMError("Cannot inflate a 3DM buffer.") }
        return out
    }

    static func brep(_ r: inout R3Reader) throws -> R3Brep {
        let (major, minor) = try r.version()
        guard major == 3 else { throw Rhino3DMError("Unsupported B-rep version \(major).\(minor).") }
        var b = R3Brep()
        func array(_ body: (inout R3Reader, Int) throws -> Void) throws {
            let (_, _, cb) = try r.chunk()
            guard var c = cb else { return }
            _ = try c.version()
            let n = try c.i32()
            guard n >= 0, n <= c.left else { throw Rhino3DMError("Bad B-rep array.") }
            for i in 0..<n { try body(&c, i) }
        }
        try array { c, _ in b.c2.append(try c.i32() != 0 ? try? curveObject(&c) : nil) }
        _ = try r.chunk()                                      // 3D edge curves
        try array { c, _ in
            if try c.i32() != 0, let (u, d) = try classChunk(&c) { var dd = d; b.surfaces.append(try? surface(u, &dd)) } else { b.surfaces.append(nil) }
        }
        _ = try r.chunk(); _ = try r.chunk()                   // vertices, edges
        try array { c, _ in
            _ = try c.i32()
            let c2i = try c.i32()
            let d = try c.interval()
            try c.skip(16)                                     // edge, vertices, 3D reversal
            let type = try c.i32()
            try c.skip(4 + 4 + 16 + 48 + 16)                   // iso, loop, tolerances, parameter box, legacy tolerances
            b.trims.append(R3Brep.Trim(c2: c2i, d: d, type: type))
        }
        try array { c, _ in
            _ = try c.i32()
            let ti = try c.intArray()
            let type = try c.i32()
            _ = try c.i32()
            b.loops.append(R3Brep.Loop(trims: ti, type: type))
        }
        try array { c, _ in
            _ = try c.i32()
            let li = try c.intArray()
            let si = try c.i32()
            let rev = try c.i32() != 0
            _ = try c.i32()                                    // material channel
            b.faces.append(R3Brep.Face(loops: li, surface: si, reversed: rev))
        }
        try r.skip(48)
        if minor >= 1, r.left > 0 {
            let (_, _, cb) = try r.chunk()
            if var c = cb {
                for _ in 0..<b.faces.count {
                    guard c.left > 0 else { break }
                    if try c.u8() != 0, let (u, d) = try classChunk(&c), u == ONClass.mesh { var dd = d; b.renderMeshes.append(try? mesh(&dd)) }
                    else { b.renderMeshes.append(nil) }
                }
            }
        }
        return b
    }

    static func extrusion(_ r: inout R3Reader) throws -> R3Extrusion {
        let (_, _, cb) = try r.chunk()
        guard var c = cb else { throw Rhino3DMError("Bad extrusion.") }
        _ = try c.i32()
        let minor = try c.i32()
        guard let profile = try curveObject(&c) else { throw Rhino3DMError("Extrusion without a profile.") }
        let from = try c.vec(), to = try c.vec()
        let t = try c.interval()
        let up = try c.vec()
        try c.skip(2 + 48 + 16 + 1)                            // mitre flags and normals, path domain, transposed
        var count = 1
        if minor >= 1 { count = try c.i32() }
        var caps = (true, true)
        if minor >= 2 { caps = (try c.u8() != 0, try c.u8() != 0) }
        var profiles = [profile]
        if count > 1, case .poly(let segs, _) = profile { profiles = segs }
        return R3Extrusion(profiles: profiles, from: from, to: to, up: up, t: t, caps: caps)
    }
}

extension Rhino3DMParser {
    public struct CRCReport: Hashable { public var leaves = 0, containers = 0, mixed = 0; public var failures: [String] = [] }

    /// Checks the CRC-32 of every CRC chunk whose content can be classified: leaf chunks (plain data) must carry the
    /// CRC of their body, pure containers (only sub-chunks) the CRC of nothing (0), as openNURBS computes CRCs over
    /// the bytes written directly in a chunk. Chunks mixing data and sub-chunks are counted but not checked.
    static func checkCRC(_ data: Data) throws -> CRCReport {
        let b = [UInt8](data)
        guard b.count >= 32, String(decoding: b[0..<24], as: UTF8.self) == header,
              let ver = Int(String(decoding: b[24..<32], as: UTF8.self).trimmingCharacters(in: .whitespaces)) else { throw Rhino3DMError("Not a Rhino 3DM file.") }
        let big = ver >= 50
        let h = big ? 12 : 8
        var rep = CRCReport()
        func value(_ o: Int) -> Int64 {
            if big { var v: UInt64 = 0; for i in 0..<8 { v |= UInt64(b[o + i]) << (8 * UInt64(i)) }; return Int64(bitPattern: v) }
            var v: UInt32 = 0; for i in 0..<4 { v |= UInt32(b[o + i]) << (8 * UInt32(i)) }; return Int64(Int32(bitPattern: v))
        }
        func tcode(_ o: Int) -> UInt32 { UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 }
        /// Chunks tiling [from, to) exactly, or nil.
        func tiles(_ from: Int, _ to: Int) -> [(Int, UInt32, Int)]? {
            var o = from
            var out: [(Int, UInt32, Int)] = []
            guard to - from >= h else { return nil }
            while o < to {
                guard o + h <= to else { return nil }
                let tc = tcode(o)
                guard tc & 0x7FFF_0000 != 0 || tc == TC.endOfTable || tc == TC.comment || tc == TC.endOfFile || tc == 0x7FFE else { return nil }
                if tc & TC.short != 0 { out.append((o, tc, 0)); o += h; continue }
                let v = value(o + 4)
                guard v >= 0, Int64(o + h) + v <= Int64(to) else { return nil }
                out.append((o, tc, Int(v)))
                o += h + Int(v)
            }
            return out
        }
        /// True when a nested anonymous chunk starts inside the range (data mixed with sub-chunks).
        func containsChunk(_ from: Int, _ to: Int) -> Bool {
            var o = from
            while o + h <= to {
                if tcode(o) == TC.anonymous || tcode(o) == TC.classChunk { let v = value(o + 4); if v >= 0, Int64(o + h) + v <= Int64(to) { return true } }
                o += 1
            }
            return false
        }
        func walk(_ from: Int, _ to: Int, depth: Int) {
            guard depth < 64, let list = tiles(from, to) else { return }
            for (o, tc, len) in list where tc & TC.short == 0 {
                let body = o + h, hasCRC = tc & TC.crc != 0 && len >= 4
                let end = body + len - (hasCRC ? 4 : 0)
                let tiled = tc != TC.comment && tiles(body, end) != nil
                if hasCRC {
                    let stored = tcode(end)
                    if R3CRC.update(0, b[body..<end]) == stored { rep.leaves += 1 }
                    else if tiled && stored == 0 { rep.containers += 1 }
                    else if containsChunk(body, end) { rep.mixed += 1 }
                    else if end - body < 4096, (body + 1..<max(body + 1, end - h + 1)).contains(where: { k in tiles(k, end) != nil && R3CRC.update(0, b[body..<k]) == stored }) { rep.mixed += 1 }
                    else { rep.failures.append(String(format: "%08X at %d", tc, o)) }
                }
                if tiled { walk(body, end, depth: depth + 1) }
            }
        }
        walk(32, b.count, depth: 0)
        return rep
    }
}
