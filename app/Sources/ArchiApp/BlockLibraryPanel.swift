// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

/// Block library / content browser (BLK-007, BLK-038, BLK-039, BLK-041): user library folders of drawings, each file and
/// each block inside it shown with a thumbnail rendered from its draw list, searchable, with favourites and recents.
/// Items are dragged onto the plan canvas (or the 3D view) to insert them, or inserted with a double-click.
@MainActor
final class BlockLibraryStore: ObservableObject {
    static let shared = BlockLibraryStore()
    private let d = UserDefaults.standard
    @Published var folders: [String] { didSet { d.set(folders, forKey: "blockLibrary.folders") } }
    @Published var current: String? { didSet { d.set(current, forKey: "blockLibrary.current"); rescan() } }
    @Published private(set) var items: [BlockLibrary.Item] = []
    @Published var favourites: [String] { didSet { d.set(favourites, forKey: "blockLibrary.favourites") } }
    @Published var recents: [String] { didSet { d.set(recents, forKey: "blockLibrary.recents") } }
    private var docs: [String: ArchiDocument] = [:]
    private var thumbs: [String: NSImage] = [:]

    init() {
        folders = d.stringArray(forKey: "blockLibrary.folders") ?? []
        favourites = d.stringArray(forKey: "blockLibrary.favourites") ?? []
        recents = d.stringArray(forKey: "blockLibrary.recents") ?? []
        current = d.string(forKey: "blockLibrary.current") ?? folders.first
        rescan()
    }

    /// Stable key of an item: file path + block name (unit separator).
    static func key(_ i: BlockLibrary.Item) -> String { i.file.path + "\u{1F}" + (i.block ?? "") }
    /// Items of one folder (non-recursive), cached by folder modification date.
    private static var folderCache: [String: (Date, [BlockLibrary.Item])] = [:]
    static func item(fromKey k: String) -> BlockLibrary.Item? {
        let p = k.components(separatedBy: "\u{1F}")
        guard p.count == 2, FileManager.default.fileExists(atPath: p[0]) else { return nil }
        let file = URL(fileURLWithPath: p[0]), dir = file.deletingLastPathComponent()
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let items: [BlockLibrary.Item]
        if let c = folderCache[dir.path], c.0 >= mtime { items = c.1 }
        else { items = BlockLibrary.scan(dir, recursive: false); folderCache[dir.path] = (Date(), items) }
        return items.first { $0.file.standardizedFileURL.path == file.standardizedFileURL.path && ($0.block ?? "") == p[1] }
    }

    func addFolder(_ url: URL) {
        let p = url.standardizedFileURL.path
        if !folders.contains(p) { folders.append(p) }
        current = p
    }
    func removeFolder(_ p: String) {
        folders.removeAll { $0 == p }
        if current == p { current = folders.first }
    }
    func rescan() {
        docs = [:]
        guard let c = current else { items = []; return }
        items = BlockLibrary.scan(URL(fileURLWithPath: c, isDirectory: true))
    }
    func toggleFavourite(_ i: BlockLibrary.Item) {
        let k = Self.key(i)
        if let j = favourites.firstIndex(of: k) { favourites.remove(at: j) } else { favourites.append(k) }
    }
    func noteUsed(_ i: BlockLibrary.Item) {
        let k = Self.key(i)
        recents.removeAll { $0 == k }
        recents.insert(k, at: 0)
        if recents.count > 12 { recents.removeLast(recents.count - 12) }
    }

    /// Source drawing of an item (cached per file).
    func document(_ file: URL) -> ArchiDocument? {
        if let d = docs[file.path] { return d }
        guard let d = try? FileImport.load(file).0 else { return nil }
        docs[file.path] = d
        return d
    }

    /// Document containing only what the item draws: the whole drawing, or one reference of the block at the origin.
    static func previewDocument(_ i: BlockLibrary.Item, source: ArchiDocument) -> ArchiDocument {
        guard let b = i.block, source.blocks[b] != nil else { return source }
        var d = source
        d.entities = []
        d.elements = []
        _ = d.add(.insert(InsertGeom(block: b, position: source.blocks[b]!.basePoint)), layer: source.layers.first?.name ?? "0")
        return d
    }

    /// Thumbnail rendered from the item's draw entries (cached by file, modification date and block).
    func thumbnail(_ i: BlockLibrary.Item) -> NSImage? {
        let mtime = (try? i.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let k = Self.key(i) + "|\(Int(mtime))"
        if let t = thumbs[k] { return t }
        guard let src = document(i.file) else { return nil }
        let img = DocumentThumbnails.render(Self.previewDocument(i, source: src), size: CGSize(width: 120, height: 90))
        thumbs[k] = img
        return img
    }

    /// Drag payload understood by `ToolDrop` ("archi-libblock:path␟block").
    static func dragString(_ i: BlockLibrary.Item) -> String { ToolDrop.libraryBlockPrefix + key(i) }

    /// Copies the item into the drawing (one undo step) and inserts one reference at `p`. Returns the new reference id.
    @discardableResult
    func insert(_ i: BlockLibrary.Item, at p: Vec2, model: AppModel) -> EntityID? {
        var id: EntityID?
        var failure: String?
        model.editor.transaction("Insert \(i.name)") { d in
            do {
                let name = try BlockLibrary.load(i, into: &d)
                id = d.add(.insert(InsertGeom(block: name, position: p)), layer: d.currentLayer)
            } catch { failure = "\(error)" }
        }
        if let failure { model.editor.print("Could not load \(i.name): \(failure)"); return nil }
        if let id { model.editor.selection = [id]; noteUsed(i); model.editor.print("Inserted \(i.name) from the block library at \(fmt(p.x, 2)),\(fmt(p.y, 2)).") }
        return id
    }
}

enum BlockLibraryWindow {
    private static var window: NSWindow?
    @MainActor static func show(model: AppModel) {
        let view = BlockLibraryView(model: model, store: .shared).preferredColorScheme(Theme.colorScheme)
        if let w = window { w.contentViewController = NSHostingController(rootView: view); w.makeKeyAndOrderFront(nil); return }
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        w.title = "Block Library"
        w.isReleasedWhenClosed = false
        w.isFloatingPanel = true
        w.hidesOnDeactivate = true
        w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: view)
        w.setFrameAutosaveName("ArchiBlockLibrary")
        if w.frame.origin == .zero { w.center() }
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct BlockLibraryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: BlockLibraryStore
    @State private var query = ""
    @State private var scope = "Folder"
    @State private var selected: String?

    private var shown: [BlockLibrary.Item] {
        switch scope {
        case "Favourites": return BlockLibrary.search(store.favourites.compactMap(BlockLibraryStore.item(fromKey:)), query)
        case "Recent": return BlockLibrary.search(store.recents.compactMap(BlockLibraryStore.item(fromKey:)), query)
        default: return BlockLibrary.search(store.items, query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(store.folders, id: \.self) { f in
                        Button { store.current = f } label: { if f == store.current { Label(f, systemImage: "checkmark") } else { Text(f) } }
                    }
                    Divider()
                    Button("Add Library Folder…") { chooseFolder() }
                    if let c = store.current { Button("Remove \(URL(fileURLWithPath: c).lastPathComponent) from the List") { store.removeFolder(c) } }
                } label: { Label(store.current.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose a folder", systemImage: "folder").font(Theme.font) }
                .menuStyle(.borderlessButton).frame(maxWidth: 180)
                IconButton(symbol: "folder.badge.plus", help: "Add a library folder of .archi / .dxf drawings") { chooseFolder() }
                IconButton(symbol: "arrow.clockwise", help: "Rescan the folder") { store.rescan() }
                Picker("", selection: $scope) { ForEach(["Folder", "Favourites", "Recent"], id: \.self) { Text($0) } }
                    .pickerStyle(.segmented).frame(width: 220).labelsHidden()
            }
            .padding(8)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                TextField("Search blocks, files and folders", text: $query).textFieldStyle(.plain).font(Theme.font)
            }
            .padding(6).darkField().padding(.horizontal, 8)
            HSeparator().padding(.top, 6)
            if store.current == nil && scope == "Folder" {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(Theme.textDim)
                    Text("Choose a folder of drawings to use as a block library.").font(Theme.font).foregroundStyle(Theme.textDim)
                    Button("Choose Folder…") { chooseFolder() }.buttonStyle(FlatButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                        ForEach(shown, id: \.self) { i in cell(i) }
                    }
                    .padding(8)
                }
            }
            HSeparator()
            Text("\(shown.count) item(s) · drag onto the drawing to insert · double-click inserts at the view centre")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).padding(6)
        }
        .background(Theme.panel)
        .frame(minWidth: 420, minHeight: 360)
    }

    private func cell(_ i: BlockLibrary.Item) -> some View {
        let k = BlockLibraryStore.key(i)
        let fav = store.favourites.contains(k)
        return VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = store.thumbnail(i) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit) }
                    else { Image(systemName: "questionmark.square.dashed").font(.system(size: 28)).foregroundStyle(Theme.textDim) }
                }
                .frame(width: 120, height: 90)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.25)))
                Button { store.toggleFavourite(i) } label: { Image(systemName: fav ? "star.fill" : "star").foregroundStyle(fav ? Theme.accent : Theme.textDim) }
                    .buttonStyle(.plain).padding(4).help(fav ? "Remove from favourites" : "Add to favourites")
            }
            Text(i.name).font(Theme.fontSmall).foregroundStyle(Theme.text).lineLimit(1)
            Text(i.block == nil ? (i.folder.isEmpty ? "drawing" : i.folder) : i.file.deletingPathExtension().lastPathComponent)
                .font(.system(size: 9)).foregroundStyle(Theme.textDim).lineLimit(1)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected == k ? Theme.accent.opacity(0.25) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { insertAtCentre(i) }
        .onTapGesture { selected = k }
        .onDrag { NSItemProvider(object: BlockLibraryStore.dragString(i) as NSString) }
        .help("\(i.file.path)\(i.block.map { " ▸ " + $0 } ?? "")")
        .contextMenu {
            Button("Insert at View Centre") { insertAtCentre(i) }
            Button(fav ? "Remove from Favourites" : "Add to Favourites") { store.toggleFavourite(i) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([i.file]) }
        }
    }

    private func insertAtCentre(_ i: BlockLibrary.Item) {
        let p = model.canvas?.viewCenterWorld ?? .zero
        store.insert(i, at: p, model: model)
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.message = "Choose a folder of drawings (.archi, .dxf) to browse as a block library"
        if p.runModal() == .OK, let u = p.url {
            store.addFolder(u)
        }
    }
}
