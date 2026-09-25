// Oanarina Archi Tool — GPL-3.0-or-later
// eTransmit / pack and go: a ZIP with the drawing, the files it references (raster images, material textures, external
// references) with paths rewritten to the packaged copies, and a transmittal report (files, missing files, fonts).
import Foundation

public struct TransmittalReport {
    public var files: [(source: String, packaged: String)] = []
    public var missing: [String] = []
    public var fonts: [String] = []
    public var text: String {
        var s = "Transmittal — Oanarina Archi Tool\nCreated: \(Markups.now())\n\nIncluded files:\n"
        for f in files { s += "  \(f.packaged)  ←  \(f.source)\n" }
        if files.isEmpty { s += "  (none besides the drawing)\n" }
        if !missing.isEmpty { s += "\nMissing (not packaged):\n" + missing.map { "  \($0)\n" }.joined() }
        s += "\nFonts used by text styles (install on the receiving Mac if missing):\n" + fonts.map { "  \($0)\n" }.joined()
        return s
    }
}

public enum ETransmit {
    /// Packs `doc` (saved from `documentURL`, used to resolve relative paths) as `<name>/<name>.archi` plus `files/…`.
    public static func pack(_ doc: ArchiDocument, documentURL: URL?, name: String) -> (data: Data, report: TransmittalReport) {
        let base = documentURL?.deletingLastPathComponent()
        var d = doc
        var rep = TransmittalReport()
        var packaged: [String: String] = [:]      // absolute source path → packaged relative path
        var used = Set<String>()
        var entries: [ZipArchive.Entry] = []
        func resolve(_ p: String) -> URL {
            let e = (p as NSString).expandingTildeInPath
            if e.hasPrefix("/") { return URL(fileURLWithPath: e) }
            return (base ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).appendingPathComponent(e)
        }
        /// Packaged relative path for a referenced file, or nil when it cannot be read.
        func include(_ p: String) -> String? {
            guard !p.isEmpty else { return nil }
            let u = resolve(p).standardizedFileURL
            if let q = packaged[u.path] { return q }
            guard let data = try? Data(contentsOf: u) else { if !rep.missing.contains(p) { rep.missing.append(p) }; return nil }
            var fname = u.lastPathComponent, k = 1
            while used.contains(fname.lowercased()) { fname = u.deletingPathExtension().lastPathComponent + "_\(k)." + u.pathExtension; k += 1 }
            used.insert(fname.lowercased())
            let rel = "files/" + fname
            packaged[u.path] = rel
            entries.append(.init(name: "\(name)/\(rel)", data: data))
            rep.files.append((u.path, rel))
            return rel
        }
        func fix(_ e: inout Entity) { if case .image(var im) = e.geometry, let r = include(im.path) { im.path = r; e.geometry = .image(im) } }
        for i in d.entities.indices { fix(&d.entities[i]) }
        for k in d.blocks.keys { for i in d.blocks[k]!.entities.indices { fix(&d.blocks[k]!.entities[i]) } }
        for l in d.layouts.indices { for i in d.layouts[l].entities.indices { fix(&d.layouts[l].entities[i]) } }
        for i in d.materials.indices { if let t = d.materials[i].texture, let r = include(t) { d.materials[i].texture = r } }
        var xr = Xrefs.all(d)
        for i in xr.indices { if let r = include(xr[i].path) { xr[i].path = r } }
        if !xr.isEmpty { Xrefs.store(xr, &d) }
        rep.fonts = Array(Set(d.textStyles.map { $0.font.isEmpty ? "Helvetica" : $0.font })).sorted()
        let archi = (try? ArchiFile.encode(d)) ?? Data()
        entries.insert(.init(name: "\(name)/\(name).archi", data: archi), at: 0)
        entries.append(.init(name: "\(name)/transmittal.txt", data: Data(rep.text.utf8)))
        return (ZipArchive.write(entries, compress: true), rep)
    }

    /// Unpacks a transmittal into `directory`; returns the drawing's URL.
    @discardableResult
    public static func unpack(_ data: Data, to directory: URL) throws -> URL {
        let entries = try ZipArchive.read(data)
        var drawing: URL?
        for e in entries {
            guard !e.name.hasSuffix("/"), !e.name.contains("..") else { continue }
            let u = directory.appendingPathComponent(e.name)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try e.data.write(to: u, options: .atomic)
            if u.pathExtension.lowercased() == "archi", e.name.split(separator: "/").count <= 2, drawing == nil { drawing = u }
        }
        guard let d = drawing else { throw DocumentIO.IOError(message: "the package contains no .archi drawing") }
        return d
    }
}
