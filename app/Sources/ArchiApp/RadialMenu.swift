// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// Right-drag marking menu (APP-022): the 8 most used commands for the context (drafting, objects selected, building
/// elements selected) around the cursor; drag towards one and release to run it. A right-click without dragging
/// still opens the shortcut menu. RADIALMENU turns it on or off.
@MainActor
enum RadialMenu {
    struct Item: Equatable { var title: String; var symbol: String; var command: String }
    enum Context: String { case drafting = "Drafting", objects = "Objects", building = "Building elements" }

    static let prefKey = "radialMenu"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: prefKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: prefKey) }
    }
    /// Drag distance (points) that opens the menu.
    static let threshold: CGFloat = 12
    static let radius: CGFloat = 96

    static func context(_ doc: ArchiDocument, selection: Set<EntityID>) -> Context {
        if selection.isEmpty { return .drafting }
        return selection.allSatisfy { doc.element($0) != nil } ? .building : .objects
    }

    /// Items clockwise from the top (N, NE, E, SE, S, SW, W, NW).
    static func items(_ c: Context) -> [Item] {
        switch c {
        case .drafting:
            return [Item(title: "Line", symbol: "line.diagonal", command: "LINE"), Item(title: "Polyline", symbol: "point.topleft.down.curvedto.point.bottomright.up", command: "PLINE"),
                    Item(title: "Wall", symbol: "rectangle.split.3x1", command: "WALL"), Item(title: "Door", symbol: "door.left.hand.open", command: "DOOR"),
                    Item(title: "Dimension", symbol: "ruler", command: "DIM"), Item(title: "Window", symbol: "window.vertical.open", command: "WINDOW"),
                    Item(title: "Rectangle", symbol: "rectangle", command: "RECTANG"), Item(title: "Circle", symbol: "circle", command: "CIRCLE")]
        case .objects:
            return [Item(title: "Move", symbol: "arrow.up.and.down.and.arrow.left.and.right", command: "MOVE"), Item(title: "Copy", symbol: "doc.on.doc", command: "COPY"),
                    Item(title: "Rotate", symbol: "rotate.right", command: "ROTATE"), Item(title: "Offset", symbol: "square.on.square.dashed", command: "OFFSET"),
                    Item(title: "Erase", symbol: "trash", command: "ERASE"), Item(title: "Trim", symbol: "scissors", command: "TRIM"),
                    Item(title: "Mirror", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", command: "MIRROR"), Item(title: "Properties", symbol: "slider.horizontal.3", command: "PROPERTIES")]
        case .building:
            return [Item(title: "Move", symbol: "arrow.up.and.down.and.arrow.left.and.right", command: "MOVE"), Item(title: "Copy", symbol: "doc.on.doc", command: "COPY"),
                    Item(title: "Rotate", symbol: "rotate.right", command: "ROTATE"), Item(title: "Array", symbol: "square.grid.3x3", command: "ARRAY"),
                    Item(title: "Erase", symbol: "trash", command: "ERASE"), Item(title: "Match Properties", symbol: "paintbrush", command: "MATCHPROP"),
                    Item(title: "Mirror", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", command: "MIRROR"), Item(title: "Properties", symbol: "slider.horizontal.3", command: "PROPERTIES")]
        }
    }

    /// Sector under a drag vector (view coordinates, y up): nil inside the dead zone.
    static func sector(dx: CGFloat, dy: CGFloat) -> Int? {
        guard hypot(dx, dy) >= threshold else { return nil }
        var a = atan2(dx, dy) * 180 / .pi   // clockwise from up
        if a < 0 { a += 360 }
        return Int(((a + 22.5) / 45).rounded(.down)) % 8
    }

    static func tooltip(_ item: Item, registry: CommandRegistry = .shared) -> String {
        guard let d = registry.lookup(item.command) else { return item.title }
        return "\(item.title) — \(d.summary) [\(d.name)\(d.aliases.isEmpty ? "" : ", " + d.aliases.prefix(2).joined(separator: ", "))]"
    }
}

/// The marking menu drawn around the right-drag origin.
final class RadialMenuView: NSView {
    var items: [RadialMenu.Item] = []
    var highlighted: Int? { didSet { if highlighted != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY), r = RadialMenu.radius
        NSColor(white: 0.12, alpha: 0.88).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r - 30, y: c.y - r - 30, width: 2 * r + 60, height: 2 * r + 60)).fill()
        let accent = NSColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1)
        for (i, it) in items.enumerated() {
            let a = CGFloat(i) * .pi / 4
            let p = NSPoint(x: c.x + sin(a) * r, y: c.y + cos(a) * r)
            let on = highlighted == i
            (on ? accent : NSColor(white: 0.24, alpha: 1)).setFill()
            NSBezierPath(roundedRect: NSRect(x: p.x - 40, y: p.y - 17, width: 80, height: 34), xRadius: 9, yRadius: 9).fill()
            let fg = on ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.92, alpha: 1)
            if let img = NSImage(systemSymbolName: it.symbol, accessibilityDescription: it.title)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
                let tinted = NSImage(size: img.size, flipped: false) { rect in img.draw(in: rect); fg.set(); rect.fill(using: .sourceAtop); return true }
                tinted.draw(in: NSRect(x: p.x - img.size.width / 2, y: p.y + 1, width: img.size.width, height: img.size.height))
            }
            let s = NSAttributedString(string: it.title, attributes: [.font: NSFont.systemFont(ofSize: 9.5, weight: .medium), .foregroundColor: fg])
            s.draw(at: NSPoint(x: p.x - s.size().width / 2, y: p.y - 14))
        }
        NSColor(white: 0.5, alpha: 0.8).setStroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - RadialMenu.threshold, y: c.y - RadialMenu.threshold, width: 2 * RadialMenu.threshold, height: 2 * RadialMenu.threshold)).stroke()
        if let h = highlighted, items.indices.contains(h) {
            let s = NSAttributedString(string: items[h].command, attributes: [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: accent])
            s.draw(at: NSPoint(x: c.x - s.size().width / 2, y: c.y - 30))
        }
    }
}
