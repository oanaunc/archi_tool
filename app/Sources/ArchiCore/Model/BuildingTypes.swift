// Oanarina Archi Tool — GPL-3.0-or-later
// Compound (layered) floor/roof types and view templates.
import Foundation

/// Layer build-up of a floor, ceiling or roof type (top → bottom), like a wall type laid flat.
/// Functions: "Finish" (floor finish on top), "Screed", "Thermal", "Membrane", "Structure", "Ceiling".
public struct SlabType: Codable, Hashable {
    public var name: String
    public var plies: [WallType.Ply]
    /// "floor" or "roof".
    public var usage: String
    public init(name: String, plies: [WallType.Ply], usage: String = "floor") { self.name = name; self.plies = plies; self.usage = usage }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), plies: try c.decodeIfPresent([WallType.Ply].self, forKey: .plies) ?? [],
                  usage: try c.decodeIfPresent(String.self, forKey: .usage) ?? "floor")
    }
    public var thickness: Double { plies.reduce(0) { $0 + $1.thickness } }
    /// Thickness of the finish layers on top (above the first non-finish ply).
    public var finishThickness: Double { plies.prefix { $0.function == "Finish" }.reduce(0) { $0 + $1.thickness } }
    /// Structural core thickness.
    public var structureThickness: Double { plies.filter { $0.function == "Structure" }.reduce(0) { $0 + $1.thickness } }
    /// Ply bands (top-down) as (ply, zTop, zBottom) relative to the top of the slab.
    public func bands() -> [(ply: WallType.Ply, top: Double, bottom: Double)] {
        var z = 0.0, out: [(ply: WallType.Ply, top: Double, bottom: Double)] = []
        for p in plies { out.append((p, z, z - p.thickness)); z -= p.thickness }
        return out
    }
    public static let library: [SlabType] = [
        SlabType(name: "Generic Floor 200", plies: [WallType.Ply(material: "Concrete", thickness: 200)]),
        SlabType(name: "Floor Tiles on Screed 280", plies: [WallType.Ply(material: "Tiles", thickness: 10, function: "Finish"),
                                                            WallType.Ply(material: "Concrete", thickness: 50, function: "Screed"),
                                                            WallType.Ply(material: "Insulation", thickness: 20, function: "Thermal"),
                                                            WallType.Ply(material: "Concrete", thickness: 200, function: "Structure")]),
        SlabType(name: "Timber Floor on Concrete 245", plies: [WallType.Ply(material: "Wood", thickness: 20, function: "Finish"),
                                                               WallType.Ply(material: "Insulation", thickness: 25, function: "Thermal"),
                                                               WallType.Ply(material: "Concrete", thickness: 200, function: "Structure")]),
        SlabType(name: "Warm Flat Roof 390", plies: [WallType.Ply(material: "Stone", thickness: 50, function: "Finish"),
                                                     WallType.Ply(material: "Insulation", thickness: 140, function: "Thermal"),
                                                     WallType.Ply(material: "Concrete", thickness: 200, function: "Structure")], usage: "roof"),
        SlabType(name: "Pitched Tiled Roof 300", plies: [WallType.Ply(material: "Roof Tiles", thickness: 40, function: "Finish"),
                                                         WallType.Ply(material: "Wood", thickness: 60, function: "Membrane"),
                                                         WallType.Ply(material: "Insulation", thickness: 180, function: "Thermal"),
                                                         WallType.Ply(material: "Plaster", thickness: 20, function: "Ceiling")], usage: "roof"),
    ]
}

/// A named set of view settings (Revit view template): document variables applied to a view (phase filter, cut plane,
/// detail level, hidden lines, depth cueing, annotations, worksets/options shown, MEP systems) and layers hidden.
public struct ViewTemplate: Codable, Hashable {
    public var name: String
    /// Variable name (upper-case) → value; an empty value clears the variable in the view.
    public var settings: [String: String]
    /// Layers hidden by the template.
    public var hiddenLayers: [String]
    public init(name: String, settings: [String: String] = [:], hiddenLayers: [String] = []) { self.name = name; self.settings = settings; self.hiddenLayers = hiddenLayers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), settings: try c.decodeIfPresent([String: String].self, forKey: .settings) ?? [:],
                  hiddenLayers: try c.decodeIfPresent([String].self, forKey: .hiddenLayers) ?? [])
    }
    /// Variables a template may carry.
    public static let keys: [String] = ["PHASE", "PHASEFILTER", "CUTPLANE", "DETAILLEVEL", "ELEVHIDDEN", "DEPTHCUE", "ELEVFARCLIP", "ELEVDIMS",
                                        "VIEWANNOTATIONS", "WORKSETSHIDDEN", "DESIGNOPTIONVIEW", "MEPSYSTEMSHOW", "RCP", "MEPCONNECTORS", "ROOFSLOPEARROWS", "HPSCALE",
                                        "VGCATEGORIES", "VIEWFILTERS", "SECTIONPOCHE"]
    /// The document as a view with this template applied.
    public func apply(to doc: ArchiDocument) -> ArchiDocument {
        var d = doc
        for (k, v) in settings { if v.isEmpty { d.variables[k.uppercased()] = nil } else { d.setVariable(k, v) } }
        for l in hiddenLayers { if let i = d.layerIndex(l) { d.layers[i].visible = false } }
        return d
    }
    /// Captures the current view settings of a document.
    public static func capture(_ name: String, from doc: ArchiDocument, hiddenLayers: Bool = true) -> ViewTemplate {
        var s: [String: String] = [:]
        for k in keys { if let v = doc.variable(k) { s[k] = v } }
        return ViewTemplate(name: name, settings: s, hiddenLayers: hiddenLayers ? doc.layers.filter { !$0.visible }.map(\.name) : [])
    }
    public static let library: [ViewTemplate] = [
        ViewTemplate(name: "Working Plan", settings: ["PHASEFILTER": "all", "VIEWANNOTATIONS": "1"]),
        ViewTemplate(name: "Presentation Plan", settings: ["PHASEFILTER": "complete", "MEPCONNECTORS": "0", "ROOFSLOPEARROWS": "0"], hiddenLayers: ["A-AREA-PLAN", "S-GRID"]),
        ViewTemplate(name: "Demolition Plan", settings: ["PHASEFILTER": "demolition"]),
        ViewTemplate(name: "Construction Section", settings: ["ELEVHIDDEN": "1", "DEPTHCUE": "0", "ELEVDIMS": "1", "DETAILLEVEL": "fine"]),
        ViewTemplate(name: "Presentation Elevation", settings: ["ELEVHIDDEN": "0", "DEPTHCUE": "1", "ELEVDIMS": "0", "VIEWANNOTATIONS": "0"]),
    ]
}

extension ArchiDocument {
    public func slabType(_ n: String?) -> SlabType? {
        guard let n = n else { return nil }
        return slabTypes.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    public func viewTemplate(_ n: String?) -> ViewTemplate? {
        guard let n = n else { return nil }
        return viewTemplates.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
}
