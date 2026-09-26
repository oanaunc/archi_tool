// Oanarina Archi Tool — GPL-3.0-or-later
// Sync conflicts (COL-013): cloud folders (iCloud Drive, Dropbox, OneDrive, Nextcloud…) keep both versions of a
// drawing edited on two machines as conflict copies ("House 2.archi", "House (conflicted copy 2026-01-02).archi",
// "House (Oana's conflicted copy).archi", "House-DESKTOP-1.archi"). The copies are merged into the drawing with the
// three-way merge: the common ancestor is the newest version snapshot (VERSIONS) older than both files, else one
// synthesised from what the two versions share, so no object of either side is lost (true conflicts keep ours and
// are reported). Merged copies are moved into "<name>.archi-conflicts/", never deleted.
import Foundation

public enum ConflictCopies {
    /// Conflict copies of `url` in its folder.
    public static func find(for url: URL) -> [URL] {
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension.lowercased()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { f in
            guard f.pathExtension.lowercased() == ext, f.lastPathComponent != url.lastPathComponent else { return false }
            let n = f.deletingPathExtension().lastPathComponent
            guard n.hasPrefix(base), n.count > base.count else { return false }
            let rest = n.dropFirst(base.count)
            let t = rest.trimmingCharacters(in: .whitespaces).lowercased()
            if rest.hasPrefix(" "), Int(t) != nil { return true }                                         // "House 2"
            if t.hasPrefix("(") && t.hasSuffix(")") {
                let inner = t.dropFirst().dropLast()
                return inner.contains("conflict") || Int(inner) != nil                                    // "(conflicted copy …)", "(1)"
            }
            if rest.hasPrefix("-"), t.count > 1, !t.contains(" ") { return true }                          // OneDrive "House-DESKTOP-1"
            return false
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func modified(_ u: URL) -> Date { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date) ?? .distantPast }

    /// Common ancestor of two versions: the latest version snapshot older than both, else the objects both share.
    public static func base(for url: URL, ours: ArchiDocument, theirs: ArchiDocument, theirsDate: Date) -> ArchiDocument {
        let limit = min(modified(url), theirsDate)
        if let v = DocumentVersions.list(for: url).filter({ $0.date <= limit }).last, let d = try? DocumentVersions.load(v.number, documentURL: url) { return d }
        return shared(ours, theirs)
    }

    /// A synthetic ancestor: settings of ours, and only the objects identical in both versions.
    public static func shared(_ a: ArchiDocument, _ b: ArchiDocument) -> ArchiDocument {
        var d = a
        let be = Dictionary(b.entities.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let bl = Dictionary(b.elements.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        d.entities = a.entities.filter { be[$0.id] == $0 }
        d.elements = a.elements.filter { bl[$0.id] == $0 }
        d.layers = a.layers.filter { l in b.layers.contains(l) }
        d.blocks = a.blocks.filter { b.blocks[$0.key] == $0.value }
        d.variables = a.variables.filter { b.variables[$0.key] == $0.value }
        d.levels = a.levels.filter { l in b.levels.contains(l) }
        d.materials = a.materials.filter { m in b.materials.contains(m) }
        d.layouts = a.layouts.filter { l in b.layouts.contains(l) }
        return d
    }

    public struct Resolution { public var merged: ArchiDocument; public var copies: [URL]; public var conflicts: [MergeConflict]; public var taken: Int }

    /// Merges every conflict copy into `ours`. Returns the merged document (nothing is written).
    public static func resolve(_ ours: ArchiDocument, documentURL url: URL, copies: [URL]? = nil) throws -> Resolution {
        var doc = ours
        var conflicts: [MergeConflict] = [], taken = 0
        let list = copies ?? find(for: url)
        var seen = Set<Data>()
        for c in list {
            // Identical copies (the same edit saved twice) are merged once.
            guard let raw = try? Data(contentsOf: c), seen.insert(raw).inserted else { continue }
            let theirs = try DocumentIO.read(c)
            let r = ThreeWayMerge.merge(base: base(for: url, ours: doc, theirs: theirs, theirsDate: modified(c)), ours: doc, theirs: theirs)
            doc = r.doc
            conflicts += r.conflicts
            taken += r.takenFromTheirs
        }
        return Resolution(merged: doc, copies: list, conflicts: conflicts, taken: taken)
    }

    /// Moves merged copies into "<name>.archi-conflicts/".
    @discardableResult
    public static func archive(_ copies: [URL], documentURL url: URL) throws -> URL {
        let dir = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-conflicts", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for c in copies {
            var dest = dir.appendingPathComponent(c.lastPathComponent)
            var n = 1
            while FileManager.default.fileExists(atPath: dest.path) { n += 1; dest = dir.appendingPathComponent(c.deletingPathExtension().lastPathComponent + " #\(n)." + c.pathExtension) }
            try FileManager.default.moveItem(at: c, to: dest)
        }
        return dir
    }

    static var command: CommandDef {
        CommandDef("RESOLVECONFLICTS", aliases: ["SYNCCONFLICTS", "MERGECONFLICTS", "CONFLICTCOPIES"], category: "Collaborate",
                   summary: "Finds the sync-conflict copies of the drawing (iCloud Drive, Dropbox, OneDrive…) and merges them in (three-way, nothing lost; true conflicts keep yours and are listed); merged copies move to <name>.archi-conflicts/.") { ed in
            guard let url = ed.fileURL else { throw CommandError.invalid("Save the drawing first.") }
            let copies = find(for: url)
            guard !copies.isEmpty else { ed.print("No conflict copies of \(url.lastPathComponent)."); return }
            for c in copies { ed.print("Conflict copy: \(c.lastPathComponent)") }
            guard try await ed.getYesNo("Merge \(copies.count) copy(ies) into this drawing?", defaultValue: true) else { return }
            let r: Resolution
            do { r = try resolve(ed.doc, documentURL: url, copies: copies) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            ed.doc = r.merged
            let dir = try? archive(copies, documentURL: url)
            ed.print("Merged \(r.taken) change(s) from \(copies.count) copy(ies); \(r.conflicts.count) conflict(s) kept yours.")
            for c in r.conflicts.prefix(50) { ed.print("  \(c.kind) \(c.key): \(c.reason)") }
            if let dir { ed.print("Copies moved to \(dir.lastPathComponent). Save to keep the merged drawing.") }
        }
    }
}
