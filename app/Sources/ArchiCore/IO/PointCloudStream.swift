// Oanarina Archi Tool — GPL-3.0-or-later
// Out-of-core point cloud sampling (IO-049, IO-050): very large LAS, XYZ/PTS/TXT and PLY files (hundreds of millions of
// points, several GB) are memory-mapped and sampled at evenly spaced records instead of being read whole, so an
// import touches only the pages of the retained points and its memory use depends on the point budget, not on the
// file size. Fixed-size records (LAS, binary PLY) are addressed directly; text files are sampled at evenly spaced
// byte offsets (the next complete line after each offset) and their point count is estimated from the mean line
// length. Small files keep the exact full readers.
import Foundation

public enum PointCloudStream {
    public struct Sample {
        public var points: [CloudPoint]
        /// LAS classification per point (empty for other formats).
        public var classes: [UInt8]
        /// Total number of points in the file (estimated for text files that were sampled).
        public var total: Int
        public var estimated: Bool
    }

    /// Files larger than this are sampled instead of read whole.
    public static var streamThreshold = 48 << 20

    static func map(_ url: URL) throws -> Data { try Data(contentsOf: url, options: [.alwaysMapped]) }

    /// Evenly spaced LAS records (all of them when the file has fewer than `maxPoints`).
    public static func sampleLAS(_ data: Data, maxPoints: Int) throws -> (header: LASReader.Header, sample: Sample) {
        let h = try LASReader.header([UInt8](data.prefix(400)))
        let rec = h.recordLength
        guard rec >= 20, h.offsetToPoints > 0 else { throw PointCloud.CloudError.invalid("Invalid LAS header.") }
        let n = min(h.pointCount, max(0, (data.count - h.offsetToPoints) / rec))
        let count = maxPoints > 0 ? min(n, maxPoints) : n
        let step = count > 0 ? Double(n) / Double(count) : 1
        let lay = LASReader.layout(h.pointFormat)
        var raw: [(Vec3, Double, (Int, Int, Int)?, UInt8)] = []
        raw.reserveCapacity(count)
        var maxC = 0
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            func u16(_ o: Int) -> Int { Int(buf[o]) | Int(buf[o + 1]) << 8 }
            func i32(_ o: Int) -> Int { Int(Int32(bitPattern: UInt32(buf[o]) | UInt32(buf[o + 1]) << 8 | UInt32(buf[o + 2]) << 16 | UInt32(buf[o + 3]) << 24)) }
            for i in 0..<count {
                let idx = min(n - 1, Int(Double(i) * step))
                let o = h.offsetToPoints + idx * rec
                let p = Vec3(Double(i32(o)) * h.scale.x + h.offset.x, Double(i32(o + 4)) * h.scale.y + h.offset.y, Double(i32(o + 8)) * h.scale.z + h.offset.z)
                var rgb: (Int, Int, Int)?
                if let c = lay.rgb, c + 6 <= rec { rgb = (u16(o + c), u16(o + c + 2), u16(o + c + 4)); maxC = max(maxC, rgb!.0, rgb!.1, rgb!.2) }
                let cls: UInt8 = lay.cls < rec ? buf[o + lay.cls] & (h.pointFormat >= 6 ? 0xFF : 0x1F) : 0
                raw.append((p, Double(u16(o + 12)), rgb, cls))
            }
        }
        let shift = maxC > 255 ? 8 : 0
        var pts: [CloudPoint] = [], classes: [UInt8] = []
        pts.reserveCapacity(raw.count); classes.reserveCapacity(raw.count)
        for r in raw {
            var cp = CloudPoint(r.0, intensity: r.1)
            if let c = r.2 { cp.color = (UInt8(truncatingIfNeeded: c.0 >> shift), UInt8(truncatingIfNeeded: c.1 >> shift), UInt8(truncatingIfNeeded: c.2 >> shift)) }
            pts.append(cp); classes.append(r.3)
        }
        return (h, Sample(points: pts, classes: classes, total: h.pointCount, estimated: false))
    }

    /// Points of the lines starting after evenly spaced byte offsets of a text cloud (XYZ/PTS/TXT, or the vertex
    /// block of an ASCII PLY from `start`). Lines that are not points (PTS count, comments) are skipped.
    public static func sampleText(_ data: Data, maxPoints: Int, start: Int = 0, end: Int? = nil) -> Sample {
        let stop = min(end ?? data.count, data.count)
        guard stop > start else { return Sample(points: [], classes: [], total: 0, estimated: true) }
        let k = max(1, maxPoints)
        var pts: [CloudPoint] = []
        pts.reserveCapacity(min(k, 1 << 20))
        var lineBytes = 0, lines = 0
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var lastEnd = start
            for i in 0..<k {
                var o = start + Int(Double(stop - start) * Double(i) / Double(k))
                if o < lastEnd { o = lastEnd }
                // Move to the beginning of the next line (unless at the very start).
                if o > start { while o < stop && buf[o - 1] != 10 { o += 1 } }
                guard o < stop else { break }
                var e = o
                while e < stop && buf[e] != 10 { e += 1 }
                lastEnd = e + 1
                guard e > o else { continue }
                let line = String(decoding: UnsafeRawBufferPointer(rebasing: buf[o..<e]), as: UTF8.self)
                lineBytes += e - o + 1; lines += 1
                if let p = PointCloud.parseText(line).first { pts.append(p) }
            }
        }
        let mean = lines > 0 ? Double(lineBytes) / Double(lines) : 1
        let total = max(pts.count, Int((Double(stop - start) / max(mean, 1)).rounded()))
        return Sample(points: pts, classes: [], total: total, estimated: true)
    }

    struct PLYLayout { var binary: Bool; var big: Bool; var headerEnd: Int; var vertexCount: Int; var props: [(name: String, type: String)]; var onlyVertices: Bool }

    static func plyLayout(_ data: Data) -> PLYLayout? {
        let head = [UInt8](data.prefix(64 * 1024))
        guard head.count > 10, String(decoding: head.prefix(3), as: UTF8.self) == "ply" else { return nil }
        let marker = Array("end_header".utf8)
        var headerEnd = 0
        var i = 0
        while i + marker.count <= head.count {
            if head[i] == marker[0], Array(head[i..<(i + marker.count)]) == marker {
                var j = i + marker.count
                while j < head.count && head[j] != 10 { j += 1 }
                headerEnd = j + 1; break
            }
            i += 1
        }
        guard headerEnd > 0 else { return nil }
        var format = "ascii", vcount = 0, props: [(String, String)] = [], inVertex = false, elements = 0, vertexFirst = false, hasList = false
        for l in String(decoding: head[0..<headerEnd], as: UTF8.self).split(whereSeparator: { $0.isNewline }) {
            let t = l.split(separator: " ").map(String.init)
            switch t.first {
            case "format": if t.count > 1 { format = t[1] }
            case "element":
                elements += 1
                inVertex = t.count >= 3 && t[1] == "vertex"
                if inVertex { vcount = Int(t[2]) ?? 0; vertexFirst = elements == 1 }
            case "property" where inVertex:
                if t.count >= 2 && t[1] == "list" { hasList = true } else if t.count >= 3 { props.append((t[2], t[1])) }
            default: break
            }
        }
        guard vertexFirst, !hasList, vcount > 0 else { return nil }
        return PLYLayout(binary: format != "ascii", big: format == "binary_big_endian", headerEnd: headerEnd, vertexCount: vcount, props: props, onlyVertices: elements == 1)
    }

    static func plySize(_ t: String) -> Int {
        switch t { case "char", "uchar", "int8", "uint8": return 1; case "short", "ushort", "int16", "uint16": return 2
        case "double", "float64": return 8; default: return 4 }
    }

    /// Evenly spaced vertices of a binary PLY with fixed-size vertex records (the vertex element first).
    static func sampleBinaryPLY(_ data: Data, _ lay: PLYLayout, maxPoints: Int) -> Sample {
        let rec = lay.props.reduce(0) { $0 + plySize($1.type) }
        let n = min(lay.vertexCount, max(0, (data.count - lay.headerEnd) / max(rec, 1)))
        let count = maxPoints > 0 ? min(n, maxPoints) : n
        let step = count > 0 ? Double(n) / Double(count) : 1
        var offsets: [String: (Int, String)] = [:]
        var acc = 0
        for p in lay.props { offsets[p.name] = (acc, p.type); acc += plySize(p.type) }
        var pts: [CloudPoint] = []
        pts.reserveCapacity(count)
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            func read(_ o: Int, _ t: String) -> Double {
                let s = plySize(t)
                var bits: UInt64 = 0
                for k in 0..<s { let b = UInt64(buf[o + (lay.big ? s - 1 - k : k)]); bits |= b << (8 * UInt64(k)) }
                switch t {
                case "float", "float32": return Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
                case "double", "float64": return Double(bitPattern: bits)
                case "char", "int8": return Double(Int8(truncatingIfNeeded: bits))
                case "short", "int16": return Double(Int16(truncatingIfNeeded: bits))
                case "int", "int32": return Double(Int32(truncatingIfNeeded: bits))
                default: return Double(bits)
                }
            }
            func val(_ base: Int, _ names: [String]) -> Double? {
                for nm in names { if let (o, t) = offsets[nm] { return read(base + o, t) } }
                return nil
            }
            for i in 0..<count {
                let base = lay.headerEnd + min(n - 1, Int(Double(i) * step)) * rec
                var cp = CloudPoint(Vec3(val(base, ["x"]) ?? 0, val(base, ["y"]) ?? 0, val(base, ["z"]) ?? 0))
                if let r = val(base, ["red", "r"]), let g = val(base, ["green", "g"]), let b = val(base, ["blue", "b"]) {
                    let unit = (offsets["red"]?.1 ?? "").hasPrefix("float") && r <= 1 && g <= 1 && b <= 1
                    let k = unit ? 255.0 : 1
                    cp.color = (UInt8(max(0, min(255, r * k))), UInt8(max(0, min(255, g * k))), UInt8(max(0, min(255, b * k))))
                }
                if let s = val(base, ["intensity", "scalar_intensity"]) { cp.intensity = s }
                pts.append(cp)
            }
        }
        return Sample(points: pts, classes: [], total: lay.vertexCount, estimated: false)
    }

    /// Samples any supported cloud file (las, xyz, pts, txt, csv, ply) to about `maxPoints` points.
    /// Returns nil when the file needs the full reader (PLY with faces or lists before the vertices, LAZ, E57).
    public static func sample(_ url: URL, maxPoints: Int) throws -> Sample? {
        let data = try map(url)
        switch url.pathExtension.lowercased() {
        case "las": return try sampleLAS(data, maxPoints: maxPoints).sample
        case "ply":
            guard let lay = plyLayout(data) else { return nil }
            if lay.binary { return sampleBinaryPLY(data, lay, maxPoints: maxPoints) }
            guard lay.onlyVertices else { return nil }
            var s = sampleText(data, maxPoints: maxPoints, start: lay.headerEnd)
            s.total = lay.vertexCount; s.estimated = false
            return s
        case "xyz", "pts", "txt", "csv", "asc": return sampleText(data, maxPoints: maxPoints)
        default: return nil
        }
    }

    /// Point entities from a cloud file: files above `streamThreshold` are sampled out of core; smaller ones use
    /// the exact readers. The budget `options.maxPoints` (0 = all) and voxel filter apply to the sampled points.
    public static func load(_ url: URL, options: PointCloudOptions, origin: Vec3 = .zero, threshold: Int? = nil) throws -> (entities: [Entity], total: Int, sampled: Bool) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
        let ext = url.pathExtension.lowercased()
        if size > (threshold ?? streamThreshold), let s = try sample(url, maxPoints: options.maxPoints > 0 ? options.maxPoints * (options.voxel > 0 ? 4 : 1) : 0) {
            guard !s.points.isEmpty else { throw PointCloud.CloudError.invalid("No points found.") }
            var pts = s.points
            if origin != .zero { for i in pts.indices { pts[i].p = pts[i].p - origin } }
            var ents = PointCloud.entities(pts, options: options)
            if ents.count == s.classes.count { for i in ents.indices where s.classes[i] != 0 { ents[i].props["class"] = "\(s.classes[i])" } }
            return (ents, s.total, true)
        }
        if ext == "las" {
            let r = try LASReader.entities(try Data(contentsOf: url), options: options, origin: origin)
            return (r.entities, r.total, false)
        }
        let r = try PointCloud.load(try Data(contentsOf: url), ext: ext, options: options)
        return (r.entities, r.total, false)
    }
}
