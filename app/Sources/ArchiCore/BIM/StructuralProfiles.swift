// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Parametric structural cross-sections for beams, columns, braces and truss members.
/// Named catalogue sizes (IPE, HEA, HEB, UPN, CHS/RHS/SHS, L, T) and parametric forms:
/// "I 300x150x7x10" (h×b×tw×tf), "H 200x200x9x15", "C 200x75x8x11", "L 100x100x10", "L 150x90x10", "T 100x100x10",
/// "RHS 200x100x8", "SHS 100x5", "CHS 168x6", "RECT 200x400", "ROUND 300" (dimensions in millimetres).
public struct StructuralSection: Hashable {
    public enum Shape: String, CaseIterable { case i, c, l, t, rhs, chs, rect, round }
    public var shape: Shape
    /// Overall depth (h, along the local Y axis / "up" for beams) and width (b, along local X).
    public var h: Double; public var b: Double
    /// Web and flange thickness (hollow sections: wall thickness in `tw`).
    public var tw: Double; public var tf: Double
    public var name: String

    /// Outline centred on the section's bounding box centre (CCW) and holes (CW) for hollow sections, in millimetres.
    public func outline(segments: Int = 24) -> (outer: [Vec2], holes: [[Vec2]]) {
        let hh = h / 2, hb = b / 2
        func V(_ x: Double, _ y: Double) -> Vec2 { Vec2(x, y) }
        switch shape {
        case .i:
            let w = tw / 2
            return ([V(-hb, -hh), V(hb, -hh), V(hb, -hh + tf), V(w, -hh + tf), V(w, hh - tf), V(hb, hh - tf), V(hb, hh), V(-hb, hh),
                     V(-hb, hh - tf), V(-w, hh - tf), V(-w, -hh + tf), V(-hb, -hh + tf)], [])
        case .c:
            // Channel: web on the left (−x), flanges pointing +x.
            return ([V(-hb, -hh), V(hb, -hh), V(hb, -hh + tf), V(-hb + tw, -hh + tf), V(-hb + tw, hh - tf), V(hb, hh - tf), V(hb, hh), V(-hb, hh)], [])
        case .l:
            // Angle: legs along −x edge and −y edge.
            return ([V(-hb, -hh), V(hb, -hh), V(hb, -hh + tf), V(-hb + tw, -hh + tf), V(-hb + tw, hh), V(-hb, hh)], [])
        case .t:
            // Tee: flange on top.
            let w = tw / 2
            return ([V(-w, -hh), V(w, -hh), V(w, hh - tf), V(hb, hh - tf), V(hb, hh), V(-hb, hh), V(-hb, hh - tf), V(-w, hh - tf)], [])
        case .rhs:
            let o = [V(-hb, -hh), V(hb, -hh), V(hb, hh), V(-hb, hh)]
            let t = min(tw, min(hb, hh) * 0.9)
            return (o, [[V(-hb + t, -hh + t), V(-hb + t, hh - t), V(hb - t, hh - t), V(hb - t, -hh + t)]])
        case .chs:
            let r = b / 2, t = min(tw, r * 0.9)
            let o = (0..<segments).map { Vec2.polar(r, 2 * Double.pi * Double($0) / Double(segments)) }
            return (o, [(0..<segments).reversed().map { Vec2.polar(r - t, 2 * Double.pi * Double($0) / Double(segments)) }])
        case .rect:
            return ([V(-hb, -hh), V(hb, -hh), V(hb, hh), V(-hb, hh)], [])
        case .round:
            return ((0..<segments).map { Vec2.polar(b / 2, 2 * Double.pi * Double($0) / Double(segments)) }, [])
        }
    }

    /// Cross-section area (mm²).
    public var area: Double {
        let o = outline(segments: 64)
        return abs(GeometryOps.signedArea(o.outer)) - o.holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }
    }
}

public enum StructuralProfiles {
    /// Catalogue: European sections (EN 10365 dimensions: h, b, tw, tf in mm).
    public static let catalogue: [String: (StructuralSection.Shape, Double, Double, Double, Double)] = [
        "IPE100": (.i, 100, 55, 4.1, 5.7), "IPE120": (.i, 120, 64, 4.4, 6.3), "IPE140": (.i, 140, 73, 4.7, 6.9), "IPE160": (.i, 160, 82, 5.0, 7.4),
        "IPE180": (.i, 180, 91, 5.3, 8.0), "IPE200": (.i, 200, 100, 5.6, 8.5), "IPE220": (.i, 220, 110, 5.9, 9.2), "IPE240": (.i, 240, 120, 6.2, 9.8),
        "IPE270": (.i, 270, 135, 6.6, 10.2), "IPE300": (.i, 300, 150, 7.1, 10.7), "IPE330": (.i, 330, 160, 7.5, 11.5), "IPE360": (.i, 360, 170, 8.0, 12.7),
        "IPE400": (.i, 400, 180, 8.6, 13.5), "IPE450": (.i, 450, 190, 9.4, 14.6), "IPE500": (.i, 500, 200, 10.2, 16.0), "IPE600": (.i, 600, 220, 12.0, 19.0),
        "HEA100": (.i, 96, 100, 5.0, 8.0), "HEA120": (.i, 114, 120, 5.0, 8.0), "HEA140": (.i, 133, 140, 5.5, 8.5), "HEA160": (.i, 152, 160, 6.0, 9.0),
        "HEA180": (.i, 171, 180, 6.0, 9.5), "HEA200": (.i, 190, 200, 6.5, 10.0), "HEA220": (.i, 210, 220, 7.0, 11.0), "HEA240": (.i, 230, 240, 7.5, 12.0),
        "HEA260": (.i, 250, 260, 7.5, 12.5), "HEA280": (.i, 270, 280, 8.0, 13.0), "HEA300": (.i, 290, 300, 8.5, 14.0), "HEA400": (.i, 390, 300, 11.0, 19.0),
        "HEB100": (.i, 100, 100, 6.0, 10.0), "HEB120": (.i, 120, 120, 6.5, 11.0), "HEB140": (.i, 140, 140, 7.0, 12.0), "HEB160": (.i, 160, 160, 8.0, 13.0),
        "HEB180": (.i, 180, 180, 8.5, 14.0), "HEB200": (.i, 200, 200, 9.0, 15.0), "HEB220": (.i, 220, 220, 9.5, 16.0), "HEB240": (.i, 240, 240, 10.0, 17.0),
        "HEB260": (.i, 260, 260, 10.0, 17.5), "HEB280": (.i, 280, 280, 10.5, 18.0), "HEB300": (.i, 300, 300, 11.0, 19.0), "HEB400": (.i, 400, 300, 13.5, 24.0),
        "UPN80": (.c, 80, 45, 6.0, 8.0), "UPN100": (.c, 100, 50, 6.0, 8.5), "UPN120": (.c, 120, 55, 7.0, 9.0), "UPN140": (.c, 140, 60, 7.0, 10.0),
        "UPN160": (.c, 160, 65, 7.5, 10.5), "UPN180": (.c, 180, 70, 8.0, 11.0), "UPN200": (.c, 200, 75, 8.5, 11.5), "UPN240": (.c, 240, 85, 9.5, 13.0),
        "UPN300": (.c, 300, 100, 10.0, 16.0),
    ]

    /// Section families offered on the command line.
    public static let families = ["I", "H", "C", "L", "T", "RHS", "SHS", "CHS", "RECT", "ROUND", "IPE", "HEA", "HEB", "UPN"]

    /// Parses a profile designation; nil when it is not understood.
    public static func section(_ spec0: String?) -> StructuralSection? {
        guard let spec0 = spec0 else { return nil }
        let spec = spec0.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "×", with: "X").replacingOccurrences(of: "*", with: "X")
        guard !spec.isEmpty else { return nil }
        if let c = catalogue[spec] { return StructuralSection(shape: c.0, h: c.1, b: c.2, tw: c.3, tf: c.4, name: spec) }
        // Prefix letters then numbers separated by X.
        let letters = String(spec.prefix { $0.isLetter })
        let nums = spec.dropFirst(letters.count).split(separator: "X").compactMap { Double($0) }
        guard !nums.isEmpty, nums.allSatisfy({ $0 > 0 }) else { return nil }
        func n(_ i: Int, _ def: Double) -> Double { i < nums.count ? nums[i] : def }
        let name = spec0.trimmingCharacters(in: .whitespaces)
        var s: StructuralSection
        switch letters {
        case "I", "W", "H", "HE":
            let h = n(0, 300), b = n(1, letters == "H" || letters == "HE" ? h : h / 2)
            s = StructuralSection(shape: .i, h: h, b: b, tw: n(2, max(h / 40, 4)), tf: n(3, max(h / 25, 6)), name: name)
        case "C", "U", "UPN", "PFC":
            let h = n(0, 200), b = n(1, h * 0.375)
            s = StructuralSection(shape: .c, h: h, b: b, tw: n(2, max(h / 25, 5)), tf: n(3, max(h / 18, 7)), name: name)
        case "L":
            // L a×b×t or L a×t (equal legs).
            if nums.count == 2 { s = StructuralSection(shape: .l, h: nums[0], b: nums[0], tw: nums[1], tf: nums[1], name: name) }
            else { s = StructuralSection(shape: .l, h: n(0, 100), b: n(1, n(0, 100)), tw: n(2, 10), tf: n(2, 10), name: name) }
        case "T":
            let h = n(0, 100)
            s = StructuralSection(shape: .t, h: h, b: n(1, h), tw: n(2, max(h / 10, 5)), tf: n(3, n(2, max(h / 10, 5))), name: name)
        case "RHS":
            s = StructuralSection(shape: .rhs, h: n(0, 200), b: n(1, n(0, 200) / 2), tw: n(2, 6), tf: n(2, 6), name: name)
        case "SHS":
            // SHS a×t or a×a×t.
            let t = nums.count >= 3 ? nums[2] : n(1, 5)
            s = StructuralSection(shape: .rhs, h: n(0, 100), b: n(0, 100), tw: t, tf: t, name: name)
        case "CHS", "TUBE", "PIPE":
            let d = n(0, 168)
            s = StructuralSection(shape: .chs, h: d, b: d, tw: n(1, max(d / 25, 3)), tf: 0, name: name)
        case "RECT", "R", "RECTANGLE":
            s = StructuralSection(shape: .rect, h: n(1, n(0, 200)), b: n(0, 200), tw: 0, tf: 0, name: name)
        case "ROUND", "CIRC", "CIRCLE", "O":
            let d = n(0, 300)
            s = StructuralSection(shape: .round, h: d, b: d, tw: 0, tf: 0, name: name)
        default: return nil
        }
        // Reject thicknesses that would not leave a section.
        switch s.shape {
        case .i, .c, .t: guard s.tw < s.b, 2 * s.tf < s.h || (s.shape == .t && s.tf < s.h) else { return nil }
        case .l: guard s.tw < s.b, s.tf < s.h else { return nil }
        case .rhs: guard 2 * s.tw < min(s.b, s.h) else { return nil }
        case .chs: guard 2 * s.tw < s.b else { return nil }
        default: break
        }
        return s
    }

    /// Outline in drawing units (`unit` = drawing units per millimetre).
    static func outline(_ s: StructuralSection, unit u: Double) -> (outer: [Vec2], holes: [[Vec2]]) {
        let o = s.outline()
        return (o.outer.map { $0 * u }, o.holes.map { $0.map { $0 * u } })
    }
}
