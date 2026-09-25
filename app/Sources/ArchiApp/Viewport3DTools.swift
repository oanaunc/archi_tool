// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import SceneKit
import AppKit
import ArchiCore

// MARK: - 3D measuring (pick two points on the model)

enum Measure3D {
    /// Distance and axis deltas between two model points, in drawing units.
    static func describe(_ a: Vec3, _ b: Vec3, precision: Int = 1) -> String {
        let d = b - a
        return "Distance \(fmt(d.length, precision)) · ΔX \(fmt(d.x, precision)) · ΔY \(fmt(d.y, precision)) · ΔZ \(fmt(d.z, precision))"
            + " · plan \(fmt(Vec2(d.x, d.y).length, precision))"
    }
}

@MainActor
final class Measure3DState: ObservableObject {
    static let shared = Measure3DState()
    @Published var active = false
    @Published private(set) var points: [Vec3] = []
    @Published private(set) var text = ""

    func toggle() { set(!active) }
    func set(_ on: Bool) {
        active = on
        points = []
        text = on ? "Measure: click the first point on the model" : ""
        if on { Gizmo3DState.shared.mode = .off }
        Viewport3DController.active?.refreshMeasureNodes()
    }
    func add(_ p: Vec3) {
        if points.count >= 2 { points = [] }
        points.append(p)
        text = points.count == 1 ? "Measure: click the second point (from \(fmt(p.x, 0)), \(fmt(p.y, 0)), \(fmt(p.z, 0)))" : Measure3D.describe(points[0], points[1])
        if points.count == 2, let m = Viewport3DController.active?.model { m.editor.print(text) }
    }
}

// MARK: - Move / rotate gizmo

@MainActor
final class Gizmo3DState: ObservableObject {
    enum Mode: String, CaseIterable { case off = "Off", move = "Move", rotate = "Rotate" }
    static let shared = Gizmo3DState()
    @Published var mode: Mode = .off {
        didSet { if mode != .off && Measure3DState.shared.active { Measure3DState.shared.set(false) }; Viewport3DController.active?.refreshGizmo(force: true) }
    }
}

/// Pure gizmo maths (tested by the self-tests).
enum GizmoMath {
    /// Model displacement along a model axis for a mouse drag, given the screen projection of the axis per model unit.
    static func axisDelta(drag: CGVector, axisScreen: CGVector) -> Double {
        let l2 = axisScreen.dx * axisScreen.dx + axisScreen.dy * axisScreen.dy
        guard l2 > 1e-12 else { return 0 }
        return Double((drag.dx * axisScreen.dx + drag.dy * axisScreen.dy) / l2)
    }
    /// Signed angle (radians, counter-clockwise on screen) swept from `a` to `b` around `c`.
    static func sweep(center c: CGPoint, from a: CGPoint, to b: CGPoint) -> Double {
        let a0 = atan2(Double(a.y - c.y), Double(a.x - c.x)), a1 = atan2(Double(b.y - c.y), Double(b.x - c.x))
        var d = a1 - a0
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
    /// Snaps an angle to `step` radians (0 = no snapping).
    static func snap(_ v: Double, step: Double) -> Double { step > 0 ? (v / step).rounded() * step : v }
    /// Transform applied to the selection for a move along plan axis (0 = X, 1 = Y) or a rotation about Z through `pivot`.
    static func transform(axis: Int, amount: Double, pivot: Vec2) -> Transform2D {
        switch axis {
        case 0: return .translation(Vec2(amount, 0))
        case 1: return .translation(Vec2(0, amount))
        default: return .rotation(amount, around: pivot)
        }
    }
    /// Applies a plan transform to objects as one undo step. Locked objects are skipped. Returns the number changed.
    @MainActor @discardableResult
    static func apply(_ ed: Editor, ids: [EntityID], _ t: Transform2D, label: String) -> Int {
        let targets = ed.expandGroups(ids).filter { ed.isSelectable($0) }
        guard !targets.isEmpty else { return 0 }
        var n = 0
        ed.transaction(label) { d in
            for id in targets {
                if let i = d.entityIndex(id) { d.entities[i].geometry = GeometryOps.transform(d.entities[i].geometry, t); n += 1 }
                else if let i = d.elementIndex(id) { d.elements[i].geometry = CommandHelpers.transform(d.elements[i].geometry, t); n += 1 }
            }
        }
        return n
    }
}

/// Gizmo state kept beside the scene nodes (SceneKit nodes do not store arbitrary values).
@MainActor
private final class GizmoRuntime {
    static var byController: [ObjectIdentifier: GizmoRuntime] = [:]
    var mode: Gizmo3DState.Mode = .off
    var selection: Set<EntityID> = []
    var pivot: SCNVector3?
    var dragging = false
}

extension Viewport3DController {
    private var gizmoRT: GizmoRuntime {
        let k = ObjectIdentifier(self)
        if let r = GizmoRuntime.byController[k] { return r }
        let r = GizmoRuntime(); GizmoRuntime.byController[k] = r; return r
    }
    private var toolsRoot: SCNNode {
        if let n = builder.modelRoot.childNode(withName: "tools3d", recursively: false) { return n }
        let n = SCNNode(); n.name = "tools3d"; builder.modelRoot.addChildNode(n); return n
    }

    /// Model point (mm) under a view point, nil when the ray hits nothing of the model.
    func modelPoint(at p: CGPoint) -> (point: Vec3, id: EntityID?)? {
        guard let v = view else { return nil }
        let hits = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for h in hits {
            var n: SCNNode? = h.node, id: EntityID?, tool = false
            while let c = n {
                if c.name == "tools3d" { tool = true; break }
                if id == nil, let name = c.name, name.hasPrefix("el:") { id = Int(name.dropFirst(3)) }
                n = c.parent
            }
            if tool { continue }
            let w = builder.modelRoot.convertPosition(h.worldCoordinates, from: nil)
            return (Vec3(Double(w.x), Double(w.y), Double(w.z)), id)
        }
        return nil
    }

    // MARK: Measure

    func measurePick(at p: CGPoint) {
        guard let hit = modelPoint(at: p) else { return }
        Measure3DState.shared.add(hit.point)
        refreshMeasureNodes()
    }

    func refreshMeasureNodes() {
        toolsRoot.childNode(withName: "measure", recursively: false)?.removeFromParentNode()
        let pts = Measure3DState.shared.points
        guard Measure3DState.shared.active, !pts.isEmpty else { return }
        let g = SCNNode(); g.name = "measure"
        let r = max(20, (builder.bounds.isEmpty ? 10000 : max(builder.bounds.max.x - builder.bounds.min.x, builder.bounds.max.y - builder.bounds.min.y)) / 300)
        let mat = SCNMaterial(); mat.diffuse.contents = Scene3DBuilder.accent; mat.emission.contents = Scene3DBuilder.accent; mat.readsFromDepthBuffer = false
        for q in pts {
            let s = SCNNode(geometry: SCNSphere(radius: CGFloat(r)))
            s.geometry?.materials = [mat]; s.position = SCNVector3(q.x, q.y, q.z); s.renderingOrder = 100
            g.addChildNode(s)
        }
        if pts.count == 2 {
            let src = SCNGeometrySource(vertices: pts.map { SCNVector3($0.x, $0.y, $0.z) })
            let el = SCNGeometryElement(indices: [Int32(0), 1], primitiveType: .line)
            let line = SCNGeometry(sources: [src], elements: [el]); line.materials = [mat]
            let ln = SCNNode(geometry: line); ln.renderingOrder = 100
            g.addChildNode(ln)
        }
        toolsRoot.addChildNode(g)
    }

    // MARK: Gizmo

    /// Plan centre and height of the selection's 3D nodes (model mm).
    func selectionCenter(_ ids: Set<EntityID>) -> Vec3? {
        var b = BBox3.empty
        for id in ids {
            guard let n = builder.modelRoot.childNode(withName: "el:\(id)", recursively: false) else { continue }
            let (lo, hi) = n.boundingBox
            if lo.x > hi.x { continue }
            b.add(Vec3(Double(lo.x), Double(lo.y), Double(lo.z))); b.add(Vec3(Double(hi.x), Double(hi.y), Double(hi.z)))
        }
        guard !b.isEmpty else { return nil }
        return Vec3((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, b.max.z)
    }

    func refreshGizmo(force: Bool = false) {
        let mode = Gizmo3DState.shared.mode
        let existing = toolsRoot.childNode(withName: "gizmo", recursively: false)
        guard mode != .off, let model, !model.editor.selection.isEmpty, let c = selectionCenter(model.editor.selection) else { existing?.removeFromParentNode(); return }
        let rt = gizmoRT
        if rt.dragging { return }
        if !force, let e = existing, rt.mode == mode, rt.selection == model.editor.selection,
           abs(Double(e.position.x) - c.x) < 1e-6, abs(Double(e.position.y) - c.y) < 1e-6 { return }
        existing?.removeFromParentNode()
        let size = CGFloat(max(400, (builder.bounds.isEmpty ? 10000 : max(builder.bounds.max.x - builder.bounds.min.x, builder.bounds.max.y - builder.bounds.min.y)) / 12))
        let g = SCNNode(); g.name = "gizmo"; g.position = SCNVector3(c.x, c.y, c.z + 50)
        rt.mode = mode; rt.selection = model.editor.selection; rt.pivot = nil
        func mat(_ col: NSColor) -> SCNMaterial { let m = SCNMaterial(); m.diffuse.contents = col; m.emission.contents = col; m.readsFromDepthBuffer = false; m.lightingModel = .constant; return m }
        if mode == .move {
            for (axis, col) in [(0, NSColor.systemRed), (1, NSColor.systemGreen)] {
                let shaft = SCNNode(geometry: SCNCylinder(radius: size * 0.03, height: size)); shaft.geometry?.materials = [mat(col)]
                let tip = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: size * 0.09, height: size * 0.25)); tip.geometry?.materials = [mat(col)]
                tip.position = SCNVector3(0, size * 0.6, 0)
                let arm = SCNNode(); arm.name = "axis\(axis)"
                shaft.position = SCNVector3(0, size / 2, 0)
                tip.position = SCNVector3(0, size * 1.125, 0)
                arm.addChildNode(shaft); arm.addChildNode(tip)
                // Cylinders point along +Y: a −90° turn about Z puts the X arm on +X.
                if axis == 0 { arm.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2) }
                for n in [shaft, tip] { n.name = "axis\(axis)"; n.renderingOrder = 110 }
                g.addChildNode(arm)
            }
        } else {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: size * 0.7, pipeRadius: size * 0.035)); ring.geometry?.materials = [mat(NSColor.systemBlue)]
            ring.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)   // torus lies in XZ; turn it into the model XY plane
            ring.name = "axis2"; ring.renderingOrder = 110
            g.addChildNode(ring)
        }
        toolsRoot.addChildNode(g)
    }

    /// Gizmo handle under a view point (0 = X, 1 = Y, 2 = rotation ring).
    func gizmoAxis(at p: CGPoint) -> Int? {
        guard let v = view, toolsRoot.childNode(withName: "gizmo", recursively: false) != nil else { return nil }
        let hits = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true, .rootNode: toolsRoot])
        for h in hits { if let n = h.node.name, n.hasPrefix("axis"), let a = Int(n.dropFirst(4)) { return a } }
        return nil
    }

    private func screen(_ q: Vec3) -> CGPoint? {
        guard let v = view else { return nil }
        let w = builder.modelRoot.convertPosition(SCNVector3(q.x, q.y, q.z), to: nil)
        let s = v.projectPoint(w)
        return CGPoint(x: s.x, y: s.y)
    }

    /// Amount (mm or radians) of a gizmo drag from `a` to `b` on the view.
    func gizmoAmount(axis: Int, from a: CGPoint, to b: CGPoint) -> Double {
        guard let g = toolsRoot.childNode(withName: "gizmo", recursively: false) else { return 0 }
        let c = Vec3(Double(g.position.x), Double(g.position.y), Double(g.position.z))
        guard let sc = screen(c) else { return 0 }
        if axis == 2 {
            return GizmoMath.snap(GizmoMath.sweep(center: sc, from: a, to: b), step: NSEvent.modifierFlags.contains(.shift) ? .pi / 12 : 0)
        }
        let unit = 1000.0
        guard let se = screen(c + (axis == 0 ? Vec3(unit, 0, 0) : Vec3(0, unit, 0))) else { return 0 }
        let axisScreen = CGVector(dx: (se.x - sc.x) / unit, dy: (se.y - sc.y) / unit)
        var d = GizmoMath.axisDelta(drag: CGVector(dx: b.x - a.x, dy: b.y - a.y), axisScreen: axisScreen)
        if let m = model, m.editor.settings.gridSnap, m.editor.settings.gridSpacing > 0 { d = GizmoMath.snap(d, step: m.editor.settings.gridSpacing) }
        return d
    }

    /// Live preview: moves/rotates the selected nodes and the gizmo by `amount`.
    func gizmoPreview(axis: Int, amount: Double) {
        guard let model, let g = toolsRoot.childNode(withName: "gizmo", recursively: false) else { return }
        let pivot = gizmoRT.pivot ?? g.position
        if gizmoRT.pivot == nil { gizmoRT.pivot = pivot }
        gizmoRT.dragging = true
        for id in model.editor.selection {
            guard let n = builder.modelRoot.childNode(withName: "el:\(id)", recursively: false) else { continue }
            if axis == 2 {
                let t = SCNMatrix4Mult(SCNMatrix4Mult(SCNMatrix4MakeTranslation(-pivot.x, -pivot.y, 0), SCNMatrix4MakeRotation(CGFloat(amount), 0, 0, 1)), SCNMatrix4MakeTranslation(pivot.x, pivot.y, 0))
                n.transform = t
            } else {
                n.transform = SCNMatrix4MakeTranslation(axis == 0 ? CGFloat(amount) : 0, axis == 1 ? CGFloat(amount) : 0, 0)
            }
        }
        if axis != 2 { g.position = SCNVector3(pivot.x + (axis == 0 ? CGFloat(amount) : 0), pivot.y + (axis == 1 ? CGFloat(amount) : 0), pivot.z) }
        else { g.eulerAngles = SCNVector3(0, 0, CGFloat(amount)) }
        model.live.snapHint = axis == 2 ? "Rotate \(fmt(amount * 180 / .pi, 1))° (Shift snaps 15°)" : "Move \(axis == 0 ? "X" : "Y") \(fmt(amount, 1))"
    }

    /// Ends a gizmo drag: resets the preview and applies the transform to the drawing as one undo step.
    func gizmoCommit(axis: Int, amount: Double) {
        guard let model else { return }
        let g = toolsRoot.childNode(withName: "gizmo", recursively: false)
        let pivot = gizmoRT.pivot ?? g?.position ?? SCNVector3(0, 0, 0)
        gizmoRT.pivot = nil; gizmoRT.selection = []; gizmoRT.dragging = false
        for id in model.editor.selection { builder.modelRoot.childNode(withName: "el:\(id)", recursively: false)?.transform = SCNMatrix4Identity }
        g?.removeFromParentNode()
        guard abs(amount) > 1e-9 else { refreshGizmo(force: true); return }
        let t = GizmoMath.transform(axis: axis, amount: amount, pivot: Vec2(Double(pivot.x), Double(pivot.y)))
        let n = GizmoMath.apply(model.editor, ids: Array(model.editor.selection), t, label: axis == 2 ? "Rotate (3D gizmo)" : "Move (3D gizmo)")
        model.editor.print(axis == 2 ? "Rotated \(n) object(s) by \(fmt(amount * 180 / .pi, 2))°." : "Moved \(n) object(s) by \(fmt(amount, 2)) along \(axis == 0 ? "X" : "Y").")
        model.revision &+= 1
    }

    // MARK: Drop materials and library items on the 3D model

    func drop(_ s: String, at p: CGPoint) -> Bool {
        guard let model else { return false }
        let hit = modelPoint(at: p)
        let at = hit.map { Vec2($0.point.x, $0.point.y) } ?? .zero
        let target = hit?.id.flatMap { id in model.doc.element(id) != nil ? id : nil }
        return ToolDrop.drop(s, at: at, onto: target, model: model)
    }
}

/// Measure / gizmo readout shown at the bottom of the 3D viewport.
struct Viewport3DToolBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var measure = Measure3DState.shared
    @ObservedObject var gizmo = Gizmo3DState.shared
    var body: some View {
        HStack(spacing: 8) {
            Button { measure.toggle() } label: { Image(systemName: "ruler").foregroundStyle(measure.active ? Theme.accent : Theme.text) }
                .buttonStyle(.borderless).help("Measure in 3D: click two points on the model (MEASURE3D)")
            Picker("", selection: $gizmo.mode) { ForEach(Gizmo3DState.Mode.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170).help("Move/rotate gizmo for the selection (GIZMO3D); Shift snaps rotation to 15°")
            if measure.active || !measure.text.isEmpty { Text(measure.text).font(Theme.mono).foregroundStyle(Theme.text).lineLimit(1) }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
    }
}

// MARK: - Clipping plane panel

@MainActor
final class ClipPlaneState: ObservableObject {
    static let shared = ClipPlaneState()
    @Published var visible = false
}

/// Orientation + offset form of a section (clipping) plane.
enum ClipPlaneForm {
    enum Orientation: String, CaseIterable { case horizontal = "Horizontal", alongX = "Along X", alongY = "Along Y" }
    /// Plane normal of an orientation (the half-space on the normal side is cut away).
    static func normal(_ o: Orientation, flipped: Bool) -> Vec3 {
        let n: Vec3 = o == .horizontal ? Vec3(0, 0, 1) : o == .alongX ? Vec3(0, 1, 0) : Vec3(1, 0, 0)
        return flipped ? n * -1 : n
    }
    /// Axis coordinate (x, y or z) a plane of the orientation runs through.
    static func axis(_ o: Orientation) -> WritableKeyPath<Vec3, Double> { o == .horizontal ? \.z : o == .alongX ? \.y : \.x }
    static func plane(_ o: Orientation, offset: Double, flipped: Bool, on: Bool = true) -> SectionPlane {
        var p = Vec3(0, 0, 0); p[keyPath: axis(o)] = offset
        return SectionPlane(on: on, point: p, normal: normal(o, flipped: flipped))
    }
    /// Recognises a stored plane that is axis-aligned (for editing it in the panel).
    static func form(_ p: SectionPlane) -> (Orientation, offset: Double, flipped: Bool)? {
        for o in Orientation.allCases {
            let n = normal(o, flipped: false)
            if p.normal.isClose(n, tol: 1e-6) { return (o, p.point[keyPath: axis(o)], false) }
            if p.normal.isClose(n * -1, tol: 1e-6) { return (o, p.point[keyPath: axis(o)], true) }
        }
        return nil
    }
}

struct ClipPlanePanel: View {
    @ObservedObject var model: AppModel
    let controller: Viewport3DController
    @State private var orientation: ClipPlaneForm.Orientation = .horizontal
    @State private var offset = 1200.0
    @State private var flipped = false
    @State private var on = true
    @State private var extents = BBox3.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.split.diagonal").foregroundStyle(Theme.accent)
                Text("Clipping Plane").font(Theme.fontBold)
                Spacer()
                Toggle("On", isOn: Binding(get: { on }, set: { on = $0; live(); commit() })).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                IconButton(symbol: "xmark", help: "Close") { ClipPlaneState.shared.visible = false }
            }
            Picker("", selection: Binding(get: { orientation }, set: { orientation = $0; offset = mid(); live(); commit() })) {
                ForEach(ClipPlaneForm.Orientation.allCases, id: \.self) { Text($0.rawValue) }
            }.pickerStyle(.segmented).labelsHidden()
            let r = range()
            HStack {
                Slider(value: Binding(get: { offset }, set: { offset = $0; live() }), in: r, onEditingChanged: { if !$0 { commit() } })
                Text(fmt(offset, 0)).font(Theme.mono).frame(width: 60, alignment: .trailing)
            }
            HStack {
                Button("Flip") { flipped.toggle(); live(); commit() }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Level") { fitLevel() }.buttonStyle(FlatButtonStyle(compact: true)).help("Horizontal cut 1.2 m above the current level")
                Button("Remove") { remove() }.buttonStyle(FlatButtonStyle(compact: true))
            }
        }
        .font(Theme.font)
        .padding(10)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .onAppear {
            extents = controller.builder.bounds
            if let p = SectionPlane.load(model.doc), let f = ClipPlaneForm.form(p) { orientation = f.0; offset = f.offset; flipped = f.flipped; on = p.on }
            else { offset = mid(); live(); commit() }
        }
    }

    private func range() -> ClosedRange<Double> {
        guard !extents.isEmpty else { return 0...10000 }
        let k = ClipPlaneForm.axis(orientation)
        let lo = extents.min[keyPath: k] - 100, hi = extents.max[keyPath: k] + 100
        return lo...max(hi, lo + 1)
    }
    private func mid() -> Double { let r = range(); return (r.lowerBound + r.upperBound) / 2 }
    private var plane: SectionPlane { ClipPlaneForm.plane(orientation, offset: offset, flipped: flipped, on: on) }
    private func live() { controller.applyClipping(box: SectionBox.load(model.doc), plane: plane) }
    private func commit() {
        let p = plane
        guard SectionPlane.load(model.doc) != p else { return }
        model.editor.transaction("Clipping Plane") { p.store(in: &$0) }
    }
    private func fitLevel() {
        orientation = .horizontal; flipped = false; on = true
        offset = (model.doc.level(model.doc.currentLevel)?.elevation ?? 0) + 1200 / max(model.doc.units.mm, 1e-9)
        live(); commit()
    }
    private func remove() {
        on = false
        model.editor.transaction("Clipping Plane") { $0.variables[SectionPlane.variable] = nil }
        controller.applyClipping(box: SectionBox.load(model.doc), plane: nil)
        ClipPlaneState.shared.visible = false
    }
}
