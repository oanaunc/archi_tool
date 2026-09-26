// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Tiled model views (APP-007, VPORTS): the split workspace shows 2, 3 or 4 views — plan, 3D, section or elevation —
/// each with its own zoom and pan. The arrangement is remembered across launches.
enum TileKind: String, CaseIterable, Identifiable, Codable {
    case plan = "Plan", model = "3D", section = "Section", north = "North", south = "South", east = "East", west = "West"
    var id: String { rawValue }
    var viewKind: ViewKind? {
        switch self {
        case .section: return .section; case .north: return .elevationNorth; case .south: return .elevationSouth
        case .east: return .elevationEast; case .west: return .elevationWest; default: return nil
        }
    }
}

enum TileArrangement: String, CaseIterable, Identifiable, Codable {
    case two = "Two: side by side", twoStacked = "Two: stacked", three = "Three: one left, two right", four = "Four: equal"
    var id: String { rawValue }
    var count: Int { switch self { case .two, .twoStacked: return 2; case .three: return 3; case .four: return 4 } }
}

@MainActor
enum TiledViewsState {
    static let arrangementKey = "tiles.arrangement", kindsKey = "tiles.kinds"
    static var arrangement: TileArrangement {
        get { UserDefaults.standard.string(forKey: arrangementKey).flatMap(TileArrangement.init) ?? .two }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: arrangementKey) }
    }
    static let defaultKinds: [TileKind] = [.plan, .model, .section, .south]
    /// View kind per tile (4 slots; the arrangement shows the first n).
    static var kinds: [TileKind] {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: kindsKey) ?? []
            var k = raw.compactMap(TileKind.init)
            while k.count < 4 { k.append(defaultKinds[k.count]) }
            return Array(k.prefix(4))
        }
        set { UserDefaults.standard.set(newValue.prefix(4).map(\.rawValue), forKey: kindsKey) }
    }
    static func setKind(_ k: TileKind, at i: Int) { var a = kinds; if a.indices.contains(i) { a[i] = k; kinds = a } }
}

struct TiledViews: View {
    @ObservedObject var model: AppModel
    @State private var arrangement = TiledViewsState.arrangement
    @State private var kinds = TiledViewsState.kinds

    var body: some View {
        Group {
            switch arrangement {
            case .two: HSplitView { tile(0); tile(1) }
            case .twoStacked: VSplitView { tile(0); tile(1) }
            case .three: HSplitView { tile(0); VSplitView { tile(1); tile(2) } }
            case .four: VSplitView { HSplitView { tile(0); tile(1) }; HSplitView { tile(2); tile(3) } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tilesChanged)) { _ in arrangement = TiledViewsState.arrangement; kinds = TiledViewsState.kinds }
    }

    @ViewBuilder private func tile(_ i: Int) -> some View {
        let k = kinds[i]
        Group {
            switch k {
            case .plan: PlanCanvas(model: model)
            case .model: Viewport3DView(model: model)
            default: ProjectionTile(model: model, view: k.viewKind ?? .section)
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Menu {
                ForEach(TileKind.allCases) { t in Button { TiledViewsState.setKind(t, at: i); kinds = TiledViewsState.kinds } label: { if t == k { Label(t.rawValue, systemImage: "checkmark") } else { Text(t.rawValue) } } }
                Divider()
                ForEach(TileArrangement.allCases) { a in Button { TiledViewsState.arrangement = a; arrangement = a } label: { if a == arrangement { Label(a.rawValue, systemImage: "checkmark") } else { Text(a.rawValue) } } }
            } label: { Text(k.rawValue).font(.system(size: 10, weight: .semibold)) }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.45)))
            .padding(6)
            .help("View shown in this tile · tile arrangement")
        }
    }
}

extension Notification.Name { static let tilesChanged = Notification.Name("ArchiTilesChanged") }

/// A section or elevation of the model (hidden-line projection) with its own zoom and pan.
struct ProjectionTile: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let view: ViewKind
    func makeNSView(context: Context) -> ProjectionTileView { let v = ProjectionTileView(); v.model = model; v.kind = view; return v }
    func updateNSView(_ v: ProjectionTileView, context: Context) {
        if v.kind != view { v.kind = view; v.cache = nil; v.fitted = false }
        v.model = model
        v.needsDisplay = true
    }
}

final class ProjectionTileView: NSView {
    weak var model: AppModel?
    var kind: ViewKind = .section
    var cache: (stamp: Int, entries: [DrawEntry], bounds: BBox2)?
    /// Model units → view points and the model point at the view centre.
    private(set) var zoom: CGFloat = 0.02
    private(set) var center = CGPoint.zero
    var fitted = false
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func entries() -> (entries: [DrawEntry], bounds: BBox2) {
        guard let model else { return ([], .empty) }
        if let c = cache, c.stamp == model.editor.changeCount { return (c.entries, c.bounds) }
        let vp = Viewport(origin: .zero, size: Vec2(1, 1), viewCenter: .zero, scale: 1, view: kind)
        let e = SheetComposer.viewportEntries(doc: model.doc, vp: vp)
        var b = BBox2.empty
        for x in e { b.add(x.bounds) }
        cache = (model.editor.changeCount, e, b)
        return (e, b)
    }
    func fit() {
        let b = entries().bounds
        guard !b.isEmpty, bounds.width > 10, bounds.height > 10 else { return }
        zoom = min(bounds.width * 0.9 / CGFloat(max(b.width, 1)), bounds.height * 0.9 / CGFloat(max(b.height, 1)))
        center = CGPoint(x: b.center.x, y: b.center.y)
        fitted = true
    }
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: bounds.midX, y: bounds.midY).scaledBy(x: zoom, y: zoom).translatedBy(x: -center.x, y: -center.y)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(.white); ctx.fill(bounds)
        if !fitted { fit() }
        let (e, _) = entries()
        var r = PlotRenderer(transform: transform, devicePerMM: 2.2, paper: true, minLineWidth: 0.5)
        r.lineweightScale = 1
        r.draw(e, in: ctx, visible: bounds)
        let label = SheetComposer.viewTitle(Viewport(origin: .zero, size: .zero, viewCenter: .zero, view: kind), doc: model?.doc ?? ArchiDocument())
        (label as NSString).draw(at: CGPoint(x: 8, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.darkGray])
    }
    override func scrollWheel(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) { pan(dx: e.scrollingDeltaX, dy: -e.scrollingDeltaY); return }
        zoom(by: pow(1.2, e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 40 : e.scrollingDeltaY), about: p)
    }
    override func magnify(with e: NSEvent) { zoom(by: max(0.2, 1 + e.magnification), about: convert(e.locationInWindow, from: nil)) }
    override func mouseDragged(with e: NSEvent) { pan(dx: e.deltaX, dy: -e.deltaY) }
    override func otherMouseDragged(with e: NSEvent) { pan(dx: e.deltaX, dy: -e.deltaY) }
    override func mouseDown(with e: NSEvent) { if e.clickCount == 2 { fit(); needsDisplay = true } }
    func pan(dx: CGFloat, dy: CGFloat) { center.x -= dx / zoom; center.y -= dy / zoom; needsDisplay = true }
    func zoom(by f: CGFloat, about p: CGPoint) {
        let w = CGPoint(x: (p.x - bounds.midX) / zoom + center.x, y: (p.y - bounds.midY) / zoom + center.y)
        zoom = min(max(zoom * f, 1e-6), 1e3)
        center = CGPoint(x: w.x - (p.x - bounds.midX) / zoom, y: w.y - (p.y - bounds.midY) / zoom)
        needsDisplay = true
    }
}
