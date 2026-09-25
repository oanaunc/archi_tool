// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for review and building analysis: COMPARE, MARKUP, BCFOUT/BCFIN, EGRESS, ACCESSIBILITY, ENERGYBALANCE,
// BOQ and TAKEOFFPHASE.
import Foundation

public enum ReviewCommands {
    public static var all: [CommandDef] { [compare, markup, bcfOut, bcfIn, egress, accessibility, energyBalance, boq, takeoffPhase] }

    /// Edits the document inside the running command (the command itself is the undo step).
    @MainActor static func edit(_ ed: Editor, _ body: (inout ArchiDocument) -> Void) {
        var d = ed.doc
        body(&d)
        if d != ed.doc { ed.doc = d }
    }

    @MainActor static func zoomTo(_ ed: Editor, _ box: BBox2, ids: [EntityID]) {
        ed.selection = Set(ids)
        if !box.isEmpty { ed.host?.perform(.zoomWindow(box.expanded(by: max(box.width, box.height) * 0.15 + 1)), editor: ed) }
    }

    static var compare: CommandDef {
        CommandDef("COMPARE", aliases: ["DWGCOMPARE", "DRAWINGCOMPARE", "MODELDIFF"], category: "Collaborate",
                   summary: "Compares the drawing with another version (.archi, .dxf, .ifc…) by object id and geometry: added, removed and modified objects; optional colour-coded overlay file (green added, red removed, yellow modified) and CSV report.") { ed in
            let url = try await IOCommands.path(ed, "Enter the other (older) version to compare with")
            let old: ArchiDocument
            do { old = try FileImport.load(url, reference: ed.doc).0 } catch { throw CommandError.invalid("Cannot read \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            let d = DocumentCompare.compare(old, ed.doc)
            for l in d.report.split(separator: "\n").prefix(200) { ed.print(String(l)) }
            if d.isIdentical { ed.print("The drawings are identical."); return }
            let changed = d.differences.filter { $0.kind != .removed }.map(\.id)
            ed.selection = Set(changed)
            let choice = try await ed.getKeyword("Output [Overlay/Csv/Highlight/None]", ["Overlay", "Csv", "Highlight", "None"], defaultValue: "None") ?? "None"
            switch choice {
            case "Overlay":
                guard let p = try await ed.getWord("Enter overlay file name <compare-overlay.archi>", defaultValue: "compare-overlay.archi") else { return }
                var out = IOCommands.resolve(ed, p)
                if out.pathExtension.isEmpty { out.appendPathExtension("archi") }
                do { try ArchiFile.encode(DocumentCompare.overlay(old, ed.doc, diff: d)).write(to: out, options: .atomic); ed.print("Wrote overlay \(out.path).") }
                catch { throw CommandError.invalid("Cannot write \(out.path)") }
            case "Csv":
                try await AnalysisCommands.saveCSV(ed, d.csv, prompt: "Enter CSV file name")
            case "Highlight":
                // Tag changed objects in this drawing (props "change"), undoable; removed ones are listed only.
                edit(ed) { doc in
                    for c in d.changes where c.kind == .added || c.kind == .modified {
                        if let i = doc.entityIndex(c.id) { doc.entities[i].props["change"] = c.kind.rawValue }
                        if let i = doc.elementIndex(c.id) { doc.elements[i].props["change"] = c.kind.rawValue }
                    }
                }
                ed.print("Tagged \(changed.count) changed objects (props change=added/modified); they are selected.")
            default: break
            }
            try await AnalysisCommands.zoomLoop(ed, d.differences.filter { $0.kind != .removed }.map { ([$0.id], $0.bounds) })
        }
    }

    static var markup: CommandDef {
        CommandDef("MARKUP", aliases: ["MARKUPS", "REVCOMMENT", "COMMENT", "ISSUE"], category: "Collaborate",
                   summary: "Review markups stored in the drawing: Add (cloud + comment with author/date, linked to selected elements and the view), List, Resolve, Reopen, Reply, Zoom, Delete.") { ed in
            let opt = try await ed.getKeyword("Markup [Add/List/Resolve/Reopen/Reply/Zoom/Delete]", ["Add", "List", "Resolve", "Reopen", "Reply", "Zoom", "Delete"], defaultValue: "List") ?? "List"
            @MainActor func pick() async throws -> Markup {
                let all = Markups.list(ed.doc)
                guard !all.isEmpty else { throw CommandError.invalid("The drawing has no markups.") }
                for (i, m) in all.enumerated() { ed.print("\(i + 1). [\(m.status)] \(m.author): \(m.title.isEmpty ? m.comment : m.title) (\(m.id.prefix(8)))") }
                guard let k = try await ed.getWord("Enter markup number or id"), let m = Markups.find(ed.doc, k) else { throw CommandError.invalid("No such markup.") }
                return m
            }
            switch opt {
            case "Add":
                let pre = Array(ed.selection).sorted()
                let a = try await ed.requirePoint("Specify first corner of the markup cloud")
                let b = try await ed.requirePoint("Specify opposite corner", base: a, preview: { p in [.polyline(Markups.cloud(a, p, arc: max(abs(p.x - a.x), abs(p.y - a.y), 1) / 8))] })
                guard let text = try await ed.getString("Enter comment"), !text.isEmpty else { throw CommandError.invalid("A comment is required.") }
                let title = try await ed.getString("Enter title <none>") ?? ""
                var linked = pre
                if linked.isEmpty {
                    let lo = Vec2(min(a.x, b.x), min(a.y, b.y)), hi = Vec2(max(a.x, b.x), max(a.y, b.y))
                    linked = ed.doc.elements.filter { $0.level == ed.doc.currentLevel && BBox2(min: lo, max: hi).contains(PlanRepresentation.bounds($0, doc: ed.doc).center) }.map(\.id)
                }
                var id = ""
                edit(ed) { d in id = Markups.add(&d, rect: (a, b), title: title, comment: text, elements: linked, level: d.currentLevel) }
                ed.print("Markup \(id.prefix(8)) added by \(Markups.author(ed.doc))\(linked.isEmpty ? "" : ", linked to " + linked.map { "#\($0)" }.joined(separator: ", ")).")
            case "List":
                let all = Markups.list(ed.doc)
                if all.isEmpty { ed.print("No markups."); return }
                for (i, m) in all.enumerated() {
                    ed.print("\(i + 1). [\(m.status)] \(m.date.prefix(10)) \(m.author): \(m.title.isEmpty ? "" : m.title + " — ")\(m.comment)\(m.replies.isEmpty ? "" : " (\(m.replies.count) replies)")")
                }
                try await AnalysisCommands.zoomLoop(ed, all.map { ($0.elements + $0.entityIDs, BBox2(min: $0.viewCenter - Vec2($0.viewHeight * 0.8, $0.viewHeight / 2), max: $0.viewCenter + Vec2($0.viewHeight * 0.8, $0.viewHeight / 2))) })
            case "Resolve", "Reopen":
                let m = try await pick()
                edit(ed) { d in Markups.setStatus(&d, m.id, resolved: opt == "Resolve") }
                ed.print("Markup \(m.id.prefix(8)) \(opt == "Resolve" ? "resolved" : "reopened").")
            case "Reply":
                let m = try await pick()
                guard let t = try await ed.getString("Enter reply"), !t.isEmpty else { return }
                edit(ed) { d in Markups.reply(&d, m.id, text: t) }
            case "Zoom":
                let m = try await pick()
                zoomTo(ed, BBox2(min: m.viewCenter - Vec2(m.viewHeight * 0.8, m.viewHeight / 2), max: m.viewCenter + Vec2(m.viewHeight * 0.8, m.viewHeight / 2)), ids: m.elements)
                if let l = m.level, ed.doc.level(l) != nil { ed.doc.currentLevel = l }
                ed.print("\(m.author) \(m.date.prefix(10)): \(m.comment)")
            case "Delete":
                let m = try await pick()
                edit(ed) { d in Markups.remove(&d, m.id) }
                ed.print("Markup deleted.")
            default: break
            }
        }
    }

    static var bcfOut: CommandDef {
        CommandDef("BCFOUT", aliases: ["BCFEXPORT", "EXPORTBCF"], category: "Collaborate",
                   summary: "Exports the markups as BCF 2.1 topics (.bcfzip) with comments, status, camera and selected elements by IFC GlobalId.", modifies: false) { ed in
            guard !Markups.list(ed.doc).isEmpty else { throw CommandError.invalid("The drawing has no markups (MARKUP Add).") }
            var url = try await IOCommands.path(ed, "Enter BCF file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("bcfzip") }
            do { try BCF.export(ed.doc).write(to: url, options: .atomic) } catch { throw CommandError.invalid("Cannot write \(url.path)") }
            ed.print("Wrote \(Markups.list(ed.doc).count) topics to \(url.path).")
        }
    }

    static var bcfIn: CommandDef {
        CommandDef("BCFIN", aliases: ["BCFIMPORT", "IMPORTBCF"], category: "Collaborate",
                   summary: "Imports BCF 2.x topics (.bcfzip) as markups: comments, status, viewpoint camera and selection mapped to elements by IFC GlobalId.") { ed in
            let url = try await IOCommands.path(ed, "Enter BCF file name")
            let topics: [BCFTopic]
            do { topics = try BCF.read(try Data(contentsOf: url)) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(url.lastPathComponent)") }
            var ids: [String] = []
            edit(ed) { d in ids = BCF.importTopics(topics, into: &d) }
            let linked = topics.reduce(0) { $0 + ($1.viewpoint?.selection.count ?? 0) }
            ed.print("Imported \(ids.count) topics as markups (\(linked) selected components).")
        }
    }

    static var egress: CommandDef {
        CommandDef("EGRESS", aliases: ["TRAVELDISTANCE", "ESCAPEROUTES", "EGRESSCHECK"], category: "Analysis",
                   summary: "Egress check: longest walking distance from each room to the nearest exit (exterior or exit=1 doors, stairs on upper levels) around walls and columns, against the limit (EGRESSMAX, m). Draws the routes on EGRESS-ROUTES.") { ed in
            var o = EgressOptions.from(ed.doc)
            if case .value(let v) = try await ed.getReal("Enter maximum travel distance (m) <\(fmt(o.maxDistance, 1))>", defaultValue: o.maxDistance), v > 0 { o.maxDistance = v }
            let lv = ed.doc.currentLevel
            let r = EgressAnalysis.compute(ed.doc, level: lv, options: o)
            guard !r.rows.isEmpty else { ed.print("No rooms on this level."); return }
            if r.exits.isEmpty { ed.print("No exits found: doors in exterior walls count, or set props exit=1 on a door.") }
            for row in r.rows {
                ed.print("\(row.number.isEmpty ? "" : row.number + " ")\(row.name): \(row.distance.map { fmt($0, 1) + " m" } ?? "no route to an exit") — \(row.ok ? "OK" : "FAIL")")
            }
            if try await ed.getYesNo("Draw the routes?", defaultValue: false) {
                edit(ed) { d in
                    if d.layerIndex("EGRESS-ROUTES") == nil { d.layers.append(Layer(name: "EGRESS-ROUTES", color: RGBA(0.1, 0.75, 0.3), lineweight: 0.5)) }
                    for row in r.rows where row.path.count >= 2 {
                        _ = d.add(Entity(layer: "EGRESS-ROUTES", color: row.ok ? .byLayer : .aci(1), geometry: .polyline(PolylineGeom(points: row.path)),
                                         props: ["egressRoom": "\(row.id)", "distance": row.distance.map { fmt($0, 2) } ?? ""]))
                    }
                }
            }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(r.table))
            try await AnalysisCommands.zoomLoop(ed, r.failures.map { ([$0.id], BBox2(points: $0.path)) })
        }
    }

    static var accessibility: CommandDef {
        CommandDef("ACCESSIBILITY", aliases: ["A11Y", "ACCESSCHECK", "ADACHECK"], category: "Analysis",
                   summary: "Accessibility check: door clear widths (A11YDOORWIDTH, default 850 mm) and Ø1500 mm wheelchair turning circles in bathrooms clear of fixtures (A11YTURNING).", modifies: false) { ed in
            let lv = try await AnalysisCommands.level(ed)
            let res = Accessibility.check(ed.doc, level: lv, options: AccessibilityOptions.from(ed.doc))
            for t in res.turning { ed.print("\(t.name): free turning circle Ø\(fmt(t.diameter, 0)) mm — \(t.ok ? "OK" : "too small")") }
            if res.issues.isEmpty { ed.print("No accessibility issues found."); return }
            for (i, iss) in res.issues.enumerated() { ed.print("\(i + 1). \(iss.description)") }
            try await AnalysisCommands.zoomLoop(ed, res.issues.map { ($0.ids, $0.bounds) })
        }
    }

    static var energyBalance: CommandDef {
        CommandDef("ENERGYBALANCE", aliases: ["HEATINGNEED", "ENERGYNEED", "SOLARGAINS"], category: "Analysis",
                   summary: "Seasonal heating energy balance: losses from degree days (latitude table or HDD), solar gains per window orientation, internal gains, utilisation factor; optional CSV.", modifies: false) { ed in
            var cl = ClimateData.from(ed.doc)
            if case .value(let v) = try await ed.getReal("Enter heating degree days (K·d) <\(fmt(cl.degreeDays, 0))>", defaultValue: cl.degreeDays), v >= 0, abs(v - cl.degreeDays) > 1e-9 {
                cl.degreeDays = v; cl.source = "entered"
            }
            let eb = EnergyBalance.compute(ed.doc, climate: cl, options: EnergyBalanceOptions.from(ed.doc))
            for l in eb.report.split(separator: "\n") { ed.print(String(l)) }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(eb.table))
        }
    }

    static var boq: CommandDef {
        CommandDef("BOQ", aliases: ["BILLOFQUANTITIES", "BILLQ"], category: "Analysis",
                   summary: "Bill of quantities: takeoff items priced with unit rates (UNITPRICE rates or a JSON table), numbered by trade with subtotals, contingency (BOQCONTINGENCY %) and VAT (BOQVAT %); CSV or XLSX.", modifies: false) { ed in
            var table = CostTable.fromVariables(ed.doc)
            if let p = try await ed.getWord("Enter unit price JSON file <drawing rates>"), !p.isEmpty {
                do { table = try CostTable.fromJSON(try FileImport.readText(IOCommands.resolve(ed, p))) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(p)") }
            }
            guard !table.prices.isEmpty else { throw CommandError.invalid("No unit rates: use UNITPRICE or give a JSON price table.") }
            var o = BoQOptions.from(ed.doc)
            if case .value(let v) = try await ed.getReal("Enter VAT % <\(fmt(o.vat, 2))>", defaultValue: o.vat) { o.vat = v }
            let b = BillOfQuantities.build(QuantityTakeoff.compute(ed.doc), table: table, options: o)
            for l in b.report.split(separator: "\n") { ed.print(String(l)) }
            guard let p = try await ed.getWord("Enter file name to save (.csv or .xlsx) <none>"), !p.isEmpty else { return }
            var url = IOCommands.resolve(ed, p)
            if url.pathExtension.isEmpty { url.appendPathExtension("csv") }
            do {
                if url.pathExtension.lowercased() == "xlsx" { try b.xlsx.write(to: url, options: .atomic) } else { try b.csv.write(to: url, atomically: true, encoding: .utf8) }
                ed.print("Wrote \(url.path).")
            } catch { throw CommandError.invalid("Cannot write \(url.path)") }
        }
    }

    static var takeoffPhase: CommandDef {
        CommandDef("TAKEOFFPHASE", aliases: ["QTOPHASE", "PHASEQUANTITIES", "TAKEOFFLEVEL"], category: "Analysis",
                   summary: "Quantity takeoff split by construction phase (new work and demolition) and level; optional CSV.", modifies: false) { ed in
            let t = PhaseLevelTakeoff.compute(ed.doc)
            guard !t.groups.isEmpty else { ed.print("No BIM elements to measure."); return }
            for g in t.groups {
                ed.print("\(g.phase) — \(g.work) — \(g.levelName):")
                for l in g.lines {
                    var q: [String] = ["\(l.count)×"]
                    if l.length > 0 { q.append("\(fmt(l.length, 2)) m") }
                    if l.area > 0 { q.append("\(fmt(l.area, 2)) m²") }
                    if l.volume > 0 { q.append("\(fmt(l.volume, 3)) m³") }
                    ed.print("  \(l.category) \(l.key)\(l.material.isEmpty ? "" : " (\(l.material))"): " + q.joined(separator: ", "))
                }
            }
            try await AnalysisCommands.saveCSV(ed, t.csv)
        }
    }
}
