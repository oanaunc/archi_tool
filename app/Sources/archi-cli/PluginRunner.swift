// Oanarina Archi Tool command-line runner — GPL-3.0-or-later
// JavaScript plugin evaluator for archi-cli (JavaScriptCore). Plugin commands get an `archi` object:
//   archi.print(text)              writes to the command history
//   archi.doc()                    document summary (units, layers, levels, counts, bounds)
//   archi.entities([type[, layer]]), archi.elements([type[, level]])   objects as JSON
//   archi.selection()              ids of the selected objects
//   archi.add(entity) → id, archi.addElement(element) → id, archi.update(id, patch), archi.remove([ids])
//   archi.getVar(name), archi.setVar(name, value)
//   archi.run(commandLine)         queued; runs after the plugin command finishes (each line its own undo step)
//   archi.registerCommand(name, fn, {aliases, summary, category, modifies})   adds a command implemented by a global function
// Edits made through add/addElement/update/remove/setVar belong to the plugin command (one undo step).
import Foundation
import JavaScriptCore
import ArchiCore

final class PluginJSBox {
    var doc: ArchiDocument
    var selection: [EntityID]
    var queue: [String] = []
    var prints: [String] = []
    var error: String?
    var registrations: [PluginCommand] = []
    init(doc: ArchiDocument, selection: [EntityID]) { self.doc = doc; self.selection = selection }
}

@MainActor enum CLIPlugins {
    /// Loads the plugin folders (default Application Support folder plus `extra`), registers their commands and installs
    /// the JavaScript evaluator.
    static func install(extra: URL?) {
        let reg = PluginRegistry.shared
        if let f = extra, !reg.folders.contains(f) { reg.folders.insert(f, at: 0) }
        reg.reload()
        reg.register(into: .shared)
        for p in reg.problems { eprint("plugin: " + p) }
        PluginRegistry.evaluator = { plugin, function, editor in try evaluate(plugin, function, editor) }
    }

    static func evaluate(_ plugin: LoadedPlugin, _ function: String, _ ed: Editor) throws {
        let queued = try run(plugin, function: function, ed)
        if !queued.isEmpty {
            // Runs after the plugin command finishes; scripts, the REPL and MCP await `backgroundTask` between lines.
            let previous = ed.backgroundTask
            ed.backgroundTask = Task { @MainActor in
                await previous?.value
                await ed.waitIdle()
                for line in queued { _ = await ed.run(line); await ed.waitIdle() }
            }
        }
    }

    /// Runs a JavaScript file (`archi-cli --js FILE`): the top level is evaluated with the `archi` API, commands it
    /// registers with `archi.registerCommand` become available, and queued `archi.run` lines run afterwards in order.
    static func runScriptFile(_ url: URL, _ ed: Editor) async throws {
        guard let src = try? String(contentsOf: url, encoding: .utf8) else { throw CLIError.message("Cannot read \(url.path)") }
        let plug = LoadedPlugin(manifest: PluginManifest(id: "script." + url.deletingPathExtension().lastPathComponent, name: url.deletingPathExtension().lastPathComponent,
                                                         main: url.lastPathComponent),
                                directory: url.deletingLastPathComponent(), source: src, enabled: true)
        let queued = try run(plug, function: nil, ed)
        for line in queued { await ed.waitIdle(); _ = await ed.run(line) }
        await ed.waitIdle()
    }

    /// Evaluates the plugin source and, when `function` is given, calls it. Returns the queued `archi.run` lines.
    static func run(_ plugin: LoadedPlugin, function: String?, _ ed: Editor) throws -> [String] {
        guard let ctx = JSContext() else { throw CLIError.message("JavaScriptCore is not available") }
        let box = PluginJSBox(doc: ed.doc, selection: Array(ed.selection).sorted())
        ctx.exceptionHandler = { _, v in box.error = v?.toString() ?? "JavaScript error" }
        guard let archi = JSValue(newObjectIn: ctx) else { throw CLIError.message("JavaScriptCore is not available") }
        func def<F>(_ name: String, _ block: F) { archi.setObject(unsafeBitCast(block, to: AnyObject.self), forKeyedSubscript: name as NSString) }
        func fail(_ m: String) { box.error = m; ctx.exception = JSValue(newErrorFromMessage: m, in: ctx) }
        let printB: @convention(block) (JSValue) -> Void = { v in
            if v.isObject, !v.isArray, let o = v.toObject(), JSONSerialization.isValidJSONObject(o) { box.prints.append(ArchiJSON.jsonString(o)) }
            else if v.isArray, let o = v.toArray(), JSONSerialization.isValidJSONObject(o) { box.prints.append(ArchiJSON.jsonString(o)) }
            else { box.prints.append(v.toString() ?? "") }
        }
        let runB: @convention(block) (String) -> Void = { line in box.queue.append(line) }
        let docB: @convention(block) () -> Any = { ArchiJSON.summary(box.doc) }
        let entitiesB: @convention(block) (JSValue, JSValue) -> Any = { t, l in
            ArchiJSON.entities(box.doc, type: t.isString ? t.toString() : nil, layer: l.isString ? l.toString() : nil)
        }
        let elementsB: @convention(block) (JSValue, JSValue) -> Any = { t, l in
            ArchiJSON.elements(box.doc, type: t.isString ? t.toString() : nil, level: l.isNumber ? Int(l.toInt32()) : nil)
        }
        let selectionB: @convention(block) () -> Any = { box.selection }
        let addB: @convention(block) (JSValue) -> Any = { v in
            do { let e = try ArchiJSON.entity(from: v.toObject() as Any, doc: box.doc); return box.doc.add(e) }
            catch { fail((error as? LocalizedError)?.errorDescription ?? "\(error)"); return NSNull() }
        }
        let addElementB: @convention(block) (JSValue) -> Any = { v in
            do { let s = try ArchiJSON.element(from: v.toObject() as Any, doc: box.doc); return ArchiJSON.add(s, to: &box.doc) }
            catch { fail((error as? LocalizedError)?.errorDescription ?? "\(error)"); return NSNull() }
        }
        let updateB: @convention(block) (JSValue, JSValue) -> Bool = { id, patch in
            guard id.isNumber, let p = patch.toObject() as? [String: Any] else { fail("update(id, patch) needs an id and an object"); return false }
            do { try ArchiJSON.patch(&box.doc, id: Int(id.toInt32()), p); return true } catch { fail((error as? LocalizedError)?.errorDescription ?? "\(error)"); return false }
        }
        let removeB: @convention(block) (JSValue) -> Int = { v in
            let raw: [Any] = v.isArray ? (v.toArray() ?? []) : [v.toObject() as Any]
            let ids = Set(raw.compactMap { ($0 as? NSNumber)?.intValue })
            let before = box.doc.entities.count + box.doc.elements.count
            box.doc.remove(ids: ids)
            return before - box.doc.entities.count - box.doc.elements.count
        }
        let getVarB: @convention(block) (String) -> Any = { n in box.doc.variable(n) ?? NSNull() }
        let setVarB: @convention(block) (String, JSValue) -> Void = { n, v in box.doc.setVariable(n, v.isNull || v.isUndefined ? "" : (v.toString() ?? "")) }
        // archi.registerCommand(name, fn | "fnName", {aliases, summary, category, modifies}) — SCR-006.
        let registerB: @convention(block) (JSValue, JSValue, JSValue) -> Bool = { n, f, o in
            guard n.isString, let name = n.toString(), !name.isEmpty else { fail("registerCommand(name, function[, options]) needs a command name"); return false }
            var fname = ""
            if f.isString { fname = f.toString() ?? "" }
            else if f.isObject, let nm = f.objectForKeyedSubscript("name"), nm.isString { fname = nm.toString() ?? "" }
            guard !fname.isEmpty else { fail("registerCommand: pass a named global function (or its name) for \(name)"); return false }
            let opts = (o.isObject ? o.toObject() as? [String: Any] : nil) ?? [:]
            box.registrations.append(PluginCommand(name: name, aliases: (opts["aliases"] as? [Any])?.compactMap { $0 as? String } ?? [],
                                                   summary: opts["summary"] as? String ?? "", function: fname,
                                                   category: opts["category"] as? String ?? "Scripts", modifies: opts["modifies"] as? Bool ?? true))
            return true
        }
        def("print", printB); def("run", runB); def("doc", docB); def("summary", docB); def("entities", entitiesB); def("elements", elementsB)
        def("selection", selectionB); def("add", addB); def("addElement", addElementB); def("update", updateB); def("remove", removeB)
        def("getVar", getVarB); def("setVar", setVarB); def("registerCommand", registerB)
        archi.setObject(plugin.manifest.name, forKeyedSubscript: "pluginName" as NSString)
        archi.setObject(function == nil ? "load" : "command", forKeyedSubscript: "mode" as NSString)
        ctx.setObject(archi, forKeyedSubscript: "archi" as NSString)
        let consoleObj = JSValue(newObjectIn: ctx)
        consoleObj?.setObject(unsafeBitCast(printB, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        ctx.setObject(consoleObj, forKeyedSubscript: "console" as NSString)

        let sourceURL = plugin.directory.appendingPathComponent(plugin.manifest.main)
        ctx.evaluateScript(plugin.source, withSourceURL: sourceURL)
        if let e = box.error { for p in box.prints { ed.print(p) }; throw CLIError.message("\(plugin.manifest.main): \(e)") }
        if let function {
            guard let fn = ctx.objectForKeyedSubscript(function), !fn.isUndefined, fn.isObject else {
                throw CLIError.message("\(plugin.manifest.main) defines no function \(function)()")
            }
            _ = fn.call(withArguments: [])
        } else {
            // Top-level run: registrations become commands (when the command itself runs, re-registration is skipped).
            for c in box.registrations {
                do {
                    let n = try PluginRegistry.shared.registerScriptCommand(c, source: plugin.source, sourceURL: sourceURL)
                    box.prints.append("Registered command \(n) (\(plugin.manifest.main): \(c.function)).")
                } catch { box.prints.append("registerCommand \(c.name): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            }
        }
        for p in box.prints { ed.print(p) }
        if let e = box.error { throw CLIError.message(e) }
        if box.doc != ed.doc { ed.doc = box.doc }
        return box.queue
    }
}
