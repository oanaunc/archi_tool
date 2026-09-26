// Oanarina Archi Tool — GPL-3.0-or-later
// Survey field codes (IO-054, "field to finish"): imported survey points carry codes such as "EP1 B", "EP1", "EP1 E",
// "BLD2 C", "TREE". The first token is the feature code with an optional string number (EP1 = feature EP, string 1);
// control tokens start (B, BEG, ST), end (E, END) or close (C, CLO, CLOSE) a string; points with the same feature and
// string number, in file order, are joined into a polyline. A description key table (SURVEYCODES:
// "EP=V-ROAD-EDGE:line; TREE=V-TREE:point; BLD=V-BUILDING:line") gives each feature its layer and whether it draws lines;
// unknown features go to SURVEY-<feature>, and join into lines when a string number or control token is used. Line
// vertices keep their elevations (props "elevations").
import Foundation

public enum SurveyCodes {
    public struct Key: Hashable { public var layer: String; public var line: Bool }

    /// Parses "EP=V-ROAD-EDGE:line; TREE=V-TREE:point".
    public static func keys(_ s: String?) -> [String: Key] {
        var out: [String: Key] = [:]
        for part in (s ?? "").split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[0].isEmpty else { continue }
            let lv = kv[1].split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            out[kv[0].uppercased()] = Key(layer: lv.first.map { String($0) } ?? "SURVEY-" + kv[0].uppercased(), line: lv.count > 1 && lv[1].lowercased().hasPrefix("l"))
        }
        return out
    }

    public struct Parsed: Hashable { public var feature: String; public var string: Int?; public var control: String? }

    /// Feature, string number and control token of a code.
    public static func parse(_ code: String) -> Parsed? {
        let toks = code.uppercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "/" }).map(String.init)
        guard let first = toks.first, first.first?.isLetter == true else { return nil }
        let letters = String(first.prefix { !$0.isNumber })
        let digits = String(first.dropFirst(letters.count))
        var control: String? = nil
        for t in toks.dropFirst() {
            switch t {
            case "B", "BEG", "BEGIN", "ST", "START", "SL": control = "B"
            case "E", "END", "EL": control = "E"
            case "C", "CLO", "CLOSE", "CL": control = "C"
            default: break
            }
        }
        return Parsed(feature: letters, string: Int(digits), control: control)
    }

    public struct Result { public var lines: [Entity]; public var moved: [(EntityID, String)] }

    /// Linework and layers for survey point entities (props "code", optional "z").
    public static func process(_ points: [Entity], keys: [String: Key]) -> Result {
        var open: [String: [(Vec2, Double?)]] = [:]
        var order: [String] = []
        var lines: [Entity] = []
        var moved: [(EntityID, String)] = []
        func layer(_ f: String) -> String { keys[f]?.layer ?? "SURVEY-" + f }
        func flush(_ k: String, closed: Bool) {
            guard let pts = open[k], pts.count >= 2 else { open[k] = nil; return }
            let f = String(k.split(separator: "#").first ?? "")
            var props = ["survey": f, "string": k]
            if pts.allSatisfy({ $0.1 != nil }) { props["elevations"] = pts.map { fmt($0.1!, 3) }.joined(separator: ",") }
            lines.append(Entity(layer: layer(f), geometry: .polyline(PolylineGeom(points: pts.map(\.0), closed: closed && pts.count >= 3)), props: props))
            open[k] = nil
        }
        for e in points {
            guard case .point(let p) = e.geometry, let code = e.props["code"], let c = parse(code) else { continue }
            moved.append((e.id, layer(c.feature)))
            let wantsLine = keys[c.feature]?.line ?? (c.string != nil || c.control != nil)
            guard wantsLine else { continue }
            let k = c.feature + "#" + String(c.string ?? 0)
            if c.control == "B", open[k] != nil { flush(k, closed: false) }
            if open[k] == nil { order.append(k) }
            open[k, default: []].append((p, e.props["z"].flatMap(Double.init)))
            if c.control == "E" { flush(k, closed: false) } else if c.control == "C" { flush(k, closed: true) }
        }
        for k in order where open[k] != nil { flush(k, closed: false) }
        return Result(lines: lines, moved: moved)
    }

    static var command: CommandDef {
        CommandDef("SURVEYLINES", aliases: ["FIELDTOFINISH", "SURVEYLINEWORK"], category: "Insert",
                   summary: "Survey field-to-finish: joins survey points into polylines by their codes (EP1 B … EP1 E, C to close) and moves points to the feature layers of the description keys (variable SURVEYCODES: EP=V-ROAD-EDGE:line; TREE=V-TREE:point).") { ed in
            let sel = ed.selection.isEmpty ? ed.doc.entities.filter { $0.props["code"] != nil }.map(\.id) : Array(ed.selection)
            let pts = ed.doc.entities.filter { sel.contains($0.id) && $0.props["code"] != nil }
            guard !pts.isEmpty else { throw CommandError.invalid("No survey points with codes (import a point file with a code column).") }
            let r = process(pts, keys: keys(ed.doc.variable("SURVEYCODES")))
            var d = ed.doc
            for (id, l) in r.moved { if let i = d.entityIndex(id) { d.ensureLayer(l); d.entities[i].layer = l } }
            var ids: [EntityID] = []
            for e in r.lines { d.ensureLayer(e.layer); ids.append(d.add(e)) }
            ed.doc = d
            ed.selection = Set(ids)
            ed.print("\(r.lines.count) line(s) from \(pts.count) coded point(s); points moved to \(Set(r.moved.map(\.1)).count) feature layer(s).")
        }
    }
}
