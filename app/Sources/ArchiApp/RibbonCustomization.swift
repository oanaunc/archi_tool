// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Customisable ribbon (APP-016, CUI)

/// User ribbon panels added to any tab (title, ordered commands, optional icons), built-in panels hidden by title,
/// reorder panels and buttons, export/import as a JSON file. Every custom button runs the same command line as typing
/// it, with the command's icon and summary as tooltip. Stored in the user defaults (pref.ribbonCustomization).
struct CustomRibbonPanel: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var tab: String
    /// Command lines (a command name, optionally with arguments: "ZOOM E").
    var commands: [String]
    /// Icon (SF Symbol) per command line; missing = the command's default icon.
    var symbols: [String: String] = [:]

    init(title: String, tab: String, commands: [String], symbols: [String: String] = [:]) { self.title = title; self.tab = tab; self.commands = commands; self.symbols = symbols }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Custom"
        tab = try c.decodeIfPresent(String.self, forKey: .tab) ?? RibbonTab.home.rawValue
        commands = try c.decodeIfPresent([String].self, forKey: .commands) ?? []
        symbols = try c.decodeIfPresent([String: String].self, forKey: .symbols) ?? [:]
    }
    func symbol(for line: String) -> String { symbols[line] ?? QuickAccess.symbol(for: line.split(separator: " ").first.map(String.init) ?? line) }
}

struct RibbonCustomization: Codable, Equatable {
    var format = "oanarina-archi-cui"
    var version = 1
    var panels: [CustomRibbonPanel] = []
    /// Built-in ribbon panels hidden by title.
    var hiddenPanels: [String] = []
    /// Quick access toolbar (exported and imported with the customisation).
    var quickAccess: [String]?

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "oanarina-archi-cui"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        panels = try c.decodeIfPresent([CustomRibbonPanel].self, forKey: .panels) ?? []
        hiddenPanels = try c.decodeIfPresent([String].self, forKey: .hiddenPanels) ?? []
        quickAccess = try c.decodeIfPresent([String].self, forKey: .quickAccess)
    }

    func panels(for tab: String) -> [CustomRibbonPanel] { panels.filter { $0.tab == tab } }

    /// Command lines whose command is not registered (reported on import).
    func unknownCommands(_ r: CommandRegistry) -> [String] {
        panels.flatMap(\.commands).filter { line in r.lookup(String(line.split(separator: " ").first ?? "")) == nil }
    }

    mutating func movePanel(_ id: UUID, by d: Int) {
        guard let i = panels.firstIndex(where: { $0.id == id }) else { return }
        // Move among the panels of the same tab.
        let same = panels.indices.filter { panels[$0].tab == panels[i].tab }
        guard let k = same.firstIndex(of: i), same.indices.contains(k + d) else { return }
        panels.swapAt(i, same[k + d])
    }
    mutating func moveCommand(panel id: UUID, from i: Int, by d: Int) {
        guard let p = panels.firstIndex(where: { $0.id == id }), panels[p].commands.indices.contains(i), panels[p].commands.indices.contains(i + d) else { return }
        panels[p].commands.swapAt(i, i + d)
    }

    func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    static func decode(_ data: Data) throws -> RibbonCustomization {
        let c = try JSONDecoder().decode(RibbonCustomization.self, from: data)
        guard c.format == "oanarina-archi-cui" else { throw CommandError.invalid("Not an Oanarina Archi Tool ribbon customisation file.") }
        return c
    }
}

@MainActor
enum RibbonCustom {
    static let key = "pref.ribbonCustomization"
    static var current: RibbonCustomization {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(RibbonCustomization.self, from: $0) } ?? RibbonCustomization() }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) }
            AppPreferences.shared.objectWillChange.send()
        }
    }
    static func isHidden(_ title: String) -> Bool { current.hiddenPanels.contains(title) }

    static func export(to url: URL) throws {
        var c = current
        c.quickAccess = AppPreferences.shared.quickAccess
        try c.encoded().write(to: url)
    }
    /// Imports a customisation file; returns the command lines that are unknown in this build.
    @discardableResult static func importFile(_ url: URL, registry: CommandRegistry = .shared) throws -> [String] {
        let c = try RibbonCustomization.decode(try Data(contentsOf: url))
        current = c
        if let q = c.quickAccess, !q.isEmpty { AppPreferences.shared.quickAccess = q.filter { registry.lookup($0) != nil } }
        return c.unknownCommands(registry)
    }
}

/// The custom panels of a ribbon tab (appended after the built-in panels).
struct CustomRibbonPanels: View {
    @ObservedObject var model: AppModel
    let tab: String
    @ObservedObject private var prefs = AppPreferences.shared
    var body: some View {
        ForEach(RibbonCustom.current.panels(for: tab)) { p in
            RibbonGroup(title: p.title) {
                ForEach(Array(p.commands.enumerated()), id: \.offset) { _, line in
                    let name = String(line.split(separator: " ").first ?? "")
                    let def = model.editor.registry.lookup(name)
                    RibbonButton(title: def.map { CommandCatalog.title(for: $0.name) } ?? name, symbol: p.symbol(for: line), size: p.commands.count > 4 ? .small : .large,
                                 active: def != nil && model.editor.activeCommand?.name == def?.name, enabled: def != nil,
                                 help: def.map { "\(line) — \($0.summary)" } ?? "\(name) is not available in this build") {
                        model.runCommand(line)
                    }
                }
            }
        }
    }
}

extension CommandCatalog {
    /// Ribbon title of a command (from the catalogs), or its name in title case.
    static func title(for name: String) -> String {
        if let i = curatedItems.first(where: { $0.names.first?.uppercased() == name.uppercased() }) { return i.title }
        return name.capitalized
    }
}

// MARK: - CUI window

private struct CUIView: View {
    @State private var custom = RibbonCustom.current
    @State private var selected: UUID?
    @State private var newCommand = ""
    @State private var hideTitle = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Customize Ribbon").font(Theme.fontBold)
                Spacer()
                Button("Import…") { importFile() }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Export…") { exportFile() }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Reset") { custom = RibbonCustomization(); save() }.buttonStyle(FlatButtonStyle(compact: true))
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Panels").foregroundStyle(Theme.textDim)
                    List(selection: $selected) {
                        ForEach(custom.panels) { p in Text("\(p.tab) ▸ \(p.title)").tag(p.id) }
                    }
                    .frame(width: 220, height: 260)
                    HStack {
                        IconButton(symbol: "plus", help: "New panel") {
                            let p = CustomRibbonPanel(title: "My Tools", tab: RibbonTab.home.rawValue, commands: [])
                            custom.panels.append(p); selected = p.id; save()
                        }
                        IconButton(symbol: "minus", help: "Delete panel") { custom.panels.removeAll { $0.id == selected }; selected = nil; save() }.disabled(selected == nil)
                        IconButton(symbol: "arrow.up", help: "Move panel left") { if let s = selected { custom.movePanel(s, by: -1); save() } }.disabled(selected == nil)
                        IconButton(symbol: "arrow.down", help: "Move panel right") { if let s = selected { custom.movePanel(s, by: 1); save() } }.disabled(selected == nil)
                    }
                }
                if let i = custom.panels.firstIndex(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: Binding(get: { custom.panels[i].title }, set: { custom.panels[i].title = $0; save() })).darkField()
                        Picker("Tab", selection: Binding(get: { custom.panels[i].tab }, set: { custom.panels[i].tab = $0; save() })) {
                            ForEach(RibbonTab.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        ForEach(Array(custom.panels[i].commands.enumerated()), id: \.offset) { k, line in
                            HStack(spacing: 6) {
                                Image(systemName: custom.panels[i].symbol(for: line)).frame(width: 18).foregroundStyle(Theme.accent)
                                Text(line).font(Theme.mono)
                                Spacer()
                                IconButton(symbol: "arrow.up", help: "Move up") { custom.moveCommand(panel: custom.panels[i].id, from: k, by: -1); save() }.disabled(k == 0)
                                IconButton(symbol: "arrow.down", help: "Move down") { custom.moveCommand(panel: custom.panels[i].id, from: k, by: 1); save() }.disabled(k == custom.panels[i].commands.count - 1)
                                IconButton(symbol: "minus.circle", help: "Remove") { custom.panels[i].commands.remove(at: k); save() }
                            }
                        }
                        HStack {
                            TextField("Command (e.g. ZOOM E)", text: $newCommand).darkField().onSubmit { add(i) }
                            Button("Add") { add(i) }.buttonStyle(FlatButtonStyle(compact: true))
                        }
                    }
                    .frame(minWidth: 300)
                } else {
                    Text("Select or add a panel.").foregroundStyle(Theme.textDim).frame(minWidth: 300)
                }
            }
            Divider()
            Text("Hidden built-in panels").foregroundStyle(Theme.textDim)
            HStack {
                TextField("Panel title (e.g. Selection)", text: $hideTitle).darkField().frame(width: 220)
                Button("Hide") { let t = hideTitle.trimmingCharacters(in: .whitespaces); if !t.isEmpty && !custom.hiddenPanels.contains(t) { custom.hiddenPanels.append(t); save() }; hideTitle = "" }
                    .buttonStyle(FlatButtonStyle(compact: true))
                ForEach(custom.hiddenPanels, id: \.self) { t in
                    Button("\(t) ✕") { custom.hiddenPanels.removeAll { $0 == t }; save() }.buttonStyle(FlatButtonStyle(compact: true))
                }
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
        .font(Theme.font)
        .padding(12)
        .frame(minWidth: 620, minHeight: 420)
        .background(Theme.panel)
    }
    private func save() { RibbonCustom.current = custom }
    private func add(_ i: Int) {
        let line = newCommand.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        guard CommandRegistry.shared.lookup(String(line.split(separator: " ").first ?? "")) != nil else { message = "Unknown command: \(line)"; return }
        custom.panels[i].commands.append(line.uppercased()); newCommand = ""; message = ""; save()
    }
    private func exportFile() {
        let p = NSSavePanel(); p.allowedContentTypes = [.json]; p.nameFieldStringValue = "Ribbon.archicui.json"
        if p.runModal() == .OK, let u = p.url { do { try RibbonCustom.export(to: u); message = "Exported." } catch { message = error.localizedDescription } }
    }
    private func importFile() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            let unknown = try RibbonCustom.importFile(u)
            custom = RibbonCustom.current
            message = unknown.isEmpty ? "Imported." : "Imported; unknown commands: " + unknown.joined(separator: ", ")
        } catch { message = error.localizedDescription }
    }
}

@MainActor
enum CUIWindow {
    private static var window: NSWindow?
    static func show() {
        let view = CUIView().preferredColorScheme(Theme.colorScheme)
        if let w = window { w.contentViewController = NSHostingController(rootView: view); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Customize Ribbon"; w.isReleasedWhenClosed = false; w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: view)
        w.center(); w.makeKeyAndOrderFront(nil)
        window = w
    }
}

// MARK: - Full screen state across relaunch (APP-004)

@MainActor
enum FullScreenState {
    static let key = "window.lastFullScreen"
    private static var observed = Set<ObjectIdentifier>()
    private static var restored = false
    static var lastFullScreen: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    /// Remembers entering/leaving full screen; the first drawing window after launch goes back to full screen.
    /// Minimum size small enough for Split View halves.
    static func track(_ w: NSWindow) {
        if w.minSize.width > 560 { w.minSize.width = 560 }
        if w.minSize.height > 420 { w.minSize.height = 420 }
        let id = ObjectIdentifier(w)
        guard !observed.contains(id) else { return }
        observed.insert(id)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: w, queue: .main) { _ in MainActor.assumeIsolated { lastFullScreen = true } }
        nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { if !NSApp.isTerminating() { lastFullScreen = false } }
        }
        guard !restored, lastFullScreen else { return }
        restored = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak w] in
            MainActor.assumeIsolated {
                guard let w, AppModel.all.contains(where: { $0.window === w }), !w.styleMask.contains(.fullScreen) else { return }
                w.toggleFullScreen(nil)
            }
        }
    }
}

private extension NSApplication {
    /// Set while the app quits (full-screen windows closing then must not clear the remembered state).
    func isTerminating() -> Bool { FullScreenQuit.quitting }
}
enum FullScreenQuit { static var quitting = false }
