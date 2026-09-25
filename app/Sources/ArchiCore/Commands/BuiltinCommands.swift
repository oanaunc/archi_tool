// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum BuiltinCommands {
    public static func registerAll(_ r: CommandRegistry) {
        r.register(DrawCommands.all)
        r.register(ModifyCommands.all)
        r.register(AnnotateCommands.all)
        r.register(ArchitectureCommands.all)
        r.register(InquiryCommands.all)
        r.register(SettingsCommands.all)
        r.register(BlockCommands.all)
        r.register(FileViewCommands.all)
        r.register(edit)
    }

    static var edit: [CommandDef] { [
        CommandDef("U", category: "Edit", summary: "Reverses the most recent action.", modifies: false) { ed in ed.undo() },
        CommandDef("UNDO", category: "Edit", summary: "Reverses the last action (optionally several).", modifies: false) { ed in
            let n = try await ed.getInteger("Enter the number of operations to undo", defaultValue: 1) ?? 1
            for _ in 0..<max(1, min(n, 1000)) { ed.undo() }
        },
        CommandDef("REDO", aliases: ["MREDO"], category: "Edit", summary: "Reverses the last undo.", modifies: false) { ed in ed.redo() },
    ] }
}
