// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// Section box face grips (VIS-035): a handle on each of the six faces; dragging one moves that face along its
/// normal and cuts the model live; releasing stores the box in the drawing (one undo step).
extension SectionBox {
    enum Face: Int, CaseIterable { case minX, maxX, minY, maxY, minZ, maxZ }
    static let minimumSize = 10.0

    /// Outward normal of a face (model axes).
    static func normal(_ f: Face) -> Vec3 {
        switch f {
        case .minX: return Vec3(-1, 0, 0); case .maxX: return Vec3(1, 0, 0)
        case .minY: return Vec3(0, -1, 0); case .maxY: return Vec3(0, 1, 0)
        case .minZ: return Vec3(0, 0, -1); case .maxZ: return Vec3(0, 0, 1)
        }
    }
    var center: Vec3 { (min + max) * 0.5 }
    func center(_ f: Face) -> Vec3 {
        let c = center
        switch f {
        case .minX: return Vec3(min.x, c.y, c.z); case .maxX: return Vec3(max.x, c.y, c.z)
        case .minY: return Vec3(c.x, min.y, c.z); case .maxY: return Vec3(c.x, max.y, c.z)
        case .minZ: return Vec3(c.x, c.y, min.z); case .maxZ: return Vec3(c.x, c.y, max.z)
        }
    }
    /// The box with one face moved outwards by `d` (negative = inwards), never thinner than `minimumSize`.
    func moved(_ f: Face, by d: Double) -> SectionBox {
        var b = self
        switch f {
        case .minX: b.min.x = Swift.min(min.x - d, max.x - SectionBox.minimumSize)
        case .maxX: b.max.x = Swift.max(max.x + d, min.x + SectionBox.minimumSize)
        case .minY: b.min.y = Swift.min(min.y - d, max.y - SectionBox.minimumSize)
        case .maxY: b.max.y = Swift.max(max.y + d, min.y + SectionBox.minimumSize)
        case .minZ: b.min.z = Swift.min(min.z - d, max.z - SectionBox.minimumSize)
        case .maxZ: b.max.z = Swift.max(max.z + d, min.z + SectionBox.minimumSize)
        }
        return b
    }
}

extension Viewport3DController {
    static let boxGripPrefix = "sbgrip:"

    /// Adds the six face handles to the box outline node.
    func addBoxGrips(_ box: SectionBox, to outline: SCNNode) {
        let r = CGFloat(Swift.max(0.06, (box.max - box.min).length * 0.0000125))
        for f in SectionBox.Face.allCases {
            let s = SCNSphere(radius: r)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Theme.nsAccent
            m.readsFromDepthBuffer = false
            s.materials = [m]
            let n = SCNNode(geometry: s)
            n.name = Viewport3DController.boxGripPrefix + "\(f.rawValue)"
            n.position = Scene3DBuilder.world(box.center(f))
            n.renderingOrder = 101
            n.castsShadow = false
            outline.addChildNode(n)
        }
    }

    var boxGripNodes: [SCNNode] {
        builder.scene.rootNode.childNode(withName: "sectionBoxOutline", recursively: false)?.childNodes.filter { $0.name?.hasPrefix(Viewport3DController.boxGripPrefix) == true } ?? []
    }

    /// Face handle under a view point.
    func sectionBoxFace(at p: CGPoint) -> SectionBox.Face? {
        guard let v = view, let outline = builder.scene.rootNode.childNode(withName: "sectionBoxOutline", recursively: false) else { return nil }
        let hits = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true, .rootNode: outline])
        for h in hits { if let n = h.node.name, n.hasPrefix(Viewport3DController.boxGripPrefix), let i = Int(n.dropFirst(Viewport3DController.boxGripPrefix.count)) { return SectionBox.Face(rawValue: i) } }
        return nil
    }

    /// Millimetres a face moves for a drag from `a` to `b` (the drag projected on the face normal's screen direction).
    func sectionBoxDragAmount(_ base: SectionBox, _ f: SectionBox.Face, from a: CGPoint, to b: CGPoint) -> Double {
        guard let v = view else { return 0 }
        let c = base.center(f), unit = 1000.0
        let s0 = v.projectPoint(Scene3DBuilder.world(c)), s1 = v.projectPoint(Scene3DBuilder.world(c + SectionBox.normal(f) * unit))
        let axis = CGVector(dx: (s1.x - s0.x) / unit, dy: (s1.y - s0.y) / unit)
        return GizmoMath.axisDelta(drag: CGVector(dx: b.x - a.x, dy: b.y - a.y), axisScreen: axis)
    }

    /// Live cut while dragging.
    func sectionBoxDragPreview(_ base: SectionBox, _ f: SectionBox.Face, amount: Double) {
        applyClipping(box: base.moved(f, by: amount), plane: model.flatMap { SectionPlane.load($0.doc) })
        view?.needsDisplay = true
    }

    /// Stores the dragged box in the drawing (undoable).
    func sectionBoxDragCommit(_ base: SectionBox, _ f: SectionBox.Face, amount: Double) {
        let b = base.moved(f, by: amount)
        guard let model, abs(amount) > 1e-9 else { return }
        model.editor.transaction("Section Box") { b.store(in: &$0) }
        applyClipping(box: b, plane: SectionPlane.load(model.doc))
    }
}
