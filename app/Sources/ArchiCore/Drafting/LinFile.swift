// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// AutoCAD-compatible .lin linetype definitions (LAY-021) including complex linetypes with text and shape elements
/// (LAY-022). A definition is a header "*NAME,description" and a pattern line "A,dash,-gap,0(dot),…" where complex
/// elements ["TEXT",STYLE,S=…,R=…,X=…,Y=…] or [SHAPE,file.shx,S=…] follow the pattern value they are placed after.
public enum LinFile {
    public struct Element: Equatable {
        public enum Kind: Equatable { case text(String, style: String), shape(String, file: String) }
        public var kind: Kind
        /// Index in `pattern` of the value the element follows.
        public var after: Int
        public var scale: Double = 1
        /// Rotation in degrees; `absolute` (A=) or relative to the line (R=, default); upright (U=) keeps text readable.
        public var rotation: Double = 0
        public var absolute = false
        public var upright = false
        public var x: Double = 0, y: Double = 0
    }
    public struct Definition: Equatable {
        public var name: String
        public var description: String
        public var pattern: [Double]
        public var elements: [Element]
        public var isComplex: Bool { !elements.isEmpty }
        public var linetype: Linetype { Linetype(name: name, description: description, pattern: pattern) }
    }

    /// Splits at top-level commas (not inside brackets or quotes).
    static func fields(_ s: String) -> [String] {
        var out: [String] = [], cur = "", depth = 0, quoted = false
        for ch in s {
            if ch == "\"" { quoted.toggle() }
            if !quoted { if ch == "[" { depth += 1 } else if ch == "]" { depth -= 1 } }
            if ch == ",", depth == 0, !quoted { out.append(cur); cur = "" } else { cur.append(ch) }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func element(_ body: String, after: Int) -> Element? {
        let f = fields(body)
        guard f.count >= 2 else { return nil }
        var e: Element
        if f[0].hasPrefix("\"") {
            e = Element(kind: .text(f[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"")), style: f[1]), after: after)
        } else {
            e = Element(kind: .shape(f[0].uppercased(), file: f[1]), after: after)
        }
        for kv in f.dropFirst(2) {
            let p = kv.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count == 2, let key = p[0].first.map({ Character($0.uppercased()) }) else { continue }
            let v = Double(p[1].trimmingCharacters(in: CharacterSet(charactersIn: "dD"))) ?? 0
            switch key {
            case "S": e.scale = v
            case "R": e.rotation = v; e.absolute = false
            case "A": e.rotation = v; e.absolute = true
            case "U": e.rotation = v; e.upright = true
            case "X": e.x = v
            case "Y": e.y = v
            default: break
            }
        }
        return e
    }

    /// Parses .lin text. Invalid definitions are skipped.
    public static func parse(_ text: String) -> [Definition] {
        var out: [Definition] = []
        var pending: (String, String)?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("*") {
                let body = String(line.dropFirst())
                let comma = body.firstIndex(of: ",")
                let name = String(body[..<(comma ?? body.endIndex)]).trimmingCharacters(in: .whitespaces)
                let desc = comma.map { String(body[body.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                pending = name.isEmpty ? nil : (name, desc)
                continue
            }
            guard let (name, desc) = pending else { continue }
            pending = nil
            var f = fields(line)
            guard let first = f.first, first.uppercased() == "A" else { continue }
            f.removeFirst()
            var pattern: [Double] = [], elements: [Element] = [], ok = true
            for item in f where !item.isEmpty {
                if item.hasPrefix("[") && item.hasSuffix("]") {
                    guard !pattern.isEmpty, let el = element(String(item.dropFirst().dropLast()), after: pattern.count - 1) else { ok = false; break }
                    elements.append(el)
                } else if let v = Double(item) { pattern.append(v) } else { ok = false; break }
            }
            if ok && !pattern.isEmpty { out.append(Definition(name: name, description: desc, pattern: pattern, elements: elements)) }
        }
        return out
    }

    static func num(_ d: Double) -> String { fmt(d, 6) }

    /// .lin text for definitions.
    public static func write(_ defs: [Definition]) -> String {
        var out = ";; Oanarina Archi Tool linetypes (units: drawing units)\n"
        for d in defs {
            out += "*\(d.name),\(d.description)\n"
            var items: [String] = ["A"]
            for (i, v) in d.pattern.enumerated() {
                items.append(num(v))
                for e in d.elements where e.after == i {
                    var parts: [String]
                    switch e.kind {
                    case .text(let t, let st): parts = ["\"\(t)\"", st]
                    case .shape(let s, let file): parts = [s, file]
                    }
                    parts.append("S=\(num(e.scale))")
                    parts.append((e.upright ? "U=" : (e.absolute ? "A=" : "R=")) + num(e.rotation))
                    parts.append("X=\(num(e.x))"); parts.append("Y=\(num(e.y))")
                    items.append("[" + parts.joined(separator: ",") + "]")
                }
            }
            out += items.joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: Library and document storage

    /// Bundled ISO linetypes (millimetre patterns, as acadiso.lin) and complex utility linetypes.
    public static let standardText = """
    *BORDER,Border __ __ . __ __ . __ __ . __ __ . __ __ .
    A,12.7,-6.35,12.7,-6.35,0,-6.35
    *BORDER2,Border (.5x) __.__.__.__.__.__.__.__.__.__.__.
    A,6.35,-3.175,6.35,-3.175,0,-3.175
    *BORDERX2,Border (2x) ____  ____  .  ____  ____  .  ___
    A,25.4,-12.7,25.4,-12.7,0,-12.7
    *CENTER,Center ____ _ ____ _ ____ _ ____ _ ____ _ ____
    A,31.75,-6.35,6.35,-6.35
    *CENTER2,Center (.5x) ___ _ ___ _ ___ _ ___ _ ___ _ ___
    A,19.05,-3.175,3.175,-3.175
    *CENTERX2,Center (2x) ________  __  ________  __  _____
    A,63.5,-12.7,12.7,-12.7
    *DASHDOT,Dash dot __ . __ . __ . __ . __ . __ . __ . __
    A,12.7,-6.35,0,-6.35
    *DASHDOT2,Dash dot (.5x) _._._._._._._._._._._._._._._.
    A,6.35,-3.175,0,-3.175
    *DASHDOTX2,Dash dot (2x) ____  .  ____  .  ____  .  ___
    A,25.4,-12.7,0,-12.7
    *DASHED,Dashed __ __ __ __ __ __ __ __ __ __ __ __ __ _
    A,12.7,-6.35
    *DASHED2,Dashed (.5x) _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    A,6.35,-3.175
    *DASHEDX2,Dashed (2x) ____  ____  ____  ____  ____  ___
    A,25.4,-12.7
    *DIVIDE,Divide ____ . . ____ . . ____ . . ____ . . ____
    A,12.7,-6.35,0,-6.35,0,-6.35
    *DIVIDE2,Divide (.5x) __..__..__..__..__..__..__..__.._
    A,6.35,-3.175,0,-3.175,0,-3.175
    *DIVIDEX2,Divide (2x) ________  .  .  ________  .  .  _
    A,25.4,-12.7,0,-12.7,0,-12.7
    *DOT,Dot . . . . . . . . . . . . . . . . . . . . . . . .
    A,0,-6.35
    *DOT2,Dot (.5x) ........................................
    A,0,-3.175
    *DOTX2,Dot (2x) .  .  .  .  .  .  .  .  .  .  .  .  .  .
    A,0,-12.7
    *HIDDEN,Hidden __ __ __ __ __ __ __ __ __ __ __ __ __ __
    A,6.35,-3.175
    *HIDDEN2,Hidden (.5x) _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    A,3.175,-1.5875
    *HIDDENX2,Hidden (2x) ____ ____ ____ ____ ____ ____ ____
    A,12.7,-6.35
    *PHANTOM,Phantom ______  __  __  ______  __  __  ______
    A,31.75,-6.35,6.35,-6.35,6.35,-6.35
    *PHANTOM2,Phantom (.5x) ___ _ _ ___ _ _ ___ _ _ ___ _ _
    A,15.875,-3.175,3.175,-3.175,3.175,-3.175
    *PHANTOMX2,Phantom (2x) ____________    ____    ____    _
    A,63.5,-12.7,12.7,-12.7,12.7,-12.7
    *ACAD_ISO02W100,ISO dash __ __ __ __ __ __ __ __ __ __ __ __ __
    A,12,-3
    *ACAD_ISO03W100,ISO dash space __    __    __    __    __    __
    A,12,-18
    *ACAD_ISO04W100,ISO long-dash dot ____ . ____ . ____ . ____ . _
    A,24,-3,0.5,-3
    *ACAD_ISO05W100,ISO long-dash double-dot ____ .. ____ .. ____ .
    A,24,-3,0.5,-3,0.5,-3
    *ACAD_ISO06W100,ISO long-dash triple-dot ____ ... ____ ... ____
    A,24,-3,0.5,-3,0.5,-3,0.5,-3
    *ACAD_ISO07W100,ISO dot . . . . . . . . . . . . . . . . . . . .
    A,0.5,-3
    *ACAD_ISO08W100,ISO long-dash short-dash ____ __ ____ __ ____ _
    A,24,-3,6,-3
    *ACAD_ISO09W100,ISO long-dash double-short-dash ____ __ __ ____
    A,24,-3,6,-3,6,-3
    *ACAD_ISO10W100,ISO dash dot __ . __ . __ . __ . __ . __ . __ .
    A,12,-3,0.5,-3
    *ACAD_ISO11W100,ISO double-dash dot __ __ . __ __ . __ __ . __ _
    A,12,-3,12,-3,0.5,-3
    *ACAD_ISO12W100,ISO dash double-dot __ . . __ . . __ . . __ . .
    A,12,-3,0.5,-3,0.5,-3
    *ACAD_ISO13W100,ISO double-dash double-dot __ __ . . __ __ . . _
    A,12,-3,12,-3,0.5,-3,0.5,-3
    *ACAD_ISO14W100,ISO dash triple-dot __ . . . __ . . . __ . . . _
    A,12,-3,0.5,-3,0.5,-3,0.5,-3
    *ACAD_ISO15W100,ISO double-dash triple-dot __ __ . . . __ __ . .
    A,12,-3,12,-3,0.5,-3,0.5,-3,0.5,-3
    *FENCELINE1,Fenceline circle ----0-----0----0-----0----0-----0--
    A,6.35,-2.54,[CIRC1,ltypeshp.shx,X=-2.54,S=2.54],-2.54,25.4
    *FENCELINE2,Fenceline square ----[]-----[]----[]-----[]----[]---
    A,6.35,-2.54,[BOX,ltypeshp.shx,X=-2.54,S=2.54],-2.54,25.4
    *TRACKS,Tracks -|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-
    A,3.81,[TRACK1,ltypeshp.shx,S=6.35],3.81
    *ZIGZAG,Zig zag /\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\
    A,0.0001,-5.08,[ZIG,ltypeshp.shx,X=-5.08,S=5.08],-10.16,[ZIG,ltypeshp.shx,R=180,X=5.08,S=5.08],-5.08
    *GAS_LINE,Gas line ----GAS----GAS----GAS----GAS----GAS----GAS--
    A,12.7,-5.08,["GAS",STANDARD,S=2.54,R=0.0,X=-2.54,Y=-1.27],-6.35
    *HOT_WATER_SUPPLY,Hot water supply ---- HW ---- HW ---- HW ----
    A,12.7,-5.08,["HW",STANDARD,S=2.54,R=0.0,X=-2.54,Y=-1.27],-5.08
    """
    public static let standard: [Definition] = parse(standardText)

    /// Document variable holding a complex linetype's definition line.
    public static func complexVariable(_ name: String) -> String { "LTCOMPLEX:" + name.uppercased() }

    /// Adds definitions to the document (existing names are skipped unless `replace`). Returns the names added.
    @discardableResult
    public static func load(_ defs: [Definition], into doc: inout ArchiDocument, replace: Bool = false) -> [String] {
        var added: [String] = []
        for d in defs {
            if let i = doc.linetypes.firstIndex(where: { $0.name.caseInsensitiveCompare(d.name) == .orderedSame }) {
                guard replace else { continue }
                doc.linetypes[i] = d.linetype
            } else { doc.linetypes.append(d.linetype) }
            doc.variables[complexVariable(d.name)] = d.isComplex ? write([d]) : nil
            added.append(d.name)
        }
        return added
    }

    /// Full definition of a loaded linetype (complex elements included).
    public static func definition(_ name: String, doc: ArchiDocument) -> Definition? {
        if let v = doc.variable(complexVariable(name)), let d = parse(v).first { return d }
        guard let lt = doc.linetype(name) else { return nil }
        return Definition(name: lt.name, description: lt.description, pattern: lt.pattern, elements: [])
    }
}
