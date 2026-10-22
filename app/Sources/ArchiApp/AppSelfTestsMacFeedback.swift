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

        // A different level far from the current plan must not move a dropped viewport off its contents.
        var sheetDoc = ArchiDocument()
        sheetDoc.levels.append(Level(id: 99, name: "Remote storey", elevation: 10000))
        _ = sheetDoc.addElement(.wall(WallGeom(start: Vec2(100000, 200000), end: Vec2(105000, 200000), thickness: 200, height: 3000)))
        _ = sheetDoc.addElement(.wall(WallGeom(start: Vec2(-500000, -500000), end: Vec2(-495000, -500000), thickness: 200, height: 3000)), level: 99)
        let payload = ViewDrop.string(.plan, level: sheetDoc.currentLevel)
        guard let vi = ViewDrop.place(payload, at: Vec2(200, 170), layoutIndex: 0, doc: &sheetDoc) else { check(false, "offset plan placed on sheet"); return }
        let placed = sheetDoc.layouts[0].viewports[vi]
        check(abs(placed.viewCenter.x - 102500) < 1, "dropped plan centres on its plotted level")
        // Exercise the actual Mac sheet renderer at 1× and Retina 2×, counting only the viewport interior.
        for backing in [1, 2] {
            let w = 840 * backing, h = 594 * backing
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            context.setFillColor(CGColor.white); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let scale = CGFloat(2 * backing)
            SheetComposer.draw(doc: sheetDoc, layoutIndex: 0, in: context,
                               paperToDevice: CGAffineTransform(scaleX: scale, y: scale), devicePerMM: scale,
                               showViewportBorders: false, visible: CGRect(x: 0, y: 0, width: w, height: h))
            var dark = 0
            for y in Int((placed.origin.y + 1) * scale)..<Int((placed.origin.y + placed.size.y - 1) * scale) {
                for x in Int((placed.origin.x + 1) * scale)..<Int((placed.origin.x + placed.size.x - 1) * scale) {
                    if let c = bitmap.colorAt(x: x, y: h - 1 - y)?.usingColorSpace(.deviceRGB), c.redComponent < 0.7 { dark += 1 }
                }
            }
            check(dark > 20, "Mac sheet contains plan pixels at \(backing)× backing scale")
        }
    }
}
