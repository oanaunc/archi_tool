// Oanarina Archi Tool command-line runner — GPL-3.0-or-later
// File life-cycle options: --upgrade, --verify, --metadata, --api-reference, --run-samples, --license.
import Foundation
import ArchiCore

let licenseNotice = """
Oanarina Archi Tool — free software under the GNU General Public License, version 3 or later (GPL-3.0-or-later).
You may redistribute and modify it under those terms; it comes with ABSOLUTELY NO WARRANTY.
Third-party notices: docs/THIRD-PARTY.md. Full licence text: LICENSE (in the app bundle: Contents/Resources/LICENSE.txt).

Privacy: no telemetry, analytics or crash reports are sent. The application and archi-cli work fully offline; network
access happens only for features you invoke explicitly (BCFSERVER to a BCF server you name, automation webhooks you
configure, the local agent server on 127.0.0.1 when you enable it).
"""

/// Handles the stand-alone options; returns an exit code, or nil to continue with the normal run.
@MainActor func fileLifecycleOptions(_ args: inout [String]) async -> Int32? {
    if args.contains("--license") { print(licenseNotice); return 0 }
    if let i = args.firstIndex(of: "--upgrade") {
        let files = args[(i + 1)...].filter { !$0.hasPrefix("--") }
        guard !files.isEmpty else { eprint("--upgrade FILES…"); return 2 }
        var failed = 0
        for f in files {
            let u = expand(f)
            do {
                let r = try ArchiFile.upgradeFile(u)
                print(r.from == r.to ? "\(u.lastPathComponent): already format \(r.to)" : "\(u.lastPathComponent): format \(r.from) → \(r.to) (backup \(r.backup?.lastPathComponent ?? "none"))")
            } catch { failed += 1; eprint("\(u.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
        }
        return failed == 0 ? 0 : 1
    }
    if let i = args.firstIndex(of: "--verify") {
        guard i + 1 < args.count else { eprint("--verify FILE"); return 2 }
        let u = expand(args[i + 1])
        do {
            let d = try loadDocument(u)
            let diffs = try ArchiFile.roundTripDifferences(d)
            print(diffs.isEmpty ? "\(u.lastPathComponent): round trip OK (\(d.entities.count) objects, \(d.elements.count) elements)" : "\(u.lastPathComponent): changes in " + diffs.joined(separator: ", "))
            return diffs.isEmpty ? 0 : 1
        } catch { eprint("\(u.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"); return 1 }
    }
    if let i = args.firstIndex(of: "--metadata") {
        guard i + 1 < args.count else { eprint("--metadata FILE"); return 2 }
        do { print(ArchiJSON.jsonString(try SpotlightMetadata.attributes(of: expand(args[i + 1])), pretty: true)); return 0 }
        catch { eprint((error as? LocalizedError)?.errorDescription ?? "\(error)"); return 1 }
    }
    if let i = args.firstIndex(of: "--api-reference") {
        CommandRegistry.shared.ensureBuiltins()
        let tools = MCPServer(editor: Editor(), path: nil).tools
        let md = APIReference.markdown(tools: tools, version: cliVersion)
        if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            let u = expand(args[i + 1])
            do { try md.write(to: u, atomically: true, encoding: .utf8); print("Wrote \(u.path)") } catch { eprint("Cannot write \(u.path)"); return 1 }
        } else { print(md) }
        return 0
    }
    if let i = args.firstIndex(of: "--check-update") {
        // Explicit, user-requested network access only.
        guard i + 1 < args.count, let u = URL(string: args[i + 1]) else { eprint("--check-update APPCAST_URL [--current VERSION]"); return 2 }
        let current = args.firstIndex(of: "--current").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? cliVersion
        do {
            let (status, data) = try BCFAPIClient.urlSession(URLRequest(url: u))
            guard (200..<300).contains(status) else { eprint("HTTP \(status)"); return 1 }
            let v = ProcessInfo.processInfo.operatingSystemVersion
            if let n = UpdateCheck.newer(UpdateCheck.parseAppcast(data), than: current, system: "\(v.majorVersion).\(v.minorVersion)") {
                print("Update available: \(n.displayVersion) — \(n.url)")
            } else { print("Up to date (\(current)).") }
            return 0
        } catch { eprint((error as? LocalizedError)?.errorDescription ?? "\(error)"); return 1 }
    }
    if args.contains("--run-samples") {
        CommandRegistry.shared.ensureBuiltins()
        let r = await APIReference.runSamples()
        for x in r { print("\(x.passed ? "ok  " : "FAIL") \(x.title)"); if !x.passed { x.log.forEach { print("     \($0)") } } }
        return r.allSatisfy(\.passed) ? 0 : 1
    }
    return nil
}
