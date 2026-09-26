// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// One-shot object snap overrides (PRC-019): typing END, MID, CEN… at a point prompt (or choosing it from the canvas
/// Shift+right-click menu, which feeds the same token) makes only that snap active for the next point. While the "of"
/// prompt is up the running snap modes are swapped for the override, so the canvas shows the override's marker; typed or
/// scripted coordinates are snapped with the override too (a script can say "MID 480,5").
extension Editor {
    /// The snap modes in force while an override prompt is active (nil otherwise).
    public var snapOverrideModes: Set<SnapKind>? { activeSnapOverride }

    func resolveSnapOverride(_ o: String, _ req: InputRequest) async -> CommandInput {
        let saved = settings
        var s = settings
        s.objectSnapTracking = false; s.gridSnap = false
        if o == "NON" { s.objectSnap = false; s.snapModes = []; s.geometricCenterSnap = false }
        else if o == "GCEN" { s.objectSnap = true; s.snapModes = []; s.geometricCenterSnap = true }
        else if let k = InputParser.snapKind(override: o) { s.objectSnap = true; s.snapModes = [k]; s.geometricCenterSnap = false }
        settings = s
        activeSnapOverride = s.objectSnap ? s.snapModes : []
        let r = InputRequest("of", kinds: [.point], base: req.base, preview: req.preview)
        let base = req.base ?? lastPoint
        let answer = await ask(r)
        let snapSettings = settings
        settings = saved
        activeSnapOverride = nil
        guard case .point(let p) = answer else { return answer == .enter ? await ask(req) : answer }
        if o == "NON" { lastPoint = p; return .point(p) }
        let tol = Swift.max(pickTolerance, 1e-9)
        if let hit = Snap.find(cursor: p, doc: doc, settings: snapSettings, tolerance: tol, base: base) {
            lastPoint = hit.point
            return .point(hit.point)
        }
        // As in AutoCAD, the override applies to the object under the aperture even when its snap point is farther away
        // (MID anywhere on a line, END on the nearer end, CEN on a circle's edge).
        if o != "INT", let hit = objectSnap(near: p, settings: snapSettings, tolerance: tol, base: base) {
            lastPoint = hit
            return .point(hit)
        }
        print("No \(Editor.snapOverrideNames[o] ?? o.lowercased()) found for specified point.")
        return await ask(req)
    }

    /// The snap of the given modes on the drafting object nearest `p` (within `tolerance` of the object), at any distance.
    func objectSnap(near p: Vec2, settings s: DraftSettings, tolerance: Double, base: Vec2?) -> Vec2? {
        let f = PickFilter(doc)
        var best: (Entity, Double)?
        for e in doc.entities where f.displayed(e) && doc.isVisible(layer: e.layer) {
            let d = GeometryOps.distance(from: p, to: e.geometry, doc: doc)
            if d <= tolerance, d < (best?.1 ?? .infinity) { best = (e, d) }
        }
        guard let (e, _) = best else { return nil }
        var one = doc
        one.entities = [e]; one.elements = []
        let b = GeometryOps.bounds(e.geometry, doc: doc)
        let reach = b.isEmpty ? tolerance : Swift.max(tolerance, b.width + b.height + p.distance(to: b.center))
        return Snap.find(cursor: p, doc: one, settings: s, tolerance: reach, base: base)?.point
    }

    static let snapOverrideNames = ["END": "endpoint", "MID": "midpoint", "CEN": "center", "GCEN": "geometric center", "NOD": "node",
                                    "QUA": "quadrant", "INT": "intersection", "EXT": "extension", "INS": "insertion", "PER": "perpendicular",
                                    "TAN": "tangent", "NEA": "nearest", "PAR": "parallel"]
}
