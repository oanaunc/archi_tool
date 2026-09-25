// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class ModelCompatibilityTests: XCTestCase {
    func testOldDocumentWithoutNewKeysDecodes() throws {
        // A format-1 document written before opening types, phases, sweeps and slab slopes existed.
        let json = """
        {"app":"Oanarina Archi Tool","formatVersion":1,"document":{"formatVersion":1,"layers":[{"name":"0","color":{"r":1,"g":1,"b":1,"a":1},"linetype":"Continuous","lineweight":0.25,"visible":true,"frozen":false,"locked":false,"plot":true,"transparency":0,"description":""}],
        "entities":[],"nextID":5,"elements":[
          {"id":1,"level":0,"name":"","layer":"A-WALL","props":{},"geometry":{"type":"wall","start":{"x":0,"y":0},"end":{"x":4000,"y":0},"thickness":200,"height":3000,"baseOffset":0,"justification":"center","bulge":0}},
          {"id":2,"level":0,"name":"","layer":"A-DOOR","props":{},"geometry":{"type":"door","kind":"door","hostWall":1,"offset":2000,"width":900,"height":2100,"sill":0,"flipHand":false,"flipFacing":false,"doorStyle":"single","windowStyle":"casement","frameWidth":50}},
          {"id":3,"level":0,"name":"","layer":"A-ELEMENTS","props":{},"geometry":{"type":"slab","boundary":[{"x":0,"y":0},{"x":1,"y":0},{"x":1,"y":1}],"holes":[],"thickness":200,"topOffset":0}},
          {"id":4,"level":0,"name":"","layer":"A-WALL","props":{},"geometry":{"type":"curtainWall","start":{"x":0,"y":0},"end":{"x":1,"y":0},"height":3000,"baseOffset":0,"gridU":1200,"gridV":1500,"mullionSize":60}}
        ]}}
        """
        let doc = try ArchiFile.decode(Data(json.utf8))
        XCTAssertEqual(doc.elements.count, 4)
        XCTAssertEqual(doc.openingTypes, OpeningType.library)
        XCTAssertEqual(doc.phases, ["Existing", "New Construction"])
        XCTAssertEqual(doc.levels.count, 2)
        guard case .wall(let w) = doc.elements[0].geometry, case .opening(let o) = doc.elements[1].geometry,
              case .slab(let s) = doc.elements[2].geometry, case .curtainWall(let c) = doc.elements[3].geometry else { return XCTFail() }
        XCTAssertTrue(w.sweeps.isEmpty); XCTAssertEqual(o.depth, 0); XCTAssertNil(o.typeName)
        XCTAssertFalse(s.isSloped); XCTAssertNil(c.uLines); XCTAssertTrue(c.panels.isEmpty)
    }

    func testNewFieldsRoundTrip() throws {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(3000, 0), sweeps: [WallSweep(profile: "cornice", depth: 80, height: 200, elevation: 2800)])))
        _ = doc.addElement(.opening(OpeningGeom(kind: .opening, hostWall: w, offset: 1500, width: 600, height: 600, sill: 900, depth: 80, typeName: "N1", mark: "N01")))
        _ = doc.addElement(.slab(SlabGeom(boundary: [.zero, Vec2(1, 0), Vec2(1, 1)], slope: 5, slopeDirection: 1, slopeOrigin: Vec2(1, 1))))
        _ = doc.addElement(.curtainWall(CurtainWallGeom(start: .zero, end: Vec2(5000, 0), uLines: [1000], vLines: [2000], panels: ["0,0": "solid"])))
        doc.phases.append("Phase 3"); doc.keynotes["05.10"] = "Brick cladding"
        doc.openingTypes.append(OpeningType(name: "Custom", kind: .window, width: 700, height: 900, params: ["UValue": "0.9"]))
        let back = try ArchiFile.decode(try ArchiFile.encode(doc))
        XCTAssertEqual(back.elements, doc.elements)
        XCTAssertEqual(back.phases, doc.phases)
        XCTAssertEqual(back.keynotes, doc.keynotes)
        XCTAssertEqual(back.openingTypes, doc.openingTypes)
    }

    func testPhaseStatus() {
        var doc = ArchiDocument()
        doc.phases = ["Existing", "Demolition", "New"]
        doc.setVariable("PHASE", "New")
        XCTAssertEqual(Phasing.status(["phaseCreated": "Existing"], doc: doc), .existing)
        XCTAssertEqual(Phasing.status(["phaseCreated": "Existing", "phaseDemolished": "New"], doc: doc), .demolished)
        XCTAssertEqual(Phasing.status(["phaseCreated": "Existing", "phaseDemolished": "Demolition"], doc: doc), .gone)
        XCTAssertEqual(Phasing.status([:], doc: doc), .new)
        doc.setVariable("PHASE", "Existing")
        XCTAssertEqual(Phasing.status(["phaseCreated": "New"], doc: doc), .future)
        XCTAssertFalse(Phasing.visible(.future, .all))
        XCTAssertFalse(Phasing.visible(.demolished, .complete))
        XCTAssertFalse(Phasing.visible(.existing, .new))
    }
}
