// Oanarina Archi Tool — GPL-3.0-or-later
// Door/window family builder: parametric family definitions for common door and window configurations
// (origin at the opening centre on the wall centreline at sill level; X along the wall, Y across, Z up).
import Foundation

public enum FamilyTemplates {
    public static let doorStyles = ["Single", "Double", "Glazed", "Panelled", "DoubleGlazed"]
    public static let windowStyles = ["Grid", "Casement", "Fixed", "Transom"]

    static func P(_ n: String, _ v: String, _ k: FamilyParameterKind = .length, formula: String? = nil, instance: Bool = true, min: Double? = nil, max: Double? = nil) -> FamilyParameter {
        FamilyParameter(n, k, value: v, formula: formula, instance: instance, min: min, max: max)
    }

    /// Frame (two jambs and a head) shared by doors and windows; `sill` adds a bottom rail.
    static func frame(sill: Bool) -> [FamilyForm] {
        var f: [FamilyForm] = [
            FamilyForm(.box, name: "Jamb L", x: "-Width/2", y: "-FrameDepth/2", dims: ["width": "FrameWidth", "depth": "FrameDepth", "height": "Height"], material: "=FrameMaterial"),
            FamilyForm(.box, name: "Jamb R", x: "Width/2 - FrameWidth", y: "-FrameDepth/2", dims: ["width": "FrameWidth", "depth": "FrameDepth", "height": "Height"], material: "=FrameMaterial"),
            FamilyForm(.box, name: "Head", x: "-Width/2 + FrameWidth", y: "-FrameDepth/2", z: "Height - FrameWidth", dims: ["width": "Width - 2*FrameWidth", "depth": "FrameDepth", "height": "FrameWidth"], material: "=FrameMaterial"),
        ]
        if sill { f.append(FamilyForm(.box, name: "Sill rail", x: "-Width/2 + FrameWidth", y: "-FrameDepth/2", dims: ["width": "Width - 2*FrameWidth", "depth": "FrameDepth", "height": "FrameWidth"], material: "=FrameMaterial")) }
        return f
    }

    /// A door family of a given style.
    public static func door(name: String, style: String = "Single", width: Double = 900, height: Double = 2100) -> FamilyDefinition {
        let st = style.lowercased()
        let double = st.hasPrefix("double")
        let glazed = st.contains("glazed")
        var params: [FamilyParameter] = [
            P("Width", fmt(width), min: 400, max: 4000), P("Height", fmt(height), min: 1500, max: 4000),
            P("WallThickness", "200"), P("FrameWidth", "50", instance: false), P("FrameDepth", "0", formula: "min(WallThickness, 120)"),
            P("LeafThickness", "40", instance: false), P("Leaves", double ? "2" : "1", .integer, min: 1, max: 2),
            P("LeafWidth", "0", formula: "(Width - 2*FrameWidth - 4*Leaves) / Leaves"), P("LeafHeight", "0", formula: "Height - FrameWidth - 10"),
            P("Glazed", glazed ? "1" : "0", .yesNo), P("GlassMargin", "150", instance: false),
            P("Panels", st == "panelled" ? "3" : "0", .integer, min: 0, max: 8),
            P("FrameMaterial", "Wood", .material, instance: false), P("LeafMaterial", "Wood", .material, instance: false),
        ]
        params.append(P("PanelHeight", "0", formula: "if(Panels > 0, (LeafHeight - 150*(Panels + 1)) / max(Panels, 1), 0)"))
        let forms: [FamilyForm] = frame(sill: false) + [
            FamilyForm(.box, name: "Leaf", x: "-Width/2 + FrameWidth + 2", y: "-LeafThickness/2", z: "5", dims: ["width": "LeafWidth", "depth": "LeafThickness", "height": "LeafHeight"],
                       material: "=LeafMaterial", arrayCount: "Leaves", arrayDX: "LeafWidth + 4"),
            FamilyForm(.box, name: "Glazing cut", x: "-Width/2 + FrameWidth + 2 + GlassMargin", y: "-LeafThickness", z: "5 + LeafHeight*0.35",
                       dims: ["width": "LeafWidth - 2*GlassMargin", "depth": "2*LeafThickness", "height": "LeafHeight*0.65 - GlassMargin"],
                       visible: "Glazed", void: true, arrayCount: "Leaves", arrayDX: "LeafWidth + 4"),
            FamilyForm(.box, name: "Glass", x: "-Width/2 + FrameWidth + 2 + GlassMargin", y: "-4", z: "5 + LeafHeight*0.35",
                       dims: ["width": "LeafWidth - 2*GlassMargin", "depth": "8", "height": "LeafHeight*0.65 - GlassMargin"], material: "Glass",
                       visible: "Glazed", arrayCount: "Leaves", arrayDX: "LeafWidth + 4"),
            FamilyForm(.box, name: "Raised panel", x: "-Width/2 + FrameWidth + 2 + 120", y: "-LeafThickness/2 - 8", z: "5 + 150",
                       dims: ["width": "LeafWidth - 240", "depth": "LeafThickness + 16", "height": "PanelHeight"], material: "=LeafMaterial",
                       visible: "Panels > 0 && Glazed == 0", arrayCount: "Panels", arrayDZ: "PanelHeight + 150"),
            FamilyForm(.cylinder, name: "Handle", x: "if(Leaves == 2, -60, Width/2 - FrameWidth - 70)", y: "-LeafThickness/2 - 50", z: "1000",
                       rotation: "0", dims: ["radius": "10", "height": "140"], material: "Aluminium"),
        ]
        return FamilyDefinition(name: name, category: "Door", parameters: params, forms: forms,
                                types: ["800x2100": ["Width": "800", "Height": "2100"], "900x2100": ["Width": "900", "Height": "2100"], "1000x2200": ["Width": "1000", "Height": "2200"]],
                                description: "Door family (\(style)) built by the door/window family builder.")
    }

    /// A window family: a frame divided into Columns × Rows lights with glazing bars and an exterior sill.
    public static func window(name: String, style: String = "Grid", width: Double = 1200, height: Double = 1200, columns: Int = 2, rows: Int = 1) -> FamilyDefinition {
        let st = style.lowercased()
        let cols = st == "fixed" ? 1 : max(1, columns), rws = st == "transom" ? max(2, rows) : max(1, rows)
        let params: [FamilyParameter] = [
            P("Width", fmt(width), min: 300, max: 6000), P("Height", fmt(height), min: 300, max: 4000), P("WallThickness", "200"),
            P("FrameWidth", "60", instance: false), P("FrameDepth", "0", formula: "min(WallThickness, 80)"),
            P("Columns", "\(cols)", .integer, min: 1, max: 12), P("Rows", "\(rws)", .integer, min: 1, max: 8), P("BarWidth", "50", instance: false),
            P("ColumnWidth", "0", formula: "(Width - 2*FrameWidth) / Columns"), P("RowHeight", "0", formula: "(Height - 2*FrameWidth) / Rows"),
            P("SillDepth", "60", instance: false), P("FrameMaterial", "Aluminium", .material, instance: false),
        ]
        let forms: [FamilyForm] = frame(sill: true) + [
            FamilyForm(.box, name: "Mullions", x: "-Width/2 + FrameWidth + ColumnWidth - BarWidth/2", y: "-FrameDepth/2 + 5", z: "FrameWidth",
                       dims: ["width": "BarWidth", "depth": "FrameDepth - 10", "height": "Height - 2*FrameWidth"], material: "=FrameMaterial",
                       visible: "Columns > 1", arrayCount: "Columns - 1", arrayDX: "ColumnWidth"),
            FamilyForm(.box, name: "Transoms", x: "-Width/2 + FrameWidth", y: "-FrameDepth/2 + 5", z: "FrameWidth + RowHeight - BarWidth/2",
                       dims: ["width": "Width - 2*FrameWidth", "depth": "FrameDepth - 10", "height": "BarWidth"], material: "=FrameMaterial",
                       visible: "Rows > 1", arrayCount: "Rows - 1", arrayDZ: "RowHeight"),
            FamilyForm(.box, name: "Glass", x: "-Width/2 + FrameWidth", y: "-4", z: "FrameWidth",
                       dims: ["width": "Width - 2*FrameWidth", "depth": "8", "height": "Height - 2*FrameWidth"], material: "Glass"),
            FamilyForm(.box, name: "Exterior sill", x: "-Width/2 - 40", y: "-WallThickness/2 - SillDepth", z: "-30",
                       dims: ["width": "Width + 80", "depth": "SillDepth + WallThickness/2 - FrameDepth/2", "height": "30"], material: "=FrameMaterial"),
        ]
        return FamilyDefinition(name: name, category: "Window", parameters: params, forms: forms,
                                types: ["1200x1200": ["Width": "1200", "Height": "1200"], "1500x1400": ["Width": "1500", "Height": "1400"]],
                                description: "Window family (\(style), \(cols)×\(rws) lights) built by the door/window family builder.")
    }

    /// A profile family: a named 2D profile flexing with Width/Height (used by sweeps, railings, gutters).
    public static func profile(name: String, points: [Vec2], width: Double, height: Double) -> FamilyDefinition {
        // Normalise the sketch to 0…1 and express vertices as fractions of Width/Height.
        let b = BBox2(points: points)
        let w = max(b.width, 1e-9), h = max(b.height, 1e-9)
        let pts = points.map { p -> [String] in ["Width*\(fmt((p.x - b.min.x) / w, 6))", "Height*\(fmt((p.y - b.min.y) / h, 6))"] }
        return FamilyDefinition(name: name, category: "Profile", parameters: [P("Width", fmt(width)), P("Height", fmt(height))],
                                profiles: [FamilyProfile(name: name, points: pts)], description: "Profile family")
    }
}
