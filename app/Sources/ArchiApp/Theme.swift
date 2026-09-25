// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Dark neutral workspace palette (AutoCAD / Revit dark) with a yellow accent.
enum Theme {
    static let canvasHex: UInt32 = 0x1E1F22
    static let canvas = Color(hex: 0x1E1F22)
    static let panel = Color(hex: 0x26272B)
    static let ribbon = Color(hex: 0x2F3035)
    static let ribbonTabBar = Color(hex: 0x232428)
    static let field = Color(hex: 0x1B1C1F)
    static let hover = Color.white.opacity(0.07)
    static let pressed = Color.white.opacity(0.12)
    static let separator = Color.white.opacity(0.09)
    static let text = Color(hex: 0xE6E6E6)
    static let textDim = Color(hex: 0x9A9BA1)
    static let textFaint = Color(hex: 0x6B6C72)
    static let accent = Color(hex: 0xF5C518)
    static let accentText = Color(hex: 0x1E1F22)
    static let danger = Color(hex: 0xE5534B)
    static let windowBlue = Color(red: 0.25, green: 0.45, blue: 0.95)
    static let crossingGreen = Color(red: 0.25, green: 0.8, blue: 0.4)

    static let nsCanvas = NSColor(hex: 0x1E1F22)
    static let nsPanel = NSColor(hex: 0x26272B)
    static let nsAccent = NSColor(hex: 0xF5C518)
    static let nsText = NSColor(hex: 0xE6E6E6)
    static let nsTextDim = NSColor(hex: 0x9A9BA1)
    static let nsField = NSColor(hex: 0x1B1C1F)

    static let font = Font.system(size: 11)
    static let fontSmall = Font.system(size: 10)
    static let fontBold = Font.system(size: 11, weight: .semibold)
    static let mono = Font.system(size: 11, design: .monospaced)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    init(_ c: RGBA) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension RGBA {
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(self) }
    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }
    init(_ c: Color) { self.init(NSColor(c)) }
}

/// Resolves a ColorRef for display (ByLayer shows the layer color).
func displayColor(_ ref: ColorRef, layer: String, doc: ArchiDocument) -> RGBA {
    switch ref {
    case .byLayer, .byBlock: return doc.layer(named: layer)?.color ?? .white
    case .aci(let i): return aciColor(i)
    case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }
}

/// Flat, compact button style used across panels and the command line.
struct FlatButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        FlatButtonBody(configuration: configuration, prominent: prominent, compact: compact)
    }
    private struct FlatButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(Theme.font)
                .foregroundStyle(prominent ? Theme.accentText : (enabled ? Theme.text : Theme.textFaint))
                .padding(.horizontal, compact ? 6 : 10)
                .padding(.vertical, compact ? 3 : 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(prominent ? Theme.accent.opacity(configuration.isPressed ? 0.8 : (hovering ? 0.92 : 1))
                              : (configuration.isPressed ? Theme.pressed : (hovering && enabled ? Theme.hover : Color.clear)))
                )
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(prominent ? Color.clear : Theme.separator, lineWidth: 1))
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

/// Small icon-only toolbar button.
struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 20)
                .foregroundStyle(active ? Theme.accent : (enabled ? Theme.text : Theme.textFaint))
                .background(RoundedRectangle(cornerRadius: 4).fill(hovering && enabled ? Theme.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Section header used in the side panels.
struct PanelHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }
}

struct HSeparator: View {
    var body: some View { Rectangle().fill(Theme.separator).frame(height: 1) }
}
struct VSeparator: View {
    var body: some View { Rectangle().fill(Theme.separator).frame(width: 1) }
}

/// Color swatch square.
struct Swatch: View {
    let color: RGBA
    var size: CGFloat = 11
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(Color(color))
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}

/// Dark text-field look for inline editing.
struct DarkFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.font)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.separator, lineWidth: 1))
    }
}
extension View {
    func darkField() -> some View { modifier(DarkFieldStyle()) }
}

/// Standard AutoCAD lineweights (mm).
let standardLineweights: [Double] = [0, 0.05, 0.09, 0.13, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.53, 0.60, 0.70, 0.80, 0.90, 1.00, 1.06, 1.20, 1.40, 1.58, 2.00, 2.11]

/// Basic color choices (ACI) for color menus.
let basicColors: [(String, ColorRef)] = [("Red", .aci(1)), ("Yellow", .aci(2)), ("Green", .aci(3)), ("Cyan", .aci(4)), ("Blue", .aci(5)),
                                         ("Magenta", .aci(6)), ("White", .aci(7)), ("Gray", .aci(8)), ("Light Gray", .aci(9)),
                                         ("Orange", .aci(30)), ("Brown", .aci(34))]
