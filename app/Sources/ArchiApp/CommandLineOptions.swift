// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Command line appearance (CMD-013) and floating command line (CMD-014)

/// Command line text size, history lines shown, background opacity and docked/floating placement (user defaults).
enum CommandLineAppearance {
    static let fontKey = "cmdline.fontSize", linesKey = "cmdline.lines", opacityKey = "cmdline.opacity", floatingKey = "cmdline.floating"
    static let floatXKey = "cmdline.floatX", floatYKey = "cmdline.floatY"
    static let defaultFont = 11.0, defaultLines = 4, defaultOpacity = 0.55
    static func clampFont(_ v: Double) -> Double { min(max(v, 8), 20) }
    static func clampLines(_ v: Int) -> Int { min(max(v, 1), 40) }
    static func clampOpacity(_ v: Double) -> Double { min(max(v, 0.1), 1) }
    static func rowHeight(_ font: Double) -> CGFloat { CGFloat((clampFont(font) * 1.36).rounded()) }
    /// Height of the history area for a font size and number of lines (plus vertical padding).
    static func historyHeight(fontSize: Double, lines: Int) -> CGFloat { rowHeight(fontSize) * CGFloat(clampLines(lines)) + 6 }

    static var fontSize: Double { get { UserDefaults.standard.object(forKey: fontKey) as? Double ?? defaultFont } set { UserDefaults.standard.set(clampFont(newValue), forKey: fontKey) } }
    static var lines: Int { get { UserDefaults.standard.object(forKey: linesKey) as? Int ?? defaultLines } set { UserDefaults.standard.set(clampLines(newValue), forKey: linesKey) } }
    static var opacity: Double { get { UserDefaults.standard.object(forKey: opacityKey) as? Double ?? defaultOpacity } set { UserDefaults.standard.set(clampOpacity(newValue), forKey: opacityKey) } }
    static var floating: Bool { get { UserDefaults.standard.bool(forKey: floatingKey) } set { UserDefaults.standard.set(newValue, forKey: floatingKey) } }

    @MainActor static var command: CommandDef {
        CommandDef("CMDLINEOPTIONS", aliases: ["CLISETTINGS", "COMMANDLINEOPTIONS", "CLIFLOAT"], category: "Settings", summary: "Command line appearance: text Size, history Lines shown, background Opacity; Float it over the canvas or Dock it at the bottom.", modifies: false) { ed in
            let k = try await ed.getKeyword("Command line [Size/Lines/Opacity/Float/Dock/Reset]", ["Size", "Lines", "Opacity", "Float", "Dock", "Reset"], defaultValue: floating ? "Dock" : "Float") ?? "Float"
            switch k {
            case "Size":
                guard let v = try await ed.getDistance("Text size in points (8–20) <\(fmt(fontSize, 1))>", defaultValue: fontSize).value, v >= 8, v <= 20 else { throw CommandError.invalid("Enter 8 to 20.") }
                fontSize = v
            case "Lines":
                guard let v = try await ed.getInteger("History lines shown (1–40) <\(lines)>", defaultValue: lines), (1...40).contains(v) else { throw CommandError.invalid("Enter 1 to 40.") }
                lines = v
            case "Opacity":
                guard let v = try await ed.getDistance("Background opacity (0.1–1) <\(fmt(opacity, 2))>", defaultValue: opacity).value, v >= 0.1, v <= 1 else { throw CommandError.invalid("Enter 0.1 to 1.") }
                opacity = v
            case "Float": floating = true
            case "Dock": floating = false
            default:
                for key in [fontKey, linesKey, opacityKey, floatingKey, floatXKey, floatYKey] { UserDefaults.standard.removeObject(forKey: key) }
            }
            ed.print("Command line: \(fmt(fontSize, 1)) pt, \(lines) line(s), opacity \(fmt(opacity, 2)), \(floating ? "floating" : "docked").")
        }
    }
}

/// The command line floating over the canvas: translucent, rounded, draggable by its grip; double-click docks it.
struct FloatingCommandLine: View {
    @ObservedObject var model: AppModel
    @AppStorage(CommandLineAppearance.floatXKey) private var fx = 0.0
    @AppStorage(CommandLineAppearance.floatYKey) private var fy = -16.0
    @State private var drag: CGSize = .zero
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Capsule().fill(Theme.textDim.opacity(0.6)).frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity).frame(height: 10)
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { v in fx += v.translation.width; fy += v.translation.height; drag = .zero })
            .onTapGesture(count: 2) { CommandLineAppearance.floating = false }
            .help("Drag to move the command line; double-click to dock it")
            CommandLineView(model: model)
        }
        .frame(maxWidth: 860)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel.opacity(0.92)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .padding(.horizontal, 24)
        .offset(x: fx + drag.width, y: min(0, fy + drag.height))
    }
}

// MARK: - Launch arguments (CMD-047)

/// Command-line parameters on launch: `open -a "Oanarina Archi Tool" --args [file.archi] [-t template] [-s script] [-c "COMMAND …"]`
/// (also --open, --template, --script, --run). Files open in windows; the template starts a new drawing from it; the
/// script (command lines or .js) and commands run in the first drawing once it is ready.
struct LaunchArguments: Equatable {
    var files: [String] = []
    var template: String?
    var scripts: [String] = []
    var commands: [String] = []
    var isEmpty: Bool { files.isEmpty && template == nil && scripts.isEmpty && commands.isEmpty }

    static func parse(_ args: [String]) -> LaunchArguments {
        var r = LaunchArguments()
        var i = 0
        func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
        func path(_ s: String) -> String { (s as NSString).expandingTildeInPath }
        while i < args.count {
            let a = args[i]
            switch a {
            case "-t", "--template": if let v = next() { r.template = path(v) }
            case "-s", "--script", "-b": if let v = next() { r.scripts.append(path(v)) }
            case "-c", "--run", "--command": if let v = next() { r.commands.append(v) }
            case "-o", "--open": if let v = next() { r.files.append(path(v)) }
            default:
                // Skip system arguments (-NSDocumentRevisionsDebugMode YES, -psn_…, --selftest).
                if a.hasPrefix("-NS") || a.hasPrefix("-Apple") { i += 1 }
                else if !a.hasPrefix("-") { r.files.append(path(a)) }
            }
            i += 1
        }
        return r
    }

    /// Applies the arguments once the first drawing window exists.
    @MainActor static func apply(_ a: LaunchArguments) {
        guard !a.isEmpty else { return }
        for f in a.files { WindowRouter.openFile(URL(fileURLWithPath: f)) }
        // A template opens as a new untitled drawing based on it.
        if let t = a.template { WindowRouter.openFile(URL(fileURLWithPath: t)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (a.files.isEmpty ? 0.8 : 1.6)) {
            MainActor.assumeIsolated {
                guard let m = AutomationURL.front() else { return }
                for s in a.scripts { m.runCommand("SCRIPT \"\(s)\"") }
                for c in a.commands { m.runCommand(c) }
            }
        }
    }
}
