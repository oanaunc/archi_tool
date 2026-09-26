// Oanarina Archi Tool — GPL-3.0-or-later
// Background, multithreaded regeneration (SYS-017): the 3D meshes of building elements and solids are built
// concurrently (the shared wall-join context is computed once and only read afterwards), in the same order and with the
// same result as MeshBuilder.build; a regenerator runs rebuilds off the main thread, coalescing requests so only the
// latest document state is delivered (a newer edit supersedes a rebuild still in progress). Measured on 720 elements the
// wall-join context dominates (≈ 55 %), so the gain is responsiveness (nothing blocks the main thread) rather than speed.
import Foundation

public enum ParallelMesh {
    /// Same groups as `MeshBuilder.build(doc:)`, computed concurrently per element / solid.
    public static func build(doc fullDoc: ArchiDocument, threads: Int = ProcessInfo.processInfo.activeProcessorCount) -> [MeshGroup] {
        let doc = ModelSets.visibleModel(BIMUpdaters.regenerated(fullDoc))
        let ctx = BIMContext(doc: doc)
        let phased = Phasing.isActive(doc)
        let pf = Phasing.filter(doc)
        func shown(_ props: [String: String]) -> Bool {
            guard phased else { return true }
            let st = Phasing.status(props, doc: doc)
            if st == .demolished { return pf == .demolition }
            return Phasing.visible(st, pf)
        }
        let els = doc.elements.filter { doc.isVisible(layer: $0.layer) && shown($0.props) && $0.props["hasParts"] != "1" && Assemblies.shown($0, doc: doc) }
        let ents = doc.entities.filter { doc.isVisible(layer: $0.layer) && shown($0.props) }
        let n = els.count + ents.count
        var results = [[MeshGroup]](repeating: [], count: n)
        if threads <= 1 || n < 8 {
            for i in 0..<n { results[i] = i < els.count ? MeshBuilder.groups(els[i], ctx: ctx) : MeshBuilder.groups(for: ents[i - els.count], doc: doc) }
        } else {
            // Work in chunks so small elements do not pay a dispatch each.
            let chunk = max(1, n / (threads * 8))
            let chunks = (n + chunk - 1) / chunk
            results.withUnsafeMutableBufferPointer { buf in
                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                    for i in (c * chunk)..<min(n, (c + 1) * chunk) {
                        buf[i] = i < els.count ? MeshBuilder.groups(els[i], ctx: ctx) : MeshBuilder.groups(for: ents[i - els.count], doc: doc)
                    }
                }
            }
        }
        var out = results.flatMap { $0 }
        if doc.variable("DATUMS3D") == "1" { out += MeshBuilder.datumGroups(doc: doc) }
        return out
    }
}

/// Rebuilds meshes in the background; `request` may be called for every edit — only the newest state is built next and
/// delivered (with its generation number) on the given queue.
public final class BackgroundRegenerator {
    private let queue = DispatchQueue(label: "org.oanarina.archi.regenerate", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: (doc: ArchiDocument, generation: Int)?
    private var running = false
    private var generation = 0
    private let deliver: DispatchQueue
    public private(set) var lastDelivered = 0

    public init(deliverOn: DispatchQueue = .main) { deliver = deliverOn }

    /// Schedules a rebuild of `doc`; returns its generation number.
    @discardableResult
    public func request(_ doc: ArchiDocument, completion: @escaping ([MeshGroup], Int) -> Void) -> Int {
        lock.lock()
        generation += 1
        let g = generation
        pending = (doc, g)
        let start = !running
        if start { running = true }
        lock.unlock()
        if start { queue.async { self.loop(completion) } }
        return g
    }

    private func loop(_ completion: @escaping ([MeshGroup], Int) -> Void) {
        while true {
            lock.lock()
            guard let job = pending else { running = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            let groups = ParallelMesh.build(doc: job.doc)
            lock.lock()
            let superseded = pending != nil   // a newer edit arrived: skip delivering this one
            lock.unlock()
            if !superseded {
                deliver.async {
                    self.lastDelivered = job.generation
                    completion(groups, job.generation)
                }
            }
        }
    }
}
