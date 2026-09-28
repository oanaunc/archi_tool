// Oanarina Archi Tool — GPL-3.0-or-later
// FILEPREVIEW on Windows: the preview picture embedded in saved .archi files (IO/ArchiFile.swift, PlanImageExport.thumbnail)
// that the Explorer thumbnail handler (windows/native/ArchiThumbnail.cpp) reads, and the archi-engine command
// (Host/EngineRecovery.swift).
import XCTest
@testable import ArchiCore

final class FilePreviewTests: XCTestCase {
    func obj(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
        var o = EngineObject()
        for (k, v) in pairs { o.set(k, v) }
        return o.json
    }
    func tmp(_ name: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-preview-" + String(ProcessInfo.processInfo.processIdentifier) + "-" + name)
        try? FileManager.default.removeItem(at: u)
        return u
    }
    @MainActor func session() -> (EngineSession, NotificationSink) {
        let reg = CommandRegistry()
        EngineSession.registerPortableAppCommands(reg)
        EngineSession.registerToolCommands(reg)
        let sink = NotificationSink()
        let s = EngineSession(editor: Editor(registry: reg), emit: { sink.lines.append($0) })
        return (s, sink)
    }
    @MainActor func feed(_ s: EngineSession, _ line: String, _ answers: [String] = []) async throws {
        var st = try await s.call("command.run", obj([("line", .string(line))]))
        for a in answers where st["active"]?.boolValue == true {
            st = try await s.call("input.text", obj([("text", .string(a))]))
        }
        if st["active"]?.boolValue == true { _ = try await s.call("input.key", obj([("key", .string("Escape"))])) }
    }
    func nonWhite(_ img: RGBAImage) -> Int {
        var n = 0
        for y in 0..<img.height { for x in 0..<img.width { let p = img.pixel(x, y); if p.r < 0.9 || p.g < 0.9 || p.b < 0.9 { n += 1 } } }
        return n
    }
    func lineDoc() -> ArchiDocument {
        var d = ArchiDocument()
        d.entities.append(Entity(id: 1, layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(5000, 3000)))))
        return d
    }

    func testThumbnailIsASquarePlanPicture() throws {
        let img = try XCTUnwrap(PlanImageExport.thumbnail(doc: lineDoc(), size: 256))
        XCTAssertEqual(img.width, 256)
        XCTAssertEqual(img.height, 256)
        XCTAssertGreaterThan(nonWhite(img), 100)
        XCTAssertLessThan(nonWhite(img), 256 * 256 / 4)
        XCTAssertNil(PlanImageExport.thumbnail(doc: ArchiDocument(), size: 256), "nothing drawn: no picture")
    }

    func testPreviewIsTheLastEnvelopeKeyAndOldReadersIgnoreIt() throws {
        let doc = lineDoc()
        let img = try XCTUnwrap(PlanImageExport.thumbnail(doc: doc, size: 128))
        let p = ArchiFile.PreviewImage(png: img.pngData(alpha: false), width: 128, height: 128)
        let data = try ArchiFile.encode(doc, preview: p)
        XCTAssertEqual(ArchiFile.preview(in: data), p)
        let text = String(decoding: data, as: UTF8.self)
        let k = try XCTUnwrap(text.range(of: "\"preview\"", options: .backwards))
        XCTAssertGreaterThan(k.lowerBound, try XCTUnwrap(text.range(of: "\"document\"")).lowerBound)
        // The document decodes the same with and without the picture, on the fast and on the migrating path.
        XCTAssertEqual(try ArchiFile.decode(data).entities.count, 1)
        XCTAssertEqual(try ArchiFile.decodeMigrating(data).entities.count, 1)
        XCTAssertNil(ArchiFile.preview(in: try ArchiFile.encode(doc)))
        // A "preview" key inside the document is not the envelope picture.
        var d2 = doc
        d2.entities[0].props["preview"] = "x"
        XCTAssertNil(ArchiFile.preview(in: try ArchiFile.encode(d2)))
    }

    @MainActor func testEngineSaveEmbedsThePictureAndFilePreviewCommand() async throws {
        let (s, sink) = session()
        XCTAssertEqual(s.editor.registry.lookup("FILEPREVIEW")?.name, "FILEPREVIEW")
        XCTAssertEqual(s.editor.registry.lookup("FINDERPREVIEW")?.name, "FILEPREVIEW")
        try await feed(s, "LINE", ["0,0", "5000,0", "5000,4000", ""])
        let f = tmp("house.archi")
        _ = try await s.call("doc.save", obj([("path", .string(f.path))]))
        let p = try XCTUnwrap(ArchiFile.preview(in: Data(contentsOf: f)))
        XCTAssertEqual(p.width, EngineRecovery.previewSize)
        XCTAssertGreaterThan(nonWhite(try RGBAImage.decodePNG(p.png)), 100)
        XCTAssertEqual(try ArchiFile.decode(Data(contentsOf: f)).entities.count, s.editor.doc.entities.count)
        // Icons Off: saves carry no picture; Update writes it into the saved file anyway.
        try await feed(s, "FILEPREVIEW", ["Icons", "Off"])
        XCTAssertFalse(s.recoveryState.previewOnSave)
        s.flushNotifications()
        XCTAssertTrue(sink.lines.contains { $0.contains("finderPreviewIcons") }, "the shell stores the preference")
        _ = try await s.call("doc.save", .object([]))
        XCTAssertNil(ArchiFile.preview(in: try Data(contentsOf: f)))
        try await feed(s, "FILEPREVIEW", ["Update"])
        XCTAssertNotNil(ArchiFile.preview(in: try Data(contentsOf: f)))
        XCTAssertTrue(s.editor.log.contains { $0.contains("house.archi updated") }, s.editor.log.suffix(3).joined(separator: " | "))
        try await feed(s, "FILEPREVIEW", ["Show"])
        XCTAssertTrue(s.editor.log.contains { $0.contains("Explorer thumbnail: \(EngineRecovery.previewSize)×\(EngineRecovery.previewSize)") }, s.editor.log.suffix(8).joined(separator: " | "))
        XCTAssertTrue(s.editor.log.contains { $0.contains("org.oanarina.archi.entityCount: \(s.editor.doc.entities.count)") }, s.editor.log.suffix(8).joined(separator: " | "))
        try await feed(s, "FILEPREVIEW", ["Versions", "Off"])
        XCTAssertFalse(s.recoveryState.versionsOnSave)
        // recovery.setup passes the stored preferences.
        _ = try await s.call("recovery.setup", obj([("previewOnSave", .bool(true))]))
        XCTAssertTrue(s.recoveryState.previewOnSave)
    }
}
