// Oanarina Archi Tool — GPL-3.0-or-later
// Shadow studies (ANL-019): ground shadows of the 3D model for a date and a series of times at the project location
// (sun position from SolarCalculator, NOAA algorithm), as plan shadow diagrams — hatched shadow outlines per time on
// their own layers — and as an image sequence (one SVG per time plus an animated HTML page). Every triangle of the
// model is projected along the sun direction onto the ground plane and rasterised; the union of the shadow is traced
// back as polygons (cell size 1/800 of the extent, then simplified), so overlapping shadows are merged and areas exact
// to the cell size. Shadows fall on the ground plane only (not onto other surfaces).
import Foundation

public enum ShadowStudy {
    public struct Frame: Hashable {
        public var time: String
        public var sun: SunPosition
        /// Shadow outlines on the ground (outer loops counter-clockwise, holes clockwise), drawing units.
        public var loops: [[Vec2]]
        /// Shadow area in square drawing units (0 when the sun is down).
        public var area: Double
    }

    static let skipKinds = ["datum", "topo", "terrain", "site", "paving", "path", "subregion", "plan"]

    /// Triangles casting shadows (drawing units, Z up).
    static func triangles(_ doc: ArchiDocument) -> [(Vec3, Vec3, Vec3)] {
        var out: [(Vec3, Vec3, Vec3)] = []
        for g in MeshBuilder.build(doc: doc) where !skipKinds.contains(where: { g.kind.lowercased().contains($0) }) {
            let p = g.mesh.positions, ix = g.mesh.indices
            var i = 0
            while i + 2 < ix.count { out.append((p[Int(ix[i])], p[Int(ix[i + 1])], p[Int(ix[i + 2])])); i += 3 }
        }
        return out
    }

    /// Ground shadow of triangles for a direction towards the sun; `cells` is the raster resolution along the longer side.
    public static func shadow(_ tris: [(Vec3, Vec3, Vec3)], toSun s: Vec3, groundZ: Double, cells: Int = 800) -> (loops: [[Vec2]], area: Double) {
        guard s.z > 1e-4 else { return ([], 0) }
        func proj(_ p: Vec3) -> Vec2 { let t = (p.z - groundZ) / s.z; return Vec2(p.x - s.x * t, p.y - s.y * t) }
        var proj2: [(Vec2, Vec2, Vec2)] = []
        var b = BBox2.empty
        for (a, c, d) in tris where max(a.z, c.z, d.z) > groundZ + 1e-9 {
            // Clip to the part above the ground (points below are lifted onto it).
            let q = (proj(a.z < groundZ ? Vec3(a.x, a.y, groundZ) : a), proj(c.z < groundZ ? Vec3(c.x, c.y, groundZ) : c), proj(d.z < groundZ ? Vec3(d.x, d.y, groundZ) : d))
            proj2.append(q); b.add(q.0); b.add(q.1); b.add(q.2)
        }
        guard !b.isEmpty, b.width > 0 || b.height > 0 else { return ([], 0) }
        let size = max(b.width, b.height) / Double(max(cells, 16))
        let pad = 2.0
        let ox = b.min.x - pad * size, oy = b.min.y - pad * size
        let nx = Int((b.width / size).rounded(.up)) + 2 * Int(pad) + 1, ny = Int((b.height / size).rounded(.up)) + 2 * Int(pad) + 1
        var grid = [Bool](repeating: false, count: nx * ny)
        // Scanline fill of every projected triangle (cell centres).
        for (p0, p1, p2) in proj2 {
            let area2 = (p1 - p0).cross(p2 - p0)
            guard abs(area2) > 1e-18 else { continue }
            let y0 = max(0, Int(((min(p0.y, p1.y, p2.y) - oy) / size - 0.5).rounded(.up))), y1 = min(ny - 1, Int(((max(p0.y, p1.y, p2.y) - oy) / size - 0.5).rounded(.down)))
            guard y0 <= y1 else { continue }
            let pts = [p0, p1, p2]
            for j in y0...y1 {
                let y = oy + (Double(j) + 0.5) * size
                var xs: [Double] = []
                for k in 0..<3 {
                    let a = pts[k], c = pts[(k + 1) % 3]
                    if (a.y <= y && c.y > y) || (c.y <= y && a.y > y) { xs.append(a.x + (y - a.y) / (c.y - a.y) * (c.x - a.x)) }
                }
                guard xs.count >= 2 else { continue }
                let xa = xs.min()!, xb = xs.max()!
                let i0 = max(0, Int(((xa - ox) / size - 0.5).rounded(.up))), i1 = min(nx - 1, Int(((xb - ox) / size - 0.5).rounded(.down)))
                if i0 <= i1 { for i in i0...i1 { grid[j * nx + i] = true } }
            }
        }
        let filled = grid.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard filled > 0 else { return ([], 0) }
        // Boundary edges between filled and empty cells, directed with the filled cell on the left, chained into loops.
        func at(_ i: Int, _ j: Int) -> Bool { i >= 0 && j >= 0 && i < nx && j < ny && grid[j * nx + i] }
        var next: [Int64: [Int64]] = [:]
        func key(_ i: Int, _ j: Int) -> Int64 { Int64(i) << 32 | Int64(j) }
        func addEdge(_ a: (Int, Int), _ c: (Int, Int)) { next[key(a.0, a.1), default: []].append(key(c.0, c.1)) }
        for j in 0..<ny { for i in 0..<nx where grid[j * nx + i] {
            if !at(i, j - 1) { addEdge((i, j), (i + 1, j)) }
            if !at(i + 1, j) { addEdge((i + 1, j), (i + 1, j + 1)) }
            if !at(i, j + 1) { addEdge((i + 1, j + 1), (i, j + 1)) }
            if !at(i - 1, j) { addEdge((i, j + 1), (i, j)) }
        } }
        var loops: [[Vec2]] = []
        while let start = next.first(where: { !$0.value.isEmpty })?.key {
            var loop: [Int64] = [start]
            var cur = start, prevDir: (Int64, Int64) = (0, 0)
            var guardN = 0
            while guardN < 4_000_000 {
                guardN += 1
                guard var outs = next[cur], !outs.isEmpty else { break }
                // At a pinch vertex (two ways out) turn left first so loops stay simple.
                var pick = 0
                if outs.count > 1 {
                    let (cx, cy) = (cur >> 32, cur & 0xffff_ffff)
                    for (n, o) in outs.enumerated() {
                        let d = ((o >> 32) - cx, (o & 0xffff_ffff) - cy)
                        if prevDir.0 * d.1 - prevDir.1 * d.0 > 0 { pick = n }
                    }
                }
                let nx2 = outs.remove(at: pick)
                next[cur] = outs
                prevDir = ((nx2 >> 32) - (cur >> 32), (nx2 & 0xffff_ffff) - (cur & 0xffff_ffff))
                cur = nx2
                if cur == start { break }
                loop.append(cur)
            }
            var pts = loop.map { Vec2(ox + Double($0 >> 32) * size, oy + Double($0 & 0xffff_ffff) * size) }
            pts = simplify(pts, tolerance: size * 0.75)
            if pts.count >= 3 { loops.append(pts) }
        }
        return (loops, Double(filled) * size * size)
    }

    /// Douglas–Peucker simplification of a closed loop (removes the raster's stair steps and collinear points).
    static func simplify(_ loop: [Vec2], tolerance: Double) -> [Vec2] {
        guard loop.count > 4 else { return loop }
        // Split the closed loop at its two farthest-apart points.
        let a = 0
        let b = loop.indices.max { loop[$0].distance(to: loop[a]) < loop[$1].distance(to: loop[a]) }!
        func dp(_ pts: [Vec2]) -> [Vec2] {
            guard pts.count > 2 else { return pts }
            let s = pts[0], e = pts[pts.count - 1], d = e - s, l = d.length
            var best = 0, bd = -1.0
            for i in 1..<(pts.count - 1) {
                let dist = l > 1e-12 ? abs(d.cross(pts[i] - s)) / l : pts[i].distance(to: s)
                if dist > bd { bd = dist; best = i }
            }
            if bd <= tolerance { return [s, e] }
            return Array(dp(Array(pts[...best])).dropLast()) + dp(Array(pts[best...]))
        }
        let first = dp(Array(loop[a...b])), second = dp(Array(loop[b...]) + [loop[a]])
        var out = Array(first.dropLast()) + Array(second.dropLast())
        // The split points themselves may be collinear with their neighbours.
        var changed = true
        while changed && out.count > 3 {
            changed = false
            for i in out.indices {
                let p = out[(i + out.count - 1) % out.count], q = out[(i + 1) % out.count], d = q - p, l = d.length
                if l > 1e-12, abs(d.cross(out[i] - p)) / l <= tolerance { out.remove(at: i); changed = true; break }
            }
        }
        return out
    }

    /// Parses a time list: "9:00,12:00,15:00" or a range "8-18/2" (hours, step in hours).
    public static func times(_ s: String) -> [String] {
        let t = s.replacingOccurrences(of: " ", with: "")
        if let slash = t.firstIndex(of: "/"), let dash = t.firstIndex(of: "-"), dash < slash,
           let a = Double(t[..<dash]), let b = Double(t[t.index(after: dash)..<slash]), let st = Double(t[t.index(after: slash)...]), st > 0, b >= a {
            var out: [String] = []
            var h = a
            while h <= b + 1e-9 && out.count < 96 { out.append(String(format: "%02d:%02d", Int(h), Int(((h - floor(h)) * 60).rounded()))); h += st }
            return out
        }
        return t.split(separator: ",").map(String.init).filter { $0.contains(":") || Double($0) != nil }.map { $0.contains(":") ? $0 : $0 + ":00" }
    }

    /// Frames for a date and local times.
    public static func frames(_ doc: ArchiDocument, day: String, times: [String], utcOffset: Double, groundZ: Double? = nil, cells: Int = 800) -> [Frame] {
        let tris = triangles(doc)
        let ground = groundZ ?? ((doc.levels.map(\.elevation).min() ?? 0))
        return times.compactMap { tm in
            guard let date = SolarCalculator.date(day, tm, utcOffset: utcOffset) else { return nil }
            let p = SolarCalculator.position(date: date, latitude: doc.info.latitude, longitude: doc.info.longitude)
            guard p.altitude > 0.5 else { return Frame(time: tm, sun: p, loops: [], area: 0) }
            let s = SolarCalculator.direction(p, northAngle: doc.info.northAngle)
            let r = shadow(tris, toSun: s, groundZ: ground, cells: cells)
            return Frame(time: tm, sun: p, loops: r.loops, area: r.area)
        }
    }

    /// Colour of the n-th frame (morning blue → evening orange).
    static func colour(_ i: Int, _ n: Int) -> RGBA {
        let t = n > 1 ? Double(i) / Double(n - 1) : 0.5
        return RGBA(0.20 + 0.70 * t, 0.35 + 0.15 * t, 0.85 - 0.65 * t)
    }

    /// One SVG per frame: the plan with that time's shadow (image sequence), all in the same window.
    public static func svgs(_ doc: ArchiDocument, frames: [Frame], day: String) -> [String] {
        var o = DrawOptions(level: doc.currentLevel); o.forPaper = true
        let plan = DrawListBuilder.entries(doc: doc, options: o)
        var box = GeometryOps.bounds(of: doc)
        for f in frames { for l in f.loops { l.forEach { box.add($0) } } }
        if box.isEmpty { box = BBox2(min: .zero, max: Vec2(1000, 1000)) }
        let pad = max(box.width, box.height) * 0.05
        box = BBox2(min: box.min - Vec2(pad, pad), max: box.max + Vec2(pad, pad))
        let ppu = 1200 / max(box.width, 1e-9)
        func X(_ p: Vec2) -> String { fmt((p.x - box.min.x) * ppu, 2) }
        func Y(_ p: Vec2) -> String { fmt((box.max.y - p.y) * ppu, 2) }
        let base = SVGExporter.export(entries: plan, bounds: box, background: RGBA(1, 1, 1), pixelsPerUnit: ppu)
        return frames.enumerated().map { (i, f) in
            var shadow = "<g opacity=\"0.45\"><path fill=\"\(colour(i, frames.count).hex)\" fill-rule=\"evenodd\" d=\""
            for l in f.loops { shadow += "M" + l.map { X($0) + " " + Y($0) }.joined(separator: " L") + " Z " }
            shadow += "\"/></g>\n"
            shadow += "<text x=\"12\" y=\"28\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"20\" fill=\"#222\">\(day) \(f.time) — sun \(fmt(f.sun.azimuth, 0))° / \(fmt(f.sun.altitude, 0))°\(f.sun.altitude <= 0.5 ? " (below the horizon)" : "")</text>\n"
            // Shadows under the plan linework: insert before the drawing group.
            if let r = base.range(of: "<g fill=\"none\"") { var s = base; s.insert(contentsOf: shadow, at: r.lowerBound); return s }
            return base.replacingOccurrences(of: "</svg>", with: shadow + "</svg>")
        }
    }

    /// HTML page cycling through the frames.
    public static func html(_ svgs: [String], frames: [Frame], title: String) -> String {
        var h = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>\(XLSX.esc(title))</title><style>body{margin:0;background:#1c1c1e;color:#eee;font-family:-apple-system,Helvetica,sans-serif;text-align:center}.f{display:none}.f.on{display:block}.f svg{max-width:96vw;max-height:88vh;height:auto;background:#fff}</style></head><body>\n"
        h += "<p><button id=\"p\">Pause</button> <span id=\"t\"></span></p>\n"
        for (i, s) in svgs.enumerated() {
            var body = s
            if let r = body.range(of: "?>\n") { body.removeSubrange(body.startIndex..<r.upperBound) }
            h += "<div class=\"f\(i == 0 ? " on" : "")\" data-t=\"\(frames[i].time)\">\(body)</div>\n"
        }
        h += "<script>var f=document.querySelectorAll('.f'),i=0,run=true;function show(){f.forEach(function(e,k){e.classList.toggle('on',k===i)});document.getElementById('t').textContent=f[i].dataset.t;}show();setInterval(function(){if(run){i=(i+1)%f.length;show();}},1200);document.getElementById('p').onclick=function(){run=!run;this.textContent=run?'Pause':'Play';};</script></body></html>\n"
        return h
    }

    static var command: CommandDef {
        CommandDef("SHADOWDIAGRAM", aliases: ["SHADOWPLAN", "SHADOWANALYSIS", "PLANSHADOWS"], category: "Analysis",
                   summary: "Shadow study for a date and times at the project location: hatched ground shadows per time on A-SHADOW-hhmm layers and/or an SVG image sequence with an animated HTML page; prints the shadow areas.") { ed in
            let day = try await ed.getWord("Enter date (YYYY-MM-DD)", defaultValue: ed.doc.variable("SUNDATE") ?? "2025-03-21") ?? "2025-03-21"
            guard SolarCalculator.date(day, "12:00", utcOffset: 0) != nil else { throw CommandError.invalid("Use a date like 2025-03-21.") }
            let tl = try await ed.getWord("Enter times (9:00,12:00,15:00 or 8-18/1)", defaultValue: ed.doc.variable("SHADOWTIMES") ?? "9:00,12:00,15:00") ?? "9:00,12:00,15:00"
            let ts = times(tl)
            guard !ts.isEmpty else { throw CommandError.invalid("No valid times.") }
            let defOff = Double(ed.doc.variable("UTCOFFSET") ?? "") ?? Double(TimeZone.current.secondsFromGMT()) / 3600
            let off = try await ed.getReal("Enter UTC offset in hours", defaultValue: defOff).value ?? defOff
            let out = try await ed.getKeyword("Output [Draw/Images/Both]", ["Draw", "Images", "Both"], defaultValue: "Draw") ?? "Draw"
            let fr = frames(ed.doc, day: day, times: ts, utcOffset: off)
            let u2 = pow(ed.doc.units.mm / 1000, 2)
            for f in fr { ed.print("\(day) \(f.time): sun azimuth \(fmt(f.sun.azimuth, 1))°, altitude \(fmt(f.sun.altitude, 1))°, shadow \(fmt(f.area * u2, 1)) m²" + (f.sun.altitude <= 0.5 ? " (night)" : "")) }
            ed.doc.setVariable("SUNDATE", day); ed.doc.setVariable("SHADOWTIMES", tl); ed.doc.setVariable("UTCOFFSET", fmt(off))
            if out != "Images" {
                var d = ed.doc
                var ids: [EntityID] = []
                for (i, f) in fr.enumerated() where !f.loops.isEmpty {
                    let layer = "A-SHADOW-" + f.time.replacingOccurrences(of: ":", with: "")
                    if d.layer(named: layer) == nil { d.layers.append(Layer(name: layer, color: colour(i, fr.count), lineweight: 0.13, description: "Shadows \(day) \(f.time)")) }
                    let loops = PolygonBoolean.normalize(f.loops).map { $0.map { PolyVertex($0) } }
                    ids.append(d.add(Entity(layer: layer, geometry: .hatch(HatchGeom(loops: loops, pattern: "SOLID")), props: ["shadow": "\(day) \(f.time)", "area": fmt(f.area * u2, 2)])))
                }
                ed.doc = d
                ed.selection = Set(ids)
                ed.print("\(ids.count) shadow hatch(es) on A-SHADOW-* layers.")
            }
            if out != "Draw" {
                let dir = try await IOCommands.path(ed, "Enter folder for the image sequence")
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let svg = svgs(ed.doc, frames: fr, day: day)
                    for (i, s) in svg.enumerated() {
                        try s.write(to: dir.appendingPathComponent(String(format: "shadow-%02d-%@.svg", i + 1, fr[i].time.replacingOccurrences(of: ":", with: ""))), atomically: true, encoding: .utf8)
                    }
                    try html(svg, frames: fr, title: "Shadow study \(day)").write(to: dir.appendingPathComponent("shadow-study.html"), atomically: true, encoding: .utf8)
                    ed.print("Wrote \(svg.count) SVG frame(s) and shadow-study.html to \(dir.path).")
                } catch { throw CommandError.invalid("Cannot write the images: \(error.localizedDescription)") }
            }
        }
    }
}
