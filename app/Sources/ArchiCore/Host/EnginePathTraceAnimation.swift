// Oanarina Archi Tool — GPL-3.0-or-later
// Object animations (OBJANIM) at a render time for the portable path tracer, as ArchiApp/PathTracerUI.swift
// PTSceneBuilder.build does for ANIMATE Frame: whole objects rotate about a vertical axis and/or move, door leaves swing
// about their hinge (ObjectAnimation / ObjectAnimations of ArchiApp/SceneEffects.swift, ported without SceneKit).
import Foundation

struct EngineObjectAnimation: Equatable {
    var id = 0
    var target = 0
    var kind = "Rotate"
    var pivot = Vec3.zero
    /// Rotation angle (degrees) at the end of the motion.
    var angle = 90.0
    var offset = Vec3.zero
    var start = 0.0
    var duration = 2.0
    var pingPong = true

    /// OBJANIM of the drawing (JSON array of ObjectAnimation; vectors as {x, y, z} or [x, y, z]).
    static func load(_ doc: ArchiDocument) -> [EngineObjectAnimation] {
        guard let s = doc.variable("OBJANIM"), let arr = (try? EngineJSON.parse(s))?.arrayValue else { return [] }
        var out: [EngineObjectAnimation] = []
        for j in arr {
            guard let id = j["id"]?.intValue, let target = j["target"]?.intValue else { continue }
            var a = EngineObjectAnimation()
            a.id = id
            a.target = target
            a.kind = j["kind"]?.stringValue ?? "Rotate"
            a.pivot = vec(j["pivot"])
            a.angle = j["angle"]?.doubleValue ?? 90
            a.offset = vec(j["offset"])
            a.start = j["start"]?.doubleValue ?? 0
            a.duration = j["duration"]?.doubleValue ?? 2
            a.pingPong = j["pingPong"]?.boolValue ?? true
            out.append(a)
        }
        return out
    }

    static func vec(_ j: EngineJSON?) -> Vec3 {
        guard let j else { return .zero }
        if let a = j.arrayValue {
            let x = a.count > 0 ? a[0].doubleValue ?? 0 : 0
            let y = a.count > 1 ? a[1].doubleValue ?? 0 : 0
            let z = a.count > 2 ? a[2].doubleValue ?? 0 : 0
            return Vec3(x, y, z)
        }
        return Vec3(j["x"]?.doubleValue ?? 0, j["y"]?.doubleValue ?? 0, j["z"]?.doubleValue ?? 0)
    }

    /// Eased progress 0…1 at time t (smoothstep; back to 0 in the second half of a ping-pong).
    func progress(at t: Double) -> Double {
        let d = max(duration, 1e-6)
        var x = (t - start) / d
        if x <= 0 { return 0 }
        if pingPong {
            if x >= 2 { x = 0 } else if x > 1 { x = 2 - x }
        } else {
            x = min(x, 1)
        }
        return x * x * (3 - 2 * x)
    }

    /// Rotation (radians about +Z through the pivot) at time t.
    func rotation(at t: Double) -> Double { angle * .pi / 180 * progress(at: t) }

    /// Moves a model point to where it is at time t.
    func apply(_ p: Vec3, at t: Double) -> Vec3 {
        let f = progress(at: t)
        let r = angle * .pi / 180 * f
        let c = cos(r), s = sin(r)
        let dx = p.x - pivot.x, dy = p.y - pivot.y
        let x = pivot.x + dx * c - dy * s + offset.x * f
        let y = pivot.y + dx * s + dy * c + offset.y * f
        return Vec3(x, y, p.z + offset.z * f)
    }

    /// Normal rotated with the object at time t.
    func applyNormal(_ n: Vec3, at t: Double) -> Vec3 {
        let r = rotation(at: t)
        let c = cos(r), s = sin(r)
        return Vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z)
    }

    /// Splits a door's mesh into the frame and one mesh per leaf (ObjectAnimations.splitDoor): triangles inside the
    /// leaf span whose vertices stay clear of the wall faces.
    static func splitDoor(_ mesh: Mesh, leaves: [EngineDoorLeaves.Leaf], tolerance e: Double = 0.5) -> (rest: Mesh, leaves: [Mesh]) {
        var rest = Mesh()
        var out = [Mesh](repeating: Mesh(), count: leaves.count)
        let n = mesh.positions.count
        let hasN = mesh.normals.count == n, hasUV = mesh.uvs.count == n
        func append(_ m: inout Mesh, _ ids: [Int]) {
            let base = UInt32(m.positions.count)
            for i in ids {
                m.positions.append(mesh.positions[i])
                if hasN { m.normals.append(mesh.normals[i]) }
                if hasUV { m.uvs.append(mesh.uvs[i]) }
            }
            m.indices += [base, base + 1, base + 2]
        }
        func inside(_ j: Int, _ l: EngineDoorLeaves.Leaf) -> Bool {
            let p = mesh.positions[j].xy - l.cs
            let s = p.dot(l.dir), t = p.dot(l.normal)
            return s >= l.s0 - e && s <= l.s1 + e && abs(t) < l.wallHalf - e
        }
        var i = 0
        while i + 2 < mesh.indices.count {
            let ids = [Int(mesh.indices[i]), Int(mesh.indices[i + 1]), Int(mesh.indices[i + 2])]
            i += 3
            guard ids.allSatisfy({ $0 < n }) else { continue }
            var placed = false
            for (k, l) in leaves.enumerated() where ids.allSatisfy({ inside($0, l) }) {
                append(&out[k], ids)
                placed = true
                break
            }
            if !placed { append(&rest, ids) }
        }
        return (rest, out)
    }

    /// The meshes of one mesh group at time t: moved as a whole, or a door split into its frame and swinging leaves.
    /// Returns nil when no animation targets the group.
    static func meshes(_ mesh: Mesh, group g: MeshGroup, anims: [EngineObjectAnimation], doc: ArchiDocument, time t: Double) -> [Mesh]? {
        guard let id = g.id else { return nil }
        let mine = anims.filter { $0.target == id }
        if mine.isEmpty { return nil }
        var m = mesh
        if let a = mine.first(where: { $0.kind != "Door" }) {
            m.positions = m.positions.map { a.apply($0, at: t) }
            if m.normals.count == m.positions.count { m.normals = m.normals.map { a.applyNormal($0, at: t) } }
        }
        let doors = mine.filter { $0.kind == "Door" }
        guard !doors.isEmpty, let el = doc.element(id), g.material == (el.material ?? "Wood") else { return [m] }
        let split = splitDoor(m, leaves: EngineDoorLeaves.leaves(el, doc: doc))
        var out = [split.rest]
        for (k, leaf) in split.leaves.enumerated() where k < doors.count {
            var lm = leaf
            let a = doors[k]
            lm.positions = lm.positions.map { a.apply($0, at: t) }
            lm.normals = lm.normals.map { a.applyNormal($0, at: t) }
            out.append(lm)
        }
        return out
    }
}
