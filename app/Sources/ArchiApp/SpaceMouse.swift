// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import IOKit
import IOKit.hid
import ArchiCore

/// 3Dconnexion SpaceMouse / multi-axis controller support (VIS-024) through IOKit HID: six axes (translation X Y Z,
/// rotation Rx Ry Rz) drive the 3D camera, in Object mode (orbit the model) or Fly mode (move the eye); button 1 fits
/// the view, button 2 switches the mode. Works without the vendor driver (generic desktop "multi-axis controller").
@MainActor
final class SpaceMouse {
    static let shared = SpaceMouse()
    enum Mode: String, CaseIterable { case object = "Object", fly = "Fly" }

    struct Config: Equatable {
        var sensitivity = 1.0
        var deadzone = 0.06
        var mode: Mode = .object
        var invertZoom = false
        var dominant = false
    }

    /// Camera motion for one tick: pan (right, up, forward as fractions of the view distance) and turns (radians).
    struct Motion: Equatable { var right = 0.0, up = 0.0, forward = 0.0, yaw = 0.0, pitch = 0.0
        var isZero: Bool { right == 0 && up == 0 && forward == 0 && yaw == 0 && pitch == 0 }
    }

    /// Raw axis values (±350 typical full deflection) → motion for `dt` seconds. HID axes: X right, Y towards the
    /// user, Z down; Rx tilt, Ry roll (unused), Rz spin.
    static func motion(axes a: [Double], config c: Config, dt: Double) -> Motion {
        guard a.count >= 6 else { return Motion() }
        var v = a.map { x -> Double in
            let n = max(-1, min(1, x / 350))
            let dz = c.deadzone
            guard abs(n) > dz else { return 0 }
            let s = (abs(n) - dz) / (1 - dz)
            return (n < 0 ? -1 : 1) * s * s   // quadratic response: fine control near the centre
        }
        if c.dominant, let i = v.indices.max(by: { abs(v[$0]) < abs(v[$1]) }) { v = v.indices.map { $0 == i ? v[i] : 0 } }
        let k = c.sensitivity * dt
        var m = Motion()
        m.right = v[0] * 1.2 * k
        m.forward = (c.invertZoom ? v[1] : -v[1]) * 1.5 * k
        m.up = -v[2] * 1.2 * k
        m.pitch = -v[3] * 1.6 * k
        m.yaw = -v[5] * 1.6 * k
        return m
    }

    /// Moves a camera (model mm, Z up). Object mode orbits and zooms about the target; Fly mode moves the eye.
    static func apply(_ m: Motion, to cam: Camera, mode: Mode) -> Camera {
        guard !m.isZero else { return cam }
        var eye = cam.eye, target = cam.target
        var fwd = target - eye
        let dist = max(fwd.length, 1)
        fwd = fwd / dist
        var right = fwd.cross(Vec3(0, 0, 1))
        if right.length < 1e-6 { right = Vec3(1, 0, 0) }
        right = right.normalized
        let up = right.cross(fwd).normalized
        func rotZ(_ v: Vec3, _ a: Double) -> Vec3 { Vec3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), v.z) }
        func rotAxis(_ v: Vec3, _ k: Vec3, _ a: Double) -> Vec3 { v * cos(a) + k.cross(v) * sin(a) + k * (k.dot(v) * (1 - cos(a))) }
        func clampPitch(_ d: Vec3) -> Bool { abs(d.normalized.z) < 0.985 }
        switch mode {
        case .object:
            // Pan and zoom scale with the distance to the target.
            let pan = right * (m.right * dist) + up * (m.up * dist)
            eye = eye + pan; target = target + pan
            let newDist = max(dist * (1 - m.forward), 50)
            var off = eye - target
            off = off.normalized * newDist
            off = rotZ(off, m.yaw)
            let o2 = rotAxis(off, right, m.pitch)
            if clampPitch(o2) { off = o2 }
            eye = target + off
        case .fly:
            let move = right * (m.right * dist) + up * (m.up * dist) + fwd * (m.forward * dist)
            eye = eye + move
            var d = rotZ(target - (eye - move), m.yaw)
            let d2 = rotAxis(d, right, m.pitch)
            if clampPitch(d2) { d = d2 }
            target = eye + d.normalized * dist
        }
        return Camera(eye: eye, target: target, fov: cam.fov, orthographic: cam.orthographic)
    }

    // MARK: Device

    var config: Config {
        get {
            let d = UserDefaults.standard
            var c = Config()
            if d.object(forKey: "spaceMouse.sensitivity") != nil { c.sensitivity = d.double(forKey: "spaceMouse.sensitivity") }
            if let m = d.string(forKey: "spaceMouse.mode"), let mm = Mode(rawValue: m) { c.mode = mm }
            c.invertZoom = d.bool(forKey: "spaceMouse.invertZoom"); c.dominant = d.bool(forKey: "spaceMouse.dominant")
            return c
        }
        set {
            let d = UserDefaults.standard
            d.set(newValue.sensitivity, forKey: "spaceMouse.sensitivity"); d.set(newValue.mode.rawValue, forKey: "spaceMouse.mode")
            d.set(newValue.invertZoom, forKey: "spaceMouse.invertZoom"); d.set(newValue.dominant, forKey: "spaceMouse.dominant")
        }
    }
    static var enabledPreference: Bool {
        get { UserDefaults.standard.object(forKey: "spaceMouse.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "spaceMouse.enabled") }
    }

    private var manager: IOHIDManager?
    private var timer: Timer?
    private(set) var axes = [Double](repeating: 0, count: 6)
    private(set) var devices: [String] = []
    private var lastTick = Date()
    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController],
            [kIOHIDVendorIDKey: 0x256F],                                                            // 3Dconnexion
            [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController],   // Logitech-made 3Dconnexion
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, match as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            guard let ctx else { return }
            let me = Unmanaged<SpaceMouse>.fromOpaque(ctx).takeUnretainedValue()
            let el = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
            let v = IOHIDValueGetIntegerValue(value)
            MainActor.assumeIsolated { me.handle(page: page, usage: usage, value: v) }
        }, ctx)
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, dev in
            guard let ctx else { return }
            let me = Unmanaged<SpaceMouse>.fromOpaque(ctx).takeUnretainedValue()
            let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "Multi-axis controller"
            MainActor.assumeIsolated { if !me.devices.contains(name) { me.devices.append(name) } }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { SpaceMouse.shared.tick() } }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let m = manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil; devices = []; axes = Array(repeating: 0, count: 6)
    }

    /// Axis and button values from the device (generic desktop X…Rz = 0x30…0x35, buttons page 9).
    func handle(page: UInt32, usage: UInt32, value: Int) {
        if page == UInt32(kHIDPage_GenericDesktop), usage >= 0x30, usage <= 0x35 { axes[Int(usage - 0x30)] = Double(value) }
        else if page == UInt32(kHIDPage_Button), value != 0 {
            if usage == 1 { Viewport3DController.active?.model?.editor.host?.perform(.zoomExtents, editor: Viewport3DController.active!.model!.editor) }
            if usage == 2 { var c = config; c.mode = c.mode == .object ? .fly : .object; config = c }
        }
    }

    private func tick() {
        let now = Date(), dt = min(now.timeIntervalSince(lastTick), 0.1)
        lastTick = now
        let m = SpaceMouse.motion(axes: axes, config: config, dt: dt)
        guard !m.isZero, let c = Viewport3DController.active else { return }
        c.apply(camera: SpaceMouse.apply(m, to: c.currentCamera, mode: config.mode), animated: false)
    }
}
