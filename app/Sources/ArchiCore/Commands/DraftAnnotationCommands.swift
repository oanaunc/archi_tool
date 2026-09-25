// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Hatch editing (associative boundaries, separate, recreate boundary), dimension style overrides, CSV-linked tables, spell check.
enum DraftAnnotationCommands {
    static var all: [CommandDef] { [hatchEdit, hatchBoundary, dimOverride, tableLink, dataLinkUpdate, spell, dimReassociate, dimDisassociate, dimRegen] }

    static func isHatch(_ g: Geometry?) -> Bool { if case .hatch? = g { return true }; return false }

    static var hatchEdit: CommandDef {
        CommandDef("HATCHEDIT", aliases: ["HE", "-HATCHEDIT"], category: "Modify", summary: "Edits hatches: Properties (pattern, scale, angle), Color/background, Associate, DIsassociate, ADd/Remove boundaries, recreate Boundary, separate Hatches.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select hatch object", filter: { isHatch(ed.doc.entity($0)?.geometry) }),
                  let i0 = ed.doc.entityIndex(pk.id), case .hatch = ed.doc.entities[i0].geometry else { return }
            let id = pk.id
            @MainActor func hatch() -> HatchGeom? { if case .hatch(let h)? = ed.doc.entity(id)?.geometry { return h }; return nil }
            @MainActor func set(_ h: HatchGeom) { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].geometry = .hatch(h) } }
            let kws = ["Properties", "Color", "Associate", "DIsassociate", "ADd", "Remove", "Boundary", "Hatches"]
            while let k = try await ed.getKeyword("Enter hatch option", kws) {
                guard var h = hatch() else { return }
                switch k {
                case "Properties":
                    let name = try await ed.getWord("Enter a pattern name or [?/Solid]", defaultValue: h.pattern) ?? h.pattern
                    if name == "?" { ed.print("Patterns: " + HatchPatterns.allNames.joined(separator: ", ")); continue }
                    h.pattern = name.uppercased() == "S" ? "SOLID" : name.uppercased()
                    if h.pattern != "SOLID" {
                        if let s = try await ed.getReal("Specify a scale for the pattern", defaultValue: h.scale).value, s > 0 { h.scale = s }
                        h.angle = try await ed.getAngle("Specify an angle for the pattern", defaultValue: h.angle).value ?? h.angle
                    }
                    set(h)
                case "Color":
                    guard let c = try await ed.getWord("Enter fill/background color (None, ByLayer, 1-255, #RRGGBB)", defaultValue: h.fill?.text ?? "None") else { continue }
                    if c.lowercased() == "none" || c.lowercased() == "." { h.fill = nil }
                    else { guard let cr = ColorRef.parse(c) else { throw CommandError.invalid("Invalid color.") }; h.fill = cr }
                    set(h)
                case "DIsassociate":
                    if let i = ed.doc.entityIndex(id) { AssociativeHatch.detach(&ed.doc.entities[i]) }
                    ed.print("Hatch is no longer associative.")
                case "Associate":
                    let ids = try await ed.getEntitySelection("Select boundary objects").filter { $0 != id && !isHatch(ed.doc.entity($0)?.geometry) }
                    guard !ids.isEmpty else { continue }
                    let closed = ids.contains { ed.doc.entity($0).flatMap { CommandHelpers.closedLoop($0.geometry) } != nil }
                    AssociativeHatch.attach(&ed.doc, hatch: id, boundary: ids, seed: closed ? nil : AssociativeHatch.interiorPoint(h))
                    var d = ed.doc; AssociativeHatch.updateAll(&d); ed.doc = d
                    ed.print("Hatch associated with \(ids.count) object(s).")
                case "ADd":
                    let ids = try await ed.getEntitySelection("Select closed objects to add").filter { $0 != id }
                    let loops = ids.compactMap { ed.doc.entity($0).flatMap { CommandHelpers.closedLoop($0.geometry) } }
                    guard !loops.isEmpty else { ed.print("No closed boundary selected."); continue }
                    h.loops = AssociativeHatch.sortLoops(h.loops + loops); set(h)
                    if let i = ed.doc.entityIndex(id), AssociativeHatch.isAssociative(ed.doc.entities[i]) {
                        AssociativeHatch.attach(&ed.doc, hatch: id, boundary: AssociativeHatch.ids(ed.doc.entities[i]) + ids, seed: nil)
                    }
                case "Remove":
                    let p = try await ed.requirePoint("Pick a point on the boundary to remove")
                    guard h.loops.count > 1 else { ed.print("A hatch needs at least one boundary."); continue }
                    let dists = h.loops.map { GeometryOps.distance(from: p, toPolyline: CommandHelpers.loopPoints($0) + [CommandHelpers.loopPoints($0)[0]]) }
                    guard let j = dists.indices.min(by: { dists[$0] < dists[$1] }) else { continue }
                    h.loops.remove(at: j); set(h)
                    if let i = ed.doc.entityIndex(id) { AssociativeHatch.detach(&ed.doc.entities[i]) }
                case "Boundary":
                    try await generateBoundary(ed, [id])
                case "Hatches":
                    let parts = HatchTools.separate(h)
                    guard parts.count > 1, let i = ed.doc.entityIndex(id) else { ed.print("The hatch has a single area."); continue }
                    var base = ed.doc.entities[i]
                    AssociativeHatch.detach(&base)
                    ed.doc.entities[i].geometry = .hatch(parts[0])
                    AssociativeHatch.detach(&ed.doc.entities[i])
                    for p in parts.dropFirst() { var e = base; e.geometry = .hatch(p); ed.doc.add(e) }
                    ed.print("\(parts.count) separate hatches.")
                    return
                default: return
                }
            }
        }
    }

    @MainActor static func generateBoundary(_ ed: Editor, _ ids: [EntityID]) async throws {
        var n = 0
        for id in ids {
            guard let e = ed.doc.entity(id), case .hatch(let h) = e.geometry else { continue }
            var made: [EntityID] = []
            for pl in HatchTools.boundaryPolylines(h) { made.append(ed.addEntity(.polyline(pl), layer: e.layer)) }
            AssociativeHatch.attach(&ed.doc, hatch: id, boundary: made, seed: nil)
            n += made.count
        }
        ed.print("\(n) boundary polyline(s) created and associated.")
    }

    static var hatchBoundary: CommandDef {
        CommandDef("HATCHGENERATEBOUNDARY", aliases: ["HGB"], category: "Modify", summary: "Creates closed polylines around selected hatches and makes the hatches associative to them.") { ed in
            let ids = try await ed.getEntitySelection("Select hatches").filter { isHatch(ed.doc.entity($0)?.geometry) }
            guard !ids.isEmpty else { return }
            try await generateBoundary(ed, ids)
            ed.selection = []
        }
    }

    static var dimOverride: CommandDef {
        CommandDef("DIMOVERRIDE", aliases: ["DOV", "-DIMOVERRIDE"], category: "Annotate", summary: "Overrides dimension style variables (DIMTXT, DIMASZ, DIMDEC, DIMSCALE, DIMPOST…) on selected dimensions, or Clear overrides.") { ed in
            var o: [String: String] = [:]
            var clear = false
            while true {
                let msg = o.isEmpty ? "Enter dimension variable name to override or [Clear overrides]" : "Enter dimension variable name to override"
                guard let n = try await ed.getWord(msg, keywords: o.isEmpty ? ["Clear"] : []) else { break }
                if n == "Clear" { clear = true; break }
                let cur = SysVarCatalog.dimGet(n.uppercased(), ed.doc.dimStyle) ?? ""
                guard let v = try await ed.getWord("Enter new value for dimension variable", defaultValue: cur) else { continue }
                if let e = DimOverrides.validate(n, v) { throw CommandError.invalid(e) }
                if let info = SysVarCatalog.info(n), info.kind != .string, let norm = SysVarCatalog.validate(info, v).0 { o[n.uppercased()] = norm } else { o[n.uppercased()] = v }
            }
            guard clear || !o.isEmpty else { return }
            let ids = try await ed.getEntitySelection("Select dimensions").filter { if case .dimension? = ed.doc.entity($0)?.geometry { return true }; return false }
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                var e = ed.doc.entities[i]
                if clear { DimOverrides.clear(&e) } else { DimOverrides.apply(o, to: &e, doc: &ed.doc) }
                ed.doc.entities[i] = e
            }
            ed.selection = []
            ed.print(clear ? "Overrides cleared on \(ids.count) dimension(s)." : "\(o.count) override(s) applied to \(ids.count) dimension(s).")
        }
    }

    static func isDim(_ g: Geometry?) -> Bool { if case .dimension? = g { return true }; return false }

    static var dimReassociate: CommandDef {
        CommandDef("DIMREASSOCIATE", aliases: ["DRE"], category: "Annotate", summary: "Associates dimensions with the objects at their definition points (automatic within a tolerance) so they follow edits.") { ed in
            let ids = try await ed.getEntitySelection("Select dimensions to reassociate").filter { isDim(ed.doc.entity($0)?.geometry) }
            let tol = try await ed.getDistance("Specify search tolerance", defaultValue: ed.pickTolerance).value ?? ed.pickTolerance
            var n = 0, pts = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                var e = ed.doc.entities[i]
                let k = DimAssociation.associate(&e, doc: ed.doc, tol: tol)
                ed.doc.entities[i] = e
                if k > 0 { n += 1; pts += k }
            }
            var d = ed.doc; DimAssociation.updateAll(&d); ed.doc = d
            ed.selection = []
            ed.print("\(n) of \(ids.count) dimension(s) associated (\(pts) point(s)).")
        }
    }
    static var dimDisassociate: CommandDef {
        CommandDef("DIMDISASSOCIATE", aliases: ["DDA"], category: "Annotate", summary: "Removes associativity from selected dimensions.") { ed in
            let ids = try await ed.getEntitySelection("Select dimensions to disassociate").filter { isDim(ed.doc.entity($0)?.geometry) }
            var n = 0
            for id in ids { if let i = ed.doc.entityIndex(id), ed.doc.entities[i].props[DimAssociation.prop] != nil { ed.doc.entities[i].props[DimAssociation.prop] = nil; n += 1 } }
            ed.selection = []
            ed.print("\(n) dimension(s) disassociated.")
        }
    }
    static var dimRegen: CommandDef {
        CommandDef("DIMREGEN", category: "Annotate", summary: "Updates associative dimensions, dimension breaks and overrides.") { ed in
            var d = ed.doc
            DimAssociation.updateAll(&d); DimOverrides.updateAll(&d); DimBreaks.updateAll(&d)
            ed.doc = d
        }
    }

    static var tableLink: CommandDef {
        CommandDef("TABLELINK", aliases: ["DATALINK", "TABLEFROMCSV"], category: "Annotate", summary: "Inserts a table linked to a CSV file (update with DATALINKUPDATE when the file changes).") { ed in
            guard let path = try await ed.getWord("Enter CSV file name") else { return }
            let base = ed.fileURL?.deletingLastPathComponent()
            let url = TableDataLink.url(path, base: base)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(url.path).") }
            let rows = TableDataLink.parseCSV(text)
            guard !rows.isEmpty else { throw CommandError.invalid("The file has no rows.") }
            let th = ed.settings.textHeight
            let p = try await ed.requirePoint("Specify insertion point") { c in [.table(TableDataLink.table(rows, origin: c, textHeight: th))] }
            let id = ed.addEntity(.table(TableDataLink.table(rows, origin: p, textHeight: th)))
            if let i = ed.doc.entityIndex(id) {
                ed.doc.entities[i].props[TableDataLink.prop] = path
                ed.doc.entities[i].props[TableDataLink.modifiedProp] = TableDataLink.modified(url).map { fmt($0, 3) }
            }
            ed.print("Table with \(rows.count) row(s) linked to \(url.lastPathComponent).")
        }
    }

    static var dataLinkUpdate: CommandDef {
        CommandDef("DATALINKUPDATE", aliases: ["DLU"], category: "Annotate", summary: "Updates linked tables from their CSV files (Update) or writes table cells back to the files (Write).") { ed in
            let k = try await ed.getKeyword("Select a data link option", ["Update", "Write"], defaultValue: "Update") ?? "Update"
            let w = try await ed.getWord("Select tables (#ids) or [All]", defaultValue: "All", keywords: ["All"]) ?? "All"
            let base = ed.fileURL?.deletingLastPathComponent()
            let linked = ed.doc.entities.filter { $0.props[TableDataLink.prop] != nil }.map(\.id)
            let ids = w == "All" ? linked : w.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }.filter { linked.contains($0) }
            var n = 0
            do {
                for id in ids {
                    guard let i = ed.doc.entityIndex(id) else { continue }
                    if k == "Write" { try TableDataLink.writeBack(ed.doc.entities[i], base: base); n += 1 }
                    else { var e = ed.doc.entities[i]; if try TableDataLink.update(&e, base: base) { n += 1 }; ed.doc.entities[i] = e }
                }
            } catch let e as Xrefs.XrefError { throw CommandError.invalid(e.localizedDescription) }
            ed.print(k == "Write" ? "\(n) file(s) written." : "\(n) of \(ids.count) linked table(s) changed.")
        }
    }

    static var spell: CommandDef {
        CommandDef("SPELL", aliases: ["SPELLCHECK"], category: "Annotate", summary: "Checks the spelling of text, leaders, tables, dimension text and attributes (Change / Ignore / Add to the drawing dictionary).") { ed in
            let w = try await ed.getWord("Select objects (#ids) or [All]", defaultValue: "All", keywords: ["All"]) ?? "All"
            let ids: Set<EntityID>? = w == "All" ? nil : Set(w.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) })
            guard let check = SpellCheck.checker else { throw CommandError.invalid("No spell checker is available in this session.") }
            var ignored = Set<String>()
            var changed = 0
            for m in SpellCheck.misspelled(ed.doc, ids: ids, isCorrect: check) where !ignored.contains(m.word.lowercased()) {
                if SpellCheck.customWords(ed.doc).contains(m.word.lowercased()) { continue }
                let sugg = SpellCheck.suggester?(m.word) ?? []
                ed.print("Not in dictionary: \"\(m.word)\" (#\(m.entity) \(m.field))\(sugg.isEmpty ? "" : " — suggestions: " + sugg.prefix(5).joined(separator: ", "))")
                let a = try await ed.getWord("Change to or [Ignore/ignore All/Add]", defaultValue: sugg.first ?? "Ignore", keywords: ["Ignore", "All", "Add"]) ?? "Ignore"
                switch a {
                case "Ignore": continue
                case "All": ignored.insert(m.word.lowercased())
                case "Add": SpellCheck.addWord(m.word, &ed.doc)
                default: if SpellCheck.replace(m.word, with: a, in: m.entity, doc: &ed.doc) { changed += 1 }
                }
            }
            ed.print("Spelling check complete (\(changed) change(s)).")
        }
    }
}
