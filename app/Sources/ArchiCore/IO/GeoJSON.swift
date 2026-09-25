// Oanarina Archi Tool — GPL-3.0-or-later
// GeoJSON (RFC 7946) import/export of 2D entities. Geographic coordinates (WGS84 lon/lat) are converted to a local
// east/north plane around the project's reference point (ProjectInfo latitude/longitude) with a spherical
// equirectangular projection (accurate to a few centimetres over a few kilometres).
import Foundation

public struct GeoJSONOptions {
    /// Coordinates are WGS84 longitude/latitude (else projected metres). nil on import = detect.
    public var geographic: Bool?
    /// Reference point (lat, lon); nil = the document's project location.
    public var origin: (lat: Double, lon: Double)?
    public var layer = "GEOJSON"
    /// Coordinate reference system. Export: projected output (UTM, Web Mercator) with a "crs" member; import: overrides
    /// the file's "crs" member. nil = WGS84 when geographic, else the file's CRS or local metres.
    public var crs: GeoCRS?
    public init(geographic: Bool? = nil, crs: GeoCRS? = nil) { self.geographic = geographic; self.crs = crs }
}

public enum GeoJSON {
    static let earthRadius = 6_378_137.0

    /// Local plan point (drawing units) → (lon, lat).
    public static func toLonLat(_ p: Vec2, origin: (lat: Double, lon: Double), unitMM: Double) -> (lon: Double, lat: Double) {
        let e = p.x * unitMM / 1000, n = p.y * unitMM / 1000
        let lat = origin.lat + deg(n / earthRadius)
        let lon = origin.lon + deg(e / (earthRadius * cos(rad(origin.lat))))
        return (lon, lat)
    }
    /// (lon, lat) → local plan point (drawing units).
    public static func fromLonLat(lon: Double, lat: Double, origin: (lat: Double, lon: Double), unitMM: Double) -> Vec2 {
        let n = rad(lat - origin.lat) * earthRadius
        let e = rad(lon - origin.lon) * earthRadius * cos(rad(origin.lat))
        return Vec2(e * 1000 / unitMM, n * 1000 / unitMM)
    }

    // MARK: export

    /// FeatureCollection of the document's entities (points, curves → LineString, closed shapes → Polygon, text → Point with "text").
    public static func export(_ doc: ArchiDocument, options: GeoJSONOptions = GeoJSONOptions(geographic: true), ids: Set<EntityID>? = nil) -> String {
        let projected: GeoCRS? = options.crs.flatMap { $0 == .wgs84 || $0 == .local ? nil : $0 }
        let geo = projected != nil ? true : (options.crs == .local ? false : (options.geographic ?? true))
        let o = options.origin ?? (doc.info.latitude, doc.info.longitude)
        let k = doc.units.mm
        func c(_ p: Vec2) -> [Double] {
            if geo {
                let q = toLonLat(p, origin: o, unitMM: k)
                if let pc = projected { let xy = pc.fromLonLat(q.lon, q.lat); return [(xy.x * 1000).rounded() / 1000, (xy.y * 1000).rounded() / 1000] }
                return [q.lon, q.lat]
            }
            return [p.x * k / 1000, p.y * k / 1000]
        }
        func ring(_ pts: [Vec2]) -> [[Double]] {
            var r = pts.map(c)
            if GeometryOps.signedArea(pts) < 0 { r.reverse() } // exterior rings counter-clockwise
            if let f = r.first { r.append(f) }
            return r
        }
        var features: [[String: Any]] = []
        for e in doc.entities where ids == nil || ids!.contains(e.id) {
            var props: [String: Any] = ["id": e.id, "layer": e.layer, "type": e.typeName]
            if case .rgb = e.color { props["color"] = e.color.text } else if case .aci = e.color { props["color"] = e.color.text }
            for (pk, pv) in e.props { props[pk] = pv }
            var geom: [String: Any]?
            switch e.geometry {
            case .point(let p): geom = ["type": "Point", "coordinates": c(p)]
            case .text(let t):
                geom = ["type": "Point", "coordinates": c(t.position)]
                props["text"] = t.content; props["height"] = t.height * k / 1000; props["rotation"] = deg(t.rotation)
            case .insert(let ins):
                geom = ["type": "Point", "coordinates": c(ins.position)]
                props["block"] = ins.block
            case .hatch(let h):
                let loops = h.loops.map { GeometryOps.polylinePoints($0, closed: true) }.filter { $0.count >= 3 }
                if let outer = loops.first {
                    let holes = loops.dropFirst().map { h -> [[Double]] in var r = ring(h); r.reverse(); return r }
                    geom = ["type": "Polygon", "coordinates": [ring(outer)] + holes]
                }
            case .circle, .polyline, .ellipse, .spline, .line, .arc:
                let closed: Bool
                switch e.geometry {
                case .circle: closed = true
                case .polyline(let p): closed = p.closed
                case .ellipse(let el): closed = el.isFull
                case .spline(let s): closed = s.closed
                default: closed = false
                }
                let paths = GeometryOps.tessellate(e.geometry, doc: doc).filter { $0.count >= 2 }
                if closed, let p = paths.first {
                    var pts = p
                    if pts.count > 2, pts[0].isClose(pts[pts.count - 1]) { pts.removeLast() }
                    if pts.count >= 3 { geom = ["type": "Polygon", "coordinates": [ring(pts)]] }
                } else if paths.count == 1 {
                    geom = ["type": "LineString", "coordinates": paths[0].map(c)]
                } else if paths.count > 1 {
                    geom = ["type": "MultiLineString", "coordinates": paths.map { $0.map(c) }]
                }
            default: break
            }
            if let g = geom { features.append(["type": "Feature", "geometry": g, "properties": props]) }
        }
        var root: [String: Any] = ["type": "FeatureCollection", "features": features]
        if !geo { root["properties"] = ["units": "m", "crs": "local"] }
        if let pc = projected, case .utm(let z, let n) = pc { root["crs"] = ["type": "name", "properties": ["name": "urn:ogc:def:crs:EPSG::\(n ? 32600 + z : 32700 + z)"]] }
        if projected == .webMercator { root["crs"] = ["type": "name", "properties": ["name": "urn:ogc:def:crs:EPSG::3857"]] }
        guard let d = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: import

    public enum GeoJSONError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid GeoJSON: \(m)" }; return nil }
    }

    /// Entities from a GeoJSON document. Returns the entities and the origin used (for geographic data).
    public static func entities(_ text: String, doc: ArchiDocument, options: GeoJSONOptions = GeoJSONOptions()) throws -> [Entity] {
        guard let data = text.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeoJSONError.invalid("not a JSON object")
        }
        var feats: [([String: Any], [String: Any])] = []   // (geometry, properties)
        func collect(_ o: [String: Any]) {
            switch o["type"] as? String {
            case "FeatureCollection": for f in (o["features"] as? [[String: Any]]) ?? [] { collect(f) }
            case "Feature": if let g = o["geometry"] as? [String: Any] { feats.append((g, o["properties"] as? [String: Any] ?? [:])) }
            case .some: feats.append((o, [:]))
            default: break
            }
        }
        collect(root)
        guard !feats.isEmpty else { throw GeoJSONError.invalid("no features") }
        // Detect geographic coordinates: every coordinate within lon/lat range.
        var allPts: [[Double]] = []
        func gather(_ v: Any) {
            if let a = v as? [Double], a.count >= 2 { allPts.append(a); return }
            if let a = v as? [Any] { a.forEach(gather) }
        }
        for (g, _) in feats { gather(g["coordinates"] ?? []); for sub in (g["geometries"] as? [[String: Any]]) ?? [] { gather(sub["coordinates"] ?? []) } }
        // CRS: option, else the (2008 GeoJSON) "crs" member, else detected from the coordinate ranges.
        var fileCRS: GeoCRS? = nil
        if let crs = root["crs"] as? [String: Any], let props = crs["properties"] as? [String: Any], let name = props["name"] as? String { fileCRS = GeoCRS.parse(name) }
        let crs = options.crs ?? fileCRS
        let projected: GeoCRS? = crs.flatMap { $0 == .wgs84 || $0 == .local ? nil : $0 }
        let geo = projected != nil || crs == .wgs84 ? true : (crs == .local ? false : (options.geographic ?? (!allPts.isEmpty && allPts.allSatisfy { abs($0[0]) <= 180 && abs($0[1]) <= 90 })))
        let k = doc.units.mm
        let o = options.origin ?? (doc.info.latitude, doc.info.longitude)
        func P(_ a: Any) -> Vec2? {
            guard let c = a as? [Double], c.count >= 2 else {
                if let n = a as? [NSNumber], n.count >= 2 { return P(n.map { $0.doubleValue }) }
                return nil
            }
            if let pc = projected { let ll = pc.toLonLat(c[0], c[1]); return fromLonLat(lon: ll.lon, lat: ll.lat, origin: o, unitMM: k) }
            return geo ? fromLonLat(lon: c[0], lat: c[1], origin: o, unitMM: k) : Vec2(c[0] * 1000 / k, c[1] * 1000 / k)
        }
        func line(_ a: Any) -> [Vec2] { (a as? [Any])?.compactMap(P) ?? [] }
        var out: [Entity] = []
        func entity(_ g: Geometry, _ props: [String: Any]) {
            var e = Entity(layer: (props["layer"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? options.layer, geometry: g)
            if let c = props["color"] as? String, let cr = ColorRef.parse(c) { e.color = cr }
            for (key, v) in props where !["layer", "color", "id", "type", "text", "height", "rotation", "block"].contains(key) {
                if v is NSNull { continue }
                e.props[key] = (v as? String) ?? "\(v)"
            }
            out.append(e)
        }
        func ringPoly(_ r: [Vec2]) -> [Vec2] {
            var pts = r
            if pts.count > 1, pts[0].isClose(pts[pts.count - 1], tol: 1e-9) { pts.removeLast() }
            return pts
        }
        func add(_ g: [String: Any], _ props: [String: Any]) {
            let coords = g["coordinates"] ?? []
            switch g["type"] as? String {
            case "Point":
                guard let p = P(coords) else { return }
                if let t = props["text"] as? String, !t.isEmpty {
                    let h = ((props["height"] as? NSNumber)?.doubleValue).map { $0 * 1000 / k } ?? 2500 / k
                    let rot = rad((props["rotation"] as? NSNumber)?.doubleValue ?? 0)
                    entity(.text(TextGeom(position: p, height: h, content: t, rotation: rot)), props)
                } else { entity(.point(p), props) }
            case "MultiPoint": for c in (coords as? [Any]) ?? [] { if let p = P(c) { entity(.point(p), props) } }
            case "LineString":
                let pts = line(coords); if pts.count >= 2 { entity(.polyline(PolylineGeom(points: pts)), props) }
            case "MultiLineString":
                for l in (coords as? [Any]) ?? [] { let pts = line(l); if pts.count >= 2 { entity(.polyline(PolylineGeom(points: pts)), props) } }
            case "Polygon", "MultiPolygon":
                let polys: [Any] = g["type"] as? String == "Polygon" ? [coords] : ((coords as? [Any]) ?? [])
                for poly in polys {
                    let rings = ((poly as? [Any]) ?? []).map { ringPoly(line($0)) }.filter { $0.count >= 3 }
                    for r in rings { entity(.polyline(PolylineGeom(points: r, closed: true)), props) }
                }
            case "GeometryCollection":
                for sub in (g["geometries"] as? [[String: Any]]) ?? [] { add(sub, props) }
            default: break
            }
        }
        for (g, p) in feats { add(g, p) }
        return out
    }
}
