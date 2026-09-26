// Oanarina Archi Tool — GPL-3.0-or-later
// ifcXML (IO-025): IFC4 models in the XML encoding of ISO 10303-28 as configured for ifcXML4 (buildingSMART). Every
// entity instance is an element named after its class with an `id`; attributes of simple types (strings, numbers,
// enumerations in lower case, booleans, lists of numbers) are XML attributes; references are child elements named after
// the attribute holding `<IfcClass ref="iN" xsi:nil="true"/>`; typed values in selects are "<IfcType-wrapper>" elements.
// Export converts the IFC STEP stream (IFCExporter) instance by instance; import converts ifcXML back to a STEP stream
// for the IFC importer (inline nested instances and references in any order are accepted). Attribute order and kinds
// come from the IFC4 schema table (IFCSchemaTable, IFCSchema4.swift).
import Foundation

public enum IFCXML {
    public struct XMLError: Error, LocalizedError { public var message: String; public var errorDescription: String? { "ifcXML: " + message } }

    static var S: IFCSchemaTable { IFCSchemaTable.ifc4 }
    static var entities: [String: IFCSchemaTable.EntityDef] { S.entities }
    static var types: [String: (name: String, kind: String)] { S.types }
    static func attributes(_ upper: String) -> [(attr: IFCSchemaTable.Attr, derived: Bool)]? { S.attributes(upper) }

    // MARK: Export

    static func esc(_ s: String) -> String {
        var o = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": o += "&amp;"; case "<": o += "&lt;"; case ">": o += "&gt;"; case "\"": o += "&quot;"
            case "\n": o += "&#10;"; case "\r": o += "&#13;"; case "\t": o += "&#9;"
            default: o.unicodeScalars.append(c)
            }
        }
        return o
    }
    static func num(_ v: StepValue) -> String? {
        switch v {
        case .real(let d): return IFCExporter.real(d).hasSuffix(".") ? IFCExporter.real(d) + "0" : IFCExporter.real(d)
        case .int(let i): return String(i)
        case .typed(_, let a): return a.first.flatMap(num)
        default: return nil
        }
    }
    static func simpleText(_ v: StepValue, kind: String) -> String? {
        switch v {
        case .null, .derived: return nil
        case .string(let s): return s
        case .enumeration(let e):
            if kind == "b" { return e == "T" ? "true" : (e == "F" ? "false" : "unknown") }
            return e.lowercased()
        case .real, .int: return num(v)
        case .typed(_, let a): return a.first.flatMap { simpleText($0, kind: kind) }
        case .list(let l): return l.compactMap { simpleText($0, kind: kind) }.joined(separator: " ")
        case .ref: return nil
        }
    }

    /// ifcXML document of an IFC4 STEP stream.
    public static func fromSTEP(_ text: String) throws -> String {
        let f = try STEPParser.parse(text)
        guard f.schema.uppercased().hasPrefix("IFC4"), !f.schema.uppercased().hasPrefix("IFC4X") else {
            throw XMLError(message: "ifcXML export needs an IFC4 model (the file is \(f.schema)).")
        }
        let header = headerFields(text)
        var o = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        o += "<ifcXML xmlns=\"http://www.buildingsmart-tech.org/ifcXML/IFC4/Add2\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
        o += "xsi:schemaLocation=\"http://www.buildingsmart-tech.org/ifcXML/IFC4/Add2 http://www.buildingsmart-tech.org/ifcXML/IFC4/Add2/IFC4_ADD2.xsd\" "
        o += "id=\"uos_1\" express=\"http://www.buildingsmart-tech.org/ifc/IFC4/Add2/IFC4_ADD2.exp\" "
        o += "configuration=\"http://www.buildingsmart-tech.org/ifcXML/IFC4/Add2/IFC4_config.xml\">\n"
        o += "  <header>\n"
        for (k, v) in header { o += "    <\(k)>\(esc(v))</\(k)>\n" }
        o += "  </header>\n"
        for e in f.entities.values.sorted(by: { $0.id < $1.id }) {
            o += element(e, f: f, indent: "  ")
        }
        o += "</ifcXML>\n"
        return o
    }

    static func headerFields(_ text: String) -> [(String, String)] {
        guard let r = text.range(of: "FILE_NAME("), let end = text.range(of: ");", range: r.upperBound..<text.endIndex) else { return [] }
        let body = String(text[r.upperBound..<end.lowerBound])
        var strs: [String] = []
        var cur = "", inStr = false
        var it = body.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inStr {
                if c == "'" { if let n = it.next(), n == "'" { cur.append("'") } else { inStr = false; strs.append(cur); cur = "" } } else { cur.append(c) }
            } else if c == "'" { inStr = true }
        }
        let names = ["name", "time_stamp", "author", "organization", "preprocessor_version", "originating_system", "authorization"]
        return zip(names, strs).map { ($0.0, $0.1) }
    }

    static func element(_ e: StepEntity, f: STEPFile, indent: String) -> String {
        guard let attrs = attributes(e.type), let def = entities[e.type] else {
            return "\(indent)<!-- #\(e.id) \(e.type) is not an IFC4 entity -->\n"
        }
        var xmlAttrs = " id=\"i\(e.id)\""
        var children = ""
        for (i, a) in attrs.enumerated() where !a.derived {
            let v = e[i]
            if case .null = v { continue }
            if case .derived = v { continue }
            let k = a.attr.kind
            switch k.first {
            case "s", "r", "u", "i", "b", "n", "x":
                if let t = simpleText(v, kind: k) { xmlAttrs += " \(a.attr.name)=\"\(esc(t))\"" }
            case "L":
                if let l = v.list, l.contains(where: { if case .string = $0 { return true }; return false }) {
                    children += "\(indent)  <\(a.attr.name)>\n"
                    for s in l { children += "\(indent)    <IfcLabel-wrapper>\(esc(s.string ?? ""))</IfcLabel-wrapper>\n" }
                    children += "\(indent)  </\(a.attr.name)>\n"
                } else if let t = simpleText(v, kind: String(k.dropFirst())) { xmlAttrs += " \(a.attr.name)=\"\(esc(t))\"" }
            case "M":
                let rows = (v.list ?? []).map { row in (row.list ?? [row]).compactMap { simpleText($0, kind: String(k.dropFirst())) }.joined(separator: " ") }
                xmlAttrs += " \(a.attr.name)=\"\(esc(rows.joined(separator: ", ")))\""
            default:   // e, v, E: child element
                let items = k == "E" ? (v.list ?? [v]) : [v]
                var inner = ""
                for it in items { inner += value(it, f: f, indent: indent + "    ") }
                if !inner.isEmpty { children += "\(indent)  <\(a.attr.name)>\n\(inner)\(indent)  </\(a.attr.name)>\n" }
            }
        }
        if children.isEmpty { return "\(indent)<\(def.name)\(xmlAttrs)/>\n" }
        return "\(indent)<\(def.name)\(xmlAttrs)>\n\(children)\(indent)</\(def.name)>\n"
    }

    /// A reference or a typed value inside an attribute element.
    static func value(_ v: StepValue, f: STEPFile, indent: String) -> String {
        switch v {
        case .ref(let r):
            let n = f[r].flatMap { entities[$0.type]?.name } ?? "IfcRoot"
            return "\(indent)<\(n) ref=\"i\(r)\" xsi:nil=\"true\"/>\n"
        case .typed(let t, let a):
            let name = types[t.uppercased()]?.name ?? t
            let text = a.first.map { x -> String in
                if case .list(let l) = x { return l.compactMap { simpleText($0, kind: "s") }.joined(separator: " ") }
                return simpleText(x, kind: types[t.uppercased()]?.kind ?? "s") ?? ""
            } ?? ""
            return "\(indent)<\(name)-wrapper>\(esc(text))</\(name)-wrapper>\n"
        case .list(let l): return l.map { value($0, f: f, indent: indent) }.joined()
        default:
            if let t = simpleText(v, kind: "s") { return "\(indent)<IfcLabel-wrapper>\(esc(t))</IfcLabel-wrapper>\n" }
            return ""
        }
    }

    // MARK: Import

    final class Node {
        var name: String; var attrs: [String: String]; var children: [Node] = []; var text = ""
        init(_ n: String, _ a: [String: String]) { name = n; attrs = a }
    }
    final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: Node? = nil
        var stack: [Node] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            var a: [String: String] = [:]
            for (k, v) in attributeDict { a[k.split(separator: ":").last.map(String.init) ?? k] = v; if k.hasPrefix("xsi:") { a["xsi:" + k.dropFirst(4)] = v } }
            let n = Node(local, a)
            if let p = stack.last { p.children.append(n) } else { root = n }
            stack.append(n)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    }

    /// STEP physical file of an ifcXML document (IFC4).
    public static func toSTEP(_ data: Data) throws -> String {
        let p = XMLParser(data: data)
        let tb = TreeBuilder()
        p.delegate = tb
        guard p.parse(), let root = tb.root else { throw XMLError(message: p.parserError?.localizedDescription ?? "not an XML document") }
        guard root.name == "ifcXML" || root.name == "uos" || root.children.contains(where: { entities[$0.name.uppercased()] != nil }) else {
            throw XMLError(message: "the root element is <\(root.name)>, not <ifcXML>")
        }
        // Instance numbers: "i123" → 123 when free, else new numbers after the largest.
        var used: Set<Int> = []
        var idMap: [String: Int] = [:]
        func collectIDs(_ n: Node) {
            if entities[n.name.uppercased()] != nil, n.attrs["ref"] == nil, let id = n.attrs["id"] {
                let digits = Int(id.filter { $0.isNumber }) ?? 0
                if digits > 0 && !used.contains(digits) { used.insert(digits); idMap[id] = digits }
            }
            n.children.forEach(collectIDs)
        }
        collectIDs(root)
        var next = (used.max() ?? 0) + 1
        func newID() -> Int { while used.contains(next) { next += 1 }; used.insert(next); return next }
        var lines: [Int: String] = [:]

        func stepValue(_ text: String, kind: String) -> StepValue {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch kind {
            case "r": return Double(t).map { .real($0) } ?? .null
            case "u": return Int(t).map { .int($0) } ?? (Double(t).map { .real($0) } ?? .null)
            case "i": return Int(t).map { .int($0) } ?? (Double(t).map { .int(Int($0)) } ?? .null)
            case "b": return .enumeration(t.lowercased() == "true" ? "T" : (t.lowercased() == "false" ? "F" : "U"))
            case "n": return .enumeration(t.uppercased())
            default: return .string(text)
            }
        }
        /// Instance number of an entity node (writing it when it is an inline definition).
        func instance(_ n: Node) -> Int? {
            if let r = n.attrs["ref"] {
                if let i = idMap[r] { return i }
                let i = newID(); idMap[r] = i; return i
            }
            let id = n.attrs["id"].flatMap { idMap[$0] } ?? {
                let i = newID(); if let k = n.attrs["id"] { idMap[k] = i }; return i
            }()
            if lines[id] == nil { lines[id] = ""; lines[id] = encode(n) }
            return id
        }
        func childValue(_ c: Node, kind: String) -> StepValue {
            if entities[c.name.uppercased()] != nil { return instance(c).map { .ref($0) } ?? .null }
            if c.name.hasSuffix("-wrapper") {
                let tn = String(c.name.dropLast("-wrapper".count))
                let tk = types[tn.uppercased()]?.kind ?? "s"
                if tk.hasPrefix("L") {
                    return .typed(tn.uppercased(), [.list(c.text.split(separator: " ").map { stepValue(String($0), kind: String(tk.dropFirst())) })])
                }
                return .typed(tn.uppercased(), [stepValue(c.text, kind: tk)])
            }
            return .null
        }
        func encode(_ n: Node) -> String {
            let up = n.name.uppercased()
            guard let attrs = attributes(up) else { return "" }
            var args: [StepValue] = []
            for a in attrs {
                if a.derived { args.append(.derived); continue }
                let k = a.attr.kind
                if let t = n.attrs[a.attr.name] {
                    switch k.first {
                    case "L": args.append(.list(t.split(separator: " ").map { stepValue(String($0), kind: String(k.dropFirst())) }))
                    case "M":
                        args.append(.list(t.split(separator: ",").map { row in .list(row.split(separator: " ").map { stepValue(String($0), kind: String(k.dropFirst())) }) }))
                    case "e", "v", "E": args.append(.string(t))
                    default: args.append(stepValue(t, kind: k))
                    }
                } else if let c = n.children.first(where: { $0.name == a.attr.name }) {
                    if k.hasPrefix("L") {
                        args.append(.list(c.children.map { stepValue($0.text, kind: String(k.dropFirst())) }))
                    } else if k == "E" {
                        args.append(.list(c.children.map { childValue($0, kind: k) }))
                    } else if let first = c.children.first {
                        args.append(childValue(first, kind: k))
                    } else { args.append(.null) }
                } else { args.append(.null) }
            }
            return up + "(" + args.map(format).joined(separator: ",") + ")"
        }
        var roots: [Node] = []
        func topLevel(_ n: Node) { for c in n.children { if entities[c.name.uppercased()] != nil { roots.append(c) } else if c.name != "header" { topLevel(c) } } }
        topLevel(root)
        for n in roots { _ = instance(n) }
        guard !lines.isEmpty else { throw XMLError(message: "no IFC entity instances found") }
        let hdr = root.children.first { $0.name == "header" }
        func h(_ k: String) -> String { IFCExporter.str(hdr?.children.first { $0.name == k }?.text ?? "") }
        var out = "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');\n"
        out += "FILE_NAME(\(h("name")),\(h("time_stamp")),(\(h("author"))),(\(h("organization"))),\(h("preprocessor_version")),\(h("originating_system")),\(h("authorization")));\n"
        out += "FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n"
        for (id, l) in lines.sorted(by: { $0.key < $1.key }) where !l.isEmpty { out += "#\(id)=\(l);\n" }
        out += "ENDSEC;\nEND-ISO-10303-21;\n"
        return out
    }

    static func format(_ v: StepValue) -> String {
        switch v {
        case .ref(let r): return "#\(r)"
        case .int(let i): return String(i)
        case .real(let d): return IFCExporter.real(d)
        case .string(let s): return IFCExporter.str(s)
        case .enumeration(let e): return ".\(e)."
        case .list(let l): return "(" + l.map(format).joined(separator: ",") + ")"
        case .typed(let t, let a): return t + "(" + a.map(format).joined(separator: ",") + ")"
        case .null: return "$"
        case .derived: return "*"
        }
    }

    /// Whether data looks like ifcXML.
    public static func sniff(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        return head.contains("<ifcXML") || head.contains("ifcXML/IFC4")
    }
}
