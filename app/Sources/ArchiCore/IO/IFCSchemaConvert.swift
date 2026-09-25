// Oanarina Archi Tool — GPL-3.0-or-later
// IFC2x3 export (IO-021, Coordination View 2.0): the IFC4 instance stream written by IFCBuilder is rewritten to the
// IFC2X3_TC1 schema — attributes that IFC4 added are dropped (PredefinedType of walls/columns/beams/openings, door and
// window operation types, quantity formulas, material descriptions), IFC4-only classes are mapped to their IFC2x3
// equivalents (door/window types → styles, IfcFurniture → IfcFurnishingElement, terminals → IfcFlowTerminal) and styled
// items get an IfcPresentationStyleAssignment. Attribute orders follow the buildingSMART IFC2x3 TC1 schema.
import Foundation

enum IFCSchemaConvert {
    /// Splits the argument list of a STEP instance at top-level commas (strings and nested lists are kept together).
    static func splitArgs(_ s: Substring) -> [String] {
        var out: [String] = [], cur = "", depth = 0, inStr = false
        var it = s.makeIterator()
        while let c = it.next() {
            if inStr {
                cur.append(c)
                if c == "'" { inStr = false }   // '' re-enters on the next quote
                continue
            }
            switch c {
            case "'": inStr = true; cur.append(c)
            case "(": depth += 1; cur.append(c)
            case ")": depth -= 1; cur.append(c)
            case "," where depth == 0: out.append(cur); cur = ""
            default: cur.append(c)
            }
        }
        out.append(cur)
        return out
    }

    /// Parses "#12=IFCWALL(a,b,c);" into (id, type, args).
    static func parse(_ line: String) -> (id: String, type: String, args: [String])? {
        guard line.hasPrefix("#"), let eq = line.firstIndex(of: "="), let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close, eq < open else { return nil }
        let type = String(line[line.index(after: eq)..<open]).trimmingCharacters(in: .whitespaces)
        return (String(line[..<eq]), type, splitArgs(line[line.index(after: open)..<close]))
    }

    static let keep8: Set<String> = ["IFCWALL", "IFCCOLUMN", "IFCBEAM", "IFCCURTAINWALL", "IFCOPENINGELEMENT", "IFCRAMPFLIGHT", "IFCMEMBER", "IFCPLATE",
                                     "IFCFURNISHINGELEMENT", "IFCSTAIRFLIGHT", "IFCBUILDINGELEMENTPART", "IFCDISCRETEACCESSORY"]
    static let toFlowTerminal: Set<String> = ["IFCSANITARYTERMINAL", "IFCLIGHTFIXTURE", "IFCELECTRICAPPLIANCE", "IFCFLOWTERMINAL", "IFCAIRTERMINAL",
                                              "IFCOUTLET", "IFCFIRESUPPRESSIONTERMINAL", "IFCCOMMUNICATIONSAPPLIANCE", "IFCAUDIOVISUALAPPLIANCE"]
    static let toProxy: Set<String> = ["IFCGEOGRAPHICELEMENT", "IFCSHADINGDEVICE", "IFCCHIMNEY", "IFCCIVILELEMENT", "IFCBUILDINGELEMENTPROXY"]
    /// IFC4-only instances without an IFC2x3 counterpart (written only for IFC4 options); dropped.
    static let dropped: Set<String> = ["IFCMAPCONVERSION", "IFCPROJECTEDCRS"]

    static func toIFC2X3(_ lines: [String], nextId: Int) -> [String] {
        var out: [String] = []
        out.reserveCapacity(lines.count + 64)
        var next = nextId
        var styleAssign: [String: String] = [:]
        for line in lines {
            guard let (id, type, a) = parse(line) else { out.append(line); continue }
            var t = type, args = a
            func keep(_ n: Int) { if args.count > n { args = Array(args.prefix(n)) } }
            switch type {
            case _ where dropped.contains(type): continue
            case _ where keep8.contains(type): keep(8)
            case "IFCFURNITURE": t = "IFCFURNISHINGELEMENT"; keep(8)
            case _ where toFlowTerminal.contains(type): t = "IFCFLOWTERMINAL"; keep(8)
            case _ where toProxy.contains(type):
                t = "IFCBUILDINGELEMENTPROXY"; keep(8); args.append("$")     // IFC2x3: CompositionType
            case "IFCDOOR", "IFCWINDOW": keep(10)
            case "IFCTRANSPORTELEMENT": keep(8); args += ["$", "$", "$"]     // OperationType, CapacityByWeight, CapacityByNumber
            case "IFCSPACE": if args.count >= 11 { args[9] = ".INTERNAL." }     // InteriorOrExteriorSpace
            case "IFCQUANTITYLENGTH", "IFCQUANTITYAREA", "IFCQUANTITYVOLUME", "IFCQUANTITYCOUNT", "IFCQUANTITYWEIGHT", "IFCQUANTITYTIME": keep(4)
            case "IFCMATERIAL": keep(1)
            case "IFCMATERIALLAYER": keep(3)
            case "IFCMATERIALLAYERSET": keep(2)
            case "IFCMATERIALLAYERSETUSAGE": keep(4)
            case "IFCDOORTYPE":
                t = "IFCDOORSTYLE"; keep(8); args += [".NOTDEFINED.", ".NOTDEFINED.", ".F.", ".F."]
            case "IFCWINDOWTYPE":
                t = "IFCWINDOWSTYLE"; keep(8); args += [".NOTDEFINED.", ".NOTDEFINED.", ".F.", ".F."]
            case "IFCSTYLEDITEM":
                // IFC2x3: Styles are IfcPresentationStyleAssignment.
                if args.count == 3 {
                    let styles = args[1]
                    let psa: String
                    if let e = styleAssign[styles] { psa = e } else {
                        psa = "#\(next)"; next += 1
                        out.append("\(psa)=IFCPRESENTATIONSTYLEASSIGNMENT(\(styles));")
                        styleAssign[styles] = psa
                    }
                    args[1] = "(\(psa))"
                }
            default: break
            }
            out.append("\(id)=\(t)(\(args.joined(separator: ",")));")
        }
        return out
    }
}
