// Oanarina Archi Tool — GPL-3.0-or-later
// Workflow commands: object isolation (HIDEOBJECTS / ISOLATEOBJECTS / UNISOLATEOBJECTS), multileader collect,
// dynamic block visibility states (BVSTATE), action macros (ACTRECORD / ACTSTOP / ACTPLAY / ACTMANAGER) and the command history (HISTORY).
import Foundation

enum WorkflowCommands {
    static let actionPrefix = "ACTION:"

    static var all: [CommandDef] { isolation + [mleaderCollect, bvstate] + actions + [history] }

    // MARK: Isolation
    static var isolation: [CommandDef] { [
        CommandDef("HIDEOBJECTS", aliases: ["HIDEOBJ"], category: "Select", summary: "Temporarily hides the selected objects (kept with the drawing until UNISOLATEOBJECTS).") { ed in
            let ids = try await ed.getSelection("Select objects to hide")
            let n = HiddenObjects.hide(Set(ids), in: &ed.doc)
            ed.selection = []
            ed.print("\(n) object(s) hidden. Use UNISOLATEOBJECTS to show them again.")
        },
        CommandDef("ISOLATEOBJECTS", aliases: ["ISOLATEOBJ", "ISOLATE"], category: "Select", summary: "Temporarily hides every object except the selected ones (on the current level for building elements).") { ed in
            let ids = Set(try await ed.getSelection("Select objects to isolate"))
            guard !ids.isEmpty else { return }
            var keep = ids
            for el in ed.doc.elements { if case .opening(let o) = el.geometry, ids.contains(o.hostWall) { keep.insert(el.id) } }
            let others = Set(ed.doc.entities.map(\.id) + ed.doc.elements.filter { $0.level == ed.doc.currentLevel }.map(\.id)).subtracting(keep)
            let n = HiddenObjects.hide(others, in: &ed.doc)
            ed.selection = []
            ed.print("\(ids.count) object(s) isolated, \(n) hidden.")
        },
        CommandDef("UNISOLATEOBJECTS", aliases: ["UNISOLATE", "UNHIDE", "ENDISOLATION"], category: "Select", summary: "Shows all objects hidden by HIDEOBJECTS or ISOLATEOBJECTS.") { ed in
            let n = HiddenObjects.restoreAll(in: &ed.doc)
            ed.print(n == 0 ? "No objects are hidden." : "\(n) object(s) shown.")
        },
    ] }

    // MARK: Multileader collect
    static var mleaderCollect: CommandDef {
        CommandDef("MLEADERCOLLECT", aliases: ["MLC"], category: "Annotate", summary: "Collects several leaders into one: the first leader's arrow with all texts stacked (Vertical) or in a row (Horizontal) at a new landing.") { ed in
            let isLeader: @MainActor (EntityID) -> Bool = { id in if case .leader? = ed.doc.entity(id)?.geometry { return true }; return false }
            let ids = try await ed.getEntitySelection("Select multileaders").filter(isLeader)
            guard ids.count >= 2 else { throw CommandError.invalid("Select at least two leaders.") }
            // Order: by landing position (top to bottom, left to right).
            let leaders: [(EntityID, LeaderGeom)] = ids.compactMap { id in if case .leader(let l)? = ed.doc.entity(id)?.geometry { return (id, l) }; return nil }
                .sorted { a, b in
                    let pa = a.1.points.last ?? .zero, pb = b.1.points.last ?? .zero
                    return abs(pa.y - pb.y) > 1e-9 ? pa.y > pb.y : pa.x < pb.x }
            let mode = try await ed.getKeyword("Collection orientation", ["Vertical", "Horizontal"], defaultValue: "Vertical") ?? "Vertical"
            guard let first = leaders.first, let tip = first.1.points.first else { return }
            let land = try await ed.getPoint("Specify collected leader location", base: first.1.points.last).point ?? (first.1.points.last ?? tip)
            var l = first.1
            if l.points.count >= 2 { l.points[l.points.count - 1] = land } else { l.points = [tip, land] }
            let texts = leaders.map { $0.1.text }.filter { !$0.isEmpty }
            l.text = texts.joined(separator: mode == "Vertical" ? "\n" : "  ")
            guard let i = ed.doc.entityIndex(first.0) else { return }
            ed.doc.entities[i].geometry = .leader(l)
            ed.doc.entities[i].props["collected"] = "\(leaders.count)"
            ed.doc.remove(ids: Set(leaders.dropFirst().map(\.0)))
            ed.selection = []
            ed.print("\(leaders.count) leaders collected into #\(first.0).")
        }
    }

    // MARK: Block visibility states
    static var bvstate: CommandDef {
        CommandDef("BVSTATE", aliases: ["BVISIBILITY", "VISIBILITYSTATE"], category: "Blocks", summary: "Dynamic block visibility states: New, Set (on references), Hide/Show objects in a state, List, Delete, Rename.") { ed in
            let isInsert: @MainActor (EntityID) -> Bool = { id in if case .insert? = ed.doc.entity(id)?.geometry { return true }; return false }
            guard case .pick(let pk) = try await ed.pickObject("Select block reference", filter: isInsert),
                  let e = ed.doc.entity(pk.id), case .insert(let ins) = e.geometry else { return }
            let block = BlockVisibility.baseBlock(of: ins, props: e.props)
            guard ed.doc.blocks[block] != nil else { throw CommandError.invalid("Block \(block) is not defined.") }
            var states = BlockVisibility.states(block, ed.doc)
            let current = e.props["visibility"]
            ed.print("Block \(block): states \(states.isEmpty ? "(none)" : states.joined(separator: ", "))\(current.map { "; this reference shows \($0)" } ?? "").")
            let k = try await ed.getKeyword("Enter an option", ["New", "Set", "Hide", "Show", "List", "Delete", "Rename"], defaultValue: states.isEmpty ? "New" : "Set") ?? "List"
            func stateName(_ msg: String, def: String?) async throws -> String {
                guard let s = try await ed.getWord(msg, defaultValue: def), !s.isEmpty else { throw CommandError.cancelled }
                guard let m = states.first(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) else { throw CommandError.invalid("No visibility state \"\(s)\".") }
                return m
            }
            switch k {
            case "New":
                guard let n = try await ed.getWord("Enter name of new visibility state"), !n.isEmpty, !n.contains("|"), !n.contains(BlockVisibility.separator) else { throw CommandError.invalid("Invalid name.") }
                guard !states.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("\"\(n)\" already exists.") }
                if states.isEmpty && n.caseInsensitiveCompare("Default") != .orderedSame { states.append("Default") }
                states.append(n)
                BlockVisibility.setStates(block, states, &ed.doc)
                BlockVisibility.regenerate(block, &ed.doc)
                if let i = ed.doc.entityIndex(pk.id) { BlockVisibility.apply(n, toInsert: i, &ed.doc) }
                ed.print("Visibility state \(n) created (all objects visible); this reference shows it. Use Hide to hide objects in it.")
            case "Set":
                guard !states.isEmpty else { throw CommandError.invalid("The block has no visibility states.") }
                let s = try await stateName("Enter visibility state [\(states.joined(separator: "/"))]", def: current ?? states.first)
                if let i = ed.doc.entityIndex(pk.id) { BlockVisibility.apply(s, toInsert: i, &ed.doc) }
                ed.print("Reference #\(pk.id) shows \(s).")
            case "Hide", "Show":
                guard !states.isEmpty else { throw CommandError.invalid("The block has no visibility states.") }
                let s = try await stateName("Enter visibility state", def: current ?? states.first)
                guard var blk = ed.doc.blocks[block], let ref = ed.doc.entity(pk.id), case .insert(let ri) = ref.geometry else { return }
                let toBlock = (ri.transform * Transform2D.translation(-blk.basePoint)).inverted
                var changed = 0
                while let p = try await ed.getPoint("Select object in the block to \(k.lowercased()) in \(s)").point {
                    let q = toBlock.apply(p)
                    let tol = ed.pickTolerance / max(1e-9, ri.transform.scaleFactor)
                    var best: (Int, Double)?
                    for (j, be) in blk.entities.enumerated() {
                        let d = GeometryOps.distance(from: q, to: be.geometry, doc: ed.doc)
                        if d <= tol, d < (best?.1 ?? .infinity) { best = (j, d) }
                    }
                    guard let (j, _) = best else { ed.print("No block object there."); continue }
                    BlockVisibility.setHidden(&blk.entities[j], k == "Hide", in: s)
                    changed += 1
                }
                ed.doc.blocks[block] = blk
                BlockVisibility.regenerate(block, &ed.doc)
                ed.print("\(changed) object(s) \(k == "Hide" ? "hidden" : "shown") in \(s).")
            case "Delete":
                let s = try await stateName("Enter visibility state to delete", def: nil)
                states.removeAll { $0 == s }
                if states.count == 1 && states[0] == "Default" { states = [] }
                if var blk = ed.doc.blocks[block] { for j in blk.entities.indices { BlockVisibility.setHidden(&blk.entities[j], false, in: s) }; ed.doc.blocks[block] = blk }
                BlockVisibility.setStates(block, states, &ed.doc)
                BlockVisibility.regenerate(block, &ed.doc)
                ed.print("Visibility state \(s) deleted.")
            case "Rename":
                let s = try await stateName("Enter visibility state to rename", def: current)
                guard let n = try await ed.getWord("Enter new name"), !n.isEmpty, !n.contains("|"), !n.contains(BlockVisibility.separator),
                      !states.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Invalid or duplicate name.") }
                states = states.map { $0 == s ? n : $0 }
                if var blk = ed.doc.blocks[block] {
                    for j in blk.entities.indices where BlockVisibility.isHidden(blk.entities[j], in: s) { BlockVisibility.setHidden(&blk.entities[j], false, in: s); BlockVisibility.setHidden(&blk.entities[j], true, in: n) }
                    ed.doc.blocks[block] = blk
                }
                for i in ed.doc.entities.indices where ed.doc.entities[i].props["visBase"] == block && ed.doc.entities[i].props["visibility"] == s { ed.doc.entities[i].props["visibility"] = n }
                BlockVisibility.setStates(block, states, &ed.doc)
                BlockVisibility.regenerate(block, &ed.doc)
            default:
                guard let blk = ed.doc.blocks[block] else { return }
                for s in states {
                    let hidden = blk.entities.filter { BlockVisibility.isHidden($0, in: s) }.count
                    let refs = ed.doc.entities.filter { $0.props["visBase"] == block && $0.props["visibility"] == s }.count
                    ed.print("  \(s): \(blk.entities.count - hidden) of \(blk.entities.count) object(s) visible, \(refs) reference(s)")
                }
            }
        }
    }

    // MARK: Action macros
    static func macroNames(_ doc: ArchiDocument) -> [String] {
        doc.variables.keys.filter { $0.hasPrefix(actionPrefix) }.map { String($0.dropFirst(actionPrefix.count)) }.sorted()
    }
    static var actions: [CommandDef] { [
        CommandDef("ACTRECORD", aliases: ["ACTIONRECORD"], category: "Tools", summary: "Starts recording an action macro (typed commands and picks); ACTSTOP saves it in the drawing.", modifies: false) { ed in
            guard ed.actionRecorder == nil else { throw CommandError.invalid("An action is already being recorded. Use ACTSTOP.") }
            ed.actionRecorder = ScriptRecorder()
            ed.print("Action recording started. Run commands, then ACTSTOP.")
        },
        CommandDef("ACTSTOP", aliases: ["ACTIONSTOP"], category: "Tools", summary: "Stops recording and saves the action macro under a name (stored in the drawing).") { ed in
            guard let rec = ed.actionRecorder else { throw CommandError.invalid("No action is being recorded.") }
            ed.actionRecorder = nil
            var lines = rec.lines
            if let i = lines.lastIndex(where: { l in
                let n = l.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
                return ed.registry.lookup(n)?.name == "ACTSTOP" }) { lines.removeSubrange(i...) }
            while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            guard !lines.isEmpty else { ed.print("Nothing was recorded."); return }
            var def = "ActMacro1", k = 1
            while ed.doc.variable(actionPrefix + def) != nil { k += 1; def = "ActMacro\(k)" }
            guard let name = try await ed.getWord("Enter action macro name", defaultValue: def), !name.isEmpty, !name.contains(" ") else { throw CommandError.invalid("Invalid name.") }
            ed.doc.setVariable(actionPrefix + name, lines.joined(separator: "\n"))
            ed.print("Action macro \(name.uppercased()) saved (\(lines.count) line(s)). Run it with ACTPLAY \(name).")
        },
        CommandDef("ACTPLAY", aliases: ["ACTIONPLAY"], category: "Tools", summary: "Plays back a recorded action macro.", modifies: false) { ed in
            let names = macroNames(ed.doc)
            guard !names.isEmpty else { throw CommandError.invalid("No action macros in this drawing.") }
            guard let n = try await ed.getWord("Enter action macro name [\(names.joined(separator: "/"))]", defaultValue: names.first), let text = ed.doc.variable(actionPrefix + n) else {
                throw CommandError.invalid("No such action macro.") }
            ed.print("Playing action \(n.uppercased()).")
            ed.backgroundTask = Task { @MainActor in await ed.runScript(text + "\n") }
        },
        CommandDef("ACTMANAGER", aliases: ["ACTLIST", "ACTIONMANAGER"], category: "Tools", summary: "Lists, shows, deletes, renames, exports (.scr) or imports action macros.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["List", "Show", "Delete", "Rename", "Export", "Import"], defaultValue: "List") ?? "List"
            let names = macroNames(ed.doc)
            switch k {
            case "List":
                if names.isEmpty { ed.print("No action macros.") }
                for n in names { ed.print("  \(n) (\((ed.doc.variable(actionPrefix + n) ?? "").split(separator: "\n").count) line(s))") }
            case "Show":
                guard let n = try await ed.getWord("Enter action macro name"), let t = ed.doc.variable(actionPrefix + n) else { throw CommandError.invalid("No such action macro.") }
                for l in t.split(separator: "\n", omittingEmptySubsequences: false) { ed.print("  " + (l.isEmpty ? "\"\"" : String(l))) }
            case "Delete":
                guard let n = try await ed.getWord("Enter action macro name"), ed.doc.variable(actionPrefix + n) != nil else { throw CommandError.invalid("No such action macro.") }
                ed.doc.variables[(actionPrefix + n).uppercased()] = nil
                ed.print("Action macro \(n.uppercased()) deleted.")
            case "Rename":
                guard let n = try await ed.getWord("Enter action macro name"), let t = ed.doc.variable(actionPrefix + n) else { throw CommandError.invalid("No such action macro.") }
                guard let m = try await ed.getWord("Enter new name"), !m.isEmpty, !m.contains(" "), ed.doc.variable(actionPrefix + m) == nil else { throw CommandError.invalid("Invalid or duplicate name.") }
                ed.doc.variables[(actionPrefix + n).uppercased()] = nil
                ed.doc.setVariable(actionPrefix + m, t)
            case "Export":
                guard let n = try await ed.getWord("Enter action macro name"), let t = ed.doc.variable(actionPrefix + n) else { throw CommandError.invalid("No such action macro.") }
                guard let p = try await ed.getWord("Enter .scr file name") else { return }
                do { try (t + "\n").write(toFile: (p as NSString).expandingTildeInPath, atomically: true, encoding: .utf8); ed.print("Exported to \(p).") }
                catch { throw CommandError.invalid("Cannot write \(p).") }
            case "Import":
                guard let p = try await ed.getWord("Enter .scr file name"), let t = try? String(contentsOfFile: (p as NSString).expandingTildeInPath, encoding: .utf8) else { throw CommandError.invalid("Cannot read the file.") }
                let def = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
                guard let n = try await ed.getWord("Enter action macro name", defaultValue: def), !n.isEmpty, !n.contains(" ") else { return }
                ed.doc.setVariable(actionPrefix + n, t.trimmingCharacters(in: .newlines))
                ed.print("Imported \(n.uppercased()).")
            default: return
            }
        },
    ] }

    // MARK: History
    static var history: CommandDef {
        CommandDef("HISTORY", aliases: ["CMDHISTORY", "HIST"], category: "Tools", summary: "Command history: List (last N), Recent input values, Save/Load a history file, Clear, or run a previous line (!n).", modifies: false) { ed in
            let k = try await ed.getWord("Enter an option [List/Recent/Save/Load/Clear] or !n to repeat", defaultValue: "List", keywords: ["List", "Recent", "Save", "Load", "Clear"]) ?? "List"
            switch k {
            case "List":
                let n = try await ed.getInteger("Number of lines", defaultValue: 20) ?? 20
                let h = ed.commandHistory
                let start = max(0, h.count - max(1, n))
                // Exclude this HISTORY line itself.
                for (i, l) in h.enumerated().dropFirst(start) where i < h.count - 1 { ed.print("  \(h.count - 1 - i): \(l)") }
                if h.count <= 1 { ed.print("No command history.") }
            case "Recent":
                if ed.recentInputs.isEmpty { ed.print("No recent input.") }
                for v in ed.recentInputs.suffix(20).reversed() { ed.print("  \(v)") }
            case "Save":
                let p = try await ed.getWord("Enter history file", defaultValue: CommandHistoryFile.defaultURL.path) ?? CommandHistoryFile.defaultURL.path
                do { try CommandHistoryFile.save(Array(ed.commandHistory.dropLast()), to: URL(fileURLWithPath: (p as NSString).expandingTildeInPath)); ed.print("History saved to \(p).") }
                catch { throw CommandError.invalid("Cannot write \(p).") }
            case "Load":
                let p = try await ed.getWord("Enter history file", defaultValue: CommandHistoryFile.defaultURL.path) ?? CommandHistoryFile.defaultURL.path
                let lines = CommandHistoryFile.load(URL(fileURLWithPath: (p as NSString).expandingTildeInPath))
                ed.setCommandHistory(lines + ed.commandHistory)
                ed.print("\(lines.count) line(s) loaded.")
            case "Clear": ed.clearHistory(); ed.print("History cleared.")
            default:
                if k.hasPrefix("!"), let n = Int(k.dropFirst()), let line = ed.historyEntry(back: n + 1) {
                    ed.print("Repeating: \(line)")
                    ed.backgroundTask = Task { @MainActor in await ed.runScript(line + "\n") }
                } else { throw CommandError.invalid("Unknown option \(k).") }
            }
        }
    }
}
