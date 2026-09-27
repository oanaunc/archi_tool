// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine: the Oanarina Archi Tool engine as a process for the Windows (and Linux) shell. Reads newline-delimited
// JSON-RPC 2.0 requests on stdin and writes responses and notifications on stdout, one JSON object per line
// (docs/ENGINE-PROTOCOL.md). Diagnostics go to stderr. Portable: Foundation + ArchiCore only.
import Foundation
import ArchiCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#endif

/// Serialised line output (responses and notifications share stdout).
final class LineWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let handle = FileHandle.standardOutput
    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        handle.write(Data((line + "\n").utf8))
    }
}

func eprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let usage = """
archi-engine — Oanarina Archi Tool engine (JSON-RPC 2.0 over stdio, one JSON object per line)
Usage: archi-engine [--open <file>] [--cwd <folder>]
       archi-engine <file.archi> --mcp   (Model Context Protocol server on stdio for Claude, like archi-cli --mcp)
       archi-engine --fixtures <folder> --sample <file.archi>   (record protocol fixtures for the shell, then exit)
       archi-engine --version
Requests and notifications are documented in docs/ENGINE-PROTOCOL.md.
"""

var openPath: String?
var cwd: String?
var fixturesDir: String?
var samplePath: String?
var mcp = false
var argv = Array(CommandLine.arguments.dropFirst())
while !argv.isEmpty {
    let a = argv.removeFirst()
    switch a {
    case "--version": print("archi-engine \(EngineSession.engineVersion) (protocol \(EngineProtocol.version))"); exit(0)
    case "--help", "-h": print(usage); exit(0)
    case "--open": if !argv.isEmpty { openPath = argv.removeFirst() }
    case "--cwd": if !argv.isEmpty { cwd = argv.removeFirst() }
    case "--fixtures": if !argv.isEmpty { fixturesDir = argv.removeFirst() }
    case "--sample": if !argv.isEmpty { samplePath = argv.removeFirst() }
    case "--mcp": mcp = true
    default:
        if !a.hasPrefix("-") && openPath == nil { openPath = a; continue }
        eprint("archi-engine: unknown argument \(a)"); eprint(usage); exit(2)
    }
}

/// Lines from stdin, read on a background thread so a command waiting for input never blocks further requests.
let lines = AsyncStream<String> { continuation in
    let t = Thread {
        while let l = readLine(strippingNewline: true) { continuation.yield(l) }
        continuation.finish()
    }
    t.stackSize = 1 << 20
    t.start()
}

let writer = LineWriter()

@MainActor
func serve() async {
    EngineSession.registerPortableAppCommands()
    EngineSession.registerToolCommands()
    EngineSession.registerOutputCommands()
    let session = EngineSession(emit: { writer.write($0) })
    if let c = cwd { session.baseDirectory = URL(fileURLWithPath: c) }
    session.loadPlugins()
    if let p = openPath {
        var params = EngineObject()
        params.set("path", p)
        do { _ = try await session.call("doc.open", params.json) } catch {
            eprint("archi-engine: could not open \(p): \(error)")
        }
    }
    var ready = EngineObject()
    ready.set("version", EngineSession.engineVersion)
    ready.set("protocol", EngineProtocol.version)
    writer.write(EngineProtocol.notification("ready", ready.json))
    for await line in lines {
        if let response = await session.handle(line: line) { writer.write(response) }
    }
}

@MainActor
func recordFixtures(_ dir: String, _ sample: String) async -> Int32 {
    // Same command set as serve(), so hello.json lists every command the shell can enable.
    EngineSession.registerPortableAppCommands()
    EngineSession.registerToolCommands()
    EngineSession.registerOutputCommands()
    do {
        let names = try await EngineSession.writeFixtures(to: URL(fileURLWithPath: dir), sample: URL(fileURLWithPath: sample))
        eprint("archi-engine: wrote \(names.count) fixture files to \(dir)")
        return 0
    } catch {
        eprint("archi-engine: fixtures failed: \(error)")
        return 1
    }
}

/// MCP mode: one document, tools for agents; engine notifications are not part of the MCP stream.
@MainActor
func serveMCP() async {
    EngineSession.registerPortableAppCommands()
    EngineSession.registerToolCommands()
    EngineSession.registerOutputCommands()
    let session = EngineSession(emit: { _ in })
    if let c = cwd { session.baseDirectory = URL(fileURLWithPath: c) }
    var target: URL?
    if let p = openPath {
        let u = session.url(p)
        if FileManager.default.fileExists(atPath: u.path) {
            var params = EngineObject()
            params.set("path", u.path)
            do { _ = try await session.call("doc.open", params.json) } catch { eprint("archi-engine: cannot open \(u.path): \(error)"); exit(1) }
            if u.pathExtension.lowercased() == "archi" { target = u }
        } else if u.pathExtension.lowercased() == "archi" {
            session.editor.fileURL = u
            target = u
            eprint("\(u.lastPathComponent) does not exist yet; starting a new document (it is created on save).")
        } else {
            eprint("archi-engine: file not found: \(u.path)"); exit(1)
        }
    }
    let server = EngineMCPServer(session: session, path: target, write: { writer.write($0) })
    await server.serve(lines: lines)
}

if mcp {
    await serveMCP()
    exit(0)
}

if let dir = fixturesDir {
    guard let sample = samplePath else { eprint("archi-engine: --fixtures needs --sample <file>"); exit(2) }
    exit(await recordFixtures(dir, sample))
}
await serve()
