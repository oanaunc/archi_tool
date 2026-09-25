// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Sheet data (numbering, order, revisions, index, view titles)

/// One revision of a sheet, stored in the layout's title block as "rev.N" = "code|date|description|by"
/// (plain [String: String] data, so older files read it and older versions ignore it).
struct SheetRevision: Hashable {
    var code: String
    var date: String
    var description: String
    var by: String
    var stored: String { [code, date, description, by].map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: "|") }
    init(code: String, date: String, description: String, by: String) { self.code = code; self.date = date; self.description = description; self.by = by }
    init?(stored: String) {
        let p = stored.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 1, !p[0].isEmpty else { return nil }
        code = p[0]; date = p.count > 1 ? p[1] : ""; description = p.count > 2 ? p[2] : ""; by = p.count > 3 ? p[3] : ""
    }
}

/// Sheet-set operations on a document. Every function is a pure document edit (callers wrap them in one undo step).
enum SheetSet {
    static let revisionPrefix = "rev."

    /// The sheet number shown in the title block ("A-101" for the first sheet unless set).
    static func number(_ doc: ArchiDocument, _ i: Int) -> String {
        guard doc.layouts.indices.contains(i) else { return "" }
        let tb = doc.layouts[i].titleBlock
        return tb["sheetNumber"] ?? tb["Sheet"] ?? String(format: "A-%03d", i + 101)
    }
    static func title(_ doc: ArchiDocument, _ i: Int) -> String {
        guard doc.layouts.indices.contains(i) else { return "" }
        return doc.layouts[i].titleBlock["sheetName"] ?? doc.layouts[i].name
    }

    /// Numbers all sheets in order: prefix + start, start+step… zero padded to `digits`.
    static func renumber(_ doc: inout ArchiDocument, prefix: String, start: Int, step: Int = 1, digits: Int = 3) {
        for i in doc.layouts.indices {
            let n = start + i * max(step, 1)
            let s = digits > 0 ? String(format: "%0\(digits)d", n) : "\(n)"
            doc.layouts[i].titleBlock["sheetNumber"] = prefix + s
            doc.layouts[i].titleBlock["Sheet"] = nil
        }
    }

    /// Moves a sheet in the set (the order of PUBLISH and of the sheet index).
    static func move(_ doc: inout ArchiDocument, from: Int, to: Int) {
        guard doc.layouts.indices.contains(from) else { return }
        let t = max(0, min(to, doc.layouts.count - 1))
        guard t != from else { return }
        let l = doc.layouts.remove(at: from)
        doc.layouts.insert(l, at: t)
    }

    /// Duplicates a sheet with its viewports and annotations (a unique name, fresh entity IDs, no revisions).
    @discardableResult
    static func duplicate(_ doc: inout ArchiDocument, _ i: Int) -> Int? {
        guard doc.layouts.indices.contains(i) else { return nil }
        var l = doc.layouts[i]
        var k = 2
        while doc.layouts.contains(where: { $0.name == "\(l.name) (\(k))" }) { k += 1 }
        l.name = "\(l.name) (\(k))"
        for key in l.titleBlock.keys where key.hasPrefix(revisionPrefix) || key == "sheetNumber" || key == "revision" { l.titleBlock[key] = nil }
        for j in l.entities.indices { l.entities[j].id = doc.allocateID() }
        doc.layouts.insert(l, at: i + 1)
        return i + 1
    }

    static func revisions(_ layout: ArchiCore.Layout) -> [SheetRevision] {
        layout.titleBlock.compactMap { k, v -> (Int, SheetRevision)? in
            guard k.hasPrefix(revisionPrefix), let n = Int(k.dropFirst(revisionPrefix.count)), let r = SheetRevision(stored: v) else { return nil }
            return (n, r)
        }
        .sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func setRevisions(_ doc: inout ArchiDocument, _ i: Int, _ revs: [SheetRevision]) {
        guard doc.layouts.indices.contains(i) else { return }
        for k in doc.layouts[i].titleBlock.keys where k.hasPrefix(revisionPrefix) { doc.layouts[i].titleBlock[k] = nil }
        for (n, r) in revs.enumerated() { doc.layouts[i].titleBlock["\(revisionPrefix)\(n + 1)"] = r.stored }
        doc.layouts[i].titleBlock["revision"] = revs.last?.code
    }

    /// Next revision code after the last one: A → B … Z → AA, 1 → 2, P01 → P02.
    static func nextCode(after last: String?) -> String {
        guard let last, !last.isEmpty else { return "A" }
        if let n = Int(last) { return "\(n + 1)" }
        // Trailing digits with a prefix (P01 → P02).
        let digits = String(last.reversed().prefix { $0.isNumber }.reversed())
        if !digits.isEmpty, let n = Int(digits) {
            return String(last.dropLast(digits.count)) + String(format: "%0\(digits.count)d", n + 1)
        }
        var chars = Array(last.uppercased())
        var i = chars.count - 1
        while i >= 0 {
            if chars[i] == "Z" { chars[i] = "A"; i -= 1 } else if let a = chars[i].asciiValue, chars[i].isLetter { chars[i] = Character(UnicodeScalar(a + 1)); return String(chars) } else { return last + "1" }
        }
        return "A" + String(chars)
    }

    static func addRevision(_ doc: inout ArchiDocument, _ i: Int, description: String, by: String, date: String = SheetComposer.dateText()) {
        guard doc.layouts.indices.contains(i) else { return }
        var revs = revisions(doc.layouts[i])
        revs.append(SheetRevision(code: nextCode(after: revs.last?.code), date: date, description: description, by: by))
        setRevisions(&doc, i, revs)
    }

    /// The sheet list table (number, title, paper, current revision).
    static func indexTable(_ doc: ArchiDocument, origin: Vec2) -> TableGeom {
        var cells: [[String]] = [["No.", "Sheet", "Paper", "Rev."]]
        for i in doc.layouts.indices {
            cells.append([number(doc, i), title(doc, i), doc.layouts[i].paper.name, revisions(doc.layouts[i]).last?.code ?? "—"])
        }
        let wTitle = max(40, min(110, Double(cells.map { $0[1].count }.max() ?? 10) * 2.1 + 6))
        return TableGeom(origin: origin, columnWidths: [22, wTitle, 22, 12], rowHeight: 6, cells: cells, textHeight: 2.5)
    }

    /// Places (or refreshes) the sheet index table on a sheet; returns false when there is no such sheet.
    @discardableResult
    static func placeIndex(_ doc: inout ArchiDocument, on i: Int) -> Bool {
        guard doc.layouts.indices.contains(i) else { return false }
        let old = doc.layouts[i].entities.first { $0.props["sheetIndex"] != nil }
        let area = SheetComposer.drawingArea(doc.layouts[i].paper)
        var origin = Vec2(area.min.x + 4, area.max.y - 4)
        if let o = old, case .table(let t) = o.geometry { origin = t.origin }
        doc.layouts[i].entities.removeAll { $0.props["sheetIndex"] != nil }
        doc.ensureLayer("A-ANNO-TTLB")
        var e = Entity(id: doc.allocateID(), layer: "A-ANNO-TTLB", color: .byLayer, geometry: .table(indexTable(doc, origin: origin)))
        e.props["sheetIndex"] = "1"
        doc.layouts[i].entities.append(e)
        return true
    }

    /// Refreshes every placed sheet index (after renumbering, renaming or reordering).
    static func refreshIndexes(_ doc: inout ArchiDocument) {
        for i in doc.layouts.indices where doc.layouts[i].entities.contains(where: { $0.props["sheetIndex"] != nil }) { placeIndex(&doc, on: i) }
    }

    /// View titles as editable paper-space entities (number bubble, title, rule, scale) under each viewport.
    /// While a sheet has them, the automatic captions are not drawn (no duplicates).
    static func refreshViewTitles(_ doc: inout ArchiDocument, _ i: Int) {
        guard doc.layouts.indices.contains(i) else { return }
        let old = Dictionary(doc.layouts[i].entities.compactMap { e -> (String, String)? in
            guard let n = e.props["viewTitle"], case .text(let t) = e.geometry, e.props["viewTitleRole"] == "title" else { return nil }
            return (n, t.content)
        }, uniquingKeysWith: { a, _ in a })
        doc.layouts[i].entities.removeAll { $0.props["viewTitle"] != nil }
        doc.ensureLayer("A-ANNO-TTLB")
        let vps = doc.layouts[i].viewports
        for (k, vp) in vps.enumerated() {
            let title = old["\(k + 1)"] ?? SheetComposer.viewTitle(vp, doc: doc)
            for (role, g) in viewTitleGeometry(vp, number: k + 1, title: title, scale: SheetComposer.ratioText(vp.scale, units: doc.units)) {
                var e = Entity(id: doc.allocateID(), layer: "A-ANNO-TTLB", color: .byLayer, geometry: g)
                e.props["viewTitle"] = "\(k + 1)"
                e.props["viewTitleRole"] = role
                doc.layouts[i].entities.append(e)
            }
        }
    }

    static func viewTitleGeometry(_ vp: Viewport, number: Int, title: String, scale: String) -> [(String, Geometry)] {
        let r = 4.5
        let c = Vec2(vp.origin.x + r, vp.origin.y - r - 2.5)
        let len = min(max(Double(title.count) * 2.5 + 8, 40), max(vp.size.x - 2 * r, 40))
        return [
            ("bubble", .circle(CircleGeom(c, r))),
            ("number", .text(TextGeom(position: c, height: 3.2, content: "\(number)", halign: .center, valign: .middle))),
            ("rule", .line(LineGeom(Vec2(c.x + r, c.y), Vec2(c.x + r + 2 + len, c.y)))),
            ("title", .text(TextGeom(position: Vec2(c.x + r + 2, c.y + 1.2), height: 3.2, content: title))),
            ("scale", .text(TextGeom(position: Vec2(c.x + r + 2, c.y - 4), height: 2.2, content: scale))),
        ]
    }

    static func hasViewTitleEntities(_ layout: ArchiCore.Layout) -> Bool { layout.entities.contains { $0.props["viewTitle"] != nil } }
}

// MARK: - Sheet set manager panel

struct SheetSetPanel: View {
    @ObservedObject var model: AppModel
    @State private var prefix = "A-"
    @State private var start = 101
    @State private var revDescription = ""
    @State private var revBy = ""
    @State private var editingName: Int?
    @State private var nameText = ""

    private var current: Int { min(max(model.activeLayout, 0), max(model.doc.layouts.count - 1, 0)) }

    var body: some View {
        let doc = model.doc
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Menu {
                    ForEach(PaperSize.standard, id: \.name) { p in Button("\(p.name) landscape") { newSheet(p) } }
                } label: { Label("New", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                Button { dup() } label: { Image(systemName: "plus.square.on.square") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(doc.layouts.isEmpty).help("Duplicate the selected sheet")
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(current == 0 || doc.layouts.isEmpty).help("Move the sheet up in the set")
                Button { move(1) } label: { Image(systemName: "arrow.down") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(current >= doc.layouts.count - 1).help("Move the sheet down in the set")
                Spacer()
                Button { remove() } label: { Image(systemName: "trash") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(doc.layouts.count < 2).help("Delete the selected sheet")
            }
            .padding(8)
            HSeparator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(doc.layouts.enumerated()), id: \.offset) { i, l in row(i, l) }
                }
            }
            .frame(minHeight: 120, maxHeight: .infinity)
            .background(Theme.panel)
            if !doc.layouts.isEmpty {
                HSeparator()
                details
            }
        }
        .background(Theme.panel)
    }

    private func row(_ i: Int, _ l: ArchiCore.Layout) -> some View {
        let sel = i == current
        return HStack(spacing: 8) {
            Text(SheetSet.number(model.doc, i)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(sel ? Theme.accentText : Theme.accent).frame(width: 58, alignment: .leading)
            if editingName == i {
                TextField("Name", text: $nameText).darkField().onSubmit { rename(i) }
            } else {
                Text(l.name).font(Theme.font).foregroundStyle(sel ? Theme.accentText : Theme.text).lineLimit(1)
            }
            Spacer()
            Text("\(l.viewports.count) vp · \(l.paper.name)").font(Theme.fontSmall).foregroundStyle(sel ? Theme.accentText : Theme.textDim)
            Text(SheetSet.revisions(l).last?.code ?? "—").font(Theme.fontSmall).foregroundStyle(sel ? Theme.accentText : Theme.textDim).frame(width: 22)
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(sel ? Theme.accent : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.activeLayout = i; model.mode = .sheet }
        .onTapGesture { model.activeLayout = i; if editingName != i { editingName = nil } }
        .contextMenu {
            Button("Open") { model.activeLayout = i; model.mode = .sheet }
            Button("Rename") { nameText = l.name; editingName = i }
            Button("Title Block…") { model.activeLayout = i; model.mode = .sheet; model.sheet = .titleBlock(i) }
            Button("Duplicate") { model.activeLayout = i; dup() }
            Divider()
            Button("Delete", role: .destructive) { model.activeLayout = i; remove() }.disabled(model.doc.layouts.count < 2)
        }
        .help("Double-click to open the sheet")
    }

    private var details: some View {
        let i = current
        let revs = SheetSet.revisions(model.doc.layouts[i])
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("NUMBERING").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.textDim)
                HStack(spacing: 4) {
                    TextField("Prefix", text: $prefix).darkField().frame(width: 50)
                    TextField("Start", value: $start, format: .number).darkField().frame(width: 56)
                    Button("Renumber All") {
                        let p = prefix, s = start
                        model.editor.transaction("Renumber Sheets") { SheetSet.renumber(&$0, prefix: p, start: s); SheetSet.refreshIndexes(&$0) }
                    }.buttonStyle(FlatButtonStyle(compact: true))
                }
                HStack(spacing: 4) {
                    Button("Sheet Index Here") { model.editor.transaction("Sheet Index") { SheetSet.placeIndex(&$0, on: i) } }
                        .buttonStyle(FlatButtonStyle(compact: true)).help("Place or refresh the sheet list table on this sheet (SHEETINDEX)")
                    Button("View Titles") { model.editor.transaction("View Titles") { SheetSet.refreshViewTitles(&$0, i) } }
                        .buttonStyle(FlatButtonStyle(compact: true)).disabled(model.doc.layouts[i].viewports.isEmpty)
                        .help("Editable view titles under every viewport (number, title, scale)")
                }
                Divider()
                Text("REVISIONS — \(model.doc.layouts[i].name)").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.textDim)
                if revs.isEmpty { Text("No revisions yet.").font(Theme.fontSmall).foregroundStyle(Theme.textFaint) }
                ForEach(Array(revs.enumerated()), id: \.offset) { k, r in
                    HStack(spacing: 6) {
                        Text(r.code).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent).frame(width: 26, alignment: .leading)
                        Text(r.date).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        Text(r.description).font(Theme.font).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Text(r.by).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        IconButton(symbol: "minus.circle", help: "Delete this revision") {
                            var list = revs; list.remove(at: k)
                            model.editor.transaction("Delete Revision") { SheetSet.setRevisions(&$0, i, list); SheetSet.refreshIndexes(&$0) }
                        }
                    }
                }
                HStack(spacing: 4) {
                    TextField("Description", text: $revDescription).darkField()
                    TextField("By", text: $revBy).darkField().frame(width: 44)
                    Button("Add") {
                        let d = revDescription.trimmingCharacters(in: .whitespaces), b = revBy.isEmpty ? model.doc.info.author : revBy
                        guard !d.isEmpty else { NSSound.beep(); return }
                        model.editor.transaction("Add Revision") { SheetSet.addRevision(&$0, i, description: d, by: b); SheetSet.refreshIndexes(&$0) }
                        revDescription = ""
                    }.buttonStyle(FlatButtonStyle(compact: true))
                }
                Text("Revisions appear in a table above the title block and set its Revision field.").font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
            }
            .padding(8)
        }
        .frame(maxHeight: 280)
    }

    private func newSheet(_ p: PaperSize) {
        model.editor.transaction("New Sheet") { d in
            var n = d.layouts.count + 1
            while d.layouts.contains(where: { $0.name == "Sheet \(n)" }) { n += 1 }
            d.layouts.append(ArchiCore.Layout(name: "Sheet \(n)", paper: p))
            SheetSet.refreshIndexes(&d)
        }
        model.activeLayout = model.doc.layouts.count - 1
    }
    private func dup() {
        let i = current
        var ni: Int?
        model.editor.transaction("Duplicate Sheet") { ni = SheetSet.duplicate(&$0, i); SheetSet.refreshIndexes(&$0) }
        if let ni { model.activeLayout = ni }
    }
    private func move(_ d: Int) {
        let i = current
        model.editor.transaction("Reorder Sheets") { SheetSet.move(&$0, from: i, to: i + d); SheetSet.refreshIndexes(&$0) }
        model.activeLayout = max(0, min(i + d, model.doc.layouts.count - 1))
    }
    private func remove() {
        let i = current
        guard model.doc.layouts.count > 1 else { return }
        model.editor.transaction("Delete Sheet") { $0.layouts.remove(at: i); SheetSet.refreshIndexes(&$0) }
        model.activeLayout = max(0, i - 1)
    }
    private func rename(_ i: Int) {
        let n = nameText.trimmingCharacters(in: .whitespaces)
        editingName = nil
        guard !n.isEmpty, model.doc.layouts.indices.contains(i), n != model.doc.layouts[i].name else { return }
        guard !model.doc.layouts.contains(where: { $0.name == n }) else { model.editor.print("A sheet named \(n) exists."); return }
        let old = model.doc.layouts[i].name
        model.editor.transaction("Rename Sheet") { d in
            d.layouts[i].name = n
            // Keep the viewport locks keyed by sheet name.
            if let v = d.variables[ViewportLock.key(old)] { d.variables[ViewportLock.key(old)] = nil; d.variables[ViewportLock.key(n)] = v }
            SheetSet.refreshIndexes(&d)
        }
    }
}
