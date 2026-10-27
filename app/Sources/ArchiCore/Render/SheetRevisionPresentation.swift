// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Revision presentation uses existing extensible sheet metadata; legacy sheets keep their appearance.
public enum SheetRevisionPresentation {
    public enum Placement: String, CaseIterable { case above = "Above", inside = "Inside", fields = "Fields" }
    private static let prefix = "presentation:Revisions:"
    public static func placement(_ layout: Layout) -> Placement { Placement(rawValue: layout.titleBlock[prefix + "placement"] ?? "") ?? .above }
    public static func width(_ layout: Layout) -> Double { number(layout, "width", 180, 40...1000) }
    public static func rowHeight(_ layout: Layout) -> Double { number(layout, "rowHeight", 5, 3...30) }
    private static func number(_ layout: Layout, _ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let v = Double(layout.titleBlock[prefix + key] ?? ""), v.isFinite, range.contains(v) else { return fallback }; return v
    }
    public static func set(_ placement: Placement, width: Double, rowHeight: Double, in layout: inout Layout) throws {
        guard width.isFinite, (40...1000).contains(width), rowHeight.isFinite, (3...30).contains(rowHeight) else { throw CommandError.invalid("Table width: 40–1000 mm; row height: 3–30 mm.") }
        layout.titleBlock[prefix + "placement"] = placement == .above ? nil : placement.rawValue
        layout.titleBlock[prefix + "width"] = width == 180 ? nil : String(width)
        layout.titleBlock[prefix + "rowHeight"] = rowHeight == 5 ? nil : String(rowHeight)
    }
    /// Automatic fields for a user's own block. Indexed rows use oldest-first revision order.
    public static func fields(_ layout: Layout) -> [String: String] {
        let revisions = EngineSheets.revisions(layout)
        let manual = layout.titleBlock["revision"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = ["revision": manual.flatMap { $0.isEmpty ? nil : $0 } ?? revisions.last?.code ?? "—",
                      "revisionCount": String(revisions.count),
                      "revisionDate": revisions.last?.date ?? "", "revisionDescription": revisions.last?.description ?? "", "revisionBy": revisions.last?.by ?? ""]
        for (i, r) in revisions.enumerated() {
            for (suffix, value) in [("code", r.code), ("date", r.date), ("description", r.description), ("by", r.by)] { values["revision.\(i + 1).\(suffix)"] = value }
        }
        return values
    }
    public static let fieldNames = ["revision", "revisionCount", "revisionDate", "revisionDescription", "revisionBy", "revision.1.code", "revision.1.date", "revision.1.description", "revision.1.by"]
    public static func makeRoomInBuiltin(_ entries: inout [DrawEntry], from start: Int, layout: Layout) {
        guard placement(layout) == .inside, SheetCustomization.visible(.revisions, in: layout), !EngineSheets.revisions(layout).isEmpty else { return }
        var offsetLayout = Layout(name: "Revision band")
        let bandHeight = Double(EngineSheets.revisions(layout).count + 1) * rowHeight(layout)
        SheetCustomization.set(.titleBlock, visible: true, offset: Vec2(0, bandHeight), in: &offsetLayout)
        SheetCustomization.finish(&entries, from: start, part: .titleBlock, layout: offsetLayout)
    }
    /// Shared by native screen/PDF/SVG and the portable engine.
    public static func entries(_ layout: Layout, titleOrigin: Vec2, titleSize: Vec2) -> [DrawEntry] {
        let revs = EngineSheets.revisions(layout)
        guard !revs.isEmpty, placement(layout) != .fields, SheetCustomization.visible(.titleBlock, in: layout) else { return [] }
        let w = width(layout), rh = rowHeight(layout)
        let origin = titleOrigin + Vec2(titleSize.x - w, placement(layout) == .inside ? 0 : titleSize.y)
        let table = EnginePlot.revisionTable(revs, x0: origin.x, x1: origin.x + w, y1: origin.y, rowHeight: rh)
        // Legacy tables follow the cartiglio; an independent offset adjusts the table within a custom drawing.
        let followingTitle = SheetCustomization.apply([table], part: .titleBlock, layout: layout)
        return SheetCustomization.apply(followingTitle, part: .revisions, layout: layout)
    }
    static var command: CommandDef {
        CommandDef("SHEETREVTABLE", aliases: ["REVSTYLE", "REVISIONSTYLE"], category: "Output", summary: "Configures revision history Above/Inside the cartiglio or Fields only. Width and row height use paper mm; SHEETSTYLE Revisions moves or hides it.") { ed in
            guard let li = FileViewCommands.currentLayoutIndex(ed) else { throw CommandError.invalid("No sheet.") }
            let l = ed.doc.layouts[li]
            let word = try await ed.getKeyword("Revision history", Placement.allCases.map(\.rawValue), defaultValue: placement(l).rawValue) ?? placement(l).rawValue
            guard let mode = Placement(rawValue: word) else { return }
            let w = try await ed.getReal("Table width (paper mm)", defaultValue: width(l)).value ?? width(l)
            let h = try await ed.getReal("Row height (paper mm)", defaultValue: rowHeight(l)).value ?? rowHeight(l)
            try set(mode, width: w, rowHeight: h, in: &ed.doc.layouts[li])
            ed.print("Revision history: \(mode.rawValue). The cartiglio's revision fields continue to update automatically.")
        }
    }
}
