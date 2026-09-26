// Oanarina Archi Tool — GPL-3.0-or-later
// Update checks (SYS-024) and opt-in crash reports (SYS-025).
import XCTest
@testable import ArchiCore

final class IOUpdateCrashTests: XCTestCase {
    func testAppcastAndVersions() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><title>Oanarina Archi Tool</title>
            <item><title>1.9</title><sparkle:version>190</sparkle:version><sparkle:shortVersionString>1.9</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
              <enclosure url="https://example.org/a-1.9.dmg" length="1000" type="application/octet-stream" sparkle:edSignature="abc"/></item>
            <item><title>1.10</title><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
              <enclosure url="https://example.org/a-1.10.dmg" length="2000" sparkle:version="1100" sparkle:shortVersionString="1.10"/></item>
            <item><title>2.0</title><sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
              <enclosure url="https://example.org/a-2.0.dmg" length="3000" sparkle:version="2000" sparkle:shortVersionString="2.0"/></item>
          </channel></rss>
        """
        let items = UpdateCheck.parseAppcast(Data(xml.utf8))
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].edSignature, "abc"); XCTAssertEqual(items[1].shortVersion, "1.10"); XCTAssertEqual(items[1].length, 2000)
        XCTAssertEqual(UpdateCheck.compare("1.10", "1.9"), .orderedDescending)
        XCTAssertEqual(UpdateCheck.compare("1.0", "1"), .orderedSame)
        XCTAssertEqual(UpdateCheck.newer(items, than: "1.9", system: "14.6")?.shortVersion, "1.10", "2.0 needs macOS 15")
        XCTAssertEqual(UpdateCheck.newer(items, than: "1.9", system: "15.1")?.shortVersion, "2.0")
        XCTAssertNil(UpdateCheck.newer(items, than: "2.0", system: "15.1"))
    }

    func testSHA256AndChecksums() {
        XCTAssertEqual(UpdateCheck.sha256(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(UpdateCheck.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(UpdateCheck.sha256(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        let file = Data("dmg bytes".utf8)
        let sums = "\(UpdateCheck.sha256(file))  Oanarina-Archi-Tool-1.10.dmg\n0000  other.dmg\n"
        XCTAssertTrue(UpdateCheck.verify(file, name: "Oanarina-Archi-Tool-1.10.dmg", sums: sums))
        XCTAssertFalse(UpdateCheck.verify(Data("tampered".utf8), name: "Oanarina-Archi-Tool-1.10.dmg", sums: sums))
        XCTAssertFalse(UpdateCheck.verify(file, name: "missing.dmg", sums: sums))
    }

    func testCrashReportsAreRedactedAndOptIn() throws {
        let r = CrashReport.make(reason: "EXC_BAD_ACCESS in /Users/oana/Projects/house.archi", stack: ["0 ArchiApp 0x1 main", "1 libswiftCore"],
                                 commands: ["LINE 0,0 10,0 ", "SAVEAS /Users/oana/Desktop/x.archi", "mail oana@example.com"], version: "1.2",
                                 system: "macOS 14.5", home: "/Users/oana", user: "oana")
        XCTAssertFalse(r.contains("/Users/oana")); XCTAssertFalse(r.contains("oana@example.com")); XCTAssertFalse(r.contains("oana"))
        XCTAssertTrue(r.contains("~/Projects/house.archi")); XCTAssertTrue(r.contains("<email>")); XCTAssertTrue(r.contains("Version: 1.2"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID().uuidString)")
        XCTAssertNil(try CrashReport.write(r, to: dir, enabled: false), "off by default: nothing written")
        XCTAssertTrue(CrashReport.pending(in: dir).isEmpty)
        let u = try CrashReport.write(r, to: dir, enabled: true)
        XCTAssertNotNil(u)
        XCTAssertEqual(CrashReport.pending(in: dir).map(\.lastPathComponent), [u!.lastPathComponent])
        XCTAssertEqual(CrashReport.mailto(r, to: "bugs@example.org")?.scheme, "mailto")
    }
}
