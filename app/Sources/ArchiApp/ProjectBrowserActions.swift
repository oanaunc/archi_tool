// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// What the project browser opens (APP-027): project views (plan / ceiling / 3D and camera objects), named views and
/// sheets. Shared by the browser panel (click / double-click) and the self tests.
@MainActor
enum ProjectBrowser {
    static func symbol(_ v: ProjectView) -> String {
        switch v.kind { case "3d": return v.camera?.orthographic == false ? "camera" : "cube"; case "ceiling": return "square.3.layers.3d.top.filled"; default: return "square.split.bottomrightquarter" }
    }

    /// Opens a project view: applies its settings and level, then shows the plan (zoomed to its crop) or the 3D camera.
    static func openView(_ name: String, model: AppModel) {
        guard let v = model.doc.view(named: name) else { return }
        model.editor.transaction("Open View") { _ = ProjectViews.open(v.name, doc: &$0) }
        if v.kind == "3d" {
            if model.mode == .plan || model.mode == .sheet { model.mode = .model }
            model.files.handle(.setView("named:" + v.name))
        } else {
            if model.mode == .sheet || model.mode == .model { model.mode = .plan }
            if let c = ProjectViews.effectiveCrop(v, doc: model.doc) {
                let b = BBox2(points: c)
                DispatchQueue.main.async { model.canvas?.zoom(to: b.expanded(by: 500 / model.doc.units.mm)) }
            }
            model.revision &+= 1
        }
    }

    /// Opens a named view: cameras in 3D, plan windows in 2D.
    static func openNamedView(_ v: NamedView, model: AppModel) {
        if v.camera != nil {
            if model.mode == .plan || model.mode == .sheet { model.mode = .model }
            model.files.handle(.setView("named:" + v.name))
        } else {
            model.mode = .plan
            let h = v.height, w = h * 1.6
            DispatchQueue.main.async { model.canvas?.zoom(toRect: CGRect(x: v.center.x - w / 2, y: v.center.y - h / 2, width: w, height: h)) }
        }
    }

    static func openSheet(_ i: Int, model: AppModel) {
        guard model.doc.layouts.indices.contains(i) else { return }
        model.activeLayout = i
        model.mode = .sheet
    }
}
