// Oanarina Archi Tool — GPL-3.0-or-later
// Built-in drawing templates for doc.new {template: "metric" | "imperial" | "building"} (the Windows app's File ▸ New
// from Template). Portable copy of the document part of FileController.template in ArchiApp (keep the two in step).
import Foundation

enum EngineTemplates {
    static let names: Set<String> = ["metric", "blankmetric", "imperial", "blankimperial", "building", "sample"]

    /// The template document and drafting settings, or nil when `name` is not a built-in template (then it is a path).
    static func make(_ name: String) -> (ArchiDocument, DraftSettings)? {
        let kind = name.lowercased()
        guard names.contains(kind) else { return nil }
        var d = ArchiDocument()
        var s = DraftSettings()
        switch kind {
        case "imperial", "blankimperial":
            d.units = .inches
            d.setVariable("MEASUREMENT", "0")
            d.setVariable("LTSCALE", "0.04")
            d.dimStyles = [DimStyle(name: "Standard", textHeight: 0.18, arrowSize: 0.18, extensionOffset: 0.0625, extensionExtend: 0.18, textGap: 0.09, decimals: 2),
                           DimStyle(name: "Architectural 1/4\"", textHeight: 6, arrowSize: 4, arrow: .architecturalTick, extensionOffset: 2, extensionExtend: 4, textGap: 2)]
            d.levels = [Level(id: 0, name: "Ground Floor", elevation: 0, height: 108), Level(id: 1, name: "First Floor", elevation: 120, height: 108)]
            s.gridSpacing = 12
            s.textHeight = 6
            s.wallThickness = 8
            s.wallHeight = 108
            s.offsetDistance = 4
        case "building", "sample":
            d.info.name = kind == "sample" ? "Sample House" : "New Building"
            d.levels = [Level(id: 0, name: "Level 0 — Ground", elevation: 0, height: 3000), Level(id: 1, name: "Level 1 — First", elevation: 3000, height: 3000),
                        Level(id: 2, name: "Roof", elevation: 6000, height: 3000)]
            d.currentDimStyle = "Architectural 1:100"
            d.currentLayer = "0"
            if kind == "building" {
                let xs: [Double] = [0, 6000, 12000, 18000], ys: [Double] = [0, 6000, 12000]
                for (i, x) in xs.enumerated() { d.addElement(.gridLine(GridLineGeom(start: Vec2(x, -2000), end: Vec2(x, 14000), label: "\(i + 1)")), level: 0) }
                for (i, y) in ys.enumerated() { d.addElement(.gridLine(GridLineGeom(start: Vec2(-2000, y), end: Vec2(20000, y), label: String(UnicodeScalar(65 + i)!))), level: 0) }
            }
            d.layouts = d.levels.prefix(2).enumerated().map { i, l in
                Layout(name: "A10\(i + 1) — \(l.name)", paper: PaperSize.standard[1],
                       viewports: [Viewport(origin: Vec2(15, 15), size: Vec2(330, 267), viewCenter: Vec2(9000, 6000), scale: 100, view: .plan, level: l.id, title: l.name)],
                       titleBlock: ["project": d.info.name, "sheetNumber": "A10\(i + 1)", "scale": "1:100"])
            }
            d.layouts.append(Layout(name: "A201 — Elevations", paper: PaperSize.standard[1],
                                    viewports: [Viewport(origin: Vec2(15, 150), size: Vec2(330, 130), viewCenter: Vec2(9000, 3000), scale: 100, view: .elevationSouth, title: "South Elevation"),
                                                Viewport(origin: Vec2(15, 15), size: Vec2(330, 130), viewCenter: Vec2(9000, 3000), scale: 100, view: .elevationEast, title: "East Elevation")],
                                    titleBlock: ["project": d.info.name, "sheetNumber": "A201", "scale": "1:100"]))
        default: break
        }
        return (d, s)
    }
}
