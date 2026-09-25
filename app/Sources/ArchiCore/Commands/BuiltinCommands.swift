// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum BuiltinCommands {
    public static func registerAll(_ r: CommandRegistry) {
        r.register([
            CommandDef("LINE", aliases: ["L"], category: "Draw", summary: "Draws straight line segments.") { ed in
                var first = try await ed.requirePoint("Specify first point")
                var start = first
                var count = 0
                while true {
                    let kws = count >= 2 ? ["Close", "Undo"] : (count >= 1 ? ["Undo"] : [])
                    let s = start
                    let a = try await ed.getPoint("Specify next point", base: start, keywords: kws) { c in [.line(LineGeom(s, c))] }
                    switch a {
                    case .point(let p):
                        ed.doc.add(.line(LineGeom(start, p))); start = p; count += 1
                    case .keyword("Close"):
                        ed.doc.add(.line(LineGeom(start, first))); return
                    case .keyword("Undo"):
                        if let last = ed.doc.entities.last, case .line(let l) = last.geometry { ed.doc.entities.removeLast(); start = l.a; count -= 1 }
                        if count == 0 { first = start }
                    default: return
                    }
                }
            },
            CommandDef("UNDO", aliases: ["U"], category: "Edit", summary: "Reverses the last action.", modifies: false) { ed in ed.undo() },
            CommandDef("REDO", category: "Edit", summary: "Reverses the last undo.", modifies: false) { ed in ed.redo() },
        ])
    }
}
