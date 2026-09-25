// Oanarina Archi Tool — GPL-3.0-or-later
// CNC / laser export (IO-019): a MakerCAM / LightBurn-style SVG at true size in millimetres. Only vector outlines are
// written (hairline strokes, no fills): connected lines, arcs and open polylines are joined into continuous paths (fewer
// pierces and head moves), arcs stay true SVG arcs, and every path goes into an operation group by colour —
// red #FF0000 cut, blue #0000FF engrave/score (layers named *ENGRAV*, *SCORE*, *ETCH* or blue objects).
// Optional kerf compensation offsets closed outer contours outward and holes inward by half the kerf.
import Foundation

public struct LaserOptions: Hashable {
    /// Drawing units per millimetre of material (1 = full size in mm drawings; 100 for a 1:100 model).
    public var scale: Double = 1
    /// Kerf width in mm (0 = no compensation).
    public var kerf: Double = 0
    /// Layers to write (empty = all visible layers).
    public var layers: Set<String> = []
    public init(scale: Double = 1, kerf: Double = 0, layers: Set<String> = []) { self.scale = scale; self.kerf = kerf; self.layers = layers }
    public static func from(_ doc: ArchiDocument) -> LaserOptions {
        var o = LaserOptions()
        if let v = doc.variable("LASERSCALE").flatMap(Double.init), v > 0 { o.scale = v }
        if let v = doc.variable("LASERKERF").flatMap(Double.init), v >= 0 { o.kerf = v }
        return o
    }
}

public enum LaserExporter {
    public struct Result { public var svg: String; public var cutPaths: Int; public var engravePaths: Int; public var skipped: Int; public var size: Vec2 }

    static func isEngrave(_ e: Entity, doc: ArchiDocument) -> Bool {
        let l = e.layer.uppercased()
        if l.contains("ENGRAV") || l.contains("SCORE") || l.contains("ETCH") { return true }
        let c: RGBA?
        switch e.color {
        case .aci(let i): c = aciColor(i)
        case .rgb(let r, let g, let b): c = RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        default: c = doc.layer(named: e.layer)?.color
        }
        if let c { return c.b > 0.6 && c.r < 0.3 && c.g < 0.5 }
        return false
    }

    public static func export(_ doc: ArchiDocument, options o: LaserOptions = LaserOptions()) -> Result {
        let k = doc.units.mm / max(o.scale, 1e-12)   // drawing units → mm on the material
        var cut: [Geometry] = [], engrave: [Geometry] = []
        var skipped = 0
        let hidden = Set(doc.layers.filter { !$0.visible || $0.frozen }.map { $0.name.lowercased() })
        for e in doc.entities {
            if !o.layers.isEmpty { guard o.layers.contains(where: { $0.caseInsensitiveCompare(e.layer) == .orderedSame }) else { continue } }
            else if hidden.contains(e.layer.lowercased()) { continue }
            var gs: [Geometry] = []
            switch e.geometry {
            case .line, .arc, .circle, .polyline, .ellipse, .spline: gs = [e.geometry]
            case .insert, .solid:
                // Block contents / 3D solids: their plan outlines.
                gs = GeometryOps.tessellate(e.geometry, doc: doc).filter { $0.count >= 2 }.map { .polyline(PolylineGeom(points: $0, closed: false)) }
            default: skipped += 1; continue
            }
            let scaled = gs.map { GeometryOps.transform($0, Transform2D.scale(k, k)) }
            if isEngrave(e, doc: doc) { engrave += scaled } else { cut += scaled }
        }
        // Continuous paths.
        cut = Modify.join(cut); engrave = Modify.join(engrave)
        if o.kerf > 0 { cut = compensate(cut, kerf: o.kerf) }
        var box = BBox2.empty
        for g in cut + engrave { box.add(GeometryOps.bounds(g, doc: nil)) }
        if box.isEmpty { box = BBox2(min: .zero, max: Vec2(1, 1)) }
        let margin = 2.0
        let W = box.width + 2 * margin, H = box.height + 2 * margin
        // SVG y points down: flip about the box.
        func P(_ p: Vec2) -> String { "\(n(p.x - box.min.x + margin)),\(n(box.max.y - p.y + margin))" }
        func path(_ g: Geometry) -> String? {
            switch g {
            case .circle(let c):
                return "<circle cx=\"\(n(c.center.x - box.min.x + margin))\" cy=\"\(n(box.max.y - c.center.y + margin))\" r=\"\(n(c.radius))\"/>"
            case .arc(let a):
                let large = a.sweep > .pi ? 1 : 0
                return "<path d=\"M\(P(a.startPoint)) A\(n(a.radius)),\(n(a.radius)) 0 \(large) 0 \(P(a.endPoint))\"/>"
            case .line(let l):
                return "<path d=\"M\(P(l.a)) L\(P(l.b))\"/>"
            case .polyline(let pl):
                guard let first = pl.vertices.first else { return nil }
                var d = "M\(P(first.p))"
                let count = pl.closed ? pl.vertices.count : pl.vertices.count - 1
                for i in 0..<max(count, 0) {
                    let a = pl.vertices[i], b = pl.vertices[(i + 1) % pl.vertices.count]
                    if abs(a.bulge) < 1e-12 { d += " L\(P(b.p))"; continue }
                    let arc = GeometryOps.bulgeArc(a.p, b.p, a.bulge)
                    let large = abs(arc.sweep) > .pi ? 1 : 0
                    // CCW in model space (bulge > 0) is clockwise on the flipped SVG canvas: sweep-flag 0.
                    d += " A\(n(arc.radius)),\(n(arc.radius)) 0 \(large) \(a.bulge > 0 ? 0 : 1) \(P(b.p))"
                }
                if pl.closed { d += " Z" }
                return "<path d=\"\(d)\"/>"
            default:
                let pts = GeometryOps.tessellate(g, doc: nil).first ?? []
                guard pts.count >= 2 else { return nil }
                return "<path d=\"M\(P(pts[0]))" + pts.dropFirst().map { " L\(P($0))" }.joined() + "\"/>"
            }
        }
        let cutEls = cut.compactMap(path), engEls = engrave.compactMap(path)
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<!-- \(doc.info.name) — laser/CNC outlines from Oanarina Archi Tool; units mm, red = cut, blue = engrave -->\n"
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"\(n(W))mm\" height=\"\(n(H))mm\" viewBox=\"0 0 \(n(W)) \(n(H))\">\n"
        s += "<g id=\"engrave\" fill=\"none\" stroke=\"#0000FF\" stroke-width=\"0.01\">\n" + engEls.map { "  " + $0 + "\n" }.joined() + "</g>\n"
        s += "<g id=\"cut\" fill=\"none\" stroke=\"#FF0000\" stroke-width=\"0.01\">\n" + cutEls.map { "  " + $0 + "\n" }.joined() + "</g>\n"
        s += "</svg>\n"
        return Result(svg: s, cutPaths: cutEls.count, engravePaths: engEls.count, skipped: skipped, size: Vec2(W, H))
    }

    static func n(_ v: Double) -> String { let s = fmt(v, 4); return s == "-0" ? "0" : s }

    /// Kerf compensation: closed contours inside another closed contour are holes (offset inward), others outward.
    static func compensate(_ gs: [Geometry], kerf: Double) -> [Geometry] {
        let half = kerf / 2
        func loop(_ g: Geometry) -> [Vec2]? {
            switch g {
            case .circle, .ellipse: return GeometryOps.tessellate(g, doc: nil).first
            case .polyline(let p) where p.closed: return GeometryOps.tessellate(g, doc: nil).first
            default: return nil
            }
        }
        let loops = gs.map(loop)
        return gs.enumerated().map { i, g in
            guard let l = loops[i], l.count >= 3 else { return g }
            let probe = l[0]
            let depth = loops.enumerated().filter { j, o in j != i && o != nil && GeometryOps.pointInPolygon(probe, o!) }.count
            let c = GeometryOps.centroid(l)
            var b = BBox2(points: l)
            b = b.expanded(by: max(b.width, b.height) + 1)
            let outside = b.max
            // Even depth = outer contour (grow), odd = hole (shrink).
            let side = depth % 2 == 0 ? outside : c
            return Modify.offset(g, distance: half, towards: side) ?? g
        }
    }
}

extension LaserExporter {
    static var command: CommandDef {
        CommandDef("LASEREXPORT", aliases: ["CNCSVG", "LASERSVG", "MAKERCAM"], category: "File",
                   summary: "Exports outlines for laser cutters / CNC as a true-size SVG in mm: joined continuous paths, red = cut, blue = engrave (layers *ENGRAV*/*SCORE*/*ETCH* or blue objects), optional model scale and kerf compensation.", modifies: false) { ed in
            var o = LaserOptions.from(ed.doc)
            o.scale = try await ed.getReal("Drawing units per mm of material (1 = full size, 100 = 1:100 model)", defaultValue: o.scale).value ?? o.scale
            o.kerf = try await ed.getReal("Kerf width mm (0 = none)", defaultValue: o.kerf).value ?? o.kerf
            guard o.scale > 0, o.kerf >= 0 else { throw CommandError.invalid("Scale must be positive and kerf zero or more.") }
            ed.doc.setVariable("LASERSCALE", fmt(o.scale, 6)); ed.doc.setVariable("LASERKERF", fmt(o.kerf, 4))
            var url = try await IOCommands.path(ed, "Enter SVG file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("svg") }
            let r = export(ed.doc, options: o)
            try IOCommands.write(ed, url, "laser SVG", { try r.svg.write(to: url, atomically: true, encoding: .utf8) })
            ed.print("\(r.cutPaths) cut path(s), \(r.engravePaths) engrave path(s), sheet \(fmt(r.size.x, 1)) × \(fmt(r.size.y, 1)) mm" + (r.skipped > 0 ? "; \(r.skipped) text/hatch/other object(s) skipped." : "."))
        }
    }
}
