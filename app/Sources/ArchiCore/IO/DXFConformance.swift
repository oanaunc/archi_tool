// Oanarina Archi Tool — GPL-3.0-or-later
// DXF conformance audit (IO-009): checks a DXF file against the structural rules readers such as LibreCAD's libdxfrw,
// ezdxf's auditor and AutoCAD rely on — well-formed group-code/value pairs with values of the type the code range
// requires, balanced SECTION/ENDSEC, TABLE/ENDTAB and BLOCK/ENDBLK, the required sections and symbol tables of the
// version, unique handles below $HANDSEED, owner (330) references that resolve, and entity references (layer,
// linetype, text style, dimension style, block) that exist in the tables. Used by DXFCHECK / DXFOUT verification and
// the export tests, so every export is audited the way a strict reader would read it.
import Foundation

public struct DXFAuditIssue: Hashable, CustomStringConvertible {
    public enum Severity: String { case error, warning }
    public var severity: Severity
    public var code: String
    public var message: String
    /// 1-based line of the group code (0 = file level).
    public var line: Int
    public var description: String { "[\(severity.rawValue.uppercased())] \(code) (line \(line)): \(message)" }
}

public enum DXFConformance {
    struct Pair { var code: Int; var value: String; var line: Int }

    public enum ValueType { case string, double, int, handle, bool }
    /// Value type of a group code (AutoCAD DXF reference, "Group code value types").
    public static func type(of code: Int) -> ValueType {
        switch code {
        case 5, 105, 320...369, 390...399, 480...481, 1005: return .handle
        case 10...59, 110...149, 210...239, 460...469, 1010...1059: return .double
        case 60...79, 90...99, 160...179, 270...289, 370...389, 400...409, 420...429, 440...459, 1060...1071: return .int
        case 280...289 where false: return .int
        case 290...299: return .bool
        default: return .string
        }
    }

    static func pairs(_ text: String, _ issues: inout [DXFAuditIssue]) -> [Pair] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if lines.count % 2 != 0 { issues.append(.init(severity: .error, code: "ODD_LINES", message: "odd number of lines (\(lines.count)): a group code without value", line: lines.count)) }
        var out: [Pair] = []
        out.reserveCapacity(lines.count / 2)
        var i = 0
        while i + 1 < lines.count {
            let c = lines[i].trimmingCharacters(in: .whitespaces)
            let v = lines[i + 1].hasSuffix("\r") ? String(lines[i + 1].dropLast()) : lines[i + 1]
            guard let code = Int(c.hasSuffix("\r") ? String(c.dropLast()) : c) else {
                issues.append(.init(severity: .error, code: "BAD_CODE", message: "group code '\(c.prefix(20))' is not an integer", line: i + 1))
                return out
            }
            let t = v.trimmingCharacters(in: .whitespaces)
            switch type(of: code) {
            case .double: if Double(t) == nil || !(Double(t)!.isFinite) { issues.append(.init(severity: .error, code: "BAD_REAL", message: "code \(code) needs a real number, found '\(t.prefix(20))'", line: i + 2)) }
            case .int, .bool: if Int(t) == nil { issues.append(.init(severity: .error, code: "BAD_INT", message: "code \(code) needs an integer, found '\(t.prefix(20))'", line: i + 2)) }
            case .handle: if UInt64(t, radix: 16) == nil { issues.append(.init(severity: .error, code: "BAD_HANDLE", message: "code \(code) needs a hexadecimal handle, found '\(t.prefix(20))'", line: i + 2)) }
            case .string: if v.count > 2049 { issues.append(.init(severity: .warning, code: "LONG_STRING", message: "code \(code) string longer than 2049 characters", line: i + 2)) }
            }
            out.append(Pair(code: code, value: t, line: i + 1))
            i += 2
        }
        return out
    }

    /// Audits DXF text. An empty result means the file is structurally sound.
    public static func audit(_ text: String) -> [DXFAuditIssue] {
        var issues: [DXFAuditIssue] = []
        let p = pairs(text, &issues)
        func err(_ code: String, _ m: String, _ line: Int) { issues.append(.init(severity: .error, code: code, message: m, line: line)) }
        func warn(_ code: String, _ m: String, _ line: Int) { issues.append(.init(severity: .warning, code: code, message: m, line: line)) }
        guard !p.isEmpty else { err("EMPTY", "no group codes", 0); return issues }

        // Sections.
        var sections: [(name: String, start: Int, end: Int)] = []
        var i = 0, sawEOF = false
        while i < p.count {
            let q = p[i]
            if q.code == 0 && q.value == "EOF" { sawEOF = true; if i != p.count - 1 { warn("DATA_AFTER_EOF", "group codes after EOF", q.line) }; break }
            guard q.code == 0, q.value == "SECTION" else { err("OUTSIDE_SECTION", "'\(q.code) \(q.value)' outside a section", q.line); i += 1; continue }
            guard i + 1 < p.count, p[i + 1].code == 2 else { err("SECTION_NAME", "SECTION without a 2 name", q.line); i += 1; continue }
            let name = p[i + 1].value
            var j = i + 2
            while j < p.count && !(p[j].code == 0 && (p[j].value == "ENDSEC" || p[j].value == "SECTION" || p[j].value == "EOF")) { j += 1 }
            if j >= p.count || p[j].value != "ENDSEC" { err("NO_ENDSEC", "section \(name) is not closed by ENDSEC", q.line); sections.append((name, i + 2, j)); i = j; continue }
            if sections.contains(where: { $0.name == name }) { err("DUP_SECTION", "section \(name) appears twice", q.line) }
            sections.append((name, i + 2, j))
            i = j + 1
        }
        if !sawEOF { err("NO_EOF", "the file does not end with 0 EOF", p.last?.line ?? 0) }
        func section(_ n: String) -> ArraySlice<Pair>? { sections.first { $0.name == n }.map { p[$0.start..<$0.end] } }

        // Header.
        var version = "AC1009"
        var handseed: UInt64?
        if let h = section("HEADER") {
            let arr = Array(h)
            for (k, q) in arr.enumerated() where q.code == 9 {
                if q.value == "$ACADVER", k + 1 < arr.count { version = arr[k + 1].value }
                if q.value == "$HANDSEED", k + 1 < arr.count { handseed = UInt64(arr[k + 1].value, radix: 16) }
            }
            if !arr.contains(where: { $0.code == 9 && $0.value == "$ACADVER" }) { err("NO_ACADVER", "HEADER has no $ACADVER", arr.first?.line ?? 0) }
        } else { warn("NO_HEADER", "no HEADER section", 0) }
        let known = ["AC1009", "AC1012", "AC1014", "AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"]
        if !known.contains(version) { err("VERSION", "unknown $ACADVER \(version)", 0) }
        let modern = version >= "AC1015"
        if modern {
            for n in ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"] where section(n) == nil { err("MISSING_SECTION", "\(version) requires a \(n) section", 0) }
            if handseed == nil { err("NO_HANDSEED", "HEADER has no $HANDSEED", 0) }
        } else if section("ENTITIES") == nil { err("MISSING_SECTION", "no ENTITIES section", 0) }

        // Handles and owners.
        var handles: [UInt64: Int] = [:]
        var owners: [(UInt64, Int)] = []
        var maxHandle: UInt64 = 0
        var inHeader = false
        for q in p {
            if q.code == 0 && q.value == "SECTION" { inHeader = false }
            if q.code == 2, q.value == "HEADER" { inHeader = true }
            if inHeader { continue }
            if q.code == 5 || q.code == 105, let h = UInt64(q.value, radix: 16) {
                if h == 0 { err("ZERO_HANDLE", "handle 0 is reserved", q.line) }
                if let prev = handles[h] { err("DUP_HANDLE", "handle \(q.value) already used at line \(prev)", q.line) } else { handles[h] = q.line }
                maxHandle = max(maxHandle, h)
            }
            if q.code == 330, let h = UInt64(q.value, radix: 16), h != 0 { owners.append((h, q.line)) }
        }
        if let hs = handseed, modern, maxHandle >= hs { err("HANDSEED", "$HANDSEED \(String(hs, radix: 16, uppercase: true)) is not above the largest handle \(String(maxHandle, radix: 16, uppercase: true))", 0) }
        for (h, line) in owners where handles[h] == nil { err("BAD_OWNER", "owner handle \(String(h, radix: 16, uppercase: true)) does not exist", line) }

        // Tables.
        var tables: [String: Set<String>] = [:]
        if let t = section("TABLES") {
            let arr = Array(t)
            var k = 0
            var current: String?
            while k < arr.count {
                let q = arr[k]
                if q.code == 0 && q.value == "TABLE" {
                    if current != nil { err("NESTED_TABLE", "TABLE inside table \(current!)", q.line) }
                    current = (k + 1 < arr.count && arr[k + 1].code == 2) ? arr[k + 1].value : nil
                    if current == nil { err("TABLE_NAME", "TABLE without a 2 name", q.line) } else { tables[current!] = tables[current!] ?? [] }
                    k += 2; continue
                }
                if q.code == 0 && q.value == "ENDTAB" { if current == nil { err("ENDTAB", "ENDTAB without TABLE", q.line) }; current = nil; k += 1; continue }
                if q.code == 0, let cur = current {
                    if q.value != cur { err("TABLE_ENTRY", "\(q.value) entry inside table \(cur)", q.line) }
                    var m = k + 1, name: String?
                    while m < arr.count && arr[m].code != 0 { if arr[m].code == 2 && name == nil { name = arr[m].value }; m += 1 }
                    if let n = name {
                        if tables[cur]!.contains(n.uppercased()) { warn("DUP_ENTRY", "\(cur) entry \(n) defined twice", q.line) }
                        tables[cur]!.insert(n.uppercased())
                    } else { err("ENTRY_NAME", "\(cur) entry without a name", q.line) }
                    k = m; continue
                }
                k += 1
            }
            if current != nil { err("NO_ENDTAB", "table \(current!) is not closed by ENDTAB", arr.last?.line ?? 0) }
            let required = modern ? ["VPORT", "LTYPE", "LAYER", "STYLE", "VIEW", "UCS", "APPID", "DIMSTYLE", "BLOCK_RECORD"] : ["LTYPE", "LAYER"]
            for r in required where tables[r] == nil { err("MISSING_TABLE", "no \(r) table", 0) }
            if let l = tables["LAYER"], !l.contains("0") { err("NO_LAYER_0", "layer 0 is missing", 0) }
            if let l = tables["LTYPE"] { for n in (modern ? ["BYBLOCK", "BYLAYER", "CONTINUOUS"] : ["CONTINUOUS"]) where !l.contains(n) { err("MISSING_LTYPE", "linetype \(n) is missing", 0) } }
            if modern, let a = tables["APPID"], !a.contains("ACAD") { err("MISSING_APPID", "APPID ACAD is missing", 0) }
            if modern, let s = tables["STYLE"], !s.contains("STANDARD") { warn("NO_STANDARD", "text style Standard is missing", 0) }
        }

        // Blocks.
        var blocks = Set<String>()
        if let b = section("BLOCKS") {
            var open: (String, Int)?
            for (k, q) in b.enumerated() where q.code == 0 {
                if q.value == "BLOCK" {
                    if let o = open { err("NESTED_BLOCK", "BLOCK inside block \(o.0)", q.line) }
                    let arr = Array(b)
                    var m = k + 1, name = ""
                    while m < arr.count && arr[m].code != 0 { if arr[m].code == 2 { name = arr[m].value }; m += 1 }
                    if name.isEmpty { err("BLOCK_NAME", "BLOCK without a name", q.line) }
                    if blocks.contains(name.uppercased()) { err("DUP_BLOCK", "block \(name) defined twice", q.line) }
                    blocks.insert(name.uppercased())
                    open = (name, q.line)
                } else if q.value == "ENDBLK" {
                    if open == nil { err("ENDBLK", "ENDBLK without BLOCK", q.line) }
                    open = nil
                }
            }
            if let o = open { err("NO_ENDBLK", "block \(o.0) is not closed by ENDBLK", o.1) }
            if modern {
                for n in ["*MODEL_SPACE", "*PAPER_SPACE"] where !blocks.contains(n) { err("MISSING_BLOCK", "block \(n) is missing", 0) }
                if let br = tables["BLOCK_RECORD"] { for n in blocks where !br.contains(n) { err("NO_BLOCK_RECORD", "block \(n) has no BLOCK_RECORD", 0) } }
            }
        }

        // Entity references (ENTITIES and block contents).
        let layers = tables["LAYER"] ?? ["0"], ltypes = tables["LTYPE"] ?? [], styles = tables["STYLE"] ?? [], dimstyles = tables["DIMSTYLE"] ?? []
        func checkEntities(_ s: ArraySlice<Pair>, inBlocks: Bool) {
            let arr = Array(s)
            var k = 0
            while k < arr.count {
                let q = arr[k]
                guard q.code == 0 else { k += 1; continue }
                let kind = q.value
                var m = k + 1
                var codes: [Int: String] = [:]
                var subclasses = 0
                while m < arr.count && arr[m].code != 0 {
                    if codes[arr[m].code] == nil { codes[arr[m].code] = arr[m].value }
                    if arr[m].code == 100 { subclasses += 1 }
                    m += 1
                }
                let structural = ["BLOCK", "ENDBLK", "SEQEND", "VERTEX", "ATTRIB"].contains(kind)
                if !(inBlocks && (kind == "BLOCK" || kind == "ENDBLK")) {
                    if let l = codes[8], !layers.contains(l.uppercased()) { err("UNKNOWN_LAYER", "\(kind) on undefined layer '\(l)'", q.line) }
                    if !structural, codes[8] == nil { warn("NO_LAYER", "\(kind) has no layer (8)", q.line) }
                    if let lt = codes[6], !ltypes.isEmpty, !ltypes.contains(lt.uppercased()) { err("UNKNOWN_LTYPE", "\(kind) uses undefined linetype '\(lt)'", q.line) }
                    if modern, !structural, codes[5] == nil { err("NO_HANDLE", "\(kind) has no handle", q.line) }
                    if modern, !structural, subclasses == 0 { err("NO_SUBCLASS", "\(kind) has no AcDbEntity subclass marker", q.line) }
                    if ["TEXT", "MTEXT", "ATTDEF"].contains(kind), let st = codes[7], !styles.isEmpty, !styles.contains(st.uppercased()) { err("UNKNOWN_STYLE", "\(kind) uses undefined text style '\(st)'", q.line) }
                    if kind == "DIMENSION" || kind == "LEADER", let ds = codes[3], !dimstyles.isEmpty, !dimstyles.contains(ds.uppercased()) { err("UNKNOWN_DIMSTYLE", "\(kind) uses undefined dimension style '\(ds)'", q.line) }
                    if kind == "INSERT" || kind == "DIMENSION", let b = codes[2], !blocks.contains(b.uppercased()) { err("UNKNOWN_BLOCK", "\(kind) references undefined block '\(b)'", q.line) }
                }
                k = m
            }
        }
        if let e = section("ENTITIES") { checkEntities(e, inBlocks: false) }
        if let b = section("BLOCKS") { checkEntities(b, inBlocks: true) }

        // Objects: the root dictionary comes first.
        if modern, let o = section("OBJECTS") {
            if let first = o.first(where: { $0.code == 0 }), first.value != "DICTIONARY" { err("ROOT_DICT", "OBJECTS must start with the root DICTIONARY", first.line) }
        }
        return issues
    }

    /// Entity type counts of the ENTITIES section (for "same entities" comparisons).
    public static func entityCounts(_ text: String) -> [String: Int] {
        var dummy: [DXFAuditIssue] = []
        let p = pairs(text, &dummy)
        var out: [String: Int] = [:], inEnt = false
        for (k, q) in p.enumerated() {
            if q.code == 0 && q.value == "SECTION" { inEnt = k + 1 < p.count && p[k + 1].value == "ENTITIES"; continue }
            if inEnt, q.code == 0, !["ENDSEC", "SEQEND", "VERTEX", "ATTRIB"].contains(q.value) { out[q.value, default: 0] += 1 }
        }
        return out
    }
}
