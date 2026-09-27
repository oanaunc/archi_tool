// Oanarina Archi Tool — GPL-3.0-or-later
// Portable counterpart of the Mac app's ArchiJSON bridge (ArchiApp/ScriptEngine.swift): converts loose JSON from
// scripts and agents (points as [x, y], missing fields defaulted) into core model types and back, using EngineJSON
// instead of JSONSerialization so it behaves the same on macOS, Windows and Linux. Used by the archi-engine
// `script.call` and `agent.call` methods and its MCP mode.
import Foundation

public enum ScriptJSON {
    public struct BridgeError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }
    public static func fail(_ m: String) -> BridgeError { BridgeError(message: m) }

    // MARK: Codable bridge

    public static func encode<T: Encodable>(_ v: T) -> EngineJSON {
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let d = try? enc.encode(v), let j = try? EngineJSON.parse(String(decoding: d, as: UTF8.self)) else { return .null }
        return j
    }

    public static func decode<T: Decodable>(_ t: T.Type, from j: EngineJSON) throws -> T {
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        do { return try dec.decode(t, from: Data(j.serialized.utf8)) }
        catch let e as DecodingError {
            switch e {
            case .keyNotFound(let k, _): throw fail("missing field '\(k.stringValue)'")
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
                let path = c.codingPath.map { $0.stringValue }.joined(separator: ".")
                throw fail(c.debugDescription + " at " + path)
            @unknown default: throw fail("\(e)")
            }
        }
    }

    // MARK: Small accessors

    public static func double(_ v: EngineJSON?) -> Double? {
        guard let v else { return nil }
        if case .bool = v { return nil }
        return v.doubleValue
    }
    public static func int(_ v: EngineJSON?) -> Int? {
        guard let v else { return nil }
        if case .bool = v { return nil }
        return v.intValue
    }
    public static func string(_ v: EngineJSON?) -> String? {
        guard let v, case .string(let s) = v else { return nil }
        return s
    }
    public static func bool(_ v: EngineJSON?) -> Bool? {
        guard let v, case .bool(let b) = v else { return nil }
        return b
    }
    public static func ids(_ v: EngineJSON?) -> [EntityID] {
        if let n = int(v) { return [n] }
        return (v?.arrayValue ?? []).compactMap { int($0) }
    }
    public static func point(_ v: EngineJSON?) -> Vec2? { v?.vec2 }
    public static func points(_ v: EngineJSON?) -> [Vec2] { (v?.arrayValue ?? []).compactMap { $0.vec2 } }
    public static func stringDict(_ v: EngineJSON?) -> [String: String] {
        var out: [String: String] = [:]
        for f in v?.fields ?? [] {
            switch f.value {
            case .string(let s): out[f.key] = s
            case .bool(let b): out[f.key] = b ? "true" : "false"
            case .null: continue
            default: out[f.key] = f.value.stringValue ?? f.value.serialized
            }
        }
        return out
    }
    public static func object(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
        .object(pairs.map { EngineJSONField($0.0, $0.1) })
    }
    public static func field(_ j: EngineJSON, _ key: String) -> EngineJSON? { j[key] }
    public static func setting(_ j: EngineJSON, _ key: String, _ value: EngineJSON) -> EngineJSON {
        var f = j.fields ?? []
        if let i = f.firstIndex(where: { $0.key == key }) { f[i].value = value } else { f.append(EngineJSONField(key, value)) }
        return .object(f)
    }
    public static func removing(_ j: EngineJSON, _ key: String) -> EngineJSON {
        .object((j.fields ?? []).filter { $0.key != key })
    }

    // MARK: Normalisation

    static let plainNumberArrays: Set<String> = ["knots", "weights", "columnWidths", "meshTriangles", "cells", "dash", "pattern"]

    static func isNumber(_ v: EngineJSON) -> Bool { if case .number = v { return true }; return false }

    /// Turns `[x, y]` / `[x, y, z]` arrays into `{x, y(, z)}` objects, recursively.
    public static func normalize(_ v: EngineJSON, key: String? = nil) -> EngineJSON {
        if let k = key, plainNumberArrays.contains(k) { return v }
        switch v {
        case .array(let a):
            if (2...3).contains(a.count), a.allSatisfy(isNumber) {
                let n = a.map { $0.doubleValue ?? 0 }
                if n.count == 2 { return object([("x", .number(n[0])), ("y", .number(n[1]))]) }
                return object([("x", .number(n[0])), ("y", .number(n[1])), ("z", .number(n[2]))])
            }
            return .array(a.map { normalize($0, key: key) })
        case .object(let f):
            return .object(f.map { EngineJSONField($0.key, normalize($0.value, key: $0.key)) })
        default:
            return v
        }
    }

    /// Polyline vertices may be points (`{x,y}`, `[x,y]`, `[x,y,bulge]`) or `{p, bulge}`.
    static func vertices(_ v: EngineJSON) -> EngineJSON {
        guard let a = v.arrayValue else { return v }
        var out: [EngineJSON] = []
        for item in a {
            guard item.fields != nil else { out.append(item); continue }
            if item["p"] != nil {
                out.append(item["bulge"] == nil ? setting(item, "bulge", .number(0)) : item)
            } else if let x = item["x"], let y = item["y"] {
                let bulge = item["bulge"] ?? item["z"] ?? .number(0)
                out.append(object([("p", object([("x", x), ("y", y)])), ("bulge", bulge)]))
            } else {
                out.append(item)
            }
        }
        return .array(out)
    }

    static func geometryDefault(_ t: String) -> Geometry? {
        switch t {
        case "point": return .point(.zero)
        case "line": return .line(LineGeom(.zero, .zero))
        case "circle": return .circle(CircleGeom(.zero, 1))
        case "arc": return .arc(ArcGeom(.zero, 1, 0, .pi))
        case "ellipse": return .ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(1, 0), ratio: 0.5))
        case "polyline": return .polyline(PolylineGeom([]))
        case "spline": return .spline(SplineGeom(controlPoints: []))
        case "text": return .text(TextGeom(position: .zero, height: 250, content: ""))
        case "dimension": return .dimension(DimensionGeom(kind: .linear, points: []))
        case "hatch": return .hatch(HatchGeom(loops: []))
        case "insert": return .insert(InsertGeom(block: "", position: .zero))
        case "leader": return .leader(LeaderGeom(points: [], text: ""))
        case "image": return .image(ImageGeom(path: "", origin: .zero, size: Vec2(1000, 1000)))
        case "table": return .table(TableGeom(origin: .zero, columnWidths: [], rowHeight: 500, cells: []))
        case "solid": return .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000)))
        default: return nil
        }
    }

    static func elementDefault(_ t: String) -> BIMGeometry? {
        switch t {
        case "wall": return .wall(WallGeom(start: .zero, end: .zero))
        case "slab": return .slab(SlabGeom(boundary: []))
        case "column": return .column(ColumnGeom(position: .zero))
        case "beam": return .beam(BeamGeom(start: .zero, end: .zero))
        case "door": return .opening(OpeningGeom(kind: .door, hostWall: 0, offset: 0, width: 900, height: 2100))
        case "window": return .opening(OpeningGeom(kind: .window, hostWall: 0, offset: 0, width: 1200, height: 1200, sill: 900))
        case "opening": return .opening(OpeningGeom(kind: .opening, hostWall: 0, offset: 0, width: 900, height: 2100))
        case "roof": return .roof(RoofGeom(boundary: []))
        case "stair": return .stair(StairGeom(start: .zero))
        case "railing": return .railing(RailingGeom(path: []))
        case "space": return .space(SpaceGeom(boundary: []))
        case "curtainWall": return .curtainWall(CurtainWallGeom(start: .zero, end: .zero))
        case "component": return .component(ComponentGeom(position: .zero))
        case "grid": return .gridLine(GridLineGeom(start: .zero, end: .zero, label: "A"))
        default: return nil
        }
    }

    static let typeAliases = ["pline": "polyline", "lwpolyline": "polyline", "mtext": "text", "room": "space", "gridline": "grid",
                              "curtainwall": "curtainWall", "block": "insert", "box": "solid"]

    static func canonicalType(_ t: String) -> String { typeAliases[t.lowercased()] ?? t }

    static func mergedWithDefaults(_ raw: EngineJSON, defaults: (String) -> EngineJSON?) throws -> EngineJSON {
        guard let t0 = string(raw["type"]) else { throw fail("object needs a \"type\"") }
        let type = canonicalType(t0)
        guard let def = defaults(type), let defFields = def.fields else { throw fail("unknown type \"\(type)\"") }
        var d = normalize(raw)
        if let dt = def["type"] { d = setting(d, "type", dt) }
        if type == "polyline", d["vertices"] == nil, let pts = d["points"] { d = setting(d, "vertices", pts) }
        if type == "text", d["content"] == nil, let t = d["text"] { d = setting(d, "content", t) }
        if let v = d["vertices"] { d = setting(d, "vertices", vertices(v)) }
        if let loops = d["loops"]?.arrayValue { d = setting(d, "loops", .array(loops.map { vertices($0) })) }
        var out = EngineJSON.object(defFields)
        for f in d.fields ?? [] { out = setting(out, f.key, f.value) }
        return out
    }

    public static func geometry(from raw: EngineJSON) throws -> Geometry {
        let m = try mergedWithDefaults(raw) { t in geometryDefault(t).map { encode($0) } }
        return try decode(Geometry.self, from: m)
    }

    public static func bimGeometry(from raw: EngineJSON) throws -> BIMGeometry {
        let m = try mergedWithDefaults(raw) { t in elementDefault(t).map { encode($0) } }
        return try decode(BIMGeometry.self, from: m)
    }

    /// An entity from `{type, ...geometry}` or `{geometry: {...}, layer, color, linetype, lineweight, props}`.
    public static func entity(from d: EngineJSON, doc: ArchiDocument) throws -> Entity {
        guard d.fields != nil else { throw fail("entity must be an object") }
        let gsrc: EngineJSON = (d["geometry"]?.fields != nil) ? d["geometry"]! : d
        let g = try geometry(from: gsrc)
        var e = Entity(layer: string(d["layer"]) ?? doc.currentLayer, geometry: g)
        if let c = d["color"], !c.isNull { e.color = ColorRef.parse(c.stringValue ?? "") ?? .byLayer }
        e.linetype = string(d["linetype"])
        e.lineweight = double(d["lineweight"])
        e.props = stringDict(d["props"])
        return e
    }

    public struct ElementSpec {
        public var geometry: BIMGeometry
        public var level: Int?
        public var layer: String?
        public var material: String?
        public var name: String
        public var props: [String: String]
    }

    public static func element(from d: EngineJSON, doc: ArchiDocument) throws -> ElementSpec {
        guard d.fields != nil else { throw fail("element must be an object") }
        let gsrc: EngineJSON = (d["geometry"]?.fields != nil) ? d["geometry"]! : d
        let g = try bimGeometry(from: gsrc)
        if case .opening(let o) = g {
            guard let host = doc.element(o.hostWall), case .wall = host.geometry else { throw fail("hostWall \(o.hostWall) is not a wall") }
        }
        let level = int(d["level"])
        if let l = level, doc.level(l) == nil { throw fail("level \(l) does not exist") }
        return ElementSpec(geometry: g, level: level, layer: string(d["layer"]), material: string(d["material"]),
                           name: string(d["name"]) ?? "", props: stringDict(d["props"]))
    }

    @discardableResult
    public static func add(_ s: ElementSpec, to doc: inout ArchiDocument) -> EntityID {
        let id = doc.addElement(s.geometry, level: s.level, layer: s.layer, material: s.material, name: s.name)
        if !s.props.isEmpty, let i = doc.elementIndex(id) { doc.elements[i].props = s.props }
        return id
    }

    /// Applies a patch to an entity or element. Top-level keys other than the object's own properties are geometry fields.
    public static func patch(_ doc: inout ArchiDocument, id: EntityID, _ p: EngineJSON) throws {
        let fields = p.fields ?? []
        if let i = doc.entityIndex(id) {
            var e = doc.entities[i]
            var g = encode(e.geometry)
            var gChanged = false
            for f in fields {
                let v = f.value
                switch f.key {
                case "id": continue
                case "layer": if let s = string(v) { doc.ensureLayer(s); e.layer = s }
                case "color": e.color = ColorRef.parse(v.stringValue ?? "") ?? e.color
                case "linetype": e.linetype = v.isNull ? nil : string(v)
                case "lineweight": e.lineweight = double(v)
                case "props": for (pk, pv) in stringDict(v) { e.props[pk] = pv }
                case "geometry":
                    if let gd = v.fields { for gf in gd { g = setting(g, gf.key, gf.value) }; gChanged = true }
                default: g = setting(g, f.key, v); gChanged = true
                }
            }
            if gChanged { e.geometry = try geometry(from: g) }
            doc.entities[i] = e
        } else if let i = doc.elementIndex(id) {
            var el = doc.elements[i]
            var g = encode(el.geometry)
            var gChanged = false
            for f in fields {
                let v = f.value
                switch f.key {
                case "id": continue
                case "level":
                    if let l = int(v) {
                        guard doc.level(l) != nil else { throw fail("level \(l) does not exist") }
                        el.level = l
                    }
                case "name": el.name = v.stringValue ?? ""
                case "layer": if let s = string(v) { doc.ensureLayer(s); el.layer = s }
                case "material": el.material = v.isNull ? nil : string(v)
                case "props": for (pk, pv) in stringDict(v) { el.props[pk] = pv }
                case "geometry":
                    if let gd = v.fields { for gf in gd { g = setting(g, gf.key, gf.value) }; gChanged = true }
                default: g = setting(g, f.key, v); gChanged = true
                }
            }
            if gChanged { el.geometry = try bimGeometry(from: g) }
            doc.elements[i] = el
        } else {
            throw fail("no object with id \(id)")
        }
    }

    public static func entities(_ doc: ArchiDocument, type: String?, layer: String?) -> [EngineJSON] {
        let t = type.map { canonicalType($0).lowercased() }
        var out: [EngineJSON] = []
        for e in doc.entities {
            if let t, e.typeName.lowercased() != t { continue }
            if let layer, e.layer.caseInsensitiveCompare(layer) != .orderedSame { continue }
            out.append(encode(e))
        }
        return out
    }

    public static func elements(_ doc: ArchiDocument, type: String?, level: Int?) -> [EngineJSON] {
        let t = type.map { canonicalType($0) }
        var out: [EngineJSON] = []
        for e in doc.elements {
            if let t, e.typeName.caseInsensitiveCompare(t) != .orderedSame { continue }
            if let level, e.level != level { continue }
            out.append(encode(e))
        }
        return out
    }

    /// The whole document as .archi JSON (the `document` member of the file).
    public static func documentJSON(_ doc: ArchiDocument) -> EngineJSON {
        guard let d = try? ArchiFile.encode(doc), let j = try? EngineJSON.parse(String(decoding: d, as: UTF8.self)) else { return encode(doc) }
        return j["document"] ?? j
    }

    public static func summary(_ doc: ArchiDocument) -> EngineJSON {
        var byType: [String: Int] = [:]
        for e in doc.entities { byType[e.typeName, default: 0] += 1 }
        var byElement: [String: Int] = [:]
        for e in doc.elements { byElement[e.typeName, default: 0] += 1 }
        let b = GeometryOps.bounds(of: doc)
        var levels: [EngineJSON] = []
        for l in doc.levels {
            levels.append(object([("id", .int(l.id)), ("name", .string(l.name)), ("elevation", .number(l.elevation)), ("height", .number(l.height))]))
        }
        var o = EngineObject()
        o.set("project", encode(doc.info))
        o.set("units", doc.units.rawValue)
        o.set("currentLayer", doc.currentLayer)
        o.set("currentLevel", doc.currentLevel)
        o.set("layers", EngineJSON.strings(doc.layers.map { $0.name }))
        o.set("levels", .array(levels))
        o.set("entityCount", doc.entities.count)
        o.set("entitiesByType", counts(byType))
        o.set("elementCount", doc.elements.count)
        o.set("elementsByType", counts(byElement))
        o.set("layouts", EngineJSON.strings(doc.layouts.map { $0.name }))
        o.set("materials", EngineJSON.strings(doc.materials.map { $0.name }))
        o.set("wallTypes", EngineJSON.strings(doc.wallTypes.map { $0.name }))
        if b.isEmpty { o.set("bounds", .null) }
        else { o.set("bounds", object([("min", .point(b.min)), ("max", .point(b.max))])) }
        return o.json
    }

    static func counts(_ d: [String: Int]) -> EngineJSON {
        .object(d.keys.sorted().map { EngineJSONField($0, .int(d[$0] ?? 0)) })
    }

    // MARK: Any bridge (AgentTools / AgentResources use [String: Any])

    /// Swift/Foundation values (native or NSNumber) to EngineJSON.
    public static func fromAny(_ v: Any?) -> EngineJSON {
        guard let v else { return .null }
        if v is NSNull { return .null }
        if let s = v as? String { return .string(s) }
        if type(of: v) == Bool.self, let b = v as? Bool { return .bool(b) }
        if let i = v as? Int, type(of: v) == Int.self { return .int(i) }
        if let d = v as? Double, type(of: v) == Double.self { return .number(d) }
        if let n = v as? NSNumber {
            if isBoolean(n) { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        }
        if let d = v as? [String: Any] {
            return .object(d.keys.sorted().map { EngineJSONField($0, fromAny(d[$0])) })
        }
        if let a = v as? [Any] { return .array(a.map { fromAny($0) }) }
        if let a = v as? [[String: Any]] { return .array(a.map { fromAny($0) }) }
        if let a = v as? [String] { return EngineJSON.strings(a) }
        if let a = v as? [Int] { return EngineJSON.ints(a) }
        if let a = v as? [Double] { return EngineJSON.numbers(a) }
        if let f = v as? Float { return .number(Double(f)) }
        if let i = v as? Int64 { return .number(Double(i)) }
        if let u = v as? UInt64 { return .number(Double(u)) }
        return .string("\(v)")
    }

    static func isBoolean(_ n: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFGetTypeID(n) == CFBooleanGetTypeID()
        #else
        let t = String(cString: n.objCType)
        return t == "c" || t == "B"
        #endif
    }

    /// EngineJSON to Foundation values (numbers as NSNumber, so `as? NSNumber` and `as? Double` both work).
    public static func toAny(_ j: EngineJSON) -> Any {
        switch j {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d):
            if d == d.rounded(), abs(d) < 9e15 { return NSNumber(value: Int(d)) }
            return NSNumber(value: d)
        case .string(let s): return s
        case .array(let a): return a.map { toAny($0) }
        case .object(let f):
            var out: [String: Any] = [:]
            for e in f { out[e.key] = toAny(e.value) }
            return out
        }
    }

    public static func toDict(_ j: EngineJSON?) -> [String: Any] { (j.map { toAny($0) } as? [String: Any]) ?? [:] }
}
