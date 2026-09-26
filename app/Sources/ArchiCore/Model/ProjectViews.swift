// Oanarina Archi Tool — GPL-3.0-or-later
// Project views (DOC-013/014/015/016/027): saved plan / ceiling / 3D views with their own view settings, crop regions,
// annotation crop, dependent views, scope boxes and per-view linework overrides. Also stair and railing type
// definitions (PAR-018). All stored as optional document keys (format 6).
import Foundation

/// A linework override (DOC-027): one edge of an element drawn with another style in one view only.
public struct LineworkOverride: Codable, Hashable {
    public var element: EntityID
    /// The overridden edge (model coordinates, as drawn in plan).
    public var a: Vec2
    public var b: Vec2
    public var linetype: String?
    public var color: RGBA?
    public var lineweight: Double?
    /// "Invisible lines" style.
    public var invisible: Bool?
    public init(element: EntityID, a: Vec2, b: Vec2, linetype: String? = nil, color: RGBA? = nil, lineweight: Double? = nil, invisible: Bool? = nil) {
        self.element = element; self.a = a; self.b = b; self.linetype = linetype; self.color = color; self.lineweight = lineweight; self.invisible = invisible
    }
}

/// A saved project view.
public struct ProjectView: Codable, Hashable {
    public var name: String
    /// "plan", "ceiling" or "3d".
    public var kind: String
    public var level: Int?
    /// View variables of the view (VIEWTEMPLATE, view range, VG, phase, detail level…).
    public var settings: [String: String]
    /// Crop region (model coordinates, counter-clockwise).
    public var crop: [Vec2]?
    /// Whether the crop region clips the view.
    public var cropActive: Bool
    /// Annotation crop: annotations are clipped this far outside the model crop (nil = annotation crop off).
    public var annotationCrop: Double?
    /// Dependent view of this parent view (shares its settings and annotations).
    public var parent: String?
    /// Scope box controlling the crop.
    public var scopeBox: String?
    public var linework: [LineworkOverride]
    /// 3D views: camera, and an axonometric preset refitted to the model after every edit (DOC-009).
    public var camera: Camera?
    public var axonometric: String?
    public init(name: String, kind: String = "plan", level: Int? = nil, settings: [String: String] = [:], crop: [Vec2]? = nil, cropActive: Bool = false,
                annotationCrop: Double? = nil, parent: String? = nil, scopeBox: String? = nil, linework: [LineworkOverride] = [], camera: Camera? = nil, axonometric: String? = nil) {
        self.name = name; self.kind = kind; self.level = level; self.settings = settings; self.crop = crop; self.cropActive = cropActive
        self.annotationCrop = annotationCrop; self.parent = parent; self.scopeBox = scopeBox; self.linework = linework; self.camera = camera; self.axonometric = axonometric
    }
    enum CodingKeys: String, CodingKey { case name, kind, level, settings, crop, cropActive, annotationCrop, parent, scopeBox, linework, camera, axonometric }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), kind: try c.decodeIfPresent(String.self, forKey: .kind) ?? "plan",
                  level: try c.decodeIfPresent(Int.self, forKey: .level), settings: try c.decodeIfPresent([String: String].self, forKey: .settings) ?? [:],
                  crop: try c.decodeIfPresent([Vec2].self, forKey: .crop), cropActive: try c.decodeIfPresent(Bool.self, forKey: .cropActive) ?? false,
                  annotationCrop: try c.decodeIfPresent(Double.self, forKey: .annotationCrop), parent: try c.decodeIfPresent(String.self, forKey: .parent),
                  scopeBox: try c.decodeIfPresent(String.self, forKey: .scopeBox), linework: try c.decodeIfPresent([LineworkOverride].self, forKey: .linework) ?? [],
                  camera: try c.decodeIfPresent(Camera.self, forKey: .camera), axonometric: try c.decodeIfPresent(String.self, forKey: .axonometric))
    }
}

/// A scope box (BIM-008): a named, possibly rotated rectangle that sets the extents of grids and levels and the crop of
/// views assigned to it.
public struct ScopeBox: Codable, Hashable {
    public var name: String
    public var center: Vec2
    public var width: Double
    public var depth: Double
    public var rotation: Double
    /// Levels the box is shown on (nil = all).
    public var levels: [Int]?
    public init(name: String, center: Vec2, width: Double, depth: Double, rotation: Double = 0, levels: [Int]? = nil) {
        self.name = name; self.center = center; self.width = width; self.depth = depth; self.rotation = rotation; self.levels = levels
    }
    /// Corners counter-clockwise.
    public var corners: [Vec2] {
        let hx = width / 2, hy = depth / 2
        return [Vec2(-hx, -hy), Vec2(hx, -hy), Vec2(hx, hy), Vec2(-hx, hy)].map { $0.rotated(by: rotation) + center }
    }
}

/// A stair type (PAR-018): the rules and build-up applied to every stair of the type.
public struct StairType: Codable, Hashable {
    public var name: String
    public var maxRiser: Double
    public var minTread: Double
    public var width: Double
    public var landingDepth: Double?
    public var material: String?
    /// Railing type name put on both sides of stairs of this type (nil = none).
    public var railingType: String?
    public init(name: String, maxRiser: Double = 180, minTread: Double = 280, width: Double = 1000, landingDepth: Double? = nil, material: String? = nil, railingType: String? = nil) {
        self.name = name; self.maxRiser = maxRiser; self.minTread = minTread; self.width = width; self.landingDepth = landingDepth; self.material = material; self.railingType = railingType
    }
    public static let library: [StairType] = [
        StairType(name: "Residential 180/280", maxRiser: 180, minTread: 280, width: 1000),
        StairType(name: "Public 170/300", maxRiser: 170, minTread: 300, width: 1500, landingDepth: 1500),
    ]
}

/// A railing type definition (PAR-018): named set of railing parameters; railings with props railingType follow it.
public struct RailingTypeDef: Codable, Hashable {
    public var name: String
    public var height: Double
    public var railProfile: String
    public var railSize: Double
    public var infill: String
    public var balusterProfile: String
    public var balusterSize: Double
    public var balusterSpacing: Double
    public var postSpacing: Double
    public var bottomRail: Bool
    public var extensionLength: Double
    public init(name: String, height: Double = 1000, railProfile: String = "round", railSize: Double = 50, infill: String = "balusters", balusterProfile: String = "rect",
                balusterSize: Double = 20, balusterSpacing: Double = 120, postSpacing: Double = 1200, bottomRail: Bool = true, extensionLength: Double = 0) {
        self.name = name; self.height = height; self.railProfile = railProfile; self.railSize = railSize; self.infill = infill; self.balusterProfile = balusterProfile
        self.balusterSize = balusterSize; self.balusterSpacing = balusterSpacing; self.postSpacing = postSpacing; self.bottomRail = bottomRail; self.extensionLength = extensionLength
    }
    /// Applies the definition to a railing geometry.
    public func apply(to g: inout RailingGeom) {
        g.height = height; g.railProfile = railProfile; g.railSize = railSize; g.infill = infill; g.balusterProfile = balusterProfile
        g.balusterSize = balusterSize; g.balusterSpacing = balusterSpacing; g.postSpacing = postSpacing; g.bottomRail = bottomRail
        g.extensionLength = extensionLength > 0 ? extensionLength : nil
    }
}

extension ArchiDocument {
    public func view(named n: String?) -> ProjectView? {
        guard let n = n else { return nil }
        return views.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    public func viewIndex(_ n: String) -> Int? { views.firstIndex { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public func scopeBox(named n: String?) -> ScopeBox? {
        guard let n = n else { return nil }
        return scopeBoxes.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    public func stairType(named n: String?) -> StairType? {
        guard let n = n else { return nil }
        return stairTypes.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    public func railingType(named n: String?) -> RailingTypeDef? {
        guard let n = n else { return nil }
        return railingTypes.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    /// The current project view (CURRENTVIEW variable).
    public var currentView: ProjectView? { view(named: variable("CURRENTVIEW")) }
}
