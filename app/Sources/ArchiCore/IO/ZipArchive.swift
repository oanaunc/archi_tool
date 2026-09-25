// Oanarina Archi Tool — GPL-3.0-or-later
// Minimal ZIP (PKWARE APPNOTE 6.3) writer/reader for package formats (3MF, USDZ).
import Foundation

public enum ZipArchive {
    public struct Entry { public var name: String; public var data: Data
        public init(name: String, data: Data) { self.name = name; self.data = data } }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    public static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    /// Writes an archive. `compress` deflates entries (Foundation zlib = raw DEFLATE) when it saves space;
    /// `align` pads so each stored entry's data starts at a multiple of `align` bytes (USDZ needs 64).
    public static func write(_ entries: [Entry], compress: Bool = false, align: Int = 0) -> Data {
        var out = Data()
        var central = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: UInt32, _ d: inout Data) { for k in 0..<4 { d.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }
        let dosTime = 0, dosDate = (2024 - 1980) << 9 | 1 << 5 | 1
        for e in entries {
            let name = Data(e.name.utf8)
            let crc = crc32(e.data)
            var payload = e.data
            var method = 0
            if compress, !e.data.isEmpty, let c = try? (e.data as NSData).compressed(using: .zlib) as Data, c.count < e.data.count {
                payload = c; method = 8
            }
            let offset = out.count
            var extra = Data()
            if align > 1 && method == 0 {
                let dataStart = offset + 30 + name.count
                var pad = (align - dataStart % align) % align
                if pad > 0 && pad < 4 { pad += align }
                if pad >= 4 { u16(0x1986, &extra); u16(pad - 4, &extra); extra.append(Data(count: pad - 4)) }
            }
            var h = Data()
            u32(0x04034b50, &h); u16(20, &h); u16(0x0800, &h); u16(method, &h); u16(dosTime, &h); u16(dosDate, &h)
            u32(crc, &h); u32(UInt32(payload.count), &h); u32(UInt32(e.data.count), &h); u16(name.count, &h); u16(extra.count, &h)
            out.append(h); out.append(name); out.append(extra); out.append(payload)
            var c = Data()
            u32(0x02014b50, &c); u16(20, &c); u16(20, &c); u16(0x0800, &c); u16(method, &c); u16(dosTime, &c); u16(dosDate, &c)
            u32(crc, &c); u32(UInt32(payload.count), &c); u32(UInt32(e.data.count), &c); u16(name.count, &c); u16(0, &c); u16(0, &c)
            u16(0, &c); u16(0, &c); u32(0, &c); u32(UInt32(offset), &c)
            c.append(name)
            central.append(c)
        }
        let cdOffset = out.count
        out.append(central)
        var end = Data()
        u32(0x06054b50, &end); u16(0, &end); u16(0, &end); u16(entries.count, &end); u16(entries.count, &end)
        u32(UInt32(central.count), &end); u32(UInt32(cdOffset), &end); u16(0, &end)
        out.append(end)
        return out
    }

    public enum ZipError: Error, LocalizedError {
        case notZip, unsupported(String), corrupt(String)
        public var errorDescription: String? {
            switch self {
            case .notZip: return "The file is not a ZIP package."
            case .unsupported(let s): return "Unsupported ZIP feature: \(s)"
            case .corrupt(let s): return "Corrupt ZIP entry \(s)"
            }
        }
    }

    /// Reads all entries (stored or deflated) using the central directory.
    public static func read(_ data: Data) throws -> [Entry] {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0 }
        guard b.count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65557) { if u32(i) == 0x06054b50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [Entry] = []
        for _ in 0..<count {
            guard u32(p) == 0x02014b50 else { throw ZipError.corrupt("central directory") }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nlen <= b.count else { throw ZipError.corrupt("name") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen
            guard u32(local) == 0x04034b50 else { throw ZipError.corrupt(name) }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { throw ZipError.corrupt(name) }
            let raw = Data(b[start..<(start + csize)])
            switch method {
            case 0: out.append(Entry(name: name, data: raw))
            case 8:
                guard let d = try? (raw as NSData).decompressed(using: .zlib) as Data else { throw ZipError.corrupt(name) }
                if usize > 0 && d.count != usize { throw ZipError.corrupt(name) }
                out.append(Entry(name: name, data: d))
            default: throw ZipError.unsupported("compression method \(method)")
            }
        }
        return out
    }
}
