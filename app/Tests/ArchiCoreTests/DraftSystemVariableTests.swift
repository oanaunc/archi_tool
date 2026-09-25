// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftSystemVariableTests: XCTestCase {
    func testCatalogCoverage() {
        XCTAssertGreaterThanOrEqual(SysVarCatalog.all.count, 150)
        XCTAssertEqual(Set(SysVarCatalog.all.map(\.name)).count, SysVarCatalog.all.count, "no duplicates")
        for n in ["OSMODE", "ORTHOMODE", "CLAYER", "LTSCALE", "PDMODE", "MIRRTEXT", "DIMSCALE", "FILEDIA", "CMDECHO", "PICKFIRST", "LUNITS", "AUNITS", "HPNAME", "INSUNITS", "TEXTSIZE", "USERI1"] {
            XCTAssertNotNil(SysVarCatalog.info(n), n)
        }
        // Every numeric default satisfies its own range.
        for i in SysVarCatalog.all where !i.readOnly && !i.defaultValue.isEmpty && (i.kind == .integer || i.kind == .real) {
            XCTAssertNil(SysVarCatalog.validate(i, i.defaultValue).1, i.name)
        }
    }

    func testGetSetSemantics() async {
        let ed = Editor()
        XCTAssertEqual(SystemVariables.get("MIRRTEXT", ed), "0", "catalog default")
        XCTAssertNotNil(SystemVariables.set("MIRRTEXT", "2", ed), "flag rejects 2")
        XCTAssertNil(SystemVariables.set("MIRRTEXT", "on", ed))
        XCTAssertEqual(ed.doc.variable("MIRRTEXT"), "1")
        XCTAssertNotNil(SystemVariables.set("PDMODE", "3.5", ed), "integer required")
        XCTAssertNotNil(SystemVariables.set("LUNITS", "9", ed), "range")
        XCTAssertNil(SystemVariables.set("LUNITS", "4", ed))
        XCTAssertNotNil(SystemVariables.set("ANGDIR", "2", ed), "allowed values")
        XCTAssertNotNil(SystemVariables.set("DWGNAME", "x", ed), "read-only")
        XCTAssertNotNil(SystemVariables.set("LTSCALE", "0", ed))
        XCTAssertNil(SystemVariables.set("LIMMAX", "1000,500", ed))
        XCTAssertEqual(ed.doc.variable("LIMMAX"), "1000,500")
        // Dimension variables drive the current dimension style.
        XCTAssertNil(SystemVariables.set("DIMTXT", "3.5", ed))
        XCTAssertEqual(ed.doc.dimStyle.textHeight, 3.5)
        XCTAssertEqual(SystemVariables.get("DIMTXT", ed), "3.5")
        XCTAssertNil(SystemVariables.set("DIMSCALE", "100", ed))
        XCTAssertEqual(ed.doc.dimStyle.scale, 100); XCTAssertEqual(ed.doc.variable("DIMSCALE"), "100")
        XCTAssertNil(SystemVariables.set("DIMBLK", "archtick", ed)); XCTAssertEqual(ed.doc.dimStyle.arrow, .architecturalTick)
        // Computed read-only values.
        await ed.run("LINE 0,0 1000,500 ")
        XCTAssertEqual(SystemVariables.get("EXTMAX", ed), "1000,500")
        XCTAssertEqual(SystemVariables.get("EXTMIN", ed), "0,0")
        XCTAssertEqual(SystemVariables.get("DBMOD", ed), "1")
        XCTAssertEqual(SystemVariables.get("CDATE", ed)?.count, 15)
        XCTAssertEqual(SystemVariables.get("CMDACTIVE", ed), "0")
        // Typed as commands, and through SETVAR.
        await ed.run("USERI1 42")
        XCTAssertEqual(SystemVariables.get("USERI1", ed), "42")
        await ed.run("SETVAR USERS1 hello")
        XCTAssertEqual(ed.doc.variable("USERS1"), "hello")
        let out = await ed.run("SETVAR ? DIMT*")
        XCTAssertTrue(out.contains { $0.hasPrefix("DIMTXT = 3.5") })
        XCTAssertFalse(out.contains { $0.hasPrefix("OSMODE") })
        let bad = await ed.run("SETVAR POLYSIDES 2")
        XCTAssertTrue(bad.contains { $0.contains("between 3 and 1024") })
    }
}
