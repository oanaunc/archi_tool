// Oanarina Archi Tool — GPL-3.0-or-later
// Memory budget (SYS-019): an estimate of the drawing's memory by kind (drafting objects, building elements, 3D meshes,
// point clouds, blocks, sheets, raster images), the process footprint (Mach task_vm_info.phys_footprint), a budget
// (MEMORYBUDGET in MB, default a quarter of the Mac's memory) with advice on what to reduce, and a point-cloud import limit
// derived from the budget so large scans are sampled to fit instead of exhausting memory.
import Foundation

public enum MemoryBudget {
    public struct Estimate: Hashable {
        public var bytes: [String: Int]
        public var total: Int { bytes.values.reduce(0, +) }
        public var counts: [String: Int]
    }

    static func entityBytes(_ e: Entity) -> Int {
        var b = MemoryLayout<Entity>.stride + e.props.reduce(0) { $0 + 48 + $1.key.utf8.count + $1.value.utf8.count } + e.layer.utf8.count
        switch e.geometry {
        case .polyline(let p): b += p.vertices.count * MemoryLayout<PolyVertex>.stride
        case .spline(let s): b += (s.controlPoints.count + s.fitPoints.count) * 16 + s.knots.count * 8
        case .hatch(let h): b += h.loops.reduce(0) { $0 + $1.count * MemoryLayout<PolyVertex>.stride }
        case .solid(let s): b += s.meshVertices.count * 24 + s.meshTriangles.count * 8 + s.profile.count * 16
        case .text(let t): b += t.content.utf8.count
        case .table(let t): b += t.cells.reduce(0) { $0 + $1.reduce(0) { $0 + $1.utf8.count + 16 } }
        default: break
        }
        return b
    }

    /// Memory estimate of a drawing.
    public static func estimate(_ doc: ArchiDocument, imageRoot: URL? = nil) -> Estimate {
        var bytes: [String: Int] = [:], counts: [String: Int] = [:]
        for e in doc.entities {
            let k: String
            switch e.geometry {
            case .point: k = e.layer.uppercased().contains("POINTCLOUD") || e.props["intensity"] != nil || e.props["class"] != nil ? "Point clouds" : "Drafting"
            case .solid: k = "3D solids and meshes"
            case .image(let im):
                k = "Raster images"
                let url = URL(fileURLWithPath: (im.path as NSString).expandingTildeInPath, relativeTo: imageRoot)
                if let px = (try? Data(contentsOf: url, options: .alwaysMapped)).flatMap({ ImageHeader.size($0) }) { bytes[k, default: 0] += px.width * px.height * 4 }
            default: k = "Drafting"
            }
            bytes[k, default: 0] += entityBytes(e); counts[k, default: 0] += 1
        }
        for el in doc.elements {
            bytes["Building elements", default: 0] += MemoryLayout<BIMElement>.stride + el.props.reduce(0) { $0 + 48 + $1.key.utf8.count + $1.value.utf8.count } + 256
            counts["Building elements", default: 0] += 1
        }
        // 3D view: roughly 12 triangles per element face set, 32 bytes per vertex in GPU/CPU copies.
        if !doc.elements.isEmpty { bytes["3D view meshes (est.)", default: 0] += doc.elements.count * 40 * 3 * 32 }
        for (_, b) in doc.blocks { bytes["Blocks", default: 0] += b.entities.reduce(0) { $0 + entityBytes($1) }; counts["Blocks", default: 0] += 1 }
        for l in doc.layouts { bytes["Sheets", default: 0] += l.entities.reduce(0) { $0 + entityBytes($1) } + l.viewports.count * 128; counts["Sheets", default: 0] += 1 }
        bytes["Undo history (est.)"] = 0
        return Estimate(bytes: bytes, counts: counts)
    }

    /// Physical memory footprint of this process (bytes), as Activity Monitor's "Memory" column.
    public static func processFootprint() -> Int? {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : nil
        #else
        return nil
        #endif
    }

    /// Budget in bytes: MEMORYBUDGET (MB) or a quarter of the physical memory.
    public static func budget(_ doc: ArchiDocument) -> Int {
        if let v = Double(doc.variable("MEMORYBUDGET") ?? ""), v > 0 { return Int(v * 1_048_576) }
        return Int(ProcessInfo.processInfo.physicalMemory / 4)
    }

    /// Largest number of points a point-cloud import may add: POINTLIMIT when set, else 200 000 or less when a quarter of
    /// the remaining budget (at about 400 bytes per point object) holds fewer (never below 20 000).
    public static func pointLimit(_ doc: ArchiDocument) -> Int {
        if let v = Int(doc.variable("POINTLIMIT") ?? ""), v > 0 { return v }
        let free = max(0, budget(doc) - estimate(doc).total)
        return max(20_000, min(200_000, free / 4 / 400))
    }

    /// Suggestions for the largest parts of the estimate when it exceeds the budget.
    public static func advice(_ e: Estimate, budget: Int) -> [String] {
        guard e.total > budget else { return [] }
        var out: [String] = []
        for (k, v) in e.bytes.sorted(by: { $0.value > $1.value }).prefix(3) where v > budget / 10 {
            switch k {
            case "Point clouds": out.append("Point clouds use \(mb(v)): sample them (import with a voxel size or lower POINTLIMIT) or keep the scan as an E57/LAS reference.")
            case "3D solids and meshes": out.append("3D meshes use \(mb(v)): decimate imported meshes (MESHDECIMATE) or remove hidden detail.")
            case "Raster images": out.append("Images use \(mb(v)): use smaller or compressed images, or detach unused ones.")
            case "Blocks": out.append("Block definitions use \(mb(v)): PURGE unused blocks.")
            default: out.append("\(k) use \(mb(v)).")
            }
        }
        return out
    }

    static func mb(_ b: Int) -> String { "\(fmt(Double(b) / 1_048_576, 1)) MB" }

    static var command: CommandDef {
        CommandDef("MEMORYREPORT", aliases: ["MEMUSAGE", "MEMSTATS", "MEMINFO"], category: "Tools",
                   summary: "Memory estimate of the drawing by kind, the app's memory footprint and the budget (MEMORYBUDGET MB) with advice; POINTLIMIT follows the budget.", modifies: false) { ed in
            let e = estimate(ed.doc, imageRoot: ed.fileURL?.deletingLastPathComponent())
            for (k, v) in e.bytes.sorted(by: { $0.value > $1.value }) where v > 0 {
                ed.print("  \(k): \(mb(v))" + (e.counts[k].map { " (\($0))" } ?? ""))
            }
            let b = budget(ed.doc)
            ed.print("Drawing estimate \(mb(e.total)) of a \(mb(b)) budget" + (processFootprint().map { "; the app uses \(mb($0))" } ?? "") + ".")
            for a in advice(e, budget: b) { ed.print("• " + a) }
            ed.print("Point cloud imports are limited to \(pointLimit(ed.doc)) points.")
        }
    }
}
