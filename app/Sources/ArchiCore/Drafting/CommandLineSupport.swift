// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Records command-line input (typed lines and UI clicks) as a replayable script (SCRIPTRECORD).
public final class ScriptRecorder {
    public var lines: [String] = []
    public var path: String?
    public init(path: String? = nil) { self.path = path }
    /// Records an input given through the UI (clicks, Enter, picks).
    public func record(_ input: CommandInput, world: Bool = true) {
        switch input {
        case .point(let p): lines.append((world ? "" : "*") + "\(fmt(p.x, 6)),\(fmt(p.y, 6))")
        case .number(let d): lines.append(fmt(d, 8))
        case .text(let t): lines.append(t.contains(" ") ? "\"\(t)\"" : t)
        case .keyword(let k): lines.append(k)
        case .selection(let ids): lines.append(ids.map { "#\($0)" }.joined(separator: ","))
        case .enter: lines.append("")
        case .cancel: break
        }
    }
    public var text: String { lines.joined(separator: "\n") + "\n" }
}

/// User-defined command aliases and macros (acad.pgp style), global and per document.
/// Document aliases live in the variables "ALIAS:<NAME>" so they persist in the .archi file.
public enum UserAliases {
    /// Global aliases (loaded from a .pgp file or set with ALIAS Global).
    public static var global: [String: String] = [:]
    private static var loadedDefault = false

    /// Default alias file: ~/Library/Application Support/Oanarina Archi Tool/aliases.pgp
    public static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/aliases.pgp")
    }

    static func loadDefaultIfNeeded() {
        guard !loadedDefault else { return }
        loadedDefault = true
        if let s = try? String(contentsOf: defaultFile, encoding: .utf8) { for (k, v) in parsePGP(s) where global[k] == nil { global[k] = v } }
    }

    /// Parses "LL, *LINE" lines (";" starts a comment). Values without "*" are macros.
    public static func parsePGP(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix(";"), let comma = line.firstIndex(of: ",") else { continue }
            let name = line[..<comma].trimmingCharacters(in: .whitespaces).uppercased()
            var value = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("*") { value.removeFirst() }
            guard isValidName(name), !value.isEmpty else { continue }
            out[name] = value
        }
        return out
    }
    public static func formatPGP(_ aliases: [String: String]) -> String {
        aliases.sorted { $0.key < $1.key }.map { k, v in
            let isCommand = !v.contains(" ") && !v.contains(";")
            return "\(k),\(String(repeating: " ", count: max(1, 8 - k.count)))\(isCommand ? "*" : "")\(v)"
        }.joined(separator: "\n") + "\n"
    }

    public static func isValidName(_ n: String) -> Bool {
        !n.isEmpty && n.count <= 64 && n.allSatisfy { $0.isLetter || $0.isNumber || "-_.$".contains($0) }
    }

    public static func documentAliases(_ doc: ArchiDocument) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in doc.variables where k.hasPrefix("ALIAS:") { out[String(k.dropFirst(6))] = v }
        return out
    }

    /// The command name or macro an alias expands to (document aliases override global ones).
    public static func expansion(for name: String, doc: ArchiDocument) -> String? {
        let n = name.uppercased()
        guard isValidName(n) else { return nil }
        if let v = doc.variable("ALIAS:" + n) { return v }
        loadDefaultIfNeeded()
        return global[n]
    }

    /// Splits a macro into command-line tokens. ";" and "" are Enter; a leading ^C^C is dropped.
    public static func macroTokens(_ macro: String) -> [String] {
        var m = macro
        while m.hasPrefix("^C") || m.hasPrefix("^c") { m.removeFirst(2) }
        var out: [String] = [], cur = "", inQuote = false, quoted = false
        func flush() { if !cur.isEmpty || quoted { out.append(cur) }; cur = ""; quoted = false }
        for ch in m {
            if ch == "\"" { inQuote.toggle(); quoted = true; continue }
            if inQuote { cur.append(ch); continue }
            if ch == " " { flush(); continue }
            if ch == ";" { flush(); out.append(""); continue }
            cur.append(ch)
        }
        flush()
        return out
    }
}

/// "Did you mean" suggestions for mistyped command names.
public enum CommandSuggestions {
    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count), cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }

    public static func suggest(_ name: String, registry: CommandRegistry, limit: Int = 3) -> [String] {
        let n = name.uppercased()
        guard n.count >= 2 else { return [] }
        var scored: [(String, Int)] = []
        for c in registry.commands.values {
            var best = Int.max
            for cand in [c.name] + c.aliases {
                var d = levenshtein(n, cand)
                if cand.hasPrefix(n) { d = min(d, 1) }
                best = min(best, d)
            }
            let maxD = n.count <= 4 ? 1 : 2
            if best <= maxD { scored.append((c.name, best)) }
        }
        return scored.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.prefix(limit).map(\.0)
    }
}
