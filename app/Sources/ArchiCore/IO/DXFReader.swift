// Oanarina Archi Tool — GPL-3.0-or-later
// ASCII DXF reader. Group-code semantics follow the AutoCAD DXF reference; hatch edge conventions
// were cross-checked against LibreCAD's libdxfrw / rs_filterdxfrw (GPL-2.0-or-later, © LibreCAD team).
import Foundation

public enum DXFError: Error, LocalizedError, Equatable {
    case notDXF
    case binaryUnsupported
    public var errorDescription: String? {
        switch self {
        case .notDXF: return "The file is not an ASCII DXF drawing."
        case .binaryUnsupported: return "Binary DXF files are not supported; save the drawing as ASCII DXF."
        }
    }
}

/// One group code / value pair.
struct DXFPair {
    let code: Int
    let value: String
    var trimmed: String { value.trimmingCharacters(in: .whitespaces) }
    var double: Double { Double(trimmed) ?? 0 }
    var int: Int { Int(trimmed) ?? Int(Double(trimmed) ?? 0) }
}

/// A DXF object: its type (group 0) and the pairs that follow it.
struct DXFRecord {
    var type: String
    var pairs: [DXFPair]
    func first(_ code: Int) -> DXFPair? { pairs.first { $0.code == code } }
    func s(_ code: Int) -> String? { first(code)?.value }
    func d(_ code: Int) -> Double? { first(code)?.double }
    func i(_ code: Int) -> Int? { first(code)?.int }
    func all(_ code: Int) -> [DXFPair] { pairs.filter { $0.code == code } }
    func v2(_ xc: Int) -> Vec2? {
        guard let x = d(xc) else { return nil }
        return Vec2(x, d(xc + 10) ?? 0)
    }
}

enum DXFTokenizer {
    static func pairs(_ text: String) throws -> [DXFPair] {
        if text.hasPrefix("AutoCAD Binary DXF") { throw DXFError.binaryUnsupported }
        let lines = normalize(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var out: [DXFPair] = []
        out.reserveCapacity(lines.count / 2)
        var i = 0
        while i + 1 < lines.count {
            let codeStr = lines[i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "")
            guard let code = Int(codeStr) else { i += 1; continue } // resync
            var v = lines[i + 1]
            while v.hasSuffix(" ") && code != 1 && code != 3 { v.removeLast() }
            out.append(DXFPair(code: code, value: v))
            i += 2
        }
        return out
    }

    /// Splits on LF, CRLF or lone CR without creating empty lines for CRLF.
    private static func normalize(_ text: String) -> [String] {
        var lines: [String] = []
        var cur: [UInt8] = []
        var prevCR = false
        for b in text.utf8 {
            if b == 0x0D { lines.append(String(decoding: cur, as: UTF8.self)); cur.removeAll(keepingCapacity: true); prevCR = true; continue }
            if b == 0x0A {
                if !prevCR { lines.append(String(decoding: cur, as: UTF8.self)); cur.removeAll(keepingCapacity: true) }
                prevCR = false; continue
            }
            prevCR = false
            cur.append(b)
        }
        if !cur.isEmpty { lines.append(String(decoding: cur, as: UTF8.self)) }
        return lines
    }
}

public enum DXFReader {
    /// Reads an ASCII DXF (R12…R2018) into a new document. Unknown entities are skipped.
    public static func read(_ text: String) throws -> ArchiDocument {
        let pairs = try DXFTokenizer.pairs(text)
        guard pairs.contains(where: { $0.code == 0 && $0.trimmed == "SECTION" }) || pairs.contains(where: { $0.code == 0 && ($0.trimmed == "LINE" || $0.trimmed == "EOF") }) else {
            throw DXFError.notDXF
        }
        var r = Reader()
        r.run(pairs)
        return r.doc
    }

    /// Converts ACI color to RGBA using the application palette.
    static func rgb(fromTrueColor v: Int) -> RGBA {
        RGBA(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    /// Groups following `1001 <app>` up to the next application (XDATA).
    static func xdataGroups(_ pairs: [DXFPair], app: String) -> [DXFPair] {
        guard let i = pairs.firstIndex(where: { $0.code == 1001 && $0.trimmed.caseInsensitiveCompare(app) == .orderedSame }) else { return [] }
        var out: [DXFPair] = []
        var j = i + 1
        while j < pairs.count && pairs[j].code != 1001 && pairs[j].code >= 1000 { out.append(pairs[j]); j += 1 }
        return out
    }

    /// Arrowhead kind of a DIMBLK block name.
    static func arrow(blockName n: String) -> ArrowKind? {
        switch n.trimmingCharacters(in: .whitespaces).uppercased() {
        case "", "_CLOSEDFILLED", "CLOSEDFILLED": return .closedFilled
        case "_OPEN", "_OPEN30", "_OPEN90", "_CLOSED", "_CLOSEDBLANK": return .open
        case "_DOT", "_DOTSMALL", "_DOTBLANK", "_SMALL", "_ORIGIN", "_ORIGIN2", "_INTEGRAL": return .dot
        case "_ARCHTICK": return .architecturalTick
        case "_OBLIQUE": return .tick
        case "_NONE": return ArrowKind.none
        default: return nil
        }
    }

    /// Removes MTEXT inline formatting codes, converting paragraph breaks to newlines.
    public static func stripMText(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        func readUntilSemicolon() { while i < chars.count && chars[i] != ";" { i += 1 }; i += 1 }
        while i < chars.count {
            let c = chars[i]
            if c == "\\" && i + 1 < chars.count {
                let n = chars[i + 1]
                i += 2
                switch n {
                case "P", "X": out.append("\n")
                case "~": out.append(" ")
                case "\\", "{", "}": out.append(n)
                case "L", "l", "O", "o", "K", "k", "N": break
                case "f", "F", "H", "W", "Q", "T", "A", "C", "c", "p": readUntilSemicolon()
                case "S":
                    var frac = ""
                    while i < chars.count && chars[i] != ";" { frac.append(chars[i]); i += 1 }
                    i += 1
                    out += frac.replacingOccurrences(of: "^", with: "/").replacingOccurrences(of: "#", with: "/")
                case "U":
                    if i + 5 <= chars.count, chars[i] == "+", let v = UInt32(String(chars[(i + 1)..<(i + 5)]), radix: 16), let u = Unicode.Scalar(v) {
                        out.unicodeScalars.append(u); i += 5
                    } else { out.append("U") }
                case "M":
                    // \M+nXXXX multibyte (legacy) — skip the code
                    i = min(chars.count, i + 6)
                default: out.append(n)
                }
                continue
            }
            if c == "{" || c == "}" { i += 1; continue }
            out.append(c); i += 1
        }
        return decodeSpecial(out)
    }

    /// Decodes %%c / %%d / %%p / %%nnn and \U+XXXX escapes in TEXT values.
    public static func decodeSpecial(_ s: String) -> String {
        guard s.contains("%%") || s.contains("\\U+") else { return s }
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "%" && i + 2 < chars.count && chars[i + 1] == "%" {
                let k = chars[i + 2]
                switch k.lowercased() {
                case "c": out.append("⌀"); i += 3; continue
                case "d": out.append("°"); i += 3; continue
                case "p": out.append("±"); i += 3; continue
                case "u", "o", "k": i += 3; continue
                case "%": out.append("%"); i += 3; continue
                default:
                    var j = i + 2, num = ""
                    while j < chars.count && j < i + 5 && chars[j].isNumber { num.append(chars[j]); j += 1 }
                    if let v = UInt32(num), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u); i = j; continue }
                }
            }
            if chars[i] == "\\" && i + 6 < chars.count + 0 && chars[i + 1] == "U" && chars[i + 2] == "+",
               let v = UInt32(String(chars[(i + 3)..<min(chars.count, i + 7)]), radix: 16), let u = Unicode.Scalar(v) {
                out.unicodeScalars.append(u); i += 7; continue
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    // MARK: - Reader state

    struct Reader {
        var doc = ArchiDocument()
        var dimStyleNames: Set<String> = []
        var textStyleNames: Set<String> = []
        /// Dimension style → DIMBLK block record handle, resolved after the tables are read.
        var pendingArrowHandles: [String: String] = [:]
        /// IMAGEDEF handle → file path (from OBJECTS).
        var imageDefs: [String: String] = [:]
        /// LAYOUT objects: name, tab order, block record handle.
        var layoutInfo: [(name: String, tab: Int, record: String)] = []
        /// BLOCK_RECORD handle → block name.
        var blockRecordNames: [String: String] = [:]
        /// Paper space entities and viewports by layout name.
        var paper: [String: [Entity]] = [:]
        var paperViewports: [String: [Viewport]] = [:]
        /// Paper size and Archi title block of LAYOUT objects (by layout name); layouts written by this app are kept even when empty.
        var layoutPaper: [String: PaperSize] = [:]
        var layoutTitle: [String: [String: String]] = [:]

        init() {
            doc.layers = [Layer(name: "0")]
            doc.entities = []
            doc.blocks = [:]
        }

        mutating func run(_ pairs: [DXFPair]) {
            prescan(pairs)
            var i = 0
            var sawSection = false
            while i < pairs.count {
                let p = pairs[i]
                if p.code == 0 && p.trimmed == "SECTION" {
                    sawSection = true
                    var name = ""
                    if i + 1 < pairs.count, pairs[i + 1].code == 2 { name = pairs[i + 1].trimmed; i += 2 } else { i += 1 }
                    var j = i
                    while j < pairs.count && !(pairs[j].code == 0 && pairs[j].trimmed == "ENDSEC") { j += 1 }
                    let body = Array(pairs[i..<j])
                    switch name {
                    case "HEADER": header(body)
                    case "TABLES": tables(records(body))
                    case "BLOCKS": blocks(records(body))
                    case "ENTITIES":
                        let ents = entities(records(body), inBlock: false)
                        let active = activePaperLayout()
                        for var e in ents {
                            if e.props.removeValue(forKey: "_paper") != nil { addPaper(e, layout: active) } else { doc.add(e) }
                        }
                    default: break
                    }
                    i = j + 1
                    continue
                }
                if p.code == 0 && p.trimmed == "EOF" { break }
                i += 1
            }
            if !sawSection {
                // Entities-only fragment without sections.
                let ents = entities(records(pairs), inBlock: false)
                for var e in ents { e.props.removeValue(forKey: "_paper"); if e.props["_viewport"] == nil { doc.add(e) } }
            }
            doc.currentLayer = "0"
            if doc.layer(named: "0") == nil { doc.layers.insert(Layer(name: "0"), at: 0) }
            collectHatchDefinitions()
            buildLayouts()
        }

        /// Reads IMAGEDEF and LAYOUT objects before the entities that reference them.
        mutating func prescan(_ pairs: [DXFPair]) {
            guard let s = pairs.indices.first(where: { pairs[$0].code == 2 && pairs[$0].trimmed == "OBJECTS" && $0 > 0 && pairs[$0 - 1].trimmed == "SECTION" }) else { return }
            var j = s + 1
            while j < pairs.count && !(pairs[j].code == 0 && pairs[j].trimmed == "ENDSEC") { j += 1 }
            for r in records(Array(pairs[(s + 1)..<j])) {
                switch r.type {
                case "IMAGEDEF":
                    if let h = r.s(5)?.trimmingCharacters(in: .whitespaces), let path = r.s(1) { imageDefs[h.uppercased()] = path }
                case "LAYOUT":
                    // The first group 1 is the page setup name (AcDbPlotSettings), the last one the layout name (AcDbLayout).
                    let body = r.pairs.prefix { $0.code < 1000 }
                    guard let name = body.last(where: { $0.code == 1 })?.value.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
                    let owners = body.filter { $0.code == 330 }.map { $0.trimmed.uppercased() }
                    layoutInfo.append((name, r.i(71) ?? 0, owners.last ?? ""))
                    if name.uppercased() != "MODEL", let w = r.d(44), let hh = r.d(45), w > 1, hh > 1 {
                        let rot = (r.i(73) ?? 0) % 2 == 1
                        let pn = r.s(4)?.trimmingCharacters(in: .whitespaces) ?? ""
                        layoutPaper[name] = PaperSize(name: pn.isEmpty ? "Custom" : pn, width: rot ? hh : w, height: rot ? w : hh)
                    }
                    let x = DXFXData.read(r.pairs)
                    if x["archiLayout"] != nil {
                        var tb: [String: String] = [:]
                        for (k, v) in x where k.hasPrefix("tb:") { tb[String(k.dropFirst(3))] = v }
                        layoutTitle[name] = tb
                    }
                default: break
                }
            }
        }

        /// Layout shown by *Paper_Space (the active paper layout).
        func activePaperLayout() -> String {
            if let h = blockRecordNames.first(where: { $0.value.uppercased() == "*PAPER_SPACE" })?.key,
               let l = layoutInfo.first(where: { $0.record == h }) { return l.name }
            return layoutInfo.filter { $0.name.uppercased() != "MODEL" }.min { $0.tab < $1.tab }?.name ?? "Layout1"
        }

        mutating func addPaper(_ e: Entity, layout: String) {
            var e = e
            if e.props["_viewport"] != nil {
                if case .polyline(let pl) = e.geometry, pl.vertices.count == 4, let c = e.props["vpCenter"].flatMap(parseVec),
                   let sc = e.props["vpScale"].flatMap(Double.init) {
                    let b = BBox2(points: pl.vertices.map(\.p))
                    var vp = Viewport(origin: b.min, size: Vec2(b.width, b.height), viewCenter: c, scale: sc)
                    if let v = e.props["vpView"].flatMap(ViewKind.init(rawValue:)) { vp.view = v }
                    vp.level = e.props["vpLevel"].flatMap { Int($0) }
                    vp.title = e.props["vpTitle"] ?? ""
                    paperViewports[layout, default: []].append(vp)
                }
                return
            }
            e.id = doc.allocateID()
            doc.ensureLayer(e.layer)
            paper[layout, default: []].append(e)
        }

        /// Hatch patterns the renderer does not know keep the line families stored in the file: they are saved in the drawing
        /// as "HPPAT:<NAME>" (like PATLOAD) and registered, so custom patterns display and write back unchanged.
        mutating func collectHatchDefinitions() {
            var defs: [String: String] = [:]
            func take(_ e: inout Entity) {
                guard let d = e.props.removeValue(forKey: "_hatchdef"), case .hatch(let h) = e.geometry else { return }
                if defs[h.pattern] == nil { defs[h.pattern] = d }
            }
            for i in doc.entities.indices { take(&doc.entities[i]) }
            for k in Array(doc.blocks.keys) { for i in doc.blocks[k]!.entities.indices { take(&doc.blocks[k]!.entities[i]) } }
            for k in Array(paper.keys) { for i in paper[k]!.indices { take(&paper[k]![i]) } }
            for (name, d) in defs.sorted(by: { $0.key < $1.key }) where HatchPatterns.families[name] == nil && name != "SOLID" && doc.variable("HPPAT:" + name) == nil {
                if HatchPatterns.register(name: name, definition: d) { doc.setVariable("HPPAT:" + name, d) }
            }
        }

        /// Pattern line families of a HATCH record, back in pattern space (unrotated by the hatch angle, unscaled), as .pat lines.
        static func hatchDefinition(_ r: DXFRecord) -> String? {
            let pairs = r.pairs
            guard let i78 = pairs.firstIndex(where: { $0.code == 78 }) else { return nil }
            let angle = rad(pairs[..<i78].last { $0.code == 52 }?.double ?? 0)
            var sc = pairs[..<i78].last { $0.code == 41 }?.double ?? 1
            if abs(sc) < 1e-12 { sc = 1 }
            var lines: [String] = []
            var i = i78 + 1
            while i < pairs.count, pairs[i].code == 53 {
                let la = pairs[i].double; i += 1
                var v: [Int: Double] = [:]
                while i < pairs.count, [43, 44, 45, 46].contains(pairs[i].code) { v[pairs[i].code] = pairs[i].double; i += 1 }
                var dashes: [Double] = []
                if i < pairs.count, pairs[i].code == 79 { i += 1 }
                while i < pairs.count, pairs[i].code == 49 { dashes.append(pairs[i].double / sc); i += 1 }
                let base = Vec2(v[43] ?? 0, v[44] ?? 0).rotated(by: -angle) / sc
                let off = Vec2(v[45] ?? 0, v[46] ?? 0).rotated(by: -rad(la)) / sc
                let fa = normAngle(rad(la) - angle) * 180 / .pi
                lines.append(([fa, base.x, base.y, off.x, off.y] + dashes).map { fmt($0, 6) }.joined(separator: ","))
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }

        func parseVec(_ s: String) -> Vec2? {
            let p = s.split(separator: ",").compactMap { Double($0) }
            return p.count == 2 ? Vec2(p[0], p[1]) : nil
        }

        /// Replaces the default sheet with the drawing's paper space layouts (tab order).
        mutating func buildLayouts() {
            let names = Set(paper.keys).union(paperViewports.keys).union(layoutTitle.keys)
            guard !names.isEmpty else { return }
            let order = layoutInfo.sorted { $0.tab < $1.tab }.map(\.name)
            let sorted = names.sorted { (order.firstIndex(of: $0) ?? Int.max, $0) < (order.firstIndex(of: $1) ?? Int.max, $1) }
            doc.layouts = sorted.map { n in
                let ents = paper[n] ?? []
                var b = BBox2.empty
                for e in ents { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
                for v in paperViewports[n] ?? [] { b.add(v.origin); b.add(v.origin + v.size) }
                // Smallest standard sheet (landscape) that holds the content.
                let size = PaperSize.standard.map { $0.width >= $0.height ? $0 : PaperSize(name: $0.name, width: $0.height, height: $0.width) }
                    .sorted { $0.width * $0.height < $1.width * $1.height }
                    .first { b.isEmpty || ($0.width >= b.max.x - 1 && $0.height >= b.max.y - 1) } ?? PaperSize.standard[1]
                return Layout(name: n, paper: layoutPaper[n] ?? size, viewports: paperViewports[n] ?? [], entities: ents, titleBlock: layoutTitle[n] ?? [:])
            }
        }

        func records(_ pairs: [DXFPair]) -> [DXFRecord] {
            var out: [DXFRecord] = []
            var cur: DXFRecord?
            for p in pairs {
                if p.code == 0 {
                    if let c = cur { out.append(c) }
                    cur = DXFRecord(type: p.trimmed.uppercased(), pairs: [])
                } else { cur?.pairs.append(p) }
            }
            if let c = cur { out.append(c) }
            return out
        }

        // MARK: Header
        mutating func header(_ pairs: [DXFPair]) {
            var i = 0
            while i < pairs.count {
                guard pairs[i].code == 9 else { i += 1; continue }
                let name = pairs[i].trimmed
                var vals: [DXFPair] = []
                i += 1
                while i < pairs.count && pairs[i].code != 9 { vals.append(pairs[i]); i += 1 }
                guard let v = vals.first else { continue }
                switch name {
                case "$INSUNITS":
                    switch v.int {
                    case 1: doc.units = .inches
                    case 2: doc.units = .feet
                    case 4: doc.units = .millimeters
                    case 5: doc.units = .centimeters
                    case 6: doc.units = .meters
                    default: break
                    }
                case "$LTSCALE": doc.setVariable("LTSCALE", fmt(v.double, 6))
                case "$TEXTSIZE": doc.setVariable("TEXTSIZE", fmt(v.double, 6))
                case "$DIMSCALE": doc.setVariable("DIMSCALE", fmt(v.double, 6))
                case "$PDMODE": doc.setVariable("PDMODE", "\(v.int)")
                case "$PDSIZE": doc.setVariable("PDSIZE", fmt(v.double, 6))
                case "$ACADVER": doc.setVariable("DXFVERSION", v.trimmed)
                default: break // $EXTMIN/$EXTMAX etc. are ignored
                }
            }
        }

        // MARK: Tables
        mutating func tables(_ recs: [DXFRecord]) {
            defer {
                // DIMBLK handles name BLOCK_RECORDs, which come after DIMSTYLE in the TABLES section.
                for (style, hnd) in pendingArrowHandles {
                    guard let bn = blockRecordNames[hnd], let a = DXFReader.arrow(blockName: bn),
                          let i = doc.dimStyles.firstIndex(where: { $0.name.caseInsensitiveCompare(style) == .orderedSame }) else { continue }
                    doc.dimStyles[i].arrow = a
                }
                pendingArrowHandles = [:]
            }
            for r in recs {
                switch r.type {
                case "BLOCK_RECORD":
                    if let h = r.s(5)?.trimmingCharacters(in: .whitespaces), let n = r.s(2)?.trimmingCharacters(in: .whitespaces) { blockRecordNames[h.uppercased()] = n }
                case "LAYER":
                    guard let name = r.s(2)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
                    let aci = r.i(62) ?? 7
                    var color = DXFColors.rgba(aci: abs(aci) == 0 ? 7 : abs(aci))
                    if let tc = r.i(420) { color = DXFReader.rgb(fromTrueColor: tc) }
                    let flags = r.i(70) ?? 0
                    var lw = 0.25
                    if let w = r.i(370), w >= 0 { lw = Double(w) / 100 }
                    var lt = r.s(6)?.trimmingCharacters(in: .whitespaces) ?? "Continuous"
                    if lt.uppercased() == "CONTINUOUS" { lt = "Continuous" }
                    var layer = Layer(name: name, color: color, linetype: lt, lineweight: lw, visible: aci >= 0,
                                      frozen: flags & 1 != 0, locked: flags & 4 != 0, plot: (r.i(290) ?? 1) != 0)
                    if let t = DXFReader.xdataGroups(r.pairs, app: "AcCmTransparency").first(where: { $0.code == 1071 }).flatMap({ DXFColors.transparencyPercent(code: $0.int) }) {
                        layer.transparency = t / 100
                    }
                    if let idx = doc.layerIndex(name) { doc.layers[idx] = layer } else { doc.layers.append(layer) }
                case "LTYPE":
                    guard let name = r.s(2)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
                    let up = name.uppercased()
                    if up == "BYLAYER" || up == "BYBLOCK" || up == "CONTINUOUS" { continue }
                    let pattern = r.all(49).map(\.double)
                    let lt = Linetype(name: name, description: r.s(3) ?? "", pattern: pattern)
                    if let idx = doc.linetypes.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        doc.linetypes[idx] = Linetype(name: doc.linetypes[idx].name, description: lt.description.isEmpty ? doc.linetypes[idx].description : lt.description, pattern: pattern)
                    } else { doc.linetypes.append(lt) }
                case "STYLE":
                    guard let name = r.s(2)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
                    if (r.i(70) ?? 0) & 1 != 0 { continue } // shape file
                    let file = r.s(3)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let acad = DXFReader.xdataGroups(r.pairs, app: "ACAD")
                    var font = DXFFonts.family(fromFile: file, face: acad.first { $0.code == 1000 }?.value)
                    if let f = acad.first(where: { $0.code == 1071 })?.int {
                        if f & 0x2000000 != 0 && !font.lowercased().hasSuffix("bold") { font += " Bold" }
                        if f & 0x1000000 != 0 && !font.lowercased().hasSuffix("italic") { font += " Italic" }
                    }
                    if !file.isEmpty { doc.setVariable("DXFFONT:" + name, file) }
                    let st = TextStyle(name: name, font: font, height: r.d(40) ?? 0, widthFactor: r.d(41) ?? 1, oblique: rad(r.d(50) ?? 0))
                    if let idx = doc.textStyles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { doc.textStyles[idx] = st } else { doc.textStyles.append(st) }
                    textStyleNames.insert(name.lowercased())
                case "DIMSTYLE":
                    guard let name = r.s(2)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
                    var ds = DimStyle(name: name)
                    if let v = r.d(140) { ds.textHeight = v }
                    if let v = r.d(41) { ds.arrowSize = v }
                    if let v = r.d(42) { ds.extensionOffset = v }
                    if let v = r.d(44) { ds.extensionExtend = v }
                    if let v = r.d(147) { ds.textGap = abs(v) }
                    if let v = r.i(271) { ds.decimals = v }
                    if let v = r.d(40), v > 0 { ds.scale = v }
                    if let v = r.d(144), v != 0 { ds.linearScale = v }
                    if let post = r.s(3), !post.isEmpty {
                        let parts = post.components(separatedBy: "<>")
                        if parts.count == 2 { ds.prefix = parts[0]; ds.suffix = parts[1] } else { ds.suffix = post }
                    }
                    if (r.i(176) ?? 0) == 0, (r.d(142) ?? 0) > 0 || (r.d(143) ?? 0) > 0 { ds.arrow = .architecturalTick }
                    else if let n = r.s(5), let a = DXFReader.arrow(blockName: n) { ds.arrow = a }
                    else if let hnd = r.s(342)?.trimmingCharacters(in: .whitespaces).uppercased(), !hnd.isEmpty { pendingArrowHandles[name] = hnd }
                    if let a = DXFXData.read(r.pairs)["arrow"].flatMap(ArrowKind.init(rawValue:)) { ds.arrow = a; pendingArrowHandles[name] = nil }
                    if let idx = doc.dimStyles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { doc.dimStyles[idx] = ds } else { doc.dimStyles.append(ds) }
                    dimStyleNames.insert(name.lowercased())
                default: break
                }
            }
        }

        // MARK: Blocks
        mutating func blocks(_ recs: [DXFRecord]) {
            var i = 0
            while i < recs.count {
                guard recs[i].type == "BLOCK" else { i += 1; continue }
                let b = recs[i]
                var j = i + 1
                while j < recs.count && recs[j].type != "ENDBLK" { j += 1 }
                let name = (b.s(2) ?? b.s(3) ?? "").trimmingCharacters(in: .whitespaces)
                let upper = name.uppercased()
                let isLayoutBlock = upper.hasPrefix("*MODEL_SPACE") || upper.hasPrefix("*PAPER_SPACE") || upper.hasPrefix("$MODEL_SPACE") || upper.hasPrefix("$PAPER_SPACE")
                if upper.hasPrefix("*PAPER_SPACE") || upper.hasPrefix("$PAPER_SPACE") {
                    // Paper layouts keep their entities in *Paper_SpaceN blocks (the active one may be empty here).
                    let rec = (b.s(330) ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                    let lay = layoutInfo.first { $0.record == rec && !rec.isEmpty }?.name ?? (upper == "*PAPER_SPACE" ? activePaperLayout() : name)
                    for var e in entities(Array(recs[(i + 1)..<j]), inBlock: true) { e.props.removeValue(forKey: "_paper"); addPaper(e, layout: lay) }
                }
                if !name.isEmpty && !isLayoutBlock {
                    var ents = entities(Array(recs[(i + 1)..<j]), inBlock: true)
                    for k in ents.indices { ents[k].id = doc.allocateID() }
                    doc.blocks[name] = Block(name: name, basePoint: b.v2(10) ?? .zero, entities: ents, description: b.s(4) ?? "")
                }
                i = j + 1
            }
        }

        // MARK: Entities
        func common(_ r: DXFRecord, geometry: Geometry) -> Entity {
            var color = ColorRef.byLayer
            if let tc = r.i(420) {
                color = .rgb(UInt8((tc >> 16) & 255), UInt8((tc >> 8) & 255), UInt8(tc & 255))
            } else if let c = r.i(62) {
                if c == 0 { color = .byBlock } else if c == 256 || c < 0 { color = .byLayer } else { color = .aci(min(c, 255)) }
            }
            var lt: String? = r.s(6)?.trimmingCharacters(in: .whitespaces)
            if let l = lt, ["BYLAYER", "BYBLOCK", ""].contains(l.uppercased()) { lt = nil }
            if let l = lt, l.uppercased() == "CONTINUOUS" { lt = "Continuous" }
            var lw: Double? = nil
            if let w = r.i(370), w >= 0 { lw = Double(w) / 100 }
            var props: [String: String] = [:]
            if let h = r.s(5) { props["dxfHandle"] = h.trimmingCharacters(in: .whitespaces) }
            // Elevation (contour polylines, survey points) so TOPO and POINTSEXPORT can use it.
            let flip = mirrored(r) ? -1.0 : 1.0
            func put(_ key: String, _ z: Double?) { if let z = z, z.isFinite, abs(z) > 1e-12 { props[key] = fmt(z, 6) } }
            switch r.type {
            case "LWPOLYLINE": put("elevation", r.d(38).map { $0 * flip })
            case "POINT": put("z", r.d(30))
            case "LINE": if let a = r.d(30), let b = r.d(31), abs(a - b) < 1e-9 { put("elevation", a) }
            case "CIRCLE", "ARC": put("elevation", r.d(30).map { $0 * flip })
            default: break
            }
            // Extended data (Archi props, other applications), transparency, MTEXT formatting.
            for (k, v) in DXFXData.read(r.pairs) where props[k] == nil { props[k] = v }
            if let t = r.i(440).flatMap({ DXFColors.transparencyPercent(code: $0) }) { props["transparency"] = fmt(t, 0) }
            if r.type == "HATCH", (r.i(70) ?? 0) == 0, let d = Reader.hatchDefinition(r) { props["_hatchdef"] = d }
            if r.type == "MTEXT" {
                var raw = ""
                for p in r.pairs where p.code == 3 { raw += p.value }
                for p in r.pairs where p.code == 1 { raw += p.value }
                let f = MTextFormatting.leading(raw)
                if f.hasFormatting {
                    props["mtext"] = raw
                    if let fn = f.font { props["font"] = fn }
                    if f.bold { props["bold"] = "1" }
                    if f.italic { props["italic"] = "1" }
                    if f.underline { props["underline"] = "1" }
                }
                if let c = f.color, color == .byLayer { color = c }
            }
            let layer = (r.s(8)?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "0"
            return Entity(id: 0, layer: layer, color: color, linetype: lt, lineweight: lw, geometry: geometry, props: props)
        }

        func entities(_ recs: [DXFRecord], inBlock: Bool) -> [Entity] {
            var out: [Entity] = []
            var i = 0
            while i < recs.count {
                let r = recs[i]
                i += 1
                let isPaper = !inBlock && (r.i(67) ?? 0) == 1
                let before = out.count
                defer { if isPaper { for k in before..<out.count { out[k].props["_paper"] = "1" } } }
                switch r.type {
                case "ATTDEF":
                    guard let tag = r.s(2)?.trimmingCharacters(in: .whitespaces), !tag.isEmpty else { break }
                    // Shown as its tag, like the block editor; ATTDEF uses 74 for vertical alignment where TEXT uses 73.
                    let tr = DXFRecord(type: "TEXT", pairs: r.pairs.filter { $0.code != 73 && $0.code != 1 }.map { $0.code == 74 ? DXFPair(code: 73, value: $0.value) : $0 } + [DXFPair(code: 1, value: tag)])
                    for g in convert(tr) {
                        var e = common(r, geometry: g)
                        e.props["attdef"] = tag.uppercased()
                        e.props["prompt"] = r.s(3) ?? tag
                        e.props["default"] = DXFReader.decodeSpecial(r.s(1) ?? "")
                        if ((r.i(70) ?? 0) & 1) != 0 { e.props["invisible"] = "1" }
                        out.append(e)
                    }
                case "VIEWPORT":
                    guard isPaper || inBlock, (r.i(69) ?? 2) != 1, let c = r.v2(10), let w = r.d(40), let h = r.d(41), w > 0, h > 0 else { break }
                    let vc = r.v2(12) ?? .zero
                    let vh = r.d(45) ?? h
                    let pts = [c + Vec2(-w / 2, -h / 2), c + Vec2(w / 2, -h / 2), c + Vec2(w / 2, h / 2), c + Vec2(-w / 2, h / 2)]
                    var e = common(r, geometry: .polyline(PolylineGeom(points: pts, closed: true)))
                    e.props["_viewport"] = "1"; e.props["vpCenter"] = "\(vc.x),\(vc.y)"; e.props["vpScale"] = "\(vh / h)"
                    out.append(e)
                case "MULTILEADER", "MLEADER":
                    for g in mleader(r) { out.append(common(r, geometry: g)) }
                case "POLYLINE":
                    var verts: [DXFRecord] = []
                    while i < recs.count && recs[i].type == "VERTEX" { verts.append(recs[i]); i += 1 }
                    if i < recs.count && recs[i].type == "SEQEND" { i += 1 }
                    if let g = polyline(r, verts) {
                        var e = common(r, geometry: g)
                        let flags = r.i(70) ?? 0
                        if case .polyline = g {
                            if flags & 8 != 0 {
                                // 3D polyline: a constant z is an elevation (contour); varying z is kept per vertex.
                                let zs = verts.filter { (($0.i(70) ?? 0) & 16) == 0 }.map { $0.d(30) ?? 0 }
                                if let z0 = zs.first, zs.allSatisfy({ abs($0 - z0) < 1e-9 }) {
                                    if abs(z0) > 1e-12 { e.props["elevation"] = fmt(z0, 6) }
                                } else if !zs.isEmpty { e.props["vertexZ"] = zs.map { fmt($0, 6) }.joined(separator: ",") }
                            } else if let z = r.d(30), abs(z) > 1e-12 {
                                e.props["elevation"] = fmt(z * (mirrored(r) ? -1 : 1), 6)
                            }
                        }
                        out.append(e)
                    }
                case "INSERT":
                    var attribs: [String: String] = [:]
                    if (r.i(66) ?? 0) == 1 {
                        while i < recs.count && recs[i].type == "ATTRIB" {
                            if let tag = recs[i].s(2) { attribs[tag.trimmingCharacters(in: .whitespaces)] = DXFReader.decodeSpecial(recs[i].s(1) ?? "") }
                            i += 1
                        }
                        if i < recs.count && recs[i].type == "SEQEND" { i += 1 }
                    }
                    for g in inserts(r, attributes: attribs) { out.append(common(r, geometry: g)) }
                default:
                    for g in convert(r) { out.append(common(r, geometry: g)) }
                }
            }
            return out
        }

        /// True when the entity's extrusion direction points down (OCS mirrored in X).
        func mirrored(_ r: DXFRecord) -> Bool { (r.d(230) ?? 1) < -1e-9 }

        func convert(_ r: DXFRecord) -> [Geometry] {
            let m = mirrored(r)
            func ocs(_ p: Vec2) -> Vec2 { m ? Vec2(-p.x, p.y) : p }
            func ocsAngle(_ a: Double) -> Double { m ? .pi - a : a }
            switch r.type {
            case "LINE":
                guard let a = r.v2(10), let b = r.v2(11) else { return [] }
                return [.line(LineGeom(a, b))]
            case "POINT":
                guard let p = r.v2(10) else { return [] }
                return [.point(p)]
            case "CIRCLE":
                guard let c = r.v2(10), let rad0 = r.d(40), rad0 > 0 else { return [] }
                return [.circle(CircleGeom(ocs(c), rad0))]
            case "ARC":
                guard let c = r.v2(10), let rr = r.d(40), rr > 0 else { return [] }
                var s = rad(r.d(50) ?? 0), e = rad(r.d(51) ?? 360)
                if m { let s2 = Double.pi - e, e2 = Double.pi - s; s = s2; e = e2 }
                return [.arc(ArcGeom(ocs(c), rr, normAngle(s), normAngle(e)))]
            case "ELLIPSE":
                guard let c = r.v2(10), let maj = r.v2(11), maj.length > geomEpsilon else { return [] }
                var s = r.d(41) ?? 0, e = r.d(42) ?? 2 * .pi
                if m { let s2 = -e, e2 = -s; s = s2; e = e2 }
                let full = abs(abs(e - s) - 2 * .pi) < 1e-6 || abs(e - s) < 1e-9
                return [.ellipse(EllipseGeom(center: c, majorAxis: maj, ratio: r.d(40) ?? 1, start: full ? 0 : normAngle(s), end: full ? 2 * .pi : normAngle(e)))]
            case "LWPOLYLINE":
                var verts: [PolyVertex] = []
                for p in r.pairs {
                    switch p.code {
                    case 10: verts.append(PolyVertex(Vec2(p.double, 0)))
                    case 20: if !verts.isEmpty { verts[verts.count - 1].p.y = p.double }
                    case 42: if !verts.isEmpty { verts[verts.count - 1].bulge = p.double }
                    default: break
                    }
                }
                if m { verts = verts.map { PolyVertex(Vec2(-$0.p.x, $0.p.y), bulge: -$0.bulge) } }
                guard verts.count >= 1 else { return [] }
                let closed = ((r.i(70) ?? 0) & 1) != 0
                if !closed, let last = verts.indices.last { verts[last].bulge = 0 }
                return [.polyline(PolylineGeom(verts, closed: closed, width: r.d(43) ?? 0))]
            case "SPLINE":
                var ctrl: [Vec2] = [], fit: [Vec2] = []
                for p in r.pairs {
                    switch p.code {
                    case 10: ctrl.append(Vec2(p.double, 0))
                    case 20: if !ctrl.isEmpty { ctrl[ctrl.count - 1].y = p.double }
                    case 11: fit.append(Vec2(p.double, 0))
                    case 21: if !fit.isEmpty { fit[fit.count - 1].y = p.double }
                    default: break
                    }
                }
                let knots = r.all(40).map(\.double)
                let w = r.all(41).map(\.double)
                let flags = r.i(70) ?? 0
                guard ctrl.count >= 2 || fit.count >= 2 else { return [] }
                return [.spline(SplineGeom(degree: r.i(71) ?? 3, controlPoints: ctrl, knots: knots,
                                           weights: (w.count == ctrl.count && w.contains { abs($0 - 1) > 1e-12 }) ? w : nil,
                                           fitPoints: fit, closed: flags & 1 != 0))]
            case "TEXT":
                let content = DXFReader.decodeSpecial(r.s(1) ?? "")
                guard !content.isEmpty else { return [] }
                let h = r.d(40) ?? 2.5
                var rot = rad(r.d(50) ?? 0)
                let ha = r.i(72) ?? 0, va = r.i(73) ?? 0
                var pos = r.v2(10) ?? .zero
                var halign = HAlign.left, valign = VAlign.baseline
                switch ha {
                case 1: halign = .center
                case 2: halign = .right
                case 4: halign = .center; valign = .middle
                default: break
                }
                if ha != 4 {
                    switch va { case 1: valign = .bottom; case 2: valign = .middle; case 3: valign = .top; default: break }
                }
                if ha == 3 || ha == 5 {
                    if let p2 = r.v2(11), p2.distance(to: pos) > geomEpsilon { rot = (p2 - pos).angle }
                } else if (ha != 0 || va != 0), let p2 = r.v2(11) { pos = p2 }
                if m { pos = ocs(pos); rot = ocsAngle(rot) }
                let style = r.s(7).map { $0.trimmingCharacters(in: .whitespaces) } ?? "Standard"
                return [.text(TextGeom(position: pos, height: h, content: content, rotation: normAngle(rot), style: style, halign: halign, valign: valign))]
            case "MTEXT":
                var raw = ""
                for p in r.pairs where p.code == 3 { raw += p.value }
                for p in r.pairs where p.code == 1 { raw += p.value }
                let content = DXFReader.stripMText(raw)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                let pos = r.v2(10) ?? .zero
                var rot = rad(r.d(50) ?? 0)
                if let dir = r.v2(11), dir.length > geomEpsilon { rot = dir.angle }
                let att = max(1, min(9, r.i(71) ?? 1))
                let halign: HAlign = [.left, .center, .right][(att - 1) % 3]
                let valign: VAlign = [.top, .middle, .bottom][(att - 1) / 3]
                let style = r.s(7).map { $0.trimmingCharacters(in: .whitespaces) } ?? "Standard"
                return [.text(TextGeom(position: pos, height: r.d(40) ?? 2.5, content: content, rotation: normAngle(rot), style: style,
                                       halign: halign, valign: valign, width: max(0, r.d(41) ?? 0)))]
            case "DIMENSION":
                return dimension(r)
            case "HATCH":
                return hatch(r).map { [$0] } ?? []
            case "LEADER":
                var pts: [Vec2] = []
                for p in r.pairs {
                    if p.code == 10 { pts.append(Vec2(p.double, 0)) } else if p.code == 20, !pts.isEmpty { pts[pts.count - 1].y = p.double }
                }
                guard pts.count >= 2 else { return [] }
                return [.leader(LeaderGeom(points: pts, text: "", textHeight: r.d(40) ?? 2.5))]
            case "SOLID", "TRACE":
                guard let a = r.v2(10), let b = r.v2(11), let c = r.v2(12) else { return [] }
                let d = r.v2(13) ?? c
                var pts = [a, b, d, c].map(ocs)
                if pts[2].isClose(pts[3]) { pts.removeLast() }
                return [.polyline(PolylineGeom(points: pts, closed: true))]
            case "3DFACE":
                guard let a = r.v2(10), let b = r.v2(11), let c = r.v2(12) else { return [] }
                var pts = [a, b, c]
                if let d = r.v2(13), !d.isClose(c) { pts.append(d) }
                return [.polyline(PolylineGeom(points: pts, closed: true))]
            case "XLINE", "RAY":
                guard let p = r.v2(10), let d = r.v2(11), d.length > geomEpsilon else { return [] }
                let big = 1e6, dir = d.normalized
                return [.line(LineGeom(r.type == "RAY" ? p : p - dir * big, p + dir * big))]
            case "MLINE":
                return mline(r)
            case "ACAD_TABLE":
                return acadTable(r).map { [$0] } ?? []
            case "IMAGE":
                guard let o = r.v2(10), let u = r.v2(11), let v = r.v2(12) else { return [] }
                let px = r.v2(13) ?? Vec2(1, 1)
                let size = Vec2(u.length * max(px.x, 1), v.length * max(px.y, 1))
                guard size.x > 0, size.y > 0 else { return [] }
                let h = (r.s(340) ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                let rot = normAngle(u.angle)
                return [.image(ImageGeom(path: imageDefs[h] ?? "", origin: o, size: size, rotation: rot < 1e-12 || abs(rot - 2 * .pi) < 1e-12 ? 0 : rot))]
            default:
                return [] // 3DSOLID, REGION, ... are ignored
            }
        }

        /// MLINE: one polyline per element line, each vertex offset along its miter direction by the element's first parameter.
        func mline(_ r: DXFRecord) -> [Geometry] {
            let pairs = r.pairs
            guard let i73 = pairs.firstIndex(where: { $0.code == 73 }) else { return [] }
            let nElems = max(0, min(pairs[i73].int, 64))
            let closed = ((r.i(71) ?? 0) & 2) != 0
            guard nElems > 0 else { return [] }
            var lines = Array(repeating: [Vec2](), count: nElems)
            var i = i73 + 1
            func vec(_ code: Int) -> Vec2? {
                guard i < pairs.count, pairs[i].code == code else { return nil }
                let x = pairs[i].double; i += 1
                var y = 0.0
                if i < pairs.count, pairs[i].code == code + 10 { y = pairs[i].double; i += 1 }
                if i < pairs.count, pairs[i].code == code + 20 { i += 1 }
                return Vec2(x, y)
            }
            while i < pairs.count && pairs[i].code != 11 { i += 1 }
            while i < pairs.count, pairs[i].code == 11 {
                guard let v = vec(11) else { break }
                _ = vec(12)
                let miter = vec(13) ?? Vec2(0, 1)
                for k in 0..<nElems {
                    var params: [Double] = []
                    if i < pairs.count, pairs[i].code == 74 {
                        let n = pairs[i].int; i += 1
                        for _ in 0..<max(0, n) where i < pairs.count && pairs[i].code == 41 { params.append(pairs[i].double); i += 1 }
                    }
                    if i < pairs.count, pairs[i].code == 75 {
                        let n = pairs[i].int; i += 1
                        for _ in 0..<max(0, n) where i < pairs.count && pairs[i].code == 42 { i += 1 }
                    }
                    lines[k].append(v + miter.normalized * (params.first ?? 0))
                }
            }
            return lines.filter { $0.count >= 2 }.map { .polyline(PolylineGeom(points: $0, closed: closed)) }
        }

        /// ACAD_TABLE: insertion point (top left), row heights (141), column widths (142) and the cell texts in row order.
        func acadTable(_ r: DXFRecord) -> Geometry? {
            let pairs = r.pairs
            guard let o = r.v2(10) else { return nil }
            let rows = pairs.filter { $0.code == 141 }.map(\.double)
            let cols = pairs.filter { $0.code == 142 }.map(\.double)
            guard !rows.isEmpty, !cols.isEmpty, rows.count <= 10_000, cols.count <= 1000 else { return nil }
            // Cells start at group 171 (cell type); the text is the cell's group 1 (plus continuation groups 2/3) or its
            // 302 value (newer files).
            var texts: [String] = []
            var cur: String? = nil
            var textHeight: Double? = nil
            var inCell = false
            for p in pairs {
                switch p.code {
                case 171:
                    if inCell { texts.append(cur ?? "") }
                    inCell = true; cur = nil
                case 1 where inCell: cur = (cur ?? "") + p.value
                case 2, 3: if inCell, cur != nil { cur! += p.value }
                case 302 where inCell && cur == nil: cur = p.value
                case 140 where inCell && textHeight == nil && p.double > 0: textHeight = p.double
                default: break
                }
            }
            if inCell { texts.append(cur ?? "") }
            var cells: [[String]] = []
            for rr in 0..<rows.count {
                cells.append((0..<cols.count).map { c in
                    let k = rr * cols.count + c
                    return k < texts.count ? DXFReader.decodeSpecial(DXFReader.stripMText(texts[k])) : ""
                })
            }
            let rh = rows.reduce(0, +) / Double(rows.count)
            return .table(TableGeom(origin: o, columnWidths: cols, rowHeight: rh, cells: cells, textHeight: textHeight ?? max(rh * 0.36, 1e-3)))
        }

        /// MULTILEADER: each leader line (arrow tip first) ends at its landing point; the first carries the MText content.
        func mleader(_ r: DXFRecord) -> [Geometry] {
            var lines: [[Vec2]] = []
            var landing: [Vec2] = []
            var cur: [Vec2]? = nil
            var inLeader = false
            var text = ""
            var textPos: Vec2? = nil
            var height = 0.0
            var pendingX: Double? = nil
            for p in r.pairs {
                switch p.code {
                case 302 where p.trimmed == "LEADER{": inLeader = true
                case 303: inLeader = false
                case 304 where p.trimmed == "LEADER_LINE{": cur = []
                case 305: if let c = cur, !c.isEmpty { lines.append(c) }; cur = nil
                case 304: if text.isEmpty { text = DXFReader.stripMText(p.value) }
                case 41 where cur == nil && !inLeader && height == 0: height = p.double
                case 12: pendingX = p.double
                case 22: if let x = pendingX, textPos == nil { textPos = Vec2(x, p.double) }; pendingX = nil
                case 10: pendingX = p.double
                case 20:
                    guard let x = pendingX else { break }
                    let v = Vec2(x, p.double)
                    if cur != nil { cur!.append(v) } else if inLeader { landing.append(v) }
                    pendingX = nil
                default: break
                }
            }
            if height <= 0 { height = 2.5 }
            var out: [Geometry] = []
            for (k, line) in lines.enumerated() {
                var pts = line
                if k < landing.count { pts.append(landing[k]) } else if let l = landing.first { pts.append(l) }
                var clean: [Vec2] = []
                for q in pts where !(clean.last.map { $0.isClose(q, tol: 1e-9) } ?? false) { clean.append(q) }
                guard clean.count >= 2 else { continue }
                out.append(.leader(LeaderGeom(points: clean, text: k == 0 ? text : "", textHeight: height)))
            }
            if out.isEmpty, !text.isEmpty, let tp = textPos { out.append(.text(TextGeom(position: tp, height: height, content: text, valign: .top))) }
            return out
        }

        func polyline(_ r: DXFRecord, _ verts: [DXFRecord]) -> Geometry? {
            let flags = r.i(70) ?? 0
            if flags & 64 != 0 { // polyface mesh
                var positions: [Vec3] = [], tris: [Int] = []
                for v in verts {
                    let vf = v.i(70) ?? 0
                    if vf & 64 != 0 { positions.append(Vec3(v.d(10) ?? 0, v.d(20) ?? 0, v.d(30) ?? 0)) }
                    else if vf & 128 != 0 {
                        let idx = [71, 72, 73, 74].compactMap { v.i($0) }.map { abs($0) - 1 }.filter { $0 >= 0 && $0 < 1_000_000 }
                        if idx.count >= 3 { tris += [idx[0], idx[1], idx[2]] }
                        if idx.count == 4 { tris += [idx[0], idx[2], idx[3]] }
                    }
                }
                tris = tris.filter { $0 < positions.count }
                guard !positions.isEmpty, tris.count >= 3 else { return nil }
                return .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: positions, meshTriangles: Array(tris.prefix(tris.count / 3 * 3))))
            }
            if flags & 16 != 0 { // polygon mesh: keep vertices as a wire polyline
                let pts = verts.compactMap { $0.v2(10) }
                return pts.count >= 2 ? .polyline(PolylineGeom(points: pts)) : nil
            }
            let m = mirrored(r) && flags & 8 == 0
            var pv: [PolyVertex] = verts.filter { (($0.i(70) ?? 0) & 16) == 0 }.map { v in
                let p = v.v2(10) ?? .zero
                return PolyVertex(m ? Vec2(-p.x, p.y) : p, bulge: m ? -(v.d(42) ?? 0) : (v.d(42) ?? 0))
            }
            guard !pv.isEmpty else { return nil }
            let closed = flags & 1 != 0
            if !closed { pv[pv.count - 1].bulge = 0 }
            return .polyline(PolylineGeom(pv, closed: closed, width: r.d(40) ?? 0))
        }

        func inserts(_ r: DXFRecord, attributes: [String: String]) -> [Geometry] {
            guard let name = r.s(2)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return [] }
            var p = r.v2(10) ?? .zero
            var sx = r.d(41) ?? 1, sy = r.d(42) ?? 1
            if sx == 0 { sx = 1 }; if sy == 0 { sy = 1 }
            var rot = rad(r.d(50) ?? 0)
            if mirrored(r) { p = Vec2(-p.x, p.y); rot = -rot; sx = -sx }
            let cols = max(1, r.i(70) ?? 1), rows = max(1, r.i(71) ?? 1)
            let cs = r.d(44) ?? 0, rs = r.d(45) ?? 0
            var out: [Geometry] = []
            for row in 0..<min(rows, 1000) {
                for col in 0..<min(cols, 1000) {
                    let off = Vec2(Double(col) * cs, Double(row) * rs).rotated(by: rot)
                    out.append(.insert(InsertGeom(block: name, position: p + off, scale: Vec2(sx, sy), rotation: rot, attributes: attributes)))
                }
            }
            return out
        }

        func dimension(_ r: DXFRecord) -> [Geometry] {
            let type = (r.i(70) ?? 0) & 7
            let p10 = r.v2(10), p11 = r.v2(11), p13 = r.v2(13), p14 = r.v2(14), p15 = r.v2(15), p16 = r.v2(16)
            var over: String? = r.s(1)
            if let o = over, o.isEmpty || o == "<>" { over = nil }
            if let o = over { over = DXFReader.stripMText(o) }
            let sname = (r.s(3) ?? "Standard").trimmingCharacters(in: .whitespaces)
            let style = dimStyleNames.contains(sname.lowercased()) ? sname : (doc.dimStyles.contains { $0.name == sname } ? sname : "Standard")
            var geom: DimensionGeom?
            switch type {
            case 0:
                if let a = p13, let b = p14, let l = p10 { geom = DimensionGeom(kind: .linear, points: [a, b, l], rotation: rad(r.d(50) ?? 0), textOverride: over, style: style) }
            case 1:
                if let a = p13, let b = p14, let l = p10 { geom = DimensionGeom(kind: .aligned, points: [a, b, l], textOverride: over, style: style) }
            case 2:
                if let a1 = p13, let a2 = p14, let b1 = p15, let b2 = p10, let arc = p16,
                   let v = GeometryOps.lineIntersection(a1, a2, b1, b2) {
                    let l1 = a1.distance(to: v) > a2.distance(to: v) ? a1 : a2
                    let l2 = b1.distance(to: v) > b2.distance(to: v) ? b1 : b2
                    geom = DimensionGeom(kind: .angular, points: [v, l1, l2, arc], textOverride: over, style: style)
                }
            case 5:
                if let v = p15, let a = p13, let b = p14, let arc = p10 { geom = DimensionGeom(kind: .angular, points: [v, a, b, arc], textOverride: over, style: style) }
            case 3:
                if let a = p15, let b = p10 { geom = DimensionGeom(kind: .diameter, points: [(a + b) / 2, a, p11 ?? a], textOverride: over, style: style) }
            case 4:
                if let c = p10, let a = p15 { geom = DimensionGeom(kind: .radius, points: [c, a, p11 ?? a], textOverride: over, style: style) }
            case 6:
                if let o = p10, let f = p13, let l = p14 { geom = DimensionGeom(kind: .ordinate, points: [f, l, o], rotation: ((r.i(70) ?? 0) & 64) != 0 ? 0 : .pi / 2, textOverride: over, style: style) }
            default: break
            }
            if let g = geom { return [.dimension(g)] }
            if let b = r.s(2)?.trimmingCharacters(in: .whitespaces), !b.isEmpty { return [.insert(InsertGeom(block: b, position: .zero))] }
            return []
        }

        func hatch(_ r: DXFRecord) -> Geometry? {
            let pairs = r.pairs
            guard let start = pairs.firstIndex(where: { $0.code == 91 }) else { return nil }
            let nPaths = pairs[start].int
            var i = start + 1
            var loops: [[PolyVertex]] = []
            func at(_ c: Int) -> Bool { i < pairs.count && pairs[i].code == c }
            func consume(_ codes: Set<Int>) -> [DXFPair] {
                var got: [DXFPair] = []
                while i < pairs.count && codes.contains(pairs[i].code) { got.append(pairs[i]); i += 1 }
                return got
            }
            func pts(_ ps: [DXFPair], _ xc: Int) -> [Vec2] {
                var out: [Vec2] = []
                for p in ps { if p.code == xc { out.append(Vec2(p.double, 0)) } else if p.code == xc + 10, !out.isEmpty { out[out.count - 1].y = p.double } }
                return out
            }
            for _ in 0..<max(0, min(nPaths, 100000)) {
                while i < pairs.count && pairs[i].code != 92 { if pairs[i].code == 75 || pairs[i].code == 98 { break }; i += 1 }
                guard at(92) else { break }
                let flags = pairs[i].int; i += 1
                var loop: [PolyVertex] = []
                if flags & 2 != 0 {
                    _ = consume([72, 73]); _ = consume([93])
                    for p in consume([10, 20, 42]) {
                        switch p.code {
                        case 10: loop.append(PolyVertex(Vec2(p.double, 0)))
                        case 20: if !loop.isEmpty { loop[loop.count - 1].p.y = p.double }
                        default: if !loop.isEmpty { loop[loop.count - 1].bulge = p.double }
                        }
                    }
                    if loop.count > 1, loop[0].p.isClose(loop[loop.count - 1].p, tol: 1e-9) { loop.removeLast() }
                } else {
                    let nEdges = at(93) ? pairs[i].int : 0
                    if at(93) { i += 1 }
                    for _ in 0..<max(0, min(nEdges, 100000)) {
                        guard at(72) else { break }
                        let et = pairs[i].int; i += 1
                        switch et {
                        case 1:
                            let d = consume([10, 20, 11, 21])
                            let a = pts(d, 10).first ?? .zero
                            loop.append(PolyVertex(a))
                        case 2:
                            let d = consume([10, 20, 40, 50, 51, 73])
                            let c = pts(d, 10).first ?? .zero
                            let rr = d.first { $0.code == 40 }?.double ?? 0
                            let s = rad(d.first { $0.code == 50 }?.double ?? 0), e = rad(d.first { $0.code == 51 }?.double ?? 360)
                            let ccw = (d.first { $0.code == 73 }?.int ?? 1) != 0
                            var sweep = normAngle(e - s)
                            if sweep < 1e-9 { sweep = 2 * .pi }
                            let sa = ccw ? s : -s
                            let sw = ccw ? sweep : -sweep
                            if abs(abs(sw) - 2 * .pi) < 1e-9 {
                                let b = sw > 0 ? 1.0 : -1.0
                                loop.append(PolyVertex(c + Vec2.polar(rr, sa), bulge: b))
                                loop.append(PolyVertex(c + Vec2.polar(rr, sa + .pi), bulge: b))
                            } else {
                                loop.append(PolyVertex(c + Vec2.polar(rr, sa), bulge: tan(sw / 4)))
                            }
                        case 3:
                            let d = consume([10, 20, 11, 21, 40, 50, 51, 73])
                            let c = pts(d, 10).first ?? .zero, maj = pts(d, 11).first ?? Vec2(1, 0)
                            let ratio = d.first { $0.code == 40 }?.double ?? 1
                            let s = rad(d.first { $0.code == 50 }?.double ?? 0), e = rad(d.first { $0.code == 51 }?.double ?? 360)
                            let ccw = (d.first { $0.code == 73 }?.int ?? 1) != 0
                            var sweep = normAngle(e - s); if sweep < 1e-9 { sweep = 2 * .pi }
                            let el = EllipseGeom(center: c, majorAxis: maj, ratio: ratio)
                            let n = max(8, Int(sweep / (2 * .pi) * 64))
                            for k in 0..<n {
                                let t = ccw ? s + sweep * Double(k) / Double(n) : -s - sweep * Double(k) / Double(n)
                                loop.append(PolyVertex(el.point(at: t)))
                            }
                        case 4:
                            var d = consume([94, 73, 74, 95, 96, 40, 10, 20, 42])
                            if at(97), i + 1 < pairs.count, [11, 12, 97].contains(pairs[i + 1].code) || pairs[i].int == 0 && [12, 13].contains(pairs[i + 1].code) {
                                i += 1
                                d += consume([11, 21, 12, 22, 13, 23])
                            }
                            let ctrl = pts(d, 10), fit = pts(d, 11)
                            let knots = d.filter { $0.code == 40 }.map(\.double)
                            let w = d.filter { $0.code == 42 }.map(\.double)
                            let deg = d.first { $0.code == 94 }?.int ?? 3
                            let sp = SplineGeom(degree: deg, controlPoints: ctrl, knots: knots, weights: w.count == ctrl.count ? w : nil, fitPoints: fit)
                            let sampled = GeometryOps.splinePoints(sp)
                            for p in sampled.dropLast() { loop.append(PolyVertex(p)) }
                        default: break
                        }
                    }
                }
                // source boundary objects
                if at(97) { let n = pairs[i].int; i += 1; for _ in 0..<n where at(330) { i += 1 } }
                if loop.count >= 2 { loops.append(loop) }
            }
            guard !loops.isEmpty else { return nil }
            let solid = (r.i(70) ?? 0) == 1 || (r.i(450) ?? 0) == 1
            var pattern = (r.s(2) ?? "SOLID").trimmingCharacters(in: .whitespaces).uppercased()
            if solid || pattern.isEmpty { pattern = "SOLID" }
            // pattern angle/scale follow the boundary data
            let tail = pairs[min(i, pairs.count)...]
            let angle = tail.first { $0.code == 52 }?.double ?? 0
            let scale = tail.first { $0.code == 41 }?.double ?? 1
            if mirrored(r) {
                loops = loops.map { $0.map { PolyVertex(Vec2(-$0.p.x, $0.p.y), bulge: -$0.bulge) } }
            }
            return .hatch(HatchGeom(loops: loops, pattern: pattern, scale: scale == 0 ? 1 : scale, angle: rad(angle)))
        }
    }
}
