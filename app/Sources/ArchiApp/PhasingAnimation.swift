// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import CoreText
import SceneKit
import ArchiCore

/// Construction sequence (4D) animation (VIS-044): phase by phase, the elements created in a phase appear from the
/// bottom up and those demolished in it disappear from the top down; the phase name is captioned. The sequence is
/// determined by the drawing's phases and element phase properties, so it is saved with the drawing and reproducible.
enum PhasingAnimation {
    /// Order in which elements of a phase are built: level elevation, then lowest point, then id.
    static func buildOrder(_ ids: [EntityID], doc: ArchiDocument) -> [EntityID] {
        var z: [EntityID: Double] = [:]
        for g in MeshBuilder.build(doc: stripped(doc, keep: Set(ids))) { if let id = g.id { z[id] = Swift.min(z[id] ?? .infinity, g.mesh.bounds.min.z) } }
        return ids.sorted { a, b in
            let za = z[a] ?? (doc.element(a).flatMap { doc.level($0.level)?.elevation } ?? 0), zb = z[b] ?? (doc.element(b).flatMap { doc.level($0.level)?.elevation } ?? 0)
            return za != zb ? za < zb : a < b
        }
    }

    /// The document with only `keep` elements and no phase properties (so everything kept is shown).
    static func stripped(_ doc: ArchiDocument, keep: Set<EntityID>) -> ArchiDocument {
        var d = doc
        d.elements = doc.elements.filter { keep.contains($0.id) }.map { var e = $0; e.props["phaseCreated"] = nil; e.props["phaseDemolished"] = nil; return e }
        d.variables["PHASE"] = nil; d.variables["PHASEFILTER"] = nil
        return d
    }

    /// Elements visible at a frame, and the phase shown.
    static func frame(_ f: Int, framesPerPhase n: Int, doc: ArchiDocument) -> (ids: [EntityID], phase: Int) {
        let phases = max(doc.phases.count, 1), per = max(n, 1)
        let p = Swift.min(f / per, phases - 1)
        let t = Double(Swift.min(f - p * per, per - 1) + 1) / Double(per)
        var ids: [EntityID] = []
        var created: [EntityID] = [], demolished: [EntityID] = []
        for e in doc.elements {
            let st = Phasing.status(e.props, doc: doc, phase: p)
            switch st {
            case .existing: ids.append(e.id)
            case .new: created.append(e.id)
            case .demolished: demolished.append(e.id)
            case .future, .gone: break
            }
        }
        let c = buildOrder(created, doc: doc)
        ids += c.prefix(Int((Double(c.count) * t).rounded(.up)))
        let dm = buildOrder(demolished, doc: doc)
        ids += dm.prefix(Int((Double(dm.count) * (1 - t)).rounded(.down)))   // top ones go first
        return (ids.sorted(), p)
    }

    /// Work-schedule 4D (WORKSCHEDULE): elements of tasks started by the end of a working day, plus unscheduled ones.
    static func scheduleFrame(day: Int, schedule s: WorkSchedule, timing: [Int: TaskTiming], doc: ArchiDocument) -> [EntityID] {
        let st = Scheduler.states(s, timing: timing, day: day)
        return doc.elements.filter { e in st[e.id].map { $0 != .notStarted } ?? true }.map(\.id).sorted()
    }

    @MainActor static func scheduleVideo(doc: ArchiDocument, settings: RenderSettings, secondsPerDay: Double, camera: Camera?, fps: Int = 30, to url: URL,
                                         progress: @escaping (Double) -> Void) async throws {
        guard let s = Scheduler.load(doc) else { throw CommandError.invalid("No work schedule (WORKSCHEDULE Generate).") }
        let timing = try Scheduler.cpm(s)
        let days = Swift.max(1, timing.values.map(\.ef).max() ?? 1)
        let perDay = Swift.max(1, Int(secondsPerDay * Double(fps)))
        let fmtr = DateFormatter(); fmtr.dateStyle = .medium
        var cache: [[EntityID]: ArchiDocument] = [:]
        try await RenderEngine.writeVideo(doc: stripped(doc, keep: Set(doc.elements.map(\.id))), settings: settings, frames: days * perDay, fps: fps, to: url, setup: { i, b, cam in
            if i == 0, let c = camera { RenderEngine.place(cam, at: c) }
            let ids = scheduleFrame(day: i / perDay, schedule: s, timing: timing, doc: doc)
            let d = cache[ids] ?? stripped(doc, keep: Set(ids))
            cache[ids] = d
            b.update(doc: d, style: "Realistic")
        }, caption: { i in "Day \(i / perDay + 1) of \(days) — \(fmtr.string(from: Scheduler.date(s, workday: i / perDay)))" }, progress: progress)
    }

    @MainActor static func video(doc: ArchiDocument, settings: RenderSettings, secondsPerPhase: Double, camera: Camera?, fps: Int = 30, to url: URL,
                                 progress: @escaping (Double) -> Void) async throws {
        let per = Swift.max(2, Int(secondsPerPhase * Double(fps)))
        let frames = per * Swift.max(doc.phases.count, 1)
        var cache: [[EntityID]: ArchiDocument] = [:]
        try await RenderEngine.writeVideo(doc: stripped(doc, keep: Set(doc.elements.map(\.id))), settings: settings, frames: frames, fps: fps, to: url, setup: { i, b, cam in
            if i == 0, let c = camera { RenderEngine.place(cam, at: c) }
            let fr = frame(i, framesPerPhase: per, doc: doc)
            let d = cache[fr.ids] ?? stripped(doc, keep: Set(fr.ids))
            cache[fr.ids] = d
            b.update(doc: d, style: "Realistic")
        }, caption: { i in
            let p = Swift.min(i / per, Swift.max(doc.phases.count, 1) - 1)
            return doc.phases.indices.contains(p) ? "Phase \(p + 1) of \(doc.phases.count): \(doc.phases[p])" : nil
        }, progress: progress)
    }
}

/// Caption burned into video frames (lower left, white on a dark band).
enum VideoCaption {
    static func draw(_ text: String, in ctx: CGContext, width w: Int, height h: Int) {
        let size = CGFloat(max(12, h / 24))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                 NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attr)
        let tw = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
        ctx.fill(CGRect(x: size * 0.6, y: size * 0.6, width: tw + size, height: size * 1.6))
        ctx.textPosition = CGPoint(x: size * 1.1, y: size * 1.05)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
