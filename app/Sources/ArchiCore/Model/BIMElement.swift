// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum WallJustification: String, Codable, CaseIterable { case center, left, right }

public struct WallGeom: Codable, Hashable {
    public var start: Vec2; public var end: Vec2
    public var thickness: Double; public var height: Double
    /// Offset of the wall base above its level.
    public var baseOffset: Double
    public var justification: WallJustification
    /// Optional arc: bulge like a polyline segment (0 = straight).
    public var bulge: Double
    /// Wall type name (see ArchiDocument.wallTypes) — nil = generic.
    public var wallType: String?
    /// Horizontal profiles run along the wall faces (cornices, skirting, string courses).
    public var sweeps: [WallSweep]
    public init(start: Vec2, end: Vec2, thickness: Double = 200, height: Double = 3000, baseOffset: Double = 0,
                justification: WallJustification = .center, bulge: Double = 0, wallType: String? = nil, sweeps: [WallSweep] = []) {
        self.start = start; self.end = end; self.thickness = thickness; self.height = height; self.baseOffset = baseOffset
        self.justification = justification; self.bulge = bulge; self.wallType = wallType; self.sweeps = sweeps
    }
    public var length: Double { start.distance(to: end) }
    public var direction: Vec2 { (end - start).normalized }
    /// Offset of the centerline from the drawn line, positive to the left.
    public var centerOffset: Double {
        switch justification { case .center: return 0; case .left: return -thickness / 2; case .right: return thickness / 2 }
    }
    public var centerStart: Vec2 { start + direction.perp * centerOffset }
    public var centerEnd: Vec2 { end + direction.perp * centerOffset }
}

public struct SlabGeom: Codable, Hashable {
    public var boundary: [Vec2]; public var holes: [[Vec2]]
    public var thickness: Double
    /// Top of slab relative to its level.
    public var topOffset: Double
    /// Slope of the top surface in degrees (0 = level). The top rises along `slopeDirection` from `slopeOrigin`.
    public var slope: Double
    /// Direction of rise (radians, plan angle).
    public var slopeDirection: Double
    /// Point where the sloped top is at `topOffset` (nil = first boundary vertex).
    public var slopeOrigin: Vec2?
    public init(boundary: [Vec2], holes: [[Vec2]] = [], thickness: Double = 200, topOffset: Double = 0,
                slope: Double = 0, slopeDirection: Double = 0, slopeOrigin: Vec2? = nil) {
        self.boundary = boundary; self.holes = holes; self.thickness = thickness; self.topOffset = topOffset
        self.slope = slope; self.slopeDirection = slopeDirection; self.slopeOrigin = slopeOrigin
    }
    public var isSloped: Bool { abs(slope) > 1e-9 }
    /// Height of the top surface above the level at a plan point.
    public func topHeight(at p: Vec2) -> Double {
        guard isSloped else { return topOffset }
        let o = slopeOrigin ?? boundary.first ?? .zero
        return topOffset + tan(slope * .pi / 180) * (p - o).dot(Vec2(cos(slopeDirection), sin(slopeDirection)))
    }
}

public struct ColumnGeom: Codable, Hashable {
    public var position: Vec2; public var width: Double; public var depth: Double; public var height: Double
    public var rotation: Double; public var round: Bool; public var baseOffset: Double
    public init(position: Vec2, width: Double = 300, depth: Double = 300, height: Double = 3000, rotation: Double = 0, round: Bool = false, baseOffset: Double = 0) {
        self.position = position; self.width = width; self.depth = depth; self.height = height; self.rotation = rotation; self.round = round; self.baseOffset = baseOffset
    }
}

public struct BeamGeom: Codable, Hashable {
    public var start: Vec2; public var end: Vec2; public var width: Double; public var depth: Double
    /// Top of beam relative to its level.
    public var topOffset: Double
    public init(start: Vec2, end: Vec2, width: Double = 200, depth: Double = 400, topOffset: Double = 3000) {
        self.start = start; self.end = end; self.width = width; self.depth = depth; self.topOffset = topOffset
    }
}

public enum OpeningKind: String, Codable, CaseIterable { case door, window, opening }
public enum DoorStyle: String, Codable, CaseIterable { case single, double, sliding, folding, revolving, garage }
public enum WindowStyle: String, Codable, CaseIterable { case fixed, casement, doubleCasement, sliding, awning, hung }

/// A door, window or empty opening hosted in a wall.
public struct OpeningGeom: Codable, Hashable {
    public var kind: OpeningKind
    public var hostWall: EntityID
    /// Distance along the wall from its start to the opening center.
    public var offset: Double
    public var width: Double; public var height: Double
    /// Height of the bottom edge above the wall base.
    public var sill: Double
    public var flipHand: Bool; public var flipFacing: Bool
    public var doorStyle: DoorStyle; public var windowStyle: WindowStyle
    public var frameWidth: Double
    /// Depth of a niche (recess) for kind `.opening`, measured from the face on the `flipFacing` side; 0 = cut through.
    public var depth: Double
    /// Type (catalog entry in ArchiDocument.openingTypes) this instance follows; nil = untyped.
    public var typeName: String?
    /// Mark shown by door/window tags (e.g. "D01"); nil = none.
    public var mark: String?
    public init(kind: OpeningKind, hostWall: EntityID, offset: Double, width: Double, height: Double, sill: Double = 0,
                flipHand: Bool = false, flipFacing: Bool = false, doorStyle: DoorStyle = .single, windowStyle: WindowStyle = .casement, frameWidth: Double = 50,
                depth: Double = 0, typeName: String? = nil, mark: String? = nil) {
        self.kind = kind; self.hostWall = hostWall; self.offset = offset; self.width = width; self.height = height; self.sill = sill
        self.flipHand = flipHand; self.flipFacing = flipFacing; self.doorStyle = doorStyle; self.windowStyle = windowStyle; self.frameWidth = frameWidth
        self.depth = depth; self.typeName = typeName; self.mark = mark
    }
    public var isNiche: Bool { kind == .opening && depth > 1e-9 }
}

public enum RoofKind: String, Codable, CaseIterable { case flat, shed, gable, hip }
public struct RoofGeom: Codable, Hashable {
    public var boundary: [Vec2]; public var kind: RoofKind
    /// Pitch in degrees.
    public var pitch: Double; public var thickness: Double; public var overhang: Double
    /// Eave height above level.
    public var baseOffset: Double
    /// Gable/shed direction: index of the boundary edge that is an eave (slopes up away from it).
    public var eaveEdge: Int
    public init(boundary: [Vec2], kind: RoofKind = .gable, pitch: Double = 30, thickness: Double = 250, overhang: Double = 500, baseOffset: Double = 3000, eaveEdge: Int = 0) {
        self.boundary = boundary; self.kind = kind; self.pitch = pitch; self.thickness = thickness; self.overhang = overhang; self.baseOffset = baseOffset; self.eaveEdge = eaveEdge
    }
}

public enum StairKind: String, Codable, CaseIterable { case straight, lShape, uShape, spiral }
public struct StairGeom: Codable, Hashable {
    public var start: Vec2; public var direction: Double
    public var width: Double; public var totalRise: Double; public var riserCount: Int; public var treadDepth: Double
    public var kind: StairKind
    public init(start: Vec2, direction: Double = 0, width: Double = 1000, totalRise: Double = 3000, riserCount: Int = 17, treadDepth: Double = 280, kind: StairKind = .straight) {
        self.start = start; self.direction = direction; self.width = width; self.totalRise = totalRise; self.riserCount = riserCount; self.treadDepth = treadDepth; self.kind = kind
    }
    public var riserHeight: Double { totalRise / Double(max(riserCount, 1)) }
    public var runLength: Double { treadDepth * Double(max(riserCount - 1, 0)) }
}

public struct RailingGeom: Codable, Hashable {
    public var path: [Vec2]; public var height: Double; public var baseOffset: Double
    public init(path: [Vec2], height: Double = 1000, baseOffset: Double = 0) { self.path = path; self.height = height; self.baseOffset = baseOffset }
}

public struct SpaceGeom: Codable, Hashable {
    public var boundary: [Vec2]; public var name: String; public var number: String; public var height: Double
    public init(boundary: [Vec2], name: String = "Room", number: String = "", height: Double = 2700) {
        self.boundary = boundary; self.name = name; self.number = number; self.height = height
    }
}

public struct CurtainWallGeom: Codable, Hashable {
    public var start: Vec2; public var end: Vec2; public var height: Double; public var baseOffset: Double
    public var gridU: Double; public var gridV: Double; public var mullionSize: Double
    /// Explicit vertical grid line positions along the wall (nil = uniform `gridU` spacing).
    public var uLines: [Double]?
    /// Explicit horizontal grid line heights above the base (nil = uniform `gridV` spacing).
    public var vLines: [Double]?
    /// Panel overrides keyed "column,row" (0-based from start/bottom): "glass", "solid", "empty".
    public var panels: [String: String]
    public init(start: Vec2, end: Vec2, height: Double = 3000, baseOffset: Double = 0, gridU: Double = 1200, gridV: Double = 1500, mullionSize: Double = 60,
                uLines: [Double]? = nil, vLines: [Double]? = nil, panels: [String: String] = [:]) {
        self.start = start; self.end = end; self.height = height; self.baseOffset = baseOffset; self.gridU = gridU; self.gridV = gridV; self.mullionSize = mullionSize
        self.uLines = uLines; self.vLines = vLines; self.panels = panels
    }
    public var length: Double { start.distance(to: end) }
    /// Interior vertical grid positions (excluding both ends), sorted.
    public var uPositions: [Double] {
        let len = length, m = mullionSize
        if let u = uLines { return u.filter { $0 > m && $0 < len - m }.sorted() }
        var xs: [Double] = []
        if gridU > 1e-9 { var x = gridU; while x < len - m * 2 { xs.append(x); x += gridU } }
        return xs
    }
    /// Interior horizontal grid heights (excluding bottom and top), sorted.
    public var vPositions: [Double] {
        let m = mullionSize
        if let v = vLines { return v.filter { $0 > m && $0 < height - m }.sorted() }
        var zs: [Double] = []
        if gridV > 1e-9 { var z = gridV; while z < height - m * 2 { zs.append(z); z += gridV } }
        return zs
    }
}

/// A profile swept horizontally along one face of a wall (cornice, skirting board, string course).
public struct WallSweep: Codable, Hashable {
    /// Profile name: "rect", "cornice", "skirting", "cove".
    public var profile: String
    /// Projection from the wall face.
    public var depth: Double
    /// Profile height.
    public var height: Double
    /// Bottom of the profile above the wall base.
    public var elevation: Double
    /// +1 = left face (as drawn start→end), −1 = right face.
    public var side: Double
    public var material: String?
    public init(profile: String = "rect", depth: Double = 50, height: Double = 150, elevation: Double = 0, side: Double = 1, material: String? = nil) {
        self.profile = profile; self.depth = depth; self.height = height; self.elevation = elevation; self.side = side; self.material = material
    }
    /// Closed profile in (outward offset, height) coordinates relative to the face at the sweep's elevation.
    public var outline: [(x: Double, z: Double)] {
        let d = max(depth, 1e-6), h = max(height, 1e-6)
        switch profile.lowercased() {
        case "cornice":
            return [(0, 0), (d * 0.3, 0), (d * 0.3, h * 0.35), (d * 0.75, h * 0.55), (d, h * 0.8), (d, h), (0, h)]
        case "skirting", "baseboard":
            return [(0, 0), (d, 0), (d, h * 0.8), (d * 0.5, h), (0, h)]
        case "cove":
            var pts: [(x: Double, z: Double)] = [(0, 0), (d, 0)]
            for i in 1..<8 { let a = Double.pi / 2 * Double(i) / 8; pts.append((d - d * sin(a), h - h * cos(a))) }
            pts.append((0, h))
            return pts
        default:
            return [(0, 0), (d, 0), (d, h), (0, h)]
        }
    }
}

/// Placed component (furniture, fixture, equipment) — a parametric box or a block instance.
public struct ComponentGeom: Codable, Hashable {
    public var category: String; public var position: Vec2; public var rotation: Double
    public var size: Vec3; public var baseOffset: Double; public var block: String?
    public init(category: String = "Furniture", position: Vec2, rotation: Double = 0, size: Vec3 = Vec3(600, 600, 750), baseOffset: Double = 0, block: String? = nil) {
        self.category = category; self.position = position; self.rotation = rotation; self.size = size; self.baseOffset = baseOffset; self.block = block
    }
}

public struct GridLineGeom: Codable, Hashable {
    public var start: Vec2; public var end: Vec2; public var label: String
    public init(start: Vec2, end: Vec2, label: String) { self.start = start; self.end = end; self.label = label }
}

public enum BIMGeometry: Hashable {
    case wall(WallGeom)
    case slab(SlabGeom)
    case column(ColumnGeom)
    case beam(BeamGeom)
    case opening(OpeningGeom)
    case roof(RoofGeom)
    case stair(StairGeom)
    case railing(RailingGeom)
    case space(SpaceGeom)
    case curtainWall(CurtainWallGeom)
    case component(ComponentGeom)
    case gridLine(GridLineGeom)

    public var typeName: String {
        switch self {
        case .wall: return "wall"
        case .slab: return "slab"
        case .column: return "column"
        case .beam: return "beam"
        case .opening(let o): return o.kind.rawValue
        case .roof: return "roof"
        case .stair: return "stair"
        case .railing: return "railing"
        case .space: return "space"
        case .curtainWall: return "curtainWall"
        case .component: return "component"
        case .gridLine: return "grid"
        }
    }
}

extension BIMGeometry: Codable {
    private enum K: String, CodingKey { case type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "wall": self = .wall(try WallGeom(from: decoder))
        case "slab": self = .slab(try SlabGeom(from: decoder))
        case "column": self = .column(try ColumnGeom(from: decoder))
        case "beam": self = .beam(try BeamGeom(from: decoder))
        case "door", "window", "opening": self = .opening(try OpeningGeom(from: decoder))
        case "roof": self = .roof(try RoofGeom(from: decoder))
        case "stair": self = .stair(try StairGeom(from: decoder))
        case "railing": self = .railing(try RailingGeom(from: decoder))
        case "space": self = .space(try SpaceGeom(from: decoder))
        case "curtainWall": self = .curtainWall(try CurtainWallGeom(from: decoder))
        case "component": self = .component(try ComponentGeom(from: decoder))
        case "grid": self = .gridLine(try GridLineGeom(from: decoder))
        case let t: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown element \(t)")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .wall(let g): try g.encode(to: encoder)
        case .slab(let g): try g.encode(to: encoder)
        case .column(let g): try g.encode(to: encoder)
        case .beam(let g): try g.encode(to: encoder)
        case .opening(let g): try g.encode(to: encoder)
        case .roof(let g): try g.encode(to: encoder)
        case .stair(let g): try g.encode(to: encoder)
        case .railing(let g): try g.encode(to: encoder)
        case .space(let g): try g.encode(to: encoder)
        case .curtainWall(let g): try g.encode(to: encoder)
        case .component(let g): try g.encode(to: encoder)
        case .gridLine(let g): try g.encode(to: encoder)
        }
    }
}

/// A building element (Revit-style family instance). Shares the ID space with 2D entities.
public struct BIMElement: Codable, Hashable, Identifiable {
    public var id: EntityID
    public var level: Int
    public var name: String
    public var layer: String
    public var material: String?
    public var geometry: BIMGeometry
    public var props: [String: String]
    public init(id: EntityID = 0, level: Int = 0, name: String = "", layer: String = "A-ELEMENTS", material: String? = nil,
                geometry: BIMGeometry, props: [String: String] = [:]) {
        self.id = id; self.level = level; self.name = name; self.layer = layer; self.material = material; self.geometry = geometry; self.props = props
    }
    public var typeName: String { geometry.typeName }
}


// MARK: - Tolerant decoding (fields added after format 1 are optional in files)

extension WallGeom {
    private enum Keys: String, CodingKey { case start, end, thickness, height, baseOffset, justification, bulge, wallType, sweeps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(start: try c.decode(Vec2.self, forKey: .start), end: try c.decode(Vec2.self, forKey: .end),
                  thickness: try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 200,
                  height: try c.decodeIfPresent(Double.self, forKey: .height) ?? 3000,
                  baseOffset: try c.decodeIfPresent(Double.self, forKey: .baseOffset) ?? 0,
                  justification: try c.decodeIfPresent(WallJustification.self, forKey: .justification) ?? .center,
                  bulge: try c.decodeIfPresent(Double.self, forKey: .bulge) ?? 0,
                  wallType: try c.decodeIfPresent(String.self, forKey: .wallType),
                  sweeps: try c.decodeIfPresent([WallSweep].self, forKey: .sweeps) ?? [])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(thickness, forKey: .thickness)
        try c.encode(height, forKey: .height); try c.encode(baseOffset, forKey: .baseOffset); try c.encode(justification, forKey: .justification)
        try c.encode(bulge, forKey: .bulge); try c.encodeIfPresent(wallType, forKey: .wallType)
        if !sweeps.isEmpty { try c.encode(sweeps, forKey: .sweeps) }
    }
}

extension SlabGeom {
    private enum Keys: String, CodingKey { case boundary, holes, thickness, topOffset, slope, slopeDirection, slopeOrigin }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(boundary: try c.decode([Vec2].self, forKey: .boundary), holes: try c.decodeIfPresent([[Vec2]].self, forKey: .holes) ?? [],
                  thickness: try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 200, topOffset: try c.decodeIfPresent(Double.self, forKey: .topOffset) ?? 0,
                  slope: try c.decodeIfPresent(Double.self, forKey: .slope) ?? 0, slopeDirection: try c.decodeIfPresent(Double.self, forKey: .slopeDirection) ?? 0,
                  slopeOrigin: try c.decodeIfPresent(Vec2.self, forKey: .slopeOrigin))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(boundary, forKey: .boundary); try c.encode(holes, forKey: .holes); try c.encode(thickness, forKey: .thickness); try c.encode(topOffset, forKey: .topOffset)
        if isSloped { try c.encode(slope, forKey: .slope); try c.encode(slopeDirection, forKey: .slopeDirection); try c.encodeIfPresent(slopeOrigin, forKey: .slopeOrigin) }
    }
}

extension OpeningGeom {
    private enum Keys: String, CodingKey { case kind, hostWall, offset, width, height, sill, flipHand, flipFacing, doorStyle, windowStyle, frameWidth, depth, typeName, mark }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var kind = try c.decodeIfPresent(OpeningKind.self, forKey: .kind)
        if kind == nil, let t = try? decoder.container(keyedBy: AnyKey.self).decode(String.self, forKey: AnyKey("type")) { kind = OpeningKind(rawValue: t) }
        self.init(kind: kind ?? .opening, hostWall: try c.decode(EntityID.self, forKey: .hostWall), offset: try c.decode(Double.self, forKey: .offset),
                  width: try c.decode(Double.self, forKey: .width), height: try c.decode(Double.self, forKey: .height),
                  sill: try c.decodeIfPresent(Double.self, forKey: .sill) ?? 0,
                  flipHand: try c.decodeIfPresent(Bool.self, forKey: .flipHand) ?? false, flipFacing: try c.decodeIfPresent(Bool.self, forKey: .flipFacing) ?? false,
                  doorStyle: try c.decodeIfPresent(DoorStyle.self, forKey: .doorStyle) ?? .single, windowStyle: try c.decodeIfPresent(WindowStyle.self, forKey: .windowStyle) ?? .casement,
                  frameWidth: try c.decodeIfPresent(Double.self, forKey: .frameWidth) ?? 50, depth: try c.decodeIfPresent(Double.self, forKey: .depth) ?? 0,
                  typeName: try c.decodeIfPresent(String.self, forKey: .typeName), mark: try c.decodeIfPresent(String.self, forKey: .mark))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey: .kind); try c.encode(hostWall, forKey: .hostWall); try c.encode(offset, forKey: .offset)
        try c.encode(width, forKey: .width); try c.encode(height, forKey: .height); try c.encode(sill, forKey: .sill)
        try c.encode(flipHand, forKey: .flipHand); try c.encode(flipFacing, forKey: .flipFacing); try c.encode(doorStyle, forKey: .doorStyle)
        try c.encode(windowStyle, forKey: .windowStyle); try c.encode(frameWidth, forKey: .frameWidth)
        if depth > 0 { try c.encode(depth, forKey: .depth) }
        try c.encodeIfPresent(typeName, forKey: .typeName); try c.encodeIfPresent(mark, forKey: .mark)
    }
}

extension CurtainWallGeom {
    private enum Keys: String, CodingKey { case start, end, height, baseOffset, gridU, gridV, mullionSize, uLines, vLines, panels }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(start: try c.decode(Vec2.self, forKey: .start), end: try c.decode(Vec2.self, forKey: .end),
                  height: try c.decodeIfPresent(Double.self, forKey: .height) ?? 3000, baseOffset: try c.decodeIfPresent(Double.self, forKey: .baseOffset) ?? 0,
                  gridU: try c.decodeIfPresent(Double.self, forKey: .gridU) ?? 1200, gridV: try c.decodeIfPresent(Double.self, forKey: .gridV) ?? 1500,
                  mullionSize: try c.decodeIfPresent(Double.self, forKey: .mullionSize) ?? 60,
                  uLines: try c.decodeIfPresent([Double].self, forKey: .uLines), vLines: try c.decodeIfPresent([Double].self, forKey: .vLines),
                  panels: try c.decodeIfPresent([String: String].self, forKey: .panels) ?? [:])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(height, forKey: .height); try c.encode(baseOffset, forKey: .baseOffset)
        try c.encode(gridU, forKey: .gridU); try c.encode(gridV, forKey: .gridV); try c.encode(mullionSize, forKey: .mullionSize)
        try c.encodeIfPresent(uLines, forKey: .uLines); try c.encodeIfPresent(vLines, forKey: .vLines)
        if !panels.isEmpty { try c.encode(panels, forKey: .panels) }
    }
}

/// String coding key for ad-hoc lookups.
struct AnyKey: CodingKey {
    var stringValue: String; var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
