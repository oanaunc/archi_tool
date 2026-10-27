// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Per-sheet text suppression leaves the drawing and other sheets intact. Uses existing extensible metadata.
public enum SheetModelText {
    private static let prefix = "presentation:HiddenText:"
    public static func isHidden(_ id: EntityID, in layout: Layout) -> Bool { layout.titleBlock[prefix + String(id)] == "1" }
    public static func set(_ doc: inout ArchiDocument, layoutIndex: Int, id: EntityID, hidden: Bool) throws {
        guard doc.layouts.indices.contains(layoutIndex), let entity = doc.entity(id), case .text = entity.geometry else {
            throw CommandError.invalid("Choose a model text object (SHEETTEXT ListModel).")
        }
        doc.layouts[layoutIndex].titleBlock[prefix + String(id)] = hidden ? "1" : nil
    }
    public static func document(_ doc: ArchiDocument, layout name: String?) -> ArchiDocument {
        guard let name, let layout = doc.layouts.first(where: { $0.name == name }), layout.titleBlock.keys.contains(where: { $0.hasPrefix(prefix) }) else { return doc }
        var result = doc
        result.entities.removeAll { entity in
            guard case .text = entity.geometry else { return false }
            return isHidden(entity.id, in: layout)
        }
        return result
    }
}
