// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Core of the heads-up input (CMD-007, CMD-032…034): clickable keyword spans of the prompt, the dynamic-input fields
/// shown next to the cursor (length / angle from the base point, or pointer coordinates) and turning typed field values
/// into command input, so the canvas tooltip and the command line behave identically.
extension InputRequest {
    /// Keywords with their character ranges inside `promptText` (for clickable options).
    public var keywordSpans: [(keyword: String, range: Range<String.Index>)] {
        let t = promptText
        guard !keywords.isEmpty, let open = t.lastIndex(of: "[") else { return [] }
        var out: [(String, Range<String.Index>)] = []
        var from = t.index(after: open)
        for k in keywords {
            guard let r = t.range(of: k, range: from..<t.endIndex) else { continue }
            out.append((k, r)); from = r.upperBound
        }
        return out
    }
}

public struct DynamicInputFields: Equatable {
    /// Distance from the base point (dimensional input) — nil when there is no base point.
    public var length: Double?
    /// Angle in degrees (0…360) from the base point.
    public var angle: Double?
    /// Pointer input: the cursor in current-UCS coordinates (relative to the base point when DYNPICOORDS = 0 and a base
    /// point exists).
    public var x: Double
    public var y: Double
    public var relative: Bool
    /// True when the fields are in the coordinate system of the active dynamic-UCS face (PRC-036).
    public var onFace: Bool = false
}

extension Editor {
    /// DYNMODE: 0 off, 1 pointer input, 2 dimensional input, 3 both (default).
    public var dynamicInputMode: Int { settings.dynamicInput ? (doc.variable("DYNMODE").flatMap(Int.init).map { abs($0) } ?? 3) : 0 }

    /// Fields for the heads-up tooltip at `cursor` for the current request (nil when no point is requested or DYNMODE 0).
    public func dynamicInputFields(cursor: Vec2) -> DynamicInputFields? {
        guard let req = request, req.kinds.contains(.point) || req.kinds.contains(.distance), dynamicInputMode != 0 else { return nil }
        let ucs = UCSFrame.current(doc)
        let base = req.base ?? (req.kinds.contains(.point) ? nil : lastPoint)
        let relativeDefault = (doc.variable("DYNPICOORDS").flatMap(Int.init) ?? 0) == 0
        var f = DynamicInputFields(length: nil, angle: nil, x: 0, y: 0, relative: false)
        if let b = base {
            let v = ucs.fromWorld(cursor) - ucs.fromWorld(b)
            f.length = v.length
            var a = deg(v.angle); if a < 0 { a += 360 }
            f.angle = a
        }
        if let b = base, relativeDefault { let v = ucs.fromWorld(cursor) - ucs.fromWorld(b); f.x = v.x; f.y = v.y; f.relative = true }
        else { let p = ucs.fromWorld(cursor); f.x = p.x; f.y = p.y }
        // Dynamic UCS on a sloped face: lengths, angles and coordinates are measured in the face plane, matching how
        // typed values are read.
        if let face = dynamicFaceFrame, !face.isHorizontal, let c3 = face.planePoint(cursor) {
            let lc = face.fromWorld(c3)
            f.onFace = true
            if let b = base {
                let b3 = face.planePoint(b) ?? Vec3(b.x, b.y, InputParser.lastZ)
                let v = lc - face.fromWorld(b3)
                f.length = Vec2(v.x, v.y).length
                var a = deg(Vec2(v.x, v.y).angle); if a < 0 { a += 360 }
                f.angle = a
                if relativeDefault { f.x = v.x; f.y = v.y; f.relative = true } else { f.x = lc.x; f.y = lc.y; f.relative = false }
            } else { f.x = lc.x; f.y = lc.y; f.relative = false }
        }
        return f
    }

    /// Command-line token for values typed in the tooltip: length (+ optional angle in degrees) → "@L<A" (direct
    /// distance along the cursor when no angle); pointer x,y → "@x,y" or "#x,y". Nil when nothing usable was typed.
    public func dynamicInputToken(length: String? = nil, angle: String? = nil, x: String? = nil, y: String? = nil, relative: Bool = true) -> String? {
        func clean(_ s: String?) -> String? { s.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } }
        if let l = clean(length) {
            guard InputParser.parseNumber(l) != nil else { return nil }
            if let a = clean(angle) { guard InputParser.parseAngleDegrees(a) != nil else { return nil }; return "@\(l)<\(a)" }
            return l
        }
        if let xs = clean(x), let ys = clean(y) {
            guard InputParser.parseNumber(xs) != nil, InputParser.parseNumber(ys) != nil else { return nil }
            return (relative && request?.base != nil ? "@" : "#") + xs + "," + ys
        }
        return nil
    }
}
