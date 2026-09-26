// Oanarina Archi Tool — GPL-3.0-or-later
// Schedule options of the SCHEDULE command (DOC-041…053): Define, Edit, Export, Import and Place stored schedules.
// They are sub-commands reached through SCHEDULE (so they share its ribbon/menu entries), not separate commands.
import Foundation

enum ScheduleCommands {
    @MainActor static func pick(_ ed: Editor, _ msg: String = "Enter schedule name") async throws -> Int {
        let names = ed.doc.schedules.map(\.name)
        guard let n = try await ed.getWord(msg + (names.isEmpty ? "" : " [" + names.joined(separator: "/") + "]"), defaultValue: names.last) else { throw CommandError.cancelled }
        guard let i = ed.doc.schedules.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("No schedule named \(n).") }
        return i
    }

    /// Field list: "mark, Level, Type:Door type, Cost=Area*350, Share%Area" (name[:heading], heading=formula, heading%field).
    static func parseFields(_ s: String) -> [ScheduleField] {
        s.split(separator: ",").compactMap { raw in
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if let r = t.range(of: "=") {
                let h = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                return ScheduleField(name: h, formula: t[r.upperBound...].trimmingCharacters(in: .whitespaces))
            }
            if let r = t.range(of: "%") {
                let h = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                return ScheduleField(name: h, percentOf: t[r.upperBound...].trimmingCharacters(in: .whitespaces))
            }
            if let r = t.range(of: ":") {
                return ScheduleField(name: t[..<r.lowerBound].trimmingCharacters(in: .whitespaces), heading: t[r.upperBound...].trimmingCharacters(in: .whitespaces))
            }
            return ScheduleField(name: t)
        }
    }

    /// "field op value" (ops: = != > < >= <= contains begins).
    static func parseRule(_ s: String) -> (String, String, String)? {
        for op in [">=", "<=", "!=", "<>", "==", "=", ">", "<", " contains ", " begins "] {
            if let r = s.range(of: op) {
                let f = s[..<r.lowerBound].trimmingCharacters(in: .whitespaces), v = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !f.isEmpty else { return nil }
                return (f, op.trimmingCharacters(in: .whitespaces), v)
            }
        }
        return nil
    }

    static func color(_ s: String) -> RGBA? {
        switch s.lowercased() {
        case "red": return RGBA(1, 0.6, 0.6); case "yellow": return RGBA(1, 0.95, 0.55); case "green": return RGBA(0.65, 0.95, 0.65)
        case "blue": return RGBA(0.65, 0.8, 1); case "orange": return RGBA(1, 0.8, 0.5); case "gray", "grey": return RGBA(0.85, 0.85, 0.85)
        default:
            let c = s.split(separator: ",").compactMap { Double($0) }
            guard c.count == 3 else { return nil }
            let k = c.max()! > 1 ? 255.0 : 1
            return RGBA(c[0] / k, c[1] / k, c[2] / k)
        }
    }

    @MainActor static func show(_ ed: Editor, _ def: ScheduleDefinition) {
        let t = Schedules.evaluate(def, doc: ed.doc)
        ed.print("\(def.name) (\(def.category)):")
        ed.print(t.headings.joined(separator: "\t"))
        var n = 0
        for r in t.rows {
            var line = r.cells.joined(separator: "\t")
            if r.kind == .item || r.kind == .embedded { n += 1; line = "\(n))\t" + line }
            if r.highlight != nil { line += "\t*" }
            ed.print(line)
        }
    }

    static var scheduleDef: CommandDef {
        CommandDef("SCHEDULEDEF", aliases: ["SCHEDULES", "SCHEDDEF", "NEWSCHEDULE"], category: "Architecture",
                   summary: "Defines schedules: New (category), Fields (incl. calculated Cost=Area*350 and percentage Share%Area), Filter, Sort, Group, Totals, Itemize, Highlight, Key (key schedules), Embed, Show, List, Delete.") { ed in
            let k = try await ed.getKeyword("Schedule option", ["List", "New", "Fields", "Filter", "Sort", "Group", "Totals", "Itemize", "Highlight", "Key", "Embed", "Show", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "List":
                if ed.doc.schedules.isEmpty { ed.print("No schedules. Categories: " + Schedules.categories.joined(separator: ", ")) }
                for d in ed.doc.schedules { ed.print("\(d.name): \(d.category), \(d.fields.isEmpty ? "default" : "\(d.fields.count)") field(s), \(d.filters.count) filter(s)") }
            case "New":
                guard let n = try await ed.getWord("Enter schedule name"), !n.isEmpty else { return }
                guard !ed.doc.schedules.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Schedule \(n) already exists.") }
                let c = try await ed.getWord("Category [" + Schedules.categories.joined(separator: "/") + "]", defaultValue: "rooms") ?? "rooms"
                guard let cat = Schedules.category(c) else { throw CommandError.invalid("Unknown category \(c).") }
                ed.doc.schedules.append(ScheduleDefinition(name: n, category: cat, fields: Schedules.defaultFields(cat)))
                ed.print("Schedule \(n) (\(cat)) created with fields " + Schedules.defaultFields(cat).map(\.name).joined(separator: ", ") + ".")
            case "Delete":
                let i = try await pick(ed)
                let n = ed.doc.schedules[i].name
                ed.doc.schedules.remove(at: i)
                ed.doc.entities.removeAll { $0.props[Schedules.placedProp] == n }
                for li in ed.doc.layouts.indices { ed.doc.layouts[li].entities.removeAll { $0.props[Schedules.placedProp] == n } }
                ed.print("Schedule \(n) deleted.")
            case "Show":
                show(ed, ed.doc.schedules[try await pick(ed)])
            default:
                let i = try await pick(ed)
                var d = ed.doc.schedules[i]
                switch k {
                case "Fields":
                    let cur = (d.fields.isEmpty ? Schedules.defaultFields(d.category) : d.fields).map { f -> String in
                        if let fo = f.formula { return "\(f.name)=\(fo)" }; if let p = f.percentOf { return "\(f.name)%\(p)" }
                        return f.heading.map { "\(f.name):\($0)" } ?? f.name }.joined(separator: ", ")
                    guard let s = try await ed.getWord("Fields (comma-separated; Name:Heading, Name=formula, Name%Field)", defaultValue: cur) else { return }
                    let fs = parseFields(s)
                    guard !fs.isEmpty else { throw CommandError.invalid("At least one field is needed.") }
                    d.fields = fs
                case "Filter":
                    guard let s = try await ed.getWord("Filter \"field op value\" or Clear", keywords: ["Clear"]) else { return }
                    if s == "Clear" { d.filters = [] }
                    else { guard let r = parseRule(s) else { throw CommandError.invalid("Use field op value, e.g. \"Level = Ground Floor\".") }; d.filters.append(ScheduleFilter(field: r.0, op: r.1, value: r.2)) }
                case "Sort":
                    guard let s = try await ed.getWord("Sort by (e.g. \"Level, Area desc\"; None clears)") else { return }
                    d.sort = s.lowercased() == "none" ? [] : s.split(separator: ",").map { t in
                        let p = t.split(separator: " ").map(String.init)
                        return ScheduleSort(field: p.first ?? "", descending: p.count > 1 && p[1].lowercased().hasPrefix("desc"))
                    }.filter { !$0.field.isEmpty }
                case "Group":
                    guard let s = try await ed.getWord("Group by field (None = no grouping)") else { return }
                    d.groupBy = s.lowercased() == "none" ? nil : s
                case "Totals": d.totals = try await ed.getYesNo("Show totals?", defaultValue: !d.totals)
                case "Itemize": d.itemize = try await ed.getYesNo("Itemize every instance?", defaultValue: !d.itemize)
                case "Highlight":
                    guard let s = try await ed.getWord("Highlight rule \"field op value\" or Clear", keywords: ["Clear"]) else { return }
                    if s == "Clear" { d.highlights = [] } else {
                        guard let r = parseRule(s) else { throw CommandError.invalid("Use field op value.") }
                        let c = color(try await ed.getWord("Colour [red/yellow/green/blue/orange or r,g,b]", defaultValue: "red") ?? "red") ?? RGBA(1, 0.6, 0.6)
                        d.highlights.append(ScheduleHighlight(field: r.0, op: r.1, value: r.2, color: c))
                    }
                case "Key":
                    guard d.category == "keys" else { throw CommandError.invalid("Key values belong to a schedule of category keys.") }
                    if d.keyParameter == nil { d.keyParameter = try await ed.getWord("Key parameter name (elements carry it)", defaultValue: "\(d.name) Key") }
                    guard let key = try await ed.getWord("Key value") else { return }
                    guard let s = try await ed.getWord("Parameters \"name=value; name=value\" (empty removes the key)", defaultValue: "") else { return }
                    if s.isEmpty { d.keys[key] = nil } else {
                        var row: [String: String] = [:]
                        for p in s.split(separator: ";") { let kv = p.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }; if kv.count == 2 { row[kv[0]] = kv[1] } }
                        d.keys[key] = row
                        let names = Set(d.keys.values.flatMap(\.keys)).sorted()
                        d.fields = [ScheduleField(name: "Key")] + names.map { ScheduleField(name: $0) }
                    }
                case "Embed":
                    guard let s = try await ed.getWord("Embedded category (doors, windows, openings; None)") else { return }
                    d.embedded = s.lowercased() == "none" ? nil : Schedules.category(s)
                default: return
                }
                ed.doc.schedules[i] = d
                ed.print("Schedule \(d.name) updated.")
            }
        }
    }

    static var scheduleEdit: CommandDef {
        CommandDef("SCHEDULEEDIT", aliases: ["EDITSCHEDULE", "SCHEDEDIT"], category: "Architecture",
                   summary: "Edits a schedule cell (row number from SCHEDULEDEF Show, field, value); the change goes to the element.") { ed in
            let i = try await pick(ed)
            guard let row = try await ed.getInteger("Row number"), let field = try await ed.getWord("Field"), let value = try await ed.getWord("New value", defaultValue: "") else { return }
            var d = ed.doc
            guard Schedules.edit(ed.doc.schedules[i], row: row - 1, field: field, value: value, doc: &d) else { throw CommandError.invalid("Cannot set \(field) = \(value) in row \(row) (read-only, calculated or invalid).") }
            ed.doc = d
            ed.print("\(field) = \(value) set.")
        }
    }

    static var scheduleExport: CommandDef {
        CommandDef("SCHEDULEEXPORT", aliases: ["SCHEDULEOUT", "EXPORTSCHEDULE"], category: "Architecture",
                   summary: "Exports a schedule to .csv or .xlsx (with an ElementID column so edits can be read back by SCHEDULEIMPORT).", modifies: false) { ed in
            let i = try await pick(ed)
            var url = try await IOCommands.path(ed, "Enter file name (.csv or .xlsx)")
            if url.pathExtension.isEmpty { url.appendPathExtension("csv") }
            let t = Schedules.evaluate(ed.doc.schedules[i], doc: ed.doc)
            let data = url.pathExtension.lowercased() == "xlsx" ? Schedules.xlsx(t) : Data(Schedules.csv(t).utf8)
            try IOCommands.write(ed, url, "schedule", { try data.write(to: url, options: .atomic) })
        }
    }

    static var scheduleImport: CommandDef {
        CommandDef("SCHEDULEIMPORT", aliases: ["SCHEDULEIN", "IMPORTSCHEDULE"], category: "Architecture",
                   summary: "Reads an edited schedule (.csv or .xlsx exported by SCHEDULEEXPORT) and applies changed values to the elements.") { ed in
            let i = try await pick(ed)
            let url = try await IOCommands.path(ed, "Enter file name (.csv or .xlsx)")
            guard let data = try? Data(contentsOf: url) else { throw CommandError.invalid("Cannot read \(url.path).") }
            let rows: [[String]]
            if url.pathExtension.lowercased() == "xlsx" {
                guard let s = try? XLSX.read(data).first else { throw CommandError.invalid("Cannot read the workbook.") }
                rows = s.rows
            } else { rows = Schedules.parseCSV(String(decoding: data, as: UTF8.self)) }
            var d = ed.doc
            let r = Schedules.applyEdits(ed.doc.schedules[i], rows: rows, doc: &d)
            ed.doc = d
            ed.print("\(r.changed) value(s) updated from \(url.lastPathComponent).")
            for m in r.rejected.prefix(20) { ed.print("  Skipped: \(m)") }
        }
    }

    static var schedulePlace: CommandDef {
        CommandDef("SCHEDULEPLACE", aliases: ["PLACESCHEDULE", "SCHEDULESHEET"], category: "Architecture",
                   summary: "Places a schedule as an associative table on a sheet (or in model space), split into columns of at most n rows.") { ed in
            let i = try await pick(ed)
            let names = ed.doc.layouts.map(\.name)
            let target = try await ed.getWord("Sheet name or Model [" + (["Model"] + names).joined(separator: "/") + "]", defaultValue: names.first ?? "Model") ?? "Model"
            let li = ed.doc.layouts.firstIndex { $0.name.caseInsensitiveCompare(target) == .orderedSame }
            if li == nil && target.lowercased() != "model" { throw CommandError.invalid("No sheet named \(target).") }
            let p = try await ed.requirePoint(li == nil ? "Specify insertion point" : "Specify insertion point on the sheet (mm)")
            let rows = try await ed.getInteger("Maximum rows per column", defaultValue: 25) ?? 25
            let th = li == nil ? ed.settings.textHeight : 2.5
            var d = ed.doc
            let n = Schedules.place(ed.doc.schedules[i], doc: &d, layout: li, at: p, maxRows: max(rows, 1), textHeight: th)
            ed.doc = d
            ed.print("Schedule \(ed.doc.schedules[i].name) placed in \(n) column(s)" + (li.map { " on \(ed.doc.layouts[$0].name)" } ?? "") + ".")
        }
    }
}
