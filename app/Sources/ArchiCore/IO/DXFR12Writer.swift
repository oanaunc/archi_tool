// Oanarina Archi Tool — GPL-3.0-or-later
// DXF R12 (AC1009) ASCII writer for older CAD/CAM/laser software. R12 has no LWPOLYLINE, ELLIPSE, SPLINE,
// MTEXT, HATCH or true colour, so those are written as POLYLINE/VERTEX, multi-line TEXT and SOLID fills.
import Foundation

public enum DXFVersion: String, CaseIterable { case r12 = "R12", r2000 = "R2000" }

extension DXFWriter {
    /// Writes the document in the requested DXF version (BIM elements of `levels` as 2D plan geometry).
    public static func write(_ doc: ArchiDocument, version: DXFVersion, levels: Set<Int>? = nil) -> String {
        switch version {
        case .r2000: return write(doc, levels: levels ?? [doc.currentLevel])
        case .r12: return DXFR12Writer.write(doc, levels: levels ?? [doc.currentLevel])
        }
    }
}

public enum DXFR12Writer {
    public static func write(_ doc: ArchiDocument, levels: Set<Int>?) -> String {
        var w = W(doc: doc)
        return w.run(levels: levels)
    }

    struct Style { var layer: String; var color: Int? = nil; var linetype: String? = nil }

    struct W {
        let doc: ArchiDocument
        var out: [String] = []
        init(doc: ArchiDocument) { self.doc = doc }

        mutating func g(_ c: Int, _ v: String) { out.append(String(format: "%3d", c)); out.append(v) }
        mutating func g(_ c: Int, _ v: Double) { g(c, num(v)) }
        mutating func g(_ c: Int, _ v: Int) { g(c, String(format: "%6d", v)) }
        func num(_ v: Double) -> String {
            guard v.isFinite else { return "0.0" }
            let s = fmt(v, 8)
            return s.contains(".") ? s : s + ".0"
        }
        mutating func pt(_ c: Int, _ p: Vec2, _ z: Double = 0) { g(c, p.x); g(c + 10, p.y); g(c + 20, z) }
        func layerName(_ n: String) -> String { DXFWriter.enc(DXFWriter.safeName(n)).replacingOccurrences(of: " ", with: "_") }

        mutating func run(levels: Set<Int>?) -> String {
            let b = GeometryOps.bounds(of: doc, includeElements: true)
            g(0, "SECTION"); g(2, "HEADER")
            g(9, "$ACADVER"); g(1, "AC1009")
            g(9, "$INSBASE"); pt(10, .zero)
            g(9, "$EXTMIN"); pt(10, b.isEmpty ? .zero : b.min)
            g(9, "$EXTMAX"); pt(10, b.isEmpty ? Vec2(1000, 1000) : b.max)
            g(9, "$LTSCALE"); g(40, Double(doc.variable("LTSCALE") ?? "1") ?? 1)
            g(9, "$HANDLING"); g(70, 0)
            g(0, "ENDSEC")
            tables()
            g(0, "SECTION"); g(2, "BLOCKS")
            for name in doc.blocks.keys.sorted() {
                guard let blk = doc.blocks[name] else { continue }
                let n = blockName(name)
                g(0, "BLOCK"); g(8, "0"); g(2, n); g(70, blk.entities.contains { $0.props["attdef"] != nil } ? 2 : 0); pt(10, blk.basePoint); g(3, n)
                for e in blk.entities { entity(e, paper: false) }
                g(0, "ENDBLK"); g(8, "0")
            }
            g(0, "ENDSEC")
            g(0, "SECTION"); g(2, "ENTITIES")
            for e in doc.entities { entity(e, paper: false) }
            for el in doc.elements where levels == nil || levels!.contains(el.level) { element(el) }
            if let lay = doc.layouts.first(where: { !$0.entities.isEmpty }) { for e in lay.entities { entity(e, paper: true) } }
            g(0, "ENDSEC")
            g(0, "EOF")
            return out.joined(separator: "\n") + "\n"
        }

        func blockName(_ n: String) -> String {
            var t = DXFWriter.enc(DXFWriter.safeName(n)).replacingOccurrences(of: " ", with: "_")
            if t.hasPrefix("*") { t = "_" + t.dropFirst() }
            return t
        }

        mutating func tables() {
            g(0, "SECTION"); g(2, "TABLES")
            let lts = doc.linetypes.filter { !["continuous", "bylayer", "byblock"].contains($0.name.lowercased()) }
            g(0, "TABLE"); g(2, "LTYPE"); g(70, lts.count + 1)
            g(0, "LTYPE"); g(2, "CONTINUOUS"); g(70, 0); g(3, "Solid line"); g(72, 65); g(73, 0); g(40, 0.0)
            for lt in lts {
                g(0, "LTYPE"); g(2, layerName(lt.name).uppercased()); g(70, 0); g(3, DXFWriter.enc(lt.description)); g(72, 65)
                g(73, lt.pattern.count); g(40, lt.pattern.reduce(0) { $0 + abs($1) })
                for d in lt.pattern { g(49, d) }
            }
            g(0, "ENDTAB")
            g(0, "TABLE"); g(2, "LAYER"); g(70, doc.layers.count)
            for l in doc.layers {
                g(0, "LAYER"); g(2, layerName(l.name)); g(70, (l.frozen ? 1 : 0) | (l.locked ? 4 : 0))
                let aci = DXFWriter.nearestACI(l.color)
                g(62, l.visible ? aci : -aci)
                g(6, linetype(l.linetype) ?? "CONTINUOUS")
            }
            g(0, "ENDTAB")
            g(0, "TABLE"); g(2, "STYLE"); g(70, 1)
            g(0, "STYLE"); g(2, "STANDARD"); g(70, 0); g(40, 0.0); g(41, 1.0); g(50, 0.0); g(71, 0); g(42, 2.5); g(3, "txt"); g(4, "")
            g(0, "ENDTAB")
            g(0, "ENDSEC")
        }

        func linetype(_ n: String?) -> String? {
            guard let n = n else { return nil }
            switch n.lowercased() {
            case "bylayer": return "BYLAYER"
            case "byblock": return "BYBLOCK"
            case "continuous": return "CONTINUOUS"
            default: return doc.linetype(n) != nil ? layerName(n).uppercased() : nil
            }
        }

        mutating func head(_ type: String, _ s: Style, paper: Bool) {
            g(0, type); g(8, layerName(s.layer))
            if let lt = s.linetype { g(6, lt) }
            if let c = s.color { g(62, c) }
            if paper { g(67, 1) }
        }

        func style(_ e: Entity) -> Style {
            var s = Style(layer: e.layer)
            switch e.color {
            case .byLayer: break
            case .byBlock: s.color = 0
            case .aci(let i): s.color = max(1, min(255, i))
            case .rgb(let r, let gg, let b): s.color = DXFWriter.nearestACI(RGBA(Double(r) / 255, Double(gg) / 255, Double(b) / 255))
            }
            if let lt = e.linetype, lt.lowercased() != "bylayer" { s.linetype = linetype(lt) }
            return s
        }

        mutating func entity(_ e: Entity, paper: Bool) {
            geometry(e.geometry, style(e), paper: paper, props: e.props, depth: 0)
        }

        mutating func polyline(_ v: [PolyVertex], closed: Bool, _ s: Style, paper: Bool) {
            guard v.count >= 2 else { return }
            head("POLYLINE", s, paper: paper); g(66, 1); pt(10, .zero); g(70, closed ? 1 : 0)
            for (i, p) in v.enumerated() {
                g(0, "VERTEX"); g(8, layerName(s.layer)); pt(10, p.p)
                if (closed || i < v.count - 1), abs(p.bulge) > 1e-12 { g(42, p.bulge) }
            }
            g(0, "SEQEND"); g(8, layerName(s.layer))
        }

        mutating func text(_ t: TextGeom, _ s: Style, paper: Bool, tag: String? = nil) {
            let lines = t.content.components(separatedBy: "\n")
            let pitch = t.height * 1.667
            // Anchor of the first line so the block keeps its alignment.
            let n = Double(lines.count - 1)
            let shift: Double
            switch t.valign { case .top: shift = 0; case .middle: shift = n * pitch / 2; case .bottom, .baseline: shift = n * pitch }
            let down = Vec2(0, -1).rotated(by: t.rotation)
            for (i, line) in lines.enumerated() where !line.isEmpty || tag != nil {
                let p = t.position + down * (Double(i) * pitch - shift)
                head(tag == nil ? "TEXT" : "ATTDEF", s, paper: paper)
                pt(10, p); g(40, t.height); g(1, DXFWriter.enc(tag == nil ? line : (tag ?? "")))
                if abs(t.rotation) > 1e-12 { g(50, deg(t.rotation)) }
                let ha = t.halign == .left ? 0 : (t.halign == .center ? 1 : 2)
                let va: Int
                switch t.valign { case .baseline: va = 0; case .bottom: va = 1; case .middle: va = 2; case .top: va = 3 }
                if ha != 0 || va != 0 { g(72, ha); pt(11, p) }
                if let tag = tag { g(3, "Enter \(tag)"); g(2, tag); g(70, 0) }
                if va != 0 { g(tag == nil ? 73 : 74, va) }
                if tag != nil { break }
            }
        }

        mutating func solidFill(_ loops: [[Vec2]], _ s: Style, paper: Bool) {
            guard let outer = loops.first, outer.count >= 3 else { return }
            let r = Triangulator.triangulateWithPoints(outer, holes: Array(loops.dropFirst()))
            for t in r.triangles {
                head("SOLID", s, paper: paper)
                pt(10, r.points[t.0]); pt(11, r.points[t.1]); pt(12, r.points[t.2]); pt(13, r.points[t.2])
            }
        }

        mutating func geometry(_ geo: Geometry, _ s: Style, paper: Bool, props: [String: String], depth: Int) {
            guard depth < 8 else { return }
            switch geo {
            case .point(let p): head("POINT", s, paper: paper); pt(10, p)
            case .line(let l): head("LINE", s, paper: paper); pt(10, l.a); pt(11, l.b)
            case .circle(let c): head("CIRCLE", s, paper: paper); pt(10, c.center); g(40, c.radius)
            case .arc(let a): head("ARC", s, paper: paper); pt(10, a.center); g(40, a.radius); g(50, deg(normAngle(a.start))); g(51, deg(normAngle(a.end)))
            case .ellipse(let e):
                var pts = GeometryOps.ellipsePoints(e)
                if e.isFull, pts.count > 2, pts[0].isClose(pts[pts.count - 1]) { pts.removeLast() }
                polyline(pts.map { PolyVertex($0) }, closed: e.isFull, s, paper: paper)
            case .polyline(let p): polyline(p.vertices, closed: p.closed, s, paper: paper)
            case .spline(let sp):
                var pts = GeometryOps.splinePoints(sp)
                if sp.closed, pts.count > 2, pts[0].isClose(pts[pts.count - 1]) { pts.removeLast() }
                polyline(pts.map { PolyVertex($0) }, closed: sp.closed, s, paper: paper)
            case .text(let t):
                if let tag = props["attdef"] { text(t, s, paper: paper, tag: tag) } else { text(t, s, paper: paper) }
            case .insert(let ins):
                head("INSERT", s, paper: paper)
                if !ins.attributes.isEmpty { g(66, 1) }
                g(2, blockName(ins.block)); pt(10, ins.position)
                if ins.scale.x != 1 { g(41, ins.scale.x) }
                if ins.scale.y != 1 { g(42, ins.scale.y) }
                if abs(ins.rotation) > 1e-12 { g(50, deg(ins.rotation)) }
                if !ins.attributes.isEmpty {
                    for (tag, value) in ins.attributes.sorted(by: { $0.key < $1.key }) {
                        g(0, "ATTRIB"); g(8, layerName(s.layer)); pt(10, ins.position); g(40, 2.5); g(1, DXFWriter.enc(value)); g(2, DXFWriter.enc(tag)); g(70, 0)
                    }
                    g(0, "SEQEND"); g(8, layerName(s.layer))
                }
            case .hatch(let h):
                let loops = h.loops.map { GeometryOps.polylinePoints($0, closed: true) }
                if h.pattern.uppercased() == "SOLID" { solidFill(loops, s, paper: paper) }
                else { for l in h.loops where l.count >= 2 { polyline(l, closed: true, s, paper: paper) } }
            case .image(let im):
                let t = Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation)
                polyline([Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y)].map { PolyVertex(t.apply($0)) }, closed: true, s, paper: paper)
            case .solid(let so):
                let fp = GeometryOps.solidFootprint(so)
                if fp.count >= 2 { polyline(fp.map { PolyVertex($0) }, closed: true, s, paper: paper) }
            case .dimension, .leader, .table:
                for sub in Modify.explode(geo, doc: doc) ?? [] { geometry(sub, s, paper: paper, props: [:], depth: depth + 1) }
            }
        }

        mutating func element(_ el: BIMElement) {
            var items = PlanRepresentation.items(el, doc: doc)
            if items.isEmpty { items = DXFWriter.fallbackPlan(el, doc: doc) }
            let lc = doc.layer(named: el.layer)?.color ?? .white
            for it in items {
                switch it {
                case .stroke(let pts, let closed, let st):
                    var s = Style(layer: el.layer)
                    if !st.color.isNear(lc) { s.color = DXFWriter.nearestACI(st.color) }
                    if pts.count == 2 && !closed { head("LINE", s, paper: false); pt(10, pts[0]); pt(11, pts[1]) }
                    else { polyline(pts.map { PolyVertex($0) }, closed: closed, s, paper: false) }
                case .fill(let loops, let color):
                    var s = Style(layer: el.layer)
                    if !color.isNear(lc) { s.color = DXFWriter.nearestACI(color) }
                    solidFill(loops, s, paper: false)
                case .text(let t, _, let color):
                    var s = Style(layer: el.layer)
                    if !color.isNear(lc) { s.color = DXFWriter.nearestACI(color) }
                    text(t, s, paper: false)
                case .image: break
                }
            }
        }
    }
}
