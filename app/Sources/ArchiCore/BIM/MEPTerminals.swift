// Oanarina Archi Tool — GPL-3.0-or-later
// MEP equipment and terminals (BIM-107): supply / return air diffusers, radiators and data outlets, with connectors on
// their systems (so they join connected MEP networks) and plan symbols drawn in their system colour.
import Foundation

extension ComponentLibrary {
    static let terminalIDs: Set<String> = ["air-supply", "air-return", "radiator", "data-outlet"]

    static func terminalParts(_ id: String, _ p: inout Parts, W: Double, D: Double, H: Double) {
        let x0 = -W / 2, x1 = W / 2, y0 = -D / 2, y1 = D / 2
        switch id {
        case "air-supply", "air-return":
            // Face plate flush with the ceiling (local z = 0), louvre rings / slots, and a neck up to the duct.
            p.box("Aluminium", x0, x1, y0, y1, 8, 33)
            if id == "air-supply" {
                for k in 1...3 {
                    let f = 0.5 - Double(k) * 0.11
                    p.box("Steel", -W * f, W * f, -D * f, D * f, 0, 8)
                }
            } else {
                var x = x0 + 40
                while x < x1 - 40 { p.box("Steel", x, x + 12, y0 + 30, y1 - 30, 0, 8); x += 50 }
            }
            let n = min(W, D) * 0.4
            p.box("Steel", -n / 2, n / 2, -n / 2, n / 2, 33, max(H, 40))
        case "radiator":
            // Panel radiator: vertical columns between top and bottom headers, on two wall brackets.
            let cols = max(3, Int(W / 60))
            let cw = W / Double(cols)
            for c in 0..<cols { p.box("Steel", x0 + Double(c) * cw + 4, x0 + Double(c + 1) * cw - 4, y0, y1, 40, H - 40) }
            p.box("Steel", x0, x1, y0 + D * 0.25, y1 - D * 0.25, 0, 40)
            p.box("Steel", x0, x1, y0 + D * 0.25, y1 - D * 0.25, H - 40, H)
        case "data-outlet":
            p.box("Laminate", x0, x1, y1 - 12, y1, 0, H)
            p.box("Rubber", -W * 0.2, W * 0.2, y1 - 14, y1 - 12, H * 0.3, H * 0.6)
        default: break
        }
    }

    static func terminalSymbol(_ id: String, W: Double, D: Double) -> [ComponentSymbolLine] {
        var out: [ComponentSymbolLine] = []
        func add(_ pts: [Vec2], closed: Bool = false, outline: Bool = true) { out.append(ComponentSymbolLine(points: pts, closed: closed, outline: outline, hidden: false)) }
        let x0 = -W / 2, x1 = W / 2, y0 = -D / 2, y1 = D / 2
        switch id {
        case "air-supply":
            // Square diffuser: outline, inner square and diagonals (four-way throw).
            add([Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)], closed: true)
            add([Vec2(x0 * 0.5, y0 * 0.5), Vec2(x1 * 0.5, y0 * 0.5), Vec2(x1 * 0.5, y1 * 0.5), Vec2(x0 * 0.5, y1 * 0.5)], closed: true, outline: false)
            add([Vec2(x0, y0), Vec2(x1, y1)], outline: false); add([Vec2(x0, y1), Vec2(x1, y0)], outline: false)
        case "air-return":
            // Return grille: outline and parallel slats.
            add([Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)], closed: true)
            for k in 1..<6 { let x = x0 + W * Double(k) / 6; add([Vec2(x, y0), Vec2(x, y1)], outline: false) }
        case "radiator":
            add([Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)], closed: true)
            let cols = max(3, Int(W / 120))
            for c in 1..<cols { let x = x0 + W * Double(c) / Double(cols); add([Vec2(x, y0), Vec2(x, y1)], outline: false) }
        case "data-outlet":
            // Triangle (communications outlet) tied to the wall.
            let r = max(min(W, 400) * 0.5, 60)
            add([Vec2(-r, -r * 0.6), Vec2(r, -r * 0.6), Vec2(0, r)], closed: true)
            add([Vec2(0, r), Vec2(0, D / 2)], outline: false)
        default: break
        }
        return out
    }

    static func terminalConnectors(_ id: String, W: Double, D: Double, H: Double) -> [MEPConnector] {
        switch id {
        case "air-supply": return [MEPConnector("SA", Vec3(0, 0, H), min(W, D) * 0.4)]
        case "air-return": return [MEPConnector("RA", Vec3(0, 0, H), min(W, D) * 0.4)]
        case "radiator": return [MEPConnector("HWS", Vec3(-W / 2 + 30, 0, 0), 15), MEPConnector("HWR", Vec3(W / 2 - 30, 0, 0), 15)]
        case "data-outlet": return [MEPConnector("DATA", Vec3(0, 0, 0), 0)]
        default: return []
        }
    }

    /// Display colour of a fixture by its system: the element's "system" property, else the family's single system.
    public static func systemDisplayColor(_ f: ComponentFamily, _ g: ComponentGeom, props: [String: String]) -> RGBA? {
        if let s = props["system"], let c = RunFamilies.systemColor(s) { return c }
        let systems = Set(connectors(f, size: g.size).map(\.system))
        guard terminalIDs.contains(f.id), let first = systems.first else { return nil }
        return RunFamilies.systemColor(systems.count == 1 ? first : (systems.contains("HWS") ? "HWS" : first))
    }
}
