// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

extension ArchitectureCommands {
    static var openingSizesCommand: CommandDef {
        CommandDef("OPENINGSIZES", aliases: ["DOORWINDOWSIZES", "QUOTAINFISSI"], category: "Annotate", summary: "Places live width × height labels on doors/windows of the current level. Configurable units and text height; Automatic labels new openings; Off disables automatic labels.") { ed in
            let action = try await ed.getKeyword("Opening sizes", ["All", "Doors", "Windows", "Automatic", "Off"], defaultValue: "All") ?? "All"
            if action == "Off" { ed.doc.setVariable("OPENINGSIZETAGS", ""); ed.print("Automatic opening size labels off; existing labels are retained."); return }
            let unit = try await ed.getKeyword("Size units", ["Drawing", "Millimetres", "Centimetres", "Metres"], defaultValue: "Centimetres") ?? "Centimetres"
            let field = ["Drawing": "size", "Millimetres": "sizemm", "Centimetres": "sizecm", "Metres": "sizem"][unit] ?? "size"
            let height = try await ed.getReal("Label text height (drawing units)", defaultValue: 180 / ed.doc.units.mm).value ?? 180 / ed.doc.units.mm
            guard height.isFinite, height > 0 else { throw CommandError.invalid("Text height must be positive and finite.") }
            if action == "Automatic" {
                ed.doc.setVariable("OPENINGSIZETAGS", field)
                ed.doc.setVariable("OPENINGSIZETAGHEIGHT", String(height))
                ed.print("New doors and windows receive live size labels in \(unit.lowercased()). Use OPENINGSIZES All for existing openings.")
                return
            }
            var count = 0
            for element in ed.doc.elements where element.level == ed.doc.currentLevel {
                guard case .opening(let opening) = element.geometry,
                      (opening.kind == .door && action != "Windows") || (opening.kind == .window && action != "Doors") else { continue }
                let existing = ed.doc.entities.firstIndex { $0.props["tagOf"] == String(element.id) && ["size", "sizemm", "sizecm", "sizem"].contains($0.props["tagField"] ?? "") }
                if let index = existing, case .text(var text) = ed.doc.entities[index].geometry {
                    text.height = height
                    text.content = Annotations.tagText(element, field: field, doc: ed.doc)
                    ed.doc.entities[index].geometry = .text(text)
                    ed.doc.entities[index].props["tagField"] = field
                } else if let id = addTag(ed, element.id, field: field), let index = ed.doc.entityIndex(id), case .text(var text) = ed.doc.entities[index].geometry {
                    text.height = height; ed.doc.entities[index].geometry = .text(text)
                }
                count += 1
            }
            ed.print("\(count) live opening size label(s) placed or updated in \(unit.lowercased()).")
        }
    }
    @MainActor static func addAutomaticSizeTag(_ ed: Editor, opening id: EntityID) {
        guard let field = ed.doc.variable("OPENINGSIZETAGS"), ["size", "sizemm", "sizecm", "sizem"].contains(field),
              let tag = addTag(ed, id, field: field), let index = ed.doc.entityIndex(tag), case .text(var text) = ed.doc.entities[index].geometry else { return }
        if let height = Double(ed.doc.variable("OPENINGSIZETAGHEIGHT") ?? ""), height.isFinite, height > 0 { text.height = height; ed.doc.entities[index].geometry = .text(text) }
    }
}
