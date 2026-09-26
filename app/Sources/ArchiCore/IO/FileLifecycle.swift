// Oanarina Archi Tool — GPL-3.0-or-later
// Native file life cycle: lossless round-trip verification (IO-001), Save a Copy (IO-002), schema upgrades of older
// .archi files with backups (IO-004), templates (.architemplate, IO-005), Spotlight/Quick Look metadata (IO-007) and
// importing pasted or dropped content (IO-064, IO-065).
import Foundation

// MARK: - Round-trip verification

extension ArchiFile {
    /// Names of the document sections that change when `doc` is saved and reopened (empty = lossless).
    public static func roundTripDifferences(_ doc: ArchiDocument) throws -> [String] {
        var expected = doc
        expected.formatVersion = ArchiDocument.currentFormatVersion
        // nextID is normalised on load (always above the highest id).
        let maxID = max(expected.entities.map(\.id).max() ?? 0, expected.elements.map(\.id).max() ?? 0)
        if expected.nextID <= maxID { expected.nextID = maxID + 1 }
        let back = try decode(encode(doc))
        if back == expected { return [] }
        func obj(_ d: ArchiDocument) throws -> [String: Any] {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            return (try JSONSerialization.jsonObject(with: enc.encode(d))) as? [String: Any] ?? [:]
        }
        let a = try obj(expected), b = try obj(back)
        var out: [String] = []
        for k in Set(a.keys).union(b.keys).sorted() {
            let x = a[k].map { NSDictionary(dictionary: ["v": $0]) }, y = b[k].map { NSDictionary(dictionary: ["v": $0]) }
            if x != y { out.append(k) }
        }
        return out.isEmpty ? ["(value precision)"] : out
    }

    // MARK: Schema information and upgrades

    public struct FileInfo: Hashable {
        public var formatVersion: Int
        public var app: String
        public var isTemplate: Bool
        public var entities: Int
        public var elements: Int
        public var needsUpgrade: Bool { formatVersion < ArchiDocument.currentFormatVersion }
        public var isNewer: Bool { formatVersion > ArchiDocument.currentFormatVersion }
    }

    /// Reads the envelope of a file without decoding the model.
    public static func inspect(_ data: Data) throws -> FileInfo {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw FileError.notAnArchiFile }
        let doc = (root["document"] as? [String: Any]) ?? ((root["layers"] != nil || root["entities"] != nil) ? root : nil)
        guard let d = doc else { throw FileError.notAnArchiFile }
        let v = (root["formatVersion"] as? Int) ?? (d["formatVersion"] as? Int) ?? 1
        return FileInfo(formatVersion: v, app: root["app"] as? String ?? "", isTemplate: root["template"] != nil,
                        entities: (d["entities"] as? [Any])?.count ?? 0, elements: (d["elements"] as? [Any])?.count ?? 0)
    }

    public struct UpgradeResult: Hashable {
        public var url: URL
        public var from: Int
        public var to: Int
        /// Copy of the original file (nil when the file was already current).
        public var backup: URL?
    }

    /// Upgrades an older .archi file in place to the current format; the original is kept as "<name>.v<N>.archi.bak".
    /// Templates keep their template metadata.
    @discardableResult
    public static func upgradeFile(_ url: URL, keepBackup: Bool = true) throws -> UpgradeResult {
        let data = try Data(contentsOf: url)
        let info = try inspect(data)
        if info.isNewer { throw FileError.newerVersion(found: info.formatVersion, supported: ArchiDocument.currentFormatVersion) }
        guard info.needsUpgrade else { return UpgradeResult(url: url, from: info.formatVersion, to: info.formatVersion, backup: nil) }
        let doc = try decode(data)
        var backup: URL?
        if keepBackup {
            let b = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".v\(info.formatVersion).\(url.pathExtension).bak")
            try? FileManager.default.removeItem(at: b)
            try FileManager.default.copyItem(at: url, to: b)
            backup = b
        }
        let out: Data
        if info.isTemplate, let t = try? ArchiTemplate.decode(data) { out = try ArchiTemplate.encode(t.document, info: t.info) }
        else { out = try encode(doc) }
        try out.write(to: url, options: .atomic)
        return UpgradeResult(url: url, from: info.formatVersion, to: ArchiDocument.currentFormatVersion, backup: backup)
    }

    /// Writes a copy of the document to `url` in the format of its extension without touching the open drawing (Save a Copy).
    public static func saveCopy(_ doc: ArchiDocument, to url: URL, format: String? = nil) throws {
        let f = (format ?? url.pathExtension).lowercased()
        if f == ArchiTemplate.fileExtension { try ArchiTemplate.encode(doc, info: ArchiTemplate.Info(name: url.deletingPathExtension().lastPathComponent)).write(to: url, options: .atomic); return }
        if f == "archi" { try encode(doc).write(to: url, options: .atomic); return }
        try DocumentIO.write(doc, to: url, format: f)
    }
}

// MARK: - Templates

/// Template files (.architemplate): the .archi format with template metadata in the envelope. Any .archi reader opens
/// them (the extra key is ignored), and a template stores every part of a document losslessly.
public enum ArchiTemplate {
    public static let fileExtension = "architemplate"

    public struct Info: Codable, Hashable {
        public var name: String
        public var description: String
        public var created: String
        public init(name: String, description: String = "", created: String = ISO8601DateFormatter().string(from: Date())) {
            self.name = name; self.description = description; self.created = created
        }
    }

    public struct Loaded: Hashable { public var document: ArchiDocument; public var info: Info }

    private struct Envelope: Codable { var app: String; var formatVersion: Int; var template: Info; var document: ArchiDocument }

    public static func encode(_ doc: ArchiDocument, info: Info) throws -> Data {
        var d = doc
        d.formatVersion = ArchiDocument.currentFormatVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try enc.encode(Envelope(app: ArchiFile.appName, formatVersion: ArchiDocument.currentFormatVersion, template: info, document: d))
    }

    /// Decodes a template (older formats are migrated). A plain .archi file is accepted as a template named "Drawing".
    public static func decode(_ data: Data) throws -> Loaded {
        let doc = try ArchiFile.decode(data)
        var info = Info(name: "Drawing", created: "")
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let t = root["template"],
           let td = try? JSONSerialization.data(withJSONObject: t), let i = try? JSONDecoder().decode(Info.self, from: td) { info = i }
        return Loaded(document: doc, info: info)
    }

    /// A new untitled drawing from a template: everything is kept (layers, styles, blocks, content, sheets, variables…)
    /// except the project name and the creation date.
    public static func newDocument(from template: ArchiDocument, now: Date = Date()) -> ArchiDocument {
        var d = template
        d.info.name = "Untitled Project"
        let jd = now.timeIntervalSince1970 / 86400 + 2440587.5
        d.variables["TDCREATE"] = fmt(jd, 8)
        d.variables.removeValue(forKey: "TDINDWG")
        return d
    }

    /// Saves `doc` as a template file.
    public static func save(_ doc: ArchiDocument, to url: URL, name: String? = nil, description: String = "") throws {
        let u = url.pathExtension.isEmpty ? url.appendingPathExtension(fileExtension) : url
        try encode(doc, info: Info(name: name ?? u.deletingPathExtension().lastPathComponent, description: description)).write(to: u, options: .atomic)
    }
}

// MARK: - Spotlight / Quick Look metadata

public enum SpotlightMetadata {
    /// Spotlight attributes of a drawing (kMDItem… keys plus app-specific "org.oanarina.archi.*").
    public static func attributes(_ doc: ArchiDocument) -> [String: Any] {
        var texts: [String] = []
        func add(_ s: String) { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { texts.append(t) } }
        for e in doc.entities {
            switch e.geometry {
            case .text(let t): add(DXFReader.stripMText(t.content))
            case .leader(let l): add(l.text)
            case .table(let t): t.cells.flatMap { $0 }.forEach(add)
            default: break
            }
            if let v = e.props["name"] { add(v) }
        }
        for b in doc.blocks.values { for e in b.entities { if case .text(let t) = e.geometry { add(t.content) } } }
        var rooms: [String] = []
        for el in doc.elements {
            if case .space(let s) = el.geometry { rooms.append(s.number.isEmpty ? s.name : "\(s.number) \(s.name)") }
            add(el.name)
        }
        var seen = Set<String>()
        let unique = texts.filter { seen.insert($0).inserted }
        var a: [String: Any] = [
            "kMDItemTitle": doc.info.name,
            "kMDItemKeywords": doc.layers.map(\.name),
            "kMDItemTextContent": (unique + rooms).joined(separator: "\n"),
            "org.oanarina.archi.formatVersion": doc.formatVersion,
            "org.oanarina.archi.units": doc.units.rawValue,
            "org.oanarina.archi.entityCount": doc.entities.count,
            "org.oanarina.archi.elementCount": doc.elements.count,
            "org.oanarina.archi.levels": doc.levels.sorted { $0.elevation < $1.elevation }.map(\.name),
            "org.oanarina.archi.layouts": doc.layouts.map(\.name),
            "org.oanarina.archi.rooms": rooms,
        ]
        if !doc.info.author.isEmpty { a["kMDItemAuthors"] = [doc.info.author] }
        if !doc.info.number.isEmpty { a["kMDItemIdentifier"] = doc.info.number }
        if !doc.info.client.isEmpty { a["kMDItemOrganizations"] = [doc.info.client] }
        if !doc.info.address.isEmpty { a["kMDItemNamedLocation"] = doc.info.address }
        a["kMDItemLatitude"] = doc.info.latitude
        a["kMDItemLongitude"] = doc.info.longitude
        return a
    }

    /// Attributes of a file (.archi, .architemplate, .archiz or any format DocumentIO reads).
    public static func attributes(of url: URL) throws -> [String: Any] {
        let ext = url.pathExtension.lowercased()
        let doc = ext == ArchiTemplate.fileExtension ? try ArchiTemplate.decode(Data(contentsOf: url)).document : try DocumentIO.read(url)
        return attributes(doc)
    }
}

// MARK: - Pasted and dropped content

/// Imports content from the pasteboard or a drag and drop: vector formats become drawing objects, images are placed
/// as image entities (bytes saved into `assetFolder`), .archi content is merged, plain text becomes a text object.
public enum ExternalContent {
    public enum Kind: String, CaseIterable { case archi, dxf, svg, pdf, image, text, file, geojson }

    public struct Result {
        public var kind: Kind
        public var ids: [EntityID]
        public var summary: String
    }

    /// Recognises content from a pasteboard type / UTI / extension, falling back to sniffing the bytes.
    public static func kind(of data: Data, type: String?) -> Kind? {
        let t = (type ?? "").lowercased()
        if t.contains("archi") { return .archi }
        if t.contains("svg") { return .svg }
        if t.contains("pdf") { return .pdf }
        if t.contains("dxf") { return .dxf }
        if ["png", "jpeg", "jpg", "tiff", "tif", "gif", "bmp", "webp", "heic", "image"].contains(where: { t.contains($0) }) { return .image }
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        if data.starts(with: Array("%PDF".utf8)) { return .pdf }
        if ImageHeader.size(data) != nil { return .image }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<svg"), head.contains("<svg") { return .svg }
        if trimmed.hasPrefix("{"), head.contains("\"document\"") || head.contains("\"entities\"") { return .archi }
        if t.contains("geo+json") || t.contains("geojson") { return .geojson }
        if trimmed.hasPrefix("{"), head.contains("\"coordinates\""), head.contains("\"type\"") { return .geojson }
        if trimmed.hasPrefix("0") && (head.contains("SECTION") && (head.contains("ENTITIES") || head.contains("HEADER"))) { return .dxf }
        if t.contains("text") || t.contains("string") || String(data: data, encoding: .utf8) != nil { return .text }
        return nil
    }

    /// Adds the content to `doc` at `at` (vector content: its lower-left corner lands there). Returns the new ids.
    public static func insert(_ data: Data, type: String?, into doc: inout ArchiDocument, at: Vec2 = .zero, assetFolder: URL? = nil,
                              name: String = "Pasted") throws -> Result {
        guard let k = kind(of: data, type: type) else { throw DocumentIO.IOError(message: "Unrecognised content") }
        func mergeEntities(_ ents: [Entity], _ label: String) -> Result {
            var src = ArchiDocument(); src.layers = [Layer(name: "0")]; src.entities = []
            for e in ents { src.add(e) }
            let b = src.entities.reduce(BBox2.empty) { $0.union(GeometryOps.bounds($1.geometry, doc: src)) }
            let off = b.isEmpty ? at : at - b.min
            let r = DocumentMerge.merge(src, into: &doc, offset: off)
            return Result(kind: k, ids: r.allIDs, summary: "\(r.allIDs.count) object(s) from \(label)")
        }
        switch k {
        case .archi:
            let src = try ArchiFile.decode(data)
            let r = DocumentMerge.merge(src, into: &doc, offset: at, scale: src.units.mm / doc.units.mm)
            return Result(kind: k, ids: r.allIDs, summary: "\(r.allIDs.count) object(s) from a drawing")
        case .dxf:
            let src = try DXFReader.read(String(decoding: data, as: UTF8.self))
            let r = DocumentMerge.merge(src, into: &doc, offset: at, scale: src.units.mm / doc.units.mm)
            return Result(kind: k, ids: r.allIDs, summary: "\(r.allIDs.count) object(s) from DXF")
        case .geojson:
            // Map coordinates (WGS 84 longitude/latitude) are placed with the project location, not at the paste point.
            var src = ArchiDocument(); src.entities = []; src.elements = []; src.units = doc.units; src.levels = doc.levels
            for e in try GeoJSON.entities(String(decoding: data, as: UTF8.self), doc: doc) { src.add(e) }
            let r = DocumentMerge.merge(src, into: &doc, offset: .zero)
            return Result(kind: k, ids: r.allIDs, summary: "\(r.allIDs.count) GeoJSON feature object(s), georeferenced")
        case .svg:
            return mergeEntities(try SVGImporter.entities(String(decoding: data, as: UTF8.self)), "SVG")
        case .pdf:
            let pdf = try PDFFile(data)
            var o = PDFImportOptions(); o.unitsPerPoint = 25.4 / 72 / doc.units.mm
            return mergeEntities(try PDFImport.entities(pdf, page: 1, options: o), "PDF")
        case .image:
            guard let px = ImageHeader.size(data) else { throw DocumentIO.IOError(message: "Unreadable image") }
            let folder = assetFolder ?? FileManager.default.temporaryDirectory.appendingPathComponent("ArchiPasted", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = imageExtension(data)
            var file = folder.appendingPathComponent("\(name).\(ext)")
            var n = 1
            while FileManager.default.fileExists(atPath: file.path) { n += 1; file = folder.appendingPathComponent("\(name) \(n).\(ext)") }
            try data.write(to: file, options: .atomic)
            // 96 dpi screen pixels at 1:1.
            let w = Double(px.width) * 25.4 / 96 / doc.units.mm
            doc.ensureLayer("IMAGES")
            let id = doc.add(Entity(layer: "IMAGES", geometry: .image(ImagePlacement.placed(path: file.path, pixels: px, origin: at, width: w)),
                                    props: ["pixels": "\(px.width)x\(px.height)"]))
            return Result(kind: k, ids: [id], summary: "image \(px.width)×\(px.height) px")
        case .text, .file:
            let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { throw DocumentIO.IOError(message: "Empty text") }
            let h = Double(doc.variable("TEXTSIZE") ?? "") ?? 250
            let id = doc.add(.text(TextGeom(position: at, height: h, content: s)), layer: doc.currentLayer)
            return Result(kind: .text, ids: [id], summary: "text (\(s.count) characters)")
        }
    }

    static func imageExtension(_ d: Data) -> String {
        let b = [UInt8](d.prefix(12))
        if b.starts(with: [0x89, 0x50]) { return "png" }
        if b.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if b.starts(with: [0x47, 0x49]) { return "gif" }
        if b.starts(with: [0x42, 0x4D]) { return "bmp" }
        if b.starts(with: [0x49, 0x49]) || b.starts(with: [0x4D, 0x4D]) { return "tif" }
        if b.count >= 12, b[8] == 0x57, b[9] == 0x45 { return "webp" }
        return "heic"
    }

    public enum DropAction: String { case open, importFile, attachImage, attachPDF, runScript, unsupported }

    /// What dropping a file does: drawings open, scripts run, images/PDFs attach, other exchange formats import.
    public static func dropAction(for url: URL) -> DropAction {
        let e = url.pathExtension.lowercased()
        if ["archi", "archiz", "archit", ArchiTemplate.fileExtension].contains(e) { return .open }
        if ["scr", "js", "lsp", "py"].contains(e) { return .runScript }
        if e == "pdf" { return .attachPDF }
        if FileImport.format(for: url) == "image" { return .attachImage }
        if FileImport.importFormats.contains(e) { return .importFile }
        return .unsupported
    }

    /// Files whose coordinates are real-world (map / survey) positions: GIS formats, terrain grids, point clouds, survey
    /// point tables and images with a world file. Dropping them keeps their georeferenced place instead of the drop point.
    public static func isGeoreferenced(_ url: URL) -> Bool {
        let f = FileImport.format(for: url)
        if ["geojson", "shp", "osm", "cityjson", "asc", "dem", "las", "laz", "e57", "pointcloud", "csv"].contains(f) { return true }
        if f == "image" { return WorldFile.candidates(for: url).contains { FileManager.default.fileExists(atPath: $0.path) } }
        return false
    }

    /// Imports dropped files (not drawings or scripts) into `doc`, placing each at `at` (files side by side).
    /// Georeferenced files (see `isGeoreferenced`) land at their map position, converted with the project location.
    public static func drop(_ urls: [URL], into doc: inout ArchiDocument, at: Vec2 = .zero) -> [(url: URL, result: Result?, error: String?)] {
        var out: [(URL, Result?, String?)] = []
        var x = at
        for u in urls {
            do {
                let r: Result
                if isGeoreferenced(u) {
                    let (m, s) = try FileImport.importFile(u, into: &doc, offset: .zero)
                    out.append((u, Result(kind: .file, ids: m.allIDs, summary: s + " — georeferenced"), nil))
                    continue
                }
                switch dropAction(for: u) {
                case .attachImage:
                    r = try insert(Data(contentsOf: u), type: "image", into: &doc, at: x, assetFolder: u.deletingLastPathComponent(), name: u.deletingPathExtension().lastPathComponent)
                case .attachPDF:
                    let a = try PDFUnderlay.attach(u, page: 1, into: &doc, at: x)
                    r = Result(kind: .pdf, ids: [a], summary: "PDF underlay \(u.lastPathComponent)")
                case .importFile:
                    let (m, s) = try FileImport.importFile(u, into: &doc, offset: x)
                    r = Result(kind: .file, ids: m.allIDs, summary: s)
                case .open, .runScript, .unsupported:
                    out.append((u, nil, "not imported (\(dropAction(for: u).rawValue))")); continue
                }
                let b = r.ids.compactMap { id in doc.entity(id).map { GeometryOps.bounds($0.geometry, doc: doc) } }.reduce(BBox2.empty) { $0.union($1) }
                if !b.isEmpty { x = Vec2(b.max.x + max(b.width, b.height) * 0.1, at.y) }
                out.append((u, r, nil))
            } catch {
                out.append((u, nil, (error as? LocalizedError)?.errorDescription ?? "\(error)"))
            }
        }
        return out
    }
}
