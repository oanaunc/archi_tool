// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import ArchiCore

/// First-person navigation modes of the 3D view (VIS-017 walk, VIS-018 fly, VIS-020 look around).
enum NavMode: String, CaseIterable {
    case walk = "Walk", fly = "Fly", look = "Look Around"
    var hint: String {
        switch self {
        case .walk: return "Walk: W A S D to move · drag to look · walls stop you, floors and stairs carry you · Shift to run · Esc to exit"
        case .fly: return "Fly: W A S D along the view direction · Q/E down/up · drag to look · Shift for speed · Esc to exit"
        case .look: return "Look around: drag or arrow keys to turn the head · the eye stays in place · Esc to exit"
        }
    }
}

/// Collision and gravity for walk mode, in SceneKit world units (metres, Y up). `ray(from, to)` returns the distance
/// from `from` to the first surface hit on the segment, or nil.
enum WalkPhysics {
    static let eyeHeight: CGFloat = 1.6
    /// Body radius kept from walls.
    static let radius: CGFloat = 0.3
    /// Highest step climbed without jumping (stairs, thresholds).
    static let stepHeight: CGFloat = 0.45
    static let gravity: CGFloat = 9.81

    /// Parameter t ∈ [0, 1] of the first triangle hit on segment a→b (model coordinates), or nil.
    static func firstHit(_ a: Vec3, _ b: Vec3, groups: [(bounds: BBox3, mesh: Mesh)]) -> Double? {
        let d = b - a
        var best: Double?
        for g in groups {
            // Slab test of the segment against the group's box (1 mm margin).
            var t0 = 0.0, t1 = best ?? 1.0, miss = false
            for (o, dd, lo, hi) in [(a.x, d.x, g.bounds.min.x, g.bounds.max.x), (a.y, d.y, g.bounds.min.y, g.bounds.max.y), (a.z, d.z, g.bounds.min.z, g.bounds.max.z)] {
                if abs(dd) < 1e-12 { if o < lo - 1 || o > hi + 1 { miss = true; break }; continue }
                var ta = (lo - 1 - o) / dd, tb = (hi + 1 - o) / dd
                if ta > tb { swap(&ta, &tb) }
                t0 = max(t0, ta); t1 = min(t1, tb)
                if t0 > t1 { miss = true; break }
            }
            if miss { continue }
            let m = g.mesh
            var i = 0
            while i + 2 < m.indices.count {
                let p0 = m.positions[Int(m.indices[i])], p1 = m.positions[Int(m.indices[i + 1])], p2 = m.positions[Int(m.indices[i + 2])]
                i += 3
                let e1 = p1 - p0, e2 = p2 - p0
                let h = d.cross(e2)
                let det = e1.dot(h)
                if abs(det) < 1e-12 { continue }
                let f = 1 / det
                let s = a - p0
                let u = f * s.dot(h)
                if u < 0 || u > 1 { continue }
                let q = s.cross(e1)
                let v = f * d.dot(q)
                if v < 0 || u + v > 1 { continue }
                let t = f * e2.dot(q)
                if t >= 0 && t <= 1 && t < (best ?? 2) { best = t }
            }
        }
        return best
    }

    static func step(eye: SCNVector3, move: SCNVector3, fallSpeed: inout CGFloat, dt: CGFloat, ray: (SCNVector3, SCNVector3) -> CGFloat?) -> SCNVector3 {
        var pos = eye
        let feet = eye.y - eyeHeight
        // Horizontal movement: full move, else slide along X or Z.
        let len = hypot(move.x, move.z)
        if len > 1e-9 {
            let tries = [SCNVector3(move.x, 0, move.z), SCNVector3(move.x, 0, 0), SCNVector3(0, 0, move.z)]
            for t in tries {
                let l = hypot(t.x, t.z)
                guard l > 1e-9 else { continue }
                let dir = SCNVector3(t.x / l, 0, t.z / l)
                var blocked = false
                for h in [feet + stepHeight + 0.05, feet + 1.0, eye.y - 0.05] {
                    let from = SCNVector3(eye.x, h, eye.z)
                    let to = SCNVector3(eye.x + dir.x * (l + radius), h, eye.z + dir.z * (l + radius))
                    if let d = ray(from, to), d < l + radius { blocked = true; break }
                }
                if !blocked { pos.x += t.x; pos.z += t.z; break }
            }
        }
        // Vertical: find the floor under the new position from step height above the feet.
        let start = SCNVector3(pos.x, feet + stepHeight, pos.z)
        if let d = ray(start, SCNVector3(pos.x, feet - 60, pos.z)) {
            let floor = start.y - d
            if floor >= feet - 0.01 {
                pos.y = floor + eyeHeight; fallSpeed = 0
            } else {
                fallSpeed += gravity * dt
                pos.y = max(floor, feet - fallSpeed * dt) + eyeHeight
                if pos.y - eyeHeight <= floor + 1e-6 { fallSpeed = 0 }
            }
        } else {
            fallSpeed = 0
            pos.y = eye.y
        }
        return pos
    }
}

/// Steering wheel (VIS-019): wedges of the full navigation wheel and their hit test.
enum SteeringWheel {
    enum Wedge: String, CaseIterable { case zoom = "ZOOM", rewind = "REWIND", pan = "PAN", orbit = "ORBIT", center = "CENTER", walk = "WALK", look = "LOOK", upDown = "UP/DOWN" }
    /// Outer ring: 4 wedges clockwise from the top; inner ring: 4 wedges.
    static let outer: [Wedge] = [.zoom, .pan, .orbit, .rewind]
    static let inner: [Wedge] = [.center, .walk, .upDown, .look]
    static let size: CGFloat = 170
    static var innerRadius: CGFloat { size * 0.18 }
    static var middleRadius: CGFloat { size * 0.33 }
    static var outerRadius: CGFloat { size * 0.5 }

    /// Wedge under a point of a wheel of `size` points (origin top-left), or nil in the hole/outside.
    static func wedge(at p: CGPoint, size s: CGFloat = size) -> Wedge? {
        let c = CGPoint(x: s / 2, y: s / 2)
        let dx = p.x - c.x, dy = c.y - p.y
        let r = hypot(dx, dy)
        let k = s / size
        guard r >= innerRadius * k, r <= outerRadius * k else { return nil }
        // Angle clockwise from the top, sectors centred on 0°, 90°, 180°, 270°.
        var a = atan2(dx, dy) * 180 / .pi
        if a < 0 { a += 360 }
        let i = Int(((a + 45) / 90).rounded(.down)) % 4
        return r >= middleRadius * k ? outer[i] : inner[i]
    }
    /// Centre of a wedge's label (for drawing).
    static func labelPoint(_ w: Wedge, size s: CGFloat = size) -> CGPoint {
        let isOuter = outer.contains(w)
        let i = (isOuter ? outer : inner).firstIndex(of: w)!
        let r = isOuter ? (middleRadius + outerRadius) / 2 : (innerRadius + middleRadius) / 2
        let a = CGFloat(i) * .pi / 2
        return CGPoint(x: s / 2 + sin(a) * r * s / size, y: s / 2 - cos(a) * r * s / size)
    }
}

extension Viewport3DController {
    // MARK: Walk / fly / look entry points

    func startNavigation(_ mode: NavMode) {
        if isWalking && navMode == mode { return }
        if isWalking { toggleWalk() }
        navMode = mode
        toggleWalk()
    }

    /// Ray test against the model meshes (walls, slabs, stairs…; not lights, billboards or the ground grid) for walk
    /// collisions: segment in world metres → distance in metres to the first triangle hit (Möller–Trumbore).
    func collisionRay(_ from: SCNVector3, _ to: SCNVector3) -> CGFloat? {
        let a = Scene3DBuilder.model(from), b = Scene3DBuilder.model(to)
        return WalkPhysics.firstHit(a, b, groups: builder.collisionGroups).map { CGFloat($0 * a.distance(to: b) * 0.001) }
    }

    // MARK: Named cameras and camera objects (VIS-039)

    /// Applies a saved camera: a project 3D view (CAMERAVIEW / AXONVIEW) or a named view with a camera.
    @discardableResult
    func applyNamedCamera(_ name: String, doc: ArchiDocument, animated: Bool = true) -> Bool {
        if let v = doc.view(named: name), let c = v.camera { apply(camera: c, animated: animated); return true }
        if let v = CameraStore.find(name, in: doc), let c = v.camera { apply(camera: c, animated: animated); return true }
        return false
    }

    /// Places the eye at a plan point at eye height looking at a target (SketchUp "position camera", VIS-020).
    func positionCamera(eye: Vec2, target: Vec2, eyeHeight: Double, levelElevation: Double) {
        let z = levelElevation + eyeHeight
        apply(camera: Camera(eye: Vec3(eye.x, eye.y, z), target: Vec3(target.x, target.y, z), fov: 60), animated: false)
    }

    // MARK: Two-point perspective (VIS-023)

    /// Levels the camera (vertical lines stay vertical) and shifts the lens so the target stays at the same height on screen.
    func setTwoPoint(_ on: Bool, viewport size: CGSize? = nil) {
        guard let cam = cameraNode.camera else { return }
        let fresh = SCNCamera()
        fresh.fieldOfView = cam.fieldOfView; fresh.zNear = cam.zNear; fresh.zFar = cam.zFar
        fresh.automaticallyAdjustsZRange = cam.automaticallyAdjustsZRange
        fresh.usesOrthographicProjection = cam.usesOrthographicProjection; fresh.orthographicScale = cam.orthographicScale
        fresh.wantsHDR = cam.wantsHDR; fresh.screenSpaceAmbientOcclusionIntensity = cam.screenSpaceAmbientOcclusionIntensity
        cameraNode.camera = fresh
        guard on else { twoPointShift = nil; return }
        if isOrtho { toggleProjection() }
        let p = cameraNode.worldPosition
        let f = cameraNode.worldFront
        let pitch = asin(max(-1, min(1, f.y)))
        let h = hypot(f.x, f.z)
        let yawA = h > 1e-6 ? atan2(-f.x, -f.z) : 0
        cameraNode.position = p
        cameraNode.eulerAngles = SCNVector3(0, yawA, 0)   // exactly level, no roll
        let half = fresh.fieldOfView * .pi / 360
        let shift = max(-3, min(3, tan(pitch) / tan(half)))
        let s = size ?? view?.bounds.size ?? CGSize(width: 1600, height: 1000)
        applyTwoPointProjection(shift: shift, size: s)
    }

    func applyTwoPointProjection(shift: CGFloat, size: CGSize) {
        guard let cam = cameraNode.camera, size.width > 0, size.height > 0 else { return }
        cam.projectionDirection = .vertical
        var m = cam.projectionTransform(withViewportSize: size)
        m.m32 = shift
        cam.projectionTransform = m
        twoPointShift = shift
        twoPointSize = size
    }

    /// Re-applies the lens shift after a resize (the projection depends on the aspect ratio).
    func refreshTwoPoint() {
        guard let s = twoPointShift, let v = view, v.bounds.size != twoPointSize, v.bounds.width > 0 else { return }
        applyTwoPointProjection(shift: s, size: v.bounds.size)
    }

    /// Projects a world point with the camera's view and projection to normalized device coordinates.
    func ndc(_ p: SCNVector3, size: CGSize) -> CGPoint? {
        guard let cam = cameraNode.camera else { return nil }
        let viewM = SCNMatrix4Invert(cameraNode.worldTransform)
        let proj = twoPointShift != nil ? cam.projectionTransform : cam.projectionTransform(withViewportSize: size)
        func mul(_ v: (CGFloat, CGFloat, CGFloat, CGFloat), _ m: SCNMatrix4) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            (v.0 * m.m11 + v.1 * m.m21 + v.2 * m.m31 + v.3 * m.m41, v.0 * m.m12 + v.1 * m.m22 + v.2 * m.m32 + v.3 * m.m42,
             v.0 * m.m13 + v.1 * m.m23 + v.2 * m.m33 + v.3 * m.m43, v.0 * m.m14 + v.1 * m.m24 + v.2 * m.m34 + v.3 * m.m44)
        }
        let c = mul(mul((p.x, p.y, p.z, 1), viewM), proj)
        guard abs(c.3) > 1e-9 else { return nil }
        return CGPoint(x: c.0 / c.3, y: c.1 / c.3)
    }

    // MARK: Steering wheel operations (VIS-019)

    var pivot: SCNVector3 { wheelPivot ?? view?.defaultCameraController.target ?? builder.worldSphere.center }

    func pushCameraHistory() {
        cameraHistory.append(currentCamera)
        if cameraHistory.count > 50 { cameraHistory.removeFirst() }
    }

    func wheelZoom(_ d: CGFloat) {
        let c = pivot, p = cameraNode.position
        let k = exp(-d * 0.01)
        if isOrtho, let cam = cameraNode.camera { cam.orthographicScale = max(0.05, cam.orthographicScale * Double(k)); return }
        let off = Viewport3DController.sub(p, c)
        guard Viewport3DController.length(off) * k > 0.05 else { return }
        cameraNode.position = SCNVector3(c.x + off.x * k, c.y + off.y * k, c.z + off.z * k)
    }

    func wheelOrbit(dx: CGFloat, dy: CGFloat) {
        let c = pivot
        var off = Viewport3DController.sub(cameraNode.position, c)
        let yawA = -dx * 0.01
        off = SCNVector3(off.x * cos(yawA) + off.z * sin(yawA), off.y, -off.x * sin(yawA) + off.z * cos(yawA))
        let r = Viewport3DController.length(off)
        let el = max(-1.45, min(1.45, asin(max(-1, min(1, off.y / max(r, 1e-9)))) + dy * 0.01))
        let h = hypot(off.x, off.z)
        let hd = h > 1e-9 ? (off.x / h, off.z / h) : (CGFloat(0), CGFloat(1))
        off = SCNVector3(hd.0 * r * cos(el), r * sin(el), hd.1 * r * cos(el))
        cameraNode.position = Viewport3DController.add(c, off)
        cameraNode.look(at: c, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    func wheelPan(dx: CGFloat, dy: CGFloat) {
        let d = max(Viewport3DController.length(Viewport3DController.sub(cameraNode.position, pivot)), 1) * 0.0025
        let r = cameraNode.worldRight, u = cameraNode.worldUp
        let t = SCNVector3(-r.x * dx * d + u.x * dy * d, -r.y * dx * d + u.y * dy * d, -r.z * dx * d + u.z * dy * d)
        cameraNode.position = Viewport3DController.add(cameraNode.position, t)
        wheelPivot = Viewport3DController.add(pivot, t)
    }

    func wheelLook(dx: CGFloat, dy: CGFloat) {
        let f = cameraNode.worldFront
        var yawA = atan2(-f.x, -f.z), pitchA = asin(max(-1, min(1, f.y)))
        yawA -= dx * 0.005; pitchA = max(-1.4, min(1.4, pitchA + dy * 0.005))
        cameraNode.eulerAngles = SCNVector3(pitchA, yawA, 0)
    }

    func wheelUpDown(_ d: CGFloat) {
        cameraNode.position = Viewport3DController.add(cameraNode.position, SCNVector3(0, d * 0.02, 0))
    }

    func wheelWalk(_ d: CGFloat) {
        let f = cameraNode.worldFront
        let h = hypot(f.x, f.z)
        guard h > 1e-6 else { return }
        cameraNode.position = Viewport3DController.add(cameraNode.position, SCNVector3(f.x / h * d * 0.03, 0, f.z / h * d * 0.03))
    }

    func wheelCenter(on point: SCNVector3? = nil) {
        let c = point ?? builder.worldSphere.center
        wheelPivot = c
        cameraNode.look(at: c, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        view?.defaultCameraController.target = c
    }

    @discardableResult
    func wheelRewind() -> Bool {
        guard let c = cameraHistory.popLast() else { return false }
        apply(camera: c, animated: false)
        return true
    }

    func wheel(_ w: SteeringWheel.Wedge, dx: CGFloat, dy: CGFloat) {
        switch w {
        case .zoom: wheelZoom(dy)
        case .orbit: wheelOrbit(dx: dx, dy: dy)
        case .pan: wheelPan(dx: dx, dy: dy)
        case .look: wheelLook(dx: dx, dy: dy)
        case .upDown: wheelUpDown(dy)
        case .walk: wheelWalk(dy)
        case .center, .rewind: break
        }
    }
}

/// The steering wheel overlay: press a wedge and drag to navigate; click Center or Rewind.
struct SteeringWheelView: View {
    @ObservedObject var controller: Viewport3DController
    @State private var active: SteeringWheel.Wedge?
    @State private var last: CGPoint = .zero
    @State private var moved = false

    var body: some View {
        let s = SteeringWheel.size
        ZStack {
            Circle().fill(Theme.panel.opacity(0.92)).frame(width: s, height: s)
            Circle().stroke(Color.white.opacity(0.15)).frame(width: SteeringWheel.middleRadius * 2, height: SteeringWheel.middleRadius * 2)
            Circle().fill(Theme.field).frame(width: SteeringWheel.innerRadius * 2, height: SteeringWheel.innerRadius * 2)
            ForEach(SteeringWheel.Wedge.allCases, id: \.self) { w in
                let p = SteeringWheel.labelPoint(w)
                Text(w.rawValue).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active == w ? Theme.accent : Theme.text)
                    .position(p)
            }
            Button { controller.showWheel = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textDim) }
                .buttonStyle(.borderless).position(x: s - 10, y: 10).help("Close the steering wheel")
        }
        .frame(width: s, height: s)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            if active == nil {
                active = SteeringWheel.wedge(at: g.startLocation)
                last = g.startLocation; moved = false
                if active != nil { controller.pushCameraHistory() }
            }
            guard let w = active else { return }
            let dx = g.location.x - last.x, dy = last.y - g.location.y
            last = g.location
            if abs(dx) + abs(dy) > 0 { moved = true; controller.wheel(w, dx: dx, dy: dy) }
        }.onEnded { _ in
            if let w = active, !moved {
                if w == .center { controller.wheelCenter(on: controller.selectionCenter(controller.model?.editor.selection ?? []).map(Scene3DBuilder.world)) }
                if w == .rewind { _ = controller.cameraHistory.popLast(); controller.wheelRewind() }
            }
            active = nil
        })
        .help("Steering wheel: press a wedge and drag (Zoom, Orbit, Pan, Look, Walk, Up/Down); click Center or Rewind")
    }
}
