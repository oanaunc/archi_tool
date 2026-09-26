// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

extension Editor {
    /// Layer for new annotation: DIMLAYER / TEXTLAYER variables when set, otherwise the current layer.
    /// Text typed with field codes (%<Area(12):m2:2>%) becomes a field text that updates automatically.
    func markFieldIfNeeded(_ i: Int) {
        let content: String
        switch doc.entities[i].geometry { case .text(let t): content = t.content; case .leader(let l): content = l.text; default: return }
        guard content.contains("%<"), content.contains(">%") else { return }
        doc.entities[i].props["field"] = content
        Fields.updateAll(&doc, ids: [doc.entities[i].id], volatile: true)
    }
    func annotationLayer(_ variable: String) -> String {
        if let l = doc.variable(variable), !l.isEmpty, l != "." { doc.ensureLayer(l); return l }
        return doc.currentLayer
    }
    @discardableResult
    func addDimension(_ d: DimensionGeom) -> EntityID {
        let id = addEntity(.dimension(d), layer: annotationLayer("DIMLAYER"))
        print("Dimension text = \(d.textOverride ?? fmt(CommandHelpers.dimMeasurement(d), doc.dimStyle(d.style).decimals))")
        return id
    }
}

enum AnnotateCommands {
    static var all: [CommandDef] { text + dims + styles }

    static func justification(_ k: String) -> (HAlign, VAlign) {
        switch k {
        case "Center": return (.center, .baseline)
        case "Right": return (.right, .baseline)
        case "Middle", "MC": return (.center, .middle)
        case "TL": return (.left, .top)
        case "TC": return (.center, .top)
        case "TR": return (.right, .top)
        case "ML": return (.left, .middle)
        case "MR": return (.right, .middle)
        case "BL": return (.left, .bottom)
        case "BC": return (.center, .bottom)
        case "BR": return (.right, .bottom)
        default: return (.left, .baseline)
        }
    }
    static let justifyKeywords = ["Left", "Center", "Right", "Middle", "TL", "TC", "TR", "ML", "MC", "MR", "BL", "BC", "BR"]

    /// Converts MTEXT paragraph codes and AutoCAD special symbols (%%d °, %%c ⌀, %%p ±, %%% %).
    static func unescape(_ s: String) -> String {
        specialSymbols(s.replacingOccurrences(of: "\\P", with: "\n").replacingOccurrences(of: "\\n", with: "\n"))
    }
    static func specialSymbols(_ s: String) -> String {
        guard s.contains("%%") else { return s }
        var out = "", i = s.startIndex
        while i < s.endIndex {
            if s[i...].hasPrefix("%%"), let n = s.index(i, offsetBy: 2, limitedBy: s.endIndex), n < s.endIndex {
                switch s[n].lowercased() {
                case "d": out += "°"; i = s.index(after: n); continue
                case "c": out += "⌀"; i = s.index(after: n); continue
                case "p": out += "±"; i = s.index(after: n); continue
                case "%": out += "%"; i = s.index(after: n); continue
                default: break
                }
                // %%nnn: character code
                var j = n, code = ""
                while j < s.endIndex, s[j].isNumber, code.count < 3 { code.append(s[j]); j = s.index(after: j) }
                if code.count == 3, let v = Int(code), let u = UnicodeScalar(v) { out.unicodeScalars.append(u); i = j; continue }
            }
            out.append(s[i]); i = s.index(after: i)
        }
        return out
    }

    // MARK: - Text
    static var text: [CommandDef] { [
        CommandDef("TEXT", aliases: ["DT", "DTEXT"], category: "Annotate", summary: "Creates single-line text objects.") { ed in
            var style = ed.doc.variable("TEXTSTYLE") ?? "Standard"
            var ha = HAlign.left, va = VAlign.baseline
            var start: Vec2
            while true {
                let a = try await ed.getPoint("Specify start point of text", keywords: ["Justify", "Style"])
                switch a {
                case .point(let p): start = p
                case .keyword("Justify"):
                    let k = try await ed.getKeyword("Enter an option", justifyKeywords, defaultValue: "Left") ?? "Left"
                    (ha, va) = justification(k); continue
                case .keyword("Style"):
                    let s = try await ed.getWord("Enter style name or [?]", defaultValue: style) ?? style
                    if s == "?" { ed.print("Text styles: " + ed.doc.textStyles.map(\.name).joined(separator: ", ")); continue }
                    guard let ts = ed.doc.textStyles.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) else { ed.print("Text style \(s) not found."); continue }
                    style = ts.name; continue
                default: return
                }
                break
            }
            let fixed = ed.doc.textStyles.first { $0.name == style }?.height ?? 0
            var h = fixed
            if fixed <= 0 { h = try await ed.getPositive("Specify height", base: start, defaultValue: ed.settings.textHeight) }
            ed.settings.textHeight = h; ed.doc.setVariable("TEXTSIZE", fmt(h))
            let rot = try await ed.getAngle("Specify rotation angle of text", base: start, defaultValue: 0).value ?? 0
            var line = 0
            while let s = try await ed.getString("Enter text"), !s.isEmpty {
                let pos = start + Vec2.polar(1, rot).perp * (-1.5 * h * Double(line))
                let tid = ed.addEntity(.text(TextGeom(position: pos, height: h, content: unescape(s), rotation: rot, style: style, halign: ha, valign: va)), layer: ed.annotationLayer("TEXTLAYER"))
                if let i = ed.doc.entityIndex(tid) { ed.markFieldIfNeeded(i) }
                line += 1
            }
        },
        CommandDef("MTEXT", aliases: ["MT", "T"], category: "Annotate", summary: "Creates paragraph (multiline) text inside a width.") { ed in
            var h = ed.settings.textHeight
            var rot = 0.0
            var style = ed.doc.variable("TEXTSTYLE") ?? "Standard"
            var ha = HAlign.left, va = VAlign.top
            let c1 = try await ed.requirePoint("Specify first corner")
            var c2: Vec2 = c1
            var width: Double? = nil
            while true {
                let a = try await ed.getPoint("Specify opposite corner", base: c1, keywords: ["Height", "Justify", "Rotation", "Style", "Width"]) { c in
                    [.polyline(PolylineGeom(points: BBox2(points: [c1, c]).corners, closed: true))] }
                switch a {
                case .point(let p): c2 = p
                case .keyword("Height"): h = try await ed.getPositive("Specify height", base: c1, defaultValue: h); continue
                case .keyword("Justify"):
                    let k = try await ed.getKeyword("Enter justification", ["TL", "TC", "TR", "ML", "MC", "MR", "BL", "BC", "BR"], defaultValue: "TL") ?? "TL"
                    (ha, va) = justification(k); continue
                case .keyword("Rotation"): rot = try await ed.getAngle("Specify rotation angle", base: c1, defaultValue: rot).value ?? rot; continue
                case .keyword("Style"): style = try await ed.getWord("Enter style name", defaultValue: style) ?? style; continue
                case .keyword("Width"): width = try await ed.getPositive("Specify width", base: c1, defaultValue: 5000, allowZero: true); c2 = c1 + Vec2(width!, -h)
                default: width = 0
                }
                break
            }
            let box = BBox2(points: [c1, c2])
            let w = width ?? box.width
            var pos = Vec2(box.min.x, box.max.y)
            if width == nil {
                switch ha { case .left: pos.x = box.min.x; case .center: pos.x = box.center.x; case .right: pos.x = box.max.x }
                switch va { case .top: pos.y = box.max.y; case .middle: pos.y = box.center.y; default: pos.y = box.min.y }
                pos = pos.rotated(by: rot, around: c1)
            } else { pos = c1 }
            guard let s = try await ed.getString("Enter text (\\P = new paragraph)"), !s.isEmpty else { return }
            ed.settings.textHeight = h
            let tid = ed.addEntity(.text(TextGeom(position: pos, height: h, content: unescape(s), rotation: rot, style: style, halign: ha, valign: va, width: w)), layer: ed.annotationLayer("TEXTLAYER"))
            if let i = ed.doc.entityIndex(tid) { ed.markFieldIfNeeded(i) }
        },
        CommandDef("TEXTEDIT", aliases: ["ED", "DDEDIT"], category: "Annotate", summary: "Edits text, leader, dimension text, table cells or attribute values.") { ed in
            while case .pick(let pk) = try await ed.pickObject("Select an annotation object", filter: { ed.doc.entity($0) != nil }) {
                guard let i = ed.doc.entityIndex(pk.id) else { continue }
                switch ed.doc.entities[i].geometry {
                case .text(var t):
                    guard let s = try await ed.getString("Enter new text", defaultValue: t.content) else { continue }
                    t.content = unescape(s); ed.doc.entities[i].geometry = .text(t)
                    ed.doc.entities[i].props["field"] = nil; ed.markFieldIfNeeded(i)
                case .leader(var l):
                    guard let s = try await ed.getString("Enter new text", defaultValue: l.text) else { continue }
                    l.text = unescape(s); ed.doc.entities[i].geometry = .leader(l)
                case .dimension(var d):
                    guard let s = try await ed.getString("Enter new dimension text (<> = measured value, empty = reset)", defaultValue: d.textOverride ?? "<>") else { continue }
                    d.textOverride = (s.isEmpty || s == "<>") ? nil : s; ed.doc.entities[i].geometry = .dimension(d)
                case .table(var tb):
                    guard let r = try await ed.getInteger("Enter row number (1 = top)", defaultValue: 1), let c = try await ed.getInteger("Enter column number", defaultValue: 1),
                          r >= 1, r <= tb.cells.count, c >= 1, c <= tb.columnWidths.count else { ed.print("Invalid cell."); continue }
                    while tb.cells[r - 1].count < tb.columnWidths.count { tb.cells[r - 1].append("") }
                    guard let s = try await ed.getString("Enter cell text", defaultValue: tb.cells[r - 1][c - 1]) else { continue }
                    tb.cells[r - 1][c - 1] = s; ed.doc.entities[i].geometry = .table(tb)
                case .insert(var ins):
                    guard let b = ed.doc.blocks[ins.block] else { continue }
                    for tag in b.entities.filter({ !AttributeModes.has($0, "C") }).compactMap({ $0.props["attdef"] }) {
                        if let v = try await ed.getString("Enter value for \(tag)", defaultValue: ins.attributes[tag] ?? "") { ins.attributes[tag] = v }
                    }
                    ed.doc.entities[i].geometry = .insert(ins)
                default: ed.print("That object has no editable text.")
                }
            }
        },
        CommandDef("FIND", category: "Annotate", summary: "Finds (and optionally replaces) text in texts, leaders, dimensions, tables and attributes.") { ed in
            guard let find = try await ed.getWord("Enter text to find"), !find.isEmpty else { return }
            let rep = try await ed.getWord("Enter replacement text (Enter = list only)")
            var found: [EntityID] = []
            func r(_ s: String) -> String { rep.map { s.replacingOccurrences(of: find, with: $0) } ?? s }
            for i in ed.doc.entities.indices {
                let e = ed.doc.entities[i]
                guard ed.doc.isEditable(layer: e.layer) || rep == nil else { continue }
                var g = e.geometry
                var hit = false
                switch g {
                case .text(var t): if t.content.contains(find) { hit = true; t.content = r(t.content); g = .text(t) }
                case .leader(var l): if l.text.contains(find) { hit = true; l.text = r(l.text); g = .leader(l) }
                case .dimension(var d): if let o = d.textOverride, o.contains(find) { hit = true; d.textOverride = r(o); g = .dimension(d) }
                case .table(var tb):
                    if tb.cells.contains(where: { $0.contains { $0.contains(find) } }) { hit = true; tb.cells = tb.cells.map { $0.map(r) }; g = .table(tb) }
                case .insert(var ins):
                    if ins.attributes.values.contains(where: { $0.contains(find) }) { hit = true; ins.attributes = ins.attributes.mapValues(r); g = .insert(ins) }
                default: break
                }
                if hit { found.append(e.id); if rep != nil { ed.doc.entities[i].geometry = g } }
            }
            for i in ed.doc.elements.indices {
                if case .space(var s) = ed.doc.elements[i].geometry, s.name.contains(find) || s.number.contains(find) {
                    found.append(ed.doc.elements[i].id)
                    if rep != nil { s.name = r(s.name); s.number = r(s.number); ed.doc.elements[i].geometry = .space(s) }
                }
            }
            ed.selection = Set(found)
            ed.print(rep == nil ? "\(found.count) object(s) contain \"\(find)\": " + found.map { "#\($0)" }.joined(separator: " ")
                                : "\(found.count) object(s) changed.")
        },
    ] }

    // MARK: - Dimensions
    @MainActor static func objectExtensionPoints(_ ed: Editor) async throws -> (Vec2, Vec2)? {
        guard case .pick(let pk) = try await ed.pickObject("Select object to dimension", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return nil }
        switch e.geometry {
        case .line(let l): return (l.a, l.b)
        case .arc(let a): return (a.startPoint, a.endPoint)
        case .circle(let c): return (c.center - Vec2(c.radius, 0), c.center + Vec2(c.radius, 0))
        case .polyline(let p):
            let v = p.vertices, n = p.closed ? v.count : v.count - 1
            var best: (Vec2, Vec2, Double)?
            for i in 0..<max(n, 0) {
                let a = v[i].p, b = v[(i + 1) % v.count].p
                let d = GeometryOps.distance(point: pk.point, segA: a, segB: b)
                if d < (best?.2 ?? .infinity) { best = (a, b, d) }
            }
            return best.map { ($0.0, $0.1) }
        default: ed.print("Select a line, arc, circle or polyline segment."); return nil
        }
    }

    static func autoRotation(_ p1: Vec2, _ p2: Vec2, _ loc: Vec2) -> Double {
        let minX = min(p1.x, p2.x), maxX = max(p1.x, p2.x), minY = min(p1.y, p2.y), maxY = max(p1.y, p2.y)
        let inX = loc.x > minX && loc.x < maxX, inY = loc.y > minY && loc.y < maxY
        if inY && !inX { return .pi / 2 }
        if inX && !inY { return 0 }
        return abs(p2.x - p1.x) >= abs(p2.y - p1.y) ? 0 : .pi / 2
    }

    @MainActor static func linearDim(_ ed: Editor, aligned: Bool) async throws {
        let style = ed.doc.currentDimStyle
        var p1: Vec2, p2: Vec2
        let a = try await ed.getPoint("Specify first extension line origin or <select object>")
        if let p = a.point {
            p1 = p
            p2 = try await ed.requirePoint("Specify second extension line origin", base: p1) { c in [.line(LineGeom(p1, c))] }
        } else {
            guard let pts = try await objectExtensionPoints(ed) else { return }
            (p1, p2) = pts
        }
        guard p1.distance(to: p2) > 1e-9 else { throw CommandError.invalid("Extension line origins coincide.") }
        var fixedRot: Double? = nil
        var textOverride: String? = nil
        while true {
            let kws = aligned ? ["Text"] : ["Text", "Horizontal", "Vertical", "Rotated"]
            let fr = fixedRot, to = textOverride
            let r = try await ed.getPoint("Specify dimension line location", base: (p1 + p2) / 2, keywords: kws) { c in
                aligned ? [.dimension(DimensionGeom(kind: .aligned, points: [p1, p2, c], textOverride: to, style: style))]
                        : [.dimension(DimensionGeom(kind: .linear, points: [p1, p2, c], rotation: fr ?? autoRotation(p1, p2, c), textOverride: to, style: style))] }
            switch r {
            case .point(let loc):
                if aligned { ed.addDimension(DimensionGeom(kind: .aligned, points: [p1, p2, loc], textOverride: textOverride, style: style)) }
                else { ed.addDimension(DimensionGeom(kind: .linear, points: [p1, p2, loc], rotation: fixedRot ?? autoRotation(p1, p2, loc), textOverride: textOverride, style: style)) }
                return
            case .keyword("Text"): textOverride = try await ed.getString("Enter dimension text", defaultValue: "<>").flatMap { $0 == "<>" || $0.isEmpty ? nil : $0 }
            case .keyword("Horizontal"): fixedRot = 0
            case .keyword("Vertical"): fixedRot = .pi / 2
            case .keyword("Rotated"): fixedRot = try await ed.getAngle("Specify angle of dimension line", defaultValue: 0).value ?? 0
            default: return
            }
        }
    }

    @MainActor static func radialDim(_ ed: Editor, diameter: Bool) async throws {
        guard case .pick(let pk) = try await ed.pickObject("Select arc or circle", filter: { id in
            switch ed.doc.entity(id)?.geometry { case .arc?, .circle?: return true; default: return false } }), let e = ed.doc.entity(pk.id) else { return }
        let c: Vec2, r: Double
        switch e.geometry { case .arc(let a): c = a.center; r = a.radius; case .circle(let ci): c = ci.center; r = ci.radius; default: return }
        let style = ed.doc.currentDimStyle
        func dim(_ loc: Vec2) -> DimensionGeom {
            var d = (loc - c).normalized; if d == .zero { d = Vec2(1, 0) }
            return DimensionGeom(kind: diameter ? .diameter : .radius, points: [c, c + d * r, loc], style: style)
        }
        let loc = try await ed.requirePoint("Specify dimension line location", base: c) { [.dimension(dim($0))] }
        ed.addDimension(dim(loc))
    }

    /// Last linear/aligned dimension (for DIMCONTINUE / DIMBASELINE).
    @MainActor static func lastDimension(_ ed: Editor) -> (EntityID, DimensionGeom)? {
        for e in ed.doc.entities.reversed() { if case .dimension(let d) = e.geometry, [.linear, .aligned, .ordinate].contains(d.kind), d.points.count >= (d.kind == .ordinate ? 2 : 3) { return (e.id, d) } }
        return nil
    }

    @MainActor static func chainDims(_ ed: Editor, baseline: Bool) async throws {
        var base: DimensionGeom
        if let (_, d) = lastDimension(ed) { base = d } else {
            guard case .pick(let pk) = try await ed.pickObject("Select base dimension"), case .dimension(let d)? = ed.doc.entity(pk.id)?.geometry, d.points.count >= 3 else { return }
            base = d
        }
        var created: [EntityID] = []
        let style = ed.doc.dimStyle(base.style)
        let spacing = ed.variableDouble("DIMDLI", max(style.textHeight * style.scale * 3.75, 1))
        var prev = base
        let first = base.points[0]
        while true {
            let a = try await ed.getPoint("Specify a second extension line origin", keywords: ["Select", "Undo"])
            switch a {
            case .point(let p):
                let dir: Vec2 = prev.kind == .linear || prev.kind == .ordinate ? Vec2.polar(1, prev.rotation ?? 0) : (prev.points[1] - prev.points[0]).normalized
                if prev.kind == .ordinate {
                    let lead = prev.points[1] - prev.points[0]
                    let end = abs(lead.x) > abs(lead.y) ? Vec2(prev.points[1].x, p.y) : Vec2(p.x, prev.points[1].y)
                    let d = DimensionGeom(kind: .ordinate, points: [p, end, prev.points.count > 2 ? prev.points[2] : .zero], style: prev.style)
                    created.append(ed.addDimension(d)); prev = d; continue
                }
                let rot = dir.angle
                var d: DimensionGeom
                if baseline {
                    var n = dir.perp
                    if (prev.points[2] - first).dot(n) < 0 { n = -n }
                    let loc = prev.points[2] + n * spacing
                    d = DimensionGeom(kind: .linear, points: [first, p, loc], rotation: rot, style: prev.style)
                } else {
                    let loc = prev.points[2] + dir * ((p - prev.points[2]).dot(dir))
                    d = DimensionGeom(kind: .linear, points: [prev.points[1], p, loc], rotation: rot, style: prev.style)
                }
                created.append(ed.addDimension(d)); prev = d
            case .keyword("Select"):
                guard case .pick(let pk) = try await ed.pickObject("Select base dimension"), case .dimension(let d)? = ed.doc.entity(pk.id)?.geometry, d.points.count >= 3 else { continue }
                prev = d
            case .keyword("Undo"):
                if let l = created.popLast() { ed.doc.remove(ids: [l]) }
                if let (_, d) = lastDimension(ed) { prev = d }
            default: return
            }
        }
    }

    static var dims: [CommandDef] { [
        CommandDef("DIMLINEAR", aliases: ["DLI", "DIMLIN"], category: "Annotate", summary: "Creates a horizontal, vertical or rotated linear dimension.") { ed in try await linearDim(ed, aligned: false) },
        CommandDef("DIMALIGNED", aliases: ["DAL", "DIMALI"], category: "Annotate", summary: "Creates a dimension aligned with its extension line origins.") { ed in try await linearDim(ed, aligned: true) },
        CommandDef("DIMRADIUS", aliases: ["DRA", "DIMRAD"], category: "Annotate", summary: "Dimensions the radius of an arc or circle.") { ed in try await radialDim(ed, diameter: false) },
        CommandDef("DIMDIAMETER", aliases: ["DDI", "DIMDIA"], category: "Annotate", summary: "Dimensions the diameter of a circle or arc.") { ed in try await radialDim(ed, diameter: true) },
        CommandDef("DIMANGULAR", aliases: ["DAN", "DIMANG"], category: "Annotate", summary: "Dimensions the angle between lines, of an arc, or of three points.") { ed in
            let style = ed.doc.currentDimStyle
            var v: Vec2, a: Vec2, b: Vec2
            var lastLinePick: EntityID?
            let pick = try await ed.pickObject("Select arc, circle, line, or <specify vertex>", filter: { ed.doc.entity($0) != nil })
            switch pick {
            case .pick(let pk):
                guard let e = ed.doc.entity(pk.id) else { return }
                switch e.geometry {
                case .arc(let arc): v = arc.center; a = arc.startPoint; b = arc.endPoint
                case .circle(let c): v = c.center; a = c.center + (pk.point - c.center).normalized * c.radius
                    b = try await ed.requirePoint("Specify second angle endpoint", base: v)
                case .line(let l1):
                    guard case .pick(let pk2) = try await ed.pickObject("Select second line", filter: { if case .line? = ed.doc.entity($0)?.geometry { return true }; return false }),
                          case .line(let l2)? = ed.doc.entity(pk2.id)?.geometry else { return }
                    lastLinePick = pk2.id
                    guard let x = GeometryOps.lineIntersection(l1.a, l1.b, l2.a, l2.b) else { throw CommandError.invalid("Lines are parallel.") }
                    v = x
                    func leg(_ l: LineGeom, _ p: Vec2) -> Vec2 { p.distance(to: x) > 1e-6 ? p : (l.a.distance(to: x) > l.b.distance(to: x) ? l.a : l.b) }
                    a = leg(l1, GeometryOps.closestOnSegment(pk.point, l1.a, l1.b)); b = leg(l2, GeometryOps.closestOnSegment(pk2.point, l2.a, l2.b))
                default: throw CommandError.invalid("Select an arc, circle or line.")
                }
            case .none:
                v = try await ed.requirePoint("Specify angle vertex")
                a = try await ed.requirePoint("Specify first angle endpoint", base: v)
                b = try await ed.requirePoint("Specify second angle endpoint", base: v)
            default: return
            }
            let (va, vb, vv) = (a, b, v)
            let loc = try await ed.requirePoint("Specify dimension arc line location", base: v) { c in [.dimension(DimensionGeom(kind: .angular, points: [vv, va, vb, c], style: style))] }
            let did = ed.addDimension(DimensionGeom(kind: .angular, points: [v, a, b, loc], style: style))
            // Between two lines: the legs stay on the lines and the vertex at their intersection when they change.
            if case .pick(let pk) = pick, case .line(let l1)? = ed.doc.entity(pk.id)?.geometry, ed.doc.variable("DIMASSOC") != "0",
               let l2id = lastLinePick, case .line(let l2)? = ed.doc.entity(l2id)?.geometry, let i = ed.doc.entityIndex(did),
               let k1 = DimAssociation.fractionKey(.line(l1), near: a), let k2 = DimAssociation.fractionKey(.line(l2), near: b) {
                ed.doc.entities[i].props[DimAssociation.prop] = "0=\(pk.id):i\(l2id);1=\(pk.id):\(k1);2=\(l2id):\(k2)"
            }
        },
        CommandDef("DIMORDINATE", aliases: ["DOR", "DIMORD"], category: "Annotate", summary: "Creates X or Y ordinate dimensions from the origin (0,0).") { ed in
            let style = ed.doc.currentDimStyle
            let origin = Vec2(ed.variableDouble("ORDORIGINX", 0), ed.variableDouble("ORDORIGINY", 0))
            let f = try await ed.requirePoint("Specify feature location")
            var datum: String? = nil
            // Points: feature, leader end, datum origin. A vertical leader measures X, a horizontal one Y.
            func leaderEnd(_ c: Vec2) -> Vec2 {
                switch datum {
                case "Xdatum"?: return Vec2(f.x, c.y)
                case "Ydatum"?: return Vec2(c.x, f.y)
                default: return abs(c.y - f.y) >= abs(c.x - f.x) ? Vec2(f.x, c.y) : Vec2(c.x, f.y)
                }
            }
            while true {
                let r = try await ed.getPoint("Specify leader endpoint location", base: f, keywords: ["Xdatum", "Ydatum"]) { c in
                    [.dimension(DimensionGeom(kind: .ordinate, points: [f, leaderEnd(c), origin], style: style))] }
                switch r {
                case .point(let c):
                    ed.addDimension(DimensionGeom(kind: .ordinate, points: [f, leaderEnd(c), origin], style: style)); return
                case .keyword(let k): datum = k
                default: return
                }
            }
        },
        CommandDef("DIMARC", aliases: ["DAR"], category: "Annotate", summary: "Dimensions the length of an arc.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select arc", filter: { if case .arc? = ed.doc.entity($0)?.geometry { return true }; return false }),
                  case .arc(let a)? = ed.doc.entity(pk.id)?.geometry else { return }
            let style = ed.doc.currentDimStyle
            let loc = try await ed.requirePoint("Specify arc length dimension location", base: a.center) { c in [.dimension(DimensionGeom(kind: .arcLength, points: [a.center, a.startPoint, a.endPoint, c], style: style))] }
            ed.addDimension(DimensionGeom(kind: .arcLength, points: [a.center, a.startPoint, a.endPoint, loc], style: style))
        },
        CommandDef("DIMCONTINUE", aliases: ["DCO", "DIMCONT"], category: "Annotate", summary: "Continues a chain of dimensions from the last one.") { ed in try await chainDims(ed, baseline: false) },
        CommandDef("DIMBASELINE", aliases: ["DBA", "DIMBASE"], category: "Annotate", summary: "Creates dimensions from the baseline of the last dimension.") { ed in try await chainDims(ed, baseline: true) },
        CommandDef("QDIM", category: "Annotate", summary: "Quickly dimensions selected objects: Continuous, Staggered, Baseline, Ordinate, Radius, Diameter, datumPoint.") { ed in
            let ids = try await ed.getEntitySelection("Select geometry to dimension")
            var pts: [Vec2] = []
            var curves: [(center: Vec2, radius: Double, isCircle: Bool)] = []
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                switch e.geometry {
                case .line(let l): pts += [l.a, l.b]
                case .polyline(let p): pts += p.vertices.map(\.p)
                case .arc(let a): pts += [a.startPoint, a.endPoint, a.center]; curves.append((a.center, a.radius, false))
                case .circle(let c): pts.append(c.center); curves.append((c.center, c.radius, true))
                case .point(let p): pts.append(p)
                default: continue
                }
            }
            ed.selection = []
            guard pts.count >= 2 || !curves.isEmpty else { throw CommandError.invalid("Select objects with at least two points.") }
            var mode = ed.doc.variable("QDIMMODE") ?? "Continuous"
            var datum = DraftProps.point(ed.doc.variable("QDIMDATUM")) ?? .zero
            let dims = QuickDim(points: pts, curves: curves, style: ed.doc.currentDimStyle,
                                spacing: ed.variableDouble("DIMDLI", max(ed.doc.dimStyle.textHeight * ed.doc.dimStyle.scale * 3.75, 1)))
            while true {
                let r = try await ed.getPoint("Specify dimension line position", keywords: ["Continuous", "Staggered", "Baseline", "Ordinate", "Radius", "Diameter", "datumPoint"]) { c in
                    dims.build(mode, at: c, datum: datum).map { .dimension($0) } }
                switch r {
                case .point(let loc):
                    let ds = dims.build(mode, at: loc, datum: datum)
                    guard !ds.isEmpty else { throw CommandError.invalid(mode == "Radius" || mode == "Diameter" ? "Select arcs or circles." : "Select objects with at least two points.") }
                    for d in ds { ed.addEntity(.dimension(d), layer: ed.annotationLayer("DIMLAYER")) }
                    ed.print("\(ds.count) dimension(s) created.")
                    return
                case .keyword("datumPoint"):
                    datum = try await ed.requirePoint("Select new datum point"); ed.doc.setVariable("QDIMDATUM", DraftProps.text(datum))
                case .keyword(let k): mode = k; ed.doc.setVariable("QDIMMODE", k)
                default: return
                }
            }
        },
        CommandDef("DIM", category: "Annotate", summary: "Smart dimension: picks an object (line → linear/aligned, arc → radius, circle → diameter) or two points.") { ed in
            let style = ed.doc.currentDimStyle
            let a = try await ed.getPoint("Select objects or specify first extension line origin")
            guard let p = a.point else { return }
            if let id = ed.pickFiltered(at: p, filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(id) {
                switch e.geometry {
                case .line(let l):
                    let axis = abs(l.a.x - l.b.x) < 1e-9 || abs(l.a.y - l.b.y) < 1e-9
                    let loc = try await ed.requirePoint("Specify dimension line location", base: p) { c in
                        [.dimension(axis ? DimensionGeom(kind: .linear, points: [l.a, l.b, c], rotation: autoRotation(l.a, l.b, c), style: style) : DimensionGeom(kind: .aligned, points: [l.a, l.b, c], style: style))] }
                    ed.addDimension(axis ? DimensionGeom(kind: .linear, points: [l.a, l.b, loc], rotation: autoRotation(l.a, l.b, loc), style: style) : DimensionGeom(kind: .aligned, points: [l.a, l.b, loc], style: style))
                case .arc(let arc):
                    let loc = try await ed.requirePoint("Specify radius dimension location", base: arc.center)
                    ed.addDimension(DimensionGeom(kind: .radius, points: [arc.center, arc.center + (loc - arc.center).normalized * arc.radius, loc], style: style))
                case .circle(let c):
                    let loc = try await ed.requirePoint("Specify diameter dimension location", base: c.center)
                    ed.addDimension(DimensionGeom(kind: .diameter, points: [c.center, c.center + (loc - c.center).normalized * c.radius, loc], style: style))
                default:
                    ed.print("Select a line, arc or circle, or specify points.")
                }
                return
            }
            let p2 = try await ed.requirePoint("Specify second extension line origin", base: p)
            let loc = try await ed.requirePoint("Specify dimension line location", base: p2) { c in [.dimension(DimensionGeom(kind: .linear, points: [p, p2, c], rotation: autoRotation(p, p2, c), style: style))] }
            ed.addDimension(DimensionGeom(kind: .linear, points: [p, p2, loc], rotation: autoRotation(p, p2, loc), style: style))
        },
        CommandDef("LEADER", aliases: ["LE", "LEAD", "QLEADER"], category: "Annotate", summary: "Creates a leader line with annotation text.") { ed in
            var pts = [try await ed.requirePoint("Specify leader start point")]
            while true {
                let cur = pts
                guard let p = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.leader(LeaderGeom(points: cur + [c], text: "", textHeight: ed.settings.textHeight))] }).point else { break }
                pts.append(p)
            }
            guard pts.count >= 2 else { throw CommandError.invalid("A leader needs at least two points.") }
            let text = try await ed.getString("Enter annotation text") ?? ""
            ed.addEntity(.leader(LeaderGeom(points: pts, text: unescape(text), textHeight: ed.settings.textHeight)), layer: ed.annotationLayer("TEXTLAYER"))
        },
        CommandDef("MLEADER", aliases: ["MLD"], category: "Annotate", summary: "Creates a multileader (arrowhead, landing, text).") { ed in
            let a = try await ed.requirePoint("Specify leader arrowhead location")
            let b = try await ed.requirePoint("Specify leader landing location", base: a) { c in [.leader(LeaderGeom(points: [a, c], text: "", textHeight: ed.settings.textHeight))] }
            let text = try await ed.getString("Enter text") ?? ""
            let style = AnnotationToolCommands.currentMLeaderStyle(ed)
            let layer = style.flatMap { $0.layer.isEmpty ? nil : $0.layer } ?? ed.annotationLayer("TEXTLAYER")
            ed.doc.ensureLayer(layer)
            var h = style?.textHeight ?? ed.settings.textHeight
            if style?.annotative == true { h = Annotative.modelHeight(paper: h, doc: ed.doc) }
            let id = ed.addEntity(.leader(LeaderGeom(points: [a, b], text: unescape(text), textHeight: h)), layer: layer)
            if let i = ed.doc.entityIndex(id) {
                if let s = style { ed.doc.entities[i].props["mleaderstyle"] = s.name }
                if style?.annotative == true { ed.doc.entities[i].props["annotative"] = "1"; ed.doc.entities[i].props["paperHeight"] = fmt(style!.textHeight, 8) }
                ed.markFieldIfNeeded(i)
            }
        },
    ] }

    // MARK: - Styles
    static var styles: [CommandDef] { [
        CommandDef("DIMSTYLE", aliases: ["D", "DST", "DDIM", "-DIMSTYLE"], category: "Annotate", summary: "Creates, edits, lists and sets dimension styles.") { ed in
            while true {
                let k = try await ed.getKeyword("Enter a dimension style option", ["Set", "New", "Edit", "List", "Apply"], defaultValue: "List") ?? "List"
                switch k {
                case "Set":
                    guard let n = try await ed.getWord("Enter dimension style name", defaultValue: ed.doc.currentDimStyle) else { return }
                    guard let s = ed.doc.dimStyles.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Dimension style \(n) not found.") }
                    ed.doc.currentDimStyle = s.name; ed.print("Current dimension style: \(s.name)"); return
                case "New":
                    guard let n = try await ed.getWord("Enter new dimension style name"), !n.isEmpty else { return }
                    guard !ed.doc.dimStyles.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Dimension style \(n) already exists.") }
                    var s = ed.doc.dimStyle; s.name = n
                    let from = ed.doc.dimStyle.name
                    ed.doc.dimStyles.append(s); ed.doc.currentDimStyle = n
                    DimStyleExtras.copy(from: from, to: n, doc: &ed.doc)
                    ed.print("Dimension style \(n) created (based on the current style) and made current.")
                    try await editDimStyle(ed, n); return
                case "Edit": try await editDimStyle(ed, ed.doc.currentDimStyle); return
                case "Apply":
                    let ids = try await ed.getEntitySelection("Select dimensions to update")
                    for id in ids { if let i = ed.doc.entityIndex(id), case .dimension(var d) = ed.doc.entities[i].geometry { d.style = ed.doc.currentDimStyle; ed.doc.entities[i].geometry = .dimension(d) } }
                    ed.selection = []; return
                default:
                    for s in ed.doc.dimStyles {
                        let x = DimStyleExtras.get(s.name, doc: ed.doc)
                        ed.print("\(s.name == ed.doc.currentDimStyle ? "*" : " ") \(s.name): text \(fmt(s.textHeight)), arrow \(s.arrow.rawValue) \(fmt(s.arrowSize)), scale \(fmt(s.scale)), decimals \(s.decimals)" + (x.isDefault ? "" : ", " + x.encoded.replacingOccurrences(of: ";", with: ", ")))
                    }
                    return
                }
            }
        },
        CommandDef("TEXTSTYLE", aliases: ["STYLE", "ST", "-STYLE"], category: "Annotate", summary: "Creates or modifies a text style and makes it current.") { ed in
            let cur = ed.doc.variable("TEXTSTYLE") ?? "Standard"
            guard let name = try await ed.getWord("Enter name of text style or [?]", defaultValue: cur) else { return }
            if name == "?" { for s in ed.doc.textStyles { ed.print("\(s.name == cur ? "*" : " ") " + TextStyleFonts.describe(s, doc: ed.doc)) }; return }
            var idx = ed.doc.textStyles.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if idx == nil { ed.doc.textStyles.append(TextStyle(name: name)); idx = ed.doc.textStyles.count - 1; ed.print("New style \(name).") }
            var s = ed.doc.textStyles[idx!]
            s.font = try await ed.getWord("Specify font name", defaultValue: s.font) ?? s.font
            if let h = try await ed.getReal("Specify height of text (0 = set when placing)", defaultValue: s.height).value, h >= 0 { s.height = h }
            if let w = try await ed.getReal("Specify width factor", defaultValue: s.widthFactor).value, w > 0 { s.widthFactor = w }
            let oldDeg = TextStyleFonts.obliqueRadians(s) * 180 / .pi
            s.oblique = oldDeg * .pi / 180
            if let o = try await ed.getReal("Specify obliquing angle (degrees)", defaultValue: oldDeg).value {
                guard abs(o) <= 85 else { throw CommandError.invalid("The obliquing angle must be between -85 and 85 degrees.") }
                s.oblique = o * .pi / 180
            }
            ed.doc.textStyles[idx!] = s
            ed.doc.setVariable("TEXTSTYLE", s.name)
            ed.print("\(s.name) is now the current text style.")
        },
    ] }

    @MainActor static func editDimStyle(_ ed: Editor, _ name: String) async throws {
        guard let i = ed.doc.dimStyles.firstIndex(where: { $0.name == name }) else { return }
        while true {
            let s = ed.doc.dimStyles[i]
            let k = try await ed.getKeyword("Edit \(name)", ["TextHeight", "ArrowSize", "ARrow", "Scale", "Decimals", "Prefix", "SUffix", "LinearScale", "EXtension", "Offset", "Gap",
                                                             "Units", "TOlerance", "ALternate", "Fit", "PLacement", "Zeros", "ROund", "STyle", "eXit"], defaultValue: "eXit") ?? "eXit"
            var n = s
            var x = DimStyleExtras.get(name, doc: ed.doc)
            switch k {
            case "Units":
                let opts = DimStyleExtras.UnitFormat.allCases.map { $0.rawValue.capitalized }
                if let u = try await ed.getKeyword("Unit format", ["Decimal", "Architectural", "Engineering", "Fractional", "SCientific"], defaultValue: x.units.rawValue.capitalized) {
                    x.units = DimStyleExtras.UnitFormat(rawValue: u.lowercased()) ?? .decimal
                } else { ed.print("Formats: " + opts.joined(separator: ", ")) }
            case "TOlerance":
                let t = try await ed.getKeyword("Tolerance", ["None", "Symmetrical", "Deviation", "Limits", "Basic"], defaultValue: "None") ?? "None"
                switch t {
                case "Symmetrical":
                    let v = try await ed.getPositive("Tolerance value", defaultValue: 0.1, allowZero: true)
                    x.tolerance = "sym:" + fmt(v, 8)
                case "Deviation", "Limits":
                    let up = try await ed.getPositive("Upper value", defaultValue: 0.1, allowZero: true)
                    let lo = try await ed.getPositive("Lower value", defaultValue: up, allowZero: true)
                    x.tolerance = (t == "Deviation" ? "dev:" : "limits:") + fmt(up, 8) + "," + fmt(lo, 8)
                case "Basic": x.tolerance = "basic"
                default: x.tolerance = nil
                }
            case "ALternate":
                guard try await ed.getYesNo("Display alternate units?", defaultValue: x.alternate != nil) else { x.alternate = nil; break }
                let f = try await ed.getPositive("Multiplier for alternate units", defaultValue: 1 / 25.4)
                let dec = try await ed.getInteger("Alternate decimal places", defaultValue: 2) ?? 2
                let suf = try await ed.getWord("Alternate suffix (. = none)", defaultValue: ".") ?? "."
                x.alternate = fmt(f, 10) + "," + String(max(0, min(8, dec))) + (suf == "." ? "" : "," + suf)
            case "Fit":
                x.fit = (try await ed.getKeyword("When there is not room for text and arrows, move", ["Best", "Arrows", "Text", "BOth"], defaultValue: x.fit.capitalized) ?? "Best").lowercased()
            case "PLacement":
                let p = try await ed.getKeyword("Text placement", ["Above", "Centered"], defaultValue: x.textCentered ? "Centered" : "Above") ?? "Above"
                x.textCentered = p == "Centered"
            case "Zeros":
                x.suppressLeadingZeros = try await ed.getYesNo("Suppress leading zeros?", defaultValue: x.suppressLeadingZeros)
                x.suppressTrailingZeros = try await ed.getYesNo("Suppress trailing zeros?", defaultValue: x.suppressTrailingZeros)
            case "ROund":
                x.roundOff = try await ed.getPositive("Round distances to (0 = off)", defaultValue: x.roundOff, allowZero: true)
            case "STyle":
                let t = try await ed.getWord("Text style (. = default)", defaultValue: x.textStyle ?? ".") ?? "."
                if t == "." { x.textStyle = nil }
                else if let st = ed.doc.textStyles.first(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) { x.textStyle = st.name }
                else { throw CommandError.invalid("Text style \(t) not found.") }
            case "TextHeight": n.textHeight = try await ed.getPositive("Text height", defaultValue: s.textHeight)
            case "ArrowSize": n.arrowSize = try await ed.getPositive("Arrow size", defaultValue: s.arrowSize, allowZero: true)
            case "ARrow":
                let names = ArrowKind.allCases.map(\.rawValue)
                if let a = try await ed.getWord("Arrow kind (\(names.joined(separator: ", ")))", defaultValue: s.arrow.rawValue), let kind = ArrowKind.allCases.first(where: { $0.rawValue.lowercased() == a.lowercased() }) { n.arrow = kind }
                else { ed.print("Unknown arrow kind.") }
            case "Scale": if let v = try await ed.getReal("Overall scale (DIMSCALE)", defaultValue: s.scale).value, v > 0 { n.scale = v }
            case "Decimals": if let v = try await ed.getInteger("Decimal places", defaultValue: s.decimals), (0...8).contains(v) { n.decimals = v }
            case "Prefix": n.prefix = try await ed.getWord("Prefix (. = none)", defaultValue: s.prefix.isEmpty ? "." : s.prefix).map { $0 == "." ? "" : $0 } ?? s.prefix
            case "SUffix": n.suffix = try await ed.getWord("Suffix (. = none)", defaultValue: s.suffix.isEmpty ? "." : s.suffix).map { $0 == "." ? "" : $0 } ?? s.suffix
            case "LinearScale": if let v = try await ed.getReal("Linear scale factor (DIMLFAC)", defaultValue: s.linearScale).value, v > 0 { n.linearScale = v }
            case "EXtension": n.extensionExtend = try await ed.getPositive("Extend beyond dimension lines", defaultValue: s.extensionExtend, allowZero: true)
            case "Offset": n.extensionOffset = try await ed.getPositive("Offset from origin", defaultValue: s.extensionOffset, allowZero: true)
            case "Gap": n.textGap = try await ed.getPositive("Text gap", defaultValue: s.textGap, allowZero: true)
            default: return
            }
            ed.doc.dimStyles[i] = n
            DimStyleExtras.set(x, style: name, doc: &ed.doc)
        }
    }
}
