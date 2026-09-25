// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// An external reference: a drawing (.archi or .dxf) shown as a block whose content is reloaded from its file.
public struct XrefInfo: Codable, Hashable {
    public var name: String
    /// Path as attached (absolute, or relative to the host drawing's folder).
    public var path: String
    /// Overlay xrefs are not carried into drawings that reference this one (nested xrefs are).
    public var overlay: Bool
    public var loaded: Bool
    /// File modification time when last loaded (seconds since 1970), for change notification.
    public var loadedModified: Double?
    public init(name: String, path: String, overlay: Bool = false, loaded: Bool = true, loadedModified: Double? = nil) {
        self.name = name; self.path = path; self.overlay = overlay; self.loaded = loaded; self.loadedModified = loadedModified
    }
    private enum K: String, CodingKey { case name, path, overlay, loaded, loadedModified }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name); path = try c.decode(String.self, forKey: .path)
        overlay = try c.decodeIfPresent(Bool.self, forKey: .overlay) ?? false
        loaded = try c.decodeIfPresent(Bool.self, forKey: .loaded) ?? true
        loadedModified = try c.decodeIfPresent(Double.self, forKey: .loadedModified)
    }
}

/// External references (XREF / XATTACH / XBIND): the registry is stored in the document variable XREFS; the content is a block
/// named after the xref whose objects use layers "XREF|LAYER" (layer 0 stays 0) and nested blocks "XREF|BLOCK".
public enum Xrefs {
    public static let variable = "XREFS"
    public static let separator = "|"

    public enum XrefError: Error, LocalizedError, Equatable {
        case notFound(String), unreadable(String), circular(String), invalidName(String)
        public var errorDescription: String? {
            switch self {
            case .notFound(let n): return "Xref \(n) not found."
            case .unreadable(let p): return "Cannot read \(p)."
            case .circular(let n): return "Xref \(n) would reference itself."
            case .invalidName(let n): return "Invalid xref name \(n)."
            }
        }
    }

    public static func all(_ doc: ArchiDocument) -> [XrefInfo] { VarJSON.load(doc, variable, as: [XrefInfo].self) ?? [] }
    public static func store(_ x: [XrefInfo], _ doc: inout ArchiDocument) { VarJSON.save(x.sorted { $0.name < $1.name }, &doc, variable, empty: x.isEmpty) }
    public static func named(_ n: String, _ doc: ArchiDocument) -> XrefInfo? { all(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public static func isXref(_ block: String, _ doc: ArchiDocument) -> Bool { named(block, doc) != nil }

    /// Resolves a stored path against the host drawing's folder.
    public static func resolve(_ path: String, base: URL?) -> URL {
        let p = (path as NSString).expandingTildeInPath
        if p.hasPrefix("/") { return URL(fileURLWithPath: p) }
        if let b = base { return b.appendingPathComponent(p).standardizedFileURL }
        return URL(fileURLWithPath: p)
    }
    static func modified(_ url: URL) -> Double? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let d = a[.modificationDate] as? Date else { return nil }
        return d.timeIntervalSince1970
    }

    /// Builds the block and layers of an xref from its source drawing.
    static func content(of src: ArchiDocument, name: String) -> (block: Block, layers: [Layer], blocks: [String: Block]) {
        let overlays = Set(all(src).filter(\.overlay).map { $0.name })
        func lay(_ l: String) -> String { l == "0" ? "0" : name + separator + l }
        func blk(_ b: String) -> String { name + separator + b }
        func convert(_ es: [Entity]) -> [Entity] {
            es.compactMap { e in
                var e = e
                if case .insert(var i) = e.geometry {
                    if overlays.contains(i.block) { return nil }
                    i.block = blk(i.block); e.geometry = .insert(i)
                }
                e.layer = lay(e.layer)
                return e
            }
        }
        var base = Vec2.zero
        if let b = src.variable("INSBASE") {
            let p = b.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count >= 2 { base = Vec2(p[0], p[1]) }
        }
        var blocks: [String: Block] = [:]
        for (k, b) in src.blocks where !overlays.contains(k) {
            blocks[blk(k)] = Block(name: blk(k), basePoint: b.basePoint, entities: convert(b.entities), description: b.description)
        }
        let layers = src.layers.filter { $0.name != "0" }.map { l -> Layer in var x = l; x.name = lay(l.name); return x }
        return (Block(name: name, basePoint: base, entities: convert(src.entities), description: "xref"), layers, blocks)
    }

    /// Loads (or reloads) the content of an xref into the document. Existing xref layer settings are kept (VISRETAIN).
    static func load(_ info: XrefInfo, src: ArchiDocument, into doc: inout ArchiDocument) {
        let c = content(of: src, name: info.name)
        let prefix = (info.name + separator).lowercased()
        // Drop nested blocks from a previous load.
        for k in doc.blocks.keys where k.lowercased().hasPrefix(prefix) { doc.blocks[k] = nil }
        for (k, b) in c.blocks { doc.blocks[k] = b }
        doc.blocks[info.name] = c.block
        let retain = doc.variable("VISRETAIN") != "0"
        for l in c.layers {
            if let i = doc.layerIndex(l.name) { if !retain { doc.layers[i] = l } } else { doc.layers.append(l) }
        }
    }

    static func readSource(_ url: URL) throws -> ArchiDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { throw XrefError.unreadable(url.path) }
        do { return try FileImport.load(url).0 } catch { throw XrefError.unreadable(url.path) }
    }

    /// Attaches (or overlays) a drawing file. Returns the xref name; place it with an insert of that block.
    @discardableResult
    public static func attach(_ doc: inout ArchiDocument, path: String, name: String? = nil, overlay: Bool = false, base: URL? = nil, host: URL? = nil) throws -> String {
        let url = resolve(path, base: base)
        let n = name ?? url.deletingPathExtension().lastPathComponent
        guard !n.isEmpty, !n.contains(separator), n.rangeOfCharacter(from: CharacterSet(charactersIn: "<>/\\\":;?*=`")) == nil else { throw XrefError.invalidName(n) }
        if let h = host, h.standardizedFileURL.path == url.standardizedFileURL.path { throw XrefError.circular(n) }
        let src = try readSource(url)
        if let h = host, all(src).contains(where: { resolve($0.path, base: url.deletingLastPathComponent()).standardizedFileURL.path == h.standardizedFileURL.path && !$0.overlay }) {
            throw XrefError.circular(n)
        }
        if doc.blocks[n] != nil && !isXref(n, doc) { throw XrefError.invalidName("\(n) (a block with that name exists)") }
        let info = XrefInfo(name: n, path: path, overlay: overlay, loaded: true, loadedModified: modified(url))
        load(info, src: src, into: &doc)
        store(all(doc).filter { $0.name.caseInsensitiveCompare(n) != .orderedSame } + [info], &doc)
        return n
    }

    /// Reloads xrefs from their files (all when `names` is nil). Returns the names reloaded.
    @discardableResult
    public static func reload(_ doc: inout ArchiDocument, names: [String]? = nil, base: URL? = nil) throws -> [String] {
        var list = all(doc)
        var done: [String] = []
        for i in list.indices where names.map({ ns in ns.contains { $0.caseInsensitiveCompare(list[i].name) == .orderedSame } }) ?? true {
            let url = resolve(list[i].path, base: base)
            let src = try readSource(url)
            list[i].loaded = true; list[i].loadedModified = modified(url)
            load(list[i], src: src, into: &doc)
            done.append(list[i].name)
        }
        store(list, &doc)
        return done
    }

    /// Unloads an xref: its references stay but draw nothing until reloaded.
    public static func unload(_ doc: inout ArchiDocument, name: String) throws {
        var list = all(doc)
        guard let i = list.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw XrefError.notFound(name) }
        list[i].loaded = false
        doc.blocks[list[i].name]?.entities = []
        store(list, &doc)
    }

    /// Detaches an xref: removes its references, block, nested blocks and xref layers.
    public static func detach(_ doc: inout ArchiDocument, name: String) throws {
        guard let info = named(name, doc) else { throw XrefError.notFound(name) }
        let prefix = (info.name + separator).lowercased()
        let ids = doc.entities.filter { if case .insert(let i) = $0.geometry { return i.block == info.name }; return false }.map(\.id)
        doc.remove(ids: Set(ids))
        for li in doc.layouts.indices { doc.layouts[li].entities.removeAll { if case .insert(let i) = $0.geometry { return i.block == info.name }; return false } }
        doc.blocks[info.name] = nil
        for k in doc.blocks.keys where k.lowercased().hasPrefix(prefix) { doc.blocks[k] = nil }
        doc.layers.removeAll { $0.name.lowercased().hasPrefix(prefix) }
        if doc.layer(named: doc.currentLayer) == nil { doc.currentLayer = "0" }
        store(all(doc).filter { $0.name != info.name }, &doc)
    }

    /// Binds an xref into the drawing as an ordinary block. Bind renames "X|NAME" to "X$0$NAME"; Insert merges into "NAME"
    /// (existing layers/blocks with that name win).
    public static func bind(_ doc: inout ArchiDocument, name: String, insert: Bool = false) throws {
        guard let info = named(name, doc) else { throw XrefError.notFound(name) }
        guard info.loaded else { throw XrefError.unreadable("\(name) (unloaded)") }
        let prefix = info.name + separator
        func renamed(_ s: String) -> String {
            guard s.lowercased().hasPrefix(prefix.lowercased()) else { return s }
            let rest = String(s.dropFirst(prefix.count))
            if insert { return rest }
            var k = 0
            while true { let c = "\(info.name)$\(k)$\(rest)"; if doc.layer(named: c) == nil && doc.blocks[c] == nil { return c }; k += 1 }
        }
        var layerMap: [String: String] = [:]
        for l in doc.layers where l.name.lowercased().hasPrefix(prefix.lowercased()) { layerMap[l.name] = renamed(l.name) }
        var blockMap: [String: String] = [:]
        for k in doc.blocks.keys where k.lowercased().hasPrefix(prefix.lowercased()) { blockMap[k] = renamed(k) }
        func fix(_ e: Entity) -> Entity {
            var e = e
            if let n = layerMap[e.layer] { e.layer = n }
            if case .insert(var i) = e.geometry, let n = blockMap[i.block] { i.block = n; e.geometry = .insert(i) }
            return e
        }
        var newLayers: [Layer] = []
        for l in doc.layers {
            guard let n = layerMap[l.name] else { newLayers.append(l); continue }
            if doc.layers.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) || newLayers.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { continue }
            var x = l; x.name = n; newLayers.append(x)
        }
        doc.layers = newLayers
        var blocks: [String: Block] = [:]
        for (k, b) in doc.blocks {
            let nk = blockMap[k] ?? k
            if blockMap[k] != nil, insert, doc.blocks[nk] != nil, nk != k { continue }
            var nb = b; nb.name = nk; nb.entities = b.entities.map(fix)
            blocks[nk] = nb
        }
        blocks[info.name]?.description = ""
        doc.blocks = blocks
        store(all(doc).filter { $0.name != info.name }, &doc)
    }

    /// Xrefs whose files changed since they were loaded (XREFNOTIFY).
    public static func changed(_ doc: ArchiDocument, base: URL?) -> [String] {
        all(doc).filter { x in
            guard x.loaded, let m = modified(resolve(x.path, base: base)) else { return false }
            return m > (x.loadedModified ?? 0) + 1e-3
        }.map(\.name)
    }
    /// Xrefs whose files are missing.
    public static func missing(_ doc: ArchiDocument, base: URL?) -> [String] {
        all(doc).filter { !FileManager.default.fileExists(atPath: resolve($0.path, base: base).path) }.map(\.name)
    }
}

// MARK: - Block library

/// Browses folders of drawings (.archi / .dxf) as block libraries: each file is an insertable block and its own block
/// definitions are available too.
public enum BlockLibrary {
    public struct Item: Hashable {
        /// The drawing file.
        public var file: URL
        /// Block inside the drawing, nil = the whole drawing.
        public var block: String?
        public var name: String { block ?? file.deletingPathExtension().lastPathComponent }
        /// Folder path relative to the library root ("" for the root).
        public var folder: String
    }
    public static let extensions: Set<String> = ["archi", "dxf"]

    /// Scans a library folder (recursively). With `blocks` the block definitions inside each file are listed too.
    public static func scan(_ root: URL, recursive: Bool = true, blocks: Bool = true) -> [Item] {
        let fm = FileManager.default
        var out: [Item] = []
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in en where extensions.contains(url.pathExtension.lowercased()) {
            let dir = url.deletingLastPathComponent().standardizedFileURL.path
            var folder = dir.hasPrefix(rootPath) ? String(dir.dropFirst(rootPath.count)) : dir
            if folder.hasPrefix("/") { folder.removeFirst() }
            out.append(Item(file: url, block: nil, folder: folder))
            if blocks, let d = try? FileImport.load(url).0 {
                for k in d.blocks.keys.sorted() where !k.hasPrefix("*") && !k.contains(Xrefs.separator) { out.append(Item(file: url, block: k, folder: folder)) }
            }
        }
        return out.sorted { ($0.folder, $0.file.lastPathComponent, $0.block ?? "") < ($1.folder, $1.file.lastPathComponent, $1.block ?? "") }
    }
    /// Case-insensitive search on item name, file name and folder (all words must match).
    public static func search(_ items: [Item], _ query: String) -> [Item] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { i in
            let hay = "\(i.name) \(i.file.lastPathComponent) \(i.folder)".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
    /// Copies a library item into the document as a block definition (with nested blocks and layers). Returns the block name.
    @discardableResult
    public static func load(_ item: Item, into doc: inout ArchiDocument) throws -> String {
        let src: ArchiDocument
        do { src = try FileImport.load(item.file).0 } catch { throw Xrefs.XrefError.unreadable(item.file.path) }
        for l in src.layers where doc.layer(named: l.name) == nil { doc.layers.append(l) }
        let name = item.name
        func nested(_ n: String, depth: Int) {
            guard depth < 16, let b = src.blocks[n] else { return }
            for e in b.entities { if case .insert(let i) = e.geometry, doc.blocks[i.block] == nil, let nb = src.blocks[i.block] { doc.blocks[i.block] = nb; nested(i.block, depth: depth + 1) } }
        }
        if let b = item.block {
            guard let def = src.blocks[b] else { throw Xrefs.XrefError.notFound(b) }
            doc.blocks[name] = def
            nested(b, depth: 0)
        } else {
            var base = Vec2.zero
            if let s = src.variable("INSBASE") {
                let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if p.count >= 2 { base = Vec2(p[0], p[1]) }
            }
            doc.blocks[name] = Block(name: name, basePoint: base, entities: src.entities)
            for e in src.entities { if case .insert(let i) = e.geometry, doc.blocks[i.block] == nil, src.blocks[i.block] != nil { doc.blocks[i.block] = src.blocks[i.block]; nested(i.block, depth: 1) } }
        }
        return name
    }
}
