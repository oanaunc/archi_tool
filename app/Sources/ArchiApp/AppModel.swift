// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Which views are visible in the main window.
enum WorkspaceMode: String, CaseIterable, Identifiable { case plan = "2D", model = "3D", split = "Split", sheet = "Sheet"
    var id: String { rawValue } }

/// Observable wrapper around the core Editor. One per document window.
@MainActor
final class AppModel: ObservableObject {
    let editor: Editor
    /// Bumped whenever the document or selection changes (views redraw).
    @Published var revision = 0
    @Published var promptText = "Command:"
    @Published var commandLog: [String] = []
    @Published var mode: WorkspaceMode = .plan
    @Published var cursorWorld: Vec2 = .zero
    @Published var snapHint: String?
    @Published var viewStyle: String = "Shaded with Edges"
    @Published var showLayers = true
    @Published var showProperties = true
    @Published var showScriptConsole = false
    @Published var activeLayout: Int = 0

    /// View requests sent to the 2D canvas / 3D viewport.
    var zoomExtentsRequest = 0
    var pendingHostAction: HostAction?

    init(document: ArchiDocument = ArchiDocument()) {
        editor = Editor(document: document)
        editor.onChange = { [weak self] in self?.revision &+= 1 }
        editor.onSelectionChange = { [weak self] in self?.revision &+= 1 }
        editor.onPromptChange = { [weak self] in
            guard let self else { return }
            self.promptText = self.editor.promptText
            self.revision &+= 1
        }
        editor.onLog = { [weak self] line in
            guard let self else { return }
            self.commandLog.append(line)
            if self.commandLog.count > 2000 { self.commandLog.removeFirst(500) }
        }
    }

    var doc: ArchiDocument { editor.doc }
}
