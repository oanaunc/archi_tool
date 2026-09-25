// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

enum InquiryCommands {
    static var all: [CommandDef] { [dist, area, id, list, count, measureGeom, massProp, status, cal] }

    /// Area and perimeter of a closed entity or a building element footprint.
    static func areaPerimeter(_ id: EntityID, doc: ArchiDocument) -> (Double, Double)? {
        if let e = doc.entity(id) {
            guard let a = GeometryOps.area(e.geometry, doc: doc) else {
                if case .solid(let s) = e.geometry { let f = GeometryOps.solidFootprint(s); return (abs(GeometryOps.signedArea(f)), CommandHelpers.polylineLength(f)) }
                return nil
            }
            var per = GeometryOps.length(e.geometry, doc: doc)
            if case .hatch(let h) = e.geometry { per = h.loops.reduce(0) { $0 + CommandHelpers.polylineLength(GeometryOps.polylinePoints($1, closed: true)) } }
            return (a, per)
        }
        if let el = doc.element(id) {
            var poly: [Vec2]
            var holes: [[Vec2]] = []
            switch el.geometry {
            case .slab(let s): poly = s.boundary; holes = s.holes
            case .space(let s): poly = s.boundary
            case .roof(let r): poly = r.boundary
            default: poly = CommandHelpers.footprint(el, doc: doc)
            }
            guard poly.count >= 3, !CommandHelpers.isOpenPath(el) else { return nil }
            let a = abs(GeometryOps.signedArea(poly)) - holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }
            return (a, CommandHelpers.polylineLength(poly + [poly[0]]))
        }
        return nil
    }

    /// Volume of 3D solids and building elements (drawing units³).
    static func volume(_ id: EntityID, doc: ArchiDocument) -> Double? {
        if let e = doc.entity(id), case .solid(let s) = e.geometry {
            switch s.kind {
            case .box: return s.size.x * s.size.y * s.size.z
            case .cylinder: return .pi * s.size.x * s.size.x * s.size.z
            case .cone: let r1 = s.size.x, r2 = s.size.y; return .pi * s.size.z * (r1 * r1 + r1 * r2 + r2 * r2) / 3
            case .sphere: return 4 / 3 * .pi * pow(s.size.x, 3)
            case .extrusion: return abs(GeometryOps.signedArea(s.profile)) * s.height
            case .revolve:
                // Pappus: area × distance travelled by the centroid (axis = local Y).
                let a = abs(GeometryOps.signedArea(s.profile)), c = GeometryOps.centroid(s.profile)
                return a * abs(c.x) * s.height
            case .mesh:
                var v = 0.0
                let t = s.meshTriangles, p = s.meshVertices
                var i = 0
                while i + 2 < t.count { if t[i] < p.count, t[i + 1] < p.count, t[i + 2] < p.count { v += p[t[i]].dot(p[t[i + 1]].cross(p[t[i + 2]])) / 6 }; i += 3 }
                return abs(v)
            }
        }
        if let el = doc.element(id) {
            switch el.geometry {
            case .wall(let w): return w.length * w.thickness * w.height
            case .slab(let s): return (abs(GeometryOps.signedArea(s.boundary)) - s.holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }) * s.thickness
            case .column(let c): return (c.round ? .pi * c.width * c.width / 4 : c.width * c.depth) * c.height
            case .beam(let b): return b.start.distance(to: b.end) * b.width * b.depth
            case .space(let s): return abs(GeometryOps.signedArea(s.boundary)) * s.height
            case .component(let c): return c.size.x * c.size.y * c.size.z
            default: return nil
            }
        }
        return nil
    }

    static func volumeText(_ v: Double, _ u: Units) -> String {
        let mm3 = v * pow(u.mm, 3)
        switch u { case .inches, .feet: return String(format: "%.3f ft³", mm3 / pow(304.8, 3)); default: return String(format: "%.3f m³", mm3 / 1e9) }
    }

    @MainActor static func distance(_ ed: Editor) async throws {
        let p1 = try await ed.requirePoint("Specify first point")
        let p2 = try await ed.requirePoint("Specify second point", base: p1) { c in [.line(LineGeom(p1, c))] }
        let d = p2 - p1
        ed.print("Distance = \(fmt(d.length, 4)), Angle in XY Plane = \(fmt(deg(normAngle(d.angle)), 4))°, Delta X = \(fmt(d.x, 4)), Delta Y = \(fmt(d.y, 4))")
        if ed.doc.units == .millimeters || ed.doc.units == .centimeters { ed.print("  (\(CommandHelpers.lengthText(d.length, units: ed.doc.units)))") }
    }

    @MainActor static func area(_ ed: Editor) async throws {
        var total = 0.0
        var mode: String? = nil
        func report(_ a: Double, _ p: Double) {
            ed.print(CommandHelpers.areaMessage(area: a, perimeter: p, units: ed.doc.units) + "  [\(fmt(a, 2)) sq units]")
            if let m = mode {
                total += m == "Add" ? a : -a
                ed.print("Total area = \(CommandHelpers.areaText(total, units: ed.doc.units))")
            }
        }
        while true {
            let a = try await ed.getPoint(mode == nil ? "Specify first corner point" : "Specify first corner point (\(mode!.uppercased()) mode)", keywords: ["Object", "Add", "Subtract"])
            switch a {
            case .point(let p):
                var pts = [p]
                while true {
                    let cur = pts
                    guard let q = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.polyline(PolylineGeom(points: cur + [c], closed: true))] }).point else { break }
                    pts.append(q)
                }
                guard pts.count >= 3 else { ed.print("At least three points are required."); if mode == nil { return }; continue }
                report(abs(GeometryOps.signedArea(pts)), CommandHelpers.polylineLength(pts + [pts[0]]))
                if mode == nil { return }
            case .keyword("Object"):
                guard case .pick(let pk) = try await ed.pickObject("Select objects") else { continue }
                guard let (ar, per) = areaPerimeter(pk.id, doc: ed.doc) else { ed.print("Selected object does not have an area."); continue }
                report(ar, per)
                if mode == nil { return }
            case .keyword(let k): mode = k
            default:
                if mode != nil { ed.print("Total area = \(CommandHelpers.areaText(total, units: ed.doc.units))") }
                return
            }
        }
    }

    static var dist: CommandDef {
        CommandDef("DIST", aliases: ["DI"], category: "Inquiry", summary: "Measures the distance and angle between two points.", modifies: false) { ed in try await distance(ed) }
    }
    static var area: CommandDef {
        CommandDef("AREA", aliases: ["AA"], category: "Inquiry", summary: "Calculates area and perimeter of points or objects (with Add/Subtract).", modifies: false) { ed in try await area(ed) }
    }
    static var id: CommandDef {
        CommandDef("ID", category: "Inquiry", summary: "Displays the coordinates of a location.", modifies: false) { ed in
            let p = try await ed.requirePoint("Specify point")
            let z = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            ed.print("X = \(fmt(p.x, 4))     Y = \(fmt(p.y, 4))     Z = \(fmt(z, 4))")
        }
    }
    static var list: CommandDef {
        CommandDef("LIST", aliases: ["LI", "LS"], category: "Inquiry", summary: "Lists the properties of selected objects.", modifies: false) { ed in
            let ids = try await ed.getSelection()
            for id in ids.sorted() {
                if let e = ed.doc.entity(id) { ed.print("\(e.typeName.uppercased())   Layer: \"\(e.layer)\"   Handle: #\(id)") }
                else if let el = ed.doc.element(id) { ed.print("\(el.typeName.uppercased())   Layer: \"\(el.layer)\"   Level: \(ed.doc.level(el.level)?.name ?? "\(el.level)")   Handle: #\(id)") }
                for p in PropertyAccess.properties(of: id, in: ed.doc) where !["id", "type", "layer"].contains(p.name) { ed.print("    \(p.name) = \(p.value)") }
                if let (a, per) = areaPerimeter(id, doc: ed.doc) { ed.print("    " + CommandHelpers.areaMessage(area: a, perimeter: per, units: ed.doc.units)) }
                let props = ed.doc.entity(id)?.props ?? ed.doc.element(id)?.props ?? [:]
                for (k, v) in props.sorted(by: { $0.key < $1.key }) { ed.print("    prop.\(k) = \(v)") }
            }
        }
    }
    static var count: CommandDef {
        CommandDef("COUNT", category: "Inquiry", summary: "Counts objects by type, block and element type (selection or whole drawing).", modifies: false) { ed in
            let ids: [EntityID] = ed.selection.isEmpty ? ed.doc.allIDs : Array(ed.selection)
            var byType: [String: Int] = [:], byBlock: [String: Int] = [:], byElement: [String: Int] = [:]
            for id in ids {
                if let e = ed.doc.entity(id) {
                    byType[e.typeName, default: 0] += 1
                    if case .insert(let i) = e.geometry { byBlock[i.block, default: 0] += 1 }
                } else if let el = ed.doc.element(id) {
                    var k = el.typeName
                    if case .component = el.geometry { k = "component: " + el.name }
                    byElement[k, default: 0] += 1
                }
            }
            ed.print("\(ids.count) object(s)\(ed.selection.isEmpty ? " in the drawing" : " selected"):")
            for (k, v) in byType.sorted(by: { $0.key < $1.key }) { ed.print("  \(k): \(v)") }
            for (k, v) in byBlock.sorted(by: { $0.key < $1.key }) { ed.print("  block \(k): \(v)") }
            for (k, v) in byElement.sorted(by: { $0.key < $1.key }) { ed.print("  \(k): \(v)") }
        }
    }
    static var measureGeom: CommandDef {
        CommandDef("MEASUREGEOM", aliases: ["MEA"], category: "Inquiry", summary: "Measures distance, radius, angle, area or volume.", modifies: false) { ed in
            let k = try await ed.getKeyword("Enter an option", ["Distance", "Radius", "Angle", "ARea", "Volume"], defaultValue: "Distance") ?? "Distance"
            switch k {
            case "Radius":
                guard case .pick(let pk) = try await ed.pickObject("Select arc or circle"), let e = ed.doc.entity(pk.id) else { return }
                switch e.geometry {
                case .circle(let c): ed.print("Radius = \(fmt(c.radius, 4)), Diameter = \(fmt(c.radius * 2, 4))")
                case .arc(let a): ed.print("Radius = \(fmt(a.radius, 4)), Diameter = \(fmt(a.radius * 2, 4)), Arc length = \(fmt(a.radius * a.sweep, 4))")
                default: ed.print("Select an arc or circle.")
                }
            case "Angle":
                let v = try await ed.requirePoint("Specify angle vertex")
                let a = try await ed.requirePoint("Specify first angle endpoint", base: v)
                let b = try await ed.requirePoint("Specify second angle endpoint", base: v)
                var ang = abs(normAngle((b - v).angle - (a - v).angle))
                if ang > .pi { ang = 2 * .pi - ang }
                ed.print("Angle = \(fmt(deg(ang), 4))°")
            case "ARea": try await area(ed)
            case "Volume":
                let ids = try await ed.getSelection("Select solids or building elements")
                var total = 0.0, n = 0
                for id in ids { if let v = volume(id, doc: ed.doc) { total += v; n += 1 } }
                ed.selection = []
                ed.print(n == 0 ? "No objects with a volume selected." : "Volume = \(volumeText(total, ed.doc.units)) (\(n) object(s))")
            default: try await distance(ed)
            }
        }
    }
    static var massProp: CommandDef {
        CommandDef("MASSPROP", category: "Inquiry", summary: "Reports area, perimeter, centroid, bounding box and volume of objects.", modifies: false) { ed in
            let ids = try await ed.getSelection()
            for id in ids.sorted() {
                ed.print("#\(id):")
                if let (a, p) = areaPerimeter(id, doc: ed.doc) { ed.print("  Area: \(fmt(a, 4))  Perimeter: \(fmt(p, 4))  (\(CommandHelpers.areaText(a, units: ed.doc.units)))") }
                var bb = BBox2.empty
                var centroidPts: [Vec2] = []
                if let e = ed.doc.entity(id) {
                    bb = GeometryOps.bounds(e.geometry, doc: ed.doc)
                    if let l = CommandHelpers.closedLoop(e.geometry) { centroidPts = CommandHelpers.loopPoints(l) }
                } else if let el = ed.doc.element(id) { centroidPts = CommandHelpers.footprint(el, doc: ed.doc); bb = BBox2(points: centroidPts) }
                if !bb.isEmpty { ed.print("  Bounding box: X: \(fmt(bb.min.x, 4)) -- \(fmt(bb.max.x, 4))  Y: \(fmt(bb.min.y, 4)) -- \(fmt(bb.max.y, 4))") }
                if centroidPts.count >= 3 { ed.print("  Centroid: \(GeometryOps.centroid(centroidPts))") }
                if let v = volume(id, doc: ed.doc) { ed.print("  Volume: \(fmt(v, 2)) (\(volumeText(v, ed.doc.units)))") }
            }
            ed.selection = []
        }
    }
    static var status: CommandDef {
        CommandDef("STATUS", category: "Inquiry", summary: "Displays drawing statistics, modes and extents.", modifies: false) { ed in
            let d = ed.doc
            let ext = GeometryOps.bounds(of: d)
            ed.print("\(d.entities.count) drawing objects, \(d.elements.count) building elements, \(d.blocks.count) block definitions, \(d.layers.count) layers, \(d.levels.count) levels")
            ed.print("Units: \(d.units.rawValue)")
            if ext.isEmpty { ed.print("Drawing extents: empty") }
            else { ed.print("Drawing uses  X: \(fmt(ext.min.x, 2)) Y: \(fmt(ext.min.y, 2))  to  X: \(fmt(ext.max.x, 2)) Y: \(fmt(ext.max.y, 2))") }
            ed.print("Current layer: \(d.currentLayer)   Current level: \(d.level(d.currentLevel)?.name ?? "?")   Dimension style: \(d.currentDimStyle)")
            ed.print("Current color: \(d.variable("CECOLOR") ?? "ByLayer")   Linetype: \(d.variable("CELTYPE") ?? "ByLayer")   Lineweight: \(d.variable("CELWEIGHT") ?? "ByLayer")")
            let s = ed.settings
            ed.print("Snap \(s.gridSnap ? "on" : "off"), Grid \(s.showGrid ? "on" : "off") (\(fmt(s.gridSpacing))), Ortho \(s.ortho ? "on" : "off"), Polar \(s.polarTracking ? "on" : "off") (\(fmt(s.polarIncrement))°), Osnap \(s.objectSnap ? "on" : "off"): \(s.snapModes.map(\.rawValue).sorted().joined(separator: ", "))")
            ed.print("Text height: \(fmt(s.textHeight))   Wall: \(fmt(s.wallThickness)) × \(fmt(s.wallHeight))   Fillet radius: \(fmt(s.filletRadius))   Offset: \(fmt(s.offsetDistance))")
            ed.print("Undo steps: \(ed.history.undoStack.count)   Modified: \(ed.isDirty ? "yes" : "no")")
        }
    }
    static var cal: CommandDef {
        CommandDef("CAL", aliases: ["QUICKCALC", "QC"], category: "Inquiry", summary: "Evaluates an arithmetic expression (+ - * / ^, sqrt, sin, cos, pi…).", modifies: false) { ed in
            guard let s = try await ed.getString("Enter expression"), !s.isEmpty else { return }
            if let v = CommandHelpers.evaluate(s) ?? InputParser.parseNumber(s) { ed.print("\(s) = \(fmt(v, 8))") }
            else { ed.print("Invalid expression: \(s)") }
        }
    }
}
