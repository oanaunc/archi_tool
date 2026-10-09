// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

extension AppSelfTests {
    static func macFeedbackChecks(_ check: (Bool, String) -> Void) {
        let m = AppModel()
        let canvas = PlanCanvasView(model: m)
        // An opaque canvas must paint its backing surface even before its child layers render.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        canvas.draw(NSRect(x: 0, y: 0, width: 100, height: 80))
        NSGraphicsContext.restoreGraphicsState()
        check((rep.colorAt(x: 50, y: 40)?.alphaComponent ?? 0) > 0.99, "2D canvas paints an opaque backing surface")
        check(canvas.layer?.masksToBounds == true, "2D canvas clips its layers to the workspace")
        let saved = UserDefaults.standard.object(forKey: "ribbonCollapsed")
        UserDefaults.standard.set(false, forKey: "ribbonCollapsed")
        defer { UserDefaults.standard.set(saved, forKey: "ribbonCollapsed") }
        let ribbon = NSHostingView(rootView: RibbonView(model: m).preferredColorScheme(.dark))
        for width in [600.0, 1440.0, 2532.0] {
            ribbon.frame = NSRect(x: 0, y: 0, width: width, height: 118)
            ribbon.layoutSubtreeIfNeeded()
            check(ribbon.fittingSize.height >= 116, "ribbon keeps its height at \(Int(width)) pt")
        }
        check(m.editor.registry.lookup("RB")?.name == "CLEANSCREENOFF", "RIBBON / RB recovery command registered")
        // The Mac composition uses the same per-sheet section graphics as the portable PDF writer.
        var doc = ArchiDocument()
        _ = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 200, height: 3000)))
        let vp = Viewport(origin: Vec2(30, 70), size: Vec2(200, 150), viewCenter: Vec2(2500, 1500), scale: 50, view: .section)
        let style = SectionSheetStyle(lines: ObjectStyle(color: RGBA(0.8, 0.1, 0.2)), shaded: false)
        style.store(in: &doc.layouts[0])
        let mac = SheetComposer.viewportEntries(doc: doc, vp: vp, layout: doc.layouts[0].name)
        let engine = EnginePlot.viewportEntries(doc: doc, vp: vp, layout: doc.layouts[0].name)
        check(mac == engine, "Mac sheet and portable plot share section style rendering")
    }
}
