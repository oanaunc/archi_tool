// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Layer tools: layer states, filters, translator, walk, merge, change to current, previous, per-viewport freeze.
public enum LayerToolCommands {
    static var all: [CommandDef] { [layerState, layFilter, layTrans, layWalk, layMrg, layCur, layerP, vpLayer] }

    static func readFile(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do { return try String(contentsOf: url, encoding: .utf8) } catch { throw CommandError.invalid("Cannot read \(url.path).") }
    }
    static func writeFile(_ path: String, _ text: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(url.path).") }
        return url.path
    }

    static var layerState: CommandDef {
        CommandDef("LAYERSTATE", aliases: ["LAS", "-LAYERSTATE", "LMAN"], category: "Settings", summary: "Saves, restores, deletes, imports and exports named layer states (on/off, freeze, lock, plot, color, linetype, lineweight).") { ed in
            let k = try await ed.getKeyword("Enter an option", layerStateOptions, defaultValue: "?") ?? "?"
            try await runLayerState(k, ed)
        }
    }

    /// Options of the command-line LAYERSTATE (the app adds a Dialog option in front of these).
    public static let layerStateOptions = ["?", "Save", "Restore", "Delete", "Import", "Export", "Rename"]

    /// Runs one LAYERSTATE option (shared by the core command and the app's dialog-aware LAYERSTATE).
    @MainActor public static func runLayerState(_ k: String, _ ed: Editor) async throws {
            switch k {
            case "?":
                let list = LayerStates.all(ed.doc)
                if list.isEmpty { ed.print("No layer states."); return }
                for s in list { ed.print("  \(s.name)  (\(s.layers.count) layers, current \(s.currentLayer ?? "-"))\(s.description.isEmpty ? "" : " — \(s.description)")") }
            case "Save":
                guard let n = try await ed.getWord("Enter new layer state name") else { return }
                let desc = try await ed.getString("Enter description", defaultValue: "") ?? ""
                LayerStates.save(&ed.doc, name: n, description: desc)
                ed.print("Layer state \"\(n)\" saved (\(ed.doc.layers.count) layers).")
            case "Restore":
                guard let n = try await ed.getWord("Enter layer state name to restore"), let st = LayerStates.named(n, ed.doc) else { throw CommandError.invalid("Layer state not found.") }
                let off = try await ed.getYesNo("Turn off layers not found in the layer state?", defaultValue: false)
                let c = LayerStates.restore(st, into: &ed.doc, turnOffOthers: off)
                ed.print("Layer state \"\(st.name)\" restored (\(c) layer(s) changed).")
            case "Delete":
                guard let n = try await ed.getWord("Enter layer state name to delete") else { return }
                if !LayerStates.delete(&ed.doc, name: n) { throw CommandError.invalid("Layer state not found.") }
            case "Rename":
                guard let n = try await ed.getWord("Enter layer state name"), let new = try await ed.getWord("Enter new name") else { return }
                guard LayerStates.rename(&ed.doc, from: n, to: new) else { throw CommandError.invalid("Layer state not found.") }
            case "Export":
                guard let n = try await ed.getWord("Enter layer state name to export"), let st = LayerStates.named(n, ed.doc) else { throw CommandError.invalid("Layer state not found.") }
                guard let path = try await ed.getWord("Enter file name", defaultValue: "~/\(st.name).las.json") else { return }
                ed.print("Exported to \(try writeFile(path, LayerStates.export(st))).")
            case "Import":
                guard let path = try await ed.getWord("Enter file name (.las.json, .archi or .dxf)") else { return }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                var st: LayerState
                if ["archi", "dxf"].contains(url.pathExtension.lowercased()) {
                    let (src, _) = try FileImport.load(url)
                    st = LayerStates.capture(src, name: url.deletingPathExtension().lastPathComponent)
                } else {
                    guard let s = LayerStates.importState(try readFile(path)) else { throw CommandError.invalid("Not a layer state file.") }
                    st = s
                }
                LayerStates.put(st, &ed.doc)
                if try await ed.getYesNo("Restore it now (creating missing layers)?", defaultValue: false) {
                    LayerStates.restore(st, into: &ed.doc, createMissing: true)
                }
                ed.print("Layer state \"\(st.name)\" imported.")
            default: return
            }
    }

    static var layFilter: CommandDef {
        CommandDef("LAYFILTER", aliases: ["-LAYFILTER"], category: "Settings", summary: "Named layer filters: New property filter (name=A-* on=yes color=1 used=no…), Group filter, Invert, Delete, List, Select, Current.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["?", "New", "Group", "Invert", "Delete", "Select", "Current"], defaultValue: "?") ?? "?"
            switch k {
            case "?":
                let fs = LayerFilters.all(ed.doc)
                if fs.isEmpty { ed.print("No layer filters.") }
                for f in fs {
                    let names = LayerFilters.layers(f, doc: ed.doc).map(\.name)
                    ed.print("  \(f.name)\(f.inverted ? " (inverted)" : "") [\(f.kind.rawValue)]: \(names.joined(separator: ", "))")
                }
            case "New":
                guard let n = try await ed.getWord("Enter filter name"), let r = try await ed.getString("Enter rules (e.g. name=A-* on=yes)") else { return }
                let rules = LayerFilters.parseRules(r)
                guard !rules.isEmpty else { throw CommandError.invalid("No rules (use key=value).") }
                LayerFilters.upsert(LayerFilter(name: n, rules: rules), &ed.doc)
                ed.print("Filter \"\(n)\": \(LayerFilters.layers(LayerFilters.named(n, ed.doc)!, doc: ed.doc).count) layer(s).")
            case "Group":
                guard let n = try await ed.getWord("Enter group filter name") else { return }
                guard let l = try await ed.getWord("Enter layer names or patterns (comma separated)") else { return }
                let names = SettingsCommands.matchLayers(ed.doc, l).map { ed.doc.layers[$0].name }
                LayerFilters.upsert(LayerFilter(name: n, kind: .group, layers: names), &ed.doc)
                ed.print("Group filter \"\(n)\": \(names.count) layer(s).")
            case "Invert":
                guard let n = try await ed.getWord("Enter filter name"), var f = LayerFilters.named(n, ed.doc) else { throw CommandError.invalid("Filter not found.") }
                f.inverted.toggle(); LayerFilters.upsert(f, &ed.doc)
            case "Delete":
                guard let n = try await ed.getWord("Enter filter name") else { return }
                LayerFilters.store(LayerFilters.all(ed.doc).filter { $0.name.caseInsensitiveCompare(n) != .orderedSame }, &ed.doc)
            case "Select":
                guard let n = try await ed.getWord("Enter filter name"), let f = LayerFilters.named(n, ed.doc) else { throw CommandError.invalid("Filter not found.") }
                let ids = LayerWalk.objects(on: LayerFilters.layers(f, doc: ed.doc).map(\.name), doc: ed.doc).filter { ed.isSelectable($0) }
                ed.selection = Set(ids); ed.print("\(ids.count) object(s) selected.")
            case "Current":
                let n = try await ed.getWord("Enter filter name to show in the layer panel (Enter = none)") ?? ""
                if n.isEmpty { ed.doc.variables["LAYERFILTER"] = nil }
                else { guard LayerFilters.named(n, ed.doc) != nil else { throw CommandError.invalid("Filter not found.") }; ed.doc.setVariable("LAYERFILTER", n) }
            default: return
            }
        }
    }

    static var layTrans: CommandDef {
        CommandDef("LAYTRANS", aliases: ["-LAYTRANS"], category: "Settings", summary: "Layer translator: maps layers to standard layers (mappings FROM=TO with wildcards, or a mapping file; standards from a drawing).") { ed in
            guard let m = try await ed.getWord("Enter mappings FROM=TO separated by ';' or @file") else { return }
            let text = m.hasPrefix("@") ? try readFile(String(m.dropFirst())) : m.replacingOccurrences(of: ";", with: "\n")
            let maps = LayerTranslator.parseMappings(text)
            guard !maps.isEmpty else { throw CommandError.invalid("No mappings.") }
            var standard: [Layer] = []
            if let s = try await ed.getWord("Enter standards drawing (.archi/.dxf) or Enter for none", defaultValue: ""), !s.isEmpty {
                let (src, _) = try FileImport.load(URL(fileURLWithPath: (s as NSString).expandingTildeInPath))
                standard = src.layers
            }
            let force = try await ed.getYesNo("Force object color, linetype and lineweight to ByLayer?", defaultValue: false)
            let r = LayerTranslator.translate(&ed.doc, mappings: maps, standard: standard, forceByLayer: force)
            for (f, t) in r.translated.sorted(by: { $0.key < $1.key }) { ed.print("  \(f) → \(t)") }
            ed.print("\(r.translated.count) layer(s) translated, \(r.moved) object(s) moved, \(r.purged.count) layer(s) purged.")
        }
    }

    static var layWalk: CommandDef {
        CommandDef("LAYWALK", category: "Settings", summary: "Walks through layers showing only the chosen ones (name, pattern, Next/Previous, Filter), then restores them.") { ed in
            let original = ed.doc.layers
            let counts = Dictionary(uniqueKeysWithValues: LayerWalk.counts(ed.doc).map { ($0.layer.lowercased(), $0.count) })
            var index = -1
            @MainActor func show(_ names: [String]) {
                ed.doc.layers = original
                ed.doc = LayerWalk.show(names, in: ed.doc)
                ed.print("Showing: " + names.map { "\($0) (\(counts[$0.lowercased()] ?? 0))" }.joined(separator: ", "))
            }
            while true {
                let w = try await ed.getWord("Enter layer name(s) or pattern to show, or [Next/Previous/Filter/Exit]", keywords: ["Next", "Previous", "Filter", "Exit"])
                guard let w = w, w != "Exit" else { break }
                switch w {
                case "Next", "Previous":
                    guard !original.isEmpty else { continue }
                    index = w == "Next" ? (index + 1) % original.count : (index - 1 + original.count) % original.count
                    show([original[index].name])
                case "Filter":
                    guard let n = try await ed.getWord("Enter filter name"), let f = LayerFilters.named(n, ed.doc) else { throw CommandError.invalid("Filter not found.") }
                    var d = ed.doc; d.layers = original
                    show(LayerFilters.layers(f, doc: d).map(\.name))
                default:
                    let names = SettingsCommands.matchLayers(ArchiDocument.withLayers(original), w).map { original[$0].name }
                    if names.isEmpty { ed.print("No matching layer."); continue }
                    show(names)
                }
            }
            if try await ed.getYesNo("Restore layers on exit?", defaultValue: true) { ed.doc.layers = original }
        }
    }

    static var layMrg: CommandDef {
        CommandDef("LAYMRG", aliases: ["-LAYMRG", "LAYMERGE"], category: "Settings", summary: "Merges layers into a target layer (objects move, the source layers are deleted).") { ed in
            guard let s = try await ed.getWord("Enter layer names or patterns to merge (or select objects with #ids)") else { return }
            var sources: [String]
            if s.hasPrefix("#") {
                sources = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }
                    .compactMap { ed.doc.entity($0)?.layer ?? ed.doc.element($0)?.layer }
            } else { sources = SettingsCommands.matchLayers(ed.doc, s).map { ed.doc.layers[$0].name } }
            guard !sources.isEmpty else { throw CommandError.invalid("No matching layers.") }
            guard let t = try await ed.getWord("Enter target layer name") else { return }
            let n = LayerMerge.merge(sources, into: t, doc: &ed.doc)
            ed.print("\(Set(sources.map { $0.lowercased() }).subtracting([t.lowercased()]).count) layer(s) merged into \"\(t)\" (\(n) object(s)).")
        }
    }

    static var layCur: CommandDef {
        CommandDef("LAYCUR", category: "Settings", summary: "Changes the layer of selected objects to the current layer.") { ed in
            let ids = try await ed.getSelection("Select objects to be changed to the current layer")
            var n = 0
            for id in ids {
                if let i = ed.doc.entityIndex(id), ed.doc.entities[i].layer != ed.doc.currentLayer { ed.doc.entities[i].layer = ed.doc.currentLayer; n += 1 }
                if let i = ed.doc.elementIndex(id), ed.doc.elements[i].layer != ed.doc.currentLayer { ed.doc.elements[i].layer = ed.doc.currentLayer; n += 1 }
            }
            ed.selection = []
            ed.print("\(n) object(s) changed to layer \"\(ed.doc.currentLayer)\".")
        }
    }

    static var layerP: CommandDef {
        CommandDef("LAYERP", aliases: ["LAYP"], category: "Settings", summary: "Undoes the last change to layer settings (on/off, freeze, lock, color, current layer…) without undoing drawing edits.") { ed in
            guard let prev = ed.layerPrevious.popLast() else { ed.print("*No previous layer states*"); return }
            // Keep layers created since then (restoring would orphan their objects); restore settings of the others.
            var layers = prev.layers
            let names = Set(layers.map { $0.name.lowercased() })
            let used = SettingsCommands.usedLayers(ed.doc)
            for l in ed.doc.layers where !names.contains(l.name.lowercased()) && used.contains(l.name.lowercased()) { layers.append(l) }
            ed.doc.layers = layers
            if ed.doc.layer(named: prev.current) != nil { ed.doc.currentLayer = prev.current }
            ed.print("Restored previous layer states.")
        }
    }

    static var vpLayer: CommandDef {
        CommandDef("VPLAYER", aliases: ["VPFREEZE"], category: "Settings", summary: "Freezes/thaws layers in individual sheet viewports: Freeze, Thaw, Reset, List (layout and viewport numbers or All).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["?", "Freeze", "Thaw", "Reset"], defaultValue: "?") ?? "?"
            let names = ed.doc.layouts.map(\.name)
            guard !names.isEmpty else { throw CommandError.invalid("The drawing has no layouts.") }
            let lname = try await ed.getWord("Enter layout name", defaultValue: names[0]) ?? names[0]
            guard let layout = ed.doc.layouts.first(where: { $0.name.caseInsensitiveCompare(lname) == .orderedSame }) else { throw CommandError.invalid("Layout not found.") }
            if k == "?" {
                for i in layout.viewports.indices {
                    let fz = ViewportLayers.frozen(ed.doc, layout: layout.name, viewport: i)
                    ed.print("  Viewport \(i + 1)\(layout.viewports[i].title.isEmpty ? "" : " \(layout.viewports[i].title)"): \(fz.isEmpty ? "no frozen layers" : fz.sorted().joined(separator: ", "))")
                }
                return
            }
            var pattern = "*"
            if k != "Reset" { pattern = try await ed.getWord("Enter layer name(s) or pattern") ?? "" }
            let v = try await ed.getWord("Enter viewport number(s) (1,2…) or All", defaultValue: "All", keywords: ["All"]) ?? "All"
            let vps: [Int] = v == "All" ? Array(layout.viewports.indices) : v.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)).map { $0 - 1 } }.filter { layout.viewports.indices.contains($0) }
            guard !vps.isEmpty else { throw CommandError.invalid("No such viewport.") }
            if k == "Reset" { ViewportLayers.reset(&ed.doc, layout: layout.name, viewports: vps); ed.print("Viewport layers reset."); return }
            let n = ViewportLayers.set(&ed.doc, patterns: pattern, frozen: k == "Freeze", layout: layout.name, viewports: vps)
            ed.print("\(n) viewport layer setting(s) changed.")
        }
    }
}

extension ArchiDocument {
    /// A document holding only the given layers (for pattern matching helpers).
    static func withLayers(_ layers: [Layer]) -> ArchiDocument { var d = ArchiDocument(); d.layers = layers; return d }
}
