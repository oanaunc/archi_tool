// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

/// Application-wide preferences (OPTIONS), persisted in UserDefaults and applied without restart.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let d = UserDefaults.standard

    // MARK: Display
    @Published var accentHex: UInt32 { didSet { d.set(Int(accentHex), forKey: "pref.accentHex"); ThemeColors.accentHex = accentHex; changed() } }
    @Published var canvasHex: UInt32 { didSet { d.set(Int(canvasHex), forKey: "pref.canvasHex"); ThemeColors.canvasHex = canvasHex; changed() } }
    /// Crosshair length as a percentage of the canvas (AutoCAD CURSORSIZE, 1…100).
    @Published var cursorSize: Int { didSet { d.set(cursorSize, forKey: "pref.cursorSize"); changed() } }

    // MARK: Files
    /// Minutes between autosaves (0 = off).
    @Published var autosaveMinutes: Int { didSet { d.set(autosaveMinutes, forKey: "pref.autosaveMinutes"); AutosaveManager.rescheduleAll() } }
    @Published var recentLimit: Int { didSet { d.set(recentLimit, forKey: "pref.recentLimit") } }
    @Published var runStartupScript: Bool { didSet { d.set(runStartupScript, forKey: "pref.runStartupScript") } }

    // MARK: New drawings
    @Published var defaultUnits: Units { didSet { d.set(defaultUnits.rawValue, forKey: "pref.defaultUnits") } }
    /// Drafting defaults for new drawings (grid spacing is in millimetres).
    @Published var draft: DraftSettings { didSet { if let data = try? JSONEncoder().encode(draft) { d.set(data, forKey: "pref.draft") } } }

    // MARK: Keyboard and toolbar
    /// Custom keyboard shortcuts: normalized key combination → command line.
    @Published var shortcuts: [String: String] { didSet { d.set(shortcuts, forKey: "pref.shortcuts") } }
    /// Commands on the quick access toolbar (left to right).
    @Published var quickAccess: [String] { didSet { d.set(quickAccess, forKey: "pref.quickAccess"); changed() } }

    // MARK: Agents
    @Published var agentPort: Int { didSet { d.set(agentPort, forKey: "pref.agentPort") } }
    @Published var agentAutoStart: Bool { didSet { d.set(agentAutoStart, forKey: "pref.agentAutoStart") } }

    static let defaultAccent: UInt32 = 0xF5C518
    static let defaultCanvas: UInt32 = 0x1E1F22
    static let defaultQuickAccess = ["NEW", "OPEN", "SAVE", "UNDO", "REDO", "PLOT"]
    static let accentPresets: [(String, UInt32)] = [("Archi Yellow", 0xF5C518), ("Orange", 0xFF8A3D), ("Red", 0xE5534B), ("Pink", 0xE86FB0),
                                                     ("Purple", 0xA27BF0), ("Blue", 0x4C9AFF), ("Teal", 0x2EC4B6), ("Green", 0x5CC96B)]
    static let canvasPresets: [(String, UInt32)] = [("Graphite", 0x1E1F22), ("Black", 0x000000), ("Model Blue", 0x21283A), ("Slate", 0x2B2F36), ("Dark Green", 0x1C2620)]

    private init() {
        let ud = UserDefaults.standard
        func int(_ k: String, _ def: Int) -> Int { ud.object(forKey: k) as? Int ?? def }
        accentHex = UInt32(truncatingIfNeeded: int("pref.accentHex", Int(AppPreferences.defaultAccent)))
        canvasHex = UInt32(truncatingIfNeeded: int("pref.canvasHex", Int(AppPreferences.defaultCanvas)))
        cursorSize = int("pref.cursorSize", 10)
        autosaveMinutes = int("pref.autosaveMinutes", 5)
        recentLimit = int("pref.recentLimit", 12)
        runStartupScript = ud.object(forKey: "pref.runStartupScript") as? Bool ?? true
        defaultUnits = Units(rawValue: ud.string(forKey: "pref.defaultUnits") ?? "") ?? .millimeters
        draft = (ud.data(forKey: "pref.draft")).flatMap { try? JSONDecoder().decode(DraftSettings.self, from: $0) } ?? DraftSettings()
        shortcuts = ud.dictionary(forKey: "pref.shortcuts") as? [String: String] ?? [:]
        quickAccess = ud.stringArray(forKey: "pref.quickAccess") ?? AppPreferences.defaultQuickAccess
        agentPort = int("pref.agentPort", 47800)
        agentAutoStart = ud.bool(forKey: "pref.agentAutoStart")
        ThemeColors.accentHex = accentHex
        ThemeColors.canvasHex = canvasHex
    }

    /// Restores every preference to its default (Reset to defaults).
    func resetToDefaults() {
        accentHex = AppPreferences.defaultAccent
        canvasHex = AppPreferences.defaultCanvas
        cursorSize = 10
        autosaveMinutes = 5
        recentLimit = 12
        runStartupScript = true
        defaultUnits = .millimeters
        draft = DraftSettings()
        shortcuts = [:]
        quickAccess = AppPreferences.defaultQuickAccess
        agentPort = 47800
        agentAutoStart = false
    }

    /// Redraws every open window so display preferences apply immediately.
    func changed() {
        for m in AppModel.all { m.canvas?.invalidateCache(); m.revision &+= 1 }
    }

    /// Drafting defaults for a new drawing in the given units (the grid spacing is converted from millimetres).
    func draftDefaults(base: DraftSettings, units: Units) -> DraftSettings {
        var s = base
        s.showGrid = draft.showGrid
        s.gridSnap = draft.gridSnap
        s.ortho = draft.ortho
        s.polarTracking = draft.polarTracking && !draft.ortho
        s.polarIncrement = draft.polarIncrement
        s.objectSnap = draft.objectSnap
        s.snapModes = draft.snapModes
        s.dynamicInput = draft.dynamicInput
        s.lineweightDisplay = draft.lineweightDisplay
        if units == .millimeters || units == .centimeters || units == .meters {
            s.gridSpacing = max(draft.gridSpacing / units.mm, 1e-6)
        }
        return s
    }
}

/// Theme colors that follow the preferences.
enum ThemeColors {
    static var accentHex: UInt32 = {
        (UserDefaults.standard.object(forKey: "pref.accentHex") as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? 0xF5C518
    }()
    static var canvasHex: UInt32 = {
        (UserDefaults.standard.object(forKey: "pref.canvasHex") as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? 0x1E1F22
    }()
}

// MARK: - Keyboard shortcuts

/// A key combination such as ⇧⌘W, stored normalized as "shift+cmd+w".
struct KeyCombo: Hashable, CustomStringConvertible {
    var command = false, shift = false, option = false, control = false
    var key: String

    static let specialKeys: [UInt16: String] = [
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape", 123: "left", 124: "right", 125: "down", 126: "up",
        115: "home", 119: "end", 116: "pageup", 121: "pagedown",
    ]

    init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased(); self.command = command; self.shift = shift; self.option = option; self.control = control
    }

    init?(event e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let k: String
        if let s = KeyCombo.specialKeys[e.keyCode] { k = s }
        else if let c = e.charactersIgnoringModifiers?.lowercased(), let ch = c.first, !c.isEmpty { k = String(ch) }
        else { return nil }
        self.init(key: k, command: f.contains(.command), shift: f.contains(.shift), option: f.contains(.option), control: f.contains(.control))
    }

    /// Parses "shift+cmd+w", "⇧⌘W", "Cmd-Shift-W"…
    init?(_ text: String) {
        var t = text.lowercased().replacingOccurrences(of: " ", with: "")
        var c = false, s = false, o = false, k = false
        for (sym, flag) in [("⌘", 0), ("⇧", 1), ("⌥", 2), ("⌃", 3)] where t.contains(sym) {
            t = t.replacingOccurrences(of: sym, with: "")
            switch flag { case 0: c = true; case 1: s = true; case 2: o = true; default: k = true }
        }
        var parts = t.split(whereSeparator: { $0 == "+" || $0 == "-" }).map(String.init)
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        for p in parts {
            switch p {
            case "cmd", "command": c = true
            case "shift": s = true
            case "opt", "option", "alt": o = true
            case "ctrl", "control": k = true
            default: return nil
            }
        }
        self.init(key: last, command: c, shift: s, option: o, control: k)
    }

    var normalized: String {
        var p: [String] = []
        if control { p.append("ctrl") }
        if option { p.append("opt") }
        if shift { p.append("shift") }
        if command { p.append("cmd") }
        p.append(key)
        return p.joined(separator: "+")
    }

    var description: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + (key.count == 1 ? key.uppercased() : key.capitalized)
    }

    /// A shortcut must use ⌘ or ⌃ (or be a function key) so typing on the command line keeps working.
    var isAssignable: Bool { command || control || key.hasPrefix("f") && key.count > 1 && Int(key.dropFirst()) != nil }
}

@MainActor
enum ShortcutDispatcher {
    /// Runs a user-assigned shortcut. Returns true when the event was consumed.
    static func handle(_ e: NSEvent) -> Bool {
        let map = AppPreferences.shared.shortcuts
        guard !map.isEmpty, let combo = KeyCombo(event: e), let line = map[combo.normalized] else { return false }
        let win = e.window ?? NSApp.keyWindow
        guard let m = AppModel.all.first(where: { $0.window === win }) ?? AppModel.all.first(where: { $0.window === NSApp.mainWindow }) else { return false }
        m.runCommand(line)
        return true
    }
}

// MARK: - Preferences window

@MainActor
enum PreferencesWindow {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", drafting = "Drafting", display = "Display", shortcuts = "Shortcuts", toolbar = "Toolbar", agents = "Agents"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .drafting: return "pencil.and.ruler"
            case .display: return "paintpalette"
            case .shortcuts: return "keyboard"
            case .toolbar: return "menubar.rectangle"
            case .agents: return "antenna.radiowaves.left.and.right"
            }
        }
    }
    private static var window: NSWindow?
    static let selection = TabSelection()
    final class TabSelection: ObservableObject { @Published var tab: Tab = .general }

    static func show(_ tab: Tab? = nil) {
        if let tab { selection.tab = tab }
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Settings"
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = Theme.nsPanel
        w.isOpaque = true
        let host = NSHostingController(rootView: PreferencesView(prefs: .shared, selection: selection))
        host.sizingOptions = []
        w.contentViewController = host
        w.setContentSize(NSSize(width: 680, height: 520))
        w.center()
        w.setFrameAutosaveName("ArchiSettingsWindow")
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct PreferencesView: View {
    @ObservedObject var prefs: AppPreferences
    @ObservedObject var selection: PreferencesWindow.TabSelection

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(PreferencesWindow.Tab.allCases) { t in
                    Button { selection.tab = t } label: {
                        Label(t.rawValue, systemImage: t.symbol)
                            .font(Theme.font)
                            .foregroundStyle(selection.tab == t ? Theme.accentText : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 5).fill(selection.tab == t ? Theme.accent : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Reset to Defaults") {
                    let a = NSAlert()
                    a.messageText = "Reset all settings to their defaults?"
                    a.informativeText = "Colors, drafting defaults, shortcuts, the quick access toolbar and autosave go back to the factory settings."
                    a.addButton(withTitle: "Reset"); a.addButton(withTitle: "Cancel")
                    if a.runModal() == .alertFirstButtonReturn { prefs.resetToDefaults() }
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
            .padding(10)
            .frame(width: 170)
            .frame(maxHeight: .infinity)
            .background(Theme.ribbonTabBar)
            VSeparator()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selection.tab {
                    case .general: GeneralPrefs(prefs: prefs)
                    case .drafting: DraftingPrefs(prefs: prefs)
                    case .display: DisplayPrefs(prefs: prefs)
                    case .shortcuts: ShortcutPrefs(prefs: prefs)
                    case .toolbar: ToolbarPrefs(prefs: prefs)
                    case .agents: AgentPrefs()
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.panel)
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .frame(minWidth: 640, minHeight: 460)
    }
}

private struct PrefSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator))
        }
    }
}

private struct GeneralPrefs: View {
    @ObservedObject var prefs: AppPreferences
    var body: some View {
        PrefSection(title: "Autosave and recovery") {
            Picker("Autosave every", selection: $prefs.autosaveMinutes) {
                Text("Off").tag(0)
                ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
            }
            .frame(width: 260)
            Text("Unsaved changes are written to a recovery file; after a crash the Start screen offers to restore them.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            Button("Show Recovery Folder") { NSWorkspace.shared.activateFileViewerSelecting([AutosaveManager.folder]) }
                .buttonStyle(FlatButtonStyle(compact: true))
        }
        PrefSection(title: "Recent files") {
            Stepper("Remember \(prefs.recentLimit) documents", value: $prefs.recentLimit, in: 1...50)
            Button("Clear Recent Documents") { RecentFiles.clear() }.buttonStyle(FlatButtonStyle(compact: true))
        }
        PrefSection(title: "New drawings") {
            Picker("Default units", selection: $prefs.defaultUnits) {
                ForEach(Units.allCases, id: \.self) { u in Text("\(u.rawValue.capitalized) (\(u.abbreviation))").tag(u) }
            }
            .frame(width: 300)
        }
        PrefSection(title: "Scripts") {
            Toggle("Run startup.js from the script library in every new window", isOn: $prefs.runStartupScript)
            Button("Open Script Library") { ScriptLibrary.revealFolder() }.buttonStyle(FlatButtonStyle(compact: true))
        }
    }
}

private struct DraftingPrefs: View {
    @ObservedObject var prefs: AppPreferences
    var body: some View {
        PrefSection(title: "Grid and snap (new drawings)") {
            Toggle("Show grid", isOn: $prefs.draft.showGrid)
            Toggle("Grid snap", isOn: $prefs.draft.gridSnap)
            HStack { Text("Grid spacing (mm)"); TextField("", value: $prefs.draft.gridSpacing, format: .number).darkField().frame(width: 90) }
            Toggle("Ortho", isOn: $prefs.draft.ortho)
            Toggle("Polar tracking", isOn: $prefs.draft.polarTracking)
            Picker("Polar increment", selection: $prefs.draft.polarIncrement) {
                ForEach([5.0, 10, 15, 18, 22.5, 30, 45, 90], id: \.self) { Text("\(fmt($0))°").tag($0) }
            }
            .frame(width: 220)
            Toggle("Dynamic input", isOn: $prefs.draft.dynamicInput)
            Toggle("Show lineweights", isOn: $prefs.draft.lineweightDisplay)
        }
        PrefSection(title: "Object snaps (new drawings)") {
            Toggle("Object snap on", isOn: $prefs.draft.objectSnap)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(SnapKind.allCases, id: \.self) { k in
                    Toggle(k.rawValue.capitalized, isOn: Binding(get: { prefs.draft.snapModes.contains(k) },
                                                                  set: { on in if on { prefs.draft.snapModes.insert(k) } else { prefs.draft.snapModes.remove(k) } }))
                }
            }
            HStack {
                Button("Apply to Open Drawings") {
                    for m in AppModel.all {
                        m.editor.settings = prefs.draftDefaults(base: m.editor.settings, units: m.doc.units)
                        m.revision &+= 1
                    }
                }
                .buttonStyle(FlatButtonStyle(compact: true))
                Text("These settings are used by every new drawing.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }
        }
    }
}

private struct DisplayPrefs: View {
    @ObservedObject var prefs: AppPreferences
    var body: some View {
        PrefSection(title: "Accent color") {
            HStack(spacing: 8) {
                ForEach(AppPreferences.accentPresets, id: \.1) { name, hex in
                    Button { prefs.accentHex = hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(prefs.accentHex == hex ? Color.white : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain).help(name)
                }
                ColorPicker("Custom", selection: Binding(get: { Color(hex: prefs.accentHex) }, set: { prefs.accentHex = RGBA($0).hex24 }), supportsOpacity: false)
            }
        }
        PrefSection(title: "2D canvas background") {
            HStack(spacing: 8) {
                ForEach(AppPreferences.canvasPresets, id: \.1) { name, hex in
                    Button { prefs.canvasHex = hex } label: {
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: hex)).frame(width: 34, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(prefs.canvasHex == hex ? Theme.accent : Theme.separator, lineWidth: 2))
                    }
                    .buttonStyle(.plain).help(name)
                }
                ColorPicker("Custom", selection: Binding(get: { Color(hex: prefs.canvasHex) }, set: { prefs.canvasHex = RGBA($0).hex24 }), supportsOpacity: false)
            }
        }
        PrefSection(title: "Crosshair") {
            HStack {
                Text("Size")
                Slider(value: Binding(get: { Double(prefs.cursorSize) }, set: { prefs.cursorSize = Int($0.rounded()) }), in: 1...100)
                    .frame(width: 240)
                Text("\(prefs.cursorSize)% of the view").font(Theme.mono).foregroundStyle(Theme.textDim)
            }
            Text("Same as the CURSORSIZE command; 100 draws a full-screen crosshair.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
        }
    }
}

extension RGBA {
    /// 0xRRGGBB.
    var hex24: UInt32 {
        func c(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return c(r) << 16 | c(g) << 8 | c(b)
    }
}

/// Records the next key combination typed.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published var recording = false
    private var monitor: Any?
    func start(_ done: @escaping (KeyCombo?) -> Void) {
        stop()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated {
                if e.keyCode == 53 { self?.stop(); done(nil); return }
                if let c = KeyCombo(event: e), c.key != "" {
                    self?.stop(); done(c)
                }
            }
            return nil
        }
    }
    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}

private struct ShortcutPrefs: View {
    @ObservedObject var prefs: AppPreferences
    @StateObject private var recorder = ShortcutRecorder()
    @State private var combo: KeyCombo?
    @State private var commandText = ""
    @State private var message = ""
    @State private var search = ""

    /// Menu shortcuts of the app; a custom shortcut with the same keys replaces them (the user is warned).
    static let reserved: [String: String] = [
        "cmd+n": "New", "cmd+o": "Open", "cmd+s": "Save", "shift+cmd+s": "Save As", "cmd+w": "Close", "cmd+p": "Plot", "shift+cmd+p": "Page Setup",
        "cmd+z": "Undo", "shift+cmd+z": "Redo", "cmd+x": "Cut", "cmd+c": "Copy", "cmd+v": "Paste", "cmd+a": "Select All", "shift+cmd+a": "Deselect All",
        "cmd+k": "Search Commands", "cmd+0": "Zoom Extents", "cmd+=": "Zoom In", "cmd+-": "Zoom Out", "opt+cmd+p": "Show/Hide Panels",
        "opt+cmd+j": "Script Console", "cmd+,": "Settings", "shift+cmd+i": "Import", "cmd+q": "Quit", "cmd+h": "Hide", "cmd+m": "Minimize",
        "opt+cmd+1": "2D Plan", "opt+cmd+2": "3D Model", "opt+cmd+3": "Split View", "opt+cmd+4": "Sheets", "ctrl+0": "Clean Screen",
    ]

    var body: some View {
        PrefSection(title: "Assign a shortcut") {
            HStack(spacing: 8) {
                Button(recorder.recording ? "Press keys… (Esc cancels)" : (combo?.description ?? "Record Shortcut")) {
                    recorder.start { c in combo = c; message = "" }
                }
                .buttonStyle(FlatButtonStyle(prominent: recorder.recording))
                .frame(minWidth: 150)
                TextField("Command (e.g. WALL or ZOOM E)", text: $commandText).darkField().frame(width: 220)
                Button("Assign") { assign() }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(combo == nil || commandText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.accent) }
            Text("Shortcuts need ⌘ or ⌃ (or a function key) so that plain typing still goes to the command line. A custom shortcut overrides the menu shortcut with the same keys.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
        PrefSection(title: "Custom shortcuts") {
            if prefs.shortcuts.isEmpty {
                Text("No custom shortcuts yet.").foregroundStyle(Theme.textDim)
            } else {
                ForEach(prefs.shortcuts.sorted { $0.value < $1.value }, id: \.key) { k, v in
                    HStack {
                        Text(KeyCombo(k)?.description ?? k).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                            .frame(width: 110, alignment: .leading)
                        Text(v).font(Theme.mono)
                        Spacer()
                        IconButton(symbol: "trash", help: "Remove") { prefs.shortcuts[k] = nil }
                    }
                }
            }
        }
        PrefSection(title: "Commands") {
            HStack(spacing: 6) {
                TextField("Search commands to assign", text: $search).darkField().frame(width: 240)
                Spacer()
                Button("Export…") { exportShortcuts() }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Import…") { importShortcuts() }.buttonStyle(FlatButtonStyle(compact: true))
            }
            let q = search.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                let byCommand = Dictionary(grouping: prefs.shortcuts, by: { $0.value.split(separator: " ").first.map(String.init)?.uppercased() ?? $0.value })
                ForEach(CommandRegistry.shared.sorted.filter { $0.name.lowercased().contains(q) || $0.aliases.contains { $0.lowercased() == q } || $0.summary.lowercased().contains(q) }.prefix(40), id: \.name) { c in
                    HStack(spacing: 8) {
                        Text(c.name).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent).frame(width: 130, alignment: .leading)
                        Text(c.summary).font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1)
                        Spacer()
                        Text((byCommand[c.name] ?? []).compactMap { KeyCombo($0.key)?.description }.joined(separator: " ")).font(Theme.mono).foregroundStyle(Theme.text)
                        Button("Set") { commandText = c.name; recorder.start { k in combo = k; message = "" } }.buttonStyle(FlatButtonStyle(compact: true))
                            .help("Record keys for \(c.name), then press Assign")
                    }
                }
            }
        }
        PrefSection(title: "Built-in") {
            Text("F3 Osnap · F7 Grid · F8 Ortho · F9 Snap · F10 Polar · F11 Object snap tracking · F12 Dynamic input · ⌘K Command search · ⌥⌘1…4 workspaces views · See Help ▸ Keyboard Shortcuts.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func assign() {
        guard let c = combo else { return }
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard c.isAssignable else { message = "\(c) cannot be used: add ⌘ or ⌃."; return }
        let first = cmd.split(separator: " ").first.map(String.init) ?? cmd
        CommandRegistry.shared.ensureBuiltins()
        guard CommandRegistry.shared.lookup(first) != nil else { message = "Unknown command \(first.uppercased())."; return }
        let previous = prefs.shortcuts[c.normalized]
        prefs.shortcuts[c.normalized] = cmd.uppercased() == cmd ? cmd : cmd.uppercased()
        var note = "\(c) now runs \(cmd.uppercased())."
        if let r = ShortcutPrefs.reserved[c.normalized] { note += " It replaces the menu shortcut for \(r)." }
        if let p = previous, p.uppercased() != cmd.uppercased() { note += " (Was \(p).)" }
        message = note
        combo = nil; commandText = ""
    }

    private func exportShortcuts() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "Archi Shortcuts.json"
        guard p.runModal() == .OK, let u = p.url else { return }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try e.encode(prefs.shortcuts).write(to: u); message = "Exported \(prefs.shortcuts.count) shortcut(s)." }
        catch { message = error.localizedDescription }
    }

    private func importShortcuts() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let u = p.url, let d = try? Data(contentsOf: u),
              let map = try? JSONDecoder().decode([String: String].self, from: d) else { message = "Not a shortcuts file."; return }
        var n = 0
        for (k, v) in map { if let c = KeyCombo(k), c.isAssignable { prefs.shortcuts[c.normalized] = v; n += 1 } }
        message = "Imported \(n) shortcut(s)."
    }
}

private struct ToolbarPrefs: View {
    @ObservedObject var prefs: AppPreferences
    @State private var newCommand = ""
    @State private var message = ""
    var body: some View {
        PrefSection(title: "Quick access toolbar") {
            ForEach(Array(prefs.quickAccess.enumerated()), id: \.offset) { i, name in
                HStack(spacing: 8) {
                    Image(systemName: QuickAccess.symbol(for: name)).frame(width: 18).foregroundStyle(Theme.accent)
                    Text(name).font(Theme.mono)
                    Text(CommandRegistry.shared.lookup(name)?.summary ?? "").font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1)
                    Spacer()
                    IconButton(symbol: "arrow.up", help: "Move left") { move(i, -1) }.disabled(i == 0)
                    IconButton(symbol: "arrow.down", help: "Move right") { move(i, 1) }.disabled(i == prefs.quickAccess.count - 1)
                    IconButton(symbol: "minus.circle", help: "Remove") { prefs.quickAccess.remove(at: i) }
                }
            }
            HStack {
                TextField("Command name (e.g. MATCHPROP)", text: $newCommand).darkField().frame(width: 220).onSubmit(add)
                Button("Add") { add() }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Restore Default") { prefs.quickAccess = AppPreferences.defaultQuickAccess }.buttonStyle(FlatButtonStyle(compact: true))
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.danger) }
        }
    }
    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard prefs.quickAccess.indices.contains(j) else { return }
        prefs.quickAccess.swapAt(i, j)
    }
    private func add() {
        CommandRegistry.shared.ensureBuiltins()
        guard let def = CommandRegistry.shared.lookup(newCommand.trimmingCharacters(in: .whitespaces)) else { message = "Unknown command."; return }
        if !prefs.quickAccess.contains(def.name) { prefs.quickAccess.append(def.name) }
        newCommand = ""; message = ""
    }
}

/// Quick access toolbar helpers (icons for common commands).
enum QuickAccess {
    static func symbol(for name: String) -> String {
        let map: [String: String] = [
            "NEW": "doc.badge.plus", "OPEN": "folder", "SAVE": "square.and.arrow.down", "SAVEAS": "square.and.arrow.down.on.square",
            "UNDO": "arrow.uturn.backward", "U": "arrow.uturn.backward", "REDO": "arrow.uturn.forward", "PLOT": "printer", "PREVIEW": "eye",
            "PUBLISH": "doc.on.doc", "EXPORT": "square.and.arrow.up", "MATCHPROP": "paintbrush.pointed", "PROPERTIES": "slider.horizontal.3",
            "LAYER": "square.3.layers.3d", "QSELECT": "line.3.horizontal.decrease.circle", "QSELECTDIALOG": "line.3.horizontal.decrease.circle",
            "RENDER": "camera.aperture", "ZOOM": "plus.magnifyingglass", "REGEN": "arrow.clockwise", "OPTIONS": "gearshape", "WALL": "rectangle.split.2x1",
            "LINE": "line.diagonal", "CIRCLE": "circle", "ERASE": "eraser", "MOVE": "arrow.up.and.down.and.arrow.left.and.right", "COPY": "plus.square.on.square",
        ]
        if let s = map[name.uppercased()] { return s }
        let cat = CommandRegistry.shared.lookup(name)?.category ?? ""
        switch cat {
        case "Draw": return "pencil.line"
        case "Modify": return "wand.and.rays"
        case "Annotate": return "textformat"
        case "View": return "eye"
        case "Architecture", "BIM": return "building.2"
        default: return "terminal"
        }
    }
}
