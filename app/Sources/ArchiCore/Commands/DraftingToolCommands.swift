// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Drafting tools: UCS, centre marks/lines, double lines, 2D solids, stars, bounding boxes, clipboard,
/// OOPS, OVERKILL, SETBYLAYER, user aliases and script recording.
enum DraftingToolCommands {
    static var all: [CommandDef] { precision + draw + clipboard + modify + commandLine }

    // MARK: - UCS
    static var precision: [CommandDef] { [
        CommandDef("UCS", category: "Settings", summary: "Sets the user coordinate system: World, Origin, Z rotation, 3point, Object, Previous, Named save/restore.") { ed in
            let cur = UCSFrame.current(ed.doc)
            let a = try await ed.getPoint("Specify origin of UCS", keywords: ["World", "Origin", "Z", "3point", "Object", "View", "Previous", "Named"])
            switch a {
            case .point(let o):
                let x = try await ed.getPoint("Specify point on X-axis or <accept>", base: o) { c in [.line(LineGeom(o, c))] }
                var f = UCSFrame(origin: o, angle: cur.angle)
                if let p = x.point, p.distance(to: o) > 1e-9 { f.angle = (p - o).angle }
                f.apply(to: &ed.doc)
            case .keyword("World"), .none: UCSFrame.world.apply(to: &ed.doc)
            case .keyword("View"):
                // XY parallel to the screen (plan views are not twisted): X axis horizontal, origin kept.
                UCSFrame(origin: cur.origin, angle: 0).apply(to: &ed.doc)
            case .keyword("Origin"):
                let o = try await ed.requirePoint("Specify new origin point")
                UCSFrame(origin: o, angle: cur.angle).apply(to: &ed.doc)
            case .keyword("Z"):
                guard let r = try await ed.getAngle("Specify rotation angle about Z axis", defaultValue: rad(90)).value else { return }
                UCSFrame(origin: cur.origin, angle: cur.angle + r).apply(to: &ed.doc)
            case .keyword("3point"):
                let o = try await ed.requirePoint("Specify new origin point")
                let p = try await ed.requirePoint("Specify point on positive portion of X-axis", base: o)
                guard p.distance(to: o) > 1e-9 else { throw CommandError.invalid("Points coincide.") }
                UCSFrame(origin: o, angle: (p - o).angle).apply(to: &ed.doc)
            case .keyword("Object"):
                guard case .pick(let pk) = try await ed.pickObject("Select object to align UCS", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
                guard let f = ucsFromObject(e.geometry, pick: pk.point) else { throw CommandError.invalid("Cannot align the UCS to that object.") }
                f.apply(to: &ed.doc)
            case .keyword("Previous"):
                var prev = (ed.doc.variable("UCSPREV") ?? "").split(separator: ";").map(String.init)
                guard let last = prev.popLast(), let f = UCSFrame(text: last) else { throw CommandError.invalid("No previous UCS.") }
                f.apply(to: &ed.doc, remember: false)
                ed.doc.setVariable("UCSPREV", prev.joined(separator: ";"))
            case .keyword("Named"):
                let k = try await ed.getKeyword("Enter an option", ["Restore", "Save", "Delete", "?"], defaultValue: "?") ?? "?"
                switch k {
                case "Save":
                    guard let n = try await ed.getWord("Enter name to save current UCS"), UserAliases.isValidName(n.uppercased()) else { throw CommandError.invalid("Invalid name.") }
                    ed.doc.setVariable("UCS:" + n, cur.text)
                case "Restore":
                    guard let n = try await ed.getWord("Enter name of UCS to restore"), let f = ed.doc.variable("UCS:" + n).flatMap(UCSFrame.init(text:)) else { throw CommandError.invalid("UCS not found.") }
                    f.apply(to: &ed.doc)
                case "Delete":
                    guard let n = try await ed.getWord("Enter UCS name to delete") else { return }
                    ed.doc.variables.removeValue(forKey: "UCS:" + n.uppercased())
                default: listUCS(ed)
                }
                return
            default: return
            }
            let f = UCSFrame.current(ed.doc)
            ed.print(f.isWorld ? "UCS: World" : "UCS origin \(fmt(f.origin.x)),\(fmt(f.origin.y)), X axis \(fmt(deg(f.angle)))°")
        },
        CommandDef("UCSMAN", aliases: ["UC", "DDUCS"], category: "Settings", summary: "Named UCS manager: lists the saved user coordinate systems and restores, saves, renames or deletes them (World and Previous too).") { ed in
            listUCS(ed)
            while true {
                guard let r = try await ed.getWord("Enter UCS name to make current or [Save/Rename/Delete/World/Previous/?]", keywords: ["Save", "Rename", "Delete", "World", "Previous", "?"]) else { return }
                let cur = UCSFrame.current(ed.doc)
                switch r {
                case "World": UCSFrame.world.apply(to: &ed.doc); ed.print("UCS: World"); return
                case "Previous":
                    var prev = (ed.doc.variable("UCSPREV") ?? "").split(separator: ";").map(String.init)
                    guard let last = prev.popLast(), let f = UCSFrame(text: last) else { throw CommandError.invalid("No previous UCS.") }
                    f.apply(to: &ed.doc, remember: false)
                    ed.doc.setVariable("UCSPREV", prev.joined(separator: ";")); return
                case "?": listUCS(ed)
                case "Save":
                    guard let n = try await ed.getWord("Enter name to save current UCS"), UserAliases.isValidName(n.uppercased()) else { throw CommandError.invalid("Invalid name.") }
                    ed.doc.setVariable("UCS:" + n, cur.text); ed.print("UCS \(n.uppercased()) saved.")
                case "Rename":
                    guard let o = try await ed.getWord("Enter UCS name to rename"), let v = ed.doc.variable("UCS:" + o) else { throw CommandError.invalid("UCS not found.") }
                    guard let n = try await ed.getWord("Enter new name"), UserAliases.isValidName(n.uppercased()) else { throw CommandError.invalid("Invalid name.") }
                    guard ed.doc.variable("UCS:" + n) == nil else { throw CommandError.invalid("UCS \(n.uppercased()) already exists.") }
                    ed.doc.variables.removeValue(forKey: "UCS:" + o.uppercased()); ed.doc.setVariable("UCS:" + n, v)
                case "Delete":
                    guard let n = try await ed.getWord("Enter UCS name to delete"), ed.doc.variables.removeValue(forKey: "UCS:" + n.uppercased()) != nil else { throw CommandError.invalid("UCS not found.") }
                    ed.print("UCS \(n.uppercased()) deleted.")
                default:
                    let n = r
                    if n.lowercased() == "world" { UCSFrame.world.apply(to: &ed.doc); return }
                    guard let f = ed.doc.variable("UCS:" + n).flatMap(UCSFrame.init(text:)) else { throw CommandError.invalid("UCS \(n) not found.") }
                    f.apply(to: &ed.doc); return
                }
            }
        },
    ] }

    @MainActor static func listUCS(_ ed: Editor) {
        let names = ed.doc.variables.keys.filter { $0.hasPrefix("UCS:") }.sorted()
        let cur = UCSFrame.current(ed.doc)
        ed.print("Current UCS: " + (cur.isWorld ? "World" : cur.text))
        if names.isEmpty { ed.print("No named UCS.") }
        for n in names { ed.print("  \(n.dropFirst(4)): \(ed.doc.variables[n] ?? "")") }
    }

    static func ucsFromObject(_ g: Geometry, pick: Vec2) -> UCSFrame? {
        switch g {
        case .line(let l):
            let (o, p) = pick.distance(to: l.a) <= pick.distance(to: l.b) ? (l.a, l.b) : (l.b, l.a)
            return UCSFrame(origin: o, angle: (p - o).angle)
        case .circle(let c): return UCSFrame(origin: c.center, angle: (pick - c.center).angle)
        case .arc(let a): return UCSFrame(origin: a.center, angle: a.start)
        case .text(let t): return UCSFrame(origin: t.position, angle: t.rotation)
        case .insert(let i): return UCSFrame(origin: i.position, angle: i.rotation)
        case .polyline(let p) where p.vertices.count >= 2:
            return UCSFrame(origin: p.vertices[0].p, angle: (p.vertices[1].p - p.vertices[0].p).angle)
        default: return nil
        }
    }

    // MARK: - Draw
    @MainActor static func centerExtension(_ ed: Editor, size: Double) -> Double {
        if let v = ed.doc.variable("CENTEREXE").flatMap(Double.init), v >= 0 { return v }
        return size * 0.1
    }

    static var draw: [CommandDef] { [
        CommandDef("CENTERMARK", aliases: ["CM", "DIMCENTER", "DCE"], category: "Draw", summary: "Adds associative centre marks to circles and arcs.") { ed in
            let ids = try await ed.getEntitySelection("Select circles or arcs")
            var n = 0
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                let (c, r): (Vec2, Double)
                switch e.geometry { case .circle(let g): (c, r) = (g.center, g.radius); case .arc(let g): (c, r) = (g.center, g.radius); default: continue }
                let ext = centerExtension(ed, size: r)
                for (k, l) in DraftGeometry.centerMark(center: c, radius: r, extension: ext).enumerated() {
                    let nid = ed.addEntity(.line(l))
                    if let i = ed.doc.entityIndex(nid) {
                        ed.doc.entities[i].linetype = ed.doc.linetype("Center") != nil ? ed.doc.linetype("Center")!.name : nil
                        ed.doc.entities[i].props["centermarkOf"] = "\(id)"
                        ed.doc.entities[i].props["centermarkAxis"] = k == 0 ? "h" : "v"
                        ed.doc.entities[i].props["centerExt"] = fmt(ext, 8)
                    }
                }
                n += 1
            }
            ed.selection = []
            ed.print("\(n) centre mark(s) created.")
        },
        CommandDef("CENTERLINE", aliases: ["CL"], category: "Draw", summary: "Creates an associative centre line between two lines.") { ed in
            guard case .pick(let a) = try await ed.pickObject("Select first line", filter: { if case .line? = ed.doc.entity($0)?.geometry { return true }; return false }),
                  case .pick(let b) = try await ed.pickObject("Select second line", filter: { if case .line? = ed.doc.entity($0)?.geometry { return true }; return false }),
                  case .line(let la)? = ed.doc.entity(a.id)?.geometry, case .line(let lb)? = ed.doc.entity(b.id)?.geometry else { return }
            let ext = centerExtension(ed, size: la.a.distance(to: la.b) * 0.5)
            guard let cl = DraftGeometry.centerLine(la, lb, extension: ext) else { throw CommandError.invalid("Cannot build a centre line for those lines.") }
            let nid = ed.addEntity(.line(cl))
            if let i = ed.doc.entityIndex(nid) {
                ed.doc.entities[i].linetype = ed.doc.linetype("Center")?.name
                ed.doc.entities[i].props["centerlineOf"] = "\(a.id),\(b.id)"
                ed.doc.entities[i].props["centerExt"] = fmt(ext, 8)
            }
        },
        CommandDef("DLINE", aliases: ["DL", "DOUBLELINE"], category: "Draw", summary: "Draws double lines (two parallel polylines with end caps).") { ed in
            var width = ed.variableDouble("DLINEWID", 100)
            var just = 0.0
            var pts: [Vec2] = []
            while pts.isEmpty {
                let a = try await ed.getPoint("Specify start point", keywords: ["Width", "Justification"])
                switch a {
                case .point(let p): pts.append(p)
                case .keyword("Width"): width = try await ed.getPositive("Specify double line width", defaultValue: width)
                case .keyword("Justification"):
                    let k = try await ed.getKeyword("Enter justification", ["Top", "Zero", "Bottom"], defaultValue: "Zero") ?? "Zero"
                    just = k == "Top" ? -1 : (k == "Bottom" ? 1 : 0)
                default: return
                }
            }
            ed.doc.setVariable("DLINEWID", fmt(width))
            var closed = false
            while true {
                let w = width, j = just, cur = pts
                let a = try await ed.getPoint("Specify next point", base: pts.last, keywords: pts.count >= 3 ? ["Close", "Undo"] : ["Undo"]) { c in
                    DraftGeometry.doubleLine(cur + [c], width: w, justification: j, closed: false) }
                switch a {
                case .point(let p): if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
                case .keyword("Close"): closed = true
                case .keyword("Undo"): if pts.count > 1 { pts.removeLast() }; continue
                default: break
                }
                if case .point = a { continue }
                break
            }
            guard pts.count >= 2 else { return }
            for g in DraftGeometry.doubleLine(pts, width: width, justification: just, closed: closed) { ed.addEntity(g) }
        },
        CommandDef("SOLID", aliases: ["SO"], category: "Draw", summary: "Creates solid-filled triangles and quadrilaterals (AutoCAD point order 1-2-3-4).") { ed in
            var p1 = try await ed.requirePoint("Specify first point")
            var p2 = try await ed.requirePoint("Specify second point", base: p1)
            while true {
                let a = p1, b = p2
                let p3 = try await ed.getPoint("Specify third point", base: p2) { c in [.polyline(PolylineGeom(points: [a, b, c], closed: true))] }
                guard let q3 = p3.point else { return }
                let p4 = try await ed.getPoint("Specify fourth point or <exit>", base: q3) { c in [.polyline(PolylineGeom(points: [a, b, c, q3], closed: true))] }
                var loop = [p1, p2]
                if let q4 = p4.point { loop += [q4, q3] } else { loop.append(q3) }
                if GeometryOps.signedArea(loop) < 0 { loop.reverse() }
                ed.addEntity(.hatch(HatchGeom(loops: [loop.map { PolyVertex($0) }], pattern: "SOLID")))
                guard let q4 = p4.point else { return }
                p1 = q3; p2 = q4
            }
        },
        CommandDef("STAR", category: "Draw", summary: "Draws a star-shaped closed polyline.") { ed in
            guard let n = try await ed.getInteger("Enter number of points", defaultValue: Int(ed.variableDouble("STARPOINTS", 5))), (3...200).contains(n) else { throw CommandError.invalid("Requires 3 to 200 points.") }
            ed.doc.setVariable("STARPOINTS", "\(n)")
            let c = try await ed.requirePoint("Specify center of star")
            let outerAns = try await ed.getDistanceOrPoint("Specify outer radius", base: c) { p in
                [.polyline(PolylineGeom(points: DraftGeometry.star(center: c, points: n, outer: c.distance(to: p), inner: c.distance(to: p) * 0.4, angle: (p - c).angle), closed: true))] }
            guard let R = outerAns.value, R > 0 else { return }
            let ang = outerAns.point.map { ($0 - c).angle } ?? .pi / 2
            let r = try await ed.getPositive("Specify inner radius", base: c, defaultValue: R * 0.4)
            ed.addEntity(.polyline(PolylineGeom(points: DraftGeometry.star(center: c, points: n, outer: R, inner: min(r, R), angle: ang), closed: true)))
        },
        CommandDef("BOUNDINGBOX", aliases: ["BBOX"], category: "Draw", summary: "Draws the rectangle bounding the selected objects.") { ed in
            let ids = try await ed.getSelection("Select objects")
            guard !ids.isEmpty else { return }
            let pad = ed.variableDouble("BBOXOFFSET", 0)
            guard let r = DraftGeometry.boundingRectangle(ed.selectionBounds(ids).expanded(by: pad)) else { return }
            ed.selection = []
            ed.addEntity(.polyline(PolylineGeom(points: r, closed: true)))
        },
        CommandDef("PTYPE", aliases: ["DDPTYPE"], category: "Draw", summary: "Sets the point display style (PDMODE) and size (PDSIZE).") { ed in
            ed.print("PDMODE: 0 dot, 1 none, 2 +, 3 x, 4 tick; add 32 circle, 64 square.")
            guard let m = try await ed.getInteger("Enter PDMODE", defaultValue: Int(ed.variableDouble("PDMODE", 0))), m >= 0, m < 100, [0, 1, 2, 3, 4].contains(m % 32) else { throw CommandError.invalid("Invalid PDMODE.") }
            let s = try await ed.getReal("Enter PDSIZE (negative = % of screen)", defaultValue: ed.variableDouble("PDSIZE", 0)).value ?? 0
            ed.doc.setVariable("PDMODE", "\(m)"); ed.doc.setVariable("PDSIZE", fmt(s))
        },
    ] }

    // MARK: - Clipboard
    @MainActor static func copyToClipboard(_ ed: Editor, base: Vec2?) async throws -> [EntityID] {
        let ids = try await ed.getSelection("Select objects")
        guard !ids.isEmpty else { return [] }
        let b = base ?? { let bb = ed.selectionBounds(ids); return bb.min }()
        let clip = DraftClipboard.capture(ids, from: ed.doc, base: b)
        DraftClipboard.current = clip
        DraftClipboard.onChange?(clip)
        ed.print("\(clip.entities.count + clip.elements.count) object(s) copied to the clipboard.")
        return ids
    }

    static var clipboard: [CommandDef] { [
        CommandDef("COPYCLIP", category: "Edit", summary: "Copies objects to the clipboard.", modifies: false) { ed in
            _ = try await copyToClipboard(ed, base: nil); ed.selection = []
        },
        CommandDef("COPYBASE", category: "Edit", summary: "Copies objects to the clipboard with a base point.", modifies: false) { ed in
            let b = try await ed.requirePoint("Specify base point")
            _ = try await copyToClipboard(ed, base: b); ed.selection = []
        },
        CommandDef("CUTCLIP", category: "Edit", summary: "Moves objects to the clipboard (removes them from the drawing).") { ed in
            let ids = try await copyToClipboard(ed, base: nil)
            ed.doc.remove(ids: Set(ids)); ed.selection = []
        },
        CommandDef("PASTECLIP", category: "Edit", summary: "Pastes the clipboard at an insertion point.") { ed in
            guard let clip = DraftClipboard.current, !clip.isEmpty else { throw CommandError.invalid("The clipboard is empty.") }
            let prev = clip.entities.map(\.geometry)
            let p = try await ed.requirePoint("Specify insertion point") { c in prev.prefix(300).map { GeometryOps.transform($0, .translation(c - clip.base)) } }
            let ids = clip.paste(into: &ed.doc, offset: p - clip.base, level: ed.doc.currentLevel)
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) pasted.")
        },
        CommandDef("PASTEORIG", category: "Edit", summary: "Pastes the clipboard at its original coordinates.") { ed in
            guard let clip = DraftClipboard.current, !clip.isEmpty else { throw CommandError.invalid("The clipboard is empty.") }
            let ids = clip.paste(into: &ed.doc, offset: .zero, level: ed.doc.currentLevel)
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) pasted at original coordinates.")
        },
        CommandDef("PASTEBLOCK", category: "Edit", summary: "Pastes the clipboard as a block reference.") { ed in
            guard let clip = DraftClipboard.current, !clip.entities.isEmpty else { throw CommandError.invalid("The clipboard has no drawing objects.") }
            var k = 1
            while ed.doc.blocks["A$C\(k)"] != nil { k += 1 }
            let name = "A$C\(k)"
            for (n, b) in clip.blocks where ed.doc.blocks[n] == nil { ed.doc.blocks[n] = b }
            for l in clip.layers where ed.doc.layer(named: l.name) == nil { ed.doc.layers.append(l) }
            let p = try await ed.requirePoint("Specify insertion point") { c in [.insert(InsertGeom(block: name, position: c))] + clip.entities.prefix(200).map { GeometryOps.transform($0.geometry, .translation(c - clip.base)) } }
            ed.doc.blocks[name] = Block(name: name, basePoint: clip.base, entities: clip.entities)
            ed.addEntity(.insert(InsertGeom(block: name, position: p)))
            ed.print("Pasted as block \(name).")
        },
    ] }

    // MARK: - Modify
    static var modify: [CommandDef] { [
        CommandDef("OOPS", category: "Modify", summary: "Restores the objects removed by the last ERASE.") { ed in
            guard let last = ed.lastErased, !(last.entities.isEmpty && last.elements.isEmpty) else { throw CommandError.invalid("Nothing to restore.") }
            var n = 0
            for e in last.entities {
                if ed.doc.contains(e.id) { ed.doc.add(e) } else { ed.doc.ensureLayer(e.layer); ed.doc.entities.append(e) }
                n += 1
            }
            for el in last.elements {
                var x = el
                if ed.doc.contains(el.id) { x.id = ed.doc.allocateID() }
                ed.doc.elements.append(x); n += 1
            }
            ed.lastErased = nil
            ed.print("\(n) object(s) restored.")
        },
        CommandDef("OVERKILL", aliases: ["-OVERKILL"], category: "Modify", summary: "Removes duplicate objects and merges overlapping collinear lines.") { ed in
            var opt = Overkill.Options()
            opt.tolerance = ed.variableDouble("OVERKILLTOL", 1e-6)
            let pre = ed.selection
            while true {
                let k = try await ed.getKeyword("Enter an option [Done]", ["Done", "Tolerance", "Ignore", "Endtoend", "Polylines"], defaultValue: "Done") ?? "Done"
                switch k {
                case "Tolerance": opt.tolerance = try await ed.getPositive("Specify tolerance", defaultValue: opt.tolerance); ed.doc.setVariable("OVERKILLTOL", fmt(opt.tolerance, 10))
                case "Ignore":
                    let s = try await ed.getWord("Properties to ignore (color,layer,linetype,lineweight or None)", defaultValue: "None") ?? "None"
                    opt.ignore = s.lowercased() == "none" ? [] : Set(s.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                case "Endtoend": opt.combineEndToEnd = try await ed.getYesNo("Combine collinear objects that touch end to end?", defaultValue: true)
                case "Polylines": opt.optimizePolylines = try await ed.getYesNo("Optimize segments within polylines?", defaultValue: true)
                default: break
                }
                if k == "Done" { break }
            }
            ed.selection = pre
            let ids = Set(try await ed.getEntitySelection("Select objects"))
            let ents = ed.doc.entities.filter { ids.contains($0.id) }
            let r = Overkill.run(ents, options: opt)
            for (id, g) in r.modified { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].geometry = g } }
            ed.doc.remove(ids: r.removed)
            ed.selection = []
            ed.print("\(r.removed.count) duplicate(s) deleted, \(r.modified.count) object(s) modified.")
        },
        CommandDef("SETBYLAYER", aliases: ["SBL"], category: "Modify", summary: "Sets color, linetype and lineweight of objects (and block contents) to ByLayer.") { ed in
            let ids = try await ed.getEntitySelection("Select objects")
            let blocks = try await ed.getYesNo("Include blocks?", defaultValue: true)
            var names = Set<String>()
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                ed.doc.entities[i].color = .byLayer; ed.doc.entities[i].linetype = nil; ed.doc.entities[i].lineweight = nil
                if blocks, case .insert(let ins) = ed.doc.entities[i].geometry { names.insert(ins.block) }
            }
            var queue = Array(names)
            while let n = queue.popLast() {
                guard var b = ed.doc.blocks[n] else { continue }
                for j in b.entities.indices {
                    b.entities[j].color = .byBlock; b.entities[j].linetype = "ByBlock"; b.entities[j].lineweight = nil
                    if case .insert(let ins) = b.entities[j].geometry, !names.contains(ins.block) { names.insert(ins.block); queue.append(ins.block) }
                }
                ed.doc.blocks[n] = b
            }
            ed.selection = []
            ed.print("\(ids.count) object(s) changed to ByLayer" + (names.isEmpty ? "." : ", \(names.count) block(s) to ByBlock."))
        },
    ] }

    // MARK: - Command line: aliases, script recording
    static var commandLine: [CommandDef] { [
        CommandDef("ALIAS", aliases: ["ALIASEDIT"], category: "Tools", summary: "Defines command aliases and macros (Define/Delete/List/Global/Load/Save); \";\" in a macro is Enter.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Define", "Delete", "List", "Global", "Load", "Save"], defaultValue: "List") ?? "List"
            switch k {
            case "Define", "Global":
                guard let n = try await ed.getWord("Enter alias name")?.uppercased(), UserAliases.isValidName(n) else { throw CommandError.invalid("Alias names use letters, digits and - _ . $ only.") }
                if let c = ed.registry.lookup(n) { throw CommandError.invalid("\(n) is already the command/alias \(c.name).") }
                guard let v = try await ed.getString("Enter command name or macro (e.g. LINE, or CIRCLE 0,0 500;)"), !v.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                var value = v.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("*") { value.removeFirst() }
                let first = UserAliases.macroTokens(value).first ?? ""
                guard ed.registry.lookup(first) != nil else { throw CommandError.invalid("Unknown command \(first.uppercased()).") }
                if k == "Global" {
                    UserAliases.global[n] = value
                    try? saveGlobal()
                } else { ed.doc.setVariable("ALIAS:" + n, value) }
                ed.print("\(n) → \(value)")
            case "Delete":
                guard let n = try await ed.getWord("Enter alias name")?.uppercased() else { return }
                if ed.doc.variable("ALIAS:" + n) != nil { ed.doc.variables.removeValue(forKey: "ALIAS:" + n) }
                else if UserAliases.global.removeValue(forKey: n) != nil { try? saveGlobal() }
                else { throw CommandError.invalid("Alias \(n) not found.") }
            case "Load":
                guard let p = try await ed.getWord("Enter .pgp file path") else { return }
                guard let s = try? String(contentsOfFile: (p as NSString).expandingTildeInPath, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(p).") }
                let parsed = UserAliases.parsePGP(s)
                for (a, v) in parsed { UserAliases.global[a] = v }
                ed.print("\(parsed.count) alias(es) loaded.")
            case "Save":
                guard let p = try await ed.getWord("Enter .pgp file path", defaultValue: UserAliases.defaultFile.path) else { return }
                var all = UserAliases.global
                for (a, v) in UserAliases.documentAliases(ed.doc) { all[a] = v }
                do { try UserAliases.formatPGP(all).write(toFile: (p as NSString).expandingTildeInPath, atomically: true, encoding: .utf8) }
                catch { throw CommandError.invalid("Cannot write \(p).") }
                ed.print("\(all.count) alias(es) saved.")
            default:
                let d = UserAliases.documentAliases(ed.doc)
                UserAliases.loadDefaultIfNeeded()
                if d.isEmpty && UserAliases.global.isEmpty { ed.print("No user aliases. Use ALIAS Define.") }
                for (a, v) in d.sorted(by: { $0.key < $1.key }) { ed.print("  \(a) → \(v)  (drawing)") }
                for (a, v) in UserAliases.global.sorted(by: { $0.key < $1.key }) where d[a] == nil { ed.print("  \(a) → \(v)  (global)") }
            }
        },
        CommandDef("SCRIPTRECORD", aliases: ["RECSCRIPT"], category: "Tools", summary: "Records typed commands and picks as a script (Start/Stop); saved to a .scr file.", modifies: false) { ed in
            if ed.recorder != nil {
                let rec = ed.recorder!
                ed.recorder = nil
                var lines = rec.lines
                if let i = lines.lastIndex(where: { let n = $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""; return ed.registry.lookup(n)?.name == "SCRIPTRECORD" }) { lines.removeSubrange(i...) }
                let text = lines.joined(separator: "\n") + "\n"
                ed.lastRecordedScript = text
                if let p = rec.path {
                    do { try text.write(toFile: (p as NSString).expandingTildeInPath, atomically: true, encoding: .utf8); ed.print("Script saved to \(p) (\(lines.count) line(s)).") }
                    catch { throw CommandError.invalid("Cannot write \(p).") }
                } else {
                    ed.print("Recorded \(lines.count) line(s):")
                    for l in lines { ed.print("  " + (l.isEmpty ? "\"\"" : l)) }
                }
                return
            }
            let p = try await ed.getWord("Enter .scr file to record to (Enter = keep in memory)", defaultValue: "")
            ed.recorder = ScriptRecorder(path: (p?.isEmpty ?? true) ? nil : p)
            ed.print("Recording started. Run SCRIPTRECORD again to stop.")
        },
    ] }

    static func saveGlobal() throws {
        let url = UserAliases.defaultFile
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try UserAliases.formatPGP(UserAliases.global).write(to: url, atomically: true, encoding: .utf8)
    }
}
