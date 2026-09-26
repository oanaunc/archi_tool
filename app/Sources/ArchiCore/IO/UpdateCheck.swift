// Oanarina Archi Tool — GPL-3.0-or-later
// Updates (SYS-024) and opt-in crash reports (SYS-025), core side. Updates: Sparkle-compatible appcast parsing,
// version comparison, SHA-256 verification of a download against the published SHA256SUMS.txt. Crash reports: a
// privacy-preserving report (version, OS, reason, stack, the last command lines) with the home folder, user name
// and e-mail addresses removed, written locally; nothing is sent unless the user chooses to.
import Foundation

public enum UpdateCheck {
    public struct Item: Hashable {
        public var title: String
        public var version: String            // build (sparkle:version)
        public var shortVersion: String       // marketing version
        public var url: String
        public var length: Int
        public var minimumSystemVersion: String?
        public var edSignature: String?
        public var notesURL: String?
        public var displayVersion: String { shortVersion.isEmpty ? version : shortVersion }
    }

    final class Parser: NSObject, XMLParserDelegate {
        var items: [Item] = []
        var cur: Item?
        var text = ""
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
            text = ""
            let name = q ?? e
            if name == "item" { cur = Item(title: "", version: "", shortVersion: "", url: "", length: 0) }
            if name == "enclosure", cur != nil {
                cur!.url = a["url"] ?? ""
                cur!.length = Int(a["length"] ?? "") ?? 0
                if let v = a["sparkle:version"] { cur!.version = v }
                if let v = a["sparkle:shortVersionString"] { cur!.shortVersion = v }
                cur!.edSignature = a["sparkle:edSignature"]
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch q ?? e {
            case "title": cur?.title = t
            case "sparkle:version": cur?.version = t
            case "sparkle:shortVersionString": cur?.shortVersion = t
            case "sparkle:minimumSystemVersion": cur?.minimumSystemVersion = t
            case "sparkle:releaseNotesLink": cur?.notesURL = t
            case "item": if let c = cur { items.append(c) }; cur = nil
            default: break
            }
            text = ""
        }
    }

    public static func parseAppcast(_ data: Data) -> [Item] {
        let p = Parser()
        let x = XMLParser(data: data); x.shouldProcessNamespaces = false; x.delegate = p
        _ = x.parse()
        return p.items
    }

    /// Numeric dotted-version comparison ("1.10" > "1.9"; missing parts are 0; non-numeric suffixes ignored).
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// The newest item newer than `current` that runs on `system` (e.g. "14.5").
    public static func newer(_ items: [Item], than current: String, system: String) -> Item? {
        items.filter { compare($0.displayVersion, current) == .orderedDescending && ($0.minimumSystemVersion.map { compare(system, $0) != .orderedAscending } ?? true) }
            .max { compare($0.displayVersion, $1.displayVersion) == .orderedAscending }
    }

    // MARK: SHA-256 (FIPS 180-4)

    static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

    public static func sha256(_ data: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var msg = [UInt8](data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() { msg.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xFF)) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: msg.count, by: 64) {
            for i in 0..<16 { w[i] = UInt32(msg[chunk + 4 * i]) << 24 | UInt32(msg[chunk + 4 * i + 1]) << 16 | UInt32(msg[chunk + 4 * i + 2]) << 8 | UInt32(msg[chunk + 4 * i + 3]) }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3), s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25), ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22), maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    /// Checks a downloaded file against a SHA256SUMS.txt ("<hex>  <file name>" lines).
    public static func verify(_ file: Data, name: String, sums: String) -> Bool {
        for l in sums.split(whereSeparator: \.isNewline) {
            let p = l.split(separator: " ", omittingEmptySubsequences: true)
            guard p.count >= 2 else { continue }
            if p.last.map({ String($0).trimmingCharacters(in: CharacterSet(charactersIn: "*")) }) == name { return p[0].lowercased() == sha256(file) }
        }
        return false
    }

    /// Sparkle EdDSA check: `sparkle:edSignature` (base64 Ed25519 signature of the archive bytes) against the app's
    /// SUPublicEDKey (base64 32-byte public key).
    public static func verifyEdSignature(_ file: Data, signature: String, publicKey: String) -> Bool {
        guard let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let pk = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return Ed25519.verify([UInt8](file), signature: [UInt8](sig), publicKey: [UInt8](pk))
    }

    /// Checks a downloaded update: the length announced in the appcast, then the EdDSA signature when the item and the
    /// app have one (else the SHA256SUMS.txt entry). Returns nil when the file may be installed, else the reason.
    public static func check(download: Data, item: Item, publicKey: String?, sums: String? = nil, name: String? = nil) -> String? {
        if item.length > 0 && download.count != item.length { return "the download has \(download.count) bytes, the appcast announces \(item.length)" }
        if let sig = item.edSignature, let key = publicKey {
            return verifyEdSignature(download, signature: sig, publicKey: key) ? nil : "the EdDSA signature does not match the app's update key"
        }
        if let sums, let name { return verify(download, name: name, sums: sums) ? nil : "the SHA-256 checksum does not match SHA256SUMS.txt" }
        return "the update is not signed"
    }
}

public enum CrashReport {
    /// Removes the home folder, user name and e-mail addresses from report text.
    public static func redact(_ s: String, home: String = NSHomeDirectory(), user: String = NSUserName()) -> String {
        var t = s
        if let re = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "<email>")
        }
        if !home.isEmpty && home != "/" { t = t.replacingOccurrences(of: home, with: "~") }
        if user.count >= 3 { t = t.replacingOccurrences(of: "/Users/\(user)", with: "~").replacingOccurrences(of: user, with: "<user>") }
        return t
    }

    /// A plain-text report: app version, OS, reason, stack and the last `commands` (redacted). No document content.
    public static func make(reason: String, stack: [String], commands: [String], version: String, system: String = ProcessInfo.processInfo.operatingSystemVersionString,
                            date: Date = Date(), home: String = NSHomeDirectory(), user: String = NSUserName()) -> String {
        let f = ISO8601DateFormatter()
        var s = "Oanarina Archi Tool crash report\nVersion: \(version)\nSystem: \(system)\nDate: \(f.string(from: date))\nReason: \(reason)\n\nStack:\n"
        s += stack.prefix(64).joined(separator: "\n") + "\n\nLast commands:\n" + commands.suffix(20).joined(separator: "\n") + "\n"
        return redact(s, home: home, user: user)
    }

    /// Writes a report into `folder` (created if needed) when the user opted in (`enabled`). Returns the file.
    @discardableResult
    public static func write(_ report: String, to folder: URL, enabled: Bool, date: Date = Date()) throws -> URL? {
        guard enabled else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let u = folder.appendingPathComponent("crash-\(f.string(from: date)).txt")
        try report.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    public static func pending(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "txt" }.sorted { $0.path < $1.path }
    }

    /// A mailto: link the user can choose to open (the report is only sent from their mail client).
    public static func mailto(_ report: String, to address: String) -> URL? {
        var c = URLComponents(); c.scheme = "mailto"; c.path = address
        c.queryItems = [URLQueryItem(name: "subject", value: "Oanarina Archi Tool crash report"), URLQueryItem(name: "body", value: String(report.prefix(6000)))]
        return c.url
    }
}
