// Oanarina Archi Tool — GPL-3.0-or-later
// Construction drafting tools: lines by angle / relative angle / parallel / perpendicular / bisector / tangents,
// Apollonius circles (TTT, tangent + points, 2 points + radius, inscribed), arcs by height or length,
// ellipses by foci / centre + 3 points / 4 points, polygon by opposite sides, point rows and lattices, snake lines,
// equidistant offsets, cutting by a line and GD&T feature control frames.
import Foundation

extension Editor {
    /// Tangency operand from a picked object (line, polyline straight segment, circle, arc, point).
    func tangentItem(_ id: EntityID, pick: Vec2) -> Construct.TangentItem? {
        guard let g = doc.entity(id)?.geometry else { return nil }
        switch g {
        case .line(let l): return .line(l.a, l.b)
        case .circle(let c): return .circle(c.center, c.radius)
        case .arc(let a): return .circle(a.center, a.radius)
        case .point(let p): return .point(p)
        case .polyline(let p):
            guard let part = Constraints.segmentPart(g, near: pick) else { return nil }
            let n = p.vertices.count
            let a = p.vertices[part], b = p.vertices[(part + 1) % n]
            if abs(a.bulge) > 1e-12 { let arc = GeometryOps.bulgeArc(a.p, b.p, a.bulge); return .circle(arc.center, arc.radius) }
            return .line(a.p, b.p)
        default: return nil
        }
    }
    /// A picked straight segment (line or polyline segment).
    func pickSegment(_ msg: String) async throws -> (Vec2, Vec2, Vec2)? {
        let isSeg: @MainActor (EntityID) -> Bool = { [unowned self] id in
            switch self.doc.entity(id)?.geometry { case .line?, .polyline?: return true; default: return false } }
        guard case .pick(let pk) = try await pickObject(msg, filter: isSeg), let g = doc.entity(pk.id)?.geometry,
              let part = Constraints.segmentPart(g, near: pk.point), let s = Constraints.segment(g, part: part) else { return nil }
        return (s.0, s.1, pk.point)
    }
    func pickCircleLike(_ msg: String) async throws -> (Vec2, Double, Vec2)? {
        let isC: @MainActor (EntityID) -> Bool = { [unowned self] id in
            switch self.doc.entity(id)?.geometry { case .circle?, .arc?: return true; default: return false } }
        guard case .pick(let pk) = try await pickObject(msg, filter: isC), let g = doc.entity(pk.id)?.geometry else { return nil }
        switch g { case .circle(let c): return (c.center, c.radius, pk.point); case .arc(let a): return (a.center, a.radius, pk.point); default: return nil }
    }
    /// Picks a tangency / through-point operand: an object, or a point when `allowPoint`.
    func pickTangentOperand(_ msg: String) async throws -> (Construct.TangentItem, Vec2)? {
        guard case .pick(let pk) = try await pickObject(msg, filter: { [unowned self] id in
            switch self.doc.entity(id)?.geometry { case .line?, .polyline?, .circle?, .arc?, .point?: return true; default: return false } }),
              let it = tangentItem(pk.id, pick: pk.point) else { return nil }
        return (it, pk.point)
    }
}

enum DraftConstructionCommands {
    @MainActor static func apolloniusCommand(_ ed: Editor, tangents: Int, points: Int, radius: Bool = false) async throws {
        var items: [Construct.TangentItem] = [], picks: [Vec2?] = []
        for i in 0..<tangents {
            guard let (it, p) = try await ed.pickTangentOperand("Specify point on object for \(["first", "second", "third"][i]) tangent of circle") else { return }
            items.append(it); picks.append(p)
        }
        for i in 0..<points {
            let p = try await ed.requirePoint("Specify \(["first", "second", "third"][tangents + i]) point on circle")
            items.append(.point(p)); picks.append(nil)
        }
        var r: Double? = nil
        if radius { r = try await ed.getPositive("Specify radius of circle", defaultValue: ed.variableDouble("CIRCLERAD", 100)) }
        let sols = Construct.apollonius(items, radius: r)
        guard let c = Construct.best(sols, items: items, picks: picks) else { throw CommandError.invalid("Circle does not exist.") }
        ed.doc.setVariable("CIRCLERAD", fmt(c.radius))
        ed.addEntity(.circle(c))
        ed.print("Circle: center \(c.center.description), radius \(fmt(c.radius)) (\(sols.count) solution(s)).")
    }

    static var all: [CommandDef] { lines + circles + curves + points + modify }

    // MARK: Lines
    static var lines: [CommandDef] { [
        CommandDef("LINEANG", aliases: ["LANG", "LINEBYANGLE"], category: "Draw", summary: "Draws a line from a point at a fixed angle and length.") { ed in
            let s = try await ed.requirePoint("Specify start point")
            let a = try await ed.getAngle("Specify angle", base: s, defaultValue: rad(ed.variableDouble("LINEANGLE", 0))).value ?? 0
            let dir = Vec2.polar(1, a)
            guard let len = try await ed.getDistance("Specify length", base: s, preview: { c in [.line(LineGeom(s, s + dir * (c - s).dot(dir)))] }).value, abs(len) > 1e-9 else { return }
            ed.doc.setVariable("LINEANGLE", fmt(deg(a)))
            ed.addEntity(.line(LineGeom(s, s + dir * len)))
        },
        CommandDef("LINEREL", aliases: ["LREL", "LINERELANGLE"], category: "Draw", summary: "Draws a line at an angle relative to a picked line or segment.") { ed in
            guard let (a, b, _) = try await ed.pickSegment("Select reference line") else { return }
            let rel = try await ed.getAngle("Specify angle relative to the line", defaultValue: rad(ed.variableDouble("LINERELANGLE", 90))).value ?? .pi / 2
            let dir = Vec2.polar(1, (b - a).angle + rel)
            let s = try await ed.requirePoint("Specify start point")
            guard let len = try await ed.getDistance("Specify length", base: s, preview: { c in [.line(LineGeom(s, s + dir * (c - s).dot(dir)))] }).value, abs(len) > 1e-9 else { return }
            ed.doc.setVariable("LINERELANGLE", fmt(deg(rel)))
            ed.addEntity(.line(LineGeom(s, s + dir * len)))
        },
        CommandDef("LINEHV", aliases: ["HVLINE", "LHV"], category: "Draw", summary: "Draws horizontal or vertical lines (end points are projected).") { ed in
            var s = try await ed.requirePoint("Specify start point")
            var vertical = (ed.doc.variable("LINEHVMODE") ?? "H") == "V"
            while true {
                let st = s, v = vertical
                let r = try await ed.getPoint("Specify end point", base: s, keywords: ["Horizontal", "Vertical"]) { c in [.line(LineGeom(st, v ? Vec2(st.x, c.y) : Vec2(c.x, st.y)))] }
                switch r {
                case .keyword("Horizontal"): vertical = false
                case .keyword("Vertical"): vertical = true
                case .point(let p):
                    let e = vertical ? Vec2(s.x, p.y) : Vec2(p.x, s.y)
                    guard !e.isClose(s, tol: 1e-9) else { continue }
                    ed.addEntity(.line(LineGeom(s, e))); s = e
                default: ed.doc.setVariable("LINEHVMODE", vertical ? "V" : "H"); return
                }
            }
        },
        CommandDef("LINEPAR", aliases: ["LPAR", "PARALLELLINE"], category: "Draw", summary: "Draws a line parallel to a picked line through a point.") { ed in
            guard let (a, b, _) = try await ed.pickSegment("Select line to be parallel to") else { return }
            let dir = (b - a).normalized
            let s = try await ed.requirePoint("Specify through point")
            let r = try await ed.getDistanceOrPoint("Specify end point or length", base: s, defaultValue: a.distance(to: b)) { c in [.line(LineGeom(s, s + dir * (c - s).dot(dir)))] }
            var len = r.value ?? a.distance(to: b)
            if let p = r.point { len = (p - s).dot(dir) }
            guard abs(len) > 1e-9 else { return }
            ed.addEntity(.line(LineGeom(s, s + dir * len)))
        },
        CommandDef("LINEPERP", aliases: ["LPERP", "PERPLINE"], category: "Draw", summary: "Draws a line from a point perpendicular to a picked line (to its foot).") { ed in
            guard let (a, b, _) = try await ed.pickSegment("Select line") else { return }
            let p = try await ed.requirePoint("Specify point") { c in [.line(LineGeom(c, Construct.foot(c, a, b)))] }
            let f = Construct.foot(p, a, b)
            if f.isClose(p, tol: 1e-9) {
                // On the line: perpendicular of a given length.
                let n = (b - a).normalized.perp
                guard let len = try await ed.getDistance("Point is on the line. Specify length", base: p, preview: { c in [.line(LineGeom(p, p + n * (c - p).dot(n)))] }).value, abs(len) > 1e-9 else { return }
                ed.addEntity(.line(LineGeom(p, p + n * len))); return
            }
            ed.addEntity(.line(LineGeom(p, f)))
        },
        CommandDef("LINEBISECT", aliases: ["LBIS", "BISECTOR"], category: "Draw", summary: "Draws the bisector of the angle between two lines from their intersection.") { ed in
            guard let (a1, b1, p1) = try await ed.pickSegment("Select first line"), let (a2, b2, p2) = try await ed.pickSegment("Select second line") else { return }
            guard let (o, dir) = Construct.bisector(LineGeom(a1, b1), LineGeom(a2, b2), toward: (p1 + p2) / 2) else { throw CommandError.invalid("The lines are parallel.") }
            let def = (a1.distance(to: b1) + a2.distance(to: b2)) / 2
            let len = try await ed.getDistance("Specify length of bisector", base: o, defaultValue: def, preview: { c in [.line(LineGeom(o, o + dir * max(0, (c - o).dot(dir))))] }).value ?? def
            guard len > 1e-9 else { return }
            ed.addEntity(.line(LineGeom(o, o + dir * len)))
        },
        CommandDef("LINETAN", aliases: ["LTAN", "TANLINE"], category: "Draw", summary: "Draws a line from a point tangent to a circle or arc.") { ed in
            let p = try await ed.requirePoint("Specify start point")
            guard let (c, r, pick) = try await ed.pickCircleLike("Select circle or arc near the tangent point") else { return }
            let ts = Construct.tangentPoints(from: p, center: c, radius: r)
            guard let t = ts.min(by: { $0.distance(to: pick) < $1.distance(to: pick) }) else { throw CommandError.invalid("The point is inside the circle.") }
            ed.addEntity(.line(LineGeom(p, t)))
        },
        CommandDef("LINETAN2", aliases: ["LTAN2", "TANGENTLINE2"], category: "Draw", summary: "Draws a common tangent of two circles (Outer or Inner), picked near the tangent points.") { ed in
            guard let (c1, r1, p1) = try await ed.pickCircleLike("Select first circle or arc"), let (c2, r2, p2) = try await ed.pickCircleLike("Select second circle or arc") else { return }
            let k = try await ed.getKeyword("Tangent type", ["Outer", "Inner"], defaultValue: ed.doc.variable("LINETAN2MODE") ?? "Outer") ?? "Outer"
            ed.doc.setVariable("LINETAN2MODE", k)
            let ts = Construct.commonTangents(c1, r1, c2, r2, kind: k == "Inner" ? .inner : .outer)
            guard let t = ts.min(by: { $0.0.distance(to: p1) + $0.1.distance(to: p2) < $1.0.distance(to: p1) + $1.1.distance(to: p2) }) else {
                throw CommandError.invalid("No \(k.lowercased()) tangent exists for these circles.") }
            ed.addEntity(.line(LineGeom(t.0, t.1)))
        },
        CommandDef("LINETANORTHO", aliases: ["LTANO"], category: "Draw", summary: "Draws a line tangent to a circle and perpendicular to a line (from the tangent point to the line).") { ed in
            guard let (c, r, pick) = try await ed.pickCircleLike("Select circle or arc near the tangent point") else { return }
            guard let (a, b, _) = try await ed.pickSegment("Select line to be perpendicular to") else { return }
            let u = (b - a).normalized
            let cands = [c + u * r, c - u * r]
            let t = cands.min { $0.distance(to: pick) < $1.distance(to: pick) }!
            let f = Construct.foot(t, a, b)
            guard !f.isClose(t, tol: 1e-9) else { throw CommandError.invalid("The tangent point lies on the line.") }
            ed.addEntity(.line(LineGeom(t, f)))
        },
        CommandDef("SNAKE", aliases: ["SNAKELINE"], category: "Draw", summary: "Draws a polyline from relative moves: R500 L200 U300 D100 (right/left/up/down), @dx,dy or @d<angle; Close/Undo.") { ed in
            let s = try await ed.requirePoint("Specify start point")
            var pts = [s]
            var close = false
            while true {
                guard let t = try await ed.getWord("Enter move (R/L/U/D + distance, @dx,dy, @d<a) or [Close/Undo]", keywords: pts.count > 2 ? ["Close", "Undo"] : ["Undo"]) else { break }
                if t == "Close" { close = true; break }
                if t == "Undo" { if pts.count > 1 { pts.removeLast() }; continue }
                let cur = pts.last!
                let up = t.uppercased()
                if let c = up.first, "RLUD".contains(c), let d = InputParser.parseNumber(String(up.dropFirst())) ?? CommandHelpers.evaluate(String(up.dropFirst())) {
                    let v: Vec2 = c == "R" ? Vec2(d, 0) : c == "L" ? Vec2(-d, 0) : c == "U" ? Vec2(0, d) : Vec2(0, -d)
                    pts.append(cur + v); ed.lastPoint = pts.last
                } else if let p = InputParser.parsePoint(t, last: cur) { pts.append(p); ed.lastPoint = p }
                else { ed.print("Invalid move \"\(t)\".") }
            }
            guard pts.count >= 2 else { return }
            ed.addEntity(.polyline(PolylineGeom(points: pts, closed: close && pts.count > 2)))
        },
    ] }

    // MARK: Circles
    static var circles: [CommandDef] { [
        CommandDef("CIRCLETTT", aliases: ["CTTT"], category: "Draw", summary: "Draws a circle tangent to three objects (lines, circles, arcs).") { ed in try await apolloniusCommand(ed, tangents: 3, points: 0) },
        CommandDef("CIRCLETPP", aliases: ["CTPP"], category: "Draw", summary: "Draws a circle tangent to one object through two points.") { ed in try await apolloniusCommand(ed, tangents: 1, points: 2) },
        CommandDef("CIRCLETTP", aliases: ["CTTP"], category: "Draw", summary: "Draws a circle tangent to two objects through one point.") { ed in try await apolloniusCommand(ed, tangents: 2, points: 1) },
        CommandDef("CIRCLE2PR", aliases: ["C2PR"], category: "Draw", summary: "Draws a circle through two points with a given radius (pick the side of the centre).") { ed in
            let p1 = try await ed.requirePoint("Specify first point on circle")
            let p2 = try await ed.requirePoint("Specify second point on circle", base: p1)
            let r = try await ed.getPositive("Specify radius of circle", defaultValue: max(ed.variableDouble("CIRCLERAD", 0), p1.distance(to: p2) / 2))
            let side = try await ed.getPoint("Specify side of the centre", base: (p1 + p2) / 2) { c in Construct.circle2PR(p1, p2, radius: r, side: c).map { [.circle($0)] } ?? [] }.point ?? ((p1 + p2) / 2 + (p2 - p1).perp)
            guard let c = Construct.circle2PR(p1, p2, radius: r, side: side) else { throw CommandError.invalid("The radius is smaller than half the distance between the points.") }
            ed.doc.setVariable("CIRCLERAD", fmt(r))
            ed.addEntity(.circle(c))
        },
        CommandDef("INCIRCLE", aliases: ["CIRCLEINSCRIBED"], category: "Draw", summary: "Draws the circle inscribed in the triangle formed by three lines.") { ed in
            guard let (a1, b1, _) = try await ed.pickSegment("Select first line"), let (a2, b2, _) = try await ed.pickSegment("Select second line"),
                  let (a3, b3, _) = try await ed.pickSegment("Select third line") else { return }
            guard let c = Construct.incircle(LineGeom(a1, b1), LineGeom(a2, b2), LineGeom(a3, b3)) else { throw CommandError.invalid("The lines do not form a triangle.") }
            ed.addEntity(.circle(c))
        },
        CommandDef("ARCTOCIRCLE", aliases: ["CIRCLEFROMARC", "ARC2CIRCLE"], category: "Draw", summary: "Completes arcs into full circles (keeps layer and properties).") { ed in
            let ids = try await ed.getEntitySelection("Select arcs")
            var n = 0
            for id in ids { if let i = ed.doc.entityIndex(id), case .arc(let a) = ed.doc.entities[i].geometry { ed.doc.entities[i].geometry = .circle(CircleGeom(a.center, a.radius)); n += 1 } }
            ed.print("\(n) arc(s) converted to circles.")
        },
    ] }

    // MARK: Arcs, ellipses, polygons
    static var curves: [CommandDef] { [
        CommandDef("ARC2PH", aliases: ["ARCHEIGHT"], category: "Draw", summary: "Draws an arc through two end points with a given height (sagitta); pick or type the height.") { ed in
            let p1 = try await ed.requirePoint("Specify start point of arc")
            let p2 = try await ed.requirePoint("Specify end point of arc", base: p1)
            guard p1.distance(to: p2) > 1e-9 else { throw CommandError.invalid("The points coincide.") }
            let m = (p1 + p2) / 2, n = (p2 - p1).normalized.perp
            let r = try await ed.getDistanceOrPoint("Specify height of arc", base: m) { c in Construct.arcByHeight(p1, p2, height: (c - m).dot(n)).map { [.arc($0)] } ?? [] }
            var h = r.value ?? 0
            if let p = r.point { h = (p - m).dot(n) }
            guard abs(h) > 1e-9, let a = Construct.arcByHeight(p1, p2, height: h) else { throw CommandError.invalid("The height must not be zero.") }
            ed.addEntity(.arc(a))
        },
        CommandDef("ARC2PL", aliases: ["ARCBYLENGTH"], category: "Draw", summary: "Draws an arc through two end points with a given arc length (longer than the chord).") { ed in
            let p1 = try await ed.requirePoint("Specify start point of arc")
            let p2 = try await ed.requirePoint("Specify end point of arc", base: p1)
            let chord = p1.distance(to: p2)
            let L = try await ed.getPositive("Specify arc length", defaultValue: chord * .pi / 2)
            guard L > chord else { throw CommandError.invalid("The arc length must be longer than the chord (\(fmt(chord))).") }
            let m = (p1 + p2) / 2, n = (p2 - p1).normalized.perp
            let side = try await ed.getPoint("Specify side of the arc", base: m) { c in Construct.arcByLength(p1, p2, length: L, left: (c - m).dot(n) >= 0).map { [.arc($0)] } ?? [] }.point ?? (m + n)
            guard let a = Construct.arcByLength(p1, p2, length: L, left: (side - m).dot(n) >= 0) else { throw CommandError.invalid("Arc does not exist.") }
            ed.addEntity(.arc(a))
        },
        CommandDef("ELLIPSEFOCI", aliases: ["ELFOCI"], category: "Draw", summary: "Draws an ellipse from its two foci and a point on the curve.") { ed in
            let f1 = try await ed.requirePoint("Specify first focus")
            let f2 = try await ed.requirePoint("Specify second focus", base: f1)
            let p = try await ed.requirePoint("Specify point on ellipse") { c in Construct.ellipseFoci(f1, f2, through: c).map { [.ellipse($0)] } ?? [] }
            guard let e = Construct.ellipseFoci(f1, f2, through: p) else { throw CommandError.invalid("Ellipse does not exist.") }
            ed.addEntity(.ellipse(e))
        },
        CommandDef("ELLIPSEC3P", aliases: ["ELC3P"], category: "Draw", summary: "Draws an ellipse from its centre and three points on the curve.") { ed in
            let c = try await ed.requirePoint("Specify center of ellipse")
            var pts: [Vec2] = []
            for i in 0..<3 {
                let cur = pts
                let p = try await ed.requirePoint("Specify \(["first", "second", "third"][i]) point on ellipse", base: c) { q in
                    cur.count == 2 ? (Construct.ellipseCenter3(c, cur + [q]).map { [.ellipse($0)] } ?? []) : [] }
                pts.append(p)
            }
            guard let e = Construct.ellipseCenter3(c, pts) else { throw CommandError.invalid("No ellipse with this centre passes through the points.") }
            ed.addEntity(.ellipse(e))
        },
        CommandDef("ELLIPSE4P", aliases: ["EL4P"], category: "Draw", summary: "Draws an ellipse through four points with its axes at a given angle (default 0).") { ed in
            var pts: [Vec2] = []
            for i in 0..<4 { pts.append(try await ed.requirePoint("Specify \(["first", "second", "third", "fourth"][i]) point on ellipse")) }
            let rot = try await ed.getAngle("Specify axis angle", defaultValue: 0).value ?? 0
            guard let e = Construct.ellipse4(pts, rotation: rot) else { throw CommandError.invalid("No ellipse with axes at that angle passes through the four points.") }
            ed.addEntity(.ellipse(e))
        },
        CommandDef("POLYGONSS", aliases: ["POLSS", "POLYGONSIDES"], category: "Draw", summary: "Draws a regular polygon from the midpoint of one side and the opposite side (odd sides: opposite vertex).") { ed in
            let n = try await ed.getInteger("Enter number of sides", defaultValue: Int(ed.variableDouble("POLYSIDES", 6))) ?? 6
            guard n >= 3, n <= 1024 else { throw CommandError.invalid("Requires 3 to 1024 sides.") }
            let p1 = try await ed.requirePoint("Specify midpoint of first side")
            let p2 = try await ed.requirePoint(n % 2 == 0 ? "Specify midpoint of opposite side" : "Specify opposite vertex", base: p1) { c in
                Construct.polygonSideSide(sides: n, p1, c).map { [.polyline(PolylineGeom(points: $0, closed: true))] } ?? [] }
            guard let pts = Construct.polygonSideSide(sides: n, p1, p2) else { throw CommandError.invalid("The points coincide.") }
            ed.doc.setVariable("POLYSIDES", "\(n)")
            ed.addEntity(.polyline(PolylineGeom(points: pts, closed: true)))
        },
        CommandDef("TOLERANCE", aliases: ["TOL", "GDT"], category: "Annotate", summary: "Creates a GD&T feature control frame: characteristic symbol, tolerance value, datums.") { ed in
            let symbols: [(String, String)] = [("Position", "⌖"), ("Flatness", "⏥"), ("Straightness", "⏤"), ("Circularity", "○"), ("Cylindricity", "⌭"),
                                               ("PRofile", "⌒"), ("SUrface", "⌓"), ("PErpendicularity", "⟂"), ("PArallelism", "∥"), ("ANgularity", "∠"),
                                               ("COncentricity", "◎"), ("SYmmetry", "⌯"), ("RUnout", "↗"), ("TOtalrunout", "⌰")]
            let k = try await ed.getKeyword("Geometric characteristic", symbols.map(\.0), defaultValue: "Position") ?? "Position"
            let sym = symbols.first { $0.0 == k }?.1 ?? "⌖"
            guard let tol = try await ed.getWord("Enter tolerance value (prefix %%c or Ø for a diameter zone)", defaultValue: "0.1") else { return }
            let datums = (try await ed.getWord("Enter datum references (e.g. A B C)", defaultValue: "")) ?? ""
            let ins = try await ed.requirePoint("Enter tolerance location")
            let h = ed.settings.textHeight
            let value = tol.replacingOccurrences(of: "%%c", with: "Ø").replacingOccurrences(of: "%%C", with: "Ø")
            var cells = [sym, value]
            cells += datums.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            let pad = h * 0.5, H = h * 2
            var x = ins.x
            let group = "GDT\(ed.doc.nextID)"
            var ids: [EntityID] = []
            for (i, c) in cells.enumerated() {
                let w = i == 0 ? H : max(H, Double(c.count) * h * 0.75 + 2 * pad)
                let rect = [Vec2(x, ins.y - H / 2), Vec2(x + w, ins.y - H / 2), Vec2(x + w, ins.y + H / 2), Vec2(x, ins.y + H / 2)]
                ids.append(ed.addEntity(.polyline(PolylineGeom(points: rect, closed: true))))
                ids.append(ed.addEntity(.text(TextGeom(position: Vec2(x + w / 2, ins.y), height: h, content: c, halign: .center, valign: .middle))))
                x += w
            }
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["group"] = group; ed.doc.entities[i].props["gdt"] = "1" } }
            ed.print("Feature control frame: \(cells.joined(separator: " | ")).")
        },
    ] }

    // MARK: Points
    static var points: [CommandDef] { [
        CommandDef("POINTSLINE", aliases: ["PTLINE", "POINTSONLINE"], category: "Draw", summary: "Places a number of evenly spaced points between two points (both ends included).") { ed in
            let a = try await ed.requirePoint("Specify first point")
            let b = try await ed.requirePoint("Specify second point", base: a)
            let n = try await ed.getInteger("Enter number of points", defaultValue: Int(ed.variableDouble("POINTSCOUNT", 5))) ?? 5
            guard n >= 1, n <= 100_000 else { throw CommandError.invalid("Requires 1 to 100000 points.") }
            ed.doc.setVariable("POINTSCOUNT", "\(n)")
            for p in Construct.pointsOnLine(a, b, count: n) { ed.addEntity(.point(p)) }
        },
        CommandDef("POINTLATTICE", aliases: ["PTLATTICE", "POINTGRID"], category: "Draw", summary: "Places a lattice of points (columns × rows at given spacings, optional angle).") { ed in
            let o = try await ed.requirePoint("Specify base point")
            let cols = try await ed.getInteger("Enter number of columns", defaultValue: 5) ?? 5
            let rows = try await ed.getInteger("Enter number of rows", defaultValue: 5) ?? 5
            guard cols >= 1, rows >= 1, cols * rows <= 100_000 else { throw CommandError.invalid("Requires 1 to 100000 points.") }
            let dx = try await ed.getDistance("Specify column spacing", base: o, defaultValue: ed.variableDouble("LATTICEDX", 1000)).value ?? 1000
            let dy = try await ed.getDistance("Specify row spacing", base: o, defaultValue: ed.variableDouble("LATTICEDY", dx)).value ?? dx
            let ang = try await ed.getAngle("Specify angle of lattice", base: o, defaultValue: 0).value ?? 0
            ed.doc.setVariable("LATTICEDX", fmt(dx)); ed.doc.setVariable("LATTICEDY", fmt(dy))
            for p in Construct.lattice(origin: o, columns: cols, rows: rows, dx: dx, dy: dy, angle: ang) { ed.addEntity(.point(p)) }
        },
    ] }

    // MARK: Modify helpers that build geometry
    static var modify: [CommandDef] { [
        CommandDef("CUTBYLINE", aliases: ["SLICELINE", "DIVIDEBYLINE"], category: "Modify", summary: "Divides the selected objects where a cutting line crosses them.") { ed in
            let ids = try await ed.getEntitySelection("Select objects to divide")
            let a = try await ed.requirePoint("Specify first point of cutting line")
            let b = try await ed.requirePoint("Specify second point of cutting line", base: a) { c in [.line(LineGeom(a, c))] }
            let cut = Geometry.line(LineGeom(a, b))
            var pieces = 0
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                let xs = Intersections.of(e.geometry, cut, doc: ed.doc)
                guard !xs.isEmpty else { continue }
                let parts = Construct.split(e.geometry, at: xs)
                if parts.count > 1 { pieces += parts.count; ed.replaceEntity(id, with: parts) }
            }
            ed.print("\(pieces) piece(s) created.")
        },
        CommandDef("OFFSETMULTI", aliases: ["EQUIDISTANT", "OFFSETM"], category: "Modify", summary: "Creates several equidistant offset copies of an object on one side.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object to offset", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
            let d = try await ed.getPositive("Specify offset distance", defaultValue: ed.settings.offsetDistance)
            let n = try await ed.getInteger("Enter number of copies", defaultValue: 3) ?? 3
            guard n >= 1, n <= 1000 else { throw CommandError.invalid("Requires 1 to 1000 copies.") }
            let side = try await ed.requirePoint("Specify point on side to offset")
            var made = 0
            for k in 1...n {
                guard let g = Modify.offset(e.geometry, distance: d * Double(k), towards: side) else { break }
                var c = e; c.geometry = g; ed.doc.add(c); made += 1
            }
            ed.settings.offsetDistance = d
            ed.print("\(made) offset cop\(made == 1 ? "y" : "ies") created.")
        },
    ] }
}
