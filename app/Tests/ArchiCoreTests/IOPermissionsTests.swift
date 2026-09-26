// Oanarina Archi Tool — GPL-3.0-or-later
// Permissions and signatures (COL-022): a signed, pinned access policy enforced when users synchronise with central.
import XCTest
@testable import ArchiCore

final class IOPermissionsTests: XCTestCase {
    func dir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-perm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    func text(_ doc: ArchiDocument, _ id: EntityID) -> String? {
        if case .text(let t) = doc.entity(id)?.geometry { return t.content }; return nil
    }
    func setText(_ doc: inout ArchiDocument, _ id: EntityID, _ s: String) {
        guard let i = doc.entities.firstIndex(where: { $0.id == id }), case .text(var t) = doc.entities[i].geometry else { return }
        t.content = s; doc.entities[i].geometry = .text(t)
    }

    func testPolicyRolesProtectedLayersAndNoDataLoss() throws {
        let d = try dir()
        let central = d.appendingPathComponent("Central.archi")
        var start = ArchiDocument()
        start.layers.append(Layer(name: "S-STRUCT", color: RGBA(1, 0, 0)))
        let note = start.add(Entity(layer: "0", geometry: .text(TextGeom(position: .zero, height: 250, content: "Note"))))
        let beam = start.add(Entity(layer: "S-STRUCT", geometry: .text(TextGeom(position: Vec2(0, 1000), height: 250, content: "Beam 200"))))
        try CentralModel.createCentral(start, at: central)

        // No policy yet: everyone edits.
        XCTAssertEqual(Permissions.load(central: central, pinnedKey: nil), .none)

        let owner = FileSignature.newKey(signer: "Ana")
        let policy = AccessPolicy(defaultRole: .editor, users: ["Cy": .viewer, "ana": .admin], layers: ["s-struct": ["Ana"]])
        try Permissions.publish(policy, central: central, key: owner)
        let pinned = try ArchiFile.decode(Data(contentsOf: central)).variable(Permissions.keyVariable)
        XCTAssertEqual(pinned, owner.publicKey)
        guard case .valid(let p, let signer) = Permissions.load(central: central, pinnedKey: pinned) else { return XCTFail("policy should verify") }
        XCTAssertEqual(signer, "Ana"); XCTAssertEqual(p.role(of: "cy"), .viewer); XCTAssertEqual(p.role(of: "Bo"), .editor)
        XCTAssertFalse(p.canEdit("Bo", layer: "S-STRUCT")); XCTAssertTrue(p.canEdit("Bo", layer: "0")); XCTAssertTrue(p.canEdit("ANA", layer: "s-struct"))

        // Another key cannot change the policy once it is pinned.
        XCTAssertThrowsError(try Permissions.publish(AccessPolicy(defaultRole: .admin), central: central, key: FileSignature.newKey(signer: "Mallory")))

        // Bo (editor) edits the note (allowed), the beam (protected layer) and adds an object on the protected layer.
        let lb = d.appendingPathComponent("Bo.archi")
        var b = try CentralModel.createLocal(central: central, local: lb, user: "Bo")
        setText(&b, note, "Note by Bo")
        setText(&b, beam, "Beam 400")
        let added = b.add(Entity(layer: "S-STRUCT", geometry: .line(LineGeom(.zero, Vec2(100, 0)))))
        b.setVariable(Permissions.keyVariable, "tampered")
        let r = try CentralModel.sync(local: b, localURL: lb, user: "Bo")
        XCTAssertEqual(Set(r.denied.map(\.id)), [beam, added])
        XCTAssertTrue(r.denied.allSatisfy { $0.reason.contains("S-STRUCT") })
        var c = try ArchiFile.decode(Data(contentsOf: central))
        XCTAssertEqual(text(c, note), "Note by Bo")
        XCTAssertEqual(text(c, beam), "Beam 200")
        XCTAssertNil(c.entity(added))
        XCTAssertEqual(c.variable(Permissions.keyVariable), owner.publicKey, "a local copy cannot re-pin the policy key")
        // The refused work is kept beside the local copy.
        let kept = try XCTUnwrap(r.rejectedFile)
        let keptDoc = try ArchiFile.decode(Data(contentsOf: kept))
        XCTAssertEqual(Set(keptDoc.entities.map(\.id)), [beam, added])
        XCTAssertEqual(text(keptDoc, beam), "Beam 400")

        // Ana (admin, listed on the layer) changes the beam; Cy (viewer) changes nothing.
        let la = d.appendingPathComponent("Ana.archi"), lc = d.appendingPathComponent("Cy.archi")
        var a = try CentralModel.createLocal(central: central, local: la, user: "Ana")
        setText(&a, beam, "Beam 300")
        XCTAssertTrue(try CentralModel.sync(local: a, localURL: la, user: "Ana").denied.isEmpty)
        var cy = try CentralModel.createLocal(central: central, local: lc, user: "Cy")
        setText(&cy, note, "Viewer edit")
        cy.layers.append(Layer(name: "CY-LAYER", color: RGBA(0, 1, 0)))
        let rc = try CentralModel.sync(local: cy, localURL: lc, user: "Cy")
        XCTAssertEqual(rc.denied.map(\.id), [note])
        c = try ArchiFile.decode(Data(contentsOf: central))
        XCTAssertEqual(text(c, beam), "Beam 300")
        XCTAssertEqual(text(c, note), "Note by Bo")
        XCTAssertNil(c.layer(named: "CY-LAYER"), "viewers do not change the layer table")
        XCTAssertEqual(text(rc.doc, note), "Note by Bo", "the viewer's local model is refreshed from central")

        // A hand-edited policy (Bo makes himself admin) no longer verifies: the model locks read-only.
        let url = Permissions.policyURL(central)
        var raw = try String(contentsOf: url, encoding: .utf8)
        raw = raw.replacingOccurrences(of: "\"Cy\" : \"viewer\"", with: "\"Cy\" : \"viewer\", \"Bo\" : \"admin\"")
        try raw.write(to: url, atomically: true, encoding: .utf8)
        guard case .invalid = Permissions.load(central: central, pinnedKey: owner.publicKey) else { return XCTFail("tampered policy must not verify") }
        var b2 = rc.doc; b2.setVariable("USERNAME", "Bo")
        b2 = try CentralModel.createLocal(central: central, local: lb, user: "Bo")
        setText(&b2, note, "Bo again")
        let r2 = try CentralModel.sync(local: b2, localURL: lb, user: "Bo")
        XCTAssertEqual(r2.denied.map(\.id), [note])
        XCTAssertTrue(r2.denied.first?.reason.contains("locked") ?? false)
        // The owner republishes and the lock is lifted.
        try Permissions.publish(policy, central: central, key: owner)
        guard case .valid = Permissions.load(central: central, pinnedKey: owner.publicKey) else { return XCTFail("republished policy verifies") }
    }

    func testPolicyDecodesOlderFilesAndEnforceIsPure() throws {
        let p = try JSONDecoder().decode(AccessPolicy.self, from: Data("{}".utf8))
        XCTAssertEqual(p.defaultRole, .editor)
        XCTAssertTrue(p.users.isEmpty && p.layers.isEmpty)
        var base = ArchiDocument()
        base.layers.append(Layer(name: "LOCKED", color: RGBA(1, 1, 1)))
        let e = base.add(Entity(layer: "LOCKED", geometry: .point(.zero)))
        var mine = base
        mine.remove(ids: [e])
        mine.layers.removeAll { $0.name == "LOCKED" }
        let r = Permissions.enforce(local: mine, base: base, user: "x", policy: AccessPolicy(layers: ["LOCKED": []]))
        XCTAssertEqual(r.rejected.map(\.id), [e], "deleting a protected object is refused")
        XCTAssertNotNil(r.doc.entity(e))
        XCTAssertNotNil(r.doc.layer(named: "LOCKED"), "protected layer definitions are restored")
        XCTAssertTrue(Permissions.enforce(local: mine, base: base, user: "x", policy: AccessPolicy(users: ["x": .admin], layers: ["LOCKED": []])).rejected.isEmpty)
    }
}
