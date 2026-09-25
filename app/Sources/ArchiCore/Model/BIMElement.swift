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
    public init(start: Vec2, end: Vec2, thickness: Double = 200, height: Double = 3000, baseOffset: Double = 0,
                justification: WallJustification = .center, bulge: Double = 0, wallType: String? = nil) {
        self.start = start; self.end = end; self.thickness = thickness; self.height = height; self.baseOffset = baseOffset
        self.justification = justification; self.bulge = bulge; self.wallType = wallType
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
    public init(boundary: [Vec2], holes: [[Vec2]] = [], thickness: Double = 200, topOffset: Double = 0) {
        self.boundary = boundary; self.holes = holes; self.thickness = thickness; self.topOffset = topOffset
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
    public init(kind: OpeningKind, hostWall: EntityID, offset: Double, width: Double, height: Double, sill: Double = 0,
                flipHand: Bool = false, flipFacing: Bool = false, doorStyle: DoorStyle = .single, windowStyle: WindowStyle = .casement, frameWidth: Double = 50) {
        self.kind = kind; self.hostWall = hostWall; self.offset = offset; self.width = width; self.height = height; self.sill = sill
        self.flipHand = flipHand; self.flipFacing = flipFacing; self.doorStyle = doorStyle; self.windowStyle = windowStyle; self.frameWidth = frameWidth
    }
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
    public init(start: Vec2, end: Vec2, height: Double = 3000, baseOffset: Double = 0, gridU: Double = 1200, gridV: Double = 1500, mullionSize: Double = 60) {
        self.start = start; self.end = end; self.height = height; self.baseOffset = baseOffset; self.gridU = gridU; self.gridV = gridV; self.mullionSize = mullionSize
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
