// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Table styles (TABLESTYLE, ANN-058): title / header / data cell styles — text height factor, alignment, text colour and
/// fill — and whether the table starts with a title row (merged across all columns) and a header row.
/// Stored in document variables "TABLESTYLE:<name>" as "key=value;…"; tables refer to one with the prop "tablestyle";
/// CTABLESTYLE is the style of new tables.
public struct TableStyle: Hashable {
    public struct Cell: Hashable {
        /// Text height relative to the table's text height.
        public var height: Double
        public var align: HAlign
        public var color: String?
        public var fill: String?
        public init(height: Double = 1, align: HAlign = .left, color: String? = nil, fill: String? = nil) {
            self.height = height; self.align = align; self.color = color; self.fill = fill
        }
    }
    public var name: String
    public var title: Cell
    public var header: Cell
    public var data: Cell
    public var hasTitle: Bool
    public var hasHeader: Bool
    public init(name: String, title: Cell = Cell(height: 1.4, align: .center), header: Cell = Cell(height: 1.1, align: .center),
                data: Cell = Cell(), hasTitle: Bool = true, hasHeader: Bool = true) {
        self.name = name; self.title = title; self.header = header; self.data = data; self.hasTitle = hasTitle; self.hasHeader = hasHeader
    }
    public static let standard = TableStyle(name: "Standard")
    public static let prop = "tablestyle"

    public enum Role: String, CaseIterable { case title, header, data }
    public func cell(_ r: Role) -> Cell { r == .title ? title : r == .header ? header : data }
    public mutating func setCell(_ r: Role, _ c: Cell) { switch r { case .title: title = c; case .header: header = c; case .data: data = c } }
    /// Role of row `i` of a table.
    public func role(row i: Int) -> Role {
        var k = i
        if hasTitle { if k == 0 { return .title }; k -= 1 }
        if hasHeader && k == 0 { return .header }
        return .data
    }

    // MARK: Storage
    public var text: String {
        var parts = ["title=\(hasTitle ? 1 : 0)", "header=\(hasHeader ? 1 : 0)"]
        for r in Role.allCases {
            let c = cell(r)
            parts.append("\(r.rawValue).height=\(fmt(c.height, 6))")
            parts.append("\(r.rawValue).align=\(c.align.rawValue)")
            if let v = c.color { parts.append("\(r.rawValue).color=\(v)") }
            if let v = c.fill { parts.append("\(r.rawValue).fill=\(v)") }
        }
        return parts.joined(separator: ";")
    }
    public init?(name: String, text: String) {
        self.init(name: name)
        var kv: [String: String] = [:]
        for p in text.split(separator: ";") {
            guard let eq = p.firstIndex(of: "=") else { continue }
            kv[String(p[..<eq]).lowercased()] = String(p[p.index(after: eq)...])
        }
        guard !kv.isEmpty else { return nil }
        hasTitle = kv["title"].map { $0 != "0" } ?? hasTitle
        hasHeader = kv["header"].map { $0 != "0" } ?? hasHeader
        for r in Role.allCases {
            var c = cell(r)
            if let h = kv["\(r.rawValue).height"].flatMap(Double.init), h > 0 { c.height = h }
            if let a = kv["\(r.rawValue).align"].flatMap(HAlign.init(rawValue:)) { c.align = a }
            c.color = kv["\(r.rawValue).color"] ?? c.color
            c.fill = kv["\(r.rawValue).fill"] ?? c.fill
            setCell(r, c)
        }
    }

    public static func key(_ n: String) -> String { "TABLESTYLE:" + n.uppercased() }
    public static func names(_ doc: ArchiDocument) -> [String] {
        var out = ["Standard"]
        for k in doc.variables.keys.sorted() where k.hasPrefix("TABLESTYLE:") {
            let n = doc.variable("TABLESTYLENAME:" + k.dropFirst(11)) ?? String(k.dropFirst(11))
            if n.caseInsensitiveCompare("Standard") != .orderedSame { out.append(n) }
        }
        return out
    }
    public static func named(_ n: String, _ doc: ArchiDocument) -> TableStyle? {
        if let t = doc.variable(key(n)) {
            let disp = doc.variable("TABLESTYLENAME:" + n.uppercased()) ?? n
            return TableStyle(name: disp, text: t)
        }
        return n.caseInsensitiveCompare("Standard") == .orderedSame ? .standard : nil
    }
    public func save(_ doc: inout ArchiDocument) {
        doc.setVariable(TableStyle.key(name), text)
        doc.setVariable("TABLESTYLENAME:" + name.uppercased(), name)
    }
    public static func delete(_ n: String, _ doc: inout ArchiDocument) {
        doc.variables[key(n)] = nil; doc.variables["TABLESTYLENAME:" + n.uppercased()] = nil
    }
    /// Style of a table entity (nil = the classic unstyled table).
    public static func of(_ e: Entity, _ doc: ArchiDocument) -> TableStyle? { e.props[prop].flatMap { named($0, doc) } }
    /// Title row merge for a styled table with a title row.
    public func titleMerge(columns: Int) -> DraftRendering.Merge? {
        hasTitle && columns > 1 ? DraftRendering.Merge(row: 0, col: 0, rowSpan: 1, colSpan: columns) : nil
    }
}
