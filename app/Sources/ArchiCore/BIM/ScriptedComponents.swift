// Oanarina Archi Tool — GPL-3.0-or-later
// GDL-like scripted BIM objects (PAR-016): an OpenSCAD-language script is the "family" of a BIM component. Its
// Customizer parameters are the object's parameters; each instance stores its own values (props "sp.<name>"), validated
// against the ranges / choices in the script, and the geometry regenerates when the script or a value changes.
// Instances move and rotate like any component (the script origin is the insertion point).
import Foundation

public enum ScriptedComponents {
    public static let scriptKey = "scadScript", paramPrefix = "sp."

    /// Script of an instance with its parameter values applied.
    public static func effectiveScript(_ props: [String: String]) -> String? {
        guard var s = props[scriptKey] else { return nil }
        for (k, v) in props.sorted(by: { $0.key < $1.key }) where k.hasPrefix(paramPrefix) {
            if let t = try? SCADCustomizer.set(s, String(k.dropFirst(paramPrefix.count)), v) { s = t }
        }
        return s
    }

    static func checksum(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }

    /// Component geometry of a script in script-local coordinates (origin = insertion point).
    static func geometry(_ script: String, category: String, position: Vec2, rotation: Double, baseOffset: Double) -> (ComponentGeom?, [String]) {
        let r = SCAD.evaluate(script)
        guard !r.triangles.isEmpty else { return (nil, r.errors.isEmpty ? ["The script makes no solid."] : r.errors) }
        let w = MeshTools.weld(r.triangles, tolerance: 1e-9)
        var b = BBox3.empty; w.vertices.forEach { b.add($0) }
        var g = ComponentGeom(category: category, position: position, rotation: rotation, size: Vec3(max(b.size.x, 1), max(b.size.y, 1), max(b.size.z, 1)), baseOffset: baseOffset)
        g.mesh = SolidGeom(kind: .mesh, origin: b.min, meshVertices: w.vertices, meshTriangles: w.triangles)
        return (g, r.errors)
    }

    @discardableResult
    public static func place(script: String, at p: Vec2, rotation: Double = 0, baseOffset: Double = 0, category: String = "Generic Models", name: String = "Scripted object", doc: inout ArchiDocument) -> EntityID? {
        let (g, errors) = geometry(script, category: category, position: p, rotation: rotation, baseOffset: baseOffset)
        guard let geo = g else { return nil }
        let id = doc.addElement(.component(geo), material: "Wood", name: name)
        if let i = doc.elementIndex(id) {
            doc.elements[i].props[scriptKey] = script
            doc.elements[i].props["scriptSig"] = checksum(script)
            doc.elements[i].props["scriptErrors"] = errors.isEmpty ? nil : errors.joined(separator: "; ")
        }
        return id
    }

    /// Sets an instance parameter (validated); the geometry follows on the next update.
    public static func setParameter(_ id: EntityID, _ name: String, _ value: String, doc: inout ArchiDocument) throws {
        guard let i = doc.elementIndex(id), let base = doc.elements[i].props[scriptKey] else { throw CommandError.invalid("Not a scripted object.") }
        var cur = effectiveScript(doc.elements[i].props) ?? base
        do { cur = try SCADCustomizer.set(cur, name, value) } catch { throw CommandError.invalid("\(name): \(error)") }
        doc.elements[i].props[paramPrefix + name] = value
        _ = cur
        updateAll(&doc)
    }

    /// Parameters of an instance with its current values.
    public static func parameters(_ el: BIMElement) -> [SCADCustomizer.Parameter] {
        guard let s = effectiveScript(el.props) else { return [] }
        return SCADCustomizer.parameters(s)
    }

    public static func hasContent(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props[scriptKey] != nil } }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.elements.indices {
            guard let s = effectiveScript(doc.elements[i].props), case .component(let g) = doc.elements[i].geometry else { continue }
            let sig = checksum(s)
            if doc.elements[i].props["scriptSig"] == sig { continue }
            let (ng, errors) = geometry(s, category: g.category, position: g.position, rotation: g.rotation, baseOffset: g.baseOffset)
            if let geo = ng { doc.elements[i].geometry = .component(geo) }
            doc.elements[i].props["scriptSig"] = sig
            doc.elements[i].props["scriptErrors"] = errors.isEmpty ? nil : errors.joined(separator: "; ")
            changed = true
        }
        return changed
    }
}

enum ScriptedComponentCommands {
    static var all: [CommandDef] { [scripted] }

    static var scripted: CommandDef {
        CommandDef("SCRIPTCOMPONENT", aliases: ["SCRIPTFAMILY", "SCRIPTEDOBJECT", "SCRIPTOBJ", "GDLCOMPONENT"], category: "Architecture", summary: "GDL-like scripted BIM objects: Place a component from an OpenSCAD script (file, or a script solid) whose Customizer parameters become instance parameters; Set a parameter (range-checked) to flex it; List its parameters.") { ed in
            let k = try await ed.getKeyword("Scripted object [Place/Set/List]", ["Place", "Set", "List"], defaultValue: "Place") ?? "Place"
            let isScripted: (EntityID) -> Bool = { ed.doc.element($0)?.props[ScriptedComponents.scriptKey] != nil }
            switch k {
            case "Set", "List":
                guard case .pick(let pk) = try await ed.pickObject("Select a scripted object", filter: isScripted), let el = ed.doc.element(pk.id) else { return }
                let ps = ScriptedComponents.parameters(el)
                if k == "List" {
                    for p in ps { ed.print("  \(p.name) = \(p.value)" + (p.min.map { " [\(fmt($0))…\(fmt(p.max ?? $0))]" } ?? "") + (p.options.isEmpty ? "" : " {\(p.options.joined(separator: ", "))}") + (p.description.isEmpty ? "" : " — \(p.description)")) }
                    if let e = el.props["scriptErrors"] { ed.print("Errors: \(e)") }
                    return
                }
                guard let name = try await ed.getWord("Parameter [" + ps.map(\.name).joined(separator: "/") + "]"), ps.contains(where: { $0.name == name }) else { throw CommandError.invalid("No such parameter.") }
                guard let v = try await ed.getString("Value", defaultValue: ps.first { $0.name == name }?.value) else { return }
                try ScriptedComponents.setParameter(pk.id, name, v, doc: &ed.doc)
                ed.print("\(name) = \(v).")
            default:
                let src = try await ed.getKeyword("Script from [File/Object]", ["File", "Object"], defaultValue: "File") ?? "File"
                var script: String
                if src == "Object" {
                    guard case .pick(let pk) = try await ed.pickObject("Select a script solid", filter: { id in
                        if case .solid(let s)? = ed.doc.entity(id)?.geometry { return s.source?.kind == .script }; return false }),
                          case .solid(let s)? = ed.doc.entity(pk.id)?.geometry, let e = s.source?.expression else { return }
                    script = e
                } else {
                    guard let path = try await ed.getString("OpenSCAD file") else { return }
                    guard let t = try? String(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), encoding: .utf8) else { throw CommandError.invalid("Cannot read \(path).") }
                    script = t
                }
                let p = try await ed.requirePoint("Insertion point")
                let rot = try await ed.getAngle("Rotation", base: p, defaultValue: 0).value ?? 0
                let cat = try await ed.getWord("Category", defaultValue: "Generic Models") ?? "Generic Models"
                let name = try await ed.getString("Name", defaultValue: "Scripted object") ?? "Scripted object"
                guard let id = ScriptedComponents.place(script: script, at: p, rotation: rot, category: cat, name: name, doc: &ed.doc) else { throw CommandError.invalid("The script makes no solid.") }
                ed.selection = [id]
                ed.print("Scripted object #\(id) with \(SCADCustomizer.parameters(script).count) parameter(s).")
            }
        }
    }
}
