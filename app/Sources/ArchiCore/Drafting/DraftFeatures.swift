// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// MARK: - Macro buttons (CMD-041)

/// A custom toolbar button that runs a macro string (AutoCAD CUI style: "^C^CLINE;\\;" — ";" or space = Enter,
/// "\\" = pause for user input, leading ^C^C cancels the running command).
public struct MacroButton: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var macro: String
    /// SF Symbol name shown on the button.
    public var icon: String
    public var tooltip: String
    /// Toolbar/panel the button belongs to.
    public var group: String
    public init(name: String, macro: String, icon: String = "command", tooltip: String = "", group: String = "Custom") {
        self.name = name; self.macro = macro; self.icon = icon; self.tooltip = tooltip; self.group = group
    }
    enum K: String, CodingKey { case name, macro, icon, tooltip, group }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name)
        macro = try c.decodeIfPresent(String.self, forKey: .macro) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "command"
        tooltip = try c.decodeIfPresent(String.self, forKey: .tooltip) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Custom"
    }
}

/// Macro buttons saved in the drawing (variable MACROBUTTONS, JSON) and in the user profile
/// (~/Library/Application Support/Oanarina Archi Tool/macrobuttons.json). Drawing buttons override user buttons of the same name.
public enum MacroButtons {
    public static let variable = "MACROBUTTONS"

    public static func document(_ doc: ArchiDocument) -> [MacroButton] {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MacroButton].self, from: d)) ?? []
    }
    public static func setDocument(_ list: [MacroButton], _ doc: inout ArchiDocument) {
        if list.isEmpty { doc.variables[variable] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(list), let s = String(data: d, encoding: .utf8) { doc.setVariable(variable, s) }
    }

    /// User profile file (nil disables it, e.g. in tests).
    public static var userFile: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Oanarina Archi Tool/macrobuttons.json")

    public static func user() -> [MacroButton] {
        guard let u = userFile, let d = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([MacroButton].self, from: d)) ?? []
    }
    @discardableResult
    public static func saveUser(_ list: [MacroButton]) -> Bool {
        guard let u = userFile else { return false }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let d = try? enc.encode(list) else { return false }
        return (try? d.write(to: u, options: .atomic)) != nil
    }

    /// Buttons to show: user buttons, then drawing buttons (replacing user buttons with the same name).
    public static func all(_ doc: ArchiDocument) -> [MacroButton] {
        var out = user()
        for b in document(doc) {
            if let i = out.firstIndex(where: { $0.name.caseInsensitiveCompare(b.name) == .orderedSame }) { out[i] = b } else { out.append(b) }
        }
        return out
    }

    /// Checks a macro: it must name a known command (or alias / user alias) after any ^C^C prefix. Returns an error message.
    @MainActor public static func validate(_ macro: String, registry: CommandRegistry = .shared, doc: ArchiDocument) -> String? {
        let toks = UserAliases.macroTokens(macro).filter { !$0.isEmpty && $0 != MacroPause.mark }
        guard var first = toks.first else { return "The macro is empty." }
        if first.hasPrefix("_") { first.removeFirst() }
        if first.hasPrefix("'") { first.removeFirst() }
        registry.ensureBuiltins()
        if registry.lookup(first) != nil || UserAliases.expansion(for: first, doc: doc) != nil || SysVarCatalog.info(first) != nil { return nil }
        return "Unknown command \"\(first.uppercased())\" in macro."
    }
}

// MARK: - Helix (DRW-055)

public enum Helix {
    public static let prop = "helix"

    /// Points of a helix (plan projection) and their elevations. `turns` > 0, radii ≥ 0, ccw = counter-clockwise twist.
    public static func points(center c: Vec2, baseRadius r0: Double, topRadius r1: Double, turns: Double, height: Double,
                              startAngle a0: Double = 0, ccw: Bool = true, segmentsPerTurn: Int = 72) -> (plan: [Vec2], z: [Double]) {
        let n = max(2, Int((turns * Double(segmentsPerTurn)).rounded(.up)))
        var plan: [Vec2] = [], z: [Double] = []
        for k in 0...n {
            let t = Double(k) / Double(n)
            let r = r0 + (r1 - r0) * t
            let a = a0 + (ccw ? 1 : -1) * 2 * .pi * turns * t
            plan.append(c + Vec2.polar(r, a)); z.append(height * t)
        }
        return (plan, z)
    }

    /// Helix entity: an open polyline (plan) with per-vertex elevations ("vertexZ") and its defining parameters.
    public static func entity(center c: Vec2, baseRadius r0: Double, topRadius r1: Double, turns: Double, height: Double,
                              startAngle a0: Double = 0, ccw: Bool = true, layer: String) -> Entity {
        let (plan, z) = points(center: c, baseRadius: r0, topRadius: r1, turns: turns, height: height, startAngle: a0, ccw: ccw)
        var e = Entity(layer: layer, geometry: .polyline(PolylineGeom(points: plan, closed: false)))
        e.props["vertexZ"] = z.map { fmt($0, 6) }.joined(separator: ",")
        e.props[prop] = [c.x, c.y, r0, r1, turns, height, a0].map { fmt($0, 9) }.joined(separator: ",") + (ccw ? ",ccw" : ",cw")
        return e
    }

    /// 3D length of a helix (sum of 3D chords of its polyline).
    public static func length(plan: [Vec2], z: [Double]) -> Double {
        guard plan.count == z.count, plan.count > 1 else { return 0 }
        var s = 0.0
        for i in 1..<plan.count { let d = plan[i].distance(to: plan[i - 1]), dz = z[i] - z[i - 1]; s += (d * d + dz * dz).squareRoot() }
        return s
    }
}

// MARK: - Block tables / lookup (BLK-025, BLK-026)

/// Named parameter sets of a dynamic block (BTABLE): variable "BTABLE:<block>" holds rows "Name|Width=1200;Count=3"
/// separated by newlines. A reference set to a row gets those values (prop "dynConfig" = row name).
public enum BlockTables {
    public static let configProp = "dynConfig"
    public static func key(_ block: String) -> String { "BTABLE:" + block }

    public struct Row: Equatable { public var name: String; public var values: [String: Double] }

    public static func rows(_ block: String, _ doc: ArchiDocument) -> [Row] {
        (doc.variable(key(block)) ?? "").split(separator: "\n").compactMap { line in
            let f = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard f.count == 2, !f[0].isEmpty else { return nil }
            return Row(name: f[0], values: DynamicBlocks.values([DynamicBlocks.valuesProp: f[1]]))
        }
    }
    public static func setRows(_ block: String, _ rows: [Row], _ doc: inout ArchiDocument) {
        if rows.isEmpty { doc.variables[key(block).uppercased()] = nil; return }
        doc.setVariable(key(block), rows.map { "\($0.name)|\(DynamicBlocks.valuesText($0.values))" }.joined(separator: "\n"))
    }

    /// Applies a row to a block reference. Returns false if the block or row is unknown.
    @discardableResult
    public static func apply(row name: String, toInsert i: Int, _ doc: inout ArchiDocument) -> Bool {
        guard doc.entities.indices.contains(i), case .insert(let ins) = doc.entities[i].geometry else { return false }
        let block = doc.entities[i].props[DynamicBlocks.baseProp] ?? ins.block
        guard let r = rows(block, doc).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        guard DynamicBlocks.apply(r.values, toInsert: i, &doc) else { return false }
        doc.entities[i].props[configProp] = r.name
        return true
    }
}

// MARK: - Bullets and numbering (ANN-005)

public enum TextLists {
    public enum Style: String, CaseIterable { case bullet, number, letter, upperLetter, off }

    static let prefixPattern = try! NSRegularExpression(pattern: "^(•\\t|• |[0-9]+\\.\\t|[0-9]+\\. |[a-zA-Z]\\.\\t|[a-zA-Z]\\. )")

    /// Removes a list marker from the start of a line.
    public static func strip(_ line: String) -> String {
        let r = NSRange(line.startIndex..., in: line)
        guard let m = prefixPattern.firstMatch(in: line, range: r), let rr = Range(m.range, in: line) else { return line }
        return String(line[rr.upperBound...])
    }

    /// Paragraphs of the text with list markers applied (empty lines are left unnumbered and restart nothing).
    public static func apply(_ content: String, style: Style, start: Int = 1) -> String {
        let usesP = content.contains("\\P")
        let lines = content.replacingOccurrences(of: "\\P", with: "\n").components(separatedBy: "\n")
        var n = start
        let out: [String] = lines.map { l in
            let body = strip(l)
            guard !body.trimmingCharacters(in: .whitespaces).isEmpty, style != .off else { return body }
            defer { n += 1 }
            switch style {
            case .bullet: return "• " + body
            case .number: return "\(n). " + body
            case .letter, .upperLetter:
                var k = n - 1, s = ""
                repeat { s = String(UnicodeScalar(UInt8(97 + k % 26))) + s; k = k / 26 - 1 } while k >= 0
                return (style == .upperLetter ? s.uppercased() : s) + ". " + body
            case .off: return body
            }
        }
        return out.joined(separator: usesP ? "\\P" : "\n")
    }
}

// MARK: - Colour books (LAY-030)

/// Named open colour palettes (no proprietary colour systems): CSS/SVG named colours, an Archi architectural palette
/// and a greyscale ramp. Entities coloured from a book keep the reference in prop "colorBook" ("Book$Name").
public enum ColorBooks {
    public struct Entry: Equatable { public var name: String; public var r: UInt8, g: UInt8, b: UInt8 }
    public static let prop = "colorBook"

    public static let books: [String: [Entry]] = {
        func e(_ n: String, _ hex: UInt32) -> Entry { Entry(name: n, r: UInt8(hex >> 16 & 255), g: UInt8(hex >> 8 & 255), b: UInt8(hex & 255)) }
        var b: [String: [Entry]] = [:]
        b["Web Named"] = [e("Black", 0x000000), e("White", 0xFFFFFF), e("Red", 0xFF0000), e("Lime", 0x00FF00), e("Blue", 0x0000FF),
                          e("Yellow", 0xFFFF00), e("Cyan", 0x00FFFF), e("Magenta", 0xFF00FF), e("Silver", 0xC0C0C0), e("Gray", 0x808080),
                          e("Maroon", 0x800000), e("Olive", 0x808000), e("Green", 0x008000), e("Purple", 0x800080), e("Teal", 0x008080),
                          e("Navy", 0x000080), e("Orange", 0xFFA500), e("Brown", 0xA52A2A), e("Tan", 0xD2B48C), e("Beige", 0xF5F5DC),
                          e("Khaki", 0xF0E68C), e("Coral", 0xFF7F50), e("Salmon", 0xFA8072), e("Gold", 0xFFD700), e("Chocolate", 0xD2691E),
                          e("Sienna", 0xA0522D), e("Peru", 0xCD853F), e("ForestGreen", 0x228B22), e("OliveDrab", 0x6B8E23), e("SeaGreen", 0x2E8B57),
                          e("SteelBlue", 0x4682B4), e("SlateGray", 0x708090), e("DarkSlateGray", 0x2F4F4F), e("Ivory", 0xFFFFF0), e("Linen", 0xFAF0E6)]
        b["Archi Materials"] = [e("Concrete", 0xA6A6A1), e("Brick", 0xA0522D), e("Terracotta", 0xC56A3F), e("Sandstone", 0xD8C49A),
                                e("Limestone", 0xE3DCC6), e("Granite", 0x7D7B78), e("Slate", 0x4F5559), e("Oak", 0xB88A55), e("Walnut", 0x6B4A2E),
                                e("Pine", 0xDDB779), e("Steel", 0x8A9299), e("Zinc", 0xB4BCC2), e("Copper", 0xB87333), e("Glass", 0xA9CCE3),
                                e("Plaster", 0xF2EFE8), e("Grass", 0x6C9A3B), e("Water", 0x4A90C2), e("Asphalt", 0x3C3C3C), e("Gravel", 0x9C9488)]
        b["Greyscale"] = (0...10).map { k in let v = UInt32(255 * k / 10); return e("Grey \(k * 10)%", v << 16 | v << 8 | v) }
        return b
    }()

    public static var names: [String] { books.keys.sorted() }

    /// "Book$Colour" (case-insensitive) → entry.
    public static func lookup(_ ref: String) -> (book: String, entry: Entry)? {
        let f = ref.split(separator: "$", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count == 2, let bk = books.keys.first(where: { $0.caseInsensitiveCompare(f[0]) == .orderedSame }),
              let en = books[bk]?.first(where: { $0.name.caseInsensitiveCompare(f[1]) == .orderedSame }) else { return nil }
        return (bk, en)
    }
    public static func color(_ e: Entry) -> ColorRef { .rgb(e.r, e.g, e.b) }
}

// MARK: - System variable monitor (CMD-037)

public enum SysVarMonitor {
    public static let listVariable = "SYSMONVARS", notifyVariable = "SYSMONNOTIFY"

    public static func watched(_ doc: ArchiDocument) -> [String] {
        (doc.variable(listVariable) ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
    }
    public static func setWatched(_ names: [String], _ doc: inout ArchiDocument) {
        var seen = Set<String>(), out: [String] = []
        for n in names.map({ $0.uppercased() }) where seen.insert(n).inserted { out.append(n) }
        if out.isEmpty { doc.variables[listVariable] = nil } else { doc.setVariable(listVariable, out.joined(separator: ";")) }
    }

    /// Changes of monitored variables between two document states: (name, old, new).
    public static func changes(from a: ArchiDocument, to b: ArchiDocument) -> [(name: String, old: String, new: String)] {
        let names = Set(watched(a) + watched(b))
        return names.sorted().compactMap { n in
            let o = a.variable(n) ?? SysVarCatalog.info(n)?.defaultValue ?? "", v = b.variable(n) ?? SysVarCatalog.info(n)?.defaultValue ?? ""
            return o == v ? nil : (n, o, v)
        }
    }
}

// MARK: - Block clipping (BLK-031)

/// Clip boundaries of block references (XCLIP): prop "xclip" = boundary in the reference's own (block) coordinates
/// "x,y;x,y;…", prop "xclipOff" = "1" to show the whole block while keeping the boundary.
public enum BlockClip {
    public static let prop = "xclip", offProp = "xclipOff"

    public static func boundary(_ e: Entity) -> [Vec2]? {
        guard case .insert(let ins) = e.geometry, let s = e.props[prop] else { return nil }
        let pts = s.split(separator: ";").compactMap { p -> Vec2? in
            let v = p.split(separator: ",").compactMap { Double($0) }
            return v.count == 2 ? Vec2(v[0], v[1]) : nil
        }
        guard pts.count >= 3 else { return nil }
        return pts.map(ins.transform.apply)
    }

    public static func setBoundary(_ world: [Vec2]?, on e: inout Entity) {
        guard case .insert(let ins) = e.geometry else { return }
        guard let w = world, w.count >= 3 else { e.props[prop] = nil; e.props[offProp] = nil; return }
        let inv = ins.transform.inverted
        e.props[prop] = w.map { let p = inv.apply($0); return "\(fmt(p.x, 9)),\(fmt(p.y, 9))" }.joined(separator: ";")
    }

    public static func active(_ e: Entity) -> Bool { e.props[prop] != nil && e.props[offProp] != "1" }
}

// MARK: - Dimension extras: tolerances, alternate units, inspection (ANN-040, ANN-039, ANN-036)

public enum DimExtras {
    /// "sym:0.1", "dev:0.2,0.1" (upper, lower), "limits:0.2,0.1", "basic".
    public static let toleranceProp = "dimTol"
    /// "factor,decimals[,suffix[,prefix]]", e.g. "0.0393700787,2,\"" for inches after millimetres.
    public static let alternateProp = "dimAlt"
    /// "round|angular|none;label;rate", e.g. "round;A;100%".
    public static let inspectProp = "dimInspect"

    public static func has(_ e: Entity) -> Bool {
        e.props[toleranceProp] != nil || e.props[alternateProp] != nil || e.props[inspectProp] != nil
    }

    static func num(_ v: Double, _ dec: Int) -> String { DimensionRenderer.number(v, decimals: dec) }

    /// Displayed text with tolerance and alternate units (basic tolerances and inspection frames are drawn around it).
    public static func text(_ d: DimensionGeom, style: DimStyle, props: [String: String]) -> String {
        let m = DimensionRenderer.measurement(d)
        let isAngle = d.kind == .angular
        let value = isAngle ? deg(m) : m * style.linearScale
        var main = DimensionRenderer.formatted(d, style: style)
        if let tol = props[toleranceProp] {
            let parts = tol.split(separator: ":", maxSplits: 1).map(String.init)
            let vals = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } : []
            let dec = style.decimals + 1
            switch parts[0].lowercased() {
            case "sym", "symmetric": if let t = vals.first { main += "±" + num(abs(t), dec) }
            case "dev", "deviation":
                let up = vals.first ?? 0, lo = vals.count > 1 ? vals[1] : up
                main += " +" + num(abs(up), dec) + "/-" + num(abs(lo), dec)
            case "limits", "lim":
                let up = vals.first ?? 0, lo = vals.count > 1 ? vals[1] : up
                let core = value
                main = style.prefix + num(core + abs(up), style.decimals) + "\n" + num(core - abs(lo), style.decimals) + style.suffix
            default: break
            }
        }
        if let alt = props[alternateProp], !isAngle {
            let f = alt.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            let factor = f.first.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? (1 / 25.4)
            let dec = f.count > 1 ? Int(f[1].trimmingCharacters(in: .whitespaces)) ?? 2 : 2
            let suffix = f.count > 2 ? f[2] : "", prefix = f.count > 3 ? f[3] : ""
            var altCore = num(m * style.linearScale * factor, dec)
            switch d.kind { case .radius: altCore = "R" + altCore; case .diameter: altCore = "Ø" + altCore; default: break }
            main += " [" + prefix + altCore + suffix + "]"
        }
        if let ins = props[inspectProp] {
            let f = ins.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            let label = f.count > 1 ? f[1] : "", rate = f.count > 2 ? f[2] : ""
            main = [label, main, rate].filter { !$0.isEmpty }.joined(separator: " | ")
        }
        return main
    }

    /// Frame shape around the dimension text: basic tolerance → box, inspection → round / angular / none.
    public static func frame(_ props: [String: String]) -> String? {
        if let ins = props[inspectProp] {
            let s = ins.split(separator: ";", omittingEmptySubsequences: false).first.map { $0.lowercased() } ?? "round"
            return s == "none" ? nil : (s == "angular" ? "angular" : "round")
        }
        if props[toleranceProp]?.lowercased().hasPrefix("basic") == true { return "box" }
        return nil
    }
}
