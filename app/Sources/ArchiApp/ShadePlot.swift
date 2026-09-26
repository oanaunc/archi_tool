// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// Shade plot of 3D sheet viewports (SHT-039): axonometric and perspective viewports draw the model seen from a
/// camera as Hidden line (default), Wireframe, As displayed (shaded faces with edges) or Rendered (a raster render
/// placed in the viewport). Sheet view, PDF plot, layered PDF and SVG all use `SheetComposer.viewportEntries`.
@MainActor
enum ShadePlot {
    enum Mode: String, CaseIterable { case asDisplayed = "As Displayed", wireframe = "Wireframe", hidden = "Hidden", rendered = "Rendered" }

    static func key(_ layout: String, _ index: Int) -> String { "SHADEPLOT:\(layout.uppercased()):\(index)" }
    static func cameraKey(_ layout: String, _ index: Int) -> String { "VPCAMERA:\(layout.uppercased()):\(index)" }

    static func is3D(_ vp: Viewport) -> Bool { vp.view == .axonometric || vp.view == .perspective }

    /// Sheet and viewport index of a viewport value (viewports are values; the first equal one wins).
    static func locate(_ vp: Viewport, in doc: ArchiDocument) -> (layout: String, index: Int)? {
        for l in doc.layouts { if let i = l.viewports.firstIndex(of: vp) { return (l.name, i) } }
        return nil
    }

    static func mode(_ doc: ArchiDocument, _ vp: Viewport) -> Mode {
        guard let (l, i) = locate(vp, in: doc), let v = doc.variable(key(l, i)) else { return .hidden }
        return Mode.allCases.first { $0.rawValue.caseInsensitiveCompare(v) == .orderedSame || $0.rawValue.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(v) == .orderedSame } ?? .hidden
    }

    static func setMode(_ m: Mode, layout: String, index: Int, _ doc: inout ArchiDocument) { doc.setVariable(key(layout, index), m.rawValue) }

    /// Cache key part for the sheet view (mode, camera and model state).
    static func cacheKey(_ doc: ArchiDocument, _ vp: Viewport) -> String {
        guard is3D(vp) else { return "" }
        let loc = locate(vp, in: doc)
        return "\(mode(doc, vp).rawValue)|\(loc.flatMap { doc.variable(cameraKey($0.layout, $0.index)) } ?? "")|\(vp.viewCenter.x),\(vp.viewCenter.y)"
    }

    /// Camera of a 3D viewport: a named 3D view (VPCAMERA:<sheet>:<n>), else an SW isometric (axonometric) or an SW
    /// eye-level-ish perspective looking at the model centre.
    static func camera(_ doc: ArchiDocument, _ vp: Viewport) -> Camera? {
        if let (l, i) = locate(vp, in: doc), let n = doc.variable(cameraKey(l, i)) {
            if let c = doc.view(named: n)?.camera { return c }
            if let c = doc.namedViews.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame })?.camera { return c }
        }
        guard var c = ProjectViews.axonCamera("sw", doc: doc) else { return nil }
        if vp.view == .perspective {
            let d = c.eye - c.target
            c.eye = c.target + Vec3(d.x, d.y, d.z * 0.45) * 0.8
            c.orthographic = false
            c.fov = 50
        }
        return c
    }

    static func entries(doc: ArchiDocument, vp: Viewport) -> [DrawEntry] {
        guard let cam = camera(doc, vp) else { return [] }
        let m = mode(doc, vp)
        var raw = ElevationBuilder.entries(doc: doc, camera: cam)
        let box = raw.unionBounds
        guard !box.isEmpty else { return [] }
        switch m {
        case .asDisplayed: break
        case .hidden:
            raw = raw.map { e in DrawEntry(id: e.id, items: e.items.map { if case .fill(let l, _) = $0 { return .fill(loops: l, color: RGBA(1, 1, 1)) }; return $0 }) }
        case .wireframe:
            raw = raw.compactMap { e in
                let items = e.items.filter { if case .fill = $0 { return false }; return true }
                return items.isEmpty ? nil : DrawEntry(id: e.id, items: items)
            }
        case .rendered:
            let px = max(vp.size.x, vp.size.y) * 8
            if let im = renderImage(doc: doc, camera: cam, box: box, maxPixels: Int(min(max(px, 400), 2400))) { raw = [DrawEntry(id: nil, items: [.image(im)])] }
        }
        // Centre the drawing on the viewport's view centre.
        let d = vp.viewCenter - box.center
        return raw.map { e in DrawEntry(id: e.id, items: e.items.map { move($0, d) }) }
    }

    static func move(_ it: DrawItem, _ d: Vec2) -> DrawItem {
        switch it {
        case .stroke(let p, let c, let s): return .stroke(points: p.map { $0 + d }, closed: c, style: s)
        case .fill(let l, let c): return .fill(loops: l.map { $0.map { $0 + d } }, color: c)
        case .text(var t, let f, let c): t.position = t.position + d; return .text(t, font: f, color: c)
        case .image(var im): im.origin = im.origin + d; return .image(im)
        }
    }

    // MARK: Rendered shade plot

    private static var renderCache: [Int: ImageGeom] = [:]

    /// Offscreen SceneKit render framed exactly like the hidden-line projection (same camera), as a PNG placed over `box`.
    static func renderImage(doc: ArchiDocument, camera c: Camera, box: BBox2, maxPixels: Int) -> ImageGeom? {
        var h = Hasher(); h.combine(doc.elements); h.combine(doc.entities.count); h.combine(c); h.combine(maxPixels); h.combine(doc.materials)
        let key = h.finalize()
        if let im = renderCache[key], FileManager.default.fileExists(atPath: im.path) { return im }
        let b = Scene3DBuilder()
        b.update(doc: doc, style: "Realistic")
        let fwd = (c.target - c.eye).normalized
        guard fwd.length > 0.5 else { return nil }
        var extent = box
        let cam = SCNCamera()
        cam.automaticallyAdjustsZRange = true
        let node = SCNNode(); node.camera = cam
        node.position = Scene3DBuilder.world(c.eye)
        node.look(at: Scene3DBuilder.world(c.target), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        var right = fwd.cross(Vec3.unitZ).normalized
        if right.length < 0.5 { right = Vec3(1, 0, 0) }
        let aspect = max(box.width, 1) / max(box.height, 1)
        if c.orthographic {
            // Ortho: image centred on the projected box; move the camera sideways/up to the box centre.
            let up = right.cross(fwd).normalized
            let cx = box.center.x - c.eye.dot(right), cy = box.center.y - c.eye.dot(up)
            node.position = Scene3DBuilder.world(c.eye + right * cx + up * cy)
            cam.usesOrthographicProjection = true
            cam.orthographicScale = box.height * 0.0005
        } else {
            // Perspective: the projection plane is at the target distance, centred on the view axis.
            let D = max(c.eye.distance(to: c.target), 1)
            let hh = max(abs(box.min.y), abs(box.max.y), max(abs(box.min.x), abs(box.max.x)) / aspect)
            extent = BBox2(min: Vec2(-hh * aspect, -hh), max: Vec2(hh * aspect, hh))
            cam.fieldOfView = CGFloat(2 * atan(hh / D) * 180 / .pi)
            cam.projectionDirection = .vertical
        }
        b.scene.rootNode.addChildNode(node)
        let W = aspect >= 1 ? maxPixels : max(Int(Double(maxPixels) * aspect), 16)
        let H = aspect >= 1 ? max(Int(Double(maxPixels) / aspect), 16) : maxPixels
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: dev, options: nil)
        r.scene = b.scene
        r.pointOfView = node
        r.autoenablesDefaultLighting = false
        b.scene.background.contents = NSColor.white
        let img = r.snapshot(atTime: 0, with: CGSize(width: W, height: H), antialiasingMode: .multisampling4X)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiShadePlot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("render-\(UInt(bitPattern: key)).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        let im = ImageGeom(path: url.path, origin: extent.min, size: Vec2(extent.width, extent.height))
        renderCache[key] = im
        return im
    }
}
