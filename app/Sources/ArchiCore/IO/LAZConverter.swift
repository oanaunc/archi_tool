// Oanarina Archi Tool — GPL-3.0-or-later
// LAZ point clouds (IO-049) through an installed decompressor, like DWG: LAZ is LAS compressed with the LASzip codec,
// so the file is decompressed to a temporary LAS by one of
//   • LASzip (Apache-2.0, `brew install laszip`): laszip -i in.laz -o out.las   (also laszip64 / laszip-cli)
//   • PDAL (BSD, `brew install pdal`): pdal translate in.laz out.las
//   • LAStools las2las: las2las -i in.laz -o out.las
// and read by the LAS reader. The tool is looked up in the LAZCONVERTER variable / ARCHI_LAZ_CONVERTER environment
// variable, then in the usual install locations.
import Foundation

public enum LAZConverter {
    public enum Kind: String { case laszip, pdal, las2las }
    public struct Tool: Equatable { public var kind: Kind; public var path: String }

    public struct LAZError: Error, LocalizedError {
        public var message: String
        public var errorDescription: String? { message }
    }

    public static let guidance = """
    LAZ files are compressed LAS. Install LASzip (brew install laszip) or PDAL (brew install pdal), or set the LAZCONVERTER \
    variable to laszip, pdal or las2las; alternatively decompress the file to .las and import that.
    """

    static let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "~/bin", "/Applications/LAStools/bin"]
    static let names = ["laszip", "laszip64", "laszip-cli", "pdal", "las2las", "las2las64"]

    public static func tool(at path: String) -> Tool? {
        let p = (path as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: p) else { return nil }
        let n = (p as NSString).lastPathComponent.lowercased()
        if n.hasPrefix("pdal") { return Tool(kind: .pdal, path: p) }
        if n.hasPrefix("las2las") { return Tool(kind: .las2las, path: p) }
        return Tool(kind: .laszip, path: p)
    }

    public static func find(override: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> Tool? {
        for c in [override, environment["ARCHI_LAZ_CONVERTER"]].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if let t = tool(at: c) { return t }
        }
        for n in names { for d in dirs { if let t = tool(at: (d as NSString).appendingPathComponent(n)) { return t } } }
        return nil
    }

    /// Command line of a decompression.
    public static func arguments(_ t: Tool, input: URL, output: URL) -> [String] {
        switch t.kind {
        case .pdal: return ["translate", input.path, output.path]
        case .laszip, .las2las: return ["-i", input.path, "-o", output.path]
        }
    }

    /// Decompresses a LAZ file to LAS bytes.
    public static func decompress(_ url: URL, converter: String? = nil, timeout: TimeInterval = 600) throws -> Data {
        guard let t = find(override: converter) else { throw LAZError(message: guidance) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("archi-laz-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let out = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".las")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: t.path)
        p.arguments = arguments(t, input: url, output: out)
        let log = dir.appendingPathComponent("log.txt")
        fm.createFile(atPath: log.path, contents: nil)
        let h = try FileHandle(forWritingTo: log)
        p.standardOutput = h; p.standardError = h
        do { try p.run() } catch { throw LAZError(message: "Cannot start \(t.path): \(error.localizedDescription)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); throw LAZError(message: "\(t.kind.rawValue) did not finish within \(Int(timeout)) s") }
        try? h.close()
        guard let data = try? Data(contentsOf: out), data.count >= 227 else {
            let msg = (try? String(contentsOf: log, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw LAZError(message: "LAZ decompression failed" + (msg.isEmpty ? " (exit code \(p.terminationStatus))" : ": " + String(msg.prefix(400))))
        }
        return data
    }
}
