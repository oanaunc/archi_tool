// Oanarina Archi Tool — GPL-3.0-or-later
// XLSX (Office Open XML SpreadsheetML, ECMA-376) schedules export/import, and HP-GL/2 (PLT) plotter output.
import Foundation

public enum XLSX {
    public struct Sheet {
        public var name: String
        public var rows: [[String]]
        public init(name: String, rows: [[String]]) { self.name = name; self.rows = rows }
    }

    public enum XLSXError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid XLSX: \(m)" }; return nil }
    }

    static func esc(_ s: String) -> String {
        var o = ""
        for u in s.unicodeScalars {
            switch u {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default: if u.value >= 32 || u == "\n" || u == "\t" { o.unicodeScalars.append(u) }
            }
        }
        return o
    }

    /// Column letters for a 0-based index (0 → A, 26 → AA).
    public static func column(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }
    /// 0-based column index of a cell reference ("C12" → 2).
    public static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for c in ref.unicodeScalars { guard c.value >= 65 && c.value <= 90 else { break }; n = n * 26 + Int(c.value - 64) }
        return max(n - 1, 0)
    }

    static func sheetName(_ s: String, used: inout Set<String>) -> String {
        var n = String(s.filter { !"[]:*?/\\".contains($0) }.prefix(31))
        if n.isEmpty { n = "Sheet" }
        var k = 2, cand = n
        while used.contains(cand.lowercased()) { cand = String(n.prefix(28)) + " \(k)"; k += 1 }
        used.insert(cand.lowercased())
        return cand
    }

    /// Workbook with one worksheet per sheet; numeric cells are written as numbers, the first row bold (header).
    public static func write(_ sheets: [Sheet]) -> Data {
        var used = Set<String>()
        let names = sheets.map { sheetName($0.name, used: &used) }
        var entries: [ZipArchive.Entry] = []
        func add(_ n: String, _ s: String) { entries.append(ZipArchive.Entry(name: n, data: Data(s.utf8))) }
        let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        var ct = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        ct += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        ct += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        ct += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for i in sheets.indices { ct += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }
        ct += "</Types>"
        add("[Content_Types].xml", ct)
        add("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        var wb = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<workbook xmlns=\"\(ns)\" xmlns:r=\"\(rel)\"><sheets>"
        var wbr = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (i, n) in names.enumerated() {
            wb += "<sheet name=\"\(esc(n))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
            wbr += "<Relationship Id=\"rId\(i + 1)\" Type=\"\(rel)/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        wb += "</sheets></workbook>"
        wbr += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"\(rel)/styles\" Target=\"styles.xml\"/></Relationships>"
        add("xl/workbook.xml", wb)
        add("xl/_rels/workbook.xml.rels", wbr)
        add("xl/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<styleSheet xmlns=\"\(ns)\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs></styleSheet>")
        for (si, sh) in sheets.enumerated() {
            var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"\(ns)\">"
            if !sh.rows.isEmpty { x += "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>" }
            x += "<sheetData>"
            for (ri, row) in sh.rows.enumerated() {
                x += "<row r=\"\(ri + 1)\">"
                for (ci, v) in row.enumerated() where !v.isEmpty {
                    let ref = column(ci) + "\(ri + 1)"
                    let style = ri == 0 ? " s=\"1\"" : ""
                    if ri > 0, let d = Double(v), d.isFinite, !v.hasPrefix("+"), !(v.hasPrefix("0") && v.count > 1 && !v.hasPrefix("0.")) {
                        x += "<c r=\"\(ref)\"\(style)><v>\(v)</v></c>"
                    } else {
                        x += "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(esc(v))</t></is></c>"
                    }
                }
                x += "</row>"
            }
            x += "</sheetData></worksheet>"
            add("xl/worksheets/sheet\(si + 1).xml", x)
        }
        return ZipArchive.write(entries, compress: true)
    }

    /// Reads every worksheet (shared strings, inline strings, numbers, booleans) as rows of text.
    public static func read(_ data: Data) throws -> [Sheet] {
        let entries = try ZipArchive.read(data)
        func entry(_ n: String) -> Data? { entries.first { $0.name == n || $0.name == "/" + n }?.data }
        guard let wb = entry("xl/workbook.xml") else { throw XLSXError.invalid("no workbook") }
        var shared: [String] = []
        if let ss = entry("xl/sharedStrings.xml") { let p = SSTParser(); let x = XMLParser(data: ss); x.delegate = p; _ = x.parse(); shared = p.strings }
        let wp = WorkbookParser(); let wx = XMLParser(data: wb); wx.delegate = wp; _ = wx.parse()
        var targets: [String: String] = [:]
        if let rels = entry("xl/_rels/workbook.xml.rels") { let rp = RelsParser(); let rx = XMLParser(data: rels); rx.delegate = rp; _ = rx.parse(); targets = rp.targets }
        var out: [Sheet] = []
        for (i, s) in wp.sheets.enumerated() {
            var t = targets[s.rid] ?? "worksheets/sheet\(i + 1).xml"
            if t.hasPrefix("/") { t.removeFirst() } else if !t.hasPrefix("xl/") { t = "xl/" + t }
            guard let d = entry(t) else { continue }
            let p = SheetParser(shared: shared); let x = XMLParser(data: d); x.delegate = p; _ = x.parse()
            out.append(Sheet(name: s.name, rows: p.rows))
        }
        return out
    }

    final class SSTParser: NSObject, XMLParserDelegate {
        var strings: [String] = []; var cur = ""; var inT = false; var inSI = false
        func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if n == "si" { inSI = true; cur = "" } else if n == "t" { inT = true }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { if inT && inSI { cur += s } }
        func parser(_ parser: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            if n == "t" { inT = false } else if n == "si" { strings.append(cur); inSI = false }
        }
    }
    final class WorkbookParser: NSObject, XMLParserDelegate {
        var sheets: [(name: String, rid: String)] = []
        func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            if n == "sheet" { sheets.append((a["name"] ?? "Sheet", a["r:id"] ?? a.first { $0.key.hasSuffix(":id") }?.value ?? "")) }
        }
    }
    final class RelsParser: NSObject, XMLParserDelegate {
        var targets: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            if n == "Relationship", let id = a["Id"], let t = a["Target"] { targets[id] = t }
        }
    }
    final class SheetParser: NSObject, XMLParserDelegate {
        let shared: [String]
        var rows: [[String]] = []
        var rowIndex = -1
        var col = 0, type = "", text = "", inV = false, inT = false
        init(shared: [String]) { self.shared = shared }
        func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch n {
            case "row":
                rowIndex = (a["r"].flatMap(Int.init) ?? (rowIndex + 2)) - 1
                while rows.count <= rowIndex { rows.append([]) }
            case "c": col = a["r"].map(XLSX.columnIndex) ?? (rows.isEmpty ? 0 : rows[max(rowIndex, 0)].count); type = a["t"] ?? ""; text = ""
            case "v": inV = true
            case "t": inT = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { if inV || inT { text += s } }
        func parser(_ parser: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            switch n {
            case "v": inV = false
            case "t": inT = false
            case "c":
                guard rowIndex >= 0 else { return }
                var v = text
                if type == "s", let i = Int(text), i >= 0, i < shared.count { v = shared[i] }
                if type == "b" { v = text == "1" ? "TRUE" : "FALSE" }
                while rows[rowIndex].count <= col { rows[rowIndex].append("") }
                rows[rowIndex][col] = v
            default: break
            }
        }
    }

    /// Schedules workbook: walls, doors, windows, rooms, slabs, quantity takeoff and room areas by level.
    public static func schedules(_ doc: ArchiDocument) -> Data {
        var sheets: [Sheet] = []
        for (k, n) in [("walls", "Walls"), ("doors", "Doors"), ("windows", "Windows"), ("rooms", "Rooms"), ("slabs", "Slabs")] {
            let t = ScheduleExporter.table(doc: doc, kind: k)
            if t.count > 1 { sheets.append(Sheet(name: n, rows: t)) }
        }
        let tk = QuantityTakeoff.compute(doc)
        if !tk.lines.isEmpty { sheets.append(Sheet(name: "Takeoff", rows: tk.table)) }
        let lv = AreaSchedule.compute(doc)
        if !lv.isEmpty { sheets.append(Sheet(name: "Areas by level", rows: AreaSchedule.table(lv))) }
        if sheets.isEmpty { sheets.append(Sheet(name: "Schedule", rows: [["No BIM elements"]])) }
        return write(sheets)
    }
}

// MARK: - HP-GL/2

public enum HPGLExporter {
    /// Plotter label text: ASCII only (common symbols spelled out), no terminator or line breaks.
    static func ascii(_ s: String) -> String {
        var o = ""
        for u in s.unicodeScalars {
            switch u {
            case "\u{3}", "\n", "\r": o += " "
            case "²": o += "2"
            case "³": o += "3"
            case "°": o += " deg"
            case "±": o += "+/-"
            case "Ø", "⌀", "ø": o += "D"
            case "×": o += "x"
            case "–", "—": o += "-"
            default: o += u.isASCII && u.value >= 32 ? String(u) : "?"
            }
        }
        return o
    }

    /// HP-GL/2 plot of a draw list: 40 plotter units per millimetre on paper at 1:`scale` (drawing mm per paper mm),
    /// one pen per distinct colour (up to 8). Text is drawn with the plotter's LB font.
    /// Roll-paper media for large-format plotters (SHT-038): the plot is sized to the drawing at scale plus margins, rotated
    /// 90° when that makes it fit the roll width (or saves paper), and the HP-GL/2 PS command sets the page.
    public struct RollMedia: Hashable {
        public var width: Double          // roll width, mm
        public var margin: Double = 10    // mm on every side
        public init(width: Double, margin: Double = 10) { self.width = width; self.margin = margin }
        /// Plot layout for a drawing extent on paper (mm): (rotated, length along the roll, fits across the roll).
        public func layout(paperWidth w: Double, paperHeight h: Double) -> (rotated: Bool, length: Double, fits: Bool) {
            let usable = width - 2 * margin
            let normalFits = h <= usable, rotatedFits = w <= usable
            // Prefer the orientation that fits; if both fit, the one using less roll length.
            let rotated: Bool
            if normalFits && rotatedFits { rotated = h > w } else { rotated = !normalFits && rotatedFits }
            let length = (rotated ? h : w) + 2 * margin
            return (rotated, length, rotated ? rotatedFits : normalFits)
        }
    }

    public static func export(_ entries: [DrawEntry], bounds: BBox2, scale: Double = 100, unitMM: Double = 1, roll: RollMedia? = nil) -> String {
        let k = 40.0 * unitMM / max(scale, 1e-9)
        var rotate = false, offset = Vec2(0, 0)
        var header: [String] = []
        if let roll {
            let wPaper = bounds.width * unitMM / max(scale, 1e-9), hPaper = bounds.height * unitMM / max(scale, 1e-9)
            let lay = roll.layout(paperWidth: wPaper, paperHeight: hPaper)
            rotate = lay.rotated
            offset = Vec2(roll.margin * 40, roll.margin * 40)
            // PS length (along the roll), width (across) in plotter units.
            header.append("PS\(Int((lay.length * 40).rounded())),\(Int((roll.width * 40).rounded()));")
        }
        func P(_ p: Vec2) -> String {
            var x = (p.x - bounds.min.x) * k, y = (p.y - bounds.min.y) * k
            if rotate { (x, y) = (y, bounds.width * k - x) }
            return "\(Int((x + offset.x).rounded())),\(Int((y + offset.y).rounded()))"
        }
        var pens: [String: Int] = [:]
        var out = ["IN;"] + header + ["SP1;"]
        var curPen = 1
        func pen(_ c: RGBA) {
            let key = c.hex
            let n: Int
            if let p = pens[key] { n = p } else { n = min(pens.count + 1, 8); pens[key] = n }
            if n != curPen { out.append("SP\(n);"); curPen = n }
        }
        for e in entries {
            for item in e.items {
                switch item {
                case .stroke(let pts, let closed, let st):
                    guard pts.count >= 2 else { continue }
                    pen(st.color)
                    var path = pts
                    if closed, let f = pts.first { path.append(f) }
                    out.append("PU\(P(path[0]));PD" + path.dropFirst().map(P).joined(separator: ",") + ";")
                case .fill(let loops, let color):
                    pen(color)
                    for l in loops where l.count >= 3 { out.append("PU\(P(l[0]));PD" + (l.dropFirst() + [l[0]]).map(P).joined(separator: ",") + ";") }
                case .text(let t, _, let color):
                    pen(color)
                    let h = max(t.height * k / 40 / 10, 0.05) // cm
                    let ang = t.rotation - (rotate ? Double.pi / 2 : 0)
                    out.append("PU\(P(t.position));SI\(fmt(h * 0.7, 3)),\(fmt(h, 3));DI\(fmt(cos(ang), 4)),\(fmt(sin(ang), 4));LB\(ascii(t.content))\u{3};")
                default: continue
                }
            }
        }
        out.append("PU;SP0;IN;")
        return out.joined(separator: "\n") + "\n"
    }
}

/// Spreadsheets placed in the drawing as table entities (one per non-empty sheet, stacked downwards).
public enum XLSXTables {
    public static func entities(_ sheets: [XLSX.Sheet], unitMM: Double, origin: Vec2 = .zero, layer: String = "TABLES") -> [Entity] {
        let th = 250 / unitMM
        var y = origin.y
        var out: [Entity] = []
        for sh in sheets {
            let rows = sh.rows.filter { $0.contains { !$0.isEmpty } }
            guard !rows.isEmpty else { continue }
            let cols = rows.map(\.count).max() ?? 0
            let cells = rows.map { $0 + Array(repeating: "", count: cols - $0.count) }
            let widths = (0..<cols).map { c in Double(max(4, cells.map { $0[c].count }.max() ?? 0)) * th * 0.75 + th }
            out.append(Entity(layer: layer, geometry: .table(TableGeom(origin: Vec2(origin.x, y), columnWidths: widths, rowHeight: th * 1.8, cells: cells, textHeight: th)),
                              props: ["name": sh.name]))
            y -= Double(cells.count) * th * 1.8 + th * 3
        }
        return out
    }
}

/// IfcZIP: a ZIP archive holding one .ifc file (buildingSMART).
public enum IFCZip {
    public enum IFCZipError: Error, LocalizedError {
        case noIFC
        public var errorDescription: String? { "The archive contains no .ifc file." }
    }
    public static func write(_ ifc: String, name: String = "model.ifc") -> Data {
        ZipArchive.write([ZipArchive.Entry(name: name.lowercased().hasSuffix(".ifc") ? name : name + ".ifc", data: Data(ifc.utf8))], compress: true)
    }
    /// The IFC STEP text of the archive's .ifc file, or of its .ifcXML file converted to STEP.
    public static func read(_ data: Data) throws -> String {
        let entries = try ZipArchive.read(data)
        if let e = entries.first(where: { $0.name.lowercased().hasSuffix(".ifc") }) {
            return String(data: e.data, encoding: .utf8) ?? String(decoding: e.data, as: UTF8.self)
        }
        if let x = entries.first(where: { $0.name.lowercased().hasSuffix(".ifcxml") || ($0.name.lowercased().hasSuffix(".xml") && IFCXML.sniff($0.data)) }) {
            return try IFCXML.toSTEP(x.data)
        }
        throw IFCZipError.noIFC
    }
    /// IfcZIP holding an ifcXML file.
    public static func writeXML(_ xml: String, name: String = "model.ifcXML") -> Data {
        ZipArchive.write([ZipArchive.Entry(name: name.lowercased().hasSuffix(".ifcxml") ? name : name + ".ifcXML", data: Data(xml.utf8))], compress: true)
    }
}
