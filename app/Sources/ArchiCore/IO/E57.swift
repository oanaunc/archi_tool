// Oanarina Archi Tool — GPL-3.0-or-later
// ASTM E57 point clouds (IO-048): reader and writer for the paged E57 container (1024-byte pages with CRC-32C),
// the XML section and CompressedVector binary sections with the default bit-pack codec. Supported point fields:
// cartesianX/Y/Z or sphericalRange/Azimuth/Elevation (Float, ScaledInteger or Integer), cartesianInvalidState,
// colorRed/Green/Blue and intensity (normalised with colorLimits / intensityLimits), and each scan's pose
// (rigidBodyTransform). Written from the ASTM E2807 standard's description; no libE57Format code is used.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum E57 {
    public struct E57Error: Error, LocalizedError { public let message: String; public var errorDescription: String? { "E57: " + message } }

    static let pageSize = 1024, logicalPage = 1020

    // MARK: CRC-32C (Castagnoli)
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0x82F63B78 : c >> 1 }
        return c
    }
    static func crc32c(_ b: ArraySlice<UInt8>) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for x in b { c = crcTable[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    // MARK: Paged container

    /// Logical bytes (checksums stripped) of the whole file.
    static func logical(_ d: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []; out.reserveCapacity(d.count)
        var i = 0
        while i < d.count { out += d[i..<min(i + logicalPage, d.count)]; i += pageSize }
        return out
    }
    static func logicalOffset(_ physical: Int) -> Int { (physical / pageSize) * logicalPage + physical % pageSize }
    static func physicalOffset(_ logical: Int) -> Int { (logical / logicalPage) * pageSize + logical % logicalPage }

    /// Physical file from a logical stream: pages padded and checksummed (big-endian CRC-32C).
    static func paged(_ l: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        repeat {
            var page = Array(l[i..<min(i + logicalPage, l.count)])
            page += [UInt8](repeating: 0, count: logicalPage - page.count)
            let c = crc32c(page[...])
            out += page + [UInt8(c >> 24), UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF)]
            i += logicalPage
        } while i < l.count
        return out
    }

    /// Pages whose checksum does not match (either byte order is accepted).
    public static func badPages(_ data: Data) -> [Int] {
        let d = [UInt8](data)
        var bad: [Int] = []
        var p = 0
        while p + pageSize <= d.count {
            let c = crc32c(d[p..<(p + logicalPage)])
            let s = d[(p + logicalPage)..<(p + pageSize)].map { UInt32($0) }
            let be = s[0] << 24 | s[1] << 16 | s[2] << 8 | s[3], le = s[3] << 24 | s[2] << 16 | s[1] << 8 | s[0]
            if c != be && c != le { bad.append(p / pageSize) }
            p += pageSize
        }
        return bad
    }

    // MARK: Model

    public struct Scan {
        public var name: String
        public var points: [CloudPoint]
        public init(name: String, points: [CloudPoint]) { self.name = name; self.points = points }
    }

    struct Field { var name: String; var type: String; var precision: String = "double"; var min = 0.0, max = 0.0, scale = 1.0, offset = 0.0
        var bits: Int {
            switch type {
            case "Float": return precision == "single" ? 32 : 64
            default:
                let range = max - min
                if range < 1 { return 0 }
                return Int(ceil(log2(range + 1)))
            }
        }
    }

    // MARK: XML tree
    final class Node { var name: String; var attrs: [String: String]; var text = ""; var children: [Node] = []
        init(_ n: String, _ a: [String: String]) { name = n; attrs = a }
        func child(_ n: String) -> Node? { children.first { $0.name == n } }
        var number: Double? { Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    final class TreeBuilder: NSObject, XMLParserDelegate {
        var stack: [Node] = [Node("#doc", [:])]
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
            let n = Node(e.split(separator: ":").last.map(String.init) ?? e, a); stack.last?.children.append(n); stack.append(n)
        }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) { if stack.count > 1 { stack.removeLast() } }
        func parser(_ p: XMLParser, foundCharacters s: String) { stack.last?.text += s }
        func parser(_ p: XMLParser, foundCDATA d: Data) { stack.last?.text += String(decoding: d, as: UTF8.self) }
    }

    // MARK: Reading

    /// Reads all scans (coordinates in metres, poses applied). `maxPoints` > 0 stops after that many points in total.
    public static func read(_ data: Data, maxPoints: Int = 0) throws -> [Scan] {
        let phys = [UInt8](data)
        guard phys.count >= 48, String(bytes: phys[0..<8], encoding: .ascii) == "ASTM-E57" else { throw E57Error(message: "not an E57 file") }
        func le64(_ b: [UInt8], _ i: Int) -> Int { var v: UInt64 = 0; for k in 0..<8 { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }; return Int(truncatingIfNeeded: v) }
        func le16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        let major = Int(phys[8]) | Int(phys[9]) << 8
        guard major == 1 else { throw E57Error(message: "unsupported version \(major)") }
        let xmlOff = le64(phys, 24), xmlLen = le64(phys, 32)
        let ps = le64(phys, 40)
        guard ps == pageSize else { throw E57Error(message: "unsupported page size \(ps)") }
        let log = logical(phys)
        let xs = logicalOffset(xmlOff)
        guard xs >= 0, xs + xmlLen <= log.count else { throw E57Error(message: "XML section outside the file") }
        let parser = XMLParser(data: Data(log[xs..<(xs + xmlLen)]))
        let tb = TreeBuilder(); parser.delegate = tb
        guard parser.parse(), let root = tb.stack.first?.children.first else { throw E57Error(message: "invalid XML section") }
        guard let data3D = root.child("data3D") else { return [] }
        var scans: [Scan] = []
        var total = 0
        for (si, scan) in data3D.children.enumerated() {
            guard let pts = scan.child("points"), pts.attrs["type"] == "CompressedVector",
                  let off = Int(pts.attrs["fileOffset"] ?? ""), let count = Int(pts.attrs["recordCount"] ?? ""), let proto = pts.child("prototype") else { continue }
            if let codecs = pts.child("codecs"), !codecs.children.isEmpty, codecs.children.contains(where: { $0.child("bitPackCodec") == nil && $0.child("inputs") != nil }) {
                throw E57Error(message: "unsupported codec in scan \(si + 1)")
            }
            let fields: [Field] = proto.children.map { n in
                Field(name: n.name, type: n.attrs["type"] ?? "Float", precision: n.attrs["precision"] ?? "double",
                      min: Double(n.attrs["minimum"] ?? "") ?? 0, max: Double(n.attrs["maximum"] ?? "") ?? 0,
                      scale: Double(n.attrs["scale"] ?? "") ?? 1, offset: Double(n.attrs["offset"] ?? "") ?? 0)
            }
            // Section header and packets.
            let sh = logicalOffset(off)
            guard sh + 32 <= log.count, log[sh] == 1 else { throw E57Error(message: "bad CompressedVector section in scan \(si + 1)") }
            let secLen = le64(log, sh + 8)
            var p = logicalOffset(le64(log, sh + 16))
            let end = sh + secLen
            var streams = [[UInt8]](repeating: [], count: fields.count)
            while p + 4 <= min(end, log.count) {
                let type = log[p]
                let len = le16(log, p + 2) + 1
                if type == 1 {
                    let n = le16(log, p + 4)
                    var q = p + 6 + 2 * n
                    for k in 0..<n {
                        let bl = le16(log, p + 6 + 2 * k)
                        if k < streams.count, q + bl <= log.count { streams[k] += log[q..<(q + bl)] }
                        q += bl
                    }
                }
                p += max(4, len)
            }
            // Decode each field.
            var values = [[Double]](repeating: [], count: fields.count)
            for (k, f) in fields.enumerated() {
                let s = streams[k]
                var v: [Double] = []; v.reserveCapacity(count)
                if f.type == "Float" {
                    let w = f.precision == "single" ? 4 : 8
                    var i = 0
                    while i + w <= s.count && v.count < count {
                        if w == 8 { var u: UInt64 = 0; for b in 0..<8 { u |= UInt64(s[i + b]) << (8 * UInt64(b)) }; v.append(Double(bitPattern: u)) }
                        else { var u: UInt32 = 0; for b in 0..<4 { u |= UInt32(s[i + b]) << (8 * UInt32(b)) }; v.append(Double(Float(bitPattern: u))) }
                        i += w
                    }
                } else {
                    let bits = f.bits
                    if bits == 0 { v = [Double](repeating: f.min, count: count) }
                    else {
                        var bitPos = 0
                        let totalBits = s.count * 8
                        if bits % 8 == 0 {
                            let w = bits / 8
                            var i = 0
                            while i + w <= s.count && v.count < count {
                                var raw: UInt64 = 0
                                for b in 0..<w { raw |= UInt64(s[i + b]) << (8 * UInt64(b)) }
                                i += w
                                let iv = Double(raw) + f.min
                                v.append(f.type == "ScaledInteger" ? iv * f.scale + f.offset : iv)
                            }
                            bitPos = totalBits
                        }
                        while bitPos + bits <= totalBits && v.count < count {
                            var raw: UInt64 = 0
                            for b in 0..<bits {
                                let bp = bitPos + b
                                if (s[bp >> 3] >> UInt8(bp & 7)) & 1 == 1 { raw |= 1 << UInt64(b) }
                            }
                            bitPos += bits
                            let iv = Double(raw) + f.min
                            v.append(f.type == "ScaledInteger" ? iv * f.scale + f.offset : iv)
                        }
                    }
                }
                values[k] = v
            }
            func col(_ n: String) -> [Double]? { fields.firstIndex { $0.name == n }.map { values[$0] } }
            func limit(_ group: String, _ key: String, _ def: Double) -> Double { scan.child(group)?.child(key)?.number ?? def }
            func protoMax(_ n: String, _ def: Double) -> Double { fields.first { $0.name == n }.map { $0.type == "Float" ? def : $0.max * $0.scale + $0.offset } ?? def }
            func protoMin(_ n: String) -> Double { fields.first { $0.name == n }.map { $0.type == "Float" ? 0 : $0.min * $0.scale + $0.offset } ?? 0 }
            let cx = col("cartesianX"), cy = col("cartesianY"), cz = col("cartesianZ")
            let sr = col("sphericalRange"), sa = col("sphericalAzimuth"), se = col("sphericalElevation")
            let inv = col("cartesianInvalidState") ?? col("sphericalInvalidState")
            let red = col("colorRed"), green = col("colorGreen"), blue = col("colorBlue"), inten = col("intensity")
            let rMin = limit("colorLimits", "colorRedMinimum", protoMin("colorRed")), rMax = limit("colorLimits", "colorRedMaximum", protoMax("colorRed", 255))
            let gMin = limit("colorLimits", "colorGreenMinimum", protoMin("colorGreen")), gMax = limit("colorLimits", "colorGreenMaximum", protoMax("colorGreen", 255))
            let bMin = limit("colorLimits", "colorBlueMinimum", protoMin("colorBlue")), bMax = limit("colorLimits", "colorBlueMaximum", protoMax("colorBlue", 255))
            let iMin = limit("intensityLimits", "intensityMinimum", protoMin("intensity")), iMax = limit("intensityLimits", "intensityMaximum", protoMax("intensity", 1))
            // Pose.
            var q = (w: 1.0, x: 0.0, y: 0.0, z: 0.0), t = Vec3.zero
            if let pose = scan.child("pose") {
                if let r = pose.child("rotation") { q = (r.child("w")?.number ?? 1, r.child("x")?.number ?? 0, r.child("y")?.number ?? 0, r.child("z")?.number ?? 0) }
                if let tr = pose.child("translation") { t = Vec3(tr.child("x")?.number ?? 0, tr.child("y")?.number ?? 0, tr.child("z")?.number ?? 0) }
            }
            func rotate(_ p: Vec3) -> Vec3 {
                let (w, x, y, z) = q
                let m00 = 1 - 2 * (y * y + z * z), m01 = 2 * (x * y - z * w), m02 = 2 * (x * z + y * w)
                let m10 = 2 * (x * y + z * w), m11 = 1 - 2 * (x * x + z * z), m12 = 2 * (y * z - x * w)
                let m20 = 2 * (x * z - y * w), m21 = 2 * (y * z + x * w), m22 = 1 - 2 * (x * x + y * y)
                return Vec3(m00 * p.x + m01 * p.y + m02 * p.z, m10 * p.x + m11 * p.y + m12 * p.z, m20 * p.x + m21 * p.y + m22 * p.z) + t
            }
            func norm(_ v: Double, _ lo: Double, _ hi: Double) -> UInt8 { hi > lo ? UInt8(max(0, min(255, ((v - lo) / (hi - lo) * 255).rounded()))) : UInt8(max(0, min(255, v))) }
            var out: [CloudPoint] = []
            for i in 0..<count {
                if maxPoints > 0 && total >= maxPoints { break }
                if let inv, i < inv.count, inv[i] != 0 { continue }
                var p: Vec3
                if let cx, let cy, let cz, i < cx.count, i < cy.count, i < cz.count { p = Vec3(cx[i], cy[i], cz[i]) }
                else if let sr, let sa, let se, i < sr.count, i < sa.count, i < se.count {
                    p = Vec3(sr[i] * cos(se[i]) * cos(sa[i]), sr[i] * cos(se[i]) * sin(sa[i]), sr[i] * sin(se[i]))
                } else { continue }
                p = rotate(p)
                var cp = CloudPoint(p)
                if let red, let green, let blue, i < red.count, i < green.count, i < blue.count {
                    cp.color = (norm(red[i], rMin, rMax), norm(green[i], gMin, gMax), norm(blue[i], bMin, bMax))
                }
                if let inten, i < inten.count { cp.intensity = iMax > iMin ? (inten[i] - iMin) / (iMax - iMin) : inten[i] }
                out.append(cp); total += 1
            }
            scans.append(Scan(name: scan.child("name")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Scan \(si + 1)", points: out))
        }
        return scans
    }

    /// Point entities of all scans (drawing units per metre = options.scale).
    public static func entities(_ data: Data, options: PointCloudOptions) throws -> (entities: [Entity], total: Int) {
        let scans = try read(data)
        let pts = scans.flatMap(\.points)
        guard !pts.isEmpty else { throw E57Error(message: "no points") }
        return (PointCloud.entities(pts, options: options), pts.count)
    }

    /// Point entities of a drawing as cloud points in metres (z from the "z" property, colour, intensity).
    public static func points(from doc: ArchiDocument) -> [CloudPoint] {
        let k = doc.units.mm / 1000
        return doc.entities.compactMap { e in
            guard case .point(let p) = e.geometry else { return nil }
            var cp = CloudPoint(Vec3(p.x * k, p.y * k, (Double(e.props["z"] ?? "") ?? 0) * k))
            if case .rgb(let r, let g, let b) = e.color { cp.color = (r, g, b) }
            cp.intensity = Double(e.props["intensity"] ?? "")
            return cp
        }
    }

    // MARK: Writing

    /// Writes scans as E57 (double-precision Cartesian coordinates in metres; 8-bit colour and intensity when present).
    public static func write(_ scans: [Scan], guid: String = UUID().uuidString) -> Data {
        var l = [UInt8](repeating: 0, count: 48)   // header placeholder
        func pad8() { while l.count % 8 != 0 { l.append(0) } }
        func put16(_ v: Int, at: Int? = nil) { let b = [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]; if let a = at { l[a] = b[0]; l[a + 1] = b[1] } else { l += b } }
        func put64(_ v: Int, at: Int) { for k in 0..<8 { l[at + k] = UInt8((UInt64(v) >> (8 * UInt64(k))) & 0xFF) } }
        func xmlEscape(_ s: String) -> String { s.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>") }
        var xmlScans = ""
        for (si, scan) in scans.enumerated() {
            pad8()
            let hasColor = scan.points.contains { $0.color != nil }
            let hasIntensity = scan.points.contains { $0.intensity != nil }
            let secStart = l.count
            l += [1, 0, 0, 0, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 24)
            let dataStart = l.count
            let per = 1500
            var i = 0
            let pts = scan.points
            repeat {
                let chunk = pts[i..<min(i + per, pts.count)]
                var streams: [[UInt8]] = []
                func dbl(_ f: (CloudPoint) -> Double) -> [UInt8] {
                    var b: [UInt8] = []; b.reserveCapacity(chunk.count * 8)
                    for p in chunk { let u = f(p).bitPattern; for k in 0..<8 { b.append(UInt8((u >> (8 * UInt64(k))) & 0xFF)) } }
                    return b
                }
                streams.append(dbl { $0.p.x }); streams.append(dbl { $0.p.y }); streams.append(dbl { $0.p.z })
                if hasColor {
                    streams.append(chunk.map { $0.color?.0 ?? 0 }); streams.append(chunk.map { $0.color?.1 ?? 0 }); streams.append(chunk.map { $0.color?.2 ?? 0 })
                }
                if hasIntensity { streams.append(dbl { $0.intensity ?? 0 }) }
                let start = l.count
                l += [1, 0, 0, 0]
                put16(streams.count)
                for s in streams { put16(s.count) }
                for s in streams { l += s }
                while (l.count - start) % 4 != 0 { l.append(0) }
                put16(l.count - start - 1, at: start + 2)
                i += per
            } while i < pts.count
            let secLen = l.count - secStart
            put64(secLen, at: secStart + 8)
            put64(physicalOffset(dataStart), at: secStart + 16)
            put64(0, at: secStart + 24)
            var proto = "<cartesianX type=\"Float\"/><cartesianY type=\"Float\"/><cartesianZ type=\"Float\"/>"
            if hasColor { proto += ["Red", "Green", "Blue"].map { "<color\($0) type=\"Integer\" minimum=\"0\" maximum=\"255\"/>" }.joined() }
            if hasIntensity { proto += "<intensity type=\"Float\"/>" }
            var bb = BBox3.empty
            for p in pts { bb.min = Vec3(min(bb.min.x, p.p.x), min(bb.min.y, p.p.y), min(bb.min.z, p.p.z)); bb.max = Vec3(max(bb.max.x, p.p.x), max(bb.max.y, p.p.y), max(bb.max.z, p.p.z)) }
            var extra = ""
            if !pts.isEmpty {
                extra += "<cartesianBounds type=\"Structure\"><xMinimum type=\"Float\">\(bb.min.x)</xMinimum><xMaximum type=\"Float\">\(bb.max.x)</xMaximum><yMinimum type=\"Float\">\(bb.min.y)</yMinimum><yMaximum type=\"Float\">\(bb.max.y)</yMaximum><zMinimum type=\"Float\">\(bb.min.z)</zMinimum><zMaximum type=\"Float\">\(bb.max.z)</zMaximum></cartesianBounds>"
            }
            if hasColor { extra += "<colorLimits type=\"Structure\">" + ["Red", "Green", "Blue"].map { "<color\($0)Minimum type=\"Integer\">0</color\($0)Minimum><color\($0)Maximum type=\"Integer\">255</color\($0)Maximum>" }.joined() + "</colorLimits>" }
            if hasIntensity { extra += "<intensityLimits type=\"Structure\"><intensityMinimum type=\"Float\">0</intensityMinimum><intensityMaximum type=\"Float\">1</intensityMaximum></intensityLimits>" }
            xmlScans += "<vectorChild type=\"Structure\"><guid type=\"String\"><![CDATA[{\(guid)-\(si)}]]></guid><name type=\"String\"><![CDATA[\(xmlEscape(scan.name))]]></name>"
                + "<points type=\"CompressedVector\" fileOffset=\"\(physicalOffset(secStart))\" recordCount=\"\(pts.count)\"><prototype type=\"Structure\">\(proto)</prototype><codecs type=\"Vector\" allowHeterogeneousChildren=\"1\"></codecs></points>\(extra)</vectorChild>"
        }
        pad8()
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<e57Root type=\"Structure\" xmlns=\"http://www.astm.org/COMMIT/E57/2010-e57-v1.0\">"
            + "<formatName type=\"String\"><![CDATA[ASTM E57 3D Imaging Data File]]></formatName><guid type=\"String\"><![CDATA[{\(guid)}]]></guid>"
            + "<versionMajor type=\"Integer\">1</versionMajor><versionMinor type=\"Integer\">0</versionMinor>"
            + "<e57LibraryVersion type=\"String\"><![CDATA[Oanarina Archi Tool]]></e57LibraryVersion><coordinateMetadata type=\"String\"></coordinateMetadata>"
            + "<data3D type=\"Vector\" allowHeterogeneousChildren=\"1\">\(xmlScans)</data3D><images2D type=\"Vector\" allowHeterogeneousChildren=\"1\"></images2D></e57Root>\n"
        let xmlStart = l.count
        let xb = Array(xml.utf8)
        l += xb
        // Header.
        for (k, c) in Array("ASTM-E57".utf8).enumerated() { l[k] = c }
        l[8] = 1   // major 1, minor 0
        let physicalLength = ((l.count + logicalPage - 1) / logicalPage) * pageSize
        put64(physicalLength, at: 16)
        put64(physicalOffset(xmlStart), at: 24)
        put64(xb.count, at: 32)
        put64(pageSize, at: 40)
        return Data(paged(l))
    }
}
