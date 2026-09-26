// Oanarina Archi Tool — GPL-3.0-or-later
// SketchUp .skp import (IO-043), where legally possible. The SKP format is closed and undocumented and the only reader
// is Trimble's proprietary SketchUp C SDK, which cannot be linked into a GPL program. The file is therefore identified
// here (its UTF-16 "SketchUp Model" signature and "{major.minor.build}" version), its embedded PNG preview can be
// extracted, and the model itself is read through a converter the user installs separately (for example a tool built
// on the SketchUp SDK) and names in the SKPCONVERTER variable or ARCHI_SKP_CONVERTER environment variable. The
// converter is run as `converter <input.skp> <output>` and must write COLLADA (.dae), OBJ, 3DM, FBX or glTF; the
// output then goes through the regular importers (units and materials included). Without a converter the error
// explains the alternatives (export COLLADA or 3DM from SketchUp).
import Foundation

public enum SketchUpImport {
    public struct Header: Hashable {
        /// "21.0.339"
        public var version: String
        public var major: Int
    }

    public enum SKPError: Error, LocalizedError {
        case notSKP, noConverter(Header?), failed(String)
        public var errorDescription: String? {
            switch self {
            case .notSKP: return "Not a SketchUp model."
            case .noConverter(let h): return (h.map { "SketchUp \($0.major) model. " } ?? "") + SketchUpImport.guidance
            case .failed(let m): return "SketchUp conversion failed: \(m)"
            }
        }
    }

    public static let guidance = """
    SketchUp files use a closed format that only Trimble's SketchUp SDK can read. In SketchUp, export the model as \
    COLLADA (.dae) or Rhino (.3dm) and import that file, or install a converter built on the SketchUp SDK and set the \
    SKPCONVERTER variable to it (it is run as: converter input.skp output.dae).
    """

    /// Output formats a converter may produce, in order of preference.
    public static let outputFormats = ["dae", "3dm", "obj", "fbx", "glb", "gltf"]

    /// Signature and version of a .skp file.
    public static func header(_ data: Data) -> Header? {
        let head = [UInt8](data.prefix(256))
        let sig = Array("SketchUp Model".utf16)
        var units: [UInt16] = []
        var i = 0
        while i + 1 < head.count { units.append(UInt16(head[i]) | UInt16(head[i + 1]) << 8); i += 2 }
        // The signature may start on an odd byte (after a 0xFF 0xFE 0xFF length prefix): try both alignments.
        var odd: [UInt16] = []
        i = 1
        while i + 1 < head.count { odd.append(UInt16(head[i]) | UInt16(head[i + 1]) << 8); i += 2 }
        for u in [units, odd] {
            guard let at = find(sig, in: u) else { continue }
            let rest = String(decoding: u[(at + sig.count)...].prefix(64), as: UTF16.self)
            guard let a = rest.firstIndex(of: "{"), let b = rest[a...].firstIndex(of: "}") else { return Header(version: "", major: 0) }
            let v = String(rest[rest.index(after: a)..<b])
            return Header(version: v, major: Int(v.split(separator: ".").first ?? "") ?? 0)
        }
        return nil
    }

    static func find(_ needle: [UInt16], in hay: [UInt16]) -> Int? {
        guard needle.count <= hay.count else { return nil }
        for s in 0...(hay.count - needle.count) where hay[s] == needle[0] {
            if Array(hay[s..<(s + needle.count)]) == needle { return s }
        }
        return nil
    }

    /// The first embedded PNG image (SketchUp stores a preview of the model).
    public static func preview(_ data: Data) -> Data? {
        let b = [UInt8](data)
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let iend: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
        guard b.count > 16 else { return nil }
        var i = 0
        while i + 8 <= b.count {
            if b[i] == 0x89, Array(b[i..<(i + 8)]) == sig {
                var j = i + 8
                while j + 8 <= b.count {
                    if b[j] == 0x49, Array(b[j..<(j + 8)]) == iend { return Data(b[i..<(j + 8)]) }
                    j += 1
                }
                return nil
            }
            i += 1
        }
        return nil
    }

    /// The converter: explicit path (variable / environment), else nil.
    public static func converter(override: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for c in [override, environment["ARCHI_SKP_CONVERTER"]].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            let p = (c as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Runs `tool input output` for each output format until one produces a file.
    public static func convert(_ input: URL, tool: String, timeout: TimeInterval = 180) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("archi-skp-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var log = ""
        for ext in outputFormats {
            let out = dir.appendingPathComponent(input.deletingPathExtension().lastPathComponent + "." + ext)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = [input.path, out.path]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch { throw SKPError.failed("cannot start \(tool): \(error.localizedDescription)") }
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if p.isRunning { p.terminate(); throw SKPError.failed("the converter did not finish within \(Int(timeout)) s") }
            log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if let size = (try? fm.attributesOfItem(atPath: out.path))?[.size] as? Int, size > 0 { return out }
        }
        let msg = log.trimmingCharacters(in: .whitespacesAndNewlines)
        throw SKPError.failed(msg.isEmpty ? "the converter wrote no .dae/.3dm/.obj/.fbx/.gltf output" : String(msg.prefix(400)))
    }

    /// Reads a .skp file through the converter into a stand-alone document (in `reference`'s units).
    public static func load(_ url: URL, reference: ArchiDocument = ArchiDocument(), converter override: String? = nil) throws -> (ArchiDocument, String) {
        let data = try Data(contentsOf: url)
        guard let h = header(data) else { throw SKPError.notSKP }
        guard let tool = converter(override: override ?? reference.variable("SKPCONVERTER")) else { throw SKPError.noConverter(h) }
        let out = try convert(url, tool: tool)
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let (d, summary) = try FileImport.load(out, reference: reference)
        return (d, "SketchUp \(h.version.isEmpty ? "model" : h.version) via \(out.pathExtension.uppercased()): \(summary)")
    }
}
