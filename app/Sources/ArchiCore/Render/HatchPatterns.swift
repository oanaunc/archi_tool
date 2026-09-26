// Oanarina Archi Tool — GPL-3.0-or-later
// Pattern definitions follow the AutoCAD .pat line-family model (angle, origin, delta, dashes);
// values are expressed in millimetres (acadiso-style). AR-* patterns are real-world size.
import Foundation

public enum HatchPatterns {
    /// One family of parallel dashed lines. `delta.x` shifts the dash phase along the line for each
    /// successive line, `delta.y` is the perpendicular spacing. Dashes: + dash, − gap, 0 dot.
    struct Family {
        var angle: Double; var origin: Vec2; var delta: Vec2; var dashes: [Double]
        init(_ angle: Double, _ ox: Double, _ oy: Double, _ dx: Double, _ dy: Double, _ dashes: [Double] = []) {
            self.angle = angle; origin = Vec2(ox, oy); delta = Vec2(dx, dy); self.dashes = dashes
        }
    }

    static let i = 25.4 // inch-based classic definitions scaled to mm

    static let families: [String: [Family]] = {
        var p: [String: [Family]] = [:]
        p["LINE"] = [Family(0, 0, 0, 0, 3.175)]
        p["ANSI31"] = [Family(45, 0, 0, 0, 3.175)]
        p["ANSI32"] = [Family(45, 0, 0, 0, 9.525), Family(45, 4.490128, 0, 0, 9.525)]
        p["ANSI37"] = [Family(45, 0, 0, 0, 3.175), Family(135, 0, 0, 0, 3.175)]
        p["NET"] = [Family(0, 0, 0, 0, 3.175), Family(90, 0, 0, 0, 3.175)]
        p["DOTS"] = [Family(0, 0, 0, 0.03125 * i, 0.0625 * i, [0, -0.0625 * i])]
        p["CROSS"] = [Family(0, 0, 0, 0.25 * i, 0.25 * i, [0.125 * i, -0.375 * i]),
                      Family(90, 0.0625 * i, -0.0625 * i, 0.25 * i, 0.25 * i, [0.125 * i, -0.375 * i])]
        p["HONEY"] = [Family(0, 0, 0, 0.1875 * i, 0.108253 * i, [0.125 * i, -0.25 * i]),
                      Family(120, 0, 0, 0.1875 * i, 0.108253 * i, [0.125 * i, -0.25 * i]),
                      Family(60, 0.125 * i, 0, 0.1875 * i, 0.108253 * i, [0.125 * i, -0.25 * i])]
        p["BRICK"] = [Family(0, 0, 0, 0, 0.25 * i), Family(90, 0, 0, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i])]
        p["AR-BRSTD"] = [Family(0, 0, 0, 0, 67.7), Family(90, 0, 0, 67.7, 101.6, [67.7, -67.7])]
        p["GRASS"] = [Family(90, 0, 0, 0.707107 * i, 0.707107 * i, [0.1875 * i, -1.226713 * i]),
                      Family(45, 0, 0, 0, 1 * i, [0.1875 * i, -0.8125 * i]),
                      Family(135, 0, 0, 0, 1 * i, [0.1875 * i, -0.8125 * i])]
        p["EARTH"] = [Family(0, 0, 0, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i]),
                      Family(0, 0, 0.09375 * i, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i]),
                      Family(0, 0, 0.1875 * i, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i]),
                      Family(90, 0.03125 * i, 0.21875 * i, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i]),
                      Family(90, 0.125 * i, 0.21875 * i, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i]),
                      Family(90, 0.21875 * i, 0.21875 * i, 0.25 * i, 0.25 * i, [0.25 * i, -0.25 * i])]
        // Concrete: scattered aggregate strokes (small triangles) plus sand dots. Real-world mm.
        p["AR-CONC"] = [Family(50, 0, 0, 104.9, -149.8, [19.05, -209.55]),
                        Family(355, 0, 0, -51.8, 187.3, [15.24, -167.6]),
                        Family(100.4, 18.9, -1.4, 178.9, 170.4, [16.2, -178.4]),
                        Family(46.2, 0, 50.8, 158.5, -226.2, [28.6, -314.3]),
                        Family(96.6, 28.3, 48.5, 269.0, 255.8, [24.3, -267.1]),
                        Family(351.2, 0, 50.8, 196.9, 224.3, [22.9, -251.5]),
                        Family(21, 25.4, 38.1, 104.9, -149.8, [19.05, -209.55]),
                        Family(326, 25.4, 38.1, -51.8, 187.3, [15.24, -167.6]),
                        Family(71.4, 38.8, 29.3, 178.9, 170.4, [16.2, -178.4]),
                        Family(37.5, 0, 0, 22.7, 40.6, [0, -52.8, 0, -40.1, 0, -47.9]),
                        Family(7.5, 0, 0, 40.8, 53.8, [0, -39.6, 0, -58.3, 0, -26.8]),
                        Family(-32.5, -56.1, 0, 43.4, 56.1, [0, -48.1, 0, -30.9, 0, -44.2]),
                        Family(-42.5, -76.2, 0, 36.2, 44.4, [0, -35.5, 0, -61.0, 0, -28.2])]
        // Sand: dense scattered dots. Real-world mm.
        p["AR-SAND"] = [Family(37.5, 0, 0, 5.7, 10.2, [0, -13.2, 0, -10.0, 0, -12.0]),
                        Family(7.5, 0, 0, 10.2, 13.5, [0, -9.9, 0, -14.6, 0, -6.7]),
                        Family(-32.5, -14.0, 0, 10.8, 14.0, [0, -12.0, 0, -7.7, 0, -11.1]),
                        Family(-42.5, -19.1, 0, 9.0, 11.1, [0, -8.9, 0, -15.2, 0, -7.1])]
        // Gravel: irregular stone outlines built from short angled strokes. Real-world mm.
        p["GRAVEL"] = [Family(228.0, 18.3, 25.4, 305.5, -25.4, [9.5, -330.4]),
                       Family(184.2, 16.0, 16.0, 333.7, 25.4, [5.8, -306.7]),
                       Family(132.5, 10.6, 16.3, 297.9, -25.4, [9.0, -331.3]),
                       Family(267.3, 17.3, 41.6, -24.5, 17.3, [13.4, -330.9]),
                       Family(292.8, 0, 32.3, 107.2, 21.5, [10.2, -86.7]),
                       Family(357.1, 3.1, 25.9, 323.5, 20.6, [18.8, -313.6]),
                       Family(37.9, 21.9, 25.7, 33.4, 29.0, [11.2, -122.3]),
                       Family(72.9, 30.7, 32.5, 11.3, 28.2, [12.0, -106.6]),
                       Family(121.0, 33.9, 44.3, -34.6, 23.9, [11.4, -104.3]),
                       Family(175.2, 28.1, 53.9, 27.8, 12.2, [13.0, -104.4])]
        // Wood end grain / timber: long lines with irregular breaks. Real-world mm.
        p["WOOD"] = [Family(0, 0, 0, 37.0, 9.0, [120, -8, 60, -14, 200, -6]),
                     Family(0, 0, 4.5, 71.0, 18.0, [40, -25, 160, -10])]
        // More of the standard acad(iso).pat library.
        p["ANSI33"] = [Family(45, 0, 0, 0, 0.25 * i), Family(45, 0.176776695 * i, 0, 0, 0.25 * i, [0.125 * i, -0.0625 * i])]
        p["ANSI34"] = [Family(45, 0, 0, 0, 0.75 * i), Family(45, 0.176776695 * i, 0, 0, 0.75 * i),
                       Family(45, 0.353553391 * i, 0, 0, 0.75 * i), Family(45, 0.530330086 * i, 0, 0, 0.75 * i)]
        p["ANSI35"] = [Family(45, 0, 0, 0, 0.25 * i), Family(45, 0.176776695 * i, 0, 0, 0.25 * i, [0.3125 * i, -0.0625 * i, 0, -0.0625 * i])]
        p["ANSI36"] = [Family(45, 0, 0, 0.21875 * i, 0.125 * i, [0.3125 * i, -0.0625 * i, 0, -0.0625 * i])]
        p["ANSI38"] = [Family(45, 0, 0, 0, 0.125 * i), Family(135, 0, 0, 0.25 * i, 0.125 * i, [0.3125 * i, -0.1875 * i])]
        p["SQUARE"] = [Family(0, 0, 0, 0, 0.125 * i, [0.125 * i, -0.125 * i]), Family(90, 0, 0, 0, 0.125 * i, [0.125 * i, -0.125 * i])]
        p["ZIGZAG"] = [Family(0, 0, 0, 0.125 * i, 0.125 * i, [0.125 * i, -0.125 * i]), Family(90, 0.125 * i, 0, 0.125 * i, 0.125 * i, [0.125 * i, -0.125 * i])]
        p["AR-B816"] = [Family(0, 0, 0, 0, 203.2), Family(90, 0, 0, 203.2, 203.2, [203.2, -203.2])]
        p["AR-HBONE"] = [Family(45, 0, 0, 101.6, 101.6, [304.8, -101.6]), Family(135, 71.84, 71.84, 101.6, -101.6, [304.8, -101.6])]
        for (k, v) in libraryFamilies where p[k] == nil { p[k] = v }
        return p
    }()

    /// The rest of the standard acad.pat / acadiso.pat names (ANSI, AR-, ISO 128 line hatches, GOST and the classic
    /// drafting patterns), defined clean-room from their published appearance (not copied from Autodesk files).
    static let libraryFamilies: [String: [Family]] = {
        var p: [String: [Family]] = [:]
        let h3 = 0.866025403784 // √3 / 2
        p["ANGLE"] = [Family(0, 0, 0, 0, 0.275 * i, [0.2 * i, -0.075 * i]), Family(90, 0, 0, 0, 0.275 * i, [0.2 * i, -0.075 * i])]
        p["BOX"] = [Family(0, 0, 0, 0, 0.5 * i, [0.25 * i, -0.25 * i]), Family(0, 0, 0.25 * i, 0, 0.5 * i, [0.25 * i, -0.25 * i]),
                    Family(90, 0, 0, 0, 0.5 * i, [0.25 * i, -0.25 * i]), Family(90, 0.25 * i, 0, 0, 0.5 * i, [0.25 * i, -0.25 * i]),
                    Family(0, 0.0625 * i, 0.0625 * i, 0, 0.5 * i, [0.125 * i, -0.375 * i]), Family(0, 0.0625 * i, 0.1875 * i, 0, 0.5 * i, [0.125 * i, -0.375 * i]),
                    Family(90, 0.0625 * i, 0.0625 * i, 0, 0.5 * i, [0.125 * i, -0.375 * i]), Family(90, 0.1875 * i, 0.0625 * i, 0, 0.5 * i, [0.125 * i, -0.375 * i])]
        p["BRASS"] = [Family(0, 0, 0, 0, 0.25 * i), Family(0, 0, 0.125 * i, 0, 0.25 * i, [0.125 * i, -0.0625 * i])]
        p["BRSTONE"] = [Family(0, 0, 0, 0, 0.33 * i), Family(90, 0, 0, 0.33 * i, 0.45 * i, [0.33 * i, -0.33 * i]),
                        Family(0, 0.1 * i, 0.11 * i, 0.45 * i, 0.33 * i, [0.25 * i, -0.65 * i]), Family(0, 0.1 * i, 0.22 * i, 0.45 * i, 0.33 * i, [0.25 * i, -0.65 * i])]
        p["CLAY"] = [Family(0, 0, 0, 0, 0.1875 * i), Family(0, 0, 0.03125 * i, 0, 0.1875 * i), Family(0, 0, 0.0625 * i, 0, 0.1875 * i),
                     Family(0, 0, 0.125 * i, 0, 0.1875 * i, [0.1875 * i, -0.125 * i])]
        p["CORK"] = [Family(0, 0, 0, 0, 0.125 * i), Family(135, 0.0625 * i, -0.0625 * i, 0, 0.353553 * i, [0.176777 * i, -0.176777 * i]),
                     Family(135, 0.09375 * i, -0.0625 * i, 0, 0.353553 * i, [0.176777 * i, -0.176777 * i])]
        p["DASH"] = [Family(0, 0, 0, 0.0625 * i, 0.125 * i, [0.125 * i, -0.125 * i])]
        p["DOLMIT"] = [Family(0, 0, 0, 0, 0.25 * i), Family(45, 0, 0, 0.353553 * i, 0.176777 * i, [0.353553 * i, -0.707107 * i])]
        p["ESCHER"] = [Family(60, 0, 0, -0.6 * i, 1.039230 * i, [1.1 * i, -0.1 * i]), Family(180, 0, 0, -0.6 * i, 1.039230 * i, [1.1 * i, -0.1 * i]),
                       Family(300, 0, 0, 0.6 * i, 1.039230 * i, [1.1 * i, -0.1 * i]), Family(60, 0.1 * i, 0, -0.6 * i, 1.039230 * i, [0.2 * i, -1 * i]),
                       Family(300, 0.1 * i, 0, 0.6 * i, 1.039230 * i, [0.2 * i, -1 * i]), Family(180, -0.05 * i, 0.086603 * i, -0.6 * i, 1.039230 * i, [0.2 * i, -1 * i])]
        p["FLEX"] = [Family(0, 0, 0, 0, 0.25 * i, [0.25 * i, -0.25 * i]),
                     Family(45, 0.25 * i, 0, 0.176777 * i, 0.176777 * i, [0.0625 * i, -0.228553 * i, 0.0625 * i, -0.353553 * i])]
        p["GRATE"] = [Family(0, 0, 0, 0, 0.03125 * i), Family(90, 0, 0, 0, 0.125 * i)]
        let s = 0.125 * i
        p["HEX"] = [Family(0, 0, 0, 1.5 * s, h3 * s, [s, -2 * s]), Family(120, 0, 0, 1.5 * s, h3 * s, [s, -2 * s]),
                    Family(60, s, 0, 1.5 * s, h3 * s, [s, -2 * s])]
        p["HOUND"] = [Family(0, 0, 0, 0.25 * i, 0.0625 * i, [1 * i, -0.5 * i]), Family(90, 0, 0, -0.25 * i, 0.0625 * i, [1 * i, -0.5 * i])]
        p["MUDST"] = [Family(0, 0, 0, 0.5 * i, 0.25 * i, [0.25 * i, -0.25 * i, 0, -0.25 * i, 0, -0.25 * i])]
        p["NET3"] = [Family(0, 0, 0, 0, 0.125 * i), Family(60, 0, 0, 0, 0.125 * i), Family(120, 0, 0, 0, 0.125 * i)]
        p["PLAST"] = [Family(0, 0, 0, 0, 0.25 * i), Family(0, 0, 0.03125 * i, 0, 0.25 * i), Family(0, 0, 0.0625 * i, 0, 0.25 * i)]
        p["PLASTI"] = p["PLAST"]! + [Family(0, 0, 0.15625 * i, 0, 0.25 * i)]
        p["SACNCR"] = [Family(45, 0, 0, 0, 0.09375 * i), Family(45, 0.066291 * i, 0, 0, 0.09375 * i, [0, -0.09375 * i])]
        p["STARS"] = [Family(0, 0, 0, 0.25 * i, 0.216506 * i, [0.125 * i, -0.125 * i]), Family(60, 0, 0, 0.25 * i, 0.216506 * i, [0.125 * i, -0.125 * i]),
                      Family(120, 0.125 * i, 0, 0.25 * i, 0.216506 * i, [0.125 * i, -0.125 * i])]
        p["STEEL"] = [Family(45, 0, 0, 0, 0.125 * i), Family(45, 0, 0.0625 * i, 0, 0.125 * i)]
        p["SWAMP"] = [Family(0, 0, 0, 0.5 * i, 0.866025 * i, [0.125 * i, -0.875 * i]),
                      Family(90, 0.0625 * i, 0, 0.866025 * i, 0.5 * i, [0.0625 * i, -1.669551 * i]),
                      Family(90, 0.078125 * i, 0, 0.866025 * i, 0.5 * i, [0.05 * i, -1.682051 * i]),
                      Family(90, 0.046875 * i, 0, 0.866025 * i, 0.5 * i, [0.05 * i, -1.682051 * i]),
                      Family(60, 0.09375 * i, 0, 0.5 * i, 0.866025 * i, [0.04 * i, -0.96 * i]),
                      Family(120, 0.03125 * i, 0, 0.5 * i, 0.866025 * i, [0.04 * i, -0.96 * i])]
        p["TRANS"] = [Family(0, 0, 0, 0, 0.25 * i), Family(0, 0, 0.125 * i, 0, 0.25 * i, [0.125 * i, -0.125 * i])]
        p["TRIANG"] = [Family(60, 0, 0, 0.1875 * i, 0.324760 * i, [0.1875 * i, -0.1875 * i]),
                       Family(120, 0, 0, 0.1875 * i, 0.324760 * i, [0.1875 * i, -0.1875 * i]),
                       Family(0, -0.09375 * i, 0.162380 * i, 0.1875 * i, 0.324760 * i, [0.1875 * i, -0.1875 * i])]
        // Architectural (real-world mm).
        p["AR-B816C"] = [Family(0, 0, 0, 203.2, 203.2, [396.875, -9.525]), Family(0, -203.2, 9.525, 203.2, 203.2, [396.875, -9.525]),
                         Family(90, 0, 0, 203.2, 203.2, [-9.525, 193.675]), Family(90, -9.525, 0, 203.2, 203.2, [-9.525, 193.675])]
        p["AR-B88"] = [Family(0, 0, 0, 0, 203.2), Family(90, 0, 0, 203.2, 101.6, [203.2, -203.2])]
        p["AR-BRELM"] = [Family(0, 0, 0, 0, 67.7), Family(90, 0, 0, 0, 203.2, [67.7, -67.7]), Family(90, 50.8, 67.7, 0, 101.6, [67.7, -67.7])]
        var parq: [Family] = []
        for k in 0...6 {
            let o = 50.8 * Double(k)
            parq.append(Family(90, o, 0, 304.8, 304.8, [304.8, -304.8]))
            parq.append(Family(0, 0, 304.8 + o, 304.8, -304.8, [304.8, -304.8]))
        }
        p["AR-PARQ1"] = parq
        p["AR-RROOF"] = [Family(0, 0, 0, 55.88, 25.4, [381, -50.8, 127, -50.8]), Family(0, 33.87, 12.7, -25.4, 33.87, [76.2, -8.5, 152.4, -19.05]),
                         Family(0, 12.7, 21.17, 132.08, 17.72, [203.2, -35.56, 101.6, -25.4])]
        p["AR-RSHKE"] = [Family(0, 0, 0, 647.7, 304.8, [152.4, -127, 177.8, -76.2, 228.6, -76.2]),
                         Family(0, 152.4, 12.7, 647.7, 304.8, [127, -482.6, 101.6, -152.4]),
                         Family(0, 457.2, -19.05, 647.7, 304.8, [76.2, -787.4]),
                         Family(90, 0, 0, 304.8, 215.9, [292.1, -927.1]),
                         Family(90, 152.4, 0, 304.8, 215.9, [285.75, -933.45]),
                         Family(90, 279.4, 0, 304.8, 215.9, [266.7, -952.5])]
        // ISO 128 line hatches (acadiso ACAD_ISOnnW100: dash patterns of the ISO linetypes, 5 mm spacing, pen width 1 mm).
        let iso: [(String, [Double])] = [
            ("02", [12, -3]), ("03", [12, -18]), ("04", [24, -3, 0.5, -3]), ("05", [24, -3, 0.5, -3, 0.5, -3]),
            ("06", [24, -3, 0.5, -3, 0.5, -6.5]), ("07", [0.5, -3]), ("08", [24, -3, 6, -3]), ("09", [24, -3, 6, -3, 6, -3]),
            ("10", [12, -3, 0.5, -3]), ("11", [12, -3, 12, -3, 0.5, -3]), ("12", [12, -3, 0.5, -3, 0.5, -3]),
            ("13", [12, -3, 12, -3, 0.5, -6.5]), ("14", [12, -3, 0.5, -3, 0.5, -6.5]), ("15", [12, -3, 12, -3, 0.5, -10])]
        for (n, d) in iso { p["ACAD_ISO\(n)W100"] = [Family(0, 0, 0, 0, 5, d)] }
        // GOST (Russian drafting standard) glass, wood and ground.
        p["GOST_GLASS"] = [Family(45, 0, 0, 6, -6, [5, -7]), Family(45, 2.12132, 0, 6, -6, [2, -10]), Family(45, 0, 2.12132, 6, -6, [2, -10])]
        p["GOST_WOOD"] = [Family(90, 0, 0, 0, -6, [10, -2]), Family(90, 2, -2, 0, -6, [6, -1.5, 5, -1.5]), Family(90, 4, -5, 0, -6, [10, -2])]
        p["GOST_GROUND"] = [Family(45, 0, 0, 10, -10, [20]), Family(45, 3, 0, 10, -10, [20]), Family(45, 6, 0, 10, -10, [20])]
        return p
    }()

    /// Short descriptions of the library patterns (pattern palette tooltips).
    public static let descriptions: [String: String] = [
        "SOLID": "Solid fill", "ANGLE": "Angle steel", "ANSI31": "ANSI iron, brick, stone masonry", "ANSI32": "ANSI steel",
        "ANSI33": "ANSI bronze, brass, copper", "ANSI34": "ANSI plastic, rubber", "ANSI35": "ANSI fire brick, refractory material",
        "ANSI36": "ANSI marble, slate, glass", "ANSI37": "ANSI lead, zinc, magnesium, sound/heat/elec insulation", "ANSI38": "ANSI aluminum",
        "AR-B816": "8x16 block elevation stretcher bond", "AR-B816C": "8x16 block elevation stretcher bond with mortar joints",
        "AR-B88": "8x8 block elevation stretcher bond", "AR-BRELM": "Standard brick elevation English bond with mortar joints",
        "AR-BRSTD": "Standard brick elevation stretcher bond", "AR-CONC": "Random dot and stone pattern (concrete)",
        "AR-HBONE": "Standard brick herringbone pattern @ 45 degrees", "AR-PARQ1": "2x12 parquet flooring: pattern of 12x12",
        "AR-RROOF": "Roof shingle texture", "AR-RSHKE": "Roof wood shake texture", "AR-SAND": "Random dot pattern (sand)",
        "BOX": "Box steel", "BRASS": "Brass material", "BRICK": "Brick or masonry-type surface", "BRSTONE": "Brick and stone",
        "CLAY": "Clay material", "CORK": "Cork material", "CROSS": "A series of crosses", "DASH": "Dashed lines", "DOLMIT": "Geological rock layering",
        "DOTS": "A series of dots", "EARTH": "Earth or ground (subterranean)", "ESCHER": "Escher pattern", "FLEX": "Flexible material",
        "GOST_GLASS": "Glass (GOST)", "GOST_WOOD": "Wood (GOST)", "GOST_GROUND": "Ground (GOST)", "GRASS": "Grass area", "GRATE": "Grated area",
        "GRAVEL": "Gravel pattern", "HEX": "Hexagons", "HONEY": "Honeycomb pattern", "HOUND": "Houndstooth check", "INSUL": "Insulation material",
        "LINE": "Parallel horizontal lines", "MUDST": "Mud and sand", "NET": "Horizontal / vertical grid", "NET3": "Network pattern 0-60-120",
        "PLAST": "Plastic material", "PLASTI": "Plastic material", "SACNCR": "Concrete", "SQUARE": "Small aligned squares", "STARS": "Star of David",
        "STEEL": "Steel material", "SWAMP": "Swampy area", "TRANS": "Heat transfer material", "TRIANG": "Equilateral triangles", "WOOD": "Timber grain",
        "ZIGZAG": "Staircase effect",
    ].merging((2...15).map { (String(format: "ACAD_ISO%02dW100", $0), "ISO 128 hatch, linetype \(String(format: "%02d", $0))") }) { a, _ in a }

    // MARK: Custom patterns (.pat files)

    /// Patterns loaded from .pat definitions (PATLOAD, or saved in a drawing as variables "HPPAT:<NAME>").
    static var custom: [String: [Family]] = [:]
    static var customSources: [String: String] = [:]

    /// Parses AutoCAD .pat text ("*NAME, description" followed by "angle, x0,y0, dx,dy [, dashes…]" lines).
    /// Returns the patterns by upper-case name with their definition text (for saving in a drawing). Values are used as written
    /// (drawing units); ";" starts a comment.
    public static func parsePat(_ text: String) -> [(name: String, text: String)] {
        var out: [(String, String)] = []
        var name: String? = nil, body: [String] = []
        func flush() { if let n = name, !body.isEmpty { out.append((n, body.joined(separator: "\n"))) }; name = nil; body = [] }
        for raw in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            var line = raw
            if let c = line.firstIndex(of: ";") { line = String(line[..<c]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("*") {
                flush()
                let n = line.dropFirst().split(separator: ",", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? ""
                name = n.isEmpty ? nil : n
            } else if name != nil, families(fromLine: line) != nil { body.append(line) }
        }
        flush()
        return out
    }

    static func families(fromLine line: String) -> Family? {
        let v = line.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard v.count >= 5, v.allSatisfy({ $0 != nil }) else { return nil }
        let n = v.map { $0! }
        return Family(n[0], n[1], n[2], n[3], n[4], Array(n.dropFirst(5)))
    }

    /// Registers a pattern definition (lines of "angle, x0,y0, dx,dy, dashes"). Returns false if nothing valid.
    @discardableResult
    public static func register(name: String, definition: String) -> Bool {
        let key = name.uppercased()
        if customSources[key] == definition { return true }
        let fams = definition.components(separatedBy: "\n").compactMap { families(fromLine: $0) }
        guard !fams.isEmpty, fams.allSatisfy({ abs($0.delta.y) > 1e-12 }) else { return false }
        custom[key] = fams; customSources[key] = definition
        return true
    }

    /// Registers the patterns saved in a drawing (variables "HPPAT:<NAME>").
    public static func register(doc: ArchiDocument) {
        for (k, v) in doc.variables where k.hasPrefix("HPPAT:") { register(name: String(k.dropFirst(6)), definition: v) }
    }

    /// Built-in and loaded pattern names.
    public static var allNames: [String] { names + custom.keys.sorted().filter { !names.contains($0) } }

    /// Pattern names understood by `lines(...)` (SOLID is a plain fill).
    public static let names: [String] = ["SOLID", "ANSI31", "ANSI32", "ANSI33", "ANSI34", "ANSI35", "ANSI36", "ANSI37", "ANSI38", "AR-CONC", "AR-SAND",
                                         "INSUL", "BRICK", "AR-BRSTD", "AR-B816", "AR-HBONE", "GRASS", "NET", "DOTS", "HONEY", "LINE", "CROSS",
                                         "EARTH", "GRAVEL", "WOOD", "SQUARE", "ZIGZAG",
                                         "ANGLE", "AR-B816C", "AR-B88", "AR-BRELM", "AR-PARQ1", "AR-RROOF", "AR-RSHKE", "BOX", "BRASS", "BRSTONE",
                                         "CLAY", "CORK", "DASH", "DOLMIT", "ESCHER", "FLEX", "GOST_GLASS", "GOST_WOOD", "GOST_GROUND", "GRATE", "HEX",
                                         "HOUND", "MUDST", "NET3", "PLAST", "PLASTI", "SACNCR", "STARS", "STEEL", "SWAMP", "TRANS", "TRIANG"]
                                         + (2...15).map { String(format: "ACAD_ISO%02dW100", $0) }

    /// Entity prop choosing how a hatch pattern scales (ANN-071): "model" = real size in millimetres, scales with the
    /// model; "drafting" = size on paper, multiplied by the annotation scale (CANNOSCALE). Absent = the plain scale.
    public static let patternTypeProp = "patternType"
    /// Pattern scale actually used for a hatch with the given props.
    public static func effectiveScale(_ scale: Double, props: [String: String], doc: ArchiDocument?) -> Double {
        let s = scale > 1e-12 ? scale : 1
        guard let t = props[patternTypeProp]?.lowercased(), let doc else { return s }
        switch t {
        case "model": return s / doc.units.mm
        case "drafting": return s * Annotative.currentScale(doc) / doc.units.mm
        default: return s
        }
    }

    /// Whether the pattern is defined at real-world size (AR-*, WOOD, GRAVEL, INSUL) rather than drafting size.
    public static func isRealWorld(_ pattern: String) -> Bool {
        let p = pattern.uppercased()
        return p.hasPrefix("AR-") || p == "WOOD" || p == "GRAVEL" || p == "INSUL"
    }

    /// Safety limit on generated segments per call.
    public static var maxSegments = 60000

    /// Pattern line segments with the pattern anchored at `origin` (HATCH origin / HPORIGIN) instead of 0,0.
    public static func lines(loops: [[Vec2]], pattern: String, scale: Double, angle: Double, origin: Vec2) -> [[Vec2]] {
        guard origin != .zero else { return lines(loops: loops, pattern: pattern, scale: scale, angle: angle) }
        let shifted = loops.map { $0.map { $0 - origin } }
        return lines(loops: shifted, pattern: pattern, scale: scale, angle: angle).map { $0.map { $0 + origin } }
    }

    /// Pattern line segments clipped to the even-odd region of `loops`. Returns [] for SOLID or unknown patterns.
    public static func lines(loops: [[Vec2]], pattern: String, scale: Double, angle: Double) -> [[Vec2]] {
        let loops = loops.map { RG.dedupe($0, closed: true) }.filter { $0.count >= 3 }
        guard !loops.isEmpty else { return [] }
        let s = scale > 1e-12 ? scale : 1
        let name = pattern.uppercased()
        if name == "INSUL" { return insulation(loops: loops, scale: s, angle: angle) }
        guard let fams = families[name] ?? custom[name] else { return [] }
        var out: [[Vec2]] = []
        for f in fams {
            family(f, loops: loops, scale: s, angle: angle, into: &out)
            if out.count > maxSegments { break }
        }
        return out
    }

    static func family(_ f: Family, loops: [[Vec2]], scale: Double, angle: Double, into out: inout [[Vec2]]) {
        let theta = rad(f.angle) + angle
        let u = Vec2.polar(1, theta), v = u.perp
        let o = (f.origin * scale).rotated(by: angle)
        let dx = f.delta.x * scale, dy = f.delta.y * scale
        guard abs(dy) > 1e-12 else { return }
        let dashes = f.dashes.map { $0 * scale }
        let period = dashes.reduce(0) { $0 + abs($1) }
        // Local coordinates: x along the lines, y across.
        let local = loops.map { $0.map { p -> Vec2 in let q = p - o; return Vec2(q.dot(u), q.dot(v)) } }
        var ymin = Double.infinity, ymax = -Double.infinity
        for l in local { for p in l { ymin = min(ymin, p.y); ymax = max(ymax, p.y) } }
        var k0 = Int((ymin / dy).rounded(.up)), k1 = Int((ymax / dy).rounded(.down))
        if k0 > k1 { swap(&k0, &k1) }
        guard k1 - k0 < 20000 else { return }
        let dotLen = max(scale * 0.05, 1e-6)
        func world(_ x: Double, _ y: Double) -> Vec2 { o + u * x + v * y }
        for k in k0...k1 {
            let y = Double(k) * dy
            var xs: [Double] = []
            for l in local {
                for i in 0..<l.count {
                    let a = l[i], b = l[(i + 1) % l.count]
                    if (a.y > y) != (b.y > y) { xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)) }
                }
            }
            xs.sort()
            var j = 0
            while j + 1 < xs.count {
                let x0 = xs[j], x1 = xs[j + 1]
                j += 2
                if x1 - x0 < 1e-12 { continue }
                if dashes.isEmpty || period < 1e-12 { out.append([world(x0, y), world(x1, y)]); continue }
                let phase = Double(k) * dx
                var c = ((x0 - phase) / period).rounded(.down)
                var guardN = 0
                while guardN < 100000 {
                    guardN += 1
                    var pos = phase + c * period
                    if pos > x1 { break }
                    for d in dashes {
                        let len = abs(d)
                        if d > 0 {
                            let a = max(pos, x0), b = min(pos + len, x1)
                            if b > a + 1e-12 { out.append([world(a, y), world(b, y)]) }
                        } else if d == 0, pos >= x0, pos <= x1 {
                            out.append([world(pos, y), world(min(pos + dotLen, x1), y)])
                        }
                        pos += len
                        if pos > x1 { break }
                    }
                    c += 1
                    if out.count > maxSegments { return }
                }
            }
        }
    }

    /// Batt insulation: rows of zig-zag strokes clipped to the region.
    static func insulation(loops: [[Vec2]], scale: Double, angle: Double) -> [[Vec2]] {
        let rowH = 100 * scale, step = rowH / 2.5
        let u = Vec2.polar(1, angle), v = u.perp
        var xmin = Double.infinity, xmax = -Double.infinity, ymin = Double.infinity, ymax = -Double.infinity
        for l in loops { for p in l { let x = p.dot(u), y = p.dot(v); xmin = min(xmin, x); xmax = max(xmax, x); ymin = min(ymin, y); ymax = max(ymax, y) } }
        let r0 = Int((ymin / rowH).rounded(.down)), r1 = Int((ymax / rowH).rounded(.up))
        guard r1 - r0 < 2000, (xmax - xmin) / step < 20000 else { return [] }
        var out: [[Vec2]] = []
        for r in r0..<max(r0 + 1, r1) {
            let y0 = Double(r) * rowH, y1 = y0 + rowH
            var x = (xmin / step).rounded(.down) * step, up = false
            var pts: [Vec2] = []
            while x <= xmax + step {
                pts.append(u * x + v * (up ? y1 : y0)); up.toggle(); x += step
            }
            out += RG.clipPolyline(pts, loops)
            if out.count > maxSegments { break }
        }
        return out
    }
}
