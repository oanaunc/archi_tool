// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Native `.archi` file format: pretty-printed, key-sorted JSON wrapped in a small envelope
/// `{"app": "Oanarina Archi Tool", "formatVersion": N, "document": {...}}`.
public enum ArchiFile {
    public static let fileExtension = "archi"
    public static let appName = "Oanarina Archi Tool"

    public enum FileError: Error, LocalizedError, Equatable {
        case notAnArchiFile
        case newerVersion(found: Int, supported: Int)
        case corrupt(String)
        public var errorDescription: String? {
            switch self {
            case .notAnArchiFile: return "The file is not an Oanarina Archi Tool document."
            case .newerVersion(let f, let s):
                return "This document was saved by a newer version of Oanarina Archi Tool (format \(f)); this version reads formats up to \(s). Please update the application."
            case .corrupt(let m): return "The document is damaged and cannot be opened: \(m)"
            }
        }
    }

    /// Migration hooks: `migrations[v]` upgrades the raw JSON `document` object from format `v` to `v + 1`.
    public static var migrations: [Int: ([String: Any]) throws -> [String: Any]] = [:]

    public static func encode(_ doc: ArchiDocument) throws -> Data {
        var d = doc
        d.formatVersion = ArchiDocument.currentFormatVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try enc.encode(Envelope(app: appName, formatVersion: ArchiDocument.currentFormatVersion, document: d))
    }

    public static func decode(_ data: Data) throws -> ArchiDocument {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw FileError.corrupt("invalid JSON (\(error.localizedDescription))") }
        guard var root = raw as? [String: Any] else { throw FileError.notAnArchiFile }
        // Accept a bare document (no envelope) for robustness.
        var docObj: [String: Any]
        var version: Int
        if let inner = root["document"] as? [String: Any] {
            docObj = inner
            version = (root["formatVersion"] as? Int) ?? (inner["formatVersion"] as? Int) ?? 1
        } else if root["layers"] != nil || root["entities"] != nil {
            docObj = root
            version = (root["formatVersion"] as? Int) ?? 1
        } else { throw FileError.notAnArchiFile }
        let current = ArchiDocument.currentFormatVersion
        if version > current { throw FileError.newerVersion(found: version, supported: current) }
        if version < 1 { throw FileError.corrupt("invalid format version \(version)") }
        while version < current {
            if let m = migrations[version] { docObj = try m(docObj) }
            version += 1
        }
        docObj["formatVersion"] = current
        root = docObj
        let normalized = try JSONSerialization.data(withJSONObject: root)
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        do { return try dec.decode(ArchiDocument.self, from: normalized) }
        catch let e as DecodingError { throw FileError.corrupt(describe(e)) }
    }

    private struct Envelope: Codable {
        var app: String; var formatVersion: Int; var document: ArchiDocument
    }

    private static func describe(_ e: DecodingError) -> String {
        func path(_ c: [CodingKey]) -> String { c.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined() }
        switch e {
        case .keyNotFound(let k, let c): return "missing key '\(k.stringValue)' at \(path(c.codingPath))"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c): return "\(c.debugDescription) at \(path(c.codingPath))"
        @unknown default: return "\(e)"
        }
    }
}
