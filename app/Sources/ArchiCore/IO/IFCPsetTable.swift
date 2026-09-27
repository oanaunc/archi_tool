// Oanarina Archi Tool — GPL-3.0-or-later
// Standard property / quantity set templates (buildingSMART Pset_ and Qto_ definitions) of IFC2X3, IFC4 and IFC4X3:
// property names, kinds, measure types and enumeration values, and the entities each set applies to. Used by IFC
// validation (reserved Pset_/Qto_ names, unknown properties, value types, enumeration values, applicability).
import Foundation

public final class IFCPsetTable {
    public struct Prop: Hashable { public var name: String; public var kind: String; public var type: String; public var values: [String] }
    public struct PSet: Hashable { public var name: String; public var applicable: [String]; public var templateType: String; public var props: [String: Prop] }

    public let sets: [String: PSet]
    init(_ table: String) {
        var out: [String: PSet] = [:]
        for line in table.split(separator: "\n") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4 else { continue }
            var props: [String: Prop] = [:]
            for p in f[3].split(separator: ",") {
                let q = p.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                guard q.count >= 3 else { continue }
                props[q[0]] = Prop(name: q[0], kind: q[1], type: q[2], values: q.count > 3 ? q[3].split(separator: ";").map(String.init) : [])
            }
            var app: [String] = []
            for part in f[1].split(separator: ",") {
                let name: String = part.split(separator: "/").first.map(String.init) ?? ""
                let t = name.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { app.append(t) }
            }
            out[f[0]] = PSet(name: f[0], applicable: app, templateType: f[2], props: props)
        }
        sets = out
    }

    public static let ifc4 = IFCPsetTable(ifc4Psets)
    public static let ifc2x3 = IFCPsetTable(ifc2x3Psets)
    public static let ifc4x3 = IFCPsetTable(ifc4x3Psets)

    public static func forSchema(_ schema: String) -> IFCPsetTable? {
        let s = schema.uppercased()
        if s.hasPrefix("IFC2X3") { return ifc2x3 }
        if s.hasPrefix("IFC4X3") { return ifc4x3 }
        if s.hasPrefix("IFC4") { return ifc4 }
        return nil
    }
}
