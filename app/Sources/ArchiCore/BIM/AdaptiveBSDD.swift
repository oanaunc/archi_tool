// Oanarina Archi Tool — GPL-3.0-or-later
// Adaptive components (PAR-015): point-driven components — struts, panels or any family whose forms use the
// adaptive point values P1x, P1y, P1z, P2x… (and L12, the P1–P2 distance) — that flex when a point moves; points can be
// typed coordinates or point objects (#id) the component follows. buildingSMART Data Dictionary lookup (BIM-131): search
// and class responses of the bSDD REST API (or a saved JSON / bSDD import file) are parsed, classes and their
// properties are assigned to elements as props (bsdd.* and "<Pset>.<Property>"), usable by view filters and schedules.
import Foundation

public enum AdaptiveComponents {
    public static let builtins = ["Strut", "Panel", "Frame"]

    /// Point tokens: "x,y,z" (world) or "#id" (a point object, elevation from its elevation property).
    public static func parse(_ s: String?) -> [String] { (s ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    static func point(_ tok: String, doc: ArchiDocument) -> Vec3? {
        if tok.hasPrefix("#") {
            guard let id = Int(tok.dropFirst()), let e = doc.entity(id) else { return nil }
            let z = e.props["elevation"].flatMap(Double.init) ?? 0
            switch e.geometry {
            case .point(let p): return Vec3(p.x, p.y, z)
            case .circle(let c): return Vec3(c.center.x, c.center.y, z)
            default: return nil
            }
        }
        let v = tok.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard v.count >= 2 else { return nil }
        return Vec3(v[0], v[1], v.count > 2 ? v[2] : 0)
    }

    static func str(_ p: Vec3) -> String { "\(fmt(p.x, 6)),\(fmt(p.y, 6)),\(fmt(p.z, 6))" }

    /// Triangles of an adaptive component through world points.
    public static func triangles(kind: String, points pts: [Vec3], props: [String: String], doc: ArchiDocument) -> [Tri3]? {
        let size = props["adaptiveSize"].flatMap(Double.init) ?? 50
        switch kind.lowercased() {
        case "strut":
            guard pts.count >= 2 else { return nil }
            var acc = MeshAcc()
            SweepMesh.sweep(RG.circle(.zero, size / 2, segments: 16), along: pts, into: &acc)
            return MeshTools.triangles(acc.mesh)
        case "panel":
            guard pts.count == 3 || pts.count == 4 else { return nil }
            let v = pts, t = pts.count == 3 ? [0, 1, 2] : [0, 1, 2, 0, 2, 3]
            guard let s = SolidPrimitives.thicken(vertices: v, triangles: t, thickness: size) else { return nil }
            return MeshTools.triangles(MeshTools.mesh(of: s))
        case "frame":
            guard pts.count >= 3 else { return nil }
            var acc = MeshAcc()
            let sq = [Vec2(-size / 2, -size / 2), Vec2(size / 2, -size / 2), Vec2(size / 2, size / 2), Vec2(-size / 2, size / 2)]
            for i in 0..<pts.count { SweepMesh.sweep(sq, along: [pts[i], pts[(i + 1) % pts.count]], into: &acc) }
            return MeshTools.triangles(acc.mesh)
        default:
            guard let def = doc.family(named: kind) else { return nil }
            var extra: [String: Double] = [:]
            for (i, p) in pts.enumerated() { extra["P\(i + 1)x"] = p.x; extra["P\(i + 1)y"] = p.y; extra["P\(i + 1)z"] = p.z }
            if pts.count >= 2 { extra["L12"] = pts[0].distance(to: pts[1]) }
            let r = FamilyEngine.evaluate(def, doc: doc, props: props, extra: extra)
            let tris = r.parts.values.flatMap { MeshTools.triangles($0.mesh) }
            return tris.isEmpty ? nil : tris
        }
    }

    /// World points of an adaptive element: referenced objects as they are now; typed points moved with the element.
    public static func worldPoints(_ el: BIMElement, doc: ArchiDocument) -> [Vec3]? {
        guard case .component(let g) = el.geometry else { return nil }
        let toks = parse(el.props["adaptivePoints"])
        guard !toks.isEmpty else { return nil }
        let ax = el.props["adaptiveAnchorX"].flatMap(Double.init) ?? g.position.x, ay = el.props["adaptiveAnchorY"].flatMap(Double.init) ?? g.position.y
        let az = el.props["adaptiveAnchorZ"].flatMap(Double.init) ?? g.baseOffset, ar = el.props["adaptiveAnchorRot"].flatMap(Double.init) ?? g.rotation
        let dr = g.rotation - ar, anchor = Vec2(ax, ay)
        var out: [Vec3] = []
        for t in toks {
            guard let p = point(t, doc: doc) else { return nil }
            if t.hasPrefix("#") { out.append(p); continue }
            let q = (p.xy.rotated(by: dr, around: anchor)) + (g.position - anchor)
            out.append(Vec3(q.x, q.y, p.z + g.baseOffset - az))
        }
        return out
    }

    /// Builds (or rebuilds) the element geometry from points; returns the geometry and the props to store.
    static func build(kind: String, tokens: [String], points: [Vec3], level: Int, props: [String: String], doc: ArchiDocument) -> (ComponentGeom, [String: String])? {
        guard let tris = triangles(kind: kind, points: points, props: props, doc: doc), !tris.isEmpty else { return nil }
        let elev = doc.level(level)?.elevation ?? 0
        guard let g = InPlaceModels.component(from: [MeshTools.solid(from: tris, tolerance: 1e-9)], category: doc.family(named: kind)?.category ?? "Adaptive Components", levelElevation: elev) else { return nil }
        var p: [String: String] = [:]
        p["adaptiveKind"] = kind
        // Typed points are stored as the world coordinates they now have.
        p["adaptivePoints"] = zip(tokens, points).map { $0.0.hasPrefix("#") ? $0.0 : str($0.1) }.joined(separator: ";")
        p["adaptiveAnchorX"] = fmt(g.position.x, 9); p["adaptiveAnchorY"] = fmt(g.position.y, 9)
        p["adaptiveAnchorZ"] = fmt(g.baseOffset, 9); p["adaptiveAnchorRot"] = fmt(g.rotation, 12)
        p["adaptiveSig"] = points.map(str).joined(separator: ";") + "|" + (props["adaptiveSize"] ?? "") + "|" + familySig(kind, doc) + "|" + props.filter { $0.key.hasPrefix("fp.") }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        if kind.lowercased() == "strut", points.count >= 2 {
            p["Length"] = fmt(zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }, 2)
        }
        if kind.lowercased() == "panel", points.count >= 3 {
            let a = (points[1] - points[0]).cross(points[2] - points[0]).length / 2 + (points.count == 4 ? (points[2] - points[0]).cross(points[3] - points[0]).length / 2 : 0)
            p["Area"] = fmt(a * pow(doc.units.mm, 2) / 1e6, 4)
        }
        return (g, p)
    }

    static func familySig(_ kind: String, _ doc: ArchiDocument) -> String {
        guard let def = doc.family(named: kind) else { return "" }
        // FNV-1a checksum of the definition (sorted-key JSON), so editing the family re-flexes its instances.
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(def) else { return "" }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }

    @discardableResult
    public static func place(kind: String, points tokens: [String], size: Double? = nil, doc: inout ArchiDocument) -> EntityID? {
        let pts = tokens.compactMap { point($0, doc: doc) }
        guard pts.count == tokens.count else { return nil }
        var props: [String: String] = [:]
        if let s = size { props["adaptiveSize"] = fmt(s) }
        guard let (g, p) = build(kind: kind, tokens: tokens, points: pts, level: doc.currentLevel, props: props, doc: doc) else { return nil }
        let id = doc.addElement(.component(g), material: kind.lowercased() == "panel" ? "Glass" : "Steel", name: "\(kind) (adaptive)")
        if let i = doc.elementIndex(id) { for (k, v) in props.merging(p, uniquingKeysWith: { _, b in b }) { doc.elements[i].props[k] = v } }
        return id
    }

    public static func hasContent(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props["adaptiveKind"] != nil } }

    /// Re-flexes adaptive components whose points (or family / size) changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.elements.indices {
            let el = doc.elements[i]
            guard let kind = el.props["adaptiveKind"], let pts = worldPoints(el, doc: doc) else { continue }
            let sig = pts.map(str).joined(separator: ";") + "|" + (el.props["adaptiveSize"] ?? "") + "|" + familySig(kind, doc) + "|" + el.props.filter { $0.key.hasPrefix("fp.") }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            if sig == el.props["adaptiveSig"] { continue }
            guard let (g, p) = build(kind: kind, tokens: parse(el.props["adaptivePoints"]), points: pts, level: el.level, props: el.props, doc: doc) else { continue }
            doc.elements[i].geometry = .component(g)
            for (k, v) in p { doc.elements[i].props[k] = v }
            changed = true
        }
        return changed
    }

    /// Moves adaptive point `index` (0-based) to a new position.
    @discardableResult
    public static func movePoint(_ id: EntityID, index: Int, to p: Vec3, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.elementIndex(id), let cur = worldPoints(doc.elements[i], doc: doc), index >= 0, index < cur.count else { return false }
        var toks = parse(doc.elements[i].props["adaptivePoints"])
        // Current world positions for typed points (the element may have been moved), the new point typed.
        for k in toks.indices where !toks[k].hasPrefix("#") { toks[k] = str(cur[k]) }
        toks[index] = str(p)
        doc.elements[i].props["adaptivePoints"] = toks.joined(separator: ";")
        if case .component(let g) = doc.elements[i].geometry {
            doc.elements[i].props["adaptiveAnchorX"] = fmt(g.position.x, 9); doc.elements[i].props["adaptiveAnchorY"] = fmt(g.position.y, 9)
            doc.elements[i].props["adaptiveAnchorZ"] = fmt(g.baseOffset, 9); doc.elements[i].props["adaptiveAnchorRot"] = fmt(g.rotation, 12)
        }
        doc.elements[i].props["adaptiveSig"] = nil
        updateAll(&doc)
        return true
    }
}

// MARK: - bSDD

public enum BSDD {
    public static let host = "https://api.bsdd.buildingsmart.org"

    public struct ClassProperty: Hashable {
        public var code: String
        public var name: String
        public var propertySet: String?
        public var dataType: String?
        public var predefinedValue: String?
        public var allowedValues: [String]
    }
    public struct BClass: Hashable {
        public var uri: String
        public var code: String
        public var name: String
        public var definition: String?
        public var dictionary: String?
        public var properties: [ClassProperty]
    }

    /// Text search URL (bSDD REST API v1, classes only; optionally restricted to one dictionary).
    public static func searchURL(_ text: String, dictionary: String? = nil) -> URL? {
        var c = URLComponents(string: host + (dictionary == nil ? "/api/TextSearch/v1" : "/api/SearchInDictionary/v1"))
        var q = [URLQueryItem(name: "SearchText", value: text)]
        if let d = dictionary { q.append(URLQueryItem(name: "DictionaryUri", value: d)) } else { q.append(URLQueryItem(name: "TypeFilter", value: "Classes")) }
        c?.queryItems = q
        return c?.url
    }
    /// Class details URL with its properties.
    public static func classURL(_ uri: String) -> URL? {
        var c = URLComponents(string: host + "/api/Class/v1")
        c?.queryItems = [URLQueryItem(name: "Uri", value: uri), URLQueryItem(name: "IncludeClassProperties", value: "true")]
        return c?.url
    }

    /// Case-insensitive dictionary lookup (the API uses camelCase, bSDD import files PascalCase).
    static func val(_ d: [String: Any], _ k: String) -> Any? { d.first { $0.key.caseInsensitiveCompare(k) == .orderedSame }?.value }
    static func s(_ d: [String: Any], _ k: String) -> String? {
        guard let v = val(d, k) else { return nil }
        if let x = v as? String { return x.isEmpty ? nil : x }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func parseClass(_ d: [String: Any], dictionary: String?) -> BClass? {
        guard let code = s(d, "code") ?? s(d, "referenceCode") else { return nil }
        let name = s(d, "name") ?? code
        let props = ((val(d, "classProperties") as? [[String: Any]]) ?? []).compactMap { p -> ClassProperty? in
            guard let pc = s(p, "propertyCode") ?? s(p, "code") ?? s(p, "name") else { return nil }
            let allowed = ((val(p, "allowedValues") as? [[String: Any]]) ?? []).compactMap { s($0, "value") ?? s($0, "code") }
            return ClassProperty(code: pc, name: s(p, "name") ?? pc, propertySet: s(p, "propertySet"), dataType: s(p, "dataType"), predefinedValue: s(p, "predefinedValue"), allowedValues: allowed)
        }
        return BClass(uri: s(d, "uri") ?? s(d, "classUri") ?? code, code: code, name: name, definition: s(d, "definition"),
                      dictionary: s(d, "dictionaryName") ?? s(d, "dictionaryUri") ?? dictionary, properties: props)
    }

    /// Classes in a bSDD response: text search ({classes: […]}), search in dictionary ({dictionary: {classes: […]}}),
    /// one class ({code, name, classProperties}) or a bSDD import file ({DictionaryName, Classes: […]}).
    public static func parse(_ data: Data) -> [BClass] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = obj as? [[String: Any]] { return arr.compactMap { parseClass($0, dictionary: nil) } }
        guard let d = obj as? [String: Any] else { return [] }
        let dictName = s(d, "dictionaryName") ?? s(d, "name")
        if let list = val(d, "classes") as? [[String: Any]] { return list.compactMap { parseClass($0, dictionary: dictName) } }
        if let inner = val(d, "dictionary") as? [String: Any], let list = val(inner, "classes") as? [[String: Any]] {
            let n = s(inner, "name") ?? s(inner, "uri")
            return list.compactMap { parseClass($0, dictionary: n) }
        }
        return parseClass(d, dictionary: nil).map { [$0] } ?? []
    }

    /// Assigns a class (and its properties' predefined values) to elements. Returns the number of elements changed.
    @discardableResult
    public static func assign(_ c: BClass, to ids: [EntityID], doc: inout ArchiDocument) -> Int {
        var n = 0
        for id in ids {
            guard let i = doc.elementIndex(id) else { continue }
            doc.elements[i].props["bsdd.Code"] = c.code
            doc.elements[i].props["bsdd.Name"] = c.name
            doc.elements[i].props["bsdd.Uri"] = c.uri
            doc.elements[i].props["bsdd.Dictionary"] = c.dictionary
            doc.elements[i].props[Classification.key(c.dictionary ?? "bSDD")] = c.code
            doc.elements[i].props[Classification.key(c.dictionary ?? "bSDD") + "Title"] = c.name
            for p in c.properties {
                let key = (p.propertySet ?? "bSDD") + "." + p.name
                if let v = p.predefinedValue { doc.elements[i].props[key] = v }
                else if doc.elements[i].props[key] == nil { doc.elements[i].props[key] = "" }
            }
            n += 1
        }
        return n
    }

    /// Adds (or replaces) a view filter on a bSDD class code.
    public static func addFilter(code: String, override o: GraphicOverride, doc: inout ArchiDocument) {
        var fs = VisibilityGraphics.filters(doc).filter { $0.name != "bSDD \(code)" }
        fs.append(ViewFilterRule(name: "bSDD \(code)", field: "bsdd.Code", op: "=", value: code, override: o))
        VisibilityGraphics.setFilters(fs, doc: &doc)
    }

    /// Network access for online lookups, installed by the app (the core itself never opens connections); nil =
    /// offline, where saved bSDD JSON files are loaded instead.
    nonisolated(unsafe) public static var fetch: ((URL) async throws -> Data)?

    /// Last search results (per process; commands pick from them by number).
    nonisolated(unsafe) public static var lastResults: [BClass] = []
}

// MARK: - Commands

enum AdaptiveBSDDCommands {
    static var all: [CommandDef] { [adaptive, bsdd] }

    static var adaptive: CommandDef {
        CommandDef("ADAPTIVE", aliases: ["ADAPTIVECOMPONENT", "ADAPTIVEPOINTS"], category: "Architecture", summary: "Adaptive components driven by placement points: Place a Strut, Panel, Frame or a family using P1x…P1z, P2x… values (points typed x,y,z or picked point objects the component follows); Move a point to flex it.") { ed in
            let k = try await ed.getKeyword("Adaptive [Place/Move]", ["Place", "Move"], defaultValue: "Place") ?? "Place"
            if k == "Move" {
                guard case .pick(let pk) = try await ed.pickObject("Select an adaptive component", filter: { ed.doc.element($0)?.props["adaptiveKind"] != nil }) else { return }
                let n = AdaptiveComponents.parse(ed.doc.element(pk.id)?.props["adaptivePoints"]).count
                guard let idx = try await ed.getInteger("Point number (1–\(n))", defaultValue: 1), idx >= 1, idx <= n else { throw CommandError.invalid("No such point.") }
                let p = try await ed.requirePoint3("New position")
                AdaptiveComponents.movePoint(pk.id, index: idx - 1, to: p, doc: &ed.doc)
                ed.print("Point \(idx) moved; the component flexed.")
                return
            }
            let kind = try await ed.getWord("Kind [Strut/Panel/Frame] or family name", defaultValue: ed.doc.variable("ADAPTIVEKIND") ?? "Strut") ?? "Strut"
            let known = AdaptiveComponents.builtins.first { $0.caseInsensitiveCompare(kind) == .orderedSame } ?? (ed.doc.family(named: kind)?.name)
            guard let kd = known else { throw CommandError.invalid("Unknown kind or family \(kind).") }
            ed.doc.setVariable("ADAPTIVEKIND", kd)
            var size: Double? = nil
            if AdaptiveComponents.builtins.contains(kd) { size = try await ed.getPositive(kd == "Panel" ? "Panel thickness" : "Member size", defaultValue: kd == "Panel" ? 30 : 60) }
            var toks: [String] = []
            while true {
                let a = try await ed.getPoint3("Adaptive point \(toks.count + 1) (x,y,z), or #id of a point object; Enter when done", keywords: ["Object"])
                if let p = a.point { toks.append(AdaptiveComponents.str(p)); continue }
                if a.keyword == "Object" {
                    guard case .pick(let pk) = try await ed.pickObject("Select a point object", filter: { id in if case .point? = ed.doc.entity(id)?.geometry { return true }; return false }) else { continue }
                    toks.append("#\(pk.id)"); continue
                }
                break
            }
            guard let id = AdaptiveComponents.place(kind: kd, points: toks, size: size, doc: &ed.doc) else { throw CommandError.invalid("\(kd) needs \(kd == "Panel" ? "3 or 4" : "at least 2") points.") }
            ed.selection = [id]
            ed.print("Adaptive \(kd) #\(id) through \(toks.count) point(s).")
        }
    }

    static var bsdd: CommandDef {
        CommandDef("BSDD", aliases: ["BSDDLOOKUP", "DATADICTIONARY"], category: "Manage", summary: "buildingSMART Data Dictionary: Search classes online (or Load a saved bSDD JSON), Assign a class and its properties to elements, add a view Filter on a class, List assigned classes.") { ed in
            let k = try await ed.getKeyword("bSDD [Search/Load/Assign/Filter/List]", ["Search", "Load", "Assign", "Filter", "List"], defaultValue: "Search") ?? "Search"
            switch k {
            case "Search", "Load":
                var data: Data
                if k == "Load" {
                    guard let path = try await ed.getString("bSDD JSON file") else { return }
                    guard let d = try? Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) else { throw CommandError.invalid("Cannot read \(path).") }
                    data = d
                } else {
                    guard let text = try await ed.getString("Search text"), !text.isEmpty, let url = BSDD.searchURL(text) else { return }
                    guard let fetch = BSDD.fetch else {
                        ed.print("Online lookup is not enabled here. Open \(url.absoluteString), save the result and use BSDD Load.")
                        return
                    }
                    do { data = try await fetch(url) } catch { throw CommandError.invalid("bSDD is not reachable: \(error.localizedDescription)") }
                }
                BSDD.lastResults = BSDD.parse(data)
                if BSDD.lastResults.isEmpty { ed.print("No classes found."); return }
                for (i, c) in BSDD.lastResults.prefix(30).enumerated() { ed.print("\(i + 1). \(c.code) \(c.name)" + (c.dictionary.map { " — \($0)" } ?? "") + (c.properties.isEmpty ? "" : " (\(c.properties.count) properties)")) }
            case "Assign":
                guard !BSDD.lastResults.isEmpty else { throw CommandError.invalid("Search or Load classes first.") }
                guard let n = try await ed.getInteger("Class number", defaultValue: 1), n >= 1, n <= BSDD.lastResults.count else { throw CommandError.invalid("No such class.") }
                var c = BSDD.lastResults[n - 1]
                if c.properties.isEmpty, c.uri.hasPrefix("http"), let fetch = BSDD.fetch, let url = BSDD.classURL(c.uri), let d = try? await fetch(url), let full = BSDD.parse(d).first {
                    c.properties = full.properties; c.definition = full.definition ?? c.definition
                }
                let ids = try await ed.getSelection("Select elements").filter { ed.doc.element($0) != nil }
                let m = BSDD.assign(c, to: ids, doc: &ed.doc)
                ed.print("\(c.code) \(c.name) assigned to \(m) element(s) with \(c.properties.count) propert\(c.properties.count == 1 ? "y" : "ies").")
            case "Filter":
                guard let code = try await ed.getWord("Class code") else { return }
                let os = try await ed.getString("Override (hide, halftone, color:red, lw:0.5; separated by ;)", defaultValue: "color:red") ?? "color:red"
                guard let o = VisibilityGraphics.parseOverride(os) else { throw CommandError.invalid("Invalid override.") }
                BSDD.addFilter(code: code, override: o, doc: &ed.doc)
                ed.print("View filter \"bSDD \(code)\" added (\(ed.doc.elements.filter { $0.props["bsdd.Code"] == code }.count) element(s) match).")
            default:
                var groups: [String: Int] = [:]
                for el in ed.doc.elements { if let c = el.props["bsdd.Code"] { groups["\(c) \(el.props["bsdd.Name"] ?? "")", default: 0] += 1 } }
                if groups.isEmpty { ed.print("No bSDD classes assigned.") }
                for (c, n) in groups.sorted(by: { $0.key < $1.key }) { ed.print("  \(c): \(n)") }
            }
        }
    }
}
