// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for the building checks and the issue tracker: LOADTAKEDOWN, RAINWATER, PARKINGCHECK, FIRECOMPARTMENTS,
// ISSUE; and inquiry helpers TLEN (total length), ANGLEBETWEEN, DISTTOOBJECT, POINTINSIDE.
import Foundation

public enum CheckCommands {
    public static var all: [CommandDef] { [loadTakedown, rainwater, parkingCheck, fireCompartments, issue, totalLength, angleBetween, distToObject, pointInside] }

    @MainActor static func csvOption(_ ed: Editor, _ rows: [[String]], defaultName: String) async throws {
        let k = try await ed.getKeyword("Write a CSV report? [Yes/No]", ["Yes", "No"], defaultValue: "No") ?? "No"
        guard k == "Yes" else { return }
        guard let p = try await ed.getWord("Enter CSV file name <\(defaultName)>", defaultValue: defaultName) else { return }
        let url = IOCommands.resolve(ed, p)
        try IOCommands.write(ed, url, "report") { try CSVText.make(rows).write(to: url, atomically: true, encoding: .utf8) }
    }

    static var loadTakedown: CommandDef {
        CommandDef("LOADTAKEDOWN", aliases: ["TAKEDOWN", "COLUMNLOADS"], category: "Analysis",
                   summary: "Structural load takedown per column: tributary slab areas, dead (self weight + LOADSDL) and imposed loads by room usage, accumulated down the stacked columns, ULS 1.35G+1.5Q, SLS and axial stress; optional CSV.", modifies: false) { ed in
            var o = TakedownOptions.from(ed.doc)
            o.superimposedDead = try await ed.getReal("Superimposed dead load kN/m²", defaultValue: o.superimposedDead).value ?? o.superimposedDead
            o.live = try await ed.getReal("Default imposed load kN/m²", defaultValue: o.live).value ?? o.live
            let r = LoadTakedown.compute(ed.doc, options: o)
            guard !r.rows.isEmpty else { ed.print("No columns found."); return }
            BuildingAnalysisCommands.printTable(ed, r.table)
            if r.wallArea > 0 { ed.print("Floor area carried by bearing walls: \(fmt(r.wallArea, 1)) m²") }
            if let top = r.rows.max(by: { $0.uls < $1.uls }) { ed.print("Most loaded column: #\(top.column) on \(top.levelName), ULS \(fmt(top.uls, 1)) kN") }
            ed.selection = Set(r.rows.map(\.column))
            try await csvOption(ed, r.table, defaultName: "load-takedown.csv")
        }
    }

    static var rainwater: CommandDef {
        CommandDef("RAINWATER", aliases: ["RAINCALC", "DOWNPIPES"], category: "Analysis",
                   summary: "Rainwater from roofs: plan area incl. overhangs, runoff coefficient, design flow Q = C·i·A, downpipes (EN 12056-3 capacities), gutter length and annual harvest; optional CSV.", modifies: false) { ed in
            var o = RainwaterOptions.from(ed.doc)
            o.intensity = try await ed.getReal("Design rainfall intensity l/(s·m²)", defaultValue: o.intensity).value ?? o.intensity
            o.annualRainfall = try await ed.getReal("Annual rainfall mm", defaultValue: o.annualRainfall).value ?? o.annualRainfall
            ed.doc.setVariable("RAININTENSITY", fmt(o.intensity, 5)); ed.doc.setVariable("ANNUALRAINFALL", fmt(o.annualRainfall, 1))
            let rows = Rainwater.compute(ed.doc, options: o)
            guard !rows.isEmpty else { ed.print("No roofs found (roof elements, or slabs with prop roof=1)."); return }
            let t: [[String]] = [["element", "kind", "area_m2", "C", "Q_l/s", "downpipes", "DN", "gutter_m", "harvest_m3/yr"]] + rows.map {
                ["#\($0.element)", $0.kind, fmt($0.planArea, 2), fmt($0.coefficient, 2), fmt($0.flow, 2), "\($0.downpipes)", "\($0.downpipeDN)", fmt($0.gutterLength, 2), fmt($0.harvest, 1)]
            }
            BuildingAnalysisCommands.printTable(ed, t)
            ed.print("Total: \(fmt(rows.reduce(0) { $0 + $1.flow }, 2)) l/s, \(rows.reduce(0) { $0 + $1.downpipes }) downpipes, \(fmt(rows.reduce(0) { $0 + $1.harvest }, 1)) m³ harvestable per year")
            try await csvOption(ed, t, defaultName: "rainwater.csv")
        }
    }

    static var parkingCheck: CommandDef {
        CommandDef("PARKINGCHECK", aliases: ["PARKINGCOUNT", "PARKINGREQ"], category: "Analysis",
                   summary: "Parking provision check: required spaces from room usage and area (PARKINGRULES, e.g. office=35;apartment=unit:1) against the parking spaces placed, including accessible spaces.", modifies: false) { ed in
            let cur = ed.doc.variable("PARKINGRULES") ?? "office=35;retail=25;shop=25;restaurant=10;apartment=unit:1;flat=unit:1;dwelling=unit:1;classroom=unit:0.5"
            if let s = try await ed.getString("Parking rules <\(cur)>", defaultValue: cur), !s.isEmpty, s != cur {
                guard !ParkingRule.parse(s).isEmpty else { throw CommandError.invalid("Rules look like office=35;apartment=unit:1") }
                ed.doc.setVariable("PARKINGRULES", s)
            }
            let r = ParkingCheck.check(ed.doc)
            for l in r.text.split(separator: "\n") { ed.print(String(l)) }
        }
    }

    static var fireCompartments: CommandDef {
        CommandDef("FIRECOMPARTMENTS", aliases: ["FIRECHECK", "COMPARTMENTS"], category: "Analysis",
                   summary: "Fire compartments: room areas grouped by prop fireCompartment (else per level) against FIREMAXAREA (doubled with FIRESPRINKLERS=1), and walls between compartments below FIRERATINGREQ minutes; selects failing walls.", modifies: false) { ed in
            let r = FireCompartments.check(ed.doc)
            guard !r.compartments.isEmpty else { ed.print("No rooms found."); return }
            for l in r.text.split(separator: "\n") { ed.print(String(l)) }
            if !r.unratedWalls.isEmpty { ed.selection = Set(r.unratedWalls) }
            let bad = r.compartments.filter { !$0.ok }.count
            ed.print(bad == 0 && r.unratedWalls.isEmpty ? "All compartments comply." : "\(bad) compartments too large, \(r.unratedWalls.count) walls to upgrade.")
        }
    }

    static var issue: CommandDef {
        CommandDef("ISSUETRACKER", aliases: ["ISSUELIST", "TRACKISSUES"], category: "Collaborate",
                   summary: "Issue tracker stored in the drawing: Add (linked to the selection), List, Show, Status, Assign, Priority, Comment, Zoom, Delete and Csv export.") { ed in
            let k = try await ed.getKeyword("Enter an option [Add/List/Show/Status/Assign/Priority/Comment/Zoom/Delete/Csv]",
                                            ["Add", "List", "Show", "Status", "Assign", "Priority", "Comment", "Zoom", "Delete", "Csv"], defaultValue: "List") ?? "List"
            @MainActor func number() async throws -> Int {
                guard let n = try await ed.getInteger("Enter issue number"), IssueTracker.issue(ed.doc, n) != nil else { throw CommandError.invalid("No such issue.") }
                return n
            }
            switch k {
            case "Add":
                guard let title = try await ed.getString("Issue title"), !title.isEmpty else { return }
                let desc = try await ed.getString("Description <none>", defaultValue: "") ?? ""
                let pr = Issue.parsePriority(try await ed.getKeyword("Priority [Low/Normal/High/Critical]", ["Low", "Normal", "High", "Critical"], defaultValue: "Normal") ?? "Normal") ?? .normal
                let who = try await ed.getString("Assign to <nobody>", defaultValue: "") ?? ""
                let ids = Array(ed.selection).sorted()
                var d = ed.doc
                let n = IssueTracker.add(&d, title: title, description: desc, priority: pr, assignee: who, elements: ids)
                ed.doc = d
                ed.print("Issue #\(n) added" + (ids.isEmpty ? "." : " for \(ids.count) objects."))
            case "List":
                let open = try await ed.getKeyword("Show [Open/All]", ["Open", "All"], defaultValue: "Open") ?? "Open"
                let list = IssueTracker.filter(ed.doc, openOnly: open == "Open")
                if list.isEmpty { ed.print("No \(open == "Open" ? "open " : "")issues.") }
                for i in list { ed.print(IssueTracker.line(i)) }
            case "Show":
                let i = IssueTracker.issue(ed.doc, try await number())!
                ed.print(IssueTracker.line(i))
                if !i.description.isEmpty { ed.print("  " + i.description) }
                ed.print("  created \(i.created) by \(i.author), modified \(i.modified)")
                for c in i.comments { ed.print("  ↳ \(c.author) \(c.date.prefix(10)): \(c.text)") }
            case "Status":
                let n = try await number()
                guard let s = try await ed.getKeyword("New status [Open/InProgress/Resolved/Closed]", ["Open", "InProgress", "Resolved", "Closed"]).flatMap(Issue.parseStatus) else { return }
                var d = ed.doc; IssueTracker.update(&d, n) { $0.status = s }; ed.doc = d
                ed.print("Issue #\(n) is \(s.rawValue).")
            case "Assign":
                let n = try await number()
                let who = try await ed.getString("Assign to") ?? ""
                var d = ed.doc; IssueTracker.update(&d, n) { $0.assignee = who; if $0.status == .open && !who.isEmpty { $0.status = .inProgress } }; ed.doc = d
                ed.print(who.isEmpty ? "Issue #\(n) unassigned." : "Issue #\(n) assigned to \(who).")
            case "Priority":
                let n = try await number()
                guard let p = try await ed.getKeyword("Priority [Low/Normal/High/Critical]", ["Low", "Normal", "High", "Critical"]).flatMap(Issue.parsePriority) else { return }
                var d = ed.doc; IssueTracker.update(&d, n) { $0.priority = p }; ed.doc = d
            case "Comment":
                let n = try await number()
                guard let t = try await ed.getString("Comment"), !t.isEmpty else { return }
                var d = ed.doc; IssueTracker.comment(&d, n, text: t); ed.doc = d
            case "Zoom":
                let i = IssueTracker.issue(ed.doc, try await number())!
                let live = i.elements.filter { ed.doc.contains($0) }
                ed.selection = Set(live)
                if let l = i.level, ed.doc.level(l) != nil { ed.doc.currentLevel = l }
                if let b = IssueTracker.bounds(ed.doc, live) { ed.host?.perform(.zoomWindow(b.expanded(by: max(b.width, b.height) * 0.2 + 1)), editor: ed) }
                else if let c = i.viewCenter, let h = i.viewHeight { ed.host?.perform(.zoomWindow(BBox2(min: c - Vec2(h * 0.8, h / 2), max: c + Vec2(h * 0.8, h / 2))), editor: ed) }
                ed.print(IssueTracker.line(i))
            case "Delete":
                let n = try await number()
                var d = ed.doc; IssueTracker.remove(&d, n); ed.doc = d
                ed.print("Issue #\(n) deleted.")
            default:
                let url = try await IOCommands.path(ed, "Enter CSV file name")
                try IOCommands.write(ed, url, "issues") { try IssueTracker.csv(ed.doc).write(to: url, atomically: true, encoding: .utf8) }
            }
        }
    }

    // MARK: Inquiry helpers

    static var totalLength: CommandDef {
        CommandDef("TLEN", aliases: ["TOTALLENGTH", "TOTLEN"], category: "Inquiry", summary: "Total length of the selected lines, arcs, circles, polylines, splines and ellipses (and wall lengths).", modifies: false) { ed in
            let ids = try await ed.getSelection("Select objects")
            var total = 0.0, n = 0
            for id in ids {
                if let e = ed.doc.entity(id) {
                    switch e.geometry {
                    case .line, .arc, .circle, .polyline, .spline, .ellipse: total += GeometryOps.length(e.geometry, doc: ed.doc); n += 1
                    default: continue
                    }
                } else if let el = ed.doc.element(id), case .wall(let w) = el.geometry { total += w.length; n += 1 }
            }
            ed.selection = []
            ed.print("\(n) objects, total length = \(fmt(total, 4))" + (n > 0 ? "  (\(CommandHelpers.lengthText(total, units: ed.doc.units)))" : ""))
        }
    }

    /// Angle (0…180°) between two directions, and its supplement.
    public static func angleBetweenDegrees(_ a: Vec2, _ b: Vec2) -> Double {
        guard a.length > 1e-12, b.length > 1e-12 else { return 0 }
        return acos(max(-1, min(1, a.normalized.dot(b.normalized)))) * 180 / .pi
    }

    static var angleBetween: CommandDef {
        CommandDef("ANGLEBETWEEN", aliases: ["ANGBETWEEN", "LINEANGLE"], category: "Inquiry", summary: "Angle between two lines (or vertex + two points).", modifies: false) { ed in
            let mode = try await ed.getKeyword("Measure between [Lines/Points]", ["Lines", "Points"], defaultValue: "Lines") ?? "Lines"
            var u = Vec2.zero, v = Vec2.zero
            if mode == "Points" {
                let c = try await ed.requirePoint("Specify angle vertex")
                let p1 = try await ed.requirePoint("Specify first angle endpoint", base: c)
                let p2 = try await ed.requirePoint("Specify second angle endpoint", base: c)
                u = p1 - c; v = p2 - c
            } else {
                @MainActor func dir(_ id: EntityID?) -> Vec2? {
                    guard let id = id else { return nil }
                    if let e = ed.doc.entity(id), case .line(let l) = e.geometry { return l.b - l.a }
                    if let e = ed.doc.entity(id), case .polyline(let pl) = e.geometry, pl.vertices.count == 2 { return pl.vertices[1].p - pl.vertices[0].p }
                    if let el = ed.doc.element(id), case .wall(let w) = el.geometry { return w.end - w.start }
                    if let el = ed.doc.element(id), case .beam(let b) = el.geometry { return b.end - b.start }
                    return nil
                }
                guard let a = dir(try await ed.getEntity("Select first line")), let b = dir(try await ed.getEntity("Select second line")) else { throw CommandError.invalid("Select two lines.") }
                u = a; v = b
            }
            let ang = angleBetweenDegrees(u, v)
            ed.print("Angle = \(fmt(ang, 4))°  (supplement \(fmt(180 - ang, 4))°)")
        }
    }

    static var distToObject: CommandDef {
        CommandDef("DISTTOOBJECT", aliases: ["DISTOBJ", "DISTTOENTITY"], category: "Inquiry", summary: "Shortest distance from a point to an object.", modifies: false) { ed in
            let p = try await ed.requirePoint("Specify point")
            guard let id = try await ed.getEntity("Select object"), let e = ed.doc.entity(id) else { throw CommandError.invalid("Select a drawing object.") }
            var best = Double.infinity, q = p
            for pts in GeometryOps.tessellate(e.geometry, doc: ed.doc) {
                if pts.count == 1 { let d = pts[0].distance(to: p); if d < best { best = d; q = pts[0] } }
                for i in 0..<max(pts.count - 1, 0) {
                    let c = GeometryOps.closestOnSegment(p, pts[i], pts[i + 1])
                    let d = c.distance(to: p)
                    if d < best { best = d; q = c }
                }
            }
            guard best.isFinite else { throw CommandError.invalid("The object has no measurable geometry.") }
            ed.print("Shortest distance = \(fmt(best, 4)) at \(fmt(q.x, 4)),\(fmt(q.y, 4))")
        }
    }

    static var pointInside: CommandDef {
        CommandDef("POINTINSIDE", aliases: ["INSIDECHECK", "PTINSIDE"], category: "Inquiry", summary: "Tells whether a point is inside, outside or on a closed contour (polyline, circle, ellipse, hatch, room, slab).", modifies: false) { ed in
            let p = try await ed.requirePoint("Specify point")
            guard let id = try await ed.getEntity("Select closed contour") else { return }
            var loop: [Vec2] = []
            if let e = ed.doc.entity(id) {
                switch e.geometry {
                case .polyline(let pl) where pl.closed: loop = GeometryOps.polylinePoints(pl)
                case .circle, .ellipse: loop = GeometryOps.tessellate(e.geometry, doc: ed.doc).first ?? []
                case .hatch(let h): loop = h.loops.first.map { GeometryOps.polylinePoints($0, closed: true) } ?? []
                default: break
                }
            } else if let el = ed.doc.element(id) {
                switch el.geometry {
                case .space(let s): loop = s.boundary
                case .slab(let s): loop = s.boundary
                case .roof(let r): loop = r.boundary
                default: break
                }
            }
            guard loop.count >= 3 else { throw CommandError.invalid("Select a closed contour.") }
            let tol = max(BBox2(points: loop).width, BBox2(points: loop).height) * 1e-9 + 1e-9
            let d = GeometryOps.distance(from: p, toPolyline: loop + [loop[0]])
            ed.print(d <= tol ? "The point is ON the contour." : (GeometryOps.pointInPolygon(p, loop) ? "The point is INSIDE the contour (\(fmt(d, 4)) from the edge)." : "The point is OUTSIDE the contour (\(fmt(d, 4)) from the edge)."))
        }
    }
}
