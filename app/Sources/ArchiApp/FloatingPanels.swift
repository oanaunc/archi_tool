// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// The content of one panel tab (shared by the docked panel column and floating panel windows).
struct PanelContent: View {
    @ObservedObject var model: AppModel
    let tab: PanelTab
    var body: some View {
        switch tab {
        case .properties: PropertiesPanel(model: model)
        case .layers: LayersPanel(model: model)
        case .levels: LevelsPanel(model: model)
        case .browser: ProjectBrowserPanel(model: model)
        case .materials: MaterialsPanel(model: model)
        case .history: HistoryPanel(model: model)
        case .tools: ToolPalettePanel(model: model)
        case .sheets: SheetSetPanel(model: model)
        case .selection: SelectionInfoPanel(model: model)
        case .navigator: NavigatorPanel(model: model)
        case .alerts: NotificationsPanel(model: model)
        case .quick: ScrollView { QuickPropertiesView(model: model) }
        case .inspector: InspectorPanel(model: model)
        case .content: DesignCenterPanel(model: model)
        }
    }
}

/// Floating (undocked) panels: each panel tab can live in its own utility window that floats over the document
/// window. The set of floating panels and their frames are remembered across relaunches.
@MainActor
enum FloatingPanels {
    private final class Entry { let panel: NSPanel; weak var model: AppModel?; init(_ p: NSPanel, _ m: AppModel) { panel = p; model = m } }
    private static var open: [String: Entry] = [:]
    private static let savedKey = "floatingPanels.open"

    private static func key(_ tab: PanelTab, _ model: AppModel) -> String { "\(ObjectIdentifier(model).hashValue)-\(tab.rawValue)" }

    static func isFloating(_ tab: PanelTab, model: AppModel) -> Bool { open[key(tab, model)] != nil }

    /// Tabs floating for a window (hidden from the docked tab strip).
    static func floatingTabs(_ model: AppModel) -> Set<PanelTab> {
        Set(PanelTab.allCases.filter { isFloating($0, model: model) })
    }

    static func float(_ tab: PanelTab, model: AppModel) {
        let k = key(tab, model)
        if let e = open[k] { e.panel.makeKeyAndOrderFront(nil); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 520),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = tab.rawValue
        p.isFloatingPanel = true
        p.hidesOnDeactivate = true
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.appearance = Theme.appearance
        p.backgroundColor = Theme.nsPanel
        p.contentViewController = NSHostingController(rootView: FloatingPanelView(model: model, tab: tab).preferredColorScheme(Theme.colorScheme))
        p.setFrameAutosaveName("ArchiFloatingPanel.\(tab.rawValue)")
        if p.frame.origin == .zero, let w = model.window {
            p.setFrameTopLeftPoint(NSPoint(x: w.frame.maxX - 320, y: w.frame.maxY - 120))
        }
        model.window?.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        open[k] = Entry(p, model)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { _ in
            MainActor.assumeIsolated { dockedBack(tab, model: model) }
        }
        remember()
        if model.panelTab == tab, let other = PanelTab.allCases.first(where: { !isFloating($0, model: model) }) { model.panelTab = other }
        model.revision &+= 1
    }

    /// Closes the floating window: the panel returns to the docked column.
    static func dock(_ tab: PanelTab, model: AppModel) {
        open[key(tab, model)]?.panel.close()
    }

    private static func dockedBack(_ tab: PanelTab, model: AppModel) {
        let k = key(tab, model)
        guard let e = open.removeValue(forKey: k) else { return }
        e.model?.window?.removeChildWindow(e.panel)
        remember()
        model.showPanels = true
        model.panelTab = tab
        model.revision &+= 1
    }

    /// Floats the panels that were floating when the app last quit (called when a window appears).
    static func restore(for model: AppModel) {
        let names = UserDefaults.standard.stringArray(forKey: savedKey) ?? []
        for n in names { if let t = PanelTab(rawValue: n), !isFloating(t, model: model) { float(t, model: model) } }
    }

    private static func remember() {
        let names = Array(Set(open.keys.compactMap { $0.split(separator: "-").last.map(String.init) })).sorted()
        UserDefaults.standard.set(names, forKey: savedKey)
    }
}

private struct FloatingPanelView: View {
    @ObservedObject var model: AppModel
    let tab: PanelTab
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol).foregroundStyle(Theme.accent)
                Text(tab.rawValue).font(Theme.fontBold).foregroundStyle(Theme.text)
                Spacer()
                IconButton(symbol: "rectangle.righthalf.inset.filled", help: "Dock the panel back into the window") { FloatingPanels.dock(tab, model: model) }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(Theme.ribbonTabBar)
            HSeparator()
            PanelContent(model: model, tab: tab).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.panel)
        .frame(minWidth: 240, minHeight: 240)
    }
}
