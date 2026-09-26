// Oanarina Archi Tool — GPL-3.0-or-later
// IFC schema tables (IFC2X3, IFC4, IFC4X3 ADD2): every entity with its supertype, explicit attributes (name, kind,
// OPTIONAL), attributes redeclared as DERIVED and the ABSTRACT flag; defined types with their underlying kind. Used by
// ifcXML conversion (attribute names) and IFC schema validation (attribute counts, kinds, required values).
import Foundation

public final class IFCSchemaTable {
    struct Attr { let name: String; let kind: String; let optional: Bool }
    struct EntityDef { let name: String; let parent: String?; let own: [Attr]; let derived: [Bool]; let abstract: Bool }

    let entities: [String: EntityDef]
    let types: [String: (name: String, kind: String)]
    public let name: String

    init(name: String, table: String, types typeList: String) {
        self.name = name
        var out: [String: EntityDef] = [:]
        for line in table.split(separator: "\n") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4 else { continue }
            let own = f[2].isEmpty ? [] : f[2].split(separator: ",").map { a -> Attr in
                let p = a.split(separator: ":")
                var k = p.count > 1 ? String(p[1]) : "s"
                let opt = k.hasSuffix("?")
                if opt { k.removeLast() }
                return Attr(name: String(p[0]), kind: k, optional: opt)
            }
            out[f[0].uppercased()] = EntityDef(name: f[0], parent: f[1].isEmpty ? nil : f[1], own: own, derived: f[3].map { $0 == "1" },
                                               abstract: f.count > 4 && f[4] == "abstract")
        }
        entities = out
        var t: [String: (String, String)] = [:]
        for x in typeList.split(separator: " ") {
            let p = x.split(separator: ":"); t[p[0].uppercased()] = (String(p[0]), p.count > 1 ? String(p[1]) : "s")
        }
        types = t
    }

    public static let ifc4 = IFCSchemaTable(name: "IFC4", table: ifc4Table, types: ifc4Types)
    public static let ifc2x3 = IFCSchemaTable(name: "IFC2X3", table: ifc2x3Table, types: ifc2x3Types)
    public static let ifc4x3 = IFCSchemaTable(name: "IFC4X3_ADD2", table: ifc4x3add2Table, types: ifc4x3add2Types)

    /// Table of a FILE_SCHEMA identifier.
    public static func forSchema(_ schema: String) -> IFCSchemaTable? {
        let s = schema.uppercased()
        if s.hasPrefix("IFC2X3") { return ifc2x3 }
        if s.hasPrefix("IFC4X3") { return ifc4x3 }
        if s == "IFC4" || s.hasPrefix("IFC4_") || s.hasPrefix("IFC4ADD") { return ifc4 }
        return nil
    }

    public func contains(_ entity: String) -> Bool { entities[entity.uppercased()] != nil }
    public func isAbstract(_ entity: String) -> Bool { entities[entity.uppercased()]?.abstract ?? false }
    /// Proper-case class name.
    public func className(_ entity: String) -> String? { entities[entity.uppercased()]?.name }
    public func isSubtype(_ entity: String, of ancestor: String) -> Bool {
        var cur: String? = entity.uppercased()
        let a = ancestor.uppercased()
        while let c = cur { if c == a { return true }; cur = entities[c]?.parent?.uppercased() }
        return false
    }

    /// All explicit attributes of an entity (supertypes first) with their derived flag in this entity.
    func attributes(_ entity: String) -> [(attr: Attr, derived: Bool)]? {
        guard let e = entities[entity.uppercased()] else { return nil }
        var chain: [EntityDef] = [e]
        while let p = chain.last?.parent, let pe = entities[p.uppercased()] { chain.append(pe) }
        let all = chain.reversed().flatMap { $0.own }
        return all.enumerated().map { ($0.element, $0.offset < e.derived.count ? e.derived[$0.offset] : false) }
    }
    /// Number of attributes (explicit, including derived redeclarations) an instance of the entity has.
    public func attributeCount(_ entity: String) -> Int? { attributes(entity)?.count }
    /// Attribute names in instance order.
    public func attributeNames(_ entity: String) -> [String]? { attributes(entity)?.map { $0.attr.name } }
}
