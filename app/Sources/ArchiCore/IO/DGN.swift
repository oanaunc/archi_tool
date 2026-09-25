// Oanarina Archi Tool — GPL-3.0-or-later
// MicroStation DGN V7 (ISFF) import and export of 2D geometry (IO-013), written from the published element layouts
// (as documented by the GDAL/OGR DGN driver notes, Frank Warmerdam): design file header (type 9, units and origin),
// lines (3), line strings (4), shapes (6), curves (11), ellipses and circles (15), arcs (16), text (17); levels 1–63 map to
// layers "LEVEL n" (export: one level per drawing layer), colour indexes to ACI. Coordinates are 32-bit integers in
// units of resolution (middle-endian), axes and origins VAX D-float doubles. 3D files are read with Z dropped.
import Foundation

public enum DGN {
    public struct DGNError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    // MARK: number formats
    static func int32(_ b: [UInt8], _ o: Int) -> Int32 {
        Int32(bitPattern: UInt32(b[o + 2]) | UInt32(b[o + 3]) << 8 | UInt32(b[o]) << 16 | UInt32(b[o + 1]) << 24)
    }
    static func putInt32(_ v: Int32, _ out: inout [UInt8]) {
        let u = UInt32(bitPattern: v)
        out += [UInt8(u >> 16 & 0xFF), UInt8(u >> 24 & 0xFF), UInt8(u & 0xFF), UInt8(u >> 8 & 0xFF)]
    }
    static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    static func putU16(_ v: Int, _ out: inout [UInt8]) { out += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }

    /// VAX D-float → IEEE double.
    static func vax(_ b: [UInt8], _ o: Int) -> Double {
        var hi = UInt32(b[o + 2]) | UInt32(b[o + 3]) << 8 | UInt32(b[o]) << 16 | UInt32(b[o + 1]) << 24
        var lo = UInt32(b[o + 6]) | UInt32(b[o + 7]) << 8 | UInt32(b[o + 4]) << 16 | UInt32(b[o + 5]) << 24
        let sign = hi & 0x8000_0000
        var exponent = (hi >> 23) & 0xFF
        if exponent != 0 { exponent = exponent + 1023 - 129 }
        let rnd = lo & 7
        lo = (lo >> 3) | (hi << 29)
        if rnd != 0 { lo |= 1 }
        hi = (hi >> 3) & 0x000F_FFFF
        hi |= (exponent << 20) | sign
        return Double(bitPattern: UInt64(hi) << 32 | UInt64(lo))
    }
    static func putVax(_ d: Double, _ out: inout [UInt8]) {
        let bits = d.bitPattern
        var hi = UInt32(bits >> 32), lo = UInt32(bits & 0xFFFF_FFFF)
        let sign = hi & 0x8000_0000
        var exponent = (hi >> 20) & 0x7FF
        if exponent != 0 { exponent = UInt32(max(1, min(255, Int(exponent) - 1023 + 129))) }
        hi = ((hi & 0x000F_FFFF) << 3) | (lo >> 29) | (exponent << 23) | sign
        lo = lo << 3
        if d == 0 { hi = 0; lo = 0 }
        out += [UInt8(hi >> 16 & 0xFF), UInt8(hi >> 24 & 0xFF), UInt8(hi & 0xFF), UInt8(hi >> 8 & 0xFF),
                UInt8(lo >> 16 & 0xFF), UInt8(lo >> 24 & 0xFF), UInt8(lo & 0xFF), UInt8(lo >> 8 & 0xFF)]
    }

    // MARK: read

    public struct ReadResult { public var entities: [Entity]; public var masterUnit: String; public var is3D: Bool }

    /// Reads a V7 design file into entities in millimetres (master units are assumed to be metres when the header names
    /// "m"/"M"; "mm", "cm", "ft"/"'", "in"/"\"" are recognised; otherwise 1 master unit = 1 mm).
    public static func read(_ data: Data) throws -> ReadResult {
        let b = [UInt8](data)
        guard b.count >= 4 else { throw DGNError(message: "Empty DGN file.") }
        guard b[1] & 0x7F == 9, b.count >= 1536 else {
            if b.count > 8, Array(b.prefix(8)) == [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] { throw DGNError(message: "This is a DGN V8 file (OLE container): save it as V7 or DWG/DXF from MicroStation.") }
            throw DGNError(message: "Not a DGN V7 design file.")
        }
        let is3D = b[1214] & 0x40 != 0
        let subPerMaster = max(1, Int(int32(b, 1112))), uorPerSub = max(1, Int(int32(b, 1116)))
        let master = String(bytes: b[1120..<1122].filter { $0 >= 32 && $0 < 127 }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        let scale = 1.0 / Double(subPerMaster * uorPerSub)         // UOR → master units
        let mmPerMaster: Double
        switch master.lowercased() { case "m", "mu": mmPerMaster = 1000; case "mm": mmPerMaster = 1; case "cm": mmPerMaster = 10; case "ft", "'": mmPerMaster = 304.8; case "in", "\"": mmPerMaster = 25.4; case "km": mmPerMaster = 1_000_000; default: mmPerMaster = 1 }
        let ox = vax(b, 1240) * scale, oy = vax(b, 1248) * scale
        let k = mmPerMaster
        func P(_ o: Int) -> Vec2 { Vec2((Double(int32(b, o)) * scale - ox) * k, (Double(int32(b, o + 4)) * scale - oy) * k) }
        let ptSize = is3D ? 12 : 8
        var out: [Entity] = []
        var i = 0
        while i + 4 <= b.count {
            if b[i] == 0xFF && b[i + 1] == 0xFF { break }
            let level = Int(b[i] & 0x3F), type = Int(b[i + 1] & 0x7F), deleted = b[i + 1] & 0x80 != 0
            let size = (u16(b, i + 2) + 2) * 2
            guard size >= 4, i + size <= b.count else { break }
            defer { i += size }
            guard !deleted, size >= 36, type != 9, type != 8, type != 10 else { continue }
            let e = i
            let color = Int(b[e + 35]), weight = Int(b[e + 34] & 0xF8) >> 3
            var g: Geometry?
            switch type {
            case 3 where size >= 36 + 2 * ptSize:
                g = .line(LineGeom(P(e + 36), P(e + 36 + ptSize)))
            case 4, 6, 11:
                guard size >= 38 else { break }
                let n = u16(b, e + 36)
                guard n >= 2, e + 38 + n * ptSize <= e + size else { break }
                var pts = (0..<n).map { P(e + 38 + $0 * ptSize) }
                if type == 6 {
                    if pts.count > 3, pts.first!.distance(to: pts.last!) < 1e-9 { pts.removeLast() }
                    g = .polyline(PolylineGeom(points: pts, closed: true))
                } else if type == 11 {
                    // Curve: the first and last two points are end tangent helpers.
                    let body = pts.count > 4 ? Array(pts[2..<(pts.count - 2)]) : pts
                    g = .spline(SplineGeom(controlPoints: [], fitPoints: body))
                } else { g = .polyline(PolylineGeom(points: pts)) }
            case 15 where !is3D && size >= 72:
                let a = vax(b, e + 36) * scale * k, bb = vax(b, e + 44) * scale * k
                let rot = Double(int32(b, e + 52)) / 360000 * .pi / 180
                let c = Vec2((vax(b, e + 56) * scale - ox) * k, (vax(b, e + 64) * scale - oy) * k)
                if abs(a - bb) < 1e-9 * max(a, 1) { g = .circle(CircleGeom(c, a)) }
                else { g = .ellipse(EllipseGeom(center: c, majorAxis: Vec2.polar(a, rot), ratio: a > 0 ? bb / a : 1)) }
            case 16 where !is3D && size >= 80:
                let start = Double(int32(b, e + 36)) / 360000
                var sweepRaw = UInt32(bitPattern: int32(b, e + 40))
                var sweep: Double
                if sweepRaw & 0x8000_0000 != 0 { sweepRaw &= 0x7FFF_FFFF; sweep = -Double(sweepRaw) / 360000 } else { sweep = Double(sweepRaw) / 360000 }
                if sweep == 0 { sweep = 360 }
                let a = vax(b, e + 44) * scale * k, bb = vax(b, e + 52) * scale * k
                let rot = Double(int32(b, e + 60)) / 360000
                let c = Vec2((vax(b, e + 64) * scale - ox) * k, (vax(b, e + 72) * scale - oy) * k)
                var s0 = (start + rot) * .pi / 180, s1 = (start + rot + sweep) * .pi / 180
                if sweep < 0 { swap(&s0, &s1) }
                if abs(a - bb) < 1e-9 * max(a, 1) { g = .arc(ArcGeom(c, a, s0, s1)) }
                else { g = .ellipse(EllipseGeom(center: c, majorAxis: Vec2.polar(a, rot * .pi / 180), ratio: a > 0 ? bb / a : 1, start: (start) * .pi / 180, end: (start + sweep) * .pi / 180)) }
            case 17 where !is3D && size >= 60:
                let hMult = Double(int32(b, e + 42)) * scale * 6 / 1000 * k
                let rot = Double(int32(b, e + 46)) / 360000 * .pi / 180
                let o = P(e + 50)
                let n = Int(b[e + 58])
                let bytes = b[(e + 60)..<min(e + 60 + n, e + size)]
                let text = String(bytes: bytes, encoding: .isoLatin1) ?? ""
                g = .text(TextGeom(position: o, height: max(hMult, 1e-6), content: text, rotation: rot))
            default: break
            }
            guard let geom = g else { continue }
            var ent = Entity(layer: "LEVEL \(level)", color: color == 0 ? .byLayer : .aci(color), geometry: geom)
            if weight > 0 { ent.lineweight = Double(weight) * 0.13 + 0.13 }
            out.append(ent)
        }
        guard !out.isEmpty else { throw DGNError(message: "The DGN file has no supported 2D elements.") }
        return ReadResult(entities: out, masterUnit: master, is3D: is3D)
    }

    // MARK: write

    /// Writes a 2D V7 design file: master unit m, 1000 sub-units (mm) per master, 10 units of resolution per mm.
    public static func write(_ doc: ArchiDocument) -> Data {
        let uorPerMM = 10.0
        let toUOR = doc.units.mm * uorPerMM
        var out = [UInt8]()
        // Design file header (type 9), 1536 bytes.
        var tcb = [UInt8](repeating: 0, count: 1536)
        tcb[0] = 8; tcb[1] = 9
        tcb[2] = UInt8((766) & 0xFF); tcb[3] = UInt8(766 >> 8)
        var tmp = [UInt8](); putInt32(1000, &tmp); tcb.replaceSubrange(1112..<1116, with: tmp)
        tmp = []; putInt32(Int32(uorPerMM), &tmp); tcb.replaceSubrange(1116..<1120, with: tmp)
        tcb[1120] = UInt8(ascii: "m"); tcb[1121] = UInt8(ascii: " "); tcb[1122] = UInt8(ascii: "m"); tcb[1123] = UInt8(ascii: "m")
        tcb[1214] = 0   // 2D
        out += tcb
        let layerLevel: [String: Int] = Dictionary(uniqueKeysWithValues: doc.layers.enumerated().map { ($0.element.name.lowercased(), $0.offset % 63 + 1) })
        func ui(_ v: Double) -> Int32 { Int32(max(Double(Int32.min + 1), min(Double(Int32.max - 1), (v * toUOR).rounded()))) }
        func header(_ type: Int, level: Int, words: Int, range: BBox2, color: Int, weight: Int) -> [UInt8] {
            var h: [UInt8] = [UInt8(level & 0x3F), UInt8(type & 0x7F)]
            putU16(words, &h)
            // Range: unsigned (sign bit flipped) low x, y, z then high x, y, z.
            for v in [ui(range.min.x), ui(range.min.y), 0, ui(range.max.x), ui(range.max.y), 0] { putInt32(Int32(bitPattern: UInt32(bitPattern: v) ^ 0x8000_0000), &h) }
            putU16(0, &h)                       // graphic group
            putU16(max(words - 14, 0), &h)      // words to attributes (none)
            putU16(0, &h)                       // properties
            h.append(UInt8((weight & 0x1F) << 3)); h.append(UInt8(max(0, min(255, color))))
            return h
        }
        func emit(_ type: Int, level: Int, body: [UInt8], range: BBox2, color: Int, weight: Int) {
            var bodyPadded = body
            if bodyPadded.count % 2 == 1 { bodyPadded.append(0) }
            let words = (36 + bodyPadded.count) / 2 - 2
            out += header(type, level: level, words: words, range: range, color: color, weight: weight) + bodyPadded
        }
        let visible = Set(doc.layers.filter { $0.visible && !$0.frozen }.map { $0.name.lowercased() })
        for e in doc.entities where visible.contains(e.layer.lowercased()) {
            let level = layerLevel[e.layer.lowercased()] ?? 1
            let color: Int = {
                switch e.color {
                case .aci(let i): return i
                case .rgb(let r, let g, let b): return DXFColors.nearest(RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255))
                default: return 0
                }
            }()
            let weight = e.lineweight.map { max(0, min(31, Int(($0 - 0.13) / 0.13 + 0.5))) } ?? 0
            let r = GeometryOps.bounds(e.geometry, doc: doc)
            func pts(_ p: [Vec2]) -> [UInt8] { var o = [UInt8](); for q in p { putInt32(ui(q.x), &o); putInt32(ui(q.y), &o) }; return o }
            switch e.geometry {
            case .line(let l): emit(3, level: level, body: pts([l.a, l.b]), range: r, color: color, weight: weight)
            case .polyline(let pl) where pl.vertices.allSatisfy({ abs($0.bulge) < 1e-12 }):
                var p = pl.vertices.map(\.p)
                if pl.closed, let f = p.first { p.append(f) }
                // At most 101 vertices per element: split longer runs (shapes stay closed only when they fit).
                if p.count <= 101 {
                    var body = [UInt8](); putU16(p.count, &body); body += pts(p)
                    emit(pl.closed && p.count >= 4 ? 6 : 4, level: level, body: body, range: r, color: color, weight: weight)
                } else {
                    var s = 0
                    while s < p.count - 1 {
                        let chunk = Array(p[s..<min(p.count, s + 101)])
                        var body = [UInt8](); putU16(chunk.count, &body); body += pts(chunk)
                        emit(4, level: level, body: body, range: BBox2(points: chunk), color: color, weight: weight)
                        s += 100
                    }
                }
            case .circle(let c):
                var body = [UInt8](); putVax(c.radius * toUOR, &body); putVax(c.radius * toUOR, &body); putInt32(0, &body)
                putVax(c.center.x * toUOR, &body); putVax(c.center.y * toUOR, &body)
                emit(15, level: level, body: body, range: r, color: color, weight: weight)
            case .ellipse(let el) where el.isFull:
                let a = el.majorAxis.length
                var body = [UInt8](); putVax(a * toUOR, &body); putVax(a * el.ratio * toUOR, &body); putInt32(Int32((el.majorAxis.angle * 180 / .pi * 360000).rounded()), &body)
                putVax(el.center.x * toUOR, &body); putVax(el.center.y * toUOR, &body)
                emit(15, level: level, body: body, range: r, color: color, weight: weight)
            case .arc(let a):
                var body = [UInt8]()
                putInt32(Int32((a.start * 180 / .pi * 360000).rounded()), &body)
                putInt32(Int32((a.sweep * 180 / .pi * 360000).rounded()), &body)
                putVax(a.radius * toUOR, &body); putVax(a.radius * toUOR, &body); putInt32(0, &body)
                putVax(a.center.x * toUOR, &body); putVax(a.center.y * toUOR, &body)
                emit(16, level: level, body: body, range: r, color: color, weight: weight)
            case .text(let t):
                let chars = Array(t.content.replacingOccurrences(of: "\n", with: " ").unicodeScalars.map { $0.value < 256 ? UInt8($0.value) : UInt8(ascii: "?") }.prefix(255))
                var body: [UInt8] = [0, 2]   // font 0, justification left-baseline
                let mult = Int32((t.height * toUOR * 1000 / 6).rounded())
                putInt32(mult, &body); putInt32(mult, &body)
                putInt32(Int32((t.rotation * 180 / .pi * 360000).rounded()), &body)
                putInt32(ui(t.position.x), &body); putInt32(ui(t.position.y), &body)
                body.append(UInt8(chars.count)); body.append(0)
                body += chars
                emit(17, level: level, body: body, range: r, color: color, weight: weight)
            case .polyline, .ellipse, .spline:
                for p in GeometryOps.tessellate(e.geometry, doc: doc) where p.count >= 2 {
                    var s = 0
                    while s < p.count - 1 {
                        let chunk = Array(p[s..<min(p.count, s + 101)])
                        var body = [UInt8](); putU16(chunk.count, &body); body += pts(chunk)
                        emit(4, level: level, body: body, range: BBox2(points: chunk), color: color, weight: weight)
                        s += 100
                    }
                }
            default: continue
            }
        }
        out += [0xFF, 0xFF]
        return Data(out)
    }
}

extension DGN {
    static var commands: [CommandDef] { [
        CommandDef("DGNIMPORT", aliases: ["DGNIN", "IMPORTDGN"], category: "Insert",
                   summary: "Imports a MicroStation V7 .dgn file (lines, line strings, shapes, curves, circles, ellipses, arcs, text; levels become layers).") { ed in
            let url = try await IOCommands.path(ed, "Enter DGN file name")
            try IOCommands.runImport(ed, url, format: "dgn")
        },
        CommandDef("DGNEXPORT", aliases: ["DGNOUT", "EXPORTDGN"], category: "File",
                   summary: "Exports the drawing's 2D objects as a MicroStation V7 .dgn file (one level per layer, master units m, resolution 0.1 mm).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter DGN file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("dgn") }
            let data = write(ed.doc)
            try IOCommands.write(ed, url, "DGN", { try data.write(to: url, options: .atomic) })
        },
    ] }
}
