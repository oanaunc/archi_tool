// Oanarina Archi Tool — GPL-3.0-or-later
// CSV/TSV point import/export (survey points: X,Y[,Z][,name][,code] or PNEZD / PENZD layouts).
import Foundation

public struct PointImportOptions {
    /// Column order when there is no header: "XYZ", "PNEZD", "PENZD", "NEZ", "ENZ". nil = detect from the header or XY(Z).
    public var layout: String?
    /// Drawing units per file unit.
    public var scale: Double = 1
    public var layer = "POINTS"
    /// Also add a text label with the point name.
    public var labels = false
    public var labelHeight: Double = 250
    public init() {}
}

public enum PointTable {
    /// Splits delimited text into rows (quotes, doubled quotes, auto-detected delimiter: tab, ';', ',', or whitespace).
    public static func rows(_ text: String) -> [[String]] {
        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        guard let sample = lines.first(where: { $0.contains(where: { $0.isNumber }) }) ?? lines.first else { return [] }
        let delim: Character?
        if sample.contains("\t") { delim = "\t" }
        else if sample.contains(";") { delim = ";" }
        else if sample.contains(",") { delim = "," }
        else { delim = nil }
        return lines.map { line in
            guard let d = delim else { return line.split(whereSeparator: { $0 == " " }).map(String.init) }
            var out: [String] = [], cur = "", q = false
            var it = Array(line), i = 0
            while i < it.count {
                let c = it[i]
                if q {
                    if c == "\"" { if i + 1 < it.count && it[i + 1] == "\"" { cur.append("\""); i += 1 } else { q = false } } else { cur.append(c) }
                } else if c == "\"" { q = true }
                else if c == d { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
                else { cur.append(c) }
                i += 1
            }
            out.append(cur.trimmingCharacters(in: .whitespaces))
            it = []
            return out
        }
    }

    /// Point entities (props "z", "name", "code"); returns entities and the number of skipped rows.
    public static func importPoints(_ text: String, options: PointImportOptions = PointImportOptions()) -> (entities: [Entity], skipped: Int) {
        var rs = rows(text)
        guard !rs.isEmpty else { return ([], 0) }
        var col: [String: Int] = [:]
        let header = rs[0].map { $0.lowercased() }
        let hasHeader = header.contains { Double($0.replacingOccurrences(of: ",", with: ".")) == nil && !$0.isEmpty } &&
            header.contains { ["x", "y", "e", "n", "easting", "northing", "east", "north", "lon", "lat"].contains($0) }
        if hasHeader {
            for (i, h) in header.enumerated() {
                switch h {
                case "x", "e", "easting", "east": col["x"] = i
                case "y", "n", "northing", "north": col["y"] = i
                case "z", "elev", "elevation", "h", "height": col["z"] = i
                case "name", "id", "p", "point", "pt", "number", "label": if col["name"] == nil { col["name"] = i }
                case "code", "d", "desc", "description", "layer": col["code"] = i
                default: break
                }
            }
            rs.removeFirst()
        } else {
            switch (options.layout ?? "").uppercased() {
            case "PNEZD": col = ["name": 0, "y": 1, "x": 2, "z": 3, "code": 4]
            case "PENZD": col = ["name": 0, "x": 1, "y": 2, "z": 3, "code": 4]
            case "NEZ": col = ["y": 0, "x": 1, "z": 2]
            case "ENZ": col = ["x": 0, "y": 1, "z": 2]
            default:
                // A leading non-numeric column followed by numbers = P,E,N[,Z][,D]; otherwise X,Y[,Z][,name].
                let r0 = rs[0]
                if r0.count >= 3, Double(r0[0]) == nil, Double(r0[1]) != nil {
                    col = ["name": 0, "x": 1, "y": 2]; if r0.count > 3 { col["z"] = 3 }; if r0.count > 4 { col["code"] = 4 }
                } else {
                    col = ["x": 0, "y": 1]; if r0.count > 2 { col["z"] = 2 }; if r0.count > 3 { col["name"] = 3 }
                }
            }
        }
        guard let xi = col["x"], let yi = col["y"] else { return ([], rs.count) }
        var out: [Entity] = []
        var skipped = 0
        for r in rs {
            func v(_ i: Int?) -> Double? { i.flatMap { $0 < r.count ? Double(r[$0]) : nil } }
            guard let x = v(xi), let y = v(yi) else { skipped += 1; continue }
            let p = Vec2(x * options.scale, y * options.scale)
            var props: [String: String] = [:]
            if let z = v(col["z"]) { props["z"] = fmt(z * options.scale, 6) }
            if let ni = col["name"], ni < r.count, !r[ni].isEmpty { props["name"] = r[ni] }
            if let ci = col["code"], ci < r.count, !r[ci].isEmpty { props["code"] = r[ci] }
            out.append(Entity(layer: options.layer, geometry: .point(p), props: props))
            if options.labels, let n = props["name"] {
                out.append(Entity(layer: options.layer + "-LABELS", geometry: .text(TextGeom(position: p + Vec2(options.labelHeight * 0.4, options.labelHeight * 0.4), height: options.labelHeight, content: n))))
            }
        }
        return (out, skipped)
    }

    /// CSV of point entities: name,x,y,z,code,layer.
    public static func exportPoints(_ doc: ArchiDocument, ids: Set<EntityID>? = nil, delimiter: String = ",") -> String {
        var lines = [["name", "x", "y", "z", "code", "layer"].joined(separator: delimiter)]
        func esc(_ s: String) -> String { s.contains(delimiter) || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        for e in doc.entities where ids == nil || ids!.contains(e.id) {
            guard case .point(let p) = e.geometry else { continue }
            lines.append([esc(e.props["name"] ?? "\(e.id)"), fmt(p.x, 6), fmt(p.y, 6), e.props["z"] ?? "0", esc(e.props["code"] ?? ""), esc(e.layer)].joined(separator: delimiter))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
