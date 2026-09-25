// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Construction phases (Revit-style): elements carry props "phaseCreated" and optionally "phaseDemolished"
/// (phase names from `ArchiDocument.phases`). Views show the model as of the current phase (variable PHASE)
/// through a phase filter (variable PHASEFILTER).
public enum Phasing {
    public enum Status: String { case existing, new, demolished, future, gone }
    public enum Filter: String, CaseIterable {
        /// Existing halftone, demolished dashed, new normal.
        case all
        /// Existing and new, demolished hidden (as built at the end of the phase).
        case complete
        /// Only elements created in the phase.
        case new
        /// Existing and demolished (demolition plan).
        case demolition
        /// No graphic overrides; future and removed elements are still hidden.
        case none
    }

    public static func phaseIndex(_ name: String?, _ doc: ArchiDocument) -> Int? {
        guard let n = name, !n.isEmpty else { return nil }
        if let i = doc.phases.firstIndex(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { return i }
        return Int(n).flatMap { $0 >= 0 && $0 < doc.phases.count ? $0 : nil }
    }

    /// The phase views show (variable PHASE, default the last phase).
    public static func currentPhase(_ doc: ArchiDocument) -> Int {
        phaseIndex(doc.variable("PHASE"), doc) ?? max(doc.phases.count - 1, 0)
    }

    public static func filter(_ doc: ArchiDocument) -> Filter {
        Filter(rawValue: (doc.variable("PHASEFILTER") ?? "").lowercased()) ?? .all
    }

    /// Whether the document uses phasing at all (any element tagged).
    public static func isActive(_ doc: ArchiDocument) -> Bool {
        doc.elements.contains { $0.props["phaseCreated"] != nil || $0.props["phaseDemolished"] != nil }
    }

    public static func status(_ props: [String: String], doc: ArchiDocument, phase: Int? = nil) -> Status {
        let p = phase ?? currentPhase(doc)
        let c = phaseIndex(props["phaseCreated"], doc) ?? p
        if c > p { return .future }
        if let d = phaseIndex(props["phaseDemolished"], doc) {
            if d < p { return .gone }
            if d == p { return .demolished }
        }
        return c < p ? .existing : .new
    }

    /// Whether an element with this status is drawn under the filter.
    public static func visible(_ s: Status, _ f: Filter) -> Bool {
        switch s {
        case .future, .gone: return false
        case .existing: return f != .new
        case .new: return f != .demolition
        case .demolished: return f == .all || f == .demolition || f == .none
        }
    }

    /// Graphic override for 2D views: halftone for existing, dashed red for demolished.
    public static func style(_ s: Status, _ f: Filter) -> (halftone: Bool, dashed: Bool, tint: RGBA?) {
        guard f != .none else { return (false, false, nil) }
        switch s {
        case .existing: return (f == .all || f == .demolition, false, nil)
        case .demolished: return (false, true, RGBA(0.85, 0.3, 0.25))
        default: return (false, false, nil)
        }
    }
}
