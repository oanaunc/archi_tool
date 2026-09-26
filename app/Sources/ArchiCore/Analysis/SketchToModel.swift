// Oanarina Archi Tool — GPL-3.0-or-later
// Sketch / photo to model (SCR-031): turns a scanned or photographed plan (PNG, BMP, PGM/PPM) into walls.
// Steps: luminance → Otsu threshold (dark ink = wall) → horizontal and vertical bands of dark runs whose length
// exceeds the minimum wall length and whose thickness lies between the minimum and maximum wall thickness → wall
// centre lines → ends snapped onto crossing or nearby perpendicular walls → collinear pieces merged. Coordinates are
// scaled by the given drawing units per pixel with the image's lower-left corner at the insertion point.
import Foundation

public enum SketchToModel {
    public struct Options {
        /// Drawing units per pixel.
        public var scale = 10.0
        public var origin = Vec2.zero
        /// Wall thickness range and minimum wall length, in pixels.
        public var minThickness = 3, maxThickness = 40, minLength = 20
        /// 0 = automatic (Otsu).
        public var threshold = 0
        /// Fixed wall thickness in drawing units (0 = measured from the image).
        public var wallThickness = 0.0
        public var wallHeight = 3000.0
        public init() {}
    }

    public struct TracedWall: Hashable {
        public var start: Vec2, end: Vec2, thickness: Double
        public var length: Double { start.distance(to: end) }
    }

    /// Otsu threshold of a luminance histogram.
    public static func otsu(_ g: [UInt8]) -> Int {
        var h = [Double](repeating: 0, count: 256)
        for v in g { h[Int(v)] += 1 }
        let total = Double(g.count)
        let sum = (0..<256).reduce(0.0) { $0 + Double($1) * h[$1] }
        var sumB = 0.0, wB = 0.0, best = 0.0, t = 127
        for i in 0..<256 {
            wB += h[i]; if wB == 0 { continue }
            let wF = total - wB; if wF == 0 { break }
            sumB += Double(i) * h[i]
            let mB = sumB / wB, mF = (sum - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; t = i }
        }
        return t
    }

    struct Run { var a: Int; var b: Int }   // inclusive pixel range

    /// Bands of long dark runs along rows (horizontal walls) in pixel space: (row0, row1, x0, x1).
    static func bands(width: Int, height: Int, dark: (Int, Int) -> Bool, o: Options) -> [(Int, Int, Int, Int)] {
        var open: [(r0: Int, r1: Int, a: Int, b: Int, lastA: Int, lastB: Int)] = []
        var out: [(Int, Int, Int, Int)] = []
        func close(_ x: (r0: Int, r1: Int, a: Int, b: Int, lastA: Int, lastB: Int)) {
            let t = x.r1 - x.r0 + 1
            if t >= o.minThickness, t <= o.maxThickness, x.b - x.a + 1 >= o.minLength { out.append((x.r0, x.r1, x.a, x.b)) }
        }
        for y in 0..<height {
            var runs: [Run] = []
            var x = 0
            while x < width {
                if dark(x, y) { let s = x; while x < width && dark(x, y) { x += 1 }; if x - s >= o.minLength { runs.append(Run(a: s, b: x - 1)) } } else { x += 1 }
            }
            var next: [(r0: Int, r1: Int, a: Int, b: Int, lastA: Int, lastB: Int)] = []
            var used = Set<Int>()
            for band in open {
                // Continue with a run overlapping ≥ 60 % of the band's last run.
                if let k = runs.indices.first(where: { !used.contains($0) && min(runs[$0].b, band.lastB) - max(runs[$0].a, band.lastA) + 1 >= Int(0.6 * Double(min(runs[$0].b - runs[$0].a, band.lastB - band.lastA) + 1)) }) {
                    used.insert(k)
                    let r = runs[k]
                    next.append((band.r0, y, max(band.a, r.a), min(band.b, r.b), r.a, r.b))
                } else { close(band) }
            }
            for (k, r) in runs.enumerated() where !used.contains(k) { next.append((y, y, r.a, r.b, r.a, r.b)) }
            open = next
        }
        open.forEach(close)
        return out
    }

    /// Traces walls in an image.
    public static func trace(_ img: RasterImage, options o: Options = Options()) -> [TracedWall] {
        let t = o.threshold > 0 ? o.threshold : otsu(img.gray)
        let w = img.width, h = img.height
        let hb = bands(width: w, height: h, dark: { x, y in Int(img.gray[y * w + x]) <= t }, o: o)
        let vb = bands(width: h, height: w, dark: { y, x in Int(img.gray[y * w + x]) <= t }, o: o)   // transposed: rows = columns
        func P(_ x: Double, _ y: Double) -> Vec2 { o.origin + Vec2(x * o.scale, (Double(h) - y) * o.scale) }
        var walls: [TracedWall] = []
        for (r0, r1, a, b) in hb {
            let yc = Double(r0 + r1 + 1) / 2
            let th = o.wallThickness > 0 ? o.wallThickness : Double(r1 - r0 + 1) * o.scale
            walls.append(TracedWall(start: P(Double(a), yc), end: P(Double(b + 1), yc), thickness: th))
        }
        for (c0, c1, a, b) in vb {
            let xc = Double(c0 + c1 + 1) / 2
            let th = o.wallThickness > 0 ? o.wallThickness : Double(c1 - c0 + 1) * o.scale
            walls.append(TracedWall(start: P(xc, Double(b + 1)), end: P(xc, Double(a)), thickness: th))
        }
        return clean(walls, tolerance: Double(o.maxThickness) * o.scale)
    }

    /// Merges collinear overlapping walls and snaps wall ends onto the centre line of a perpendicular wall within
    /// `tolerance` (so corners and T-junctions meet at centre lines).
    public static func clean(_ input: [TracedWall], tolerance: Double) -> [TracedWall] {
        var walls = input.filter { $0.length > 1e-9 }
        // Merge collinear pieces.
        var merged = true
        while merged {
            merged = false
            outer: for i in walls.indices {
                for j in walls.indices where j > i {
                    let a = walls[i], b = walls[j]
                    let da = (a.end - a.start).normalized, db = (b.end - b.start).normalized
                    guard abs(da.cross(db)) < 1e-6, abs((b.start - a.start).cross(da)) < max(a.thickness, b.thickness) / 2 else { continue }
                    let ta = [0.0, (a.end - a.start).dot(da)], tb = [(b.start - a.start).dot(da), (b.end - a.start).dot(da)]
                    let lo = min(ta.min()!, tb.min()!), hi = max(ta.max()!, tb.max()!)
                    guard min(ta.max()!, tb.max()!) >= max(ta.min()!, tb.min()!) - tolerance else { continue }
                    walls[i] = TracedWall(start: a.start + da * lo, end: a.start + da * hi, thickness: max(a.thickness, b.thickness))
                    walls.remove(at: j)
                    merged = true
                    break outer
                }
            }
        }
        // Snap ends to perpendicular centre lines.
        for i in walls.indices {
            for end in [false, true] {
                let p = end ? walls[i].end : walls[i].start
                let d = (walls[i].end - walls[i].start).normalized
                var best: (Vec2, Double)?
                for j in walls.indices where j != i {
                    let q = walls[j], e = q.end - q.start
                    guard abs(d.cross(e.normalized)) > 0.99 else { continue }
                    // Intersection of the wall's line with the other centre line.
                    let den = d.cross(e); if abs(den) < 1e-12 { continue }
                    let s = (q.start - p).cross(e) / den, u = (q.start - p).cross(d) / den
                    guard abs(s) <= tolerance, u >= -tolerance / max(e.length, 1e-9), u <= 1 + tolerance / max(e.length, 1e-9) else { continue }
                    let x = p + d * s
                    if best == nil || abs(s) < best!.1 { best = (x, abs(s)) }
                }
                if let b = best { if end { walls[i].end = b.0 } else { walls[i].start = b.0 } }
            }
        }
        return walls.filter { $0.length > tolerance / 2 }
    }

    /// Adds the traced walls to the document (one element per wall) and returns their ids.
    public static func build(_ walls: [TracedWall], into doc: inout ArchiDocument, level: Int, height: Double) -> [EntityID] {
        walls.map { doc.addElement(.wall(WallGeom(start: $0.start, end: $0.end, thickness: $0.thickness, height: height)), level: level, name: "Traced wall") }
    }
}
