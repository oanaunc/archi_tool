// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Live fields in custom cartigli, including text in nested imported blocks. Source blocks remain editable.
public enum TitleBlockFields {
    public static func substitute(_ text: String, values: [String: String]) -> String {
        let values = Dictionary(values.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        var out = "", i = text.startIndex
        while i < text.endIndex {
            if text[i] == "{", let close = text[i...].firstIndex(of: "}") {
                let key = String(text[text.index(after: i)..<close]).lowercased()
                if let value = values[key] { out += value; i = text.index(after: close); continue }
                if key.hasPrefix("revision.") { i = text.index(after: close); continue }
            }
            out.append(text[i]); i = text.index(after: i)
        }
        return out
    }

    public static func texts(_ doc: ArchiDocument, block: String) -> [(path: String, text: String)] {
        func visit(_ name: String, _ prefix: String, _ seen: Set<String>) -> [(path: String, text: String)] {
            guard !seen.contains(name), seen.count < 32, let b = doc.blocks[name] else { return [] }
            var result: [(path: String, text: String)] = []
            for (i, e) in b.entities.enumerated() {
                let path = prefix + String(i + 1)
                if case .text(let t) = e.geometry { result.append((path, t.content)) }
                if case .insert(let insert) = e.geometry { result += visit(insert.block, path + "/", seen.union([name])) }
            }
            return result
        }
        return visit(block, "", [])
    }

    /// A path is the one-based entity position at each block level, e.g. 3/2.
    public static func bind(_ doc: inout ArchiDocument, block: String, path: String, field: String) throws {
        guard let field = EngineSheetCommands.titleFieldNames.first(where: { $0.caseInsensitiveCompare(field) == .orderedSame }) else {
            throw CommandError.invalid("Unknown title-block field.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 32 else { throw CommandError.invalid("Invalid text path.") }
        var name = block
        for (depth, part) in parts.enumerated() {
            guard let n = Int(part), var b = doc.blocks[name], b.entities.indices.contains(n - 1) else { throw CommandError.invalid("No such cartiglio text.") }
            if depth == parts.count - 1 {
                guard case .text(var text) = b.entities[n - 1].geometry else { throw CommandError.invalid("Choose a text object.") }
                text.content = "{" + field + "}"
                b.entities[n - 1].geometry = .text(text)
                b.entities[n - 1].props["attdef"] = nil
                doc.blocks[name] = b
            } else {
                guard case .insert(let insert) = b.entities[n - 1].geometry else { throw CommandError.invalid("Invalid nested text path.") }
                name = insert.block
            }
        }
    }

    public static func entries(doc: ArchiDocument, block: String, anchor: Vec2, values: [String: String]) -> [DrawEntry]? {
        guard let original = doc.blocks[block] else { return nil }
        let lower = Dictionary(values.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        var tmp = ArchiDocument()
        tmp.layers = doc.layers; tmp.blocks = doc.blocks; tmp.textStyles = doc.textStyles
        tmp.linetypes = doc.linetypes; tmp.units = .millimeters
        // Resolve definitions before expanding inserts, so fields in nested blocks work as well.
        var visited: Set<String> = []
        func resolve(_ name: String) {
            guard visited.count < 64, visited.insert(name).inserted, var b = tmp.blocks[name] else { return }
            for i in b.entities.indices {
                if case .insert(let insert) = b.entities[i].geometry { resolve(insert.block) }
                if case .text(var text) = b.entities[i].geometry {
                    let tag = b.entities[i].props["attdef"]?.lowercased()
                    text.content = tag.flatMap { lower[$0] } ?? substitute(text.content, values: lower)
                    b.entities[i].geometry = .text(text)
                    b.entities[i].props["attdef"] = nil; b.entities[i].props["invisible"] = nil
                }
            }
            tmp.blocks[name] = b
        }
        resolve(block)
        let transform = Transform2D.translation(anchor - original.basePoint)
        for var entity in tmp.blocks[block]?.entities ?? [] {
            entity.geometry = GeometryOps.transform(entity.geometry, transform)
            _ = tmp.add(entity)
        }
        var options = DrawOptions(level: nil); options.forPaper = true
        return DrawListBuilder.entries(doc: tmp, options: options).map { DrawEntry(id: nil, items: $0.items) }
    }

    /// Shared action of TITLEBLOCKDESIGN / TBDESIGN on native and portable hosts.
    @MainActor public static func bindCommand(_ ed: Editor) async throws {
        let li = FileViewCommands.currentLayoutIndex(ed)
        let defaultName = li.flatMap { EngineCustomTitleBlock.blockName(ed.doc, layout: ed.doc.layouts[$0].name) }
        guard let name = try await ed.getWord("Cartiglio block", defaultValue: defaultName), ed.doc.blocks[name] != nil else { throw CommandError.invalid("Choose an existing cartiglio block.") }
        for item in texts(ed.doc, block: name) { ed.print("\(item.path): \(item.text)") }
        guard let path = try await ed.getWord("Text path from list (e.g. 3 or 3/2)"),
              let field = try await ed.getWord("Automatic field", defaultValue: "revision") else { return }
        try bind(&ed.doc, block: name, path: path, field: field)
        ed.print("Linked to {\(field)}. Shared block users update together.")
    }
}
