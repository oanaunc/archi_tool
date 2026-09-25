// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit

/// The real application icon (AppIcon.icns from the bundle), with a drawn fallback when running unbundled.
@MainActor
enum AppIcon {
    static var image: NSImage {
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) { return i }
        if let i = NSApp?.applicationIconImage, i.isValid { return i }
        return NSImage(size: NSSize(width: 128, height: 128), flipped: false) { r in
            NSColor(hex: 0xF5C518).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 8, dy: 8), xRadius: 26, yRadius: 26).fill()
            let s = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: 72, weight: .black), .foregroundColor: NSColor(hex: 0x1E1F22)])
            let sz = s.size()
            s.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
            return true
        }
    }

    /// Installs the bundle icon as the Dock/application icon (needed when the executable runs outside a bundle).
    static func install() {
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) {
            NSApp.applicationIconImage = i
        }
    }
}

struct AppIconView: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: AppIcon.image).resizable().interpolation(.high).frame(width: size, height: size)
    }
}

@MainActor
enum AboutWindow {
    private static var window: NSWindow?
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }
    static func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "About Oanarina Archi Tool"
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = Theme.nsPanel
        w.isOpaque = true
        w.contentViewController = NSHostingController(rootView: AboutView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct AboutView: View {
    private let credits: [(String, String)] = [
        ("LibreCAD", "2D drafting commands, snaps and DXF ideas"),
        ("SolveSpace", "constraint and sketch workflow ideas"),
        ("OpenSCAD", "script-driven solid modelling ideas"),
        ("BRL-CAD", "solid modelling and CSG ideas"),
        ("IfcOpenShell", "IFC4 structure and BIM data ideas"),
        ("CAD Sketcher", "parametric sketch ideas"),
        ("Sverchok", "node-based and generative design ideas"),
    ]
    var body: some View {
        VStack(spacing: 12) {
            AppIconView(size: 96).padding(.top, 18)
            Text("Oanarina Archi Tool").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
            Text(AboutWindow.version).font(Theme.font).foregroundStyle(Theme.textDim)
            Text("Drafting, building design, 3D, rendering and scripting for the Mac.")
                .font(Theme.font).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                Text("FREE SOFTWARE").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
                Text("This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU GPL v3 for details.")
                    .font(Theme.fontSmall).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("View License") {
                        if let u = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(u) }
                        else if let u = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") { NSWorkspace.shared.open(u) }
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
            VStack(alignment: .leading, spacing: 4) {
                Text("THANKS").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
                Text("Ideas and algorithms were studied from these free projects (see THIRD-PARTY.md):").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                ForEach(credits, id: \.0) { n, what in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(n).font(Theme.fontBold).foregroundStyle(Theme.accent).frame(width: 92, alignment: .leading)
                        Text(what).font(Theme.fontSmall).foregroundStyle(Theme.text)
                    }
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
            HStack(spacing: 4) {
                Text("© Oanarina ·").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Link("oanarina.com", destination: URL(string: "https://oanarina.com")!).font(Theme.fontSmall)
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .frame(width: 460)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}
