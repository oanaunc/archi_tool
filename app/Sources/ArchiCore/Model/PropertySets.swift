// Oanarina Archi Tool — GPL-3.0-or-later
// Property set templates (BIM-129 / BIM-130). Values live in element props as "<Pset>.<Property>" (the IFC exporter
// writes them as IfcPropertySet), so templates only describe names, types, defaults and the categories they apply to.
import Foundation

public struct PsetProperty: Codable, Hashable {
    public enum Kind: String, Codable, CaseIterable { case text, boolean, number, integer, length, label }
    public var name: String
    public var kind: Kind
    public var defaultValue: String?
    public init(_ name: String, _ kind: Kind = .label, defaultValue: String? = nil) { self.name = name; self.kind = kind; self.defaultValue = defaultValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(String.self, forKey: .name), try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .label,
                  defaultValue: try c.decodeIfPresent(String.self, forKey: .defaultValue))
    }

    /// Normalised value, or nil when it does not fit the type.
    public func normalize(_ v: String) -> String? {
        let t = v.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .boolean:
            switch t.lowercased() { case "true", "yes", "1", ".t.": return "true"; case "false", "no", "0", ".f.": return "false"; default: return nil }
        case .number, .length: return Double(t).map { fmt($0, 6) }
        case .integer: return Int(t).map(String.init)
        case .text, .label: return t
        }
    }
}

public struct PsetTemplate: Codable, Hashable {
    public var name: String
    /// Element type names it applies to ("wall", "door", "slab"…); empty = all.
    public var applicableTo: [String]
    public var properties: [PsetProperty]
    public init(name: String, applicableTo: [String] = [], properties: [PsetProperty] = []) { self.name = name; self.applicableTo = applicableTo; self.properties = properties }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), applicableTo: try c.decodeIfPresent([String].self, forKey: .applicableTo) ?? [],
                  properties: try c.decodeIfPresent([PsetProperty].self, forKey: .properties) ?? [])
    }
    public func applies(to typeName: String) -> Bool { applicableTo.isEmpty || applicableTo.contains { $0.caseInsensitiveCompare(typeName) == .orderedSame } }
    public func property(_ n: String) -> PsetProperty? { properties.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }

    /// Standard IFC4 common property sets (subset of properties most used in practice).
    public static let standard: [PsetTemplate] = [
        PsetTemplate(name: "Pset_WallCommon", applicableTo: ["wall", "curtainWall"], properties: [
            PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("LoadBearing", .boolean), PsetProperty("FireRating"),
            PsetProperty("AcousticRating"), PsetProperty("ThermalTransmittance", .number), PsetProperty("Combustible", .boolean), PsetProperty("Compartmentation", .boolean)]),
        PsetTemplate(name: "Pset_SlabCommon", applicableTo: ["slab"], properties: [
            PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("LoadBearing", .boolean), PsetProperty("FireRating"),
            PsetProperty("AcousticRating"), PsetProperty("ThermalTransmittance", .number), PsetProperty("PitchAngle", .number)]),
        PsetTemplate(name: "Pset_DoorCommon", applicableTo: ["door"], properties: [
            PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("FireRating"), PsetProperty("AcousticRating"),
            PsetProperty("SecurityRating"), PsetProperty("HandicapAccessible", .boolean), PsetProperty("FireExit", .boolean), PsetProperty("ThermalTransmittance", .number)]),
        PsetTemplate(name: "Pset_WindowCommon", applicableTo: ["window"], properties: [
            PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("FireRating"), PsetProperty("AcousticRating"),
            PsetProperty("ThermalTransmittance", .number), PsetProperty("GlazingAreaFraction", .number), PsetProperty("Infiltration", .number)]),
        PsetTemplate(name: "Pset_ColumnCommon", applicableTo: ["column"], properties: [PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("LoadBearing", .boolean), PsetProperty("FireRating")]),
        PsetTemplate(name: "Pset_BeamCommon", applicableTo: ["beam"], properties: [PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("LoadBearing", .boolean), PsetProperty("FireRating"), PsetProperty("Span", .length)]),
        PsetTemplate(name: "Pset_RoofCommon", applicableTo: ["roof"], properties: [PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("FireRating"), PsetProperty("ThermalTransmittance", .number)]),
        PsetTemplate(name: "Pset_StairCommon", applicableTo: ["stair"], properties: [PsetProperty("Reference"), PsetProperty("NumberOfRiser", .integer), PsetProperty("NumberOfTreads", .integer),
                                                                                       PsetProperty("RiserHeight", .length), PsetProperty("TreadLength", .length), PsetProperty("FireExit", .boolean), PsetProperty("HandicapAccessible", .boolean)]),
        PsetTemplate(name: "Pset_RailingCommon", applicableTo: ["railing"], properties: [PsetProperty("Reference"), PsetProperty("Height", .length), PsetProperty("IsExternal", .boolean)]),
        PsetTemplate(name: "Pset_SpaceCommon", applicableTo: ["space"], properties: [PsetProperty("Reference"), PsetProperty("IsExternal", .boolean), PsetProperty("GrossPlannedArea", .number),
                                                                                       PsetProperty("NetPlannedArea", .number), PsetProperty("PubliclyAccessible", .boolean), PsetProperty("HandicapAccessible", .boolean)]),
    ]
}

extension ArchiDocument {
    /// Standard and custom templates (custom ones with a standard name replace it).
    public var allPsetTemplates: [PsetTemplate] {
        PsetTemplate.standard.filter { s in !psetTemplates.contains { $0.name.caseInsensitiveCompare(s.name) == .orderedSame } } + psetTemplates
    }
    public func psetTemplate(_ n: String) -> PsetTemplate? { allPsetTemplates.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
}
