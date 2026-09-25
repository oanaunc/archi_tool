// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class IOCollaborationTests: XCTestCase {
    func tmpDir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-collab-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testVersionHistorySaveRestoreDiff() throws {
        let dir = try tmpDir()
        let url = dir.appendingPathComponent("House.archi")
        var d = ArchiDocument()
        let a = d.add(.line(LineGeom(.zero, Vec2(1000, 0))))
        try ArchiFile.encode(d).write(to: url)
        let v1 = try XCTUnwrap(DocumentVersions.save(d, documentURL: url, message: "first", author: "OR"))
        XCTAssertEqual(v1.number, 1)
        XCTAssertNil(try DocumentVersions.save(d, documentURL: url, message: "same"), "identical snapshot is skipped")
        let b = d.add(.circle(CircleGeom(Vec2(5, 5), 50)))
        if let i = d.entityIndex(a) { d.entities[i].layer = "A-WALL" }
        let v2 = try XCTUnwrap(DocumentVersions.save(d, documentURL: url, message: "second"))
        XCTAssertEqual(v2.number, 2)
        XCTAssertEqual(DocumentVersions.list(for: url).map(\.message), ["first", "second"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: DocumentVersions.folder(for: url).appendingPathComponent("v0002.archi").path))
        let diff = try DocumentVersions.diff(from: 1, to: 2, documentURL: url)
        XCTAssertEqual(diff.count(.added), 1); XCTAssertEqual(diff.count(.modified), 1)
        XCTAssertEqual(diff.differences.first { $0.kind == .added }?.id, b)
        XCTAssertEqual(diff.differences.first { $0.kind == .modified }?.fields, ["layer"])
        let old = try DocumentVersions.load(1, documentURL: url)
        XCTAssertEqual(old.entities.count, 1)
        try DocumentVersions.delete(1, documentURL: url)
        XCTAssertEqual(DocumentVersions.list(for: url).map(\.number), [2])
    }

    @MainActor func testVersionsCommandRestoreIsUndoable() async throws {
        let dir = try tmpDir()
        let url = dir.appendingPathComponent("Plan.archi")
        let ed = Editor()
        ed.fileURL = url
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("VERSIONS Save \"one line\"")
        await ed.run("CIRCLE 0,0 300")
        XCTAssertEqual(ed.doc.entities.count, 2)
        await ed.run("VERSIONS Restore 1")
        XCTAssertEqual(ed.doc.entities.count, 1)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 2)
        let out = await ed.run("VERSIONS Diff 1 0")
        XCTAssertTrue(out.joined(separator: "\n").contains("1 added"), out.joined(separator: "\n"))
    }

    func testBackupAndRecoverDamagedFile() throws {
        let dir = try tmpDir()
        let url = dir.appendingPathComponent("A.archi")
        var d = ArchiDocument()
        for i in 0..<40 { d.add(.line(LineGeom(Vec2(Double(i) * 10, 0), Vec2(Double(i) * 10, 100)))) }
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 200, height: 3000)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 900, height: 2100)))
        try ArchiFile.save(d, to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ArchiFile.backupURL(for: url).path))
        d.add(.point(Vec2(1, 1)))
        try ArchiFile.save(d, to: url)
        let bak = try ArchiFile.decode(Data(contentsOf: ArchiFile.backupURL(for: url)))
        XCTAssertEqual(bak.entities.count, 40)

        // Clean file: nothing to repair.
        let (ok, rep0) = try ArchiFile.recover(Data(contentsOf: url))
        XCTAssertTrue(rep0.isClean); XCTAssertEqual(ok, try ArchiFile.decode(Data(contentsOf: url)))

        // Truncated in the middle of the entity list (forced quit while writing).
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let cut = text.range(of: "\"entities\"")!.upperBound
        let partial = Data(text[..<text.index(cut, offsetBy: 2500)].utf8)
        XCTAssertThrowsError(try ArchiFile.decode(partial))
        let (rec, rep) = try ArchiFile.recover(partial)
        XCTAssertTrue(rep.truncatedRepaired)
        XCTAssertGreaterThan(rec.entities.count, 3)
        XCTAssertLessThan(rec.entities.count, 41)
        XCTAssertNotNil(rec.layer(named: "0"))

        // A damaged object and a damaged setting are dropped; the rest survives; orphan openings are removed.
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var doc = obj["document"] as! [String: Any]
        var ents = doc["entities"] as! [Any]
        ents[3] = ["id": "not a number", "geometry": 42]
        doc["entities"] = ents
        doc["units"] = ["bad": true]
        var els = doc["elements"] as! [[String: Any]]
        els.removeAll { ($0["geometry"] as? [String: Any])?["type"] as? String == "wall" }
        doc["elements"] = els
        obj["document"] = doc
        let broken = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try ArchiFile.decode(broken))
        let (fixed, rep2) = try ArchiFile.recover(broken)
        XCTAssertEqual(rep2.droppedEntities, 1)
        XCTAssertEqual(fixed.entities.count, 40)
        XCTAssertTrue(rep2.droppedKeys.contains("units"))
        XCTAssertEqual(fixed.units, .millimeters)
        XCTAssertTrue(fixed.elements.isEmpty, "door without wall removed")
        XCTAssertThrowsError(try ArchiFile.recover(Data("garbage".utf8)))
    }

    func testJournalReplaysAfterForcedQuit() throws {
        let dir = try tmpDir()
        let url = dir.appendingPathComponent("j.archijournal")
        var d = ArchiDocument()
        let a = d.add(.line(LineGeom(.zero, Vec2(100, 0))))
        let j = try DocumentJournal(url: url, base: d)
        XCTAssertFalse(try j.record(d))
        let b = d.add(.circle(CircleGeom(.zero, 10)))
        _ = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(3000, 0))))
        XCTAssertTrue(try j.record(d, label: "CIRCLE"))
        if let i = d.entityIndex(a) { d.entities[i].geometry = .line(LineGeom(.zero, Vec2(500, 0))) }
        d.remove(ids: [b])
        d.setVariable("MYVAR", "1")
        d.layers.append(Layer(name: "NEW"))
        d.entities.reverse()
        try j.record(d)
        let r = try DocumentJournal.recover(url)
        XCTAssertEqual(r.applied, 2); XCTAssertFalse(r.damagedTail)
        XCTAssertEqual(r.doc, d)
        // A half-written last line (forced quit) is skipped; earlier changes survive.
        d.add(.point(Vec2(9, 9)))
        try j.record(d)
        var raw = try Data(contentsOf: url)
        raw.removeLast(40)
        try raw.write(to: url)
        let r2 = try DocumentJournal.recover(url)
        XCTAssertTrue(r2.damagedTail); XCTAssertEqual(r2.applied, 2)
        XCTAssertEqual(r2.doc.entities.count, 1)
        XCTAssertEqual(r2.doc.variable("MYVAR"), "1")
        try j.compact()
        XCTAssertEqual(try DocumentJournal.recover(url).applied, 0)
        let files = RecoveryFiles.list(folders: [dir])
        XCTAssertEqual(files.map(\.kind), ["journal"])
        XCTAssertEqual(try RecoveryFiles.open(files[0]).0.entities.count, d.entities.count)
    }

    @MainActor func testAutosaveJournalTicks() throws {
        let dir = try tmpDir()
        let ed = Editor()
        let s = try AutosaveJournal(editor: ed, url: dir.appendingPathComponent("e.archijournal"), interval: 3600)
        XCTAssertFalse(s.tick())
        ed.doc.add(.line(LineGeom(.zero, Vec2(1, 1))))
        XCTAssertTrue(s.tick())
        XCTAssertEqual(try DocumentJournal.recover(s.journal.url).doc.entities.count, 1)
        s.stop(keep: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.journal.url.path))
    }

    func testThreeWayMerge() {
        var base = ArchiDocument()
        let l1 = base.add(.line(LineGeom(.zero, Vec2(100, 0))))
        let l2 = base.add(.line(LineGeom(.zero, Vec2(0, 100))))
        let l3 = base.add(.line(LineGeom(.zero, Vec2(100, 100))))
        let w = base.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        var ours = base, theirs = base
        // Ours: modify l1, delete l2, add a circle (id collides with theirs' addition), rename a layer colour.
        ours.entities[ours.entityIndex(l1)!].layer = "A-WALL"
        ours.remove(ids: [l2])
        let oc = ours.add(.circle(CircleGeom(.zero, 5)))
        ours.info.name = "Ours"
        // Theirs: modify l3, add a door in the wall and a text (same new id as our circle), change a variable, conflict on l1.
        theirs.entities[theirs.entityIndex(l3)!].color = .aci(1)
        let tt = theirs.add(.text(TextGeom(position: .zero, height: 5, content: "T")))
        XCTAssertEqual(tt, oc, "both branches allocate the same next id")
        let door = theirs.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 900, height: 2100)))
        theirs.setVariable("LTSCALE", "2")
        theirs.entities[theirs.entityIndex(l1)!].color = .aci(3)
        let r = ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs)
        let m = r.doc
        XCTAssertEqual(m.info.name, "Ours")
        XCTAssertNil(m.entity(l2), "our deletion stays")
        XCTAssertEqual(m.entity(l3)?.color, .aci(1), "their change is taken")
        XCTAssertEqual(m.entity(l1)?.layer, "A-WALL", "conflict keeps ours")
        XCTAssertEqual(r.conflicts.map(\.key), ["#\(l1)"])
        XCTAssertNotNil(m.entity(oc).flatMap { if case .circle = $0.geometry { return $0 }; return nil })
        let renum = try? XCTUnwrap(r.renumbered[tt])
        XCTAssertNotNil(renum)
        if let n = renum { if case .text(let t) = m.entity(n)?.geometry { XCTAssertEqual(t.content, "T") } else { XCTFail("their text missing") } }
        // Door ids did not collide (ours added an entity, theirs an element with the next id after the text).
        let doors = m.elements.filter { if case .opening = $0.geometry { return true }; return false }
        XCTAssertEqual(doors.count, 1); _ = door
        XCTAssertEqual(m.variable("LTSCALE"), "2")
        XCTAssertEqual(Set(m.entities.map(\.id) + m.elements.map(\.id)).count, m.entities.count + m.elements.count)
        XCTAssertGreaterThan(m.nextID, (m.entities.map(\.id) + m.elements.map(\.id)).max()!)
        // Theirs deleting what ours modified is a conflict too.
        var t2 = base; t2.remove(ids: [l1])
        let r2 = ThreeWayMerge.merge(base: base, ours: ours, theirs: t2)
        XCTAssertTrue(r2.conflicts.contains { $0.key == "#\(l1)" && $0.reason.contains("removed") })
        XCTAssertNotNil(r2.doc.entity(l1))
    }

    func testStandardsPackageExportImportCheck() throws {
        var office = ArchiDocument()
        office.layers.append(Layer(name: "A-FURN", color: RGBA(0.2, 0.9, 0.2), lineweight: 0.18))
        office.dimStyles[0].textHeight = 3.5
        office.setVariable("HPPAT:OFFICEHATCH", "45,0,0,0,4")
        let pkg = StandardsPackage(name: "Office", from: office)
        let back = try StandardsPackage.decode(pkg.encoded())
        XCTAssertEqual(back, pkg)
        var project = ArchiDocument()
        project.layers.append(Layer(name: "A-XTRA"))
        XCTAssertTrue(back.deviations(in: project).contains { $0.contains("Dimension style Standard") })
        XCTAssertTrue(back.deviations(in: project).contains { $0.contains("A-XTRA") })
        let r1 = back.apply(to: &project, overwrite: false)
        XCTAssertGreaterThanOrEqual(r1.added, 2)
        XCTAssertNotNil(project.layer(named: "A-FURN"))
        XCTAssertEqual(project.dimStyles[0].textHeight, 2.5, "not overwritten")
        XCTAssertEqual(project.variable("HPPAT:OFFICEHATCH"), "45,0,0,0,4")
        let r2 = back.apply(to: &project, overwrite: true)
        XCTAssertGreaterThanOrEqual(r2.updated, 1)
        XCTAssertEqual(project.dimStyles[0].textHeight, 3.5)
        XCTAssertFalse(back.deviations(in: project).contains { $0.contains("Dimension style") })
        // Old / partial packages decode with defaults.
        let partial = try StandardsPackage.decode(Data(#"{"name":"Mini","layers":[]}"#.utf8))
        XCTAssertTrue(partial.materials.isEmpty)
    }

    func testCompressedPackageRoundTrip() throws {
        let dir = try tmpDir()
        let img = dir.appendingPathComponent("site.png")
        try IOInteropTests.png.write(to: img)
        var d = ArchiDocument()
        d.add(.image(ImageGeom(path: img.path, origin: .zero, size: Vec2(100, 100))))
        if let i = d.materials.firstIndex(where: { $0.name == "Brick" }) { d.materials[i].texture = "site.png" }
        let src = dir.appendingPathComponent("Proj.archi")
        try ArchiFile.encode(d).write(to: src)
        let pkg = dir.appendingPathComponent("Proj.archiz")
        let rep = try ArchiPackage.write(d, to: pkg, documentURL: src)
        XCTAssertEqual(rep.files.count, 1, "one file shared by the image and the texture")
        try FileManager.default.removeItem(at: img)
        let out = dir.appendingPathComponent("unpacked")
        let back = try ArchiPackage.read(pkg, into: out)
        guard case .image(let im) = back.entities.first?.geometry else { return XCTFail() }
        XCTAssertTrue(im.path.hasPrefix(out.path)); XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: im.path)), IOInteropTests.png)
        XCTAssertEqual(back.material("Brick")?.texture, im.path)
        // DocumentIO knows the format.
        let pkg2 = dir.appendingPathComponent("Copy.archiz")
        try DocumentIO.write(back, to: pkg2)
        XCTAssertEqual(try DocumentIO.read(pkg2).entities.count, 1)
    }

    @MainActor func testPluginRegistryCommandsAndManager() async throws {
        let dir = try tmpDir()
        let p = dir.appendingPathComponent("stairs-helper", isDirectory: true)
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        try #"{"id":"test.helper","name":"Helper","version":"2.0","commands":[{"name":"MAKEBOX","aliases":["MKBOX"],"summary":"Adds a box.","function":"makeBox"},{"name":"LINE","function":"x"}]}"#
            .write(to: p.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "function makeBox() { archi.run('RECTANG 0,0 10,10 '); }".write(to: p.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        let bad = dir.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try "{ not json".write(to: bad.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let reg = CommandRegistry()
        BuiltinCommands.registerAll(reg)
        let plugins = PluginRegistry(folders: [dir])
        plugins.reload()
        XCTAssertEqual(plugins.plugins.map(\.id), ["test.helper"])
        XCTAssertTrue(plugins.problems.contains { $0.hasPrefix("broken") })
        let names = plugins.register(into: reg)
        XCTAssertEqual(names, ["MAKEBOX"], "a plugin cannot replace a built-in command")
        XCTAssertTrue(plugins.problems.contains { $0.contains("LINE") })
        XCTAssertEqual(reg.lookup("MKBOX")?.name, "MAKEBOX")

        // The host evaluator runs the plugin function; edits are one undo step.
        var calls: [String] = []
        let saved = PluginRegistry.evaluator
        defer { PluginRegistry.evaluator = saved }
        PluginRegistry.evaluator = { plugin, fn, ed in
            calls.append("\(plugin.id).\(fn)")
            XCTAssertTrue(plugin.source.contains("makeBox"))
            ed.doc.add(.circle(CircleGeom(.zero, 1)))
            ed.doc.add(.circle(CircleGeom(.zero, 2)))
        }
        let ed = Editor(registry: reg)
        await ed.run("MKBOX")
        XCTAssertEqual(calls, ["test.helper.makeBox"])
        XCTAssertEqual(ed.doc.entities.count, 2)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 0)
        // Disabled: the command refuses to run and the state persists.
        try plugins.setEnabled("Helper", false)
        await ed.run("MAKEBOX")
        XCTAssertEqual(ed.doc.entities.count, 0)
        let again = PluginRegistry(folders: [dir])
        again.reload()
        XCTAssertEqual(again.plugins.first?.enabled, false)
        try again.setEnabled("test.helper", true)
        XCTAssertTrue(PluginRegistry(folders: [dir]).reload().first!.enabled)
        XCTAssertThrowsError(try PluginRegistry.parseManifest(Data(#"{"id":"x","name":"X","commands":[{"name":"BAD NAME","function":"f"}]}"#.utf8)))
    }

    @MainActor func testScriptToJavaScriptAndScaffold() throws {
        let reg = CommandRegistry()
        BuiltinCommands.registerAll(reg)
        let lines = ["; recorded", "LINE", "0,0", "100,0", "", "CIRCLE", "50,50", "25", "TEXT", "0,0", "2.5", "0", "Hello \"world\""]
        let cmds = ScriptConverter.commands(fromScriptLines: lines, registry: reg)
        XCTAssertEqual(cmds, ["LINE 0,0 100,0 ", "CIRCLE 50,50 25 ", "TEXT 0,0 2.5 0 Hello \"world\" "])
        let js = ScriptConverter.javaScript(fromScriptLines: lines, registry: reg)
        XCTAssertTrue(js.contains("archi.run(\"CIRCLE 50,50 25 \");"))
        XCTAssertTrue(js.contains("Hello \\\"world\\\""))
        let dir = try tmpDir()
        let pdir = try PluginRegistry.scaffold(in: dir, name: "My Tools", command: "DRAWTHING", script: ["LINE", "0,0", "1,1", ""], registry: reg)
        let m = try PluginRegistry.parseManifest(Data(contentsOf: pdir.appendingPathComponent("plugin.json")))
        XCTAssertEqual(m.commands.first?.name, "DRAWTHING")
        let main = try String(contentsOf: pdir.appendingPathComponent("main.js"), encoding: .utf8)
        XCTAssertTrue(main.contains("function runDrawthing()")); XCTAssertTrue(main.contains("archi.run(\"LINE 0,0 1,1 \");"))
    }
}
