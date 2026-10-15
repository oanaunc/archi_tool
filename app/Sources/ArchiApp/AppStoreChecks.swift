// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// A focused check that runs inside the actual signed sandbox, without changing user drawings or settings.
@MainActor
enum AppStoreChecks {
    static func run() -> Int {
        var failed = 0
        func check(_ ok: Bool, _ name: String) {
            print("\(ok ? "PASS" : "FAIL"): \(name)")
            if !ok { failed += 1 }
        }
        check(AppDistribution.isAppStore, "store distribution channel")
        check(NSHomeDirectory().contains("/Containers/com.oanarina.architool/"), "running inside the app sandbox container")
        let suite = "com.oanarina.architool.sandbox-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiStoreCheck-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("Test.archi")
            let editor = Editor(document: ArchiDocument())
            editor.transaction("Test line") { d in _ = d.add(.line(LineGeom(.zero, Vec2(1000, 0)))) }
            check(editor.doc.entities.count == 1, "drawing edit")
            editor.undo()
            check(editor.doc.entities.isEmpty, "undo")
            editor.redo()
            try ArchiFile.save(editor.doc, to: file, backup: false)
            check(try ArchiFile.decode(Data(contentsOf: file)).entities.count == 1, "save and reopen .archi")
            let export = folder.appendingPathComponent("Test.dxf")
            try DXFWriter.write(editor.doc).write(to: export, atomically: true, encoding: .utf8)
            check(try DXFReader.read(String(contentsOf: export, encoding: .utf8)).entities.count == 1, "DXF export and import")
            let first = FileAccessBookmarks(defaults: defaults, enabled: true)
            check(first.remember(folder), "create security-scoped folder bookmark")
            first.stop()
            let second = FileAccessBookmarks(defaults: defaults, enabled: true)
            second.restore()
            check(try Data(contentsOf: file).isEmpty == false, "read after bookmark restoration")
            second.stop()
            // Invalid or removed bookmarks must not prevent launch or erase other grants.
            defaults.set(["missing": Data([0, 1, 2])], forKey: "SandboxFileBookmarks")
            second.restore(); second.stop()
            check(defaults.dictionary(forKey: "SandboxFileBookmarks")?.count == 1, "invalid bookmark safely ignored")
            let direct = FileAccessBookmarks(defaults: defaults, enabled: false)
            check(direct.remember(file), "website edition does not require bookmark storage")
            check(defaults.dictionary(forKey: "SandboxFileBookmarks")?.count == 1, "website edition preserves preferences")
            check(AppCommandsNav.all.contains { $0.name == "FILEACCESS" && $0.aliases.contains("FA") }, "file-access command and alias")
            check(CommandCatalog.navigationItems.contains { $0.names.contains("FILEACCESS") }, "file-access menu entry")
            let helper = Process()
            helper.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/archi-cli")
            helper.arguments = ["--license"]
            let output = Pipe(); helper.standardOutput = output; helper.standardError = output
            try helper.run()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            helper.waitUntilExit()
            check(helper.terminationStatus == 0 && text.contains("GPL-3.0-or-later"), "bundled helper launches with inherited sandbox")
            if let i = CommandLine.arguments.firstIndex(of: "--deny-write"), CommandLine.arguments.indices.contains(i + 1) {
                let forbidden = URL(fileURLWithPath: CommandLine.arguments[i + 1])
                do {
                    try Data("sandbox probe".utf8).write(to: forbidden, options: .withoutOverwriting)
                    try? FileManager.default.removeItem(at: forbidden)
                    check(false, "ungranted outside-container write is denied")
                } catch { check(true, "ungranted outside-container write is denied") }
            }
            networkChecks(check)
        } catch { check(false, error.localizedDescription) }
        print("Sandbox checks: \(failed) failure(s).")
        return failed
    }

    private static func networkChecks(_ check: (Bool, String) -> Void) {
        CommandRegistry.shared.ensureBuiltins()
        AppCommands.registerAll()
        let model = AppModel()
        let port = UInt16.random(in: 50000...60000)
        do { try AgentServer.shared.start(model: model, port: port) }
        catch { check(false, "agent server: \(error.localizedDescription)"); return }
        defer { AgentServer.shared.stop() }
        func rpc(_ method: String, _ params: [String: Any]) -> [String: Any]? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/rpc")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("Bearer \(AgentServer.shared.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
            var response: [String: Any]?, done = false
            URLSession.shared.dataTask(with: request) { data, _, _ in
                let result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async { response = result; done = true }
            }.resume()
            AppSelfTests.spin(7) { done }
            return response
        }
        // Give the listener time to enter its ready state before the first request.
        AppSelfTests.spin(0.2) { false }
        let added = rpc("run_command", ["command": "CIRCLE 0,0 100"])
        check(added?["result"] != nil && model.doc.entities.count == 1, "command via sandboxed loopback agent API")
        let undone = rpc("undo", [:])
        check(undone?["result"] != nil && model.doc.entities.isEmpty, "undo via sandboxed agent API")
        let engine = ScriptEngine(model: model)
        var result: ScriptResult?
        Task { @MainActor in result = await engine.evaluate("1 + 2") }
        AppSelfTests.spin(5) { result != nil }
        check(result?.error == nil && result?.value == "3", "JavaScriptCore console in sandbox")
    }
}
