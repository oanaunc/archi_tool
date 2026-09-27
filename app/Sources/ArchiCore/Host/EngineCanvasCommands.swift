// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac sheet-viewport commands (ArchiApp/AppCommands.swift VPLOCK, AppCommandsNav.swift VPMAX,
// VPMIN, VPCLIP): same names, aliases, prompts and messages. The active sheet is CTAB (the sheet the shell shows).
// VPMAX / VPMIN ask the shell to switch views with `host` notifications:
// {"action":"maximizeViewport","layout":i,"viewport":j,"rect":[x0,y0,x1,y1],"level":n} and {"action":"restoreViewport","layout":i}.
// Registered by archi-engine only (EngineSession.registerCanvasCommands); the Mac app registers its own versions.
import Foundation

enum EngineCanvasCommands {
    static var all: [CommandDef] { [vplock, vpmax, vpmin, vpclip, toolPalettes, toolPalettesClose, radialMenu] }

    @MainActor static func viewportNumber(_ ed: Editor, _ li: Int) async throws -> Int? {
        let n = ed.doc.layouts[li].viewports.count
        guard n > 0 else { throw CommandError.invalid("The sheet has no viewports.") }
        if n == 1 { return 0 }
        guard let v = try await ed.getInteger("Enter viewport number (1–\(n)) <1>", defaultValue: 1) else { return nil }
        guard (1...n).contains(v) else { throw CommandError.invalid("No such viewport.") }
        return v - 1
    }

    static var vplock: CommandDef {
        CommandDef("VPLOCK", aliases: ["VPORTLOCK", "LOCKVIEWPORT"], category: "Output", summary: "Locks or unlocks sheet viewports so their scale and position cannot change.") { ed in
            let li = EngineToolCommands.activeSheet(ed)
            guard ed.doc.layouts.indices.contains(li), !ed.doc.layouts[li].viewports.isEmpty else { throw CommandError.invalid("The active sheet has no viewports.") }
            let n = ed.doc.layouts[li].viewports.count
            let k = try await ed.getKeyword("Viewport display locking [On/Off]", ["On", "Off"], defaultValue: "On") ?? "On"
            let which = try await ed.getString("Enter viewport number (1–\(n)) or All <All>", defaultValue: "All") ?? "All"
            var targets: [Int] = []
            if which.lowercased().hasPrefix("a") { targets = Array(0..<n) }
            else {
                for s in which.split(separator: ",") {
                    if let v = Int(s.trimmingCharacters(in: .whitespaces)), (1...n).contains(v) { targets.append(v - 1) }
                }
            }
            guard !targets.isEmpty else { throw CommandError.invalid("No such viewport.") }
            var d = ed.doc
            for t in targets { EngineViewports.setLocked(&d, li, t, k == "On") }
            ed.doc = d
            ed.print("\(targets.count) viewport(s) \(k == "On" ? "locked" : "unlocked") on \(d.layouts[li].name).")
        }
    }

    static var vpmax: CommandDef {
        CommandDef("VPMAX", aliases: ["VPMAXIMIZE"], category: "View", summary: "Maximises a sheet viewport: edits the model through it at full window size (VPMIN returns).", modifies: false) { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("No sheet to maximise a viewport of.") }
            let li = EngineToolCommands.activeSheet(ed)
            guard let vi = try await viewportNumber(ed, li) else { throw CommandError.invalid("No sheet to maximise a viewport of.") }
            let vp = ed.doc.layouts[li].viewports[vi]
            guard vp.view == .plan || vp.view == .ceiling else { throw CommandError.invalid("Only plan viewports can be maximised.") }
            EngineCanvasState.of(ed).maximized = (li, vi)
            if let lv = vp.level, ed.doc.level(lv) != nil, ed.doc.currentLevel != lv { ed.doc.currentLevel = lv }
            let box = EngineViewports.modelWindow(vp)
            try EngineToolCommands.host(ed, "maximizeViewport", [("layout", .int(li)), ("viewport", .int(vi)), ("rect", EngineDrawJSON.rect(box)),
                                                                 ("level", vp.level.map { EngineJSON.int($0) } ?? .null)])
            ed.print("Viewport \(vi + 1) maximised. VPMIN returns to the sheet.")
        }
    }

    static var vpmin: CommandDef {
        CommandDef("VPMIN", aliases: ["VPMINIMIZE"], category: "View", summary: "Returns from a maximised viewport to its sheet, keeping the new view centre (unless the viewport is locked).") { ed in
            let st = EngineCanvasState.of(ed)
            guard let (li, vi) = st.maximized, ed.doc.layouts.indices.contains(li), ed.doc.layouts[li].viewports.indices.contains(vi) else {
                throw CommandError.invalid("No viewport is maximised.")
            }
            if !EngineViewports.isLocked(ed.doc, li, vi), let c = st.viewCenter { ed.doc.layouts[li].viewports[vi].viewCenter = c }
            st.maximized = nil
            try EngineToolCommands.host(ed, "restoreViewport", [("layout", .int(li)), ("viewport", .int(vi))])
        }
    }

    static var vpclip: CommandDef {
        CommandDef("VPCLIP", category: "View", summary: "Clips a sheet viewport to a polygon of paper points (x,y in mm), or Deletes the clip.") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("No sheet.") }
            let li = EngineToolCommands.activeSheet(ed)
            guard let vi = try await viewportNumber(ed, li) else { throw CommandError.invalid("No sheet.") }
            var pts: [Vec2] = []
            while true {
                let a = try await ed.getPoint(pts.isEmpty ? "Specify first paper point or [Delete]" : "Specify next paper point (Enter to close)", keywords: pts.isEmpty ? ["Delete"] : [])
                if case .keyword("Delete") = a { EngineViewports.setClip(&ed.doc, li, vi, nil); ed.print("Clip removed."); return }
                guard let p = a.point else { break }
                pts.append(p)
            }
            guard pts.count >= 3 else { throw CommandError.invalid("A clip boundary needs at least 3 points.") }
            EngineViewports.setClip(&ed.doc, li, vi, pts)
            ed.print("Viewport \(vi + 1) clipped to \(pts.count) points.")
        }
    }

    static var toolPalettes: CommandDef {
        CommandDef("TOOLPALETTES", aliases: ["TP", "TOOLPALETTE"], category: "View", summary: "Shows the tool palettes panel (grouped tools and My Tools).", modifies: false) { ed in
            try EngineToolCommands.host(ed, "showPanel", [("panel", .string("Tools"))])
        }
    }

    static var toolPalettesClose: CommandDef {
        CommandDef("TOOLPALETTESCLOSE", category: "View", summary: "Hides the tool palettes panel.", modifies: false) { ed in
            try EngineToolCommands.host(ed, "hidePanel", [("panel", .string("Tools"))])
        }
    }

    /// Context of the marking menu (ArchiApp RadialMenu.swift): drafting, objects selected, building elements selected.
    static func radialContext(_ doc: ArchiDocument, selection: Set<EntityID>) -> String {
        if selection.isEmpty { return "Drafting" }
        return selection.allSatisfy { doc.element($0) != nil } ? "Building elements" : "Objects"
    }
    static func radialCommands(_ context: String) -> [String] {
        switch context {
        case "Objects": return ["MOVE", "COPY", "ROTATE", "OFFSET", "ERASE", "TRIM", "MIRROR", "PROPERTIES"]
        case "Building elements": return ["MOVE", "COPY", "ROTATE", "ARRAY", "ERASE", "MATCHPROP", "MIRROR", "PROPERTIES"]
        default: return ["LINE", "PLINE", "WALL", "DOOR", "DIM", "WINDOW", "RECTANG", "CIRCLE"]
        }
    }

    static var radialMenu: CommandDef {
        CommandDef("RADIALMENU", aliases: ["MARKINGMENU", "PIEMENU"], category: "View", summary: "Right-drag marking menu with the 8 most used commands for the context (On/Off/List).", modifies: false) { ed in
            let k = try await ed.getKeyword("Marking menu [On/Off/List]", ["On", "Off", "List"], defaultValue: "List") ?? "List"
            let st = EngineCanvasState.of(ed)
            if k == "List" {
                let c = radialContext(ed.doc, selection: ed.selection)
                ed.print("Marking menu (\(st.radialMenu ? "on" : "off")), \(c): " + radialCommands(c).joined(separator: ", "))
            } else {
                st.radialMenu = k == "On"
                try EngineToolCommands.host(ed, "preference", [("key", .string("radialMenu")), ("value", .bool(k == "On"))])
                ed.print("Marking menu \(k.lowercased()): right-drag in the drawing.")
            }
        }
    }
}

extension EngineSession {
    /// Registers the portable sheet-viewport commands (archi-engine only; the Mac app has its own).
    public static func registerCanvasCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineCanvasCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
    }
}
