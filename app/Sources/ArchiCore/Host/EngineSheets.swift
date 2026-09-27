// Oanarina Archi Tool — GPL-3.0-or-later
// Sheet-set operations for archi-engine (the Windows Sheet Set Manager and Title Block dialog): the portable twin of
// the Mac app's SheetSet (ArchiApp/SheetSetManager.swift), SheetTools custom fields and the SheetComposer helpers it
// uses (drawing area, scale ratio text, view titles, date). Same document data, so .archi files are shared.
import Foundation

public struct EngineSheetRevision: Hashable {
    public var code: String
    public var date: String
    public var description: String
    public var by: String
    public var stored: String { [code, date, description, by].map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: "|") }
    public init(code: String, date: String, description: String, by: String) { self.code = code; self.date = date; self.description = description; self.by = by }
    public init?(stored: String) {
        let p = stored.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 1, !p[0].isEmpty else { return nil }
        code = p[0]
        date = p.count > 1 ? p[1] : ""
        description = p.count > 2 ? p[2] : ""
        by = p.count > 3 ? p[3] : ""
    }
}

public enum EngineSheets {
    public static let revisionPrefix = "rev."
    public static let projectPrefix = "PROJFIELD:"
    public static let sheetPrefix = "custom:"
    static let margin = 10.0
    static let bindingMargin = 20.0
    static let bottomBand = 52.0

    static func pad(_ n: Int, _ digits: Int) -> String {
        let s = String(abs(n))
        let body = s.count >= digits ? s : String(repeating: "0", count: digits - s.count) + s
        return n < 0 ? "-" + body : body
    }

    // MARK: SheetComposer helpers

    public static func drawingArea(_ paper: PaperSize) -> BBox2 {
        BBox2(min: Vec2(bindingMargin + 4, margin + bottomBand), max: Vec2(paper.width - margin - 4, paper.height - margin - 4))
    }
    public static func ratioText(_ scale: Double, units: Units) -> String {
        let r = scale * units.mm
        if r >= 1 { return "1:" + fmt(r, 1) }
        return fmt(1 / r, 1) + ":1"
    }
    public static func viewTitle(_ vp: Viewport, doc: ArchiDocument) -> String {
        if !vp.title.isEmpty { return vp.title }
        let levelName = vp.level.flatMap { doc.level($0)?.name }
        switch vp.view {
        case .plan: return (levelName ?? "Plan") + " Plan"
        case .ceiling: return (levelName ?? "") + " Ceiling Plan"
        case .elevationNorth: return "North Elevation"
        case .elevationSouth: return "South Elevation"
        case .elevationEast: return "East Elevation"
        case .elevationWest: return "West Elevation"
        case .section: return "Section A-A"
        case .axonometric: return "Axonometric"
        case .perspective: return "Perspective"
        }
    }
    public static func dateText(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: Numbers, titles, revisions

    public static func number(_ doc: ArchiDocument, _ i: Int) -> String {
        guard doc.layouts.indices.contains(i) else { return "" }
        let tb = doc.layouts[i].titleBlock
        return tb["sheetNumber"] ?? tb["Sheet"] ?? "A-" + pad(i + 101, 3)
    }
    public static func title(_ doc: ArchiDocument, _ i: Int) -> String {
        guard doc.layouts.indices.contains(i) else { return "" }
        return doc.layouts[i].titleBlock["sheetName"] ?? doc.layouts[i].name
    }

    public static func renumber(_ doc: inout ArchiDocument, prefix: String, start: Int, step: Int = 1, digits: Int = 3) {
        for i in doc.layouts.indices {
            let n = start + i * max(step, 1)
            let s = digits > 0 ? pad(n, digits) : String(n)
            doc.layouts[i].titleBlock["sheetNumber"] = prefix + s
            doc.layouts[i].titleBlock["Sheet"] = nil
        }
    }

    public static func move(_ doc: inout ArchiDocument, from: Int, to: Int) {
        guard doc.layouts.indices.contains(from) else { return }
        let t = max(0, min(to, doc.layouts.count - 1))
        guard t != from else { return }
        let l = doc.layouts.remove(at: from)
        doc.layouts.insert(l, at: t)
    }

    @discardableResult
    public static func duplicate(_ doc: inout ArchiDocument, _ i: Int) -> Int? {
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

    public static func revisions(_ layout: Layout) -> [EngineSheetRevision] {
        var list: [(Int, EngineSheetRevision)] = []
        for (k, v) in layout.titleBlock where k.hasPrefix(revisionPrefix) {
            guard let n = Int(k.dropFirst(revisionPrefix.count)), let r = EngineSheetRevision(stored: v) else { continue }
            list.append((n, r))
        }
        list.sort { $0.0 < $1.0 }
        return list.map { $0.1 }
    }

    public static func setRevisions(_ doc: inout ArchiDocument, _ i: Int, _ revs: [EngineSheetRevision]) {
        guard doc.layouts.indices.contains(i) else { return }
        for k in doc.layouts[i].titleBlock.keys where k.hasPrefix(revisionPrefix) { doc.layouts[i].titleBlock[k] = nil }
        for (n, r) in revs.enumerated() { doc.layouts[i].titleBlock[revisionPrefix + String(n + 1)] = r.stored }
        doc.layouts[i].titleBlock["revision"] = revs.last?.code
    }

    /// Next revision code after the last one: A → B … Z → AA, 1 → 2, P01 → P02.
    public static func nextCode(after last: String?) -> String {
        guard let last, !last.isEmpty else { return "A" }
        if let n = Int(last) { return String(n + 1) }
        let digits = String(last.reversed().prefix { $0.isNumber }.reversed())
        if !digits.isEmpty, let n = Int(digits) { return String(last.dropLast(digits.count)) + pad(n + 1, digits.count) }
        var chars = Array(last.uppercased())
        var i = chars.count - 1
        while i >= 0 {
            if chars[i] == "Z" { chars[i] = "A"; i -= 1; continue }
            if let a = chars[i].asciiValue, chars[i].isLetter { chars[i] = Character(UnicodeScalar(a + 1)); return String(chars) }
            return last + "1"
        }
        return "A" + String(chars)
    }

    public static func addRevision(_ doc: inout ArchiDocument, _ i: Int, description: String, by: String, date: String = EngineSheets.dateText()) {
        guard doc.layouts.indices.contains(i) else { return }
        var revs = revisions(doc.layouts[i])
        revs.append(EngineSheetRevision(code: nextCode(after: revs.last?.code), date: date, description: description, by: by))
        setRevisions(&doc, i, revs)
    }

    // MARK: Index table and view titles

    public static func indexTable(_ doc: ArchiDocument, origin: Vec2) -> TableGeom {
        var cells: [[String]] = [["No.", "Sheet", "Paper", "Rev."]]
        var longest = 10
        for i in doc.layouts.indices {
            let t = title(doc, i)
            longest = max(longest, t.count)
            cells.append([number(doc, i), t, doc.layouts[i].paper.name, revisions(doc.layouts[i]).last?.code ?? "—"])
        }
        longest = max(longest, 5)
        let wTitle = max(40, min(110, Double(longest) * 2.1 + 6))
        return TableGeom(origin: origin, columnWidths: [22, wTitle, 22, 12], rowHeight: 6, cells: cells, textHeight: 2.5)
    }

    @discardableResult
    public static func placeIndex(_ doc: inout ArchiDocument, on i: Int) -> Bool {
        guard doc.layouts.indices.contains(i) else { return false }
        let old = doc.layouts[i].entities.first { $0.props["sheetIndex"] != nil }
        let area = drawingArea(doc.layouts[i].paper)
        var origin = Vec2(area.min.x + 4, area.max.y - 4)
        if let o = old, case .table(let t) = o.geometry { origin = t.origin }
        doc.layouts[i].entities.removeAll { $0.props["sheetIndex"] != nil }
        doc.ensureLayer("A-ANNO-TTLB")
        var e = Entity(id: doc.allocateID(), layer: "A-ANNO-TTLB", color: .byLayer, geometry: .table(indexTable(doc, origin: origin)))
        e.props["sheetIndex"] = "1"
        doc.layouts[i].entities.append(e)
        return true
    }

    public static func refreshIndexes(_ doc: inout ArchiDocument) {
        for i in doc.layouts.indices where doc.layouts[i].entities.contains(where: { $0.props["sheetIndex"] != nil }) { placeIndex(&doc, on: i) }
    }

    public static func refreshViewTitles(_ doc: inout ArchiDocument, _ i: Int) {
        guard doc.layouts.indices.contains(i) else { return }
        var old: [String: String] = [:]
        for e in doc.layouts[i].entities {
            guard let n = e.props["viewTitle"], e.props["viewTitleRole"] == "title", case .text(let t) = e.geometry else { continue }
            if old[n] == nil { old[n] = t.content }
        }
        doc.layouts[i].entities.removeAll { $0.props["viewTitle"] != nil }
        doc.ensureLayer("A-ANNO-TTLB")
        let vps = doc.layouts[i].viewports
        for (k, vp) in vps.enumerated() {
            let title = old[String(k + 1)] ?? viewTitle(vp, doc: doc)
            let scale = ratioText(vp.scale, units: doc.units)
            for (role, g) in viewTitleGeometry(vp, number: k + 1, title: title, scale: scale) {
                var e = Entity(id: doc.allocateID(), layer: "A-ANNO-TTLB", color: .byLayer, geometry: g)
                e.props["viewTitle"] = String(k + 1)
                e.props["viewTitleRole"] = role
                doc.layouts[i].entities.append(e)
            }
        }
    }

    public static func viewTitleGeometry(_ vp: Viewport, number: Int, title: String, scale: String) -> [(String, Geometry)] {
        let r = 4.5
        let c = Vec2(vp.origin.x + r, vp.origin.y - r - 2.5)
        let wanted = Double(title.count) * 2.5 + 8
        let len = min(max(wanted, 40), max(vp.size.x - 2 * r, 40))
        let bubble = Geometry.circle(CircleGeom(c, r))
        let num = Geometry.text(TextGeom(position: c, height: 3.2, content: String(number), halign: .center, valign: .middle))
        let rule = Geometry.line(LineGeom(Vec2(c.x + r, c.y), Vec2(c.x + r + 2 + len, c.y)))
        let t = Geometry.text(TextGeom(position: Vec2(c.x + r + 2, c.y + 1.2), height: 3.2, content: title))
        let s = Geometry.text(TextGeom(position: Vec2(c.x + r + 2, c.y - 4), height: 2.2, content: scale))
        return [("bubble", bubble), ("number", num), ("rule", rule), ("title", t), ("scale", s)]
    }

    public static func hasViewTitleEntities(_ layout: Layout) -> Bool { layout.entities.contains { $0.props["viewTitle"] != nil } }

    // MARK: Custom title-block fields (SheetTools)

    public static func projectFields(_ doc: ArchiDocument) -> [(String, String)] {
        var out: [(String, String)] = []
        for (k, v) in doc.variables where k.hasPrefix(projectPrefix) { out.append((String(k.dropFirst(projectPrefix.count)), v)) }
        return out.sorted { $0.0 < $1.0 }
    }
    public static func setProjectField(_ doc: inout ArchiDocument, _ label: String, _ value: String?) {
        let k = projectPrefix + label.uppercased()
        doc.variables[k] = (value?.isEmpty ?? true) ? nil : value
    }
    public static func setSheetField(_ doc: inout ArchiDocument, _ i: Int, _ label: String, _ value: String?) {
        guard doc.layouts.indices.contains(i) else { return }
        doc.layouts[i].titleBlock[sheetPrefix + label.uppercased()] = (value?.isEmpty ?? true) ? nil : value
    }

    /// The automatic value a title-block field shows when the sheet leaves it empty (TitleBlockSheet.defaultValue).
    public static func defaultValue(_ doc: ArchiDocument, _ i: Int, _ k: String) -> String {
        guard doc.layouts.indices.contains(i) else { return "" }
        let l = doc.layouts[i]
        switch k {
        case "sheetName": return l.name
        case "sheetNumber": return "A-" + pad(i + 101, 3)
        case "scale":
            let s = Array(Set(l.viewports.map { ratioText($0.scale, units: doc.units) })).sorted()
            return s.isEmpty ? "—" : (s.count == 1 ? s[0] : "As indicated")
        case "date": return dateText()
        case "revision": return "—"
        case "project": return doc.info.name
        case "client": return doc.info.client
        case "author": return doc.info.author
        case "number": return doc.info.number
        default: return ""
        }
    }

    public static let sheetKeys: [(String, String)] = [("sheetName", "Sheet title"), ("sheetNumber", "Sheet number"), ("scale", "Scale"), ("date", "Date"), ("revision", "Revision")]
    public static let projectOverrideKeys: [(String, String)] = [("project", "Project"), ("client", "Client"), ("author", "Drawn by"), ("number", "Project no.")]
}
