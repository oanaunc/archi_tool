// Oanarina Archi Tool — GPL-3.0-or-later
// Minimal raster decoding for image analysis in the core (no Core Graphics): PNG (all colour types, bit depths 1–16,
// non-interlaced and Adam7), BMP (1/4/8/24/32-bit, uncompressed) and Netpbm (PGM/PPM, ASCII and binary), converted
// to 8-bit luminance. PNG writing (grayscale) for tests and exports.
import Foundation

public struct RasterImage: Hashable {
    public var width: Int
    public var height: Int
    /// Row-major luminance, top row first (0 = black, 255 = white).
    public var gray: [UInt8]

    public init(width: Int, height: Int, gray: [UInt8]) { self.width = width; self.height = height; self.gray = gray }

    public struct DecodeError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    public subscript(x: Int, y: Int) -> UInt8 { gray[y * width + x] }

    static func luma(_ r: Int, _ g: Int, _ b: Int) -> UInt8 { UInt8(max(0, min(255, (299 * r + 587 * g + 114 * b + 500) / 1000))) }

    /// Decodes PNG, BMP or PGM/PPM data.
    public static func decode(_ data: Data) throws -> RasterImage {
        let b = [UInt8](data)
        if b.count > 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return try png(b) }
        if b.count > 54, b[0] == 0x42, b[1] == 0x4D { return try bmp(b) }
        if b.count > 2, b[0] == 0x50, [0x32, 0x33, 0x35, 0x36].contains(b[1]) { return try pnm(b) }
        throw DecodeError(message: "Unsupported image format (use PNG, BMP, PGM or PPM).")
    }

    // MARK: PNG

    static func inflateZlib(_ d: [UInt8]) throws -> [UInt8] {
        guard d.count > 6 else { throw DecodeError(message: "PNG: empty image data") }
        guard let out = try? RawDeflate.decompress(Data(d[2..<(d.count - 4)])) else {
            if let out2 = try? RawDeflate.decompress(Data(d[2...])) { return [UInt8](out2) }
            throw DecodeError(message: "PNG: corrupt image data")
        }
        return [UInt8](out)
    }

    static func png(_ b: [UInt8]) throws -> RasterImage {
        func be32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
        var i = 8
        var w = 0, h = 0, depth = 8, ctype = 0, interlace = 0
        var idat: [UInt8] = [], palette: [(Int, Int, Int)] = []
        while i + 8 <= b.count {
            let len = be32(i), type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let s = i + 8
            guard s + len <= b.count else { break }
            switch type {
            case "IHDR": w = be32(s); h = be32(s + 4); depth = Int(b[s + 8]); ctype = Int(b[s + 9]); interlace = Int(b[s + 12])
            case "PLTE": palette = stride(from: s, to: s + len - 2, by: 3).map { (Int(b[$0]), Int(b[$0 + 1]), Int(b[$0 + 2])) }
            case "IDAT": idat += b[s..<(s + len)]
            default: break
            }
            if type == "IEND" { break }
            i = s + len + 4
        }
        guard w > 0, h > 0, w * h <= 200_000_000 else { throw DecodeError(message: "PNG: invalid size") }
        let channels = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][ctype] ?? 1
        let bpp = max(1, channels * depth / 8)
        let raw = try inflateZlib(idat)
        var out = [UInt8](repeating: 255, count: w * h)
        var pos = 0
        func sample(_ row: [UInt8], _ x: Int, _ c: Int) -> Int {
            if depth == 8 { return Int(row[x * channels + c]) }
            if depth == 16 { return Int(row[(x * channels + c) * 2]) }
            let per = 8 / depth, byte = row[(x * channels + c) / per], shift = 8 - depth * ((x * channels + c) % per + 1)
            return Int((byte >> UInt8(shift)) & UInt8((1 << depth) - 1))
        }
        func maxv() -> Int { depth == 16 ? 255 : (1 << min(depth, 8)) - 1 }
        func pass(_ x0: Int, _ y0: Int, _ dx: Int, _ dy: Int) throws {
            let pw = (w - x0 + dx - 1) / dx, ph = (h - y0 + dy - 1) / dy
            guard pw > 0, ph > 0 else { return }
            let stride = (pw * channels * depth + 7) / 8
            var prev = [UInt8](repeating: 0, count: stride)
            for py in 0..<ph {
                guard pos + 1 + stride <= raw.count else { throw DecodeError(message: "PNG: truncated image data") }
                let f = raw[pos]; var row = Array(raw[(pos + 1)..<(pos + 1 + stride)]); pos += 1 + stride
                for k in 0..<stride {
                    let a = k >= bpp ? Int(row[k - bpp]) : 0, up = Int(prev[k]), c = k >= bpp ? Int(prev[k - bpp]) : 0
                    let v: Int
                    switch f {
                    case 1: v = a
                    case 2: v = up
                    case 3: v = (a + up) / 2
                    case 4:
                        let p = a + up - c, pa = abs(p - a), pb = abs(p - up), pc = abs(p - c)
                        v = pa <= pb && pa <= pc ? a : pb <= pc ? up : c
                    default: v = 0
                    }
                    row[k] = UInt8((Int(row[k]) + v) & 0xFF)
                }
                prev = row
                let m = maxv()
                for px in 0..<pw {
                    let x = x0 + px * dx, y = y0 + py * dy
                    var g: Int, alpha = 255
                    switch ctype {
                    case 2, 6:
                        g = Int(luma(sample(row, px, 0) * 255 / m, sample(row, px, 1) * 255 / m, sample(row, px, 2) * 255 / m))
                        if ctype == 6 { alpha = sample(row, px, 3) * 255 / m }
                    case 3:
                        let idx = sample(row, px, 0)
                        g = idx < palette.count ? Int(luma(palette[idx].0, palette[idx].1, palette[idx].2)) : 0
                    case 4: g = sample(row, px, 0) * 255 / m; alpha = sample(row, px, 1) * 255 / m
                    default: g = sample(row, px, 0) * 255 / m
                    }
                    // Composite on white.
                    out[y * w + x] = UInt8((g * alpha + 255 * (255 - alpha)) / 255)
                }
            }
        }
        if interlace == 1 {
            for (x0, y0, dx, dy) in [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)] { try pass(x0, y0, dx, dy) }
        } else { try pass(0, 0, 1, 1) }
        return RasterImage(width: w, height: h, gray: out)
    }

    // MARK: BMP

    static func bmp(_ b: [UInt8]) throws -> RasterImage {
        func le32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func le16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        let off = le32(10), hs = le32(14), w = le32(18)
        let hRaw = Int(Int32(truncatingIfNeeded: le32(22)))
        let bits = le16(28), comp = le32(30)
        guard w > 0, hRaw != 0, [1, 4, 8, 24, 32].contains(bits), comp == 0 || comp == 3 else { throw DecodeError(message: "BMP: unsupported variant") }
        let h = abs(hRaw)
        var pal: [(Int, Int, Int)] = []
        if bits <= 8 {
            let n = le32(46) == 0 ? 1 << bits : le32(46)
            for k in 0..<n { let p = 14 + hs + 4 * k; if p + 2 < b.count { pal.append((Int(b[p + 2]), Int(b[p + 1]), Int(b[p]))) } }
        }
        let stride = ((w * bits + 31) / 32) * 4
        guard off + stride * h <= b.count else { throw DecodeError(message: "BMP: truncated") }
        var out = [UInt8](repeating: 255, count: w * h)
        for r in 0..<h {
            let y = hRaw > 0 ? h - 1 - r : r
            let base = off + r * stride
            for x in 0..<w {
                let g: UInt8
                switch bits {
                case 24, 32: let p = base + x * bits / 8; g = luma(Int(b[p + 2]), Int(b[p + 1]), Int(b[p]))
                default:
                    let bitIndex = x * bits, byte = b[base + bitIndex / 8], shift = 8 - bits - bitIndex % 8
                    let idx = Int((byte >> UInt8(shift)) & UInt8((1 << bits) - 1))
                    g = idx < pal.count ? luma(pal[idx].0, pal[idx].1, pal[idx].2) : 0
                }
                out[y * w + x] = g
            }
        }
        return RasterImage(width: w, height: h, gray: out)
    }

    // MARK: Netpbm

    static func pnm(_ b: [UInt8]) throws -> RasterImage {
        let kind = b[1]
        var i = 2
        func token() -> Int? {
            while i < b.count {
                if b[i] == 0x23 { while i < b.count && b[i] != 0x0A { i += 1 } }
                else if b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 } else { break }
            }
            var v = 0, any = false
            while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { v = v * 10 + Int(b[i] - 0x30); i += 1; any = true }
            return any ? v : nil
        }
        guard let w = token(), let h = token(), let mx = token(), w > 0, h > 0, mx > 0 else { throw DecodeError(message: "PNM: bad header") }
        let color = kind == 0x33 || kind == 0x36, binary = kind == 0x35 || kind == 0x36
        var out = [UInt8](repeating: 255, count: w * h)
        if binary { i += 1 }
        let bytes = mx > 255 ? 2 : 1
        func next() -> Int {
            if binary { guard i + bytes <= b.count else { return 0 }; let v = bytes == 2 ? Int(b[i]) << 8 | Int(b[i + 1]) : Int(b[i]); i += bytes; return v }
            return token() ?? 0
        }
        for k in 0..<(w * h) {
            if color { let r = next() * 255 / mx, g = next() * 255 / mx, bl = next() * 255 / mx; out[k] = luma(r, g, bl) }
            else { out[k] = UInt8(min(255, next() * 255 / mx)) }
        }
        return RasterImage(width: w, height: h, gray: out)
    }

    // MARK: PNG writing

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n); for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c
    }
    static func crc(_ d: [UInt8]) -> UInt32 { var c: UInt32 = 0xFFFFFFFF; for x in d { c = crcTable[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) }; return c ^ 0xFFFFFFFF }

    /// 8-bit grayscale PNG.
    public func pngData() -> Data {
        var raw: [UInt8] = []; raw.reserveCapacity((width + 1) * height)
        for y in 0..<height { raw.append(0); raw += gray[(y * width)..<((y + 1) * width)] }
        var a: UInt32 = 1, bb: UInt32 = 0
        for x in raw { a = (a + UInt32(x)) % 65521; bb = (bb + a) % 65521 }
        let deflated = RawDeflate.compress(Data(raw))
        let z = [0x78, 0x9C] + [UInt8](deflated) + [UInt8(bb >> 8), UInt8(bb & 0xFF), UInt8(a >> 8), UInt8(a & 0xFF)]
        func be(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ t: String, _ d: [UInt8]) -> [UInt8] { let td = Array(t.utf8) + d; let c = RasterImage.crc(td); return be(d.count) + td + be(Int(c)) }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be(width) + be(height) + [8, 0, 0, 0, 0])
        out += chunk("IDAT", z)
        out += chunk("IEND", [])
        return Data(out)
    }
}
