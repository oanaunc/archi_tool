// Oanarina Archi Tool — GPL-3.0-or-later
// Raster image import: pixel size from the file header (PNG, JPEG, GIF, BMP, TIFF, WebP, HEIC/AVIF), georeferencing from ESRI
// world files (.pgw/.jgw/.tfw/.gfw/.bpw/.wld), and rescaling an image so that two picked points are a known distance
// apart (calibrating a scanned plan).
import Foundation

public enum ImageHeader {
    /// Pixel width and height, or nil when the format is not recognised.
    public static func size(_ d: Data) -> (width: Int, height: Int)? {
        let b = [UInt8](d.prefix(512 * 1024))
        func be16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) << 8 | Int(b[i + 1]) : 0 }
        func be32(_ i: Int) -> Int { i + 3 < b.count ? Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) : 0 }
        func le16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
        func le32(_ i: Int) -> Int { i + 3 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 : 0 }
        guard b.count >= 24 else { return nil }
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return (be32(16), be32(20)) }                  // PNG IHDR
        if b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 { return (le16(6), le16(8)) }                                      // GIF
        if b[0] == 0x42 && b[1] == 0x4D { return (le32(18), abs(Int(Int32(truncatingIfNeeded: le32(22))))) }             // BMP
        if b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b.count > 30 && b[8] == 0x57 && b[9] == 0x45 {    // WebP
            let chunk = String(bytes: b[12..<16], encoding: .ascii) ?? ""
            if chunk == "VP8 " { return (le16(26) & 0x3FFF, le16(28) & 0x3FFF) }
            if chunk == "VP8L" { let v = le32(21); return ((v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1) }
            if chunk == "VP8X" { return ((Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16) + 1, (Int(b[27]) | Int(b[28]) << 8 | Int(b[29]) << 16) + 1) }
        }
        if String(bytes: b[4..<8], encoding: .ascii) == "ftyp" {                                                              // HEIC/HEIF/AVIF: 'ispe' box
            var i = 8
            while i + 16 <= b.count {
                if b[i] == 0x69 && b[i + 1] == 0x73 && b[i + 2] == 0x70 && b[i + 3] == 0x65 { return (be32(i + 8), be32(i + 12)) }
                i += 1
            }
            return nil
        }
        if b[0] == 0xFF && b[1] == 0xD8 {                                                                                   // JPEG: find SOFn
            var i = 2
            while i + 9 < b.count {
                guard b[i] == 0xFF else { i += 1; continue }
                let m = b[i + 1]
                if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) { i += 2; continue }
                if m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC { return (be16(i + 7), be16(i + 5)) }
                i += 2 + be16(i + 2)
            }
            return nil
        }
        if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 42) || (b[0] == 0x4D && b[1] == 0x4D && b[3] == 42) {                    // TIFF
            let le = b[0] == 0x49
            func u16(_ i: Int) -> Int { le ? le16(i) : be16(i) }
            func u32(_ i: Int) -> Int { le ? le32(i) : be32(i) }
            let ifd = u32(4)
            guard ifd + 2 < b.count else { return nil }
            var w = 0, h = 0
            for k in 0..<u16(ifd) {
                let e = ifd + 2 + k * 12
                guard e + 12 <= b.count else { break }
                let tag = u16(e), type = u16(e + 2)
                let v = type == 3 ? u16(e + 8) : u32(e + 8)
                if tag == 256 { w = v } else if tag == 257 { h = v }
            }
            return w > 0 && h > 0 ? (w, h) : nil
        }
        return nil
    }
}

/// ESRI world file: x = A·col + B·row + C, y = D·col + E·row + F (C, F = centre of the upper-left pixel).
public struct WorldFile: Hashable {
    public var a, d, b, e, c, f: Double

    public static func parse(_ text: String) -> WorldFile? {
        let v = text.split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "\t" }).compactMap { Double($0) }
        guard v.count >= 6, v[0] != 0 || v[2] != 0 else { return nil }
        return WorldFile(a: v[0], d: v[1], b: v[2], e: v[3], c: v[4], f: v[5])
    }

    /// Sidecar world file names for an image (e.g. plan.png → plan.pgw, plan.pngw, plan.wld).
    public static func candidates(for image: URL) -> [URL] {
        let ext = image.pathExtension.lowercased()
        let base = image.deletingPathExtension()
        var exts: [String] = []
        if ext.count >= 3 { exts.append(String(ext.first!) + String(ext.last!) + "w") }
        exts += [ext + "w", "wld"]
        if ext == "jpeg" { exts.append("jgw") }
        if ext == "tiff" { exts.append("tfw") }
        return exts.map { base.appendingPathExtension($0) }
    }

    /// Image placement in world units for a width × height pixel image.
    public func placement(width: Int, height: Int) -> (origin: Vec2, size: Vec2, rotation: Double) {
        let w = Double(width), h = Double(height)
        func world(_ col: Double, _ row: Double) -> Vec2 { Vec2(a * col + b * row + c, d * col + e * row + f) }
        let lowerLeft = world(-0.5, h - 0.5)
        let lowerRight = world(w - 0.5, h - 0.5)
        let upperLeft = world(-0.5, -0.5)
        return (lowerLeft, Vec2(lowerLeft.distance(to: lowerRight), lowerLeft.distance(to: upperLeft)), atan2(lowerRight.y - lowerLeft.y, lowerRight.x - lowerLeft.x))
    }
}

public enum ImagePlacement {
    /// Georeferenced image: world file placement converted from world units (metres by default) to drawing units,
    /// relative to `worldOrigin` (a local origin in world units, e.g. from the GEOORIGIN variable).
    public static func georeferenced(path: String, pixels: (width: Int, height: Int), world: WorldFile, unitMM: Double,
                                     worldUnitMM: Double = 1000, worldOrigin: Vec2 = .zero) -> ImageGeom {
        let p = world.placement(width: pixels.width, height: pixels.height)
        let k = worldUnitMM / unitMM
        return ImageGeom(path: path, origin: (p.origin - worldOrigin) * k, size: p.size * k, rotation: normAngle(p.rotation) < 1e-12 ? 0 : normAngle(p.rotation))
    }

    /// Image of `width` drawing units at `origin`, height from the pixel aspect ratio.
    public static func placed(path: String, pixels: (width: Int, height: Int)?, origin: Vec2, width: Double, rotation: Double = 0) -> ImageGeom {
        let aspect = pixels.map { $0.width > 0 ? Double($0.height) / Double($0.width) : 0.75 } ?? 0.75
        return ImageGeom(path: path, origin: origin, size: Vec2(width, width * aspect), rotation: rotation)
    }

    /// Scales an image about `p1` so that the points `p1` and `p2` (on the image) end up `distance` apart.
    public static func scaled(_ im: ImageGeom, p1: Vec2, p2: Vec2, distance: Double) -> ImageGeom? {
        let cur = p1.distance(to: p2)
        guard cur > 1e-12, distance > 0, distance.isFinite else { return nil }
        let k = distance / cur
        var out = im
        out.origin = p1 + (im.origin - p1) * k
        out.size = im.size * k
        return out
    }

    /// Reads an image file (and its world file when present) into an image entity.
    public static func load(_ url: URL, doc: ArchiDocument, origin: Vec2 = .zero, width: Double? = nil, useWorldFile: Bool = true) throws -> (ImageGeom, georeferenced: Bool) {
        let data = try Data(contentsOf: url)
        guard let px = ImageHeader.size(data) else { throw GISImportError.invalid("\(url.lastPathComponent) is not a PNG, JPEG, GIF, BMP, TIFF or WebP image") }
        if useWorldFile {
            for wf in WorldFile.candidates(for: url) where FileManager.default.fileExists(atPath: wf.path) {
                if let text = try? String(contentsOf: wf, encoding: .utf8), let w = WorldFile.parse(text) {
                    let o = doc.variable("GEOORIGIN").map { $0.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } } ?? []
                    let unit = doc.variable("WORLDUNITMM").flatMap(Double.init) ?? 1000
                    return (georeferenced(path: url.path, pixels: px, world: w, unitMM: doc.units.mm, worldUnitMM: unit, worldOrigin: o.count >= 2 ? Vec2(o[0], o[1]) : .zero), true)
                }
            }
        }
        return (placed(path: url.path, pixels: px, origin: origin, width: width ?? Double(px.width) * 10 / doc.units.mm), false)
    }
}
