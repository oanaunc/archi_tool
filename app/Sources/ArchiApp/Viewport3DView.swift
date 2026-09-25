// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import ArchiCore

// MARK: - Scene construction (shared by the viewport and the renderer)

/// Converts ArchiCore mesh groups into a SceneKit scene. Model space is millimetres, Z up;
/// the model root node scales by 0.001 and rotates −90° about X so SceneKit sees metres, Y up.
@MainActor
final class Scene3DBuilder {
    static let visualStyles = ["Wireframe", "Hidden Line", "Shaded", "Shaded with Edges", "Realistic", "X-Ray"]
    static let accent = NSColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1)

    let scene = SCNScene()
    let modelRoot = SCNNode()
    let sunNode = SCNNode()
    let ambientNode = SCNNode()
    let groundNode = SCNNode()
    private(set) var style = ""
    /// Model-space bounds (mm) of everything built.
    private(set) var bounds = BBox3.empty
    private var nodes: [String: (hash: Int, node: SCNNode)] = [:]
    private var originalMaterials: [ObjectIdentifier: [SCNMaterial]] = [:]
    private var highlighted: Set<EntityID> = []
    private var materialCache: [String: SCNMaterial] = [:]
    private var edgeMaterial = SCNMaterial()

    init() {
        modelRoot.name = "modelRoot"
        modelRoot.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        modelRoot.scale = SCNVector3(0.001, 0.001, 0.001)
        scene.rootNode.addChildNode(modelRoot)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1000
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 16
        sun.shadowRadius = 4
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.shadowColor = NSColor(white: 0, alpha: 0.45)
        sun.automaticallyAdjustsShadowProjection = true
        sun.shadowCascadeCount = 2
        sun.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
        sunNode.light = sun
        sunNode.name = "sun"
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 350
        amb.color = NSColor(white: 0.9, alpha: 1)
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)

        groundNode.name = "ground"
        groundNode.castsShadow = false
        modelRoot.addChildNode(groundNode)
        setSun(direction: Vec3(-0.45, -0.7, 0.75))
    }

    // MARK: Coordinates
    static func world(_ p: Vec3) -> SCNVector3 { SCNVector3(p.x * 0.001, p.z * 0.001, -p.y * 0.001) }
    static func model(_ w: SCNVector3) -> Vec3 { Vec3(Double(w.x) * 1000, -Double(w.z) * 1000, Double(w.y) * 1000) }

    /// Bounding sphere of the model in SceneKit world units (metres).
    var worldSphere: (center: SCNVector3, radius: CGFloat) {
        if bounds.isEmpty { return (SCNVector3(0, 1.5, 0), 10) }
        let c = Scene3DBuilder.world(bounds.center)
        let r = max(1, CGFloat(bounds.size.length * 0.0005))
        return (c, r)
    }

    /// Points the sun along the model-space direction *towards* the sun.
    func setSun(direction d0: Vec3) {
        var d = d0.normalized
        if d.z < 0.05 { d = Vec3(d.x, d.y, 0.05).normalized }
        let s = worldSphere
        let w = SCNVector3(d.x, d.z, -d.y)
        sunNode.position = SCNVector3(s.center.x + w.x * s.radius * 3, s.center.y + w.y * s.radius * 3, s.center.z + w.z * s.radius * 3)
        sunNode.look(at: s.center, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        sunNode.light?.maximumShadowDistance = s.radius * 8
        sunNode.light?.orthographicScale = s.radius * 1.5
    }

    // MARK: Build / update

    func update(doc: ArchiDocument, style newStyle: String) {
        let styleChanged = newStyle != style
        if styleChanged {
            style = newStyle
            materialCache.removeAll()
            for (_, v) in nodes { v.node.removeFromParentNode() }
            nodes.removeAll()
            originalMaterials.removeAll()
            configureEnvironment()
        }
        let groups = MeshBuilder.build(doc: doc)
        var byKey: [String: [MeshGroup]] = [:]
        var order: [String] = []
        var anon = 0
        for g in groups {
            let key: String
            if let id = g.id { key = "el:\(id)" } else { key = "anon:\(anon)"; anon += 1 }
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(g)
        }
        // Materials may have been edited: they are part of each group's hash.
        var seen = Set<String>()
        var newBounds = BBox3.empty
        for key in order {
            let gs = byKey[key]!
            var h = Hasher()
            h.combine(gs)
            for g in gs { h.combine(doc.material(g.material)) }
            let hash = h.finalize()
            for g in gs { for p in g.mesh.positions { newBounds.add(p) }; for e in g.edges { for p in e { newBounds.add(p) } } }
            seen.insert(key)
            if let existing = nodes[key], existing.hash == hash { continue }
            nodes[key]?.node.removeFromParentNode()
            if let n = nodes[key]?.node { forgetMaterials(n) }
            let node = makeNode(key: key, groups: gs, doc: doc)
            modelRoot.addChildNode(node)
            nodes[key] = (hash, node)
        }
        for (key, v) in nodes where !seen.contains(key) {
            v.node.removeFromParentNode(); forgetMaterials(v.node); nodes[key] = nil
        }
        let boundsChanged = newBounds != bounds
        bounds = newBounds
        if boundsChanged || styleChanged { updateGround() }
        let h = highlighted
        highlighted = []
        applySelection(h)
    }

    private func forgetMaterials(_ n: SCNNode) {
        n.enumerateHierarchy { c, _ in originalMaterials[ObjectIdentifier(c)] = nil }
    }

    private func makeNode(key: String, groups: [MeshGroup], doc: ArchiDocument) -> SCNNode {
        let parent = SCNNode()
        parent.name = key
        for g in groups {
            if style != "Wireframe", let geo = Scene3DBuilder.geometry(g.mesh) {
                geo.materials = [material(for: g.material, doc: doc)]
                let n = SCNNode(geometry: geo)
                n.name = key
                let transparent = (doc.material(g.material)?.transparency ?? 0) > 0.3
                n.castsShadow = !transparent && style != "X-Ray"
                if style == "X-Ray" { n.renderingOrder = 10 }
                parent.addChildNode(n)
            }
            if showsEdges, let eg = Scene3DBuilder.edgeGeometry(g) {
                eg.materials = [edgeMaterial]
                let n = SCNNode(geometry: eg)
                n.name = key
                n.castsShadow = false
                n.renderingOrder = 20
                parent.addChildNode(n)
            }
        }
        return parent
    }

    var showsEdges: Bool { ["Wireframe", "Hidden Line", "Shaded with Edges", "X-Ray"].contains(style) }

    static func geometry(_ mesh: Mesh) -> SCNGeometry? {
        guard !mesh.isEmpty, !mesh.positions.isEmpty else { return nil }
        let n = mesh.positions.count
        guard mesh.indices.allSatisfy({ Int($0) < n }) else { return nil }
        var sources = [SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })]
        if mesh.normals.count == n { sources.append(SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) })) }
        if mesh.uvs.count == n { sources.append(SCNGeometrySource(textureCoordinates: mesh.uvs.map { CGPoint(x: $0.x, y: $0.y) })) }
        return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
    }

    /// Feature edges as a line geometry, nudged 2 mm outward to avoid z-fighting with faces.
    static func edgeGeometry(_ g: MeshGroup) -> SCNGeometry? {
        guard !g.edges.isEmpty else { return nil }
        var b = BBox3.empty
        for e in g.edges { for p in e { b.add(p) } }
        if !g.mesh.positions.isEmpty { b = g.mesh.bounds }
        let c = b.isEmpty ? Vec3.zero : b.center
        var verts: [SCNVector3] = []
        var idx: [UInt32] = []
        for poly in g.edges where poly.count >= 2 {
            let base = UInt32(verts.count)
            for p in poly {
                let off = (p - c).normalized * 2
                let q = p + off
                verts.append(SCNVector3(q.x, q.y, q.z))
            }
            for i in 0..<(poly.count - 1) { idx += [base + UInt32(i), base + UInt32(i + 1)] }
        }
        guard !idx.isEmpty else { return nil }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
    }

    func material(for name: String, doc: ArchiDocument) -> SCNMaterial {
        if let m = materialCache[name] { return m }
        let src = doc.material(name) ?? Material(name: name, color: RGBA(0.8, 0.8, 0.8))
        let m = SCNMaterial()
        m.name = name
        let color = NSColor(srgbRed: src.color.r, green: src.color.g, blue: src.color.b, alpha: 1)
        let t = min(max(src.transparency, 0), 0.95)
        switch style {
        case "Hidden Line":
            m.lightingModel = .constant
            m.diffuse.contents = t > 0.3 ? NSColor(white: 0.93, alpha: 1) : NSColor.white
        case "X-Ray":
            m.lightingModel = .lambert
            m.diffuse.contents = color
            m.transparency = 0.22
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            m.blendMode = .alpha
        case "Realistic":
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.roughness.contents = NSNumber(value: min(max(src.roughness, 0.02), 1))
            m.metalness.contents = NSNumber(value: min(max(src.metalness, 0), 1))
            if t > 0 {
                m.transparency = 1 - t
                m.transparencyMode = .dualLayer
                m.isDoubleSided = true
                m.writesToDepthBuffer = t < 0.5
                m.fresnelExponent = 1.5
            }
        default: // Shaded, Shaded with Edges
            m.lightingModel = .blinn
            m.diffuse.contents = color
            m.specular.contents = NSColor(white: src.metalness > 0.5 ? 0.5 : 0.08, alpha: 1)
            m.shininess = CGFloat(max(2, (1 - src.roughness) * 60))
            if t > 0 {
                m.transparency = 1 - t
                m.isDoubleSided = true
                m.writesToDepthBuffer = t < 0.5
            }
        }
        if src.transparency > 0 { m.isDoubleSided = true }
        if style != "Hidden Line", style != "X-Ray", let img = MaterialTextures.image(src.texture) {
            m.diffuse.contents = img
            m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
            let k = CGFloat(1000 / max(src.textureScale, 1))
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(k, k, 1)
            m.multiply.contents = color.blended(withFraction: 0.75, of: .white) ?? NSColor.white
        }
        materialCache[name] = m
        return m
    }

    private func configureEnvironment() {
        let em = SCNMaterial()
        em.lightingModel = .constant
        switch style {
        case "Wireframe": em.diffuse.contents = NSColor(white: 0.85, alpha: 1)
        case "Hidden Line": em.diffuse.contents = NSColor(white: 0.08, alpha: 1)
        case "X-Ray": em.diffuse.contents = NSColor(white: 0.9, alpha: 0.9)
        default: em.diffuse.contents = NSColor(white: 0.12, alpha: 1)
        }
        em.readsFromDepthBuffer = style != "X-Ray"
        edgeMaterial = em

        let realistic = style == "Realistic"
        let light = style == "Hidden Line"
        let sky = Scene3DBuilder.gradient(top: light ? NSColor(white: 0.98, alpha: 1) : (realistic ? NSColor(srgbRed: 0.42, green: 0.58, blue: 0.78, alpha: 1) : NSColor(srgbRed: 0.20, green: 0.215, blue: 0.24, alpha: 1)),
                                          bottom: light ? NSColor(white: 0.9, alpha: 1) : (realistic ? NSColor(srgbRed: 0.86, green: 0.88, blue: 0.9, alpha: 1) : NSColor(srgbRed: 0.09, green: 0.095, blue: 0.105, alpha: 1)))
        scene.background.contents = sky
        scene.lightingEnvironment.contents = realistic ? sky : nil
        scene.lightingEnvironment.intensity = realistic ? 1.3 : 0
        let shadows = ["Shaded", "Shaded with Edges", "Realistic"].contains(style)
        sunNode.light?.castsShadow = shadows
        sunNode.light?.intensity = realistic ? 1600 : (light ? 0 : 900)
        ambientNode.light?.intensity = realistic ? 220 : (light ? 1000 : 420)
    }

    private func updateGround() {
        let size = bounds.isEmpty ? 100_000.0 : max(100_000, max(bounds.size.x, bounds.size.y) * 6)
        let plane = SCNPlane(width: size, height: size)
        let m = SCNMaterial()
        let realistic = style == "Realistic", light = style == "Hidden Line"
        let base: NSColor = realistic ? NSColor(srgbRed: 0.56, green: 0.58, blue: 0.53, alpha: 1)
            : (light ? NSColor.white : NSColor(srgbRed: 0.17, green: 0.18, blue: 0.19, alpha: 1))
        let line: NSColor = realistic ? NSColor(white: 0.48, alpha: 1) : (light ? NSColor(white: 0.86, alpha: 1) : NSColor(white: 0.30, alpha: 1))
        m.diffuse.contents = Scene3DBuilder.gridImage(base: base, line: line)
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(size / 5000), CGFloat(size / 5000), 1)
        m.lightingModel = realistic ? .physicallyBased : (light ? .constant : .lambert)
        m.roughness.contents = NSNumber(value: 1)
        m.writesToDepthBuffer = true
        if style == "Wireframe" || style == "X-Ray" { m.transparency = 0.5 }
        plane.materials = [m]
        groundNode.geometry = plane
        let z = bounds.isEmpty ? 0 : bounds.min.z - 3
        let c = bounds.isEmpty ? Vec3.zero : bounds.center
        groundNode.position = SCNVector3(c.x, c.y, z)
        groundNode.renderingOrder = -10
        setSunKeepingDirection()
    }

    private func setSunKeepingDirection() {
        let f = sunNode.worldFront
        setSun(direction: Vec3(-Double(f.x), Double(f.z), -Double(f.y)))
    }

    // MARK: Selection highlight

    func applySelection(_ ids: Set<EntityID>) {
        guard ids != highlighted else { return }
        for id in highlighted.subtracting(ids) { setHighlight(id, on: false) }
        for id in ids.subtracting(highlighted) { setHighlight(id, on: true) }
        highlighted = ids
    }

    private func setHighlight(_ id: EntityID, on: Bool) {
        guard let node = nodes["el:\(id)"]?.node else { return }
        for child in node.childNodes {
            guard let geo = child.geometry else { continue }
            let key = ObjectIdentifier(child)
            if on {
                if originalMaterials[key] == nil { originalMaterials[key] = geo.materials }
                geo.materials = geo.materials.map { m in
                    let c = m.copy() as! SCNMaterial
                    c.emission.contents = Scene3DBuilder.accent.withAlphaComponent(1)
                    c.emission.intensity = 0.55
                    if geo.elements.first?.primitiveType == .line { c.diffuse.contents = Scene3DBuilder.accent }
                    return c
                }
            } else if let orig = originalMaterials[key] {
                geo.materials = orig
                originalMaterials[key] = nil
            }
        }
    }

    // MARK: Images

    static func gradient(top: NSColor, bottom: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 8, height: 256))
        img.lockFocus()
        NSGradient(starting: bottom, ending: top)?.draw(in: NSRect(x: 0, y: 0, width: 8, height: 256), angle: 90)
        img.unlockFocus()
        return img
    }

    /// One 5 m tile: 1 m minor lines and a stronger 5 m line.
    static func gridImage(base: NSColor, line: NSColor) -> NSImage {
        let s: CGFloat = 500
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        base.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
        line.withAlphaComponent(0.45).setFill()
        for i in 1..<5 { let p = CGFloat(i) * s / 5
            NSRect(x: p - 0.75, y: 0, width: 1.5, height: s).fill(); NSRect(x: 0, y: p - 0.75, width: s, height: 1.5).fill() }
        line.setFill()
        NSRect(x: 0, y: 0, width: 3, height: s).fill(); NSRect(x: 0, y: 0, width: s, height: 3).fill()
        img.unlockFocus()
        return img
    }
}

// MARK: - Controller (camera, walk mode, overlay commands)

@MainActor
final class Viewport3DController: NSObject, ObservableObject {
    /// The most recently shown 3D viewport (used by the renderer for its camera).
    static weak var active: Viewport3DController?

    @Published var isOrtho = false
    @Published var isWalking = false
    let builder = Scene3DBuilder()
    let cameraNode = SCNNode()
    weak var view: ArchiSCNView?
    weak var model: AppModel?
    private var lastChange = -1
    private var lastStyle = ""
    private var positioned = false
    private var walkTimer: Timer?
    private var yaw: CGFloat = 0, pitch: CGFloat = 0
    private var lastTick = Date()
    /// Section box currently applied to the scene materials.
    var sectionBoxApplied: SectionBox?
    weak var cubeView: ViewCubeView?
    private var cubeTimer: Timer?

    override init() {
        super.init()
        let cam = SCNCamera()
        cam.fieldOfView = 45
        cam.automaticallyAdjustsZRange = true
        cam.zNear = 0.05
        cam.zFar = 20000
        cameraNode.camera = cam
        cameraNode.name = "camera"
        builder.scene.rootNode.addChildNode(cameraNode)
        cameraNode.position = SCNVector3(-20, 15, 20)
        cameraNode.look(at: SCNVector3(0, 0, 0))
    }

    func attach(_ v: ArchiSCNView) {
        view = v
        v.controller = self
        v.scene = builder.scene
        v.pointOfView = cameraNode
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.inertiaFriction = 0.12
        v.defaultCameraController.worldUp = SCNVector3(0, 1, 0)
        v.cameraControlConfiguration.allowsTranslation = true
        v.cameraControlConfiguration.autoSwitchToFreeCamera = false
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(srgbRed: 0.1, green: 0.105, blue: 0.115, alpha: 1)
        v.showsStatistics = false
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = false
        Viewport3DController.active = self
        if cubeTimer == nil {
            cubeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let cube = self.cubeView, cube.window != nil else { return }
                    cube.sync(orientation: self.cameraNode.presentation.worldOrientation)
                }
            }
        }
    }

    func sync(model: AppModel) {
        self.model = model
        if model.viewport3D !== self { model.viewport3D = self }
        let style = Scene3DBuilder.visualStyles.contains(model.viewStyle) ? model.viewStyle : "Shaded with Edges"
        if model.editor.changeCount != lastChange || style != lastStyle {
            lastChange = model.editor.changeCount
            lastStyle = style
            builder.update(doc: model.doc, style: style)
            applyCameraEffects(style)
            if !positioned && !builder.bounds.isEmpty { positioned = true; setView("Iso", animated: false) }
        }
        builder.applySelection(model.editor.selection)
        let box = SectionBox.load(model.doc)
        if box?.on == true || sectionBoxApplied != nil {
            // Live slider edits are applied by the panel; here the stored box is re-applied after rebuilds.
            if !model.showSectionBoxPanel || sectionBoxApplied == nil || box != sectionBoxApplied { applySectionBox(box) }
            else { applySectionBox(sectionBoxApplied) }
        }
        // Camera requests from the ribbon, menus and command line.
        if let action = model.pendingHostAction {
            switch action {
            case .setView(let v) where v != "zoomPrevious":
                model.pendingHostAction = nil
                if isWalking { toggleWalk() }
                if v.lowercased() == "ortho" || v.lowercased() == "perspective" {
                    if (v.lowercased() == "ortho") != isOrtho { toggleProjection() }
                } else { setView(v) }
            case .zoomExtents:
                model.pendingHostAction = nil; zoomExtents()
            case .walkthrough:
                model.pendingHostAction = nil
                if !isWalking { toggleWalk() }
            default: break
            }
        }
        if !model.walkMode && isWalking && model.pendingHostAction == nil { }
    }

    private func applyCameraEffects(_ style: String) {
        guard let cam = cameraNode.camera else { return }
        let realistic = style == "Realistic"
        cam.wantsHDR = realistic
        cam.bloomIntensity = realistic ? 0.12 : 0
        cam.bloomThreshold = 0.92
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0
        cam.screenSpaceAmbientOcclusionIntensity = realistic ? 0.9 : (style.hasPrefix("Shaded") ? 0.35 : 0)
        cam.screenSpaceAmbientOcclusionRadius = 0.4
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.2
        cam.vignettingIntensity = realistic ? 0.25 : 0
        cam.vignettingPower = 0.6
    }

    // MARK: Views

    func setView(_ name: String, animated: Bool = true) {
        if isWalking { toggleWalk() }
        let s = builder.worldSphere
        let fov = (cameraNode.camera?.fieldOfView ?? 45) * .pi / 180
        let d = s.radius / sin(fov / 2) * 1.15
        let dir: SCNVector3
        var up = SCNVector3(0, 1, 0)
        switch name.lowercased() {
        case "top", "plan": dir = SCNVector3(0, 1, 0); up = SCNVector3(0, 0, -1)
        case "bottom": dir = SCNVector3(0, -1, 0); up = SCNVector3(0, 0, 1)
        case "front", "south": dir = SCNVector3(0, 0, 1)
        case "back", "north": dir = SCNVector3(0, 0, -1)
        case "right", "east": dir = SCNVector3(1, 0, 0)
        case "left", "west": dir = SCNVector3(-1, 0, 0)
        case "se iso", "seiso": dir = Viewport3DController.norm(SCNVector3(1, 0.9, 1))
        case "ne iso", "neiso": dir = Viewport3DController.norm(SCNVector3(1, 0.9, -1))
        case "nw iso", "nwiso": dir = Viewport3DController.norm(SCNVector3(-1, 0.9, -1))
        default: dir = Viewport3DController.norm(SCNVector3(-1, 0.9, 1)) // SW iso
        }
        let pos = SCNVector3(s.center.x + dir.x * d, s.center.y + dir.y * d, s.center.z + dir.z * d)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.45 : 0
        cameraNode.position = pos
        cameraNode.look(at: s.center, up: up, localFront: SCNVector3(0, 0, -1))
        cameraNode.camera?.orthographicScale = Double(s.radius) * 1.1
        SCNTransaction.commit()
        view?.defaultCameraController.target = s.center
        view?.defaultCameraController.clearRoll()
    }

    func zoomExtents() {
        if isWalking { toggleWalk() }
        let s = builder.worldSphere
        let fov = (cameraNode.camera?.fieldOfView ?? 45) * .pi / 180
        let d = s.radius / sin(fov / 2) * 1.1
        var dir = cameraNode.worldFront
        dir = SCNVector3(-dir.x, -dir.y, -dir.z)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        cameraNode.position = SCNVector3(s.center.x + dir.x * d, s.center.y + dir.y * d, s.center.z + dir.z * d)
        cameraNode.camera?.orthographicScale = Double(s.radius) * 1.1
        SCNTransaction.commit()
        view?.defaultCameraController.target = s.center
    }

    func toggleProjection() {
        isOrtho.toggle()
        guard let cam = cameraNode.camera else { return }
        if isOrtho {
            let target = view?.defaultCameraController.target ?? builder.worldSphere.center
            let dist = Viewport3DController.length(Viewport3DController.sub(cameraNode.position, target))
            cam.orthographicScale = Double(max(0.5, dist * tan((cam.fieldOfView * .pi / 180) / 2)))
        }
        cam.usesOrthographicProjection = isOrtho
    }

    // MARK: Walk mode (WASD + drag to look, eye height 1.6 m)

    func toggleWalk() {
        isWalking.toggle()
        guard let v = view else { return }
        if isWalking {
            if isOrtho { toggleProjection() }
            v.allowsCameraControl = false
            let levelZ = (model.flatMap { m in m.doc.level(m.doc.currentLevel)?.elevation } ?? 0) * 0.001
            var p = cameraNode.presentation.worldPosition
            let s = builder.worldSphere
            if Viewport3DController.length(Viewport3DController.sub(p, s.center)) > s.radius * 1.5 || p.y > levelZ + 20 {
                p = SCNVector3(s.center.x, 0, s.center.z + s.radius * 1.2)
            }
            p.y = CGFloat(levelZ + 1.6)
            let f = cameraNode.presentation.worldFront
            yaw = atan2(-f.x, -f.z)
            pitch = 0
            cameraNode.position = p
            cameraNode.camera?.fieldOfView = 60
            applyLook()
            lastTick = Date()
            v.window?.makeFirstResponder(v)
            walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.walkStep() }
            }
            v.rendersContinuously = true
        } else {
            walkTimer?.invalidate(); walkTimer = nil
            v.pressedKeys.removeAll()
            v.rendersContinuously = false
            cameraNode.camera?.fieldOfView = 45
            let f = cameraNode.worldFront
            let p = cameraNode.position
            v.defaultCameraController.target = SCNVector3(p.x + f.x * 5, p.y + f.y * 5, p.z + f.z * 5)
            v.allowsCameraControl = true
        }
    }

    private func applyLook() {
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    func look(dx: CGFloat, dy: CGFloat) {
        yaw -= dx * 0.005
        pitch = max(-1.4, min(1.4, pitch - dy * 0.005))
        applyLook()
    }

    private func walkStep() {
        guard let v = view else { return }
        let now = Date(); let dt = CGFloat(min(0.1, now.timeIntervalSince(lastTick))); lastTick = now
        let keys = v.pressedKeys
        guard !keys.isEmpty else { return }
        let speed: CGFloat = (v.shiftDown ? 4.5 : 1.5) * dt
        let fwd = SCNVector3(-sin(yaw), 0, -cos(yaw)), right = SCNVector3(cos(yaw), 0, -sin(yaw))
        var m = SCNVector3(0, 0, 0)
        if keys.contains("w") || keys.contains(Character(UnicodeScalar(NSUpArrowFunctionKey)!)) { m = Viewport3DController.add(m, fwd) }
        if keys.contains("s") || keys.contains(Character(UnicodeScalar(NSDownArrowFunctionKey)!)) { m = Viewport3DController.sub(m, fwd) }
        if keys.contains("d") { m = Viewport3DController.add(m, right) }
        if keys.contains("a") { m = Viewport3DController.sub(m, right) }
        if keys.contains(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)) { yaw += 1.8 * dt; applyLook() }
        if keys.contains(Character(UnicodeScalar(NSRightArrowFunctionKey)!)) { yaw -= 1.8 * dt; applyLook() }
        if keys.contains("e") { m.y += 1 }
        if keys.contains("q") { m.y -= 1 }
        let p = cameraNode.position
        cameraNode.position = SCNVector3(p.x + m.x * speed, p.y + m.y * speed, p.z + m.z * speed)
    }

    // MARK: Picking

    func pick(at p: CGPoint, extend: Bool) {
        guard let v = view, let model else { return }
        let hits = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
        var id: EntityID?
        for h in hits {
            var n: SCNNode? = h.node
            while let c = n {
                if let name = c.name, name.hasPrefix("el:"), let i = Int(name.dropFirst(3)) { id = i; break }
                n = c.parent
            }
            if id != nil { break }
        }
        if let id {
            if extend { if model.editor.selection.contains(id) { model.editor.selection.remove(id) } else { model.editor.selection.insert(id) } }
            else { model.editor.selection = [id] }
        } else if !extend {
            model.editor.selection = []
        }
    }

    // MARK: Vector helpers
    static func add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func sub(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 { SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func length(_ a: SCNVector3) -> CGFloat { sqrt(a.x * a.x + a.y * a.y + a.z * a.z) }
    static func norm(_ a: SCNVector3) -> SCNVector3 { let l = max(length(a), 1e-9); return SCNVector3(a.x / l, a.y / l, a.z / l) }
}

/// SCNView with click-to-select and walk-mode keyboard/mouse handling.
final class ArchiSCNView: SCNView {
    weak var controller: Viewport3DController?
    var pressedKeys = Set<Character>()
    var shiftDown = false
    private var downPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        if controller?.isWalking == true { return }
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        if controller?.isWalking == true { MainActor.assumeIsolated { controller?.look(dx: event.deltaX, dy: event.deltaY) }; return }
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let d = downPoint, hypot(p.x - d.x, p.y - d.y) < 4 {
            let extend = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            MainActor.assumeIsolated { controller?.pick(at: p, extend: extend) }
        }
        downPoint = nil
        if controller?.isWalking != true { super.mouseUp(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        guard controller?.isWalking == true else { super.keyDown(with: event); return }
        if event.keyCode == 53 { MainActor.assumeIsolated { controller?.toggleWalk() }; return }
        shiftDown = event.modifierFlags.contains(.shift)
        for c in (event.charactersIgnoringModifiers ?? "").lowercased() { pressedKeys.insert(c) }
    }
    override func keyUp(with event: NSEvent) {
        guard controller?.isWalking == true else { super.keyUp(with: event); return }
        for c in (event.charactersIgnoringModifiers ?? "").lowercased() { pressedKeys.remove(c) }
    }
    override func flagsChanged(with event: NSEvent) {
        shiftDown = event.modifierFlags.contains(.shift)
        super.flagsChanged(with: event)
    }
}

// MARK: - SwiftUI view

struct Viewport3DView: View {
    @ObservedObject var model: AppModel
    @StateObject private var controller = Viewport3DController()
    init(model: AppModel) { self.model = model }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SceneHost(model: model, controller: controller, revision: model.revision, style: model.viewStyle)
            VStack(alignment: .trailing, spacing: 8) {
                overlay
                if model.showViewCube {
                    ViewCubeRepresentable(controller: controller)
                        .frame(width: 96, height: 96)
                        .help("View cube: click a face, edge or corner")
                }
                if model.showSectionBoxPanel { SectionBoxPanel(model: model, controller: controller) }
                if model.showSunStudy { SunStudyPanel(model: model, controller: controller) }
            }
            .padding(10)
            if controller.isWalking {
                VStack {
                    Spacer()
                    Text("Walk: W A S D to move · drag to look · Q/E down/up · Shift to run · Esc to exit")
                        .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(Theme.text)
                        .background(Capsule().fill(Theme.panel))
                        .padding(.bottom, 12)
                }.frame(maxWidth: .infinity)
            }
        }
        .onAppear { Viewport3DController.active = controller; model.viewport3D = controller }
    }

    private var overlay: some View {
        HStack(spacing: 2) {
            pill("Top", "square.grid.3x3.topleft.filled") { controller.setView("Top") }
            pill("Front", "square.bottomhalf.filled") { controller.setView("Front") }
            pill("Right", "square.righthalf.filled") { controller.setView("Right") }
            pill("Iso", "cube") { controller.setView("Iso") }
            Divider().frame(height: 16).padding(.horizontal, 3)
            pill(controller.isOrtho ? "Orthographic (click for perspective)" : "Perspective (click for orthographic)",
                 controller.isOrtho ? "square.stack.3d.up" : "perspective") { controller.toggleProjection() }
            pill("Zoom extents", "arrow.up.left.and.arrow.down.right") { controller.zoomExtents() }
            pill(controller.isWalking ? "Exit walk mode" : "Walk mode (WASD)", "figure.walk", active: controller.isWalking) { controller.toggleWalk() }
            pill("Orbit around the selection (zooms to it)", "scope", active: false) {
                if !controller.orbitSelection(model.editor.selection, frame: true) { model.editor.print("Select building elements to orbit around.") }
            }
            Divider().frame(height: 16).padding(.horizontal, 3)
            pill("Section box", "cube.transparent", active: model.showSectionBoxPanel || SectionBox.load(model.doc)?.on == true) { model.showSectionBoxPanel.toggle() }
            pill("Sun study", "sun.max", active: model.showSunStudy) { model.showSunStudy.toggle() }
            pill(model.showViewCube ? "Hide the view cube" : "Show the view cube", "cube", active: model.showViewCube) { model.showViewCube.toggle() }
            CamerasMenu(model: model, controller: controller)
            Divider().frame(height: 16).padding(.horizontal, 3)
            Menu {
                ForEach(Scene3DBuilder.visualStyles, id: \.self) { s in
                    Button { model.viewStyle = s } label: { if s == model.viewStyle { Label(s, systemImage: "checkmark") } else { Text(s) } }
                }
            } label: { Text(model.viewStyle).font(.caption) }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 6)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .foregroundStyle(Theme.text)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
    }

    private func pill(_ help: String, _ icon: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 24, height: 22)
                .foregroundStyle(active ? Theme.accent : Theme.text)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct SceneHost: NSViewRepresentable {
    let model: AppModel
    let controller: Viewport3DController
    let revision: Int
    let style: String

    func makeNSView(context: Context) -> ArchiSCNView {
        let v = ArchiSCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        controller.attach(v)
        controller.sync(model: model)
        return v
    }

    func updateNSView(_ v: ArchiSCNView, context: Context) {
        if controller.view !== v { controller.attach(v) }
        controller.sync(model: model)
    }
}
