// Oanarina Archi Tool — GPL-3.0-or-later
// Permissions (COL-022): a signed access policy next to a central model ("<central>.permissions.json" + ".sig").
// Roles: viewer (reads only — synchronisation sends nothing), editor (edits everything except protected layers it is not
// listed on), admin (everything). The policy is signed with the owner's Ed25519 key (Signatures.swift); the first
// publication pins that public key in the central model (variable POLICYKEY), after which only the same key can change
// the policy and a policy file that is missing, edited by hand or signed by another key locks the model read-only for
// everyone until the owner republishes it. Synchronize with Central enforces the policy on the local changes; rejected
// local objects are never lost: they are written to "<local>.rejected-<time>.archi" next to the local copy.
import Foundation

public struct AccessPolicy: Codable, Hashable {
    public enum Role: String, Codable, CaseIterable { case viewer, editor, admin }
    public var defaultRole: Role = .editor
    /// User name (case-insensitive) → role.
    public var users: [String: Role] = [:]
    /// Protected layer (case-insensitive) → users allowed to change its objects (admins always can).
    public var layers: [String: [String]] = [:]
    public var updated: String = ""
    public var updatedBy: String = ""

    public init(defaultRole: Role = .editor, users: [String: Role] = [:], layers: [String: [String]] = [:]) {
        self.defaultRole = defaultRole; self.users = users; self.layers = layers
    }
    enum CodingKeys: String, CodingKey { case defaultRole, users, layers, updated, updatedBy }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultRole = try c.decodeIfPresent(Role.self, forKey: .defaultRole) ?? .editor
        users = try c.decodeIfPresent([String: Role].self, forKey: .users) ?? [:]
        layers = try c.decodeIfPresent([String: [String]].self, forKey: .layers) ?? [:]
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? ""
    }

    public func role(of user: String) -> Role {
        let u = user.lowercased()
        return users.first { $0.key.lowercased() == u }?.value ?? defaultRole
    }
    /// Users allowed on a protected layer (nil = layer not protected).
    public func allowed(onLayer layer: String) -> [String]? {
        let l = layer.lowercased()
        return layers.first { $0.key.lowercased() == l }?.value
    }
    public func canEdit(_ user: String, layer: String) -> Bool {
        switch role(of: user) {
        case .viewer: return false
        case .admin: return true
        case .editor:
            guard let who = allowed(onLayer: layer) else { return true }
            return who.contains { $0.lowercased() == user.lowercased() }
        }
    }
    public var summary: String {
        var s = "Default role: \(defaultRole.rawValue)"
        for (u, r) in users.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) { s += "\n  \(u): \(r.rawValue)" }
        for (l, who) in layers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) { s += "\n  layer \(l): " + (who.isEmpty ? "admins only" : who.joined(separator: ", ")) }
        return s
    }
}

public enum Permissions {
    public struct PermissionError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }
    public enum State: Equatable {
        /// No policy: everyone edits (borrowing still applies).
        case none
        case valid(AccessPolicy, signer: String)
        /// A pinned policy that does not verify: the model is read-only for everyone.
        case invalid(String)
    }
    public static let keyVariable = "POLICYKEY"

    public static func policyURL(_ central: URL) -> URL { central.deletingLastPathComponent().appendingPathComponent(central.lastPathComponent + ".permissions.json") }

    /// Loads and verifies the policy of a central model. `pinnedKey` is the central model's POLICYKEY.
    public static func load(central: URL, pinnedKey: String?) -> State {
        let url = policyURL(central)
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard let pin = pinnedKey, !pin.isEmpty else {
            return exists ? .invalid("the permissions file is not pinned in the central model") : .none
        }
        guard exists else { return .invalid("the permissions file is missing") }
        let (status, rec) = FileSignature.verifyFile(url, trusted: [pin])
        switch status {
        case .missing: return .invalid("the permissions file is not signed")
        case .invalid: return .invalid("the permissions signature does not verify")
        case .modified: return .invalid("the permissions file was changed after it was signed")
        case .valid(let signer, let trusted):
            guard trusted else { return .invalid("the permissions file is signed by \(signer), not by the policy owner") }
            guard let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(AccessPolicy.self, from: d) else {
                return .invalid("the permissions file cannot be read")
            }
            _ = rec
            return .valid(p, signer: signer)
        }
    }

    /// Signs and publishes a policy next to the central model; the first publication pins the key in the central model.
    public static func publish(_ policy: AccessPolicy, central: URL, key: FileSignature.Key, now: Date = Date()) throws {
        try CentralModel.withLock(central) {
            var doc = try ArchiFile.decode(Data(contentsOf: central))
            if let pin = doc.variable(keyVariable), !pin.isEmpty, pin != key.publicKey {
                throw PermissionError(message: "Only the policy owner can change the permissions of this central model (your key is not the pinned POLICYKEY).")
            }
            var p = policy
            p.updated = ISO8601DateFormatter().string(from: now); p.updatedBy = key.signer
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = policyURL(central)
            try enc.encode(p).write(to: url, options: .atomic)
            try FileSignature.signFile(url, key: key)
            if doc.variable(keyVariable) != key.publicKey {
                doc.setVariable(keyVariable, key.publicKey)
                try ArchiFile.encode(doc).write(to: central, options: .atomic)
            }
        }
    }

    /// Restricts `local`'s changes against `base` to what `user` may do. Returns the permitted document and the rejected
    /// objects with the reason.
    public static func enforce(local: ArchiDocument, base: ArchiDocument, user: String, policy: AccessPolicy,
                               reason: String? = nil) -> (doc: ArchiDocument, rejected: [(id: EntityID, reason: String)]) {
        var rejected: [(EntityID, String)] = []
        let role = policy.role(of: user)
        if role == .admin { return (local, []) }
        var mine = local
        let baseEnt = Dictionary(base.entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let baseEl = Dictionary(base.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func why(_ layer: String) -> String {
            if let r = reason { return r }
            return role == .viewer ? "\(user) is a viewer" : "layer \(layer) is protected"
        }
        // Drawing objects.
        var ents: [Entity] = []
        for e in mine.entities {
            if let b = baseEnt[e.id] {
                if b != e, !(policy.canEdit(user, layer: b.layer) && policy.canEdit(user, layer: e.layer)) { ents.append(b); rejected.append((e.id, why(b.layer))) }
                else { ents.append(e) }
            } else if policy.canEdit(user, layer: e.layer) { ents.append(e) } else { rejected.append((e.id, why(e.layer))) }
        }
        let entIDs = Set(mine.entities.map(\.id))
        for b in base.entities where !entIDs.contains(b.id) && !policy.canEdit(user, layer: b.layer) { ents.append(b); rejected.append((b.id, why(b.layer))) }
        mine.entities = ents
        // Building elements.
        var els: [BIMElement] = []
        for e in mine.elements {
            if let b = baseEl[e.id] {
                if b != e, !(policy.canEdit(user, layer: b.layer) && policy.canEdit(user, layer: e.layer)) { els.append(b); rejected.append((e.id, why(b.layer))) }
                else { els.append(e) }
            } else if policy.canEdit(user, layer: e.layer) { els.append(e) } else { rejected.append((e.id, why(e.layer))) }
        }
        let elIDs = Set(mine.elements.map(\.id))
        for b in base.elements where !elIDs.contains(b.id) && !policy.canEdit(user, layer: b.layer) { els.append(b); rejected.append((b.id, why(b.layer))) }
        mine.elements = els
        // Viewers change nothing else either; editors cannot redefine protected layers.
        if role == .viewer {
            var d = base
            d.entities = mine.entities; d.elements = mine.elements
            for k in CentralModel.localVariables { d.variables[k] = local.variables[k] }
            d.currentLayer = local.currentLayer; d.currentLevel = local.currentLevel
            return (d, rejected)
        }
        for (i, l) in mine.layers.enumerated() where policy.allowed(onLayer: l.name) != nil && !policy.canEdit(user, layer: l.name) {
            if let b = base.layers.first(where: { $0.name == l.name }) { mine.layers[i] = b }
        }
        for b in base.layers where policy.allowed(onLayer: b.name) != nil && !policy.canEdit(user, layer: b.name) && !mine.layers.contains(where: { $0.name == b.name }) {
            mine.layers.append(b)
        }
        return (mine, rejected)
    }

    /// Writes the local versions of rejected objects to "<local>.rejected-<time>.archi" so no work is lost.
    @discardableResult
    public static func saveRejected(_ ids: [EntityID], from local: ArchiDocument, localURL: URL, now: Date = Date()) throws -> URL? {
        let set = Set(ids)
        var d = local
        d.entities = local.entities.filter { set.contains($0.id) }
        d.elements = local.elements.filter { set.contains($0.id) }
        guard !d.entities.isEmpty || !d.elements.isEmpty else { return nil }
        for k in CentralModel.localVariables { d.variables[k] = nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let name = localURL.deletingPathExtension().lastPathComponent + ".rejected-" + f.string(from: now) + "." + ArchiFile.fileExtension
        let url = localURL.deletingLastPathComponent().appendingPathComponent(name)
        try ArchiFile.encode(d).write(to: url, options: .atomic)
        return url
    }

    /// CENTRAL Permissions: Show, Role (viewer/editor/admin per user), Layer (protect a layer for listed users), Default
    /// role, Check the selection. Changes are signed with the user's key (SIGNKEY); the first publication pins it.
    @MainActor static func run(_ ed: Editor) async throws {
            let k = try await ed.getKeyword("Enter an option [Show/Role/Layer/Default/Check]", ["Show", "Role", "Layer", "Default", "Check"], defaultValue: "Show") ?? "Show"
            let user = ed.doc.variable("USERNAME") ?? NSUserName()
            let central: URL
            if let p = ed.doc.variable("CENTRALFILE"), !p.isEmpty { central = URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
            else if let u = ed.fileURL { central = u }
            else { throw CommandError.invalid("Open a central model or a local copy of one first.") }
            func pinned() -> String? {
                if ed.fileURL == central { return ed.doc.variable(keyVariable) }
                return (try? ArchiFile.decode(Data(contentsOf: central)))?.variable(keyVariable)
            }
            let state = load(central: central, pinnedKey: pinned())
            var policy: AccessPolicy
            switch state {
            case .none: policy = AccessPolicy()
            case .valid(let p, _): policy = p
            case .invalid: policy = AccessPolicy(defaultRole: .viewer)
            }
            @MainActor func publishNow() throws {
                let key: FileSignature.Key
                do { key = try FileSignature.loadKey(FileSignature.defaultKeyURL) } catch { throw CommandError.invalid("Create a signing key first (SIGNKEY).") }
                do { try publish(policy, central: central, key: key) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
                if ed.fileURL == central { ed.doc.setVariable(keyVariable, key.publicKey) }
                ed.print("Permissions published and signed by \(key.signer).\n" + policy.summary)
            }
            switch k {
            case "Role":
                guard let name = try await ed.getWord("User name"), !name.isEmpty else { return }
                let r = try await ed.getKeyword("Role [Viewer/Editor/Admin]", ["Viewer", "Editor", "Admin"], defaultValue: "Editor") ?? "Editor"
                policy.users[name] = AccessPolicy.Role(rawValue: r.lowercased()) ?? .editor
                try publishNow()
            case "Layer":
                guard let layer = try await ed.getWord("Layer to protect"), !layer.isEmpty else { return }
                let who = try await ed.getString("Users allowed (comma separated; * removes the protection)", defaultValue: "") ?? ""
                if who.trimmingCharacters(in: .whitespaces) == "*" { policy.layers = policy.layers.filter { $0.key.lowercased() != layer.lowercased() } }
                else { policy.layers[layer] = who.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                try publishNow()
            case "Default":
                let r = try await ed.getKeyword("Default role [Viewer/Editor/Admin]", ["Viewer", "Editor", "Admin"], defaultValue: "Editor") ?? "Editor"
                policy.defaultRole = AccessPolicy.Role(rawValue: r.lowercased()) ?? .editor
                try publishNow()
            case "Check":
                let ids = try await ed.getSelection("Select objects to check")
                var denied: [EntityID] = []
                for id in ids {
                    let layer = ed.doc.entity(id)?.layer ?? ed.doc.elements.first { $0.id == id }?.layer ?? "0"
                    if case .invalid = state { denied.append(id) } else if case .valid(let p, _) = state, !p.canEdit(user, layer: layer) { denied.append(id) }
                }
                ed.print(denied.isEmpty ? "\(user) may change all \(ids.count) selected object(s)." : "\(user) may not change \(denied.count) of \(ids.count) object(s): " + denied.map { "#\($0)" }.joined(separator: ", "))
                ed.selection = Set(denied)
            default:
                switch state {
                case .none: ed.print("No permissions: everyone edits (element borrowing still applies).")
                case .valid(let p, let s): ed.print("Permissions signed by \(s)" + (p.updated.isEmpty ? "" : " on \(p.updated)") + ". You (\(user)) are \(p.role(of: user).rawValue).\n" + p.summary)
                case .invalid(let why): ed.print("LOCKED: \(why). The model is read-only until the policy owner republishes the permissions.")
                }
            }
    }
}
