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
    /// Top constraint (Revit "Up to level"): id of the level the wall top follows; nil = unconnected (`height` is used).
    public var topLevel: Int?
    /// Offset of the wall top above `topLevel` (ignored when unconnected).
    public var topOffset: Double
    /// Elevation profile (BIM-020): a closed polygon of (distance along the wall from its start, height above the wall
    /// base) the wall is trimmed to — gables, steps, cut-outs. nil = rectangular.
    public var profile: [Vec2]?
    /// Slanted wall (BIM-023): lean from vertical in degrees, positive towards the left side (as drawn). nil = vertical.
    public var slant: Double?
    /// Tapered wall (BIM-023): thickness at the top (the base keeps `thickness`), symmetric about the centreline.
    public var topThickness: Double?
    public init(start: Vec2, end: Vec2, thickness: Double = 200, height: Double = 3000, baseOffset: Double = 0,
                justification: WallJustification = .center, bulge: Double = 0, wallType: String? = nil, sweeps: [WallSweep] = [],
                topLevel: Int? = nil, topOffset: Double = 0) {
        self.start = start; self.end = end; self.thickness = thickness; self.height = height; self.baseOffset = baseOffset
        self.justification = justification; self.bulge = bulge; self.wallType = wallType; self.sweeps = sweeps
        self.topLevel = topLevel; self.topOffset = topOffset
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
    /// Slab edges (BIM-051).
    public var edges: [SlabEdge]?
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
    /// Structural section from `StructuralProfiles` ("HEA200", "RHS 200x100x8"…); nil = plain rectangle/circle.
    public var profile: String?
    public init(position: Vec2, width: Double = 300, depth: Double = 300, height: Double = 3000, rotation: Double = 0, round: Bool = false, baseOffset: Double = 0,
                profile: String? = nil) {
        self.position = position; self.width = width; self.depth = depth; self.height = height; self.rotation = rotation; self.round = round; self.baseOffset = baseOffset
        self.profile = profile
    }
}

public struct BeamGeom: Codable, Hashable {
    public var start: Vec2; public var end: Vec2; public var width: Double; public var depth: Double
    /// Top of beam relative to its level.
    public var topOffset: Double
    /// Structural section from `StructuralProfiles` (nil = rectangular width × depth).
    public var profile: String?
    /// Top of the beam at its end (braces, rafters, sloped beams); nil = level (same as `topOffset`).
    public var endTopOffset: Double?
    public init(start: Vec2, end: Vec2, width: Double = 200, depth: Double = 400, topOffset: Double = 3000, profile: String? = nil, endTopOffset: Double? = nil) {
        self.start = start; self.end = end; self.width = width; self.depth = depth; self.topOffset = topOffset; self.profile = profile; self.endTopOffset = endTopOffset
    }
    public var isSloped: Bool { endTopOffset.map { abs($0 - topOffset) > 1e-9 } ?? false }
    /// Top of the beam at its end.
    public var endTop: Double { endTopOffset ?? topOffset }
}

public enum OpeningKind: String, Codable, CaseIterable { case door, window, opening }
/// Operation variants refining the base door/window style (BIM-036/037): pocket (sliding into the wall) and bi-fold doors,
/// pivot and tilt-turn windows. The base style stays the IFC/exchange fallback (pocket → sliding, bi-fold → folding,
/// pivot and tilt-turn → casement).
public enum OpeningVariant: String, Codable, CaseIterable {
    case pocket, biFold, pivot, tiltTurn
    public var isDoor: Bool { self == .pocket || self == .biFold }
    public var baseDoorStyle: DoorStyle { self == .pocket ? .sliding : .folding }
    /// Parses a style name ("pocket", "bifold", "bi-fold", "pivot", "tilt-turn", "tiltturn").
    public init?(name: String) {
        switch name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") {
        case "pocket": self = .pocket
        case "bifold": self = .biFold
        case "pivot": self = .pivot
        case "tiltturn", "tilt": self = .tiltTurn
        default: return nil
        }
    }
}
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
    /// Windows: extra vertical mullions dividing the glazing into equal lights (0 = none).
    public var mullions: Int
    /// Windows: horizontal transoms dividing the glazing; doors: 1 or more = a fanlight (transom light) above the leaf.
    public var transoms: Int
    /// Doors: a threshold plate across the opening at floor level.
    public var threshold: Bool
    /// Operation variant refining the style (pocket, bi-fold, pivot, tilt-turn); nil = the plain style.
    public var variant: OpeningVariant?
    public init(kind: OpeningKind, hostWall: EntityID, offset: Double, width: Double, height: Double, sill: Double = 0,
                flipHand: Bool = false, flipFacing: Bool = false, doorStyle: DoorStyle = .single, windowStyle: WindowStyle = .casement, frameWidth: Double = 50,
                depth: Double = 0, typeName: String? = nil, mark: String? = nil, mullions: Int = 0, transoms: Int = 0, threshold: Bool = false) {
        self.kind = kind; self.hostWall = hostWall; self.offset = offset; self.width = width; self.height = height; self.sill = sill
        self.flipHand = flipHand; self.flipFacing = flipFacing; self.doorStyle = doorStyle; self.windowStyle = windowStyle; self.frameWidth = frameWidth
        self.depth = depth; self.typeName = typeName; self.mark = mark
        self.mullions = max(0, mullions); self.transoms = max(0, transoms); self.threshold = threshold
    }
    public var isNiche: Bool { kind == .opening && depth > 1e-9 }
}

public enum RoofKind: String, Codable, CaseIterable { case flat, shed, gable, hip }
/// Two-pitch and curved roof forms (BIM-058). Mansard: every eave rises at `pitch` for `breakDistance` (plan distance
/// from the eave), then at `upperPitch`. Gambrel: the same on the two gable slopes. Dome: spherical cap over the
/// footprint (rise = radius × tan(pitch), at most a hemisphere). Barrel: circular vault spanning across the eave edge.
public struct RoofProfile: Codable, Hashable {
    public enum Form: String, Codable, CaseIterable { case mansard, gambrel, dome, barrel }
    public var form: Form
    public var upperPitch: Double
    public var breakDistance: Double
    public init(form: Form, upperPitch: Double = 20, breakDistance: Double = 1200) { self.form = form; self.upperPitch = upperPitch; self.breakDistance = breakDistance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(form: try c.decode(Form.self, forKey: .form), upperPitch: try c.decodeIfPresent(Double.self, forKey: .upperPitch) ?? 20,
                  breakDistance: try c.decodeIfPresent(Double.self, forKey: .breakDistance) ?? 1200)
    }
    public var isCurved: Bool { form == .dome || form == .barrel }
}

public struct RoofGeom: Codable, Hashable {
    public var boundary: [Vec2]; public var kind: RoofKind
    /// Pitch in degrees.
    public var pitch: Double; public var thickness: Double; public var overhang: Double
    /// Eave height above level.
    public var baseOffset: Double
    /// Gable/shed direction: index of the boundary edge that is an eave (slopes up away from it).
    public var eaveEdge: Int
    /// Special roof forms (mansard, gambrel, dome, barrel vault); nil = the plain `kind`.
    public var profile: RoofProfile?
    /// Roof by extrusion (BIM-057): a sketched profile extruded along a plan direction (replaces the kind's faces).
    public var extrusion: RoofExtrusion?
    /// Shape editing of flat roofs (BIM-063): plan points with heights above the flat top (drainage falls); the top
    /// becomes a triangulated surface through them and the footprint corners.
    public var shapePoints: [Vec3]?
    public init(boundary: [Vec2], kind: RoofKind = .gable, pitch: Double = 30, thickness: Double = 250, overhang: Double = 500, baseOffset: Double = 3000, eaveEdge: Int = 0) {
        self.boundary = boundary; self.kind = kind; self.pitch = pitch; self.thickness = thickness; self.overhang = overhang; self.baseOffset = baseOffset; self.eaveEdge = eaveEdge
    }
}

/// Roof by extrusion: profile points (x along `direction` from `origin`, z above the eave height) extruded `depth` to
/// the left of the direction.
public struct RoofExtrusion: Codable, Hashable {
    public var origin: Vec2
    public var direction: Double
    public var profile: [Vec2]
    public var depth: Double
    public init(origin: Vec2, direction: Double, profile: [Vec2], depth: Double) { self.origin = origin; self.direction = direction; self.profile = profile; self.depth = depth }
    /// Plan rectangle covered by the roof (counter-clockwise).
    public var footprint: [Vec2] {
        let xs = profile.map(\.x)
        guard let x0 = xs.min(), let x1 = xs.max(), x1 - x0 > 1e-9, depth > 0 else { return [] }
        let u = Vec2.polar(1, direction), n = u.perp
        return [origin + u * x0, origin + u * x1, origin + u * x1 + n * depth, origin + u * x0 + n * depth]
    }
}

/// A slab edge (BIM-051): a profile along boundary edges — Upstand (curb, balcony upstand on top of the slab, inside the
/// edge) or Fascia (slab edge band outside the edge, hanging down from the top).
public struct SlabEdge: Codable, Hashable {
    /// Boundary edge index (from vertex i to i + 1); -1 = every edge.
    public var edge: Int
    public var kind: String
    public var width: Double
    public var height: Double
    public var material: String?
    public init(edge: Int, kind: String = "upstand", width: Double = 150, height: Double = 300, material: String? = nil) {
        self.edge = edge; self.kind = kind; self.width = width; self.height = height; self.material = material
    }
}

public enum StairKind: String, Codable, CaseIterable { case straight, lShape, uShape, spiral }
public struct StairGeom: Codable, Hashable {
    public var start: Vec2; public var direction: Double
    public var width: Double; public var totalRise: Double; public var riserCount: Int; public var treadDepth: Double
    public var kind: StairKind
    /// Depth of landings in the walking direction (nil = stair width). Used by L/U stairs and straight stairs with a landing.
    public var landingDepth: Double?
    /// Straight stairs: number of risers before an intermediate landing (nil = no landing). L/U stairs: risers of the first flight (nil = half).
    public var landingAt: Int?
    /// Level the stair arrives at (nil = rise set by `totalRise`); the upper level shows the stair with a DN arrow.
    public var topLevel: Int?
    /// L/U stairs: number of winder treads replacing the corner/half landing (nil or 0 = flat landing).
    public var winders: Int?
    /// Turn direction: L/U stairs turn right and spirals wind clockwise when true (default: left / counter-clockwise).
    public var clockwise: Bool?
    /// Spiral stairs: radius of the central column / inner edge of the treads (nil = automatic).
    public var innerRadius: Double?
    /// Stair by sketch (BIM-066): riser lines bottom to top (each two plan points); treads span consecutive risers.
    public var sketchRisers: [[Vec2]]?
    public init(start: Vec2, direction: Double = 0, width: Double = 1000, totalRise: Double = 3000, riserCount: Int = 17, treadDepth: Double = 280, kind: StairKind = .straight,
                landingDepth: Double? = nil, landingAt: Int? = nil, topLevel: Int? = nil, winders: Int? = nil, clockwise: Bool? = nil, innerRadius: Double? = nil) {
        self.start = start; self.direction = direction; self.width = width; self.totalRise = totalRise; self.riserCount = riserCount; self.treadDepth = treadDepth; self.kind = kind
        self.landingDepth = landingDepth; self.landingAt = landingAt; self.topLevel = topLevel
        self.winders = winders; self.clockwise = clockwise; self.innerRadius = innerRadius
    }
    /// Winder treads actually used (L: 2–6, U: 3–10), 0 = flat landing.
    public var winderCount: Int {
        guard let w = winders, w > 0 else { return 0 }
        switch kind { case .lShape: return min(max(w, 2), 6); case .uShape: return min(max(w, 3), 10); default: return 0 }
    }
    public var turnsRight: Bool { clockwise ?? false }
    /// Spiral inner radius (column).
    public var spiralInnerRadius: Double { max(innerRadius ?? max(100, width * 0.15), 1e-3) }
    public var riserHeight: Double { totalRise / Double(max(riserCount, 1)) }
    public var runLength: Double { treadDepth * Double(max(riserCount - 1, 0)) }
}

public struct RailingGeom: Codable, Hashable {
    public var path: [Vec2]; public var height: Double; public var baseOffset: Double
    /// Railing type (nil = generic posts and top rail): handrail profile and size, infill ("balusters", "glass", "cables",
    /// "bars", "none"), baluster profile/size/spacing, post spacing, bottom rail and handrail extensions at the ends.
    public var railProfile: String?
    public var railSize: Double?
    public var infill: String?
    public var balusterProfile: String?
    public var balusterSize: Double?
    public var balusterSpacing: Double?
    public var postSpacing: Double?
    public var bottomRail: Bool?
    public var extensionLength: Double?
    /// Heights of the path vertices above `baseOffset` (railings on stairs and ramps, BIM-072); nil = level.
    public var pathZ: [Double]?
    public init(path: [Vec2], height: Double = 1000, baseOffset: Double = 0, pathZ: [Double]? = nil) { self.path = path; self.height = height; self.baseOffset = baseOffset; self.pathZ = pathZ }
    /// Height above `baseOffset` of path vertex i.
    public func z(_ i: Int) -> Double { guard let z = pathZ, i >= 0, i < z.count else { return 0 }; return z[i] }
    /// Height above `baseOffset` at a plan point on the path (interpolated along the nearest segment).
    public func z(at p: Vec2) -> Double {
        guard let zs = pathZ, zs.count == path.count, path.count >= 2 else { return 0 }
        var best = (d: Double.infinity, z: 0.0)
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1], e = b - a, l2 = e.dot(e)
            let t = l2 > 1e-18 ? min(max((p - a).dot(e) / l2, 0), 1) : 0
            let d = p.distance(to: a + e * t)
            if d < best.d { best = (d, zs[i] + (zs[i + 1] - zs[i]) * t) }
        }
        return best.z
    }
    public var isSloped: Bool { (pathZ ?? []).contains { abs($0) > 1e-9 } }
    /// Whether any railing-type parameter is set.
    public var isTyped: Bool { railProfile != nil || infill != nil || balusterSpacing != nil || postSpacing != nil || extensionLength != nil || bottomRail != nil }
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
    /// Interior mullion type ("rect", "round", "fin", "capped", "tee"); nil = rectangular.
    public var mullionProfile: String?
    /// Border (perimeter) mullion type; nil = same as `mullionProfile`.
    public var borderProfile: String?
    /// Mullion depth perpendicular to the wall (nil = 1.5 × mullionSize).
    public var mullionDepth: Double?
    public init(start: Vec2, end: Vec2, height: Double = 3000, baseOffset: Double = 0, gridU: Double = 1200, gridV: Double = 1500, mullionSize: Double = 60,
                uLines: [Double]? = nil, vLines: [Double]? = nil, panels: [String: String] = [:],
                mullionProfile: String? = nil, borderProfile: String? = nil, mullionDepth: Double? = nil) {
        self.start = start; self.end = end; self.height = height; self.baseOffset = baseOffset; self.gridU = gridU; self.gridV = gridV; self.mullionSize = mullionSize
        self.uLines = uLines; self.vLines = vLines; self.panels = panels
        self.mullionProfile = mullionProfile; self.borderProfile = borderProfile; self.mullionDepth = mullionDepth
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
    /// Reveal (BIM-021): the profile is cut into the wall face (a groove) instead of projecting from it; nil/false = sweep.
    public var reveal: Bool?
    public init(profile: String = "rect", depth: Double = 50, height: Double = 150, elevation: Double = 0, side: Double = 1, material: String? = nil, reveal: Bool? = nil) {
        self.profile = profile; self.depth = depth; self.height = height; self.elevation = elevation; self.side = side; self.material = material; self.reveal = reveal
    }
    public var isReveal: Bool { reveal ?? false }
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
    /// Parametric family from `ComponentLibrary` (e.g. "bed-double", "sofa"); nil = plain box or block.
    public var family: String?
    /// Run families (pipes, ducts, cable trays, retaining walls): centreline in component-local coordinates
    /// (world = position + rotation · local), so MOVE/ROTATE/COPY carry it along. nil = a point-placed component.
    public var path: [Vec2]?
    /// Heights of the path vertices above `baseOffset` (sloped runs); nil = level at `baseOffset`.
    public var pathZ: [Double]?
    /// In-place model geometry (BIM-103): a mesh in component-local coordinates (base centred at the origin).
    public var mesh: SolidGeom?
    public init(category: String = "Furniture", position: Vec2, rotation: Double = 0, size: Vec3 = Vec3(600, 600, 750), baseOffset: Double = 0, block: String? = nil,
                family: String? = nil, path: [Vec2]? = nil, pathZ: [Double]? = nil) {
        self.category = category; self.position = position; self.rotation = rotation; self.size = size; self.baseOffset = baseOffset; self.block = block
        self.family = family; self.path = path; self.pathZ = pathZ
    }
    /// World-space run path (empty for point components).
    public var worldPath: [Vec2] {
        guard let p = path else { return [] }
        let c = cos(rotation), s = sin(rotation)
        return p.map { Vec2(position.x + $0.x * c - $0.y * s, position.y + $0.x * s + $0.y * c) }
    }
    /// Height above `baseOffset` of path vertex i.
    public func pathHeight(_ i: Int) -> Double { guard let z = pathZ, i >= 0, i < z.count else { return 0 }; return z[i] }
}

public struct GridLineGeom: Codable, Hashable {
    public var start: Vec2; public var end: Vec2; public var label: String
    /// Arc grid (radial grid systems): bulge like a polyline segment (0 = straight).
    public var bulge: Double
    /// Multi-segment grids (BIM-005): intermediate vertices in the chord frame — x along start→end and y to its left,
    /// both as fractions of the chord length — so MOVE/ROTATE/SCALE of the end points carry the whole polyline along.
    public var bends: [Vec2]
    /// Head bubbles: "start" (default), "end", "both" or "none".
    public var heads: String?
    public init(start: Vec2, end: Vec2, label: String, bulge: Double = 0, bends: [Vec2] = [], heads: String? = nil) {
        self.start = start; self.end = end; self.label = label; self.bulge = bulge; self.bends = bends; self.heads = heads
    }
    /// Multi-segment grid through world points (first and last are the grid ends).
    public init?(through pts: [Vec2], label: String) {
        guard pts.count >= 2, let a = pts.first, let b = pts.last, a.distance(to: b) > 1e-9 else { return nil }
        let L = a.distance(to: b), d = (b - a) / L, n = d.perp
        self.init(start: a, end: b, label: label, bends: pts.dropFirst().dropLast().map { Vec2(($0 - a).dot(d) / L, ($0 - a).dot(n) / L) })
    }
    enum CodingKeys: String, CodingKey { case start, end, label, bulge, bends, heads }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try c.decode(Vec2.self, forKey: .start), end: try c.decode(Vec2.self, forKey: .end),
                  label: try c.decodeIfPresent(String.self, forKey: .label) ?? "", bulge: try c.decodeIfPresent(Double.self, forKey: .bulge) ?? 0,
                  bends: try c.decodeIfPresent([Vec2].self, forKey: .bends) ?? [], heads: try c.decodeIfPresent(String.self, forKey: .heads))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(label, forKey: .label)
        if bulge != 0 { try c.encode(bulge, forKey: .bulge) }
        if !bends.isEmpty { try c.encode(bends, forKey: .bends) }
        try c.encodeIfPresent(heads, forKey: .heads)
    }
    /// World vertices of a multi-segment grid (start, bends…, end).
    public var vertices: [Vec2] {
        guard !bends.isEmpty else { return [start, end] }
        let L = start.distance(to: end)
        guard L > 1e-9 else { return [start, end] }
        let d = (end - start) / L, n = d.perp
        return [start] + bends.map { start + d * ($0.x * L) + n * ($0.y * L) } + [end]
    }
    /// Points along the grid line (tessellated for arc grids).
    public var points: [Vec2] {
        guard bends.isEmpty else { return vertices }
        guard abs(bulge) > 1e-12, start.distance(to: end) > 1e-9 else { return [start, end] }
        let a = GeometryOps.bulgeArc(start, end, bulge)
        let n = max(8, Int(abs(a.sweep) / (Double.pi / 48)))
        return (0...n).map { k in a.center + Vec2.polar(a.radius, a.start + a.sweep * Double(k) / Double(n)) }
    }
    /// Straight single-segment grid.
    public var isStraight: Bool { bends.isEmpty && abs(bulge) < 1e-12 }
    /// Head bubbles: (at start, at end).
    public var headEnds: (start: Bool, end: Bool) {
        switch (heads ?? "start").lowercased() { case "end": return (false, true); case "both": return (true, true); case "none": return (false, false); default: return (true, false) }
    }
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
    private enum Keys: String, CodingKey { case start, end, thickness, height, baseOffset, justification, bulge, wallType, sweeps, topLevel, topOffset, profile, slant, topThickness }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(start: try c.decode(Vec2.self, forKey: .start), end: try c.decode(Vec2.self, forKey: .end),
                  thickness: try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 200,
                  height: try c.decodeIfPresent(Double.self, forKey: .height) ?? 3000,
                  baseOffset: try c.decodeIfPresent(Double.self, forKey: .baseOffset) ?? 0,
                  justification: try c.decodeIfPresent(WallJustification.self, forKey: .justification) ?? .center,
                  bulge: try c.decodeIfPresent(Double.self, forKey: .bulge) ?? 0,
                  wallType: try c.decodeIfPresent(String.self, forKey: .wallType),
                  sweeps: try c.decodeIfPresent([WallSweep].self, forKey: .sweeps) ?? [],
                  topLevel: try c.decodeIfPresent(Int.self, forKey: .topLevel), topOffset: try c.decodeIfPresent(Double.self, forKey: .topOffset) ?? 0)
        profile = try c.decodeIfPresent([Vec2].self, forKey: .profile)
        slant = try c.decodeIfPresent(Double.self, forKey: .slant)
        topThickness = try c.decodeIfPresent(Double.self, forKey: .topThickness)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(thickness, forKey: .thickness)
        try c.encode(height, forKey: .height); try c.encode(baseOffset, forKey: .baseOffset); try c.encode(justification, forKey: .justification)
        try c.encode(bulge, forKey: .bulge); try c.encodeIfPresent(wallType, forKey: .wallType)
        if !sweeps.isEmpty { try c.encode(sweeps, forKey: .sweeps) }
        if let t = topLevel { try c.encode(t, forKey: .topLevel); try c.encode(topOffset, forKey: .topOffset) }
        try c.encodeIfPresent(profile, forKey: .profile); try c.encodeIfPresent(slant, forKey: .slant); try c.encodeIfPresent(topThickness, forKey: .topThickness)
    }
    /// Whether the wall leans or tapers.
    public var isSlantedOrTapered: Bool { abs(slant ?? 0) > 1e-9 || (topThickness.map { abs($0 - thickness) > 1e-9 } ?? false) }
}

extension SlabGeom {
    private enum Keys: String, CodingKey { case boundary, holes, thickness, topOffset, slope, slopeDirection, slopeOrigin, edges }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(boundary: try c.decode([Vec2].self, forKey: .boundary), holes: try c.decodeIfPresent([[Vec2]].self, forKey: .holes) ?? [],
                  thickness: try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 200, topOffset: try c.decodeIfPresent(Double.self, forKey: .topOffset) ?? 0,
                  slope: try c.decodeIfPresent(Double.self, forKey: .slope) ?? 0, slopeDirection: try c.decodeIfPresent(Double.self, forKey: .slopeDirection) ?? 0,
                  slopeOrigin: try c.decodeIfPresent(Vec2.self, forKey: .slopeOrigin))
        edges = try c.decodeIfPresent([SlabEdge].self, forKey: .edges)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(boundary, forKey: .boundary); try c.encode(holes, forKey: .holes); try c.encode(thickness, forKey: .thickness); try c.encode(topOffset, forKey: .topOffset)
        if isSloped { try c.encode(slope, forKey: .slope); try c.encode(slopeDirection, forKey: .slopeDirection); try c.encodeIfPresent(slopeOrigin, forKey: .slopeOrigin) }
        if let e = edges, !e.isEmpty { try c.encode(e, forKey: .edges) }
    }
}

extension OpeningGeom {
    private enum Keys: String, CodingKey { case kind, hostWall, offset, width, height, sill, flipHand, flipFacing, doorStyle, windowStyle, frameWidth, depth, typeName, mark, mullions, transoms, threshold, variant }
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
                  typeName: try c.decodeIfPresent(String.self, forKey: .typeName), mark: try c.decodeIfPresent(String.self, forKey: .mark),
                  mullions: try c.decodeIfPresent(Int.self, forKey: .mullions) ?? 0, transoms: try c.decodeIfPresent(Int.self, forKey: .transoms) ?? 0,
                  threshold: try c.decodeIfPresent(Bool.self, forKey: .threshold) ?? false)
        variant = try c.decodeIfPresent(OpeningVariant.self, forKey: .variant)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey: .kind); try c.encode(hostWall, forKey: .hostWall); try c.encode(offset, forKey: .offset)
        try c.encode(width, forKey: .width); try c.encode(height, forKey: .height); try c.encode(sill, forKey: .sill)
        try c.encode(flipHand, forKey: .flipHand); try c.encode(flipFacing, forKey: .flipFacing); try c.encode(doorStyle, forKey: .doorStyle)
        try c.encode(windowStyle, forKey: .windowStyle); try c.encode(frameWidth, forKey: .frameWidth)
        if depth > 0 { try c.encode(depth, forKey: .depth) }
        try c.encodeIfPresent(typeName, forKey: .typeName); try c.encodeIfPresent(mark, forKey: .mark)
        if mullions > 0 { try c.encode(mullions, forKey: .mullions) }
        if transoms > 0 { try c.encode(transoms, forKey: .transoms) }
        if threshold { try c.encode(threshold, forKey: .threshold) }
        try c.encodeIfPresent(variant, forKey: .variant)
    }
}

extension CurtainWallGeom {
    private enum Keys: String, CodingKey { case start, end, height, baseOffset, gridU, gridV, mullionSize, uLines, vLines, panels, mullionProfile, borderProfile, mullionDepth }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(start: try c.decode(Vec2.self, forKey: .start), end: try c.decode(Vec2.self, forKey: .end),
                  height: try c.decodeIfPresent(Double.self, forKey: .height) ?? 3000, baseOffset: try c.decodeIfPresent(Double.self, forKey: .baseOffset) ?? 0,
                  gridU: try c.decodeIfPresent(Double.self, forKey: .gridU) ?? 1200, gridV: try c.decodeIfPresent(Double.self, forKey: .gridV) ?? 1500,
                  mullionSize: try c.decodeIfPresent(Double.self, forKey: .mullionSize) ?? 60,
                  uLines: try c.decodeIfPresent([Double].self, forKey: .uLines), vLines: try c.decodeIfPresent([Double].self, forKey: .vLines),
                  panels: try c.decodeIfPresent([String: String].self, forKey: .panels) ?? [:],
                  mullionProfile: try c.decodeIfPresent(String.self, forKey: .mullionProfile), borderProfile: try c.decodeIfPresent(String.self, forKey: .borderProfile),
                  mullionDepth: try c.decodeIfPresent(Double.self, forKey: .mullionDepth))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(height, forKey: .height); try c.encode(baseOffset, forKey: .baseOffset)
        try c.encode(gridU, forKey: .gridU); try c.encode(gridV, forKey: .gridV); try c.encode(mullionSize, forKey: .mullionSize)
        try c.encodeIfPresent(uLines, forKey: .uLines); try c.encodeIfPresent(vLines, forKey: .vLines)
        if !panels.isEmpty { try c.encode(panels, forKey: .panels) }
        try c.encodeIfPresent(mullionProfile, forKey: .mullionProfile); try c.encodeIfPresent(borderProfile, forKey: .borderProfile)
        try c.encodeIfPresent(mullionDepth, forKey: .mullionDepth)
    }
}

/// String coding key for ad-hoc lookups.
struct AnyKey: CodingKey {
    var stringValue: String; var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
