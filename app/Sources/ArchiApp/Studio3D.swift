// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import SceneKit
import AppKit
import ArchiCore

// MARK: - Vertical move (Z arrow of the 3D gizmo, MOVEZ)

/// Moves objects up or down: BIM elements change their base/top offset (or sill for doors and windows), solids are
/// translated. Plan-only objects (2D drafting, rooms, grids, stairs that rise from their level) are left unchanged.
enum ZMove {
    static func shifted(_ g: BIMGeometry, dz: Double) -> BIMGeometry? {
        switch g {
        case .wall(var w): w.baseOffset += dz; if w.topLevel != nil { w.topOffset += dz }; return .wall(w)
        case .slab(var s): s.topOffset += dz; return .slab(s)
        case .column(var c): c.baseOffset += dz; return .column(c)
        case .beam(var b): b.topOffset += dz; if let e = b.endTopOffset { b.endTopOffset = e + dz }; return .beam(b)
        case .opening(var o): o.sill += dz; return .opening(o)
        case .roof(var r): r.baseOffset += dz; return .roof(r)
        case .railing(var r): r.baseOffset += dz; return .railing(r)
        case .curtainWall(var c): c.baseOffset += dz; return .curtainWall(c)
        case .component(var c): c.baseOffset += dz; return .component(c)
        case .stair, .space, .gridLine: return nil
        }
    }
    static func shifted(_ g: Geometry, dz: Double) -> Geometry? {
        if case .solid(let s) = g { return .solid(SolidOps.translated(s, by: Vec3(0, 0, dz))) }
        return nil
    }
    /// Applies a vertical move as one undo step (locked objects skipped).
    @MainActor @discardableResult
    static func apply(_ ed: Editor, ids: [EntityID], dz: Double, label: String = "Move Z") -> (moved: Int, skipped: Int) {
        let targets = ed.expandGroups(ids).filter { ed.isSelectable($0) }
        guard !targets.isEmpty, abs(dz) > 1e-12 else { return (0, targets.count) }
        var n = 0, skipped = 0
        ed.transaction(label) { d in
            for id in targets {
                if let i = d.entityIndex(id) {
                    if let g = shifted(d.entities[i].geometry, dz: dz) { d.entities[i].geometry = g; n += 1 } else { skipped += 1 }
                } else if let i = d.elementIndex(id) {
                    if let g = shifted(d.elements[i].geometry, dz: dz) { d.elements[i].geometry = g; n += 1 } else { skipped += 1 }
                }
            }
        }
        return (n, skipped)
    }
}

// MARK: - Isolate / explode levels in 3D (VIS-038)

@MainActor
final class LevelView3DState: ObservableObject {
    static let shared = LevelView3DState()
    /// Level shown alone (nil = all levels).
    @Published var isolate: Int? { didSet { Viewport3DController.active?.applyLevelView() } }
    /// Extra vertical gap between consecutive levels (0 = not exploded), drawing units.
    @Published var explodeGap: Double = 0 { didSet { Viewport3DController.active?.applyLevelView() } }
    var isActive: Bool { isolate != nil || explodeGap > 1e-9 }
}

enum LevelView3D {
    /// Vertical offset of each level (by id) for an exploded view: levels sorted by elevation, the lowest stays put.
    static func offsets(_ levels: [Level], gap: Double) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for (k, l) in levels.sorted(by: { ($0.elevation, $0.id) < ($1.elevation, $1.id) }).enumerated() { out[l.id] = Double(k) * gap }
        return out
    }
    /// Whether an element on `level` is shown when `isolate` is set (drafting objects without a level stay visible).
    static func visible(level: Int?, isolate: Int?) -> Bool {
        guard let iso = isolate, let l = level else { return true }
        return l == iso
    }
}

extension Viewport3DController {
    /// Hides elements of other levels and lifts each level by its explode offset.
    func applyLevelView() {
        guard let model else { return }
        let st = LevelView3DState.shared
        let offs = LevelView3D.offsets(model.doc.levels, gap: st.explodeGap)
        var levelOf: [EntityID: Int] = [:]
        for el in model.doc.elements { levelOf[el.id] = el.level }
        for n in builder.modelRoot.childNodes {
            guard let name = n.name, name.hasPrefix("el:"), let id = Int(name.dropFirst(3)) else { continue }
            let lv = levelOf[id]
            n.isHidden = !LevelView3D.visible(level: lv, isolate: st.isolate)
            let z = CGFloat(lv.flatMap { offs[$0] } ?? 0)
            if abs(n.position.z - z) > 1e-6 || n.position.x != 0 || n.position.y != 0 { n.position = SCNVector3(0, 0, z) }
        }
    }

    // MARK: Field of view (VIS-022)

    var fieldOfView: Double {
        get { Double(cameraNode.camera?.fieldOfView ?? 45) }
        set { cameraNode.camera?.fieldOfView = CGFloat(FieldOfView.clamp(newValue)); objectWillChange.send() }
    }

    // MARK: Viewport image export (VIS-088)

    /// Renders the current 3D view (camera, visual style, clipping) to an image of the given size.
    func viewportImage(width: Int, height: Int, transparent: Bool = false) -> NSImage? {
        guard width > 0, height > 0 else { return nil }
        let r = SCNRenderer(device: view?.device ?? MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = builder.scene
        r.pointOfView = cameraNode
        let bg = builder.scene.background.contents, groundHidden = builder.groundNode.isHidden
        if transparent { builder.scene.background.contents = NSColor.clear; builder.groundNode.isHidden = true }
        defer { if transparent { builder.scene.background.contents = bg; builder.groundNode.isHidden = groundHidden } }
        return r.snapshot(atTime: 0, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
    }
}

enum FieldOfView {
    static let range: ClosedRange<Double> = 15...120
    static func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }
    /// 35 mm-equivalent focal length of a vertical field of view (24 mm film height).
    static func focalLength(fov: Double) -> Double { 12 / tan(clamp(fov) * .pi / 360) }
    static func fov(focalLength f: Double) -> Double { clamp(2 * atan(12 / max(f, 1e-6)) * 180 / .pi) }
}

/// Image export helpers shared by the viewport and sheet exports.
enum ImageExport {
    enum Format: String, CaseIterable { case png = "PNG", jpeg = "JPEG", tiff = "TIFF"
        var ext: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
        var type: NSBitmapImageRep.FileType { self == .png ? .png : self == .jpeg ? .jpeg : .tiff }
        static func from(_ path: String) -> Format? {
            switch (path as NSString).pathExtension.lowercased() {
            case "png": return .png
            case "jpg", "jpeg": return .jpeg
            case "tif", "tiff": return .tiff
            default: return nil
            }
        }
    }
    static func data(_ image: NSImage, format: Format, quality: Double = 0.9) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: format.type, properties: format == .jpeg ? [.compressionFactor: quality] : [:])
    }
    /// Pixel size of an image (not points).
    static func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }
}

/// Levels / field-of-view popover shown from the 3D overlay.
struct Level3DMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: Viewport3DController
    @ObservedObject var st = LevelView3DState.shared
    var body: some View {
        Menu {
            Button { st.isolate = nil } label: { if st.isolate == nil { Label("All levels", systemImage: "checkmark") } else { Text("All levels") } }
            ForEach(model.doc.levels.sorted { $0.elevation < $1.elevation }, id: \.id) { l in
                Button { st.isolate = l.id } label: { if st.isolate == l.id { Label("Only \(l.name)", systemImage: "checkmark") } else { Text("Only \(l.name)") } }
            }
            Divider()
            ForEach([0.0, 1500, 3000, 6000], id: \.self) { g in
                Button { st.explodeGap = g / max(model.doc.units.mm, 1e-9) } label: {
                    let t = g == 0 ? "Not exploded" : "Explode levels by \(fmt(g / 1000, 1)) m"
                    if abs(st.explodeGap * model.doc.units.mm - g) < 1e-6 { Label(t, systemImage: "checkmark") } else { Text(t) }
                }
            }
            Divider()
            ForEach([24.0, 35, 45, 60, 90], id: \.self) { f in
                Button { controller.fieldOfView = f } label: {
                    let t = "Field of view \(Int(f))° (\(Int(FieldOfView.focalLength(fov: f).rounded())) mm)"
                    if abs(controller.fieldOfView - f) < 0.5 { Label(t, systemImage: "checkmark") } else { Text(t) }
                }
            }
        } label: { Image(systemName: st.isActive ? "square.stack.3d.up.fill" : "square.stack.3d.up").foregroundStyle(st.isActive ? Theme.accent : Theme.text) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 26)
            .help("Isolate or explode levels in 3D (LEVELVIEW3D), field of view (FOV)")
    }
}

// MARK: - Click-to-place with Space rotation (MOD-029)

@MainActor
enum Placement {
    enum Preview { case geometry(Geometry), element(BIMElement) }
    static func angle(_ turns: Int) -> Double { Double(((turns % 4) + 4) % 4) * .pi / 2 }
    static func degrees(_ turns: Int) -> Int { ((turns % 4) + 4) % 4 * 90 }
    /// What the palette item will look like placed at `p` with `turns` quarter turns.
    static func preview(_ item: String, at p: Vec2, turns: Int, doc: ArchiDocument) -> Preview? {
        if item.hasPrefix(ToolDrop.blockPrefix) {
            let n = String(item.dropFirst(ToolDrop.blockPrefix.count))
            guard doc.blocks[n] != nil else { return nil }
            return .geometry(.insert(InsertGeom(block: n, position: p, rotation: angle(turns))))
        }
        if item.hasPrefix(ToolDrop.componentPrefix), let f = ComponentLibrary.family(String(item.dropFirst(ToolDrop.componentPrefix.count))) {
            return .element(BIMElement(id: -1, level: doc.currentLevel, name: f.name, layer: doc.currentLayer,
                                       geometry: .component(ComponentGeom(category: f.category, position: p, rotation: angle(turns), size: f.size, baseOffset: f.baseOffset, family: f.id))))
        }
        return nil
    }
}
