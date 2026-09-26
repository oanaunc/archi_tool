// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// MARK: - Dimension style overrides (DIMOVERRIDE)

/// Per-dimension style overrides. A dimension with overrides carries props "dimOverrides" ("DIMTXT=3.5;DIMDEC=2") and
/// "dimBaseStyle"; it references a derived style "<base>$OVR<hash>" rebuilt from the base style after every edit, so edits of
/// the base style propagate while the overridden values stay.
public enum DimOverrides {
    public static let prop = "dimOverrides", baseProp = "dimBaseStyle"
    public static let marker = "$OVR"

    public static func parse(_ s: String?) -> [String: String] {
        var out: [String: String] = [:]
        for part in (s ?? "").split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 { out[kv[0].uppercased()] = kv[1] }
        }
        return out
    }
    public static func text(_ o: [String: String]) -> String { o.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") }
    public static func isOverrideStyle(_ name: String) -> Bool { name.contains(marker) }

    /// The style resulting from applying the overrides to a base style.
    public static func derived(_ base: DimStyle, _ o: [String: String]) -> DimStyle {
        var s = base
        for (k, v) in o.sorted(by: { $0.key < $1.key }) { _ = SysVarCatalog.dimSet(k, v, &s) }
        var h: UInt32 = 2166136261
        for b in (base.name + "|" + text(o)).utf8 { h ^= UInt32(b); h = h &* 16777619 }
        s.name = base.name + marker + String(h % 0xFFFFFF, radix: 16, uppercase: true)
        return s
    }

    /// Validates an override (a dimension variable known to the style mapping).
    public static func validate(_ name: String, _ value: String) -> String? {
        let n = name.uppercased()
        guard SysVarCatalog.dimStyleVars.contains(n) else { return "\(n) cannot be overridden (use one of \(SysVarCatalog.dimStyleVars.sorted().joined(separator: ", ")))." }
        if n == "DIMPOST" || n == "DIMBLK" {
            var probe = DimStyle(name: "x")
            return SysVarCatalog.dimSet(n, value, &probe) ? nil : "Invalid value for \(n)."
        }
        guard let info = SysVarCatalog.info(n) else { return nil }
        return SysVarCatalog.validate(info, value).1
    }

    /// Sets overrides on a dimension entity (merging with existing ones; empty dictionary clears them).
    public static func apply(_ o: [String: String], to e: inout Entity, doc: inout ArchiDocument, merge: Bool = true) {
        guard case .dimension(var d) = e.geometry else { return }
        let base = e.props[baseProp] ?? d.style
        var all = merge ? parse(e.props[prop]) : [:]
        for (k, v) in o { all[k.uppercased()] = v }
        if all.isEmpty || o.isEmpty && !merge {
            e.props[prop] = nil; e.props[baseProp] = nil; d.style = base; e.geometry = .dimension(d); return
        }
        e.props[prop] = text(all); e.props[baseProp] = base
        let st = derived(doc.dimStyle(base), all)
        if let i = doc.dimStyles.firstIndex(where: { $0.name == st.name }) { doc.dimStyles[i] = st } else { doc.dimStyles.append(st) }
        d.style = st.name; e.geometry = .dimension(d)
    }
    public static func clear(_ e: inout Entity) {
        guard case .dimension(var d) = e.geometry, let base = e.props[baseProp] else { e.props[prop] = nil; return }
        d.style = base; e.geometry = .dimension(d); e.props[prop] = nil; e.props[baseProp] = nil
    }

    /// Rebuilds derived styles from their base styles and removes derived styles no longer used (DocumentUpdaters).
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard doc.dimStyles.contains(where: { isOverrideStyle($0.name) }) || doc.entities.contains(where: { $0.props[prop] != nil }) else { return false }
        var changed = false
        var used = Set<String>()
        for i in doc.entities.indices where doc.entities[i].props[prop] != nil {
            guard case .dimension(var d) = doc.entities[i].geometry, let base = doc.entities[i].props[baseProp] else { continue }
            let baseStyle = doc.dimStyles.first { $0.name == base } ?? doc.dimStyle
            let st = derived(baseStyle, parse(doc.entities[i].props[prop]))
            if let j = doc.dimStyles.firstIndex(where: { $0.name == st.name }) {
                if doc.dimStyles[j] != st { doc.dimStyles[j] = st; changed = true }
            } else { doc.dimStyles.append(st); changed = true }
            if d.style != st.name { d.style = st.name; doc.entities[i].geometry = .dimension(d); changed = true }
            used.insert(st.name)
        }
        let n = doc.dimStyles.count
        doc.dimStyles.removeAll { isOverrideStyle($0.name) && !used.contains($0.name) && $0.name != doc.currentDimStyle }
        if doc.dimStyles.count != n { changed = true }
        return changed
    }
}

// MARK: - CSV-linked tables (data links)

/// Tables linked to a CSV file: props "dataLink" (path) and "dataLinkModified" (file time at the last update).
public enum TableDataLink {
    public static let prop = "dataLink", modifiedProp = "dataLinkModified"

    /// RFC 4180 CSV (quotes, doubled quotes, embedded separators/newlines); the separator is detected (, ; or tab).
    public static func parseCSV(_ text: String) -> [[String]] {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let sep: Character = [",", ";", "\t"].max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQ = false
        var it = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if it.first == "\u{FEFF}" { it.removeFirst() }
        var i = 0
        while i < it.count {
            let c = it[i]
            if inQ {
                if c == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" { field.append("\""); i += 1 } else { inQ = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty { inQ = true }
            else if c == sep { row.append(field); field = "" }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        let w = rows.map(\.count).max() ?? 0
        return rows.map { $0 + [String](repeating: "", count: w - $0.count) }
    }

    /// Linked sheet of a spreadsheet link (prop), "" = first sheet.
    public static let sheetProp = "dataLinkSheet"

    /// Splits "file.xlsx!Sheet" into the path and the sheet name.
    public static func splitSheet(_ spec: String) -> (path: String, sheet: String?) {
        guard let bang = spec.lastIndex(of: "!"), spec[..<bang].lowercased().hasSuffix(".xlsx") else { return (spec, nil) }
        let sh = String(spec[spec.index(after: bang)...])
        return (String(spec[..<bang]), sh.isEmpty ? nil : sh)
    }
    public static func isSpreadsheet(_ path: String) -> Bool { path.lowercased().hasSuffix(".xlsx") }

    /// Rows of a linked file: CSV text, or one sheet of an .xlsx workbook (by name, else the first sheet).
    public static func rows(at u: URL, sheet: String?) throws -> [[String]] {
        if isSpreadsheet(u.path) {
            guard let data = try? Data(contentsOf: u) else { throw Xrefs.XrefError.unreadable(u.path) }
            guard let sheets = try? XLSX.read(data), !sheets.isEmpty else { throw Xrefs.XrefError.unreadable(u.path) }
            let sh = sheet.flatMap { n in sheets.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } } ?? sheets[0]
            let w = sh.rows.map(\.count).max() ?? 0
            return sh.rows.map { $0 + [String](repeating: "", count: w - $0.count) }
        }
        guard let text = try? String(contentsOf: u, encoding: .utf8) else { throw Xrefs.XrefError.unreadable(u.path) }
        return parseCSV(text)
    }

    static func modified(_ url: URL) -> Double? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let d = a[.modificationDate] as? Date else { return nil }
        return d.timeIntervalSince1970
    }
    public static func url(_ path: String, base: URL?) -> URL { Xrefs.resolve(path, base: base) }

    /// A table geometry from CSV rows (column widths from the longest text).
    public static func table(_ rows: [[String]], origin: Vec2, textHeight: Double, rowHeight: Double? = nil) -> TableGeom {
        let cols = rows.map(\.count).max() ?? 0
        var widths = [Double](repeating: textHeight * 4, count: cols)
        for r in rows { for (j, c) in r.enumerated() { widths[j] = max(widths[j], Double(c.count) * textHeight * 0.75 + textHeight * 2) } }
        return TableGeom(origin: origin, columnWidths: widths, rowHeight: rowHeight ?? textHeight * 2.2, cells: rows, textHeight: textHeight)
    }

    /// Reloads the cells of a linked table from its file, keeping column widths where the column count is unchanged.
    public static func update(_ e: inout Entity, base: URL?) throws -> Bool {
        guard case .table(var t) = e.geometry, let p = e.props[prop] else { return false }
        let u = url(p, base: base)
        let rows = try self.rows(at: u, sheet: e.props[sheetProp])
        let cols = rows.map(\.count).max() ?? 0
        if cols != t.columnWidths.count { t.columnWidths = table(rows, origin: t.origin, textHeight: t.textHeight).columnWidths }
        let changed = t.cells != rows
        t.cells = rows
        e.geometry = .table(t)
        e.props[modifiedProp] = modified(u).map { fmt($0, 3) }
        return changed
    }
    /// Linked tables whose file changed since the last update.
    public static func stale(_ doc: ArchiDocument, base: URL?) -> [EntityID] {
        doc.entities.filter { e in
            guard let p = e.props[prop], let m = modified(url(p, base: base)) else { return false }
            return m > (e.props[modifiedProp].flatMap(Double.init) ?? 0) + 1e-3
        }.map(\.id)
    }
    /// Writes table cells back to the linked file (CSV).
    public static func writeBack(_ e: Entity, base: URL?) throws {
        guard case .table(let t) = e.geometry, let p = e.props[prop] else { return }
        let u = url(p, base: base)
        if isSpreadsheet(u.path) {
            // Replace the linked sheet, keep the workbook's other sheets.
            var sheets = (try? Data(contentsOf: u)).flatMap { try? XLSX.read($0) } ?? []
            let name = e.props[sheetProp] ?? sheets.first?.name ?? "Sheet1"
            if let i = sheets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { sheets[i].rows = t.cells }
            else { sheets.append(XLSX.Sheet(name: name, rows: t.cells)) }
            do { try XLSX.write(sheets).write(to: u) } catch { throw Xrefs.XrefError.unreadable(u.path) }
            return
        }
        do { try TableFormulas.csv(t).write(to: u, atomically: true, encoding: .utf8) } catch { throw Xrefs.XrefError.unreadable(u.path) }
    }
}

// MARK: - Spell checking support

/// Words of the drawing's annotation for spell checking (the app checks them with the system spell checker).
public enum SpellCheck {
    public struct Word: Hashable { public var entity: EntityID; public var word: String; public var field: String }
    /// Words the user added to the drawing dictionary (variable SPELLDICT, "|" separated).
    public static func customWords(_ doc: ArchiDocument) -> Set<String> {
        Set((doc.variable("SPELLDICT") ?? "").split(separator: "|").map { $0.lowercased() })
    }
    public static func addWord(_ w: String, _ doc: inout ArchiDocument) {
        var s = customWords(doc); s.insert(w.lowercased())
        doc.setVariable("SPELLDICT", s.sorted().joined(separator: "|"))
    }
    /// Removes MTEXT-style formatting codes (\P, \f..;, {…}) and field markers so only readable text remains.
    public static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\P", with: " ")
        t = t.replacingOccurrences(of: #"\\[A-Za-z][^;\\{} ]*;"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"%<[^>]*>%"#, with: " ", options: .regularExpression)
        return t.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }
    /// Splits text into words (letters with inner apostrophes/hyphens; numbers and codes are skipped).
    public static func words(in text: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(plain(text))
        for (i, c) in chars.enumerated() {
            if c.isLetter { cur.append(c); continue }
            if (c == "'" || c == "’" || c == "-"), !cur.isEmpty, i + 1 < chars.count, chars[i + 1].isLetter { cur.append(c); continue }
            if c.isNumber, !cur.isEmpty { cur = "\u{0}"; continue }
            if !cur.isEmpty { if !cur.contains("\u{0}") && cur.count > 1 { out.append(cur) }; cur = "" }
        }
        if !cur.isEmpty && !cur.contains("\u{0}") && cur.count > 1 { out.append(cur) }
        return out
    }
    /// Every word of text, leaders, tables, dimension text overrides and block attributes (optionally only some objects).
    public static func words(_ doc: ArchiDocument, ids: Set<EntityID>? = nil) -> [Word] {
        var out: [Word] = []
        for e in doc.entities where ids?.contains(e.id) ?? true {
            var texts: [(String, String)] = []
            switch e.geometry {
            case .text(let t): texts = [("text", t.content)]
            case .leader(let l): texts = [("text", l.text)]
            case .dimension(let d): if let o = d.textOverride { texts = [("override", o)] }
            case .table(let t): for (r, row) in t.cells.enumerated() { for (c, v) in row.enumerated() where !v.hasPrefix("=") { texts.append((TableFormulas.cellName(row: r, col: c), v)) } }
            case .insert(let i): texts = i.attributes.sorted { $0.key < $1.key }.map { ("attribute " + $0.key, $0.value) }
            default: break
            }
            for (f, s) in texts { for w in words(in: s) { out.append(Word(entity: e.id, word: w, field: f)) } }
        }
        return out
    }
    /// Words not accepted by `isCorrect` nor in the drawing dictionary (all-capital abbreviations are skipped like AutoCAD).
    public static func misspelled(_ doc: ArchiDocument, ids: Set<EntityID>? = nil, isCorrect: (String) -> Bool) -> [Word] {
        let custom = customWords(doc)
        return words(doc, ids: ids).filter { w in
            !(w.word.count > 1 && w.word == w.word.uppercased()) && !custom.contains(w.word.lowercased()) && !isCorrect(w.word)
        }
    }
    /// Replaces a whole word in one object's text (all occurrences). Returns true when something changed.
    @discardableResult
    public static func replace(_ word: String, with new: String, in id: EntityID, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.entityIndex(id) else { return false }
        let pat = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}])"
        func r(_ s: String) -> String { s.replacingOccurrences(of: pat, with: NSRegularExpression.escapedTemplate(for: new), options: .regularExpression) }
        let before = doc.entities[i].geometry
        switch before {
        case .text(var t): t.content = r(t.content); doc.entities[i].geometry = .text(t)
        case .leader(var l): l.text = r(l.text); doc.entities[i].geometry = .leader(l)
        case .dimension(var d): d.textOverride = d.textOverride.map(r); doc.entities[i].geometry = .dimension(d)
        case .table(var t): t.cells = t.cells.map { $0.map { $0.hasPrefix("=") ? $0 : r($0) } }; doc.entities[i].geometry = .table(t)
        case .insert(var ins): ins.attributes = ins.attributes.mapValues(r); doc.entities[i].geometry = .insert(ins)
        default: return false
        }
        return doc.entities[i].geometry != before
    }
    /// Spell checker installed by the app (NSSpellChecker); nil in headless use.
    nonisolated(unsafe) public static var checker: ((String) -> Bool)?
    /// Suggestions provider installed by the app.
    nonisolated(unsafe) public static var suggester: ((String) -> [String])?
}
