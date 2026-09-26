// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Block editor and in-place reference editing commands (BLK-004, BLK-005).
enum BlockEditCommands {
    static var all: [CommandDef] { [bedit, bsave, bclose, refedit, refset, refclose] }

    @MainActor static func fail(_ e: Error) -> CommandError { CommandError.invalid((e as? BlockEditing.EditError)?.description ?? "\(e)") }

    static var bedit: CommandDef {
        CommandDef("BEDIT", aliases: ["BE", "BLOCKEDITOR"], category: "Blocks", summary: "Opens a block definition in the block editor (only its objects are shown; new objects join the block). BCLOSE saves.") { ed in
            let pre = ed.selection.compactMap { id -> String? in if case .insert(let i)? = ed.doc.entity(id)?.geometry { return i.block }; return nil }.first
            guard let n = try await ed.getWord("Enter block name to edit or create", defaultValue: pre) else { return }
            guard BlockCommands.validName(n) else { throw CommandError.invalid("Invalid block name.") }
            ed.selection = []
            do {
                let c = try BlockEditing.beginBlockEdit(n, doc: &ed.doc)
                ed.print("Editing block \"\(BlockEditing.editingBlock(ed.doc) ?? n)\" (\(c) object(s)). BSAVE saves, BCLOSE closes the block editor.")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch { throw fail(error) }
        }
    }
    static var bsave: CommandDef {
        CommandDef("BSAVE", category: "Blocks", summary: "Saves the block editor content into the block definition.") { ed in
            guard let n = BlockEditing.editingBlock(ed.doc) else { throw CommandError.invalid("The block editor is not open.") }
            do { let c = try BlockEditing.saveBlockEdit(doc: &ed.doc); ed.print("Block \"\(n)\" saved (\(c) object(s)).") } catch { throw fail(error) }
        }
    }
    static var bclose: CommandDef {
        CommandDef("BCLOSE", category: "Blocks", summary: "Closes the block editor, saving or discarding the changes.") { ed in
            guard let n = BlockEditing.editingBlock(ed.doc) else { throw CommandError.invalid("The block editor is not open.") }
            let k = try await ed.getKeyword("Save changes to \(n)?", ["Save", "Discard"], defaultValue: "Save") ?? "Save"
            ed.selection = []
            do {
                let c = try BlockEditing.endBlockEdit(save: k == "Save", doc: &ed.doc)
                ed.print(k == "Save" ? "Block \"\(n)\" saved (\(c) object(s)); references updated." : "Changes to \"\(n)\" discarded.")
                ed.host?.perform(.regen, editor: ed)
            } catch { throw fail(error) }
        }
    }
    static var refedit: CommandDef {
        CommandDef("REFEDIT", aliases: ["-REFEDIT"], category: "Blocks", summary: "Edits a block reference in place; REFSET adds or removes objects, REFCLOSE saves or discards.") { ed in
            let pre = ed.selection.first { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }
            var id = pre
            if id == nil {
                guard case .pick(let pk) = try await ed.pickObject("Select reference", filter: { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }) else { return }
                id = pk.id
            }
            guard let rid = id else { return }
            ed.selection = []
            do {
                let ids = try BlockEditing.beginRefEdit(rid, doc: &ed.doc)
                ed.selection = Set(ids)
                ed.print("Editing \"\(BlockEditing.refEditingBlock(ed.doc) ?? "")\" in place (\(ids.count) object(s)). REFCLOSE saves or discards.")
            } catch { throw fail(error) }
        }
    }
    static var refset: CommandDef {
        CommandDef("REFSET", category: "Blocks", summary: "Adds drawing objects to, or removes objects from, the in-place reference working set.") { ed in
            guard BlockEditing.refEditingBlock(ed.doc) != nil else { throw CommandError.invalid("No reference is being edited.") }
            let k = try await ed.getKeyword("Transfer objects", ["Add", "Remove"], defaultValue: "Add") ?? "Add"
            let ids = try await ed.getEntitySelection("Select objects")
            if k == "Add" { ed.print("\(BlockEditing.addToWorkingSet(ids, doc: &ed.doc)) object(s) added to the working set.") }
            else {
                var n = 0
                for id in ids { if let i = ed.doc.entityIndex(id), ed.doc.entities[i].props[BlockEditing.refeditTag] != nil { ed.doc.entities[i].props[BlockEditing.refeditTag] = nil; n += 1 } }
                // Removed objects that were placed from the block must not look like new objects: keep them as drawing objects.
                ed.print("\(n) object(s) removed from the working set (they stay in the drawing).")
            }
        }
    }
    static var refclose: CommandDef {
        CommandDef("REFCLOSE", category: "Blocks", summary: "Ends in-place reference editing: Save writes the changes to the block definition, Discard restores it.") { ed in
            guard let n = BlockEditing.refEditingBlock(ed.doc) else { throw CommandError.invalid("No reference is being edited.") }
            let k = try await ed.getKeyword("Enter option", ["Save", "Discard"], defaultValue: "Save") ?? "Save"
            ed.selection = []
            do {
                let c = try BlockEditing.endRefEdit(save: k == "Save", doc: &ed.doc)
                ed.print(k == "Save" ? "Block \"\(n)\" redefined with \(c) object(s)." : "Reference changes discarded.")
            } catch { throw fail(error) }
        }
    }
}
