// Oanarina Archi Tool — GPL-3.0-or-later
// Automation triggers (SCR-023): rules that watch a folder and run a batch job for every new or changed file matching a
// pattern (e.g. convert each dropped DXF to .archi and IFC, or run checks and write reports), then optionally POST a JSON
// summary to a webhook. Rules file:
//   {"interval": 5, "rules": [{"name": "dxf→archi", "pattern": "*.dxf", "job": {"import": ["{file}"], "commands": ["AUDIT"],
//     "outputs": ["out/{name}.archi", "out/{name}.ifc"]}, "webhook": "https://example.org/hook"}]}
// Placeholders in the job: {file} (full path), {name} (base name), {ext}, {dir}. Processed files and their modification
// dates are remembered in ".archi-automation.json" inside the watched folder.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AutomationRule {
    public var name: String
    public var pattern: String
    public var job: [String: Any]
    public var webhook: URL?
}

public final class AutomationWatcher {
    public let folder: URL
    public let rules: [AutomationRule]
    public let interval: Double
    public static let stateName = ".archi-automation.json"
    var state: [String: Double] = [:]

    public init(folder: URL, rulesData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: rulesData) as? [String: Any], let list = root["rules"] as? [[String: Any]], !list.isEmpty else {
            throw AgentTools.ToolError(message: "the rules file needs a \"rules\" array")
        }
        var out: [AutomationRule] = []
        for (i, r) in list.enumerated() {
            guard let p = r["pattern"] as? String, let job = r["job"] as? [String: Any] else { throw AgentTools.ToolError(message: "rule \(i + 1) needs a pattern and a job") }
            out.append(AutomationRule(name: r["name"] as? String ?? "rule \(i + 1)", pattern: p, job: job, webhook: (r["webhook"] as? String).flatMap(URL.init(string:))))
        }
        self.folder = folder
        self.rules = out
        self.interval = max(0.5, root["interval"] as? Double ?? 5)
        if let d = try? Data(contentsOf: folder.appendingPathComponent(AutomationWatcher.stateName)), let s = try? JSONSerialization.jsonObject(with: d) as? [String: Double] { state = s }
    }

    /// Shell-style wildcard match (* and ?), case-insensitive.
    public static func matches(_ name: String, _ pattern: String) -> Bool {
        let n = Array(name.lowercased()), p = Array(pattern.lowercased())
        var memo: [[Bool?]] = Array(repeating: Array(repeating: nil, count: p.count + 1), count: n.count + 1)
        func m(_ i: Int, _ j: Int) -> Bool {
            if let v = memo[i][j] { return v }
            let r: Bool
            if j == p.count { r = i == n.count }
            else if p[j] == "*" { r = m(i, j + 1) || (i < n.count && m(i + 1, j)) }
            else { r = i < n.count && (p[j] == "?" || p[j] == n[i]) && m(i + 1, j + 1) }
            memo[i][j] = r
            return r
        }
        return m(0, 0)
    }

    /// Files (top level of the folder) that are new or changed since they were last processed, with their rule.
    public func pending() -> [(file: URL, rule: Int)] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var out: [(URL, Int)] = []
        for f in files {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let m = AutomationWatcher.modified(f) else { continue }
            guard let r = rules.firstIndex(where: { AutomationWatcher.matches(f.lastPathComponent, $0.pattern) }) else { continue }
            if let seen = state[f.lastPathComponent], seen >= m { continue }
            out.append((f, r))
        }
        return out
    }

    /// The rule's job with the placeholders filled in for one file.
    public func job(for file: URL, rule: AutomationRule) throws -> BatchJob {
        let name = file.deletingPathExtension().lastPathComponent, ext = file.pathExtension, dir = file.deletingLastPathComponent().path
        func fill(_ v: Any) -> Any {
            if let s = v as? String { return s.replacingOccurrences(of: "{file}", with: file.path).replacingOccurrences(of: "{name}", with: name).replacingOccurrences(of: "{ext}", with: ext).replacingOccurrences(of: "{dir}", with: dir) }
            if let a = v as? [Any] { return a.map(fill) }
            if let d = v as? [String: Any] { return d.mapValues(fill) }
            return v
        }
        var j = fill(rule.job) as? [String: Any] ?? [:]
        if j["name"] == nil { j["name"] = "\(rule.name): \(file.lastPathComponent)" }
        let data = try JSONSerialization.data(withJSONObject: ["jobs": [j]])
        guard let job = try BatchJob.parse(data).jobs.first else { throw AgentTools.ToolError(message: "empty job") }
        return job
    }

    /// The file's modification time read from the file itself. Not the date prefetched by the directory listing: on
    /// Windows (NTFS) the directory entry's timestamps are updated lazily, so a listing can report an older time that
    /// changes after the file is opened, and the file would look changed again.
    static func modified(_ f: URL) -> Double? {
        ((try? FileManager.default.attributesOfItem(atPath: f.path))?[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    func saveState() {
        if let d = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: folder.appendingPathComponent(AutomationWatcher.stateName), options: .atomic) }
    }

    /// Processes the pending files once. Returns one summary per file ({file, rule, ok, written, error?, webhook?}).
    @MainActor
    public func runOnce(host: EditorHost? = nil, progress: ((String) -> Void)? = nil) async -> [[String: Any]] {
        var results: [[String: Any]] = []
        for (f, ri) in pending() {
            let rule = rules[ri]
            var r: [String: Any] = ["file": f.path, "rule": rule.name]
            do {
                let job = try job(for: f, rule: rule)
                let s = await BatchRunner.run([job], stopOnError: true, base: folder, host: host, progress: progress)
                let jr = (s["jobs"] as? [[String: Any]])?.first ?? [:]
                r["ok"] = jr["ok"] as? Bool ?? false
                r["written"] = jr["written"] ?? []
                if let e = jr["error"] { r["error"] = e }
            } catch {
                r["ok"] = false; r["error"] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            if let m = AutomationWatcher.modified(f) { state[f.lastPathComponent] = m }
            if let hook = rule.webhook { r["webhook"] = await AutomationWatcher.post(r, to: hook) }
            results.append(r)
        }
        if !results.isEmpty { saveState() }
        return results
    }

    /// POSTs a JSON body; returns the HTTP status (0 when the request failed).
    public static func post(_ body: [String: Any], to url: URL) async -> Int {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body.mapValues { v -> Any in JSONSerialization.isValidJSONObject([v]) ? v : "\(v)" })
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return 0 }
        return (resp as? HTTPURLResponse)?.statusCode ?? 0
    }
}
