// Oanarina Archi Tool — GPL-3.0-or-later
// The archi-engine wire protocol: newline-delimited JSON-RPC 2.0 over stdin/stdout (docs/ENGINE-PROTOCOL.md).
import Foundation

public struct EngineError: Error, Equatable {
    public var code: Int
    public var message: String
    public init(_ code: Int, _ message: String) { self.code = code; self.message = message }

    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    /// The request was valid but the engine could not do it (file not found, nothing to save…).
    public static let engineFailure = -32000

    public static func params(_ m: String) -> EngineError { EngineError(invalidParams, m) }
    public static func failed(_ m: String) -> EngineError { EngineError(engineFailure, m) }
}

public enum EngineProtocol {
    public static let version = "1.0"
    public static let jsonrpc = "2.0"

    /// Every request method the engine answers.
    public static let methods: [String] = [
        "engine.hello", "doc.new", "doc.open", "doc.save", "doc.info",
        "command.run", "command.complete", "input.text", "input.point", "input.key", "input.cursor",
        "view.drawList", "pick", "select.window", "select.set", "select.get", "grips.get", "grips.drag",
        "model.meshes", "render.settings", "render.preset",
        "panel.layers", "panel.levels", "panel.properties", "panel.materials", "panel.sheets", "panel.history", "panel.set",
        "edit.undo", "edit.redo", "sysvar.get", "sysvar.set", "file.export", "file.import", "engine.log",
    ] + EngineDialogMethods.all + EngineToolMethods.all + EngineCanvasMethods.all + EngineView3DMethods.all + EngineOutputMethods.all

    public static func response(id: EngineJSON, result: EngineJSON) -> String {
        var o = EngineObject()
        o.set("jsonrpc", jsonrpc)
        o.set("id", id)
        o.set("result", result)
        return o.json.serialized
    }

    public static func errorResponse(id: EngineJSON, _ e: EngineError) -> String {
        var err = EngineObject()
        err.set("code", e.code)
        err.set("message", e.message)
        var o = EngineObject()
        o.set("jsonrpc", jsonrpc)
        o.set("id", id)
        o.set("error", err.json)
        return o.json.serialized
    }

    public static func notification(_ method: String, _ params: EngineJSON) -> String {
        var o = EngineObject()
        o.set("jsonrpc", jsonrpc)
        o.set("method", method)
        o.set("params", params)
        return o.json.serialized
    }
}
