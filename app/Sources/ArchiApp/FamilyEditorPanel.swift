// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Editing model (PAR-001, PAR-003, PAR-004, PAR-034)

/// Working copy of a document family edited in the Family Editor panel. Edits change the draft only; Apply writes it to
/// the document as one undo step and regenerates every instance.
@MainActor
final class FamilyEditorModel: ObservableObject {
    enum Template: String, CaseIterable { case generic = "Generic Model", door = "Door", window = "Window", furniture = "Furniture" }

    @Published var draft: FamilyDefinition?
    /// Name of the family in the document (nil = new family not yet applied).
    @Published var originalName: String?
    /// Type shown in the preview (nil = default values).
    @Published var previewType: String?
    /// Flex values typed in the preview (parameter → value), not stored.
    @Published var flex: [String: String] = [:]
    @Published var selectedForm: Int?
    @Published var message = ""

    // MARK: Load / new

    func load(_ name: String, from doc: ArchiDocument) {
        guard let d = doc.family(named: name) else { return }
        draft = d; originalName = d.name; previewType = d.types.keys.sorted().first; flex = [:]; selectedForm = d.forms.isEmpty ? nil : 0; message = ""
    }

    static func uniqueName(_ base: String, in doc: ArchiDocument, except: String? = nil) -> String {
        func taken(_ n: String) -> Bool { doc.families.contains { $0.name.caseInsensitiveCompare(n) == .orderedSame && $0.name != except } }
        if !taken(base) { return base }
        var k = 2
        while taken("\(base) \(k)") { k += 1 }
        return "\(base) \(k)"
    }

    /// Starts a new family from a template (generic box, door, window or furniture table).
    func newFamily(_ template: Template, in doc: ArchiDocument) {
        let name = FamilyEditorModel.uniqueName(template == .generic ? "Family" : template.rawValue, in: doc)
        var d: FamilyDefinition
        switch template {
        case .door: d = FamilyTemplates.door(name: name)
        case .window: d = FamilyTemplates.window(name: name)
        case .generic:
            d = FamilyDefinition(name: name, category: "Generic Model",
                                 parameters: [FamilyParameter("Width", value: "600"), FamilyParameter("Depth", value: "600"), FamilyParameter("Height", value: "900")],
                                 forms: [FamilyForm(.box, name: "Body", x: "-Width/2", y: "-Depth/2", dims: ["width": "Width", "depth": "Depth", "height": "Height"])])
        case .furniture:
            d = FamilyDefinition(name: name, category: "Furniture",
                                 parameters: [FamilyParameter("Width", value: "1600"), FamilyParameter("Depth", value: "900"), FamilyParameter("Height", value: "750"),
                                              FamilyParameter("Top", value: "40", instance: false), FamilyParameter("Leg", value: "60", instance: false),
                                              FamilyParameter("Inset", value: "50", instance: false)],
                                 forms: [FamilyForm(.box, name: "Top", x: "-Width/2", y: "-Depth/2", z: "Height - Top", dims: ["width": "Width", "depth": "Depth", "height": "Top"]),
                                         FamilyForm(.box, name: "Legs", x: "-Width/2 + Inset", y: "-Depth/2 + Inset", dims: ["width": "Leg", "depth": "Leg", "height": "Height - Top"],
                                                    arrayCount: "2", arrayDX: "Width - 2*Inset - Leg"),
                                         FamilyForm(.box, name: "Legs back", x: "-Width/2 + Inset", y: "Depth/2 - Inset - Leg", dims: ["width": "Leg", "depth": "Leg", "height": "Height - Top"],
                                                    arrayCount: "2", arrayDX: "Width - 2*Inset - Leg")],
                                 types: ["1600 x 900": ["Width": "1600", "Depth": "900"], "1200 x 800": ["Width": "1200", "Depth": "800"]])
        }
        draft = d; originalName = nil; previewType = d.types.keys.sorted().first; flex = [:]; selectedForm = d.forms.isEmpty ? nil : 0
        message = "New \(template.rawValue.lowercased()) family — Apply to add it to the drawing."
    }

    func isDirty(_ doc: ArchiDocument) -> Bool {
        guard let d = draft else { return false }
        guard let o = originalName else { return true }
        return doc.family(named: o) != d
    }

    // MARK: Parameters

    func addParameter(_ kind: FamilyParameterKind = .length) {
        guard var d = draft else { return }
        var n = "Param", k = 1
        while d.parameter(k == 1 ? n : "\(n)\(k)") != nil { k += 1 }
        if k > 1 { n += "\(k)" }
        d.parameters.append(FamilyParameter(n, kind, value: kind.isNumeric ? "0" : ""))
        draft = d
    }
    func removeParameter(_ i: Int) {
        guard var d = draft, d.parameters.indices.contains(i) else { return }
        let name = d.parameters[i].name
        d.parameters.remove(at: i)
        for t in d.types.keys { d.types[t]?[name] = nil }
        draft = d
    }
    /// Renames a parameter and every formula, form expression, type value and plane that refers to it.
    func renameParameter(_ i: Int, to new: String) {
        guard var d = draft, d.parameters.indices.contains(i) else { return }
        let old = d.parameters[i].name, n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old, d.parameter(n) == nil || n.caseInsensitiveCompare(old) == .orderedSame else { return }
        func sub(_ s: String) -> String { FamilyEditorModel.replaceIdentifier(old, with: n, in: s) }
        func sub(_ s: String?) -> String? { s.map(sub) }
        d.parameters[i].name = n
        for j in d.parameters.indices { d.parameters[j].formula = sub(d.parameters[j].formula) }
        for j in d.forms.indices {
            var f = d.forms[j]
            f.x = sub(f.x); f.y = sub(f.y); f.z = sub(f.z); f.rotation = sub(f.rotation)
            f.dims = f.dims.mapValues(sub); f.path = f.path.map { $0.map(sub) }
            f.visible = sub(f.visible); f.arrayCount = sub(f.arrayCount); f.arrayDX = sub(f.arrayDX); f.arrayDY = sub(f.arrayDY); f.arrayDZ = sub(f.arrayDZ)
            if f.material == "=" + old { f.material = "=" + n }
            d.forms[j] = f
        }
        for j in d.profiles.indices { d.profiles[j].points = d.profiles[j].points.map { $0.map(sub) }; d.profiles[j].width = sub(d.profiles[j].width); d.profiles[j].height = sub(d.profiles[j].height) }
        for j in d.referencePlanes.indices { d.referencePlanes[j].offset = sub(d.referencePlanes[j].offset) }
        for t in d.types.keys { if let v = d.types[t]?[old] { d.types[t]?[old] = nil; d.types[t]?[n] = v } }
        draft = d
    }
    /// Replaces a whole identifier (case-insensitive) in an expression.
    static func replaceIdentifier(_ old: String, with new: String, in s: String) -> String {
        var out = "", cur = ""
        func flush() { out += cur.caseInsensitiveCompare(old) == .orderedSame ? new : cur; cur = "" }
        for c in s {
            if c.isLetter || c.isNumber || c == "_" || (c == "." && !cur.isEmpty) { cur.append(c) } else { flush(); out.append(c) }
        }
        flush()
        return out
    }

    // MARK: Forms

    static func defaultDims(_ k: FamilyFormKind) -> [String: String] {
        switch k {
        case .box: return ["width": "100", "depth": "100", "height": "100"]
        case .cylinder: return ["radius": "50", "height": "100"]
        case .extrusion: return ["height": "100", "width": "100", "depth": "100"]
        case .sweep: return ["width": "50", "height": "50"]
        case .revolve: return ["angle": "360", "width": "100", "height": "100"]
        case .blend: return ["height": "100", "width": "100", "depth": "100", "width2": "50", "depth2": "50"]
        case .sweptBlend: return ["width": "50", "height": "50", "width2": "25", "height2": "25"]
        case .nested: return [:]
        }
    }
    func addForm(_ kind: FamilyFormKind) {
        guard var d = draft else { return }
        var f = FamilyForm(kind, name: "\(kind.rawValue.capitalized) \(d.forms.count + 1)", dims: FamilyEditorModel.defaultDims(kind))
        if kind == .extrusion || kind == .revolve || kind == .blend { f.profile = d.profiles.first?.name ?? "rect" }
        if kind == .sweep || kind == .sweptBlend { f.profile = d.profiles.first?.name ?? "round"; f.path = [["0", "0", "0"], ["0", "0", "500"]] }
        if kind == .nested { f.family = nil }
        d.forms.append(f)
        draft = d
        selectedForm = d.forms.count - 1
    }
    func removeForm(_ i: Int) {
        guard var d = draft, d.forms.indices.contains(i) else { return }
        d.forms.remove(at: i); draft = d
        selectedForm = d.forms.isEmpty ? nil : min(i, d.forms.count - 1)
    }
    func duplicateForm(_ i: Int) {
        guard var d = draft, d.forms.indices.contains(i) else { return }
        var f = d.forms[i]; f.name += " copy"
        d.forms.insert(f, at: i + 1); draft = d; selectedForm = i + 1
    }
    func moveForm(_ i: Int, by delta: Int) {
        guard var d = draft, d.forms.indices.contains(i), d.forms.indices.contains(i + delta) else { return }
        d.forms.swapAt(i, i + delta); draft = d; selectedForm = i + delta
    }
    /// Changes a form's kind, adding the dimension keys the new kind uses (existing values are kept).
    func setKind(_ i: Int, _ k: FamilyFormKind) {
        guard var d = draft, d.forms.indices.contains(i) else { return }
        d.forms[i].kind = k
        for (key, v) in FamilyEditorModel.defaultDims(k) where d.forms[i].dims[key] == nil { d.forms[i].dims[key] = v }
        draft = d
    }

    // MARK: Types table

    func addType(_ name: String) {
        guard var d = draft else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !d.types.keys.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { message = "Type names must be unique."; return }
        // A new type starts from the values of the type shown in the preview (or the defaults).
        var vals: [String: String] = [:]
        let src = previewType.flatMap { d.types[$0] } ?? [:]
        for p in d.parameters where p.formula == nil { vals[p.name] = src[p.name] ?? p.value }
        d.types[n] = vals
        draft = d; previewType = n
    }
    func removeType(_ name: String) {
        guard var d = draft else { return }
        d.types[name] = nil; draft = d
        if previewType == name { previewType = d.types.keys.sorted().first }
    }
    func renameType(_ old: String, to new: String) {
        guard var d = draft, let v = d.types[old] else { return }
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old, d.types[n] == nil else { return }
        d.types[old] = nil; d.types[n] = v; draft = d
        if previewType == old { previewType = n }
    }
    func setTypeValue(_ type: String, _ param: String, _ value: String) {
        guard var d = draft, d.types[type] != nil else { return }
        d.types[type]?[param] = value.isEmpty ? nil : value
        draft = d
    }

    // MARK: Reference planes and profiles

    func addPlane(axis: String) {
        guard var d = draft else { return }
        var k = d.referencePlanes.count + 1
        while d.referencePlanes.contains(where: { $0.name == "Plane\(k)" }) { k += 1 }
        d.referencePlanes.append(FamilyReferencePlane("Plane\(k)", axis: axis, offset: "0"))
        draft = d
    }
    func removePlane(_ i: Int) { guard var d = draft, d.referencePlanes.indices.contains(i) else { return }; d.referencePlanes.remove(at: i); draft = d }
    func addProfile() {
        guard var d = draft else { return }
        var k = d.profiles.count + 1
        while d.profile("Profile\(k)") != nil { k += 1 }
        d.profiles.append(FamilyProfile(name: "Profile\(k)", points: [["0", "0"], ["100", "0"], ["100", "100"], ["0", "100"]]))
        draft = d
    }
    func removeProfile(_ i: Int) { guard var d = draft, d.profiles.indices.contains(i) else { return }; d.profiles.remove(at: i); draft = d }

    /// Point list text: "x,y; x,y" (expressions may contain commas inside parentheses).
    static func pointsText(_ pts: [[String]]) -> String { pts.map { $0.joined(separator: ", ") }.joined(separator: "; ") }
    static func parsePoints(_ s: String, dims: Int) -> [[String]]? {
        var out: [[String]] = []
        for part in split(s, on: ";") {
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let c = split(t, on: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count == dims, c.allSatisfy({ !$0.isEmpty }) else { return nil }
            out.append(c)
        }
        return out
    }
    /// Splits at `sep` outside parentheses.
    static func split(_ s: String, on sep: Character) -> [String] {
        var out: [String] = [], cur = "", depth = 0
        for c in s {
            if c == "(" { depth += 1 } else if c == ")" { depth = max(0, depth - 1) }
            if c == sep && depth == 0 { out.append(cur); cur = "" } else { cur.append(c) }
        }
        out.append(cur)
        return out
    }

    // MARK: Evaluation (flex)

    /// Instance props for the preview: the preview type and flex values.
    var previewProps: [String: String] {
        var p: [String: String] = [:]
        if let t = previewType { p["familyType"] = t }
        for (k, v) in flex where !v.trimmingCharacters(in: .whitespaces).isEmpty { p["fp." + k] = v }
        return p
    }
    func resolved(_ doc: ArchiDocument) -> (values: [String: Double], text: [String: String], errors: [String]) {
        guard let d = draft else { return ([:], [:], []) }
        return FamilyExpr.resolve(d, overrides: FamilyEngine.overrides(previewProps), type: previewType)
    }
    /// Document in which the draft replaces the stored family (preview and validation).
    func previewDocument(_ doc: ArchiDocument) -> ArchiDocument {
        var pd = doc
        guard let d = draft else { return pd }
        pd.families.removeAll { $0.name.caseInsensitiveCompare(originalName ?? d.name) == .orderedSame || $0.name.caseInsensitiveCompare(d.name) == .orderedSame }
        pd.families.append(d)
        return pd
    }
    func evaluate(_ doc: ArchiDocument) -> FamilyEngine.Result? {
        guard let d = draft else { return nil }
        return FamilyEngine.evaluate(d, doc: previewDocument(doc), props: previewProps)
    }
    /// Triangle meshes of the draft at the origin (one component instance built by the normal mesh builder).
    func previewGroups(_ doc: ArchiDocument) -> [MeshGroup] {
        guard let d = draft else { return [] }
        var pd = previewDocument(doc)
        pd.entities = []; pd.elements = []
        let lv = pd.levels.first?.id ?? 0
        pd.currentLevel = lv
        let id = pd.addElement(.component(ComponentGeom(category: d.category, position: .zero, size: Vec3(1, 1, 1), family: d.name)), level: lv, name: d.name)
        if let j = pd.elementIndex(id) { for (k, v) in previewProps { pd.elements[j].props[k] = v } }
        let z0 = pd.level(lv)?.elevation ?? 0
        return MeshBuilder.build(doc: pd).filter { $0.id == id }.map { g in
            var g = g; g.mesh.positions = g.mesh.positions.map { Vec3($0.x, $0.y, $0.z - z0) }; g.edges = g.edges.map { $0.map { Vec3($0.x, $0.y, $0.z - z0) } }; return g
        }
    }

    // MARK: Validation / apply

    func problems(_ doc: ArchiDocument) -> [String] {
        guard let d = draft else { return [] }
        var out: [String] = []
        if d.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("The family needs a name.") }
        if doc.families.contains(where: { $0.name.caseInsensitiveCompare(d.name) == .orderedSame && $0.name.caseInsensitiveCompare(originalName ?? "") != .orderedSame }) {
            out.append("Another family is already called \(d.name).")
        }
        var seen = Set<String>()
        for p in d.parameters {
            let k = p.name.lowercased()
            if p.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("A parameter has no name.") }
            else if seen.contains(k) { out.append("Duplicate parameter \(p.name).") }
            seen.insert(k)
            if !p.kind.isNumeric, let e = p.kind.validate(p.value, families: doc.families) { out.append("\(p.name): \(e)") }
        }
        out += resolved(doc).errors
        if let r = evaluate(doc) { out += r.errors.filter { !out.contains($0) } }
        return out
    }

    /// Writes the draft to the document (one undo step), renames instance references and regenerates instances.
    @discardableResult
    func apply(_ ed: Editor) -> Bool {
        guard let d = draft else { return false }
        let name = d.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { message = "The family needs a name."; return false }
        if ed.doc.families.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.name.caseInsensitiveCompare(originalName ?? "") != .orderedSame }) {
            message = "Another family is already called \(name)."; return false
        }
        let old = originalName
        var def = d; def.name = name
        ed.transaction(old == nil ? "New Family \(name)" : "Edit Family \(name)") { doc in
            if let o = old, let i = doc.familyIndex(o) { doc.families[i] = def } else { doc.families.append(def) }
            if let o = old, o != name {
                for j in doc.elements.indices {
                    if case .component(var g) = doc.elements[j].geometry, g.family?.caseInsensitiveCompare(o) == .orderedSame { g.family = name; doc.elements[j].geometry = .component(g) }
                    if doc.elements[j].props["family"]?.caseInsensitiveCompare(o) == .orderedSame { doc.elements[j].props["family"] = name }
                }
                for k in doc.families.indices { for f in doc.families[k].forms.indices where doc.families[k].forms[f].family?.caseInsensitiveCompare(o) == .orderedSame { doc.families[k].forms[f].family = name } }
            }
            FamilyInstances.updateAll(&doc)
            doc.setVariable("CURRENTFAMILY", name)
        }
        draft = def; originalName = name
        let n = FamilyInstances.count(name, doc: ed.doc)
        message = "Applied \(name): \(n) instance(s) updated."
        return true
    }

    /// Removes the family from the document (refused while instances exist).
    @discardableResult
    func deleteFamily(_ ed: Editor) -> Bool {
        guard let o = originalName else { draft = nil; return true }
        let n = FamilyInstances.count(o, doc: ed.doc)
        guard n == 0 else { message = "\(o) has \(n) instance(s); delete them first."; return false }
        ed.transaction("Delete Family \(o)") { doc in doc.families.removeAll { $0.name.caseInsensitiveCompare(o) == .orderedSame } }
        draft = nil; originalName = nil; message = "Deleted \(o)."
        return true
    }
}

// MARK: - Preview rendering

/// Flat-shaded axonometric projection of family meshes (painter's algorithm) for the editor preview.
enum FamilyPreviewProjection {
    struct Face { var points: [CGPoint]; var depth: Double; var shade: Double; var color: RGBA }
    /// Projects triangles into `size` with a view rotated `yaw` about Z and tilted `pitch` (radians).
    static func faces(_ groups: [MeshGroup], doc: ArchiDocument, yaw: Double, pitch: Double, size: CGSize, margin: CGFloat = 12) -> [Face] {
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        func view(_ p: Vec3) -> Vec3 {
            let x = p.x * cy - p.y * sy, y = p.x * sy + p.y * cy
            return Vec3(x, y * sp + p.z * cp, y * cp - p.z * sp)   // screen x, screen y (up), depth (larger = farther)
        }
        var raw: [(Vec3, Vec3, Vec3, RGBA, Double)] = []
        let light = Vec3(-0.4, -0.6, 0.7).normalized
        for g in groups {
            let col = doc.material(g.material)?.color ?? RGBA(0.75, 0.75, 0.72)
            let m = g.mesh
            var i = 0
            while i + 2 < m.indices.count {
                let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
                let n = (b - a).cross(c - a)
                let shade = n.length > 1e-12 ? 0.45 + 0.55 * abs(n.normalized.dot(light)) : 0.6
                raw.append((view(a), view(b), view(c), col, shade))
                i += 3
            }
        }
        guard !raw.isEmpty else { return [] }
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        for t in raw { for p in [t.0, t.1, t.2] { lo = Vec2(min(lo.x, p.x), min(lo.y, p.y)); hi = Vec2(max(hi.x, p.x), max(hi.y, p.y)) } }
        let w = max(hi.x - lo.x, 1e-9), h = max(hi.y - lo.y, 1e-9)
        let s = min((Double(size.width) - 2 * Double(margin)) / w, (Double(size.height) - 2 * Double(margin)) / h)
        let ox = (Double(size.width) - w * s) / 2, oy = (Double(size.height) - h * s) / 2
        func pt(_ p: Vec3) -> CGPoint { CGPoint(x: ox + (p.x - lo.x) * s, y: Double(size.height) - (oy + (p.y - lo.y) * s)) }
        return raw.map { Face(points: [pt($0.0), pt($0.1), pt($0.2)], depth: ($0.0.z + $0.1.z + $0.2.z) / 3, shade: $0.4, color: $0.3) }
            .sorted { $0.depth > $1.depth }
    }
}

struct FamilyPreviewView: View {
    let groups: [MeshGroup]
    let doc: ArchiDocument
    var yaw: Double = -.pi / 6
    var pitch: Double = .pi / 5
    var body: some View {
        Canvas { ctx, size in
            let faces = FamilyPreviewProjection.faces(groups, doc: doc, yaw: yaw, pitch: pitch, size: size)
            if faces.isEmpty {
                ctx.draw(Text("No geometry").font(Theme.font).foregroundColor(Theme.textDim), at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            for f in faces {
                var p = Path(); p.addLines(f.points); p.closeSubpath()
                let c = Color(.sRGB, red: f.color.r * f.shade, green: f.color.g * f.shade, blue: f.color.b * f.shade, opacity: max(0.35, f.color.a))
                ctx.fill(p, with: .color(c))
                ctx.stroke(p, with: .color(c.opacity(0.9)), lineWidth: 0.4)
            }
        }
        .background(Color(hex: 0x1B1C1F))
    }
}

// MARK: - Window

@MainActor
enum FamilyEditorWindow {
    private(set) static var window: NSPanel?
    /// The editing model of the open panel (also used by the self-tests).
    private(set) static var editor = FamilyEditorModel()
    static var isOpen: Bool { window?.isVisible == true || hosting != nil }
    private static var hosting: NSHostingController<AnyView>?

    /// Opens the panel on a family (or the current one). `present: false` builds it off screen (self-tests).
    private static weak var owner: AppModel?
    static func show(model: AppModel, family: String? = nil, present: Bool = true) {
        // The panel edits one document window at a time: switching windows starts from that window's families.
        if owner !== model { owner = model; editor = FamilyEditorModel() }
        if let f = family ?? model.doc.variable("CURRENTFAMILY") ?? model.doc.families.first?.name, model.doc.family(named: f) != nil,
           editor.originalName?.caseInsensitiveCompare(f) != .orderedSame || editor.draft == nil {
            editor.load(f, from: model.doc)
        }
        let root = AnyView(FamilyEditorPanel(model: model, fe: editor).preferredColorScheme(Theme.colorScheme))
        let hc = NSHostingController(rootView: root)
        hosting = hc
        if let w = window { w.contentViewController = hc } else {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            w.title = "Family Editor"
            w.isReleasedWhenClosed = false
            w.isFloatingPanel = true
            w.hidesOnDeactivate = true
            w.appearance = Theme.appearance
            w.contentViewController = hc
            w.setFrameAutosaveName("ArchiFamilyEditor")
            if w.frame.origin == .zero { w.center() }
            window = w
        }
        if present { window?.makeKeyAndOrderFront(nil) } else { hc.view.frame = NSRect(x: 0, y: 0, width: 980, height: 640); hc.view.layoutSubtreeIfNeeded() }
    }
    static func close() {
        window?.orderOut(nil)
        hosting = nil
        window?.contentViewController = nil
    }
}

// MARK: - Panel

struct FamilyEditorPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var fe: FamilyEditorModel
    @State private var tab = "Parameters"
    @State private var yaw = -Double.pi / 6

    var body: some View {
        HStack(spacing: 0) {
            FamilyListColumn(model: model, fe: fe).frame(width: 190)
            Divider()
            if fe.draft != nil {
                VStack(alignment: .leading, spacing: 6) {
                    FamilyHeader(model: model, fe: fe)
                    Picker("", selection: $tab) { ForEach(["Parameters", "Forms", "Types", "Planes & Profiles"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                    ScrollView {
                        switch tab {
                        case "Forms": FamilyFormsEditor(model: model, fe: fe)
                        case "Types": FamilyTypesEditor(fe: fe)
                        case "Planes & Profiles": FamilyPlanesEditor(fe: fe)
                        default: FamilyParametersEditor(fe: fe)
                        }
                    }
                }
                .padding(8).frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Divider()
                FamilyPreviewColumn(model: model, fe: fe, yaw: $yaw).frame(width: 290)
            } else {
                VStack { Spacer(); Text("Select a family or create one from a template.").foregroundStyle(Theme.textDim); Spacer() }.frame(maxWidth: .infinity)
            }
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .background(Theme.panel)
        .frame(minWidth: 820, minHeight: 480)
    }
}

private struct FamilyListColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var fe: FamilyEditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Families").font(Theme.fontBold).padding(.horizontal, 8).padding(.top, 8)
            List(model.doc.families, id: \.name) { f in
                Button { if !fe.isDirty(model.doc) || confirmDiscard() { fe.load(f.name, from: model.doc) } } label: {
                    HStack {
                        Image(systemName: "cube.box").foregroundStyle(fe.originalName == f.name ? Theme.accent : Theme.textDim)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(f.name).lineLimit(1)
                            Text("\(f.category) · \(FamilyInstances.count(f.name, doc: model.doc)) placed").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        }
                    }
                }.buttonStyle(.plain)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Menu("New from Template") {
                ForEach(FamilyEditorModel.Template.allCases, id: \.self) { t in Button(t.rawValue) { if !fe.isDirty(model.doc) || confirmDiscard() { fe.newFamily(t, in: model.doc) } } }
            }.menuStyle(.borderlessButton).padding(8)
        }
    }
    private func confirmDiscard() -> Bool {
        let a = NSAlert(); a.messageText = "Discard the changes to \(fe.draft?.name ?? "this family")?"; a.addButton(withTitle: "Discard"); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

private struct FamilyHeader: View {
    @ObservedObject var model: AppModel
    @ObservedObject var fe: FamilyEditorModel
    var body: some View {
        let d = fe.draft ?? FamilyDefinition(name: "")
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Name", text: Binding(get: { d.name }, set: { fe.draft?.name = $0 })).textFieldStyle(.plain).padding(4).darkField().frame(width: 170)
                Picker("", selection: Binding(get: { d.category }, set: { fe.draft?.category = $0 })) {
                    ForEach(Array(Set(["Generic Model", "Furniture", "Door", "Window", "Casework", "Lighting", "Plumbing", "Profile", "Specialty"] + [d.category])).sorted(), id: \.self) { Text($0) }
                }.labelsHidden().frame(width: 130)
                Spacer()
                Button("Revert") { if let o = fe.originalName { fe.load(o, from: model.doc) } else { fe.draft = nil } }
                    .buttonStyle(FlatButtonStyle(compact: true)).disabled(!fe.isDirty(model.doc))
                Button("Apply") { fe.apply(model.editor) }.buttonStyle(FlatButtonStyle(prominent: true, compact: true)).disabled(!fe.isDirty(model.doc))
                Menu {
                    Button("Place in Drawing") {
                        if fe.isDirty(model.doc) { fe.apply(model.editor) }
                        if let n = fe.originalName { model.editor.doc.setVariable("CURRENTFAMILY", n); model.runCommand("FAMILY Place " + n) }
                    }.disabled(fe.draft?.name.contains(" ") == true)
                    Button("Select Instances") {
                        guard let n = fe.originalName else { return }
                        model.editor.selection = Set(model.doc.elements.filter { el in
                            if case .component(let g) = el.geometry, g.family?.caseInsensitiveCompare(n) == .orderedSame { return true }
                            return el.props["family"]?.caseInsensitiveCompare(n) == .orderedSame }.map(\.id))
                    }
                    Divider()
                    Button("Delete Family") { fe.deleteFamily(model.editor) }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            TextField("Description", text: Binding(get: { d.description }, set: { fe.draft?.description = $0 })).textFieldStyle(.plain).padding(4).darkField()
            if !fe.message.isEmpty { Text(fe.message).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
    }
}

/// Parameter table: name, kind, value, formula, instance/type, range.
private struct FamilyParametersEditor: View {
    @ObservedObject var fe: FamilyEditorModel
    var body: some View {
        let ps = fe.draft?.parameters ?? []
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("Name").frame(width: 92, alignment: .leading); Text("Kind").frame(width: 78, alignment: .leading)
                Text("Value").frame(width: 70, alignment: .leading); Text("Formula").frame(maxWidth: .infinity, alignment: .leading)
                Text("Inst.").frame(width: 34); Text("Min").frame(width: 42); Text("Max").frame(width: 42); Spacer().frame(width: 18)
            }.font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            ForEach(ps.indices, id: \.self) { i in FamilyParameterRow(fe: fe, index: i) }
            Menu("Add Parameter") { ForEach(FamilyParameterKind.allCases, id: \.self) { k in Button(k.rawValue) { fe.addParameter(k) } } }
                .menuStyle(.borderlessButton).fixedSize().padding(.top, 4)
        }
    }
}

private struct FamilyParameterRow: View {
    @ObservedObject var fe: FamilyEditorModel
    let index: Int
    @State private var nameEdit = ""
    var body: some View {
        if let p = fe.draft?.parameters[safe: index] {
            HStack(spacing: 4) {
                TextField("", text: Binding(get: { nameEdit.isEmpty ? p.name : nameEdit }, set: { nameEdit = $0 }), onCommit: { fe.renameParameter(index, to: nameEdit); nameEdit = "" })
                    .textFieldStyle(.plain).padding(3).darkField().frame(width: 92)
                Picker("", selection: Binding(get: { p.kind }, set: { fe.draft?.parameters[index].kind = $0 })) { ForEach(FamilyParameterKind.allCases, id: \.self) { Text($0.rawValue) } }
                    .labelsHidden().frame(width: 78)
                TextField("", text: Binding(get: { p.value }, set: { fe.draft?.parameters[index].value = $0 })).textFieldStyle(.plain).padding(3).darkField().frame(width: 70)
                    .disabled(p.formula?.isEmpty == false)
                TextField("free", text: Binding(get: { p.formula ?? "" }, set: { fe.draft?.parameters[index].formula = $0.isEmpty ? nil : $0 })).textFieldStyle(.plain).padding(3).darkField()
                Toggle("", isOn: Binding(get: { p.instance }, set: { fe.draft?.parameters[index].instance = $0 })).labelsHidden().frame(width: 34).help("Instance parameter (off = type parameter)")
                TextField("", text: Binding(get: { p.min.map { fmt($0, 4) } ?? "" }, set: { fe.draft?.parameters[index].min = Double($0) })).textFieldStyle(.plain).padding(3).darkField().frame(width: 42)
                TextField("", text: Binding(get: { p.max.map { fmt($0, 4) } ?? "" }, set: { fe.draft?.parameters[index].max = Double($0) })).textFieldStyle(.plain).padding(3).darkField().frame(width: 42)
                Button { fe.removeParameter(index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).frame(width: 18)
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Forms list and the selected form's placement, dimensions, profile, material, visibility, void and array.
private struct FamilyFormsEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject var fe: FamilyEditorModel
    var body: some View {
        let forms = fe.draft?.forms ?? []
        VStack(alignment: .leading, spacing: 6) {
            ForEach(forms.indices, id: \.self) { i in
                let f = forms[i]
                HStack {
                    Image(systemName: f.void ? "cube.transparent" : f.kind == .nested ? "square.on.square" : "cube.fill")
                        .foregroundStyle(fe.selectedForm == i ? Theme.accent : Theme.textDim)
                    Text(f.name.isEmpty ? f.kind.rawValue : f.name).lineLimit(1)
                    Text(f.kind.rawValue + (f.void ? " · void" : "") + ((f.arrayCount.map { $0 != "1" } ?? false) ? " · array" : "")).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    Spacer()
                    Button { fe.moveForm(i, by: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(i == 0)
                    Button { fe.moveForm(i, by: 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(i == forms.count - 1)
                    Button { fe.duplicateForm(i) } label: { Image(systemName: "plus.square.on.square") }.buttonStyle(.borderless)
                    Button { fe.removeForm(i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(fe.selectedForm == i ? Theme.hover : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { fe.selectedForm = i }
            }
            Menu("Add Form") { ForEach(FamilyFormKind.allCases, id: \.self) { k in Button(k.rawValue) { fe.addForm(k) } } }.menuStyle(.borderlessButton).fixedSize()
            if let i = fe.selectedForm, forms.indices.contains(i) {
                HSeparator()
                FamilyFormDetail(model: model, fe: fe, index: i)
            }
        }
    }
}

private struct FamilyFormDetail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var fe: FamilyEditorModel
    let index: Int
    @State private var pathText = ""
    private func field(_ label: String, _ kp: WritableKeyPath<FamilyForm, String>, width: CGFloat = 90) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(Theme.textDim)
            TextField("", text: Binding(get: { fe.draft?.forms[safe: index]?[keyPath: kp] ?? "" }, set: { fe.draft?.forms[index][keyPath: kp] = $0 }))
                .textFieldStyle(.plain).padding(3).darkField().frame(width: width)
        }
    }
    private func optField(_ label: String, _ kp: WritableKeyPath<FamilyForm, String?>, placeholder: String = "", width: CGFloat = 90) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(Theme.textDim)
            TextField(placeholder, text: Binding(get: { fe.draft?.forms[safe: index]?[keyPath: kp] ?? "" }, set: { fe.draft?.forms[index][keyPath: kp] = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.plain).padding(3).darkField().frame(width: width)
        }
    }
    var body: some View {
        if let f = fe.draft?.forms[safe: index], let d = fe.draft {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    field("Name", \.name, width: 140)
                    Picker("", selection: Binding(get: { f.kind }, set: { fe.setKind(index, $0) })) { ForEach(FamilyFormKind.allCases, id: \.self) { Text($0.rawValue) } }.labelsHidden().frame(width: 110)
                    Toggle("Void", isOn: Binding(get: { f.void }, set: { fe.draft?.forms[index].void = $0 })).help("Void forms cut the solid forms")
                }
                HStack { field("X", \.x); field("Y", \.y); field("Z", \.z) }
                HStack { field("Rotation°", \.rotation, width: 60); optField("Visible if", \.visible, placeholder: "always", width: 150) }
                Text("Dimensions").font(Theme.fontBold)
                let keys = Array(Set(f.dims.keys).union(FamilyEditorModel.defaultDims(f.kind).keys)).sorted()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(keys, id: \.self) { k in
                        HStack(spacing: 3) {
                            Text(k).foregroundStyle(Theme.textDim).frame(width: 48, alignment: .trailing)
                            TextField("", text: Binding(get: { fe.draft?.forms[safe: index]?.dims[k] ?? "" }, set: { fe.draft?.forms[index].dims[k] = $0.isEmpty ? nil : $0 }))
                                .textFieldStyle(.plain).padding(3).darkField().frame(width: 90)
                        }
                    }
                }
                if [.extrusion, .sweep, .revolve, .blend, .sweptBlend].contains(f.kind) {
                    HStack {
                        profileMenu("Profile", current: f.profile, d: d) { fe.draft?.forms[index].profile = $0 }
                        if f.kind == .blend || f.kind == .sweptBlend { profileMenu("End profile", current: f.profile2, d: d) { fe.draft?.forms[index].profile2 = $0 } }
                    }
                }
                if f.kind == .sweep || f.kind == .sweptBlend {
                    HStack(spacing: 3) {
                        Text("Path x,y,z;…").foregroundStyle(Theme.textDim)
                        TextField("", text: Binding(get: { pathText.isEmpty ? FamilyEditorModel.pointsText(f.path) : pathText }, set: { pathText = $0 }), onCommit: {
                            if let p = FamilyEditorModel.parsePoints(pathText, dims: 3), p.count >= 2 { fe.draft?.forms[index].path = p; pathText = "" } else { fe.message = "A path needs at least two x,y,z points." }
                        }).textFieldStyle(.plain).padding(3).darkField()
                    }
                }
                if f.kind == .nested {
                    HStack {
                        Picker("Family", selection: Binding(get: { f.family ?? "" }, set: { fe.draft?.forms[index].family = $0.isEmpty ? nil : $0 })) {
                            Text("—").tag("")
                            ForEach(model.doc.families.map(\.name).filter { $0 != d.name }, id: \.self) { Text($0).tag($0) }
                            ForEach(d.parameters.filter { $0.kind == .familyType }.map { "=" + $0.name }, id: \.self) { Text($0).tag($0) }
                        }.frame(width: 220)
                    }
                }
                HStack {
                    Picker("Material", selection: Binding(get: { f.material ?? "" }, set: { fe.draft?.forms[index].material = $0.isEmpty ? nil : $0 })) {
                        Text("By element").tag("")
                        ForEach(model.doc.materials.map(\.name).sorted(), id: \.self) { Text($0).tag($0) }
                        ForEach(d.parameters.filter { $0.kind == .material }.map { "=" + $0.name }, id: \.self) { Text($0).tag($0) }
                        if let m = f.material, !m.isEmpty, !model.doc.materials.contains(where: { $0.name == m }), !m.hasPrefix("=") { Text(m).tag(m) }
                    }.frame(width: 240)
                }
                HStack { optField("Array ×", \.arrayCount, placeholder: "1", width: 44); optField("dX", \.arrayDX, width: 70); optField("dY", \.arrayDY, width: 70); optField("dZ", \.arrayDZ, width: 70) }
            }
        }
    }
    private func profileMenu(_ title: String, current: String?, d: FamilyDefinition, set: @escaping (String?) -> Void) -> some View {
        Picker(title, selection: Binding(get: { current ?? "" }, set: { set($0.isEmpty ? nil : $0) })) {
            Text("—").tag("")
            ForEach(d.profiles.map(\.name), id: \.self) { Text($0).tag($0) }
            ForEach(ProfileLibrary.builtins.map(\.name), id: \.self) { Text($0).tag($0) }
            if let c = current, !c.isEmpty, d.profile(c) == nil, !ProfileLibrary.isBuiltin(c) { Text(c).tag(c) }
        }.frame(width: 200)
    }
}

/// Family types table (PAR-034): one column per type, one row per non-formula parameter.
private struct FamilyTypesEditor: View {
    @ObservedObject var fe: FamilyEditorModel
    @State private var newType = ""
    var body: some View {
        let d = fe.draft ?? FamilyDefinition(name: "")
        let types = d.types.keys.sorted()
        let params = d.parameters.filter { $0.formula == nil }
        VStack(alignment: .leading, spacing: 4) {
            if types.isEmpty { Text("No types: instances use the parameter defaults. Add a type to build a types table.").foregroundStyle(Theme.textDim) }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Parameter").frame(width: 100, alignment: .leading).foregroundStyle(Theme.textDim)
                        ForEach(types, id: \.self) { t in
                            HStack(spacing: 2) {
                                TextField("", text: Binding(get: { t }, set: { fe.renameType(t, to: $0) })).textFieldStyle(.plain).padding(3).darkField()
                                Button { fe.removeType(t) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                            }.frame(width: 110)
                        }
                    }
                    ForEach(params, id: \.name) { p in
                        HStack(spacing: 4) {
                            Text(p.name + (p.instance ? "" : " (type)")).lineLimit(1).frame(width: 100, alignment: .leading)
                            ForEach(types, id: \.self) { t in
                                TextField(p.value, text: Binding(get: { fe.draft?.types[t]?[p.name] ?? "" }, set: { fe.setTypeValue(t, p.name, $0) }))
                                    .textFieldStyle(.plain).padding(3).darkField().frame(width: 110)
                            }
                        }
                    }
                }
            }
            HStack {
                TextField("New type name", text: $newType).textFieldStyle(.plain).padding(3).darkField().frame(width: 160)
                Button("Add Type") { fe.addType(newType); newType = "" }.buttonStyle(FlatButtonStyle(compact: true)).disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// Reference planes (PAR-003) and parametric profiles.
private struct FamilyPlanesEditor: View {
    @ObservedObject var fe: FamilyEditorModel
    @State private var edits: [Int: String] = [:]
    var body: some View {
        let d = fe.draft ?? FamilyDefinition(name: "")
        VStack(alignment: .leading, spacing: 5) {
            Text("Reference planes").font(Theme.fontBold)
            Text("Use a plane's name in any expression; forms drawn to it follow the plane when parameters flex.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            ForEach(d.referencePlanes.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    TextField("", text: Binding(get: { fe.draft?.referencePlanes[safe: i]?.name ?? "" }, set: { fe.draft?.referencePlanes[i].name = $0 })).textFieldStyle(.plain).padding(3).darkField().frame(width: 100)
                    Picker("", selection: Binding(get: { fe.draft?.referencePlanes[safe: i]?.axis ?? "x" }, set: { fe.draft?.referencePlanes[i].axis = $0 })) {
                        Text("⟂ X").tag("x"); Text("⟂ Y").tag("y"); Text("⟂ Z").tag("z")
                    }.labelsHidden().frame(width: 70)
                    TextField("offset", text: Binding(get: { fe.draft?.referencePlanes[safe: i]?.offset ?? "" }, set: { fe.draft?.referencePlanes[i].offset = $0 })).textFieldStyle(.plain).padding(3).darkField()
                    Button { fe.removePlane(i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack { ForEach(["x", "y", "z"], id: \.self) { a in Button("Add ⟂ \(a.uppercased())") { fe.addPlane(axis: a) }.buttonStyle(FlatButtonStyle(compact: true)) } }
            HSeparator()
            Text("Profiles").font(Theme.fontBold)
            Text("Vertices as x, y; x, y … (expressions allowed).").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            ForEach(d.profiles.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        TextField("", text: Binding(get: { fe.draft?.profiles[safe: i]?.name ?? "" }, set: { fe.draft?.profiles[i].name = $0 })).textFieldStyle(.plain).padding(3).darkField().frame(width: 120)
                        Spacer()
                        Button { fe.removeProfile(i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                    TextField("", text: Binding(get: { edits[i] ?? FamilyEditorModel.pointsText(fe.draft?.profiles[safe: i]?.points ?? []) }, set: { edits[i] = $0 }), onCommit: {
                        if let t = edits[i] {
                            if let p = FamilyEditorModel.parsePoints(t, dims: 2), p.count >= 3 { fe.draft?.profiles[i].points = p; edits[i] = nil } else { fe.message = "A profile needs at least three x, y points." }
                        }
                    }).textFieldStyle(.plain).padding(3).darkField()
                }
            }
            Button("Add Profile") { fe.addProfile() }.buttonStyle(FlatButtonStyle(compact: true))
        }
    }
}

/// 3D preview, type picker, flex values, evaluated parameters and problems.
private struct FamilyPreviewColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var fe: FamilyEditorModel
    @Binding var yaw: Double
    var body: some View {
        let d = fe.draft ?? FamilyDefinition(name: "")
        let res = fe.resolved(model.doc)
        let probs = fe.problems(model.doc)
        let b = fe.evaluate(model.doc)?.bounds ?? .empty
        VStack(alignment: .leading, spacing: 6) {
            FamilyPreviewView(groups: fe.previewGroups(model.doc), doc: fe.previewDocument(model.doc), yaw: yaw)
                .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 6))
                .gesture(DragGesture().onChanged { v in yaw = -Double.pi / 6 + Double(v.translation.width) / 120 })
            Text(b.isEmpty ? "Empty" : "Size \(fmt(b.max.x - b.min.x, 0)) × \(fmt(b.max.y - b.min.y, 0)) × \(fmt(b.max.z - b.min.z, 0))").font(Theme.mono)
            if !d.types.isEmpty {
                Picker("Type", selection: Binding(get: { fe.previewType ?? "" }, set: { fe.previewType = $0.isEmpty ? nil : $0 })) {
                    Text("Defaults").tag("")
                    ForEach(d.types.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
            Text("Flex (preview only)").font(Theme.fontBold)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(d.parameters, id: \.name) { p in
                        HStack(spacing: 4) {
                            Text(p.name).lineLimit(1).frame(width: 90, alignment: .leading)
                            if p.formula == nil && p.instance {
                                TextField(res.values[p.name.lowercased()].map { fmt($0, 3) } ?? res.text[p.name.lowercased()] ?? "", text: Binding(get: { fe.flex[p.name] ?? "" }, set: { fe.flex[p.name] = $0 }))
                                    .textFieldStyle(.plain).padding(3).darkField()
                            } else {
                                Text(res.values[p.name.lowercased()].map { fmt($0, 3) } ?? res.text[p.name.lowercased()] ?? "—").font(Theme.mono).foregroundStyle(Theme.textDim)
                                Text(p.formula != nil ? "= formula" : "type").font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
                            }
                        }
                    }
                    if !fe.flex.isEmpty { Button("Reset Flex") { fe.flex = [:] }.buttonStyle(FlatButtonStyle(compact: true)) }
                }
            }
            if !probs.isEmpty {
                VStack(alignment: .leading, spacing: 2) { ForEach(probs.prefix(6), id: \.self) { Text("⚠ " + $0).font(Theme.fontSmall).foregroundStyle(Theme.danger) } }
            }
        }
        .padding(8)
    }
}
