// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Stylized entourage meshes (people, bicycles) built from simple solids, and their plan symbols.
/// Family-local coordinates: width = X, depth = Y (front faces −Y), height = Z, origin at the footprint centre on the ground.
enum Entourage {
    static func tube(_ p: inout ComponentLibrary.Parts, _ m: String, _ a: Vec3, _ b: Vec3, r: Double, segments: Int = 10) {
        guard r > 1e-6, a.distance(to: b) > 1e-6 else { return }
        let sec = RG.circle(.zero, r, segments: segments)
        p.acc(m) { $0.member(sec, from: a, to: b, smooth: true) }
    }

    /// Standing or walking person (head, torso, hips, arms, legs, shoes). Walking: legs and arms swing about the hips/shoulders.
    static func person(_ p: inout ComponentLibrary.Parts, width W: Double, depth D: Double, height H: Double, walking: Bool) {
        let headR = H * 0.063
        let limb = max(H * 0.028, 8), arm = max(H * 0.022, 6)
        // Arms hang just inside the width; the torso sits inside the arms.
        let armX = max(W / 2 - arm * 1.25, arm)
        let sh = max(armX - arm * 1.3, arm)            // shoulder half-width
        let hip = sh * 0.62
        let zHip = H * 0.52, zSh = H * 0.815
        let stride = walking ? max(0, min(D / 2 - H * 0.075 - 10, H * 0.22)) : 0
        // Legs (thigh + shin as one tapered tube each) and shoes.
        for (side, swing) in [(-1.0, 1.0), (1.0, -1.0)] {
            let foot = Vec3(side * hip * 0.9, -swing * stride, H * 0.035)
            let top = Vec3(side * hip * 0.8, 0, zHip)
            let knee = Vec3((top.x + foot.x) / 2, (top.y + foot.y) / 2 - (walking ? H * 0.02 : 0), H * 0.28)
            tube(&p, "Clothing", top, knee, r: limb * 1.15)
            tube(&p, "Clothing", knee, foot, r: limb)
            p.box("Rubber", foot.x - limb, foot.x + limb, foot.y - H * 0.075, foot.y + H * 0.03, 0, H * 0.045)
        }
        // Hips, torso, neck, head.
        p.ellipsoid("Clothing", Vec3(0, 0, zHip + H * 0.02), hip * 1.35, H * 0.075, H * 0.065)
        p.ellipsoid("Clothing Light", Vec3(0, 0, H * 0.675), sh * 0.92, H * 0.078, H * 0.165)
        tube(&p, "Skin", Vec3(0, 0, H * 0.8), Vec3(0, 0, H * 0.87), r: headR * 0.45)
        p.ellipsoid("Skin", Vec3(0, -headR * 0.1, H - headR * 1.05), headR * 0.85, headR * 0.95, headR * 1.05)
        // Arms (upper arm + forearm) with hands.
        for (side, swing) in [(-1.0, -1.0), (1.0, 1.0)] {
            let s0 = Vec3(side * (armX - arm * 0.4), 0, zSh)
            let hand = Vec3(side * armX, -swing * stride * 0.6, H * 0.45)
            let elbow = Vec3(side * armX, (s0.y + hand.y) / 2 + (walking ? -H * 0.015 : 0), H * 0.63)
            tube(&p, "Clothing Light", s0, elbow, r: arm * 1.2)
            tube(&p, "Skin", elbow, hand, r: arm)
            p.ellipsoid("Skin", hand + Vec3(0, 0, -arm), arm * 1.1, arm * 1.1, arm * 1.6)
        }
    }

    /// Bicycle: two wheels (tyre tori, hubs, spokes), diamond frame, fork, handlebar, saddle, cranks.
    static func bicycle(_ p: inout ComponentLibrary.Parts, width W: Double, depth D: Double, height H: Double) {
        let R = max(min(H * 0.34, D * 0.19), 50)
        let wb = max(D - 2 * R, R)                       // wheelbase (hub to hub)
        let rear = Vec3(0, wb / 2, R), front = Vec3(0, -wb / 2, R)
        let tr = max(R * 0.055, 6)
        // Tyres: circle profile swept round a vertical circle in the Y–Z plane (up = X keeps frames untwisted).
        for c in [rear, front] {
            let ring = (0..<36).map { k -> Vec3 in let a = 2 * Double.pi * Double(k) / 36; return c + Vec3(0, cos(a) * (R - tr * 1.02), sin(a) * (R - tr * 1.02)) }
            let prof = RG.circle(.zero, tr, segments: 8)
            p.acc("Rubber") { SweepMesh.sweep(prof, along: ring, up: Vec3(1, 0, 0), closedPath: true, into: &$0) }
            tube(&p, "Steel", c + Vec3(-40, 0, 0), c + Vec3(40, 0, 0), r: max(R * 0.05, 5))
            for k in 0..<12 {
                let a = 2 * Double.pi * Double(k) / 12
                tube(&p, "Steel", c + Vec3(k % 2 == 0 ? -20 : 20, 0, 0), c + Vec3(0, cos(a) * (R - 2 * tr), sin(a) * (R - 2 * tr)), r: 1.5, segments: 4)
            }
        }
        let t = max(R * 0.045, 8)
        let bb = Vec3(0, wb * 0.06, R * 0.92)                  // bottom bracket
        let seatTop = Vec3(0, wb * 0.2, H * 0.8)
        let headTop = Vec3(0, -wb * 0.36, H * 0.84), headBot = Vec3(0, -wb * 0.4, R * 1.55)
        tube(&p, "Car Paint", bb, seatTop, r: t)                  // seat tube
        tube(&p, "Car Paint", seatTop, headTop, r: t)             // top tube
        tube(&p, "Car Paint", bb, headBot, r: t * 1.15)           // down tube
        tube(&p, "Car Paint", headBot, headTop, r: t * 1.2)       // head tube
        for side in [-1.0, 1.0] {
            tube(&p, "Car Paint", bb + Vec3(side * 25, 0, 0), rear + Vec3(side * 40, 0, 0), r: t * 0.7)         // chain stays
            tube(&p, "Car Paint", seatTop + Vec3(side * 15, 0, -40), rear + Vec3(side * 40, 0, 0), r: t * 0.7) // seat stays
            tube(&p, "Steel", headBot + Vec3(side * 20, 0, 0), front + Vec3(side * 40, 0, 0), r: t * 0.8)       // fork
        }
        // Seat post, saddle, stem, handlebar, cranks and pedals.
        let saddle = seatTop + Vec3(0, 20, H * 0.1)
        tube(&p, "Steel", seatTop, saddle, r: t * 0.7)
        p.ellipsoid("Rubber", saddle + Vec3(0, -40, 20), 70, 130, 25)
        let barC = headTop + Vec3(0, -40, H * 0.12)
        tube(&p, "Steel", headTop, barC, r: t * 0.8)
        let hw = max(W / 2 - 30, 150)
        tube(&p, "Steel", barC + Vec3(-hw, 30, 0), barC + Vec3(hw, 30, 0), r: t * 0.7)
        for side in [-1.0, 1.0] { tube(&p, "Rubber", barC + Vec3(side * hw, 30, 0), barC + Vec3(side * (hw - 110), 30, 0), r: t * 0.95) }
        let crank = R * 0.45
        tube(&p, "Steel", bb + Vec3(-60, 0, 0), bb + Vec3(-60, -crank * 0.6, -crank * 0.8), r: 8)
        tube(&p, "Steel", bb + Vec3(60, 0, 0), bb + Vec3(60, crank * 0.6, crank * 0.8), r: 8)
        p.box("Rubber", -150, -70, -crank * 0.6 - 40, -crank * 0.6 + 40, bb.z - crank * 0.8 - 10, bb.z - crank * 0.8 + 10)
        p.box("Rubber", 70, 150, crank * 0.6 - 40, crank * 0.6 + 40, bb.z + crank * 0.8 - 10, bb.z + crank * 0.8 + 10)
        p.acc("Steel") { $0.extrudeSection(RG.circle(.zero, R * 0.2, segments: 20), origin: bb + Vec3(35, 0, 0), axis: Vec3(1, 0, 0), xAxis: Vec3(0, 1, 0), length: 6) }
    }

    /// Plan symbol of an entourage family (family-local coordinates).
    static func symbol(_ id: String, width W: Double, depth D: Double, height H: Double) -> [ComponentSymbolLine] {
        var out: [ComponentSymbolLine] = []
        func add(_ pts: [Vec2], closed: Bool, outline: Bool = false) { out.append(ComponentSymbolLine(points: pts, closed: closed, outline: outline, hidden: false)) }
        switch id {
        case "bicycle":
            let R = max(min(H * 0.34, D * 0.19), 50), wb = max(D - 2 * R, R)
            for cy in [wb / 2, -wb / 2] { add([Vec2(-20, cy - R), Vec2(20, cy - R), Vec2(20, cy + R), Vec2(-20, cy + R)], closed: true, outline: true) }
            add([Vec2(0, wb / 2), Vec2(0, wb * 0.06), Vec2(0, -wb * 0.4), Vec2(0, -wb / 2)], closed: false)
            let hw = max(W / 2 - 30, 150), by = -wb * 0.36 - 10
            add([Vec2(-hw, by), Vec2(hw, by)], closed: false, outline: true)
            add(ComponentLibrary.ellipse(Vec2(0, wb * 0.2 - 20), 70, 130, segments: 16), closed: true)
        default:
            let arm = max(H * 0.022, 6), headR = H * 0.063
            let sh = max(max(W / 2 - arm * 1.25, arm) - arm * 1.3, arm)
            // Shoulders (ellipse) and head seen from above, nose side −Y; walking adds the forward/back feet.
            add(ComponentLibrary.ellipse(.zero, sh * 1.05, H * 0.08, segments: 28), closed: true, outline: true)
            add(RG.circle(Vec2(0, -headR * 0.1), headR * 0.9, segments: 20), closed: true, outline: true)
            add([Vec2(-headR * 0.25, -headR), Vec2(0, -headR * 1.3), Vec2(headR * 0.25, -headR)], closed: false)
            if id == "person-walking" {
                let stride = max(0, min(D / 2 - H * 0.075 - 10, H * 0.22)), hip = sh * 0.62
                add([Vec2(-hip * 0.9 - 40, -stride - H * 0.075), Vec2(-hip * 0.9 + 40, -stride - H * 0.075), Vec2(-hip * 0.9 + 40, -stride + H * 0.03), Vec2(-hip * 0.9 - 40, -stride + H * 0.03)], closed: true)
                add([Vec2(hip * 0.9 - 40, stride - H * 0.075), Vec2(hip * 0.9 + 40, stride - H * 0.075), Vec2(hip * 0.9 + 40, stride + H * 0.03), Vec2(hip * 0.9 - 40, stride + H * 0.03)], closed: true)
            }
        }
        return out
    }
}
