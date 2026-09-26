// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Materials panel sections: PBR maps (VIS-061) and the identity / graphics / physical assets (VIS-068),
/// plus buttons for procedural and photo materials (VIS-066/067) and the path tracer preview (VIS-060).
struct MaterialMapsSection: View {
    @ObservedObject var model: AppModel
    let material: ArchiCore.Material
    @State private var showAssets = false

    private var maps: MaterialMaps { MaterialMaps.load(material.name, doc: model.doc) }
    private var assets: MaterialAssetSet { MaterialAssetSet.load(material.name, doc: model.doc) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PBR maps").font(Theme.fontBold).foregroundStyle(Theme.textDim)
            ForEach(MaterialMaps.slots, id: \.title) { slot in
                HStack(spacing: 6) {
                    Text(slot.title).frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
                    Text(maps[keyPath: slot.key].map { ($0 as NSString).lastPathComponent } ?? "None").lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { choose(slot.key, slot.title) }.buttonStyle(FlatButtonStyle(compact: true))
                    if maps[keyPath: slot.key] != nil { IconButton(symbol: "xmark.circle", help: "Remove the \(slot.title.lowercased()) map") { edit("Map") { $0[keyPath: slot.key] = nil } } }
                }
            }
            if maps.normal != nil {
                HStack(spacing: 6) {
                    Text("Normal").frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
                    Slider(value: Binding(get: { maps.normalStrength }, set: { v in edit("Normal Strength") { $0.normalStrength = (v * 100).rounded() / 100 } }), in: 0...3)
                    Text(fmt(maps.normalStrength, 2)).font(Theme.mono).frame(width: 34, alignment: .trailing)
                }
            }
            if maps.displacement != nil {
                HStack(spacing: 6) {
                    Text("Height").frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
                    TextField("", value: Binding(get: { maps.displacementScale }, set: { v in edit("Displacement") { $0.displacementScale = max(0, v) } }), format: .number).darkField().frame(width: 70)
                    Text("mm").foregroundStyle(Theme.textDim)
                }
            }
            HStack(spacing: 6) {
                Button("Path Trace") { PathTraceWindow.show(model: model) }.buttonStyle(FlatButtonStyle(compact: true))
                    .help("Preview the materials in the path tracer (glass refraction, PBR maps)")
                Button("Procedural…") { model.runCommand("PROCMATERIAL") }.buttonStyle(FlatButtonStyle(compact: true))
                Button("From Photo…") { fromPhoto() }.buttonStyle(FlatButtonStyle(compact: true))
            }
            DisclosureGroup("Identity, graphics & physical", isExpanded: $showAssets) { assetsForm }
                .foregroundStyle(Theme.textDim)
        }
    }

    @ViewBuilder private var assetsForm: some View {
        let a = assets
        VStack(alignment: .leading, spacing: 4) {
            row("Description") { TextField("", text: Binding(get: { a.description }, set: { v in editAsset { $0.description = v } })).darkField() }
            row("Manufacturer") { TextField("", text: Binding(get: { a.manufacturer }, set: { v in editAsset { $0.manufacturer = v } })).darkField() }
            row("Mark") { TextField("", text: Binding(get: { a.mark }, set: { v in editAsset { $0.mark = v } })).darkField() }
            Toggle("Shaded views use the render colour", isOn: Binding(get: { a.useRenderAppearance }, set: { v in editAsset { $0.useRenderAppearance = v; if !v && $0.shadingColor == nil { $0.shadingColor = material.color.hexRGB } } }))
            if !a.useRenderAppearance {
                row("Shading") {
                    ColorPicker("", selection: Binding(get: { Color(RGBA(hexString: a.shadingColor ?? "") ?? material.color) }, set: { c in editAsset { $0.shadingColor = RGBA(c).hexRGB } }), supportsOpacity: false).labelsHidden()
                }
            }
            row("Density") { number(a.density, "kg/m³") { v in editAsset { $0.density = v } } }
            row("Conductivity") { number(a.conductivity, "W/m·K") { v in editAsset { $0.conductivity = v } } }
            row("Specific heat") { number(a.specificHeat, "J/kg·K") { v in editAsset { $0.specificHeat = v } } }
        }
        .padding(.top, 4)
    }
    private func row<V: View>(_ t: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(spacing: 6) { Text(t).frame(width: 90, alignment: .leading).foregroundStyle(Theme.textDim); v() }
    }
    private func number(_ v: Double?, _ unit: String, _ set: @escaping (Double?) -> Void) -> some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(get: { v ?? 0 }, set: { set($0 > 0 ? $0 : nil) }), format: .number).darkField().frame(width: 80)
            Text(unit).foregroundStyle(Theme.textDim)
        }
    }

    private func edit(_ label: String, _ change: (inout MaterialMaps) -> Void) {
        var m = maps
        change(&m)
        let n = material.name
        model.editor.transaction("Material \(label)") { MaterialMaps.store(m, material: n, in: &$0) }
    }
    private func editAsset(_ change: (inout MaterialAssetSet) -> Void) {
        var a = assets
        change(&a)
        let n = material.name
        model.editor.transaction("Material Asset") { MaterialAssetSet.store(a, material: n, in: &$0) }
    }
    private func choose(_ key: WritableKeyPath<MaterialMaps, String?>, _ title: String) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Choose the \(title.lowercased()) map (it tiles like the albedo texture)"
        guard p.runModal() == .OK, let u = p.url else { return }
        var path = u.path
        if let dir = model.editor.fileURL?.deletingLastPathComponent().path, path.hasPrefix(dir + "/") { path = String(path.dropFirst(dir.count + 1)) }
        edit("Map") { m in
            m[keyPath: key] = path
            if key == \MaterialMaps.displacement && m.displacementScale == 0 { m.displacementScale = 5 }
        }
    }
    private func fromPhoto() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Choose a photo of the surface"
        guard p.runModal() == .OK, let u = p.url else { return }
        let n = u.deletingPathExtension().lastPathComponent.capitalized
        do { try model.editor.transaction("Material from Photo") { _ = try PhotoMaterial.create(from: u, name: n, tileSize: 1000, in: &$0) } }
        catch { model.editor.print("Material from photo failed: \(error.localizedDescription)") }
    }
}
