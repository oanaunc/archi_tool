// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// The portable DEFLATE codec (used on Windows and Linux) against real data and, on the Mac, against Apple's codec.
final class RawDeflateTests: XCTestCase {
    private func samples() -> [Data] {
        var rng = SystemRandomNumberGenerator()
        let text = Data(String(repeating: "WALL 0,0 @6000,0 @0,8500 C · Cedar House, limestone and cedar. ", count: 400).utf8)
        let random = Data((0..<70_000).map { _ in UInt8.random(in: 0...255, using: &rng) })
        let runs = Data((0..<100_000).map { UInt8(($0 / 700) % 7) })
        let mixed = text + random.prefix(5000) + runs.prefix(40_000) + text
        return [Data(), Data([42]), Data("ab".utf8), text, random, runs, mixed]
    }

    func testPortableRoundTrip() throws {
        for d in samples() {
            let c = RawDeflate.deflatePortable(d)
            XCTAssertEqual(try RawDeflate.inflatePortable(c), d, "round trip of \(d.count) bytes")
        }
        let text = samples()[3]
        XCTAssertLessThan(RawDeflate.deflatePortable(text).count, text.count / 10, "repetitive text compresses well")
    }

    func testTrailingBytesAreIgnored() throws {
        let d = Data("Oanarina Archi Tool".utf8)
        XCTAssertEqual(try RawDeflate.inflatePortable(RawDeflate.deflatePortable(d) + Data([1, 2, 3, 4])), d)
    }

    func testCorruptStreamThrows() {
        XCTAssertThrowsError(try RawDeflate.inflatePortable(Data([0xFF, 0xFF, 0xFF])))
        XCTAssertThrowsError(try RawDeflate.inflatePortable(Data([0x00, 0x05, 0x00, 0x00, 0x00])))   // stored block, bad NLEN
    }

    func testPublicAPIRoundTrip() throws {
        for d in samples() { XCTAssertEqual(try RawDeflate.decompress(RawDeflate.compress(d)), d) }
    }

    #if canImport(Darwin)
    /// Streams written by Apple's zlib (dynamic Huffman blocks) must inflate with the portable decoder, and the other way round.
    func testInteroperatesWithAppleCodec() throws {
        for d in samples() {
            let apple = try (d as NSData).compressed(using: .zlib) as Data
            XCTAssertEqual(try RawDeflate.inflatePortable(apple), d, "portable inflate of Apple's stream (\(d.count) bytes)")
            let mine = RawDeflate.deflatePortable(d)
            XCTAssertEqual(try (mine as NSData).decompressed(using: .zlib) as Data, d, "Apple inflate of the portable stream (\(d.count) bytes)")
        }
    }
    #endif
}
