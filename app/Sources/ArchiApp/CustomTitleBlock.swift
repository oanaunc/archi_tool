// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// Custom title blocks (SHT-014): any block (drawn with the normal tools, edited with BEDIT) can replace the built-in
/// title block on all sheets or one sheet. Its base point sits on the lower-right corner of the drawing frame; text
/// containing {field} placeholders and attribute definitions whose tag is a field name show the sheet's values
/// (project, sheetName, sheetNumber, scale, date, revision, client, author, number, paper, address, custom fields).
enum CustomTitleBlock {
    static let variable = "TITLEBLOCKBLOCK"
    static let starterName = "TB-CUSTOM"

    static func blockName(_ doc: ArchiDocument, layout: String) -> String? {
        let n = doc.variable(variable + ":" + layout.uppercased()) ?? doc.variable(variable)
        guard let n, !n.isEmpty, doc.blocks[n] != nil else { return nil }
        return n
    }

    /// Replaces {key} placeholders (case-insensitive) with values.
    static func substitute(_ s: String, _ values: [String: String]) -> String {
        guard s.contains("{") else { return s }
        var out = "", i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{", let close = s[i...].firstIndex(of: "}") {
                let key = String(s[s.index(after: i)..<close]).lowercased()
                if let v = values[key] { out += v; i = s.index(after: close); continue }
            }
            out.append(s[i]); i = s.index(after: i)
        }
        return out
    }

    /// Paper-space entries of the custom title block of a sheet, or nil to draw the built-in one.
    @MainActor static func entries(doc: ArchiDocument, layout: ArchiCore.Layout, anchor: Vec2, values v0: [String: String]) -> [DrawEntry]? {
        guard let name = blockName(doc, layout: layout.name), let blk = doc.blocks[name] else { return nil }
        let values = Dictionary(v0.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        var tmp = ArchiDocument()
        tmp.layers = doc.layers; tmp.blocks = doc.blocks; tmp.textStyles = doc.textStyles; tmp.linetypes = doc.linetypes; tmp.units = .millimeters
        let t = Transform2D.translation(anchor - blk.basePoint)
        for e in blk.entities {
            var e2 = e
            e2.geometry = GeometryOps.transform(e.geometry, t)
            if case .text(var tg) = e2.geometry {
                if let tag = e.props["attdef"], let v = values[tag.lowercased()] { tg.content = v } else { tg.content = substitute(tg.content, values) }
                e2.geometry = .text(tg)
                e2.props["attdef"] = nil; e2.props["invisible"] = nil
            }
            _ = tmp.add(e2)
        }
        var o = DrawOptions(level: nil)
        o.forPaper = true
        return DrawListBuilder.entries(doc: tmp, options: o).map { DrawEntry(id: nil, items: $0.items) }
    }

    /// A starter block like the built-in title block, with placeholders, drawn left of and above its base point.
    static func starter() -> Block {
        func line(_ a: Vec2, _ b: Vec2) -> Entity { Entity(layer: "0", geometry: .line(LineGeom(a, b))) }
        func text(_ p: Vec2, _ h: Double, _ s: String) -> Entity { Entity(layer: "0", geometry: .text(TextGeom(position: p, height: h, content: s))) }
        let w = 180.0, h = 42.0
        var es: [Entity] = [line(Vec2(-w, 0), Vec2(0, 0)), line(Vec2(0, 0), Vec2(0, h)), line(Vec2(0, h), Vec2(-w, h)), line(Vec2(-w, h), Vec2(-w, 0)),
                            line(Vec2(-w, 28), Vec2(0, 28)), line(Vec2(-w, 14), Vec2(0, 14)), line(Vec2(-90, 0), Vec2(-90, 28))]
        es += [text(Vec2(-w + 3, 32), 5, "{project}"), text(Vec2(-w + 3, 18), 2.5, "{sheetName}"), text(Vec2(-87, 18), 2.5, "Scale {scale}"),
               text(Vec2(-w + 3, 4), 2.5, "{client}  ·  {date}"), text(Vec2(-87, 4), 4, "{sheetNumber}  rev {revision}")]
        return Block(name: starterName, basePoint: .zero, entities: es, description: "Custom title block (edit with BEDIT)")
    }

    static let fieldNames = ["project", "sheetName", "sheetNumber", "scale", "date", "revision", "client", "author", "number", "paper", "address"]
}
