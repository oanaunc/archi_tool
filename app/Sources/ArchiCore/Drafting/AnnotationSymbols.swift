// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Drafting section / elevation / detail symbols (ANN-053): parametric block references with attributes, so the numbers
/// are edited with ATTEDIT, the symbols scale with the annotation scale and they move, copy and explode like any block.
/// Block definitions are unit-sized (bubble diameter 1) and created on demand.
public enum AnnotationSymbols {
    public static let sectionHead = "_SYM_SECTION"
    public static let elevation = "_SYM_ELEVATION"
    public static let detail = "_SYM_DETAIL"
    public static let prop = "annosymbol"

    static func attr(_ tag: String, _ p: Vec2, _ h: Double) -> Entity {
        var e = Entity(id: 0, layer: "0", geometry: .text(TextGeom(position: p, height: h, content: tag, halign: .center, valign: .middle)))
        e.props["attdef"] = tag
        return e
    }
    static func ent(_ g: Geometry) -> Entity { Entity(id: 0, layer: "0", geometry: g) }
    static func tri(_ pts: [Vec2]) -> Entity { ent(.hatch(HatchGeom(loops: [pts.map { PolyVertex($0) }], pattern: "SOLID"))) }

    /// Bubble split horizontally: NUM above, SHEET below.
    static func bubble() -> [Entity] {
        [ent(.circle(CircleGeom(.zero, 0.5))), ent(.line(LineGeom(Vec2(-0.5, 0), Vec2(0.5, 0)))),
         attr("NUM", Vec2(0, 0.22), 0.26), attr("SHEET", Vec2(0, -0.22), 0.2)]
    }
    /// Block definitions: section head (bubble + solid arrow pointing +Y, the view direction), elevation marker (bubble +
    /// solid pointer towards +Y), detail bubble.
    public static func definitions() -> [Block] {
        let arrow = tri([Vec2(-0.5, 0), Vec2(0.5, 0), Vec2(0, 0.95)])
        let pointer = tri([Vec2(-0.354, 0.354), Vec2(0, 0.85), Vec2(0.354, 0.354)])
        return [Block(name: sectionHead, entities: [arrow] + bubble(), description: "Section head (ANN-053)"),
                Block(name: elevation, entities: [pointer] + bubble(), description: "Elevation marker (ANN-053)"),
                Block(name: detail, entities: bubble(), description: "Detail bubble (ANN-053)")]
    }
    public static func ensureBlocks(_ doc: inout ArchiDocument) {
        for b in definitions() where doc.blocks[b.name] == nil { doc.blocks[b.name] = b }
    }
    /// Bubble diameter in drawing units: `paper` mm on paper at the current annotation scale.
    public static func size(_ doc: ArchiDocument, paper: Double = 12) -> Double { Annotative.modelHeight(paper: paper, doc: doc) }

    static func insert(_ block: String, at p: Vec2, size: Double, rotation: Double, num: String, sheet: String) -> Entity {
        var e = Entity(id: 0, layer: "0", geometry: .insert(InsertGeom(block: block, position: p, scale: Vec2(size, size), rotation: rotation,
                                                                     attributes: ["NUM": num, "SHEET": sheet])))
        e.props[prop] = block
        return e
    }

    /// Section symbol: a cut line from `a` to `b` with heads at both ends looking towards `side` (a point on the viewing
    /// side). Returns the entities (line + two heads) to add, all in one group.
    public static func section(from a: Vec2, to b: Vec2, side: Vec2, size: Double, num: String, sheet: String) -> [Entity] {
        let d = (b - a).normalized
        guard d != .zero, size > 0 else { return [] }
        var n = d.perp
        if (side - a).dot(n) < 0 { n = n * -1 }
        let rot = n.angle - .pi / 2
        var line = ent(.line(LineGeom(a, b)))
        line.lineweight = 0.5
        line.props[prop] = "sectionLine"
        let r = size / 2
        return [line, insert(sectionHead, at: a - d * r, size: size, rotation: rot, num: num, sheet: sheet),
                insert(sectionHead, at: b + d * r, size: size, rotation: rot, num: num, sheet: sheet)]
    }
    /// Elevation marker at `p` looking towards `direction`.
    public static func elevationMark(at p: Vec2, direction: Vec2, size: Double, num: String, sheet: String) -> Entity {
        insert(elevation, at: p, size: size, rotation: direction.angle - .pi / 2, num: num, sheet: sheet)
    }
    /// Detail bubble at `p` (with an optional leader line to `target`).
    public static func detailMark(at p: Vec2, size: Double, num: String, sheet: String, target: Vec2? = nil) -> [Entity] {
        var out = [insert(detail, at: p, size: size, rotation: 0, num: num, sheet: sheet)]
        if let t = target, t.distance(to: p) > size / 2 {
            var l = ent(.line(LineGeom(p + (t - p).normalized * (size / 2), t)))
            l.props[prop] = "detailLeader"
            out.append(l)
        }
        return out
    }
}
