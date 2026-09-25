// Oanarina Archi Tool — GPL-3.0-or-later
// Git-friendly projects (COL-004): the ".archit" text format writes one line per layer, block, material, level, drawing
// object and building element (sorted by name / id; compact key-sorted JSON), so a line-based diff or a git merge maps
// exactly onto model objects. `ArchiText.diff` lists every added / removed / modified object between two versions.
// `GitVersioning` drives the git command line (IfcGit-style): init, commit, log, show a revision as a document, and diff
// two revisions object by object.
import Foundation

public enum ArchiText {
    public static let fileExtension = "archit"
    public static let magic = "#archi-text 1"

    /// Kinds of lines (the key is "<kind> <name or id>").
    static let tables: [(key: String, kind: String)] = [("layers", "layer"), ("materials", "material"), ("levels", "level"), ("wallTypes", "walltype"),
                                                         ("openingTypes", "openingtype"), ("slabTypes", "slabtype"), ("layouts", "layout"), ("namedViews", "view")]

    static func compact(_ o: Any) throws -> String {
        let d = try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: d, as: UTF8.self)
    }

    /// One line per object; the header line holds the remaining document settings.
    public static func encode(_ doc: ArchiDocument) throws -> String {
        let full = try ArchiFile.encode(doc)
        guard let env = try JSONSerialization.jsonObject(with: full) as? [String: Any], var d = env["document"] as? [String: Any] else {
            throw ArchiFile.FileError.corrupt("cannot encode")
        }
        var lines: [String] = [magic]
        let entities = d.removeValue(forKey: "entities") as? [[String: Any]] ?? []
        let elements = d.removeValue(forKey: "elements") as? [[String: Any]] ?? []
        let blocks = d.removeValue(forKey: "blocks") as? [String: Any] ?? [:]
        let variables = d.removeValue(forKey: "variables") as? [String: Any] ?? [:]
        var tableLines: [String] = []
        for t in tables {
            guard let arr = d.removeValue(forKey: t.key) as? [[String: Any]] else { continue }
            // Keep table order: the index is part of the key so reordering shows as a change.
            for (i, o) in arr.enumerated() {
                let name = (o["name"] as? String) ?? (o["id"].map { "\($0)" }) ?? "\(i)"
                tableLines.append("\(t.kind) \(String(format: "%05d", i)) \(escapeKey(name)) \(try compact(o))")
            }
        }
        lines.append("header " + (try compact(d)))
        lines += tableLines
        for (k, v) in variables.sorted(by: { $0.key < $1.key }) { lines.append("var \(escapeKey(k)) \(try compact(v))") }
        for (k, v) in blocks.sorted(by: { $0.key < $1.key }) { lines.append("block \(escapeKey(k)) \(try compact(v))") }
        for o in entities.sorted(by: { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }) { lines.append("entity \(o["id"] as? Int ?? 0) \(try compact(o))") }
        for o in elements.sorted(by: { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }) { lines.append("element \(o["id"] as? Int ?? 0) \(try compact(o))") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Keys may not contain spaces: percent-encode them.
    static func escapeKey(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:@+()[]"))) ?? s
    }

    /// Splits "kind key json" (tables: "kind index key json").
    static func split(_ line: Substring) -> (kind: String, key: String, json: Substring)? {
        guard let s1 = line.firstIndex(of: " ") else { return nil }
        let kind = String(line[..<s1])
        if kind == "header" { return (kind, "", line[line.index(after: s1)...]) }
        var rest = line[line.index(after: s1)...]
        var key = ""
        if tables.contains(where: { $0.kind == kind }) {
            guard let s2 = rest.firstIndex(of: " ") else { return nil }
            key = String(rest[..<s2]) + " "
            rest = rest[rest.index(after: s2)...]
        }
        guard let s3 = rest.firstIndex(of: " ") else { return nil }
        key += String(rest[..<s3])
        return (kind, key, rest[rest.index(after: s3)...])
    }

    public static func decode(_ text: String) throws -> ArchiDocument {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.first.map({ $0.hasPrefix("#archi-text") }) == true else { throw ArchiFile.FileError.notAnArchiFile }
        lines.removeFirst()
        var doc: [String: Any] = [:]
        var entities: [Any] = [], elements: [Any] = [], blocks: [String: Any] = [:], variables: [String: Any] = [:]
        var tableRows: [String: [(String, Any)]] = [:]
        for l in lines {
            // Git conflict markers make the file unreadable on purpose.
            if l.hasPrefix("<<<<<<<") || l.hasPrefix(">>>>>>>") || l == "=======" { throw ArchiFile.FileError.corrupt("unresolved merge conflict") }
            guard let (kind, key, json) = split(l) else { continue }
            let obj = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
            switch kind {
            case "header": if let h = obj as? [String: Any] { doc.merge(h) { $1 } }
            case "entity": entities.append(obj)
            case "element": elements.append(obj)
            case "block": blocks[key.removingPercentEncoding ?? key] = obj
            case "var": variables[key.removingPercentEncoding ?? key] = obj
            default:
                if let t = tables.first(where: { $0.kind == kind }) { tableRows[t.key, default: []].append((key, obj)) }
            }
        }
        for (k, rows) in tableRows { doc[k] = rows.sorted { $0.0 < $1.0 }.map(\.1) }
        doc["entities"] = entities; doc["elements"] = elements; doc["blocks"] = blocks; doc["variables"] = variables
        let version = doc["formatVersion"] as? Int ?? ArchiDocument.currentFormatVersion
        let env: [String: Any] = ["app": ArchiFile.appName, "formatVersion": version, "document": doc]
        return try ArchiFile.decode(JSONSerialization.data(withJSONObject: env))
    }

    public struct Change: Hashable, CustomStringConvertible {
        public var kind: ChangeKind
        /// "entity", "element", "layer", "block", "material", "level", "var", "header", …
        public var object: String
        public var key: String
        public var description: String { "\(kind.rawValue) \(object) \(key.removingPercentEncoding ?? key)" }
    }

    /// Object-level differences between two .archit texts (every added / removed / modified line).
    public static func diff(_ old: String, _ new: String) -> [Change] {
        func map(_ t: String) -> [String: (String, Substring)] {
            var m: [String: (String, Substring)] = [:]
            for l in t.split(separator: "\n") where !l.hasPrefix("#") {
                guard let (k, key, json) = split(l) else { continue }
                // Table rows are keyed by name (the index only orders them).
                let id = tables.contains { $0.kind == k } ? String(key.split(separator: " ").last ?? "") : key
                m[k + " " + id] = (k, json)
            }
            return m
        }
        let a = map(old), b = map(new)
        var out: [Change] = []
        for (k, v) in b {
            let key = String(k.dropFirst(v.0.count + 1))
            if let o = a[k] { if o.1 != v.1 { out.append(Change(kind: .modified, object: v.0, key: key)) } }
            else { out.append(Change(kind: .added, object: v.0, key: key)) }
        }
        for (k, v) in a where b[k] == nil { out.append(Change(kind: .removed, object: v.0, key: String(k.dropFirst(v.0.count + 1)))) }
        return out.sorted { ($0.object, Int($0.key) ?? 0, $0.key) < ($1.object, Int($1.key) ?? 0, $1.key) }
    }
}

/// Git versioning of a drawing saved as .archit (uses the git command line; `git` must be installed).
public enum GitVersioning {
    public struct GitError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }
    public struct Commit: Hashable { public var hash: String; public var author: String; public var date: String; public var message: String }

    static func gitPath() -> String? {
        for p in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    @discardableResult
    public static func git(_ args: [String], in dir: URL) throws -> String {
        guard let g = gitPath() else { throw GitError(message: "git is not installed (install the Xcode command line tools)") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: g)
        p.arguments = ["-C", dir.path, "-c", "core.quotepath=off"] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["LC_ALL"] = "C"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw GitError(message: "git \(args.first ?? ""): " + String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return String(decoding: o, as: UTF8.self)
    }

    /// Writes the drawing as .archit next to/at `file` and commits it (initialising the repository when needed).
    /// Returns the commit hash, or nil when nothing changed.
    @discardableResult
    public static func commit(_ doc: ArchiDocument, file: URL, message: String, author: String) throws -> String? {
        let dir = file.deletingLastPathComponent()
        if (try? git(["rev-parse", "--git-dir"], in: dir)) == nil { try git(["init", "-q"], in: dir) }
        try ArchiText.encode(doc).write(to: file, atomically: true, encoding: .utf8)
        try git(["add", "--", file.lastPathComponent], in: dir)
        let status = try git(["status", "--porcelain", "--", file.lastPathComponent], in: dir)
        guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let email = author.replacingOccurrences(of: " ", with: ".").lowercased() + "@archi.local"
        try git(["-c", "user.name=\(author)", "-c", "user.email=\(email)", "commit", "-q", "-m", message.isEmpty ? "Update \(file.lastPathComponent)" : message, "--", file.lastPathComponent], in: dir)
        return try git(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func log(file: URL, limit: Int = 50) throws -> [Commit] {
        let out = try git(["log", "-n", "\(limit)", "--format=%H%x1f%an%x1f%aI%x1f%s", "--", file.lastPathComponent], in: file.deletingLastPathComponent())
        return out.split(separator: "\n").compactMap { l in
            let f = l.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            return f.count >= 4 ? Commit(hash: f[0], author: f[1], date: f[2], message: f[3]) : nil
        }
    }

    /// The .archit text of `file` at a revision (hash, tag, HEAD~n).
    public static func text(file: URL, revision: String) throws -> String {
        try git(["show", "\(revision):./\(file.lastPathComponent)"], in: file.deletingLastPathComponent())
    }

    public static func document(file: URL, revision: String) throws -> ArchiDocument { try ArchiText.decode(try text(file: file, revision: revision)) }

    /// Object-level changes between two revisions (`to` nil = the working file).
    public static func diff(file: URL, from: String, to: String?) throws -> [ArchiText.Change] {
        let a = try text(file: file, revision: from)
        let b = try to.map { try text(file: file, revision: $0) } ?? String(contentsOf: file, encoding: .utf8)
        return ArchiText.diff(a, b)
    }
}
