// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Custom node packages (SCR-015)

/// A shareable package of node-graph snippets (reusable sub-graphs) with a name, version, author and description,
/// saved as a `.archinodes` JSON file. Installed packages live in the user's library and their snippets can be
/// inserted into any graph (node ids are remapped, links kept), so shared graphs evaluate exactly like the original.
struct NodeSnippet: Codable, Equatable {
    var name: String
    var description = ""
    var graph: NodeGraph
    init(name: String, description: String = "", graph: NodeGraph) { self.name = name; self.description = description; self.graph = graph }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        graph = try c.decodeIfPresent(NodeGraph.self, forKey: .graph) ?? NodeGraph()
    }
}

struct NodePackage: Codable, Equatable {
    var format = NodePackage.formatID
    var name: String
    var version = "1.0"
    var author = ""
    var description = ""
    var snippets: [NodeSnippet] = []
    static let formatID = "oanarina-archi-nodes"
    static let fileExtension = "archinodes"

    init(name: String, version: String = "1.0", author: String = "", description: String = "", snippets: [NodeSnippet] = []) {
        self.name = name; self.version = version; self.author = author; self.description = description; self.snippets = snippets
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? NodePackage.formatID
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        snippets = try c.decodeIfPresent([NodeSnippet].self, forKey: .snippets) ?? []
    }
    func data() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return try e.encode(self) }
    static func decode(_ d: Data) throws -> NodePackage {
        let p = try JSONDecoder().decode(NodePackage.self, from: d)
        guard p.format == formatID else { throw CommandError.invalid("Not an Oanarina node package.") }
        guard !p.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.invalid("The package has no name.") }
        return p
    }
}

extension NodeGraph {
    /// The nodes with the given ids and the links between them, moved so the top-left node sits at the origin.
    func subgraph(_ ids: Set<Int>) -> NodeGraph {
        var g = NodeGraph()
        let sel = nodes.filter { ids.contains($0.id) }
        let x0 = sel.map(\.x).min() ?? 0, y0 = sel.map(\.y).min() ?? 0
        g.nodes = sel.map { var n = $0; n.x -= x0; n.y -= y0; return n }
        g.links = links.filter { ids.contains($0.from) && ids.contains($0.to) }
        g.nextID = (sel.map(\.id).max() ?? 0) + 1
        return g
    }

    /// Inserts another graph's nodes and links at an offset with fresh ids; returns old id → new id.
    @discardableResult
    mutating func insert(_ other: NodeGraph, x: Double, y: Double) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for n in other.nodes.sorted(by: { $0.id < $1.id }) {
            var m = n
            m.id = nextID; m.x = n.x + x; m.y = n.y + y
            map[n.id] = nextID
            nodes.append(m); nextID += 1
        }
        for l in other.links { if let f = map[l.from], let t = map[l.to] { links.append(GraphLink(from: f, to: t, port: l.port)) } }
        return map
    }
}

@MainActor
enum NodePackages {
    static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let u = base.appendingPathComponent("Oanarina Archi Tool/NodePackages", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func fileName(_ name: String) -> String { name.replacingOccurrences(of: "/", with: "-") + "." + NodePackage.fileExtension }

    static func installed() -> [NodePackage] {
        guard let f = folder, let files = try? FileManager.default.contentsOfDirectory(at: f, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == NodePackage.fileExtension }
            .compactMap { try? NodePackage.decode(Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Installs (copies) a package file into the library; replaces a package of the same name.
    @discardableResult static func install(_ url: URL) throws -> NodePackage {
        let p = try NodePackage.decode(Data(contentsOf: url))
        try install(p)
        return p
    }
    static func install(_ p: NodePackage) throws {
        guard let f = folder else { throw CommandError.invalid("No library folder.") }
        try p.data().write(to: f.appendingPathComponent(fileName(p.name)))
    }
    static func remove(_ name: String) throws {
        guard let f = folder else { return }
        try FileManager.default.removeItem(at: f.appendingPathComponent(fileName(name)))
    }
    static func package(named n: String) -> NodePackage? { installed().first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }

    /// A package from a graph: one snippet per titled group, or the whole graph when it has no groups.
    static func make(from g: NodeGraph, name: String, author: String = "", description: String = "") -> NodePackage {
        var snippets: [NodeSnippet] = g.groups.compactMap { fr in
            let ids = Set(g.members(of: fr))
            return ids.isEmpty ? nil : NodeSnippet(name: fr.title, graph: g.subgraph(ids))
        }
        if snippets.isEmpty && !g.nodes.isEmpty { snippets = [NodeSnippet(name: name, graph: g.subgraph(Set(g.nodes.map(\.id))))] }
        return NodePackage(name: name, author: author, description: description, snippets: snippets)
    }
}

/// Packages menu of the node editor: insert installed snippets, package the current graph, install or remove files.
struct NodePackagesMenu: View {
    @Binding var graph: NodeGraph
    @Binding var status: String
    var body: some View {
        Menu {
            let pkgs = NodePackages.installed()
            if pkgs.isEmpty { Text("No packages installed") }
            ForEach(pkgs, id: \.name) { p in
                Menu("\(p.name) \(p.version)") {
                    ForEach(p.snippets, id: \.name) { s in
                        Button(s.name) {
                            let x = (graph.nodes.map(\.x).max() ?? 0) + 260
                            graph.insert(s.graph, x: graph.nodes.isEmpty ? 40 : x, y: 40)
                            status = "Inserted “\(s.name)” from \(p.name)."
                        }
                    }
                    Divider()
                    Button("Remove Package") { try? NodePackages.remove(p.name); status = "Removed \(p.name)." }
                }
            }
            Divider()
            Button("Save Graph as Package…") { savePackage() }
            Button("Install Package…") { installPackage() }
            Button("Show Library Folder") { if let f = NodePackages.folder { NSWorkspace.shared.activateFileViewerSelecting([f]) } }
        } label: { Label("Packages", systemImage: "shippingbox") }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Custom node packages: reusable graph snippets shared as .archinodes files")
    }
    private func savePackage() {
        let p = NSSavePanel(); p.nameFieldStringValue = "My Nodes." + NodePackage.fileExtension
        guard p.runModal() == .OK, let u = p.url else { return }
        let pkg = NodePackages.make(from: graph, name: u.deletingPathExtension().lastPathComponent, author: NSFullUserName())
        do { try pkg.data().write(to: u); try NodePackages.install(pkg); status = "Package \(pkg.name): \(pkg.snippets.count) snippet(s)." } catch { status = error.localizedDescription }
    }
    private func installPackage() {
        let p = NSOpenPanel()
        guard p.runModal() == .OK, let u = p.url else { return }
        do { let pkg = try NodePackages.install(u); status = "Installed \(pkg.name) \(pkg.version)." } catch { status = error.localizedDescription }
    }
}
