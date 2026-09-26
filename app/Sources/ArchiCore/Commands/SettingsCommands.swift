// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// AutoCAD-style system variables mapped onto editor settings and the document.
public enum SystemVariables {
    /// OSMODE bit values (AutoCAD).
    public static let osmodeBits: [(SnapKind, Int)] = [
        (.endpoint, 1), (.midpoint, 2), (.center, 4), (.node, 8), (.quadrant, 16), (.intersection, 32), (.insertion, 64),
        (.perpendicular, 128), (.tangent, 256), (.nearest, 512), (.extension, 4096), (.parallel, 8192),
    ]
    public static func osmode(_ s: DraftSettings) -> Int {
        var v = osmodeBits.reduce(0) { s.snapModes.contains($1.0) ? $0 | $1.1 : $0 }
        if !s.objectSnap { v |= 16384 }
        return v
    }
    public static func applyOsmode(_ v: Int, to s: inout DraftSettings) {
        s.snapModes = Set(osmodeBits.filter { v & $0.1 != 0 }.map(\.0)).union(s.snapModes.contains(.grid) ? [.grid] : [])
        s.objectSnap = v & 16384 == 0 && v != 0
    }
    /// Names with dedicated handling (others are stored in ArchiDocument.variables).
    public static let known = ["ORTHOMODE", "SNAPMODE", "GRIDMODE", "SNAPUNIT", "GRIDUNIT", "OSMODE", "POLARMODE", "AUTOSNAP", "POLARANG", "DYNMODE", "LWDISPLAY",
                               "TEXTSIZE", "FILLETRAD", "CHAMFERA", "OFFSETDIST", "CLAYER", "CECOLOR", "CELTYPE", "CELWEIGHT", "DIMSTYLE", "TEXTSTYLE", "LTSCALE",
                               "WALLTHICKNESS", "WALLHEIGHT", "INSUNITS", "CLEVEL", "OTRACK"]
    /// Other commonly used variables registered as commands.
    public static let stored = ["CANNOSCALE", "PICKSTYLE", "SELECTSIMILARMODE", "INSBASE", "CENTEREXE", "CHAMFERB", "DIMSCALE", "DIMDLI", "LUPREC", "PDMODE", "PDSIZE", "MIRRTEXT", "DELOBJ", "HPNAME", "HPSCALE", "HPANG", "PLINEWID", "TRIMMODE", "DIMLAYER", "TEXTLAYER", "CONSTRAINTINFER", "AUTOCONSTRAINDIST", "AUTOCONSTRAINANGLE", "CETRANSPARENCY", "TRANSPARENCYDISPLAY", "PLOTTRANSPARENCY"]

    static func flag(_ b: Bool) -> String { b ? "1" : "0" }
    public static func parseFlag(_ s: String) -> Bool? {
        switch s.lowercased() { case "1", "on", "yes", "true": return true; case "0", "off", "no", "false": return false; default: return nil }
    }

    @MainActor public static func get(_ name: String, _ ed: Editor) -> String? {
        let s = ed.settings
        switch name.uppercased() {
        case "ORTHOMODE": return flag(s.ortho)
        case "SNAPMODE": return flag(s.gridSnap)
        case "GRIDMODE": return flag(s.showGrid)
        case "SNAPUNIT", "GRIDUNIT": return fmt(s.gridSpacing)
        case "OSMODE": return "\(osmode(s))"
        case "POLARMODE", "AUTOSNAP": return flag(s.polarTracking)
        case "POLARANG": return fmt(s.polarIncrement)
        case "OTRACK": return flag(s.objectSnapTracking)
        case "DYNMODE": return flag(s.dynamicInput)
        case "LWDISPLAY": return flag(s.lineweightDisplay)
        case "TEXTSIZE": return fmt(s.textHeight)
        case "FILLETRAD": return fmt(s.filletRadius)
        case "CHAMFERA": return fmt(s.chamferDistance)
        case "OFFSETDIST": return fmt(s.offsetDistance)
        case "WALLTHICKNESS": return fmt(s.wallThickness)
        case "WALLHEIGHT": return fmt(s.wallHeight)
        case "CLAYER": return ed.doc.currentLayer
        case "CLEVEL": return ed.doc.level(ed.doc.currentLevel)?.name
        case "DIMSTYLE": return ed.doc.currentDimStyle
        case "TEXTSTYLE": return ed.doc.variable("TEXTSTYLE") ?? "Standard"
        case "CECOLOR": return ed.doc.variable("CECOLOR") ?? "ByLayer"
        case "CELTYPE": return ed.doc.variable("CELTYPE") ?? "ByLayer"
        case "CELWEIGHT": return ed.doc.variable("CELWEIGHT") ?? "ByLayer"
        case "LTSCALE": return ed.doc.variable("LTSCALE") ?? "1"
        case "INSUNITS": return ed.doc.units.rawValue
        case "SNAPSTYL": return s.isometric ? "1" : "0"
        case "SNAPISOPAIR": return "\(s.isoPlane)"
        default:
            let n = name.uppercased()
            if let info = SysVarCatalog.info(n), info.readOnly, let c = SysVarCatalog.computed(n, ed) { return c }
            if SysVarCatalog.dimStyleVars.contains(n), let v = SysVarCatalog.dimGet(n, ed.doc.dimStyle) { return v }
            return ed.doc.variable(name) ?? SysVarCatalog.info(n)?.defaultValue
        }
    }

    /// Sets a variable. Returns an error message, or nil on success.
    @MainActor @discardableResult
    public static func set(_ name: String, _ value: String, _ ed: Editor) -> String? {
        let n = name.uppercased()
        let num = InputParser.parseNumber(value)
        func pos(_ f: (Double) -> Void, allowZero: Bool = false) -> String? {
            guard let v = num, v > 0 || (allowZero && v == 0) else { return "Requires a \(allowZero ? "non-negative" : "positive") number." }
            f(v); return nil
        }
        func onOff(_ f: (Bool) -> Void) -> String? { guard let b = parseFlag(value) else { return "Requires 0 or 1." }; f(b); return nil }
        switch n {
        case "ORTHOMODE": return onOff { ed.settings.ortho = $0 }
        case "SNAPMODE": return onOff { ed.settings.gridSnap = $0 }
        case "GRIDMODE": return onOff { ed.settings.showGrid = $0 }
        case "POLARMODE", "AUTOSNAP": return onOff { ed.settings.polarTracking = $0 }
        case "DYNMODE": return onOff { ed.settings.dynamicInput = $0 }
        case "OTRACK": return onOff { ed.settings.objectSnapTracking = $0; if !$0 { Snap.tracker.clear() } }
        case "LWDISPLAY": return onOff { ed.settings.lineweightDisplay = $0 }
        case "SNAPUNIT", "GRIDUNIT": return pos { ed.settings.gridSpacing = $0 }
        case "POLARANG": return pos { ed.settings.polarIncrement = $0 }
        case "TEXTSIZE": return pos { ed.settings.textHeight = $0; ed.doc.setVariable("TEXTSIZE", fmt($0)) }
        case "FILLETRAD": return pos({ ed.settings.filletRadius = $0; ed.doc.setVariable("FILLETRAD", fmt($0)) }, allowZero: true)
        case "CHAMFERA": return pos({ ed.settings.chamferDistance = $0; ed.doc.setVariable("CHAMFERA", fmt($0)) }, allowZero: true)
        case "OFFSETDIST": return pos { ed.settings.offsetDistance = $0 }
        case "WALLTHICKNESS": return pos { ed.settings.wallThickness = $0 }
        case "WALLHEIGHT": return pos { ed.settings.wallHeight = $0 }
        case "OSMODE":
            guard let v = num, v >= 0, v < 32768 else { return "Requires an integer between 0 and 32767." }
            applyOsmode(Int(v), to: &ed.settings); return nil
        case "CLAYER":
            guard let l = ed.doc.layer(named: value) else { return "Layer \(value) not found." }
            guard !l.frozen else { return "Cannot make a frozen layer current." }
            ed.doc.currentLayer = l.name; return nil
        case "CLEVEL":
            guard let l = ed.doc.levels.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) ?? Int(value).flatMap({ ed.doc.level($0) }) else { return "Level \(value) not found." }
            ed.doc.currentLevel = l.id; return nil
        case "DIMSTYLE":
            guard let s = ed.doc.dimStyles.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { return "Dimension style \(value) not found." }
            ed.doc.currentDimStyle = s.name; return nil
        case "TEXTSTYLE":
            guard let s = ed.doc.textStyles.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { return "Text style \(value) not found." }
            ed.doc.setVariable("TEXTSTYLE", s.name); return nil
        case "CECOLOR":
            guard let c = ColorRef.parse(value) else { return "Invalid color." }
            ed.doc.setVariable("CECOLOR", c.text); return nil
        case "CELTYPE":
            guard value.lowercased() == "bylayer" || value.lowercased() == "byblock" || ed.doc.linetype(value) != nil else { return "Linetype \(value) not loaded." }
            ed.doc.setVariable("CELTYPE", ed.doc.linetype(value)?.name ?? "ByLayer"); return nil
        case "CELWEIGHT":
            if value.lowercased() == "bylayer" { ed.doc.variables.removeValue(forKey: "CELWEIGHT"); return nil }
            return pos({ ed.doc.setVariable("CELWEIGHT", fmt($0)) }, allowZero: true)
        case "LTSCALE": return pos { ed.doc.setVariable("LTSCALE", fmt($0)) }
        case "CANNOSCALE":
            guard Annotative.factor(value) != nil else { return "Requires a scale such as 1:100." }
            ed.doc.setVariable("CANNOSCALE", value.replacingOccurrences(of: " ", with: "")); return nil
        case "PICKSTYLE":
            guard let v = num, [0, 1, 2, 3].contains(Int(v)) else { return "Requires 0-3." }
            ed.doc.setVariable("PICKSTYLE", "\(Int(v))"); return nil
        case "SELECTSIMILARMODE":
            guard let v = num, v >= 0, v <= 255 else { return "Requires an integer between 0 and 255." }
            ed.doc.setVariable("SELECTSIMILARMODE", "\(Int(v))"); return nil
        case "INSBASE":
            InputParser.context = ParseContext(units: ed.doc.units, ucs: .world)
            guard let p = InputParser.parsePoint(value, last: nil) else { return "Requires a point x,y." }
            ed.doc.setVariable("INSBASE", "\(fmt(p.x, 8)),\(fmt(p.y, 8))"); return nil
        case "CENTEREXE":
            return pos({ ed.doc.setVariable("CENTEREXE", fmt($0, 8)) }, allowZero: true)
        case "SNAPSTYL":
            guard let v = num, v == 0 || v == 1 else { return "Requires 0 (rectangular) or 1 (isometric)." }
            ed.settings.isometric = v == 1; return nil
        case "SNAPISOPAIR":
            guard let v = num, [0, 1, 2].contains(Int(v)), v == v.rounded() else { return "Requires 0 (left), 1 (top) or 2 (right)." }
            ed.settings.isoPlane = Int(v); return nil
        case "UCSORG", "UCSANG", "UCSPREV":
            return "\(n) is read-only; use the UCS command."
        case "INSUNITS":
            guard let u = Units.allCases.first(where: { $0.rawValue.hasPrefix(value.lowercased()) || $0.abbreviation == value.lowercased() }) else { return "Unknown units." }
            ed.doc.units = u; return nil
        default:
            guard let info = SysVarCatalog.info(n) else { ed.doc.setVariable(n, value); return nil }
            if info.readOnly { return "\(n) is read-only." }
            let (norm, err) = SysVarCatalog.validate(info, value)
            guard let v = norm else { return err }
            if SysVarCatalog.dimStyleVars.contains(n), let i = ed.doc.dimStyles.firstIndex(where: { $0.name == ed.doc.dimStyle.name }) {
                guard SysVarCatalog.dimSet(n, v, &ed.doc.dimStyles[i]) else { return "Invalid value for \(n)." }
                if n != "DIMSCALE" { return nil }
            }
            ed.doc.setVariable(n, v); return nil
        }
    }
}

enum SettingsCommands {
    static var all: [CommandDef] { layers + drafting + housekeeping + variableCommands }

    /// Glob match (* and ?) case-insensitively.
    static func glob(_ pattern: String, _ s: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(s.lowercased())
        var memo: [Int: Bool] = [:]
        func m(_ i: Int, _ j: Int) -> Bool {
            let key = i * (t.count + 1) + j
            if let v = memo[key] { return v }
            var r: Bool
            if i == p.count { r = j == t.count }
            else if p[i] == "*" { r = m(i + 1, j) || (j < t.count && m(i, j + 1)) }
            else { r = j < t.count && (p[i] == "?" || p[i] == t[j]) && m(i + 1, j + 1) }
            memo[key] = r
            return r
        }
        return m(0, 0)
    }
    static func matchLayers(_ doc: ArchiDocument, _ list: String) -> [Int] {
        let pats = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return doc.layers.indices.filter { i in pats.contains { glob($0, doc.layers[i].name) } }
    }
    static func rgba(_ c: ColorRef) -> RGBA? {
        switch c {
        case .aci(let i): return aciColor(i)
        case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        default: return nil
        }
    }
    static func usedLayers(_ doc: ArchiDocument) -> Set<String> {
        var s = Set(doc.entities.map { $0.layer.lowercased() } + doc.elements.map { $0.layer.lowercased() })
        for b in doc.blocks.values { for e in b.entities { s.insert(e.layer.lowercased()) } }
        for l in doc.layouts { for e in l.entities { s.insert(e.layer.lowercased()) } }
        return s
    }

    @MainActor static func pickLayers(_ ed: Editor, _ msg: String, apply: (inout Layer) -> Void) async throws {
        var n = 0
        while case .pick(let pk) = try await ed.pickObject(msg) {
            let name = ed.doc.entity(pk.id)?.layer ?? ed.doc.element(pk.id)?.layer ?? ""
            guard let i = ed.doc.layerIndex(name) else { continue }
            apply(&ed.doc.layers[i]); n += 1
            ed.print("Layer \"\(ed.doc.layers[i].name)\" changed.")
        }
        _ = n
    }

    // MARK: - Layers
    static var layers: [CommandDef] { [
        CommandDef("LAYER", aliases: ["LA", "-LAYER", "-LA"], category: "Settings", summary: "Manages layers: make, set, new, rename, on/off, freeze/thaw, lock/unlock, color, linetype, lineweight, delete.") { ed in
            ed.host?.perform(.showPanel("Layers"), editor: ed)
            let kws = ["?", "Make", "Set", "New", "Rename", "ON", "OFF", "Color", "Ltype", "LWeight", "TRansparency", "Freeze", "Thaw", "LOck", "Unlock", "Delete", "Plot"]
            ed.print("Current layer: \"\(ed.doc.currentLayer)\"")
            while let k = try await ed.getKeyword("Enter an option", kws) {
                switch k {
                case "?":
                    for l in ed.doc.layers {
                        ed.print(String(format: "%@ %-20@ %@ %@ %@ color %@ %@ %@mm", l.name == ed.doc.currentLayer ? "*" : " ", l.name as NSString,
                                        l.visible ? "on " : "off", l.frozen ? "frozen" : "thawed", l.locked ? "locked" : "      ", l.color.hex, l.linetype, fmt(l.lineweight, 2)))
                    }
                case "Make", "New":
                    guard let s = try await ed.getWord(k == "Make" ? "Enter name for new layer (becomes the current layer)" : "Enter name list for new layer(s)") else { continue }
                    let names = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    for n in names where n.rangeOfCharacter(from: CharacterSet(charactersIn: "<>/\\\":;?*|=`")) == nil {
                        if ed.doc.layer(named: n) == nil { ed.doc.layers.append(Layer(name: n)) }
                    }
                    if k == "Make", let n = names.first, let l = ed.doc.layer(named: n) {
                        if let i = ed.doc.layerIndex(l.name) { ed.doc.layers[i].frozen = false; ed.doc.layers[i].visible = true }
                        ed.doc.currentLayer = l.name
                    }
                case "Set":
                    guard let n = try await ed.getWord("Enter layer name to make current", defaultValue: ed.doc.currentLayer) else { continue }
                    guard let l = ed.doc.layer(named: n) else { ed.print("Cannot find layer \"\(n)\"."); continue }
                    if l.frozen { ed.print("Cannot set a frozen layer current."); continue }
                    ed.doc.currentLayer = l.name
                case "Rename":
                    guard let old = try await ed.getWord("Enter layer to rename"), let i = ed.doc.layerIndex(old) else { ed.print("Layer not found."); continue }
                    guard let new = try await ed.getWord("Enter new layer name"), !new.isEmpty else { continue }
                    guard ed.doc.layer(named: new) == nil || ed.doc.layerIndex(new) == i else { ed.print("Layer \"\(new)\" already exists."); continue }
                    if ed.doc.layers[i].name == "0" { ed.print("Layer 0 cannot be renamed."); continue }
                    renameLayer(&ed.doc, from: ed.doc.layers[i].name, to: new)
                case "Delete":
                    guard let s = try await ed.getWord("Enter layer name(s) to delete") else { continue }
                    let used = usedLayers(ed.doc)
                    for i in matchLayers(ed.doc, s).reversed() {
                        let l = ed.doc.layers[i]
                        if l.name == "0" || l.name == ed.doc.currentLayer { ed.print("Layer \"\(l.name)\" cannot be deleted (layer 0 or current)."); continue }
                        if used.contains(l.name.lowercased()) { ed.print("Layer \"\(l.name)\" contains objects and was not deleted."); continue }
                        ed.doc.layers.remove(at: i); ed.print("Layer \"\(l.name)\" deleted.")
                    }
                case "Color":
                    guard let c = try await ed.getWord("New color [1-255, #RRGGBB, r,g,b, name]"), let cr = ColorRef.parse(c), let rgba = rgba(cr) else { ed.print("Invalid color."); continue }
                    let s = try await ed.getWord("Enter name list of layer(s) for color", defaultValue: ed.doc.currentLayer) ?? ed.doc.currentLayer
                    for i in matchLayers(ed.doc, s) { ed.doc.layers[i].color = rgba }
                case "Ltype":
                    guard let lt = try await ed.getWord("Enter a loaded linetype name", defaultValue: "Continuous"), let t = ed.doc.linetype(lt) else { ed.print("Linetype not loaded."); continue }
                    let s = try await ed.getWord("Enter name list of layer(s) for linetype", defaultValue: ed.doc.currentLayer) ?? ed.doc.currentLayer
                    for i in matchLayers(ed.doc, s) { ed.doc.layers[i].linetype = t.name }
                case "TRansparency":
                    guard let v = try await ed.getReal("Enter transparency value (0-90)", defaultValue: 0).value, v >= 0, v <= 90 else { ed.print("Transparency must be between 0 and 90."); continue }
                    let s = try await ed.getWord("Enter name list of layer(s) for transparency", defaultValue: ed.doc.currentLayer) ?? ed.doc.currentLayer
                    for i in matchLayers(ed.doc, s) { ed.doc.layers[i].transparency = v / 100 }
                case "LWeight":
                    guard let v = try await ed.getReal("Enter lineweight (mm)", defaultValue: 0.25).value, v >= 0, v <= 2.11 else { ed.print("Lineweight must be between 0 and 2.11 mm."); continue }
                    let s = try await ed.getWord("Enter name list of layers(s) for lineweight", defaultValue: ed.doc.currentLayer) ?? ed.doc.currentLayer
                    for i in matchLayers(ed.doc, s) { ed.doc.layers[i].lineweight = v }
                default:
                    guard let s = try await ed.getWord("Enter name list of layer(s) to \(k.lowercased())") else { continue }
                    let idx = matchLayers(ed.doc, s)
                    if idx.isEmpty { ed.print("No matching layer."); continue }
                    for i in idx {
                        switch k {
                        case "ON": ed.doc.layers[i].visible = true
                        case "OFF":
                            ed.doc.layers[i].visible = false
                            if ed.doc.layers[i].name == ed.doc.currentLayer { ed.print("Note: the current layer is turned off.") }
                        case "Freeze":
                            if ed.doc.layers[i].name == ed.doc.currentLayer { ed.print("Cannot freeze the current layer."); continue }
                            ed.doc.layers[i].frozen = true
                        case "Thaw": ed.doc.layers[i].frozen = false
                        case "LOck": ed.doc.layers[i].locked = true
                        case "Unlock": ed.doc.layers[i].locked = false
                        case "Plot": ed.doc.layers[i].plot.toggle(); ed.print("Layer \"\(ed.doc.layers[i].name)\" \(ed.doc.layers[i].plot ? "will" : "will not") plot.")
                        default: break
                        }
                    }
                    ed.selection = ed.selection.filter { ed.isSelectable($0) }
                }
            }
        },
        CommandDef("LAYISO", category: "Settings", summary: "Isolates the layers of selected objects (turns the other layers off or locks them).") { ed in
            let ids = try await ed.getSelection("Select objects on the layer(s) to be isolated")
            guard !ids.isEmpty else { return }
            let keep = Set(ids.compactMap { ed.doc.entity($0)?.layer ?? ed.doc.element($0)?.layer }.map { $0.lowercased() })
            let mode = try await ed.getKeyword("Isolate by", ["Off", "Lock"], defaultValue: "Off") ?? "Off"
            var state: [String: String] = [:]
            for l in ed.doc.layers { state[l.name] = "\(l.visible ? 1 : 0),\(l.locked ? 1 : 0)" }
            if let data = try? JSONEncoder().encode(state), let s = String(data: data, encoding: .utf8) { ed.doc.setVariable("LAYISOSTATE", s) }
            for i in ed.doc.layers.indices where !keep.contains(ed.doc.layers[i].name.lowercased()) {
                if mode == "Off" { ed.doc.layers[i].visible = false } else { ed.doc.layers[i].locked = true }
            }
            if !keep.contains(ed.doc.currentLayer.lowercased()), let first = ed.doc.layers.first(where: { keep.contains($0.name.lowercased()) }) { ed.doc.currentLayer = first.name }
            ed.selection = []
            ed.print("\(keep.count) layer(s) isolated. Layer \"\(ed.doc.currentLayer)\" is current.")
        },
        CommandDef("LAYUNISO", category: "Settings", summary: "Restores the layers hidden or locked by LAYISO.") { ed in
            guard let s = ed.doc.variable("LAYISOSTATE"), let d = s.data(using: .utf8), let state = try? JSONDecoder().decode([String: String].self, from: d) else { ed.print("No isolated layers to restore."); return }
            for i in ed.doc.layers.indices {
                guard let v = state[ed.doc.layers[i].name] else { continue }
                let parts = v.split(separator: ",")
                if parts.count == 2 { ed.doc.layers[i].visible = parts[0] == "1"; ed.doc.layers[i].locked = parts[1] == "1" }
            }
            ed.doc.variables.removeValue(forKey: "LAYISOSTATE")
            ed.print("Layers restored.")
        },
        CommandDef("LAYOFF", category: "Settings", summary: "Turns off the layer of each selected object.") { ed in
            try await pickLayers(ed, "Select an object on the layer to be turned off") { $0.visible = false }
        },
        CommandDef("LAYFRZ", category: "Settings", summary: "Freezes the layer of each selected object.") { ed in
            let cur = ed.doc.currentLayer
            try await pickLayers(ed, "Select an object on the layer to be frozen") { l in if l.name != cur { l.frozen = true } }
        },
        CommandDef("LAYLCK", aliases: ["LAYLOCK"], category: "Settings", summary: "Locks the layer of each selected object.") { ed in
            try await pickLayers(ed, "Select an object on the layer to be locked") { $0.locked = true }
        },
        CommandDef("LAYULK", aliases: ["LAYUNLOCK"], category: "Settings", summary: "Unlocks the layer of a selected object.") { ed in
            // Locked objects are not pickable; pick by position ignoring locks.
            while let p = try await ed.getPoint("Select an object on the layer to be unlocked").point {
                var best: (String, Double)?
                for e in ed.doc.entities where ed.doc.isVisible(layer: e.layer) {
                    let d = GeometryOps.distance(from: p, to: e.geometry, doc: ed.doc)
                    if d <= ed.pickTolerance, d < (best?.1 ?? .infinity) { best = (e.layer, d) }
                }
                for el in ed.doc.elements where el.level == ed.doc.currentLevel && ed.doc.isVisible(layer: el.layer) {
                    let d = CommandHelpers.elementDistance(p, el, doc: ed.doc)
                    if d <= ed.pickTolerance, d < (best?.1 ?? .infinity) { best = (el.layer, d) }
                }
                if let n = best?.0, let i = ed.doc.layerIndex(n) { ed.doc.layers[i].locked = false; ed.print("Layer \"\(n)\" unlocked.") } else { ed.print("No object found.") }
            }
        },
        CommandDef("LAYON", category: "Settings", summary: "Turns on all layers.") { ed in
            for i in ed.doc.layers.indices { ed.doc.layers[i].visible = true }
            ed.print("All layers have been turned on.")
        },
        CommandDef("LAYTHW", category: "Settings", summary: "Thaws all layers.") { ed in
            for i in ed.doc.layers.indices { ed.doc.layers[i].frozen = false }
            ed.print("All layers have been thawed.")
        },
        CommandDef("LAYMCUR", category: "Settings", summary: "Makes the layer of a selected object current.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object whose layer will become current") else { return }
            guard let n = ed.doc.entity(pk.id)?.layer ?? ed.doc.element(pk.id)?.layer, let l = ed.doc.layer(named: n) else { return }
            ed.doc.currentLayer = l.name
            ed.print("\(l.name) is now the current layer.")
        },
        CommandDef("LAYDEL", category: "Settings", summary: "Deletes a layer and all objects on it.") { ed in
            guard let n = try await ed.getWord("Enter name of layer to delete"), let l = ed.doc.layer(named: n) else { throw CommandError.invalid("Layer not found.") }
            guard l.name != "0", l.name != ed.doc.currentLayer else { throw CommandError.invalid("Cannot delete layer 0 or the current layer.") }
            let ids = Set(ed.doc.entities.filter { $0.layer.caseInsensitiveCompare(l.name) == .orderedSame }.map(\.id) + ed.doc.elements.filter { $0.layer.caseInsensitiveCompare(l.name) == .orderedSame }.map(\.id))
            guard try await ed.getYesNo("Delete layer \"\(l.name)\" and its \(ids.count) object(s)?", defaultValue: false) else { return }
            ed.doc.remove(ids: ids)
            ed.doc.layers.removeAll { $0.name == l.name }
            ed.print("Layer \"\(l.name)\" deleted with \(ids.count) object(s).")
        },
        CommandDef("COLOR", aliases: ["COL", "COLOUR"], category: "Settings", summary: "Sets the color for new objects (CECOLOR).") { ed in
            guard let v = try await ed.getWord("Enter default object color [ByLayer/ByBlock/1-255/#RRGGBB]", defaultValue: ed.doc.variable("CECOLOR") ?? "ByLayer") else { return }
            if let e = SystemVariables.set("CECOLOR", v, ed) { throw CommandError.invalid(e) }
        },
        CommandDef("LINETYPE", aliases: ["LT", "-LINETYPE", "LTYPE"], category: "Settings", summary: "Lists, loads, creates and sets the current linetype.") { ed in
            while let k = try await ed.getKeyword("Enter an option", ["?", "Load", "File", "Create", "Set", "Export"]) {
                switch k {
                case "?": for l in ed.doc.linetypes { ed.print("\(l.name == ed.doc.variable("CELTYPE") ? "*" : " ") \(l.name): \(l.description)\(ed.doc.variable(LinFile.complexVariable(l.name)) != nil ? " (complex)" : "")") }
                case "Load":
                    // The basic set plus the bundled ISO / complex library (acadiso.lin equivalents).
                    let s = try await ed.getWord("Enter linetype(s) to load (* = all standard)", defaultValue: "*") ?? "*"
                    var n = 0
                    for lt in Linetype.standard where glob(s, lt.name) && ed.doc.linetype(lt.name) == nil { ed.doc.linetypes.append(lt); n += 1 }
                    n += LinFile.load(LinFile.standard.filter { glob(s, $0.name) }, into: &ed.doc).count
                    ed.print("\(n) linetype(s) loaded.")
                case "File":
                    // Linetypes from a .lin file (AutoCAD format, complex text/shape elements included).
                    guard let path = try await ed.getString("Enter .lin file name") , !path.isEmpty else { continue }
                    let defs = LinFile.parse(try LayerToolCommands.readFile(path))
                    guard !defs.isEmpty else { throw CommandError.invalid("No linetype definitions in \(path).") }
                    let s = try await ed.getWord("Enter linetype(s) to load (* = all)", defaultValue: "*") ?? "*"
                    let names = LinFile.load(defs.filter { glob(s, $0.name) }, into: &ed.doc, replace: true)
                    ed.print("\(names.count) linetype(s) loaded: \(names.joined(separator: ", "))")
                case "Export":
                    guard let path = try await ed.getString("Enter .lin file name to write"), !path.isEmpty else { continue }
                    let defs = ed.doc.linetypes.filter { !$0.pattern.isEmpty }.compactMap { LinFile.definition($0.name, doc: ed.doc) }
                    let url = try LayerToolCommands.writeFile(path, LinFile.write(defs))
                    ed.print("\(defs.count) linetype(s) written to \(url).")
                case "Create":
                    guard let name = try await ed.getWord("Enter name of linetype to create"), !name.isEmpty else { continue }
                    guard ed.doc.linetype(name) == nil else { ed.print("Linetype \(name) already exists."); continue }
                    guard let pat = try await ed.getWord("Enter pattern (dash,-gap,0=dot…) e.g. 12,-6") else { continue }
                    let vals = pat.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    guard !vals.isEmpty else { ed.print("Invalid pattern."); continue }
                    ed.doc.linetypes.append(Linetype(name: name, description: pat, pattern: vals))
                case "Set":
                    guard let v = try await ed.getWord("Specify linetype name or [ByLayer/ByBlock]", defaultValue: ed.doc.variable("CELTYPE") ?? "ByLayer") else { continue }
                    if let e = SystemVariables.set("CELTYPE", v, ed) { ed.print(e) }
                default: break
                }
            }
        },
        CommandDef("LWEIGHT", aliases: ["LW", "LINEWEIGHT"], category: "Settings", summary: "Sets the current lineweight and lineweight display.") { ed in
            ed.print("Current lineweight: \(ed.doc.variable("CELWEIGHT") ?? "ByLayer"), display \(ed.settings.lineweightDisplay ? "on" : "off")")
            guard let v = try await ed.getWord("Enter default lineweight in mm [ByLayer/Display]", defaultValue: ed.doc.variable("CELWEIGHT") ?? "ByLayer", keywords: ["ByLayer", "Display"]) else { return }
            if v == "Display" { ed.settings.lineweightDisplay.toggle(); ed.print("Lineweight display \(ed.settings.lineweightDisplay ? "on" : "off")."); return }
            if let e = SystemVariables.set("CELWEIGHT", v, ed) { throw CommandError.invalid(e) }
        },
        CommandDef("LTSCALE", aliases: ["LTS"], category: "Settings", summary: "Sets the global linetype scale factor.") { ed in
            guard let v = try await ed.getReal("Enter new linetype scale factor", defaultValue: Double(ed.doc.variable("LTSCALE") ?? "1") ?? 1).value, v > 0 else { throw CommandError.invalid("Requires a positive number.") }
            ed.doc.setVariable("LTSCALE", fmt(v))
            ed.print("Regenerating model.")
        },
        CommandDef("UNITS", aliases: ["UN", "-UNITS"], category: "Settings", summary: "Sets drawing units (mm, cm, m, in, ft) and optionally scales the drawing.") { ed in
            let names = ["Millimeters", "Centimeters", "MEters", "Inches", "Feet"]
            let cur = names.first { $0.lowercased() == ed.doc.units.rawValue } ?? "Millimeters"
            let k = try await ed.getKeyword("Enter drawing units", names, defaultValue: cur) ?? cur
            guard let u = Units(rawValue: k.lowercased()) else { return }
            if let p = try await ed.getInteger("Enter number of decimal places (LUPREC)", defaultValue: Int(ed.doc.variable("LUPREC") ?? "2")), (0...8).contains(p) { ed.doc.setVariable("LUPREC", "\(p)") }
            if u != ed.doc.units, !ed.doc.entities.isEmpty || !ed.doc.elements.isEmpty {
                if try await ed.getYesNo("Scale existing objects to the new units?", defaultValue: false) {
                    let f = ed.doc.units.mm / u.mm
                    let ids = ed.doc.allIDs
                    ed.transformObjects(ids, .scale(f, f), copy: false)
                    for i in ed.doc.elements.indices { ed.doc.elements[i].geometry = scaleSizes(ed.doc.elements[i].geometry, f) }
                    for i in ed.doc.levels.indices { ed.doc.levels[i].elevation *= f; ed.doc.levels[i].height *= f }
                    ed.settings.textHeight *= f; ed.settings.wallThickness *= f; ed.settings.wallHeight *= f; ed.settings.gridSpacing *= f; ed.settings.offsetDistance *= f
                }
            }
            ed.doc.units = u
            ed.print("Units: \(u.rawValue)")
        },
    ] }

    static func scaleSizes(_ g: BIMGeometry, _ f: Double) -> BIMGeometry {
        switch g {
        case .wall(var w): w.thickness *= f; w.height *= f; w.baseOffset *= f; return .wall(w)
        case .slab(var s): s.thickness *= f; s.topOffset *= f; return .slab(s)
        case .column(var c): c.width *= f; c.depth *= f; c.height *= f; c.baseOffset *= f; return .column(c)
        case .beam(var b): b.width *= f; b.depth *= f; b.topOffset *= f; return .beam(b)
        case .opening(var o): o.offset *= f; o.width *= f; o.height *= f; o.sill *= f; o.frameWidth *= f; return .opening(o)
        case .roof(var r): r.thickness *= f; r.overhang *= f; r.baseOffset *= f; return .roof(r)
        case .stair(var s): s.width *= f; s.totalRise *= f; s.treadDepth *= f; return .stair(s)
        case .railing(var r): r.height *= f; r.baseOffset *= f; return .railing(r)
        case .space(var s): s.height *= f; return .space(s)
        case .curtainWall(var c): c.height *= f; c.baseOffset *= f; c.gridU *= f; c.gridV *= f; c.mullionSize *= f; return .curtainWall(c)
        case .component(var c): c.size = c.size * f; c.baseOffset *= f; return .component(c)
        case .gridLine: return g
        }
    }

    static func renameLayer(_ doc: inout ArchiDocument, from old: String, to new: String) {
        guard let i = doc.layerIndex(old) else { return }
        let oldName = doc.layers[i].name
        doc.layers[i].name = new
        for j in doc.entities.indices where doc.entities[j].layer == oldName { doc.entities[j].layer = new }
        for j in doc.elements.indices where doc.elements[j].layer == oldName { doc.elements[j].layer = new }
        for k in doc.blocks.keys { for j in doc.blocks[k]!.entities.indices where doc.blocks[k]!.entities[j].layer == oldName { doc.blocks[k]!.entities[j].layer = new } }
        if doc.currentLayer == oldName { doc.currentLayer = new }
    }

    // MARK: - Drafting aids
    static var drafting: [CommandDef] { [
        CommandDef("SETVAR", aliases: ["SET"], category: "Settings", summary: "Lists or changes system variables.") { ed in
            guard let n = try await ed.getWord("Enter variable name or [?]") else { return }
            if n == "?" {
                let pat = try await ed.getWord("Enter variable(s) to list", defaultValue: "*") ?? "*"
                let names = Set(SystemVariables.known + SysVarCatalog.all.map(\.name) + Array(ed.doc.variables.keys)).filter { !$0.hasPrefix("LAYISO") && SettingsCommands.glob(pat, $0) }
                for k in names.sorted() {
                    let v = SystemVariables.get(k, ed) ?? ""
                    ed.print("\(k) = \(v.count > 60 ? String(v.prefix(57)) + "..." : v)\(SysVarCatalog.info(k)?.readOnly == true ? "  (read only)" : "")")
                }
                return
            }
            guard let v = try await ed.getWord("Enter new value for \(n.uppercased())", defaultValue: SystemVariables.get(n, ed)) else { return }
            if let e = SystemVariables.set(n, v, ed) { throw CommandError.invalid(e) }
            ed.print("\(n.uppercased()) = \(SystemVariables.get(n, ed) ?? v)")
        },
        CommandDef("ORTHO", category: "Settings", summary: "Constrains cursor movement to horizontal/vertical (F8).") { ed in
            let k = try await ed.getKeyword("Enter mode", ["ON", "OFF"], defaultValue: ed.settings.ortho ? "OFF" : "ON") ?? "ON"
            ed.settings.ortho = k == "ON"; ed.print("<Ortho \(ed.settings.ortho ? "on" : "off")>")
        },
        CommandDef("OSNAP", aliases: ["OS", "-OSNAP", "DDOSNAP"], category: "Settings", summary: "Sets running object snap modes (END,MID,CEN,NOD,QUA,INT,EXT,INS,PER,TAN,NEA,PAR, ON/OFF).") { ed in
            let cur = (ed.settings.snapModes.map(\.rawValue) + (ed.settings.geometricCenterSnap ? ["gcen"] : [])).sorted().joined(separator: ",")
            guard let s = try await ed.getWord("Enter list of object snap modes [?/ON/OFF]", defaultValue: cur) else { return }
            let map: [String: SnapKind] = ["END": .endpoint, "MID": .midpoint, "CEN": .center, "NOD": .node, "QUA": .quadrant, "INT": .intersection, "EXT": .extension,
                                           "INS": .insertion, "PER": .perpendicular, "TAN": .tangent, "NEA": .nearest, "PAR": .parallel, "GRI": .grid]
            switch s.uppercased() {
            case "?": ed.print("Running snaps (\(ed.settings.objectSnap ? "on" : "off")): \(cur)  OSMODE = \(SystemVariables.osmode(ed.settings))"); return
            case "ON": ed.settings.objectSnap = true
            case "OFF", "NON", "NONE": ed.settings.objectSnap = false
            default:
                var modes = Set<SnapKind>()
                var gcen = false
                for part in s.split(separator: ",") {
                    let p = part.trimmingCharacters(in: .whitespaces).uppercased()
                    if p.hasPrefix("GCE") || p == "GEOMETRICCENTER" { gcen = true; continue }
                    if let k = map[String(p.prefix(3))] ?? SnapKind(rawValue: p.lowercased()) { modes.insert(k) } else { throw CommandError.invalid("Unknown snap mode \(p).") }
                }
                ed.settings.snapModes = modes; ed.settings.geometricCenterSnap = gcen; ed.settings.objectSnap = !modes.isEmpty || gcen
            }
            ed.print("OSMODE = \(SystemVariables.osmode(ed.settings))")
        },
        CommandDef("GRIDDISPLAY", aliases: ["DGRID", "F7"], category: "Settings", summary: "Shows/hides the drawing grid or sets its spacing.") { ed in
            guard let v = try await ed.getWord("Specify grid spacing or [ON/OFF]", defaultValue: fmt(ed.settings.gridSpacing), keywords: ["ON", "OFF"]) else { return }
            switch v { case "ON": ed.settings.showGrid = true
            case "OFF": ed.settings.showGrid = false
            default:
                guard let d = InputParser.parseNumber(v), d > 0 else { throw CommandError.invalid("Requires a positive spacing, ON or OFF.") }
                ed.settings.gridSpacing = d; ed.settings.showGrid = true }
        },
        CommandDef("SNAP", aliases: ["SN"], category: "Settings", summary: "Turns grid snap on/off or sets the snap spacing (F9).") { ed in
            guard let v = try await ed.getWord("Specify snap spacing or [ON/OFF]", defaultValue: ed.settings.gridSnap ? "OFF" : "ON", keywords: ["ON", "OFF"]) else { return }
            switch v { case "ON": ed.settings.gridSnap = true
            case "OFF": ed.settings.gridSnap = false
            default:
                guard let d = InputParser.parseNumber(v), d > 0 else { throw CommandError.invalid("Requires a positive spacing, ON or OFF.") }
                ed.settings.gridSpacing = d; ed.settings.gridSnap = true }
            ed.print("<Snap \(ed.settings.gridSnap ? "on" : "off")>, spacing \(fmt(ed.settings.gridSpacing))")
        },
        CommandDef("DSETTINGS", aliases: ["DS", "SE", "DDRMODES"], category: "Settings", summary: "Opens the drafting settings (snap, grid, polar, object snap).", modifies: false) { ed in
            ed.host?.perform(.showPanel("Drafting Settings"), editor: ed)
            let s = ed.settings
            ed.print("Snap \(s.gridSnap ? "on" : "off") / Grid \(s.showGrid ? "on" : "off") spacing \(fmt(s.gridSpacing)); Ortho \(s.ortho ? "on" : "off"); Polar \(s.polarTracking ? "on" : "off") every \(fmt(s.polarIncrement))°; OSNAP \(s.objectSnap ? "on" : "off") (OSMODE \(SystemVariables.osmode(s)))")
        },
        CommandDef("LIMITS", category: "Settings", summary: "Sets the drawing limits (LIMMIN/LIMMAX).") { ed in
            let lo = try await ed.getPoint("Specify lower left corner", keywords: ["ON", "OFF"])
            switch lo {
            case .keyword(let k): ed.doc.setVariable("LIMCHECK", k == "ON" ? "1" : "0"); return
            case .point(let p):
                let q = try await ed.requirePoint("Specify upper right corner", base: p)
                let b = BBox2(points: [p, q])
                ed.doc.setVariable("LIMMIN", b.min.description); ed.doc.setVariable("LIMMAX", b.max.description)
            default: return
            }
        },
    ] }

    // MARK: - PURGE / RENAME / AUDIT
    static func purge(_ doc: inout ArchiDocument, kinds: Set<String>) -> [String] {
        var removed: [String] = []
        if kinds.contains("Blocks") {
            while true {
                var used = Set<String>()
                // References to visibility/dynamic variants keep their base block (it regenerates the variants).
                func scan(_ es: [Entity]) {
                    for e in es {
                        guard case .insert(let i) = e.geometry else { continue }
                        used.insert(i.block)
                        if let b = e.props["visBase"] { used.insert(b) }
                        if let b = e.props[DynamicBlocks.baseProp] { used.insert(b) }
                    }
                }
                scan(doc.entities); doc.layouts.forEach { scan($0.entities) }; doc.blocks.values.forEach { scan($0.entities) }
                for el in doc.elements { if case .component(let c) = el.geometry, let b = c.block { used.insert(b) } }
                let unused = doc.blocks.keys.filter { !used.contains($0) }
                if unused.isEmpty { break }
                for k in unused { doc.blocks.removeValue(forKey: k); removed.append("Block \"\(k)\"") }
            }
        }
        if kinds.contains("Layers") {
            let used = usedLayers(doc)
            let keep = Set(["0", doc.currentLayer.lowercased(), "defpoints"])
            let gone = doc.layers.filter { !used.contains($0.name.lowercased()) && !keep.contains($0.name.lowercased()) && $0.name != doc.currentLayer }
            doc.layers.removeAll { l in gone.contains { $0.name == l.name } }
            removed += gone.map { "Layer \"\($0.name)\"" }
        }
        if kinds.contains("LTypes") {
            var used = Set(doc.layers.map { $0.linetype.lowercased() } + doc.entities.compactMap { $0.linetype?.lowercased() })
            for b in doc.blocks.values { for e in b.entities { if let l = e.linetype { used.insert(l.lowercased()) } } }
            used.insert("continuous"); if let c = doc.variable("CELTYPE") { used.insert(c.lowercased()) }
            let gone = doc.linetypes.filter { !used.contains($0.name.lowercased()) }
            doc.linetypes.removeAll { l in gone.contains { $0.name == l.name } }
            removed += gone.map { "Linetype \"\($0.name)\"" }
        }
        if kinds.contains("Styles") {
            var used = Set(["standard", (doc.variable("TEXTSTYLE") ?? "Standard").lowercased()])
            func scan(_ es: [Entity]) { for e in es { if case .text(let t) = e.geometry { used.insert(t.style.lowercased()) } } }
            scan(doc.entities); doc.blocks.values.forEach { scan($0.entities) }; doc.layouts.forEach { scan($0.entities) }
            let gone = doc.textStyles.filter { !used.contains($0.name.lowercased()) }
            doc.textStyles.removeAll { s in gone.contains { $0.name == s.name } }
            removed += gone.map { "Text style \"\($0.name)\"" }
        }
        if kinds.contains("Dimstyles") {
            var used = Set(["Standard", doc.currentDimStyle])
            func scan(_ es: [Entity]) { for e in es { if case .dimension(let d) = e.geometry { used.insert(d.style) } } }
            scan(doc.entities); doc.blocks.values.forEach { scan($0.entities) }; doc.layouts.forEach { scan($0.entities) }
            let gone = doc.dimStyles.filter { !used.contains($0.name) }
            doc.dimStyles.removeAll { s in gone.contains { $0.name == s.name } }
            removed += gone.map { "Dimension style \"\($0.name)\"" }
        }
        return removed
    }

    /// Checks the document for inconsistencies; with `fix` repairs them. Returns the problems found.
    public static func audit(_ doc: inout ArchiDocument, fix: Bool) -> [String] {
        var issues: [String] = []
        // Duplicate IDs
        var seen = Set<EntityID>()
        let maxID = (doc.allIDs.max() ?? 0)
        var next = max(doc.nextID, maxID + 1)
        for i in doc.entities.indices {
            if seen.contains(doc.entities[i].id) { issues.append("Duplicate ID #\(doc.entities[i].id) (entity)"); if fix { doc.entities[i].id = next; next += 1 } }
            seen.insert(doc.entities[i].id)
        }
        for i in doc.elements.indices {
            if seen.contains(doc.elements[i].id) { issues.append("Duplicate ID #\(doc.elements[i].id) (element)"); if fix { doc.elements[i].id = next; next += 1 } }
            seen.insert(doc.elements[i].id)
        }
        if doc.nextID <= maxID { issues.append("Next ID counter too low (\(doc.nextID) ≤ \(maxID))") }
        if fix { doc.nextID = max(next, (doc.allIDs.max() ?? 0) + 1) }
        // Layers
        var missing = Set<String>()
        for e in doc.entities where doc.layer(named: e.layer) == nil { missing.insert(e.layer) }
        for e in doc.elements where doc.layer(named: e.layer) == nil { missing.insert(e.layer) }
        for m in missing.sorted() { issues.append("Missing layer \"\(m)\""); if fix { doc.ensureLayer(m) } }
        if doc.layer(named: doc.currentLayer) == nil { issues.append("Current layer missing"); if fix { doc.ensureLayer("0"); doc.currentLayer = "0" } }
        // Levels
        if doc.levels.isEmpty { issues.append("No levels"); if fix { doc.levels = [Level(id: 0, name: "Ground Floor", elevation: 0)] } }
        if doc.level(doc.currentLevel) == nil, let f = doc.levels.first { issues.append("Current level missing"); if fix { doc.currentLevel = f.id } }
        for i in doc.elements.indices where doc.level(doc.elements[i].level) == nil {
            issues.append("Element #\(doc.elements[i].id) on missing level \(doc.elements[i].level)"); if fix, let f = doc.levels.first { doc.elements[i].level = f.id }
        }
        // Openings
        var dangling = Set<EntityID>()
        for i in doc.elements.indices {
            guard case .opening(var o) = doc.elements[i].geometry else { continue }
            guard let h = doc.element(o.hostWall), case .wall(let w) = h.geometry else { issues.append("Opening #\(doc.elements[i].id) has no host wall"); dangling.insert(doc.elements[i].id); continue }
            let lo = min(o.width / 2, w.length / 2), hi = max(w.length - o.width / 2, w.length / 2)
            if o.offset < lo - 1e-6 || o.offset > hi + 1e-6 { issues.append("Opening #\(doc.elements[i].id) lies outside its wall"); if fix { o.offset = max(lo, min(hi, o.offset)); doc.elements[i].geometry = .opening(o) } }
            if h.level != doc.elements[i].level { issues.append("Opening #\(doc.elements[i].id) level differs from its host"); if fix { doc.elements[i].level = h.level } }
        }
        if fix { doc.elements.removeAll { dangling.contains($0.id) } }
        // Block references
        var badInserts = Set<EntityID>()
        for e in doc.entities { if case .insert(let i) = e.geometry, doc.blocks[i.block] == nil { issues.append("Insert #\(e.id) references missing block \"\(i.block)\""); badInserts.insert(e.id) } }
        if fix { doc.entities.removeAll { badInserts.contains($0.id) } }
        // Invalid geometry
        var bad = Set<EntityID>()
        for e in doc.entities {
            let b = GeometryOps.bounds(e.geometry, doc: doc)
            if !b.isEmpty && !(b.min.x.isFinite && b.min.y.isFinite && b.max.x.isFinite && b.max.y.isFinite) { issues.append("Entity #\(e.id) has invalid coordinates"); bad.insert(e.id) }
        }
        if fix { doc.entities.removeAll { bad.contains($0.id) } }
        if doc.dimStyles.isEmpty { issues.append("No dimension styles"); if fix { doc.dimStyles = [DimStyle(name: "Standard")]; doc.currentDimStyle = "Standard" } }
        else if !doc.dimStyles.contains(where: { $0.name == doc.currentDimStyle }) { issues.append("Current dimension style missing"); if fix { doc.currentDimStyle = doc.dimStyles[0].name } }
        return issues
    }

    static var housekeeping: [CommandDef] { [
        CommandDef("PURGE", aliases: ["PU", "-PURGE"], category: "Settings", summary: "Removes unused blocks, layers, linetypes, text styles and dimension styles.") { ed in
            let k = try await ed.getKeyword("Enter type of unused objects to purge", ["Blocks", "Layers", "LTypes", "Styles", "Dimstyles", "All"], defaultValue: "All") ?? "All"
            let kinds: Set<String> = k == "All" ? ["Blocks", "Layers", "LTypes", "Styles", "Dimstyles"] : [k]
            var doc = ed.doc
            let removed = purge(&doc, kinds: kinds)
            ed.doc = doc
            for r in removed { ed.print("Deleting \(r).") }
            ed.print(removed.isEmpty ? "No unreferenced objects found." : "\(removed.count) item(s) purged.")
        },
        CommandDef("RENAME", aliases: ["REN", "-RENAME"], category: "Settings", summary: "Renames blocks, layers, linetypes, text styles, dimension styles, levels, views and wall types.") { ed in
            let k = try await ed.getKeyword("Enter object type to rename", ["Block", "Layer", "LType", "Style", "Dimstyle", "LEVel", "View", "WallType"], defaultValue: "Layer") ?? "Layer"
            guard let old = try await ed.getWord("Enter old name"), let new = try await ed.getWord("Enter new name"), !new.isEmpty else { return }
            var d = ed.doc
            switch k {
            case "Block":
                guard let b = d.blocks[old] else { throw CommandError.invalid("Block \(old) not found.") }
                guard d.blocks[new] == nil else { throw CommandError.invalid("Block \(new) already exists.") }
                d.blocks.removeValue(forKey: old); var nb = b; nb.name = new; d.blocks[new] = nb
                func fixInserts(_ es: inout [Entity]) { for i in es.indices { if case .insert(var ins) = es[i].geometry, ins.block == old { ins.block = new; es[i].geometry = .insert(ins) } } }
                fixInserts(&d.entities)
                for key in d.blocks.keys { fixInserts(&d.blocks[key]!.entities) }
                for i in d.layouts.indices { fixInserts(&d.layouts[i].entities) }
            case "Layer":
                guard d.layer(named: old) != nil else { throw CommandError.invalid("Layer \(old) not found.") }
                guard d.layer(named: new) == nil else { throw CommandError.invalid("Layer \(new) already exists.") }
                guard old != "0" else { throw CommandError.invalid("Layer 0 cannot be renamed.") }
                renameLayer(&d, from: old, to: new)
            case "LType":
                guard let i = d.linetypes.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame }) else { throw CommandError.invalid("Linetype \(old) not found.") }
                let o = d.linetypes[i].name; d.linetypes[i].name = new
                for j in d.layers.indices where d.layers[j].linetype == o { d.layers[j].linetype = new }
                for j in d.entities.indices where d.entities[j].linetype == o { d.entities[j].linetype = new }
            case "Style":
                guard let i = d.textStyles.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame }) else { throw CommandError.invalid("Text style \(old) not found.") }
                let o = d.textStyles[i].name; d.textStyles[i].name = new
                for j in d.entities.indices { if case .text(var t) = d.entities[j].geometry, t.style == o { t.style = new; d.entities[j].geometry = .text(t) } }
                if d.variable("TEXTSTYLE") == o { d.setVariable("TEXTSTYLE", new) }
            case "Dimstyle":
                guard let i = d.dimStyles.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame }) else { throw CommandError.invalid("Dimension style \(old) not found.") }
                let o = d.dimStyles[i].name; d.dimStyles[i].name = new
                for j in d.entities.indices { if case .dimension(var dm) = d.entities[j].geometry, dm.style == o { dm.style = new; d.entities[j].geometry = .dimension(dm) } }
                if d.currentDimStyle == o { d.currentDimStyle = new }
            case "LEVel":
                guard let i = d.levels.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame }) else { throw CommandError.invalid("Level \(old) not found.") }
                d.levels[i].name = new
            case "View":
                guard let i = d.namedViews.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame }) else { throw CommandError.invalid("View \(old) not found.") }
                d.namedViews[i].name = new
            case "WallType":
                guard let i = d.wallTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(old) == .orderedSame }) else { throw CommandError.invalid("Wall type \(old) not found.") }
                let o = d.wallTypes[i].name; d.wallTypes[i].name = new
                for j in d.elements.indices { if case .wall(var w) = d.elements[j].geometry, w.wallType == o { w.wallType = new; d.elements[j].geometry = .wall(w) } }
            default: return
            }
            ed.doc = d
            ed.print("\(k) \"\(old)\" renamed to \"\(new)\".")
        },
        CommandDef("AUDIT", category: "Settings", summary: "Checks the drawing for errors (duplicate IDs, dangling openings, missing layers/blocks) and fixes them.") { ed in
            let fix = try await ed.getYesNo("Fix any errors detected?", defaultValue: true)
            var d = ed.doc
            let issues = audit(&d, fix: fix)
            if fix { ed.doc = d }
            for i in issues { ed.print("  \(i)") }
            ed.print("Total errors found \(issues.count), fixed \(fix ? issues.count : 0)")
        },
    ] }

    /// System variables typed as commands (e.g. "OSMODE 3", "TEXTSIZE 350").
    static var variableCommands: [CommandDef] {
        let skip = Set(["LTSCALE", "DIMSTYLE", "TEXTSTYLE"])
        return (SystemVariables.known + SystemVariables.stored).filter { !skip.contains($0) }.map { name in
            CommandDef(name, category: "Settings", summary: "System variable \(name).") { ed in
                guard let v = try await ed.getWord("Enter new value for \(name)", defaultValue: SystemVariables.get(name, ed)) else { return }
                if let e = SystemVariables.set(name, v, ed) { throw CommandError.invalid(e) }
            }
        }
    }
}
