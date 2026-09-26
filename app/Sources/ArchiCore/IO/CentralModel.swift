// Oanarina Archi Tool — GPL-3.0-or-later
// Work sharing (COL-015 element borrowing, COL-017 central / local model): a central .archi on a shared folder, one
// local copy per user (variable CENTRALFILE, base snapshot "<local>.archi-base" = central at the last sync). Users borrow
// elements (ownership table "<central>.owners.json"); Synchronize with Central merges base / central / local three-way
// under a lock file: local edits to objects owned by someone else are rejected (the central version stays), other local
// changes are applied, concurrent edits of the same object keep the central version (first to sync wins) and are
// reported, new objects that collide by id are renumbered. The merged model is written to central and becomes the local
// model and the new base; borrowed elements are relinquished unless asked to keep them.
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CentralModel {
    public struct CentralError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    public struct SyncResult {
        public var doc: ArchiDocument
        /// Local changes rejected because another user owns the object: (id, owner).
        public var rejected: [(id: EntityID, owner: String)] = []
        public var conflicts: [MergeConflict] = []
        /// Objects of this user that were renumbered in the merge (old → new id).
        public var renumbered: [EntityID: EntityID] = [:]
        /// Local changes refused by the permissions policy: (id, reason).
        public var denied: [(id: EntityID, reason: String)] = []
        /// Where the refused local objects were saved (nothing is lost).
        public var rejectedFile: URL?
        public var applied = 0
        public var received = 0
    }

    /// Variables that belong to one user's local copy and never travel to central.
    public static let localVariables: Set<String> = ["USERNAME", "CENTRALFILE", "TRACEPREVLAYER"]

    public static func ownersURL(_ central: URL) -> URL { central.deletingLastPathComponent().appendingPathComponent(central.lastPathComponent + ".owners.json") }
    public static func lockURL(_ central: URL) -> URL { central.deletingLastPathComponent().appendingPathComponent(central.lastPathComponent + ".lock") }
    public static func baseURL(_ local: URL) -> URL { local.deletingLastPathComponent().appendingPathComponent(local.lastPathComponent + "-base") }

    /// Runs `body` holding the central lock (exclusive create; a lock older than `stale` seconds is broken).
    static func withLock<T>(_ central: URL, stale: TimeInterval = 120, _ body: () throws -> T) throws -> T {
        let path = lockURL(central).path
        var fd: Int32 = -1
        for attempt in 0..<50 {
            fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 { break }
            if let a = try? FileManager.default.attributesOfItem(atPath: path), let d = a[.modificationDate] as? Date, Date().timeIntervalSince(d) > stale {
                try? FileManager.default.removeItem(atPath: path); continue
            }
            if attempt == 49 { throw CentralError(message: "The central model is locked by another synchronisation (\(path)).") }
            usleep(100_000)
        }
        let info = "\(ProcessInfo.processInfo.processIdentifier) \(NSUserName())\n"
        _ = info.withCString { write(fd, $0, strlen($0)) }
        close(fd)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try body()
    }

    public static func owners(central: URL) -> [EntityID: String] {
        guard let d = try? Data(contentsOf: ownersURL(central)), let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        var out: [EntityID: String] = [:]
        for (k, v) in o { if let id = Int(k) { out[id] = v } }
        return out
    }
    static func writeOwners(_ o: [EntityID: String], central: URL) throws {
        let obj = Dictionary(uniqueKeysWithValues: o.map { ("\($0.key)", $0.value) })
        try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]).write(to: ownersURL(central), options: .atomic)
    }

    /// Creates a local copy of the central model for `user`.
    @discardableResult
    public static func createLocal(central: URL, local: URL, user: String) throws -> ArchiDocument {
        guard FileManager.default.fileExists(atPath: central.path) else { throw CentralError(message: "No central model at \(central.path).") }
        var d = try ArchiFile.decode(Data(contentsOf: central))
        try ArchiFile.encode(d).write(to: baseURL(local), options: .atomic)
        d.setVariable("CENTRALFILE", central.path)
        d.setVariable("USERNAME", user)
        try ArchiFile.encode(d).write(to: local, options: .atomic)
        return d
    }

    /// Makes a document the central model (writes it and an empty ownership table).
    public static func createCentral(_ doc: ArchiDocument, at central: URL) throws {
        var d = doc
        for k in localVariables { d.variables[k] = nil }
        try ArchiFile.encode(d).write(to: central, options: .atomic)
        try writeOwners([:], central: central)
    }

    /// Takes ownership of objects. Objects owned by another user are denied.
    public static func borrow(_ ids: [EntityID], user: String, central: URL) throws -> (granted: [EntityID], denied: [(id: EntityID, owner: String)]) {
        try withLock(central) {
            var o = owners(central: central)
            var granted: [EntityID] = [], denied: [(EntityID, String)] = []
            for id in ids {
                if let who = o[id], who != user { denied.append((id, who)) } else { o[id] = user; granted.append(id) }
            }
            try writeOwners(o, central: central)
            return (granted, denied)
        }
    }

    /// Gives back objects (all of the user's when `ids` is nil). Returns how many were released.
    @discardableResult
    public static func relinquish(_ ids: [EntityID]? = nil, user: String, central: URL) throws -> Int {
        try withLock(central) {
            var o = owners(central: central)
            let mine = o.filter { $0.value == user }.map(\.key)
            let release = ids.map { Set($0).intersection(mine) } ?? Set(mine)
            for id in release { o[id] = nil }
            try writeOwners(o, central: central)
            return release.count
        }
    }

    /// Synchronises a local model with central (see the file header). Writes central, the base snapshot and returns the
    /// merged local model.
    public static func sync(local: ArchiDocument, localURL: URL, user: String, relinquishAll: Bool = true) throws -> SyncResult {
        guard let cpath = local.variable("CENTRALFILE"), !cpath.isEmpty else { throw CentralError(message: "This drawing is not a local copy of a central model (CENTRAL Local).") }
        let central = URL(fileURLWithPath: (cpath as NSString).expandingTildeInPath)
        return try withLock(central) {
            let theirsCentral = try ArchiFile.decode(Data(contentsOf: central))
            let base = (try? Data(contentsOf: baseURL(localURL))).flatMap { try? ArchiFile.decode($0) } ?? theirsCentral
            let own = owners(central: central)
            var mine = local
            var res = SyncResult(doc: local)
            for k in localVariables { mine.variables[k] = base.variables[k] }
            // Reject local changes to objects owned by other users (restore the base version).
            let baseEnt = Dictionary(base.entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let baseEl = Dictionary(base.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            func ownedByOther(_ id: EntityID) -> String? { own[id].flatMap { $0 != user ? $0 : nil } }
            for i in mine.entities.indices {
                let e = mine.entities[i]
                if let b = baseEnt[e.id], b != e, let who = ownedByOther(e.id) { mine.entities[i] = b; res.rejected.append((e.id, who)) }
            }
            for i in mine.elements.indices {
                let e = mine.elements[i]
                if let b = baseEl[e.id], b != e, let who = ownedByOther(e.id) { mine.elements[i] = b; res.rejected.append((e.id, who)) }
            }
            // Deleted objects owned by others come back.
            let mineIDs = Set(mine.entities.map(\.id) + mine.elements.map(\.id))
            for (id, b) in baseEnt where !mineIDs.contains(id) { if let who = ownedByOther(id) { mine.entities.append(b); res.rejected.append((id, who)) } }
            for (id, b) in baseEl where !mineIDs.contains(id) { if let who = ownedByOther(id) { mine.elements.append(b); res.rejected.append((id, who)) } }
            // Permissions policy (signed, pinned in central): restrict the local changes to what this user may do.
            mine.variables[Permissions.keyVariable] = base.variables[Permissions.keyVariable]
            switch Permissions.load(central: central, pinnedKey: theirsCentral.variable(Permissions.keyVariable)) {
            case .none: break
            case .valid(let p, _):
                let r = Permissions.enforce(local: mine, base: base, user: user, policy: p)
                mine = r.doc; res.denied = r.rejected
            case .invalid(let why):
                let r = Permissions.enforce(local: mine, base: base, user: user, policy: AccessPolicy(defaultRole: .viewer), reason: "permissions locked: \(why)")
                mine = r.doc; res.denied = r.rejected
            }
            let refused = res.rejected.map(\.id) + res.denied.map(\.id)
            if !refused.isEmpty { res.rejectedFile = try? Permissions.saveRejected(refused, from: local, localURL: localURL) }
            // Central is "ours" in the merge: shared objects keep their ids; local additions that collide are renumbered.
            let m = ThreeWayMerge.merge(base: base, ours: theirsCentral, theirs: mine)
            res.conflicts = m.conflicts
            res.renumbered = m.renumbered
            res.applied = m.takenFromTheirs
            res.received = DocumentCompare.compare(base, theirsCentral).differences.count
            var merged = m.doc
            try ArchiFile.encode(merged).write(to: central, options: .atomic)
            try ArchiFile.encode(merged).write(to: baseURL(localURL), options: .atomic)
            // Back to the local copy: local variables and current layer/level.
            for k in localVariables { merged.variables[k] = local.variables[k] }
            if merged.layer(named: local.currentLayer) != nil { merged.currentLayer = local.currentLayer }
            if merged.level(local.currentLevel) != nil { merged.currentLevel = local.currentLevel }
            // Ownership: auto-borrowed = objects this user changed; released unless kept.
            var o = own
            if relinquishAll { for (id, who) in o where who == user { o[id] = nil } }
            try writeOwners(o, central: central)
            res.doc = merged
            return res
        }
    }

    static var command: CommandDef {
        CommandDef("CENTRAL", aliases: ["WORKSHARING", "SYNCCENTRAL", "STC"], category: "Collaborate",
                   summary: "Work sharing with a central model: Create (make this drawing the central file), Local (open a local copy of a central file), Sync (synchronise with central, optionally keeping borrowed elements), Borrow / Relinquish selected elements, Owners (who owns what), Permissions (signed access policy: viewer/editor/admin roles and protected layers, enforced on Sync; refused changes are saved beside the local copy).") { ed in
            let k = try await ed.getKeyword("Enter an option [Create/Local/Sync/Borrow/Relinquish/Owners/Permissions]", ["Create", "Local", "Sync", "Borrow", "Relinquish", "Owners", "Permissions"], defaultValue: "Sync") ?? "Sync"
            if k == "Permissions" { try await Permissions.run(ed); return }
            let user = ed.doc.variable("USERNAME") ?? NSUserName()
            @MainActor func central() throws -> URL {
                guard let p = ed.doc.variable("CENTRALFILE"), !p.isEmpty else { throw CommandError.invalid("This drawing is not a local copy of a central model (CENTRAL Local).") }
                return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            }
            do {
                switch k {
                case "Create":
                    let url = try await IOCommands.path(ed, "Central model file name (.archi on a shared folder)")
                    try createCentral(ed.doc, at: url)
                    ed.print("Central model written to \(url.path). Each user opens a local copy with CENTRAL Local.")
                case "Local":
                    let c = try await IOCommands.path(ed, "Central model file")
                    let l = try await IOCommands.path(ed, "Local copy file name")
                    let name = try await ed.getWord("User name <\(user)>", defaultValue: user) ?? user
                    let d = try createLocal(central: c, local: l, user: name)
                    ed.replaceDocument(d, url: l)
                    ed.print("Local copy \(l.lastPathComponent) of \(c.lastPathComponent) for \(name).")
                case "Sync":
                    guard let local = ed.fileURL else { throw CommandError.invalid("Save the local copy first.") }
                    let keep = try await ed.getYesNo("Keep borrowed elements?", defaultValue: false)
                    let r = try sync(local: ed.doc, localURL: local, user: user, relinquishAll: !keep)
                    ed.doc = r.doc
                    ed.print("Synchronised with central: \(r.applied) local change(s) sent, \(r.received) received, \(r.conflicts.count) conflict(s) (central kept), \(r.rejected.count + r.denied.count) rejected.")
                    for x in r.rejected { ed.print("  #\(x.id) is owned by \(x.owner): your change was not saved.") }
                    for x in r.denied { ed.print("  #\(x.id) not sent: \(x.reason).") }
                    if let f = r.rejectedFile { ed.print("  Your refused changes are kept in \(f.lastPathComponent).") }
                    for c in r.conflicts { ed.print("  conflict \(c.kind) \(c.key): \(c.reason)") }
                    for (a, b) in r.renumbered { ed.print("  your new object #\(a) is now #\(b).") }
                    ed.selection = Set(r.rejected.map(\.id) + r.denied.map(\.id)).filter { ed.doc.contains($0) }
                case "Borrow":
                    let ids = try await ed.getSelection("Select elements to borrow")
                    let r = try borrow(ids, user: user, central: try central())
                    ed.print("Borrowed \(r.granted.count) object(s)." + (r.denied.isEmpty ? "" : " \(r.denied.count) owned by others: " + r.denied.map { "#\($0.id) (\($0.owner))" }.joined(separator: ", ")))
                case "Relinquish":
                    let n = try relinquish(user: user, central: try central())
                    ed.print("Relinquished \(n) object(s).")
                default:
                    let o = owners(central: try central())
                    if o.isEmpty { ed.print("No borrowed elements.") }
                    for (who, ids) in Dictionary(grouping: o, by: \.value).sorted(by: { $0.key < $1.key }) {
                        ed.print("\(who): " + ids.map { "#\($0.key)" }.sorted().joined(separator: ", "))
                    }
                }
            } catch let e as CommandError { throw e }
            catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }
}
