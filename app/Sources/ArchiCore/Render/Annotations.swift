// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Model-aware annotations: element tags (doors, windows, rooms, keynotes) whose text follows the model,
/// and terrain contour display.
public enum Annotations {
    public enum TagKind: String, CaseIterable { case door, window, room, keynote, element }

    /// Text shown by a tag of `el` for a field ("mark", "type", "name", "number", "area", "keynote", "height", …).
    public static func tagText(_ el: BIMElement, field: String, doc: ArchiDocument) -> String {
        // Tag families (PAR-014): the family's label template with {Parameter} fields read from the element.
        if field.lowercased().hasPrefix("family:") {
            let name = String(field.dropFirst(7))
            guard let def = doc.family(named: name) else { return "?" }
            return fillLabel(def.label ?? "{Mark}", el: el, doc: doc)
        }
        switch field.lowercased() {
        case "mark":
            if case .opening(let o) = el.geometry { return o.mark ?? el.props["mark"] ?? "\(el.id)" }
            if case .space(let s) = el.geometry { return s.number.isEmpty ? s.name : s.number }
            return el.props["mark"] ?? "\(el.id)"
        case "type":
            if case .opening(let o) = el.geometry { return o.typeName ?? el.name }
            if case .wall(let w) = el.geometry { return w.wallType ?? "Generic" }
            return el.name
        case "name":
            if case .space(let s) = el.geometry { return s.name }
            return el.name
        case "number":
            if case .space(let s) = el.geometry { return s.number }
            return el.props["mark"] ?? "\(el.id)"
        case "area":
            if case .space(let s) = el.geometry { return PlanRepresentation.formatArea(abs(GeometryOps.signedArea(s.boundary)), doc) }
            if case .slab(let s) = el.geometry { return PlanRepresentation.formatArea(abs(GeometryOps.signedArea(s.boundary)), doc) }
            return ""
        case "room":
            if case .space(let s) = el.geometry {
                let a = PlanRepresentation.formatArea(abs(GeometryOps.signedArea(s.boundary)), doc)
                return [s.name, [s.number, a].filter { !$0.isEmpty }.joined(separator: "  ")].joined(separator: "\n")
            }
            return el.name
        case "keynote":
            return el.props["keynote"] ?? ""
        case "size":
            if case .opening(let o) = el.geometry { return "\(fmt(o.width))×\(fmt(o.height))" }
            return ""
        default:
            return el.props[field] ?? PropertyAccess.getProperty(el, field) ?? ProjectParameters.value(field, of: el, doc: doc) ?? ""
        }
    }

    /// Replaces {Field} placeholders by the element's values (any tag field or parameter name).
    public static func fillLabel(_ template: String, el: BIMElement, doc: ArchiDocument) -> String {
        var out = "", key = ""
        var inKey = false
        for ch in template {
            if ch == "{" && !inKey { inKey = true; key = ""; continue }
            if ch == "}" && inKey { out += key.hasPrefix("family:") ? "" : tagText(el, field: key.trimmingCharacters(in: .whitespaces), doc: doc); inKey = false; continue }
            if inKey { key.append(ch) } else { out.append(ch) }
        }
        if inKey { out += "{" + key }
        return out.replacingOccurrences(of: "\\n", with: "\n")
    }

    static func tagKind(_ el: BIMElement, field: String) -> TagKind {
        if field.lowercased() == "keynote" { return .keynote }
        switch el.geometry {
        case .opening(let o): return o.kind == .window ? .window : .door
        case .space: return .room
        default: return .element
        }
    }

    /// Anchor point of an element for tag leaders.
    public static func anchor(_ el: BIMElement, doc: ArchiDocument) -> Vec2 {
        switch el.geometry {
        case .opening(let o):
            if let host = doc.element(o.hostWall), let f = WallFrame(host) { return f.pos(o.offset) }
        case .space(let s): return LabelPlacement.pole(of: s.boundary).point
        default: break
        }
        let b = PlanRepresentation.bounds(el, doc: doc)
        return b.isEmpty ? .zero : b.center
    }

    /// Draw items of a tag entity (text geometry with props tagOf/tagField): a symbol around the live text
    /// and a leader to the element when the tag was moved away from it.
    static func tagItems(_ e: Entity, _ t0: TextGeom, doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        let field = e.props["tagField"] ?? "mark"
        guard let id = e.props["tagOf"].flatMap(Int.init), let el = doc.element(id) else {
            return [.text(TextGeom(position: t0.position, height: t0.height, content: "?", halign: .center, valign: .middle), font: "Helvetica", color: color)]
        }
        var t = t0
        t.content = tagText(el, field: field, doc: doc)
        t.halign = .center; t.valign = .middle
        let h = max(t.height, 1e-9)
        let lines = t.content.components(separatedBy: "\n")
        let w = max(Double(lines.map(\.count).max() ?? 1) * h * 0.62, h)
        let bh = h * (1 + 1.5 * Double(lines.count - 1))
        let c = t.position
        let st = StrokeStyle(color: color, lineweight: 0.18)
        var out: [DrawItem] = []
        var outline: [Vec2]
        // Tag family graphics: the family's symbolic lines around the label, flexing with the label size (Width, Height).
        if field.lowercased().hasPrefix("family:"), let def = doc.family(named: String(field.dropFirst(7))), !def.symbolic.isEmpty {
            let r = FamilyEngine.evaluate(def, doc: doc, extra: ["width": w + h, "height": bh + h * 0.8, "textheight": h], origin: Vec3(c.x, c.y, 0))
            var box = BBox2.empty
            for sy in r.symbols {
                out.append(.stroke(points: sy.points, closed: sy.closed, style: sy.dashed ? StrokeStyle(color: color, lineweight: 0.18, dash: [h * 0.4, -h * 0.3]) : st))
                sy.points.forEach { box.add($0) }
            }
            outline = box.isEmpty ? [c] : box.corners
            if lines.count > 1 {
                let top = c + Vec2(0, bh / 2 - h / 2)
                for (i, l) in lines.enumerated() { var lt = t; lt.content = l; lt.position = top - Vec2(0, 1.5 * h * Double(i)); out.append(.text(lt, font: "Helvetica", color: color)) }
            } else { out.append(.text(t, font: "Helvetica", color: color)) }
            let a = anchor(el, doc: doc)
            if outline.count >= 3, !GeometryOps.pointInPolygon(a, outline), e.props["leader"] != "0", a.distance(to: c) > max(w, bh) * 1.2 {
                let best = outline.min { $0.distance(to: a) < $1.distance(to: a) }!
                out.append(.stroke(points: [best, a], closed: false, style: st))
            }
            return out
        }
        switch tagKind(el, field: field) {
        case .door:
            outline = RG.circle(c, max(w, bh) * 0.5 + h * 0.45, segments: 32)
        case .window:
            let r = max(w, bh) * 0.5 + h * 0.5
            outline = (0..<6).map { c + Vec2.polar(r, Double($0) * .pi / 3) }
        case .keynote:
            let s = max(w, bh) / 2 + h * 0.4
            outline = [c + Vec2(-s, -s), c + Vec2(s, -s), c + Vec2(s, s), c + Vec2(-s, s)]
        case .room, .element:
            let hw = w / 2 + h * 0.5, hh = bh / 2 + h * 0.4
            outline = [c + Vec2(-hw, -hh), c + Vec2(hw, -hh), c + Vec2(hw, hh), c + Vec2(-hw, hh)]
        }
        if lines.count > 1 {
            // Multi-line text: first line above the center.
            let top = c + Vec2(0, bh / 2 - h / 2)
            for (i, l) in lines.enumerated() {
                var lt = t; lt.content = l; lt.position = top - Vec2(0, 1.5 * h * Double(i))
                out.append(.text(lt, font: "Helvetica", color: color))
            }
        } else { out.append(.text(t, font: "Helvetica", color: color)) }
        out.append(.stroke(points: outline, closed: true, style: st))
        // Leader when the tag sits away from the element.
        let a = anchor(el, doc: doc)
        if !GeometryOps.pointInPolygon(a, outline), e.props["leader"] != "0" {
            let far = a.distance(to: c)
            if far > max(w, bh) * 1.2 {
                var best = outline[0]
                for p in outline where p.distance(to: a) < best.distance(to: a) { best = p }
                out.append(.stroke(points: [best, a], closed: false, style: st))
            }
        }
        return out
    }

    /// Terrain plan: contour lines (every `major`-th bold and labelled) and the outline.
    static func terrainItems(_ s: SolidGeom, interval: Double, major: Int, doc: ArchiDocument, color: RGBA, lineweight: Double, showLabels: Bool) -> [DrawItem] {
        let v = s.meshVertices, t = s.meshTriangles
        var out: [DrawItem] = []
        let cs = Terrain.contours(vertices: v, triangles: t, interval: interval, minZ: s.origin.z + interval * 0.01)
        let u = 1 / doc.units.mm
        for c in cs {
            let idx = Int((c.z / interval).rounded())
            let isMajor = major > 0 && idx % major == 0
            let st = StrokeStyle(color: isMajor ? color : PlanRepresentation.blend(color, RGBA(0.5, 0.5, 0.5), 0.4), lineweight: isMajor ? max(lineweight, 0.35) : 0.13)
            for l in c.lines where l.count >= 2 {
                out.append(.stroke(points: l, closed: false, style: st))
                if isMajor && showLabels {
                    let (p, dir) = CommandHelpers.pointAlong(l, fraction: 0.5)
                    let rot = DimensionRenderer.readable(dir.angle)
                    out.append(.text(TextGeom(position: p, height: 200 * u, content: fmt(c.z * doc.units.mm / 1000, 2), rotation: rot, halign: .center, valign: .bottom),
                                     font: "Helvetica", color: color))
                }
            }
        }
        // Outline of the surface (boundary edges of the top surface).
        let top = MeshTools.featureEdges(vertices: v, triangles: t, angle: 80).map { $0.map(\.xy) }.filter { $0[0].distance(to: $0[1]) > 1e-9 }
        for e in top { out.append(.stroke(points: e, closed: false, style: StrokeStyle(color: color, lineweight: 0.25))) }
        return out
    }

    // MARK: Section markers

    /// Line of the current section marker (variable SECTION, else the first marker), oriented so the view looks to its left.
    public static func sectionLine(_ doc: ArchiDocument) -> (Vec2, Vec2)? {
        let cur = doc.variable("SECTION")
        let marks = doc.entities.filter { $0.props["sectionMark"] != nil }
        guard let m = marks.first(where: { $0.props["sectionMark"]?.caseInsensitiveCompare(cur ?? "") == .orderedSame }) ?? marks.first,
              case .polyline(let pl) = m.geometry, pl.vertices.count >= 2 else { return nil }
        let a = pl.vertices[0].p, b = pl.vertices[pl.vertices.count - 1].p
        return a.distance(to: b) > 1e-9 ? (a, b) : nil
    }

    /// Plan symbol of a section line: dash-dot line, bubbles with the label at both ends, arrows toward the view.
    static func sectionItems(_ e: Entity, doc: ArchiDocument, color: RGBA, lineweight: Double) -> [DrawItem] {
        guard case .polyline(let pl) = e.geometry, pl.vertices.count >= 2 else { return [] }
        let a = pl.vertices[0].p, b = pl.vertices[pl.vertices.count - 1].p
        guard a.distance(to: b) > 1e-9 else { return [] }
        let u = 1 / doc.units.mm
        let label = e.props["sectionMark"] ?? "A"
        let d = (b - a).normalized, look = d.perp
        let r = 350 * u
        let dash = [1200 * u, -200 * u, 150 * u, -200 * u]
        var out: [DrawItem] = [.stroke(points: [a, b], closed: false, style: StrokeStyle(color: color, lineweight: 0.18, dash: dash)),
                               .stroke(points: [a, a + d * (r * 3)], closed: false, style: StrokeStyle(color: color, lineweight: max(lineweight, 0.5))),
                               .stroke(points: [b - d * (r * 3), b], closed: false, style: StrokeStyle(color: color, lineweight: max(lineweight, 0.5)))]
        for (p, s) in [(a, -1.0), (b, 1.0)] {
            let c = p + d * (s * r)
            out.append(.stroke(points: RG.circle(c, r, segments: 40), closed: true, style: StrokeStyle(color: color, lineweight: 0.25)))
            out.append(.text(TextGeom(position: c, height: r * 0.9, content: label, halign: .center, valign: .middle), font: "Helvetica", color: color))
            // Filled half-disc arrow toward the viewing direction.
            let tip = c + look * (r * 1.9)
            out.append(.fill(loops: [[c + d * r * 0.9, tip, c - d * r * 0.9]], color: color))
        }
        return out
    }
}
