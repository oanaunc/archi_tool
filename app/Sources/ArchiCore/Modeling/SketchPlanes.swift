// Oanarina Archi Tool — GPL-3.0-or-later
// Sketch environment (M3D-076) with sketches on 3D work planes (M3D-084): a sketch is a named work plane (horizontal
// at an elevation, on a planar face of a solid, or vertical through a line) plus the 2D objects drawn in its own
// coordinates (props "sketch"), constrained and solved by the geometric constraint solver like any drawing. The sketch
// reports its remaining degrees of freedom, and an associative pad extrudes its closed profile along the plane
// normal — rebuilt whenever the sketch objects, their constraints' results or the plane change.
import Foundation

public struct SketchPlane: Codable, Hashable {
    public var name: String
    public var origin: Vec3
    public var xAxis: Vec3
    public var normal: Vec3
    public init(name: String, origin: Vec3, xAxis: Vec3, normal: Vec3) {
        self.name = name; self.origin = origin
        let n = normal.normalized
        self.normal = n
        // Keep the x axis in the plane.
        let x = xAxis - n * xAxis.dot(n)
        self.xAxis = x.length > 1e-9 ? x.normalized : Mesh.basis(n).0
    }
    /// Face-hosted planes (M3D-084): the solid whose planar face carries the sketch, the origin's offset from that
    /// face's centroid, and the host geometry signature the plane was last placed on. The plane follows the face
    /// when the solid is moved, pushed or pulled (nil for free planes; absent in older files).
    public var host: EntityID?
    public var hostOffset: Vec3?
    public var hostSig: String?
    public var yAxis: Vec3 { normal.cross(xAxis).normalized }
    public func world(_ p: Vec2, _ h: Double = 0) -> Vec3 { origin + xAxis * p.x + yAxis * p.y + normal * h }
    public func local(_ p: Vec3) -> Vec2 { let d = p - origin; return Vec2(d.dot(xAxis), d.dot(yAxis)) }
    /// A plane whose sketch coordinates are plan coordinates (horizontal, at an elevation).
    public var isPlan: Bool { normal.z > 1 - 1e-9 && abs(xAxis.x - 1) < 1e-9 && abs(origin.x) < 1e-9 && abs(origin.y) < 1e-9 }
}

public enum Sketches {
    public static let variable = "SKETCHPLANES", key = "sketch"

    public static func all(_ doc: ArchiDocument) -> [SketchPlane] {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([SketchPlane].self, from: d) else { return [] }
        return v
    }
    public static func save(_ v: [SketchPlane], doc: inout ArchiDocument) {
        if v.isEmpty { doc.variables[variable] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if let d = try? enc.encode(v), let s = String(data: d, encoding: .utf8) { doc.setVariable(variable, s) }
    }
    public static func plane(_ name: String, doc: ArchiDocument) -> SketchPlane? { all(doc).first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }

    public static func define(_ p: SketchPlane, doc: inout ArchiDocument) {
        var v = all(doc).filter { $0.name.caseInsensitiveCompare(p.name) != .orderedSame }
        v.append(p)
        save(v, doc: &doc)
        let layer = "SKETCH-" + p.name
        if doc.layer(named: layer) == nil { doc.layers.append(Layer(name: layer, color: RGBA(0.3, 0.8, 0.95), lineweight: 0.18, description: "Sketch \(p.name)")) }
    }

    public static func entities(_ name: String, doc: ArchiDocument) -> [Entity] { doc.entities.filter { $0.props[key]?.caseInsensitiveCompare(name) == .orderedSame } }

    /// Remaining degrees of freedom of a sketch (constraints among its objects; unconstrained objects count fully).
    public static func freedom(_ name: String, doc: ArchiDocument) -> Int {
        let ents = entities(name, doc: doc)
        let ids = Set(ents.map(\.id))
        var d = doc
        d.entities = ents
        var set = ConstraintSet.load(doc)
        set.constraints = set.constraints.filter { c in c.refs.allSatisfy { ids.contains($0.entity) } }
        set.save(&d)
        let constrained = Set(set.constraints.filter { !$0.reference }.flatMap { $0.refs.map(\.entity) })
        let free = ents.filter { !constrained.contains($0.id) }.compactMap { Constraints.params($0.geometry)?.count }.reduce(0, +)
        return Constraints.freedom(doc: d).dof + free
    }

    /// Closed profile loops of a sketch (closed polylines, circles, ellipses, and lines/arcs chained end to end).
    public static func loops(_ name: String, doc: ArchiDocument) -> [[Vec2]] {
        var out: [[Vec2]] = []
        var open: [Geometry] = []
        for e in entities(name, doc: doc) {
            if let l = CommandHelpers.closedLoop(e.geometry) { out.append(CommandHelpers.loopPoints(l)) }
            else { switch e.geometry { case .line, .arc, .polyline: open.append(e.geometry); default: break } }
        }
        if !open.isEmpty { for g in Modify.join(open) { if let l = CommandHelpers.closedLoop(g) { out.append(CommandHelpers.loopPoints(l)) } } }
        return out.map { RG.dedupe($0, closed: true) }.filter { $0.count >= 3 && abs(GeometryOps.signedArea($0)) > 1e-9 }
    }

    /// Extrusion of the sketch profile (largest loop; loops inside it are holes) along the plane normal.
    public static func pad(_ name: String, distance d: Double, doc: ArchiDocument) -> SolidGeom? {
        guard let p = plane(name, doc: doc), abs(d) > 1e-9 else { return nil }
        let ls = loops(name, doc: doc).sorted { abs(GeometryOps.signedArea($0)) > abs(GeometryOps.signedArea($1)) }
        guard let outer = ls.first else { return nil }
        let holes = ls.dropFirst().filter { GeometryOps.pointInPolygon(GeometricCentroid.inside($0), outer) }
        var acc = MeshAcc()
        acc.prism(outer, holes: Array(holes), z0: min(0, d), z1: max(0, d))
        let tris = MeshTools.triangles(acc.mesh).map { (p.world($0.0.xy, $0.0.z), p.world($0.1.xy, $0.1.z), p.world($0.2.xy, $0.2.z)) }
        return SolidPrimitives.solid(tris)
    }

    static func signature(_ name: String, doc: ArchiDocument) -> String {
        let p = plane(name, doc: doc).map { "\($0.origin)|\($0.xAxis)|\($0.normal)" } ?? ""
        return p + "|" + entities(name, doc: doc).map { "\($0.id):\($0.geometry)" }.joined(separator: ";")
    }

    /// Adds an associative pad of a sketch. Returns the solid's id.
    @discardableResult
    public static func addPad(_ name: String, distance d: Double, doc: inout ArchiDocument) -> EntityID? {
        guard let s = pad(name, distance: d, doc: doc) else { return nil }
        var e = Entity(layer: doc.currentLayer, geometry: .solid(s))
        e.props["sketchPad"] = name; e.props["padDistance"] = fmt(d, 9); e.props["sketchSig"] = signature(name, doc: doc)
        return doc.add(e)
    }

    public static func hasContent(_ doc: ArchiDocument) -> Bool {
        doc.entities.contains { $0.props["sketchPad"] != nil } || (doc.variable(variable)?.contains("\"host\"") ?? false)
    }

    /// Planar face regions of a solid: (triangles, unit normal, area-weighted centroid, area).
    static func faces(_ m: SubObjects.IM) -> [(tris: Set<Int>, normal: Vec3, centroid: Vec3, area: Double)] {
        var seen = Set<Int>(), out: [(tris: Set<Int>, normal: Vec3, centroid: Vec3, area: Double)] = []
        for f in 0..<(m.triangles.count / 3) where !seen.contains(f) {
            let r = SubObjects.faceRegion(m, seed: f)
            seen.formUnion(r)
            var c = Vec3.zero, a = 0.0
            for t in r {
                let (p, q, w) = SubObjects.corners(m, t)
                let ar = (q - p).cross(w - p).length / 2
                c = c + (p + q + w) * (ar / 3); a += ar
            }
            guard a > 1e-12 else { continue }
            out.append((r, SubObjects.normal(m, f), c / a, a))
        }
        return out
    }

    /// Hosts a plane on the face of solid `host` nearest to `point`: the plane records the face centroid offset.
    public static func hosted(_ p: SketchPlane, on host: EntityID, doc: ArchiDocument) -> SketchPlane {
        guard let s = ModelingCommands.solidOf(doc, host) else { return p }
        let w = SolidOps.welded(s)
        let fs = faces(w).filter { $0.normal.dot(p.normal) > 1 - 1e-6 && abs(($0.centroid - p.origin).dot(p.normal)) < 1e-6 * max(1, $0.centroid.length) + 1e-6 }
        guard let f = fs.min(by: { $0.centroid.distance(to: p.origin) < $1.centroid.distance(to: p.origin) }) else { return p }
        var q = p
        q.host = host; q.hostOffset = p.origin - f.centroid; q.hostSig = "\(s)"
        return q
    }

    /// Moves face-hosted planes with their faces after the host solid changed (the face with the closest normal and
    /// centroid to the old one). Planes whose host was deleted become free planes.
    @discardableResult
    public static func followHosts(_ doc: inout ArchiDocument) -> Bool {
        var planes = all(doc)
        var changed = false
        for i in planes.indices {
            guard let hid = planes[i].host else { continue }
            guard let s = ModelingCommands.solidOf(doc, hid) else { planes[i].host = nil; planes[i].hostOffset = nil; planes[i].hostSig = nil; changed = true; continue }
            let sig = "\(s)"
            if sig == planes[i].hostSig { continue }
            let p = planes[i]
            let off = p.hostOffset ?? .zero
            let oldC = p.origin - off
            let fs = faces(SolidOps.welded(s))
            guard !fs.isEmpty else { continue }
            let best = fs.max { a, b in
                let da = a.normal.dot(p.normal), db = b.normal.dot(p.normal)
                if abs(da - db) > 1e-6 { return da < db }
                return a.centroid.distance(to: oldC) > b.centroid.distance(to: oldC)
            }!
            var np = SketchPlane(name: p.name, origin: best.centroid + off, xAxis: p.xAxis, normal: best.normal)
            // Keep the origin on the face plane (the offset lies in the old plane).
            np.origin = np.origin - np.normal * (np.origin - best.centroid).dot(np.normal)
            np.host = hid; np.hostOffset = np.origin - best.centroid; np.hostSig = sig
            planes[i] = np
            changed = true
        }
        if changed { save(planes, doc: &doc) }
        return changed
    }

    /// World-space polylines of a sketch object drawn on its (non-plan) work plane, for the 3D views.
    public static func edges3D(_ e: Entity, doc: ArchiDocument) -> [[Vec3]]? {
        guard let n = e.props[key], let p = plane(n, doc: doc), !p.isPlan else { return nil }
        return GeometryOps.tessellate(e.geometry, doc: doc).filter { $0.count >= 2 }.map { $0.map { p.world($0) } }
    }

    /// Rebuilds pads whose sketch changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = followHosts(&doc)
        for i in doc.entities.indices {
            guard let n = doc.entities[i].props["sketchPad"], let d = doc.entities[i].props["padDistance"].flatMap(Double.init) else { continue }
            let sig = signature(n, doc: doc)
            if sig == doc.entities[i].props["sketchSig"] { continue }
            if let s = pad(n, distance: d, doc: doc) { doc.entities[i].geometry = .solid(s) }
            doc.entities[i].props["sketchSig"] = sig
            changed = true
        }
        return changed
    }
}

/// A point strictly inside a loop (centroid, or a nudge towards it for non-convex loops).
enum GeometricCentroid {
    static func inside(_ l: [Vec2]) -> Vec2 {
        let c = GeometryOps.centroid(l)
        if GeometryOps.pointInPolygon(c, l) { return c }
        for i in 0..<l.count {
            let m = (l[i] + l[(i + 1) % l.count]) / 2
            for t in [0.01, 0.05, 0.2] { let q = m + (c - m) * t; if GeometryOps.pointInPolygon(q, l) { return q } }
        }
        return l[0]
    }
}

enum SketchPlaneCommands {
    static var all: [CommandDef] { [sketchPlane, sketchPad] }

    static var sketchPlane: CommandDef {
        CommandDef("SKETCHPLANE", aliases: ["SKETCHER", "NEWSKETCH", "SKETCHON", "SKETCH3D"], category: "Parametric", summary: "Sketch environment: New sketch on a work plane (XY at an elevation, a solid Face, or vertical through a Line), Add objects drawn in sketch coordinates, Status (degrees of freedom — constrain with the geometric/dimensional constraints), List, Delete.") { ed in
            let k = try await ed.getKeyword("Sketch [New/Add/Status/List/Delete]", ["New", "Add", "Status", "List", "Delete"], defaultValue: "New") ?? "New"
            if k == "List" {
                let ps = Sketches.all(ed.doc)
                if ps.isEmpty { ed.print("No sketches.") }
                for p in ps { ed.print("  \(p.name): origin \(p.origin), normal \(fmt(p.normal.x, 3)),\(fmt(p.normal.y, 3)),\(fmt(p.normal.z, 3)); \(Sketches.entities(p.name, doc: ed.doc).count) object(s), \(Sketches.freedom(p.name, doc: ed.doc)) DOF") }
                return
            }
            guard let name = try await ed.getWord("Sketch name", defaultValue: Sketches.all(ed.doc).last?.name ?? "Sketch1") else { return }
            switch k {
            case "New":
                let m = try await ed.getKeyword("Work plane [XY/Face/Line]", ["XY", "Face", "Line"], defaultValue: "XY") ?? "XY"
                var p: SketchPlane
                switch m {
                case "Face":
                    guard case .pick(let pk) = try await ed.pickObject("Select a solid", filter: { ModelingCommands.solidOf(ed.doc, $0) != nil }), let s = ModelingCommands.solidOf(ed.doc, pk.id) else { return }
                    let q = try await ed.requirePoint3("Specify a point on the face (sketch origin)")
                    let w = SolidOps.welded(s)
                    guard let f = SubObjects.nearestFace((w.vertices, w.triangles), to: q) else { return }
                    let n = SubObjects.normal((w.vertices, w.triangles), f)
                    let v0 = w.vertices[w.triangles[3 * f]]
                    let o = q - n * (q - v0).dot(n)
                    let x = abs(n.z) > 0.99 ? Vec3(1, 0, 0) : Vec3(0, 0, 1).cross(n)
                    // Hosted on the face: the sketch follows it when the solid is edited (M3D-084).
                    p = Sketches.hosted(SketchPlane(name: name, origin: o, xAxis: x, normal: n), on: pk.id, doc: ed.doc)
                case "Line":
                    guard case .pick(let pk) = try await ed.pickObject("Select a line (the sketch x axis)", filter: { id in if case .line? = ed.doc.entity(id)?.geometry { return true }; return false }),
                          case .line(let l)? = ed.doc.entity(pk.id)?.geometry, l.a.distance(to: l.b) > 1e-9 else { return }
                    let z = ed.doc.entity(pk.id)?.props["elevation"].flatMap(Double.init) ?? 0
                    let d = (l.b - l.a).normalized
                    p = SketchPlane(name: name, origin: Vec3(l.a.x, l.a.y, z), xAxis: Vec3(d.x, d.y, 0), normal: Vec3(d.y, -d.x, 0))
                default:
                    let z = try await ed.getDistance("Elevation", defaultValue: 0).value ?? 0
                    p = SketchPlane(name: name, origin: Vec3(0, 0, z), xAxis: Vec3(1, 0, 0), normal: .unitZ)
                }
                Sketches.define(p, doc: &ed.doc)
                ed.doc.currentLayer = "SKETCH-" + name
                ed.print("Sketch \(name) created" + (p.isPlan ? " (plan coordinates)." : "; draw in sketch coordinates on layer SKETCH-\(name), then SKETCHPLANE Add."))
            case "Add":
                guard Sketches.plane(name, doc: ed.doc) != nil else { throw CommandError.invalid("No sketch \(name).") }
                ed.selection = []
                let ids = try await ed.getEntitySelection("Select objects for the sketch")
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[Sketches.key] = name; ed.doc.entities[i].layer = "SKETCH-" + name } }
                ed.print("\(ids.count) object(s) added to \(name); \(Sketches.freedom(name, doc: ed.doc)) degrees of freedom left.")
            case "Status":
                guard Sketches.plane(name, doc: ed.doc) != nil else { throw CommandError.invalid("No sketch \(name).") }
                let dof = Sketches.freedom(name, doc: ed.doc)
                let loops = Sketches.loops(name, doc: ed.doc).count
                ed.print("Sketch \(name): \(Sketches.entities(name, doc: ed.doc).count) object(s), \(loops) closed profile(s), " + (dof == 0 ? "fully constrained." : "\(dof) degree(s) of freedom."))
            default:
                Sketches.save(Sketches.all(ed.doc).filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }, doc: &ed.doc)
                for i in ed.doc.entities.indices where ed.doc.entities[i].props[Sketches.key]?.caseInsensitiveCompare(name) == .orderedSame { ed.doc.entities[i].props[Sketches.key] = nil }
                ed.print("Sketch \(name) deleted (its objects are kept).")
            }
        }
    }

    static var sketchPad: CommandDef {
        CommandDef("SKETCHPAD", aliases: ["PADSKETCH", "SKETCHEXTRUDE"], category: "3D", summary: "Pads a sketch: its closed profile (with holes) extruded along the work-plane normal; the solid follows every change of the sketch.") { ed in
            guard let name = try await ed.getWord("Sketch name", defaultValue: Sketches.all(ed.doc).last?.name), Sketches.plane(name, doc: ed.doc) != nil else { throw CommandError.invalid("No such sketch.") }
            let d = try await ed.getDistance("Pad length (negative = reverse)", defaultValue: 500).value ?? 500
            guard let id = Sketches.addPad(name, distance: d, doc: &ed.doc) else { throw CommandError.invalid("The sketch has no closed profile.") }
            ed.selection = [id]
            ed.print("Pad #\(id) of \(name).")
        }
    }
}
