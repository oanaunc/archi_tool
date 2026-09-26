// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum BuiltinCommands {
    public static func registerAll(_ r: CommandRegistry) {
        r.register(allDefinitions)
    }

    /// Every built-in command in registration order (later entries would replace earlier ones with the same name).
    public static var allDefinitions: [CommandDef] {
        var out: [CommandDef] = []
        out += DrawCommands.all
        out += ModifyCommands.all
        out += AnnotateCommands.all
        out += ArchitectureCommands.all
        out += InquiryCommands.all
        out += SettingsCommands.all
        out += BlockCommands.all
        out += FileViewCommands.all
        out += edit
        out += SelectionCommands.all
        out += DraftingToolCommands.all
        out += AnnotationToolCommands.all
        out += BlockToolCommands.all
        out += IOCommands.all
        out += AnalysisCommands.all
        out += ConstraintCommands.all
        out += DraftConstructionCommands.all
        out += ModifyToolCommands.all
        out += WorkflowCommands.all
        out += LayerToolCommands.all
        out += DraftAnnotationCommands.all
        out += DraftAidCommands.all
        out += DraftDetailCommands.all
        out += DraftFeatureCommands.all
        out += WorkplaneCommands.all
        out += BlockEditCommands.all
        out += Round8AnnotationCommands.all
        return out
    }

    static var edit: [CommandDef] { [
        CommandDef("U", category: "Edit", summary: "Reverses the most recent action.", modifies: false) { ed in ed.undo() },
        CommandDef("UNDO", category: "Edit", summary: "Reverses actions: a count, or Mark/Back (to a mark) and BEgin/End (group several commands into one step).", modifies: false) { ed in
            let w = try await ed.getWord("Enter the number of operations to undo or [Auto/Control/BEgin/End/Mark/Back]", defaultValue: "1",
                                         keywords: ["Auto", "Control", "BEgin", "End", "Mark", "Back"]) ?? "1"
            switch w {
            case "Mark": ed.undoMarks.append(ed.history.undoStack.count); ed.print("Mark set.")
            case "Back":
                let target = ed.undoMarks.popLast() ?? 0
                if ed.undoMarks.isEmpty && target == 0 { ed.print("No mark: everything was undone.") }
                var guardN = 0
                while ed.history.undoStack.count > target && guardN < 10000 { ed.undo(); guardN += 1 }
                ed.undoMarks = ed.undoMarks.filter { $0 <= ed.history.undoStack.count }
            case "BEgin":
                if ed.undoGroupActive { ed.endUndoGroup() }
                ed.undoGroupActive = true; ed.undoGroupStart = ed.doc
                ed.print("Undo group started.")
            case "End":
                guard ed.undoGroupActive else { ed.print("No undo group is active."); return }
                ed.endUndoGroup()
            case "Auto", "Control": ed.print("Every command is always one undo step; Control is not needed.")
            default:
                guard let n = Int(w), n >= 1 else { throw CommandError.invalid("Requires a positive number or an option.") }
                for _ in 0..<min(n, 1000) { ed.undo() }
            }
        },
        CommandDef("REDO", aliases: ["MREDO"], category: "Edit", summary: "Reverses the last undo.", modifies: false) { ed in ed.redo() },
    ] }
}
