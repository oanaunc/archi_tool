// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// A saved arrangement of the window: visible views, panels, ribbon tab (WSCURRENT / WSSAVE).
struct WorkspaceLayout: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var mode: String
    var showPanels: Bool
    var panelTab: String
    var showScriptConsole: Bool
    var ribbonTab: String
    var ribbonCollapsed: Bool
    var cleanScreen: Bool

    static let builtIn: [WorkspaceLayout] = [
        WorkspaceLayout(name: "Drafting & Annotation", mode: WorkspaceMode.plan.rawValue, showPanels: true, panelTab: PanelTab.properties.rawValue,
                        showScriptConsole: false, ribbonTab: "Home", ribbonCollapsed: false, cleanScreen: false),
        WorkspaceLayout(name: "Building Design", mode: WorkspaceMode.split.rawValue, showPanels: true, panelTab: PanelTab.levels.rawValue,
                        showScriptConsole: false, ribbonTab: "Architecture", ribbonCollapsed: false, cleanScreen: false),
        WorkspaceLayout(name: "3D Modeling", mode: WorkspaceMode.model.rawValue, showPanels: true, panelTab: PanelTab.materials.rawValue,
                        showScriptConsole: false, ribbonTab: "View", ribbonCollapsed: false, cleanScreen: false),
        WorkspaceLayout(name: "Sheets & Plotting", mode: WorkspaceMode.sheet.rawValue, showPanels: true, panelTab: PanelTab.browser.rawValue,
                        showScriptConsole: false, ribbonTab: "Output", ribbonCollapsed: false, cleanScreen: false),
        WorkspaceLayout(name: "Scripting", mode: WorkspaceMode.plan.rawValue, showPanels: true, panelTab: PanelTab.history.rawValue,
                        showScriptConsole: true, ribbonTab: "Script", ribbonCollapsed: false, cleanScreen: false),
    ]
}

@MainActor
enum Workspaces {
    private static let customKey = "workspaces.custom"
    private static let currentKey = "workspaces.current"

    static var custom: [WorkspaceLayout] {
        get { (UserDefaults.standard.data(forKey: customKey)).flatMap { try? JSONDecoder().decode([WorkspaceLayout].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customKey) }
    }
    static var all: [WorkspaceLayout] {
        let c = custom
        return WorkspaceLayout.builtIn.filter { b in !c.contains { $0.name.caseInsensitiveCompare(b.name) == .orderedSame } } + c
    }
    static var currentName: String {
        get { UserDefaults.standard.string(forKey: currentKey) ?? WorkspaceLayout.builtIn[0].name }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }
    static func find(_ name: String) -> WorkspaceLayout? {
        let n = name.trimmingCharacters(in: .whitespaces)
        return all.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
            ?? all.first { $0.name.lowercased().hasPrefix(n.lowercased()) && !n.isEmpty }
    }

    /// Captures the window's current arrangement.
    static func capture(_ m: AppModel, name: String) -> WorkspaceLayout {
        WorkspaceLayout(name: name, mode: m.mode.rawValue, showPanels: m.showPanels, panelTab: m.panelTab.rawValue, showScriptConsole: m.showScriptConsole,
                        ribbonTab: UserDefaults.standard.string(forKey: "ribbonTab") ?? "Home",
                        ribbonCollapsed: UserDefaults.standard.bool(forKey: "ribbonCollapsed"), cleanScreen: m.cleanScreen)
    }

    /// Saves (or replaces) a custom workspace.
    static func save(_ w: WorkspaceLayout) {
        var c = custom
        c.removeAll { $0.name.caseInsensitiveCompare(w.name) == .orderedSame }
        c.append(w)
        custom = c
        currentName = w.name
    }

    static func delete(_ name: String) {
        custom = custom.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
    }

    /// Applies a workspace to a window (panels, views and ribbon change at once).
    static func apply(_ w: WorkspaceLayout, to m: AppModel) {
        if let mode = WorkspaceMode(rawValue: w.mode) { m.mode = mode }
        m.showPanels = w.showPanels
        if let t = PanelTab(rawValue: w.panelTab) { m.panelTab = t }
        m.showScriptConsole = w.showScriptConsole
        m.cleanScreen = w.cleanScreen
        UserDefaults.standard.set(w.ribbonTab, forKey: "ribbonTab")
        UserDefaults.standard.set(w.ribbonCollapsed, forKey: "ribbonCollapsed")
        currentName = w.name
        m.revision &+= 1
    }
}
