// Oanarina Archi Tool — GPL-3.0-or-later
// KML 2.2 / KMZ export placed at the project's geolocation (ProjectInfo latitude/longitude, true-north angle):
// extruded building footprints (walls, slabs, roofs, rooms) and 2D linework in folders by level and layer, and in KMZ
// the 3D model as a COLLADA file referenced by a <Model> with location and heading (Google Earth).
import Foundation

public struct KMLOptions {
    /// Include the COLLADA model in KMZ packages.
    public var includeModel = true
    /// Include 2D drafting entities as line strings.
    public var includeLinework = true
    /// Ground altitude (m) added to heights (relativeToGround).
    public var altitude = 0.0
    public init() {}
}

public enum KMLExporter {
    static func esc(_ s: String) -> String { XLSX.esc(s) }

    /// Plan point (drawing units, model north rotated by `northAngle`) → (lon, lat).
    public static func lonLat(_ p: Vec2, doc: ArchiDocument) -> (lon: Double, lat: Double) {
        // ProjectInfo.northAngle: true north is the drawing's +Y axis turned counter-clockwise by this angle (°), so
        // (east, north) = R(−northAngle)·p.
        let q = p.rotated(by: -rad(doc.info.northAngle))
        return GeoJSON.toLonLat(q, origin: (doc.info.latitude, doc.info.longitude), unitMM: doc.units.mm)
    }

    static func coords(_ pts: [Vec2], z: Double, doc: ArchiDocument, close: Bool) -> String {
        var ps = pts
        if close, let f = ps.first, let l = ps.last, !f.isClose(l) { ps.append(f) }
        return ps.map { let g = lonLat($0, doc: doc); return "\(fmt(g.lon, 8)),\(fmt(g.lat, 8)),\(fmt(z, 3))" }.joined(separator: " ")
    }

    static func color(_ c: RGBA, alpha: Double = 1) -> String {
        func h(_ v: Double) -> String { String(format: "%02x", Int((max(0, min(1, v)) * 255).rounded())) }
        return h(alpha) + h(c.b) + h(c.g) + h(c.r)   // KML is aabbggrr
    }

    public static func kml(_ doc: ArchiDocument, options: KMLOptions = KMLOptions(), modelHref: String? = nil) -> String {
        let m = doc.units.mm / 1000
        var styles: [String: String] = [:]
        func style(_ key: String, _ c: RGBA, fillAlpha: Double) -> String {
            let id = "s-" + MeshExport.safeName(key)
            styles[id] = "<Style id=\"\(id)\"><LineStyle><color>\(color(c))</color><width>1.5</width></LineStyle><PolyStyle><color>\(color(c, alpha: fillAlpha))</color></PolyStyle></Style>"
            return id
        }
        func polygon(_ name: String, _ pts: [Vec2], base: Double, top: Double, styleID: String, desc: String = "") -> String {
            guard pts.count >= 3 else { return "" }
            var ring = pts
            if GeometryOps.signedArea(ring) < 0 { ring.reverse() }   // KML outer rings counter-clockwise
            let extrude = top - base > 1e-6
            return "<Placemark><name>\(esc(name))</name>\(desc.isEmpty ? "" : "<description>\(esc(desc))</description>")<styleUrl>#\(styleID)</styleUrl><Polygon>\(extrude ? "<extrude>1</extrude>" : "")<altitudeMode>relativeToGround</altitudeMode><outerBoundaryIs><LinearRing><coordinates>\(coords(ring, z: top + options.altitude, doc: doc, close: true))</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>\n"
        }
        var folders: [String] = []
        for lv in doc.levels.sorted(by: { $0.elevation < $1.elevation }) {
            let z0 = lv.elevation * m
            var body = ""
            for el in doc.elements where el.level == lv.id {
                let mat = doc.material(el.material)?.color ?? doc.layer(named: el.layer)?.color ?? RGBA(0.8, 0.8, 0.8)
                let label = el.name.isEmpty ? "\(el.typeName) \(el.id)" : el.name
                switch el.geometry {
                case .wall(let w):
                    body += polygon(label, DXFWriter.wallOutline(w), base: z0 + w.baseOffset * m, top: z0 + (w.baseOffset + w.height) * m, styleID: style("wall-" + (el.material ?? ""), mat, fillAlpha: 0.9))
                case .slab(let s):
                    body += polygon(label, s.boundary, base: z0, top: z0 + s.topOffset * m, styleID: style("slab-" + (el.material ?? ""), mat, fillAlpha: 0.6))
                case .roof(let r):
                    body += polygon(label, r.boundary, base: z0 + r.baseOffset * m, top: z0 + (r.baseOffset + r.thickness) * m, styleID: style("roof-" + (el.material ?? ""), mat, fillAlpha: 0.8))
                case .column(let c):
                    let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
                    let pts = [Vec2(-c.width / 2, -c.depth / 2), Vec2(c.width / 2, -c.depth / 2), Vec2(c.width / 2, c.depth / 2), Vec2(-c.width / 2, c.depth / 2)].map(t.apply)
                    body += polygon(label, pts, base: z0 + c.baseOffset * m, top: z0 + (c.baseOffset + c.height) * m, styleID: style("column", mat, fillAlpha: 0.9))
                case .space(let s):
                    let a = abs(GeometryOps.signedArea(s.boundary)) * m * m
                    body += polygon((s.number.isEmpty ? "" : s.number + " ") + s.name, s.boundary, base: z0, top: z0 + 0.01, styleID: style("room", RGBA(0.96, 0.77, 0.09), fillAlpha: 0.35),
                                    desc: "Area \(fmt(a, 2)) m²")
                default: continue
                }
            }
            if !body.isEmpty { folders.append("<Folder><name>\(esc(lv.name))</name>\n\(body)</Folder>\n") }
        }
        if options.includeLinework {
            var byLayer: [String: String] = [:]
            for e in doc.entities {
                let segs: [[Vec2]]
                switch e.geometry {
                case .line(let l): segs = [[l.a, l.b]]
                case .polyline(let p): segs = [p.vertices.map(\.p) + (p.closed && !p.vertices.isEmpty ? [p.vertices[0].p] : [])]
                case .circle(let c): segs = [GeometryOps.arcPoints(center: c.center, radius: c.radius, start: 0, sweep: 2 * .pi)]
                case .arc(let a): segs = [GeometryOps.arcPoints(center: a.center, radius: a.radius, start: a.start, sweep: normAngle(a.end - a.start))]
                default: continue
                }
                let c = doc.layer(named: e.layer)?.color ?? .white
                let sid = style("layer-" + e.layer, c, fillAlpha: 0)
                let z = (e.props["elevation"].flatMap(Double.init) ?? 0) * m + options.altitude
                for s in segs where s.count >= 2 {
                    byLayer[e.layer, default: ""] += "<Placemark><name>\(esc(e.typeName)) \(e.id)</name><styleUrl>#\(sid)</styleUrl><LineString><altitudeMode>clampToGround</altitudeMode><coordinates>\(coords(s, z: z, doc: doc, close: false))</coordinates></LineString></Placemark>\n"
                }
            }
            for (l, body) in byLayer.sorted(by: { $0.key < $1.key }) { folders.append("<Folder><name>Layer \(esc(l))</name>\n\(body)</Folder>\n") }
        }
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n<Document><name>\(esc(doc.info.name))</name>\n"
        x += styles.sorted(by: { $0.key < $1.key }).map(\.value).joined(separator: "\n") + "\n"
        x += "<Placemark><name>\(esc(doc.info.name))</name><description>\(esc(doc.info.address))</description><Point><coordinates>\(fmt(doc.info.longitude, 8)),\(fmt(doc.info.latitude, 8)),0</coordinates></Point></Placemark>\n"
        if let href = modelHref {
            // COLLADA is in metres with the model origin at the project location; heading turns model north to true north.
            x += "<Placemark><name>3D model</name><Model><altitudeMode>relativeToGround</altitudeMode><Location><longitude>\(fmt(doc.info.longitude, 8))</longitude><latitude>\(fmt(doc.info.latitude, 8))</latitude><altitude>\(fmt(options.altitude, 3))</altitude></Location>"
            x += "<Orientation><heading>\(fmt(doc.info.northAngle, 4))</heading><tilt>0</tilt><roll>0</roll></Orientation><Scale><x>1</x><y>1</y><z>1</z></Scale><Link><href>\(esc(href))</href></Link></Model></Placemark>\n"
        }
        x += folders.joined() + "</Document>\n</kml>\n"
        return x
    }

    /// KMZ: doc.kml plus models/model.dae.
    public static func kmz(_ doc: ArchiDocument, options: KMLOptions = KMLOptions()) -> Data {
        var entries: [ZipArchive.Entry] = []
        if options.includeModel {
            let groups = MeshBuilder.build(doc: doc)
            if !groups.isEmpty {
                entries.append(.init(name: "models/model.dae", data: Data(ColladaExporter.export(groups, materials: doc.materials, unitMM: doc.units.mm).utf8)))
            }
        }
        let kmlText = kml(doc, options: options, modelHref: entries.isEmpty ? nil : "models/model.dae")
        entries.insert(.init(name: "doc.kml", data: Data(kmlText.utf8)), at: 0)
        return ZipArchive.write(entries, compress: true)
    }
}
