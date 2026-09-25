// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Bottom status bar: coordinates, drafting toggles, level/layer, units, zoom, selection, agent server.
struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            CoordinateReadout(live: model.live, units: model.doc.units)
                .frame(width: 210, alignment: .leading)
                .padding(.leading, 8)
            VSeparator().padding(.vertical, 4)
            HStack(spacing: 1) {
                toggle("GRID", "F7", \.showGrid)
                toggle("SNAP", "F9", \.gridSnap)
                toggle("ORTHO", "F8", \.ortho)
                toggle("POLAR", "F10", \.polarTracking)
                toggle("OSNAP", "F3", \.objectSnap)
                toggle("DYN", "F12", \.dynamicInput)
                toggle("LWT", "", \.lineweightDisplay)
            }
            .padding(.horizontal, 4)
            VSeparator().padding(.vertical, 4)
            LevelDropdown(model: model).frame(width: 150).padding(.horizontal, 4)
            LayerDropdown(model: model).frame(width: 130).padding(.trailing, 4)
            Spacer(minLength: 6)
            Group {
                let sel = model.editor.selection.count
                if sel > 0 {
                    Label("\(sel) selected", systemImage: "cursorarrow.rays").foregroundStyle(Theme.accent)
                }
                Menu {
                    ForEach(Units.allCases, id: \.self) { u in
                        Button(u.rawValue.capitalized) { model.editor.transaction("Units") { $0.units = u } }
                    }
                } label: { Text(model.doc.units.abbreviation) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Drawing units")
                ZoomReadout(live: model.live)
                agentIndicator
            }
            .font(Theme.fontSmall)
            .foregroundStyle(Theme.textDim)
            .padding(.trailing, 10)
        }
        .frame(height: 24)
        .background(Theme.ribbonTabBar)
    }

    private func toggle(_ title: String, _ key: String, _ path: WritableKeyPath<DraftSettings, Bool>) -> some View {
        let on = model.editor.settings[keyPath: path]
        return Button {
            model.editor.settings[keyPath: path].toggle()
            model.editor.print("<\(title.capitalized) \(model.editor.settings[keyPath: path] ? "on" : "off")>")
            model.revision &+= 1
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(on ? Theme.accentText : Theme.textDim)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 3).fill(on ? Theme.accent : Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .help("\(title) \(on ? "on" : "off")" + (key.isEmpty ? "" : " (\(key))"))
    }

    private var agentIndicator: some View {
        Button { model.toggleAgentServer() } label: {
            HStack(spacing: 4) {
                Circle().fill(model.agentRunning ? Color.green : Theme.textFaint).frame(width: 6, height: 6)
                Text(model.agentRunning ? "Agent: on :\(AgentServer.shared.port)" : "Agent: off")
            }
        }
        .buttonStyle(.plain)
        .help(model.agentRunning ? "Agent server listening on 127.0.0.1:\(AgentServer.shared.port) — click to stop" : "Start the local agent server")
    }
}

/// Coordinates update on every mouse move; kept in its own view so the rest of the bar does not re-render.
private struct CoordinateReadout: View {
    @ObservedObject var live: LiveState
    let units: Units
    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%.2f, %.2f", live.cursorWorld.x, live.cursorWorld.y))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.text)
            Text(units.abbreviation).font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
            if let s = live.snapHint {
                Text(s).font(Theme.fontSmall).foregroundStyle(Theme.accent)
            }
        }
        .lineLimit(1)
    }
}

private struct ZoomReadout: View {
    @ObservedObject var live: LiveState
    var body: some View {
        let p = live.zoomPercent
        let text: String
        if p <= 0 || !p.isFinite { text = "—" }
        else if p >= 100 { text = String(format: "%.1f:1", p / 100) }
        else { text = "1:\(Int((100 / p).rounded()))" }
        return Text("Zoom \(text)").help("Screen scale relative to real size")
    }
}
