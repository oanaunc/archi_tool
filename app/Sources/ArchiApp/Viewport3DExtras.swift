// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import ArchiCore

// MARK: - Section box (model millimetres, persisted in the SECTIONBOX variable)

struct SectionBox: Equatable {
    var on: Bool
    var min: Vec3
    var max: Vec3

    static let variable = "SECTIONBOX"

    static func load(_ doc: ArchiDocument) -> SectionBox? {
        guard let s = doc.variables[variable] else { return nil }
        let parts = s.split(separator: ";")
        guard parts.count == 2 else { return nil }
        let n = parts[1].split(separator: ",").compactMap { Double($0) }
        guard n.count == 6, n.allSatisfy(\.isFinite) else { return nil }
        return SectionBox(on: parts[0] == "on", min: Vec3(Swift.min(n[0], n[3]), Swift.min(n[1], n[4]), Swift.min(n[2], n[5])),
                          max: Vec3(Swift.max(n[0], n[3]), Swift.max(n[1], n[4]), Swift.max(n[2], n[5])))
    }

    var stored: String {
        (on ? "on" : "off") + ";" + [min.x, min.y, min.z, max.x, max.y, max.z].map { fmt($0, 1) }.joined(separator: ",")
    }

    func store(in doc: inout ArchiDocument) { doc.variables[SectionBox.variable] = stored }

    /// A box around the given bounds, slightly enlarged so nothing is cut at first.
    static func around(_ b: BBox3) -> SectionBox {
        let pad = Swift.max(100, b.size.length * 0.02)
        return SectionBox(on: true, min: b.min - Vec3(pad, pad, pad), max: b.max + Vec3(pad, pad, pad))
    }

    /// World-space (SceneKit metres, Y up) corners.
    var worldMin: SCNVector4 { SCNVector4(min.x * 0.001, min.z * 0.001, -max.y * 0.001, 0) }
    var worldMax: SCNVector4 { SCNVector4(max.x * 0.001, max.z * 0.001, -min.y * 0.001, 0) }

    /// Clipping shader shared by the section box and the section plane (w = 1 enables each test).
    static let shader = """
    #pragma arguments
    float4 archiBoxMin;
    float4 archiBoxMax;
    float4 archiPlaneP;
    float4 archiPlaneN;
    #pragma body
    float4 archiWP = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
    if (archiBoxMax.w > 0.5 && (archiWP.x < archiBoxMin.x || archiWP.y < archiBoxMin.y || archiWP.z < archiBoxMin.z ||
        archiWP.x > archiBoxMax.x || archiWP.y > archiBoxMax.y || archiWP.z > archiBoxMax.z)) {
        discard_fragment();
    }
    if (archiPlaneN.w > 0.5 && dot(archiWP.xyz - archiPlaneP.xyz, archiPlaneN.xyz) > 0.0) {
        discard_fragment();
    }
    """
}

// MARK: - Section plane (model millimetres, persisted in the SECTIONPLANE variable)

/// A single live cutting plane in 3D: everything on the normal's side is hidden and the cut is capped with solid faces.
struct SectionPlane: Equatable {
    static let capsName = "sectionPlaneCaps"
    var on: Bool
    var point: Vec3
    var normal: Vec3

    static let variable = "SECTIONPLANE"

    static func load(_ doc: ArchiDocument) -> SectionPlane? {
        guard let s = doc.variables[variable] else { return nil }
        let parts = s.split(separator: ";")
        guard parts.count == 3 else { return nil }
        let p = parts[1].split(separator: ",").compactMap { Double($0) }, n = parts[2].split(separator: ",").compactMap { Double($0) }
        guard p.count == 3, n.count == 3, (p + n).allSatisfy(\.isFinite), Vec3(n[0], n[1], n[2]).length > 1e-9 else { return nil }
        return SectionPlane(on: parts[0] == "on", point: Vec3(p[0], p[1], p[2]), normal: Vec3(n[0], n[1], n[2]).normalized)
    }
    var stored: String {
        (on ? "on" : "off") + ";" + [point.x, point.y, point.z].map { fmt($0, 3) }.joined(separator: ",") + ";" + [normal.x, normal.y, normal.z].map { fmt($0, 6) }.joined(separator: ",")
    }
    func store(in doc: inout ArchiDocument) { doc.variables[SectionPlane.variable] = stored }

    /// Horizontal cut at height z (keeps what is below).
    static func horizontal(z: Double) -> SectionPlane { SectionPlane(on: true, point: Vec3(0, 0, z), normal: Vec3(0, 0, 1)) }
    /// Vertical cut through the plan line a→b, hiding the side to the left of a→b.
    static func vertical(_ a: Vec2, _ b: Vec2) -> SectionPlane? {
        let d = b - a
        guard d.length > 1e-9 else { return nil }
        let left = Vec2(-d.y, d.x).normalized
        return SectionPlane(on: true, point: Vec3(a.x, a.y, 0), normal: Vec3(left.x, left.y, 0))
    }
    var flipped: SectionPlane { SectionPlane(on: on, point: point, normal: normal * -1) }

    var worldPoint: SCNVector4 { SCNVector4(point.x * 0.001, point.z * 0.001, -point.y * 0.001, 1) }
    var worldNormal: SCNVector4 { SCNVector4(normal.x, normal.z, -normal.y, 1) }
}

extension Viewport3DController {
    /// Applies (or removes) the section-box clipping shader on every model material (the stored section plane is kept).
    func applySectionBox(_ box: SectionBox?) {
        applyClipping(box: box, plane: model.flatMap { SectionPlane.load($0.doc) })
    }

    /// Applies the section box and the section plane together (one shader), with the plane's cap faces.
    func applyClipping(box: SectionBox?, plane: SectionPlane?) {
        let active = box?.on == true ? box : nil
        let cut = plane?.on == true ? plane : nil
        let root = builder.modelRoot
        let off = SCNVector4(0, 0, 0, 0)
        root.enumerateHierarchy { n, _ in
            guard n.name != "ground", n.name != SectionPlane.capsName, let g = n.geometry else { return }
            for m in g.materials {
                if active != nil || cut != nil {
                    if m.shaderModifiers?[.surface] != SectionBox.shader { m.shaderModifiers = [.surface: SectionBox.shader] }
                    m.setValue(NSValue(scnVector4: active?.worldMin ?? off), forKey: "archiBoxMin")
                    var hi = active?.worldMax ?? off
                    hi.w = active == nil ? 0 : 1
                    m.setValue(NSValue(scnVector4: hi), forKey: "archiBoxMax")
                    m.setValue(NSValue(scnVector4: cut?.worldPoint ?? off), forKey: "archiPlaneP")
                    m.setValue(NSValue(scnVector4: cut?.worldNormal ?? off), forKey: "archiPlaneN")
                } else if m.shaderModifiers != nil {
                    m.shaderModifiers = nil
                }
            }
        }
        updateBoxOutline(active)
        sectionBoxApplied = active
        updateCaps(cut)
    }

    /// Cap faces where the section plane cuts the model (recomputed when the plane or the drawing changes).
    private func updateCaps(_ plane: SectionPlane?) {
        let key = plane.map { "\($0.stored)|\(model?.editor.changeCount ?? 0)" }
        guard key != capsKey else { return }
        capsKey = key
        builder.modelRoot.childNode(withName: SectionPlane.capsName, recursively: false)?.removeFromParentNode()
        sectionPlaneApplied = plane
        guard let p = plane, let doc = model?.doc else { return }
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [UInt32] = []
        let offset = p.normal * -0.5   // just inside the kept side (mm): no z-fighting with cut faces
        for g in MeshBuilder.build(doc: doc) where !g.mesh.isEmpty {
            let m = g.mesh
            var tris: [(Vec3, Vec3, Vec3)] = []
            var i = 0
            while i + 2 < m.indices.count {
                tris.append((m.positions[Int(m.indices[i])], m.positions[Int(m.indices[i + 1])], m.positions[Int(m.indices[i + 2])])); i += 3
            }
            let loops = SectionCap.loops(tris, point: p.point, normal: p.normal)
            for (a, b, c) in SectionCap.triangles(loops, normal: p.normal) {
                for q in [a, b, c] {
                    let w = q + offset
                    verts.append(SCNVector3(w.x, w.y, w.z)); normals.append(SCNVector3(p.normal.x, p.normal.y, p.normal.z))
                    idx.append(UInt32(verts.count - 1))
                }
            }
        }
        guard !idx.isEmpty else { return }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(srgbRed: 0.55, green: 0.12, blue: 0.1, alpha: 1)
        mat.isDoubleSided = true
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)   // model coordinates: modelRoot converts mm → m and Z-up → Y-up
        node.name = SectionPlane.capsName
        node.castsShadow = false
        builder.modelRoot.addChildNode(node)
        view?.needsDisplay = true
    }

    private func updateBoxOutline(_ box: SectionBox?) {
        let name = "sectionBoxOutline"
        builder.scene.rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode()
        guard let b = box else { return }
        let lo = b.worldMin, hi = b.worldMax
        let c: [SCNVector3] = [SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, lo.y, lo.z), SCNVector3(hi.x, lo.y, hi.z), SCNVector3(lo.x, lo.y, hi.z),
                               SCNVector3(lo.x, hi.y, lo.z), SCNVector3(hi.x, hi.y, lo.z), SCNVector3(hi.x, hi.y, hi.z), SCNVector3(lo.x, hi.y, hi.z)]
        let idx: [UInt32] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: c)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Theme.nsAccent
        m.readsFromDepthBuffer = false
        geo.materials = [m]
        let node = SCNNode(geometry: geo)
        node.name = name
        node.renderingOrder = 100
        node.castsShadow = false
        addBoxGrips(b, to: node)
        builder.scene.rootNode.addChildNode(node)
    }

    // MARK: Direction views (view cube)

    /// Looks at the model from a direction (world space, pointing from the model to the camera).
    func setViewDirection(_ d: SCNVector3, animated: Bool = true) {
        if isWalking { toggleWalk() }
        let dir = Viewport3DController.norm(d)
        let s = builder.worldSphere
        let target = view?.defaultCameraController.target ?? s.center
        let center = Viewport3DController.length(Viewport3DController.sub(target, s.center)) < s.radius * 2 ? target : s.center
        let fov = (cameraNode.camera?.fieldOfView ?? 45) * .pi / 180
        let dist = s.radius / sin(fov / 2) * 1.15
        var up = SCNVector3(0, 1, 0)
        if abs(dir.y) > 0.98 { up = dir.y > 0 ? SCNVector3(0, 0, -1) : SCNVector3(0, 0, 1) }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.45 : 0
        cameraNode.position = SCNVector3(center.x + dir.x * dist, center.y + dir.y * dist, center.z + dir.z * dist)
        cameraNode.look(at: center, up: up, localFront: SCNVector3(0, 0, -1))
        cameraNode.camera?.orthographicScale = Double(s.radius) * 1.1
        SCNTransaction.commit()
        view?.defaultCameraController.target = center
        view?.defaultCameraController.clearRoll()
    }

    // MARK: Selection orbit / zoom

    /// World bounds of the selected elements' 3D nodes.
    func selectionWorldBounds(_ ids: Set<EntityID>) -> (min: SCNVector3, max: SCNVector3)? {
        var lo = SCNVector3(CGFloat.infinity, CGFloat.infinity, CGFloat.infinity), hi = SCNVector3(-CGFloat.infinity, -CGFloat.infinity, -CGFloat.infinity)
        var found = false
        builder.modelRoot.enumerateHierarchy { n, _ in
            guard n.geometry != nil, let name = n.name, name.hasPrefix("el:"), let id = Int(name.dropFirst(3)), ids.contains(id) else { return }
            let (a, b) = n.boundingBox
            for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                let w = n.convertPosition(SCNVector3(x, y, z), to: nil)
                lo = SCNVector3(Swift.min(lo.x, w.x), Swift.min(lo.y, w.y), Swift.min(lo.z, w.z))
                hi = SCNVector3(Swift.max(hi.x, w.x), Swift.max(hi.y, w.y), Swift.max(hi.z, w.z))
                found = true
            } } }
        }
        return found ? (lo, hi) : nil
    }

    /// Orbits around (and optionally frames) the selection. Returns false when nothing selected has 3D geometry.
    @discardableResult
    func orbitSelection(_ ids: Set<EntityID>, frame: Bool) -> Bool {
        guard let (lo, hi) = selectionWorldBounds(ids) else { return false }
        if isWalking { toggleWalk() }
        let c = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        let r = Swift.max(0.3, Viewport3DController.length(Viewport3DController.sub(hi, lo)) / 2)
        view?.defaultCameraController.target = c
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        if frame {
            let fov = (cameraNode.camera?.fieldOfView ?? 45) * .pi / 180
            let d = r / sin(fov / 2) * 1.2
            let f = cameraNode.worldFront
            cameraNode.position = SCNVector3(c.x - f.x * d, c.y - f.y * d, c.z - f.z * d)
            cameraNode.camera?.orthographicScale = Double(r) * 1.2
        }
        cameraNode.look(at: c, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        SCNTransaction.commit()
        return true
    }

    // MARK: Saved cameras (named views with a camera)

    var currentCamera: Camera {
        let p = cameraNode.presentation
        let eye = Scene3DBuilder.model(p.worldPosition)
        let target = view?.defaultCameraController.target ?? {
            let f = p.worldFront; let w = p.worldPosition
            return SCNVector3(w.x + f.x * 10, w.y + f.y * 10, w.z + f.z * 10)
        }()
        return Camera(eye: eye, target: Scene3DBuilder.model(target), fov: Double(p.camera?.fieldOfView ?? 45), orthographic: isOrtho)
    }

    func apply(camera c: Camera, animated: Bool = true) {
        if isWalking { toggleWalk() }
        if c.orthographic != isOrtho { toggleProjection() }
        let eye = Scene3DBuilder.world(c.eye), target = Scene3DBuilder.world(c.target)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        cameraNode.position = eye
        cameraNode.camera?.fieldOfView = CGFloat(Swift.max(10, Swift.min(120, c.fov)))
        cameraNode.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        if c.orthographic { cameraNode.camera?.orthographicScale = Double(Viewport3DController.length(Viewport3DController.sub(eye, target))) * 0.45 }
        SCNTransaction.commit()
        view?.defaultCameraController.target = target
    }

    // MARK: Sun study

    func applySun(dayOfYear: Int, hour: Double, doc: ArchiDocument) {
        let s = SunPosition.compute(dayOfYear: dayOfYear, localHour: hour, latitude: doc.info.latitude, longitude: doc.info.longitude,
                                    utcOffsetHours: (doc.info.longitude / 15).rounded())
        builder.setSun(direction: SunPosition.direction(altitude: s.altitude, azimuth: s.azimuth, northAngleDegrees: doc.info.northAngle))
        let alt = s.altitude
        builder.sunNode.light?.intensity = alt <= 0 ? 0 : CGFloat(1400 * Swift.min(1, sin(alt) * 2.2 + 0.1))
        builder.sunNode.light?.color = alt < 0.25 ? NSColor(srgbRed: 1, green: 0.78, blue: 0.55, alpha: 1) : NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
        builder.sunNode.light?.castsShadow = true
        view?.needsDisplay = true
    }

    func resetSun() {
        builder.setSun(direction: Vec3(-0.45, -0.7, 0.75))
        builder.sunNode.light?.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
        let style = builder.style
        builder.sunNode.light?.intensity = style == "Realistic" ? 1600 : (style == "Hidden Line" ? 0 : 900)
        builder.sunNode.light?.castsShadow = ["Shaded", "Shaded with Edges", "Realistic"].contains(style)
    }
}

// MARK: - View cube

/// Small SceneKit cube mirroring the camera orientation. Click a face, edge or corner to look from that direction.
final class ViewCubeView: SCNView {
    weak var controller: Viewport3DController?
    let cubeCamera = SCNNode()
    private var lastOrientation = SCNQuaternion(0, 0, 0, 1)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 96), options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let s = SCNScene()
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.08)
        // SCNBox material order: front (+Z = south), right (+X = east), back (−Z = north), left (−X = west), top (+Y), bottom (−Y).
        box.materials = ["FRONT", "RIGHT", "BACK", "LEFT", "TOP", "BOTTOM"].map { ViewCubeView.faceMaterial($0) }
        let cube = SCNNode(geometry: box)
        cube.name = "cube"
        s.rootNode.addChildNode(cube)
        let edges = SCNNode(geometry: ViewCubeView.edgeGeometry())
        s.rootNode.addChildNode(edges)
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = 1.05
        cubeCamera.camera = cam
        cubeCamera.position = SCNVector3(0, 0, 4)
        s.rootNode.addChildNode(cubeCamera)
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 900
        s.rootNode.addChildNode(amb)
        scene = s
        pointOfView = cubeCamera
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        allowsCameraControl = false
        rendersContinuously = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { false }

    static func faceMaterial(_ label: String) -> SCNMaterial {
        let img = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { r in
            NSColor(srgbRed: 0.22, green: 0.23, blue: 0.26, alpha: 1).setFill()
            r.fill()
            NSColor(white: 1, alpha: 0.12).setStroke()
            let b = NSBezierPath(rect: r.insetBy(dx: 2, dy: 2)); b.lineWidth = 3; b.stroke()
            let s = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: label.count > 5 ? 20 : 24, weight: .semibold),
                                                                   .foregroundColor: NSColor(white: 0.92, alpha: 1)])
            let sz = s.size()
            s.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
            return true
        }
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.lightingModel = .constant
        return m
    }

    static func edgeGeometry() -> SCNGeometry {
        let h: CGFloat = 0.505
        let c: [SCNVector3] = [SCNVector3(-h, -h, -h), SCNVector3(h, -h, -h), SCNVector3(h, -h, h), SCNVector3(-h, -h, h),
                               SCNVector3(-h, h, -h), SCNVector3(h, h, -h), SCNVector3(h, h, h), SCNVector3(-h, h, h)]
        let idx: [UInt32] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: c)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(white: 0.75, alpha: 1)
        g.materials = [m]
        return g
    }

    /// Mirrors the main camera's orientation.
    func sync(orientation q: SCNQuaternion) {
        guard q.x != lastOrientation.x || q.y != lastOrientation.y || q.z != lastOrientation.z || q.w != lastOrientation.w else { return }
        lastOrientation = q
        cubeCamera.orientation = q
        let back = cubeCamera.worldFront
        cubeCamera.position = SCNVector3(-back.x * 4, -back.y * 4, -back.z * 4)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first(where: { $0.node.name == "cube" }) else { return }
        let l = hit.localCoordinates
        func axis(_ v: CGFloat) -> CGFloat { v > 0.28 ? 1 : (v < -0.28 ? -1 : 0) }
        var d = SCNVector3(axis(l.x), axis(l.y), axis(l.z))
        if d.x == 0 && d.y == 0 && d.z == 0 { d = hit.worldNormal }
        let dir = d
        MainActor.assumeIsolated { controller?.setViewDirection(dir) }
    }
}

struct ViewCubeRepresentable: NSViewRepresentable {
    let controller: Viewport3DController
    func makeNSView(context: Context) -> ViewCubeView {
        let v = ViewCubeView()
        v.controller = controller
        controller.cubeView = v
        return v
    }
    func updateNSView(_ v: ViewCubeView, context: Context) {
        v.controller = controller
        controller.cubeView = v
    }
}

// MARK: - Overlay panels

/// Six sliders cutting the model live; the box is saved with the drawing (undoable).
struct SectionBoxPanel: View {
    @ObservedObject var model: AppModel
    let controller: Viewport3DController
    @State private var box = SectionBox(on: true, min: .zero, max: Vec3(1000, 1000, 1000))
    @State private var extents = BBox3.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cube.transparent").foregroundStyle(Theme.accent)
                Text("Section Box").font(Theme.fontBold)
                Spacer()
                Toggle("On", isOn: Binding(get: { box.on }, set: { box.on = $0; live(); commit() })).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                IconButton(symbol: "xmark", help: "Close") { model.showSectionBoxPanel = false }
            }
            if !extents.isEmpty {
                pair("X (east)", \.x)
                pair("Y (north)", \.y)
                pair("Z (height)", \.z)
            }
            HStack {
                Button("Selection") { fitSelection() }.buttonStyle(FlatButtonStyle(compact: true)).disabled(model.editor.selection.isEmpty)
                    .help("Fit the box to the selected elements")
                Button("Level") { fitLevel() }.buttonStyle(FlatButtonStyle(compact: true)).help("Cut above the current level")
                Button("Reset") { box = SectionBox.around(extents); live(); commit() }.buttonStyle(FlatButtonStyle(compact: true))
            }
        }
        .font(Theme.font)
        .padding(10)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .onAppear {
            extents = controller.builder.bounds
            box = SectionBox.load(model.doc) ?? SectionBox.around(extents)
            if !box.on { box.on = true }
            live(); commit()
        }
    }

    private func pair(_ title: String, _ kp: WritableKeyPath<Vec3, Double>) -> some View {
        let pad = max(100, extents.size.length * 0.02)
        let lo = extents.min[keyPath: kp] - pad, hi = extents.max[keyPath: kp] + pad
        return VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            HStack(spacing: 4) {
                Slider(value: Binding(get: { box.min[keyPath: kp] }, set: { box.min[keyPath: kp] = min($0, box.max[keyPath: kp] - 10); live() }),
                       in: lo...max(hi, lo + 1), onEditingChanged: { if !$0 { commit() } })
                Slider(value: Binding(get: { box.max[keyPath: kp] }, set: { box.max[keyPath: kp] = max($0, box.min[keyPath: kp] + 10); live() }),
                       in: lo...max(hi, lo + 1), onEditingChanged: { if !$0 { commit() } })
            }
        }
    }

    private func live() { controller.applySectionBox(box) }

    private func commit() {
        let b = box
        guard SectionBox.load(model.doc) != b else { return }
        model.editor.transaction("Section Box") { b.store(in: &$0) }
    }

    private func fitSelection() {
        guard let (lo, hi) = controller.selectionWorldBounds(model.editor.selection) else { return }
        let a = Scene3DBuilder.model(lo), b = Scene3DBuilder.model(hi)
        var bb = BBox3.empty; bb.add(a); bb.add(b)
        box = SectionBox.around(bb)
        live(); commit()
    }

    private func fitLevel() {
        guard let l = model.doc.level(model.doc.currentLevel) else { return }
        box.min.z = max(extents.min.z - 100, l.elevation - 50)
        box.max.z = l.elevation + l.height * 0.9
        box.on = true
        live(); commit()
    }
}

/// Sun study: date and time sliders with a day animation (shadows in the shaded styles).
struct SunStudyPanel: View {
    @ObservedObject var model: AppModel
    let controller: Viewport3DController
    @State private var day = 172
    @State private var hour = 15.0
    @State private var playing = false
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sun.max").foregroundStyle(Theme.accent)
                Text("Sun Study").font(Theme.fontBold)
                Spacer()
                IconButton(symbol: playing ? "pause.fill" : "play.fill", help: playing ? "Pause" : "Animate the day") { togglePlay() }
                IconButton(symbol: "xmark", help: "Close") { close() }
            }
            Text(dateText).font(Theme.mono).foregroundStyle(Theme.text)
            HStack { Text("Day").frame(width: 34, alignment: .leading).foregroundStyle(Theme.textDim)
                Slider(value: Binding(get: { Double(day) }, set: { day = Int($0); apply() }), in: 1...365, onEditingChanged: { if !$0 { save() } }) }
            HStack { Text("Time").frame(width: 34, alignment: .leading).foregroundStyle(Theme.textDim)
                Slider(value: Binding(get: { hour }, set: { hour = $0; apply() }), in: 4...22, onEditingChanged: { if !$0 { save() } }) }
            Text(sunText).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            HStack(spacing: 4) {
                ForEach([("Mar 21", 80), ("Jun 21", 172), ("Sep 23", 266), ("Dec 21", 355)], id: \.1) { n, d in
                    Button(n) { day = d; apply(); save() }.buttonStyle(FlatButtonStyle(compact: true))
                }
            }
        }
        .font(Theme.font)
        .padding(10)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .onAppear {
            if let v = model.doc.variables["SUNSTUDY"] {
                let p = v.split(separator: ",").compactMap { Double($0) }
                if p.count == 2 { day = Int(p[0]); hour = p[1] }
            }
            if model.viewStyle == "Wireframe" || model.viewStyle == "Hidden Line" || model.viewStyle == "X-Ray" { model.viewStyle = "Shaded" }
            apply()
        }
        .onDisappear { timer?.invalidate(); timer = nil; controller.resetSun() }
    }

    private var dateText: String {
        var c = DateComponents(); c.year = 2025; c.day = day
        let d = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        let f = DateFormatter(); f.dateFormat = "d MMMM"
        return "\(f.string(from: d))  \(String(format: "%02d:%02d", Int(hour), Int((hour - floor(hour)) * 60) % 60))"
    }
    private var sunText: String {
        let s = SunPosition.compute(dayOfYear: day, localHour: hour, latitude: model.doc.info.latitude, longitude: model.doc.info.longitude,
                                    utcOffsetHours: (model.doc.info.longitude / 15).rounded())
        return s.altitude <= 0 ? "Sun below the horizon" : "Altitude \(fmt(deg(s.altitude), 1))°, azimuth \(fmt(deg(s.azimuth), 1))° · site \(fmt(model.doc.info.latitude, 2))°, \(fmt(model.doc.info.longitude, 2))°"
    }
    private func apply() { controller.applySun(dayOfYear: day, hour: hour, doc: model.doc) }
    private func save() {
        let v = "\(day),\(fmt(hour, 2))"
        guard model.doc.variables["SUNSTUDY"] != v else { return }
        model.editor.transaction("Sun Study") { $0.variables["SUNSTUDY"] = v }
    }
    private func togglePlay() {
        playing.toggle()
        timer?.invalidate(); timer = nil
        guard playing else { save(); return }
        if hour >= 21.5 { hour = 5 }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                hour += 0.05
                if hour >= 21.5 { hour = 21.5; playing = false; timer?.invalidate(); timer = nil; save() }
                apply()
            }
        }
    }
    private func close() { timer?.invalidate(); timer = nil; playing = false; model.showSunStudy = false }
}

/// Saved 3D cameras menu.
struct CamerasMenu: View {
    @ObservedObject var model: AppModel
    let controller: Viewport3DController
    var body: some View {
        let cams = model.doc.namedViews.filter { $0.camera != nil }
        Menu {
            Button("Save Current Camera…") { model.sheet = .saveCamera }
            if !cams.isEmpty {
                Divider()
                ForEach(cams, id: \.name) { v in
                    Button(v.name) { if let c = v.camera { controller.apply(camera: c) } }
                }
                Divider()
                Menu("Delete") {
                    ForEach(cams, id: \.name) { v in
                        Button(v.name) { model.editor.transaction("Delete Camera") { $0.namedViews.removeAll { $0.name == v.name && $0.camera != nil } } }
                    }
                }
            }
        } label: { Image(systemName: "camera") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.horizontal, 4)
        .help("Saved cameras")
    }
}

struct SaveCameraSheet: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Camera").font(.system(size: 13, weight: .semibold))
            TextField("Camera name", text: $name).darkField().frame(width: 280).onSubmit(save)
            Text("Saved with the drawing; restore it from the camera menu in the 3D view or with the CAMERA command.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).frame(width: 280, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .font(Theme.font)
        .padding(16)
        .background(Theme.panel)
        .onAppear { name = "Camera \(model.doc.namedViews.filter { $0.camera != nil }.count + 1)" }
    }
    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let c = model.viewport3D?.currentCamera else { model.sheet = nil; return }
        CameraStore.save(n, camera: c, model: model)
        model.sheet = nil
    }
}

@MainActor
enum CameraStore {
    static func save(_ name: String, camera c: Camera, model: AppModel) {
        let center = Vec2(c.target.x, c.target.y)
        let h = max(1000, (c.eye - c.target).length)
        model.editor.transaction("Save Camera") { d in
            d.namedViews.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.camera != nil }
            d.namedViews.append(NamedView(name: name, center: center, height: h, camera: c))
        }
        model.editor.print("Camera “\(name)” saved.")
    }
    static func find(_ name: String, in doc: ArchiDocument) -> NamedView? {
        doc.namedViews.first { $0.camera != nil && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
