// Oanarina Archi Tool — GPL-3.0-or-later
// Raw DEFLATE (RFC 1951, no zlib header) for ZIP, PNG, PDF, FBX and Rhino streams.
// Apple platforms use Foundation's built-in codec; elsewhere (Windows, Linux) the portable Swift codec below.
import Foundation

public enum RawDeflate {
    public struct Corrupt: Error, CustomStringConvertible { public let reason: String; public var description: String { "Corrupt DEFLATE stream: \(reason)" } }

    /// Compresses to a raw DEFLATE stream.
    public static func compress(_ data: Data) -> Data {
        #if canImport(Darwin)
        if let c = try? (data as NSData).compressed(using: .zlib) as Data { return c }
        #endif
        return deflatePortable(data)
    }

    /// Decompresses a raw DEFLATE stream; bytes after the final block are ignored.
    public static func decompress(_ data: Data) throws -> Data {
        #if canImport(Darwin)
        if let d = try? (data as NSData).decompressed(using: .zlib) as Data { return d }
        #endif
        return try inflatePortable(data)
    }

    // MARK: - Inflate

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int]
        init(lengths: [Int]) {
            symbols = [Int](repeating: 0, count: lengths.count)
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offs = [Int](repeating: 0, count: 16)
            for i in 1..<16 { offs[i] = offs[i - 1] + counts[i - 1] }
            for (s, l) in lengths.enumerated() where l != 0 { symbols[offs[l]] = s; offs[l] += 1 }
        }
    }

    private struct BitReader {
        let bytes: [UInt8]; var pos = 0; var bitBuf = 0; var bitCount = 0
        init(_ b: [UInt8]) { bytes = b }
        mutating func bits(_ n: Int) throws -> Int {
            var v = bitBuf
            while bitCount < n {
                guard pos < bytes.count else { throw Corrupt(reason: "unexpected end of data") }
                v |= Int(bytes[pos]) << bitCount; pos += 1; bitCount += 8
            }
            bitBuf = v >> n; bitCount -= n
            return v & ((1 << n) - 1)
        }
        mutating func alignToByte() { bitBuf = 0; bitCount = 0 }
        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                code |= try bits(1)
                let count = h.counts[len]
                if code - count < first { return h.symbols[index + (code - first)] }
                index += count; first += count; first <<= 1; code <<= 1
            }
            throw Corrupt(reason: "bad Huffman code")
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let fixedLit: Huffman = {
        var l = [Int](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }; for i in 256..<280 { l[i] = 7 }
        return Huffman(lengths: l)
    }()
    private static let fixedDist = Huffman(lengths: [Int](repeating: 5, count: 30))

    public static func inflatePortable(_ data: Data) throws -> Data {
        var r = BitReader([UInt8](data))
        var out = [UInt8](); out.reserveCapacity(data.count * 3)
        var last = 0
        repeat {
            last = try r.bits(1)
            switch try r.bits(2) {
            case 0:
                r.alignToByte()
                guard r.pos + 4 <= r.bytes.count else { throw Corrupt(reason: "short stored block") }
                let len = Int(r.bytes[r.pos]) | Int(r.bytes[r.pos + 1]) << 8
                let nlen = Int(r.bytes[r.pos + 2]) | Int(r.bytes[r.pos + 3]) << 8
                guard len == (~nlen & 0xFFFF) else { throw Corrupt(reason: "stored length check") }
                r.pos += 4
                guard r.pos + len <= r.bytes.count else { throw Corrupt(reason: "stored block past end") }
                out.append(contentsOf: r.bytes[r.pos..<(r.pos + len)]); r.pos += len
            case 1:
                try codes(&r, &out, fixedLit, fixedDist)
            case 2:
                let nlen = try r.bits(5) + 257, ndist = try r.bits(5) + 1, ncode = try r.bits(4) + 4
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var cl = [Int](repeating: 0, count: 19)
                for i in 0..<ncode { cl[order[i]] = try r.bits(3) }
                let clh = Huffman(lengths: cl)
                var lengths = [Int](); lengths.reserveCapacity(nlen + ndist)
                while lengths.count < nlen + ndist {
                    let sym = try r.decode(clh)
                    switch sym {
                    case 0..<16: lengths.append(sym)
                    case 16:
                        guard let prev = lengths.last else { throw Corrupt(reason: "repeat with no previous length") }
                        lengths += [Int](repeating: prev, count: 3 + (try r.bits(2)))
                    case 17: lengths += [Int](repeating: 0, count: 3 + (try r.bits(3)))
                    default: lengths += [Int](repeating: 0, count: 11 + (try r.bits(7)))
                    }
                }
                guard lengths.count == nlen + ndist else { throw Corrupt(reason: "too many lengths") }
                try codes(&r, &out, Huffman(lengths: Array(lengths[0..<nlen])), Huffman(lengths: Array(lengths[nlen...])))
            default:
                throw Corrupt(reason: "invalid block type")
            }
        } while last == 0
        return Data(out)
    }

    private static func codes(_ r: inout BitReader, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman) throws {
        while true {
            let sym = try r.decode(lit)
            if sym < 256 { out.append(UInt8(sym)); continue }
            if sym == 256 { return }
            let li = sym - 257
            guard li < 29 else { throw Corrupt(reason: "bad length symbol") }
            let len = lengthBase[li] + (try r.bits(lengthExtra[li]))
            let di = try r.decode(dist)
            guard di < 30 else { throw Corrupt(reason: "bad distance symbol") }
            let d = distBase[di] + (try r.bits(distExtra[di]))
            guard d <= out.count else { throw Corrupt(reason: "distance too far back") }
            let start = out.count - d
            for k in 0..<len { out.append(out[start + k]) }
        }
    }

    // MARK: - Deflate (LZ77 with hash chains, fixed Huffman codes)

    private struct BitWriter {
        var out = [UInt8](); var acc = 0; var n = 0
        mutating func put(_ v: Int, _ bits: Int) {        // LSB first
            acc |= v << n; n += bits
            while n >= 8 { out.append(UInt8(acc & 0xFF)); acc >>= 8; n -= 8 }
        }
        mutating func putReversed(_ code: Int, _ bits: Int) {   // Huffman codes go MSB first
            var r = 0, c = code
            for _ in 0..<bits { r = (r << 1) | (c & 1); c >>= 1 }
            put(r, bits)
        }
        mutating func flush() { if n > 0 { out.append(UInt8(acc & 0xFF)); acc = 0; n = 0 } }
    }

    private static func putLiteral(_ w: inout BitWriter, _ s: Int) {
        switch s {
        case 0..<144: w.putReversed(0x30 + s, 8)
        case 144..<256: w.putReversed(0x190 + (s - 144), 9)
        case 256..<280: w.putReversed(s - 256, 7)
        default: w.putReversed(0xC0 + (s - 280), 8)
        }
    }

    public static func deflatePortable(_ data: Data) -> Data {
        let src = [UInt8](data), n = src.count
        var w = BitWriter(); w.out.reserveCapacity(n / 2 + 16)
        w.put(1, 1); w.put(1, 2)                            // one final block, fixed Huffman
        let hashBits = 15, hashSize = 1 << hashBits, window = 32768, maxChain = 64
        var head = [Int](repeating: -1, count: hashSize)
        var prev = [Int](repeating: -1, count: window)
        func hash(_ i: Int) -> Int { ((Int(src[i]) << 10) ^ (Int(src[i + 1]) << 5) ^ Int(src[i + 2])) & (hashSize - 1) }
        func insert(_ i: Int) { guard i + 2 < n else { return }; let h = hash(i); prev[i & (window - 1)] = head[h]; head[h] = i }
        var i = 0
        while i < n {
            var bestLen = 0, bestDist = 0
            if i + 2 < n {
                var cand = head[hash(i)], chain = 0
                let maxLen = min(258, n - i)
                while cand >= 0 && i - cand <= window - 1 && chain < maxChain {
                    if src[cand + bestLen] == src[i + bestLen] || bestLen == 0 {
                        var l = 0
                        while l < maxLen && src[cand + l] == src[i + l] { l += 1 }
                        if l > bestLen { bestLen = l; bestDist = i - cand; if l == maxLen { break } }
                    }
                    cand = prev[cand & (window - 1)]; chain += 1
                }
            }
            if bestLen >= 3 {
                var li = 28
                while lengthBase[li] > bestLen { li -= 1 }
                putLiteral(&w, 257 + li); w.put(bestLen - lengthBase[li], lengthExtra[li])
                var di = 29
                while distBase[di] > bestDist { di -= 1 }
                w.putReversed(di, 5); w.put(bestDist - distBase[di], distExtra[di])
                for k in 0..<bestLen { insert(i + k) }
                i += bestLen
            } else {
                putLiteral(&w, Int(src[i])); insert(i); i += 1
            }
        }
        putLiteral(&w, 256)
        w.flush()
        return Data(w.out)
    }
}
