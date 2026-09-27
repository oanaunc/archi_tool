// Oanarina Archi Tool — GPL-3.0-or-later
// JSON encoding of the resolved 2D draw list (Render/DrawList.swift) for the Windows shell, which paints exactly the
// items the Mac canvas paints. Field names follow the Swift types; colours are "#rrggbb" (+ "alpha" when not opaque),
// points are [x, y] in drawing units (sheets: paper millimetres).
import Foundation

public enum EngineDrawJSON {
    /// "#rrggbb" (lower case).
    public static func hex(_ c: RGBA) -> String {
        func b(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        let v = (b(c.r) << 16) | (b(c.g) << 8) | b(c.b)
        let s = String(v, radix: 16)
        return "#" + String(repeating: "0", count: 6 - s.count) + s
    }

    static func setColor(_ o: inout EngineObject, _ key: String, _ c: RGBA) {
        o.set(key, hex(c))
        if c.a < 0.999 { o.set("alpha", c.a) }
    }

    static func points(_ p: [Vec2]) -> EngineJSON { .array(p.map { EngineJSON.point($0) }) }

    public static func textGeom(_ t: TextGeom) -> EngineJSON {
        var o = EngineObject()
        o.set("position", EngineJSON.point(t.position))
        o.set("height", t.height)
        o.set("rotation", t.rotation)
        o.set("content", t.content)
        o.set("style", t.style)
        o.set("halign", t.halign.rawValue)
        o.set("valign", t.valign.rawValue)
        o.set("width", t.width)
        return o.json
    }

    public static func imageGeom(_ im: ImageGeom) -> EngineJSON {
        var o = EngineObject()
        o.set("path", im.path)
        o.set("origin", EngineJSON.point(im.origin))
        o.set("size", EngineJSON.point(im.size))
        o.set("rotation", im.rotation)
        return o.json
    }

    public static func style(_ s: StrokeStyle) -> EngineJSON {
        var o = EngineObject()
        setColor(&o, "color", s.color)
        o.set("lineweight", s.lineweight)
        o.set("dash", EngineJSON.numbers(s.dash))
        return o.json
    }

    /// One draw item; `id` is the object it belongs to (nil for decoration), `clip` a paper rectangle (sheet viewports).
    public static func item(_ it: DrawItem, id: EntityID? = nil, clip: BBox2? = nil) -> EngineJSON {
        var o = EngineObject()
        switch it {
        case .stroke(let p, let closed, let st):
            o.set("type", "stroke")
            o.set("points", points(p))
            o.set("closed", closed)
            o.set("style", style(st))
        case .fill(let loops, let c):
            o.set("type", "fill")
            o.set("loops", EngineJSON.array(loops.map { points($0) }))
            setColor(&o, "color", c)
        case .text(let t, let font, let c):
            o.set("type", "text")
            o.set("text", textGeom(t))
            o.set("font", font)
            setColor(&o, "color", c)
        case .image(let im):
            o.set("type", "image")
            o.set("image", imageGeom(im))
        }
        if let id { o.set("id", id) }
        if let c = clip { o.set("clip", rect(c)) }
        return o.json
    }

    public static func rect(_ b: BBox2) -> EngineJSON { EngineJSON.numbers([b.min.x, b.min.y, b.max.x, b.max.y]) }

    public static func items(_ items: [DrawItem]) -> EngineJSON { .array(items.map { item($0) }) }

    /// Maps a draw item through a similarity transform p' = (p - from) / scale + to (model → paper for sheet viewports).
    public static func mapped(_ it: DrawItem, from: Vec2, scale: Double, to: Vec2) -> DrawItem {
        func m(_ p: Vec2) -> Vec2 { (p - from) / scale + to }
        switch it {
        case .stroke(let p, let closed, var st):
            st.dash = st.dash.map { $0 / scale }
            return .stroke(points: p.map(m), closed: closed, style: st)
        case .fill(let loops, let c):
            return .fill(loops: loops.map { $0.map(m) }, color: c)
        case .text(var t, let font, let c):
            t.position = m(t.position); t.height /= scale; t.width /= scale
            return .text(t, font: font, color: c)
        case .image(var im):
            im.origin = m(im.origin); im.size = im.size / scale
            return .image(im)
        }
    }
}
