// Oanarina Archi Tool — GPL-3.0-or-later
// DWFx import (IO-012): DWFx is an XPS (Open XML Paper Specification, ECMA-388) package; each sheet is a FixedPage of
// Path / Glyphs elements inside transformed Canvases. Paths (abbreviated geometry syntax, PathGeometry/PathFigure markup
// and StaticResource geometries) become polylines with their stroke colours, glyph runs become text, one page per sheet
// laid side by side, in millimetres (XPS units are 1/96 inch). Classic binary .dwf (W2D streams) is not supported.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum DWFxImporter {
    public struct DWFError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    public static func entities(_ data: Data) throws -> [Entity] {
        if data.starts(with: Array("(DWF V".utf8)) { throw DWFError(message: "Classic binary DWF is not supported: republish it as DWFx or PDF.") }
        let entries = try ZipArchive.read(data)
        let pages = entries.filter { $0.name.lowercased().hasSuffix(".fpage") }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !pages.isEmpty else { throw DWFError(message: "No XPS pages (.fpage) in the package.") }
        var out: [Entity] = []
        var x0 = 0.0
        for (n, p) in pages.enumerated() {
            let r = PageParser(pageIndex: n + 1)
            let xml = XMLParser(data: p.data)
            xml.delegate = r
            xml.parse()
            let shifted = r.entities.map { e -> Entity in var c = e; c.geometry = GeometryOps.transform(e.geometry, Transform2D.translation(Vec2(x0, 0))); return c }
            out += shifted
            x0 += r.pageWidth + 20
        }
        guard !out.isEmpty else { throw DWFError(message: "The DWFx pages contain no vector graphics.") }
        return out
    }

    static func matrix(_ s: String?) -> Transform2D? {
        guard let s else { return nil }
        let v = s.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        return v.count == 6 ? Transform2D(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]) : nil
    }
    static func color(_ s: String?) -> ColorRef? {
        guard var h = s?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
        h.removeFirst()
        if h.count == 8 { h.removeFirst(2) }   // #AARRGGBB
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return .rgb(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    final class PageParser: NSObject, XMLParserDelegate {
        let k = 25.4 / 96
        var base = Transform2D.identity
        var stack: [Transform2D] = []
        var entities: [Entity] = []
        var resources: [String: String] = [:]
        var pageWidth = 0.0
        let layer: String
        // Current Path being read (its data may come from child elements).
        struct PathState { var attrs: [String: String]; var transform: Transform2D; var data: String }
        var path: PathState?
        var figure: String?
        var inRenderTransform = false
        var resourceKey: String?
        init(pageIndex: Int) { layer = "DWF-SHEET\(pageIndex)" }

        var current: Transform2D { stack.last ?? base }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch name {
            case "FixedPage":
                let w = Double(a["Width"] ?? "") ?? 816, h = Double(a["Height"] ?? "") ?? 1056
                pageWidth = w * k
                base = Transform2D(a: k, d: -k, ty: h * k)
                stack = [base]
            case "Canvas":
                stack.append(current * (DWFxImporter.matrix(a["RenderTransform"]) ?? .identity))
            case "Canvas.RenderTransform", "Path.RenderTransform", "Glyphs.RenderTransform": inRenderTransform = true
            case "MatrixTransform" where inRenderTransform:
                guard let m = DWFxImporter.matrix(a["Matrix"]) else { break }
                if path != nil { path!.transform = path!.transform * m } else if !stack.isEmpty { stack[stack.count - 1] = stack[stack.count - 1] * m }
            case "Path":
                var data = a["Data"] ?? ""
                if data.hasPrefix("{StaticResource"), let key = data.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "}")) { data = resources[key] ?? "" }
                path = PathState(attrs: a, transform: current * (DWFxImporter.matrix(a["RenderTransform"]) ?? .identity), data: data)
            case "PathGeometry":
                let figs = a["Figures"] ?? ""
                if let key = a["x:Key"] ?? a["Key"] { resources[key] = figs; resourceKey = key }
                else if path != nil { path!.data += " " + figs }
            case "PathFigure":
                let sp = (a["StartPoint"] ?? "0,0").replacingOccurrences(of: ",", with: " ")
                figure = "M \(sp)"
                if a["IsClosed"]?.lowercased() == "true" { closedFigure = true } else { closedFigure = false }
            case "PolyLineSegment", "LineSegment":
                figure? += " L " + (a["Points"] ?? a["Point"] ?? "").replacingOccurrences(of: ",", with: " ")
            case "PolyBezierSegment", "BezierSegment":
                let pts = a["Points"] ?? [a["Point1"], a["Point2"], a["Point3"]].compactMap { $0 }.joined(separator: " ")
                figure? += " C " + pts.replacingOccurrences(of: ",", with: " ")
            case "PolyQuadraticBezierSegment", "QuadraticBezierSegment":
                let pts = a["Points"] ?? [a["Point1"], a["Point2"]].compactMap { $0 }.joined(separator: " ")
                figure? += " Q " + pts.replacingOccurrences(of: ",", with: " ")
            case "ArcSegment":
                let size = (a["Size"] ?? "0,0").replacingOccurrences(of: ",", with: " ")
                let pt = (a["Point"] ?? "0,0").replacingOccurrences(of: ",", with: " ")
                figure? += " A \(size) \(a["RotationAngle"] ?? "0") \(a["IsLargeArc"]?.lowercased() == "true" ? 1 : 0) \(a["SweepDirection"] == "Clockwise" ? 1 : 0) \(pt)"
            case "Glyphs":
                guard let s = a["UnicodeString"], !s.isEmpty else { break }
                let t = current * (DWFxImporter.matrix(a["RenderTransform"]) ?? .identity)
                let o = t.apply(Vec2(Double(a["OriginX"] ?? "") ?? 0, Double(a["OriginY"] ?? "") ?? 0))
                let em = Double(a["FontRenderingEmSize"] ?? "") ?? 12
                let rot = atan2(-t.b, t.a) == 0 ? 0 : -atan2(t.b, t.a)
                entities.append(Entity(layer: layer + "-TEXT", color: DWFxImporter.color(a["Fill"]) ?? .byLayer,
                                       geometry: .text(TextGeom(position: o, height: em * t.scaleFactor * 0.7, content: s.hasPrefix("{}") ? String(s.dropFirst(2)) : s, rotation: rot))))
            default: break
            }
        }
        var closedFigure = false

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "Canvas": if stack.count > 1 { stack.removeLast() }
            case "Canvas.RenderTransform", "Path.RenderTransform", "Glyphs.RenderTransform": inRenderTransform = false
            case "PathFigure":
                if var f = figure {
                    if closedFigure { f += " Z" }
                    if let key = resourceKey { resources[key, default: ""] += " " + f } else if path != nil { path!.data += " " + f }
                }
                figure = nil
            case "PathGeometry": resourceKey = nil
            case "Path":
                guard let p = path else { break }
                path = nil
                var d = p.data.trimmingCharacters(in: .whitespaces)
                if d.hasPrefix("F0") || d.hasPrefix("F1") { d = String(d.dropFirst(2)) }
                let stroke = DWFxImporter.color(p.attrs["Stroke"]), fill = DWFxImporter.color(p.attrs["Fill"])
                guard !d.isEmpty, stroke != nil || fill != nil else { break }
                for pl in SVGImporter.pathPolylines(d, p.transform, segments: 8) where pl.vertices.count >= 2 {
                    var e = Entity(layer: stroke == nil ? layer + "-FILL" : layer, color: stroke ?? fill ?? .byLayer, geometry: .polyline(pl))
                    if let w = Double(p.attrs["StrokeThickness"] ?? ""), stroke != nil { e.lineweight = w * p.transform.scaleFactor }
                    if pl.vertices.count == 2, !pl.closed, pl.vertices[0].bulge == 0 { e.geometry = .line(LineGeom(pl.vertices[0].p, pl.vertices[1].p)) }
                    entities.append(e)
                }
            default: break
            }
        }
    }
}

extension DWFxImporter {
    static var command: CommandDef {
        CommandDef("DWFIMPORT", aliases: ["DWFXIMPORT", "IMPORTDWF"], category: "Insert",
                   summary: "Imports the sheets of a DWFx file (XPS paths, colours, line weights and text; one sheet after the other) as drawing objects.") { ed in
            let url = try await IOCommands.path(ed, "Enter DWFx file name")
            try IOCommands.runImport(ed, url, format: "dwfx")
        }
    }
}
