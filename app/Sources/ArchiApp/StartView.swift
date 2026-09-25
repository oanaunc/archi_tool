// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers
import AppKit
import ArchiCore

/// Start screen shown in new windows until the user picks a template or opens a file: start actions, a template
/// gallery, the bundled sample projects as cards, and recent drawings with plan thumbnails.
struct StartView: View {
    @ObservedObject var model: AppModel
    @State private var recents: [URL] = []
    @State private var recovered: [AutosaveInfo] = []
    @State private var templates: [DrawingTemplate] = []

    private let samples: [(name: String, subtitle: String)] = [("Cedar House", "Contemporary house with materials"), ("Nordic House", "Nordic timber house")]

    var body: some View {
        ZStack {
            Theme.canvas.opacity(0.97).ignoresSafeArea()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        AppIconView(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Oanarina Archi Tool").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("Drafting and building design for the Mac").font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                        }
                    }
                    Text("START").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textDim).padding(.top, 4)
                    VStack(spacing: 8) {
                        StartTile(symbol: "square.and.pencil", title: "New Drawing", subtitle: AppPreferences.shared.defaultUnits == .inches || AppPreferences.shared.defaultUnits == .feet ? "Imperial" : "Metric · \(AppPreferences.shared.defaultUnits.rawValue)") { model.newDocument(.blankMetric) }
                        StartTile(symbol: "folder", title: "Open…", subtitle: ".archi projects and DXF drawings") { model.files.openPanel() }
                        StartTile(symbol: "house.lodge", title: "Build Sample House", subtitle: "Watch a house being drawn by commands") { model.newDocument(.sample); model.buildSampleHouse() }
                    }
                    if !recovered.isEmpty { recoverySection }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard").foregroundStyle(Theme.accent)
                        Text("Tip: just start typing — LINE, WALL, DOOR, ROOM… Space or Enter repeats the last command.")
                    }
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .frame(width: 300)
                .padding(24)
                VSeparator()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("TEMPLATES") {
                            Button("Folder") {
                                try? FileManager.default.createDirectory(at: FileLocations.templates, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([FileLocations.templates])
                            }
                            .buttonStyle(FlatButtonStyle(compact: true)).help("Put .archi files here to use them as templates (or SAVEASTEMPLATE)")
                            Button("Open Template…") {
                                let p = NSOpenPanel()
                                p.allowedContentTypes = [UTType(filenameExtension: TemplateLibrary.fileExtension) ?? .data, UTType(filenameExtension: ArchiFile.fileExtension) ?? .data]
                                p.message = "Choose a template (.architemplate) to start a new drawing from"
                                if p.runModal() == .OK, let u = p.url { TemplateLibrary.apply(TemplateLibrary.template(for: u), to: model) }
                            }
                            .buttonStyle(FlatButtonStyle(compact: true)).help("Start a new drawing from any .architemplate file")
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(templates) { t in
                                TemplateCard(title: t.name, subtitle: t.subtitle, symbol: t.symbol, url: t.url) { TemplateLibrary.apply(t, to: model) }
                            }
                        }
                        sectionHeader("SAMPLE PROJECTS") { EmptyView() }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                            ForEach(samples, id: \.name) { smp in
                                DocumentCard(title: smp.name, subtitle: smp.subtitle, url: SampleProjects.bundled(smp.name), accent: true) {
                                    if let url = SampleProjects.prepare(smp.name) { model.files.openURL(url) }
                                    else { model.newDocument(.sample); model.buildSampleHouse() }
                                }
                            }
                        }
                        sectionHeader("RECENT") {
                            if !recents.isEmpty { Button("Clear") { RecentFiles.clear(); recents = [] }.buttonStyle(FlatButtonStyle(compact: true)) }
                        }
                        if recents.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "clock").foregroundStyle(Theme.textFaint)
                                Text("No recent documents").font(Theme.font).foregroundStyle(Theme.textDim)
                            }
                            .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                                ForEach(recents, id: \.self) { url in
                                    DocumentCard(title: url.deletingPathExtension().lastPathComponent,
                                                 subtitle: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                                                    .map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? url.deletingLastPathComponent().lastPathComponent,
                                                 url: url) { model.files.load(url) }
                                        .help(url.path)
                                        .contextMenu {
                                            Button("Open") { model.files.load(url) }
                                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                            Button("Remove from List") { RecentFiles.remove(url); recents = RecentFiles.urls }
                                        }
                                }
                            }
                        }
                    }
                    .padding(22)
                }
                .frame(width: 600)
            }
            .frame(height: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "xmark", help: "Continue with an empty drawing") { model.showStart = false; model.canvas?.focus() }.padding(10)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .onAppear { recents = RecentFiles.urls; recovered = AutosaveManager.recoverable(); templates = TemplateLibrary.all() }
    }

    private func sectionHeader<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textDim)
            Spacer()
            trailing()
        }
    }

    /// Documents recovered from autosave after a crash.
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lifepreserver").foregroundStyle(Theme.accent)
                Text("RECOVERED DOCUMENTS").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.accent)
            }
            Text("These documents had unsaved changes when the app last quit unexpectedly.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            ForEach(recovered.prefix(3), id: \.id) { info in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(DateFormatter.localizedString(from: info.date, dateStyle: .medium, timeStyle: .short))
                            .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Button("Restore") { AutosaveManager.restore(info, into: model); recovered = AutosaveManager.recoverable() }
                        .buttonStyle(FlatButtonStyle(prominent: true, compact: true))
                    Button("Discard") { AutosaveManager.remove(info); recovered = AutosaveManager.recoverable() }
                        .buttonStyle(FlatButtonStyle(compact: true))
                }
                .padding(.horizontal, 8).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.08)))
            }
        }
    }
}

/// Template card (symbol, or a plan thumbnail for file templates).
private struct TemplateCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL?
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if url != nil { ThumbnailView(url: url, symbol: symbol).frame(height: 70) }
                else {
                    ZStack { RoundedRectangle(cornerRadius: 6).fill(Theme.canvas); Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Theme.accent) }
                        .frame(height: 70)
                }
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.hover : Theme.field.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovering ? Theme.accent.opacity(0.7) : Theme.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Drawing card with a plan thumbnail (samples and recent files).
private struct DocumentCard: View {
    let title: String
    let subtitle: String
    let url: URL?
    var accent = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(url: url, symbol: accent ? "house" : "building.columns").frame(height: 100)
                HStack(spacing: 5) {
                    if accent { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.accent) }
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                }
                Text(subtitle).font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.hover : Theme.field.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovering ? Theme.accent.opacity(0.7) : Theme.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct StartTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    var accent = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 30)
                    .foregroundStyle(accent ? Theme.accent : Theme.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(hovering ? Theme.accent : Theme.textFaint)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.hover : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(hovering ? Theme.accent.opacity(0.6) : Theme.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: url.pathExtension.lowercased() == "dxf" ? "doc.text" : "building.columns")
                    .foregroundStyle(Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    Text(d, style: .date).font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 8).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}

// MARK: - Sample house

extension AppModel {
    /// Builds a small single-storey house through the command line (like a user or an agent would),
    /// falling back to direct element creation for anything a command could not produce.
    func buildSampleHouse() {
        let ed = editor
        showStart = false
        Task { @MainActor in
            @MainActor func count(_ f: (BIMGeometry) -> Bool) -> Int { ed.doc.elements.filter { f($0.geometry) }.count }
            func isWall(_ g: BIMGeometry) -> Bool { if case .wall = g { return true }; return false }
            func isOpening(_ g: BIMGeometry, _ k: OpeningKind) -> Bool { if case .opening(let o) = g { return o.kind == k }; return false }
            ed.print("Building the sample house…")
            ed.settings.objectSnap = false
            ed.pickTolerance = 150
            let script: [String] = [
                "WALL 0,0 12000,0 12000,8000 0,8000 C",
                "WALL 5000,0 5000,8000",
                "WALL 5000,4500 12000,4500",
            ]
            for l in script { await ed.run(l) }
            if count(isWall) < 4 {
                ed.print("WALL command unavailable — creating walls directly.")
                ed.transaction("Sample walls") { d in
                    let segs: [(Vec2, Vec2)] = [(Vec2(0, 0), Vec2(12000, 0)), (Vec2(12000, 0), Vec2(12000, 8000)), (Vec2(12000, 8000), Vec2(0, 8000)), (Vec2(0, 8000), Vec2(0, 0)),
                                                (Vec2(5000, 0), Vec2(5000, 8000)), (Vec2(5000, 4500), Vec2(12000, 4500))]
                    for (a, b) in segs { d.addElement(.wall(WallGeom(start: a, end: b, thickness: a.y == b.y && (a.y == 0 || a.y == 8000) || a.x == b.x && (a.x == 0 || a.x == 12000) ? 300 : 120))) }
                }
            }
            let doors: [Vec2] = [Vec2(2500, 0), Vec2(5000, 6000), Vec2(8000, 4500)]
            let windows: [Vec2] = [Vec2(0, 4000), Vec2(8500, 0), Vec2(2500, 8000), Vec2(9000, 8000), Vec2(12000, 2200), Vec2(12000, 6200)]
            for p in doors { await ed.run("DOOR \(p.x),\(p.y)") }
            for p in windows { await ed.run("WINDOW \(p.x),\(p.y)") }
            func wallAt(_ p: Vec2, _ d: ArchiDocument) -> (EntityID, WallGeom)? {
                for el in d.elements { if case .wall(let w) = el.geometry, GeometryOps.distance(point: p, segA: w.start, segB: w.end) < 1 { return (el.id, w) } }
                return nil
            }
            if count({ isOpening($0, .door) }) == 0 || count({ isOpening($0, .window) }) == 0 {
                let needDoors = count({ isOpening($0, .door) }) == 0, needWindows = count({ isOpening($0, .window) }) == 0
                ed.transaction("Sample openings") { d in
                    for (list, kind) in [(needDoors ? doors : [], OpeningKind.door), (needWindows ? windows : [], OpeningKind.window)] {
                        for p in list {
                            guard let (id, w) = wallAt(p, d) else { continue }
                            let off = (p - w.start).dot(w.direction)
                            d.addElement(.opening(OpeningGeom(kind: kind, hostWall: id, offset: off, width: kind == .door ? 900 : 1200, height: kind == .door ? 2100 : 1200, sill: kind == .door ? 0 : 900)))
                        }
                    }
                }
            }
            await ed.run("SLAB -150,-150 12150,-150 12150,8150 -150,8150 C")
            if count({ if case .slab = $0 { return true }; return false }) == 0 {
                ed.transaction("Sample slab") { $0.addElement(.slab(SlabGeom(boundary: [Vec2(-150, -150), Vec2(12150, -150), Vec2(12150, 8150), Vec2(-150, 8150)]))) }
            }
            await ed.run("ROOF -150,-150 12150,-150 12150,8150 -150,8150 C")
            if count({ if case .roof = $0 { return true }; return false }) == 0 {
                ed.transaction("Sample roof") { $0.addElement(.roof(RoofGeom(boundary: [Vec2(-150, -150), Vec2(12150, -150), Vec2(12150, 8150), Vec2(-150, 8150)], kind: .gable, pitch: 30))) }
            }
            await ed.run("ROOM Name Living 2500,4000 Name Bedroom 8500,6250 Name Kitchen 8500,2250")
            if count({ if case .space = $0 { return true }; return false }) == 0 {
                ed.transaction("Sample rooms") { d in
                    let rooms: [(String, [Vec2])] = [("Living", [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 8000), Vec2(0, 8000)]),
                                                     ("Bedroom", [Vec2(5000, 4500), Vec2(12000, 4500), Vec2(12000, 8000), Vec2(5000, 8000)]),
                                                     ("Kitchen", [Vec2(5000, 0), Vec2(12000, 0), Vec2(12000, 4500), Vec2(5000, 4500)])]
                    for (i, r) in rooms.enumerated() { d.addElement(.space(SpaceGeom(boundary: r.1, name: r.0, number: "\(101 + i)"))) }
                }
            }
            for c in ["COMPONENT Bed 8500,6600", "COMPONENT Sofa 2500,6200", "COMPONENT Table 2500,3000", "COMPONENT Kitchen 8500,600"] { await ed.run(c) }
            let dimsBefore = ed.doc.entities.count
            await ed.run("DIMLINEAR 0,0 12000,0 6000,-1500")
            await ed.run("DIMLINEAR 12000,0 12000,8000 13500,4000")
            if ed.doc.entities.count == dimsBefore {
                ed.transaction("Sample dimensions") { d in
                    d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(12000, 0), Vec2(6000, -1500)], rotation: 0, style: d.currentDimStyle)), layer: "A-ANNO-DIMS")
                    d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(12000, 0), Vec2(12000, 8000), Vec2(13500, 4000)], rotation: .pi / 2, style: d.currentDimStyle)), layer: "A-ANNO-DIMS")
                }
            }
            ed.settings.objectSnap = true
            ed.selection = []
            ed.doc.info.name = "Sample House"
            ed.isDirty = true
            ed.print("Sample house ready: \(ed.doc.elements.count) building elements. Switch to 3D (View ▸ 3D) to explore it.")
            self.revision &+= 1
            self.zoomExtents()
        }
    }
}


/// Sample projects bundled in Resources/Samples. They are copied (with their textures) to
/// ~/Documents/Oanarina Archi Tool/Samples so they can be edited and saved.
enum SampleProjects {
    /// The bundled (read-only) sample file, for thumbnails.
    static func bundled(_ name: String) -> URL? {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent("Samples").appendingPathComponent(name + ".archi"),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
    static func prepare(_ name: String) -> URL? {
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("Samples") else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.appendingPathComponent(name + ".archi").path),
              let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dest = docs.appendingPathComponent("Oanarina Archi Tool/Samples", isDirectory: true)
        do {
            try fm.createDirectory(at: dest.appendingPathComponent("textures"), withIntermediateDirectories: true)
            for t in (try? fm.contentsOfDirectory(atPath: src.appendingPathComponent("textures").path)) ?? [] {
                let to = dest.appendingPathComponent("textures").appendingPathComponent(t)
                if !fm.fileExists(atPath: to.path) { try fm.copyItem(at: src.appendingPathComponent("textures").appendingPathComponent(t), to: to) }
            }
            let file = dest.appendingPathComponent(name + ".archi")
            if !fm.fileExists(atPath: file.path) { try fm.copyItem(at: src.appendingPathComponent(name + ".archi"), to: file) }
            return file
        } catch { return nil }
    }
}
