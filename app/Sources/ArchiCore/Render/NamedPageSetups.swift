// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Reusable page setups in the existing document variables. Paper, plot settings and section
/// graphics travel together; model geometry, viewport scales and title-block fields stay intact.
public struct NamedPageSetup: Codable, Hashable {
    public var settings: String
    public var paper: PaperSize
    public var sectionStyle: SectionSheetStyle?
    public var plotTables: [String: String]
}

public enum NamedPageSetups {
    public static let key = "NAMEDPAGESETUPS"
    public static func all(_ doc: ArchiDocument) -> [String: NamedPageSetup] {
        guard let raw = doc.variable(key) else { return [:] }
        return (try? JSONDecoder().decode([String: NamedPageSetup].self, from: Data(raw.utf8))) ?? [:]
    }
    public static func names(_ doc: ArchiDocument) -> [String] { all(doc).keys.sorted() }
    public static func find(_ name: String, doc: ArchiDocument) -> NamedPageSetup? {
        all(doc).first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    public static func capture(_ doc: ArchiDocument, layoutIndex i: Int) -> NamedPageSetup? {
        guard doc.layouts.indices.contains(i) else { return nil }
        let setup = EnginePageSetup.load(doc, layoutIndex: i)
        var tables: [String: String] = [:]
        for k in [setup.plotStyleTable.map { EnginePlotStyleTable.variablePrefix + $0.uppercased() },
                  setup.namedStyleTable.map { EngineNamedPlotStyles.tablePrefix + $0.uppercased() }].compactMap({ $0 }) {
            if let raw = doc.variable(k) { tables[k] = raw }
        }
        return NamedPageSetup(settings: setup.json.serialized, paper: doc.layouts[i].paper,
                              sectionStyle: SectionSheetStyle.load(doc.layouts[i]), plotTables: tables)
    }
    public static func save(_ preset: NamedPageSetup, name: String, doc: inout ArchiDocument) {
        var values = all(doc)
        if let old = values.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { values[old] = nil }
        values[name] = preset
        store(values, doc: &doc)
    }
    public static func delete(_ name: String, doc: inout ArchiDocument) {
        var values = all(doc)
        if let old = values.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { values[old] = nil }
        store(values, doc: &doc)
    }
    static func store(_ values: [String: NamedPageSetup], doc: inout ArchiDocument) {
        if values.isEmpty { doc.variables[key] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if let data = try? enc.encode(values) { doc.setVariable(key, String(decoding: data, as: UTF8.self)) }
    }
    @discardableResult public static func importFrom(_ source: ArchiDocument, doc: inout ArchiDocument) -> Int {
        let presets = all(source)
        for name in presets.keys.sorted() { if let preset = presets[name] { save(preset, name: name, doc: &doc) } }
        return presets.count
    }
    /// Validate every target before making any changes. Colliding imported pen tables get unique
    /// names, so applying a preset cannot change the output of an unrelated sheet.
    public static func apply(_ preset: NamedPageSetup, to indices: [Int], doc: inout ArchiDocument) throws {
        guard !indices.isEmpty, indices.allSatisfy({ doc.layouts.indices.contains($0) }),
              let json = try? EngineJSON.parse(preset.settings) else { throw CommandError.invalid("Invalid preset or sheet selection.") }
        var setup = EnginePageSetup(); try setup.apply(json)
        func importTable(_ name: String?, prefix: String) -> String? {
            guard let name, let raw = preset.plotTables[prefix + name.uppercased()] else { return name }
            var result = name, n = 2
            while let old = doc.variable(prefix + result.uppercased()), old != raw {
                result = name + " (\(n))"; n += 1
            }
            doc.setVariable(prefix + result.uppercased(), raw)
            return result
        }
        setup.plotStyleTable = importTable(setup.plotStyleTable, prefix: EnginePlotStyleTable.variablePrefix)
        setup.namedStyleTable = importTable(setup.namedStyleTable, prefix: EngineNamedPlotStyles.tablePrefix)
        for i in Set(indices).sorted() {
            setup.store(in: &doc, layoutIndex: i)
            doc.layouts[i].paper = preset.paper
            if let style = preset.sectionStyle { style.store(in: &doc.layouts[i]) }
            else { doc.layouts[i].titleBlock[SectionSheetStyle.key] = nil }
        }
    }
    @MainActor static func targets(_ text: String, doc: ArchiDocument) throws -> [Int] {
        if text.caseInsensitiveCompare("All") == .orderedSame { return Array(doc.layouts.indices) }
        let names = text.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        return try names.map { name in
            guard let i = doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw CommandError.invalid("Sheet \(name) not found.") }
            return i
        }
    }
    static var command: CommandDef {
        CommandDef("PAGEPRESET", aliases: ["PSPRESET", "NAMEDPAGESETUP"], category: "Output",
                   summary: "Named page setups: Save from a sheet, Apply to one/selected/all sheets, Import from .archi, Delete, List. Preserves paper, pens and section style; one undo step.") { ed in
            let op = try await ed.getKeyword("Named page setup", ["Save", "Apply", "Import", "Delete", "List"], defaultValue: "List") ?? "List"
            if op == "List" { ed.print("Named page setups: " + names(ed.doc).joined(separator: ", ")); return }
            if op == "Import" {
                guard let path = try await ed.getString("Source .archi file") else { return }
                let source = try DocumentIO.read(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
                ed.print("Imported \(importFrom(source, doc: &ed.doc)) named page setup(s).")
                return
            }
            guard let name = try await ed.getString("Page setup name"), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if op == "Save" {
                guard let sheet = try await ed.getString("Source sheet", defaultValue: ed.doc.variable("CTAB").flatMap { $0 == "Model" ? nil : $0 } ?? ed.doc.layouts.first?.name ?? ""),
                      let i = ed.doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(sheet) == .orderedSame }), let preset = capture(ed.doc, layoutIndex: i) else { throw CommandError.invalid("Sheet not found.") }
                save(preset, name: name, doc: &ed.doc)
                ed.print("Page setup \(name) saved.")
            } else {
                guard let preset = find(name, doc: ed.doc) else { throw CommandError.invalid("Page setup not found.") }
                if op == "Delete" { delete(name, doc: &ed.doc); return }
                guard let text = try await ed.getString("Target sheets (All or names separated by |)", defaultValue: ed.doc.layouts.first?.name ?? "") else { return }
                let selected = try targets(text, doc: ed.doc)
                try apply(preset, to: selected, doc: &ed.doc)
                ed.print("Page setup \(name) applied to \(selected.count) sheet(s).")
            }
        }
    }
}
