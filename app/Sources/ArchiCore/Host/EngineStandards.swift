// Oanarina Archi Tool — GPL-3.0-or-later
// Graphic standards, clipboard and sharing for the Windows shell: the data behind the Mac Graphic Styles manager
// (GraphicStylesUI.swift), the Object Styles, Material Fill Patterns and Image Adjust dialogs (AppRound12Panels.swift),
// custom visual styles (VisualStyleDef, AppNavigation.swift), Paste from Other App and Copy as Picture
// (AppRound11Support.swift ExternalPaste / Artwork), the description SPEAKDRAWING speaks (A11y.summary), node packages
// (NodePackages.swift) and the rendered shade plot (ShadePlot.renderImage), drawn here with the portable path tracer
// when the shell has not stored a render. Same validation, messages and undo labels as the Mac.
// docs/ENGINE-PROTOCOL.md "Graphic standards, clipboard and sharing".
import Foundation

public enum EngineStandardsMethods {
    /// Protocol methods answered by `EngineSession.callStandards` (listed in engine.hello "methods").
    public static let all: [String] = [
        "graphicstyles.get", "graphicstyles.edit", "objectstyles.get", "objectstyles.set", "matpatterns.get", "matpatterns.set",
        "imageadjust.get", "imageadjust.set", "visualstyles.list", "clipboard.paste", "copypicture.make", "drawing.describe",
    ]
}

// MARK: - Helpers

enum EngineStd {
    /// "#RRGGBB" (upper case, as the Mac `hexRGB`).
    static func hex(_ c: RGBA) -> String { EngineDrawJSON.hex(c).uppercased() }
    static func optHex(_ c: RGBA?) -> EngineJSON { c.map { EngineJSON.string(hex($0)) } ?? .null }
    static func parseHex(_ s: String) -> RGBA? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        let r = Double((v >> 16) & 255) / 255
        let g = Double((v >> 8) & 255) / 255
        let b = Double(v & 255) / 255
        return RGBA(r, g, b)
    }
    static func hexNumber(_ s: String) -> UInt32? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return t.isEmpty ? nil : UInt32(t, radix: 16)
    }
    static func hexString(_ v: UInt32) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - s.count)) + s
    }
    /// Number field of the Mac forms ("," accepted as the decimal separator; empty = nil).
    static func num(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return t.isEmpty ? nil : Double(t)
    }
    static func str(_ v: Double?) -> String { v.map { fmt($0, 3) } ?? "" }
    static func errorText(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? String(describing: e) }

    /// Application data folder: %APPDATA% on Windows, ~/Library/Application Support elsewhere (the Mac app's folder).
    static func appData() -> URL {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let base = env["APPDATA"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        #else
        let base = env["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        #endif
        return base.appendingPathComponent("Oanarina Archi Tool", isDirectory: true)
    }
    static func desktop() -> URL {
        let env = ProcessInfo.processInfo.environment
        let home = env["USERPROFILE"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Desktop", isDirectory: true)
    }
    static func userName() -> String {
        let env = ProcessInfo.processInfo.environment
        return env["USERNAME"] ?? env["USER"] ?? ""
    }
    /// Where pasted pictures are kept: "<drawing> assets" next to a saved drawing, else the application data folder.
    static func assetFolder(_ fileURL: URL?) -> URL {
        if let u = fileURL {
            return u.deletingLastPathComponent().appendingPathComponent(u.deletingPathExtension().lastPathComponent + " assets", isDirectory: true)
        }
        return appData().appendingPathComponent("Pasted", isDirectory: true)
    }
    /// File name without characters Windows and macOS refuse.
    static func safeName(_ s: String, fallback: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let t = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? fallback : t
    }

    /// Vector picture of objects (Artwork.pdf): the largest standard scale that fits 280 mm (small pieces at 1:1), a
    /// 12 pt margin; the PDF and the same page as SVG (the shell rasterises it for the PNG).
    static func picture(_ doc: ArchiDocument, ids: Set<EntityID>?, level: Int?) -> (pdf: Data, svg: String, widthMM: Double, heightMM: Double, ratio: Double)? {
        var o = DrawOptions(level: level)
        o.forPaper = true
        var d = doc
        if let ids { d.entities = d.entities.filter { ids.contains($0.id) } }
        var ents = DrawListBuilder.entries(doc: d, options: o)
        if let ids { ents = ents.filter { e in e.id.map { ids.contains($0) } ?? false } }
        let b = EnginePlot.unionBounds(ents)
        guard !b.isEmpty else { return nil }
        let mm = doc.units.mm
        let needed = max(b.width, b.height) * mm / 280
        let ratio = EnginePlot.standardRatios.first { $0 >= needed } ?? (needed / 1000).rounded(.up) * 1000
        let k = EnginePlot.pointsPerMM
        let perUnit = k * mm / ratio
        let margin = 12.0
        let wPt = b.width * perUnit + 2 * margin
        let hPt = b.height * perUnit + 2 * margin
        let toOrigin = Transform2D.translation(Vec2(-b.min.x, -b.min.y))
        let t = Transform2D.translation(Vec2(margin, margin)) * Transform2D.scale(perUnit, perUnit) * toOrigin
        let r = EnginePlotRenderer(transform: t, devicePerMM: k, paper: true, minLineWidth: 0.12)
        let part = EnginePlotPart(entries: ents, renderer: r, clip: nil)
        let page = EnginePlotPage(name: "Picture", widthMM: wPt / k, heightMM: hPt / k, parts: [part], bookmark: nil)
        let out = EnginePDF.document([page], doc: doc, title: doc.info.name, layered: false)
        let svg = EnginePlotSVG.svg(EnginePDF.resolve(page, doc: doc, layered: false))
        return (out.data, svg, wPt / k, hPt / k, ratio)
    }
}

// MARK: - Custom visual styles (VisualStyleDef, AppNavigation.swift)

/// A named visual style: a built-in base plus overrides (edges, edge colour, face opacity, shadows, background),
/// stored in the drawing (variable VISUALSTYLES, JSON) exactly as the Mac stores it.
struct EngineVisualStyle: Codable, Hashable {
    var name: String
    var base: String
    var edges: Bool?
    var edgeColor: UInt32?
    var faceOpacity: Double?
    var shadows: Bool?
    var background: UInt32?

    static let variable = "VISUALSTYLES"
    static let builtIn = EngineView3DMethods.styles

    /// The built-in style a name or keyword denotes, nil when unknown (VisualStyleNames.resolve).
    static func resolve(_ s: String) -> String? {
        let k = s.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        switch k {
        case "wireframe", "2dwireframe", "3dwireframe", "wire": return "Wireframe"
        case "hidden", "hiddenline", "hide": return "Hidden Line"
        case "shaded", "flat", "gouraud", "shade": return "Shaded"
        case "shadedwithedges", "shadededges", "flatwithedges", "gouraudwithedges", "edges": return "Shaded with Edges"
        case "realistic", "textured", "materials": return "Realistic"
        case "xray", "transparent": return "X-Ray"
        case "conceptual", "consistentcolors", "consistentcolours", "consistent": return "Conceptual"
        case "sketchy", "sketch", "handdrawn", "hand": return "Sketchy"
        default: return builtIn.first { $0.caseInsensitiveCompare(s) == .orderedSame }
        }
    }
    static func all(_ doc: ArchiDocument) -> [EngineVisualStyle] {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([EngineVisualStyle].self, from: d)) ?? []
    }
    static func store(_ list: [EngineVisualStyle], in doc: inout ArchiDocument) {
        if list.isEmpty { doc.variables[variable] = nil; return }
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        let sorted = list.sorted { $0.name < $1.name }
        if let d = try? enc.encode(sorted), let s = String(data: d, encoding: .utf8) { doc.variables[variable] = s }
    }
    static func named(_ n: String, in doc: ArchiDocument) -> EngineVisualStyle? { all(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    /// Adds or replaces a style; refuses built-in names and unknown bases.
    @discardableResult
    static func save(_ v: EngineVisualStyle, in doc: inout ArchiDocument) -> Bool {
        let n = v.name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !builtIn.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }), let base = resolve(v.base) else { return false }
        var list = all(doc).filter { $0.name.caseInsensitiveCompare(n) != .orderedSame }
        var x = v
        x.name = n
        x.base = base
        list.append(x)
        store(list, in: &doc)
        return true
    }
    static func delete(_ n: String, in doc: inout ArchiDocument) -> Bool {
        let list = all(doc)
        let rest = list.filter { $0.name.caseInsensitiveCompare(n) != .orderedSame }
        guard rest.count < list.count else { return false }
        store(rest, in: &doc)
        return true
    }
    /// Every style name the menus offer: built-in then custom.
    static func menuNames(_ doc: ArchiDocument) -> [String] { builtIn + all(doc).map(\.name) }

    var json: EngineJSON {
        var o = EngineObject()
        o.set("name", name)
        o.set("base", base)
        o.set("edges", edges.map { EngineJSON.bool($0) } ?? .null)
        o.set("edgeColor", edgeColor.map { EngineJSON.string(EngineStd.hexString($0)) } ?? .null)
        o.set("faceOpacity", faceOpacity.map { EngineJSON.number($0) } ?? .null)
        o.set("shadows", shadows.map { EngineJSON.bool($0) } ?? .null)
        o.set("background", background.map { EngineJSON.string(EngineStd.hexString($0)) } ?? .null)
        return o.json
    }
    /// The line VISUALSTYLES List prints for the style.
    var listLine: String {
        var s = "  " + name + " — base " + base
        if let e = edges { s += e ? ", edges" : ", no edges" }
        if let o = faceOpacity { s += ", faces " + String(Int(o * 100)) + "%" }
        if let sh = shadows { s += sh ? ", shadows" : ", no shadows" }
        return s
    }
}

// MARK: - Node packages (NodePackages.swift)

/// A shareable package of node-graph snippets saved as a `.archinodes` JSON file (same format as the Mac and the
/// Windows node editor); installed packages live in the application data folder ("NodePackages").
struct EngineNodeSnippet: Codable, Equatable {
    var name: String
    var description = ""
    var graph: NodeGraph
    init(name: String, description: String = "", graph: NodeGraph) { self.name = name; self.description = description; self.graph = graph }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        graph = try c.decodeIfPresent(NodeGraph.self, forKey: .graph) ?? NodeGraph()
    }
}

struct EngineNodePackage: Codable, Equatable {
    var format = EngineNodePackage.formatID
    var name: String
    var version = "1.0"
    var author = ""
    var description = ""
    var snippets: [EngineNodeSnippet] = []
    static let formatID = "oanarina-archi-nodes"
    static let fileExtension = "archinodes"

    init(name: String, author: String = "", snippets: [EngineNodeSnippet] = []) { self.name = name; self.author = author; self.snippets = snippets }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? EngineNodePackage.formatID
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        snippets = try c.decodeIfPresent([EngineNodeSnippet].self, forKey: .snippets) ?? []
    }
    func data() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    static func decode(_ d: Data) throws -> EngineNodePackage {
        let p = try JSONDecoder().decode(EngineNodePackage.self, from: d)
        guard p.format == formatID else { throw CommandError.invalid("Not an Oanarina node package.") }
        guard !p.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.invalid("The package has no name.") }
        return p
    }
}

@MainActor
enum EngineNodePackages {
    /// The library folder (the shell sends its own with ui.prefs `nodePackagesFolder`).
    static var folder: URL {
        let u = EngineSession.uiPreferences["nodePackagesFolder"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? EngineStd.appData().appendingPathComponent("NodePackages", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func fileName(_ name: String) -> String { name.replacingOccurrences(of: "/", with: "-") + "." + EngineNodePackage.fileExtension }

    static func installed() -> [EngineNodePackage] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let pkgs = files.filter { $0.pathExtension == EngineNodePackage.fileExtension }.compactMap { u -> EngineNodePackage? in
            guard let d = try? Data(contentsOf: u) else { return nil }
            return try? EngineNodePackage.decode(d)
        }
        return pkgs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    @discardableResult static func install(_ url: URL) throws -> EngineNodePackage {
        let p = try EngineNodePackage.decode(Data(contentsOf: url))
        try install(p)
        return p
    }
    static func install(_ p: EngineNodePackage) throws { try p.data().write(to: folder.appendingPathComponent(fileName(p.name))) }
    static func remove(_ name: String) throws { try FileManager.default.removeItem(at: folder.appendingPathComponent(fileName(name))) }
    static func package(named n: String) -> EngineNodePackage? { installed().first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }

    /// The nodes with the given ids and the links between them, moved so the top-left node sits at the origin.
    static func subgraph(_ g0: NodeGraph, _ ids: Set<Int>) -> NodeGraph {
        var g = NodeGraph()
        let sel = g0.nodes.filter { ids.contains($0.id) }
        let x0 = sel.map(\.x).min() ?? 0
        let y0 = sel.map(\.y).min() ?? 0
        g.nodes = sel.map { n in
            var m = n
            m.x -= x0
            m.y -= y0
            return m
        }
        g.links = g0.links.filter { ids.contains($0.from) && ids.contains($0.to) }
        g.nextID = (sel.map(\.id).max() ?? 0) + 1
        return g
    }
    /// Inserts another graph's nodes and links at an offset with fresh ids; returns old id → new id.
    @discardableResult
    static func insert(_ other: NodeGraph, into g: inout NodeGraph, x: Double, y: Double) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for n in other.nodes.sorted(by: { $0.id < $1.id }) {
            var m = n
            m.id = g.nextID
            m.x = n.x + x
            m.y = n.y + y
            map[n.id] = g.nextID
            g.nodes.append(m)
            g.nextID += 1
        }
        for l in other.links {
            if let f = map[l.from], let t = map[l.to] { g.links.append(GraphLink(from: f, to: t, port: l.port)) }
        }
        return map
    }
    /// A package from a graph: one snippet per titled group, or the whole graph when it has no groups.
    static func make(from g: NodeGraph, name: String, author: String) -> EngineNodePackage {
        var snippets: [EngineNodeSnippet] = []
        for fr in g.groups {
            let ids = Set(g.members(of: fr))
            if !ids.isEmpty { snippets.append(EngineNodeSnippet(name: fr.title, graph: subgraph(g, ids))) }
        }
        if snippets.isEmpty && !g.nodes.isEmpty { snippets = [EngineNodeSnippet(name: name, graph: subgraph(g, Set(g.nodes.map(\.id))))] }
        return EngineNodePackage(name: name, author: author, snippets: snippets)
    }
}

// MARK: - Rendered shade plot without the shell (ShadePlot.renderImage)

extension EngineShadePlot {
    /// Longest side of the fallback render in pixels and path-tracing passes (tests lower them).
    static var fallbackMaxPixels = 1000
    static var fallbackPasses = 6
    private static var pathTraceCache: [Int: ImageGeom] = [:]

    /// Size of the fallback render of a viewport: 8 px per paper millimetre like the Mac, within the limits above.
    static func fallbackPixels(_ vp: Viewport) -> Int {
        let px = max(vp.size.x, vp.size.y) * 8
        return Int(min(max(px, 400), Double(max(fallbackMaxPixels, 16))))
    }

    /// Path-traced render framed exactly like the hidden-line projection (same camera), as a PNG placed over `box`;
    /// used for "Rendered" viewports when the shell stored no render (plots from the command line, MCP, batch, or a
    /// drawing whose stored render file is gone). Misses of the camera rays are white paper, as on the Mac.
    static func pathTracedImage(doc: ArchiDocument, camera c: Camera, box: BBox2, maxPixels: Int) -> ImageGeom? {
        var h = Hasher()
        h.combine(doc.elements)
        h.combine(doc.entities.count)
        h.combine(doc.materials)
        h.combine(c)
        h.combine(maxPixels)
        h.combine(box.min.x); h.combine(box.min.y); h.combine(box.max.x); h.combine(box.max.y)
        let key = h.finalize()
        if let im = pathTraceCache[key], FileManager.default.fileExists(atPath: im.path) { return im }
        let fwd = (c.target - c.eye).normalized
        guard fwd.length > 0.5, !box.isEmpty else { return nil }
        var right = fwd.cross(Vec3(0, 0, 1)).normalized
        if right.length < 0.5 { right = Vec3(1, 0, 0) }
        let up = right.cross(fwd).normalized
        let aspect = max(box.width, 1) / max(box.height, 1)
        var extent = box
        var eye = c.eye
        var target = c.target
        var fov = c.fov
        if c.orthographic {
            // Image centred on the projected box: the camera moves sideways/up to the box centre.
            let cx = box.center.x - c.eye.dot(right)
            let cy = box.center.y - c.eye.dot(up)
            let shift = right * cx + up * cy
            eye = eye + shift
            target = target + shift
            let d = max((target - eye).length, 1)
            fov = 2 * atan(box.height / 2 / d) * 180 / Double.pi
        } else {
            // The projection plane is at the target distance, centred on the view axis.
            let dist = max((c.eye - c.target).length, 1)
            let hx = max(abs(box.min.x), abs(box.max.x)) / aspect
            let hh = max(abs(box.min.y), abs(box.max.y), hx)
            extent = BBox2(min: Vec2(-hh * aspect, -hh), max: Vec2(hh * aspect, hh))
            fov = 2 * atan(hh / dist) * 180 / Double.pi
        }
        let W = aspect >= 1 ? maxPixels : max(Int(Double(maxPixels) * aspect), 16)
        let H = aspect >= 1 ? max(Int(Double(maxPixels) / aspect), 16) : maxPixels
        var o = EPTSceneBuilder.Options()
        o.ground = false
        let (scene, _) = EPTSceneBuilder.build(doc: doc, camera: nil, options: o)
        guard !scene.tris.isEmpty else { return nil }
        var st = EPTSettings()
        st.width = W
        st.height = H
        st.maxBounces = 3
        st.camera = EPTCamera(Camera(eye: eye, target: target, fov: fov, orthographic: c.orthographic))
        let s = EPTSession(scene: scene, settings: st)
        for _ in 0..<max(fallbackPasses, 1) { s.renderPass() }
        let depth = s.meanDepth
        let hdr = EPTDenoiser.denoise(color: s.compose(), albedo: s.meanAlbedo, normal: s.meanNormal, depth: depth, width: W, height: H)
        var px = EPTToneMap.rgb(hdr, ev: 0)
        guard px.count == W * H * 3 else { return nil }
        for i in 0..<(W * H) {
            // Share of the samples that missed the model (their depth is 1e9): blend towards white paper.
            let f = min(max(depth[i] / 1e9, 0), 1)
            if f <= 0 { continue }
            for ch in 0..<3 {
                let v = Float(px[i * 3 + ch]) * (1 - f) + 255 * f
                px[i * 3 + ch] = UInt8(min(max(v.rounded(), 0), 255))
            }
        }
        let png = EnginePNG.rgb(px, width: W, height: H)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiShadePlot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("render-" + String(UInt(bitPattern: key)) + ".png")
        guard (try? png.write(to: url)) != nil else { return nil }
        let im = ImageGeom(path: url.path, origin: extent.min, size: Vec2(extent.width, extent.height))
        pathTraceCache[key] = im
        return im
    }
}

// MARK: - Methods

extension EngineSession {
    /// Runs one of `EngineStandardsMethods.all` (nil for other methods).
    func callStandards(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "graphicstyles.get": return graphicStylesGet(message: nil)
        case "graphicstyles.edit": return try graphicStylesEdit(p)
        case "objectstyles.get": return objectStylesGet()
        case "objectstyles.set": return try objectStylesSet(p)
        case "matpatterns.get": return matPatternsGet()
        case "matpatterns.set": return try matPatternsSet(p)
        case "imageadjust.get": return imageAdjustGet(p)
        case "imageadjust.set": return try imageAdjustSet(p)
        case "visualstyles.list": return visualStylesList()
        case "clipboard.paste": return try clipboardPaste(p)
        case "copypicture.make": return try copyPictureMake(p)
        case "drawing.describe": return .object([EngineJSONField("text", .string(drawingDescription()))])
        default: return nil
        }
    }

    // MARK: Graphic styles

    func graphicStylesGet(message: String?) -> EngineJSON {
        let doc = editor.doc
        var styles: [EngineJSON] = []
        for key in GraphicStyles.lineStyleNames(doc) {
            guard let s = GraphicStyles.lineStyle(key, doc: doc) else { continue }
            var o = EngineObject()
            o.set("key", key)
            o.set("name", s.name)
            o.set("color", s.color?.text ?? "")
            o.set("lineweight", s.lineweight.map { EngineJSON.number($0) } ?? .null)
            o.set("linetype", s.linetype ?? "")
            styles.append(o.json)
        }
        var layers: [EngineJSON] = []
        for l in doc.layers {
            var o = EngineObject()
            o.set("name", l.name)
            o.set("lineStyle", GraphicStyles.layerLineStyle(l.name, doc: doc) ?? "")
            layers.append(o.json)
        }
        var rows: [EngineJSON] = []
        for r in GraphicStyles.lineweightTable(doc) {
            var o = EngineObject()
            o.set("scale", r.scale)
            o.set("factor", r.factor)
            o.set("text", "1:" + fmt(r.scale, 0) + " → × " + fmt(r.factor, 2))
            rows.append(o.json)
        }
        var pens: [EngineJSON] = []
        for n in GraphicStyles.penSetNames(doc) {
            var o = EngineObject()
            o.set("name", n)
            o.set("pens", doc.variable(GraphicStyles.penSetPrefix + n) ?? "")
            pens.append(o.json)
        }
        var filters: [EngineJSON] = []
        for r in GraphicStyles.filters(doc) {
            var o = EngineObject()
            o.set("name", r.name)
            o.set("enabled", r.enabled)
            o.set("field", r.field)
            o.set("op", r.op)
            o.set("value", r.value)
            o.set("condition", r.field + " " + r.op + " " + r.value)
            o.set("effect", Self.describeOverride(r.override))
            filters.append(o.json)
        }
        var o = EngineObject()
        o.set("lineStyles", .array(styles))
        o.set("linetypes", EngineJSON.strings(doc.linetypes.map(\.name)))
        o.set("layers", .array(layers))
        o.set("lwTable", doc.variable(GraphicStyles.lineweightTableVariable) ?? "")
        o.set("lwRows", .array(rows))
        o.set("penSets", .array(pens))
        o.set("activePenSet", doc.variable(GraphicStyles.currentPenSetVariable) ?? "")
        o.set("penSetDisplay", doc.variable(GraphicStyles.penSetDisplayVariable) == "1")
        o.set("filters", .array(filters))
        o.set("fields", EngineJSON.strings(["layer", "type", "color", "linetype", "lineweight"]))
        o.set("ops", EngineJSON.strings(GraphicStyles.ops))
        o.set("message", message ?? "")
        return o.json
    }

    static func describeOverride(_ o: GraphicOverride) -> String {
        var p: [String] = []
        if o.hidden == true { p.append("hidden") }
        if let c = o.color { p.append(EngineStd.hex(c)) }
        if let w = o.lineweight { p.append(fmt(w, 2) + " mm") }
        if o.halftone == true { p.append("halftone") }
        return p.joined(separator: ", ")
    }

    /// One edit of the Graphic Styles window; each is one undo step with the Mac label.
    func graphicStylesEdit(_ p: EngineJSON) throws -> EngineJSON {
        let op = try string(p, "op")
        var message: String?
        let text = { (k: String) -> String in (p[k]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) }
        switch op {
        case "addLineStyle":
            let n = text("name")
            if !n.isEmpty { editor.transaction("New Line Style") { GraphicStyles.setLineStyle(GraphicStyles.LineStyle(name: n, lineweight: 0.25), doc: &$0) } }
        case "setLineStyle":
            let key = try string(p, "key")
            guard var s = GraphicStyles.lineStyle(key, doc: editor.doc) else { throw EngineError.params("no line style '" + key + "'") }
            if let c = p["color"]?.stringValue { s.color = c.isEmpty ? nil : ColorRef.parse(c) }
            if let w = p["lineweight"] {
                if let v = w.doubleValue { s.lineweight = v >= 0 ? min(v, 5) : nil } else { s.lineweight = nil }
            }
            if let l = p["linetype"]?.stringValue { s.linetype = l.isEmpty ? nil : l }
            let n = s
            editor.transaction("Line Style") { GraphicStyles.setLineStyle(n, doc: &$0) }
        case "deleteLineStyle":
            let key = try string(p, "key")
            editor.transaction("Delete Line Style") { GraphicStyles.deleteLineStyle(key, doc: &$0) }
        case "setLayerLineStyle":
            let layer = try string(p, "layer")
            let style = text("style")
            editor.transaction("Layer Line Style") { GraphicStyles.setLayerLineStyle(layer, style.isEmpty ? nil : style, doc: &$0) }
        case "setLwTable":
            let t = p["text"]?.stringValue ?? ""
            let rows = GraphicStyles.parseTable(t)
            if t.trimmingCharacters(in: .whitespaces).isEmpty {
                editor.transaction("Lineweight Table") { $0.variables[GraphicStyles.lineweightTableVariable] = nil }
                message = "Table cleared."
            } else if rows.isEmpty {
                message = "No valid rows (use 1:50=1)."
            } else {
                editor.transaction("Lineweight Table") { $0.setVariable(GraphicStyles.lineweightTableVariable, t) }
                message = String(rows.count) + " row(s)."
            }
        case "setActivePenSet":
            let n = text("name")
            editor.transaction("Pen Set") { d in
                if n.isEmpty { d.variables[GraphicStyles.currentPenSetVariable] = nil } else { d.setVariable(GraphicStyles.currentPenSetVariable, n) }
            }
        case "setPenSetDisplay":
            let on = p["on"]?.boolValue ?? false
            editor.transaction("Pen Set Display") { $0.setVariable(GraphicStyles.penSetDisplayVariable, on ? "1" : "0") }
        case "deletePenSet":
            let n = try string(p, "name")
            editor.transaction("Delete Pen Set") { $0.variables[(GraphicStyles.penSetPrefix + n).uppercased()] = nil }
        case "savePenSet":
            let n = text("name")
            let pens = GraphicStyles.parsePens(p["pens"]?.stringValue ?? "")
            if n.isEmpty || pens.isEmpty {
                message = "Give a name and at least one pen."
            } else {
                editor.transaction("Pen Set") { GraphicStyles.setPenSet(n, pens, doc: &$0) }
                message = "Pen set \(n): \(pens.count) pen(s)."
            }
        case "setFilterEnabled", "raiseFilter", "deleteFilter":
            var all = GraphicStyles.filters(editor.doc)
            guard let i = p["index"]?.intValue, all.indices.contains(i) else { throw EngineError.params("no filter at 'index'") }
            if op == "setFilterEnabled" { all[i].enabled = p["enabled"]?.boolValue ?? true }
            if op == "raiseFilter" && i > 0 { all.swapAt(i, i - 1) }
            if op == "deleteFilter" { all.remove(at: i) }
            let list = all
            editor.transaction("Graphic Filter") { GraphicStyles.setFilters(list, doc: &$0) }
        case "addFilter":
            let name = text("name").isEmpty ? "Rule" : text("name")
            let field = text("field").isEmpty ? "layer" : text("field")
            let rop = text("operator").isEmpty ? "=" : text("operator")
            var r = GraphicStyles.FilterRule(name: name, field: field, op: rop, value: p["value"]?.stringValue ?? "", override: GraphicOverride())
            r.override.color = EngineStd.parseHex(text("color"))
            r.override.lineweight = Double(text("lineweight")).flatMap { $0 >= 0 ? $0 : nil }
            r.override.halftone = p["halftone"]?.boolValue == true ? true : nil
            r.override.hidden = p["hide"]?.boolValue == true ? true : nil
            if r.value.isEmpty || r.override.isEmpty {
                message = "Give a value and an override."
            } else {
                let rule = r
                editor.transaction("Graphic Filter") { GraphicStyles.setFilters(GraphicStyles.filters($0) + [rule], doc: &$0) }
                message = "Rule " + r.name + " added."
            }
        default:
            throw EngineError.params("unknown op '" + op + "'")
        }
        return graphicStylesGet(message: message)
    }

    // MARK: Object styles (ObjectStylesForm)

    static let objectStyleLineweights = ["", "0.13", "0.18", "0.25", "0.35", "0.5", "0.7", "1", "1.4", "2"]

    func objectStylesGet() -> EngineJSON {
        let all = ObjectStyles.all(editor.doc)
        let extra = all.keys.sorted().filter { !ObjectStyles.categories.contains($0) }
        var rows: [EngineJSON] = []
        for c in ObjectStyles.categories + extra {
            let s = all[c] ?? ObjectStyle()
            var o = EngineObject()
            o.set("category", c)
            o.set("title", c.capitalized)
            o.set("projection", EngineStd.str(s.projectionLineweight))
            o.set("cut", EngineStd.str(s.cutLineweight))
            o.set("color", EngineStd.optHex(s.color))
            o.set("fill", EngineStd.optHex(s.cutFill))
            o.set("pattern", s.cutPattern ?? "")
            rows.append(o.json)
        }
        var o = EngineObject()
        o.set("rows", .array(rows))
        o.set("patterns", EngineJSON.strings(HatchPatterns.allNames))
        o.set("lineweights", EngineJSON.strings(Self.objectStyleLineweights))
        return o.json
    }

    /// Apply of the Object Styles dialog: the Mac form validation, one "Object Styles" undo step.
    func objectStylesSet(_ p: EngineJSON) throws -> EngineJSON {
        guard let rows = p["rows"]?.arrayValue else { throw EngineError.params("missing 'rows'") }
        var errors: [String] = []
        var styles: [String: ObjectStyle] = [:]
        for r in rows {
            guard let cat = r["category"]?.stringValue, !cat.isEmpty else { continue }
            let cut = r["cut"]?.stringValue ?? "", proj = r["projection"]?.stringValue ?? ""
            if !cut.trimmingCharacters(in: .whitespaces).isEmpty, (EngineStd.num(cut) ?? -1) <= 0 { errors.append(cat + ": cut lineweight") }
            if !proj.trimmingCharacters(in: .whitespaces).isEmpty, (EngineStd.num(proj) ?? -1) <= 0 { errors.append(cat + ": projection lineweight") }
            let pattern = r["pattern"]?.stringValue ?? ""
            var s = ObjectStyle()
            if let v = EngineStd.num(proj), v > 0 { s.projectionLineweight = v }
            if let v = EngineStd.num(cut), v > 0 { s.cutLineweight = v }
            if let c = r["color"]?.stringValue { s.color = EngineStd.parseHex(c) }
            if let c = r["fill"]?.stringValue { s.cutFill = EngineStd.parseHex(c) }
            if !pattern.isEmpty { s.cutPattern = pattern }
            if !s.isEmpty { styles[cat] = s }
        }
        var o = EngineObject()
        if !errors.isEmpty {
            o.set("ok", false)
            o.set("message", "Check: " + errors.joined(separator: ", "))
            return o.json
        }
        let final = styles
        editor.transaction("Object Styles") { ObjectStyles.setAll(final, doc: &$0) }
        let n = final.count
        o.set("ok", true)
        o.set("message", String(n) + " categor" + (n == 1 ? "y" : "ies") + " styled.")
        o.set("data", objectStylesGet())
        return o.json
    }

    // MARK: Material fill patterns (MaterialPatternForm)

    func matPatternsGet() -> EngineJSON {
        let doc = editor.doc
        var rows: [EngineJSON] = []
        for m in doc.materials {
            var o = EngineObject()
            o.set("name", m.name)
            o.set("cut", MaterialPatterns.pattern(m.name, kind: .cut, doc: doc) ?? "")
            o.set("surface", MaterialPatterns.pattern(m.name, kind: .surface, doc: doc) ?? "")
            rows.append(o.json)
        }
        var o = EngineObject()
        o.set("rows", .array(rows))
        o.set("patterns", EngineJSON.strings(HatchPatterns.allNames))
        return o.json
    }

    /// Apply of the Material Fill Patterns dialog: changed patterns, bound hatches and floor patterns follow
    /// ("Material Patterns").
    func matPatternsSet(_ p: EngineJSON) throws -> EngineJSON {
        guard let rows = p["rows"]?.arrayValue else { throw EngineError.params("missing 'rows'") }
        let wanted: [(String, String, String)] = rows.compactMap { r in
            guard let n = r["name"]?.stringValue else { return nil }
            return (n, r["cut"]?.stringValue ?? "", r["surface"]?.stringValue ?? "")
        }
        var n = 0
        editor.transaction("Material Patterns") { d in
            for (name, cut, surface) in wanted where d.materials.contains(where: { $0.name == name }) {
                let oldCut = MaterialPatterns.pattern(name, kind: .cut, doc: d) ?? ""
                let oldSurface = MaterialPatterns.pattern(name, kind: .surface, doc: d) ?? ""
                if oldCut != cut, MaterialPatterns.setPattern(name, kind: .cut, pattern: cut.isEmpty ? nil : cut, doc: &d) { n += 1 }
                if oldSurface != surface, MaterialPatterns.setPattern(name, kind: .surface, pattern: surface.isEmpty ? nil : surface, doc: &d) { n += 1 }
            }
            if n > 0 {
                _ = MaterialPatterns.updateAll(&d)
                _ = FloorPatterns.updateAll(&d)
            }
        }
        var o = EngineObject()
        o.set("changed", n)
        o.set("message", String(n) + " pattern" + (n == 1 ? "" : "s") + " changed.")
        o.set("data", matPatternsGet())
        return o.json
    }

    // MARK: Image adjust (ImageAdjustPanel)

    func imageIDs(_ p: EngineJSON) -> [EntityID] {
        let ids = (p["ids"]?.arrayValue ?? []).compactMap(\.intValue)
        return ids.filter { id in
            if case .image? = editor.doc.entity(id)?.geometry { return true }
            return false
        }
    }

    func imageAdjustGet(_ p: EngineJSON) -> EngineJSON {
        let ids = imageIDs(p)
        let first = ids.first.flatMap { editor.doc.entity($0) }
        let a = first.map(ImageDisplay.adjustment) ?? ImageDisplay.Adjustment()
        var o = EngineObject()
        o.set("ids", EngineJSON.ints(ids))
        o.set("brightness", a.brightness)
        o.set("contrast", a.contrast)
        o.set("fade", a.fade)
        var path: String?
        if let e = first, case .image(let im) = e.geometry {
            path = PathSupport.isAbsolute(im.path) ? im.path : (editor.fileURL?.deletingLastPathComponent().appendingPathComponent(im.path).path ?? im.path)
        }
        o.set("path", EngineJSON.optString(path))
        let n = ids.count
        let plural: String = n == 1 ? "" : "s"
        let note: String = "\(n) image\(plural) — the same result on screen, in PDF plots and after reopening."
        o.set("note", note)
        return o.json
    }

    func imageAdjustSet(_ p: EngineJSON) throws -> EngineJSON {
        let ids = imageIDs(p)
        guard !ids.isEmpty else { throw EngineError.params("no images in 'ids'") }
        func v(_ k: String, _ d: Double) -> Double { max(0, min(100, p[k]?.doubleValue ?? d)) }
        let a = ImageDisplay.Adjustment(brightness: v("brightness", 50), contrast: v("contrast", 50), fade: v("fade", 0))
        var n = 0
        editor.transaction("Image Adjust") { d in
            for id in ids {
                guard let i = d.entityIndex(id), case .image = d.entities[i].geometry else { continue }
                ImageDisplay.setAdjustment(a, on: &d.entities[i])
                n += 1
            }
        }
        var o = EngineObject()
        o.set("adjusted", n)
        let plural: String = n == 1 ? "" : "s"
        let message: String = "\(n) image\(plural) adjusted."
        o.set("message", message)
        return o.json
    }

    // MARK: Visual styles

    func visualStylesList() -> EngineJSON {
        var o = EngineObject()
        o.set("builtIn", EngineJSON.strings(EngineVisualStyle.builtIn))
        o.set("custom", .array(EngineVisualStyle.all(editor.doc).map(\.json)))
        o.set("menu", EngineJSON.strings(EngineVisualStyle.menuNames(editor.doc)))
        o.set("current", view3d.style)
        return o.json
    }

    // MARK: Clipboard

    /// Content another app put on the Windows clipboard (read by the shell), inserted at a point as one undo step
    /// ("Paste SVG", "Paste PNG" …) exactly like ExternalPaste.paste; pictures are saved in the asset folder.
    func clipboardPaste(_ p: EngineJSON) throws -> EngineJSON {
        let type = try string(p, "type")
        guard let b64 = p["data"]?.stringValue, let data = Data(base64Encoded: b64) else { throw EngineError.params("missing 'data' (base64)") }
        let at = try rawPoint(p)
        let folder = EngineStd.assetFolder(editor.fileURL)
        var r: ExternalContent.Result?
        var o = EngineObject()
        do {
            try editor.transaction("Paste " + type.uppercased()) { d in
                r = try ExternalContent.insert(data, type: type, into: &d, at: at, assetFolder: folder, name: "Pasted")
            }
        } catch {
            editor.print("Cannot paste: " + EngineStd.errorText(error))
            o.set("ok", false)
            return o.json
        }
        guard let res = r else { o.set("ok", false); return o.json }
        editor.selection = Set(res.ids)
        editor.print("Pasted " + res.summary + ".")
        o.set("ok", true)
        o.set("ids", EngineJSON.ints(res.ids))
        o.set("summary", res.summary)
        return o.json
    }

    /// PDF (file) and SVG picture of objects or of the drawing, for the clipboard of other apps.
    func copyPictureMake(_ p: EngineJSON) throws -> EngineJSON {
        let ids = (p["ids"]?.arrayValue ?? []).compactMap(\.intValue)
        let set: Set<EntityID>? = ids.isEmpty ? nil : Set(ids)
        guard let pic = EngineStd.picture(editor.doc, ids: set, level: set == nil ? editor.doc.currentLevel : nil) else { throw EngineError.failed("Nothing to copy.") }
        return try pictureJSON(pic)
    }

    func pictureJSON(_ pic: (pdf: Data, svg: String, widthMM: Double, heightMM: Double, ratio: Double)) throws -> EngineJSON {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiCopy-" + UUID().uuidString + ".pdf")
        do { try pic.pdf.write(to: url) } catch { throw EngineError.failed("Cannot write " + url.path + ".") }
        var o = EngineObject()
        o.set("pdf", url.path)
        o.set("svg", pic.svg)
        o.set("width", pic.widthMM)
        o.set("height", pic.heightMM)
        o.set("ratio", pic.ratio)
        return o.json
    }

    // MARK: Accessibility (A11y.summary)

    /// Spoken description of the window: view, level, contents, selection, prompt and crosshair.
    func drawingDescription() -> String {
        let d = editor.doc
        var parts: [String] = []
        let mode = EngineSession.uiPreferences["viewMode"] ?? "2D"
        var view = "Plan"
        if mode == "3D" { view = "3D view" }
        if mode == "Sheet" {
            let name = activeSheetIndex.map { d.layouts[$0].name } ?? ""
            view = "Sheet " + name
        }
        var first = view
        if !d.levels.isEmpty { first += ", level " + (d.level(d.currentLevel)?.name ?? "") }
        first += ", layer " + d.currentLayer + "."
        parts.append(first)
        let ne = d.entities.count, nb = d.elements.count
        let objects = ne == 1 ? "1 drawing object" : "\(ne) drawing objects"
        let elements = nb == 1 ? "1 building element" : "\(nb) building elements"
        parts.append("\(objects), \(elements).")
        if editor.selection.isEmpty {
            parts.append("Nothing selected.")
        } else {
            var kinds: [String: Int] = [:]
            for id in editor.selection {
                if let e = d.entity(id) { kinds[e.typeName, default: 0] += 1 } else if let el = d.element(id) { kinds[el.typeName, default: 0] += 1 }
            }
            let list = kinds.keys.sorted().map { String(kinds[$0] ?? 0) + " " + $0 }
            parts.append("Selected: " + list.joined(separator: ", ") + ".")
        }
        if let r = editor.request {
            let opts = r.keywords.isEmpty ? "" : ", options " + r.keywords.joined(separator: ", ")
            parts.append("Prompt: " + r.message + opts + ".")
        } else {
            parts.append("Ready for a command.")
        }
        let c = editor.cursor ?? Vec2(0, 0)
        parts.append("Crosshair at \(fmt(c.x, 2)), \(fmt(c.y, 2)).")
        return parts.joined(separator: " ")
    }
}
