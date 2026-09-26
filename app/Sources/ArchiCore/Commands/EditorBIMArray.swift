// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Rectangular / linear arrays of BIM elements (MOD-035): the source elements and their copies form one group
/// ("*BAn", selected as a unit) and the array parameters are kept in the drawing (BIMARRAY:*BAn = "rows;cols;dx;dy;ids"),
/// so ARRAYEDIT can change the count or spacing afterwards (copies are regenerated from the sources).
public struct BIMArrayParams: Hashable {
    public var rows: Int
    public var columns: Int
    public var rowSpacing: Double
    public var columnSpacing: Double
    public var sources: [EntityID]
    public init(rows: Int, columns: Int, rowSpacing: Double, columnSpacing: Double, sources: [EntityID]) {
        self.rows = rows; self.columns = columns; self.rowSpacing = rowSpacing; self.columnSpacing = columnSpacing; self.sources = sources
    }
    public var text: String { "\(rows);\(columns);\(fmt(rowSpacing, 9));\(fmt(columnSpacing, 9));" + sources.map(String.init).joined(separator: ",") }
    public init?(text: String) {
        let p = text.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 5, let r = Int(p[0]), let c = Int(p[1]), let dy = Double(p[2]), let dx = Double(p[3]) else { return nil }
        self.init(rows: r, columns: c, rowSpacing: dy, columnSpacing: dx, sources: p[4].split(separator: ",").compactMap { Int($0) })
    }
    public var count: Int { rows * columns }
}

extension Editor {
    static let bimArrayPrefix = "BIMARRAY:"

    /// Name of the BIM array an object belongs to.
    public func bimArrayName(of id: EntityID) -> String? {
        guard let g = BlockTools.group(of: id, doc), doc.variable(Editor.bimArrayPrefix + g) != nil else { return nil }
        return g
    }
    public func bimArrayParams(_ name: String) -> BIMArrayParams? { doc.variable(Editor.bimArrayPrefix + name).flatMap(BIMArrayParams.init(text:)) }
    /// Members (sources and copies) of a BIM array.
    public func bimArrayMembers(_ name: String) -> [EntityID] { BlockTools.groups(doc)[name] ?? [] }

    /// Places the copies of `p.sources` for every array cell except (0,0); returns the new ids (including openings that
    /// follow copied host walls).
    func placeBIMArrayCopies(_ p: BIMArrayParams) -> [EntityID] {
        var out: [EntityID] = []
        for r in 0..<max(p.rows, 1) { for c in 0..<max(p.columns, 1) where r > 0 || c > 0 {
            let before = Set(doc.elements.map(\.id)).union(doc.entities.map(\.id))
            _ = transformObjects(p.sources, .translation(Vec2(Double(c) * p.columnSpacing, Double(r) * p.rowSpacing)), copy: true)
            out += doc.elements.map(\.id).filter { !before.contains($0) } + doc.entities.map(\.id).filter { !before.contains($0) }
        } }
        return out
    }

    /// Creates a BIM array from the selected objects (at least one BIM element). Returns the array (group) name.
    @discardableResult
    public func createBIMArray(_ ids: [EntityID], rows: Int, columns: Int, rowSpacing: Double, columnSpacing: Double) -> String? {
        let src = ids.filter { (doc.element($0) != nil || doc.entity($0) != nil) && isSelectable($0) }
        guard !src.isEmpty, rows >= 1, columns >= 1, rows * columns > 1, rows * columns <= 10000 else { return nil }
        var j = 1
        while BlockTools.groups(doc)["*BA\(j)"] != nil || doc.variable(Editor.bimArrayPrefix + "*BA\(j)") != nil { j += 1 }
        let name = "*BA\(j)"
        let p = BIMArrayParams(rows: rows, columns: columns, rowSpacing: rowSpacing, columnSpacing: columnSpacing, sources: src)
        // Openings hosted by source walls are copied with them; they belong to the sources too.
        let copies = placeBIMArrayCopies(p)
        for id in src + copies { BlockTools.setGroup(id, name, &doc) }
        for el in doc.elements { if case .opening(let o) = el.geometry, src.contains(o.hostWall) { BlockTools.setGroup(el.id, name, &doc) } }
        doc.setVariable(Editor.bimArrayPrefix + name, p.text)
        return name
    }

    /// Changes the rows / columns / spacing of a BIM array: copies are deleted and regenerated from the sources (which keep
    /// their current position and edits). Returns the member count.
    @discardableResult
    public func updateBIMArray(_ name: String, rows: Int? = nil, columns: Int? = nil, rowSpacing: Double? = nil, columnSpacing: Double? = nil) -> Int {
        guard var p = bimArrayParams(name) else { return 0 }
        p.sources = p.sources.filter { doc.element($0) != nil || doc.entity($0) != nil }
        guard !p.sources.isEmpty else { return 0 }
        if let r = rows { p.rows = max(1, r) }
        if let c = columns { p.columns = max(1, c) }
        if let s = rowSpacing { p.rowSpacing = s }
        if let s = columnSpacing { p.columnSpacing = s }
        guard p.count <= 10000 else { return 0 }
        let keep = Set(p.sources).union(doc.elements.filter { if case .opening(let o) = $0.geometry { return p.sources.contains(o.hostWall) }; return false }.map(\.id))
        let old = Set(bimArrayMembers(name)).subtracting(keep)
        doc.remove(ids: old)
        let copies = placeBIMArrayCopies(p)
        for id in copies { BlockTools.setGroup(id, name, &doc) }
        doc.setVariable(Editor.bimArrayPrefix + name, p.text)
        return bimArrayMembers(name).count
    }

    /// Dissolves a BIM array into independent elements (the group and parameters go).
    public func explodeBIMArray(_ name: String) {
        BlockTools.dissolve(&doc, groups: [name])
        doc.variables[Editor.bimArrayPrefix + name] = nil
    }
}
