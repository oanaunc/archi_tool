// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

extension ModelingCommands {
    /// Push/pull a face of any solid picked in plan (top, bottom or side face).
    @MainActor static func pushPullFace(_ ed: Editor, _ id: EntityID, _ s: SolidGeom, at p: Vec2, mode: String) async throws {
        let tol = 300 / ed.doc.units.mm
        guard let f = FacePushPull.pick(s, at: p, mode: mode, tolerance: tol) else { throw CommandError.invalid("No \(mode) face of that solid at the picked point.") }
        guard let d = try await ed.getDistance("Specify push/pull distance (face area \(fmt(f.area * pow(ed.doc.units.mm, 2) / 1e6, 3)) m², + pulls out)", defaultValue: ed.variableDouble("PRESSPULLDIST", 500 / ed.doc.units.mm)).value,
              abs(d) > 1e-9 else { return }
        ed.doc.setVariable("PRESSPULLDIST", fmt(d))
        guard let r = FacePushPull.apply(s, face: f, distance: d) else {
            ed.doc.remove(ids: [id]); ed.print("The solid was pushed away entirely (UNDO restores it)."); return
        }
        var nr = r; if nr.source == nil { nr.source = s.source }
        replace(ed, id, with: nr)
        ed.print("Face \(d > 0 ? "pulled" : "pushed") by \(fmt(abs(d))): volume " + volumeText(CSG.volume(nr), units: ed.doc.units) + ".")
    }
}

/// Solid feature history, face push/pull and section blocks of solids.
enum FeatureCommands {
    static var all: [CommandDef] { [solidHist, solidHistory, pressPullFace, sectionSolids] }

    static var solidHist: CommandDef {
        CommandDef("SOLIDHIST", aliases: ["RECORDHISTORY"], category: "3D", summary: "Turns recording of the CSG feature history of solids on or off (booleans on solids with a history always record).") { ed in
            let cur = ed.doc.variable("SOLIDHIST") == "1"
            let k = try await ed.getKeyword("Record solid history? [On/Off]", ["On", "Off"], defaultValue: cur ? "On" : "Off") ?? (cur ? "On" : "Off")
            ed.doc.setVariable("SOLIDHIST", k == "On" ? "1" : "0")
            ed.print("Solid history recording is \(k == "On" ? "on" : "off").")
        }
    }

    static var solidHistory: CommandDef {
        CommandDef("SOLIDHISTORY", aliases: ["FEATURES", "FEATURETREE", "SHISTORY"], category: "3D", summary: "Feature list of a solid: list, suppress/unsuppress, delete or move a boolean feature (the solid regenerates), or flatten the history.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select a solid", filter: { ModelingCommands.solidOf(ed.doc, $0) != nil }), var s = ModelingCommands.solidOf(ed.doc, pk.id) else { return }
            if s.history == nil {
                guard try await ed.getYesNo("The solid has no history. Start one (later booleans are recorded)?", defaultValue: true) else { return }
                var b = s; b.source = nil
                s.history = SolidHistory(base: b)
                ModelingCommands.replace(ed, pk.id, with: s)
                ed.print("History started with the current solid as base.")
                return
            }
            var h = s.history!
            for l in SolidHistoryEngine.describe(h) { ed.print(l) }
            let k = try await ed.getKeyword("Feature option", ["List", "Suppress", "Unsuppress", "Delete", "Move", "Flatten"], defaultValue: "List") ?? "List"
            if k == "List" { return }
            if k == "Flatten" {
                s.history = nil
                ModelingCommands.replace(ed, pk.id, with: s)
                ed.print("History removed; the solid keeps its current shape.")
                return
            }
            guard !h.features.isEmpty else { throw CommandError.invalid("The solid has no features.") }
            guard let n = try await ed.getInteger("Feature number (1–\(h.features.count))", defaultValue: h.features.count), n >= 1, n <= h.features.count else { throw CommandError.invalid("No such feature.") }
            switch k {
            case "Suppress": h.features[n - 1].suppressed = true
            case "Unsuppress": h.features[n - 1].suppressed = false
            case "Delete": h.features.remove(at: n - 1)
            case "Move":
                let a = try await ed.requirePoint("Specify base point")
                let b = try await ed.requirePoint("Specify second point", base: a) { c in [.line(LineGeom(a, c))] }
                let dz = try await ed.getDistance("Specify vertical displacement", defaultValue: 0).value ?? 0
                SolidHistoryEngine.moveTool(&h, feature: n - 1, by: Vec3(b.x - a.x, b.y - a.y, dz))
            default: return
            }
            var t = s; t.history = h
            guard let r = SolidHistoryEngine.regenerate(t) else { throw CommandError.invalid("The result would be empty; change not applied.") }
            var nr = r; nr.source = s.source
            ModelingCommands.replace(ed, pk.id, with: nr)
            ed.print("Feature \(n) \(k.lowercased())\(k.hasSuffix("e") ? "d" : "ed"); solid regenerated: volume " + ModelingCommands.volumeText(CSG.volume(nr), units: ed.doc.units) + ".")
        }
    }

    static var pressPullFace: CommandDef {
        CommandDef("PRESSPULLFACE", aliases: ["PPFACE", "PUSHPULLFACE", "FACEPULL"], category: "3D", summary: "Pushes or pulls a planar face (top, bottom or side) of any 3D solid along its normal.") { ed in
            var mode = "top"
            while true {
                let a = try await ed.getPoint("Pick a solid face in plan [\(mode) face]", keywords: ["Top", "Bottom", "Side"])
                switch a {
                case .keyword(let k): mode = k.lowercased(); continue
                case .point(let p):
                    let tol = 300 / ed.doc.units.mm
                    let hits = ed.doc.entities.filter { e in
                        guard case .solid(let s) = e.geometry, ed.doc.isVisible(layer: e.layer) else { return false }
                        return FacePushPull.pick(s, at: p, mode: mode, tolerance: tol) != nil
                    }
                    // Highest top face / lowest bottom face / nearest side face among the solids.
                    let pick = hits.max { x, y in
                        guard case .solid(let sx) = x.geometry, case .solid(let sy) = y.geometry,
                              let fx = FacePushPull.pick(sx, at: p, mode: mode, tolerance: tol), let fy = FacePushPull.pick(sy, at: p, mode: mode, tolerance: tol) else { return false }
                        switch mode {
                        case "bottom": return fx.triangles[0].0.z > fy.triangles[0].0.z
                        case "side": return GeometryOps.distance(from: p, toPolyline: fx.boundary.flatMap { [$0.0.xy, $0.1.xy] }) > GeometryOps.distance(from: p, toPolyline: fy.boundary.flatMap { [$0.0.xy, $0.1.xy] })
                        default: return fx.triangles[0].0.z < fy.triangles[0].0.z
                        }
                    }
                    guard let e = pick, case .solid(let s) = e.geometry else { ed.print("No solid face there."); continue }
                    try await ModelingCommands.pushPullFace(ed, e.id, s, at: p, mode: mode)
                    return
                default: return
                }
            }
        }
    }

    static var sectionSolids: CommandDef {
        CommandDef("SECTIONSOLIDS", aliases: ["GENERATESECTION", "SECTIONBLOCK", "SOLIDSECTION"], category: "3D", summary: "Cuts 3D solids with a vertical section plane (two points) and places the 2D section (cut poché + projection) as a block; Plan cuts them horizontally.") { ed in
            let a = try await ed.getPoint("Specify first point of the section plane", keywords: ["Plan"])
            if case .keyword = a {
                let z = try await ed.getDistance("Specify height of the horizontal cut", defaultValue: ed.variableDouble("ELEVATION", 0) + 1000 / ed.doc.units.mm).value ?? 0
                let loops = SolidSections.horizontal(doc: ed.doc, z: z)
                guard !loops.isEmpty else { throw CommandError.invalid("The plane does not cut any solid.") }
                ed.doc.ensureLayer("A-SECT")
                for l in loops {
                    ed.addEntity(.hatch(HatchGeom(loops: [l.map { PolyVertex($0) }], pattern: "ANSI31", scale: ed.variableDouble("HPSCALE", 1), angle: 0)), layer: "A-SECT")
                    ed.addEntity(.polyline(PolylineGeom(points: l, closed: true)), layer: "A-SECT")
                }
                ed.print("\(loops.count) cut outline(s) at height \(fmt(z)).")
                return
            }
            guard let p = a.point else { return }
            let q = try await ed.requirePoint("Specify second point", base: p) { c in [.line(LineGeom(p, c))] }
            let bim = try await ed.getYesNo("Include the building model?", defaultValue: false)
            guard let name = SolidSections.makeBlock(&ed.doc, a: p, b: q, includeModel: bim) else { throw CommandError.invalid("The section plane does not cut or see any solid.") }
            let at = try await ed.requirePoint("Specify lower-left corner of the section drawing")
            ed.doc.ensureLayer("A-VIEW")
            let id = ed.doc.add(.insert(InsertGeom(block: name, position: at)), layer: "A-VIEW")
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = ed.doc.blocks[name]?.description.replacingOccurrences(of: "view:", with: "") }
            ed.print("\(name) placed (\(ed.doc.blocks[name]?.entities.count ?? 0) objects). VIEWUPDATE regenerates it.")
        }
    }
}
