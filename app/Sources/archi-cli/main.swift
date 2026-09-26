// Oanarina Archi Tool command-line runner — GPL-3.0-or-later
//
// archi-cli [file.archi|.dxf|.dwg|.ifc|.ifczip|.svg|.obj|.stl|.3mf|.gltf|.glb|.ply|.off|.amf|.step|.geojson|.shp|.osm|.asc|.xlsx|.csv|.xyz|.pts]
//           [--script file.scr] [--out file.<format>] [--mcp] [--convert FORMAT files… [--outdir DIR]]
// Headless: uses ArchiCore only. See docs/AGENT-API.md.
import Foundation
import ArchiCore

setvbuf(stdout, nil, _IOLBF, 0)

let cliVersion = "1.0"

func eprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

// MARK: - JSON bridge
// NOTE: kept in sync with `ArchiJSON` in app/Sources/ArchiApp/ScriptEngine.swift (the CLI cannot import the app target).

/// Converts between loose JSON (from scripts/agents) and core model types.
/// Geometry objects use the `.archi` Codable format; missing fields get defaults and points may be `[x, y]`.
enum ArchiJSON {
    struct BridgeError: Error, LocalizedError { let message: String; var errorDescription: String? { message } }
    static func fail(_ m: String) -> BridgeError { BridgeError(message: m) }

    static func object<T: Encodable>(_ v: T) -> Any {
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let d = try? enc.encode(v), let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) else { return NSNull() }
        return o
    }

    static func decode<T: Decodable>(_ t: T.Type, from obj: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed])
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        do { return try dec.decode(t, from: data) }
        catch let e as DecodingError {
            switch e {
            case .keyNotFound(let k, _): throw fail("missing field '\(k.stringValue)'")
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
                throw fail("\(c.debugDescription) at \(c.codingPath.map { $0.stringValue }.joined(separator: "."))")
            @unknown default: throw fail("\(e)")
            }
        }
    }

    static func jsonString(_ obj: Any, pretty: Bool = false) -> String {
        guard JSONSerialization.isValidJSONObject(obj) || obj is String || obj is NSNumber || obj is NSNull,
              let d = try? JSONSerialization.data(withJSONObject: obj, options: pretty ? [.fragmentsAllowed, .prettyPrinted, .sortedKeys] : [.fragmentsAllowed, .sortedKeys]) else { return "\(obj)" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    // MARK: Normalisation

    static let plainNumberArrays: Set<String> = ["knots", "weights", "columnWidths", "meshTriangles", "cells", "dash", "pattern"]

    static func isNumber(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) != CFBooleanGetTypeID()
    }

    /// Turns `[x, y]` / `[x, y, z]` arrays into `{x, y(, z)}` objects, recursively.
    static func normalize(_ v: Any, key: String? = nil) -> Any {
        if let k = key, plainNumberArrays.contains(k) { return v }
        if let a = v as? [Any] {
            if (2...3).contains(a.count), a.allSatisfy(isNumber) {
                let n = a.map { ($0 as! NSNumber).doubleValue }
                return n.count == 2 ? ["x": n[0], "y": n[1]] : ["x": n[0], "y": n[1], "z": n[2]]
            }
            return a.map { normalize($0, key: key) }
        }
        if let d = v as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, x) in d { out[k] = normalize(x, key: k) }
            return out
        }
        return v
    }

    /// Polyline vertices may be points (`{x,y}`, `[x,y]`, `[x,y,bulge]`) or `{p, bulge}`.
    static func vertices(_ v: Any) -> Any {
        guard let a = v as? [Any] else { return v }
        return a.map { item -> Any in
            guard let d = item as? [String: Any] else { return item }
            if d["p"] != nil { var o = d; if o["bulge"] == nil { o["bulge"] = 0 }; return o }
            if let x = d["x"], let y = d["y"] { return ["p": ["x": x, "y": y], "bulge": d["bulge"] ?? d["z"] ?? 0] }
            return item
        }
    }

    static let geometryDefaults: [String: Geometry] = [
        "point": .point(.zero), "line": .line(LineGeom(.zero, .zero)), "circle": .circle(CircleGeom(.zero, 1)),
        "arc": .arc(ArcGeom(.zero, 1, 0, .pi)), "ellipse": .ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(1, 0), ratio: 0.5)),
        "polyline": .polyline(PolylineGeom([])), "spline": .spline(SplineGeom(controlPoints: [])),
        "text": .text(TextGeom(position: .zero, height: 250, content: "")), "dimension": .dimension(DimensionGeom(kind: .linear, points: [])),
        "hatch": .hatch(HatchGeom(loops: [])), "insert": .insert(InsertGeom(block: "", position: .zero)),
        "leader": .leader(LeaderGeom(points: [], text: "")), "image": .image(ImageGeom(path: "", origin: .zero, size: Vec2(1000, 1000))),
        "table": .table(TableGeom(origin: .zero, columnWidths: [], rowHeight: 500, cells: [])),
        "solid": .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))),
    ]
    static let elementDefaults: [String: BIMGeometry] = [
        "wall": .wall(WallGeom(start: .zero, end: .zero)), "slab": .slab(SlabGeom(boundary: [])), "column": .column(ColumnGeom(position: .zero)),
        "beam": .beam(BeamGeom(start: .zero, end: .zero)),
        "door": .opening(OpeningGeom(kind: .door, hostWall: 0, offset: 0, width: 900, height: 2100)),
        "window": .opening(OpeningGeom(kind: .window, hostWall: 0, offset: 0, width: 1200, height: 1200, sill: 900)),
        "opening": .opening(OpeningGeom(kind: .opening, hostWall: 0, offset: 0, width: 900, height: 2100)),
        "roof": .roof(RoofGeom(boundary: [])), "stair": .stair(StairGeom(start: .zero)), "railing": .railing(RailingGeom(path: [])),
        "space": .space(SpaceGeom(boundary: [])), "curtainWall": .curtainWall(CurtainWallGeom(start: .zero, end: .zero)),
        "component": .component(ComponentGeom(position: .zero)), "grid": .gridLine(GridLineGeom(start: .zero, end: .zero, label: "A")),
    ]
    static let typeAliases = ["pline": "polyline", "lwpolyline": "polyline", "mtext": "text", "room": "space", "gridline": "grid",
                              "curtainwall": "curtainWall", "block": "insert", "box": "solid"]

    static func mergedWithDefaults(_ raw: [String: Any], defaults: (String) -> Any?) throws -> [String: Any] {
        guard var type = raw["type"] as? String else { throw fail("object needs a \"type\"") }
        type = typeAliases[type.lowercased()] ?? type
        guard let def = defaults(type) as? [String: Any] else { throw fail("unknown type \"\(type)\"") }
        var d = normalize(raw) as! [String: Any]
        d["type"] = def["type"]
        if type == "polyline", d["vertices"] == nil, let pts = d["points"] { d["vertices"] = pts }
        if type == "text", d["content"] == nil, let t = d["text"] { d["content"] = t }
        if let v = d["vertices"] { d["vertices"] = vertices(v) }
        if let loops = d["loops"] as? [Any] { d["loops"] = loops.map { vertices($0) } }
        var out = def
        for (k, v) in d { out[k] = v }
        return out
    }

    static func geometry(from raw: [String: Any]) throws -> Geometry {
        let m = try mergedWithDefaults(raw) { t in geometryDefaults[t].map { object($0) } }
        return try decode(Geometry.self, from: m)
    }

    static func bimGeometry(from raw: [String: Any]) throws -> BIMGeometry {
        let m = try mergedWithDefaults(raw) { t in elementDefaults[t].map { object($0) } }
        return try decode(BIMGeometry.self, from: m)
    }

    static func stringDict(_ v: Any?) -> [String: String] {
        guard let d = v as? [String: Any] else { return [:] }
        return d.mapValues { "\($0)" }
    }
    static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? String).flatMap(Int.init) }
    static func ids(_ v: Any?) -> [EntityID] {
        if let n = int(v) { return [n] }
        return (v as? [Any])?.compactMap { int($0) } ?? []
    }
    static func point(_ v: Any?) -> Vec2? {
        if let a = v as? [Any], a.count >= 2, let x = double(a[0]), let y = double(a[1]) { return Vec2(x, y) }
        if let d = v as? [String: Any], let x = double(d["x"]), let y = double(d["y"]) { return Vec2(x, y) }
        return nil
    }
    static func points(_ v: Any?) -> [Vec2] { (v as? [Any])?.compactMap { point($0) } ?? [] }

    /// An entity from `{type, ...geometry}` or `{geometry: {...}, layer, color, linetype, lineweight, props}`.
    static func entity(from obj: Any, doc: ArchiDocument) throws -> Entity {
        guard let d = obj as? [String: Any] else { throw fail("entity must be an object") }
        let g = try geometry(from: (d["geometry"] as? [String: Any]) ?? d)
        var e = Entity(layer: d["layer"] as? String ?? doc.currentLayer, geometry: g)
        if let c = d["color"] { e.color = ColorRef.parse("\(c)") ?? .byLayer }
        e.linetype = d["linetype"] as? String
        e.lineweight = double(d["lineweight"])
        e.props = stringDict(d["props"])
        return e
    }

    struct ElementSpec { var geometry: BIMGeometry; var level: Int?; var layer: String?; var material: String?; var name: String; var props: [String: String] }

    static func element(from obj: Any, doc: ArchiDocument) throws -> ElementSpec {
        guard let d = obj as? [String: Any] else { throw fail("element must be an object") }
        let g = try bimGeometry(from: (d["geometry"] as? [String: Any]) ?? d)
        if case .opening(let o) = g {
            guard let host = doc.element(o.hostWall), case .wall = host.geometry else { throw fail("hostWall \(o.hostWall) is not a wall") }
        }
        let level = int(d["level"])
        if let l = level, doc.level(l) == nil { throw fail("level \(l) does not exist") }
        return ElementSpec(geometry: g, level: level, layer: d["layer"] as? String, material: d["material"] as? String,
                           name: d["name"] as? String ?? "", props: stringDict(d["props"]))
    }

    @discardableResult
    static func add(_ s: ElementSpec, to doc: inout ArchiDocument) -> EntityID {
        let id = doc.addElement(s.geometry, level: s.level, layer: s.layer, material: s.material, name: s.name)
        if !s.props.isEmpty, let i = doc.elementIndex(id) { doc.elements[i].props = s.props }
        return id
    }

    /// Applies a patch to an entity or element. Top-level keys other than the object's own
    /// properties are treated as geometry fields.
    static func patch(_ doc: inout ArchiDocument, id: EntityID, _ p: [String: Any]) throws {
        if let i = doc.entityIndex(id) {
            var e = doc.entities[i]
            var g = object(e.geometry) as? [String: Any] ?? [:]
            var gChanged = false
            for (k, v) in p {
                switch k {
                case "id": continue
                case "layer": if let s = v as? String { doc.ensureLayer(s); e.layer = s }
                case "color": e.color = ColorRef.parse("\(v)") ?? e.color
                case "linetype": e.linetype = v is NSNull ? nil : v as? String
                case "lineweight": e.lineweight = double(v)
                case "props": for (pk, pv) in stringDict(v) { e.props[pk] = pv }
                case "geometry": if let gd = v as? [String: Any] { for (gk, gv) in gd { g[gk] = gv }; gChanged = true }
                default: g[k] = v; gChanged = true
                }
            }
            if gChanged { e.geometry = try geometry(from: g) }
            doc.entities[i] = e
        } else if let i = doc.elementIndex(id) {
            var el = doc.elements[i]
            var g = object(el.geometry) as? [String: Any] ?? [:]
            var gChanged = false
            for (k, v) in p {
                switch k {
                case "id": continue
                case "level": if let l = int(v) { guard doc.level(l) != nil else { throw fail("level \(l) does not exist") }; el.level = l }
                case "name": el.name = "\(v)"
                case "layer": if let s = v as? String { doc.ensureLayer(s); el.layer = s }
                case "material": el.material = v is NSNull ? nil : v as? String
                case "props": for (pk, pv) in stringDict(v) { el.props[pk] = pv }
                case "geometry": if let gd = v as? [String: Any] { for (gk, gv) in gd { g[gk] = gv }; gChanged = true }
                default: g[k] = v; gChanged = true
                }
            }
            if gChanged { el.geometry = try bimGeometry(from: g) }
            doc.elements[i] = el
        } else {
            throw fail("no object with id \(id)")
        }
    }

    static func entities(_ doc: ArchiDocument, type: String?, layer: String?) -> [Any] {
        let t = type.map { typeAliases[$0.lowercased()] ?? $0.lowercased() }
        return doc.entities.filter { e in
            (t == nil || e.typeName == t) && (layer == nil || e.layer.caseInsensitiveCompare(layer!) == .orderedSame)
        }.map { object($0) }
    }

    static func elements(_ doc: ArchiDocument, type: String?, level: Int?) -> [Any] {
        let t = type.map { typeAliases[$0.lowercased()] ?? $0 }
        return doc.elements.filter { e in
            (t == nil || e.typeName.caseInsensitiveCompare(t!) == .orderedSame) && (level == nil || e.level == level)
        }.map { object($0) }
    }

    static func documentJSON(_ doc: ArchiDocument) -> Any {
        guard let d = try? ArchiFile.encode(doc), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return object(doc) }
        return o["document"] ?? o
    }

    static func summary(_ doc: ArchiDocument) -> [String: Any] {
        var byType: [String: Int] = [:]
        for e in doc.entities { byType[e.typeName, default: 0] += 1 }
        var byElement: [String: Int] = [:]
        for e in doc.elements { byElement[e.typeName, default: 0] += 1 }
        let b = GeometryOps.bounds(of: doc)
        return [
            "project": object(doc.info), "units": doc.units.rawValue, "currentLayer": doc.currentLayer, "currentLevel": doc.currentLevel,
            "layers": doc.layers.map { $0.name }, "levels": doc.levels.map { ["id": $0.id, "name": $0.name, "elevation": $0.elevation, "height": $0.height] },
            "entityCount": doc.entities.count, "entitiesByType": byType, "elementCount": doc.elements.count, "elementsByType": byElement,
            "layouts": doc.layouts.map { $0.name }, "materials": doc.materials.map { $0.name }, "wallTypes": doc.wallTypes.map { $0.name },
            "bounds": b.isEmpty ? NSNull() : ["min": [b.min.x, b.min.y], "max": [b.max.x, b.max.y]] as Any,
        ]
    }
}


// MARK: - Files

enum CLIError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

func expand(_ path: String) -> URL {
    let p = (path as NSString).expandingTildeInPath
    return p.hasPrefix("/") ? URL(fileURLWithPath: p) : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(p)
}

func loadDocument(_ url: URL) throws -> ArchiDocument { try DocumentIO.read(url) }

/// Writes the document; the format comes from `format` or the file extension (see DocumentIO.write).
func writeDocument(_ doc: ArchiDocument, to url: URL, format: String? = nil, level: Int? = nil) throws {
    try DocumentIO.write(doc, to: url, format: format, level: level)
}

/// Handles host actions (SAVE, EXPORT, OPEN…) requested by commands when running headless.
final class CLIHost: EditorHost {
    func perform(_ action: HostAction, editor: Editor) {
        MainActor.assumeIsolated {
            do {
                switch action {
                case .save(let p), .saveAs(let p):
                    guard let url = p.map(expand) ?? editor.fileURL else { editor.print("No file name: use SAVEAS <path>."); return }
                    try writeDocument(editor.doc, to: url, format: "archi")
                    editor.fileURL = url; editor.isDirty = false
                    editor.print("Saved \(url.path)")
                case .export(let format, let p):
                    guard let p else { editor.print("Export needs a path."); return }
                    let url = expand(p)
                    try writeDocument(editor.doc, to: url, format: format)
                    editor.print("Exported \(url.path)")
                case .open(let p):
                    guard let p else { editor.print("Open needs a path."); return }
                    let url = expand(p)
                    editor.replaceDocument(try loadDocument(url), url: url)
                    editor.print("Opened \(url.path)")
                case .newDocument:
                    editor.replaceDocument(ArchiDocument(), url: nil)
                case .message(let m):
                    editor.print(m)
                default:
                    break // view-only actions are meaningless headless
                }
            } catch {
                editor.print("Error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - MCP server (stdio, newline-delimited JSON-RPC 2.0)

@MainActor
final class MCPServer {
    let ed: Editor
    var path: URL?
    init(editor: Editor, path: URL?) { ed = editor; self.path = path }

    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static func schema(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        var s: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { s["required"] = required }
        return s
    }

    lazy var tools: [[String: Any]] = baseTools + AgentTools.definitions + AgentExtraTools.mutatingDefinitions + [MCPServer.batchTool]

    static let batchTool: [String: Any] = ["name": "run_batch", "title": "Run batch jobs",
        "description": "Runs batch jobs headless (each on its own document): open or import files, run command lines or a .scr script, write outputs in any export format, write tool reports (JSON/CSV) and save. Pass `path` to a jobs JSON file or `jobs` inline: [{\"input\":\"a.archi\",\"commands\":[\"WALL 0,0 5000,0 \"],\"outputs\":[\"a.dxf\",{\"path\":\"a.ifc\"}],\"reports\":[{\"tool\":\"takeoff\",\"path\":\"q.csv\",\"arguments\":{\"format\":\"csv\"}}],\"save\":\"out.archi\"}]. The open document is not changed.",
        "inputSchema": MCPServer.schema(["path": ["type": "string"], "jobs": ["type": "array", "items": ["type": "object"]], "stopOnError": ["type": "boolean"]])]

    let baseTools: [[String: Any]] = [
        ["name": "run_command", "title": "Run command",
         "description": "Runs one or more AutoCAD-style command lines (newline-separated) against the document, e.g. \"LINE 0,0 1000,0 \" or \"WALL 0,0 5000,0 \". Unanswered prompts get Enter. Returns the command log (the last `maxLines` lines when long). With a progressToken in _meta, every log line is also streamed as a notifications/progress message while the commands run (and as notifications/message when logging is enabled).",
         "inputSchema": MCPServer.schema(["command": ["type": "string", "description": "Command line(s)"], "maxLines": ["type": "integer", "description": "Return at most this many (last) log lines; default 500"]], required: ["command"])],
        ["name": "get_document_summary", "title": "Document summary",
         "description": "Project info, units, layers, levels, entity/element counts by type and model bounds.", "inputSchema": MCPServer.schema([:])],
        ["name": "get_document", "title": "Full document", "description": "The whole document as .archi JSON (can be large).", "inputSchema": MCPServer.schema([:])],
        ["name": "list_entities", "title": "List entities",
         "description": "2D/3D drafting entities (line, circle, arc, polyline, text, dimension, hatch, insert, solid…) with geometry.",
         "inputSchema": MCPServer.schema(["type": ["type": "string"], "layer": ["type": "string"], "limit": ["type": "integer"]])],
        ["name": "list_elements", "title": "List BIM elements",
         "description": "Building elements (wall, slab, column, beam, door, window, roof, stair, railing, space, curtainWall, component, grid).",
         "inputSchema": MCPServer.schema(["type": ["type": "string"], "level": ["type": "integer"]])],
        ["name": "add_entity", "title": "Add entity",
         "description": "Adds drafting entities. Geometry uses the .archi JSON format with a \"type\"; points may be [x,y]. Example: {\"type\":\"line\",\"a\":[0,0],\"b\":[1000,0],\"layer\":\"0\"}. Pass an array to add several. Units are millimetres, angles radians.",
         "inputSchema": MCPServer.schema(["entity": ["description": "Entity object or array of objects"]], required: ["entity"])],
        ["name": "add_element", "title": "Add BIM element",
         "description": "Adds building elements, e.g. {\"type\":\"wall\",\"start\":[0,0],\"end\":[5000,0],\"thickness\":200,\"height\":3000} or {\"type\":\"door\",\"hostWall\":12,\"offset\":1500,\"width\":900}. Optional level, layer, material, name, props.",
         "inputSchema": MCPServer.schema(["element": ["description": "Element object or array of objects"]], required: ["element"])],
        ["name": "update_entity", "title": "Update entity or element",
         "description": "Patches an entity/element by id. Keys: layer, color, linetype, lineweight, props, level, name, material, geometry, or any geometry field directly.",
         "inputSchema": MCPServer.schema(["id": ["type": "integer"], "patch": ["type": "object"]], required: ["id", "patch"])],
        ["name": "delete", "title": "Delete", "description": "Deletes entities/elements by id (hosted doors/windows go with their wall).",
         "inputSchema": MCPServer.schema(["ids": ["type": "array", "items": ["type": "integer"]]], required: ["ids"])],
        ["name": "save", "title": "Save", "description": "Saves the document as .archi (to `path`, or to the file it was opened from).",
         "inputSchema": MCPServer.schema(["path": ["type": "string"]])],
        ["name": "export", "title": "Export",
         "description": "Exports to dxf, dxf12, svg (2D plan of a level), ifc, ifczip, obj (+mtl), stl, glb, 3mf, usda, usdz, step (AP214 faceted B-rep), ply, plt (HP-GL/2), xlsx (schedules workbook), csv (schedules), geojson, points, analytical (structural model JSON), gbxml (energy model), cobie (COBie 2.4 xlsx), dae (COLLADA), kml/kmz (Google Earth, geolocated), bcf (markups as BCF 2.1), boq (bill of quantities CSV/XLSX), svglayers, dwg (needs an installed converter) or archi.",
         "inputSchema": MCPServer.schema(["path": ["type": "string"], "format": ["type": "string", "enum": ["dxf", "dxf12", "svg", "ifc", "ifczip", "obj", "stl", "glb", "3mf", "usda", "usdz", "step", "ply", "plt", "xlsx", "csv", "geojson", "points", "analytical", "gbxml", "cobie", "dae", "dwg", "kml", "kmz", "bcf", "boq", "svglayers", "archi"]], "level": ["type": "integer"]], required: ["path"])],
        ["name": "list_commands", "title": "List commands", "description": "All command names, aliases, categories and summaries.",
         "inputSchema": MCPServer.schema(["category": ["type": "string"]])],
        ["name": "undo", "title": "Undo", "description": "Undoes the last change.", "inputSchema": MCPServer.schema([:])],
        ["name": "import_file", "title": "Import file",
         "description": "Imports a file into the document (merged with new ids): .archi, .dxf, .dwg (via an installed ODA/LibreDWG converter), .ifc/.ifczip (walls/slabs/columns/beams/doors/windows/spaces/ramps/footings become BIM elements, other products meshes), .svg, .obj, .stl, .3mf, .gltf/.glb, .ply, .off, .amf, .dae, .step (polyhedral), .cityjson, .geojson (EPSG:4326/3857/UTM), .shp, .osm, .asc (elevation grid → toposurface), .xlsx (tables), .csv/.txt survey points, .xyz/.pts point clouds. Returns the new ids and a summary.",
         "inputSchema": MCPServer.schema(["path": ["type": "string"], "format": ["type": "string", "description": "Override the format detected from the extension"],
                                          "offset": ["type": "array", "items": ["type": "number"], "description": "[dx, dy] move in drawing units"]], required: ["path"])],
        ["name": "takeoff", "title": "Quantity takeoff",
         "description": "Quantities of BIM elements (SI units): wall length/net area/volume per type and material (openings deducted), slabs, roofs, columns, beams, door/window/opening counts, spaces; plus material volumes. format=csv returns CSV text.",
         "inputSchema": MCPServer.schema(["level": ["type": "integer"], "format": ["type": "string", "enum": ["json", "csv"]]])],
        ["name": "cost_estimate", "title": "Cost estimate",
         "description": "Cost of the takeoff from unit rates: `prices` (object like {\"currency\":\"EUR\",\"wall:area\":45,\"door:count\":350} or {\"prices\":[{category,type,measure,price}]}), a JSON file `path`, or the drawing's COST:<category>[:<type>]:<measure> variables.",
         "inputSchema": MCPServer.schema(["prices": ["type": "object"], "path": ["type": "string"], "format": ["type": "string", "enum": ["json", "csv"]]])],
        ["name": "room_schedule", "title": "Room schedule",
         "description": "Rooms with net area (minus columns), gross area (to wall centre lines), perimeter, height and volume.",
         "inputSchema": MCPServer.schema(["level": ["type": "integer"], "format": ["type": "string", "enum": ["json", "csv"]]])],
        ["name": "clash", "title": "Clash detection",
         "description": "Hard clashes between BIM elements and 3D solids (mesh bounding boxes then triangle-triangle tests; touching, hosted and joined elements ignored). Optional `ids` limits one side of each pair.",
         "inputSchema": MCPServer.schema(["tolerance": ["type": "number"], "ids": ["type": "array", "items": ["type": "integer"]], "includeSpaces": ["type": "boolean"]])],
        ["name": "check_model", "title": "Check model",
         "description": "Model audit: walls without height/length, openings wider than or outside their host, overlapping or duplicate walls, room problems (unnamed, duplicate numbers, overlapping, self-intersecting), duplicate entities, missing levels. Each issue has ids and a zoom box.",
         "inputSchema": MCPServer.schema([:])],
        ["name": "sun_position", "title": "Sun position",
         "description": "Sun azimuth (clockwise from north) and altitude, sunrise/sunset for an ISO date-time (e.g. 2025-06-21T14:30:00+03:00) at the project location or given latitude/longitude.",
         "inputSchema": MCPServer.schema(["datetime": ["type": "string"], "latitude": ["type": "number"], "longitude": ["type": "number"]], required: ["datetime"])],
    ]

    /// Streaming of command logs: progress token of the running tools/call, and the client's logging level.
    var progressToken: Any?
    var progressCount = 0
    var logLevel: String?

    func stream(_ line: String) {
        if let t = progressToken {
            progressCount += 1
            write(["jsonrpc": "2.0", "method": "notifications/progress", "params": ["progressToken": t, "progress": progressCount, "message": line] as [String: Any]])
        }
        if logLevel != nil, ["debug", "info"].contains(logLevel!) {
            write(["jsonrpc": "2.0", "method": "notifications/message", "params": ["level": "info", "logger": "archi", "data": line] as [String: Any]])
        }
    }

    func write(_ obj: Any) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(d + Data("\n".utf8))
    }

    func error(_ id: Any?, _ code: Int, _ msg: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": msg]]
    }

    func serve() async {
        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) else {
                write(error(nil, -32700, "Parse error")); continue
            }
            if let batch = obj as? [Any] {
                var out: [Any] = []
                for item in batch { if let r = await handle(item) { out.append(r) } }
                if !out.isEmpty { write(out) }
            } else if let r = await handle(obj) {
                write(r)
            }
        }
    }

    func handle(_ item: Any) async -> Any? {
        guard let req = item as? [String: Any], let method = req["method"] as? String else {
            // Responses from the client (we send no requests) are ignored.
            if let r = item as? [String: Any], r["result"] != nil || r["error"] != nil { return nil }
            return error((item as? [String: Any])?["id"], -32600, "Invalid Request")
        }
        let id = req["id"]
        let params = req["params"] as? [String: Any] ?? [:]
        if id == nil { return nil } // notification (e.g. notifications/initialized)
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return ["jsonrpc": "2.0", "id": id!, "result": [
                "protocolVersion": MCPServer.supportedVersions.contains(asked) ? asked : MCPServer.supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false], "logging": [String: Any](), "resources": ["listChanged": false, "subscribe": false],
                                 "prompts": ["listChanged": false]],
                "serverInfo": ["name": "archi", "title": "Oanarina Archi Tool", "version": cliVersion],
                "instructions": "Edits an Oanarina Archi Tool (.archi) CAD/BIM document. Units are millimetres (see get_document_summary). Use run_command for AutoCAD-style commands (list_commands), add_entity/add_element for precise JSON edits, and save to write the file.",
            ] as [String: Any]]
        case "ping":
            return ["jsonrpc": "2.0", "id": id!, "result": [String: Any]()]
        case "logging/setLevel":
            logLevel = (params["level"] as? String)?.lowercased()
            return ["jsonrpc": "2.0", "id": id!, "result": [String: Any]()]
        case "tools/list":
            return ["jsonrpc": "2.0", "id": id!, "result": ["tools": tools]]
        case "resources/list":
            return ["jsonrpc": "2.0", "id": id!, "result": ["resources": AgentResources.list(ed.doc)]]
        case "resources/templates/list":
            return ["jsonrpc": "2.0", "id": id!, "result": ["resourceTemplates": AgentResources.templates]]
        case "resources/read":
            guard let uri = params["uri"] as? String else { return error(id, -32602, "missing uri") }
            do {
                let c = try AgentResources.read(uri, doc: ed.doc)
                return ["jsonrpc": "2.0", "id": id!, "result": ["contents": [["uri": c.uri, "mimeType": c.mimeType, "text": c.text]]]]
            } catch {
                return self.error(id, -32002, (error as? LocalizedError)?.errorDescription ?? "Resource not found: \(uri)")
            }
        case "prompts/list":
            return ["jsonrpc": "2.0", "id": id!, "result": ["prompts": AgentPrompts.definitions]]
        case "prompts/get":
            guard let name = params["name"] as? String else { return error(id, -32602, "missing name") }
            var args: [String: String] = [:]
            for (k, v) in (params["arguments"] as? [String: Any]) ?? [:] { args[k] = "\(v)" }
            do { return ["jsonrpc": "2.0", "id": id!, "result": try AgentPrompts.get(name, arguments: args, doc: ed.doc)] }
            catch { return self.error(id, -32602, (error as? LocalizedError)?.errorDescription ?? "\(error)") }
        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0["name"] as? String == name }) else {
                return error(id, -32602, "Unknown tool: \(params["name"] ?? "")")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            progressToken = (params["_meta"] as? [String: Any])?["progressToken"]
            progressCount = 0
            defer { progressToken = nil }
            do {
                let result = try await call(name, args)
                let text = result as? String ?? ArchiJSON.jsonString(result, pretty: true)
                var r: [String: Any] = ["content": [["type": "text", "text": text]], "isError": false]
                if let obj = result as? [String: Any] { r["structuredContent"] = obj }
                return ["jsonrpc": "2.0", "id": id!, "result": r]
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                return ["jsonrpc": "2.0", "id": id!, "result": ["content": [["type": "text", "text": "Error: \(msg)"]], "isError": true] as [String: Any]]
            }
        default:
            return error(id, -32601, "Method not found: \(method)")
        }
    }

    func call(_ name: String, _ a: [String: Any]) async throws -> Any {
        switch name {
        case "run_command":
            guard let text = a["command"] as? String else { throw CLIError.message("missing 'command'") }
            var log: [String] = []
            let streaming = progressToken != nil || logLevel != nil
            if streaming { ed.onLog = { [weak self] s in self?.stream(s) } }
            defer { ed.onLog = nil }
            for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                log += await ed.run(line)
                let mark = ed.log.count
                await drainBackground(ed)
                if ed.log.count > mark { log += ed.log[mark...] }
            }
            let maxLines = max(ArchiJSON.int(a["maxLines"]) ?? 500, 1)
            if log.count > maxLines { return ["log": Array(log.suffix(maxLines)), "truncated": log.count - maxLines, "totalLines": log.count] }
            return ["log": log]
        case "get_document_summary":
            var s = ArchiJSON.summary(ed.doc)
            s["file"] = path.map { $0.path as Any } ?? NSNull()
            s["unsavedChanges"] = ed.isDirty
            return s
        case "get_document": return ArchiJSON.documentJSON(ed.doc)
        case "list_entities":
            var r = ArchiJSON.entities(ed.doc, type: a["type"] as? String, layer: a["layer"] as? String)
            if let lim = ArchiJSON.int(a["limit"]), lim >= 0, r.count > lim { r = Array(r.prefix(lim)) }
            return ["entities": r, "count": r.count]
        case "list_elements":
            let r = ArchiJSON.elements(ed.doc, type: a["type"] as? String, level: ArchiJSON.int(a["level"]))
            return ["elements": r, "count": r.count]
        case "add_entity":
            guard let e = a["entity"] else { throw CLIError.message("missing 'entity'") }
            let list = (e as? [Any]) ?? [e]
            var ids: [EntityID] = []
            try ed.transaction("Agent Add") { d in for item in list { ids.append(d.add(try ArchiJSON.entity(from: item, doc: d))) } }
            return ["ids": ids]
        case "add_element":
            guard let e = a["element"] else { throw CLIError.message("missing 'element'") }
            let list = (e as? [Any]) ?? [e]
            var ids: [EntityID] = []
            try ed.transaction("Agent Add Element") { d in for item in list { ids.append(ArchiJSON.add(try ArchiJSON.element(from: item, doc: d), to: &d)) } }
            return ["ids": ids]
        case "update_entity":
            guard let id = ArchiJSON.int(a["id"]), let patch = a["patch"] as? [String: Any] else { throw CLIError.message("needs 'id' and 'patch'") }
            try ed.transaction("Agent Update") { d in try ArchiJSON.patch(&d, id: id, patch) }
            return ed.doc.entity(id).map { ArchiJSON.object($0) } ?? ed.doc.element(id).map { ArchiJSON.object($0) } ?? NSNull()
        case "delete":
            let ids = Set(ArchiJSON.ids(a["ids"]))
            guard !ids.isEmpty else { throw CLIError.message("missing 'ids'") }
            let before = ed.doc.entities.count + ed.doc.elements.count
            ed.transaction("Agent Delete") { $0.remove(ids: ids) }
            ed.selection.subtract(ids)
            return ["deleted": before - ed.doc.entities.count - ed.doc.elements.count]
        case "save":
            guard let url = (a["path"] as? String).map(expand) ?? path else { throw CLIError.message("no path: pass 'path'") }
            try writeDocument(ed.doc, to: url, format: "archi")
            path = url; ed.fileURL = url; ed.isDirty = false
            return ["path": url.path]
        case "export":
            guard let p = a["path"] as? String else { throw CLIError.message("missing 'path'") }
            let url = expand(p)
            try writeDocument(ed.doc, to: url, format: a["format"] as? String, level: ArchiJSON.int(a["level"]))
            return ["path": url.path]
        case "list_commands":
            let cat = (a["category"] as? String)?.lowercased()
            let cmds = CommandRegistry.shared.sorted.filter { cat == nil || $0.category.lowercased() == cat }
            return ["commands": cmds.map { ["name": $0.name, "aliases": $0.aliases, "category": $0.category, "summary": $0.summary] }]
        case "undo":
            ed.undo(); return ["ok": true]
        case "import_file":
            guard let p = a["path"] as? String else { throw CLIError.message("missing 'path'") }
            let url = expand(p)
            let off = ArchiJSON.point(a["offset"]) ?? .zero
            var result: (DocumentMerge.Result, String)?
            try ed.transaction("Agent Import") { d in result = try FileImport.importFile(url, into: &d, format: a["format"] as? String, offset: off) }
            guard let r = result else { throw CLIError.message("import failed") }
            return ["summary": r.1, "entityIds": r.0.entityIDs, "elementIds": r.0.elementIDs, "addedLevels": r.0.addedLevels]
        case "takeoff":
            let t = QuantityTakeoff.compute(ed.doc, level: ArchiJSON.int(a["level"]))
            if (a["format"] as? String) == "csv" { return t.csv }
            return ["lines": t.lines.map { l -> [String: Any] in
                        ["category": l.category, "type": l.key, "material": l.material, "count": l.count, "length_m": l.length, "area_m2": l.area,
                         "volume_m3": l.volume, "deducted_m2": l.deducted, "ids": l.ids] },
                    "materials": t.materials.map { ["material": $0.material, "area_m2": $0.area, "volume_m3": $0.volume] }]
        case "cost_estimate":
            var table = CostTable.fromVariables(ed.doc)
            if let pr = a["prices"] as? [String: Any] {
                let d = try JSONSerialization.data(withJSONObject: pr)
                table = try CostTable.fromJSON(String(decoding: d, as: UTF8.self))
            } else if let p = a["path"] as? String {
                table = try CostTable.fromJSON(try FileImport.readText(expand(p)))
            }
            guard !table.prices.isEmpty else { throw CLIError.message("no unit rates: pass 'prices' or 'path', or set COST:<category>:<measure> variables") }
            let est = CostEstimate.compute(QuantityTakeoff.compute(ed.doc), table: table)
            if (a["format"] as? String) == "csv" { return est.csv }
            return ["currency": est.currency, "total": est.total,
                    "lines": est.lines.map { ["category": $0.line.category, "type": $0.line.key, "measure": $0.measure, "quantity": $0.quantity, "unitPrice": $0.unitPrice, "total": $0.total] },
                    "unpriced": est.unpriced.map { ["category": $0.category, "type": $0.key] }]
        case "room_schedule":
            let rows = RoomSchedule.compute(ed.doc, level: ArchiJSON.int(a["level"]))
            if (a["format"] as? String) == "csv" { return RoomSchedule.csv(rows) }
            return ["rooms": rows.map { ["id": $0.id, "number": $0.number, "name": $0.name, "level": $0.level, "netArea_m2": $0.netArea, "grossArea_m2": $0.grossArea,
                                         "perimeter_m": $0.perimeter, "height_m": $0.height, "volume_m3": $0.volume] }]
        case "clash":
            var o = ClashOptions()
            if let t = ArchiJSON.double(a["tolerance"]) { o.tolerance = t }
            let ids = ArchiJSON.ids(a["ids"])
            if !ids.isEmpty { o.setA = Set(ids) }
            if let s = a["includeSpaces"] as? Bool { o.includeSpaces = s }
            let cs = ClashDetector.detect(ed.doc, options: o)
            return ["count": cs.count, "clashes": cs.map { ["a": $0.a, "kindA": $0.kindA, "b": $0.b, "kindB": $0.kindB, "point": [$0.point.x, $0.point.y, $0.point.z],
                                                            "contained": $0.contained, "min": [$0.bounds.min.x, $0.bounds.min.y, $0.bounds.min.z], "max": [$0.bounds.max.x, $0.bounds.max.y, $0.bounds.max.z]] }]
        case "check_model":
            let issues = ModelChecker.check(ed.doc)
            return ["count": issues.count, "issues": issues.map { i -> [String: Any] in
                var o: [String: Any] = ["severity": i.severity.rawValue, "code": i.code, "message": i.message, "ids": i.ids]
                if !i.bounds.isEmpty { o["zoom"] = ["min": [i.bounds.min.x, i.bounds.min.y], "max": [i.bounds.max.x, i.bounds.max.y]] }
                return o
            }]
        case "sun_position":
            guard let s = a["datetime"] as? String else { throw CLIError.message("missing 'datetime'") }
            let iso = ISO8601DateFormatter()
            var date = iso.date(from: s)
            if date == nil { iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]; iso.timeZone = TimeZone(secondsFromGMT: 0); date = iso.date(from: s) }
            guard let dt = date else { throw CLIError.message("datetime must be ISO 8601, e.g. 2025-06-21T14:30:00+03:00") }
            let lat = ArchiJSON.double(a["latitude"]) ?? ed.doc.info.latitude, lon = ArchiJSON.double(a["longitude"]) ?? ed.doc.info.longitude
            let p = SolarCalculator.position(date: dt, latitude: lat, longitude: lon)
            let t = SolarCalculator.sunTimes(date: dt, latitude: lat, longitude: lon)
            let out = ISO8601DateFormatter()
            let dir = SolarCalculator.direction(p, northAngle: ed.doc.info.northAngle)
            return ["azimuth": p.azimuth, "altitude": p.altitude, "declination": p.declination, "equationOfTime_min": p.equationOfTime,
                    "sunriseUTC": t.sunrise.map { out.string(from: $0) as Any } ?? NSNull(), "solarNoonUTC": out.string(from: t.noon),
                    "sunsetUTC": t.sunset.map { out.string(from: $0) as Any } ?? NSNull(), "direction": [dir.x, dir.y, dir.z], "latitude": lat, "longitude": lon]
        case "run_batch":
            var spec: Data
            var base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if let p = a["path"] as? String { let u = expand(p); spec = try Data(contentsOf: u); base = u.deletingLastPathComponent() }
            else if let jobs = a["jobs"] { spec = try JSONSerialization.data(withJSONObject: ["jobs": jobs, "stopOnError": a["stopOnError"] as? Bool ?? false]) }
            else { throw CLIError.message("pass 'path' or 'jobs'") }
            let parsed = try BatchJob.parse(spec)
            return await runBatch(parsed.jobs, stopOnError: parsed.stopOnError, base: base)
        default:
            if AgentExtraTools.mutatingNames.contains(name) {
                var result: Any = NSNull()
                try ed.transaction("Agent \(name)") { d in result = try AgentExtraTools.mutate(name, a, doc: &d, resolve: expand) }
                return result
            }
            guard AgentTools.names.contains(name) else { throw CLIError.message("unknown tool \(name)") }
            let r = try AgentTools.call(name, a, doc: ed.doc, resolve: expand)
            if name == "plan_svg", let svg = r as? String, let p = a["path"] as? String {
                let url = expand(p)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try svg.write(to: url, atomically: true, encoding: .utf8)
            }
            return r
        }
    }
}

// MARK: - Batch jobs

/// Runs batch jobs, each on a fresh document; returns a JSON-compatible summary.
@MainActor func runBatch(_ jobs: [BatchJob], stopOnError: Bool, base: URL, verbose: Bool = false) async -> [String: Any] {
    let host = CLIHost()
    let r = await BatchRunner.run(jobs, stopOnError: stopOnError, base: base, host: host, progress: verbose ? { print($0) } : nil)
    withExtendedLifetime(host) {}
    return r
}

// MARK: - Main

/// Waits for work a command left running (queued plugin `archi.run` lines, SCRIPT, ACTPLAY).
@MainActor func drainBackground(_ ed: Editor) async {
    var n = 0
    while let t = ed.backgroundTask, n < 100 {
        await t.value
        if ed.backgroundTask == t { ed.backgroundTask = nil }
        n += 1
    }
}

let usage = """
Usage: archi-cli [file.archi|file.dxf] [--script file.scr] [--out file] [--mcp]

  (no options)     REPL: reads command lines from stdin and prints the command log.
                   Extra REPL lines: :save [path], :export <path>, :quit
  --script FILE    Runs the command lines in FILE (AutoCAD .scr style; ';' starts a comment).
  --out FILE       Writes the result: .archi, .dxf, .svg, .ifc, .ifczip, .obj, .stl, .glb, .csv, .3mf, .usda, .usdz, .geojson,
                   .step, .ply, .plt, .xlsx, .dae, .ifcxml, .dwg (with a converter)
                   (input may also be .dwg, .ifc, .ifczip, .svg, .obj, .stl, .3mf, .gltf/.glb, .ply, .off, .amf, .dae, .step,
                   .geojson, .cityjson, .shp, .osm, .asc, .xlsx, .csv points or .xyz/.pts point clouds)
  --mcp            Model Context Protocol server on stdin/stdout (for Claude and other agents).
  --convert FMT FILES…  Batch conversion: writes each input file as FMT (dxf, ifc, step, glb, svg, archi, …) next to it
                   or into --outdir DIR; prints one line per file and exits non-zero if any failed.
  --batch FILE     Runs the jobs of a JSON batch file (open/import, commands or script, outputs, reports, save);
                   prints one line per job and a JSON summary, exits non-zero if any job failed.
  --plugins DIR    Also loads JavaScript plugins from DIR (folders with plugin.json; see docs/AGENT-API.md).
  --js FILE        Runs a JavaScript file with the archi API (repeatable; before --script). Functions registered with
                   archi.registerCommand(name, fn) become commands for the following script / REPL / MCP session.
  --py SCRIPT [args]  Runs a Python 3 script with the `archi` module (same calls as the JavaScript API) on the drawing
                   given before --py; the drawing is saved when the script ends.
  --watch DIR --rules FILE [--once]  Automation: runs the rules' batch jobs for every new or changed file in DIR that
                   matches a rule's pattern (then POSTs to the rule's webhook); --once processes pending files and exits.
  --python-module [DIR]  Writes archi.py (the Python bridge module) to DIR (default: the current folder).
  --template FILE  Starts a new untitled drawing from a template (.architemplate or .archi) instead of an input file.
  --upgrade FILES… Upgrades older .archi/.architemplate files to the current format (originals kept as .vN.archi.bak).
  --verify FILE    Checks that the drawing saves and reopens identically (exit 1 if not).
  --metadata FILE  Prints the Spotlight metadata of a drawing as JSON.
  --api-reference [FILE]  Writes the generated Markdown API reference (commands, agent tools, formats, samples).
  --docs DIR [--source DOCSDIR]  Writes the documentation as an offline HTML site with search (user guide, scripting,
                   agent API, architecture, command reference); sources default to the app bundle or ./docs.
  --run-samples    Runs the reference's sample scripts and reports each result (exit 1 if one fails).
  --license        Prints the licence and privacy notice (GPL-3.0-or-later; no telemetry, works offline).
  --check-update APPCAST [--current V]  Checks a Sparkle appcast for a newer version (explicit network access).
  --verify-download FILE --ed-signature SIG --public-key KEY  Verifies a downloaded update's Sparkle EdDSA signature.
  --version        Prints the version.
"""

/// Converts files one by one; failures are reported and do not stop the batch.
@MainActor func batchConvert(_ files: [URL], format: String, outDir: URL?) -> Int32 {
    var failed = 0
    let ext = ["dxf12": "dxf", "dxf2004": "dxf", "dxf2007": "dxf", "dxf2010": "dxf", "dxf2013": "dxf", "dxf2018": "dxf", "points": "csv", "analytical": "json",
               "hpgl": "plt", "stp": "step", "gbxml": "xml", "cobie": "xlsx", "saf": "xlsx", "ifcstructural": "ifc", "ifcxml": "ifcXML"][format] ?? format
    for f in files {
        let dest = (outDir ?? f.deletingLastPathComponent()).appendingPathComponent(f.deletingPathExtension().lastPathComponent + (format == "analytical" ? ".analytical" : "")).appendingPathExtension(ext)
        do {
            guard dest.standardizedFileURL != f.standardizedFileURL else { throw CLIError.message("output would overwrite the input") }
            let doc = try loadDocument(f)
            try writeDocument(doc, to: dest, format: format)
            print("\(f.lastPathComponent) → \(dest.path)")
        } catch {
            failed += 1
            eprint("\(f.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        }
    }
    print("Converted \(files.count - failed) of \(files.count) file(s).")
    return failed == 0 ? 0 : 1
}

@MainActor func runCLI() async -> Int32 {
    var input: String?, script: String?, out: String?, mcp = false, pluginDir: URL?, jsFiles: [URL] = [], templatePath: String?
    var args = Array(CommandLine.arguments.dropFirst())
    if let r = await fileLifecycleOptions(&args) { return r }
    if let bi = args.firstIndex(of: "--batch") {
        guard bi + 1 < args.count else { eprint(usage); return 2 }
        let u = expand(args[bi + 1])
        CommandRegistry.shared.ensureBuiltins()
        do {
            let parsed = try BatchJob.parse(try Data(contentsOf: u))
            let summary = await runBatch(parsed.jobs, stopOnError: parsed.stopOnError, base: u.deletingLastPathComponent(), verbose: true)
            print(ArchiJSON.jsonString(summary, pretty: true))
            return (summary["failed"] as? Int ?? 1) == 0 ? 0 : 1
        } catch {
            eprint("Batch file \(u.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            return 2
        }
    }
    if let wi = args.firstIndex(of: "--watch") {
        guard wi + 1 < args.count, let ri = args.firstIndex(of: "--rules"), ri + 1 < args.count else { eprint("--watch DIR --rules rules.json [--once]"); return 2 }
        let dir = expand(args[wi + 1]), rulesURL = expand(args[ri + 1])
        CommandRegistry.shared.ensureBuiltins()
        let watcher: AutomationWatcher
        do { watcher = try AutomationWatcher(folder: dir, rulesData: Data(contentsOf: rulesURL)) }
        catch { eprint("Rules \(rulesURL.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"); return 2 }
        let host = CLIHost()
        let once = args.contains("--once")
        var failures = 0
        repeat {
            for r in await watcher.runOnce(host: host, progress: { print($0) }) {
                print(ArchiJSON.jsonString(r))
                if (r["ok"] as? Bool) != true { failures += 1 }
            }
            if !once { try? await Task.sleep(nanoseconds: UInt64(watcher.interval * 1_000_000_000)) }
        } while !once
        withExtendedLifetime(host) {}
        return failures == 0 ? 0 : 1
    }
    if let mi = args.firstIndex(of: "--python-module") {
        let dir = mi + 1 < args.count ? expand(args[mi + 1]) : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        do { print(try PythonBridge.writeModule(to: dir).path); return 0 } catch { eprint("Cannot write archi.py: \(error.localizedDescription)"); return 1 }
    }
    if let pi = args.firstIndex(of: "--py") {
        guard pi + 1 < args.count else { eprint(usage); return 2 }
        let script = expand(args[pi + 1])
        let before = Array(args[..<pi]).filter { !$0.hasPrefix("-") }
        return PythonBridge.run(script: script, file: before.first.map(expand), args: Array(args[(pi + 2)...]))
    }
    if let ci = args.firstIndex(of: "--convert") {
        var rest = Array(args[(ci + 1)...])
        guard !rest.isEmpty else { eprint(usage); return 2 }
        let fmtName = rest.removeFirst().lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var outDir: URL?
        if let oi = rest.firstIndex(of: "--outdir"), oi + 1 < rest.count { outDir = expand(rest[oi + 1]); rest.removeSubrange(oi...(oi + 1)) }
        let files = rest + Array(args[..<ci]).filter { !$0.hasPrefix("-") }
        guard !files.isEmpty else { eprint("No input files."); return 2 }
        CommandRegistry.shared.ensureBuiltins()
        return batchConvert(files.map(expand), format: fmtName, outDir: outDir)
    }
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--script", "-s": guard !args.isEmpty else { eprint(usage); return 2 }; script = args.removeFirst()
        case "--out", "-o": guard !args.isEmpty else { eprint(usage); return 2 }; out = args.removeFirst()
        case "--mcp": mcp = true
        case "--template": guard !args.isEmpty else { eprint(usage); return 2 }; templatePath = args.removeFirst()
        case "--plugins": guard !args.isEmpty else { eprint(usage); return 2 }; pluginDir = expand(args.removeFirst())
        case "--js": guard !args.isEmpty else { eprint(usage); return 2 }; jsFiles.append(expand(args.removeFirst()))
        case "--help", "-h": print(usage); return 0
        case "--version": print("archi-cli \(cliVersion) (Oanarina Archi Tool)"); return 0
        default:
            if a.hasPrefix("-") { eprint("Unknown option \(a)\n" + usage); return 2 }
            input = a
        }
    }

    let host = CLIHost()
    CommandRegistry.shared.ensureBuiltins()
    CLIPlugins.install(extra: pluginDir)
    let ed = Editor()
    ed.host = host
    var fileURL: URL?
    if let t = templatePath {
        do { ed.replaceDocument(ArchiTemplate.newDocument(from: try ArchiTemplate.decode(Data(contentsOf: expand(t))).document), url: nil) }
        catch { eprint("Cannot open template \(t): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"); return 1 }
    }
    if let input {
        let url = expand(input)
        fileURL = url
        if FileManager.default.fileExists(atPath: url.path) {
            do { ed.replaceDocument(try loadDocument(url), url: url.pathExtension.lowercased() == "archi" ? url : nil) }
            catch { eprint("Cannot open \(url.path): \(error.localizedDescription)"); return 1 }
        } else if url.pathExtension.lowercased() == "archi" {
            ed.fileURL = url
            eprint("\(url.lastPathComponent) does not exist yet; starting a new document (it is created on save).")
        } else {
            eprint("File not found: \(url.path)"); return 1
        }
    }

    if !mcp { ed.onLog = { print($0) } }
    for js in jsFiles {
        do { try await CLIPlugins.runScriptFile(js, ed) }
        catch { eprint("\(js.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"); return 1 }
    }
    if mcp {
        let server = MCPServer(editor: ed, path: fileURL?.pathExtension.lowercased() == "archi" ? fileURL : nil)
        await server.serve()
        return 0
    }

    ed.onLog = { print($0) }
    if !jsFiles.isEmpty && script == nil {
        // JavaScript only: no REPL.
    } else if let script {
        let url = expand(script)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { eprint("Cannot read script \(url.path)"); return 1 }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            await ed.run(line)
            await drainBackground(ed)
        }
    } else {
        let interactive = isatty(STDIN_FILENO) != 0
        if interactive { print("Oanarina Archi Tool \(cliVersion) — type HELP for commands, :quit to exit.") }
        while true {
            if interactive { print("Command: ", terminator: ""); fflush(stdout) }
            guard let line = readLine() else { break }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == ":quit" || t == ":q" || t.uppercased() == "QUIT" || t.uppercased() == "EXIT" { break }
            if t.hasPrefix(":save") || t.hasPrefix(":export") {
                let parts = t.split(separator: " ", maxSplits: 1).map(String.init)
                let isSave = parts[0] == ":save"
                guard let url = parts.count > 1 ? expand(parts[1]) : (isSave ? ed.fileURL ?? fileURL : nil) else { print("Needs a path."); continue }
                do { try writeDocument(ed.doc, to: url, format: isSave ? "archi" : nil); print("Wrote \(url.path)") }
                catch { print("Error: \(error.localizedDescription)") }
                continue
            }
            await ed.run(line)
            await drainBackground(ed)
        }
    }

    if let out {
        let url = expand(out)
        do { try writeDocument(ed.doc, to: url); eprint("Wrote \(url.path)") }
        catch { eprint("Cannot write \(url.path): \(error.localizedDescription)"); return 1 }
    }
    return 0
}

exit(await runCLI())
