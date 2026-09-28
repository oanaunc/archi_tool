// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the last Mac UI-layer commands: APPSELFTEST (ArchiApp/AppSelfTests.swift), HELPWINDOW
// (AppCommandsNav.swift), VRVIEW (AppCommandsRound12.swift) and SPACEMOUSE (AppCommandsRound10.swift). Same names,
// aliases, categories, prompts and messages; the window, device and browser parts are done by the Windows shell, asked
// with `host` notifications (docs/ENGINE-PROTOCOL.md "Self test, help browser, VR, SpaceMouse and spelling"):
//   APPSELFTEST → {"action":"selfTest","passed":n,"failures":[…]} (the shell adds its own checks and prints the report)
//   HELPWINDOW  → {"action":"helpBrowser","route":"index"|"cmd/LINE"|"tutorials"|"shortcuts"|"scripting"}
//   VRVIEW      → {"action":"vrView","path":…,"mode":"Open"|"Reveal"} after writing the WebXR page (EngineWebViewer)
//   SPACEMOUSE  → {"action":"spaceMouse","enabled":…,"mode":"Object"|"Fly","sensitivity":…}
// Methods: `selftest.run {}` (the engine's checks) and `spell.verdicts {misspelled:{word:[suggestions]}}`, which installs
// the Windows spell checker's answers as SpellCheck.checker / suggester so SPELL runs as on the Mac (NSSpellChecker).
// Registered by archi-engine only (EngineSession.registerPortableAppCommands); the Mac app registers its own versions.
import Foundation

enum EngineSystemCommands {
    static var all: [CommandDef] { [appSelfTest, helpWindow, vrView, spaceMouse] }

    // MARK: APPSELFTEST

    static var appSelfTest: CommandDef {
        CommandDef("APPSELFTEST", aliases: ["SELFTEST"], category: "Help",
                   summary: "Runs the app's built-in regression checks (node graph, sheet set, presets, clipboard, ribbon).", modifies: false) { ed in
            let r = EngineSelfTests.run(registry: ed.registry)
            let shell = EngineSession.uiPreferences["selfTest.shell"] == "1" && (ed.host as? EngineHostBridge)?.session != nil
            if shell {
                // The Windows shell adds its checks (ribbon and menu catalogue, coverage, command search, help browser,
                // SpaceMouse, WebXR, spelling) and prints the report in the Mac's words.
                try EngineUICommands.host(ed, "selfTest", [("passed", .number(Double(r.passed))), ("failures", EngineJSON.strings(r.failures))])
                return
            }
            for f in r.failures { ed.print("FAIL: " + f) }
            ed.print("\(r.passed) check(s) passed, \(r.failures.count) failed.")
            if !r.failures.isEmpty { throw CommandError.invalid("\(r.failures.count) self-test check(s) failed.") }
        }
    }

    // MARK: HELPWINDOW

    static var helpWindow: CommandDef {
        CommandDef("HELPWINDOW", aliases: ["DOCS", "HELPBROWSER", "MANUAL"], category: "Help",
                   summary: "Opens the offline help browser (command pages, tutorials, shortcuts); F1 opens the running command's page.", modifies: false) { ed in
            let t = try await ed.getString("Command or topic [Tutorials/Shortcuts/Scripting] (Enter = index)", defaultValue: "")
            let s = (t ?? "").trimmingCharacters(in: .whitespaces)
            let route = try helpRoute(s, ed.registry)
            try EngineUICommands.host(ed, "helpBrowser", [("route", .string(route))])
        }
    }

    /// The help page for a typed topic (HelpBrowser.show routes): "" = index, a topic, or a command name / alias.
    static func helpRoute(_ s: String, _ r: CommandRegistry) throws -> String {
        if s.isEmpty { return "index" }
        let l = s.lowercased()
        if ["tutorials", "shortcuts", "scripting"].contains(l) { return l }
        if let d = r.lookup(s) { return "cmd/" + d.name }
        throw CommandError.invalid("Unknown command \"\(s)\".")
    }

    // MARK: VRVIEW

    static var vrView: CommandDef {
        CommandDef("VRVIEW", aliases: ["WEBXR", "VREXPORT", "HEADSETVIEW"], category: "View",
                   summary: "VR headset viewing: writes the model as a WebXR page (life-size, floor on the room floor, pinch/trigger steps forward) for Apple Vision Pro, Meta Quest or OpenXR browsers; Open, Reveal (AirDrop) or just Save.",
                   modifies: false) { ed in
            let s = EngineWebViewer.scene(doc: ed.doc)
            guard s.triangles > 0 else { throw CommandError.invalid("The model has no 3D content.") }
            let k = try await ed.getKeyword("After saving [Open/Reveal/Save]", ["Open", "Reveal", "Save"], defaultValue: "Reveal") ?? "Reveal"
            let url = vrPageURL(ed)
            do { try EngineWebViewer.html(doc: ed.doc).write(to: url, atomically: true, encoding: .utf8) }
            catch { throw CommandError.invalid("Cannot write " + url.path + ".") }
            // The Mac names AirDrop to Vision Pro; on Windows the page is copied to the headset or hosted over HTTPS.
            ed.print("VR page: \(s.triangles) triangles → \(url.path). Open it in the headset's browser (copy it to the headset, or host it over HTTPS) and choose Enter VR.")
            if k != "Save" { try? EngineUICommands.host(ed, "vrView", [("path", .string(url.path)), ("mode", .string(k))]) }
        }
    }

    /// "<drawing>-VR.html" next to the saved drawing, else on the Desktop (the Mac's choice).
    @MainActor static func vrPageURL(_ ed: Editor) -> URL {
        let name = ed.doc.info.name.isEmpty ? "Model" : ed.doc.info.name
        let base = ed.fileURL?.deletingPathExtension().lastPathComponent ?? name
        let fm = FileManager.default
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        let dir = ed.fileURL?.deletingLastPathComponent() ?? desktop
        return dir.appendingPathComponent(base + "-VR.html")
    }

    // MARK: SPACEMOUSE

    /// The shell's SpaceMouse settings and device list (ui.prefs spaceMouse.*; the Mac keeps them in UserDefaults).
    struct SpaceMouseState: Equatable {
        var enabled = true
        var mode = "Object"
        var sensitivity = 1.0
        /// WebHID is available in this window (the Mac: the IOHIDManager opened).
        var available = false
        var devices: [String] = []

        @MainActor static var current: SpaceMouseState {
            let p = EngineSession.uiPreferences
            var s = SpaceMouseState()
            if let v = p["spaceMouse.enabled"] { s.enabled = SystemVariables.parseFlag(v) ?? true }
            if let m = p["spaceMouse.mode"], m == "Object" || m == "Fly" { s.mode = m }
            if let v = p["spaceMouse.sensitivity"].flatMap(Double.init), v.isFinite { s.sensitivity = min(10, max(0.05, v)) }
            s.available = p["spaceMouse.available"] == "1"
            s.devices = (p["spaceMouse.devices"] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            return s
        }
        @MainActor func store() {
            EngineSession.uiPreferences["spaceMouse.enabled"] = enabled ? "1" : "0"
            EngineSession.uiPreferences["spaceMouse.mode"] = mode
            EngineSession.uiPreferences["spaceMouse.sensitivity"] = fmt(sensitivity, 4)
        }
        var running: Bool { enabled && available }
        var statusLine: String {
            let dev = devices.isEmpty ? "none connected" : devices.joined(separator: ", ")
            return "SpaceMouse \(running ? "on" : "off"), \(mode) mode, sensitivity \(fmt(sensitivity, 2)); devices: \(dev)."
        }
    }

    static var spaceMouse: CommandDef {
        CommandDef("SPACEMOUSE", aliases: ["3DMOUSE", "NDOF", "3DCONNEXION"], category: "View",
                   summary: "3Dconnexion SpaceMouse: On/Off, Object (orbit) or Fly mode, Sensitivity, Status. Axes move the 3D camera; button 1 fits the view.",
                   modifies: false) { ed in
            var st = SpaceMouseState.current
            let k = try await ed.getKeyword("SpaceMouse [On/Off/Object/Fly/Sensitivity/Status]", ["On", "Off", "Object", "Fly", "Sensitivity", "Status"], defaultValue: "Status") ?? "Status"
            switch k {
            case "On": st.enabled = true
            case "Off": st.enabled = false
            case "Object", "Fly": st.mode = k
            case "Sensitivity":
                let v = try await EngineView3DCommands.number(ed, "Sensitivity (0.05–10)", st.sensitivity)
                st.sensitivity = min(10, max(0.05, v))
            default: break
            }
            if k != "Status" {
                st.store()
                let fields: [(String, EngineJSON)] = [("enabled", .bool(st.enabled)), ("mode", .string(st.mode)), ("sensitivity", .number(st.sensitivity))]
                try? EngineUICommands.host(ed, "spaceMouse", fields)
            }
            ed.print(st.statusLine)
        }
    }
}

// MARK: - Methods

extension EngineSession {
    static let systemMethods: Set<String> = ["selftest.run", "spell.verdicts"]

    func callSystem(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "selftest.run":
            let r = EngineSelfTests.run(registry: editor.registry)
            var o = EngineObject()
            o.set("passed", r.passed)
            o.set("failures", EngineJSON.strings(r.failures))
            return o.json
        case "spell.verdicts":
            var bad: [String: [String]] = [:]
            for f in p["misspelled"]?.fields ?? [] { bad[f.key] = (f.value.arrayValue ?? []).compactMap { $0.stringValue } }
            let table = bad
            SpellCheck.checker = { table[$0] == nil }
            SpellCheck.suggester = { table[$0] ?? [] }
            var o = EngineObject()
            o.set("misspelled", table.count)
            return o.json
        default: return nil
        }
    }
}

// MARK: - Self test

/// The engine half of APPSELFTEST: the Mac's portable checks (node graphs, sheet sets) and the engine versions of
/// the Mac UI-layer commands (help routes, VR page, spelling, SpaceMouse status).
@MainActor
enum EngineSelfTests {
    struct Result { var passed = 0; var failures: [String] = [] }

    static func run(registry: CommandRegistry) -> Result {
        var r = Result()
        func check(_ ok: Bool, _ name: String) { if ok { r.passed += 1 } else { r.failures.append(name) } }
        nodeGraphChecks(check)
        nodeGraphGroupChecks(check)
        sheetSetChecks(check)
        commandChecks(check, registry)
        return r
    }

    static func nodeGraphChecks(_ check: (Bool, String) -> Void) {
        // Node graph: sample graph = octagon extruded, arrayed 3 × 2.
        let sample = NodeGraph.sample
        let ev = sample.evaluate()
        check(ev.errors.isEmpty, "node sample has no errors")
        check(ev.output.count == 6, "node sample makes 6 solids (got \(ev.output.count))")
        if case .solid(let s)? = ev.output.first {
            let ok = s.kind == .extrusion && abs(s.height - 3000) < 1e-9 && s.profile.count == 8
            check(ok, "extrusion height and octagon profile")
        } else { check(false, "node output is a solid") }
        // Range → Point → Circle broadcasting.
        var g = NodeGraph()
        let range = g.add(.range, x: 0, y: 0)
        let pt = g.add(.point, x: 0, y: 0)
        let circ = g.add(.circle, x: 0, y: 0)
        check(g.connect(from: range, to: pt, port: "x"), "connect range → point.x")
        check(g.connect(from: pt, to: circ, port: "center"), "connect point → circle.center")
        check(!g.connect(from: circ, to: pt, port: "y"), "type mismatch refused")
        let e2 = g.evaluate()
        check(e2.output.count == 5, "range of 5 gives 5 circles (got \(e2.output.count))")
        if case .circle(let c)? = e2.output.last { check(abs(c.center.x - 10000) < 1e-9, "last circle at x = 10000") }
        // Cycles are refused.
        var g3 = NodeGraph()
        let m1 = g3.add(.move, x: 0, y: 0)
        let m2 = g3.add(.move, x: 0, y: 0)
        check(g3.connect(from: m1, to: m2, port: "geometry"), "connect move → move")
        check(!g3.connect(from: m2, to: m1, port: "geometry"), "cycle refused")
        // Persistence round trip through a document variable, and baking.
        var doc = ArchiDocument()
        sample.store(in: &doc)
        check(NodeGraph.load(doc) == sample, "node graph JSON round trip")
        let ids = NodeGraphBake.bake(ev.output, into: &doc)
        _ = NodeGraphBake.bake(ev.output, into: &doc)
        check(ids.count == 6 && NodeGraphBake.bakedCount(doc) == 6, "bake replaces earlier output")
    }

    static func nodeGraphGroupChecks(_ check: (Bool, String) -> Void) {
        var g = NodeGraph.sample
        let gid = g.addGroup(title: "Columns", around: g.nodes.map(\.id))
        let cid = g.addComment("Octagonal columns", x: 10, y: 10)
        check(g.members(of: g.groups[0]).count == 4, "group frames its nodes")
        let x0 = g.nodes[0].x
        g.moveGroup(gid, dx: 100, dy: 0)
        check(abs(g.nodes[0].x - x0 - 100) < 1e-9 && g.comments.first?.id == cid, "moving a group moves its nodes")
        let gj = try? JSONEncoder().encode(g)
        let back = gj.flatMap { try? JSONDecoder().decode(NodeGraph.self, from: $0) }
        check(back == g, "groups and comments round trip")
        let js = NodeGraphScript.javascript(g, name: "cols")
        check(js.contains("archi.bakeGraph(graph)") && js.contains("archi.evaluateGraph(graph)"), "graph exported as a parametric script")
    }

    static func sheetSetChecks(_ check: (Bool, String) -> Void) {
        check(EngineSheets.nextCode(after: nil) == "A", "first revision A")
        check(EngineSheets.nextCode(after: "B") == "C", "B → C")
        check(EngineSheets.nextCode(after: "Z") == "AA", "Z → AA")
        check(EngineSheets.nextCode(after: "AZ") == "BA", "AZ → BA")
        check(EngineSheets.nextCode(after: "P01") == "P02", "P01 → P02")
        check(EngineSheets.nextCode(after: "9") == "10", "9 → 10")
        var sd = ArchiDocument()
        sd.layouts = [Layout(name: "Plans"), Layout(name: "Sections"), Layout(name: "Details")]
        EngineSheets.renumber(&sd, prefix: "A-", start: 101)
        check(EngineSheets.number(sd, 2) == "A-103", "renumber A-103")
        EngineSheets.addRevision(&sd, 0, description: "Issued for comment", by: "OA", date: "2026-09-25")
        EngineSheets.addRevision(&sd, 0, description: "Planning", by: "OA", date: "2026-10-01")
        let codes = EngineSheets.revisions(sd.layouts[0]).map(\.code)
        check(codes == ["A", "B"] && sd.layouts[0].titleBlock["revision"] == "B", "revisions A, B and title block field")
        EngineSheets.move(&sd, from: 0, to: 2)
        check(sd.layouts.map(\.name) == ["Sections", "Details", "Plans"], "move sheet to the end")
        let dup = EngineSheets.duplicate(&sd, 2)
        let dupOK = dup == 3 && sd.layouts[3].name == "Plans (2)" && EngineSheets.revisions(sd.layouts[3]).isEmpty
        check(dupOK, "duplicate sheet without revisions")
        EngineSheets.placeIndex(&sd, on: 0)
        EngineSheets.placeIndex(&sd, on: 0)
        let idx = sd.layouts[0].entities.filter { $0.props["sheetIndex"] != nil }
        if idx.count == 1, case .table(let t) = idx[0].geometry {
            check(t.cells.count == 5 && t.cells[2][0] == "A-103" && t.cells[4][0] == "A-104", "sheet index rows")
        } else { check(false, "one sheet index table") }
    }

    static func commandChecks(_ check: (Bool, String) -> Void, _ r: CommandRegistry) {
        // The Mac UI-layer commands of this file and the spelling commands are registered.
        let names = ["APPSELFTEST", "HELPWINDOW", "VRVIEW", "SPACEMOUSE", "SPELL"]
        let missing = names.filter { r.lookup($0) == nil }
        check(missing.isEmpty, "engine commands missing: \(missing.joined(separator: ", "))")
        // Help browser routes (HelpBrowser.show): topics, commands by alias, unknown names refused.
        check((try? EngineSystemCommands.helpRoute("", r)) == "index", "help index route")
        check((try? EngineSystemCommands.helpRoute("Tutorials", r)) == "tutorials", "help topic route")
        check((try? EngineSystemCommands.helpRoute("l", r)) == "cmd/LINE", "command page by alias")
        check((try? EngineSystemCommands.helpRoute("NOPE_NOT_A_CMD", r)) == nil, "unknown help topic refused")
        // The VR page is the WebXR viewer (Enter VR, immersive-vr, local-floor).
        let html = EngineWebViewer.html(doc: ArchiDocument())
        check(html.contains("immersive-vr") && html.contains("Enter VR") && html.contains("local-floor"), "VR page offers a WebXR session")
        // Spelling: words of a text and the misspelled ones for a checker.
        var d = ArchiDocument()
        let id = d.add(.text(TextGeom(position: .zero, height: 250, content: "Kitchn and bedroom")))
        let bad = SpellCheck.misspelled(d, ids: nil, isCorrect: { $0.lowercased() != "kitchn" })
        check(bad.count == 1 && bad.first?.word == "Kitchn" && bad.first?.entity == id, "spell check finds the misspelled word")
        check(SpellCheck.replace("Kitchn", with: "Kitchen", in: id, doc: &d), "spelling replacement")
        // SpaceMouse status line (the Mac's wording).
        var st = EngineSystemCommands.SpaceMouseState()
        st.available = true
        check(st.statusLine == "SpaceMouse on, Object mode, sensitivity 1; devices: none connected.", "SpaceMouse status")
    }
}
