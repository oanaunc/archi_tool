// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public let geomEpsilon: Double = 1e-9

public struct Vec2: Codable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }
    public func dot(_ b: Vec2) -> Double { x * b.x + y * b.y }
    public func cross(_ b: Vec2) -> Double { x * b.y - y * b.x }
    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }
    public var normalized: Vec2 { let l = length; return l < geomEpsilon ? .zero : self / l }
    public var perp: Vec2 { Vec2(-y, x) }
    public var angle: Double { atan2(y, x) }
    public func distance(to b: Vec2) -> Double { (self - b).length }
    public func rotated(by a: Double) -> Vec2 { let c = cos(a), s = sin(a); return Vec2(x * c - y * s, x * s + y * c) }
    public func rotated(by a: Double, around c: Vec2) -> Vec2 { (self - c).rotated(by: a) + c }
    public func lerp(_ b: Vec2, _ t: Double) -> Vec2 { self + (b - self) * t }
    public static func polar(_ r: Double, _ a: Double) -> Vec2 { Vec2(r * cos(a), r * sin(a)) }
    public func isClose(_ b: Vec2, tol: Double = 1e-7) -> Bool { abs(x - b.x) <= tol && abs(y - b.y) <= tol }
    public var description: String { "\(fmt(x)),\(fmt(y))" }
    public var vec3: Vec3 { Vec3(x, y, 0) }
}

public struct Vec3: Codable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(0, 0, 0)
    public static let unitZ = Vec3(0, 0, 1)
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    public static func / (a: Vec3, s: Double) -> Vec3 { Vec3(a.x / s, a.y / s, a.z / s) }
    public static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }
    public func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: Vec3) -> Vec3 { Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: Vec3 { let l = length; return l < geomEpsilon ? .zero : self / l }
    public var xy: Vec2 { Vec2(x, y) }
    public func distance(to b: Vec3) -> Double { (self - b).length }
    public var description: String { "\(fmt(x)),\(fmt(y)),\(fmt(z))" }
}

/// Formats a number compactly for command line echo and files.
public func fmt(_ v: Double, _ decimals: Int = 4) -> String {
    if v.isNaN { return "NaN" }
    let r = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
    if r == r.rounded() && abs(r) < 1e15 { return String(Int64(r)) }
    var s = String(format: "%.\(decimals)f", r)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
}

public func deg(_ radians: Double) -> Double { radians * 180 / .pi }
public func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// Normalizes an angle to [0, 2π).
public func normAngle(_ a: Double) -> Double {
    var r = a.truncatingRemainder(dividingBy: 2 * .pi)
    if r < 0 { r += 2 * .pi }
    return r
}

/// 2D affine transform: [a c tx; b d ty].
public struct Transform2D: Codable, Hashable {
    public var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static let identity = Transform2D()
    public static func translation(_ v: Vec2) -> Transform2D { Transform2D(tx: v.x, ty: v.y) }
    public static func rotation(_ ang: Double, around p: Vec2 = .zero) -> Transform2D {
        let cs = cos(ang), sn = sin(ang)
        return Transform2D.translation(p) * Transform2D(a: cs, b: sn, c: -sn, d: cs) * Transform2D.translation(-p)
    }
    public static func scale(_ sx: Double, _ sy: Double, around p: Vec2 = .zero) -> Transform2D {
        Transform2D.translation(p) * Transform2D(a: sx, d: sy) * Transform2D.translation(-p)
    }
    /// Mirror across the line through p1 and p2.
    public static func mirror(_ p1: Vec2, _ p2: Vec2) -> Transform2D {
        let ang = (p2 - p1).angle
        let cs = cos(2 * ang), sn = sin(2 * ang)
        return Transform2D.translation(p1) * Transform2D(a: cs, b: sn, c: sn, d: -cs) * Transform2D.translation(-p1)
    }
    public static func * (m: Transform2D, n: Transform2D) -> Transform2D {
        Transform2D(a: m.a * n.a + m.c * n.b, b: m.b * n.a + m.d * n.b,
                    c: m.a * n.c + m.c * n.d, d: m.b * n.c + m.d * n.d,
                    tx: m.a * n.tx + m.c * n.ty + m.tx, ty: m.b * n.tx + m.d * n.ty + m.ty)
    }
    public func apply(_ p: Vec2) -> Vec2 { Vec2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }
    public func applyVector(_ v: Vec2) -> Vec2 { Vec2(a * v.x + c * v.y, b * v.x + d * v.y) }
    public var determinant: Double { a * d - b * c }
    public var isMirroring: Bool { determinant < 0 }
    /// Uniform scale factor (geometric mean of axis scales).
    public var scaleFactor: Double { abs(determinant).squareRoot() }
    public var rotationAngle: Double { atan2(b, a) }
    public var inverted: Transform2D {
        let det = determinant
        guard abs(det) > geomEpsilon else { return .identity }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return Transform2D(a: ia, b: ib, c: ic, d: id, tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
    }
}

public struct BBox2: Codable, Hashable {
    public var min: Vec2
    public var max: Vec2
    public init(min: Vec2, max: Vec2) { self.min = min; self.max = max }
    public static let empty = BBox2(min: Vec2(.infinity, .infinity), max: Vec2(-.infinity, -.infinity))
    public var isEmpty: Bool { min.x > max.x || min.y > max.y }
    public init(points: [Vec2]) { self = .empty; for p in points { add(p) } }
    public mutating func add(_ p: Vec2) {
        min = Vec2(Swift.min(min.x, p.x), Swift.min(min.y, p.y))
        max = Vec2(Swift.max(max.x, p.x), Swift.max(max.y, p.y))
    }
    public mutating func add(_ b: BBox2) { if !b.isEmpty { add(b.min); add(b.max) } }
    public func union(_ b: BBox2) -> BBox2 { var r = self; r.add(b); return r }
    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
    public var center: Vec2 { (min + max) / 2 }
    public func contains(_ p: Vec2) -> Bool { p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y }
    public func contains(_ b: BBox2) -> Bool { contains(b.min) && contains(b.max) }
    public func intersects(_ b: BBox2) -> Bool { !(b.min.x > max.x || b.max.x < min.x || b.min.y > max.y || b.max.y < min.y) }
    public func expanded(by d: Double) -> BBox2 { BBox2(min: min - Vec2(d, d), max: max + Vec2(d, d)) }
}

public struct BBox3: Codable, Hashable {
    public var min: Vec3
    public var max: Vec3
    public static let empty = BBox3(min: Vec3(.infinity, .infinity, .infinity), max: Vec3(-.infinity, -.infinity, -.infinity))
    public init(min: Vec3, max: Vec3) { self.min = min; self.max = max }
    public var isEmpty: Bool { min.x > max.x }
    public mutating func add(_ p: Vec3) {
        min = Vec3(Swift.min(min.x, p.x), Swift.min(min.y, p.y), Swift.min(min.z, p.z))
        max = Vec3(Swift.max(max.x, p.x), Swift.max(max.y, p.y), Swift.max(max.z, p.z))
    }
    public var center: Vec3 { (min + max) / 2 }
    public var size: Vec3 { max - min }
}
