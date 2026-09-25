// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Annotation editing: text scaling/justification, DIMSPACE/DIMEDIT/DIMTEDIT, fields, annotative scale,
/// table editing with formulas, multileader styles and alignment.
enum AnnotationToolCommands {
    static var all: [CommandDef] { text + dims + fields + tables + leaders }

    static func isText(_ g: Geometry?) -> Bool { if case .text? = g { return true }; return false }

    // MARK: - Text
    static var text: [CommandDef] { [
        CommandDef("SCALETEXT", category: "Annotate", summary: "Changes the height of text objects (new height or scale factor) keeping their insertion points.") { ed in
            let ids = try await ed.getEntitySelection("Select text objects").filter { id in
                switch ed.doc.entity(id)?.geometry { case .text?, .leader?: return true; default: return false } }
            guard !ids.isEmpty else { throw CommandError.invalid("No text selected.") }
            let a = try await ed.getDistance("Specify new model height", defaultValue: ed.settings.textHeight, keywords: ["Scale"])
            var height: Double? = nil, factor: Double? = nil
            switch a {
            case .value(let h): guard h > 0 else { throw CommandError.invalid("Height must be positive.") }; height = h
            case .keyword: guard let f = try await ed.getReal("Specify scale factor", defaultValue: 2).value, f > 0 else { return }; factor = f
            case .none: return
            }
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                switch ed.doc.entities[i].geometry {
                case .text(var t): t.height = height ?? t.height * (factor ?? 1); ed.doc.entities[i].geometry = .text(t)
                case .leader(var l): l.textHeight = height ?? l.textHeight * (factor ?? 1); ed.doc.entities[i].geometry = .leader(l)
                default: break
                }
                if ed.doc.entities[i].props["annotative"] == "1" { _ = Annotative.makeAnnotative(&ed.doc.entities[i], doc: ed.doc) }
            }
            ed.selection = []
            ed.print("\(ids.count) text object(s) changed.")
        },
        CommandDef("JUSTIFYTEXT", aliases: ["TEXTALIGN"], category: "Annotate", summary: "Changes the justification of text without moving it.") { ed in
            let ids = try await ed.getEntitySelection("Select text objects").filter { isText(ed.doc.entity($0)?.geometry) }
            guard !ids.isEmpty else { throw CommandError.invalid("No text selected.") }
            let k = try await ed.getKeyword("Enter a justification option", AnnotateCommands.justifyKeywords, defaultValue: "Left") ?? "Left"
            let (ha, va) = AnnotateCommands.justification(k)
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .text(let t) = ed.doc.entities[i].geometry else { continue }
                ed.doc.entities[i].geometry = .text(rejustify(t, ha, va))
            }
            ed.selection = []
        },
        CommandDef("TXT2MTXT", aliases: ["TEXTTOMTEXT"], category: "Annotate", summary: "Combines single-line texts into one multiline text (top to bottom).") { ed in
            let ids = try await ed.getEntitySelection("Select text objects").filter { isText(ed.doc.entity($0)?.geometry) }
            let texts = ids.compactMap { id -> (EntityID, TextGeom)? in if case .text(let t)? = ed.doc.entity(id)?.geometry { return (id, t) }; return nil }
            guard !texts.isEmpty else { throw CommandError.invalid("No text selected.") }
            let merged = mergeTexts(texts.map(\.1))
            let proto = ed.doc.entity(texts[0].0)!
            ed.doc.remove(ids: Set(texts.map(\.0)))
            var e = proto; e.geometry = .text(merged); e.props["field"] = nil
            ed.doc.add(e)
            ed.selection = []
            ed.print("\(texts.count) text object(s) combined.")
        },
    ] }

    /// Same text box, new justification.
    static func rejustify(_ t: TextGeom, _ ha: HAlign, _ va: VAlign) -> TextGeom {
        let old = GeometryOps.textBoxCorners(t)
        var n = t; n.halign = ha; n.valign = va
        let moved = GeometryOps.textBoxCorners(n)
        n.position = n.position + (old[0] - moved[0])
        return n
    }

    /// Orders texts top-to-bottom (in their own rotation frame) and joins them as paragraphs.
    static func mergeTexts(_ ts: [TextGeom]) -> TextGeom {
        let rot = ts[0].rotation
        let sorted = ts.sorted { a, b in
            let ya = a.position.rotated(by: -rot).y, yb = b.position.rotated(by: -rot).y
            return abs(ya - yb) > 1e-9 ? ya > yb : a.position.rotated(by: -rot).x < b.position.rotated(by: -rot).x
        }
        let top = sorted[0]
        let corners = sorted.flatMap { GeometryOps.textBoxCorners($0) }.map { $0.rotated(by: -rot) }
        let minX = corners.map(\.x).min() ?? 0, maxX = corners.map(\.x).max() ?? 0, maxY = corners.map(\.y).max() ?? 0
        let width = maxX - minX
        return TextGeom(position: Vec2(minX, maxY).rotated(by: rot), height: top.height, content: sorted.map(\.content).joined(separator: "\n"),
                        rotation: rot, style: top.style, halign: .left, valign: .top, width: width * 1.05)
    }

    // MARK: - Dimensions
    static func isDim(_ g: Geometry?) -> Bool { if case .dimension? = g { return true }; return false }

    static var dims: [CommandDef] { [
        CommandDef("DIMSPACE", category: "Annotate", summary: "Evenly spaces parallel linear/aligned dimensions from a base dimension (0 aligns them).") { ed in
            guard case .pick(let b) = try await ed.pickObject("Select base dimension", filter: { isDim(ed.doc.entity($0)?.geometry) }),
                  case .dimension(let base)? = ed.doc.entity(b.id)?.geometry else { return }
            guard DraftGeometry.dimensionDirection(base) != nil else { throw CommandError.invalid("The base must be a linear or aligned dimension.") }
            let ids = try await ed.getEntitySelection("Select dimensions to space").filter { $0 != b.id && isDim(ed.doc.entity($0)?.geometry) }
            guard !ids.isEmpty else { return }
            let style = ed.doc.dimStyle(base.style)
            let auto = style.textHeight * style.scale * 2
            let a = try await ed.getDistance("Enter value or [Auto]", defaultValue: auto, keywords: ["Auto"])
            let spacing = a.value ?? auto
            let dims = ids.compactMap { id -> DimensionGeom? in if case .dimension(let d)? = ed.doc.entity(id)?.geometry { return d }; return nil }
            let spaced = DraftGeometry.spaceDimensions(base: base, others: dims, spacing: spacing)
            for (id, d) in zip(ids, spaced) { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].geometry = .dimension(d) } }
            ed.selection = []
        },
        CommandDef("DIMEDIT", aliases: ["DED", "DIMED"], category: "Annotate", summary: "Edits dimension text: Home (measured value), New text (<> = measurement).") { ed in
            let k = try await ed.getKeyword("Enter type of dimension editing", ["Home", "New"], defaultValue: "Home") ?? "Home"
            var newText: String? = nil
            if k == "New" {
                guard let s = try await ed.getString("Enter dimension text (<> = measured value)", defaultValue: "<>") else { return }
                newText = s == "<>" || s.isEmpty ? nil : AnnotateCommands.unescape(s)
            }
            let ids = try await ed.getEntitySelection("Select dimensions").filter { isDim(ed.doc.entity($0)?.geometry) }
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .dimension(var d) = ed.doc.entities[i].geometry else { continue }
                d.textOverride = newText
                ed.doc.entities[i].geometry = .dimension(d)
            }
            ed.selection = []
            ed.print("\(ids.count) dimension(s) edited.")
        },
        CommandDef("DIMTEDIT", aliases: ["DIMTED"], category: "Annotate", summary: "Moves the text / dimension line of a dimension to a new location.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select dimension", filter: { isDim(ed.doc.entity($0)?.geometry) }),
                  let i = ed.doc.entityIndex(pk.id), case .dimension(var d) = ed.doc.entities[i].geometry else { return }
            let slot: Int
            switch d.kind { case .angular: slot = 3; case .ordinate: slot = 1; default: slot = 2 }
            guard d.points.count > slot else { throw CommandError.invalid("That dimension cannot be edited.") }
            let proto = d
            let p = try await ed.requirePoint("Specify new location for dimension text") { c in var x = proto; x.points[slot] = c; return [.dimension(x)] }
            d.points[slot] = p
            ed.doc.entities[i].geometry = .dimension(d)
        },
    ] }

    // MARK: - Fields and annotative scale
    static var fields: [CommandDef] { [
        CommandDef("FIELD", category: "Annotate", summary: "Inserts text containing a field (area, length, property, variable, count, date) that updates automatically.") { ed in
            let k = try await ed.getKeyword("Enter field type", ["Area", "Length", "Perimeter", "Radius", "Property", "Variable", "Count", "Date", "FileName"], defaultValue: "Area") ?? "Area"
            var code: String
            switch k {
            case "Area", "Length", "Perimeter", "Radius", "Property":
                guard case .pick(let pk) = try await ed.pickObject("Select object") else { return }
                if k == "Property" {
                    guard let prop = try await ed.getWord("Enter property name", defaultValue: "layer") else { return }
                    code = "Prop(\(pk.id),\(prop))"
                } else { code = "\(k)(\(pk.id))" }
            case "Variable":
                guard let v = try await ed.getWord("Enter variable name", defaultValue: "CLAYER") else { return }
                code = "Var(\(v.uppercased()))"
            case "Count":
                let t = try await ed.getWord("Enter object type to count", defaultValue: "*") ?? "*"
                code = "Count(\(t))"
            case "Date": code = "Date(" + (try await ed.getWord("Enter date format", defaultValue: "yyyy-MM-dd") ?? "yyyy-MM-dd") + ")"
            default: code = "FileName"
            }
            if ["Area", "Length", "Perimeter", "Radius"].contains(k) {
                let def = k == "Area" ? (ed.doc.units == .millimeters ? "m2:2" : "2") : "0"
                let f = try await ed.getWord("Enter format (unit and/or decimals, e.g. m2:2, m:3, 0)", defaultValue: def) ?? def
                if !f.isEmpty { code += ":" + f }
            }
            let tpl = try await ed.getString("Enter text (# = field value)", defaultValue: "#") ?? "#"
            let template = (tpl.contains("#") ? tpl : tpl + " #").replacingOccurrences(of: "#", with: "%<\(code)>%")
            let p = try await ed.requirePoint("Specify start point of text")
            let h = try await ed.getPositive("Specify height", base: p, defaultValue: ed.settings.textHeight)
            let content = Fields.expand(template, doc: ed.doc)
            let id = ed.addEntity(.text(TextGeom(position: p, height: h, content: content)), layer: ed.annotationLayer("TEXTLAYER"))
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["field"] = template }
            ed.print("Field: \(content)")
        },
        CommandDef("UPDATEFIELD", aliases: ["UPDFIELD"], category: "Annotate", summary: "Updates fields (including date fields) in the selected text.") { ed in
            let ids = try await ed.getEntitySelection("Select objects")
            let n = ids.filter { ed.doc.entity($0)?.props["field"] != nil }.count
            Fields.updateAll(&ed.doc, ids: Set(ids), volatile: true)
            ed.selection = []
            ed.print("\(n) field object(s) found and updated.")
        },
        CommandDef("ANNOTATIVE", aliases: ["ANNO"], category: "Annotate", summary: "Makes text, leaders and tables annotative (height follows CANNOSCALE) or turns it off.") { ed in
            let k = try await ed.getKeyword("Annotative", ["Yes", "No"], defaultValue: "Yes") ?? "Yes"
            let ids = try await ed.getEntitySelection("Select annotation objects")
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                if k == "Yes" { if Annotative.makeAnnotative(&ed.doc.entities[i], doc: ed.doc) { n += 1 } }
                else if ed.doc.entities[i].props.removeValue(forKey: "annotative") != nil { ed.doc.entities[i].props["paperHeight"] = nil; n += 1 }
            }
            ed.selection = []
            ed.print("\(n) object(s) changed. Annotation scale: \(ed.doc.variable("CANNOSCALE") ?? "1:1")")
        },
        CommandDef("SCALELISTEDIT", aliases: ["SCALELIST"], category: "Annotate", summary: "Edits the list of annotation scales (Add/Delete/Reset/List).") { ed in
            var list = Annotative.scaleList(ed.doc)
            let k = try await ed.getKeyword("Enter option", ["Add", "Delete", "Reset", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "Add":
                guard let s = try await ed.getWord("Enter scale (e.g. 1:75)"), Annotative.factor(s) != nil else { throw CommandError.invalid("Invalid scale.") }
                if !list.contains(s) { list.append(s) }
                list.sort { (Annotative.factor($0) ?? 0) < (Annotative.factor($1) ?? 0) }
                ed.doc.setVariable("SCALELIST", list.joined(separator: ";"))
            case "Delete":
                guard let s = try await ed.getWord("Enter scale to delete"), let i = list.firstIndex(of: s) else { throw CommandError.invalid("Scale not in list.") }
                guard s != ed.doc.variable("CANNOSCALE") else { throw CommandError.invalid("Cannot delete the current annotation scale.") }
                list.remove(at: i)
                ed.doc.setVariable("SCALELIST", list.joined(separator: ";"))
            case "Reset": ed.doc.variables.removeValue(forKey: "SCALELIST")
            default: ed.print("Scales: " + list.joined(separator: ", "))
            }
        },
    ] }

    // MARK: - Tables
    static func isTable(_ g: Geometry?) -> Bool { if case .table? = g { return true }; return false }

    static var tables: [CommandDef] { [
        CommandDef("TABLEEDIT", aliases: ["TABEDIT", "TABLEDIT"], category: "Annotate", summary: "Edits a table: cell text or =formula (SUM, AVERAGE…), insert/delete rows and columns, column widths.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select table", filter: { isTable(ed.doc.entity($0)?.geometry) }), let idx = ed.doc.entityIndex(pk.id) else { return }
            while true {
                guard let i = ed.doc.entityIndex(pk.id), case .table(var t) = ed.doc.entities[i].geometry else { return }
                _ = idx
                var e = ed.doc.entities[i]
                var f = TableFormulas.formulas(e)
                let k = try await ed.getKeyword("Enter an option", ["Cell", "InsertRow", "DeleteRow", "InsertColumn", "DeleteColumn", "Width", "eXit"], defaultValue: "eXit") ?? "eXit"
                switch k {
                case "Cell":
                    guard let ref = try await ed.getWord("Enter cell (e.g. B2)"), let (r, c) = TableFormulas.cellIndex(ref), r < t.cells.count, c < t.columnWidths.count else { ed.print("Invalid cell."); continue }
                    while t.cells[r].count < t.columnWidths.count { t.cells[r].append("") }
                    let key = TableFormulas.cellName(row: r, col: c)
                    let cur = f[key].map { "=" + $0 } ?? t.cells[r][c]
                    guard let v = try await ed.getString("Enter cell text or =formula", defaultValue: cur) else { continue }
                    if v.hasPrefix("=") {
                        guard TableFormulas.evaluate(v, cells: t.cells) != nil else { ed.print("Invalid formula \(v)."); continue }
                        f[key] = String(v.dropFirst())
                    } else { f[key] = nil; t.cells[r][c] = v }
                case "InsertRow", "DeleteRow":
                    guard let n = try await ed.getInteger(k == "InsertRow" ? "Insert before row number (\(t.cells.count + 1) = at end)" : "Row number to delete", defaultValue: t.cells.count), n >= 1 else { continue }
                    if k == "InsertRow" {
                        guard n <= t.cells.count + 1 else { ed.print("Invalid row."); continue }
                        t.cells.insert(Array(repeating: "", count: t.columnWidths.count), at: n - 1)
                        f = TableFormulas.shifted(f, row: n - 1, rowDelta: 1)
                    } else {
                        guard n <= t.cells.count, t.cells.count > 1 else { ed.print("Invalid row."); continue }
                        t.cells.remove(at: n - 1)
                        f = TableFormulas.shifted(f, row: n - 1, rowDelta: -1)
                    }
                case "InsertColumn", "DeleteColumn":
                    guard let n = try await ed.getInteger(k == "InsertColumn" ? "Insert before column number (\(t.columnWidths.count + 1) = at end)" : "Column number to delete", defaultValue: t.columnWidths.count), n >= 1 else { continue }
                    if k == "InsertColumn" {
                        guard n <= t.columnWidths.count + 1 else { ed.print("Invalid column."); continue }
                        t.columnWidths.insert(t.columnWidths[min(n - 1, t.columnWidths.count - 1)], at: n - 1)
                        for r in t.cells.indices { while t.cells[r].count < t.columnWidths.count - 1 { t.cells[r].append("") }; t.cells[r].insert("", at: n - 1) }
                        f = TableFormulas.shifted(f, col: n - 1, colDelta: 1)
                    } else {
                        guard n <= t.columnWidths.count, t.columnWidths.count > 1 else { ed.print("Invalid column."); continue }
                        t.columnWidths.remove(at: n - 1)
                        for r in t.cells.indices where n - 1 < t.cells[r].count { t.cells[r].remove(at: n - 1) }
                        f = TableFormulas.shifted(f, col: n - 1, colDelta: -1)
                    }
                case "Width":
                    guard let n = try await ed.getInteger("Column number", defaultValue: 1), n >= 1, n <= t.columnWidths.count else { ed.print("Invalid column."); continue }
                    t.columnWidths[n - 1] = try await ed.getPositive("Specify column width", defaultValue: t.columnWidths[n - 1])
                default: return
                }
                e.geometry = .table(t)
                TableFormulas.setFormulas(&e, f)
                ed.doc.entities[i] = e
                TableFormulas.updateAll(&ed.doc)
            }
        },
        CommandDef("TABLEEXPORT", aliases: ["TABLEEXP"], category: "Annotate", summary: "Exports a table to a CSV file.", modifies: false) { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select table", filter: { isTable(ed.doc.entity($0)?.geometry) }), case .table(let t)? = ed.doc.entity(pk.id)?.geometry else { return }
            guard let p = try await ed.getWord("Enter CSV file path") else { return }
            var path = (p as NSString).expandingTildeInPath
            if (path as NSString).pathExtension.isEmpty { path += ".csv" }
            do { try TableFormulas.csv(t).write(toFile: path, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(path).") }
            ed.print("Table exported to \(path).")
        },
    ] }

    // MARK: - Multileader styles
    struct MLeaderStyle: Equatable {
        var name: String
        var textHeight: Double
        var annotative: Bool
        var layer: String
        var text: String { "height=\(fmt(textHeight, 8));annotative=\(annotative ? 1 : 0);layer=\(layer)" }
        init(name: String, textHeight: Double, annotative: Bool = false, layer: String = "") { self.name = name; self.textHeight = textHeight; self.annotative = annotative; self.layer = layer }
        init?(name: String, text: String) {
            var h = 0.0, a = false, l = ""
            for kv in text.split(separator: ";") {
                let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
                guard p.count == 2 else { continue }
                switch p[0] { case "height": h = Double(p[1]) ?? 0; case "annotative": a = p[1] == "1"; case "layer": l = p[1]; default: break }
            }
            guard h > 0 else { return nil }
            self.init(name: name, textHeight: h, annotative: a, layer: l)
        }
    }
    @MainActor static func currentMLeaderStyle(_ ed: Editor) -> MLeaderStyle? {
        guard let n = ed.doc.variable("CMLEADERSTYLE"), let t = ed.doc.variable("MLSTYLE:" + n) else { return nil }
        return MLeaderStyle(name: n, text: t)
    }

    static var leaders: [CommandDef] { [
        CommandDef("MLEADERSTYLE", aliases: ["MLS"], category: "Annotate", summary: "Creates, edits, lists and sets multileader styles (text height, annotative, layer).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Set", "New", "Edit", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "Set":
                guard let n = try await ed.getWord("Enter multileader style name") else { return }
                guard ed.doc.variable("MLSTYLE:" + n) != nil || n.lowercased() == "standard" else { throw CommandError.invalid("Style \(n) not found.") }
                if n.lowercased() == "standard" { ed.doc.variables.removeValue(forKey: "CMLEADERSTYLE") } else { ed.doc.setVariable("CMLEADERSTYLE", n.uppercased()) }
            case "New", "Edit":
                let n: String
                if k == "Edit" { n = ed.doc.variable("CMLEADERSTYLE") ?? "" ; guard !n.isEmpty else { throw CommandError.invalid("The Standard style uses TEXTSIZE; create a style with New.") } }
                else { guard let w = try await ed.getWord("Enter new style name"), UserAliases.isValidName(w.uppercased()) else { throw CommandError.invalid("Invalid name.") }; n = w.uppercased() }
                let cur = ed.doc.variable("MLSTYLE:" + n).flatMap { MLeaderStyle(name: n, text: $0) } ?? MLeaderStyle(name: n, textHeight: ed.settings.textHeight)
                let h = try await ed.getPositive("Text height", defaultValue: cur.textHeight)
                let a = try await ed.getYesNo("Annotative?", defaultValue: cur.annotative)
                let l = try await ed.getWord("Layer (. = current)", defaultValue: cur.layer.isEmpty ? "." : cur.layer) ?? "."
                let s = MLeaderStyle(name: n, textHeight: h, annotative: a, layer: l == "." ? "" : l)
                ed.doc.setVariable("MLSTYLE:" + n, s.text)
                ed.doc.setVariable("CMLEADERSTYLE", n)
                ed.print("Multileader style \(n) is current.")
            default:
                let cur = ed.doc.variable("CMLEADERSTYLE")
                ed.print("\(cur == nil ? "*" : " ") Standard (TEXTSIZE)")
                for key in ed.doc.variables.keys.filter({ $0.hasPrefix("MLSTYLE:") }).sorted() {
                    let n = String(key.dropFirst(8))
                    ed.print("\(cur == n ? "*" : " ") \(n): \(ed.doc.variables[key] ?? "")")
                }
            }
        },
        CommandDef("MLEADERALIGN", aliases: ["MLA"], category: "Annotate", summary: "Aligns the landings (text) of leaders with a reference leader, vertically or horizontally.") { ed in
            let isLeader: @MainActor (EntityID) -> Bool = { id in if case .leader? = ed.doc.entity(id)?.geometry { return true }; return false }
            let ids = try await ed.getEntitySelection("Select multileaders").filter(isLeader)
            guard ids.count >= 2 else { throw CommandError.invalid("Select at least two leaders.") }
            guard case .pick(let r) = try await ed.pickObject("Select multileader to align to", filter: isLeader), case .leader(let ref)? = ed.doc.entity(r.id)?.geometry, let land = ref.points.last else { return }
            let k = try await ed.getKeyword("Alignment", ["Vertical", "Horizontal"], defaultValue: "Vertical") ?? "Vertical"
            for id in ids where id != r.id {
                guard let i = ed.doc.entityIndex(id), case .leader(var l) = ed.doc.entities[i].geometry, l.points.count >= 2 else { continue }
                let last = l.points.count - 1
                let d = k == "Vertical" ? Vec2(land.x - l.points[last].x, 0) : Vec2(0, land.y - l.points[last].y)
                // Move the landing (and any intermediate vertex after the arrow) so the text lines up.
                for j in 1...last { l.points[j] = l.points[j] + d }
                ed.doc.entities[i].geometry = .leader(l)
            }
            ed.selection = []
        },
    ] }
}

extension TableFormulas {
    /// Shifts formula cells and the references inside formulas after inserting/deleting rows or columns.
    public static func shifted(_ f: [String: String], row: Int = Int.max, rowDelta: Int = 0, col: Int = Int.max, colDelta: Int = 0) -> [String: String] {
        func shiftRef(_ r: Int, _ c: Int) -> (Int, Int)? {
            var nr = r, nc = c
            if rowDelta != 0 && r >= row { if rowDelta < 0 && r == row { return nil }; nr += rowDelta }
            if colDelta != 0 && c >= col { if colDelta < 0 && c == col { return nil }; nc += colDelta }
            return (nr, nc)
        }
        var out: [String: String] = [:]
        for (k, v) in f {
            guard let (r, c) = cellIndex(k), let (nr, nc) = shiftRef(r, c) else { continue }
            // Rewrite references in the formula.
            var s = "", i = v.startIndex
            while i < v.endIndex {
                if v[i].isLetter {
                    var j = i
                    while j < v.endIndex, v[j].isLetter { j = v.index(after: j) }
                    var k2 = j
                    while k2 < v.endIndex, v[k2].isNumber { k2 = v.index(after: k2) }
                    let word = String(v[i..<k2])
                    if k2 > j, let (rr, cc) = cellIndex(word) {
                        if let (a, b) = shiftRef(rr, cc) { s += cellName(row: a, col: b) } else { s += "0" }
                    } else { s += word }
                    i = k2
                } else { s.append(v[i]); i = v.index(after: i) }
            }
            out[cellName(row: nr, col: nc)] = s
        }
        return out
    }
}
