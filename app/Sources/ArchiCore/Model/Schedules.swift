// Oanarina Archi Tool — GPL-3.0-or-later
// Schedule definitions (DOC-041…053): tabular views of the model stored in the document.
import Foundation

/// A schedule column: a property/parameter of the scheduled objects, or a calculated value.
public struct ScheduleField: Codable, Hashable {
    /// Property or parameter name (case-insensitive): computed fields (Level, Type, Area, Volume, Length, Perimeter,
    /// Count, Category, ID, Material), element properties (width, height, mark…) or custom parameters (props).
    public var name: String
    /// Column heading (nil = the name).
    public var heading: String?
    /// Calculated field (DOC-043): an expression over the other numeric fields (spaces in names become "_"),
    /// e.g. "Width * Height / 1e6".
    public var formula: String?
    /// Percentage field (DOC-043): this row's value of the named field as a percentage of its total.
    public var percentOf: String?
    /// Summed in group and grand totals (nil = automatic: Area, Volume, Length, Count and calculated fields).
    public var total: Bool?
    /// Decimal places for numeric values (nil = automatic).
    public var decimals: Int?
    public init(name: String, heading: String? = nil, formula: String? = nil, percentOf: String? = nil, total: Bool? = nil, decimals: Int? = nil) {
        self.name = name; self.heading = heading; self.formula = formula; self.percentOf = percentOf; self.total = total; self.decimals = decimals
    }
    public var title: String { heading ?? name }
    public var isCalculated: Bool { formula != nil || percentOf != nil }
}

/// Row filter: field op value (op: = != > < >= <= contains begins).
public struct ScheduleFilter: Codable, Hashable {
    public var field: String; public var op: String; public var value: String
    public init(field: String, op: String, value: String) { self.field = field; self.op = op; self.value = value }
}

/// Sort key.
public struct ScheduleSort: Codable, Hashable {
    public var field: String; public var descending: Bool
    public init(field: String, descending: Bool = false) { self.field = field; self.descending = descending }
}

/// Conditional formatting (DOC-052): rows whose field matches the rule are highlighted in `color`.
public struct ScheduleHighlight: Codable, Hashable {
    public var field: String; public var op: String; public var value: String; public var color: RGBA
    public init(field: String, op: String, value: String, color: RGBA) { self.field = field; self.op = op; self.value = value; self.color = color }
}

public struct ScheduleDefinition: Codable, Hashable {
    public var name: String
    /// walls, doors, windows, openings, rooms, areas, slabs, columns, beams, roofs, stairs, railings, curtainWalls,
    /// components, elements (all), materials (material takeoff), sheets, views, annotations (note blocks), keys.
    public var category: String
    public var fields: [ScheduleField]
    public var filters: [ScheduleFilter]
    public var sort: [ScheduleSort]
    /// Group rows by a field (header per group and, with totals, a subtotal row).
    public var groupBy: String?
    /// false = one row per group only (counts and totals), like Revit's "Itemize every instance" off.
    public var itemize: Bool
    public var totals: Bool
    public var highlights: [ScheduleHighlight]
    /// Key schedules (DOC-045): the key parameter name elements carry (props), and the parameter values per key.
    public var keyParameter: String?
    public var keys: [String: [String: String]]
    /// Embedded schedule (DOC-051): category listed under each row (doors / windows of a room, openings of a wall).
    public var embedded: String?
    public init(name: String, category: String, fields: [ScheduleField] = [], filters: [ScheduleFilter] = [], sort: [ScheduleSort] = [],
                groupBy: String? = nil, itemize: Bool = true, totals: Bool = false, highlights: [ScheduleHighlight] = [],
                keyParameter: String? = nil, keys: [String: [String: String]] = [:], embedded: String? = nil) {
        self.name = name; self.category = category; self.fields = fields; self.filters = filters; self.sort = sort; self.groupBy = groupBy
        self.itemize = itemize; self.totals = totals; self.highlights = highlights; self.keyParameter = keyParameter; self.keys = keys; self.embedded = embedded
    }
    enum CodingKeys: String, CodingKey { case name, category, fields, filters, sort, groupBy, itemize, totals, highlights, keyParameter, keys, embedded }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), category: try c.decodeIfPresent(String.self, forKey: .category) ?? "elements",
                  fields: try c.decodeIfPresent([ScheduleField].self, forKey: .fields) ?? [], filters: try c.decodeIfPresent([ScheduleFilter].self, forKey: .filters) ?? [],
                  sort: try c.decodeIfPresent([ScheduleSort].self, forKey: .sort) ?? [], groupBy: try c.decodeIfPresent(String.self, forKey: .groupBy),
                  itemize: try c.decodeIfPresent(Bool.self, forKey: .itemize) ?? true, totals: try c.decodeIfPresent(Bool.self, forKey: .totals) ?? false,
                  highlights: try c.decodeIfPresent([ScheduleHighlight].self, forKey: .highlights) ?? [],
                  keyParameter: try c.decodeIfPresent(String.self, forKey: .keyParameter), keys: try c.decodeIfPresent([String: [String: String]].self, forKey: .keys) ?? [:],
                  embedded: try c.decodeIfPresent(String.self, forKey: .embedded))
    }
}

/// A project parameter (PAR-023): a named parameter added to elements of some categories, with a default value or a
/// formula over the element's other values; shared parameters (PAR-022) carry the GUID of their shared definition.
public struct ProjectParameter: Codable, Hashable {
    public var name: String
    public var kind: FamilyParameterKind
    /// Categories (wall, door, window, room, slab, …; empty = every element).
    public var categories: [String]
    public var value: String
    public var formula: String?
    public var group: String?
    public var guid: String?
    public init(name: String, kind: FamilyParameterKind = .text, categories: [String] = [], value: String = "", formula: String? = nil, group: String? = nil, guid: String? = nil) {
        self.name = name; self.kind = kind; self.categories = categories; self.value = value; self.formula = formula; self.group = group; self.guid = guid
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), kind: try c.decodeIfPresent(FamilyParameterKind.self, forKey: .kind) ?? .text,
                  categories: try c.decodeIfPresent([String].self, forKey: .categories) ?? [], value: try c.decodeIfPresent(String.self, forKey: .value) ?? "",
                  formula: try c.decodeIfPresent(String.self, forKey: .formula), group: try c.decodeIfPresent(String.self, forKey: .group), guid: try c.decodeIfPresent(String.self, forKey: .guid))
    }
}
