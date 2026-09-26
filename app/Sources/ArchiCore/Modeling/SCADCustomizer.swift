// Oanarina Archi Tool — GPL-3.0-or-later
// OpenSCAD Customizer parameters (M3D-093) and scripted parametric objects (PAR-016): the top-level assignments of a
// script (before the first module/function and outside a "[Hidden]" group) are its parameters, with the Customizer
// comment syntax for ranges ("// [10:100]", "// [0:5:100]") and choices ("// [a, b, c]"). Changing a value rewrites the
// assignment and regenerates the object.
import Foundation

public enum SCADCustomizer {
    public struct Parameter: Hashable {
        public enum Kind: String { case number, bool, string, vector }
        public var name: String
        public var value: String
        public var kind: Kind
        public var min: Double?
        public var max: Double?
        public var step: Double?
        public var options: [String]
        public var description: String
        public var group: String
        /// Line index of the assignment in the script.
        public var line: Int
    }

    static func kind(of v: String) -> Parameter.Kind {
        let t = v.trimmingCharacters(in: .whitespaces)
        if t == "true" || t == "false" { return .bool }
        if t.hasPrefix("\"") { return .string }
        if t.hasPrefix("[") { return .vector }
        return .number
    }

    /// Parameters of a script, in order.
    public static func parameters(_ script: String) -> [Parameter] {
        var out: [Parameter] = []
        var group = "Parameters", desc = ""
        var depth = 0
        for (i, raw) in script.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if depth == 0, line.hasPrefix("module ") || line.hasPrefix("function ") { break }
            if line.hasPrefix("/*"), let a = line.range(of: "["), let b = line.range(of: "]"), a.upperBound < b.lowerBound {
                group = String(line[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces)
                if group.lowercased() == "hidden" { break }
                continue
            }
            if line.hasPrefix("//") { desc = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces); continue }
            let opens = line.filter { $0 == "{" }.count, closes = line.filter { $0 == "}" }.count
            defer { depth += opens - closes }
            guard depth == 0, let eq = line.firstIndex(of: "="), let semi = line.firstIndex(of: ";"), eq < semi else { if !line.isEmpty { desc = "" }; continue }
            let name = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }), !name.hasPrefix("$") else { desc = ""; continue }
            let value = String(line[line.index(after: eq)..<semi]).trimmingCharacters(in: .whitespaces)
            var p = Parameter(name: name, value: value, kind: kind(of: value), min: nil, max: nil, step: nil, options: [], description: desc, group: group, line: i)
            let rest = line[line.index(after: semi)...]
            if let c = rest.range(of: "//") {
                let comment = rest[c.upperBound...].trimmingCharacters(in: .whitespaces)
                if comment.hasPrefix("["), comment.hasSuffix("]") {
                    let body = String(comment.dropFirst().dropLast())
                    let nums = body.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if !body.contains(","), nums.count >= 1, nums.allSatisfy({ $0 != nil }) {
                        let n = nums.compactMap { $0 }
                        switch n.count {
                        case 1: p.max = n[0]; p.min = 0
                        case 2: p.min = n[0]; p.max = n[1]
                        default: p.min = n[0]; p.step = n[1]; p.max = n[2]
                        }
                    } else {
                        p.options = body.split(separator: ",").map { String($0.split(separator: ":").first ?? "").trimmingCharacters(in: .whitespaces) }
                    }
                }
            }
            out.append(p)
            desc = ""
        }
        return out
    }

    public enum SetError: Error, Equatable, CustomStringConvertible {
        case unknown(String), outOfRange(String), notAnOption(String), badValue(String)
        public var description: String {
            switch self {
            case .unknown(let n): return "Unknown parameter \(n)."
            case .outOfRange(let s): return "Value out of range \(s)."
            case .notAnOption(let s): return "Choose one of \(s)."
            case .badValue(let s): return "Invalid value for \(s)."
            }
        }
    }

    /// The script with one parameter changed (validated against its range / choices).
    public static func set(_ script: String, _ name: String, _ value0: String) throws -> String {
        guard let p = parameters(script).first(where: { $0.name == name }) else { throw SetError.unknown(name) }
        var value = value0.trimmingCharacters(in: .whitespaces)
        switch p.kind {
        case .number:
            guard let v = Double(value) else { throw SetError.badValue(name) }
            if let lo = p.min, let hi = p.max, v < lo - 1e-12 || v > hi + 1e-12 { throw SetError.outOfRange("\(fmt(lo))…\(fmt(hi))") }
            if !p.options.isEmpty, !p.options.contains(where: { Double($0) == v }) { throw SetError.notAnOption(p.options.joined(separator: ", ")) }
        case .bool:
            guard value == "true" || value == "false" else { throw SetError.badValue(name) }
        case .string:
            if !value.hasPrefix("\"") { value = "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            let bare = String(value.dropFirst().dropLast())
            if !p.options.isEmpty, !p.options.contains(where: { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == bare }) { throw SetError.notAnOption(p.options.joined(separator: ", ")) }
        case .vector:
            guard value.hasPrefix("["), value.hasSuffix("]") else { throw SetError.badValue(name) }
        }
        var lines = script.components(separatedBy: "\n")
        let l = lines[p.line]
        guard let eq = l.firstIndex(of: "="), let semi = l.firstIndex(of: ";") else { throw SetError.badValue(name) }
        lines[p.line] = String(l[...eq]) + " " + value + String(l[semi...])
        return lines.joined(separator: "\n")
    }
}

enum SCADObjectCommands {
    static var all: [CommandDef] { [scadObject] }

    static var scadObject: CommandDef {
        CommandDef("SCADOBJECT", aliases: ["SCRIPTOBJECT", "CUSTOMIZER", "GDLOBJECT"], category: "3D", summary: "Scripted parametric objects (OpenSCAD language, GDL-like): New from a script or File, list Params (Customizer ranges and choices), Set a parameter to regenerate.") { ed in
            let k = try await ed.getKeyword("Scripted object [New/File/Params/Set]", ["New", "File", "Params", "Set"], defaultValue: "New") ?? "New"
            if k == "Params" || k == "Set" {
                guard case .pick(let pk) = try await ed.pickObject("Select a scripted object", filter: { ModelingCommands.solidOf(ed.doc, $0)?.source?.kind == .script }),
                      let s = ModelingCommands.solidOf(ed.doc, pk.id), var src = s.source, let code = src.expression else { return }
                let ps = SCADCustomizer.parameters(code)
                if k == "Params" {
                    if ps.isEmpty { ed.print("The script has no parameters.") }
                    for p in ps {
                        var r = ""
                        if let lo = p.min, let hi = p.max { r = " [\(fmt(lo))…\(fmt(hi))\(p.step.map { " step \(fmt($0))" } ?? "")]" }
                        if !p.options.isEmpty { r = " [\(p.options.joined(separator: ", "))]" }
                        ed.print("\(p.group) › \(p.name) = \(p.value)\(r)\(p.description.isEmpty ? "" : " — \(p.description)")")
                    }
                    return
                }
                guard let assign = try await ed.getString("Parameter = value"), let eq = assign.firstIndex(of: "=") else { return }
                let name = assign[..<eq].trimmingCharacters(in: .whitespaces), value = String(assign[assign.index(after: eq)...])
                do { src.expression = try SCADCustomizer.set(code, name, value) } catch let e as SCADCustomizer.SetError { throw CommandError.invalid(e.description) }
                guard var n = FeatureSources.build(src, doc: ed.doc) else { throw CommandError.invalid("The script produces no solid with that value.") }
                n.source = src
                ModelingCommands.replace(ed, pk.id, with: n)
                ed.print("\(name) = \(value.trimmingCharacters(in: .whitespaces)): volume " + ModelingCommands.volumeText(CSG.volume(n), units: ed.doc.units) + ".")
                return
            }
            var code: String
            if k == "File" {
                guard let path = try await ed.getString("File (.scad)") else { return }
                guard let t = try? String(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), encoding: .utf8) else { throw CommandError.invalid("Cannot read \(path).") }
                code = t
            } else {
                guard let t = try await ed.getString("OpenSCAD script"), !t.isEmpty else { return }
                code = t.replacingOccurrences(of: "\\n", with: "\n")
            }
            let at = try await ed.getPoint("Specify insertion point <0,0>").point ?? .zero
            let src = SolidSource(kind: .script, profiles: [], params: [at.x, at.y, PrimitiveCommands.z(ed)], expression: code)
            let r = SCAD.evaluate(code)
            for e in r.errors { ed.print("SCAD: \(e)") }
            guard var s = FeatureSources.build(src, doc: ed.doc) else { throw CommandError.invalid("The script produces no solid.") }
            s.source = src
            ed.addEntity(.solid(s))
            ed.print("Scripted object with \(SCADCustomizer.parameters(code).count) parameter(s): volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
        }
    }
}
