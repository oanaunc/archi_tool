// Oanarina Archi Tool — GPL-3.0-or-later
// Export of the structural analytical model to analysis programs (ANL-034):
// • SAF — the Structural Analysis Format (an open, Excel-based exchange format read by SCIA Engineer, RFEM/RSTAB,
//   FEM-Design, Dlubal, Axis VM, Revit via plug-in…): materials, cross-sections, point connections, curve members,
//   surface members, point supports, load groups, load cases, surface and point actions (SAF 2.x sheet layout).
// • IFC4 structural analysis view: IfcStructuralAnalysisModel with IfcStructuralPointConnection (vertex topology,
//   IfcBoundaryNodeCondition for supports), IfcStructuralCurveMember (edge topology, material profile set usage),
//   IfcStructuralSurfaceMember (face topology, thickness), IfcRelConnectsStructuralMember, load groups (load cases)
//   with IfcStructuralPointAction / IfcStructuralPlanarAction; SI units (m, N, Pa).
// Nodal loads the frame solver lumps from slabs are not exported: the slabs carry their area loads instead.
import Foundation

public enum StructuralExchange {
    // MARK: SAF

    public static func safSheets(_ m: AnalyticalModel, name: String, options o: AnalyticalOptions = AnalyticalOptions(), now: Date = Date()) -> [XLSX.Sheet] {
        func f(_ v: Double, _ d: Int = 6) -> String { fmt(v, d) }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate]
        // Materials.
        var mats: [String: StructMaterial] = [:]
        for x in m.members { mats[x.material.name] = x.material }
        for p in m.panels { mats[p.material.name] = p.material }
        func matType(_ s: StructMaterial) -> String {
            let n = s.name.lowercased()
            if n.contains("steel") { return "Steel" }
            if n.contains("timber") || n.contains("wood") || n.contains("glulam") || n.contains("clt") { return "Timber" }
            if n.contains("alumin") { return "Aluminium" }
            if n.contains("brick") || n.contains("masonry") { return "Masonry" }
            return "Concrete"
        }
        let project = XLSX.Sheet(name: "Project", rows: [
            ["Name", name], ["Description", "Structural analysis model"], ["Location", ""], ["Software", "Oanarina Archi Tool"],
            ["Author", ""], ["Date", iso.string(from: now)], ["Version of SAF", "2.2.0"], ["Unit system", "SI (m, kN, MPa)"],
        ])
        var matRows = [["Name", "Type", "Subtype", "Quality", "Unit mass [kg/m3]", "E modulus [MPa]", "G modulus [MPa]", "Poisson Coefficient", "Thermal expansion [1/K]"]]
        for s in mats.values.sorted(by: { $0.name < $1.name }) {
            let nu = s.g > 0 ? max(0, min(0.5, s.e / (2 * s.g) - 1)) : 0.2
            let alpha = matType(s) == "Steel" ? 1.2e-5 : (matType(s) == "Timber" ? 5e-6 : 1e-5)
            matRows.append([s.name, matType(s), "", s.name, f(s.weight * 1000 / 9.81, 1), f(s.e, 1), f(s.g, 1), f(nu, 4), String(format: "%.2e", alpha)])
        }
        // Cross-sections (one per shape, size and material).
        var sections: [String: AnalyticalMember] = [:]
        func secName(_ x: AnalyticalMember) -> String {
            x.round ? "CHS \(Int((x.width * 1000).rounded())) \(x.material.name)" : "RECT \(Int((x.width * 1000).rounded()))x\(Int((x.depth * 1000).rounded())) \(x.material.name)"
        }
        for x in m.members { sections[secName(x)] = x }
        var secRows = [["Name", "Material", "Cross-section type", "Shape", "Parameters [mm]", "Profile", "Form code", "Description ID of the profile", "A [m2]", "Iy [m4]", "Iz [m4]", "It [m4]"]]
        for (n, x) in sections.sorted(by: { $0.key < $1.key }) {
            secRows.append([n, x.material.name, "Parametric", x.round ? "Circle" : "Rectangle",
                            x.round ? f(x.width * 1000, 1) : f(x.depth * 1000, 1) + ";" + f(x.width * 1000, 1), "", x.round ? "11" : "1", "",
                            String(format: "%.6e", x.area), String(format: "%.6e", x.iy), String(format: "%.6e", x.iz), String(format: "%.6e", x.j)])
        }
        // Point connections: model nodes plus panel corners.
        var points = m.nodes.map { (name: "N\($0.id)", p: $0.p) }
        func pointName(_ p: Vec3) -> String {
            if let q = points.first(where: { $0.p.distance(to: p) <= 1e-4 }) { return q.name }
            let n = "N\(m.nodes.count + points.count - m.nodes.count + 1)"
            points.append((n, p)); return n
        }
        var memberRows = [["Name", "Type", "Cross section", "Arc point", "Nodes", "Segments", "Begin node", "End node", "Length [m]", "System line", "Layer", "Behaviour", "Analysis type"]]
        for x in m.members {
            let a = m.nodes[x.start - 1], b = m.nodes[x.end - 1]
            memberRows.append(["B\(x.id)", x.kind == "column" ? "Column" : "Beam", secName(x), "", "N\(a.id);N\(b.id)", "Line", "N\(a.id)", "N\(b.id)",
                               f(a.p.distance(to: b.p), 4), "Centre", x.kind == "column" ? "Columns" : "Beams", "Standard", "Standard"])
        }
        var surfRows = [["Name", "Type", "Material", "Thickness type", "Thickness [mm]", "System plane at", "Nodes", "Internal nodes", "Edges", "Layer", "Analysis model", "Shape"]]
        for p in m.panels {
            let names = p.outline.map(pointName)
            surfRows.append(["S\(p.id)", p.kind == "wall" ? "Wall" : "Plate", p.material.name, "Constant", f(p.thickness * 1000, 1), "Centre", names.joined(separator: ";"), "",
                             Array(repeating: "Line", count: names.count).joined(separator: ";"), p.kind == "wall" ? "Walls" : "Slabs", "Isotropic", "Flat"])
        }
        var pointRows = [["Name", "Coordinate X [m]", "Coordinate Y [m]", "Coordinate Z [m]"]]
        for q in points { pointRows.append([q.name, f(q.p.x), f(q.p.y), f(q.p.z)]) }
        var supRows = [["Name", "Type", "Node", "Coordinate system", "ux", "uy", "uz", "fix", "fiy", "fiz"]]
        for n in m.nodes where n.isSupported {
            let t = n.support.allSatisfy { $0 } ? "Fixed" : (n.support.prefix(3).allSatisfy { $0 } && !n.support.suffix(3).contains(true) ? "Hinged" : "Custom")
            supRows.append(["Sn\(n.id)", t, "N\(n.id)", "Global"] + n.support.map { $0 ? "Rigid" : "Free" })
        }
        // Loads.
        let userCases = Array(Set(m.nodeLoads.map(\.loadCase).filter { !$0.isEmpty })).sorted()
        var groups = [["Name", "Load group type", "Relation"], ["LG1", "Permanent", "Together"], ["LG2", "Variable", "Exclusive"]]
        var cases = [["Name", "Description", "Action type", "Load group", "Load type"],
                     ["LC1", "Self weight", "Permanent", "LG1", "Self weight"],
                     ["LC2", "Superimposed dead load", "Permanent", "LG1", "Others"],
                     ["LC3", "Imposed load", "Variable", "LG2", "Static"]]
        for (i, c) in userCases.enumerated() {
            let variable = c.lowercased().hasPrefix("l") || c.lowercased().contains("live") || c.lowercased().contains("wind") || c.lowercased().contains("snow")
            cases.append(["LC\(4 + i)", c, variable ? "Variable" : "Permanent", variable ? "LG2" : "LG1", variable ? "Static" : "Others"])
        }
        if userCases.isEmpty { groups = Array(groups.prefix(3)) }
        var surfLoads = [["Name", "2D member", "Direction", "Type", "Value [kN/m2]", "Load case", "Coordinate system", "Location"]]
        for p in m.panels where p.kind == "slab" {
            if o.deadLoad != 0 { surfLoads.append(["SF\(p.id)D", "S\(p.id)", "Z", "Force", f(-o.deadLoad, 3), "LC2", "GCS", "Length"]) }
            if o.liveLoad != 0 { surfLoads.append(["SF\(p.id)L", "S\(p.id)", "Z", "Force", f(-o.liveLoad, 3), "LC3", "GCS", "Length"]) }
        }
        var pointLoads = [["Name", "Node", "Direction", "Type", "Value [kN]", "Load case", "Coordinate system"]]
        var k = 1
        for l in m.nodeLoads where !l.loadCase.isEmpty {
            let lc = "LC\(4 + (userCases.firstIndex(of: l.loadCase) ?? 0))"
            for (dir, v) in [("X", l.force.x), ("Y", l.force.y), ("Z", l.force.z)] where abs(v) > 1e-12 {
                pointLoads.append(["F\(k)", "N\(l.node)", dir, "Force", f(v, 4), lc, "GCS"]); k += 1
            }
            for (dir, v) in [("X", l.moment.x), ("Y", l.moment.y), ("Z", l.moment.z)] where abs(v) > 1e-12 {
                pointLoads.append(["M\(k)", "N\(l.node)", dir, "Moment", f(v, 4), lc, "GCS"]); k += 1
            }
        }
        return [project, XLSX.Sheet(name: "StructuralMaterial", rows: matRows), XLSX.Sheet(name: "StructuralCrossSection", rows: secRows),
                XLSX.Sheet(name: "StructuralPointConnection", rows: pointRows), XLSX.Sheet(name: "StructuralCurveMember", rows: memberRows),
                XLSX.Sheet(name: "StructuralSurfaceMember", rows: surfRows), XLSX.Sheet(name: "StructuralPointSupport", rows: supRows),
                XLSX.Sheet(name: "StructuralLoadGroup", rows: groups), XLSX.Sheet(name: "StructuralLoadCase", rows: cases),
                XLSX.Sheet(name: "StructuralSurfaceAction", rows: surfLoads), XLSX.Sheet(name: "StructuralPointAction", rows: pointLoads)]
    }

    public static func saf(_ m: AnalyticalModel, name: String, options: AnalyticalOptions = AnalyticalOptions()) -> Data {
        XLSX.write(safSheets(m, name: name, options: options))
    }

    // MARK: IFC structural analysis view

    public static func ifc(_ m: AnalyticalModel, name: String, options o: AnalyticalOptions = AnalyticalOptions(), author: String = "") -> String {
        var lines: [String] = []
        var next = 1
        @discardableResult func add(_ s: String) -> Int { let id = next; next += 1; lines.append("#\(id)=\(s);"); return id }
        func r(_ v: Double) -> String { IFCExporter.real(v) }
        func s(_ v: String) -> String { IFCExporter.str(v) }
        func refs(_ ids: [Int]) -> String { "(" + ids.map { "#\($0)" }.joined(separator: ",") + ")" }
        func g(_ key: String) -> String { s(IFCExporter.guid("struct:\(name):" + key)) }
        func pt(_ p: Vec3) -> Int { add("IFCCARTESIANPOINT((\(r(p.x)),\(r(p.y)),\(r(p.z))))") }

        let person = add("IFCPERSON($,\(s(author)),$,$,$,$,$,$)")
        let org = add("IFCORGANIZATION($,'Oanarina',$,$,$)")
        let po = add("IFCPERSONANDORGANIZATION(#\(person),#\(org),$)")
        let app = add("IFCAPPLICATION(#\(org),'1.0','Oanarina Archi Tool','OanarinaArchi')")
        let oh = add("IFCOWNERHISTORY(#\(po),#\(app),$,.ADDED.,$,$,$,\(Int(Date().timeIntervalSince1970)))")
        let origin = pt(.zero)
        let dz = add("IFCDIRECTION((0.,0.,1.))"), dx = add("IFCDIRECTION((1.,0.,0.))")
        let wcs = add("IFCAXIS2PLACEMENT3D(#\(origin),#\(dz),#\(dx))")
        let ctx = add("IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#\(wcs),$)")
        let topo = add("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Reference','Model',*,*,*,*,#\(ctx),$,.MODEL_VIEW.,$)")
        let lu = add("IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)")
        let fu = add("IFCSIUNIT(*,.FORCEUNIT.,$,.NEWTON.)")
        let pu = add("IFCSIUNIT(*,.PRESSUREUNIT.,$,.PASCAL.)")
        let au = add("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.)")
        let mu = add("IFCSIUNIT(*,.MASSUNIT.,.KILO.,.GRAM.)")
        let units = add("IFCUNITASSIGNMENT((#\(lu),#\(fu),#\(pu),#\(au),#\(mu)))")
        let project = add("IFCPROJECT(\(g("project")),#\(oh),\(s(name)),'Structural analysis model',$,$,$,(#\(ctx)),#\(units))")
        let placement = add("IFCLOCALPLACEMENT($,#\(wcs))")

        // Materials with mechanical properties.
        var matID: [String: Int] = [:]
        var mats: [String: StructMaterial] = [:]
        for x in m.members { mats[x.material.name] = x.material }
        for p in m.panels { mats[p.material.name] = p.material }
        for mat in mats.values.sorted(by: { $0.name < $1.name }) {
            let id = add("IFCMATERIAL(\(s(mat.name)),$,$)")
            matID[mat.name] = id
            let nu = mat.g > 0 ? max(0, min(0.5, mat.e / (2 * mat.g) - 1)) : 0.2
            let p1 = add("IFCPROPERTYSINGLEVALUE('YoungModulus',$,IFCMODULUSOFELASTICITYMEASURE(\(r(mat.e * 1e6))),$)")
            let p2 = add("IFCPROPERTYSINGLEVALUE('ShearModulus',$,IFCMODULUSOFELASTICITYMEASURE(\(r(mat.g * 1e6))),$)")
            let p3 = add("IFCPROPERTYSINGLEVALUE('PoissonRatio',$,IFCPOSITIVERATIOMEASURE(\(r(nu))),$)")
            add("IFCMATERIALPROPERTIES('Pset_MaterialMechanical',$,(#\(p1),#\(p2),#\(p3)),#\(id))")
            let p4 = add("IFCPROPERTYSINGLEVALUE('MassDensity',$,IFCMASSDENSITYMEASURE(\(r(mat.weight * 1000 / 9.81))),$)")
            add("IFCMATERIALPROPERTIES('Pset_MaterialCommon',$,(#\(p4)),#\(id))")
        }

        // Point connections.
        var vertexOf: [Int: Int] = [:], connOf: [Int: Int] = [:]
        var members: [Int] = []
        func vertex(_ p: Vec3) -> Int { add("IFCVERTEXPOINT(#\(pt(p)))") }
        for n in m.nodes {
            let v = vertex(n.p)
            vertexOf[n.id] = v
            let rep = add("IFCTOPOLOGYREPRESENTATION(#\(topo),'Reference','Vertex',(#\(v)))")
            let pds = add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(rep)))")
            var cond = "$"
            if n.isSupported {
                let b = n.support.map { $0 ? "IFCBOOLEAN(.T.)" : "IFCBOOLEAN(.F.)" }
                cond = "#" + String(add("IFCBOUNDARYNODECONDITION('Sn\(n.id)',\(b.joined(separator: ",")))"))
            }
            let c = add("IFCSTRUCTURALPOINTCONNECTION(\(g("node:\(n.id)")),#\(oh),'N\(n.id)',$,$,#\(placement),#\(pds),\(cond),$)")
            connOf[n.id] = c
            members.append(c)
        }
        // Curve members with profiles.
        var profileSet: [String: Int] = [:]
        var memberIDs: [(Int, AnalyticalMember)] = []
        for x in m.members {
            let a = x.start, b = x.end
            guard let va = vertexOf[a], let vb = vertexOf[b] else { continue }
            let e = add("IFCEDGE(#\(va),#\(vb))")
            let rep = add("IFCTOPOLOGYREPRESENTATION(#\(topo),'Reference','Edge',(#\(e)))")
            let pds = add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(rep)))")
            // Local z axis: global Y for columns, global Z for beams.
            let axis = add(x.kind == "column" ? "IFCDIRECTION((0.,1.,0.))" : "IFCDIRECTION((0.,0.,1.))")
            let id = add("IFCSTRUCTURALCURVEMEMBER(\(g("member:\(x.id)")),#\(oh),'B\(x.id)',$,\(s(x.kind)),#\(placement),#\(pds),.RIGID_JOINED_MEMBER.,#\(axis))")
            memberIDs.append((id, x))
            members.append(id)
            let key = "\(x.round ? "C" : "R")\(x.width)x\(x.depth)|\(x.material.name)"
            if profileSet[key] == nil {
                let pos = add("IFCAXIS2PLACEMENT2D(#\(add("IFCCARTESIANPOINT((0.,0.))")),$)")
                let prof = x.round ? add("IFCCIRCLEPROFILEDEF(.AREA.,'CHS',#\(pos),\(r(x.width / 2)))")
                                   : add("IFCRECTANGLEPROFILEDEF(.AREA.,'RECT',#\(pos),\(r(x.width)),\(r(x.depth)))")
                let mp = add("IFCMATERIALPROFILE($,$,#\(matID[x.material.name]!),#\(prof),$,$)")
                profileSet[key] = add("IFCMATERIALPROFILESET($,$,(#\(mp)),$)")
            }
            let usage = add("IFCMATERIALPROFILESETUSAGE(#\(profileSet[key]!),5,$)")
            add("IFCRELASSOCIATESMATERIAL(\(g("mat:member:\(x.id)")),#\(oh),$,$,(#\(id)),#\(usage))")
            for (end, nid) in [("start", a), ("end", b)] {
                if let c = connOf[nid] { add("IFCRELCONNECTSSTRUCTURALMEMBER(\(g("rel:\(x.id):\(end)")),#\(oh),$,$,#\(id),#\(c),$,$,$,$)") }
            }
        }
        // Surface members.
        var surfaceIDs: [Int: Int] = [:]
        for p in m.panels where p.outline.count >= 3 {
            let vs = p.outline.map(vertex)
            var edges: [Int] = []
            for i in 0..<vs.count {
                let e = add("IFCEDGE(#\(vs[i]),#\(vs[(i + 1) % vs.count]))")
                edges.append(add("IFCORIENTEDEDGE(*,*,#\(e),.T.)"))
            }
            let loop = add("IFCEDGELOOP(\(refs(edges)))")
            let bound = add("IFCFACEOUTERBOUND(#\(loop),.T.)")
            // Plane of the panel (Newell normal).
            var nrm = Vec3.zero
            for i in 0..<p.outline.count { let a = p.outline[i], b = p.outline[(i + 1) % p.outline.count]; nrm = nrm + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
            let nn = nrm.length > 1e-12 ? nrm / nrm.length : Vec3(0, 0, 1)
            var xd = p.outline[1] - p.outline[0]; xd = xd - nn * xd.dot(nn); xd = xd.length > 1e-12 ? xd / xd.length : Vec3(1, 0, 0)
            let pl = add("IFCPLANE(#\(add("IFCAXIS2PLACEMENT3D(#\(pt(p.outline[0])),#\(add("IFCDIRECTION((\(r(nn.x)),\(r(nn.y)),\(r(nn.z))))")),#\(add("IFCDIRECTION((\(r(xd.x)),\(r(xd.y)),\(r(xd.z))))")))")))")
            let face = add("IFCFACESURFACE((#\(bound)),#\(pl),.T.)")
            let rep = add("IFCTOPOLOGYREPRESENTATION(#\(topo),'Reference','Face',(#\(face)))")
            let pds = add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(rep)))")
            let id = add("IFCSTRUCTURALSURFACEMEMBER(\(g("panel:\(p.id)")),#\(oh),'S\(p.id)',$,\(s(p.kind)),#\(placement),#\(pds),.SHELL.,\(r(p.thickness)))")
            surfaceIDs[p.id] = id
            members.append(id)
            if let mid = matID[p.material.name] { add("IFCRELASSOCIATESMATERIAL(\(g("mat:panel:\(p.id)")),#\(oh),$,$,(#\(id)),#\(mid))") }
        }
        // Load cases and actions.
        var groups: [Int] = []
        func loadGroup(_ key: String, _ nm: String, action: String, source: String, _ acts: [Int]) {
            guard !acts.isEmpty else { return }
            let lg = add("IFCSTRUCTURALLOADGROUP(\(g("lc:" + key)),#\(oh),\(s(nm)),$,$,.LOAD_CASE.,.\(action).,.\(source).,1.,$)")
            add("IFCRELASSIGNSTOGROUP(\(g("lcrel:" + key)),#\(oh),$,$,\(refs(acts)),$,#\(lg))")
            groups.append(lg)
        }
        func planar(_ p: AnalyticalPanel, _ q: Double, _ tag: String) -> Int? {
            guard let sid = surfaceIDs[p.id], abs(q) > 1e-12 else { return nil }
            let load = add("IFCSTRUCTURALLOADPLANARFORCE(\(s(tag)),0.,0.,\(r(-q * 1000)))")
            let act = add("IFCSTRUCTURALPLANARACTION(\(g("act:\(tag):\(p.id)")),#\(oh),\(s(tag)),$,$,#\(placement),$,#\(load),.GLOBAL_COORDS.,.F.,.TRUE_LENGTH.,.CONST.)")
            add("IFCRELCONNECTSSTRUCTURALACTIVITY(\(g("actrel:\(tag):\(p.id)")),#\(oh),$,$,#\(sid),#\(act))")
            return act
        }
        let slabs = m.panels.filter { $0.kind == "slab" }
        loadGroup("dead", "Superimposed dead load", action: "PERMANENT_G", source: "DEAD_LOAD_G", slabs.compactMap { planar($0, o.deadLoad, "Dead") })
        loadGroup("live", "Imposed load", action: "VARIABLE_Q", source: "LIVE_LOAD_Q", slabs.compactMap { planar($0, o.liveLoad, "Live") })
        let userCases = Array(Set(m.nodeLoads.map(\.loadCase).filter { !$0.isEmpty })).sorted()
        for c in userCases {
            var acts: [Int] = []
            for (i, l) in m.nodeLoads.enumerated() where l.loadCase == c {
                guard let conn = connOf[l.node] else { continue }
                let load = add("IFCSTRUCTURALLOADSINGLEFORCE(\(s(c)),\(r(l.force.x * 1000)),\(r(l.force.y * 1000)),\(r(l.force.z * 1000)),\(r(l.moment.x * 1000)),\(r(l.moment.y * 1000)),\(r(l.moment.z * 1000)))")
                let v = vertexOf[l.node].map { "#\($0)" } ?? "$"
                let rep = v == "$" ? "$" : "#\(add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(add("IFCTOPOLOGYREPRESENTATION(#\(topo),'Reference','Vertex',(\(v)))")))))"))"
                let act = add("IFCSTRUCTURALPOINTACTION(\(g("pact:\(c):\(i)")),#\(oh),\(s(c)),$,$,#\(placement),\(rep),#\(load),.GLOBAL_COORDS.,.F.)")
                add("IFCRELCONNECTSSTRUCTURALACTIVITY(\(g("pactrel:\(c):\(i)")),#\(oh),$,$,#\(conn),#\(act))")
                acts.append(act)
            }
            let variable = c.lowercased().contains("live") || c.lowercased().contains("wind") || c.lowercased().contains("snow")
            loadGroup("user:" + c, c, action: variable ? "VARIABLE_Q" : "PERMANENT_G", source: variable ? "LIVE_LOAD_Q" : "DEAD_LOAD_G", acts)
        }
        let model = add("IFCSTRUCTURALANALYSISMODEL(\(g("model")),#\(oh),\(s(name + " analysis")),$,$,.LOADING_3D.,$,\(groups.isEmpty ? "$" : refs(groups)),$,#\(placement))")
        if !members.isEmpty { add("IFCRELASSIGNSTOGROUP(\(g("modelrel")),#\(oh),$,$,\(refs(members)),$,#\(model))") }
        add("IFCRELDECLARES(\(g("declares")),#\(oh),$,$,#\(project),(#\(model)))")
        _ = memberIDs

        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        var out = "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('ViewDefinition [StructuralAnalysisView]'),'2;1');\n"
        out += "FILE_NAME(\(s(name + ".ifc")),\(s(iso.string(from: Date()))),(\(s(author))),(''),'Oanarina Archi Tool','Oanarina Archi Tool','');\n"
        out += "FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n" + lines.joined(separator: "\n") + "\nENDSEC;\nEND-ISO-10303-21;\n"
        return out
    }
}
