// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Per-sheet presentation stored in the existing extensible titleBlock dictionary.
/// No document schema change: older drawings keep their original appearance.
public enum SheetCustomization {
    public enum Part: String, CaseIterable {
        case frame = "Frame", titleBlock = "TitleBlock", north = "North", scaleBar = "ScaleBar", captions = "Captions"
    }
    public static func key(_ part: Part, _ field: String) -> String { "presentation:\(part.rawValue):\(field)" }
    public static func visible(_ part: Part, in layout: Layout) -> Bool { layout.titleBlock[key(part, "visible")] != "0" }
    public static func offset(_ part: Part, in layout: Layout) -> Vec2 {
        func number(_ field: String) -> Double {
            guard let n = Double(layout.titleBlock[key(part, field)] ?? "0"), n.isFinite else { return 0 }
            return n
        }
        return Vec2(number("x"), number("y"))
    }
    public static func set(_ part: Part, visible: Bool, offset: Vec2, in layout: inout Layout) {
        guard offset.x.isFinite, offset.y.isFinite else { return }
        layout.titleBlock[key(part, "visible")] = visible ? nil : "0"
        layout.titleBlock[key(part, "x")] = offset.x == 0 ? nil : String(offset.x)
        layout.titleBlock[key(part, "y")] = offset.y == 0 ? nil : String(offset.y)
    }
    public static func apply(_ entries: [DrawEntry], part: Part, layout: Layout) -> [DrawEntry] {
        guard visible(part, in: layout) else { return [] }
        let delta = offset(part, in: layout)
        guard delta != .zero else { return entries }
        return entries.map { entry in
            DrawEntry(id: entry.id, items: entry.items.map { item in
                switch item {
                case .stroke(let pts, let closed, let style): return .stroke(points: pts.map { $0 + delta }, closed: closed, style: style)
                case .fill(let loops, let color): return .fill(loops: loops.map { $0.map { $0 + delta } }, color: color)
                case .text(var t, let font, let color): t.position = t.position + delta; return .text(t, font: font, color: color)
                case .image(var image): image.origin = image.origin + delta; return .image(image)
                }
            })
        }
    }
    /// Applies one decoration group just appended by either the native or portable renderer.
    public static func finish(_ entries: inout [DrawEntry], from start: Int, part: Part, layout: Layout) {
        let result = apply(Array(entries[start...]), part: part, layout: layout)
        entries.replaceSubrange(start..., with: result)
    }
}

public enum SheetViewportEditing {
    public static func updated(_ viewport: Viewport, property: String, point: Vec2 = .zero,
                               ratio: Double = 100, doc: ArchiDocument, layoutIndex: Int, index: Int) throws -> Viewport {
        guard doc.layouts.indices.contains(layoutIndex), doc.layouts[layoutIndex].viewports.indices.contains(index) else { throw CommandError.invalid("No viewport.") }
        guard !EngineViewports.isLocked(doc, layoutIndex, index) else { throw CommandError.invalid("The viewport is locked (VPLOCK Off to unlock).") }
        guard point.x.isFinite, point.y.isFinite, ratio.isFinite else { throw CommandError.invalid("Enter finite values.") }
        var vp = viewport
        switch property {
        case "Position": vp.origin = point
        case "Size":
            guard point.x > 0, point.y > 0 else { throw CommandError.invalid("Width and height must be positive.") }
            vp.size = point
        case "Center": vp.viewCenter = point
        case "Scale":
            guard ratio > 0 else { throw CommandError.invalid("Scale must be positive.") }
            vp.scale = ratio / doc.units.mm
        case "CenterContent":
            guard vp.view != .axonometric && vp.view != .perspective else { throw CommandError.invalid("Use a plan, ceiling, section or elevation viewport.") }
            let b = ViewportFraming.bounds(doc: doc, viewport: vp, layoutIndex: layoutIndex, index: index)
            guard !b.isEmpty else { throw CommandError.invalid("No plotted content at this level. Check layers and Plot settings.") }
            vp.viewCenter = b.center
        case "CenterOnSheet":
            let paper = doc.layouts[layoutIndex].paper
            vp.origin = (Vec2(paper.width, paper.height) - vp.size) / 2
        default: throw CommandError.invalid("Unknown viewport property.")
        }
        return vp
    }
}

enum SheetCustomizationCommands {
    static var all: [CommandDef] { [
        CommandDef("SHEETSTYLE", aliases: ["SHTSTYLE", "SHEETCUSTOMIZE"], category: "Output", summary: "Shows, hides or moves the current sheet's frame, title block, north arrow, scale bar or captions. Offsets are paper mm.") { ed in
            guard let li = FileViewCommands.currentLayoutIndex(ed) else { throw CommandError.invalid("No sheet.") }
            let name = try await ed.getKeyword("Sheet element", SheetCustomization.Part.allCases.map(\.rawValue), defaultValue: "North") ?? "North"
            guard let part = SheetCustomization.Part(rawValue: name) else { return }
            let action = try await ed.getKeyword("Presentation", ["Show", "Hide", "Move", "Reset"], defaultValue: "Hide") ?? "Hide"
            let layout = ed.doc.layouts[li]
            var visible = SheetCustomization.visible(part, in: layout), offset = SheetCustomization.offset(part, in: layout)
            switch action {
            case "Show": visible = true
            case "Hide": visible = false
            case "Reset": visible = true; offset = .zero
            case "Move":
                guard let p = try await ed.getPoint("Offset x,y from the default position (paper mm)").point else { return }
                offset = p
            default: break
            }
            SheetCustomization.set(part, visible: visible, offset: offset, in: &ed.doc.layouts[li])
            ed.print("\(name): \(visible ? "shown" : "hidden"), offset \(fmt(offset.x, 2)),\(fmt(offset.y, 2)) mm.")
        },
        CommandDef("VPEDIT", aliases: ["VPE", "VIEWPORTEDIT"], category: "Output", summary: "Edits a viewport's paper Position/Size, model Center, print Scale, or centres content without changing scale (CenterContent), or centres its frame on the page (CenterOnSheet).") { ed in
            guard let li = FileViewCommands.currentLayoutIndex(ed), !ed.doc.layouts[li].viewports.isEmpty else { throw CommandError.invalid("The sheet has no viewports.") }
            guard let n = try await ed.getInteger("Viewport number", defaultValue: 1), ed.doc.layouts[li].viewports.indices.contains(n - 1) else { throw CommandError.invalid("No viewport.") }
            let property = try await ed.getKeyword("Property", ["Position", "Size", "Center", "Scale", "CenterContent", "CenterOnSheet"], defaultValue: "CenterContent") ?? "CenterContent"
            var point = Vec2.zero, ratio = 100.0
            if ["Position", "Size", "Center"].contains(property) {
                guard let p = try await ed.getPoint(property == "Center" ? "Model centre x,y (drawing units)" : "x,y (paper mm)").point else { return }; point = p
            } else if property == "Scale" {
                guard let word = try await ed.getWord("Print scale (e.g. 1:100)"), let s = FileViewCommands.parseScale(word) else { throw CommandError.invalid("Invalid scale.") }; ratio = s
            }
            ed.doc.layouts[li].viewports[n - 1] = try SheetViewportEditing.updated(ed.doc.layouts[li].viewports[n - 1], property: property, point: point, ratio: ratio, doc: ed.doc, layoutIndex: li, index: n - 1)
            ed.print("Viewport \(n): \(property) updated.")
        }
    ] }
}
