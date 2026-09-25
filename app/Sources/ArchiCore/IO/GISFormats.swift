// Oanarina Archi Tool — GPL-3.0-or-later
// GIS/site formats: ESRI Shapefile (.shp + .dbf + .prj, per the ESRI Shapefile Technical Description, 1998),
// OpenStreetMap XML (.osm) buildings/roads/context, and ESRI ASCII grid (.asc) elevation rasters as toposurfaces.
import Foundation

public struct GISImportOptions {
    /// Reference point for geographic data (lat, lon); nil = the document's project location.
    public var origin: (lat: Double, lon: Double)?
    /// CRS of projected coordinates when the file does not say (nil = from .prj / local metres).
    public var crs: GeoCRS?
    /// Local metres are shifted by this amount (metres) — e.g. the lower-left of a survey — before import.
    public var shift: Vec2 = .zero
    public var layer: String?
    /// OSM/Shapefile buildings also become extruded mass solids.
    public var masses = false
    public init() {}
}

public enum GISImportError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let m) = self { return m }; return nil }
}

/// Converts file coordinates to drawing coordinates: geographic via the project origin, projected CRS via lon/lat,
/// local metres by scaling.
struct GeoMapper {
    let crs: GeoCRS
    let origin: (lat: Double, lon: Double)
    let unitMM: Double
    let shift: Vec2
    func map(_ x: Double, _ y: Double) -> Vec2 {
        switch crs {
        case .wgs84: return GeoJSON.fromLonLat(lon: x, lat: y, origin: origin, unitMM: unitMM)
        case .local: return Vec2((x - shift.x) * 1000 / unitMM, (y - shift.y) * 1000 / unitMM)
        default: let ll = crs.toLonLat(x, y); return GeoJSON.fromLonLat(lon: ll.lon, lat: ll.lat, origin: origin, unitMM: unitMM)
        }
    }
}

public enum Shapefile {
    /// CRS from a .prj (ESRI WKT): UTM zones, Web Mercator, geographic.
    public static func crs(fromPRJ wkt: String) -> GeoCRS? {
        let u = wkt.uppercased()
        if u.contains("MERCATOR_AUXILIARY_SPHERE") || u.contains("PSEUDO-MERCATOR") || u.contains("WEB_MERCATOR") || u.contains("POPULAR VISUALISATION") { return .webMercator }
        if let r = u.range(of: "UTM[_ ]ZONE[_ ]([0-9]{1,2})([NS]?)", options: .regularExpression) {
            let t = String(u[r])
            let digits = t.filter(\.isNumber)
            guard let z = Int(digits), (1...60).contains(z) else { return nil }
            var north = !t.hasSuffix("S")
            if !t.hasSuffix("N") && !t.hasSuffix("S") { north = !u.contains("SOUTH") }
            return .utm(zone: z, north: north)
        }
        if u.hasPrefix("GEOGCS") { return .wgs84 }
        if u.hasPrefix("PROJCS") { return .local }
        return nil
    }

    /// dBASE III attribute table: one dictionary per record (trimmed strings; deleted records are empty).
    public static func readDBF(_ data: Data) -> [[String: String]] {
        let b = [UInt8](data)
        guard b.count >= 32 else { return [] }
        let n = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
        let headerLen = Int(b[8]) | Int(b[9]) << 8, recLen = Int(b[10]) | Int(b[11]) << 8
        var fields: [(String, Int)] = []
        var o = 32
        while o + 32 <= b.count && b[o] != 0x0D && o < headerLen {
            let nameBytes = b[o..<(o + 11)].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            fields.append((name, Int(b[o + 16])))
            o += 32
        }
        var out: [[String: String]] = []
        for r in 0..<n {
            let start = headerLen + r * recLen
            guard start + recLen <= b.count, recLen > 0 else { break }
            var rec: [String: String] = [:]
            if b[start] != 0x2A { // '*' = deleted
                var p = start + 1
                for (name, len) in fields {
                    guard p + len <= b.count else { break }
                    let raw = Data(b[p..<(p + len)])
                    let v = (String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { rec[name] = v }
                    p += len
                }
            }
            out.append(rec)
        }
        return out
    }

    /// Entities from a shapefile: points, polylines, closed polygons (all rings), attributes as props; a Z value or an
    /// ELEV/ELEVATION/CONTOUR/Z attribute becomes the "elevation" prop (contours usable by TOPO).
    public static func entities(shp: Data, dbf: Data? = nil, prj: String? = nil, doc: ArchiDocument, options: GISImportOptions = GISImportOptions()) throws -> [Entity] {
        let b = [UInt8](shp)
        guard b.count >= 100 else { throw GISImportError.invalid("The .shp file is too short.") }
        func be32(_ o: Int) -> Int { Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]) }
        func le32(_ o: Int) -> Int { Int(Int32(bitPattern: UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24)) }
        func dbl(_ o: Int) -> Double { var u: UInt64 = 0; for k in 0..<8 { u |= UInt64(b[o + k]) << (8 * UInt64(k)) }; return Double(bitPattern: u) }
        guard be32(0) == 9994 else { throw GISImportError.invalid("Not an ESRI shapefile.") }
        let attrs = dbf.map(readDBF) ?? []
        let crs = options.crs ?? prj.flatMap(crs(fromPRJ:)) ?? {
            // No .prj: geographic when the bounding box fits lon/lat, else local metres.
            let xmin = dbl(36), ymin = dbl(44), xmax = dbl(52), ymax = dbl(60)
            return abs(xmin) <= 180 && abs(xmax) <= 180 && abs(ymin) <= 90 && abs(ymax) <= 90 ? GeoCRS.wgs84 : GeoCRS.local
        }()
        let m = GeoMapper(crs: crs, origin: options.origin ?? (doc.info.latitude, doc.info.longitude), unitMM: doc.units.mm, shift: options.shift)
        let layer = options.layer ?? "SHP"
        var out: [Entity] = []
        var o = 100
        var rec = 0
        let zKeys = ["ELEV", "ELEVATION", "CONTOUR", "Z", "HEIGHT_M", "ALT", "ALTITUDE"]
        while o + 8 <= b.count {
            let len = be32(o + 4) * 2
            let c = o + 8
            o = c + len
            defer { rec += 1 }
            guard len >= 4, c + len <= b.count else { break }
            let type = le32(c)
            var props = rec < attrs.count ? attrs[rec] : [:]
            if props["elevation"] == nil, let k = props.keys.first(where: { zKeys.contains($0.uppercased()) }), let v = Double(props[k]!) { props["elevation"] = fmt(v * 1000 / doc.units.mm, 6) }
            switch type {
            case 1, 11, 21: // Point, PointZ, PointM
                guard len >= 20 else { continue }
                var e = Entity(layer: layer, geometry: .point(m.map(dbl(c + 4), dbl(c + 12))), props: props)
                if type == 11, len >= 28 { e.props["z"] = fmt(dbl(c + 20) * 1000 / doc.units.mm, 6) }
                out.append(e)
            case 8, 18, 28: // MultiPoint
                guard len >= 40 else { continue }
                let n = le32(c + 36)
                guard n >= 0, c + 40 + n * 16 <= b.count else { continue }
                let zBase = c + 40 + n * 16 + 16
                for i in 0..<n {
                    var e = Entity(layer: layer, geometry: .point(m.map(dbl(c + 40 + i * 16), dbl(c + 48 + i * 16))), props: props)
                    if type == 18, zBase + (i + 1) * 8 <= c + len { e.props["z"] = fmt(dbl(zBase + i * 8) * 1000 / doc.units.mm, 6) }
                    out.append(e)
                }
            case 3, 5, 13, 15, 23, 25: // PolyLine / Polygon (+Z, +M)
                guard len >= 44 else { continue }
                let np = le32(c + 36), n = le32(c + 40)
                guard np > 0, n > 0, c + 44 + np * 4 + n * 16 <= b.count else { continue }
                let parts = (0..<np).map { le32(c + 44 + $0 * 4) } + [n]
                let pb = c + 44 + np * 4
                let zs: [Double]? = (type == 13 || type == 15) && pb + n * 16 + 16 + n * 8 <= c + len ? (0..<n).map { dbl(pb + n * 16 + 16 + $0 * 8) } : nil
                let polygon = type % 10 == 5
                for k in 0..<np {
                    let a = max(0, parts[k]), z = min(n, parts[k + 1])
                    guard z - a >= 2 else { continue }
                    var pts = (a..<z).map { m.map(dbl(pb + $0 * 16), dbl(pb + $0 * 16 + 8)) }
                    if polygon, pts.count > 2, pts[0].isClose(pts[pts.count - 1], tol: 1e-9) { pts.removeLast() }
                    var e = Entity(layer: layer, geometry: .polyline(PolylineGeom(points: pts, closed: polygon && pts.count >= 3)), props: props)
                    if let zz = zs {
                        let part = Array(zz[a..<z])
                        if let z0 = part.first, part.allSatisfy({ abs($0 - z0) < 1e-9 }) { if abs(z0) > 1e-12 { e.props["elevation"] = fmt(z0 * 1000 / doc.units.mm, 6) } }
                        else { e.props["vertexZ"] = part.map { fmt($0 * 1000 / doc.units.mm, 4) }.joined(separator: ",") }
                    }
                    out.append(e)
                    if polygon && options.masses, let h = OSMImporter.height(props), pts.count >= 3 {
                        out.append(Entity(layer: layer + "-MASS", geometry: .solid(SolidGeom(kind: .extrusion, origin: .zero, profile: pts, height: h * 1000 / doc.units.mm)), props: props))
                    }
                }
            default: continue // null shapes, multipatch
            }
        }
        return out
    }

    /// Reads name.shp with its .dbf/.prj siblings.
    public static func load(_ url: URL, doc: ArchiDocument, options: GISImportOptions = GISImportOptions()) throws -> [Entity] {
        let base = url.deletingPathExtension()
        func sib(_ ext: String) -> URL? {
            for e in [ext, ext.uppercased()] { let u = base.appendingPathExtension(e); if FileManager.default.fileExists(atPath: u.path) { return u } }
            return nil
        }
        let shp = try Data(contentsOf: url)
        let dbf = sib("dbf").flatMap { try? Data(contentsOf: $0) }
        let prj = sib("prj").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return try entities(shp: shp, dbf: dbf, prj: prj, doc: doc, options: options)
    }
}

// MARK: - OpenStreetMap

public enum OSMImporter {
    /// Building height in metres from OSM tags: height, building:height, or building:levels × 3 m (+ roof).
    public static func height(_ tags: [String: String]) -> Double? {
        func num(_ s: String?) -> Double? {
            guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
            let digits = s.prefix { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
            guard let v = Double(digits) else { return nil }
            if s.hasSuffix("ft") || s.hasSuffix("'") { return v * 0.3048 }
            return v
        }
        if let h = num(tags["height"]) ?? num(tags["building:height"]) ?? num(tags["HEIGHT"]) { return h }
        if let l = num(tags["building:levels"]) ?? num(tags["LEVELS"]) { return l * 3 + (num(tags["roof:height"]) ?? 0) }
        return nil
    }

    /// Buildings (closed ways/multipolygon outers tagged building=*) → closed polylines on OSM-BUILDINGS (optionally
    /// extruded masses), highways → polylines on OSM-ROADS, water/landuse/natural areas → OSM-AREAS.
    public static func entities(_ data: Data, doc: ArchiDocument, options: GISImportOptions = GISImportOptions()) throws -> [Entity] {
        let p = OSMParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse(), !p.nodes.isEmpty else { throw GISImportError.invalid("Not an OpenStreetMap XML file (no nodes).") }
        let origin = options.origin ?? (doc.info.latitude, doc.info.longitude)
        let k = doc.units.mm
        func P(_ id: Int64) -> Vec2? { p.nodes[id].map { GeoJSON.fromLonLat(lon: $0.lon, lat: $0.lat, origin: origin, unitMM: k) } }
        var out: [Entity] = []
        func emit(_ refs: [Int64], _ tags: [String: String], id: Int64) {
            var pts = refs.compactMap(P)
            guard pts.count >= 2 else { return }
            let closed = refs.count > 3 && refs.first == refs.last
            if closed { pts.removeLast() }
            var props = tags.filter { ["name", "building", "highway", "height", "building:levels", "addr:street", "addr:housenumber", "landuse", "natural", "amenity", "surface", "lanes", "width"].contains($0.key) }
            props["osmId"] = "\(id)"
            let layer: String
            if tags["building"] != nil || tags["building:part"] != nil { layer = "OSM-BUILDINGS" }
            else if tags["highway"] != nil { layer = "OSM-ROADS" }
            else if tags["railway"] != nil { layer = "OSM-RAIL" }
            else if tags["waterway"] != nil || tags["natural"] == "water" { layer = "OSM-WATER" }
            else if closed && (tags["landuse"] != nil || tags["natural"] != nil || tags["leisure"] != nil) { layer = "OSM-AREAS" }
            else { return }
            if layer == "OSM-BUILDINGS", let h = height(tags) { props["heightM"] = fmt(h, 2) }
            out.append(Entity(layer: layer, geometry: .polyline(PolylineGeom(points: pts, closed: closed && pts.count >= 3)), props: props))
            if layer == "OSM-BUILDINGS" && options.masses && closed && pts.count >= 3 {
                let h = (height(tags) ?? 9) * 1000 / k
                let minH = (Double(tags["min_height"] ?? "") ?? 0) * 1000 / k
                var poly = pts
                if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
                out.append(Entity(layer: "OSM-MASSES", geometry: .solid(SolidGeom(kind: .extrusion, origin: Vec3(0, 0, minH), profile: poly, height: max(h - minH, 1000 / k))), props: props))
            }
        }
        for w in p.ways { emit(w.refs, w.tags, id: w.id) }
        // Multipolygon relations: outer ways (joined when split) with the relation's tags.
        for r in p.relations where r.tags["type"] == "multipolygon" {
            let outers = r.members.filter { $0.role != "inner" }.compactMap { m in p.ways.first { $0.id == m.ref } }
            var rings: [[Int64]] = []
            var pending = outers.map(\.refs)
            while !pending.isEmpty {
                var ring = pending.removeFirst()
                var grown = true
                while grown && ring.first != ring.last {
                    grown = false
                    for (i, w) in pending.enumerated() {
                        if w.first == ring.last { ring += w.dropFirst(); pending.remove(at: i); grown = true; break }
                        if w.last == ring.last { ring += w.reversed().dropFirst(); pending.remove(at: i); grown = true; break }
                    }
                }
                rings.append(ring)
            }
            for ring in rings { emit(ring, r.tags, id: r.id) }
        }
        return out
    }
}

final class OSMParser: NSObject, XMLParserDelegate {
    struct Way { var id: Int64; var refs: [Int64] = []; var tags: [String: String] = [:] }
    struct Member { var ref: Int64; var role: String }
    struct Relation { var id: Int64; var members: [Member] = []; var tags: [String: String] = [:] }
    var nodes: [Int64: (lat: Double, lon: Double)] = [:]
    var ways: [Way] = []
    var relations: [Relation] = []
    var ctx = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "node":
            if let id = a["id"].flatMap({ Int64($0) }), let la = a["lat"].flatMap(Double.init), let lo = a["lon"].flatMap(Double.init) { nodes[id] = (la, lo) }
            ctx = "node"
        case "way": ways.append(Way(id: a["id"].flatMap { Int64($0) } ?? 0)); ctx = "way"
        case "relation": relations.append(Relation(id: a["id"].flatMap { Int64($0) } ?? 0)); ctx = "relation"
        case "nd": if ctx == "way", let r = a["ref"].flatMap({ Int64($0) }), !ways.isEmpty { ways[ways.count - 1].refs.append(r) }
        case "member":
            if ctx == "relation", a["type"] == "way", let r = a["ref"].flatMap({ Int64($0) }), !relations.isEmpty { relations[relations.count - 1].members.append(Member(ref: r, role: a["role"] ?? "")) }
        case "tag":
            guard let k = a["k"], let v = a["v"] else { return }
            if ctx == "way", !ways.isEmpty { ways[ways.count - 1].tags[k] = v }
            if ctx == "relation", !relations.isEmpty { relations[relations.count - 1].tags[k] = v }
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "node" || name == "way" || name == "relation" { ctx = "" }
    }
}

// MARK: - ESRI ASCII grid

public enum ElevationGrid {
    public struct Grid {
        public var ncols: Int, nrows: Int
        /// Lower-left corner of the lower-left cell (metres / file units).
        public var xll: Double, yll: Double
        public var cell: Double
        public var nodata: Double?
        /// Row-major, first row = northernmost.
        public var values: [Double]
        public func value(col: Int, row: Int) -> Double? {
            let v = values[row * ncols + col]
            if let nd = nodata, abs(v - nd) < 1e-9 { return nil }
            return v.isFinite ? v : nil
        }
    }

    /// Parses an ESRI ASCII grid (.asc): ncols, nrows, xllcorner|xllcenter, yllcorner|yllcenter, cellsize, NODATA_value.
    public static func parse(_ text: String) throws -> Grid {
        var head: [String: Double] = [:]
        var vals: [Double] = []
        var isCenter = false
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let f = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," })
            guard let first = f.first else { continue }
            if let v = Double(first) { vals.append(v); for t in f.dropFirst() { vals.append(Double(t) ?? .nan) }; continue }
            let key = first.lowercased()
            if f.count >= 2, let v = Double(f[1]) { head[key] = v; if key.hasSuffix("center") { isCenter = true } }
        }
        guard let nc = head["ncols"].map(Int.init), let nr = head["nrows"].map(Int.init), nc >= 2, nr >= 2, let cell = head["cellsize"], cell > 0 else {
            throw GISImportError.invalid("Not an ESRI ASCII grid (needs ncols, nrows and cellsize).")
        }
        guard vals.count >= nc * nr else { throw GISImportError.invalid("The grid has \(vals.count) values, expected \(nc * nr).") }
        var xll = head["xllcorner"] ?? head["xllcenter"] ?? 0, yll = head["yllcorner"] ?? head["yllcenter"] ?? 0
        if isCenter { xll -= cell / 2; yll -= cell / 2 }
        return Grid(ncols: nc, nrows: nr, xll: xll, yll: yll, cell: cell, nodata: head["nodata_value"], values: Array(vals.prefix(nc * nr)))
    }

    /// Terrain points (cell centres, drawing units) subsampled to at most `maxPoints`; x/y relative to the grid's
    /// lower-left corner unless `keepCoordinates`.
    public static func points(_ g: Grid, unitMM: Double, maxPoints: Int = 40_000, keepCoordinates: Bool = false) -> [Vec3] {
        let total = g.ncols * g.nrows
        let step = max(1, Int(ceil(sqrt(Double(total) / Double(max(maxPoints, 4))))))
        let k = 1000 / unitMM
        var out: [Vec3] = []
        var rows = Array(stride(from: 0, to: g.nrows, by: step)); if rows.last != g.nrows - 1 { rows.append(g.nrows - 1) }
        var cols = Array(stride(from: 0, to: g.ncols, by: step)); if cols.last != g.ncols - 1 { cols.append(g.ncols - 1) }
        for r in rows {
            for c in cols {
                guard let z = g.value(col: c, row: r) else { continue }
                let x = (Double(c) + 0.5) * g.cell + (keepCoordinates ? g.xll : 0)
                let y = (Double(g.nrows - 1 - r) + 0.5) * g.cell + (keepCoordinates ? g.yll : 0)
                out.append(Vec3(x * k, y * k, z * k))
            }
        }
        return out
    }

    /// Toposurface entity (layer C-TOPO, like TOPO) from a grid.
    public static func topo(_ g: Grid, unitMM: Double, interval: Double? = nil, maxPoints: Int = 40_000, keepCoordinates: Bool = false) throws -> Entity {
        let pts = points(g, unitMM: unitMM, maxPoints: maxPoints, keepCoordinates: keepCoordinates)
        guard pts.count >= 3, let s = Terrain.solid(pts) else { throw GISImportError.invalid("The grid has fewer than three valid cells.") }
        var e = Entity(layer: "C-TOPO", geometry: .solid(s))
        e.props["topo"] = "1"; e.props["material"] = "Grass"
        e.props["contourInterval"] = fmt(interval ?? 1000 / unitMM); e.props["contourMajor"] = "5"
        e.props["gridOrigin"] = "\(fmt(g.xll, 3)),\(fmt(g.yll, 3))"
        return e
    }
}
