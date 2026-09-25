// Oanarina Archi Tool — GPL-3.0-or-later
// PDF reading for CAD (IO-014 vector import, COL-008 markup import), written from the PDF 1.7 specification (ISO
// 32000-1): objects (also inside compressed object streams), page tree with inherited resources, FlateDecode streams,
// content-stream interpretation (paths with the CTM and form XObjects, stroke colours, optional-content layers,
// text with ToUnicode maps) into drawing entities, and page annotations (Text, FreeText, Square, Circle, Line, Ink,
// Polygon, PolyLine, Highlight…) into review markups linked to the elements under them.
import Foundation

public indirect enum PDFObj: Equatable {
    case null, bool(Bool), num(Double), str(Data), name(String), array([PDFObj]), dict([String: PDFObj]), ref(Int, Int), op(String)
    case stream([String: PDFObj], Data)
    var dict: [String: PDFObj]? { switch self { case .dict(let d): return d; case .stream(let d, _): return d; default: return nil } }
    var array: [PDFObj]? { if case .array(let a) = self { return a }; return nil }
    var num: Double? { if case .num(let n) = self { return n }; return nil }
    var name: String? { if case .name(let n) = self { return n }; return nil }
    var data: Data? { if case .str(let d) = self { return d }; return nil }
}

struct PDFLexer {
    let b: [UInt8]
    var i: Int
    static let delims: Set<UInt8> = Set("()<>[]{}/%".utf8)
    static func isWS(_ c: UInt8) -> Bool { c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32 }
    mutating func ws() {
        while i < b.count {
            if PDFLexer.isWS(b[i]) { i += 1 }
            else if b[i] == UInt8(ascii: "%") { while i < b.count && b[i] != 10 && b[i] != 13 { i += 1 } }
            else { break }
        }
    }
    mutating func token() -> String {
        var s = [UInt8]()
        while i < b.count, !PDFLexer.isWS(b[i]), !PDFLexer.delims.contains(b[i]) { s.append(b[i]); i += 1 }
        return String(decoding: s, as: UTF8.self)
    }
    /// Parses one object; bare keywords come back as `.op` (content streams).
    mutating func object() -> PDFObj? {
        ws()
        guard i < b.count else { return nil }
        let c = b[i]
        switch c {
        case UInt8(ascii: "/"):
            i += 1
            var s = [UInt8]()
            while i < b.count, !PDFLexer.isWS(b[i]), !PDFLexer.delims.contains(b[i]) {
                if b[i] == UInt8(ascii: "#"), i + 2 < b.count, let v = UInt8(String(decoding: b[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) { s.append(v); i += 3 }
                else { s.append(b[i]); i += 1 }
            }
            return .name(String(decoding: s, as: UTF8.self))
        case UInt8(ascii: "("):
            i += 1
            var depth = 1, s = [UInt8]()
            while i < b.count {
                let x = b[i]
                if x == UInt8(ascii: "\\"), i + 1 < b.count {
                    i += 1
                    let e = b[i]
                    switch e {
                    case UInt8(ascii: "n"): s.append(10); case UInt8(ascii: "r"): s.append(13); case UInt8(ascii: "t"): s.append(9)
                    case UInt8(ascii: "b"): s.append(8); case UInt8(ascii: "f"): s.append(12)
                    case 10: break
                    case 13: if i + 1 < b.count, b[i + 1] == 10 { i += 1 }
                    case UInt8(ascii: "0")...UInt8(ascii: "7"):
                        var v = Int(e - 48), n = 1
                        while n < 3, i + 1 < b.count, (48...55).contains(b[i + 1]) { i += 1; v = v * 8 + Int(b[i] - 48); n += 1 }
                        s.append(UInt8(v & 0xFF))
                    default: s.append(e)
                    }
                    i += 1; continue
                }
                if x == UInt8(ascii: "(") { depth += 1 } else if x == UInt8(ascii: ")") { depth -= 1; if depth == 0 { i += 1; break } }
                s.append(x); i += 1
            }
            return .str(Data(s))
        case UInt8(ascii: "<"):
            if i + 1 < b.count, b[i + 1] == UInt8(ascii: "<") {
                i += 2
                var d: [String: PDFObj] = [:]
                while true {
                    ws()
                    guard i < b.count else { break }
                    if b[i] == UInt8(ascii: ">"), i + 1 < b.count, b[i + 1] == UInt8(ascii: ">") { i += 2; break }
                    guard case .name(let k)? = object() else { i += 1; continue }
                    d[k] = object() ?? .null
                }
                return .dict(d)
            }
            i += 1
            var hex = [UInt8]()
            while i < b.count, b[i] != UInt8(ascii: ">") { if !PDFLexer.isWS(b[i]) { hex.append(b[i]) }; i += 1 }
            i += 1
            if hex.count % 2 == 1 { hex.append(UInt8(ascii: "0")) }
            var out = [UInt8]()
            var k = 0
            while k + 1 < hex.count { out.append(UInt8(String(decoding: hex[k...(k + 1)], as: UTF8.self), radix: 16) ?? 0); k += 2 }
            return .str(Data(out))
        case UInt8(ascii: "["):
            i += 1
            var a: [PDFObj] = []
            while true {
                ws()
                guard i < b.count else { break }
                if b[i] == UInt8(ascii: "]") { i += 1; break }
                guard let o = object() else { break }
                a.append(o)
            }
            return .array(a)
        case UInt8(ascii: "]"), UInt8(ascii: ">"), UInt8(ascii: ")"), UInt8(ascii: "{"), UInt8(ascii: "}"):
            i += 1; return .op(String(UnicodeScalar(c)))
        default:
            let t = token()
            if t.isEmpty { i += 1; return .op("") }
            if let n = Double(t) {
                // "N G R" reference.
                let save = i
                if n == n.rounded(), n >= 0 {
                    ws()
                    let t2 = token()
                    if let g = Int(t2) {
                        ws()
                        if i < b.count, b[i] == UInt8(ascii: "R"), i + 1 >= b.count || PDFLexer.isWS(b[i + 1]) || PDFLexer.delims.contains(b[i + 1]) { i += 1; return .ref(Int(n), g) }
                    }
                }
                i = save
                return .num(n)
            }
            switch t { case "true": return .bool(true); case "false": return .bool(false); case "null": return .null; default: return .op(t) }
        }
    }
}

public final class PDFFile {
    public struct PDFError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }
    public private(set) var objects: [Int: PDFObj] = [:]
    let bytes: [UInt8]

    public init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes.prefix(5)) == Array("%PDF-".utf8) || bytes.prefix(1024).windows(ofCount: 5).contains(where: { Array($0) == Array("%PDF-".utf8) }) else {
            throw PDFError(message: "Not a PDF file.")
        }
        scan()
        guard !objects.isEmpty else { throw PDFError(message: "No objects found (damaged PDF?).") }
        expandObjectStreams()
    }

    /// Finds "N G obj" markers and parses each object (later definitions win, as in incremental updates).
    func scan() {
        let b = bytes
        var i = 0
        let obj = Array("obj".utf8)
        while i + 3 <= b.count {
            guard b[i] == obj[0], i + 2 < b.count, b[i + 1] == obj[1], b[i + 2] == obj[2], i > 0, PDFLexer.isWS(b[i - 1]) || b[i - 1] == UInt8(ascii: ">") || b[i - 1] == UInt8(ascii: "]") || true else { i += 1; continue }
            // Walk back over "G " and "N ".
            var j = i - 1
            while j >= 0, PDFLexer.isWS(b[j]) { j -= 1 }
            var gEnd = j
            while j >= 0, (48...57).contains(b[j]) { j -= 1 }
            guard j < gEnd, let g = Int(String(decoding: b[(j + 1)...gEnd], as: UTF8.self)) else { i += 1; continue }
            while j >= 0, PDFLexer.isWS(b[j]) { j -= 1 }
            gEnd = j
            while j >= 0, (48...57).contains(b[j]) { j -= 1 }
            guard j < gEnd, (j < 0 || PDFLexer.isWS(b[j]) || PDFLexer.delims.contains(b[j])), let num = Int(String(decoding: b[(j + 1)...gEnd], as: UTF8.self)) else { i += 1; continue }
            _ = g
            var lx = PDFLexer(b: b, i: i + 3)
            guard let o = lx.object() else { i += 3; continue }
            var value = o
            var after = lx
            after.ws()
            if case .dict(let d) = o, after.i + 6 <= b.count, Array(b[after.i..<(after.i + 6)]) == Array("stream".utf8) {
                var s = after.i + 6
                if s < b.count, b[s] == 13 { s += 1 }
                if s < b.count, b[s] == 10 { s += 1 }
                var len = -1
                if case .num(let n)? = d["Length"] { len = Int(n) }
                else if case .ref(let r, _)? = d["Length"], case .num(let n)? = objects[r] { len = Int(n) }
                var e: Int
                if len >= 0, s + len <= b.count, b[min(b.count - 1, s + len)...].prefix(20).windows(ofCount: 9).contains(where: { Array($0) == Array("endstream".utf8) }) { e = s + len }
                else {
                    // Search for endstream.
                    e = s
                    let es = Array("endstream".utf8)
                    while e + 9 <= b.count, Array(b[e..<(e + 9)]) != es { e += 1 }
                    while e > s, b[e - 1] == 10 || b[e - 1] == 13 { e -= 1 }
                }
                value = .stream(d, Data(b[s..<min(e, b.count)]))
                lx.i = e
            }
            objects[num] = value
            i = max(lx.i, i + 3)
        }
    }

    func expandObjectStreams() {
        for (_, o) in objects {
            guard case .stream(let d, _) = o, d["Type"]?.name == "ObjStm", let n = d["N"]?.num, let first = d["First"]?.num, let data = decode(o) else { continue }
            let b = [UInt8](data)
            var lx = PDFLexer(b: b, i: 0)
            var pairs: [(Int, Int)] = []
            for _ in 0..<Int(n) {
                guard case .num(let on)? = lx.object(), case .num(let off)? = lx.object() else { break }
                pairs.append((Int(on), Int(off)))
            }
            for (on, off) in pairs where objects[on] == nil {
                var l2 = PDFLexer(b: b, i: Int(first) + off)
                if let v = l2.object() { objects[on] = v }
            }
        }
    }

    public func resolve(_ o: PDFObj?) -> PDFObj? {
        var cur = o, n = 0
        while case .ref(let r, _)? = cur, n < 32 { cur = objects[r]; n += 1 }
        return cur
    }
    func dict(_ o: PDFObj?) -> [String: PDFObj]? { resolve(o)?.dict }

    /// Stream data after its filters (FlateDecode supported; PNG predictors for Flate).
    public func decode(_ o: PDFObj) -> Data? {
        guard case .stream(let d, let raw) = o else { return nil }
        var filters: [String] = []
        if let f = resolve(d["Filter"]) { if let n = f.name { filters = [n] } else if let a = f.array { filters = a.compactMap { resolve($0)?.name } } }
        var data = raw
        for f in filters {
            switch f {
            case "FlateDecode", "Fl":
                guard data.count > 2 else { return nil }
                let body = data.subdata(in: 2..<data.count)
                if let out = try? (body as NSData).decompressed(using: .zlib) as Data { data = out }
                else if data.count > 6, let out = try? (data.subdata(in: 2..<(data.count - 4)) as NSData).decompressed(using: .zlib) as Data { data = out }
                else { return nil }
                if let parms = dict(d["DecodeParms"]), let pred = parms["Predictor"]?.num, pred >= 10 {
                    let cols = Int(parms["Columns"]?.num ?? 1) * Int(parms["Colors"]?.num ?? 1) * Int(parms["BitsPerComponent"]?.num ?? 8) / 8
                    data = PDFFile.unpredict(data, columns: max(cols, 1))
                }
            default: return nil
            }
        }
        return data
    }

    static func unpredict(_ d: Data, columns: Int) -> Data {
        let b = [UInt8](d)
        var out = [UInt8](), prev = [UInt8](repeating: 0, count: columns)
        var i = 0
        while i + columns < b.count + 1, i < b.count {
            let type = b[i]; i += 1
            var row = Array(b[i..<min(b.count, i + columns)]); i += columns
            if row.count < columns { row += [UInt8](repeating: 0, count: columns - row.count) }
            for k in 0..<columns {
                let left = k > 0 ? row[k - 1] : 0, up = prev[k], ul = k > 0 ? prev[k - 1] : 0
                switch type {
                case 1: row[k] = row[k] &+ left
                case 2: row[k] = row[k] &+ up
                case 3: row[k] = row[k] &+ UInt8((Int(left) + Int(up)) / 2)
                case 4:
                    let p = Int(left) + Int(up) - Int(ul), pa = abs(p - Int(left)), pb = abs(p - Int(up)), pc = abs(p - Int(ul))
                    row[k] = row[k] &+ (pa <= pb && pa <= pc ? left : pb <= pc ? up : ul)
                default: break
                }
            }
            out += row; prev = row
        }
        return Data(out)
    }

    public struct Page { public var dict: [String: PDFObj]; public var mediaBox: BBox2; public var resources: [String: PDFObj] }

    /// Pages in document order (page tree from the catalog; inherited MediaBox and Resources).
    public lazy var pages: [Page] = {
        var out: [Page] = []
        func box(_ o: PDFObj?) -> BBox2? {
            guard let a = resolve(o)?.array?.compactMap({ resolve($0)?.num }), a.count == 4 else { return nil }
            return BBox2(min: Vec2(min(a[0], a[2]), min(a[1], a[3])), max: Vec2(max(a[0], a[2]), max(a[1], a[3])))
        }
        func walk(_ o: PDFObj?, _ mb: BBox2?, _ res: [String: PDFObj]?, depth: Int) {
            guard depth < 64, let d = dict(o) else { return }
            let m = box(d["MediaBox"]) ?? mb, r = dict(d["Resources"]) ?? res
            if d["Type"]?.name == "Pages" || d["Kids"] != nil {
                for k in resolve(d["Kids"])?.array ?? [] { walk(k, m, r, depth: depth + 1) }
            } else {
                out.append(Page(dict: d, mediaBox: m ?? BBox2(min: .zero, max: Vec2(612, 792)), resources: r ?? [:]))
            }
        }
        if let cat = objects.values.first(where: { $0.dict?["Type"]?.name == "Catalog" }) { walk(cat.dict?["Pages"], nil, nil, depth: 0) }
        if out.isEmpty {
            for (_, o) in objects.sorted(by: { $0.key < $1.key }) where o.dict?["Type"]?.name == "Page" {
                out.append(Page(dict: o.dict!, mediaBox: BBox2(min: .zero, max: Vec2(612, 792)), resources: dict(o.dict?["Resources"]) ?? [:]))
            }
        }
        return out
    }()

    /// Decodes a PDF text string (UTF-16BE with BOM, UTF-8 with BOM, else PDFDocEncoding ≈ Latin-1).
    public static func text(_ d: Data) -> String {
        let b = [UInt8](d)
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF { return String(data: Data(b.dropFirst(2)), encoding: .utf16BigEndian) ?? "" }
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { return String(decoding: b.dropFirst(3), as: UTF8.self) }
        return String(data: d, encoding: .isoLatin1) ?? ""
    }
}

private extension Array {
    func windows(ofCount n: Int) -> [ArraySlice<Element>] { count < n ? [] : (0...(count - n)).map { self[$0..<($0 + n)] } }
}
private extension ArraySlice {
    func windows(ofCount n: Int) -> [ArraySlice<Element>] { count < n ? [] : (0...(count - n)).map { self[(startIndex + $0)..<(startIndex + $0 + n)] } }
}
