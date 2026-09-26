// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Dimension style settings beyond the core `DimStyle` record (ANN-031): primary unit format (DIMLUNIT), rounding
/// (DIMRND), zero suppression (DIMZIN), style-level tolerances (DIMTOL/DIMTP/DIMTM), alternate units (DIMALT…), fit
/// (DIMATFIT), text placement (DIMTAD) and the text style (DIMTXSTY). Stored per style in the document variable
/// `DIMSTYLEX:<NAME>` ("key=value;…"), so older files simply have none and newer ones stay readable by older builds.
/// A dimension's own `dimTol` / `dimAlt` props override the style's.
public struct DimStyleExtras: Hashable {
    public enum UnitFormat: String, CaseIterable { case decimal, architectural, engineering, fractional, scientific }

    public var units: UnitFormat = .decimal
    /// Tolerance in `DimExtras.toleranceProp` syntax ("sym:0.1", "dev:0.2,0.1", "limits:0.2,0.1", "basic").
    public var tolerance: String?
    /// Alternate units in `DimExtras.alternateProp` syntax ("factor,decimals[,suffix[,prefix]]").
    public var alternate: String?
    /// "best", "arrows", "text" or "both".
    public var fit: String = "best"
    public var textCentered = false
    public var suppressLeadingZeros = false
    public var suppressTrailingZeros = false
    /// Round measured distances to the nearest multiple (0 = off).
    public var roundOff: Double = 0
    /// Text style of the dimension text (nil = the drawing's default style).
    public var textStyle: String?

    public init() {}

    public static let variablePrefix = "DIMSTYLEX:"

    public var isDefault: Bool { self == DimStyleExtras() }
    public var layout: DimLayout { DimLayout(fit: fit, textCentered: textCentered) }

    // MARK: Storage

    public var encoded: String {
        var parts: [String] = []
        if units != .decimal { parts.append("units=" + units.rawValue) }
        if let t = tolerance, !t.isEmpty { parts.append("tol=" + t) }
        if let a = alternate, !a.isEmpty { parts.append("alt=" + a) }
        if fit.lowercased() != "best" { parts.append("fit=" + fit.lowercased()) }
        if textCentered { parts.append("tad=0") }
        let zin = (suppressLeadingZeros ? 4 : 0) | (suppressTrailingZeros ? 8 : 0)
        if zin != 0 { parts.append("zin=\(zin)") }
        if roundOff > 0 { parts.append("rnd=" + fmt(roundOff, 8)) }
        if let s = textStyle, !s.isEmpty { parts.append("txsty=" + s) }
        return parts.joined(separator: ";")
    }

    public init(encoded s: String) {
        for part in s.split(separator: ";") {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let k = part[..<eq].lowercased(), v = String(part[part.index(after: eq)...])
            switch k {
            case "units": units = UnitFormat(rawValue: v.lowercased()) ?? .decimal
            case "tol": tolerance = v.isEmpty ? nil : v
            case "alt": alternate = v.isEmpty ? nil : v
            case "fit": fit = ["arrows", "text", "both"].contains(v.lowercased()) ? v.lowercased() : "best"
            case "tad": textCentered = v == "0"
            case "zin": let z = Int(v) ?? 0; suppressLeadingZeros = z & 4 != 0; suppressTrailingZeros = z & 8 != 0
            case "rnd": roundOff = max(0, Double(v) ?? 0)
            case "txsty": textStyle = v.isEmpty ? nil : v
            default: break
            }
        }
    }

    public static func get(_ style: String, doc: ArchiDocument) -> DimStyleExtras {
        doc.variable(variablePrefix + style).map { DimStyleExtras(encoded: $0) } ?? DimStyleExtras()
    }

    public static func set(_ x: DimStyleExtras, style: String, doc: inout ArchiDocument) {
        let key = (variablePrefix + style).uppercased()
        if x.isDefault { doc.variables[key] = nil } else { doc.variables[key] = x.encoded }
    }

    /// Copies the extras of one style to another (new styles start from the current one).
    public static func copy(from a: String, to b: String, doc: inout ArchiDocument) {
        set(get(a, doc: doc), style: b, doc: &doc)
    }

    // MARK: Formatting

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    /// "n/d" fraction text of a numerator over a power-of-two denominator (reduced), "" for zero.
    static func fraction(_ num: Int, _ den: Int) -> String {
        guard num != 0, den > 0 else { return "" }
        let g = gcd(num, den)
        return "\(num / g)/\(den / g)"
    }

    /// Formats a distance (drawing units) in this style's unit format. `unitMM` = millimetres per drawing unit (used
    /// to convert to inches for the imperial formats).
    public func format(_ v0: Double, decimals: Int, unitMM: Double) -> String {
        var v = v0
        if roundOff > 0 { v = (v / roundOff).rounded() * roundOff }
        let dec = max(0, min(8, decimals))
        let neg = v < 0
        let a = abs(v)
        var s: String
        switch units {
        case .decimal:
            s = zeros(DimensionRenderer.number(a, decimals: dec))
        case .scientific:
            s = String(format: "%.\(dec)E", a)
        case .architectural, .fractional:
            let inches = a * unitMM / 25.4
            let den = 1 << dec
            var total = Int((inches * Double(den)).rounded())
            if units == .fractional {
                let whole = total / den, rem = total % den
                let f = DimStyleExtras.fraction(rem, den)
                s = whole == 0 && !f.isEmpty ? f : (f.isEmpty ? "\(whole)" : "\(whole) \(f)")
            } else {
                let perFoot = 12 * den
                let feet = total / perFoot
                total -= feet * perFoot
                let whole = total / den, rem = total % den
                let f = DimStyleExtras.fraction(rem, den)
                let inchText = f.isEmpty ? "\(whole)" : (whole == 0 ? f : "\(whole) \(f)")
                if feet == 0 && suppressLeadingZeros { s = inchText + "\"" }
                else if total == 0 && suppressTrailingZeros { s = "\(feet)'" }
                else { s = "\(feet)'-" + inchText + "\"" }
            }
        case .engineering:
            let inches = a * unitMM / 25.4
            var feet = Int((inches / 12).rounded(.down))
            var rest = inches - Double(feet) * 12
            if Double(String(format: "%.\(dec)f", rest)) ?? 0 >= 12 { feet += 1; rest = 0 }
            let r = zeros(DimensionRenderer.number(rest, decimals: dec))
            if feet == 0 && suppressLeadingZeros { s = r + "\"" } else { s = "\(feet)'-" + r + "\"" }
        }
        return (neg ? "-" : "") + s
    }

    /// Applies zero suppression to a decimal number text.
    func zeros(_ s0: String) -> String {
        var s = s0
        if suppressTrailingZeros, s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if suppressLeadingZeros, s.hasPrefix("0."), s.count > 2 { s.removeFirst() }
        return s
    }

    /// Primary text of a dimension (symbols, prefix/suffix, text override with "<>").
    public func primaryText(_ d: DimensionGeom, style: DimStyle, unitMM: Double) -> String {
        if units == .decimal && !suppressLeadingZeros && !suppressTrailingZeros && roundOff <= 0 { return DimensionRenderer.formatted(d, style: style) }
        let m = DimensionRenderer.measurement(d)
        var core: String
        if d.kind == .angular {
            core = zeros(DimensionRenderer.number(m * 180 / .pi, decimals: style.decimals)) + "°"
        } else {
            core = format(m * style.linearScale, decimals: style.decimals, unitMM: unitMM)
        }
        switch d.kind {
        case .radius: core = "R" + core
        case .diameter: core = "Ø" + core
        case .arcLength: core = "⌒" + core
        default: break
        }
        let measured = style.prefix + core + style.suffix
        if let o = d.textOverride, !o.isEmpty { return o.replacingOccurrences(of: "<>", with: measured) }
        return measured
    }

    /// Props of a dimension with the style's tolerance and alternate units filled in where the object has none.
    public func mergedProps(_ props: [String: String]) -> [String: String] {
        var p = props
        if p[DimExtras.toleranceProp] == nil, let t = tolerance { p[DimExtras.toleranceProp] = t }
        if p[DimExtras.alternateProp] == nil, let a = alternate { p[DimExtras.alternateProp] = a }
        return p
    }

    /// Full displayed text of a dimension following its style and its own overrides.
    public static func text(_ d: DimensionGeom, props: [String: String], doc: ArchiDocument) -> String {
        let ds = doc.dimStyle(d.style)
        let x = get(ds.name, doc: doc)
        var dd = d
        dd.textOverride = x.primaryText(d, style: ds, unitMM: doc.units.mm)
        return DimExtras.text(dd, style: ds, props: x.mergedProps(props))
    }

    /// Whether a dimension needs the extended renderer (style extras, object extras or a stroke-font text style).
    public static func needsCustomRendering(_ e: Entity, _ d: DimensionGeom, doc: ArchiDocument) -> Bool {
        if DimExtras.has(e) { return true }
        let x = get(doc.dimStyle(d.style).name, doc: doc)
        if !x.isDefault { return true }
        return TextStyleFonts.style("Standard", doc: doc).map { TextStyleFonts.usesStrokes($0, doc: doc) } ?? false
    }
}
