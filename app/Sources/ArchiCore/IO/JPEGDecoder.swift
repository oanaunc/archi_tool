// Oanarina Archi Tool — GPL-3.0-or-later
// Baseline JPEG decoder (ITU T.81 sequential DCT, Huffman, 8-bit, 1 or 3 components, any sampling factors, restart
// intervals) without Core Graphics, so the portable path tracer (Windows / Linux archi-engine) can read material
// textures. Progressive and arithmetic-coded files are refused.
import Foundation

public struct JPEGImage {
    public var width: Int
    public var height: Int
    /// RGB bytes, rows top to bottom.
    public var rgb: [UInt8]
}

public enum JPEGDecoder {
    public struct DecodeError: Error, CustomStringConvertible { public let description: String }

    static let zigzag: [Int] = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
                                35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

    struct Huffman {
        var maxcode = [Int](repeating: -1, count: 18)
        var valptr = [Int](repeating: 0, count: 17)
        var mincode = [Int](repeating: 0, count: 17)
        var values: [UInt8] = []
        init() {}
        init(counts: [Int], values v: [UInt8]) {
            values = v
            var code = 0, k = 0
            for l in 1...16 {
                let n = counts[l - 1]
                if n > 0 {
                    valptr[l] = k
                    mincode[l] = code
                    code += n
                    k += n
                    maxcode[l] = code - 1
                } else { maxcode[l] = -1 }
                code <<= 1
            }
            maxcode[17] = Int.max
        }
    }

    struct Component {
        var id: Int, h: Int, v: Int, tq: Int
        var td = 0, ta = 0
        var pred = 0
        var plane: [UInt8] = []
        var stride = 0
    }

    struct BitReader {
        let data: [UInt8]
        var pos: Int
        var acc: UInt32 = 0
        var bits = 0
        var hitMarker = false
        init(_ d: [UInt8], _ p: Int) { data = d; pos = p }
        mutating func fill() {
            while bits <= 24 {
                var byte: UInt8 = 0
                if !hitMarker && pos < data.count {
                    let b = data[pos]
                    if b == 0xFF {
                        let n = pos + 1 < data.count ? data[pos + 1] : 0
                        if n == 0x00 { byte = 0xFF; pos += 2 } else { hitMarker = true }
                    } else { byte = b; pos += 1 }
                }
                acc |= UInt32(byte) << UInt32(24 - bits)
                bits += 8
            }
        }
        mutating func bit() -> Int {
            if bits == 0 { fill() }
            let b = Int(acc >> 31)
            acc <<= 1
            bits -= 1
            return b
        }
        mutating func receive(_ n: Int) -> Int {
            if n == 0 { return 0 }
            if bits < n { fill() }
            let v = Int(acc >> UInt32(32 - n))
            acc <<= UInt32(n)
            bits -= n
            return v
        }
        mutating func decode(_ h: Huffman) -> Int {
            var code = 0
            for l in 1...16 {
                code = (code << 1) | bit()
                if code <= h.maxcode[l] {
                    let i = h.valptr[l] + code - h.mincode[l]
                    return i < h.values.count ? Int(h.values[i]) : 0
                }
            }
            return 0
        }
        /// Skips to the next restart marker and resets the bit buffer.
        mutating func restart() {
            acc = 0; bits = 0; hitMarker = false
            while pos + 1 < data.count {
                if data[pos] == 0xFF && (0xD0...0xD7).contains(data[pos + 1]) { pos += 2; return }
                pos += 1
            }
        }
    }

    static func extend(_ v: Int, _ s: Int) -> Int { s == 0 ? 0 : (v < (1 << (s - 1)) ? v - (1 << s) + 1 : v) }

    /// Separable float IDCT of one block (natural order coefficients) into 8-bit samples.
    static func idct(_ blk: inout [Float], into out: inout [UInt8], at off: Int, stride: Int, cos table: [Float]) {
        var tmp = [Float](repeating: 0, count: 64)
        for y in 0..<8 {
            for x in 0..<8 {
                var s: Float = 0
                for u in 0..<8 { s += table[x * 8 + u] * blk[y * 8 + u] }
                tmp[y * 8 + x] = s
            }
        }
        for x in 0..<8 {
            for y in 0..<8 {
                var s: Float = 0
                for v in 0..<8 { s += table[y * 8 + v] * tmp[v * 8 + x] }
                let val = Int((s / 4 + 128).rounded())
                out[off + y * stride + x] = UInt8(max(0, min(255, val)))
            }
        }
    }

    public static func decode(_ d: Data) throws -> JPEGImage {
        let b = [UInt8](d)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { throw DecodeError(description: "Not a JPEG file") }
        var qt = [[Float]](repeating: [Float](repeating: 1, count: 64), count: 4)
        var dcTables = [Huffman](repeating: Huffman(), count: 4)
        var acTables = [Huffman](repeating: Huffman(), count: 4)
        var comps: [Component] = []
        var width = 0, height = 0, restartInterval = 0
        var i = 2
        var table = [Float](repeating: 0, count: 64)
        for x in 0..<8 {
            for u in 0..<8 {
                let cu: Float = u == 0 ? Float(1.0 / 2.0.squareRoot()) : 1
                table[x * 8 + u] = cu * Float(cos(Double(2 * x + 1) * Double(u) * Double.pi / 16))
            }
        }
        while i + 3 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xD8 || m == 0x01 || (0xD0...0xD7).contains(m) || m == 0xFF { i += m == 0xFF ? 1 : 2; continue }
            if m == 0xD9 { break }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            let seg = i + 4, end = i + 2 + len
            guard end <= b.count else { throw DecodeError(description: "Truncated JPEG") }
            switch m {
            case 0xDB:
                var p = seg
                while p < end {
                    let pq = Int(b[p] >> 4), tq = Int(b[p] & 15)
                    p += 1
                    var q = [Float](repeating: 1, count: 64)
                    for k in 0..<64 {
                        let v = pq == 0 ? Int(b[p + k]) : (Int(b[p + 2 * k]) << 8 | Int(b[p + 2 * k + 1]))
                        q[zigzag[k]] = Float(v)
                    }
                    p += pq == 0 ? 64 : 128
                    if tq < 4 { qt[tq] = q }
                }
            case 0xC0, 0xC1:
                height = Int(b[seg + 1]) << 8 | Int(b[seg + 2])
                width = Int(b[seg + 3]) << 8 | Int(b[seg + 4])
                let n = Int(b[seg + 5])
                comps = []
                for k in 0..<n {
                    let o = seg + 6 + k * 3
                    comps.append(Component(id: Int(b[o]), h: max(1, Int(b[o + 1] >> 4)), v: max(1, Int(b[o + 1] & 15)), tq: Int(b[o + 2] & 3)))
                }
            case 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF:
                throw DecodeError(description: "Only baseline JPEG is supported")
            case 0xC4:
                var p = seg
                while p < end {
                    let tc = Int(b[p] >> 4), th = Int(b[p] & 3)
                    var counts: [Int] = []
                    for k in 0..<16 { counts.append(Int(b[p + 1 + k])) }
                    let total = counts.reduce(0, +)
                    let vals = Array(b[(p + 17)..<min(p + 17 + total, b.count)])
                    if tc == 0 { dcTables[th] = Huffman(counts: counts, values: vals) } else { acTables[th] = Huffman(counts: counts, values: vals) }
                    p += 17 + total
                }
            case 0xDD:
                restartInterval = Int(b[seg]) << 8 | Int(b[seg + 1])
            case 0xDA:
                guard width > 0, height > 0, !comps.isEmpty else { throw DecodeError(description: "JPEG scan before frame header") }
                let ns = Int(b[seg])
                for k in 0..<ns {
                    let cid = Int(b[seg + 1 + k * 2]), t = b[seg + 2 + k * 2]
                    if let ci = comps.firstIndex(where: { $0.id == cid }) { comps[ci].td = Int(t >> 4) & 3; comps[ci].ta = Int(t & 15) & 3 }
                }
                let hmax = comps.map(\.h).max() ?? 1, vmax = comps.map(\.v).max() ?? 1
                let mcux = (width + 8 * hmax - 1) / (8 * hmax), mcuy = (height + 8 * vmax - 1) / (8 * vmax)
                for ci in comps.indices {
                    comps[ci].stride = mcux * comps[ci].h * 8
                    comps[ci].plane = [UInt8](repeating: 0, count: comps[ci].stride * mcuy * comps[ci].v * 8)
                    comps[ci].pred = 0
                }
                var r = BitReader(b, end)
                var blk = [Float](repeating: 0, count: 64)
                var count = 0
                for my in 0..<mcuy {
                    for mx in 0..<mcux {
                        if restartInterval > 0 && count > 0 && count % restartInterval == 0 {
                            r.restart()
                            for ci in comps.indices { comps[ci].pred = 0 }
                        }
                        count += 1
                        for ci in comps.indices {
                            let c = comps[ci]
                            let q = qt[c.tq]
                            for by in 0..<c.v {
                                for bx in 0..<c.h {
                                    for k in 0..<64 { blk[k] = 0 }
                                    let s = r.decode(dcTables[c.td])
                                    let diff = extend(r.receive(s), s)
                                    comps[ci].pred += diff
                                    blk[0] = Float(comps[ci].pred) * q[0]
                                    var k = 1
                                    while k < 64 {
                                        let rs = r.decode(acTables[c.ta])
                                        let run = rs >> 4, sz = rs & 15
                                        if sz == 0 {
                                            if run == 15 { k += 16; continue }
                                            break
                                        }
                                        k += run
                                        if k > 63 { break }
                                        let z = zigzag[k]
                                        blk[z] = Float(extend(r.receive(sz), sz)) * q[z]
                                        k += 1
                                    }
                                    let x0 = (mx * c.h + bx) * 8, y0 = (my * c.v + by) * 8
                                    idct(&blk, into: &comps[ci].plane, at: y0 * c.stride + x0, stride: c.stride, cos: table)
                                }
                            }
                        }
                    }
                }
                return convert(comps, width: width, height: height, hmax: hmax, vmax: vmax)
            default: break
            }
            i = end
        }
        throw DecodeError(description: "JPEG without image data")
    }

    static func convert(_ comps: [Component], width w: Int, height h: Int, hmax: Int, vmax: Int) -> JPEGImage {
        var out = [UInt8](repeating: 0, count: w * h * 3)
        func sample(_ c: Component, _ x: Int, _ y: Int) -> Float {
            let sx = x * c.h / hmax, sy = y * c.v / vmax
            return Float(c.plane[sy * c.stride + sx])
        }
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 3
                if comps.count >= 3 {
                    let yy = sample(comps[0], x, y), cb = sample(comps[1], x, y) - 128, cr = sample(comps[2], x, y) - 128
                    let r = yy + 1.402 * cr
                    let g = yy - 0.344136 * cb - 0.714136 * cr
                    let bl = yy + 1.772 * cb
                    out[o] = UInt8(max(0, min(255, r.rounded())))
                    out[o + 1] = UInt8(max(0, min(255, g.rounded())))
                    out[o + 2] = UInt8(max(0, min(255, bl.rounded())))
                } else {
                    let v = UInt8(max(0, min(255, sample(comps[0], x, y))))
                    out[o] = v; out[o + 1] = v; out[o + 2] = v
                }
            }
        }
        return JPEGImage(width: w, height: h, rgb: out)
    }
}
