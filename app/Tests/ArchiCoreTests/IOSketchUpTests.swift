// Oanarina Archi Tool — GPL-3.0-or-later
// SketchUp import (IO-043): signature/version detection, preview extraction, guidance without a converter and the
// conversion path through a user converter (a stand-in shell script writing OBJ).
import XCTest
@testable import ArchiCore

final class IOSketchUpTests: XCTestCase {
    /// A file starting like a SketchUp 2021 model: FF FE FF, length, UTF-16 "SketchUp Model", then "{21.0.339}".
    static func fakeSKP(png: Bool = true) -> Data {
        var b: [UInt8] = [0xFF, 0xFE, 0xFF, 0x0E]
        for u in "SketchUp Model".utf16 { b += [UInt8(u & 255), UInt8(u >> 8)] }
        b += [0xFF, 0xFE, 0xFF, 0x0A]
        for u in "{21.0.339}".utf16 { b += [UInt8(u & 255), UInt8(u >> 8)] }
        b += [UInt8](repeating: 7, count: 40)
        if png {
            b += [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 0x49, 0x48, 0x44, 0x52, 1, 2, 3]
            b += [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
        }
        b += [UInt8](repeating: 9, count: 20)
        return Data(b)
    }

    func testHeaderAndPreview() throws {
        let d = Self.fakeSKP()
        let h = try XCTUnwrap(SketchUpImport.header(d))
        XCTAssertEqual(h.version, "21.0.339")
        XCTAssertEqual(h.major, 21)
        XCTAssertNil(SketchUpImport.header(Data("solid x".utf8)))
        let png = try XCTUnwrap(SketchUpImport.preview(d))
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertTrue(png.suffix(8).elementsEqual([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]))
        XCTAssertNil(SketchUpImport.preview(Self.fakeSKP(png: false)))
        XCTAssertTrue(FileImport.importFormats.contains("skp"))
    }

    func testGuidanceWithoutConverterAndConversionThroughOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let skp = dir.appendingPathComponent("house.skp")
        try Self.fakeSKP().write(to: skp)
        var doc = ArchiDocument()
        doc.setVariable("SKPCONVERTER", dir.appendingPathComponent("missing").path)
        XCTAssertThrowsError(try FileImport.load(skp, reference: doc)) { e in
            let m = (e as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(m.contains("SketchUp 21"), m)
            XCTAssertTrue(m.contains("COLLADA"), m)
        }
        // A converter writing OBJ (it is asked for .dae first and declines).
        let tool = dir.appendingPathComponent("skpconv.sh")
        try "#!/bin/sh\ncase \"$2\" in *.obj) printf 'v 0 0 0\\nv 1 0 0\\nv 0 1 0\\nf 1 2 3\\n' > \"$2\";; esac\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        doc.setVariable("SKPCONVERTER", tool.path)
        let (d, summary) = try FileImport.load(skp, reference: doc)
        XCTAssertTrue(summary.contains("21.0.339") && summary.contains("OBJ"), summary)
        XCTAssertEqual(d.entities.count, 1)
        if case .solid(let s) = d.entities.first?.geometry { XCTAssertEqual(s.meshTriangles.count, 3) } else { XCTFail("mesh expected") }
    }
}
