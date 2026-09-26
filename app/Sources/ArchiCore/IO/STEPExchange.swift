// Oanarina Archi Tool — GPL-3.0-or-later
// STEP (ISO 10303-21) exchange with MCAD tools: AP214 export of the model as faceted B-reps (one FACETED_BREP per
// element, with colours), and import of B-rep, surface-model and tessellated STEP geometry with assembly placements
// and colours (curved faces are tessellated by StepBRepReader in STEPBRep.swift). Entity names and attribute orders follow ISO 10303-42/-41 and AP214 (automotive_design).
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

/// Units of a STEP file: those assigned by the geometric representation context (GLOBAL_UNIT_ASSIGNED_CONTEXT) — files
/// often define several length and angle units — with conversion-based units (inch, foot, degree) through their measure.
enum StepUnits {
    static func lengthMM(_ e: StepEntity, _ f: STEPFile, depth: Int = 0) -> Double? {
        guard e.parts["LENGTH_UNIT"] != nil || e.type == "LENGTH_UNIT" else { return nil }
        if let si = e.parts["SI_UNIT"] {
            switch si.first?.enumValue ?? "" {
            case "MILLI": return 1
            case "CENTI": return 10
            case "DECI": return 100
            case "KILO": return 1_000_000
            case "MICRO": return 0.001
            case "NANO": return 1e-6
            default: return 1000
            }
        }
        if let cb = e.parts["CONVERSION_BASED_UNIT"] {
            if depth < 4, let m = f[cb[stepSafe: 1]?.ref], let v = m[0].double, let u = f[m[1].ref], let base = lengthMM(u, f, depth: depth + 1) { return v * base }
            let n = (cb.first?.string ?? "").uppercased()
            if n.contains("INCH") { return 25.4 }
            if n.contains("FOOT") || n.contains("FEET") { return 304.8 }
        }
        return nil
    }
    static func angleRad(_ e: StepEntity, _ f: STEPFile, depth: Int = 0) -> Double? {
        guard e.parts["PLANE_ANGLE_UNIT"] != nil || e.type == "PLANE_ANGLE_UNIT" else { return nil }
        if e.parts["SI_UNIT"] != nil { return 1 }
        if let cb = e.parts["CONVERSION_BASED_UNIT"] {
            if depth < 4, let m = f[cb[stepSafe: 1]?.ref], let v = m[0].double, let u = f[m[1].ref], let base = angleRad(u, f, depth: depth + 1) { return v * base }
            if (cb.first?.string ?? "").uppercased().contains("DEG") { return .pi / 180 }
        }
        return nil
    }
    static func resolve(_ f: STEPFile) -> (mmPerUnit: Double, radPerAngle: Double) {
        let sorted = f.entities.values.sorted { $0.id < $1.id }
        var units: [StepEntity] = []
        if let ctx = sorted.first(where: { $0.parts["GLOBAL_UNIT_ASSIGNED_CONTEXT"] != nil }) {
            units = (ctx.parts["GLOBAL_UNIT_ASSIGNED_CONTEXT"]?.first?.refs ?? []).compactMap { f[$0] }
        }
        units += sorted
        let mm = units.lazy.compactMap { lengthMM($0, f) }.first ?? 1
        let rad = units.lazy.compactMap { angleRad($0, f) }.first ?? 1
        return (mm, rad)
    }
}


public enum STEPImporter {
    public enum STEPImportError: Error, LocalizedError {
        case noGeometry
        public var errorDescription: String? { "The STEP file has no B-rep, surface model or tessellated geometry that can be read." }
    }

    /// Mesh solids (one per shell) in drawing units (`unitMM` millimetres per drawing unit).
    public static func entities(_ text: String, unitMM: Double = 1, layer: String = "IMPORT-STEP") throws -> [Entity] {
        let f = try STEPParser.parse(text)
        let mm = StepUnits.resolve(f).mmPerUnit
        let reader = StepBRepReader(f, scale: mm / unitMM)
        let out = assemble(f, reader, layer: layer)
        if out.isEmpty { throw STEPImportError.noGeometry }
        return out
    }

    /// Faces of a shell (oriented shells reverse their faces).
    static func shellFaces(_ f: STEPFile, _ id: Int?) -> (faces: [Int], flip: Bool) {
        guard let sh = f[id] else { return ([], false) }
        if sh.type.hasPrefix("ORIENTED_") { let inner = shellFaces(f, sh[2].ref); return (inner.faces, inner.flip != (sh[3].enumValue == "F")) }
        return (sh[1].refs, false)
    }

    /// Colour of a styled item (first COLOUR_RGB / pre-defined colour reachable from its styles).
    static func colour(_ f: STEPFile, _ v: StepValue, depth: Int = 0) -> (Double, Double, Double)? {
        guard depth < 24 else { return nil }
        switch v {
        case .list(let l): for x in l { if let c = colour(f, x, depth: depth + 1) { return c } }; return nil
        case .ref(let r):
            guard let e = f[r] else { return nil }
            if e.type == "COLOUR_RGB", let r = e[1].double, let g = e[2].double, let b = e[3].double { return (r, g, b) }
            if e.type == "DRAUGHTING_PRE_DEFINED_COLOUR" {
                switch (e[0].string ?? "").lowercased() {
                case "red": return (1, 0, 0); case "green": return (0, 1, 0); case "blue": return (0, 0, 1)
                case "yellow": return (1, 1, 0); case "magenta": return (1, 0, 1); case "cyan": return (0, 1, 1)
                case "black": return (0, 0, 0); case "white": return (1, 1, 1); default: return nil
                }
            }
            for a in e.args { if let c = colour(f, a, depth: depth + 1) { return c } }
            return nil
        default: return nil
        }
    }

    static func assemble(_ f: STEPFile, _ r: StepBRepReader, layer: String) -> [Entity] {
        let sorted = f.entities.values.sorted { $0.id < $1.id }
        // 1. Geometric items.
        struct Item { var id: Int; var name: String; var shells: [Int]; var tess: [Int] }
        var items: [Item] = []
        var ownedShells: Set<Int> = [], ownedTess: Set<Int> = []
        let tessTypes: Set<String> = ["TRIANGULATED_FACE", "COMPLEX_TRIANGULATED_FACE", "TRIANGULATED_SURFACE_SET", "COMPLEX_TRIANGULATED_SURFACE_SET"]
        for e in sorted {
            switch e.type {
            case "MANIFOLD_SOLID_BREP", "FACETED_BREP", "BREP_WITH_VOIDS":
                var sh = [e[1].ref].compactMap { $0 }
                if e.type == "BREP_WITH_VOIDS" { sh += e[2].refs }
                items.append(Item(id: e.id, name: e[0].string ?? "", shells: sh, tess: [])); ownedShells.formUnion(sh)
            case "SHELL_BASED_SURFACE_MODEL", "FACE_BASED_SURFACE_MODEL":
                items.append(Item(id: e.id, name: e[0].string ?? "", shells: e[1].refs, tess: [])); ownedShells.formUnion(e[1].refs)
            case "TESSELLATED_SOLID", "TESSELLATED_SHELL":
                items.append(Item(id: e.id, name: e[0].string ?? "", shells: [], tess: e[1].refs)); ownedTess.formUnion(e[1].refs)
            default: break
            }
        }
        for e in sorted where ["CLOSED_SHELL", "OPEN_SHELL", "CONNECTED_FACE_SET"].contains(e.type) && !ownedShells.contains(e.id) {
            items.append(Item(id: e.id, name: "shell \(e.id)", shells: [e.id], tess: []))
        }
        for e in sorted where tessTypes.contains(e.type) && !ownedTess.contains(e.id) {
            items.append(Item(id: e.id, name: e[0].string ?? "", shells: [], tess: [e.id]))
        }
        guard !items.isEmpty else { return [] }

        // 2. Assembly structure: representations, same-frame links, placed children.
        func repArgs(_ e: StepEntity) -> [StepValue]? {
            let names = [e.type] + Array(e.parts.keys)
            guard names.contains(where: { $0.hasSuffix("REPRESENTATION") && !$0.hasSuffix("DEFINITION_REPRESENTATION") && !$0.contains("RELATIONSHIP") && $0 != "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION" }) else { return nil }
            let a = e.parts["REPRESENTATION"] ?? e.args
            return a.count > 1 && a[1].list != nil ? a : nil
        }
        var itemReps: [Int: [Int]] = [:]
        var repItems: [Int: [Int]] = [:]
        for e in sorted { if let a = repArgs(e) { repItems[e.id] = a[1].refs; for i in a[1].refs { itemReps[i, default: []].append(e.id) } } }
        var parent: [Int: Int] = [:]
        func find(_ x: Int) -> Int { var x = x; while let p = parent[x], p != x { x = p }; return x }
        func union(_ a: Int, _ b: Int) { let x = find(a), y = find(b); if x != y { parent[x] = y } }
        // Product definitions' representations (to tell parent from child in a relationship).
        var pdReps: [Int: Set<Int>] = [:]
        for e in sorted where ["SHAPE_DEFINITION_REPRESENTATION", "PROPERTY_DEFINITION_REPRESENTATION"].contains(e.type) {
            if let pds = f[e[0].ref], let pd = pds[2].ref, let rep = e[1].ref { pdReps[pd, default: []].insert(rep) }
        }
        var relChild: [Int: Int] = [:]   // relationship id → child rep (from the assembly usage)
        for e in sorted where e.type == "CONTEXT_DEPENDENT_SHAPE_REPRESENTATION" {
            guard let rel = e[0].ref, let pds = f[e[1].ref], let nauo = f[pds[2].ref], let related = nauo[4].ref, let reps = pdReps[related] else { continue }
            relChild[rel] = reps.first
        }
        var links: [(child: Int, parent: Int, t: StepXform)] = []
        for e in sorted {
            let rr = e.parts["REPRESENTATION_RELATIONSHIP"] ?? (e.type.hasSuffix("REPRESENTATION_RELATIONSHIP") || e.type == "REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION" ? e.args : nil)
            guard let rr, rr.count >= 4, let r1 = rr[2].ref, let r2 = rr[3].ref else { continue }
            let tr = e.parts["REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION"]?.first ?? (e.type == "REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION" ? e[4] : .null)
            guard let tid = tr.ref, let te = f[tid] else { union(r1, r2); continue }
            var T = StepXform.identity
            if te.type == "ITEM_DEFINED_TRANSFORMATION" {
                let F1 = r.frame(te[2].ref) ?? .identity, F2 = r.frame(te[3].ref) ?? .identity
                T = F2 * F1.inverse
            } else if let op = r.frame(tid) { T = op }
            if let c = relChild[e.id], find(c) == find(r2), find(c) != find(r1) {
                links.append((r2, r1, T.inverse))
            } else {
                links.append((r1, r2, T))
            }
        }
        for (rep, its) in repItems {
            for i in its {
                guard let m = f[i], m.type == "MAPPED_ITEM", let map = f[m[1].ref], let child = map[1].ref else { continue }
                let origin = r.frame(map[0].ref) ?? .identity, target = r.frame(m[2].ref) ?? .identity
                links.append((child, rep, target * origin.inverse))
            }
        }
        var parentsOf: [Int: [(Int, StepXform)]] = [:]
        for l in links { parentsOf[find(l.child), default: []].append((find(l.parent), l.t)) }
        var memo: [Int: [StepXform]] = [:], visiting: Set<Int> = []
        func worlds(_ c: Int) -> [StepXform] {
            if let m = memo[c] { return m }
            guard !visiting.contains(c) else { return [.identity] }
            visiting.insert(c)
            let ps = parentsOf[c] ?? []
            var out: [StepXform] = ps.isEmpty ? [.identity] : []
            outer: for (p, t) in ps { for w in worlds(p) { out.append(w * t); if out.count >= 2000 { break outer } } }
            visiting.remove(c)
            memo[c] = out
            return out
        }

        // 3. Colours of styled items.
        var colours: [Int: (Double, Double, Double)] = [:]
        for e in sorted where e.type == "STYLED_ITEM" || e.type == "OVER_RIDING_STYLED_ITEM" {
            if let it = e[2].ref, colours[it] == nil, let c = colour(f, e[1]) { colours[it] = c }
        }

        // 4. Meshes, one entity per placed occurrence.
        var out: [Entity] = []
        var triBudget = 6_000_000
        for it in items {
            var verts: [Vec3] = [], tris: [Int] = []
            for sid in it.shells {
                let (faces, flip) = shellFaces(f, sid)
                for fr in faces {
                    guard let face = f[fr], ["FACE", "ADVANCED_FACE", "FACE_SURFACE"].contains(face.type) else { continue }
                    let m = r.tessellate(face)
                    let base = verts.count
                    verts += m.verts
                    var i = 0
                    while i + 2 < m.tris.count {
                        if flip { tris += [base + m.tris[i], base + m.tris[i + 2], base + m.tris[i + 1]] } else { tris += [base + m.tris[i], base + m.tris[i + 1], base + m.tris[i + 2]] }
                        i += 3
                    }
                }
            }
            for tid in it.tess {
                guard let te = f[tid] else { continue }
                if let m = r.tessellatedItem(te) { let base = verts.count; verts += m.verts; tris += m.tris.map { $0 + base } }
            }
            guard !tris.isEmpty else { continue }
            // Weld duplicate vertices.
            var weld: [String: Int] = [:], wv: [Vec3] = [], remap: [Int] = []
            let q = 1000.0   // weld grid: 0.001 drawing units
            for p in verts {
                let key = "\(Int((p.x * q).rounded())),\(Int((p.y * q).rounded())),\(Int((p.z * q).rounded()))"
                if let i = weld[key] { remap.append(i) } else { weld[key] = wv.count; remap.append(wv.count); wv.append(p) }
            }
            var wt: [Int] = []
            var i = 0
            while i + 2 < tris.count { let a = remap[tris[i]], b = remap[tris[i + 1]], c = remap[tris[i + 2]]; if a != b && b != c && a != c { wt += [a, b, c] }; i += 3 }
            guard !wt.isEmpty else { continue }
            var clusters: [Int] = []
            for rep in itemReps[it.id] ?? [] { let c = find(rep); if !clusters.contains(c) { clusters.append(c) } }
            let places = clusters.isEmpty ? [StepXform.identity] : clusters.flatMap { worlds($0) }
            let name = it.name.isEmpty ? "solid \(it.id)" : it.name
            for (n, T) in places.enumerated() {
                guard triBudget > 0 else { break }
                triBudget -= wt.count / 3
                let pv = T.isIdentity ? wv : wv.map { T.apply($0) }
                var ent = Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: pv, meshTriangles: wt)),
                                 props: ["name": places.count > 1 ? "\(name) [\(n + 1)]" : name])
                if let c = colours[it.id] {
                    func b(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
                    ent.color = .rgb(b(c.0), b(c.1), b(c.2))
                }
                out.append(ent)
            }
        }
        return out
    }
}
