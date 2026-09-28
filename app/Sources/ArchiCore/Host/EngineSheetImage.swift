// Oanarina Archi Tool — GPL-3.0-or-later
// SHEETIMAGE without Core Graphics (ArchiApp/StudioPanels.swift SheetImageExport): a sheet at true size on white paper,
// or the Model page of the current level (the same page as the model PDF plot), rasterised at a chosen dpi from the
// plotted page operations of EnginePDF (colours, lineweights and plot styles of the page setup, viewport clips).
// PNG and TIFF are written here; JPEG is encoded by the Windows shell (Chromium) from the PNG.
import Foundation

public enum EngineSheetImage {
    public struct TooLarge: Error, LocalizedError { public var errorDescription: String? { "Could not render the image (too large?)." } }

    static func ext(_ format: String) -> String {
        switch format.lowercased() {
        case "jpeg", "jpg": return "jpg"
        case "tiff", "tif": return "tiff"
        default: return "png"
        }
    }

    /// Circle (polygon) around a point, for dots.
    static func circle(_ c: Vec2, _ r: Double) -> [Vec2] {
        (0..<16).map { i in
            let a = Double(i) / 16 * 2 * Double.pi
            return Vec2(c.x + cos(a) * r, c.y + sin(a) * r)
        }
    }

    /// PDF dash lengths (on, off, …) → draw-list dash pattern (positive dash, negative gap, 0 dot).
    static func dashPattern(_ lens: [Double]) -> [Double] {
        var out: [Double] = []
        for (i, v) in lens.enumerated() {
            if i % 2 == 0 { out.append(v <= 0.02 ? 0 : v) } else { out.append(-max(v, 0.01)) }
        }
        return out
    }

    /// Rasterises a resolved page (points, y up) at `dpi` on white paper.
    public static func render(_ page: EngineResolvedPage, dpi: Double, imageBase: URL? = nil) throws -> RGBAImage {
        let k = dpi / 72
        let w = Int((page.width * k).rounded()), h = Int((page.height * k).rounded())
        guard w > 0, h > 0, w <= 40000, h <= 40000, w * h <= 400_000_000 else { throw TooLarge() }
        var img = RGBAImage(width: w, height: h)
        img.dpi = dpi
        var r = DrawRaster(image: img, origin: Vec2(0, page.height), scale: k)
        r.lineweightScale = k
        r.imageBase = imageBase
        var stack: [(base: RGBAImage, clip: [Vec2])] = []
        for op in page.ops {
            switch op {
            case .stroke(let pts, let closed, let color, let width, let dash):
                let style = StrokeStyle(color: color, lineweight: width, dash: dash.isEmpty ? [] : dashPattern(dash))
                r.stroke(pts, closed: closed, style: style)
            case .dot(let c, let radius, let color):
                r.fill([circle(c, max(radius, 0.5 / k))], color)
            case .fill(let loops, let color):
                r.fill(loops, color)
            case .text(let lines, let font, let size, let color, let underlines):
                let format = RasterTextFormat(bold: font == 2 || font == 4, italic: font == 3 || font == 4, underline: false, strike: false)
                for l in lines {
                    let m = l.matrix
                    let t = TextGeom(position: Vec2(m.tx, m.ty), height: size * 0.718, content: l.text, rotation: atan2(m.b, m.a))
                    r.text(t, color: color, format: format)
                }
                for u in underlines { r.fill([u], color) }
            case .image(let path, let m):
                let wImg = (m.a * m.a + m.b * m.b).squareRoot(), hImg = (m.c * m.c + m.d * m.d).squareRoot()
                r.image(ImageGeom(path: path, origin: Vec2(m.tx, m.ty), size: Vec2(wImg, hImg), rotation: atan2(m.b, m.a)))
            case .clipBegin(let poly):
                stack.append((r.image, poly))
            case .clipEnd:
                guard let top = stack.popLast() else { break }
                r.image = composite(base: top.base, over: r.image, clip: top.clip, pageHeight: page.height, scale: k)
            default:
                break
            }
        }
        return r.image
    }

    /// Keeps `over` inside the clip polygon (antialiased edge) and `base` outside it.
    static func composite(base: RGBAImage, over: RGBAImage, clip: [Vec2], pageHeight: Double, scale k: Double) -> RGBAImage {
        guard clip.count >= 3 else { return over }
        let b = BBox2(points: clip)
        let x0 = max(0, Int((b.min.x * k).rounded(.down)) - 1), x1 = min(base.width, Int((b.max.x * k).rounded(.up)) + 1)
        let y0 = max(0, Int(((pageHeight - b.max.y) * k).rounded(.down)) - 1), y1 = min(base.height, Int(((pageHeight - b.min.y) * k).rounded(.up)) + 1)
        var out = base
        guard x1 > x0, y1 > y0 else { return out }
        // Mask of the clip polygon over its bounding box.
        let mw = x1 - x0, mh = y1 - y0
        var mr = DrawRaster(image: RGBAImage(width: mw, height: mh, background: RGBA(0, 0, 0, 0)), origin: Vec2(Double(x0) / k, pageHeight - Double(y0) / k), scale: k)
        mr.fill([clip], RGBA(0, 0, 0, 1))
        let mask = mr.image
        for y in y0..<y1 {
            for x in x0..<x1 {
                let a = Double(mask.pixels[((y - y0) * mw + (x - x0)) * 4 + 3]) / 255
                if a <= 0 { continue }
                let i = (y * base.width + x) * 4
                for c in 0..<4 {
                    let v = Double(base.pixels[i + c]) * (1 - a) + Double(over.pixels[i + c]) * a
                    out.pixels[i + c] = UInt8(max(0, min(255, v.rounded())))
                }
            }
        }
        return out
    }

    /// The image of a sheet, or of the Model page of `level` (default the current level).
    public static func image(doc: ArchiDocument, layoutIndex li: Int?, level: Int? = nil, dpi: Double, imageBase: URL? = nil) throws -> RGBAImage {
        guard dpi > 0 else { throw TooLarge() }
        let page: EnginePlotPage
        if let li {
            guard let p = EnginePlot.sheetPage(doc: doc, layoutIndex: li) else { throw CommandError.invalid("Unknown sheet.") }
            page = p
        } else {
            page = EnginePlot.modelPage(doc: doc, level: level ?? doc.currentLevel).page
        }
        return try render(EnginePDF.resolve(page, doc: doc, layered: false), dpi: dpi, imageBase: imageBase)
    }

    // MARK: TIFF (baseline, uncompressed RGB, resolution in dpi)

    public static func tiffData(_ img: RGBAImage) -> Data {
        var d = Data()
        func u16(_ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: Int) { u16(v & 0xFFFF); u16((v >> 16) & 0xFFFF) }
        let w = img.width, h = img.height
        let entries = 12
        let ifdSize = 2 + entries * 12 + 4
        let bpsOffset = 8 + ifdSize
        let xresOffset = bpsOffset + 6
        let yresOffset = xresOffset + 8
        let dataOffset = yresOffset + 8
        let dpiNum = Int((img.dpi * 100).rounded())
        d.append(contentsOf: [0x49, 0x49])
        u16(42); u32(8)
        u16(entries)
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) {
            u16(tag); u16(type); u32(count)
            if type == 3 && count == 1 { u16(value); u16(0) } else { u32(value) }
        }
        entry(256, 4, 1, w)
        entry(257, 4, 1, h)
        entry(258, 3, 3, bpsOffset)
        entry(259, 3, 1, 1)
        entry(262, 3, 1, 2)
        entry(273, 4, 1, dataOffset)
        entry(277, 3, 1, 3)
        entry(278, 4, 1, h)
        entry(279, 4, 1, w * h * 3)
        entry(282, 5, 1, xresOffset)
        entry(283, 5, 1, yresOffset)
        entry(296, 3, 1, 2)
        u32(0)
        u16(8); u16(8); u16(8)
        u32(dpiNum); u32(100)
        u32(dpiNum); u32(100)
        var rgb = [UInt8](repeating: 255, count: w * h * 3)
        var j = 0
        var i = 0
        while i < img.pixels.count {
            let a = Double(img.pixels[i + 3]) / 255
            for c in 0..<3 {
                // Flatten on white.
                let v = Double(img.pixels[i + c]) + 255 * (1 - a)
                rgb[j + c] = UInt8(max(0, min(255, v.rounded())))
            }
            i += 4
            j += 3
        }
        d.append(contentsOf: rgb)
        return d
    }
}

extension EngineSession {
    /// `sheet.image {layout: index|"Model", dpi?=150, format?="png"|"tiff"|"jpeg", path?, level?}` → `{path?, width, height,
    /// bytes, png?}`. PNG and TIFF are written to `path`; for JPEG (or without a path) the PNG goes to a temporary file
    /// (`png`) that the shell converts and saves.
    func sheetImage(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        var li: Int? = nil
        if let i = p["layout"]?.intValue { li = i }
        else if let n = p["layout"]?.stringValue, n.caseInsensitiveCompare("Model") != .orderedSame {
            guard let i = doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw EngineError.params("unknown sheet '\(n)'") }
            li = i
        }
        if let i = li, !doc.layouts.indices.contains(i) { throw EngineError.params("no sheet \(i)") }
        let dpi = p["dpi"]?.intValue ?? 150
        guard (36...1200).contains(dpi) else { throw EngineError.params("Resolution must be 36–1200 dpi.") }
        let format = (p["format"]?.stringValue ?? "png").lowercased()
        let level = p["level"]?.intValue
        let img: RGBAImage
        do { img = try EngineSheetImage.image(doc: doc, layoutIndex: li, level: level, dpi: Double(dpi), imageBase: editor.fileURL?.deletingLastPathComponent() ?? baseDirectory) }
        catch { throw EngineError.failed(EngineSession.describe(error)) }
        let title = li.map { doc.layouts[$0].name } ?? "Model"
        var o = EngineObject()
        o.set("width", img.width)
        o.set("height", img.height)
        o.set("title", title)
        let jpeg = format == "jpeg" || format == "jpg"
        if let path = p["path"]?.stringValue, !path.isEmpty, !jpeg {
            let u = url(path)
            let data = format.hasPrefix("tif") ? EngineSheetImage.tiffData(img) : img.pngData(alpha: false)
            do { try data.write(to: u, options: .atomic) } catch { throw EngineError.failed("Cannot write \(u.path): \(EngineSession.describe(error))") }
            o.set("path", u.path)
            o.set("bytes", data.count)
            if p["quiet"]?.boolValue != true {
                editor.print("Saved \(title) at \(dpi) dpi (\(img.width)×\(img.height) px) to \(u.path).")
            }
            return o.json
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("archi-sheetimage-" + UUID().uuidString + ".png")
        let data = img.pngData(alpha: false)
        do { try data.write(to: tmp, options: .atomic) } catch { throw EngineError.failed("Cannot write \(tmp.path): \(EngineSession.describe(error))") }
        o.set("png", tmp.path)
        o.set("bytes", data.count)
        o.set("dpi", dpi)
        return o.json
    }
}
