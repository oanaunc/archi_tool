// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum Units: String, Codable, CaseIterable {
    case millimeters, centimeters, meters, inches, feet
    /// Millimetres per unit.
    public var mm: Double {
        switch self { case .millimeters: return 1; case .centimeters: return 10; case .meters: return 1000; case .inches: return 25.4; case .feet: return 304.8 }
    }
    public var abbreviation: String {
        switch self { case .millimeters: return "mm"; case .centimeters: return "cm"; case .meters: return "m"; case .inches: return "in"; case .feet: return "ft" }
    }
}

public struct Layer: Codable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var color: RGBA
    public var linetype: String
    public var lineweight: Double
    public var visible: Bool
    public var frozen: Bool
    public var locked: Bool
    public var plot: Bool
    public var transparency: Double
    public var description: String
    public init(name: String, color: RGBA = .white, linetype: String = "Continuous", lineweight: Double = 0.25,
                visible: Bool = true, frozen: Bool = false, locked: Bool = false, plot: Bool = true, transparency: Double = 0, description: String = "") {
        self.name = name; self.color = color; self.linetype = linetype; self.lineweight = lineweight
        self.visible = visible; self.frozen = frozen; self.locked = locked; self.plot = plot; self.transparency = transparency; self.description = description
    }
    public var isEditable: Bool { visible && !frozen && !locked }
}

/// Dash pattern in drawing units: positive = dash, negative = gap, 0 = dot.
public struct Linetype: Codable, Hashable {
    public var name: String; public var description: String; public var pattern: [Double]
    public init(name: String, description: String, pattern: [Double]) { self.name = name; self.description = description; self.pattern = pattern }
    public static let standard: [Linetype] = [
        Linetype(name: "Continuous", description: "Solid line", pattern: []),
        Linetype(name: "Dashed", description: "__ __ __", pattern: [12, -6]),
        Linetype(name: "Hidden", description: "_ _ _ _", pattern: [6, -3]),
        Linetype(name: "Center", description: "____ _ ____ _", pattern: [30, -6, 6, -6]),
        Linetype(name: "Phantom", description: "_____ _ _ _____", pattern: [30, -6, 6, -6, 6, -6]),
        Linetype(name: "Dot", description: ". . . .", pattern: [0, -3]),
        Linetype(name: "DashDot", description: "__ . __ .", pattern: [12, -3, 0, -3]),
        Linetype(name: "Border", description: "__ __ . __", pattern: [12, -3, 12, -3, 0, -3]),
        Linetype(name: "Divide", description: "__ . . __", pattern: [12, -3, 0, -3, 0, -3]),
    ]
}

public struct TextStyle: Codable, Hashable {
    public var name: String; public var font: String; public var height: Double; public var widthFactor: Double; public var oblique: Double
    public init(name: String, font: String = "Helvetica", height: Double = 0, widthFactor: Double = 1, oblique: Double = 0) {
        self.name = name; self.font = font; self.height = height; self.widthFactor = widthFactor; self.oblique = oblique
    }
}

public enum ArrowKind: String, Codable, CaseIterable { case closedFilled, open, tick, dot, architecturalTick, none }

public struct DimStyle: Codable, Hashable {
    public var name: String
    public var textHeight: Double; public var arrowSize: Double; public var arrow: ArrowKind
    public var extensionOffset: Double; public var extensionExtend: Double; public var textGap: Double
    public var decimals: Int; public var prefix: String; public var suffix: String
    /// Multiplier from drawing units to displayed value.
    public var linearScale: Double
    /// Overall scale of dimension graphics (DIMSCALE).
    public var scale: Double
    public init(name: String, textHeight: Double = 2.5, arrowSize: Double = 2.5, arrow: ArrowKind = .closedFilled,
                extensionOffset: Double = 1, extensionExtend: Double = 1.25, textGap: Double = 0.8, decimals: Int = 0,
                prefix: String = "", suffix: String = "", linearScale: Double = 1, scale: Double = 1) {
        self.name = name; self.textHeight = textHeight; self.arrowSize = arrowSize; self.arrow = arrow
        self.extensionOffset = extensionOffset; self.extensionExtend = extensionExtend; self.textGap = textGap
        self.decimals = decimals; self.prefix = prefix; self.suffix = suffix; self.linearScale = linearScale; self.scale = scale
    }
}

public struct Block: Codable, Hashable {
    public var name: String; public var basePoint: Vec2; public var entities: [Entity]; public var description: String
    public init(name: String, basePoint: Vec2 = .zero, entities: [Entity] = [], description: String = "") {
        self.name = name; self.basePoint = basePoint; self.entities = entities; self.description = description
    }
}

public struct Level: Codable, Hashable, Identifiable {
    public var id: Int; public var name: String; public var elevation: Double; public var height: Double
    public init(id: Int, name: String, elevation: Double, height: Double = 3000) { self.id = id; self.name = name; self.elevation = elevation; self.height = height }
}

public struct Material: Codable, Hashable {
    public var name: String; public var color: RGBA; public var roughness: Double; public var metalness: Double
    public var transparency: Double; public var texture: String?; public var textureScale: Double
    /// 2D hatch used when the material is cut in plan/section.
    public var cutPattern: String
    public init(name: String, color: RGBA, roughness: Double = 0.8, metalness: Double = 0, transparency: Double = 0,
                texture: String? = nil, textureScale: Double = 1000, cutPattern: String = "SOLID") {
        self.name = name; self.color = color; self.roughness = roughness; self.metalness = metalness; self.transparency = transparency
        self.texture = texture; self.textureScale = textureScale; self.cutPattern = cutPattern
    }
    public static let library: [Material] = [
        Material(name: "Concrete", color: RGBA(0.72, 0.72, 0.70), roughness: 0.9, cutPattern: "AR-CONC"),
        Material(name: "Brick", color: RGBA(0.62, 0.30, 0.22), roughness: 0.85, cutPattern: "ANSI31"),
        Material(name: "Plaster", color: RGBA(0.95, 0.94, 0.91), roughness: 0.9, cutPattern: "SOLID"),
        Material(name: "Wood", color: RGBA(0.64, 0.46, 0.29), roughness: 0.6, cutPattern: "ANSI32"),
        Material(name: "Glass", color: RGBA(0.62, 0.78, 0.86), roughness: 0.05, transparency: 0.7, cutPattern: "SOLID"),
        Material(name: "Steel", color: RGBA(0.55, 0.57, 0.60), roughness: 0.35, metalness: 1, cutPattern: "ANSI37"),
        Material(name: "Aluminium", color: RGBA(0.80, 0.81, 0.83), roughness: 0.3, metalness: 1),
        Material(name: "Roof Tiles", color: RGBA(0.55, 0.22, 0.16), roughness: 0.8),
        Material(name: "Stone", color: RGBA(0.66, 0.63, 0.57), roughness: 0.9, cutPattern: "AR-SAND"),
        Material(name: "Insulation", color: RGBA(0.95, 0.85, 0.40), roughness: 1, cutPattern: "INSUL"),
        Material(name: "Grass", color: RGBA(0.35, 0.55, 0.25), roughness: 1),
        Material(name: "Tiles", color: RGBA(0.88, 0.88, 0.86), roughness: 0.3),
    ]
}

/// Layer build-up of a wall type (Revit compound structure).
public struct WallType: Codable, Hashable {
    public struct Ply: Codable, Hashable { public var material: String; public var thickness: Double; public var function: String
        public init(material: String, thickness: Double, function: String = "Structure") { self.material = material; self.thickness = thickness; self.function = function } }
    public var name: String; public var plies: [Ply]
    public init(name: String, plies: [Ply]) { self.name = name; self.plies = plies }
    public var thickness: Double { plies.reduce(0) { $0 + $1.thickness } }
    public static let library: [WallType] = [
        WallType(name: "Generic 200", plies: [Ply(material: "Concrete", thickness: 200)]),
        WallType(name: "Exterior Brick 365", plies: [Ply(material: "Plaster", thickness: 15, function: "Finish"), Ply(material: "Brick", thickness: 240),
                                                     Ply(material: "Insulation", thickness: 100, function: "Thermal"), Ply(material: "Plaster", thickness: 10, function: "Finish")]),
        WallType(name: "Interior Partition 100", plies: [Ply(material: "Plaster", thickness: 12.5, function: "Finish"), Ply(material: "Insulation", thickness: 75), Ply(material: "Plaster", thickness: 12.5, function: "Finish")]),
        WallType(name: "Concrete 250", plies: [Ply(material: "Concrete", thickness: 250)]),
    ]
}

/// A door, window or opening type (Revit family type): shared parameters for all instances that follow it.
public struct OpeningType: Codable, Hashable {
    public var name: String
    public var kind: OpeningKind
    public var width: Double; public var height: Double; public var sill: Double
    public var doorStyle: DoorStyle; public var windowStyle: WindowStyle
    public var frameWidth: Double
    public var material: String?
    /// Free-form type parameters (fire rating, U-value, manufacturer, cost…), shown in schedules.
    public var params: [String: String]
    public init(name: String, kind: OpeningKind, width: Double, height: Double, sill: Double = 0, doorStyle: DoorStyle = .single,
                windowStyle: WindowStyle = .casement, frameWidth: Double = 50, material: String? = nil, params: [String: String] = [:]) {
        self.name = name; self.kind = kind; self.width = width; self.height = height; self.sill = sill; self.doorStyle = doorStyle
        self.windowStyle = windowStyle; self.frameWidth = frameWidth; self.material = material; self.params = params
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), kind: try c.decodeIfPresent(OpeningKind.self, forKey: .kind) ?? .door,
                  width: try c.decodeIfPresent(Double.self, forKey: .width) ?? 900, height: try c.decodeIfPresent(Double.self, forKey: .height) ?? 2100,
                  sill: try c.decodeIfPresent(Double.self, forKey: .sill) ?? 0, doorStyle: try c.decodeIfPresent(DoorStyle.self, forKey: .doorStyle) ?? .single,
                  windowStyle: try c.decodeIfPresent(WindowStyle.self, forKey: .windowStyle) ?? .casement, frameWidth: try c.decodeIfPresent(Double.self, forKey: .frameWidth) ?? 50,
                  material: try c.decodeIfPresent(String.self, forKey: .material), params: try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:])
    }
    /// Applies the type's parameters to an instance.
    public func apply(to o: inout OpeningGeom) {
        o.kind = kind; o.width = width; o.height = height; o.sill = sill; o.doorStyle = doorStyle; o.windowStyle = windowStyle
        o.frameWidth = frameWidth; o.typeName = name
    }
    public static let library: [OpeningType] = [
        OpeningType(name: "Single Door 900x2100", kind: .door, width: 900, height: 2100, params: ["FireRating": "", "Finish": "Painted"]),
        OpeningType(name: "Single Door 800x2100", kind: .door, width: 800, height: 2100),
        OpeningType(name: "Double Door 1600x2100", kind: .door, width: 1600, height: 2100, doorStyle: .double),
        OpeningType(name: "Sliding Door 1800x2200", kind: .door, width: 1800, height: 2200, doorStyle: .sliding),
        OpeningType(name: "Garage Door 2500x2200", kind: .door, width: 2500, height: 2200, doorStyle: .garage),
        OpeningType(name: "Casement 1200x1200", kind: .window, width: 1200, height: 1200, sill: 900, windowStyle: .casement, params: ["UValue": "1.1"]),
        OpeningType(name: "Double Casement 1500x1400", kind: .window, width: 1500, height: 1400, sill: 800, windowStyle: .doubleCasement),
        OpeningType(name: "Fixed 600x1800", kind: .window, width: 600, height: 1800, sill: 300, windowStyle: .fixed),
        OpeningType(name: "Sliding 2400x2200", kind: .window, width: 2400, height: 2200, sill: 0, windowStyle: .sliding),
        OpeningType(name: "Opening 1000x2100", kind: .opening, width: 1000, height: 2100),
    ]
}

public struct PaperSize: Codable, Hashable {
    public var name: String; public var width: Double; public var height: Double
    public init(name: String, width: Double, height: Double) { self.name = name; self.width = width; self.height = height }
    public static let standard: [PaperSize] = [
        PaperSize(name: "A4", width: 297, height: 210), PaperSize(name: "A3", width: 420, height: 297),
        PaperSize(name: "A2", width: 594, height: 420), PaperSize(name: "A1", width: 841, height: 594),
        PaperSize(name: "A0", width: 1189, height: 841), PaperSize(name: "Letter", width: 279.4, height: 215.9),
        PaperSize(name: "Tabloid", width: 431.8, height: 279.4), PaperSize(name: "ARCH D", width: 914.4, height: 609.6),
    ]
}

public enum ViewKind: String, Codable, CaseIterable { case plan, ceiling, elevationNorth, elevationSouth, elevationEast, elevationWest, section, axonometric, perspective }

/// A viewport on a sheet showing model space at a scale (1:scale).
public struct Viewport: Codable, Hashable {
    public var origin: Vec2          // lower-left on paper (mm)
    public var size: Vec2            // on paper (mm)
    public var viewCenter: Vec2      // model coordinates
    public var scale: Double         // model units per paper mm (e.g. 100 for 1:100 in mm)
    public var view: ViewKind
    public var level: Int?
    public var title: String
    public init(origin: Vec2, size: Vec2, viewCenter: Vec2, scale: Double = 100, view: ViewKind = .plan, level: Int? = nil, title: String = "") {
        self.origin = origin; self.size = size; self.viewCenter = viewCenter; self.scale = scale; self.view = view; self.level = level; self.title = title
    }
}

public struct Layout: Codable, Hashable {
    public var name: String; public var paper: PaperSize; public var viewports: [Viewport]
    /// Paper-space annotation entities (title block, notes), in mm.
    public var entities: [Entity]
    public var titleBlock: [String: String]
    public init(name: String, paper: PaperSize = PaperSize.standard[1], viewports: [Viewport] = [], entities: [Entity] = [], titleBlock: [String: String] = [:]) {
        self.name = name; self.paper = paper; self.viewports = viewports; self.entities = entities; self.titleBlock = titleBlock
    }
}

public struct NamedView: Codable, Hashable {
    public var name: String; public var center: Vec2; public var height: Double
    public var camera: Camera?
    public init(name: String, center: Vec2, height: Double, camera: Camera? = nil) { self.name = name; self.center = center; self.height = height; self.camera = camera }
}

public struct Camera: Codable, Hashable {
    public var eye: Vec3; public var target: Vec3; public var fov: Double; public var orthographic: Bool
    public init(eye: Vec3, target: Vec3, fov: Double = 50, orthographic: Bool = false) { self.eye = eye; self.target = target; self.fov = fov; self.orthographic = orthographic }
}

public struct ProjectInfo: Codable, Hashable {
    public var name: String = "Untitled Project"
    public var number: String = ""
    public var client: String = ""
    public var address: String = ""
    public var author: String = ""
    public var latitude: Double = 44.43
    public var longitude: Double = 26.10
    /// Angle of project north from up, degrees.
    public var northAngle: Double = 0
    public init() {}
}

public struct ArchiDocument: Codable, Hashable {
    /// 1: 1.0 preview. 2: optional BIM fields (slab slope, niches, marks, opening types, phases, terrain,
    /// curtain-wall grids, area plans). Version 2 only adds optional keys, so 1 → 2 needs no data change;
    /// the bump stops older builds from opening (and silently dropping) the new data.
    public static let currentFormatVersion = 2
    public var formatVersion: Int = ArchiDocument.currentFormatVersion
    public var info = ProjectInfo()
    public var units: Units = .millimeters
    public var layers: [Layer]
    public var currentLayer: String = "0"
    public var linetypes: [Linetype] = Linetype.standard
    public var textStyles: [TextStyle] = [TextStyle(name: "Standard")]
    public var dimStyles: [DimStyle] = [DimStyle(name: "Standard"), DimStyle(name: "Architectural 1:100", textHeight: 250, arrowSize: 150, arrow: .architecturalTick, extensionOffset: 100, extensionExtend: 150, textGap: 80)]
    public var currentDimStyle: String = "Standard"
    public var blocks: [String: Block] = [:]
    public var entities: [Entity] = []
    public var elements: [BIMElement] = []
    public var levels: [Level] = [Level(id: 0, name: "Ground Floor", elevation: 0), Level(id: 1, name: "First Floor", elevation: 3000)]
    public var currentLevel: Int = 0
    public var materials: [Material] = Material.library
    public var wallTypes: [WallType] = WallType.library
    public var layouts: [Layout] = [Layout(name: "Sheet 1")]
    public var namedViews: [NamedView] = []
    /// AutoCAD-style system variables (OSMODE, ORTHOMODE, TEXTSIZE…), stored as strings.
    public var variables: [String: String] = [:]
    public var nextID: Int = 1
    /// Door/window/opening type catalog.
    public var openingTypes: [OpeningType] = OpeningType.library
    /// Construction phases in time order (elements carry props "phaseCreated"/"phaseDemolished").
    public var phases: [String] = ["Existing", "New Construction"]
    /// Keynote legend: key → description (elements reference keys through props["keynote"]).
    public var keynotes: [String: String] = [:]

    public init() {
        layers = [
            Layer(name: "0"),
            Layer(name: "A-WALL", color: RGBA(0.95, 0.95, 0.95), lineweight: 0.5),
            Layer(name: "A-DOOR", color: RGBA(0.35, 0.8, 1.0), lineweight: 0.25),
            Layer(name: "A-GLAZ", color: RGBA(0.4, 0.9, 0.9), lineweight: 0.18),
            Layer(name: "A-ELEMENTS", color: RGBA(0.85, 0.85, 0.85), lineweight: 0.35),
            Layer(name: "A-ANNO-DIMS", color: RGBA(0.961, 0.773, 0.094), lineweight: 0.18),
            Layer(name: "A-ANNO-TEXT", color: RGBA(1, 1, 1), lineweight: 0.18),
            Layer(name: "A-AREA", color: RGBA(1.0, 0.55, 0.3), lineweight: 0.13),
            Layer(name: "S-GRID", color: RGBA(0.9, 0.3, 0.3), linetype: "Center", lineweight: 0.13),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, info, units, layers, currentLayer, linetypes, textStyles, dimStyles, currentDimStyle, blocks, entities, elements
        case levels, currentLevel, materials, wallTypes, layouts, namedViews, variables, nextID, openingTypes, phases, keynotes
    }

    /// Tolerant decoding: every collection falls back to its default when absent, so older files keep opening.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func opt<T: Decodable>(_ k: CodingKeys, _ into: inout T) throws { if let v = try c.decodeIfPresent(T.self, forKey: k) { into = v } }
        try opt(.formatVersion, &formatVersion); try opt(.info, &info); try opt(.units, &units); try opt(.layers, &layers)
        try opt(.currentLayer, &currentLayer); try opt(.linetypes, &linetypes); try opt(.textStyles, &textStyles); try opt(.dimStyles, &dimStyles)
        try opt(.currentDimStyle, &currentDimStyle); try opt(.blocks, &blocks); try opt(.entities, &entities); try opt(.elements, &elements)
        try opt(.levels, &levels); try opt(.currentLevel, &currentLevel); try opt(.materials, &materials); try opt(.wallTypes, &wallTypes)
        try opt(.layouts, &layouts); try opt(.namedViews, &namedViews); try opt(.variables, &variables); try opt(.nextID, &nextID)
        try opt(.openingTypes, &openingTypes); try opt(.phases, &phases); try opt(.keynotes, &keynotes)
        let maxID = max(entities.map(\.id).max() ?? 0, elements.map(\.id).max() ?? 0)
        if nextID <= maxID { nextID = maxID + 1 }
    }

    public func openingType(_ n: String?) -> OpeningType? {
        guard let n = n else { return nil }
        return openingTypes.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }

    // MARK: IDs and lookup
    public mutating func allocateID() -> EntityID { defer { nextID += 1 }; return nextID }

    public func layer(named n: String) -> Layer? { layers.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public func layerIndex(_ n: String) -> Int? { layers.firstIndex { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public mutating func ensureLayer(_ n: String) { if layer(named: n) == nil { layers.append(Layer(name: n)) } }

    public func entity(_ id: EntityID) -> Entity? { entities.first { $0.id == id } }
    public func entityIndex(_ id: EntityID) -> Int? { entities.firstIndex { $0.id == id } }
    public func element(_ id: EntityID) -> BIMElement? { elements.first { $0.id == id } }
    public func elementIndex(_ id: EntityID) -> Int? { elements.firstIndex { $0.id == id } }
    public func level(_ id: Int) -> Level? { levels.first { $0.id == id } }
    public func material(_ n: String?) -> Material? { guard let n = n else { return nil }; return materials.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public func linetype(_ n: String) -> Linetype? { linetypes.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public var dimStyle: DimStyle { dimStyles.first { $0.name == currentDimStyle } ?? dimStyles[0] }
    public func dimStyle(_ n: String) -> DimStyle { dimStyles.first { $0.name == n } ?? dimStyle }

    // MARK: Mutation
    @discardableResult
    public mutating func add(_ geometry: Geometry, layer: String? = nil, color: ColorRef = .byLayer) -> EntityID {
        let id = allocateID()
        entities.append(Entity(id: id, layer: layer ?? currentLayer, color: color, geometry: geometry))
        return id
    }
    @discardableResult
    public mutating func add(_ e: Entity) -> EntityID {
        var e = e; e.id = allocateID(); ensureLayer(e.layer); entities.append(e); return e.id
    }
    @discardableResult
    public mutating func addElement(_ g: BIMGeometry, level: Int? = nil, layer: String? = nil, material: String? = nil, name: String = "") -> EntityID {
        let id = allocateID()
        let lay: String
        switch g {
        case .wall, .curtainWall: lay = "A-WALL"
        case .opening(let o): lay = o.kind == .window ? "A-GLAZ" : "A-DOOR"
        case .space: lay = "A-AREA"
        case .gridLine: lay = "S-GRID"
        default: lay = "A-ELEMENTS"
        }
        let l = layer ?? lay
        ensureLayer(l)
        elements.append(BIMElement(id: id, level: level ?? currentLevel, name: name, layer: l, material: material ?? defaultMaterial(for: g), geometry: g))
        return id
    }
    func defaultMaterial(for g: BIMGeometry) -> String? {
        switch g {
        case .wall: return "Plaster"
        case .slab, .column, .beam, .stair: return "Concrete"
        case .roof: return "Roof Tiles"
        case .opening(let o): return o.kind == .window ? "Glass" : "Wood"
        case .curtainWall: return "Glass"
        case .railing: return "Steel"
        case .component: return "Wood"
        default: return nil
        }
    }
    /// Removes entities and elements. Openings hosted in deleted walls are removed too.
    public mutating func remove(ids: Set<EntityID>) {
        entities.removeAll { ids.contains($0.id) }
        elements.removeAll { el in
            if ids.contains(el.id) { return true }
            if case .opening(let o) = el.geometry, ids.contains(o.hostWall) { return true }
            return false
        }
    }
    public func contains(_ id: EntityID) -> Bool { entity(id) != nil || element(id) != nil }
    public var allIDs: [EntityID] { entities.map(\.id) + elements.map(\.id) }

    /// Effective color of an entity, resolving ByLayer.
    public func resolvedColor(_ e: Entity) -> RGBA {
        switch e.color {
        case .byLayer, .byBlock: return layer(named: e.layer)?.color ?? .white
        case .aci(let i): return aciColor(i)
        case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        }
    }
    public func resolvedLinetype(_ e: Entity) -> Linetype? {
        let n = e.linetype ?? layer(named: e.layer)?.linetype ?? "Continuous"
        return linetype(n == "ByLayer" ? (layer(named: e.layer)?.linetype ?? "Continuous") : n)
    }
    public func resolvedLineweight(_ e: Entity) -> Double { e.lineweight ?? layer(named: e.layer)?.lineweight ?? 0.25 }

    public func isVisible(layer n: String) -> Bool { guard let l = layer(named: n) else { return true }; return l.visible && !l.frozen }
    public func isEditable(layer n: String) -> Bool { layer(named: n)?.isEditable ?? true }

    public func variable(_ name: String) -> String? { variables[name.uppercased()] }
    public mutating func setVariable(_ name: String, _ value: String) { variables[name.uppercased()] = value }
}

/// Snapshot-based undo history. ArchiDocument is a value type, so snapshots share storage until mutated.
public struct UndoHistory {
    public struct Entry { public var label: String; public var doc: ArchiDocument }
    public private(set) var undoStack: [Entry] = []
    public private(set) var redoStack: [Entry] = []
    public var limit = 300
    public init() {}
    public mutating func record(_ label: String, before: ArchiDocument) {
        undoStack.append(Entry(label: label, doc: before))
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }
    public mutating func undo(current: ArchiDocument) -> (ArchiDocument, String)? {
        guard let e = undoStack.popLast() else { return nil }
        redoStack.append(Entry(label: e.label, doc: current)); return (e.doc, e.label)
    }
    public mutating func redo(current: ArchiDocument) -> (ArchiDocument, String)? {
        guard let e = redoStack.popLast() else { return nil }
        undoStack.append(Entry(label: e.label, doc: current)); return (e.doc, e.label)
    }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }
}
