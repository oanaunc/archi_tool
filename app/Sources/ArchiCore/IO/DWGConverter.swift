// Oanarina Archi Tool — GPL-3.0-or-later
// DWG support through an external converter. DWG is a closed, undocumented binary format; a clean-room reader is out of
// scope, so DWG files are converted to/from DXF by a converter installed on the Mac:
//   • ODA File Converter (free download from opendesign.com): ODAFileConverter <inDir> <outDir> <version> <type> <recurse> <audit> [<filter>]
//   • LibreDWG (GPL, `brew install libredwg`): dwg2dxf / dxf2dwg
// The converter is looked up in the DWGCONVERTER variable / ARCHI_DWG_CONVERTER environment variable, then in the usual
// install locations.
import Foundation

public enum DWGConverter {
    public enum Kind: String { case oda, libredwg }

    public struct Tool: Equatable {
        public var kind: Kind
        /// Executable (ODAFileConverter, or the directory's dwg2dxf for LibreDWG).
        public var path: String
        public init(kind: Kind, path: String) { self.kind = kind; self.path = path }
    }

    public enum DWGError: Error, LocalizedError {
        case noConverter
        case failed(String)
        public var errorDescription: String? {
            switch self {
            case .noConverter: return DWGConverter.guidance
            case .failed(let m): return "DWG conversion failed: \(m)"
            }
        }
    }

    /// How to get DWG support (shown when no converter is installed).
    public static let guidance = """
    DWG files need a converter. Either install the free ODA File Converter (https://www.opendesign.com/guestfiles/oda_file_converter) \
    into /Applications, or LibreDWG (brew install libredwg); or set the DWGCONVERTER variable to the converter's path. \
    Alternatively save the drawing as DXF in the original CAD program (SAVEAS → AutoCAD DXF) and open the DXF.
    """

    static let odaCandidates = [
        "/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter",
        "/Applications/ODA/ODAFileConverter.app/Contents/MacOS/ODAFileConverter",
        "~/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter",
        "/usr/bin/ODAFileConverter", "/usr/local/bin/ODAFileConverter",
    ]
    static let libreCandidates = ["/opt/homebrew/bin/dwg2dxf", "/usr/local/bin/dwg2dxf", "/usr/bin/dwg2dxf"]

    /// Classifies a converter path by its file name.
    public static func tool(at path: String) -> Tool? {
        let p = (path as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: p) else { return nil }
        let name = (p as NSString).lastPathComponent.lowercased()
        if name.hasPrefix("dwg2dxf") || name.hasPrefix("dxf2dwg") || name.hasPrefix("dwgread") {
            return Tool(kind: .libredwg, path: ((p as NSString).deletingLastPathComponent as NSString).appendingPathComponent("dwg2dxf"))
        }
        return Tool(kind: .oda, path: p)
    }

    /// The converter to use: explicit path (variable/environment) first, then the standard locations.
    public static func find(override: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> Tool? {
        for c in [override, environment["ARCHI_DWG_CONVERTER"]].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if let t = tool(at: c) { return t }
        }
        for c in odaCandidates { if let t = tool(at: c) { return t } }
        for c in libreCandidates { if let t = tool(at: c) { return t } }
        return nil
    }

    /// DWG/DXF version names understood by the ODA converter.
    public static func odaVersion(_ v: String) -> String {
        switch v.uppercased().replacingOccurrences(of: " ", with: "") {
        case "R12", "AC1009", "ACAD12": return "ACAD12"
        case "R14", "ACAD14": return "ACAD14"
        case "2000", "R2000", "ACAD2000": return "ACAD2000"
        case "2004", "ACAD2004": return "ACAD2004"
        case "2007", "ACAD2007": return "ACAD2007"
        case "2010", "ACAD2010": return "ACAD2010"
        case "2013", "ACAD2013": return "ACAD2013"
        default: return "ACAD2018"
        }
    }

    /// Arguments for one conversion. ODA converts whole folders filtered by file name; LibreDWG converts one file.
    public static func arguments(_ tool: Tool, input: URL, outputDir: URL, toDWG: Bool, version: String = "2018") -> (executable: String, args: [String], output: URL) {
        let base = input.deletingPathExtension().lastPathComponent
        let out = outputDir.appendingPathComponent(base + (toDWG ? ".dwg" : ".dxf"))
        switch tool.kind {
        case .oda:
            return (tool.path, [input.deletingLastPathComponent().path, outputDir.path, odaVersion(version), toDWG ? "DWG" : "DXF", "0", "1", input.lastPathComponent], out)
        case .libredwg:
            let dir = (tool.path as NSString).deletingLastPathComponent
            let exe = (dir as NSString).appendingPathComponent(toDWG ? "dxf2dwg" : "dwg2dxf")
            return (exe, ["-y", "-o", out.path, input.path], out)
        }
    }

    /// Runs the converter and returns the produced file (in a fresh temporary folder).
    public static func convert(_ input: URL, toDWG: Bool, tool: Tool, version: String = "2018", timeout: TimeInterval = 120) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("archi-dwg-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // ODA converts every matching file of the input folder: stage the input alone in its own folder.
        let stageIn = dir.appendingPathComponent("in")
        try fm.createDirectory(at: stageIn, withIntermediateDirectories: true)
        let staged = stageIn.appendingPathComponent(input.lastPathComponent)
        try fm.copyItem(at: input, to: staged)
        let outDir = dir.appendingPathComponent("out")
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        let a = arguments(tool, input: staged, outputDir: outDir, toDWG: toDWG, version: version)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: a.executable)
        p.arguments = a.args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { throw DWGError.failed("cannot start \(a.executable): \(error.localizedDescription)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); throw DWGError.failed("the converter did not finish within \(Int(timeout)) s") }
        let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        // The output name's case can differ (ODA keeps the input's base name).
        let produced = (try? fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension.lowercased() == (toDWG ? "dwg" : "dxf") }
        guard let out = fm.fileExists(atPath: a.output.path) ? a.output : produced else {
            let msg = log.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DWGError.failed(msg.isEmpty ? "no output (exit code \(p.terminationStatus))" : String(msg.prefix(400)))
        }
        return out
    }

    /// Reads a DWG file through the converter.
    public static func read(_ url: URL, converter: String? = nil) throws -> ArchiDocument {
        guard let t = find(override: converter) else { throw DWGError.noConverter }
        let dxf = try convert(url, toDWG: false, tool: t)
        defer { try? FileManager.default.removeItem(at: dxf.deletingLastPathComponent().deletingLastPathComponent()) }
        return try DXFReader.read(try FileImport.readText(dxf))
    }

    /// Writes a DWG file: DXF R2000 first, then the converter.
    public static func write(_ doc: ArchiDocument, to url: URL, version: String = "2018", converter: String? = nil) throws {
        guard let t = find(override: converter) else { throw DWGError.noConverter }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-dwgout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dxf = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".dxf")
        try DXFWriter.write(doc).write(to: dxf, atomically: true, encoding: .utf8)
        let out = try convert(dxf, toDWG: true, tool: t, version: version)
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent().deletingLastPathComponent()) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.copyItem(at: out, to: url)
    }
}
