// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Bottom status bar: coordinates, drafting toggles, level/layer, units, zoom, selection, agent server.
struct StatusBarView: View {
    @ObservedObject var model: AppModel

    /// Isolate / hide objects (APP-043): tinted while objects are hidden.
    private var isolateMenu: some View {
        let count = model.doc.variables[HiddenObjects.variable] == nil ? 0 : 1
        let sel = !model.editor.selection.isEmpty
        return Menu {
            Button("Isolate Selection") { model.runCommand("ISOLATEOBJECTS") }.disabled(!sel)
            Button("Hide Selection") { model.runCommand("HIDEOBJECTS") }.disabled(!sel)
            Divider()
            Button("End Isolation") { model.runCommand("UNISOLATEOBJECTS") }.disabled(count == 0)
        } label: {
            Image(systemName: count > 0 ? "eye.trianglebadge.exclamationmark" : "eye")
                .foregroundStyle(count > 0 ? Theme.accent : Theme.textDim)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(count > 0 ? "Objects are hidden — End Isolation shows them again" : "Isolate or hide the selected objects")
    }

    var body: some View {
        HStack(spacing: 0) {
            CoordinateReadout(live: model.live, units: model.doc.units, ucs: UCSFrame.current(model.doc),
                              format: (UnitFormat.linearType(model.doc), UnitFormat.linearPrecision(model.doc)))
                .frame(width: 210, alignment: .leading)
                .padding(.leading, 8)
            ucsIndicator
            MacroButtonBar(model: model)
            VSeparator().padding(.vertical, 4)
            HStack(spacing: 1) {
                toggle("GRID", "F7", \.showGrid)
                toggle("SNAP", "F9", \.gridSnap)
                toggle("ORTHO", "F8", \.ortho)
                toggle("POLAR", "F10", \.polarTracking)
                toggle("OTRACK", "F11", \.objectSnapTracking)
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
                ProgressStatusView()
                isolateMenu
                AnnotationScaleMenu(model: model)
                Button { model.showQuickProperties.toggle() } label: { Image(systemName: "slider.horizontal.below.rectangle").foregroundStyle(model.showQuickProperties ? Theme.accent : Theme.textDim) }
                    .buttonStyle(.plain).help("Quick Properties (QP) \(model.showQuickProperties ? "on" : "off")")
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
        .accessibilityLabel(A11y.toggleNames[title] ?? title)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityHint(key.isEmpty ? "Toggles \(title)" : "Toggles \(title), shortcut \(key)")
    }

    /// Current coordinate system (WCS or UCS with origin and angle); the menu switches or edits it.
    private var ucsIndicator: some View {
        let ucs = UCSFrame.current(model.doc)
        return Menu {
            Button("World (WCS)") { model.runCommand("UCS W") }.disabled(ucs.isWorld)
            Button("Previous") { model.runCommand("UCS P") }
            Button("New Origin…") { model.runCommand("UCS O") }
            Button("Rotate About Z…") { model.runCommand("UCS Z") }
            Button("3 Points…") { model.runCommand("UCS 3") }
            Button("Align to Object…") { model.runCommand("UCS OB") }
            Divider()
            Button("Named UCS…") { model.runCommand("UCSMAN") }
        } label: {
            Text(ucs.isWorld ? "WCS" : "UCS")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(ucs.isWorld ? Theme.textDim : Theme.accentText)
                .padding(.horizontal, 5).frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 3).fill(ucs.isWorld ? Color.white.opacity(0.04) : Theme.accent))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.trailing, 6)
        .help(ucs.isWorld ? "World coordinate system — coordinates are world X,Y" : "User coordinate system: origin \(fmt(ucs.origin.x, 2)),\(fmt(ucs.origin.y, 2)), X axis \(fmt(deg(ucs.angle), 2))°. Coordinates are shown in the UCS.")
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
    var ucs: UCSFrame = .world
    /// LUNITS / LUPREC of the drawing (APP-049).
    var format: (UnitFormat.Linear, Int) = (.decimal, 2)
    var body: some View {
        let p = ucs.isWorld ? live.cursorWorld : ucs.fromWorld(live.cursorWorld)
        HStack(spacing: 6) {
            Text(UnitFormat.linear(p.x, units: units, type: format.0, precision: format.1) + ", " + UnitFormat.linear(p.y, units: units, type: format.0, precision: format.1))
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


/// Custom macro buttons (CMD-041, MACROBUTTON): user-profile and drawing buttons, run like AutoCAD CUI macros.
struct MacroButtonBar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let buttons = MacroButtons.all(model.doc)
        if !buttons.isEmpty {
            HStack(spacing: 2) {
                VSeparator().padding(.vertical, 4)
                ForEach(buttons.prefix(12)) { b in
                    Button { model.editor.runMacro(b.macro) } label: {
                        Image(systemName: NSImage(systemSymbolName: b.icon, accessibilityDescription: nil) == nil ? "command" : b.icon)
                            .foregroundStyle(Theme.textDim).frame(width: 20)
                    }
                    .buttonStyle(.borderless)
                    .help(b.tooltip.isEmpty ? "\(b.name): \(b.macro)" : b.tooltip)
                }
                if buttons.count > 12 {
                    Menu {
                        ForEach(buttons.dropFirst(12)) { b in Button(b.name) { model.editor.runMacro(b.macro) } }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
