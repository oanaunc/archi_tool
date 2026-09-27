// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Linear and angular unit display (APP-049), AutoCAD style: LUNITS 1 scientific, 2 decimal, 3 engineering,
/// 4 architectural, 5 fractional with LUPREC; AUNITS 0 decimal degrees, 1 deg/min/sec, 2 grads, 3 radians,
/// 4 surveyor's units with AUPREC. Engineering, architectural and fractional values are in inches (drawings in
/// millimetres, centimetres or metres are converted), feet shown with ' and inches with ".
/// Portable (ArchiCore): the Mac status bar and Units dialog and the Windows Units dialog (units.get) use it.
public enum UnitFormat {
    public enum Linear: Int, CaseIterable { case scientific = 1, decimal = 2, engineering = 3, architectural = 4, fractional = 5
        public var title: String { ["Scientific", "Decimal", "Engineering", "Architectural", "Fractional"][rawValue - 1] }
    }
    public enum Angular: Int, CaseIterable { case degrees = 0, dms = 1, grads = 2, radians = 3, surveyor = 4
        public var title: String { ["Decimal degrees", "Deg/Min/Sec", "Grads", "Radians", "Surveyor's units"][rawValue] }
    }

    public static func linearType(_ doc: ArchiDocument) -> Linear { doc.variable("LUNITS").flatMap(Int.init).flatMap(Linear.init) ?? .decimal }
    public static func linearPrecision(_ doc: ArchiDocument) -> Int { min(max(doc.variable("LUPREC").flatMap(Int.init) ?? 2, 0), 8) }
    public static func angularType(_ doc: ArchiDocument) -> Angular { doc.variable("AUNITS").flatMap(Int.init).flatMap(Angular.init) ?? .degrees }
    public static func angularPrecision(_ doc: ArchiDocument) -> Int { min(max(doc.variable("AUPREC").flatMap(Int.init) ?? 0, 0), 8) }

    public static func linear(_ v: Double, doc: ArchiDocument) -> String { linear(v, units: doc.units, type: linearType(doc), precision: linearPrecision(doc)) }
    public static func angle(_ radians: Double, doc: ArchiDocument) -> String { angle(radians, type: angularType(doc), precision: angularPrecision(doc)) }

    /// Inches in one drawing unit (engineering / architectural / fractional).
    public static func inchesPerUnit(_ u: Units) -> Double { u == .inches ? 1 : (u == .feet ? 12 : u.mm / 25.4) }

    public static func linear(_ v: Double, units: Units, type: Linear, precision p: Int) -> String {
        guard v.isFinite else { return "—" }
        switch type {
        case .scientific: return String(format: "%.\(p)E", v)
        case .decimal: return String(format: "%.\(p)f", v)
        case .engineering:
            let inches = v * inchesPerUnit(units)
            let sign = inches < 0 ? "-" : "", a = abs(inches)
            var ft = (a / 12).rounded(.down)
            var inch = a - ft * 12
            if Double(String(format: "%.\(p)f", inch)) ?? inch >= 12 { ft += 1; inch = 0 }
            return "\(sign)\(Int(ft))'-\(String(format: "%.\(p)f", inch))\""
        case .architectural, .fractional:
            let inches = v * inchesPerUnit(units)
            let sign = inches < 0 ? "-" : "", a = abs(inches)
            let den = 1 << p
            var whole = Int(a.rounded(.down))
            var num = Int(((a - Double(whole)) * Double(den)).rounded())
            if num == den { whole += 1; num = 0 }
            var d = den
            while num > 0 && num % 2 == 0 && d > 1 { num /= 2; d /= 2 }
            let frac = num == 0 ? "" : "\(num)/\(d)"
            if type == .fractional { return sign + (frac.isEmpty ? "\(whole)" : (whole == 0 ? frac : "\(whole) \(frac)")) + "\"" }
            let ft = whole / 12, inch = whole % 12
            let inchText = frac.isEmpty ? "\(inch)" : (inch == 0 ? frac : "\(inch) \(frac)")
            return "\(sign)\(ft)'-\(inchText)\""
        }
    }

    public static func angle(_ r: Double, type: Angular, precision p: Int) -> String {
        let deg = r * 180 / .pi
        switch type {
        case .degrees: return String(format: "%.\(p)f", deg) + "°"
        case .grads: return String(format: "%.\(p)fg", deg * 400 / 360)
        case .radians: return String(format: "%.\(p)fr", r)
        case .dms:
            var a = abs(deg)
            var d = Int(a.rounded(.down)); a = (a - Double(d)) * 60
            var m = Int(a.rounded(.down)); var s = (a - Double(m)) * 60
            if s >= 59.9995 { s = 0; m += 1 }; if m >= 60 { m = 0; d += 1 }
            let sign = deg < 0 ? "-" : ""
            switch p { case 0: return "\(sign)\(d + (m >= 30 ? 1 : 0))d"; case 1, 2: return "\(sign)\(d)d\(m)'"; default: return "\(sign)\(d)d\(m)'\(String(format: "%.\(max(0, p - 4))f", s))\"" }
        case .surveyor:
            // Bearing from north or south towards east or west (0° = east, counter-clockwise).
            var b = (90 - deg).truncatingRemainder(dividingBy: 360); if b < 0 { b += 360 }
            var ns = "N", ew = "E", ang = b
            if b > 270 { ns = "N"; ew = "W"; ang = 360 - b }
            else if b > 180 { ns = "S"; ew = "W"; ang = b - 180 }
            else if b > 90 { ns = "S"; ew = "E"; ang = 180 - b }
            if abs(ang) < 1e-9 { return ns == "N" ? "N" : "S" }
            if abs(ang - 90) < 1e-9 { return ew }
            return "\(ns) \(angle(ang * .pi / 180, type: .dms, precision: max(p, 1))) \(ew)"
        }
    }
}
