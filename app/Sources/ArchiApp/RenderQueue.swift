// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import UniformTypeIdentifiers
import ArchiCore

// MARK: - Keyframed camera paths (VIS-042)

/// A camera key at a time (seconds) on a path.
struct CameraKey: Codable, Hashable {
    var name: String
    var time: Double
    var camera: Camera
}

/// A named camera animation: keys at times, played back along a smooth (Catmull-Rom) path through the keys.
struct CameraPathDef: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var keys: [CameraKey] = []
    var fps: Int = 30
    var duration: Double { keys.map(\.time).max() ?? 0 }

    /// Keys in time order.
    var sorted: [CameraKey] { keys.sorted { $0.time < $1.time } }

    /// Camera at a time: exactly the key cameras at the key times, smooth in between, clamped at both ends.
    func sample(at time: Double) -> Camera? {
        let k = sorted
        guard let first = k.first else { return nil }
        if k.count == 1 || time <= first.time { return first.camera }
        if time >= k.last!.time { return k.last!.camera }
        var i = 0
        while i + 1 < k.count - 1 && k[i + 1].time <= time { i += 1 }
        let span = max(k[i + 1].time - k[i].time, 1e-9)
        let u = min(max((time - k[i].time) / span, 0), 1)
        return CameraPath.sample(k.map(\.camera), t: (Double(i) + u) / Double(k.count - 1))
    }

    /// Spreads the keys evenly over `seconds` keeping their order.
    mutating func retime(total seconds: Double) {
        let k = sorted
        guard k.count > 1 else { if !keys.isEmpty { keys[0].time = 0 }; return }
        keys = k.enumerated().map { i, key in var c = key; c.time = seconds * Double(i) / Double(k.count - 1); return c }
    }
}

enum CameraPaths {
    static let variable = "CAMERAPATHS"
    static func load(_ doc: ArchiDocument) -> [CameraPathDef] {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CameraPathDef].self, from: d)) ?? []
    }
    static func store(_ paths: [CameraPathDef], in doc: inout ArchiDocument) {
        if paths.isEmpty { doc.variables[variable] = nil; return }
        if let d = try? JSONEncoder().encode(paths), let s = String(data: d, encoding: .utf8) { doc.setVariable(variable, s) }
    }
    static func uniqueName(_ base: String, in paths: [CameraPathDef]) -> String {
        var n = base, k = 2
        while paths.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { n = "\(base) \(k)"; k += 1 }
        return n
    }
}

enum CameraPathWindow {
    private static var window: NSPanel?
    @MainActor static func show(model: AppModel) {
        if model.mode == .plan || model.mode == .sheet { model.mode = .model }
        let v = CameraPathEditor(model: model)
        if let w = window { w.contentViewController = NSHostingController(rootView: v.preferredColorScheme(Theme.colorScheme)); w.makeKeyAndOrderFront(nil); return }
        window = ReviewUI.panel("Camera Paths", key: "ArchiCameraPaths", size: NSSize(width: 460, height: 560), content: v)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Camera path editor with a timeline: keys from the current 3D view or saved cameras, times, scrubbing and playback in
/// the 3D viewport, and video export of the path.
struct CameraPathEditor: View {
    @ObservedObject var model: AppModel
    @State private var current = ""
    @State private var time = 0.0
    @State private var playing = false
    @State private var timer: Timer?
    @State private var status = ""
    @State private var progress = 0.0
    @State private var exporting = false

    private var paths: [CameraPathDef] { CameraPaths.load(model.doc) }
    private var path: CameraPathDef? { paths.first { $0.name == current } ?? paths.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Path", selection: Binding(get: { path?.name ?? "" }, set: { current = $0; time = 0 })) {
                    ForEach(paths) { Text($0.name).tag($0.name) }
                }.frame(maxWidth: 240)
                Button("New") { edit("New Camera Path") { ps in let n = CameraPaths.uniqueName("Path", in: ps); ps.append(CameraPathDef(name: n)); current = n } }
                    .buttonStyle(FlatButtonStyle(compact: true))
                if let p = path {
                    Button("Delete") { edit("Delete Camera Path") { ps in ps.removeAll { $0.name == p.name } }; current = "" }.buttonStyle(FlatButtonStyle(compact: true))
                }
            }
            if let p = path {
                HStack {
                    Button("Add Current View") { addCurrent(p) }.buttonStyle(FlatButtonStyle(compact: true))
                    Menu("Add Saved Camera") {
                        ForEach(model.doc.namedViews.filter { $0.camera != nil }, id: \.name) { v in
                            Button(v.name) { addKey(p, name: v.name, camera: v.camera!) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    Button("Even Timing") { edit("Retime Camera Path") { ps in if let i = ps.firstIndex(where: { $0.name == p.name }) { ps[i].retime(total: max(p.duration, Double(max(p.keys.count - 1, 1)) * 3)) } } }
                        .buttonStyle(FlatButtonStyle(compact: true)).disabled(p.keys.count < 2)
                }
                List {
                    ForEach(Array(p.sorted.enumerated()), id: \.offset) { i, k in
                        HStack {
                            Text("\(i + 1)").font(Theme.mono).foregroundStyle(Theme.textDim).frame(width: 20)
                            Text(k.name).font(Theme.font)
                            Spacer()
                            TextField("s", value: Binding(get: { k.time }, set: { v in setTime(p, key: k, v) }), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.plain).padding(2).darkField().frame(width: 56)
                            Text("s").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                            Button { time = k.time; show(p) } label: { Image(systemName: "eye") }.buttonStyle(.plain).help("Show this key in the 3D view")
                            Button { edit("Delete Camera Key") { ps in if let j = ps.firstIndex(where: { $0.name == p.name }) { ps[j].keys.removeAll { $0 == k } } } } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).help("Delete the key")
                        }
                    }
                }.listStyle(.plain).frame(minHeight: 160)
                // Timeline.
                HStack {
                    Button { togglePlay(p) } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }.buttonStyle(.plain).disabled(p.keys.count < 2)
                    Slider(value: Binding(get: { time }, set: { time = $0; show(p) }), in: 0...max(p.duration, 0.1))
                    Text("\(fmt(time, 1)) / \(fmt(p.duration, 1)) s").font(Theme.mono).frame(width: 90)
                }
                timelineMarks(p)
                HStack {
                    Stepper("FPS \(p.fps)", value: Binding(get: { p.fps }, set: { v in edit("Camera Path FPS") { ps in if let i = ps.firstIndex(where: { $0.name == p.name }) { ps[i].fps = max(1, min(60, v)) } } }), in: 1...60)
                    Spacer()
                    Button("Export Video…") { export(p) }.buttonStyle(FlatButtonStyle()).disabled(p.keys.count < 2 || exporting)
                    Button("Queue Frames") { queueFrames(p) }.buttonStyle(FlatButtonStyle(compact: true)).disabled(p.keys.isEmpty)
                        .help("Adds one render job per key to the render queue")
                }
                if exporting { ProgressView(value: progress) }
            } else {
                Text("Create a path, then add keys from the current 3D view or from saved cameras. Keys are played back along a smooth path at their times.")
                    .font(Theme.font).foregroundStyle(Theme.textDim)
                Spacer()
            }
            if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
        .padding(10)
        .background(Theme.panel)
        .frame(minWidth: 400, minHeight: 420)
        .onDisappear { timer?.invalidate(); timer = nil; playing = false }
    }

    private func timelineMarks(_ p: CameraPathDef) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.textFaint.opacity(0.4)).frame(height: 2)
                ForEach(Array(p.sorted.enumerated()), id: \.offset) { _, k in
                    Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(Theme.accent)
                        .offset(x: CGFloat(k.time / max(p.duration, 0.1)) * (g.size.width - 8))
                }
            }
        }.frame(height: 12).padding(.horizontal, 24)
    }

    private func edit(_ label: String, _ f: @escaping (inout [CameraPathDef]) -> Void) {
        model.editor.transaction(label) { d in var ps = CameraPaths.load(d); f(&ps); CameraPaths.store(ps, in: &d) }
        model.revision &+= 1
    }
    private func addKey(_ p: CameraPathDef, name: String, camera: Camera) {
        let t = p.keys.isEmpty ? 0 : p.duration + 3
        edit("Add Camera Key") { ps in if let i = ps.firstIndex(where: { $0.name == p.name }) { ps[i].keys.append(CameraKey(name: name, time: t, camera: camera)) } }
        time = t
    }
    private func addCurrent(_ p: CameraPathDef) {
        guard let c = Viewport3DController.active?.currentCamera else { status = "Open the 3D view first."; return }
        addKey(p, name: "Key \(p.keys.count + 1)", camera: c)
    }
    private func setTime(_ p: CameraPathDef, key: CameraKey, _ v: Double) {
        edit("Camera Key Time") { ps in
            if let i = ps.firstIndex(where: { $0.name == p.name }), let j = ps[i].keys.firstIndex(of: key) { ps[i].keys[j].time = max(0, v) }
        }
    }
    private func show(_ p: CameraPathDef) {
        guard let c = p.sample(at: time), let v = Viewport3DController.active else { return }
        RenderEngine.place(v.cameraNode, at: c)
    }
    private func togglePlay(_ p: CameraPathDef) {
        if playing { timer?.invalidate(); timer = nil; playing = false; return }
        playing = true
        if time >= p.duration { time = 0 }
        let start = Date(), t0 = time
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { t in
            MainActor.assumeIsolated {
                time = min(p.duration, t0 + Date().timeIntervalSince(start))
                show(p)
                if time >= p.duration { t.invalidate(); timer = nil; playing = false }
            }
        }
    }
    private func export(_ p: CameraPathDef) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(model.doc.info.name) \(p.name).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true; progress = 0
        var s = RenderSettings(); s.width = 1280; s.height = 720
        let doc = model.doc, frames = max(2, Int(p.duration * Double(p.fps)) + 1), fps = p.fps
        Task { @MainActor in
            do {
                try await RenderEngine.writeVideo(doc: doc, settings: s, frames: frames, fps: fps, to: url, setup: { i, _, cam in
                    if let c = p.sample(at: Double(i) / Double(fps)) { RenderEngine.place(cam, at: c) }
                }, progress: { progress = $0 })
                status = "Saved \(url.lastPathComponent) (\(frames) frames)."
            } catch { status = "Video export failed: \(error.localizedDescription)" }
            exporting = false
        }
    }
    private func queueFrames(_ p: CameraPathDef) {
        for k in p.sorted { RenderQueue.shared.add(name: "\(p.name) – \(k.name)", camera: k.camera, preset: nil) }
        RenderQueueWindow.show(model: model)
    }
}

// MARK: - Render queue and history (VIS-076, VIS-079)

@MainActor
final class RenderQueue: ObservableObject {
    static let shared = RenderQueue()
    enum Status: Equatable { case pending, running, done(URL), failed(String) }
    struct Job: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var camera: Camera?
        var preset: String?
        var width = 1920
        var height = 1080
        var status: Status = .pending
        var seconds = 0.0
    }
    struct HistoryItem: Codable, Hashable, Identifiable { var id: String { path }; var path: String; var name: String; var date: Date; var seconds: Double }

    @Published var jobs: [Job] = []
    @Published private(set) var running = false
    @Published var history: [HistoryItem] = []
    private var cancelRequested = false
    private let historyKey = "render.history"

    var outputFolder: URL {
        get {
            if let p = UserDefaults.standard.string(forKey: "render.queueFolder") { return URL(fileURLWithPath: p, isDirectory: true) }
            return (FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Archi Renders", isDirectory: true)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: "render.queueFolder"); objectWillChange.send() }
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: historyKey), let h = try? JSONDecoder().decode([HistoryItem].self, from: d) {
            history = h.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func add(name: String, camera: Camera?, preset: String?, width: Int = 1920, height: Int = 1080) {
        jobs.append(Job(name: name, camera: camera, preset: preset, width: width, height: height))
    }
    var pendingCount: Int { jobs.filter { $0.status == .pending }.count }

    /// File name for a job: safe characters, numbered when the name repeats in the folder.
    static func fileName(_ name: String, existing: Set<String>) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        var base = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "Render" }
        var n = base + ".png", k = 2
        while existing.contains(n.lowercased()) { n = "\(base) \(k).png"; k += 1 }
        return n
    }

    /// Renders the pending jobs one after the other (the app stays responsive between jobs).
    func start(model: AppModel) {
        guard !running else { return }
        running = true; cancelRequested = false
        let folder = outputFolder
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            while !cancelRequested, let i = jobs.firstIndex(where: { $0.status == .pending }) {
                jobs[i].status = .running
                await Task.yield()
                let job = jobs[i]
                var s = RenderSettings()
                if let pn = job.preset, let p = RenderPreset.all.first(where: { $0.name == pn }) { p.apply(to: &s) }
                s.width = job.width; s.height = job.height
                var override: SCNMatrix4?
                if let c = job.camera ?? Viewport3DController.active?.currentCamera {
                    let n = SCNNode(); n.camera = SCNCamera(); RenderEngine.place(n, at: c); override = n.transform
                }
                let t0 = Date()
                let img = RenderEngine.render(doc: model.doc, settings: s, camera: override)
                let secs = Date().timeIntervalSince(t0)
                guard let j = jobs.firstIndex(where: { $0.id == job.id }) else { continue }
                jobs[j].seconds = secs
                let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map { $0.lowercased() })
                let url = folder.appendingPathComponent(Self.fileName(job.name, existing: existing))
                if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    do {
                        try png.write(to: url, options: .atomic)
                        jobs[j].status = .done(url)
                        history.insert(HistoryItem(path: url.path, name: job.name, date: Date(), seconds: secs), at: 0)
                        if history.count > 50 { history.removeLast(history.count - 50) }
                        saveHistory()
                    } catch { jobs[j].status = .failed(error.localizedDescription) }
                } else { jobs[j].status = .failed("Rendering failed (Metal unavailable)") }
            }
            running = false
            model.editor.print("Render queue finished: \(jobs.filter { if case .done = $0.status { return true }; return false }.count) image(s) in \(folder.path).")
        }
    }
    func cancel() { cancelRequested = true }
    func clearFinished() { jobs.removeAll { if case .pending = $0.status { return false }; if case .running = $0.status { return false }; return true } }
    func saveHistory() { if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: historyKey) } }
}

enum RenderQueueWindow {
    private static var window: NSPanel?
    @MainActor static func show(model: AppModel) {
        let v = RenderQueueView(model: model, queue: .shared)
        if let w = window { w.contentViewController = NSHostingController(rootView: v.preferredColorScheme(Theme.colorScheme)); w.makeKeyAndOrderFront(nil); return }
        window = ReviewUI.panel("Render Queue", key: "ArchiRenderQueue", size: NSSize(width: 520, height: 560), content: v)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct RenderQueueView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var queue: RenderQueue
    @State private var preset = ""
    @State private var size = "1920×1080"
    private let sizes = ["1280×720", "1920×1080", "2560×1440", "3840×2160", "2048×2048"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Preset", selection: $preset) { Text("Default").tag(""); ForEach(RenderPreset.all) { Text($0.name).tag($0.name) } }.frame(width: 200)
                Picker("Size", selection: $size) { ForEach(sizes, id: \.self) { Text($0) } }.frame(width: 150)
            }
            HStack {
                Button("Add Current View") { add("\(model.doc.info.name) – view \(queue.jobs.count + 1)", Viewport3DController.active?.currentCamera) }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Add Saved Cameras") { for v in model.doc.namedViews { if let c = v.camera { add("\(model.doc.info.name) – \(v.name)", c) } } }
                    .buttonStyle(FlatButtonStyle(compact: true)).disabled(!model.doc.namedViews.contains { $0.camera != nil })
                Spacer()
                Button("Folder…") { chooseFolder() }.buttonStyle(FlatButtonStyle(compact: true)).help(queue.outputFolder.path)
            }
            List {
                ForEach(queue.jobs) { j in
                    HStack {
                        statusIcon(j.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(j.name).font(Theme.font)
                            Text("\(j.width)×\(j.height)\(j.preset.map { " · " + $0 } ?? "")\(j.seconds > 0 ? " · \(fmt(j.seconds, 1)) s" : "")\(statusText(j.status))")
                                .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        if j.status == .pending { Button { queue.jobs.removeAll { $0.id == j.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    }
                }
            }.listStyle(.plain).frame(minHeight: 140)
            HStack {
                Button(queue.running ? "Stop After Current" : "Render \(queue.pendingCount) Job(s)") { if queue.running { queue.cancel() } else { queue.start(model: model) } }
                    .buttonStyle(FlatButtonStyle()).disabled(!queue.running && queue.pendingCount == 0)
                Button("Clear Finished") { queue.clearFinished() }.buttonStyle(FlatButtonStyle(compact: true))
                Spacer()
                Text(queue.outputFolder.lastPathComponent).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }
            HSeparator()
            Text("Render history").font(Theme.fontBold)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(queue.history) { h in
                        VStack(spacing: 2) {
                            HistoryThumb(path: h.path).frame(width: 120, height: 68)
                            Text(h.name).font(.system(size: 9)).lineLimit(1).frame(width: 120)
                            Text("\(DateFormatter.localizedString(from: h.date, dateStyle: .short, timeStyle: .short)) · \(fmt(h.seconds, 1)) s").font(.system(size: 8)).foregroundStyle(Theme.textDim)
                        }
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(fileURLWithPath: h.path)) }
                        .contextMenu {
                            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: h.path)) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: h.path)]) }
                            Button("Remove from History") { queue.history.removeAll { $0 == h }; queue.saveHistory() }
                        }
                    }
                }
            }.frame(height: 100)
        }
        .padding(10)
        .background(Theme.panel)
        .frame(minWidth: 460, minHeight: 440)
    }

    private func add(_ name: String, _ cam: Camera?) {
        let p = size.split(separator: "×").compactMap { Int($0) }
        queue.add(name: name, camera: cam, preset: preset.isEmpty ? nil : preset, width: p.first ?? 1920, height: p.last ?? 1080)
    }
    @ViewBuilder private func statusIcon(_ s: RenderQueue.Status) -> some View {
        switch s {
        case .pending: Image(systemName: "clock").foregroundStyle(Theme.textDim)
        case .running: Image(systemName: "hourglass").foregroundStyle(Theme.accent)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
        }
    }
    private func statusText(_ s: RenderQueue.Status) -> String {
        switch s { case .failed(let m): return " · " + m; case .done(let u): return " · " + u.lastPathComponent; default: return "" }
    }
    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.message = "Choose the folder for queued renders"
        if p.runModal() == .OK, let u = p.url { queue.outputFolder = u }
    }
}

private struct HistoryThumb: View {
    let path: String
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.3))
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) } else { Image(systemName: "photo").foregroundStyle(Theme.textDim) }
        }
        .task { image = NSImage(contentsOfFile: path) }
    }
}
