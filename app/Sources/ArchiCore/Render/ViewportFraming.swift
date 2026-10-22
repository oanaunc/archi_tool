// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Frame the content actually plotted by a viewport, rather than unrelated levels or non-plotting objects.
public enum ViewportFraming {
    public static func bounds(doc: ArchiDocument, viewport: Viewport, layoutIndex: Int? = nil, index: Int? = nil) -> BBox2 {
        var source = doc
        var name: String?
        if let li = layoutIndex, doc.layouts.indices.contains(li) {
            name = doc.layouts[li].name
            if let index { source = ViewportLayers.document(for: doc, layout: doc.layouts[li].name, viewport: index) }
        }
        return EnginePlot.viewportEntries(doc: source, vp: viewport, layout: name, index: index)
            .reduce(BBox2.empty) { $0.union($1.bounds) }
    }

    /// Keeps the paper frame and level; fits plotted content inside it with a small margin. Empty views stay intact.
    public static func fitted(_ viewport: Viewport, bounds: BBox2) -> Viewport? {
        guard !bounds.isEmpty, viewport.size.x > 0, viewport.size.y > 0 else { return nil }
        var vp = viewport
        vp.viewCenter = bounds.center
        let scale = max(bounds.width / (vp.size.x * 0.9), bounds.height / (vp.size.y * 0.9))
        if scale > 0, scale.isFinite { vp.scale = scale }
        return vp
    }
}
