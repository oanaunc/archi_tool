// Oanarina Archi Tool — GPL-3.0-or-later
// DXF R2000 (AC1015) ASCII writer. Fixed table/dictionary handles follow the layout used by
// LibreCAD's libdxfrw (GPL-2.0-or-later, © LibreCAD team), which AutoCAD and LibreCAD both open.
import Foundation

public enum DXFWriter {
    /// Writes the document. BIM elements of the current level are written as their 2D plan representation.
    public static func write(_ doc: ArchiDocument) -> String {
        write(doc, levels: [doc.currentLevel])
    }

    /// Writes the document, including BIM elements on the given levels (nil = all levels).
    public static func write(_ doc: ArchiDocument, levels: Set<Int>?) -> String {
        var w = Writer(doc: doc)
        return w.run(levels: levels)
    }

    /// Standard DXF lineweights in 1/100 mm.
    static let standardLineweights = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140, 158, 200, 211]
    static func lineweightCode(_ mm: Double) -> Int {
        let v = Int((mm * 100).rounded())
        return standardLineweights.min { abs($0 - v) < abs($1 - v) } ?? 25
    }

    /// Nearest AutoCAD Color Index (1…255) to an RGB color.
    static func nearestACI(_ c: RGBA) -> Int { DXFColors.nearest(c) }
    static func trueColor(_ c: RGBA) -> Int {
        func b(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return b(c.r) << 16 | b(c.g) << 8 | b(c.b)
    }

    /// Makes a symbol-table-safe name.
    static func safeName(_ s: String) -> String {
        let bad = Set("<>/\\\":;?*|=`")
        let t = String(s.map { bad.contains($0) ? "_" : $0 })
        return t.isEmpty ? "_" : t
    }

    /// Encodes non-ASCII characters as \U+XXXX (R2000 files are code-page based).
    static func enc(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u.value == 10 || u.value == 13 { out += " "; continue }
            if u.value < 128 { out.unicodeScalars.append(u) }
            else if u.value <= 0xFFFF { out += String(format: "\\U+%04X", u.value) }
            else {
                // Outside the Basic Multilingual Plane: UTF-16 surrogate pair (as AutoCAD writes it).
                let v = u.value - 0x10000
                out += String(format: "\\U+%04X\\U+%04X", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
            }
        }
        return out
    }

    /// Hatch pattern line families (angle°, base x, base y, offset x, offset y, dashes) in PAT units.
    static let patterns: [String: [(Double, Double, Double, Double, Double, [Double])]] = [
        "ANSI31": [(45, 0, 0, 0, 3.175, [])],
        "ANSI32": [(45, 0, 0, 0, 9.525, []), (45, 4.49013, 0, 0, 9.525, [3.175, -6.35])],
        "ANSI33": [(45, 0, 0, 0, 6.35, []), (45, 4.49013, 0, 4.49013, 6.35, [3.175, -1.5875])],
        "ANSI37": [(45, 0, 0, 0, 3.175, []), (135, 0, 0, 0, 3.175, [])],
        "LINE": [(0, 0, 0, 0, 3.175, [])],
        "NET": [(0, 0, 0, 0, 3.175, []), (90, 0, 0, 0, 3.175, [])],
        "DOTS": [(0, 0, 0, 0.79375, 1.5875, [0, -1.5875])],
        "AR-SAND": [(37.5, 0, 0, 1.123, 1.567, [0, -1.52]), (7.5, 0, 0, 2.2, 1.73, [0, -1.72])],
        "AR-CONC": [(50, 0, 0, 4.12, -4.12, [0.75, -8.25]), (355, 0, 0, -2.2, 5.5, [0.6, -7.0])],
        "INSUL": [(0, 0, 0, 0, 3.175, []), (0, 0, 1.0583, 0, 3.175, [1.0583, -1.0583])],
    ]

    /// Line families written for a hatch pattern: a definition saved in the drawing (variable "HPPAT:<NAME>", from PATLOAD
    /// or a DXF import) wins, then the DXF table above, then the renderer's built-in library, else ANSI31.
    static func patternDefinition(_ name: String, doc: ArchiDocument) -> [(Double, Double, Double, Double, Double, [Double])] {
        let key = name.uppercased()
        if let def = doc.variable("HPPAT:" + key) ?? doc.variables.first(where: { $0.key.uppercased() == "HPPAT:" + key })?.value {
            let fams = def.components(separatedBy: "\n").compactMap { HatchPatterns.families(fromLine: $0) }
            if !fams.isEmpty { return fams.map { ($0.angle, $0.origin.x, $0.origin.y, $0.delta.x, $0.delta.y, $0.dashes) } }
        }
        if let p = patterns[key] { return p }
        if let fams = HatchPatterns.families[key], !fams.isEmpty { return fams.map { ($0.angle, $0.origin.x, $0.origin.y, $0.delta.x, $0.delta.y, $0.dashes) } }
        return patterns["ANSI31"]!
    }

    // MARK: -

    struct Writer {
        let doc: ArchiDocument
        var body: [String] = []
        var nextHandle = 0x30
        var dimBlocks: [(name: String, dim: DimensionGeom, layer: String)] = []
        var dimCursor = 0
        var blockRecordHandles: [String: String] = [:]
        var blockNames: [String: String] = [:] // doc name -> dxf name
        /// Z / elevation of the entity being written (props "elevation" or "z": contours, survey points).
        var elevation = 0.0
        /// Props of the entity being written (MTEXT formatting), its XDATA (attached to its first DXF entity, emitted just
        /// before the next group 0) and its transparency (group 440 on every DXF entity it produces).
        var entityProps: [String: String] = [:]
        var armedXData: [(Int, String)]? = nil
        var pendingXData: [(Int, String)] = []
        var entityTransparency: Int? = nil
        /// Block record handle per sheet layout (layout 0 is *Paper_Space = 1E, the others *Paper_SpaceN).
        var layoutRecords: [String] = []
        /// First dimension block of the active (first) layout's paper-space entities.
        var paperDimStart = 0
        /// Entities being written belong to paper space (group 67 = 1).
        var paperSpace = false

        init(doc: ArchiDocument) { self.doc = doc }

        mutating func h() -> String { defer { nextHandle += 1 }; return String(nextHandle, radix: 16, uppercase: true) }
        mutating func g(_ code: Int, _ v: String) {
            if code == 0 && !pendingXData.isEmpty {
                let x = pendingXData
                pendingXData = []
                for (xc, xv) in x { g(xc, xv) }
            }
            let c = String(code)
            body.append(String(repeating: " ", count: max(0, 3 - c.count)) + c)
            body.append(v)
        }
        mutating func g(_ code: Int, _ v: Double) { g(code, num(v)) }
        mutating func g(_ code: Int, _ v: Int) { g(code, String(v)) }
        func num(_ v: Double) -> String {
            guard v.isFinite else { return "0.0" }
            let s = fmt(v, 10)
            return s.contains(".") ? s : s + ".0"
        }
        mutating func pt(_ code: Int, _ p: Vec2, _ z: Double = 0) { g(code, p.x); g(code + 10, p.y); g(code + 20, z) }

        // MARK: run
        mutating func run(levels: Set<Int>?) -> String {
            // Pre-pass: dimension blocks (model space first, then block definitions, same order as writing).
            let sortedBlocks = doc.blocks.keys.sorted()
            var used = Set<String>(["*MODEL_SPACE", "*PAPER_SPACE"])
            for name in sortedBlocks {
                var n = DXFWriter.safeName(name)
                if name.hasPrefix("*") && !name.uppercased().hasPrefix("*U") && !name.uppercased().hasPrefix("*D") { n = "_" + n.dropFirst() }
                while used.contains(n.uppercased()) { n += "_" }
                used.insert(n.uppercased())
                blockNames[name] = n
            }
            var k = 1
            func collect(_ ents: [Entity]) {
                for e in ents { if case .dimension(let d) = e.geometry {
                    while used.contains("*D\(k)") { k += 1 }
                    used.insert("*D\(k)")
                    dimBlocks.append(("*D\(k)", d, e.layer)); k += 1
                } }
            }
            collect(doc.entities)
            for name in sortedBlocks { collect(doc.blocks[name]!.entities) }
            // Sheet layouts: layouts 2… live in *Paper_SpaceN blocks (written after the user blocks), layout 1 in ENTITIES.
            for (i, l) in doc.layouts.enumerated() where i > 0 { collect(l.entities) }
            paperDimStart = dimBlocks.count
            if let l0 = doc.layouts.first { collect(l0.entities) }

            // Block record handles
            blockRecordHandles["*Model_Space"] = "1F"; blockRecordHandles["*Paper_Space"] = "1E"
            for name in sortedBlocks { blockRecordHandles[blockNames[name]!] = h() }
            layoutRecords = []
            for i in doc.layouts.indices {
                if i == 0 { layoutRecords.append("1E"); continue }
                let hd = h()
                blockRecordHandles["*Paper_Space\(i - 1)"] = hd
                layoutRecords.append(hd)
            }
            for d in dimBlocks { blockRecordHandles[d.name] = h() }

            classes()
            tables()
            blocks(sortedBlocks)
            entitiesSection(levels: levels)
            objects()
            g(0, "EOF")
            let tail = body
            body = []
            header()
            body += tail
            return body.joined(separator: "\n") + "\n"
        }

        mutating func header() {
            let b = GeometryOps.bounds(of: doc, includeElements: false)
            g(0, "SECTION"); g(2, "HEADER")
            g(9, "$ACADVER"); g(1, "AC1015")
            g(9, "$DWGCODEPAGE"); g(3, "ANSI_1252")
            g(9, "$INSBASE"); pt(10, .zero)
            g(9, "$EXTMIN"); pt(10, b.isEmpty ? .zero : b.min)
            g(9, "$EXTMAX"); pt(10, b.isEmpty ? Vec2(1000, 1000) : b.max)
            g(9, "$LTSCALE"); g(40, Double(doc.variable("LTSCALE") ?? "") ?? 1)
            g(9, "$TEXTSIZE"); g(40, Double(doc.variable("TEXTSIZE") ?? "") ?? 2.5)
            g(9, "$DIMSCALE"); g(40, Double(doc.variable("DIMSCALE") ?? "") ?? 1)
            g(9, "$CLAYER"); g(8, DXFWriter.enc(doc.currentLayer))
            g(9, "$DIMSTYLE"); g(2, DXFWriter.enc(DXFWriter.safeName(doc.currentDimStyle)))
            g(9, "$INSUNITS")
            let iu: Int
            switch doc.units { case .inches: iu = 1; case .feet: iu = 2; case .millimeters: iu = 4; case .centimeters: iu = 5; case .meters: iu = 6 }
            g(70, iu)
            g(9, "$MEASUREMENT"); g(70, (doc.units == .inches || doc.units == .feet) ? 0 : 1)
            g(9, "$LUNITS"); g(70, 2)
            g(9, "$LWDISPLAY"); g(290, 1)
            g(9, "$HANDSEED"); g(5, String(nextHandle + 1, radix: 16, uppercase: true))
            g(0, "ENDSEC")
        }

        mutating func classes() { g(0, "SECTION"); g(2, "CLASSES"); g(0, "ENDSEC") }

        mutating func tableHead(_ name: String, _ handle: String, _ count: Int) {
            g(0, "TABLE"); g(2, name); g(5, handle); g(330, "0"); g(100, "AcDbSymbolTable"); g(70, count)
        }
        mutating func record(_ type: String, _ owner: String, _ sub: String, handleCode: Int = 5, handle: String? = nil) {
            g(0, type); g(handleCode, handle ?? h()); g(330, owner); g(100, "AcDbSymbolTableRecord"); g(100, sub)
        }

        var exportLinetypes: [Linetype] {
            doc.linetypes.filter { !["continuous", "bylayer", "byblock"].contains($0.name.lowercased()) }
        }

        mutating func tables() {
            g(0, "SECTION"); g(2, "TABLES")
            // VPORT
            tableHead("VPORT", "8", 1)
            let b = GeometryOps.bounds(of: doc, includeElements: true)
            record("VPORT", "8", "AcDbViewportTableRecord")
            g(2, "*Active"); g(70, 0)
            g(10, 0.0); g(20, 0.0); g(11, 1.0); g(21, 1.0)
            g(12, b.isEmpty ? 0 : b.center.x); g(22, b.isEmpty ? 0 : b.center.y)
            g(13, 0.0); g(23, 0.0); g(14, 10.0); g(24, 10.0); g(15, 10.0); g(25, 10.0)
            g(16, 0.0); g(26, 0.0); g(36, 1.0); g(17, 0.0); g(27, 0.0); g(37, 0.0)
            g(40, b.isEmpty ? 1000 : max(b.height, b.width / 1.6, 1) * 1.1); g(41, 1.6); g(42, 50.0)
            g(43, 0.0); g(44, 0.0); g(50, 0.0); g(51, 0.0)
            g(71, 0); g(72, 100); g(73, 1); g(74, 3); g(75, 0); g(76, 0); g(77, 0); g(78, 0)
            g(0, "ENDTAB")
            // LTYPE
            let lts = exportLinetypes
            tableHead("LTYPE", "5", lts.count + 3)
            for (hd, n) in [("14", "ByBlock"), ("15", "ByLayer"), ("16", "Continuous")] {
                record("LTYPE", "5", "AcDbLinetypeTableRecord", handle: hd)
                g(2, n); g(70, 0); g(3, n == "Continuous" ? "Solid line" : ""); g(72, 65); g(73, 0); g(40, 0.0)
            }
            for lt in lts {
                record("LTYPE", "5", "AcDbLinetypeTableRecord")
                g(2, DXFWriter.enc(DXFWriter.safeName(lt.name))); g(70, 0); g(3, DXFWriter.enc(lt.description)); g(72, 65)
                g(73, lt.pattern.count); g(40, lt.pattern.reduce(0) { $0 + abs($1) })
                for e in lt.pattern { g(49, e); g(74, 0) }
            }
            g(0, "ENDTAB")
            // LAYER
            var layers = doc.layers
            if !layers.contains(where: { $0.name == "0" }) { layers.insert(Layer(name: "0"), at: 0) }
            tableHead("LAYER", "2", layers.count)
            for l in layers {
                record("LAYER", "2", "AcDbLayerTableRecord", handle: l.name == "0" ? "10" : nil)
                g(2, DXFWriter.enc(DXFWriter.safeName(l.name)))
                g(70, (l.frozen ? 1 : 0) | (l.locked ? 4 : 0))
                let aci = DXFWriter.nearestACI(l.color)
                g(62, l.visible ? aci : -aci)
                if !DXFColors.rgba(aci: aci).isNear(l.color) { g(420, DXFWriter.trueColor(l.color)) }
                g(6, linetypeName(l.linetype) ?? "Continuous")
                if !l.plot { g(290, 0) }
                g(370, DXFWriter.lineweightCode(l.lineweight))
                if l.transparency > 1e-9 {
                    let pct = l.transparency > 1 ? l.transparency : l.transparency * 100
                    g(1001, "AcCmTransparency"); g(1071, DXFColors.transparencyCode(percent: pct))
                }
            }
            g(0, "ENDTAB")
            // STYLE
            var styles = doc.textStyles
            if !styles.contains(where: { $0.name.lowercased() == "standard" }) { styles.insert(TextStyle(name: "Standard"), at: 0) }
            tableHead("STYLE", "3", styles.count)
            for s in styles {
                record("STYLE", "3", "AcDbTextStyleTableRecord")
                g(2, DXFWriter.enc(DXFWriter.safeName(s.name))); g(70, 0); g(40, s.height); g(41, s.widthFactor == 0 ? 1 : s.widthFactor)
                g(50, deg(s.oblique)); g(71, 0); g(42, 2.5)
                let original = doc.variable("DXFFONT:" + s.name)
                let keep = original.map { DXFFonts.family(fromFile: $0).caseInsensitiveCompare(s.font) == .orderedSame } ?? false
                let font = DXFFonts.file(forFamily: s.font, original: keep ? original : nil)
                g(3, DXFWriter.enc(font)); g(4, "")
                if font.lowercased().hasSuffix(".ttf") || font.lowercased().hasSuffix(".otf") {
                    let lower = s.font.lowercased()
                    var face = s.font.isEmpty ? "Arial" : s.font
                    var flags = 34
                    if lower.hasSuffix(" bold") { face = String(face.dropLast(5)); flags |= 0x2000000 }
                    if lower.hasSuffix(" italic") { face = String(face.dropLast(7)); flags |= 0x1000000 }
                    if lower == "helvetica" { face = "Arial" }
                    g(1001, "ACAD"); g(1000, DXFWriter.enc(face)); g(1071, flags)
                }
            }
            g(0, "ENDTAB")
            // VIEW, UCS
            tableHead("VIEW", "6", 0); g(0, "ENDTAB")
            tableHead("UCS", "7", 0); g(0, "ENDTAB")
            // APPID
            var apps = DXFXData.appNames(doc).filter { $0.uppercased() != "ACAD" }
            if doc.layers.contains(where: { $0.transparency > 1e-9 }) { apps.append("AcCmTransparency") }
            if !doc.dimStyles.isEmpty && !apps.contains(DXFXData.app) { apps.append(DXFXData.app) }
            tableHead("APPID", "9", 1 + apps.count)
            record("APPID", "9", "AcDbRegAppTableRecord", handle: "12"); g(2, "ACAD"); g(70, 0)
            for a in apps { record("APPID", "9", "AcDbRegAppTableRecord"); g(2, DXFWriter.enc(a)); g(70, 0) }
            g(0, "ENDTAB")
            // DIMSTYLE
            g(0, "TABLE"); g(2, "DIMSTYLE"); g(5, "A"); g(330, "0"); g(100, "AcDbSymbolTable"); g(70, doc.dimStyles.count)
            g(100, "AcDbDimStyleTable"); g(71, 0)
            for ds in doc.dimStyles {
                record("DIMSTYLE", "A", "AcDbDimStyleTableRecord", handleCode: 105)
                g(2, DXFWriter.enc(DXFWriter.safeName(ds.name))); g(70, 0)
                if !ds.prefix.isEmpty || !ds.suffix.isEmpty { g(3, DXFWriter.enc(ds.prefix + "<>" + ds.suffix)) }
                g(40, ds.scale); g(41, ds.arrowSize); g(42, ds.extensionOffset); g(44, ds.extensionExtend)
                if ds.arrow == .architecturalTick || ds.arrow == .tick { g(142, ds.arrowSize) }
                g(144, ds.linearScale); g(140, ds.textHeight); g(147, ds.textGap)
                g(77, 1); g(271, ds.decimals); g(272, ds.decimals)
                g(1001, DXFXData.app); g(1000, "arrow=" + ds.arrow.rawValue)
            }
            g(0, "ENDTAB")
            // BLOCK_RECORD
            let names = Array(blockRecordHandles.keys).filter { $0 != "*Model_Space" && $0 != "*Paper_Space" }.sorted { (blockRecordHandles[$0]!.count, blockRecordHandles[$0]!) < (blockRecordHandles[$1]!.count, blockRecordHandles[$1]!) }
            tableHead("BLOCK_RECORD", "1", names.count + 2)
            record("BLOCK_RECORD", "1", "AcDbBlockTableRecord", handle: "1F"); g(2, "*Model_Space")
            record("BLOCK_RECORD", "1", "AcDbBlockTableRecord", handle: "1E"); g(2, "*Paper_Space")
            for n in names {
                record("BLOCK_RECORD", "1", "AcDbBlockTableRecord", handle: blockRecordHandles[n]); g(2, DXFWriter.enc(n))
            }
            g(0, "ENDTAB")
            g(0, "ENDSEC")
        }

        func linetypeName(_ n: String?) -> String? {
            guard let n = n else { return nil }
            switch n.lowercased() {
            case "bylayer": return "ByLayer"
            case "byblock": return "ByBlock"
            case "continuous": return "Continuous"
            default:
                guard let lt = doc.linetype(n) else { return nil }
                return DXFWriter.enc(DXFWriter.safeName(lt.name))
            }
        }

        mutating func blockBegin(_ name: String, owner: String, base: Vec2, flags: Int, paper: Bool = false, handle: String? = nil) {
            g(0, "BLOCK"); g(5, handle ?? h()); g(330, owner); g(100, "AcDbEntity")
            if paper { g(67, 1) }
            g(8, "0"); g(100, "AcDbBlockBegin"); g(2, DXFWriter.enc(name)); g(70, flags); pt(10, base); g(3, DXFWriter.enc(name)); g(1, "")
        }
        mutating func blockEnd(owner: String, paper: Bool = false, handle: String? = nil) {
            g(0, "ENDBLK"); g(5, handle ?? h()); g(330, owner); g(100, "AcDbEntity")
            if paper { g(67, 1) }
            g(8, "0"); g(100, "AcDbBlockEnd")
        }

        mutating func blocks(_ sorted: [String]) {
            g(0, "SECTION"); g(2, "BLOCKS")
            blockBegin("*Model_Space", owner: "1F", base: .zero, flags: 0, handle: "20"); blockEnd(owner: "1F", handle: "21")
            blockBegin("*Paper_Space", owner: "1E", base: .zero, flags: 0, paper: true, handle: "1C"); blockEnd(owner: "1E", paper: true, handle: "1D")
            // user blocks consume dimension blocks after model space: skip model-space dims in the cursor
            let modelDims = doc.entities.filter { if case .dimension = $0.geometry { return true }; return false }.count
            dimCursor = modelDims
            for name in sorted {
                let b = doc.blocks[name]!
                let n = blockNames[name]!
                let owner = blockRecordHandles[n]!
                blockBegin(n, owner: owner, base: b.basePoint, flags: n.hasPrefix("*") ? 1 : 0)
                for e in b.entities { entity(e, owner: owner) }
                blockEnd(owner: owner)
            }
            for (i, l) in doc.layouts.enumerated() where i > 0 {
                let owner = layoutRecords[i]
                blockBegin("*Paper_Space\(i - 1)", owner: owner, base: .zero, flags: 0, paper: true)
                layoutContent(l, owner: owner)
                blockEnd(owner: owner, paper: true)
            }
            for d in dimBlocks {
                let owner = blockRecordHandles[d.name]!
                blockBegin(d.name, owner: owner, base: .zero, flags: 1)
                dimensionPrimitives(d.dim, layer: d.layer, owner: owner)
                blockEnd(owner: owner)
            }
            dimCursor = 0
            g(0, "ENDSEC")
        }

        mutating func entitiesSection(levels: Set<Int>?) {
            g(0, "SECTION"); g(2, "ENTITIES")
            for e in doc.entities { entity(e, owner: "1F") }
            for el in doc.elements where levels == nil || levels!.contains(el.level) { element(el) }
            if let l0 = doc.layouts.first {
                dimCursor = paperDimStart
                layoutContent(l0, owner: "1E")
            }
            g(0, "ENDSEC")
        }

        /// Paper-space content of a sheet: the overall paper viewport (id 1), the model viewports and the annotation entities.
        mutating func layoutContent(_ l: Layout, owner: String) {
            paperSpace = true
            defer { paperSpace = false }
            let paper = Vec2(l.paper.width, l.paper.height)
            viewport(Viewport(origin: .zero, size: paper, viewCenter: paper / 2, scale: 1), id: 1, owner: owner)
            for (k, v) in l.viewports.enumerated() { viewport(v, id: k + 2, owner: owner) }
            for e in l.entities { entity(e, owner: owner) }
        }

        /// VIEWPORT entity: paper centre/size, model view centre, view height = paper height × scale. View kind, level and
        /// title travel as Archi XDATA.
        mutating func viewport(_ v: Viewport, id: Int, owner: String) {
            let w = max(abs(v.size.x), 1e-6), hgt = max(abs(v.size.y), 1e-6)
            let c = v.origin + Vec2(w, hgt) / 2
            if id > 1 {
                var p: [String: String] = ["vpView": v.view.rawValue]
                if let lv = v.level { p["vpLevel"] = "\(lv)" }
                if !v.title.isEmpty { p["vpTitle"] = v.title }
                armedXData = DXFXData.groups(p, enc: DXFWriter.enc)
            }
            head("VIEWPORT", Style(layer: "0"), owner: owner, sub: "AcDbViewport")
            pt(10, c); g(40, w); g(41, hgt); g(68, id == 1 ? 1 : 2); g(69, id)
            g(12, v.viewCenter.x); g(22, v.viewCenter.y)
            g(13, 0.0); g(23, 0.0); g(14, 10.0); g(24, 10.0); g(15, 10.0); g(25, 10.0)
            g(16, 0.0); g(26, 0.0); g(36, 1.0); g(17, 0.0); g(27, 0.0); g(37, 0.0)
            g(42, 50.0); g(43, 0.0); g(44, 0.0); g(45, hgt * v.scale); g(50, 0.0); g(51, 0.0); g(72, 1000); g(90, 32864)
            g(1, ""); g(281, 0); g(71, 1); g(74, 0); g(110, 0.0); g(120, 0.0); g(130, 0.0)
            g(111, 1.0); g(121, 0.0); g(131, 0.0); g(112, 0.0); g(122, 1.0); g(132, 0.0); g(79, 0); g(146, 0.0)
        }

        mutating func objects() {
            g(0, "SECTION"); g(2, "OBJECTS")
            let dictHandle = "1A"
            let modelLayout = h()
            var layoutHandles: [String] = []
            for _ in doc.layouts { layoutHandles.append(h()) }
            g(0, "DICTIONARY"); g(5, "C"); g(330, "0"); g(100, "AcDbDictionary"); g(281, 1)
            g(3, "ACAD_GROUP"); g(350, "D"); g(3, "ACAD_LAYOUT"); g(350, dictHandle)
            g(0, "DICTIONARY"); g(5, "D"); g(330, "C"); g(100, "AcDbDictionary"); g(281, 1)
            g(0, "DICTIONARY"); g(5, dictHandle); g(330, "C"); g(100, "AcDbDictionary"); g(281, 1)
            g(3, "Model"); g(350, modelLayout)
            var usedNames = Set<String>(["MODEL"])
            var layoutNames: [String] = []
            for l in doc.layouts {
                var n = DXFWriter.safeName(l.name.isEmpty ? "Layout" : l.name)
                while usedNames.contains(n.uppercased()) { n += "_" }
                usedNames.insert(n.uppercased()); layoutNames.append(n)
            }
            for (i, n) in layoutNames.enumerated() { g(3, DXFWriter.enc(n)); g(350, layoutHandles[i]) }
            layoutObject(name: "Model", handle: modelLayout, dict: dictHandle, tab: 0, record: "1F", paper: PaperSize(name: "A3", width: 420, height: 297), titleBlock: nil)
            for (i, l) in doc.layouts.enumerated() {
                layoutObject(name: layoutNames[i], handle: layoutHandles[i], dict: dictHandle, tab: i + 1, record: layoutRecords[i], paper: l.paper, titleBlock: l.titleBlock)
            }
            g(0, "ENDSEC")
        }

        /// LAYOUT object (AcDbPlotSettings + AcDbLayout). Paper size in mm (44/45); the title block travels as Archi XDATA.
        mutating func layoutObject(name: String, handle: String, dict: String, tab: Int, record: String, paper: PaperSize, titleBlock: [String: String]?) {
            g(0, "LAYOUT"); g(5, handle); g(102, "{ACAD_REACTORS"); g(330, dict); g(102, "}"); g(330, dict)
            g(100, "AcDbPlotSettings"); g(1, ""); g(2, "none_device"); g(4, DXFWriter.enc(paper.name))
            g(6, ""); g(40, 0.0); g(41, 0.0); g(42, 0.0); g(43, 0.0); g(44, paper.width); g(45, paper.height)
            g(46, 0.0); g(47, 0.0); g(48, 0.0); g(49, 0.0); g(140, 0.0); g(141, 0.0); g(142, 1.0); g(143, 1.0)
            g(70, 688); g(72, 1); g(73, 0); g(74, 5); g(7, ""); g(75, 16); g(147, 1.0); g(148, 0.0); g(149, 0.0)
            g(100, "AcDbLayout"); g(1, DXFWriter.enc(name)); g(70, 1); g(71, tab)
            g(10, 0.0); g(20, 0.0); g(11, paper.width); g(21, paper.height)
            g(12, 0.0); g(22, 0.0); g(32, 0.0); g(14, 0.0); g(24, 0.0); g(34, 0.0); g(15, paper.width); g(25, paper.height); g(35, 0.0)
            g(146, 0.0); g(13, 0.0); g(23, 0.0); g(33, 0.0); g(16, 1.0); g(26, 0.0); g(36, 0.0); g(17, 0.0); g(27, 1.0); g(37, 0.0)
            g(76, 0); g(330, record)
            if let tb = titleBlock {
                var p: [String: String] = ["archiLayout": "1"]
                for (k, v) in tb { p["tb:" + k] = v }
                for (c, v) in DXFXData.groups(p, enc: DXFWriter.enc) { g(c, v) }
            }
        }

        // MARK: entities

        struct Style { var layer: String; var color: ColorRef = .byLayer; var linetype: String? = nil; var lineweight: Double? = nil }

        mutating func head(_ type: String, _ s: Style, owner: String, sub: String) {
            g(0, type); g(5, h()); g(330, owner); g(100, "AcDbEntity")
            if paperSpace { g(67, 1) }
            g(8, DXFWriter.enc(DXFWriter.safeName(s.layer)))
            if let lt = linetypeName(s.linetype), lt != "ByLayer" { g(6, lt) }
            switch s.color {
            case .byLayer: break
            case .byBlock: g(62, 0)
            case .aci(let i): g(62, max(0, min(256, i)))
            case .rgb(let r, let gg, let b):
                let c = RGBA(Double(r) / 255, Double(gg) / 255, Double(b) / 255)
                g(62, DXFWriter.nearestACI(c)); g(420, Int(r) << 16 | Int(gg) << 8 | Int(b))
            }
            if let lw = s.lineweight { g(370, DXFWriter.lineweightCode(lw)) }
            if let t = entityTransparency { g(440, t) }
            g(100, sub)
            if let x = armedXData { pendingXData = x; armedXData = nil }
        }

        mutating func entity(_ e: Entity, owner: String) {
            let s = Style(layer: e.layer, color: e.color, linetype: e.linetype, lineweight: e.lineweight)
            elevation = DXFWriter.elevation(of: e)
            entityProps = e.props
            let x = DXFXData.groups(e.props, enc: DXFWriter.enc)
            armedXData = x.isEmpty ? nil : x
            entityTransparency = e.props["transparency"].flatMap { Double($0) }.map { DXFColors.transparencyCode(percent: $0) }
            defer { entityProps = [:]; armedXData = nil; entityTransparency = nil }
            geometry(e.geometry, s, owner: owner)
            elevation = 0
            // Toposurfaces also get their contour lines as polylines at their elevation (readable by TOPO Contours).
            if e.props["topo"] == "1", case .solid(let sol) = e.geometry {
                for c in DXFWriter.topoContours(sol, props: e.props) {
                    elevation = c.z
                    for l in c.lines where l.count >= 2 {
                        let closed = l.count > 3 && l[0].isClose(l[l.count - 1], tol: 1e-9)
                        lwpolyline((closed ? Array(l.dropLast()) : l).map { PolyVertex($0) }, closed: closed, width: 0, s, owner: owner)
                    }
                }
                elevation = 0
            }
        }

        mutating func geometry(_ geo: Geometry, _ s: Style, owner: String) {
            switch geo {
            case .point(let p):
                head("POINT", s, owner: owner, sub: "AcDbPoint"); pt(10, p, elevation)
            case .line(let l):
                head("LINE", s, owner: owner, sub: "AcDbLine"); pt(10, l.a, elevation); pt(11, l.b, elevation)
            case .circle(let c):
                head("CIRCLE", s, owner: owner, sub: "AcDbCircle"); pt(10, c.center, elevation); g(40, c.radius)
            case .arc(let a):
                head("ARC", s, owner: owner, sub: "AcDbCircle"); pt(10, a.center, elevation); g(40, a.radius)
                g(100, "AcDbArc"); g(50, deg(normAngle(a.start))); g(51, deg(normAngle(a.end)))
            case .ellipse(let e):
                var major = e.majorAxis, ratio = e.ratio, s0 = e.start, e0 = e.end
                if ratio > 1 { major = e.majorAxis.perp * ratio; ratio = 1 / ratio; s0 -= .pi / 2; e0 -= .pi / 2 }
                head("ELLIPSE", s, owner: owner, sub: "AcDbEllipse"); pt(10, e.center); pt(11, major)
                g(210, 0.0); g(220, 0.0); g(230, 1.0)
                g(40, max(1e-6, ratio))
                if e.isFull { g(41, 0.0); g(42, 2 * Double.pi) } else { g(41, normAngle(s0)); g(42, normAngle(e0)) }
            case .polyline(let p):
                lwpolyline(p.vertices, closed: p.closed, width: p.width, s, owner: owner)
            case .spline(let sp):
                spline(sp, s, owner: owner)
            case .text(let t):
                if let tag = entityProps["attdef"], !tag.isEmpty { attdef(t, tag: tag, s, owner: owner) } else { text(t, s, owner: owner) }
            case .dimension(let d):
                dimension(d, s, owner: owner)
            case .hatch(let hg):
                hatch(hg.loops, pattern: hg.pattern, scale: hg.scale, angle: hg.angle, s, owner: owner)
            case .insert(let ins):
                guard let n = blockNames[ins.block] else { return }
                head("INSERT", s, owner: owner, sub: "AcDbBlockReference")
                if !ins.attributes.isEmpty { g(66, 1) }
                g(2, DXFWriter.enc(n)); pt(10, ins.position)
                g(41, ins.scale.x); g(42, ins.scale.y); g(43, 1.0); g(50, deg(ins.rotation))
                if !ins.attributes.isEmpty {
                    var y = 0.0
                    // Attribute definitions of the block give each ATTRIB its place, height and visibility.
                    var defs: [String: (TextGeom, Bool)] = [:]
                    let blk = doc.blocks[ins.block]
                    for e in blk?.entities ?? [] {
                        if let tag = e.props["attdef"], case .text(let t) = e.geometry { defs[tag.uppercased()] = (t, e.props["invisible"] == "1") }
                    }
                    for (tag, value) in ins.attributes.sorted(by: { $0.key < $1.key }) {
                        var pos = ins.position + Vec2(0, y), hgt = 2.5, rot = ins.rotation, invisible = false
                        var ha = 0, va = 0
                        if let (t, inv) = defs[tag.uppercased()] {
                            pos = ins.transform.apply(t.position - (blk?.basePoint ?? .zero))
                            hgt = t.height * abs(ins.scale.y); rot = t.rotation + ins.rotation; invisible = inv
                            ha = t.halign == .left ? 0 : (t.halign == .center ? 1 : 2)
                            switch t.valign { case .baseline: va = 0; case .bottom: va = 1; case .middle: va = 2; case .top: va = 3 }
                        } else { y -= 3.75 }
                        head("ATTRIB", s, owner: owner, sub: "AcDbText")
                        pt(10, pos); g(40, hgt); g(1, DXFWriter.enc(value))
                        if abs(rot) > 1e-12 { g(50, deg(normAngle(rot))) }
                        if ha != 0 { g(72, ha) }
                        if ha != 0 || va != 0 { pt(11, pos) }
                        g(100, "AcDbAttribute"); g(2, DXFWriter.enc(DXFWriter.safeName(tag).replacingOccurrences(of: " ", with: "_"))); g(70, invisible ? 1 : 0)
                        if va != 0 { g(74, va) }
                    }
                    g(0, "SEQEND"); g(5, h()); g(330, owner); g(100, "AcDbEntity"); g(8, DXFWriter.enc(DXFWriter.safeName(s.layer)))
                }
            case .leader(let l):
                guard l.points.count >= 2 else { return }
                head("LEADER", s, owner: owner, sub: "AcDbLeader")
                g(3, DXFWriter.enc(DXFWriter.safeName(doc.currentDimStyle))); g(71, 1); g(72, 0); g(73, 3); g(74, 0); g(75, 0)
                g(40, l.textHeight); g(41, 0.0); g(76, l.points.count)
                for p in l.points { pt(10, p) }
                if !l.text.isEmpty, let last = l.points.last {
                    let prev = l.points[l.points.count - 2]
                    let right = last.x >= prev.x
                    text(TextGeom(position: last + Vec2(right ? l.textHeight * 0.5 : -l.textHeight * 0.5, 0), height: l.textHeight, content: l.text,
                                  halign: right ? .left : .right, valign: .middle), s, owner: owner)
                }
            case .image(let im):
                let t = Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation)
                let pts = [Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y)].map(t.apply)
                lwpolyline(pts.map { PolyVertex($0) }, closed: true, width: 0, s, owner: owner)
            case .table(let tb):
                let w = tb.columnWidths.reduce(0, +), rows = tb.cells.count
                let o = tb.origin
                for r in 0...rows { geometry(.line(LineGeom(o + Vec2(0, -Double(r) * tb.rowHeight), o + Vec2(w, -Double(r) * tb.rowHeight))), s, owner: owner) }
                var x = 0.0
                for c in 0...tb.columnWidths.count {
                    geometry(.line(LineGeom(o + Vec2(x, 0), o + Vec2(x, -Double(rows) * tb.rowHeight))), s, owner: owner)
                    if c < tb.columnWidths.count { x += tb.columnWidths[c] }
                }
                for (r, row) in tb.cells.enumerated() {
                    var cx = 0.0
                    for (c, cell) in row.enumerated() where c < tb.columnWidths.count {
                        if !cell.isEmpty {
                            text(TextGeom(position: o + Vec2(cx + tb.textHeight * 0.5, -(Double(r) + 0.5) * tb.rowHeight), height: tb.textHeight, content: cell, valign: .middle), s, owner: owner)
                        }
                        cx += tb.columnWidths[c]
                    }
                }
            case .solid(let sol):
                let groups = MeshBuilder.groups(for: Entity(id: 0, layer: s.layer, geometry: geo), doc: doc)
                var faces: [(Vec3, Vec3, Vec3)] = []
                for gr in groups {
                    let m = gr.mesh
                    var k = 0
                    while k + 2 < m.indices.count {
                        faces.append((m.positions[Int(m.indices[k])], m.positions[Int(m.indices[k + 1])], m.positions[Int(m.indices[k + 2])])); k += 3
                    }
                }
                if faces.isEmpty && sol.kind == .mesh {
                    var k = 0
                    while k + 2 < sol.meshTriangles.count {
                        let v = sol.meshVertices
                        let a = sol.meshTriangles[k], b = sol.meshTriangles[k + 1], c = sol.meshTriangles[k + 2]
                        if a < v.count && b < v.count && c < v.count { faces.append((v[a], v[b], v[c])) }
                        k += 3
                    }
                }
                if faces.isEmpty {
                    let fp = GeometryOps.solidFootprint(sol)
                    lwpolyline(fp.map { PolyVertex($0) }, closed: true, width: 0, s, owner: owner)
                } else {
                    for f in faces {
                        head("3DFACE", s, owner: owner, sub: "AcDbFace")
                        g(10, f.0.x); g(20, f.0.y); g(30, f.0.z)
                        g(11, f.1.x); g(21, f.1.y); g(31, f.1.z)
                        g(12, f.2.x); g(22, f.2.y); g(32, f.2.z)
                        g(13, f.2.x); g(23, f.2.y); g(33, f.2.z)
                    }
                }
            }
        }

        mutating func lwpolyline(_ v0: [PolyVertex], closed: Bool, width: Double, _ s: Style, owner: String) {
            var v = v0
            var closed = closed
            if v.count > 2, v[0].p.isClose(v[v.count - 1].p, tol: 1e-9) { v.removeLast(); closed = true }
            guard !v.isEmpty else { return }
            head("LWPOLYLINE", s, owner: owner, sub: "AcDbPolyline")
            g(90, v.count); g(70, closed ? 1 : 0)
            if width != 0 { g(43, width) }
            if elevation != 0 { g(38, elevation) }
            for (i, p) in v.enumerated() {
                g(10, p.p.x); g(20, p.p.y)
                if p.bulge != 0 && (closed || i < v.count - 1) { g(42, p.bulge) }
            }
        }

        mutating func spline(_ sp: SplineGeom, _ s: Style, owner: String) {
            if sp.controlPoints.count < 2 {
                let pts = GeometryOps.splinePoints(sp)
                lwpolyline(pts.map { PolyVertex($0) }, closed: sp.closed, width: 0, s, owner: owner); return
            }
            let n = sp.controlPoints.count
            let p = max(1, min(sp.degree, n - 1))
            var knots = sp.knots
            if knots.count != n + p + 1 {
                knots = Array(repeating: 0, count: p + 1)
                let inner = n - p - 1
                if inner > 0 { for i in 1...inner { knots.append(Double(i) / Double(inner + 1)) } }
                knots += Array(repeating: 1, count: p + 1)
            }
            let rational = sp.weights.map { $0.count == n } ?? false
            head("SPLINE", s, owner: owner, sub: "AcDbSpline")
            g(210, 0.0); g(220, 0.0); g(230, 1.0)
            g(70, 8 | (sp.closed ? 1 : 0) | (rational ? 4 : 0)); g(71, p); g(72, knots.count); g(73, n); g(74, sp.fitPoints.count)
            g(42, 1e-10); g(43, 1e-10); g(44, 1e-10)
            for k in knots { g(40, k) }
            if rational, let w = sp.weights { for x in w { g(41, x) } }
            for c in sp.controlPoints { pt(10, c) }
            for f in sp.fitPoints { pt(11, f) }
        }

        static func mtextEscape(_ s: String) -> String {
            var out = ""
            for ch in s {
                switch ch {
                case "\\": out += "\\\\"
                case "{": out += "\\{"
                case "}": out += "\\}"
                case "\n": out += "\\P"
                default: out.append(ch)
                }
            }
            return out
        }

        /// Block attribute definition (tag, prompt, default value, invisible flag).
        mutating func attdef(_ t: TextGeom, tag: String, _ s: Style, owner: String) {
            head("ATTDEF", s, owner: owner, sub: "AcDbText")
            pt(10, t.position); g(40, t.height); g(1, DXFWriter.enc(entityProps["default"] ?? ""))
            if t.rotation != 0 { g(50, deg(normAngle(t.rotation))) }
            g(7, DXFWriter.enc(DXFWriter.safeName(t.style.isEmpty ? "Standard" : t.style)))
            let ha: Int = t.halign == .left ? 0 : (t.halign == .center ? 1 : 2)
            let va: Int
            switch t.valign { case .baseline: va = 0; case .bottom: va = 1; case .middle: va = 2; case .top: va = 3 }
            if ha != 0 { g(72, ha) }
            if ha != 0 || va != 0 { pt(11, t.position) }
            g(100, "AcDbAttributeDefinition")
            g(3, DXFWriter.enc(entityProps["prompt"] ?? tag)); g(2, DXFWriter.enc(DXFWriter.safeName(tag).replacingOccurrences(of: " ", with: "_")))
            g(70, entityProps["invisible"] == "1" ? 1 : 0)
            if va != 0 { g(74, va) }
        }

        mutating func text(_ t: TextGeom, _ s: Style, owner: String) {
            let style = DXFWriter.enc(DXFWriter.safeName(t.style.isEmpty ? "Standard" : t.style))
            if t.content.contains("\n") || t.width > 0 || entityProps["mtext"] != nil || entityProps[DraftRendering.textMaskProp] != nil {
                head("MTEXT", s, owner: owner, sub: "AcDbMText")
                // Columns (ANN-006) travel as the R2007+ ACAD XDATA block, which R2000 readers ignore safely.
                if let spec = entityProps[DraftRendering.textColumnsProp], let c = MTextCodes.columns(spec: spec, text: t) {
                    pendingXData += MTextCodes.columnXData(c).map { ($0.code, DXFWriter.enc($0.value)) }
                }
                pt(10, t.position); g(40, t.height)
                if t.width > 0 { g(41, t.width) }
                let col: Int = t.halign == .left ? 1 : (t.halign == .center ? 2 : 3)
                let row: Int = (t.valign == .top) ? 0 : (t.valign == .middle ? 1 : 2)
                g(71, row * 3 + col); g(72, 1)
                // Stacks (\S…;), list paragraphs and escapes go through the shared MTEXT codec (ANN-005/006).
                var content = DXFWriter.enc(MTextCodes.encode(t.content).replacingOccurrences(of: "\\U+", with: "\u{1}"))
                content = content.replacingOccurrences(of: "\u{1}", with: "\\U+")
                if let raw = entityProps["mtext"], DXFReader.mtextContent(raw) == t.content { content = DXFWriter.enc(raw) }
                var chunks: [String] = []
                var cur = ""
                for ch in content { cur.append(ch); if cur.count >= 240 && ch != "\\" { chunks.append(cur); cur = "" } }
                for c in chunks { g(3, c) }
                g(1, cur)
                g(7, style)
                g(11, cos(t.rotation)); g(21, sin(t.rotation)); g(31, 0.0)
                // Background mask (ANN-013).
                for (code, v) in TextMaskExchange.mtextGroups(entityProps) { g(code, v) }
                return
            }
            head("TEXT", s, owner: owner, sub: "AcDbText")
            pt(10, t.position); g(40, t.height); g(1, DXFWriter.enc(t.content))
            if t.rotation != 0 { g(50, deg(normAngle(t.rotation))) }
            g(7, style)
            let ha: Int = t.halign == .left ? 0 : (t.halign == .center ? 1 : 2)
            let va: Int
            switch t.valign { case .baseline: va = 0; case .bottom: va = 1; case .middle: va = 2; case .top: va = 3 }
            if ha != 0 { g(72, ha) }
            if ha != 0 || va != 0 { pt(11, t.position) }
            g(100, "AcDbText")
            if va != 0 { g(73, va) }
        }

        mutating func dimension(_ d: DimensionGeom, _ s: Style, owner: String) {
            guard dimCursor < dimBlocks.count else { return }
            let blockName = dimBlocks[dimCursor].name
            dimCursor += 1
            let pts = d.points
            let style = doc.dimStyle(d.style)
            let prims = DimensionRenderer.primitives(d, style: style)
            func pad(_ i: Int) -> Vec2 { i < pts.count ? pts[i] : (pts.last ?? .zero) }
            var textMid = prims.text?.position ?? (pts.isEmpty ? .zero : pts.reduce(Vec2.zero, +) / Double(pts.count))
            if pts.isEmpty { return }
            var type = 0
            var defPoint = pad(2)
            switch d.kind {
            case .linear:
                let (theta, p10) = linearFrame(d)
                defPoint = p10; type = 0
                _ = theta
            case .aligned:
                let a = pad(0), b = pad(1), l = pad(2)
                let n = (b - a).normalized.perp
                defPoint = n == .zero ? l : b + n * (l - b).dot(n); type = 1
            case .angular: defPoint = pad(3); type = 5
            case .diameter: defPoint = pad(0) * 2 - pad(1); type = 3
            case .radius: defPoint = pad(0); type = 4
            case .ordinate: defPoint = pad(2); type = 6 | ((d.rotation ?? .pi / 2) == 0 ? 64 : 0)
            case .arcLength:
                head("INSERT", s, owner: owner, sub: "AcDbBlockReference"); g(2, blockName); pt(10, .zero)
                return
            }
            if prims.text == nil, d.kind == .radius || d.kind == .diameter { textMid = pad(2) }
            head("DIMENSION", s, owner: owner, sub: "AcDbDimension")
            g(2, blockName); pt(10, defPoint); pt(11, textMid); g(70, type | 32)
            if let o = d.textOverride { g(1, DXFWriter.enc(o)) }
            g(3, DXFWriter.enc(DXFWriter.safeName(d.style)))
            let meas = DimensionRenderer.measurement(d)
            if meas != 0 { g(42, meas) }
            switch d.kind {
            case .linear:
                g(100, "AcDbAlignedDimension"); pt(13, pad(0)); pt(14, pad(1))
                g(50, deg(linearFrame(d).0)); g(100, "AcDbRotatedDimension")
            case .aligned:
                g(100, "AcDbAlignedDimension"); pt(13, pad(0)); pt(14, pad(1))
            case .angular:
                g(100, "AcDb3PointAngularDimension"); pt(13, pad(1)); pt(14, pad(2)); pt(15, pad(0))
            case .diameter:
                g(100, "AcDbDiametricDimension"); pt(15, pad(1)); g(40, 0.0)
            case .radius:
                g(100, "AcDbRadialDimension"); pt(15, pad(1)); g(40, 0.0)
            case .ordinate:
                g(100, "AcDbOrdinateDimension"); pt(13, pad(0)); pt(14, pad(1))
            case .arcLength: break
            }
        }

        /// Rotation of a linear dimension and the definition point on its dimension line.
        func linearFrame(_ d: DimensionGeom) -> (Double, Vec2) {
            let a = d.points.count > 0 ? d.points[0] : .zero
            let b = d.points.count > 1 ? d.points[1] : a
            let l = d.points.count > 2 ? d.points[2] : b
            var theta: Double
            if let r = d.rotation { theta = r } else {
                let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
                if l.x >= minX && l.x <= maxX { theta = 0 }
                else if l.y >= minY && l.y <= maxY { theta = .pi / 2 }
                else { theta = abs(b.x - a.x) >= abs(b.y - a.y) ? 0 : .pi / 2 }
            }
            let dir = Vec2(cos(theta), sin(theta))
            return (theta, l + dir * (b - l).dot(dir))
        }

        mutating func dimensionPrimitives(_ d: DimensionGeom, layer: String, owner: String) {
            let prims = DimensionRenderer.primitives(d, style: doc.dimStyle(d.style))
            let s = Style(layer: "0", color: .byBlock, linetype: "ByBlock", lineweight: nil)
            for l in prims.lines where l.count >= 2 {
                for i in 0..<(l.count - 1) where !l[i].isClose(l[i + 1]) { geometry(.line(LineGeom(l[i], l[i + 1])), s, owner: owner) }
            }
            for a in prims.arrows where a.count >= 3 {
                head("SOLID", s, owner: owner, sub: "AcDbTrace")
                pt(10, a[0]); pt(11, a[1]); pt(12, a.count > 3 ? a[3] : a[2]); pt(13, a[2])
            }
            for a in prims.arrows where a.count == 2 { geometry(.line(LineGeom(a[0], a[1])), s, owner: owner) }
            if var t = prims.text {
                if let o = d.textOverride, !o.isEmpty { t.content = o.replacingOccurrences(of: "<>", with: DimensionRenderer.formatted(d, style: doc.dimStyle(d.style))) }
                if !t.content.isEmpty {
                    head("MTEXT", s, owner: owner, sub: "AcDbMText")
                    pt(10, t.position); g(40, t.height)
                    let col: Int = t.halign == .left ? 1 : (t.halign == .center ? 2 : 3)
                    let row: Int = (t.valign == .top) ? 0 : (t.valign == .middle ? 1 : 2)
                    g(71, row * 3 + col); g(72, 1)
                    g(1, DXFWriter.enc(Writer.mtextEscape(t.content)))
                    g(11, cos(t.rotation)); g(21, sin(t.rotation)); g(31, 0.0)
                }
            }
        }

        mutating func hatch(_ loops: [[PolyVertex]], pattern: String, scale: Double, angle: Double, _ s: Style, owner: String) {
            let loops = loops.filter { $0.count >= 2 }
            guard !loops.isEmpty else { return }
            let pat = pattern.uppercased()
            let solid = pat == "SOLID" || pat.isEmpty
            let defs = solid ? [] : DXFWriter.patternDefinition(pat, doc: doc)
            head("HATCH", s, owner: owner, sub: "AcDbHatch")
            pt(10, .zero); g(210, 0.0); g(220, 0.0); g(230, 1.0)
            g(2, DXFWriter.enc(DXFWriter.safeName(solid ? "SOLID" : pat))); g(70, solid ? 1 : 0); g(71, 0); g(91, loops.count)
            for (li, loop0) in loops.enumerated() {
                var loop = loop0
                if loop.count > 2, loop[0].p.isClose(loop[loop.count - 1].p, tol: 1e-9) { loop.removeLast() }
                let hasBulge = loop.contains { $0.bulge != 0 }
                g(92, li == 0 ? 3 : 2); g(72, hasBulge ? 1 : 0); g(73, 1); g(93, loop.count)
                for v in loop { g(10, v.p.x); g(20, v.p.y); if hasBulge { g(42, v.bulge) } }
                g(97, 0)
            }
            g(75, 0); g(76, 1)
            if !solid {
                let sc = scale == 0 ? 1 : scale
                g(52, deg(angle)); g(41, sc); g(77, 0); g(78, defs.count)
                for d in defs {
                    let total = rad(d.0) + angle
                    let base = Vec2(d.1, d.2).rotated(by: angle) * sc
                    let off = Vec2(d.3, d.4).rotated(by: total) * sc
                    g(53, deg(total)); g(43, base.x); g(44, base.y); g(45, off.x); g(46, off.y); g(79, d.5.count)
                    for dash in d.5 { g(49, dash * sc) }
                }
            }
            g(98, 0)
        }

        // MARK: BIM elements

        mutating func element(_ el: BIMElement) {
            let layer = doc.layer(named: el.layer) ?? Layer(name: el.layer)
            var items = PlanRepresentation.items(el, doc: doc)
            if items.isEmpty { items = DXFWriter.fallbackPlan(el, doc: doc) }
            for it in items {
                switch it {
                case .stroke(let pts, let closed, let st):
                    guard pts.count >= 2 else { continue }
                    var s = Style(layer: el.layer)
                    if !st.color.isNear(layer.color) { s.color = .rgb(UInt8((st.color.r * 255).rounded()), UInt8((st.color.g * 255).rounded()), UInt8((st.color.b * 255).rounded())) }
                    if abs(st.lineweight - layer.lineweight) > 1e-6 { s.lineweight = st.lineweight }
                    if !st.dash.isEmpty, let lt = doc.linetypes.first(where: { $0.pattern == st.dash }) { s.linetype = lt.name }
                    else if !st.dash.isEmpty { s.linetype = "Dashed" }
                    lwpolyline(pts.map { PolyVertex($0) }, closed: closed, width: 0, s, owner: "1F")
                case .fill(let loops, let color):
                    var s = Style(layer: el.layer)
                    if !color.isNear(layer.color) { s.color = .rgb(UInt8((color.r * 255).rounded()), UInt8((color.g * 255).rounded()), UInt8((color.b * 255).rounded())) }
                    hatch(loops.map { $0.map { PolyVertex($0) } }, pattern: "SOLID", scale: 1, angle: 0, s, owner: "1F")
                case .text(let t, _, let color):
                    var s = Style(layer: el.layer)
                    if !color.isNear(layer.color) { s.color = .rgb(UInt8((color.r * 255).rounded()), UInt8((color.g * 255).rounded()), UInt8((color.b * 255).rounded())) }
                    text(t, s, owner: "1F")
                case .image: break
                }
            }
        }
    }

    /// Simple plan outlines used when no plan representation is available.
    static func fallbackPlan(_ el: BIMElement, doc: ArchiDocument) -> [DrawItem] {
        let color = doc.layer(named: el.layer)?.color ?? .white
        let lw = doc.layer(named: el.layer)?.lineweight ?? 0.25
        let st = StrokeStyle(color: color, lineweight: lw)
        func rect(_ c: Vec2, _ w: Double, _ d: Double, _ rot: Double) -> [Vec2] {
            let t = Transform2D.translation(c) * Transform2D.rotation(rot)
            return [Vec2(-w / 2, -d / 2), Vec2(w / 2, -d / 2), Vec2(w / 2, d / 2), Vec2(-w / 2, d / 2)].map(t.apply)
        }
        switch el.geometry {
        case .wall(let w):
            return [.stroke(points: wallOutline(w), closed: true, style: st)]
        case .slab(let s):
            return [.stroke(points: s.boundary, closed: true, style: st)] + s.holes.map { .stroke(points: $0, closed: true, style: st) }
        case .column(let c):
            if c.round { return [.stroke(points: GeometryOps.arcPoints(center: c.position, radius: c.width / 2, start: 0, sweep: 2 * .pi), closed: true, style: st)] }
            return [.stroke(points: rect(c.position, c.width, c.depth, c.rotation), closed: true, style: st)]
        case .beam(let b):
            let dir = b.end - b.start
            return [.stroke(points: rect((b.start + b.end) / 2, dir.length, b.width, dir.angle), closed: true, style: StrokeStyle(color: color, lineweight: lw, dash: [12, -6]))]
        case .opening(let o):
            guard let host = doc.element(o.hostWall), case .wall(let w) = host.geometry, w.length > geomEpsilon else { return [] }
            let c = w.centerStart + w.direction * o.offset
            var items: [DrawItem] = [.stroke(points: rect(c, o.width, w.thickness, w.direction.angle), closed: true, style: st)]
            if o.kind == .door {
                let side: Double = o.flipFacing ? -1 : 1
                let hinge = c + w.direction * (o.flipHand ? o.width / 2 : -o.width / 2) + w.direction.perp * (side * w.thickness / 2)
                let base = (o.flipHand ? -w.direction : w.direction).angle
                let sweep = (o.flipHand ? -1.0 : 1.0) * side * .pi / 2
                items.append(.stroke(points: [hinge, hinge + Vec2.polar(o.width, base + sweep)], closed: false, style: st))
                items.append(.stroke(points: GeometryOps.arcPoints(center: hinge, radius: o.width, start: base, sweep: sweep), closed: false, style: st))
            } else if o.kind == .window {
                items.append(.stroke(points: [c - w.direction * (o.width / 2), c + w.direction * (o.width / 2)], closed: false, style: st))
            }
            return items
        case .roof(let r):
            return [.stroke(points: r.boundary, closed: true, style: StrokeStyle(color: color, lineweight: lw, dash: [12, -6]))]
        case .stair(let s):
            let dir = Vec2.polar(1, s.direction), n = dir.perp
            let len = max(s.runLength, s.treadDepth)
            var items: [DrawItem] = [.stroke(points: [s.start - n * (s.width / 2), s.start - n * (s.width / 2) + dir * len, s.start + n * (s.width / 2) + dir * len, s.start + n * (s.width / 2)], closed: true, style: st)]
            if s.riserCount > 2 { for i in 1..<(s.riserCount - 1) {
                let p = s.start + dir * (Double(i) * s.treadDepth)
                items.append(.stroke(points: [p - n * (s.width / 2), p + n * (s.width / 2)], closed: false, style: st))
            } }
            return items
        case .railing(let r):
            return [.stroke(points: r.path, closed: false, style: st)]
        case .space(let s):
            guard s.boundary.count >= 3 else { return [] }
            let c = GeometryOps.centroid(s.boundary)
            let area = abs(GeometryOps.signedArea(s.boundary)) / 1_000_000 * (doc.units.mm * doc.units.mm)
            let label = (s.number.isEmpty ? "" : s.number + " ") + s.name + "\n" + String(format: "%.2f m²", area)
            return [.stroke(points: s.boundary, closed: true, style: st),
                    .text(TextGeom(position: c, height: 250 / doc.units.mm, content: label, halign: .center, valign: .middle), font: "Helvetica", color: color)]
        case .curtainWall(let cw):
            return [.stroke(points: [cw.start, cw.end], closed: false, style: st)]
        case .component(let c):
            return [.stroke(points: rect(c.position, c.size.x, c.size.y, c.rotation), closed: true, style: st)]
        case .gridLine(let gl):
            let r = 400 / doc.units.mm
            let d = (gl.end - gl.start).normalized
            let bc = gl.end + d * r
            return [.stroke(points: [gl.start, gl.end], closed: false, style: StrokeStyle(color: color, lineweight: lw, dash: [30, -6, 6, -6])),
                    .stroke(points: GeometryOps.arcPoints(center: bc, radius: r, start: 0, sweep: 2 * .pi), closed: true, style: st),
                    .text(TextGeom(position: bc, height: r, content: gl.label, halign: .center, valign: .middle), font: "Helvetica", color: color)]
        }
    }

    /// Plan outline of a wall (straight or curved via bulge).
    /// Elevation carried by an entity: props "elevation" (contours, lines) or "z" (survey points); 0 = none.
    static func elevation(of e: Entity) -> Double {
        switch e.geometry {
        case .point, .line, .circle, .arc, .polyline:
            return (e.props["elevation"] ?? e.props["z"]).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil } ?? 0
        default: return 0
        }
    }

    /// Contour lines of a toposurface solid (its contour interval, or none when contours are hidden).
    static func topoContours(_ s: SolidGeom, props: [String: String]) -> [(z: Double, lines: [[Vec2]])] {
        guard let iv = props["contourInterval"].flatMap(Double.init), iv > 0, s.kind == .mesh else { return [] }
        return Terrain.contours(vertices: s.meshVertices, triangles: s.meshTriangles, interval: iv, minZ: s.origin.z + iv * 0.01)
    }

    static func wallOutline(_ w: WallGeom) -> [Vec2] {
        let a = w.centerStart, b = w.centerEnd
        let n = w.direction.perp, t = w.thickness / 2
        if abs(w.bulge) < 1e-9 {
            return [a + n * t, b + n * t, b - n * t, a - n * t]
        }
        let arc = GeometryOps.bulgeArc(w.start, w.end, w.bulge)
        let sign: Double = w.bulge > 0 ? 1 : -1
        // Centerline radius shifts by the justification offset (towards/away from the center).
        let rc = arc.radius - sign * w.centerOffset
        let inner = GeometryOps.arcPoints(center: arc.center, radius: max(0, rc - t), start: arc.start, sweep: arc.sweep)
        let outer = GeometryOps.arcPoints(center: arc.center, radius: rc + t, start: arc.start, sweep: arc.sweep)
        return outer + inner.reversed()
    }
}

extension RGBA {
    func isNear(_ o: RGBA, tol: Double = 1.0 / 255) -> Bool { abs(r - o.r) <= tol && abs(g - o.g) <= tol && abs(b - o.b) <= tol }
}
