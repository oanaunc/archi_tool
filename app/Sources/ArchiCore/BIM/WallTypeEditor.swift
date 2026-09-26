// Oanarina Archi Tool — GPL-3.0-or-later
// Compound wall type editing (BIM-014/015): ply lists in text form, validation, and propagation of an edited type to
// the walls that use it (thickness kept in step with the build-up; the core — Structure plies — defines the core faces).
import Foundation

public enum WallTypeEditor {
    public static let functions = ["Structure", "Thermal", "Finish", "Membrane", "Substrate", "Air"]

    /// "Plaster 15 Finish; Brick 240 Structure; Mineral Wool 100 Thermal" → plies (left face first). Material names may
    /// contain spaces; the thickness is the first number, the function (optional) follows it. nil on malformed input.
    public static func parse(_ spec: String, doc: ArchiDocument) -> [WallType.Ply]? {
        var out: [WallType.Ply] = []
        for part in spec.split(whereSeparator: { $0 == ";" || $0 == "|" }) {
            let words = part.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard let ti = words.firstIndex(where: { Double($0) != nil }), ti > 0, let t = Double(words[ti]), t > 0 else { return nil }
            let mat = words[..<ti].joined(separator: " ")
            let fnWord = words.dropFirst(ti + 1).joined(separator: " ")
            let fn = fnWord.isEmpty ? "Structure" : (functions.first { $0.lowercased().hasPrefix(fnWord.lowercased()) } ?? fnWord.capitalized)
            let known = doc.material(mat)?.name ?? mat
            out.append(WallType.Ply(material: known, thickness: t, function: fn))
        }
        return out.isEmpty ? nil : out
    }

    public static func describe(_ wt: WallType) -> String {
        wt.plies.map { "\($0.material) \(fmt($0.thickness)) \($0.function)" }.joined(separator: "; ")
    }

    /// Core boundaries (offsets from the left face) — the span of the Structure plies (whole wall when none).
    public static func core(_ wt: WallType) -> (from: Double, to: Double) {
        var t = 0.0, a: Double? = nil, b = 0.0
        for p in wt.plies {
            if p.function == "Structure" { if a == nil { a = t }; b = t + p.thickness }
            t += p.thickness
        }
        return a.map { ($0, b) } ?? (0, t)
    }

    /// Adds or replaces a wall type; walls of that type take its thickness (and missing materials are created).
    /// Returns the number of walls updated.
    @discardableResult
    public static func apply(_ wt: WallType, doc: inout ArchiDocument) -> Int {
        if let i = doc.wallTypes.firstIndex(where: { $0.name == wt.name }) { doc.wallTypes[i] = wt } else { doc.wallTypes.append(wt) }
        for p in wt.plies where doc.material(p.material) == nil {
            doc.materials.append(Material(name: p.material, color: RGBA(0.8, 0.78, 0.74)))
        }
        var n = 0
        for i in doc.elements.indices {
            guard case .wall(var w) = doc.elements[i].geometry, w.wallType == wt.name, abs(w.thickness - wt.thickness) > 1e-9 else { continue }
            w.thickness = wt.thickness; doc.elements[i].geometry = .wall(w); n += 1
        }
        return n
    }
}
