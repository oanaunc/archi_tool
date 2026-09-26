// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public typealias EntityID = Int

/// Color reference as in CAD: by layer, by block, AutoCAD Color Index or true color.
public enum ColorRef: Codable, Hashable {
    case byLayer
    case byBlock
    case aci(Int)
    case rgb(UInt8, UInt8, UInt8)

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = ColorRef.parse(s) ?? .byLayer
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(text)
    }
    public var text: String {
        switch self {
        case .byLayer: return "ByLayer"
        case .byBlock: return "ByBlock"
        case .aci(let i): return "\(i)"
        case .rgb(let r, let g, let b): return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
    /// Parses "ByLayer", "ByBlock", "1".."255", "#RRGGBB", "r,g,b" or a color name.
    public static func parse(_ s: String) -> ColorRef? {
        let t = s.trimmingCharacters(in: .whitespaces)
        switch t.lowercased() {
        case "bylayer": return .byLayer
        case "byblock": return .byBlock
        case "red": return .aci(1)
        case "yellow": return .aci(2)
        case "green": return .aci(3)
        case "cyan": return .aci(4)
        case "blue": return .aci(5)
        case "magenta": return .aci(6)
        case "white", "black": return .aci(7)
        case "gray", "grey": return .aci(8)
        default: break
        }
        if let i = Int(t), (0...256).contains(i) { return .aci(i) }
        if t.hasPrefix("#"), t.count == 7, let v = UInt32(t.dropFirst(), radix: 16) {
            return .rgb(UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255))
        }
        let parts = t.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3, parts.allSatisfy({ (0...255).contains($0) }) {
            return .rgb(UInt8(parts[0]), UInt8(parts[1]), UInt8(parts[2]))
        }
        return nil
    }
}

public struct RGBA: Codable, Hashable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public static let white = RGBA(1, 1, 1), black = RGBA(0, 0, 0), accent = RGBA(0.961, 0.773, 0.094)
    public init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255)
    }
    public var hex: String { String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)) }
}

/// Standard AutoCAD Color Index colors 1-9; others approximated from the ACI wheel.
public func aciColor(_ i: Int) -> RGBA {
    switch i {
    case 1: return RGBA(1, 0, 0)
    case 2: return RGBA(1, 1, 0)
    case 3: return RGBA(0, 1, 0)
    case 4: return RGBA(0, 1, 1)
    case 5: return RGBA(0, 0, 1)
    case 6: return RGBA(1, 0, 1)
    case 7: return RGBA(1, 1, 1)
    case 8: return RGBA(0.5, 0.5, 0.5)
    case 9: return RGBA(0.75, 0.75, 0.75)
    case 250...255: let g = 0.2 + Double(i - 250) * 0.16; return RGBA(g, g, g)
    case 10...249:
        let hue = Double((i - 10) / 10) / 24.0
        let shade = [1.0, 1.0, 0.8, 0.8, 0.6, 0.6, 0.5, 0.5, 0.3, 0.3][(i - 10) % 10]
        let sat = (i % 2 == 0) ? 1.0 : 0.5
        return hsv(hue, sat, shade)
    default: return RGBA(1, 1, 1)
    }
}

func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
    let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch i {
    case 0: return RGBA(v, t, p)
    case 1: return RGBA(q, v, p)
    case 2: return RGBA(p, v, t)
    case 3: return RGBA(p, q, v)
    case 4: return RGBA(t, p, v)
    default: return RGBA(v, p, q)
    }
}

// MARK: - Geometry payloads

public struct PolyVertex: Codable, Hashable {
    public var p: Vec2
    /// Bulge = tan(sweep/4) of the arc to the next vertex; 0 = straight.
    public var bulge: Double
    public init(_ p: Vec2, bulge: Double = 0) { self.p = p; self.bulge = bulge }
}

public struct LineGeom: Codable, Hashable { public var a: Vec2; public var b: Vec2
    public init(_ a: Vec2, _ b: Vec2) { self.a = a; self.b = b } }
public struct CircleGeom: Codable, Hashable { public var center: Vec2; public var radius: Double
    public init(_ c: Vec2, _ r: Double) { center = c; radius = r } }
/// Counter-clockwise arc from start to end angle (radians).
public struct ArcGeom: Codable, Hashable {
    public var center: Vec2; public var radius: Double; public var start: Double; public var end: Double
    public init(_ c: Vec2, _ r: Double, _ s: Double, _ e: Double) { center = c; radius = r; start = s; end = e }
    public var sweep: Double { let s = normAngle(end - start); return s < geomEpsilon ? 2 * .pi : s }
    public var startPoint: Vec2 { center + Vec2.polar(radius, start) }
    public var endPoint: Vec2 { center + Vec2.polar(radius, end) }
    public var midPoint: Vec2 { center + Vec2.polar(radius, start + sweep / 2) }
}
public struct EllipseGeom: Codable, Hashable {
    public var center: Vec2; public var majorAxis: Vec2; public var ratio: Double
    public var start: Double; public var end: Double
    public init(center: Vec2, majorAxis: Vec2, ratio: Double, start: Double = 0, end: Double = 2 * .pi) {
        self.center = center; self.majorAxis = majorAxis; self.ratio = ratio; self.start = start; self.end = end
    }
    public var isFull: Bool { abs(normAngle(end - start)) < 1e-9 || abs(end - start - 2 * .pi) < 1e-9 }
    public func point(at t: Double) -> Vec2 {
        let minor = majorAxis.perp * ratio
        return center + majorAxis * cos(t) + minor * sin(t)
    }
}
public struct PolylineGeom: Codable, Hashable {
    public var vertices: [PolyVertex]; public var closed: Bool; public var width: Double
    public init(_ v: [PolyVertex], closed: Bool = false, width: Double = 0) { vertices = v; self.closed = closed; self.width = width }
    public init(points: [Vec2], closed: Bool = false) { self.init(points.map { PolyVertex($0) }, closed: closed) }
}
public struct SplineGeom: Codable, Hashable {
    public var degree: Int; public var controlPoints: [Vec2]; public var knots: [Double]
    public var weights: [Double]?; public var fitPoints: [Vec2]; public var closed: Bool
    public init(degree: Int = 3, controlPoints: [Vec2], knots: [Double] = [], weights: [Double]? = nil, fitPoints: [Vec2] = [], closed: Bool = false) {
        self.degree = degree; self.controlPoints = controlPoints; self.knots = knots; self.weights = weights; self.fitPoints = fitPoints; self.closed = closed
    }
}
public enum HAlign: String, Codable { case left, center, right }
public enum VAlign: String, Codable { case baseline, bottom, middle, top }
public struct TextGeom: Codable, Hashable {
    public var position: Vec2; public var height: Double; public var rotation: Double
    public var content: String; public var style: String
    public var halign: HAlign; public var valign: VAlign
    /// Wrap width for multiline text (0 = single line / no wrap).
    public var width: Double
    public init(position: Vec2, height: Double, content: String, rotation: Double = 0, style: String = "Standard",
                halign: HAlign = .left, valign: VAlign = .baseline, width: Double = 0) {
        self.position = position; self.height = height; self.content = content; self.rotation = rotation
        self.style = style; self.halign = halign; self.valign = valign; self.width = width
    }
}
public enum DimKind: String, Codable, CaseIterable { case linear, aligned, angular, radius, diameter, ordinate, arcLength }
public struct DimensionGeom: Codable, Hashable {
    public var kind: DimKind
    /// Definition points. linear/aligned: p1,p2 measured, p3 dimension line location.
    /// radius/diameter: p1 center, p2 point on curve, p3 text location.
    /// angular: p1 vertex, p2 & p3 points on the legs, p4 arc location.
    public var points: [Vec2]
    /// Fixed angle for linear dimensions (0 = horizontal, π/2 = vertical, nil = automatic).
    public var rotation: Double?
    public var textOverride: String?
    public var style: String
    public init(kind: DimKind, points: [Vec2], rotation: Double? = nil, textOverride: String? = nil, style: String = "Standard") {
        self.kind = kind; self.points = points; self.rotation = rotation; self.textOverride = textOverride; self.style = style
    }
}
public struct HatchGeom: Codable, Hashable {
    public var loops: [[PolyVertex]]; public var pattern: String; public var scale: Double; public var angle: Double
    public var fill: ColorRef?
    public init(loops: [[PolyVertex]], pattern: String = "SOLID", scale: Double = 1, angle: Double = 0, fill: ColorRef? = nil) {
        self.loops = loops; self.pattern = pattern; self.scale = scale; self.angle = angle; self.fill = fill
    }
}
public struct InsertGeom: Codable, Hashable {
    public var block: String; public var position: Vec2; public var scale: Vec2; public var rotation: Double
    public var attributes: [String: String]
    public init(block: String, position: Vec2, scale: Vec2 = Vec2(1, 1), rotation: Double = 0, attributes: [String: String] = [:]) {
        self.block = block; self.position = position; self.scale = scale; self.rotation = rotation; self.attributes = attributes
    }
    public var transform: Transform2D {
        Transform2D.translation(position) * Transform2D.rotation(rotation) * Transform2D.scale(scale.x, scale.y)
    }
}
public struct LeaderGeom: Codable, Hashable {
    public var points: [Vec2]; public var text: String; public var textHeight: Double
    public init(points: [Vec2], text: String, textHeight: Double = 2.5) { self.points = points; self.text = text; self.textHeight = textHeight }
}
public struct ImageGeom: Codable, Hashable {
    public var path: String; public var origin: Vec2; public var size: Vec2; public var rotation: Double
    public init(path: String, origin: Vec2, size: Vec2, rotation: Double = 0) { self.path = path; self.origin = origin; self.size = size; self.rotation = rotation }
}
public struct TableGeom: Codable, Hashable {
    public var origin: Vec2; public var columnWidths: [Double]; public var rowHeight: Double; public var cells: [[String]]; public var textHeight: Double
    /// Cell background colours keyed "row,column" (conditional formatting of placed schedules).
    public var fills: [String: RGBA]?
    public init(origin: Vec2, columnWidths: [Double], rowHeight: Double, cells: [[String]], textHeight: Double = 2.5) {
        self.origin = origin; self.columnWidths = columnWidths; self.rowHeight = rowHeight; self.cells = cells; self.textHeight = textHeight
    }
}
/// A 3D solid primitive or extrusion drawn in model space (not a BIM element).
public struct SolidGeom: Codable, Hashable {
    public enum Kind: String, Codable { case box, cylinder, sphere, cone, extrusion, revolve, mesh }
    public var kind: Kind
    public var origin: Vec3
    public var size: Vec3               // box dims; cylinder/cone: (radius, radius2, height); sphere: (r,_,_)
    public var profile: [Vec2]          // extrusion/revolve profile (local XY)
    public var height: Double           // extrusion height or revolve angle (radians)
    public var rotation: Double         // about Z
    public var meshVertices: [Vec3]
    public var meshTriangles: [Int]
    /// Feature history (solid history light): base solid and the ordered boolean features that produced this solid.
    public var history: SolidHistory?
    /// Associative source (sweep of profile entities along a path entity): regenerated when the sources change.
    public var source: SolidSource?
    public init(kind: Kind, origin: Vec3, size: Vec3 = Vec3(1, 1, 1), profile: [Vec2] = [], height: Double = 0, rotation: Double = 0,
                meshVertices: [Vec3] = [], meshTriangles: [Int] = [], history: SolidHistory? = nil, source: SolidSource? = nil) {
        self.kind = kind; self.origin = origin; self.size = size; self.profile = profile; self.height = height; self.rotation = rotation
        self.meshVertices = meshVertices; self.meshTriangles = meshTriangles; self.history = history; self.source = source
    }
}

/// One step of a solid's feature history.
public struct SolidFeature: Codable, Hashable {
    public enum Op: String, Codable, CaseIterable { case union, subtract, intersect }
    public var op: Op
    /// Index of the tool solid in `SolidHistory.solids`.
    public var tool: Int
    public var suppressed: Bool
    public var name: String
    public init(op: Op, tool: Int, suppressed: Bool = false, name: String = "") { self.op = op; self.tool = tool; self.suppressed = suppressed; self.name = name }
}

/// Feature list of a solid: `solids[0]` is the base, features apply tools in order; the solid's mesh is the evaluated result.
public struct SolidHistory: Codable, Hashable {
    public var solids: [SolidGeom]
    public var features: [SolidFeature]
    public init(base: SolidGeom, features: [SolidFeature] = [], tools: [SolidGeom] = []) {
        var b = base; b.history = nil
        solids = [b] + tools.map { var t = $0; t.history = nil; return t }
        self.features = features
    }
    public var base: SolidGeom { solids[0] }
}

/// Associative source of a generated solid.
public struct SolidSource: Codable, Hashable {
    public enum Kind: String, Codable { case sweep, loft, pipe }
    public var kind: Kind
    /// Profile entity ids (sweep: one profile; loft: sections in order).
    public var profiles: [EntityID]
    /// Path entity (sweep).
    public var path: EntityID?
    /// Path elevation (sweep, pipe) or section heights (loft); pipe: heights = [outer radius, wall thickness].
    public var elevation: Double
    public var heights: [Double]
    public var twist: Double
    public var endScale: Double
    /// Snapshot of the source geometries the solid was built from (regenerated when they differ).
    public var inputs: [Geometry]
    public init(kind: Kind, profiles: [EntityID], path: EntityID? = nil, elevation: Double = 0, heights: [Double] = [], twist: Double = 0, endScale: Double = 1, inputs: [Geometry] = []) {
        self.kind = kind; self.profiles = profiles; self.path = path; self.elevation = elevation; self.heights = heights
        self.twist = twist; self.endScale = endScale; self.inputs = inputs
    }
}

public enum Geometry: Hashable {
    case point(Vec2)
    case line(LineGeom)
    case circle(CircleGeom)
    case arc(ArcGeom)
    case ellipse(EllipseGeom)
    case polyline(PolylineGeom)
    case spline(SplineGeom)
    case text(TextGeom)
    case dimension(DimensionGeom)
    case hatch(HatchGeom)
    case insert(InsertGeom)
    case leader(LeaderGeom)
    case image(ImageGeom)
    case table(TableGeom)
    case solid(SolidGeom)

    public var typeName: String {
        switch self {
        case .point: return "point"
        case .line: return "line"
        case .circle: return "circle"
        case .arc: return "arc"
        case .ellipse: return "ellipse"
        case .polyline: return "polyline"
        case .spline: return "spline"
        case .text: return "text"
        case .dimension: return "dimension"
        case .hatch: return "hatch"
        case .insert: return "insert"
        case .leader: return "leader"
        case .image: return "image"
        case .table: return "table"
        case .solid: return "solid"
        }
    }
}

extension Geometry: Codable {
    private enum K: String, CodingKey { case type, p }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "point": self = .point(try c.decode(Vec2.self, forKey: .p))
        case "line": self = .line(try LineGeom(from: decoder))
        case "circle": self = .circle(try CircleGeom(from: decoder))
        case "arc": self = .arc(try ArcGeom(from: decoder))
        case "ellipse": self = .ellipse(try EllipseGeom(from: decoder))
        case "polyline": self = .polyline(try PolylineGeom(from: decoder))
        case "spline": self = .spline(try SplineGeom(from: decoder))
        case "text": self = .text(try TextGeom(from: decoder))
        case "dimension": self = .dimension(try DimensionGeom(from: decoder))
        case "hatch": self = .hatch(try HatchGeom(from: decoder))
        case "insert": self = .insert(try InsertGeom(from: decoder))
        case "leader": self = .leader(try LeaderGeom(from: decoder))
        case "image": self = .image(try ImageGeom(from: decoder))
        case "table": self = .table(try TableGeom(from: decoder))
        case "solid": self = .solid(try SolidGeom(from: decoder))
        case let t: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown geometry \(t)")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .point(let p): try c.encode(p, forKey: .p)
        case .line(let g): try g.encode(to: encoder)
        case .circle(let g): try g.encode(to: encoder)
        case .arc(let g): try g.encode(to: encoder)
        case .ellipse(let g): try g.encode(to: encoder)
        case .polyline(let g): try g.encode(to: encoder)
        case .spline(let g): try g.encode(to: encoder)
        case .text(let g): try g.encode(to: encoder)
        case .dimension(let g): try g.encode(to: encoder)
        case .hatch(let g): try g.encode(to: encoder)
        case .insert(let g): try g.encode(to: encoder)
        case .leader(let g): try g.encode(to: encoder)
        case .image(let g): try g.encode(to: encoder)
        case .table(let g): try g.encode(to: encoder)
        case .solid(let g): try g.encode(to: encoder)
        }
    }
}

/// A drawable object in model space or in a block definition.
public struct Entity: Codable, Hashable, Identifiable {
    public var id: EntityID
    public var layer: String
    public var color: ColorRef
    /// nil = ByLayer
    public var linetype: String?
    /// Line weight in millimetres; nil = ByLayer
    public var lineweight: Double?
    public var geometry: Geometry
    /// Free-form user properties (also used by scripts/agents).
    public var props: [String: String]
    public init(id: EntityID = 0, layer: String = "0", color: ColorRef = .byLayer, linetype: String? = nil,
                lineweight: Double? = nil, geometry: Geometry, props: [String: String] = [:]) {
        self.id = id; self.layer = layer; self.color = color; self.linetype = linetype
        self.lineweight = lineweight; self.geometry = geometry; self.props = props
    }
    public var typeName: String { geometry.typeName }
}
