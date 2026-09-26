// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Fill patterns bound to materials (ANN-072). Every material has a cut pattern (`Material.cutPattern`, drawn where
/// walls and other elements are cut in plans and sections) and a surface pattern (document variable
/// MATSURFACE:<material>, e.g. tile or brick coursing seen in elevation / on floors). Hatches bound to a material
/// (props `material` and `materialPattern` = cut | surface) always show that material's pattern: the pattern name,
/// scale (real-world patterns at true size, drafting patterns at 15 mm per unit like the plan cut patterns) and — with
/// `materialShade` = 1 — a background fill in the material colour are kept in the hatch itself by a document updater,
/// so screen, PDF, SVG and DXF all carry the current material pattern, and associative hatches still follow their
/// boundary.
public enum MaterialPatterns {
    public static let prop = "material"
    public static let kindProp = "materialPattern"
    public static let shadeProp = "materialShade"
    public static let scaleProp = "materialScale"
    public static let surfacePrefix = "MATSURFACE:"

    public enum Kind: String, CaseIterable { case cut, surface }

    public static func surfacePattern(_ material: String, doc: ArchiDocument) -> String? {
        guard let m = doc.material(material) else { return nil }
        let v = doc.variable(surfacePrefix + m.name)?.trimmingCharacters(in: .whitespaces)
        return v?.isEmpty == false ? v : nil
    }
    public static func pattern(_ material: String, kind: Kind, doc: ArchiDocument) -> String? {
        guard let m = doc.material(material) else { return nil }
        switch kind {
        case .cut: return m.cutPattern
        case .surface: return surfacePattern(m.name, doc: doc)
        }
    }
    /// Sets a material's cut or surface pattern (validated against the known patterns). Returns false when unknown.
    @discardableResult
    public static func setPattern(_ material: String, kind: Kind, pattern: String?, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.materials.firstIndex(where: { $0.name.caseInsensitiveCompare(material) == .orderedSame }) else { return false }
        let p = pattern?.uppercased()
        if let p, !HatchPatterns.allNames.contains(p) { return false }
        switch kind {
        case .cut: doc.materials[i].cutPattern = p ?? "SOLID"
        case .surface:
            if let p { doc.setVariable(surfacePrefix + doc.materials[i].name, p) } else { doc.variables[(surfacePrefix + doc.materials[i].name).uppercased()] = nil; doc.variables[surfacePrefix + doc.materials[i].name] = nil }
        }
        return true
    }

    /// Scale used for a material pattern (the same rule as the plan cut patterns).
    public static func scale(_ pattern: String, doc: ArchiDocument) -> Double { PlanRepresentation.patternScale(pattern, doc) }

    /// The hatch a material-bound hatch should currently be (nil when the entity is not bound or the material is gone).
    public static func resolved(_ e: Entity, doc: ArchiDocument) -> HatchGeom? {
        guard case .hatch(var h) = e.geometry, let mat = e.props[prop], let m = doc.material(mat) else { return nil }
        let kind = Kind(rawValue: (e.props[kindProp] ?? "cut").lowercased()) ?? .cut
        let pat = pattern(m.name, kind: kind, doc: doc) ?? "SOLID"
        h.pattern = pat
        if pat.uppercased() != "SOLID" { h.scale = scale(pat, doc: doc) * (e.props[scaleProp].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? 1) }
        let c = m.color
        let rgb = ColorRef.rgb(UInt8((max(0, min(1, c.r)) * 255).rounded()), UInt8((max(0, min(1, c.g)) * 255).rounded()), UInt8((max(0, min(1, c.b)) * 255).rounded()))
        if pat.uppercased() == "SOLID" || e.props[shadeProp] == "1" { h.fill = rgb } else { h.fill = nil }
        return h
    }

    /// Keeps material-bound hatches in step with their materials. Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices where doc.entities[i].props[prop] != nil && doc.entities[i].props[FloorPatterns.prop] == nil {
            guard let h = resolved(doc.entities[i], doc: doc), case .hatch(let old) = doc.entities[i].geometry, h != old else { continue }
            doc.entities[i].geometry = .hatch(h); changed = true
        }
        return changed
    }

    /// Binds a hatch to a material.
    public static func bind(_ e: inout Entity, material: String, kind: Kind, shade: Bool, doc: ArchiDocument) -> Bool {
        guard case .hatch = e.geometry, let m = doc.material(material) else { return false }
        e.props[prop] = m.name; e.props[kindProp] = kind.rawValue; e.props[shadeProp] = shade ? "1" : nil
        if let h = resolved(e, doc: doc) { e.geometry = .hatch(h) }
        return true
    }
}
