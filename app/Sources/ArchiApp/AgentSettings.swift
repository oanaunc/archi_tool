// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Settings ▸ Agents: local JSON-RPC server (port, start/stop, token) and how to connect Claude through MCP.
struct AgentPrefs: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var revealToken = false
    @State private var running = AgentServer.shared.isRunning
    @State private var status = ""
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AgentServerBox(prefs: prefs, revealToken: $revealToken, running: $running, status: $status)
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECT CLAUDE").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude Desktop and Claude Code talk to Oanarina Archi Tool through the bundled archi-cli in MCP mode, or to this running window through the local agent server.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show Setup Instructions…") { showHelp = true }.buttonStyle(FlatButtonStyle(prominent: true))
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator))
            }
        }
        .sheet(isPresented: $showHelp) { ConnectClaudeSheet(onClose: { showHelp = false }) }
    }
}

private struct AgentServerBox: View {
    @ObservedObject var prefs: AppPreferences
    @Binding var revealToken: Bool
    @Binding var running: Bool
    @Binding var status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCAL AGENT SERVER").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle().fill(running ? Color.green : Theme.textFaint).frame(width: 8, height: 8)
                    Text(running ? "Listening on http://127.0.0.1:\(AgentServer.shared.port)/rpc" : "Stopped").font(Theme.fontBold)
                    Spacer()
                    Button(running ? "Stop" : "Start") { toggle() }.buttonStyle(FlatButtonStyle(prominent: !running))
                }
                HStack {
                    Text("Port")
                    TextField("", value: $prefs.agentPort, format: .number.grouping(.never)).darkField().frame(width: 70)
                    Text("(127.0.0.1 only; restart the server to apply)").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                Toggle("Start the agent server when the app launches", isOn: $prefs.agentAutoStart)
                HStack(spacing: 6) {
                    Text("Token").frame(width: 40, alignment: .leading)
                    Text(revealToken ? AgentServer.shared.token : String(repeating: "•", count: 24))
                        .font(Theme.mono).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    IconButton(symbol: revealToken ? "eye.slash" : "eye", help: revealToken ? "Hide" : "Reveal") { revealToken.toggle() }
                    Button("Copy Token") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentServer.shared.token, forType: .string)
                        status = "Token copied. Send it as “Authorization: Bearer <token>”."
                    }
                    .buttonStyle(FlatButtonStyle(compact: true))
                }
                HStack(spacing: 6) {
                    Text("Info file").frame(width: 60, alignment: .leading)
                    Text(AgentServer.infoFileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(Theme.mono).foregroundStyle(Theme.textDim)
                        .lineLimit(1).truncationMode(.middle)
                }
                Text("The token changes every launch. Agents can also read the port and token from the info file while the server runs.")
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.accent) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator))
        }
        .onAppear { running = AgentServer.shared.isRunning }
    }

    private func toggle() {
        if AgentServer.shared.isRunning {
            AgentServer.shared.stop()
            status = "Server stopped."
        } else {
            guard let m = AppModel.all.first(where: { $0.window?.isKeyWindow == true || $0.window?.isMainWindow == true }) ?? AppModel.all.first else {
                status = "Open a document window first."; return
            }
            do {
                try AgentServer.shared.start(model: m, port: UInt16(clamping: max(1024, min(prefs.agentPort, 65535))))
                status = "Server started for “\(m.displayName)”."
            } catch { status = "Could not start: \(error.localizedDescription)" }
        }
        running = AgentServer.shared.isRunning
        for m in AppModel.all { m.agentRunning = running }
    }
}

/// “Connect Claude” help: archi-cli --mcp for Claude Desktop / Claude Code, plus the HTTP agent server.
struct ConnectClaudeSheet: View {
    var onClose: () -> Void
    @State private var copied = ""

    static var cliPath: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/archi-cli").path
        return FileManager.default.fileExists(atPath: bundled) ? bundled : "/Applications/Oanarina Archi Tool.app/Contents/MacOS/archi-cli"
    }
    static var projectPath: String { NSHomeDirectory() + "/Documents/MyProject.archi" }

    static var desktopConfig: String {
        """
        {
          "mcpServers": {
            "oanarina-archi": {
              "command": "\(cliPath)",
              "args": ["\(projectPath)", "--mcp"]
            }
          }
        }
        """
    }
    static var claudeCodeCommand: String { "claude mcp add oanarina-archi -- \"\(cliPath)\" \"\(projectPath)\" --mcp" }
    static var curlExample: String {
        """
        curl -s http://127.0.0.1:\(AgentServer.shared.port)/rpc \\
          -H "Authorization: Bearer $(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("\(AgentServer.infoFileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")))["token"])')" \\
          -d '{"jsonrpc":"2.0","id":1,"method":"run_command","params":{"command":"CIRCLE 0,0 500"}}'
        """
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Connect Claude to Oanarina Archi Tool").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done", action: onClose).buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(14)
            HSeparator()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step("1", "What archi-cli --mcp does",
                         "archi-cli is bundled inside the app. With --mcp it becomes a Model Context Protocol server on stdin/stdout that opens (or creates) one .archi file and exposes tools: run_command (any command line such as WALL 0,0 6000,0), get_document, list_entities, add_entity, update_entity, delete_entities, add_element, export and screenshot. Every change is saved back to the file, so you can open it here afterwards.")
                    step("2", "Claude Desktop", "Settings ▸ Developer ▸ Edit Config, then add this to claude_desktop_config.json and restart Claude Desktop:")
                    code(ConnectClaudeSheet.desktopConfig)
                    step("3", "Claude Code", "Run once in a terminal:")
                    code(ConnectClaudeSheet.claudeCodeCommand)
                    step("4", "Drive this open window instead", "Start the local agent server (Settings ▸ Agents or Script ▸ Start Server). Agents send JSON-RPC 2.0 to 127.0.0.1 with the session token; the same methods are available and you watch the edits live:")
                    code(ConnectClaudeSheet.curlExample)
                    Text("Replace MyProject.archi with your own file. Keep the token private: anyone with it can edit the open drawing while the server runs. The server only accepts connections from this Mac.")
                        .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                    if !copied.isEmpty { Text(copied).font(Theme.fontSmall).foregroundStyle(Theme.accent) }
                }
                .padding(18)
            }
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .frame(width: 640, height: 600)
        .background(Theme.panel)
    }

    private func step(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accentText)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.fontBold)
                Text(text).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func code(_ s: String) -> some View {
        HStack(alignment: .top) {
            Text(s).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
                copied = "Copied to the clipboard."
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(FlatButtonStyle(compact: true)).help("Copy")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
        .padding(.leading, 30)
    }
}

// MARK: - Script library (SCR-003): ~/Library/Application Support/Oanarina Archi Tool/Scripts

@MainActor
enum ScriptLibrary {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/Scripts", isDirectory: true)
    }

    static func ensureFolder() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = """
        // startup.js runs in every new document window when Settings ▸ General ▸ Scripts is on.
        // Rename this file to startup.js to try it. The archi API is documented in the Script console.
        // archi.print("Hello from startup.js — layers:", archi.layers().length);
        """
        try? readme.write(to: folder.appendingPathComponent("startup.example.js"), atomically: true, encoding: .utf8)
    }

    static func scripts() -> [URL] {
        ensureFolder()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["js", "scr", "txt"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func save(name: String, code: String) throws -> URL {
        ensureFolder()
        var n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { n = "script" }
        if !n.lowercased().hasSuffix(".js") { n += ".js" }
        let u = folder.appendingPathComponent(n.replacingOccurrences(of: "/", with: "-"))
        try code.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    static func revealFolder() {
        ensureFolder()
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Runs startup.js for a new document window (once per window).
    static func runStartup(for model: AppModel) {
        guard AppPreferences.shared.runStartupScript else { return }
        let u = folder.appendingPathComponent("startup.js")
        guard FileManager.default.fileExists(atPath: u.path) else { return }
        model.runScriptFile(u)
    }
}
