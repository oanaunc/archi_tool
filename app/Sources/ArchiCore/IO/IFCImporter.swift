// Oanarina Archi Tool — GPL-3.0-or-later
// IFC (IFC2x3 / IFC4 STEP) importer. Attribute positions follow the IFC4 schema (buildingSMART).
// Walls, slabs, columns, beams, doors, windows, openings and spaces with extruded bodies become native BIM
// elements; every other product (or a body we cannot map) becomes a triangle-mesh solid entity.
import Foundation

public struct IFCImportOptions {
    /// Store property set values as element props ("Pset_WallCommon.IsExternal"); "Archi_Properties" are always restored.
    public var importPropertySets = true
    /// Import products that are not mapped to BIM elements as mesh solids.
    public var meshUnsupported = true
    public init() {}
}

public struct IFCImportResult {
    public var doc: ArchiDocument
    /// Counts by created kind ("wall", "slab", …, "mesh").
    public var stats: [String: Int]
    public var warnings: [String]
    public var schema: String
    public var summary: String {
        let parts = stats.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        return "IFC (\(schema.isEmpty ? "unknown schema" : schema)): " + (parts.isEmpty ? "nothing imported" : parts.joined(separator: ", "))
    }
}

/// Right-handed 3D frame (origin + axes) used to resolve IFC placements.
public struct Frame3: Hashable {
    public var o: Vec3, x: Vec3, y: Vec3, z: Vec3
    public init(o: Vec3 = .zero, x: Vec3 = Vec3(1, 0, 0), y: Vec3 = Vec3(0, 1, 0), z: Vec3 = Vec3(0, 0, 1)) { self.o = o; self.x = x; self.y = y; self.z = z }
    public static let identity = Frame3()
    public func apply(_ p: Vec3) -> Vec3 { o + x * p.x + y * p.y + z * p.z }
    public func dir(_ v: Vec3) -> Vec3 { x * v.x + y * v.y + z * v.z }
    /// `self ∘ child`: the child frame expressed in this frame's parent space.
    public func compose(_ c: Frame3) -> Frame3 { Frame3(o: apply(c.o), x: dir(c.x), y: dir(c.y), z: dir(c.z)) }
}

public enum IFCImporter {
    /// Parses IFC text into a new document (millimetres).
    public static func read(_ text: String, options: IFCImportOptions = IFCImportOptions()) throws -> ArchiDocument {
        try importFile(text, options: options).doc
    }

    public static func importFile(_ text: String, options: IFCImportOptions = IFCImportOptions()) throws -> IFCImportResult {
        let f = try STEPParser.parse(text)
        guard f.schema.uppercased().hasPrefix("IFC") || f.entities.values.contains(where: { $0.type == "IFCPROJECT" }) else { throw STEPError.notSTEP }
        let r = IFCReader(file: f, options: options)
        r.run()
        return IFCImportResult(doc: r.doc, stats: r.stats, warnings: r.warnings, schema: f.schema)
    }
}

/// Simple triangle soup.
struct TriMesh {
    var v: [Vec3] = []
    var t: [Int] = []
    var isEmpty: Bool { t.isEmpty }
    mutating func append(_ m: TriMesh) { let b = v.count; v += m.v; t += m.t.map { $0 + b } }
    mutating func polygon(_ pts3: [Vec3], holes: [[Vec3]] = []) {
        guard pts3.count >= 3 else { return }
        let n = Mesh.polygonNormal(pts3)
        guard n.length > 0.5 else { return }
        let (u, w) = Mesh.basis(n)
        let d = pts3[0].dot(n)
        let flat = pts3.map { Vec2($0.dot(u), $0.dot(w)) }
        let hf = holes.filter { $0.count >= 3 }.map { $0.map { Vec2($0.dot(u), $0.dot(w)) } }
        let r = Triangulator.triangulateWithPoints(flat, holes: hf)
        let base = v.count
        v += r.points.map { u * $0.x + w * $0.y + n * d }
        for tr in r.triangles {
            // keep the input winding (triangulator outputs CCW in the (u, w) basis, which faces +n)
            t += [base + tr.0, base + tr.1, base + tr.2]
        }
    }
    var bounds: BBox3 { var b = BBox3.empty; for i in t where i < v.count { b.add(v[i]) }; return b }
}

struct IFCProfile {
    var outer: [Vec2]
    var holes: [[Vec2]] = []
    /// Rectangle description when the profile is (or reduces to) a rectangle.
    var rect: (center: Vec2, u: Vec2, a: Double, b: Double)?
    var circleRadius: Double?
    var circleCenter: Vec2?
}

struct IFCExtrusion {
    var profile: IFCProfile
    /// Solid position frame in world space.
    var frame: Frame3
    /// Extrusion direction in world space (unit).
    var dir: Vec3
    var depth: Double
}

final class IFCReader {
    let f: STEPFile
    let options: IFCImportOptions
    var doc = ArchiDocument()
    var stats: [String: Int] = [:]
    var warnings: [String] = []
    var scale = 1000.0      // file length unit → mm
    var angleScale = 1.0    // file plane-angle unit → radians
    var placementCache: [Int: Frame3] = [:]

    var storeyOf: [Int: Int] = [:]          // product → storey entity
    var parentOf: [Int: Int] = [:]          // part → aggregate parent
    var voidsHost: [Int: Int] = [:]         // opening → host element
    var fillsOpening: [Int: Int] = [:]      // door/window → opening
    var materialOf: [Int: Int] = [:]        // product → material select
    var psetsOf: [Int: [Int]] = [:]
    var typeOf: [Int: Int] = [:]
    var levelOfStorey: [Int: Int] = [:]
    var elementOf: [Int: EntityID] = [:]    // IFC product → element id

    init(file: STEPFile, options: IFCImportOptions) {
        f = file; self.options = options
        doc.units = .millimeters
        doc.elements = []; doc.entities = []
    }

    func e(_ v: StepValue) -> StepEntity? { v.ref.flatMap { f.entities[$0] } }
    func bump(_ k: String) { stats[k, default: 0] += 1 }

    // MARK: units & basic geometry

    func readUnits() {
        guard let proj = f.all("IFCPROJECT").first, let ua = e(proj[8]) else { return }
        for u in ua[0].list ?? [] {
            guard let ue = e(u) else { continue }
            let kind = ue.type == "IFCSIUNIT" ? ue[1].enumValue : ue[1].enumValue
            switch (ue.type, kind) {
            case ("IFCSIUNIT", "LENGTHUNIT"): scale = siFactor(ue) * 1000
            case ("IFCSIUNIT", "PLANEANGLEUNIT"): angleScale = 1
            case ("IFCCONVERSIONBASEDUNIT", "LENGTHUNIT"), ("IFCCONVERSIONBASEDUNITWITHOFFSET", "LENGTHUNIT"):
                if let m = e(ue[3]) { let v = m[0].double ?? 1; let base = e(m[1]).map { siFactor($0) } ?? 1; scale = v * base * 1000 }
                else if let n = ue[2].string?.uppercased() { scale = n.contains("FOOT") ? 304.8 : (n.contains("INCH") ? 25.4 : scale) }
            case ("IFCCONVERSIONBASEDUNIT", "PLANEANGLEUNIT"):
                if let m = e(ue[3]) { angleScale = (m[0].double ?? .pi / 180) * (e(m[1]).map { siFactor($0) } ?? 1) } else { angleScale = .pi / 180 }
            default: break
            }
        }
    }

    func siFactor(_ u: StepEntity) -> Double {
        switch u[2].enumValue ?? "" {
        case "EXA": return 1e18
        case "PETA": return 1e15
        case "TERA": return 1e12
        case "GIGA": return 1e9
        case "MEGA": return 1e6
        case "KILO": return 1e3
        case "HECTO": return 1e2
        case "DECA": return 1e1
        case "DECI": return 1e-1
        case "CENTI": return 1e-2
        case "MILLI": return 1e-3
        case "MICRO": return 1e-6
        default: return 1
        }
    }

    func coords(_ v: StepValue) -> [Double] { (v.list ?? []).compactMap { $0.double } }
    func point3(_ v: StepValue) -> Vec3? {
        guard let p = e(v), p.type == "IFCCARTESIANPOINT" else { return nil }
        let c = coords(p[0])
        guard c.count >= 2 else { return nil }
        return Vec3(c[0] * scale, c[1] * scale, (c.count > 2 ? c[2] : 0) * scale)
    }
    func point2(_ v: StepValue) -> Vec2? { point3(v)?.xy }
    func dir3(_ v: StepValue) -> Vec3? {
        guard let d = e(v), d.type == "IFCDIRECTION" else { return nil }
        let c = coords(d[0])
        guard c.count >= 2 else { return nil }
        let r = Vec3(c[0], c[1], c.count > 2 ? c[2] : 0)
        return r.length > 1e-12 ? r.normalized : nil
    }

    func axisFrame(_ v: StepValue) -> Frame3 {
        guard let a = e(v) else { return .identity }
        switch a.type {
        case "IFCAXIS2PLACEMENT3D":
            let o = point3(a[0]) ?? .zero
            let z = dir3(a[1]) ?? Vec3(0, 0, 1)
            var x = dir3(a[2]) ?? (abs(z.z) > 0.999 ? Vec3(1, 0, 0) : Vec3(0, 0, 1).cross(z))
            x = (x - z * x.dot(z)).normalized
            if x.length < 0.5 { x = abs(z.x) < 0.9 ? Vec3(1, 0, 0) : Vec3(0, 1, 0); x = (x - z * x.dot(z)).normalized }
            return Frame3(o: o, x: x, y: z.cross(x).normalized, z: z)
        case "IFCAXIS2PLACEMENT2D":
            let o = point3(a[0]) ?? .zero
            var x = dir3(a[1]) ?? Vec3(1, 0, 0)
            x = Vec3(x.x, x.y, 0).normalized
            if x.length < 0.5 { x = Vec3(1, 0, 0) }
            return Frame3(o: o, x: x, y: Vec3(-x.y, x.x, 0), z: Vec3(0, 0, 1))
        case "IFCAXIS1PLACEMENT":
            return Frame3(o: point3(a[0]) ?? .zero)
        default: return .identity
        }
    }

    /// Cartesian transformation operator (mapped items, derived profiles).
    func cto(_ v: StepValue) -> Frame3 {
        guard let t = e(v) else { return .identity }
        let x = dir3(t[0]) ?? Vec3(1, 0, 0)
        let o = point3(t[2]) ?? .zero
        let s = t[3].double ?? 1
        if t.type.hasPrefix("IFCCARTESIANTRANSFORMATIONOPERATOR2D") {
            let y = dir3(t[1]) ?? Vec3(-x.y, x.x, 0)
            let s2 = t.type.contains("NONUNIFORM") ? (t[4].double ?? s) : s
            return Frame3(o: o, x: x * s, y: y * s2, z: Vec3(0, 0, 1))
        }
        let z = dir3(t[4]) ?? Vec3(0, 0, 1)
        let y = dir3(t[1]) ?? z.cross(x).normalized
        var s2 = s, s3 = s
        if t.type.contains("NONUNIFORM") { s2 = t[5].double ?? s; s3 = t[6].double ?? s }
        return Frame3(o: o, x: x * s, y: y * s2, z: z * s3)
    }

    func placement(_ v: StepValue) -> Frame3 {
        guard let id = v.ref, let p = f.entities[id] else { return .identity }
        if let c = placementCache[id] { return c }
        var r = Frame3.identity
        if p.type == "IFCLOCALPLACEMENT" {
            placementCache[id] = .identity // cycle guard
            let parent = p[0].isNull ? Frame3.identity : placement(p[0])
            r = parent.compose(axisFrame(p[1]))
        }
        placementCache[id] = r
        return r
    }

    // MARK: curves and profiles

    func curve2D(_ v: StepValue, depth: Int = 0) -> [Vec2] {
        guard depth < 16, let c = e(v) else { return [] }
        switch c.type {
        case "IFCPOLYLINE":
            return (c[0].list ?? []).compactMap { point2($0) }
        case "IFCINDEXEDPOLYCURVE":
            guard let pl = e(c[0]) else { return [] }
            let pts = (pl[0].list ?? []).compactMap { l -> Vec2? in
                let q = coords(l); return q.count >= 2 ? Vec2(q[0] * scale, q[1] * scale) : nil
            }
            guard let segs = c[1].list, !segs.isEmpty else { return pts }
            var out: [Vec2] = []
            func add(_ p: Vec2) { if let l = out.last, l.isClose(p, tol: 1e-6) { return }; out.append(p) }
            for s in segs {
                guard case .typed(let name, let args) = s else { continue }
                let idx = (args.first?.list ?? []).compactMap { $0.double }.map { Int($0) - 1 }.filter { $0 >= 0 && $0 < pts.count }
                if name == "IFCARCINDEX", idx.count == 3 {
                    for p in arc3(pts[idx[0]], pts[idx[1]], pts[idx[2]]) { add(p) }
                } else { for i in idx { add(pts[i]) } }
            }
            return out
        case "IFCCOMPOSITECURVE", "IFCCOMPOSITECURVEONSURFACE":
            var out: [Vec2] = []
            for s in c[0].list ?? [] {
                guard let seg = e(s) else { continue }
                var pts = curve2D(seg[2], depth: depth + 1)
                if seg[1].enumValue == "F" { pts.reverse() }
                for p in pts where !(out.last.map { $0.isClose(p, tol: 1e-6) } ?? false) { out.append(p) }
            }
            return out
        case "IFCTRIMMEDCURVE":
            guard let basis = e(c[0]) else { return [] }
            let sense = c[3].enumValue != "F"
            if basis.type == "IFCCIRCLE" || basis.type == "IFCELLIPSE" {
                let fr = axisFrame(basis[0])
                let r1 = (basis[1].double ?? 0) * scale
                let r2 = basis.type == "IFCELLIPSE" ? (basis[2].double ?? 0) * scale : r1
                func angle(_ trims: StepValue) -> Double? {
                    for t in trims.list ?? [] {
                        if case .typed(let n, let a) = t, n == "IFCPARAMETERVALUE", let d = a.first?.double { return d * angleScale }
                    }
                    for t in trims.list ?? [] {
                        if let p = point3(t) {
                            let q = p - fr.o
                            return atan2(q.dot(fr.y) / max(r2, 1e-9), q.dot(fr.x) / max(r1, 1e-9))
                        }
                    }
                    return nil
                }
                guard let a0 = angle(c[1]), let a1 = angle(c[2]) else { return [] }
                var sweep = sense ? normAngle(a1 - a0) : -normAngle(a0 - a1)
                if abs(sweep) < 1e-9 { sweep = sense ? 2 * .pi : -2 * .pi }
                let n = max(4, Int(abs(sweep) / (2 * .pi) * 48))
                return (0...n).map { i in
                    let t = a0 + sweep * Double(i) / Double(n)
                    return fr.apply(Vec3(r1 * cos(t), r2 * sin(t), 0)).xy
                }
            }
            var pts = curve2D(c[0], depth: depth + 1)
            if !sense { pts.reverse() }
            return pts
        case "IFCCIRCLE", "IFCELLIPSE":
            let fr = axisFrame(c[0])
            let r1 = (c[1].double ?? 0) * scale
            let r2 = c.type == "IFCELLIPSE" ? (c[2].double ?? 0) * scale : r1
            guard r1 > 0, r2 > 0 else { return [] }
            return (0..<48).map { i in let t = 2 * .pi * Double(i) / 48; return fr.apply(Vec3(r1 * cos(t), r2 * sin(t), 0)).xy }
        default:
            return []
        }
    }

    /// Points of the circular arc through three points.
    func arc3(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> [Vec2] {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-12 else { return [a, b, c] }
        let a2 = a.lengthSquared, b2 = b.lengthSquared, c2 = c.lengthSquared
        let ctr = Vec2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d, (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        let r = ctr.distance(to: a)
        let s = (a - ctr).angle
        let ccw = (b - a).cross(c - b) > 0
        let sweep = ccw ? normAngle((c - ctr).angle - s) : -normAngle(s - (c - ctr).angle)
        let n = max(4, Int(abs(sweep) / (2 * .pi) * 48))
        return (0...n).map { ctr + Vec2.polar(r, s + sweep * Double($0) / Double(n)) }
    }

    static func clean(_ pts: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where !(out.last.map { $0.isClose(p, tol: 1e-6) } ?? false) { out.append(p) }
        if out.count > 1, out[0].isClose(out[out.count - 1], tol: 1e-6) { out.removeLast() }
        return out
    }

    /// Rectangle fit of a 4-point loop.
    static func rectangle(_ pts: [Vec2]) -> (center: Vec2, u: Vec2, a: Double, b: Double)? {
        let p = clean(pts)
        guard p.count == 4 else { return nil }
        for i in 0..<4 {
            let e1 = p[(i + 1) % 4] - p[i], e2 = p[(i + 2) % 4] - p[(i + 1) % 4]
            guard e1.length > 1e-6, e2.length > 1e-6, abs(e1.normalized.dot(e2.normalized)) < 1e-4 else { return nil }
        }
        let e0 = p[1] - p[0]
        return ((p[0] + p[2]) / 2, e0.normalized, e0.length, (p[2] - p[1]).length)
    }

    func profile(_ v: StepValue, depth: Int = 0) -> IFCProfile? {
        guard depth < 8, let p = e(v) else { return nil }
        func pos(_ i: Int) -> Frame3 { p[i].isNull ? .identity : axisFrame(p[i]) }
        func tr(_ fr: Frame3, _ q: Vec2) -> Vec2 { fr.apply(Vec3(q.x, q.y, 0)).xy }
        switch p.type {
        case "IFCRECTANGLEPROFILEDEF", "IFCROUNDEDRECTANGLEPROFILEDEF", "IFCRECTANGLEHOLLOWPROFILEDEF":
            let fr = pos(2)
            let a = (p[3].double ?? 0) * scale, b = (p[4].double ?? 0) * scale
            guard a > 0, b > 0 else { return nil }
            let corners = [Vec2(-a / 2, -b / 2), Vec2(a / 2, -b / 2), Vec2(a / 2, b / 2), Vec2(-a / 2, b / 2)]
            var prof = IFCProfile(outer: corners.map { tr(fr, $0) })
            if p.type == "IFCRECTANGLEHOLLOWPROFILEDEF", let t = p[5].double.map({ $0 * scale }), t > 0, t * 2 < min(a, b) {
                prof.holes = [[Vec2(-a / 2 + t, -b / 2 + t), Vec2(-a / 2 + t, b / 2 - t), Vec2(a / 2 - t, b / 2 - t), Vec2(a / 2 - t, -b / 2 + t)].map { tr(fr, $0) }]
            } else {
                prof.rect = (fr.o.xy, fr.x.xy.normalized, a, b)
            }
            return prof
        case "IFCCIRCLEPROFILEDEF", "IFCCIRCLEHOLLOWPROFILEDEF":
            let fr = pos(2)
            let r = (p[3].double ?? 0) * scale
            guard r > 0 else { return nil }
            let n = 32
            var prof = IFCProfile(outer: (0..<n).map { tr(fr, Vec2.polar(r, 2 * .pi * Double($0) / Double(n))) })
            if p.type == "IFCCIRCLEHOLLOWPROFILEDEF", let t = p[4].double.map({ $0 * scale }), t > 0, t < r {
                prof.holes = [(0..<n).reversed().map { tr(fr, Vec2.polar(r - t, 2 * .pi * Double($0) / Double(n))) }]
            } else { prof.circleRadius = r; prof.circleCenter = fr.o.xy }
            return prof
        case "IFCELLIPSEPROFILEDEF":
            let fr = pos(2)
            let a = (p[3].double ?? 0) * scale, b = (p[4].double ?? 0) * scale
            guard a > 0, b > 0 else { return nil }
            return IFCProfile(outer: (0..<32).map { i in let t = 2 * .pi * Double(i) / 32; return tr(fr, Vec2(a * cos(t), b * sin(t))) })
        case "IFCISHAPEPROFILEDEF":
            let fr = pos(2)
            let w = (p[3].double ?? 0) * scale, d = (p[4].double ?? 0) * scale
            let tw = (p[5].double ?? 0) * scale, tf = (p[6].double ?? 0) * scale
            guard w > 0, d > 0, tw > 0, tf > 0, tw < w, 2 * tf < d else { return nil }
            let pts = [Vec2(-w / 2, -d / 2), Vec2(w / 2, -d / 2), Vec2(w / 2, -d / 2 + tf), Vec2(tw / 2, -d / 2 + tf), Vec2(tw / 2, d / 2 - tf),
                       Vec2(w / 2, d / 2 - tf), Vec2(w / 2, d / 2), Vec2(-w / 2, d / 2), Vec2(-w / 2, d / 2 - tf), Vec2(-tw / 2, d / 2 - tf),
                       Vec2(-tw / 2, -d / 2 + tf), Vec2(-w / 2, -d / 2 + tf)]
            var prof = IFCProfile(outer: pts.map { tr(fr, $0) })
            prof.rect = (fr.o.xy, fr.x.xy.normalized, w, d)
            return prof
        case "IFCARBITRARYCLOSEDPROFILEDEF", "IFCARBITRARYPROFILEDEFWITHVOIDS":
            let outer = IFCReader.clean(curve2D(p[2]))
            guard outer.count >= 3 else { return nil }
            var prof = IFCProfile(outer: outer)
            if p.type == "IFCARBITRARYPROFILEDEFWITHVOIDS" {
                prof.holes = (p[3].list ?? []).map { IFCReader.clean(curve2D($0)) }.filter { $0.count >= 3 }
            }
            if prof.holes.isEmpty { prof.rect = IFCReader.rectangle(outer) }
            return prof
        case "IFCDERIVEDPROFILEDEF":
            guard var parent = profile(p[2], depth: depth + 1) else { return nil }
            let t = cto(p[3])
            parent.outer = parent.outer.map { tr(t, $0) }
            parent.holes = parent.holes.map { $0.map { tr(t, $0) } }
            parent.rect = IFCReader.rectangle(parent.outer)
            parent.circleRadius = nil
            return parent
        case "IFCCOMPOSITEPROFILEDEF":
            return (p[2].list ?? []).lazy.compactMap { self.profile($0, depth: depth + 1) }.first
        default:
            return nil
        }
    }

    // MARK: representation items → meshes

    func bodyItems(_ product: StepEntity) -> [StepValue] {
        guard let pds = e(product[6]) else { return [] }
        let reps = (pds[2].list ?? []).compactMap { e($0) }
        let body = reps.first { ($0[1].string ?? "").lowercased() == "body" }
            ?? reps.first { !["CURVE2D", "CURVE", "GEOMETRICCURVESET", "ANNOTATION2D", "POINT", "BOUNDINGBOX"].contains(($0[2].string ?? "").uppercased()) && ($0[1].string ?? "").lowercased() != "axis" && ($0[1].string ?? "").lowercased() != "footprint" }
        return body?[3].list ?? []
    }

    func mesh(_ v: StepValue, _ fr: Frame3, depth: Int = 0) -> TriMesh {
        var m = TriMesh()
        guard depth < 12, let it = e(v) else { return m }
        switch it.type {
        case "IFCEXTRUDEDAREASOLID", "IFCEXTRUDEDAREASOLIDTAPERED":
            if let x = extrusion(it, fr) { m = prism(x) }
        case "IFCFACETEDBREP", "IFCFACETEDBREPWITHVOIDS":
            if let sh = e(it[0]) { m = faces(sh[0], fr) }
        case "IFCCLOSEDSHELL", "IFCOPENSHELL", "IFCCONNECTEDFACESET":
            m = faces(it[0], fr)
        case "IFCSHELLBASEDSURFACEMODEL", "IFCFACEBASEDSURFACEMODEL":
            for s in it[0].list ?? [] { if let sh = e(s) { m.append(faces(sh[0], fr)) } }
        case "IFCTRIANGULATEDFACESET", "IFCTRIANGULATEDIRREGULARNETWORK":
            m = triangulatedFaceSet(it, fr)
        case "IFCPOLYGONALFACESET":
            m = polygonalFaceSet(it, fr)
        case "IFCBOOLEANRESULT", "IFCBOOLEANCLIPPINGRESULT":
            m = mesh(it[1], fr, depth: depth + 1)
            if it[0].enumValue == "UNION" { m.append(mesh(it[2], fr, depth: depth + 1)) }
        case "IFCMAPPEDITEM":
            guard let src = e(it[0]), let rep = e(src[1]) else { break }
            let t = fr.compose(cto(it[1])).compose(axisFrame(src[0]))
            for sub in rep[3].list ?? [] { m.append(mesh(sub, t, depth: depth + 1)) }
        case "IFCBLOCK":
            let p = fr.compose(axisFrame(it[0]))
            let a = (it[1].double ?? 0) * scale, b = (it[2].double ?? 0) * scale, c = (it[3].double ?? 0) * scale
            m = prism(IFCExtrusion(profile: IFCProfile(outer: [Vec2(0, 0), Vec2(a, 0), Vec2(a, b), Vec2(0, b)]), frame: p, dir: p.z, depth: c))
        case "IFCRIGHTCIRCULARCYLINDER":
            let p = fr.compose(axisFrame(it[0]))
            let h = (it[1].double ?? 0) * scale, r = (it[2].double ?? 0) * scale
            guard r > 0, h > 0 else { break }
            let circle = (0..<32).map { Vec2.polar(r, 2 * .pi * Double($0) / 32) }
            m = prism(IFCExtrusion(profile: IFCProfile(outer: circle), frame: p, dir: p.z, depth: h))
        case "IFCCSGSOLID":
            m = mesh(it[0], fr, depth: depth + 1)
        default: break
        }
        return m
    }

    func extrusion(_ it: StepEntity, _ fr: Frame3) -> IFCExtrusion? {
        guard let prof = profile(it[0]) else { return nil }
        let pos = fr.compose(it[1].isNull ? .identity : axisFrame(it[1]))
        let d = dir3(it[2]) ?? Vec3(0, 0, 1)
        let depth = (it[3].double ?? 0) * scale
        guard depth > 1e-9 else { return nil }
        return IFCExtrusion(profile: prof, frame: pos, dir: pos.dir(d).normalized, depth: depth)
    }

    /// Unwraps a single extruded body (through clipping results) for semantic mapping.
    func singleExtrusion(_ product: StepEntity, _ world: Frame3) -> IFCExtrusion? {
        let items = bodyItems(product)
        guard items.count == 1 else { return nil }
        var cur = e(items[0])
        var guardN = 0
        while let c = cur, c.type == "IFCBOOLEANCLIPPINGRESULT" || (c.type == "IFCBOOLEANRESULT" && c[0].enumValue == "DIFFERENCE"), guardN < 8 {
            cur = e(c[1]); guardN += 1
        }
        guard let c = cur, c.type == "IFCEXTRUDEDAREASOLID" else { return nil }
        return extrusion(c, world)
    }

    func prism(_ x: IFCExtrusion) -> TriMesh {
        var m = TriMesh()
        var outer = IFCReader.clean(x.profile.outer)
        guard outer.count >= 3 else { return m }
        if GeometryOps.signedArea(outer) < 0 { outer.reverse() }
        let holes = x.profile.holes.map { h -> [Vec2] in var hh = IFCReader.clean(h); if GeometryOps.signedArea(hh) > 0 { hh.reverse() }; return hh }.filter { $0.count >= 3 }
        let off = x.dir * x.depth
        func P(_ p: Vec2) -> Vec3 { x.frame.apply(Vec3(p.x, p.y, 0)) }
        let tri = Triangulator.triangulateWithPoints(outer, holes: holes)
        // Orientation: caps face ∓ extrusion direction.
        let flip = x.frame.z.dot(x.dir) < 0
        let base = m.v.count
        m.v += tri.points.map(P)
        m.v += tri.points.map { P($0) + off }
        let n = tri.points.count
        for t in tri.triangles {
            if flip { m.t += [base + t.0, base + t.1, base + t.2]; m.t += [base + n + t.0, base + n + t.2, base + n + t.1] }
            else { m.t += [base + t.0, base + t.2, base + t.1]; m.t += [base + n + t.0, base + n + t.1, base + n + t.2] }
        }
        for loop in [outer] + holes {
            for i in 0..<loop.count {
                let a = P(loop[i]), b = P(loop[(i + 1) % loop.count])
                let k = m.v.count
                m.v += [a, b, b + off, a + off]
                if flip { m.t += [k, k + 2, k + 1, k, k + 3, k + 2] } else { m.t += [k, k + 1, k + 2, k, k + 2, k + 3] }
            }
        }
        return m
    }

    func faces(_ v: StepValue, _ fr: Frame3) -> TriMesh {
        var m = TriMesh()
        for fv in v.list ?? [] {
            guard let face = e(fv) else { continue }
            var outer: [Vec3] = [], holes: [[Vec3]] = []
            for bv in face[0].list ?? [] {
                guard let bnd = e(bv), let loop = e(bnd[0]), loop.type == "IFCPOLYLOOP" else { continue }
                var pts = (loop[0].list ?? []).compactMap { point3($0) }.map { fr.apply($0) }
                if bnd[1].enumValue == "F" { pts.reverse() }
                if bnd.type == "IFCFACEOUTERBOUND" && outer.isEmpty { outer = pts } else { holes.append(pts) }
            }
            if outer.isEmpty, !holes.isEmpty { outer = holes.removeFirst() }
            if outer.count == 3 && holes.isEmpty {
                let k = m.v.count; m.v += outer; m.t += [k, k + 1, k + 2]
            } else { m.polygon(outer, holes: holes) }
        }
        return m
    }

    func pointList3(_ v: StepValue) -> [Vec3] {
        guard let pl = e(v) else { return [] }
        return (pl[0].list ?? []).compactMap { l -> Vec3? in
            let q = coords(l); return q.count >= 3 ? Vec3(q[0] * scale, q[1] * scale, q[2] * scale) : nil
        }
    }

    func triangulatedFaceSet(_ it: StepEntity, _ fr: Frame3) -> TriMesh {
        var m = TriMesh()
        let pts = pointList3(it[0]).map { fr.apply($0) }
        guard !pts.isEmpty else { return m }
        // CoordIndex: first list-of-triples after Coordinates; PnIndex: a flat integer list.
        var coordIndex: [[Int]] = []
        var pn: [Int] = []
        for a in it.args.dropFirst() {
            guard let l = a.list, !l.isEmpty else { continue }
            if coordIndex.isEmpty, let first = l.first?.list, first.count == 3, first.allSatisfy({ if case .int = $0 { return true }; return false }) {
                coordIndex = l.map { ($0.list ?? []).compactMap { $0.double }.map { Int($0) } }
            } else if !coordIndex.isEmpty, l.allSatisfy({ if case .int = $0 { return true }; return false }) {
                pn = l.compactMap { $0.double }.map { Int($0) }
            }
        }
        m.v = pts
        for tri in coordIndex where tri.count == 3 {
            let idx = tri.map { i -> Int in let j = i - 1; return pn.isEmpty ? j : (j >= 0 && j < pn.count ? pn[j] - 1 : -1) }
            guard idx.allSatisfy({ $0 >= 0 && $0 < pts.count }) else { continue }
            m.t += idx
        }
        return m
    }

    func polygonalFaceSet(_ it: StepEntity, _ fr: Frame3) -> TriMesh {
        var m = TriMesh()
        let pts = pointList3(it[0]).map { fr.apply($0) }
        let pn = (it[3].list ?? []).compactMap { $0.double }.map { Int($0) }
        func P(_ i: Int) -> Vec3? {
            let j = i - 1
            let k = pn.isEmpty ? j : (j >= 0 && j < pn.count ? pn[j] - 1 : -1)
            return k >= 0 && k < pts.count ? pts[k] : nil
        }
        for fv in it[2].list ?? [] {
            guard let face = e(fv) else { continue }
            let outer = (face[0].list ?? []).compactMap { $0.double }.compactMap { P(Int($0)) }
            var holes: [[Vec3]] = []
            if face.type == "IFCINDEXEDPOLYGONALFACEWITHVOIDS" {
                holes = (face[1].list ?? []).map { ($0.list ?? []).compactMap { $0.double }.compactMap { P(Int($0)) } }
            }
            if outer.count == 3 && holes.isEmpty { let k = m.v.count; m.v += outer; m.t += [k, k + 1, k + 2] }
            else { m.polygon(outer, holes: holes) }
        }
        return m
    }

    func productMesh(_ p: StepEntity) -> TriMesh {
        let w = placement(p[5])
        var m = TriMesh()
        for it in bodyItems(p) { m.append(mesh(it, w)) }
        return m
    }

    // MARK: relationships

    func readRelationships() {
        for r in f.entities.values {
            switch r.type {
            case "IFCRELCONTAINEDINSPATIALSTRUCTURE":
                guard let s = r[5].ref else { continue }
                for id in r[4].refs { storeyOf[id] = s }
            case "IFCRELAGGREGATES", "IFCRELNESTS":
                guard let parent = r[4].ref else { continue }
                for id in r[5].refs { parentOf[id] = parent }
            case "IFCRELVOIDSELEMENT":
                if let h = r[4].ref, let o = r[5].ref { voidsHost[o] = h }
            case "IFCRELFILLSELEMENT":
                if let o = r[4].ref, let el = r[5].ref { fillsOpening[el] = o }
            case "IFCRELASSOCIATESMATERIAL":
                guard let m = r[5].ref else { continue }
                for id in r[4].refs { materialOf[id] = m }
            case "IFCRELDEFINESBYPROPERTIES":
                guard let ps = r[5].ref else { continue }
                for id in r[4].refs { psetsOf[id, default: []].append(ps) }
            case "IFCRELDEFINESBYTYPE":
                guard let t = r[5].ref else { continue }
                for id in r[4].refs { typeOf[id] = t }
            default: break
            }
        }
    }

    /// Storey entity of a product (walking up aggregates, spaces and hosts).
    func storey(of id: Int) -> Int? {
        var cur = id
        for _ in 0..<16 {
            if let s = storeyOf[cur] {
                if f.entities[s]?.type == "IFCBUILDINGSTOREY" { return s }
                cur = s; continue
            }
            if let p = parentOf[cur] {
                if f.entities[p]?.type == "IFCBUILDINGSTOREY" { return p }
                cur = p; continue
            }
            if let o = fillsOpening[cur], let h = voidsHost[o] { cur = h; continue }
            return nil
        }
        return nil
    }

    // MARK: levels

    func readStoreys() {
        let storeys = f.all("IFCBUILDINGSTOREY")
        guard !storeys.isEmpty else { return }
        var list: [(Int, String, Double)] = storeys.map { s in
            let elev = s[9].double.map { $0 * scale } ?? placement(s[5]).o.z
            return (s.id, s[2].string ?? s[7].string ?? "Level", elev)
        }
        list.sort { $0.2 < $1.2 }
        doc.levels = []
        for (i, s) in list.enumerated() {
            let next = i + 1 < list.count ? list[i + 1].2 : s.2 + 3000
            doc.levels.append(Level(id: i, name: s.1, elevation: s.2, height: max(next - s.2, 1)))
            levelOfStorey[s.0] = i
        }
        doc.currentLevel = 0
    }

    func level(for product: Int, baseZ: Double) -> Int {
        if let s = storey(of: product), let l = levelOfStorey[s] { return l }
        // nearest level at or below the base
        let below = doc.levels.filter { $0.elevation <= baseZ + 1 }.max { $0.elevation < $1.elevation }
        return below?.id ?? doc.levels.first?.id ?? 0
    }
    func elevation(_ level: Int) -> Double { doc.level(level)?.elevation ?? 0 }

    // MARK: materials & properties

    func materialInfo(_ id: Int) -> (name: String?, layerSet: String?, plies: [WallType.Ply]) {
        var mref = materialOf[id]
        if mref == nil, let t = typeOf[id] { mref = materialOf[t] }
        guard let m = mref.flatMap({ f.entities[$0] }) else { return (nil, nil, []) }
        func matName(_ v: StepValue) -> String? { e(v).flatMap { $0.type == "IFCMATERIAL" ? $0[0].string : nil } }
        switch m.type {
        case "IFCMATERIAL": return (m[0].string, nil, [])
        case "IFCMATERIALLAYERSETUSAGE", "IFCMATERIALLAYERSET":
            let set = m.type == "IFCMATERIALLAYERSET" ? m : e(m[0])
            guard let s = set else { return (nil, nil, []) }
            let layers = (s[0].list ?? []).compactMap { e($0) }
            let plies = layers.compactMap { l -> WallType.Ply? in
                guard let n = matName(l[0]), let t = l[1].double, t > 0 else { return nil }
                return WallType.Ply(material: n, thickness: t * scale, function: l[3].string ?? "Structure")
            }
            return (plies.max { $0.thickness < $1.thickness }?.material, s[1].string, plies)
        case "IFCMATERIALLIST": return ((m[0].list ?? []).lazy.compactMap { matName($0) }.first, nil, [])
        case "IFCMATERIALCONSTITUENTSET":
            return ((m[2].list ?? []).lazy.compactMap { self.e($0) }.compactMap { matName($0[2]) }.first ?? m[0].string, nil, [])
        case "IFCMATERIALPROFILESETUSAGE", "IFCMATERIALPROFILESET":
            let set = m.type == "IFCMATERIALPROFILESET" ? m : e(m[0])
            return ((set?[2].list ?? []).lazy.compactMap { self.e($0) }.compactMap { matName($0[2]) }.first, nil, [])
        default: return (nil, nil, [])
        }
    }

    func ensureMaterial(_ name: String?) -> String? {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        if let m = doc.material(n) { return m.name }
        doc.materials.append(Material(name: n, color: RGBA(0.78, 0.78, 0.78)))
        return n
    }

    func properties(_ id: Int) -> [String: String] {
        var out: [String: String] = [:]
        var sets = psetsOf[id] ?? []
        if let t = typeOf[id], let tt = f.entities[t] { sets += (tt[5].list ?? []).compactMap { $0.ref }; if let n = tt[2].string { out["ifcTypeName"] = n } }
        for ps in sets {
            guard let p = f.entities[ps], p.type == "IFCPROPERTYSET" else { continue }
            let setName = p[2].string ?? "Pset"
            let isOurs = setName == "Archi_Properties"
            guard isOurs || options.importPropertySets else { continue }
            for pv in p[4].list ?? [] {
                guard let prop = e(pv), prop.type == "IFCPROPERTYSINGLEVALUE", let n = prop[0].string, let val = prop[2].text else { continue }
                out[isOurs ? n : "\(setName).\(n)"] = val
            }
        }
        return out
    }

    static let defaultNamePattern = try? NSRegularExpression(pattern: "^(Wall|Slab|Column|Beam|Door|Window|Opening|Roof|Stair|Railing|Component|Curtainwall) [0-9]+$")
    func cleanName(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "" }
        if let re = IFCReader.defaultNamePattern, re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return "" }
        return s
    }

    @discardableResult
    func addElement(_ p: StepEntity, _ g: BIMGeometry, level: Int, material: String?, kind: String) -> EntityID {
        let id = doc.addElement(g, level: level, material: ensureMaterial(material), name: cleanName(p[2].string))
        if let i = doc.elementIndex(id) {
            var props = properties(p.id)
            if let guid = p[0].string, !guid.isEmpty { props["ifcGuid"] = guid }
            doc.elements[i].props = props
            if material == nil { doc.elements[i].material = doc.defaultMaterial(for: g) }
        }
        elementOf[p.id] = id
        bump(kind)
        return id
    }

    func addMesh(_ p: StepEntity, _ m: TriMesh) {
        guard options.meshUnsupported, !m.isEmpty else { return }
        let pretty = p.type.hasPrefix("IFC") ? String(p.type.dropFirst(3)).capitalized : p.type.capitalized
        let layer = "IFC-" + pretty
        var props = properties(p.id)
        props["ifcType"] = p.type
        if let g = p[0].string { props["ifcGuid"] = g }
        if let n = p[2].string, !n.isEmpty { props["name"] = n }
        if let mat = ensureMaterial(materialInfo(p.id).name) { props["material"] = mat }
        let z = m.bounds.min.z
        if let lv = doc.level(level(for: p.id, baseZ: z.isFinite ? z : 0)) { props["level"] = lv.name }
        doc.ensureLayer(layer)
        doc.add(Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: m.v, meshTriangles: m.t)), props: props))
        bump("mesh")
    }

    // MARK: run

    static let spatial: Set<String> = ["IFCPROJECT", "IFCSITE", "IFCBUILDING", "IFCBUILDINGSTOREY", "IFCSPACE", "IFCOPENINGELEMENT",
                                       "IFCOPENINGSTANDARDCASE", "IFCGRID", "IFCANNOTATION", "IFCVIRTUALELEMENT", "IFCSPATIALZONE", "IFCEXTERNALSPATIALELEMENT"]

    func isProduct(_ p: StepEntity) -> Bool {
        guard p.args.count >= 7, p[0].string != nil, let pl = e(p[5]), pl.type == "IFCLOCALPLACEMENT" || pl.type == "IFCGRIDPLACEMENT",
              let rep = e(p[6]), rep.type == "IFCPRODUCTDEFINITIONSHAPE" else { return false }
        return true
    }

    func run() {
        readUnits()
        readRelationships()
        readStoreys()
        if let proj = f.all("IFCPROJECT").first {
            if let n = proj[2].string, !n.isEmpty { doc.info.name = n }
            if let n = proj[3].string { doc.info.number = n }
        }
        if let site = f.all("IFCSITE").first {
            func dms(_ v: StepValue) -> Double? {
                let c = (v.list ?? []).compactMap { $0.double }
                guard c.count >= 3 else { return nil }
                let sgn = c.first(where: { $0 != 0 }).map { $0 < 0 ? -1.0 : 1.0 } ?? 1
                return sgn * (abs(c[0]) + abs(c[1]) / 60 + abs(c[2]) / 3600 + (c.count > 3 ? abs(c[3]) / 3.6e9 : 0))
            }
            if let la = dms(site[9]) { doc.info.latitude = la }
            if let lo = dms(site[10]) { doc.info.longitude = lo }
        }

        let products = f.entities.values.filter { isProduct($0) }.sorted { $0.id < $1.id }
        var handled = Set<Int>()
        func typeIs(_ p: StepEntity, _ prefixes: [String]) -> Bool { prefixes.contains { p.type == $0 || p.type == $0 + "STANDARDCASE" || p.type == $0 + "ELEMENTEDCASE" } }

        // Walls first (openings need their hosts).
        for p in products where typeIs(p, ["IFCWALL"]) {
            if wall(p) { handled.insert(p.id) }
        }
        for p in products where !handled.contains(p.id) {
            if typeIs(p, ["IFCSLAB"]) { if slab(p) { handled.insert(p.id) } }
            else if typeIs(p, ["IFCCOLUMN"]) { if column(p) { handled.insert(p.id) } }
            else if typeIs(p, ["IFCBEAM"]) { if beam(p) { handled.insert(p.id) } }
            else if p.type == "IFCSPACE" { if space(p) { handled.insert(p.id) } }
        }
        for p in products where !handled.contains(p.id) && typeIs(p, ["IFCDOOR", "IFCWINDOW"]) {
            if opening(p) { handled.insert(p.id) }
        }
        // Empty openings (voids without a filling) in imported walls.
        let filled = Set(fillsOpening.values)
        for (o, host) in voidsHost.sorted(by: { $0.key < $1.key }) where !filled.contains(o) {
            guard let op = f.entities[o], let wid = elementOf[host] else { continue }
            _ = emptyOpening(op, wallID: wid)
        }
        for p in products where !handled.contains(p.id) && !IFCReader.spatial.contains(p.type) {
            addMesh(p, productMesh(p))
        }
        doc.currentLayer = "0"
    }

    // MARK: element mapping

    func vertical(_ x: IFCExtrusion) -> Bool { abs(abs(x.dir.z) - 1) < 1e-6 && abs(abs(x.frame.z.z) - 1) < 1e-6 }

    /// World-space rectangle from a vertical extrusion: center, unit axis (along the long or first side), sizes, base z.
    func worldRect(_ x: IFCExtrusion) -> (center: Vec2, u: Vec2, a: Double, b: Double, baseZ: Double)? {
        guard let r = x.profile.rect, vertical(x) else { return nil }
        let c = x.frame.apply(Vec3(r.center.x, r.center.y, 0))
        let u3 = x.frame.dir(Vec3(r.u.x, r.u.y, 0))
        let baseZ = x.dir.z > 0 ? c.z : c.z - x.depth
        return (c.xy, u3.xy.normalized, r.a, r.b, baseZ)
    }

    func wall(_ p: StepEntity) -> Bool {
        let w = placement(p[5])
        guard let x = singleExtrusion(p, w), let r = worldRect(x) else { return false }
        let alongU = r.a >= r.b
        let axis = alongU ? r.u : r.u.perp
        let len = max(r.a, r.b), thk = min(r.a, r.b)
        guard len > 1e-6, thk > 1e-6 else { return false }
        let lv = level(for: p.id, baseZ: r.baseZ)
        let info = materialInfo(p.id)
        var wallType: String? = nil
        let candidates = [p[4].string, info.layerSet].compactMap { $0 }.filter { !$0.isEmpty }
        if let t = candidates.first(where: { n in doc.wallTypes.contains { $0.name == n } }) { wallType = t }
        else if let n = info.layerSet, !n.isEmpty, !info.plies.isEmpty {
            doc.wallTypes.append(WallType(name: n, plies: info.plies)); wallType = n
        }
        let g = WallGeom(start: r.center - axis * (len / 2), end: r.center + axis * (len / 2), thickness: thk, height: x.depth,
                         baseOffset: r.baseZ - elevation(lv), wallType: wallType)
        addElement(p, .wall(g), level: lv, material: info.name, kind: "wall")
        return true
    }

    func slab(_ p: StepEntity) -> Bool {
        let w = placement(p[5])
        guard let x = singleExtrusion(p, w), vertical(x) else { return false }
        func P(_ q: Vec2) -> Vec2 { x.frame.apply(Vec3(q.x, q.y, 0)).xy }
        let boundary = IFCReader.clean(x.profile.outer.map(P))
        guard boundary.count >= 3 else { return false }
        let z0 = x.frame.o.z
        let baseZ = x.dir.z > 0 ? z0 : z0 - x.depth
        let lv = level(for: p.id, baseZ: baseZ + x.depth)
        let g = SlabGeom(boundary: boundary, holes: x.profile.holes.map { IFCReader.clean($0.map(P)) }.filter { $0.count >= 3 },
                         thickness: x.depth, topOffset: baseZ + x.depth - elevation(lv))
        addElement(p, .slab(g), level: lv, material: materialInfo(p.id).name, kind: "slab")
        return true
    }

    func column(_ p: StepEntity) -> Bool {
        let w = placement(p[5])
        guard let x = singleExtrusion(p, w), vertical(x) else { return false }
        let lv: Int
        var g: ColumnGeom
        if let r = x.profile.circleRadius, let c0 = x.profile.circleCenter {
            let c = x.frame.apply(Vec3(c0.x, c0.y, 0))
            let baseZ = x.dir.z > 0 ? c.z : c.z - x.depth
            lv = level(for: p.id, baseZ: baseZ)
            g = ColumnGeom(position: c.xy, width: 2 * r, depth: 2 * r, height: x.depth, rotation: 0, round: true, baseOffset: baseZ - elevation(lv))
        } else if let r = worldRect(x) {
            lv = level(for: p.id, baseZ: r.baseZ)
            g = ColumnGeom(position: r.center, width: r.a, depth: r.b, height: x.depth, rotation: normAngle(r.u.angle), baseOffset: r.baseZ - elevation(lv))
            if abs(g.rotation - 2 * .pi) < 1e-9 { g.rotation = 0 }
        } else { return false }
        addElement(p, .column(g), level: lv, material: materialInfo(p.id).name, kind: "column")
        return true
    }

    func beam(_ p: StepEntity) -> Bool {
        let w = placement(p[5])
        guard let x = singleExtrusion(p, w), let r = x.profile.rect else { return false }
        if let wr = worldRect(x) {
            // Plan-profile beam (our exporter): long side of the rectangle is the span.
            let alongU = wr.a >= wr.b
            let axis = alongU ? wr.u : wr.u.perp
            let len = max(wr.a, wr.b), width = min(wr.a, wr.b)
            let lv = level(for: p.id, baseZ: wr.baseZ)
            let g = BeamGeom(start: wr.center - axis * (len / 2), end: wr.center + axis * (len / 2), width: width, depth: x.depth,
                             topOffset: wr.baseZ + x.depth - elevation(lv))
            addElement(p, .beam(g), level: lv, material: materialInfo(p.id).name, kind: "beam")
            return true
        }
        guard abs(x.dir.z) < 1e-6 else { return false }
        // Section profile extruded horizontally along the span.
        let c = x.frame.apply(Vec3(r.center.x, r.center.y, 0))
        let u3 = x.frame.dir(Vec3(r.u.x, r.u.y, 0))
        let uVertical = abs(u3.z) > 0.9
        let depth = uVertical ? r.a : r.b, width = uVertical ? r.b : r.a
        let top = c.z + depth / 2
        let lv = level(for: p.id, baseZ: top - depth)
        let g = BeamGeom(start: c.xy, end: c.xy + x.dir.xy.normalized * x.depth, width: width, depth: depth, topOffset: top - elevation(lv))
        addElement(p, .beam(g), level: lv, material: materialInfo(p.id).name, kind: "beam")
        return true
    }

    func space(_ p: StepEntity) -> Bool {
        let w = placement(p[5])
        guard let x = singleExtrusion(p, w), vertical(x) else { return false }
        let boundary = IFCReader.clean(x.profile.outer.map { x.frame.apply(Vec3($0.x, $0.y, 0)).xy })
        guard boundary.count >= 3 else { return false }
        let baseZ = x.dir.z > 0 ? x.frame.o.z : x.frame.o.z - x.depth
        let lv = level(for: p.id, baseZ: baseZ)
        let long = p[7].string ?? ""
        let short = p[2].string ?? ""
        let g = SpaceGeom(boundary: boundary, name: long.isEmpty ? (short.isEmpty ? "Room" : short) : long,
                          number: long.isEmpty ? "" : short, height: x.depth)
        let id = doc.addElement(.space(g), level: lv)
        if let i = doc.elementIndex(id) {
            var props = properties(p.id)
            if let guid = p[0].string { props["ifcGuid"] = guid }
            doc.elements[i].props = props
        }
        elementOf[p.id] = id
        bump("space")
        return true
    }

    /// Wall element and its center line for an IFC host.
    func hostWall(_ id: EntityID) -> (BIMElement, WallGeom)? {
        guard let el = doc.element(id), case .wall(let w) = el.geometry, w.length > 1e-9 else { return nil }
        return (el, w)
    }

    func placeInWall(bounds b: BBox3, wall: (BIMElement, WallGeom), verts: [Vec3]) -> (offset: Double, width: Double, sill: Double, height: Double) {
        let w = wall.1, dir = w.direction
        let cs = w.centerStart
        var lo = Double.infinity, hi = -Double.infinity
        for v in verts { let t = (v.xy - cs).dot(dir); lo = min(lo, t); hi = max(hi, t) }
        let wallBase = elevation(wall.0.level) + w.baseOffset
        return ((lo + hi) / 2, hi - lo, b.min.z - wallBase, b.max.z - b.min.z)
    }

    func opening(_ p: StepEntity) -> Bool {
        let isDoor = p.type.hasPrefix("IFCDOOR")
        var hostID: EntityID?
        var geomMesh = TriMesh()
        if let o = fillsOpening[p.id], let op = f.entities[o] {
            if let h = voidsHost[o] { hostID = elementOf[h] }
            geomMesh = productMesh(op)
        }
        let own = productMesh(p)
        let origin = placement(p[5]).o
        if hostID == nil {
            // Nearest imported wall containing the placement point in plan.
            var best: (EntityID, Double)?
            for el in doc.elements { if case .wall(let w) = el.geometry, w.length > 1e-9 {
                let d = GeometryOps.distance(point: origin.xy, segA: w.centerStart, segB: w.centerEnd)
                if d <= w.thickness / 2 + 50, d < (best?.1 ?? .infinity) { best = (el.id, d) }
            } }
            hostID = best?.0
        }
        guard let hid = hostID, let host = hostWall(hid) else { return false }
        let m = geomMesh.isEmpty ? own : geomMesh
        guard !m.isEmpty else { return false }
        let used = m.t.map { m.v[$0] }
        var fit = placeInWall(bounds: m.bounds, wall: host, verts: used)
        if let W = p[9].double, W > 0 { fit.width = W * scale }
        if let H = p[8].double, H > 0 { fit.height = H * scale }
        var g = OpeningGeom(kind: isDoor ? .door : .window, hostWall: hid, offset: fit.offset, width: fit.width, height: fit.height, sill: max(0, fit.sill))
        let op = (p.args.count > 11 ? p[11].enumValue : nil) ?? ""
        if isDoor {
            switch op {
            case "SINGLE_SWING_RIGHT": g.flipHand = true
            case "DOUBLE_DOOR_SINGLE_SWING", "DOUBLE_DOOR_DOUBLE_SWING", "DOUBLE_SWING_LEFT", "DOUBLE_SWING_RIGHT": g.doorStyle = .double
            case "SLIDING_TO_LEFT", "SLIDING_TO_RIGHT", "DOUBLE_DOOR_SLIDING": g.doorStyle = .sliding
            case "FOLDING_TO_LEFT", "FOLDING_TO_RIGHT", "DOUBLE_DOOR_FOLDING": g.doorStyle = .folding
            case "REVOLVING": g.doorStyle = .revolving
            case "ROLLINGUP": g.doorStyle = .garage
            default: break
            }
        } else {
            switch op {
            case "DOUBLE_PANEL_VERTICAL", "TRIPLE_PANEL_VERTICAL": g.windowStyle = .doubleCasement
            case "DOUBLE_PANEL_HORIZONTAL", "TRIPLE_PANEL_HORIZONTAL": g.windowStyle = .hung
            default: break
            }
        }
        if let tag = p[7].string, !tag.isEmpty, Int(tag) == nil { g.mark = tag }
        addElement(p, .opening(g), level: host.0.level, material: materialInfo(p.id).name, kind: isDoor ? "door" : "window")
        return true
    }

    func emptyOpening(_ op: StepEntity, wallID: EntityID) -> Bool {
        guard let host = hostWall(wallID) else { return false }
        let m = productMesh(op)
        guard !m.isEmpty else { return false }
        let fit = placeInWall(bounds: m.bounds, wall: host, verts: m.t.map { m.v[$0] })
        guard fit.width > 1e-6, fit.height > 1e-6 else { return false }
        let g = OpeningGeom(kind: .opening, hostWall: wallID, offset: fit.offset, width: fit.width, height: fit.height, sill: max(0, fit.sill))
        let id = doc.addElement(.opening(g), level: host.0.level)
        if let i = doc.elementIndex(id), let guid = op[0].string { doc.elements[i].props["ifcGuid"] = guid }
        bump("opening")
        return true
    }
}
