// Oanarina Archi Tool — GPL-3.0-or-later
// STEP (ISO 10303-21) exchange with MCAD tools: AP214 export of the model as faceted B-reps (one FACETED_BREP per
// element, with colours), and import of polyhedral STEP geometry (FACETED_BREP, planar faces bounded by poly loops,
// lines, polylines and circles). Entity names and attribute orders follow ISO 10303-42/-41 and AP214 (automotive_design).
import Foundation

public enum STEPExporter {
    /// AP214 part with one FACETED_BREP per mesh group (millimetres, Z up).
    public static func export(_ groups: [MeshGroup], materials: [Material], name: String = "Model", author: String = "") -> String {
        var lines: [String] = []
        var next = 1
        @discardableResult func add(_ s: String) -> Int { let id = next; next += 1; lines.append("#\(id)=\(s);"); return id }
        func r(_ v: Double) -> String { IFCExporter.real(v) }
        func s(_ v: String) -> String { IFCExporter.str(v) }
        func refs(_ ids: [Int]) -> String { "(" + ids.map { "#\($0)" }.joined(separator: ",") + ")" }

        let appCtx = add("APPLICATION_CONTEXT('core data for automotive mechanical design processes')")
        add("APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#\(appCtx))")
        let prodCtx = add("PRODUCT_CONTEXT('',#\(appCtx),'mechanical')")
        let product = add("PRODUCT(\(s(name)),\(s(name)),'',(#\(prodCtx)))")
        let pdf = add("PRODUCT_DEFINITION_FORMATION('','',#\(product))")
        let pdc = add("PRODUCT_DEFINITION_CONTEXT('part definition',#\(appCtx),'design')")
        let pd = add("PRODUCT_DEFINITION('design','',#\(pdf),#\(pdc))")
        let pds = add("PRODUCT_DEFINITION_SHAPE('','',#\(pd))")
        add("PRODUCT_RELATED_PRODUCT_CATEGORY('part',$,(#\(product)))")
        let lu = add("(LENGTH_UNIT()NAMED_UNIT(*)SI_UNIT(.MILLI.,.METRE.))")
        let au = add("(NAMED_UNIT(*)PLANE_ANGLE_UNIT()SI_UNIT($,.RADIAN.))")
        let su = add("(NAMED_UNIT(*)SI_UNIT($,.STERADIAN.)SOLID_ANGLE_UNIT())")
        let unc = add("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-05),#\(lu),'distance_accuracy_value','confusion accuracy')")
        let ctx = add("(GEOMETRIC_REPRESENTATION_CONTEXT(3)GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#\(unc)))GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(lu),#\(au),#\(su)))REPRESENTATION_CONTEXT('Context3D','3D Context with 1e-05 uncertainty'))")
        let o = add("CARTESIAN_POINT('',(0.,0.,0.))")
        let z = add("DIRECTION('',(0.,0.,1.))"), x = add("DIRECTION('',(1.,0.,0.))")
        let axis = add("AXIS2_PLACEMENT_3D('',#\(o),#\(z),#\(x))")

        var items: [Int] = [axis]
        var styled: [Int] = []
        var styleOf: [String: Int] = [:]
        for (gi, g) in groups.enumerated() {
            let m = g.mesh
            let tris = MeshExport.triangles(m)
            guard !tris.isEmpty else { continue }
            var ptOf: [Int: Int] = [:]
            var weld: [String: Int] = [:]
            func pid(_ i: Int) -> Int {
                if let e = ptOf[i] { return e }
                let p = m.positions[i]
                let key = "\(Int((p.x * 100).rounded())),\(Int((p.y * 100).rounded())),\(Int((p.z * 100).rounded()))"
                if let e = weld[key] { ptOf[i] = e; return e }
                let e = add("CARTESIAN_POINT('',(\(r(p.x)),\(r(p.y)),\(r(p.z))))"); ptOf[i] = e; weld[key] = e; return e
            }
            var faces: [Int] = []
            var t = 0
            while t + 2 < tris.count {
                let a = pid(Int(tris[t])), b = pid(Int(tris[t + 1])), c = pid(Int(tris[t + 2]))
                t += 3
                if a == b || b == c || a == c { continue }
                let loop = add("POLY_LOOP('',(#\(a),#\(b),#\(c)))")
                let bound = add("FACE_OUTER_BOUND('',#\(loop),.T.)")
                faces.append(add("FACE('',(#\(bound)))"))
            }
            guard !faces.isEmpty else { continue }
            let shell = add("CLOSED_SHELL('',\(refs(faces)))")
            let brep = add("FACETED_BREP(\(s(MeshExport.groupName(g, index: gi))),#\(shell))")
            items.append(brep)
            // Colour (presentation style shared per material).
            let key = g.material.lowercased()
            let psa: Int
            if let e = styleOf[key] { psa = e } else {
                let mat = MeshExport.material(g.material, in: materials)
                let col = add("COLOUR_RGB(\(s(mat.name)),\(r(max(0, min(1, mat.color.r)))),\(r(max(0, min(1, mat.color.g)))),\(r(max(0, min(1, mat.color.b)))))")
                let fasc = add("FILL_AREA_STYLE_COLOUR('',#\(col))")
                let fas = add("FILL_AREA_STYLE('',(#\(fasc)))")
                let ssfa = add("SURFACE_STYLE_FILL_AREA(#\(fas))")
                let sss = add("SURFACE_SIDE_STYLE('',(#\(ssfa)))")
                let ssu = add("SURFACE_STYLE_USAGE(.BOTH.,#\(sss))")
                psa = add("PRESENTATION_STYLE_ASSIGNMENT((#\(ssu)))")
                styleOf[key] = psa
            }
            styled.append(add("STYLED_ITEM('color',(#\(psa)),#\(brep))"))
        }
        let rep = add("FACETED_BREP_SHAPE_REPRESENTATION(\(s(name)),\(refs(items)),#\(ctx))")
        add("SHAPE_DEFINITION_REPRESENTATION(#\(pds),#\(rep))")
        if !styled.isEmpty { add("MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_REPRESENTATION('',\(refs(styled)),#\(ctx))") }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var out = "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('Oanarina Archi Tool model (faceted B-rep)'),'2;1');\n"
        out += "FILE_NAME(\(s(name + ".stp")),\(s(iso.string(from: Date()))),(\(s(author))),(''),'Oanarina Archi Tool','Oanarina Archi Tool','');\n"
        out += "FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n"
        out += lines.joined(separator: "\n")
        out += "\nENDSEC;\nEND-ISO-10303-21;\n"
        return out
    }
}

public enum STEPImporter {
    public enum STEPImportError: Error, LocalizedError {
        case noGeometry
        public var errorDescription: String? { "The STEP file has no polyhedral (planar) geometry that can be read; curved B-rep surfaces need a CAD kernel — export as STL/OBJ from the CAD program instead." }
    }

    /// Mesh solids (one per shell) in drawing units (`unitMM` millimetres per drawing unit).
    public static func entities(_ text: String, unitMM: Double = 1, layer: String = "IMPORT-STEP") throws -> [Entity] {
        let f = try STEPParser.parse(text)
        // Length unit of the file.
        var mm = 1.0
        for e in f.entities.values where e.parts["LENGTH_UNIT"] != nil {
            if let si = e.parts["SI_UNIT"] {
                switch si.first?.enumValue ?? "" {
                case "MILLI": mm = 1
                case "CENTI": mm = 10
                case "DECI": mm = 100
                case "KILO": mm = 1_000_000
                case "MICRO": mm = 0.001
                default: mm = si.first?.isNull ?? true ? 1000 : 1
                }
            } else if let cb = e.parts["CONVERSION_BASED_UNIT"], let n = cb.first?.string?.uppercased() {
                mm = n.contains("INCH") ? 25.4 : (n.contains("FOOT") || n.contains("FEET") ? 304.8 : mm)
            }
            break
        }
        let k = mm / unitMM
        func point(_ id: Int?) -> Vec3? {
            guard let e = f[id] else { return nil }
            if e.type == "VERTEX_POINT" { return point(e[1].ref) }
            guard e.type == "CARTESIAN_POINT", let c = e[1].list?.compactMap({ $0.double }), c.count >= 2 else { return nil }
            return Vec3(c[0], c[1], c.count > 2 ? c[2] : 0) * k
        }
        func direction(_ id: Int?) -> Vec3? {
            guard let e = f[id], e.type == "DIRECTION", let c = e[1].list?.compactMap({ $0.double }), c.count >= 3 else { return nil }
            let v = Vec3(c[0], c[1], c[2]); return v.length > 1e-12 ? v * (1 / v.length) : nil
        }
        /// Points along an edge curve from `a` to `b` (exclusive of b).
        func edgePoints(_ curve: StepEntity?, _ a: Vec3, _ b: Vec3, sameSense: Bool) -> [Vec3] {
            guard let c = curve else { return [a] }
            if c.type == "CIRCLE", let pl = f[c[1].ref], let ctr = point(pl[1].ref), let rad = c[2].double.map({ $0 * k }), rad > 0 {
                let n = direction(pl[2].ref) ?? Vec3(0, 0, 1)
                var xa = direction(pl[3].ref) ?? (abs(n.z) < 0.9 ? Vec3(0, 0, 1).cross(n) : Vec3(1, 0, 0).cross(n))
                xa = xa * (1 / max(xa.length, 1e-12))
                let ya = n.cross(xa)
                func ang(_ p: Vec3) -> Double { let d = p - ctr; return atan2(d.dot(ya), d.dot(xa)) }
                var a0 = ang(a), a1 = ang(b)
                // Traversal follows the circle's sense (counter-clockwise about n) unless reversed.
                if sameSense { while a1 <= a0 + 1e-9 { a1 += 2 * .pi } } else { while a1 >= a0 - 1e-9 { a1 -= 2 * .pi } }
                let steps = max(2, Int(abs(a1 - a0) / (.pi / 16)))
                return (0..<steps).map { i in let t = a0 + (a1 - a0) * Double(i) / Double(steps); return ctr + xa * (rad * cos(t)) + ya * (rad * sin(t)) }
            }
            if c.type == "POLYLINE" {
                var pts = (c[1].list ?? []).compactMap { point($0.ref) }
                if !pts.isEmpty && pts[0].distance(to: a) > (pts.last!.distance(to: a)) { pts.reverse() }
                return pts.isEmpty ? [a] : Array(pts.dropLast())
            }
            return [a]
        }
        func loopPoints(_ loop: StepEntity) -> [Vec3] {
            if loop.type == "POLY_LOOP" { return (loop[1].list ?? []).compactMap { point($0.ref) } }
            guard loop.type == "EDGE_LOOP" else { return [] }
            var pts: [Vec3] = []
            for oeRef in loop[1].list ?? [] {
                guard let oe = f[oeRef.ref], oe.type == "ORIENTED_EDGE", let ec = f[oe[3].ref], ec.type == "EDGE_CURVE",
                      let s0 = point(ec[1].ref), let s1 = point(ec[2].ref) else { continue }
                let forward = oe[4].enumValue != "F"
                let sense = ec[4].enumValue != "F"
                let (a, b) = forward ? (s0, s1) : (s1, s0)
                pts += edgePoints(f[ec[3].ref], a, b, sameSense: forward == sense)
            }
            return pts
        }
        func vec3distance(_ a: Vec3, _ b: Vec3) -> Double { (a - b).length }

        var out: [Entity] = []
        let shells = f.entities.values.filter { ["CLOSED_SHELL", "OPEN_SHELL", "CONNECTED_FACE_SET"].contains($0.type) }.sorted { $0.id < $1.id }
        for sh in shells {
            var verts: [Vec3] = []
            var tris: [Int] = []
            for fr in sh[1].list ?? [] {
                guard let face = f[fr.ref], ["FACE", "ADVANCED_FACE", "FACE_SURFACE"].contains(face.type) else { continue }
                if face.type != "FACE", let surf = f[face[2].ref], surf.type != "PLANE" { continue } // curved surface
                var loops: [(pts: [Vec3], outer: Bool)] = []
                for bRef in face[1].list ?? [] {
                    guard let bound = f[bRef.ref], let loop = f[bound[1].ref] else { continue }
                    var pts = loopPoints(loop)
                    if bound[2].enumValue == "F" { pts.reverse() }
                    var clean: [Vec3] = []
                    for p in pts where clean.last.map({ vec3distance($0, p) > 1e-9 }) ?? true { clean.append(p) }
                    if clean.count > 2, vec3distance(clean[0], clean[clean.count - 1]) < 1e-9 { clean.removeLast() }
                    if clean.count >= 3 { loops.append((clean, bound.type == "FACE_OUTER_BOUND")) }
                }
                guard !loops.isEmpty else { continue }
                let oi = loops.firstIndex { $0.outer } ?? 0
                let outer = loops[oi].pts
                // Plane of the face (Newell normal), project, triangulate with holes.
                var n = Vec3(0, 0, 0)
                for i in 0..<outer.count { let a = outer[i], b = outer[(i + 1) % outer.count]; n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
                guard n.length > 1e-12 else { continue }
                n = n * (1 / n.length)
                let u = (abs(n.z) < 0.9 ? Vec3(0, 0, 1) : Vec3(1, 0, 0)).cross(n)
                let uu = u * (1 / u.length), vv = n.cross(uu)
                let origin = outer[0]
                func proj(_ p: Vec3) -> Vec2 { let d = p - origin; return Vec2(d.dot(uu), d.dot(vv)) }
                var o2 = outer.map(proj)
                var o3 = outer
                if GeometryOps.signedArea(o2) < 0 { o2.reverse(); o3.reverse() }
                var holes2: [[Vec2]] = [], holes3: [[Vec3]] = []
                for (i, l) in loops.enumerated() where i != oi {
                    var h2 = l.pts.map(proj), h3 = l.pts
                    if GeometryOps.signedArea(h2) > 0 { h2.reverse(); h3.reverse() }
                    holes2.append(h2); holes3.append(h3)
                }
                let all3 = o3 + holes3.flatMap { $0 }
                let tr = Triangulator.triangulateWithPoints(o2, holes: holes2)
                // Map triangulation points back to 3D by matching projected coordinates.
                let all2 = o2 + holes2.flatMap { $0 }
                let base = verts.count
                var local: [Int] = []
                for p in tr.points {
                    var best = 0, bd = Double.infinity
                    for (j, q) in all2.enumerated() { let d = (p - q).length; if d < bd { bd = d; best = j } }
                    local.append(verts.count)
                    verts.append(bd < 1e-6 ? all3[best] : origin + uu * p.x + vv * p.y)
                }
                _ = base
                // Keep the face's orientation (normal n).
                for t in tr.triangles {
                    let a = verts[local[t.0]], b = verts[local[t.1]], c = verts[local[t.2]]
                    if (b - a).cross(c - a).dot(n) >= 0 { tris += [local[t.0], local[t.1], local[t.2]] } else { tris += [local[t.0], local[t.2], local[t.1]] }
                }
            }
            guard !tris.isEmpty else { continue }
            // Weld duplicate vertices.
            var weld: [String: Int] = [:], wv: [Vec3] = [], remap: [Int] = []
            for p in verts {
                let key = "\(Int((p.x * 1000).rounded())),\(Int((p.y * 1000).rounded())),\(Int((p.z * 1000).rounded()))"
                if let i = weld[key] { remap.append(i) } else { weld[key] = wv.count; remap.append(wv.count); wv.append(p) }
            }
            var wt: [Int] = []
            var i = 0
            while i + 2 < tris.count { let a = remap[tris[i]], b = remap[tris[i + 1]], c = remap[tris[i + 2]]; if a != b && b != c && a != c { wt += [a, b, c] }; i += 3 }
            guard !wt.isEmpty else { continue }
            let owner = f.entities.values.first { ($0.type == "FACETED_BREP" || $0.type == "MANIFOLD_SOLID_BREP") && $0[1].ref == sh.id }
            let nm = owner?[0].string.flatMap { $0.isEmpty ? nil : $0 } ?? "shell \(sh.id)"
            out.append(Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: wv, meshTriangles: wt)), props: ["name": nm]))
        }
        if out.isEmpty { throw STEPImportError.noGeometry }
        return out
    }
}
