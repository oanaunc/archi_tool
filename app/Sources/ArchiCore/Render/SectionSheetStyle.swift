// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Overrides only the section viewports on one sheet. Stored in the existing title-block
/// metadata dictionary, so old documents require no schema migration.
public struct SectionSheetStyle: Codable, Hashable {
    public static let key = "_sectionStyle"
    public var lines: ObjectStyle
    public var shaded: Bool
    public init(lines: ObjectStyle = ObjectStyle(), shaded: Bool = true) {
        self.lines = lines; self.shaded = shaded
    }
    public static func load(_ layout: Layout) -> SectionSheetStyle? {
        guard let raw = layout.titleBlock[key] else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(raw.utf8))
    }
    public func store(in layout: inout Layout) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(self) else { return }
        layout.titleBlock[Self.key] = String(decoding: data, as: UTF8.self)
    }
    public static func parse(_ spec: String) -> SectionSheetStyle? {
        var parts: [String] = [], shaded = true
        for part in spec.split(separator: ";") {
            let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if kv.first == "shading" {
                guard kv.count == 2, ["on", "off"].contains(kv[1]) else { return nil }
                shaded = kv[1] == "on"
            } else { parts.append(String(part)) }
        }
        guard let lines = ObjectStyles.parse(parts.joined(separator: ";")) else { return nil }
        return Self(lines: lines, shaded: shaded)
    }
    /// A temporary rendering document; project-wide graphics stay intact.
    public static func document(_ doc: ArchiDocument, layout: String?, view: ViewKind) -> ArchiDocument {
        guard view == .section, let layout, let sheet = doc.layouts.first(where: { $0.name == layout }), let style = load(sheet) else { return doc }
        var result = doc
        var all = ObjectStyles.all(doc)
        for category in ObjectStyles.categories {
            all[category] = (all[category] ?? ObjectStyle()).merged(style.lines)
        }
        ObjectStyles.setAll(all, doc: &result)
        result.setVariable("SECTIONSHADING", style.shaded ? "1" : "0")
        return result
    }
    static var command: CommandDef {
        CommandDef("SECTIONSTYLE", aliases: ["SECSTYLE", "SSTYLE"], category: "Output",
                   summary: "Section graphics on one sheet: Set line/cut weights, colour, cut fill and Shading; Reset or List. SECTIONSTYLE Set \"Sheet 1\" \"color:black;fill:0.7,0.7,0.7;cut:0.5;proj:0.25;shading:off\".") { ed in
            let option = try await ed.getKeyword("Section sheet style", ["Set", "Reset", "List"], defaultValue: "List") ?? "List"
            guard let name = try await ed.getString("Sheet name", defaultValue: ed.doc.variable("CTAB").flatMap { $0 == "Model" ? nil : $0 } ?? ed.doc.layouts.first?.name ?? ""),
                  let i = ed.doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw CommandError.invalid("Sheet not found.") }
            switch option {
            case "Set":
                guard let spec = try await ed.getString("Style (cut:0.5;proj:0.25;color:black;fill:0.7,0.7,0.7;shading:on/off)"), let style = parse(spec) else { throw CommandError.invalid("Invalid section style.") }
                style.store(in: &ed.doc.layouts[i])
                ed.print("Section style saved on \(ed.doc.layouts[i].name). Use PREVIEW before printing.")
            case "Reset": ed.doc.layouts[i].titleBlock[key] = nil
            default:
                if let style = load(ed.doc.layouts[i]) { ed.print(ObjectStyles.describe(style.lines) + ", shading " + (style.shaded ? "on" : "off")) }
                else { ed.print("Section style: project defaults.") }
            }
        }
    }
}
