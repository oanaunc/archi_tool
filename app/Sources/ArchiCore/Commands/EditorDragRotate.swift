// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Rotate-by-90° while dragging (MOD-029, Revit's Space shortcut).
///
/// Commands that place or move objects ask for their destination point with `getRotatablePoint`: the prompt is flagged
/// `rotatable`, the UI calls `rotateDrag90()` when the user presses Space during the drag (scripts type the `Turn90`
/// keyword), and the preview and the final result are turned by `dragRotation` about the destination point.
extension Editor {
    /// Keyword accepted at rotatable prompts (typed or scripted) to turn the preview 90° counter-clockwise.
    public static let turnKeyword = "Turn90"

    /// Whether the current prompt accepts a 90° turn.
    public var canRotateDrag: Bool { request?.rotatable == true }

    /// Turns the current drag preview by 90° (counter-clockwise, or clockwise). Returns false when the prompt is not rotatable,
    /// so the caller can fall back to the key's normal meaning.
    @discardableResult
    public func rotateDrag90(clockwise: Bool = false) -> Bool {
        guard canRotateDrag else { return false }
        dragRotation = Editor.quarterTurn(dragRotation + (clockwise ? -1 : 1) * Double.pi / 2)
        onPromptChange?()
        onChange?()
        return true
    }

    /// Normalises an angle to an exact multiple of π/2 in [0, 2π).
    public static func quarterTurn(_ a: Double) -> Double {
        let q = ((Int((a / (Double.pi / 2)).rounded()) % 4) + 4) % 4
        return Double(q) * Double.pi / 2
    }

    /// Transform of a drag from `base` to `p` with the current quarter turn about `p`: translation then rotation, exact for
    /// multiples of 90° (cos/sin snapped to 0/±1).
    public static func dragTransform(from base: Vec2, to p: Vec2, rotation: Double) -> Transform2D {
        let q = Int((Editor.quarterTurn(rotation) / (Double.pi / 2)).rounded()) % 4
        let c: Double = [1, 0, -1, 0][q], s: Double = [0, 1, 0, -1][q]
        // x' = R (x - base) + p
        return Transform2D(a: c, b: s, c: -s, d: c, tx: p.x - (c * base.x - s * base.y), ty: p.y - (s * base.x + c * base.y))
    }

    /// Asks for a point with a preview that follows the quarter-turn rotation. The preview closure receives the cursor and
    /// the current rotation. Returns the answer and the rotation in effect when it was given (reset to `rotation` first).
    public func getRotatablePoint(_ msg: String, base: Vec2? = nil, keywords: [String] = [], rotation: Double = 0,
                                  preview: @escaping (Vec2, Double) -> [Geometry]) async throws -> (answer: PointAnswer, rotation: Double) {
        dragRotation = Editor.quarterTurn(rotation)
        defer { dragRotation = 0 }
        let kws = keywords + [Editor.turnKeyword]
        while true {
            var req = InputRequest(msg, kinds: [.point, .keyword], keywords: kws, base: base, preview: { [unowned self] c in preview(c, self.dragRotation) })
            req.rotatable = true
            let r = await ask(req)
            switch r {
            case .point(let p): return (.point(p), dragRotation)
            case .keyword(let k) where k == Editor.turnKeyword:
                dragRotation = Editor.quarterTurn(dragRotation + Double.pi / 2)
                continue
            case .keyword(let k): return (.keyword(k), dragRotation)
            case .enter: return (.none, dragRotation)
            case .cancel: throw CommandError.cancelled
            case .number(let d):
                if let b = base {
                    let dir = ((cursor ?? b + Vec2(1, 0)) - b).normalized
                    return (.point(b + (dir == .zero ? Vec2(1, 0) : dir) * d), dragRotation)
                }
                return (.none, dragRotation)
            default: return (.none, dragRotation)
            }
        }
    }
}
