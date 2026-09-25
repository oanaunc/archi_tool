// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Resolved 2D drawing primitives shared by the screen canvas, PDF/print and SVG export.
public struct StrokeStyle: Hashable {
    public var color: RGBA
    /// Plotted line weight in millimetres.
    public var lineweight: Double
    /// Dash pattern in drawing units (positive dash, negative gap, 0 dot). Empty = continuous.
    public var dash: [Double]
    public init(color: RGBA, lineweight: Double = 0.25, dash: [Double] = []) { self.color = color; self.lineweight = lineweight; self.dash = dash }
}

public enum DrawItem: Hashable {
    /// Open or closed polyline.
    case stroke(points: [Vec2], closed: Bool, style: StrokeStyle)
    /// Filled region; multiple loops use the even-odd rule.
    case fill(loops: [[Vec2]], color: RGBA)
    /// Text with resolved font and color.
    case text(TextGeom, font: String, color: RGBA)
    case image(ImageGeom)
}

/// Draw items for one object; `id` is nil for non-selectable decoration.
public struct DrawEntry: Hashable {
    public var id: EntityID?
    public var items: [DrawItem]
    public var bounds: BBox2
    public init(id: EntityID?, items: [DrawItem]) {
        self.id = id; self.items = items
        var b = BBox2.empty
        for it in items {
            switch it {
            case .stroke(let p, _, _): p.forEach { b.add($0) }
            case .fill(let l, _): l.forEach { $0.forEach { b.add($0) } }
            case .text(let t, _, _): GeometryOps.textBoxCorners(t).forEach { b.add($0) }
            case .image(let im): b.add(im.origin); b.add(im.origin + im.size)
            }
        }
        self.bounds = b
    }
}
