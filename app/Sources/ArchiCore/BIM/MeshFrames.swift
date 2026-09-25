// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

extension MeshAcc {
    /// Appends `other` mapped through the affine frame p ↦ origin + X·p.x + Y·p.y + Z·p.z (normals follow;
    /// winding is flipped for left-handed frames so faces stay outward).
    mutating func appendMapped(_ other: MeshAcc, origin: Vec3, X: Vec3, Y: Vec3, Z: Vec3) {
        guard !other.mesh.isEmpty else { edges += other.edges.map { $0.map { origin + X * $0.x + Y * $0.y + Z * $0.z } }; return }
        func P(_ p: Vec3) -> Vec3 { origin + X * p.x + Y * p.y + Z * p.z }
        // Normal transform: inverse transpose of [X Y Z]; for the orthogonal frames used here that is the frame itself.
        let det = X.dot(Y.cross(Z))
        var m = other.mesh
        m.positions = m.positions.map(P)
        m.normals = m.normals.map { (X * $0.x + Y * $0.y + Z * $0.z).normalized }
        if det < 0 {
            var i = 0
            while i + 2 < m.indices.count { m.indices.swapAt(i + 1, i + 2); i += 3 }
        }
        mesh.append(m)
        edges += other.edges.map { $0.map(P) }
    }

    /// Straight prism of a closed 2D section (with optional holes) extruded `length` along `axis` from `origin`;
    /// section x runs along `xAxis`, y along axis × xAxis.
    mutating func extrudeSection(_ loop: [Vec2], holes: [[Vec2]] = [], origin: Vec3, axis: Vec3, xAxis: Vec3, length: Double, smooth: Bool = false) {
        guard length > 1e-9, loop.count >= 3 else { return }
        let Z = axis.normalized
        var X = (xAxis - Z * xAxis.dot(Z))
        if X.length < 1e-9 { X = abs(Z.z) < 0.9 ? Vec3.unitZ.cross(Z) : Vec3(1, 0, 0).cross(Z) }
        X = X.normalized
        let Y = Z.cross(X).normalized
        var local = MeshAcc()
        local.prism(loop, holes: holes, z0: 0, z1: length, smooth: smooth)
        appendMapped(local, origin: origin, X: X, Y: Y, Z: Z)
    }

    /// Member (beam, brace, truss chord) between two 3D points with a section: section x across (horizontal,
    /// to the left of travel), y "up" (perpendicular to the member in the vertical plane through it).
    mutating func member(_ loop: [Vec2], holes: [[Vec2]] = [], from a: Vec3, to b: Vec3, smooth: Bool = false) {
        let v = b - a, L = v.length
        guard L > 1e-9 else { return }
        let Z = v / L
        var side = Vec3.unitZ.cross(Z)
        if side.length < 1e-9 { side = Vec3(1, 0, 0) }  // vertical member
        side = side.normalized
        // Section x to the left of travel: X = −side so that X × Y = Z with Y ≈ up.
        let X = side * -1
        let Y = Z.cross(X).normalized
        var local = MeshAcc()
        local.prism(loop, holes: holes, z0: 0, z1: L, smooth: smooth)
        // local frame: section x → X, section y → Y, extrusion → Z.
        appendMapped(local, origin: a, X: X, Y: Y, Z: Z)
    }
}
