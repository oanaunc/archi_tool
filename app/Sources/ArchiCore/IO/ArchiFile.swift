// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Native `.archi` file format: pretty-printed, key-sorted JSON wrapped in a small envelope
/// `{"app": "Oanarina Archi Tool", "formatVersion": N, "document": {...}}`.
/// Files saved by archi-engine (Windows, Linux) may carry an optional envelope field
/// `"preview": {"png": "<base64>", "width": W, "height": H}` after the document: the plan picture the Windows Explorer
/// thumbnail handler shows (windows/native/ArchiThumbnail.cpp, FILEPREVIEW). It is outside `document`, so readers that
/// do not know it ignore it and the document format version is unchanged (docs/WINDOWS-FILEPREVIEW.md).
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
    public static var migrations: [Int: ([String: Any]) throws -> [String: Any]] = [
        1: { $0 },   // 1 → 2: new BIM fields are optional; old documents decode unchanged.
    ]

    public static func encode(_ doc: ArchiDocument) throws -> Data { try encode(doc, preview: nil) }

    /// Encodes the document with an optional embedded preview picture (PNG data). With sorted keys `preview` is the last
    /// top-level key, so readers find it at the end of the file without parsing the document.
    public static func encode(_ doc: ArchiDocument, preview: PreviewImage?) throws -> Data {
        var d = doc
        d.formatVersion = ArchiDocument.currentFormatVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try enc.encode(Envelope(app: appName, formatVersion: ArchiDocument.currentFormatVersion, document: d,
                                       preview: preview.map { EnvelopePreview(png: $0.png.base64EncodedString(), width: $0.width, height: $0.height) }))
    }

    public static func decode(_ data: Data) throws -> ArchiDocument {
        // Fast path (SYS-020): a current-format file decodes in one pass; older or damaged files take the migrating path.
        if let fast = try? decoder().decode(Envelope.self, from: data), fast.formatVersion == ArchiDocument.currentFormatVersion,
           fast.document.formatVersion == ArchiDocument.currentFormatVersion {
            return fast.document
        }
        return try decodeMigrating(data)
    }

    static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return dec
    }

    /// Generic path: parses the JSON, runs the migrations from the file's format version, then decodes.
    static func decodeMigrating(_ data: Data) throws -> ArchiDocument {
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
        var preview: EnvelopePreview? = nil
    }
    private struct EnvelopePreview: Codable { var png: String; var width: Int; var height: Int }

    /// Preview picture embedded in a saved file (PNG bytes and pixel size).
    public struct PreviewImage: Equatable {
        public var png: Data
        public var width: Int
        public var height: Int
        public init(png: Data, width: Int, height: Int) { self.png = png; self.width = width; self.height = height }
    }

    /// The embedded preview of `.archi` file data, found the way the Explorer thumbnail handler finds it: the last
    /// `"preview"` key in the final 16 MB, which must be the last top-level value (one `{`, two `}` after it), then its
    /// `"png"` base64 string, `width` and `height`. nil when there is none.
    public static func preview(in data: Data) -> PreviewImage? {
        let tail = data.count > 16 << 20 ? data.suffix(16 << 20) : data
        guard let k = tail.range(of: Data("\"preview\"".utf8), options: .backwards) else { return nil }
        let rest = tail[k.upperBound...]
        guard rest.filter({ $0 == UInt8(ascii: "{") }).count == 1, rest.filter({ $0 == UInt8(ascii: "}") }).count == 2 else { return nil }
        func string(_ key: String) -> String? {
            guard let r = rest.range(of: Data("\"\(key)\"".utf8)),
                  let q1 = rest[r.upperBound...].firstIndex(of: UInt8(ascii: "\"")),
                  let q2 = rest[(q1 + 1)...].firstIndex(of: UInt8(ascii: "\"")) else { return nil }
            return String(decoding: rest[(q1 + 1)..<q2], as: UTF8.self)
        }
        func int(_ key: String) -> Int {
            guard let r = rest.range(of: Data("\"\(key)\"".utf8)) else { return 0 }
            let digits = rest[r.upperBound...].drop(while: { !(0x30...0x39).contains($0) }).prefix(while: { (0x30...0x39).contains($0) })
            return Int(String(decoding: digits, as: UTF8.self)) ?? 0
        }
        guard let b64 = string("png"), let png = Data(base64Encoded: b64.replacingOccurrences(of: "\\/", with: "/")),
              png.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return nil }
        return PreviewImage(png: png, width: int("width"), height: int("height"))
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
