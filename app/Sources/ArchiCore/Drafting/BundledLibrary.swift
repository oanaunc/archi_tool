// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Bundled block library (BLK-037) and symbol-based annotation library (BLK-042): free, procedurally drawn 2D
/// architectural blocks in millimetres — furniture, sanitary, kitchen, vehicles, people, trees — and annotation symbols
/// (north arrows, section / elevation / detail marks, scale bar, A3 title block). LIBRARYINSTALL writes them as .archi
/// drawings into a folder, where the block library panel and BLOCKLIBRARY browse, search and insert them.
public enum BundledLibrary {
    typealias G = Geometry
    static func e(_ g: G) -> Entity { Entity(id: 0, layer: "0", geometry: g) }
    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> G { .polyline(PolylineGeom(points: [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)], closed: true)) }
    /// Rectangle with rounded corners of radius r.
    static func rrect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r0: Double) -> G {
        let r = min(r0, w / 2, h / 2), b = tan(Double.pi / 8)
        let v: [PolyVertex] = [PolyVertex(Vec2(x + r, y)), PolyVertex(Vec2(x + w - r, y), bulge: b), PolyVertex(Vec2(x + w, y + r)), PolyVertex(Vec2(x + w, y + h - r), bulge: b),
                               PolyVertex(Vec2(x + w - r, y + h)), PolyVertex(Vec2(x + r, y + h), bulge: b), PolyVertex(Vec2(x, y + h - r)), PolyVertex(Vec2(x, y + r), bulge: b)]
        return .polyline(PolylineGeom(v, closed: true))
    }
    static func circle(_ x: Double, _ y: Double, _ r: Double) -> G { .circle(CircleGeom(Vec2(x, y), r)) }
    static func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> G { .line(LineGeom(Vec2(x0, y0), Vec2(x1, y1))) }
    static func ellipse(_ x: Double, _ y: Double, _ a: Double, _ b: Double) -> G { .ellipse(EllipseGeom(center: Vec2(x, y), majorAxis: Vec2(a, 0), ratio: b / a)) }
    static func block(_ name: String, _ base: Vec2 = .zero, _ desc: String, _ gs: [G]) -> Block { Block(name: name, basePoint: base, entities: gs.map(e), description: desc) }

    static func chair(_ x: Double, _ y: Double, rot: Double = 0) -> [G] {
        let t = Transform2D.rotation(rot, around: Vec2(x, y))
        return [rrect(x - 225, y - 225, 450, 450, 40), rect(x - 225, y + 175, 450, 80)].map { GeometryOps.transform($0, t) }
    }
    /// Deciduous tree crown: a scalloped circle.
    static func crown(_ r: Double, lobes: Int) -> G {
        let pts = (0..<lobes).map { Vec2.polar(r, Double($0) * 2 * .pi / Double(lobes)) }
        let b = tan(Double.pi / Double(lobes) * 0.9)
        return .polyline(PolylineGeom(pts.map { PolyVertex($0, bulge: b) }, closed: true))
    }

    // MARK: Categories

    static var furniture: [Block] { [
        block("Bed single 900x2000", .zero, "Single bed with pillow", [rect(0, 0, 900, 2000), rrect(100, 1650, 700, 280, 60), line(0, 1550, 900, 1550)]),
        block("Bed double 1600x2000", .zero, "Double bed with two pillows", [rect(0, 0, 1600, 2000), rrect(80, 1650, 680, 280, 60), rrect(840, 1650, 680, 280, 60), line(0, 1550, 1600, 1550)]),
        block("Sofa 3 seat 2100x900", .zero, "Three-seat sofa", [rrect(0, 0, 2100, 900, 80), rect(150, 0, 1800, 650), line(750, 0, 750, 650), line(1350, 0, 1350, 650)]),
        block("Armchair 850x850", .zero, "Armchair", [rrect(0, 0, 850, 850, 80), rect(150, 0, 550, 650)]),
        block("Chair 450x500", Vec2(0, 0), "Dining chair (centre base point)", chair(0, 0)),
        block("Dining table 6 seats 1800x900", Vec2(900, 450), "Rectangular dining table with six chairs",
              [rect(0, 0, 1800, 900)] + chair(400, -350, rot: .pi) + chair(900, -350, rot: .pi) + chair(1400, -350, rot: .pi)
              + chair(400, 1250) + chair(900, 1250) + chair(1400, 1250)),
        block("Round table 1200", .zero, "Round table with four chairs",
              [circle(0, 0, 600)] + chair(0, 850) + chair(0, -850, rot: .pi) + chair(850, 0, rot: -.pi / 2) + chair(-850, 0, rot: .pi / 2)),
        block("Desk 1400x700", .zero, "Desk with chair", [rect(0, 0, 1400, 700)] + chair(700, -300, rot: .pi)),
        block("Wardrobe 1200x600", .zero, "Wardrobe with hanging rail", [rect(0, 0, 1200, 600), line(0, 300, 1200, 300), line(600, 0, 600, 60)]),
        block("Bookcase 900x350", .zero, "Bookcase", [rect(0, 0, 900, 350), line(0, 30, 900, 30)]),
    ] }
    static var sanitary: [Block] { [
        block("WC 380x700", Vec2(190, 700), "Toilet with cistern (base at wall)", [rect(0, 480, 380, 220), ellipse(190, 250, 190, 250), ellipse(190, 250, 130, 180)]),
        block("Basin 550x450", Vec2(275, 450), "Wash basin (base at wall)", [rrect(0, 0, 550, 450, 60), ellipse(275, 200, 200, 140), circle(275, 380, 20)]),
        block("Bath 1700x750", .zero, "Bath tub", [rect(0, 0, 1700, 750), rrect(60, 60, 1580, 630, 250), circle(1500, 375, 30)]),
        block("Shower 900x900", .zero, "Shower tray", [rect(0, 0, 900, 900), line(0, 0, 900, 900), line(900, 0, 0, 900), circle(450, 450, 40)]),
        block("Bidet 380x560", Vec2(190, 560), "Bidet (base at wall)", [ellipse(190, 250, 190, 280), ellipse(190, 250, 120, 190), circle(190, 480, 20)]),
        block("Urinal 400x350", Vec2(200, 350), "Urinal (base at wall)", [rrect(0, 0, 400, 350, 120), ellipse(200, 170, 130, 110)]),
    ] }
    static var kitchen: [Block] { [
        block("Sink double 1200x600", .zero, "Double bowl sink", [rect(0, 0, 1200, 600), rrect(60, 60, 500, 440, 50), rrect(640, 60, 500, 440, 50), circle(600, 540, 25)]),
        block("Hob 600x600", .zero, "Four-burner hob", [rect(0, 0, 600, 600), circle(150, 150, 100), circle(450, 150, 80), circle(150, 450, 80), circle(450, 450, 100)]),
        block("Fridge 600x650", .zero, "Refrigerator", [rect(0, 0, 600, 650), line(0, 60, 600, 60), .text(TextGeom(position: Vec2(300, 350), height: 100, content: "REF", halign: .center, valign: .middle))]),
        block("Oven 600x600", .zero, "Oven", [rect(0, 0, 600, 600), rect(60, 60, 480, 400), .text(TextGeom(position: Vec2(300, 530), height: 80, content: "OV", halign: .center, valign: .middle))]),
        block("Dishwasher 600x600", .zero, "Dishwasher", [rect(0, 0, 600, 600), .text(TextGeom(position: Vec2(300, 300), height: 100, content: "DW", halign: .center, valign: .middle))]),
    ] }
    static var vehicles: [Block] { [
        block("Car 4500x1800", .zero, "Passenger car, plan", [rrect(0, 0, 4500, 1800, 350), rrect(1300, 150, 2000, 1500, 250), line(1300, 150, 1000, 100), line(1300, 1650, 1000, 1700), line(3300, 150, 3700, 120), line(3300, 1650, 3700, 1680)]),
        block("Bicycle 1800x600", .zero, "Bicycle, plan", [rrect(0, 250, 700, 100, 50), rrect(1100, 250, 700, 100, 50), line(700, 300, 1100, 300), line(1500, 0, 1500, 600)]),
        block("Motorcycle 2100x800", .zero, "Motorcycle, plan", [rrect(0, 300, 700, 200, 100), rrect(1400, 300, 700, 200, 100), rrect(600, 250, 900, 300, 120), line(1500, 0, 1500, 800)]),
        block("Parking bay 2500x5000", .zero, "Parking bay outline", [line(0, 0, 0, 5000), line(2500, 0, 2500, 5000), line(0, 0, 2500, 0)]),
    ] }
    static var people: [Block] { [
        block("Person plan", .zero, "Person seen from above", [ellipse(0, 0, 280, 130), circle(0, 0, 110)]),
        block("Person elevation 1750", .zero, "Standing person, elevation", [circle(0, 1620, 120), line(0, 1500, 0, 900), line(0, 900, -120, 0), line(0, 900, 120, 0), line(0, 1350, -250, 950), line(0, 1350, 250, 950)]),
        block("Wheelchair 700x1200", .zero, "Wheelchair, plan (turning circle 1500)", [rrect(-350, -600, 700, 1200, 80), line(-350, -300, -350, 400), line(350, -300, 350, 400), .circle(CircleGeom(.zero, 750))]),
    ] }
    static var trees: [Block] { [
        block("Tree deciduous 5000", .zero, "Deciduous tree, crown 5 m", [crown(2500, lobes: 12), circle(0, 0, 150)]),
        block("Tree deciduous 3000", .zero, "Deciduous tree, crown 3 m", [crown(1500, lobes: 10), circle(0, 0, 100)]),
        block("Tree conifer 3000", .zero, "Conifer, crown 3 m", [circle(0, 0, 1500)] + (0..<12).map { i in let p = Vec2.polar(1500, Double(i) * .pi / 6); return .line(LineGeom(.zero, p)) }),
        block("Shrub 1200", .zero, "Shrub", [crown(600, lobes: 8)]),
    ] }
    static var annotation: [Block] {
        var out: [Block] = [
            block("North arrow", .zero, "North arrow, 1:100 (12 mm on paper)", DraftSymbols.northArrow(center: .zero, size: 1200, angle: .pi / 2)),
            block("Scale bar 1-100", .zero, "Scale bar 0–5 m at 1:100", DraftSymbols.scaleBar(origin: .zero, segment: 1000, count: 5, height: 150, labelFactor: 0.001, unitLabel: "m")),
        ]
        // Section, elevation and detail marks drawn at 1:100 (12 mm bubbles), attributes NUM / SHEET kept.
        let s = 1200.0
        for d in AnnotationSymbols.definitions() {
            let t = Transform2D.scale(s, s)
            let ents = d.entities.map { en -> Entity in
                var c = en; c.geometry = GeometryOps.transform(en.geometry, t)
                if case .text(var tx) = c.geometry { tx.height = tx.height * s; c.geometry = .text(tx) }
                return c
            }
            let title = d.name == AnnotationSymbols.sectionHead ? "Section mark" : d.name == AnnotationSymbols.elevation ? "Elevation mark" : "Detail mark"
            out.append(Block(name: title, basePoint: .zero, entities: ents, description: title + " 1:100 with NUM / SHEET attributes"))
        }
        // A3 landscape title block (paper size in mm) with attribute fields.
        var tb: [Entity] = [e(rect(0, 0, 420, 297)), e(rect(10, 10, 400, 277)), e(rect(230, 10, 180, 50)), e(line(230, 35, 410, 35)), e(line(320, 10, 320, 35))]
        for (tag, x, y, h) in [("PROJECT", 235.0, 47.0, 6.0), ("DRAWING", 235, 22, 4), ("SCALE", 235, 14, 3), ("SHEET", 325, 22, 5), ("DATE", 325, 14, 3)] {
            var t = Entity(id: 0, layer: "0", geometry: .text(TextGeom(position: Vec2(x, y), height: h, content: tag)))
            t.props["attdef"] = tag
            tb.append(t)
        }
        out.append(Block(name: "Title block A3", basePoint: .zero, entities: tb, description: "A3 landscape title block (paper mm) with PROJECT / DRAWING / SCALE / SHEET / DATE"))
        return out
    }

    /// Library drawings: file name → blocks.
    public static var categories: [(name: String, blocks: [Block])] {
        [("Furniture", furniture), ("Sanitary", sanitary), ("Kitchen", kitchen), ("Vehicles", vehicles), ("People", people), ("Trees", trees),
         ("Annotation Symbols", annotation)]
    }
    /// One drawing per category holding its blocks (and one reference of each laid out in a row, for the preview).
    public static func document(_ category: String) -> ArchiDocument? {
        guard let c = categories.first(where: { $0.name.caseInsensitiveCompare(category) == .orderedSame }) else { return nil }
        var d = ArchiDocument()
        var x = 0.0
        for b in c.blocks {
            d.blocks[b.name] = b
            let bb = b.entities.reduce(BBox2.empty) { var r = $0; r.add(GeometryOps.bounds($1.geometry, doc: nil)); return r }
            let w = bb.isEmpty ? 1000 : bb.width
            d.add(.insert(InsertGeom(block: b.name, position: Vec2(x - (bb.isEmpty ? 0 : bb.min.x) + b.basePoint.x, -(bb.isEmpty ? 0 : bb.min.y) + b.basePoint.y))), layer: "0")
            x += w + 500
        }
        d.info.name = "Oanarina Archi Library — \(c.name)"
        return d
    }
    /// Writes every category drawing into `folder` (created when missing). Returns the files written.
    @discardableResult
    public static func install(to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var out: [URL] = []
        for c in categories {
            guard let d = document(c.name) else { continue }
            let url = folder.appendingPathComponent(c.name).appendingPathExtension(ArchiFile.fileExtension)
            try ArchiFile.encode(d).write(to: url, options: .atomic)
            out.append(url)
        }
        return out
    }
    /// Default install folder.
    public static var defaultFolder: String { "~/Documents/Oanarina Archi Library" }
}
