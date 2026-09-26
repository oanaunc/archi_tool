// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Table styles (ANN-058), filled / masking regions (ANN-073), model and drafting patterns (ANN-071), section /
/// elevation / detail marks (ANN-053), revision cloud listing (ANN-052), layer notification (LAY-020) and the bundled
/// block and annotation libraries (BLK-037 / BLK-042).
enum Round8AnnotationCommands {
    static var all: [CommandDef] { [tableStyle, filledRegion, maskingRegion, hatchType, sectionMark, elevationMark, detailMark,
                                    revCloudList, layerNotify, layReconcile, libraryInstall, dblClkEdit] }

    // MARK: Table styles
    static var tableStyle: CommandDef {
        CommandDef("TABLESTYLE", aliases: ["TS"], category: "Annotate", summary: "Table styles: New / Edit title, header and data cells (height, alignment, colour, fill), Current, Apply to tables, List, Delete.") { ed in
            let cur = ed.doc.variable("CTABLESTYLE") ?? "Standard"
            let k = try await ed.getKeyword("Enter an option", ["New", "Edit", "Current", "Apply", "List", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "List":
                for n in TableStyle.names(ed.doc) {
                    let s = TableStyle.named(n, ed.doc)!
                    ed.print("  \(n)\(n.caseInsensitiveCompare(cur) == .orderedSame ? " (current)" : ""): title \(s.hasTitle ? "on" : "off"), header \(s.hasHeader ? "on" : "off")")
                }
            case "New", "Edit":
                guard let n = try await ed.getWord("Enter table style name", defaultValue: k == "Edit" ? cur : nil), BlockCommands.validName(n) else { throw CommandError.invalid("Invalid name.") }
                var s = TableStyle.named(n, ed.doc) ?? TableStyle(name: n)
                if k == "New", TableStyle.named(n, ed.doc) != nil { throw CommandError.invalid("Table style \(n) already exists.") }
                if k == "Edit", n.caseInsensitiveCompare("Standard") == .orderedSame { s = TableStyle(name: "Standard") }
                s.name = n
                while true {
                    guard let o = try await ed.getKeyword("Edit", ["Title", "Header", "Data", "TItlerow", "HEaderrow", "eXit"], defaultValue: "eXit"), o != "eXit" else { break }
                    switch o {
                    case "TItlerow": s.hasTitle = try await ed.getYesNo("Start with a title row?", defaultValue: s.hasTitle)
                    case "HEaderrow": s.hasHeader = try await ed.getYesNo("Include a header row?", defaultValue: s.hasHeader)
                    default:
                        let role: TableStyle.Role = o == "Title" ? .title : o == "Header" ? .header : .data
                        var c = s.cell(role)
                        c.height = try await ed.getReal("Text height factor (× table text height)", defaultValue: c.height).value ?? c.height
                        guard c.height > 0 else { throw CommandError.invalid("The height factor must be positive.") }
                        let a = try await ed.getKeyword("Alignment", ["Left", "Center", "Right"], defaultValue: c.align.rawValue.capitalized) ?? "Left"
                        c.align = HAlign(rawValue: a.lowercased()) ?? .left
                        let col = try await ed.getWord("Text color [ByBlock] or a color", defaultValue: c.color ?? "ByBlock") ?? "ByBlock"
                        c.color = col.lowercased() == "byblock" ? nil : col
                        let f = try await ed.getWord("Fill color [None] or a color", defaultValue: c.fill ?? "None") ?? "None"
                        c.fill = f.lowercased() == "none" ? nil : f
                        if let v = c.color, ColorRef.parse(v) == nil { throw CommandError.invalid("Invalid color \(v).") }
                        if let v = c.fill, ColorRef.parse(v) == nil { throw CommandError.invalid("Invalid color \(v).") }
                        s.setCell(role, c)
                    }
                }
                s.save(&ed.doc)
                if k == "New" { ed.doc.setVariable("CTABLESTYLE", n) }
                ed.print("Table style \(n) saved.")
            case "Current":
                guard let n = try await ed.getWord("Enter table style name", defaultValue: cur), let s = TableStyle.named(n, ed.doc) else { throw CommandError.invalid("Table style not found.") }
                ed.doc.setVariable("CTABLESTYLE", s.name)
            case "Apply":
                guard let n = try await ed.getWord("Enter table style name", defaultValue: cur), let s = TableStyle.named(n, ed.doc) else { throw CommandError.invalid("Table style not found.") }
                let ids = try await ed.getEntitySelection("Select tables")
                var c = 0
                for id in ids { if let i = ed.doc.entityIndex(id), case .table = ed.doc.entities[i].geometry { ed.doc.entities[i].props[TableStyle.prop] = s.name; c += 1 } }
                ed.selection = []
                ed.print("\(c) table(s) use style \(s.name).")
            case "Delete":
                guard let n = try await ed.getWord("Enter table style name") else { return }
                guard n.caseInsensitiveCompare("Standard") != .orderedSame, TableStyle.named(n, ed.doc) != nil else { throw CommandError.invalid("Cannot delete that style.") }
                if ed.doc.entities.contains(where: { $0.props[TableStyle.prop]?.caseInsensitiveCompare(n) == .orderedSame }) { throw CommandError.invalid("Table style \(n) is in use.") }
                TableStyle.delete(n, &ed.doc)
                if cur.caseInsensitiveCompare(n) == .orderedSame { ed.doc.variables["CTABLESTYLE"] = nil }
            default: return
            }
        }
    }

    // MARK: Filled and masking regions
    @MainActor static func regionLoops(_ ed: Editor, _ msg: String) async throws -> (loops: [[PolyVertex]], seed: Vec2?)? {
        let a = try await ed.getPoint(msg, keywords: ["Draw", "Select"])
        switch a {
        case .point(let p):
            guard let r = RegionFinder.region(at: p, curves: DrawCommands.hatchCurves(ed), doc: ed.doc) else { throw CommandError.invalid("Valid boundary not found.") }
            return ([r.outer] + r.holes, p)
        case .keyword("Select"):
            guard case .pick(let pk) = try await ed.pickObject("Select a closed boundary"), let e = ed.doc.entity(pk.id), let loop = CommandHelpers.closedLoop(e.geometry) else { throw CommandError.invalid("Select a closed object.") }
            return ([loop], nil)
        case .keyword("Draw"):
            var pts = [try await ed.requirePoint("Specify first point")]
            while true {
                let cur = pts
                guard let q = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.polyline(PolylineGeom(points: cur + [c], closed: true))] }).point else { break }
                pts.append(q)
            }
            guard pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-9 else { throw CommandError.invalid("A region needs at least three non-collinear points.") }
            return ([pts.map { PolyVertex($0) }], nil)
        default: return nil
        }
    }
    @MainActor static func placeRegion(_ ed: Editor, _ g: HatchGeom, loops: [[PolyVertex]], seed: Vec2?, props: [String: String], edges: Bool) -> EntityID {
        let id = ed.addEntity(.hatch(g))
        guard let i = ed.doc.entityIndex(id) else { return id }
        // View-specific: shown only on the current level's plan.
        ed.doc.entities[i].props["level"] = "\(ed.doc.currentLevel)"
        for (k, v) in props { ed.doc.entities[i].props[k] = v }
        if let p = seed, ed.doc.variable("HPASSOC") != "0" {
            let bnd = AssociativeHatch.boundaryObjects(of: loops, candidates: ed.doc.entities.filter { $0.id != id && ed.doc.isVisible(layer: $0.layer) }, doc: ed.doc)
            AssociativeHatch.attach(&ed.doc, hatch: id, boundary: bnd, seed: p)
        }
        if edges {
            for l in loops {
                let eid = ed.addEntity(.polyline(PolylineGeom(l, closed: true)))
                if let j = ed.doc.entityIndex(eid) { ed.doc.entities[j].props["level"] = "\(ed.doc.currentLevel)"; ed.doc.entities[j].props["regionEdgeOf"] = "\(id)" }
            }
        }
        return id
    }
    static var filledRegion: CommandDef {
        CommandDef("FILLEDREGION", aliases: ["FR", "REGIONFILL"], category: "Annotate", summary: "View-specific filled region on the current level: solid colour or a drafting / model pattern, with optional boundary lines; associative to its boundary.") { ed in
            var pattern = ed.doc.variable("FRPATTERN") ?? "SOLID"
            var color = ed.doc.variable("FRCOLOR") ?? "#C8C8C8"
            var type = ed.doc.variable("FRPATTERNTYPE") ?? "Drafting"
            var edges = ed.doc.variable("FREDGES") == "1"
            while true {
                let k = try await ed.getKeyword("Specify boundary", ["Boundary", "Pattern", "Color", "Type", "Lines"], defaultValue: "Boundary") ?? "Boundary"
                switch k {
                case "Pattern":
                    let p = try await ed.getWord("Enter pattern name (SOLID for a solid fill)", defaultValue: pattern) ?? pattern
                    guard p.uppercased() == "SOLID" || !HatchPatterns.lines(loops: [[.zero, Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)]], pattern: p, scale: 1, angle: 0).isEmpty else { throw CommandError.invalid("Unknown pattern \(p).") }
                    pattern = p.uppercased(); ed.doc.setVariable("FRPATTERN", pattern); continue
                case "Color":
                    let c = try await ed.getWord("Enter fill color", defaultValue: color) ?? color
                    guard ColorRef.parse(c) != nil else { throw CommandError.invalid("Invalid color.") }
                    color = c; ed.doc.setVariable("FRCOLOR", c); continue
                case "Type":
                    type = try await ed.getKeyword("Pattern type", ["Drafting", "Model"], defaultValue: type) ?? type
                    ed.doc.setVariable("FRPATTERNTYPE", type); continue
                case "Lines":
                    edges = try await ed.getYesNo("Draw boundary lines?", defaultValue: edges); ed.doc.setVariable("FREDGES", edges ? "1" : "0"); continue
                default: break
                }
                break
            }
            guard let r = try await regionLoops(ed, "Pick internal point") else { return }
            let solid = pattern == "SOLID"
            let fill = ColorRef.parse(color)
            let g = HatchGeom(loops: r.loops, pattern: pattern, fill: solid ? fill : nil)
            var props = ["filledRegion": "1"]
            if !solid { props[HatchPatterns.patternTypeProp] = type.lowercased() }
            let id = placeRegion(ed, g, loops: r.loops, seed: r.seed, props: props, edges: edges)
            if !solid, let i = ed.doc.entityIndex(id), let f = fill { ed.doc.entities[i].color = f }
            let area = r.loops.enumerated().reduce(0.0) { acc, x in
                let a = abs(GeometryOps.signedArea(GeometryOps.polylinePoints(x.element, closed: true)))
                return x.offset == 0 ? acc + a : acc - a
            }
            ed.print("Filled region created: area = \(CommandHelpers.areaText(area, units: ed.doc.units)).")
        }
    }
    static var maskingRegion: CommandDef {
        CommandDef("MASKINGREGION", aliases: ["MASKREGION"], category: "Annotate", summary: "View-specific masking region on the current level: hides the model and drafting beneath it.") { ed in
            guard let r = try await regionLoops(ed, "Pick internal point") else { return }
            let g = HatchGeom(loops: r.loops, pattern: "SOLID", fill: .rgb(255, 255, 255))
            _ = placeRegion(ed, g, loops: r.loops, seed: r.seed, props: ["wipeout": "1", "maskingRegion": "1"], edges: false)
            ed.print("Masking region created.")
        }
    }

    // MARK: Model / drafting patterns
    static var hatchType: CommandDef {
        CommandDef("HATCHTYPE", aliases: ["HPTYPE", "PATTERNTYPE"], category: "Annotate", summary: "Sets hatches to Model patterns (real size, scale with the model) or Drafting patterns (fixed size on paper at the annotation scale).") { ed in
            let k = try await ed.getKeyword("Pattern type", ["Model", "Drafting", "Default"], defaultValue: "Drafting") ?? "Drafting"
            let ids = ed.selection.isEmpty ? try await ed.getEntitySelection("Select hatches (Enter = new hatches)") : Array(ed.selection)
            ed.selection = []
            if ids.isEmpty {
                if k == "Default" { ed.doc.variables["HPTYPE"] = nil } else { ed.doc.setVariable("HPTYPE", k.lowercased()) }
                ed.print("New hatches use \(k.lowercased()) patterns."); return
            }
            var c = 0
            for id in ids { if let i = ed.doc.entityIndex(id), case .hatch = ed.doc.entities[i].geometry { ed.doc.entities[i].props[HatchPatterns.patternTypeProp] = k == "Default" ? nil : k.lowercased(); c += 1 } }
            ed.print("\(c) hatch(es) set to \(k.lowercased()) patterns.")
        }
    }

    // MARK: Section / elevation / detail marks
    @MainActor static func symbolGroup(_ ed: Editor, _ ents: [Entity], prefix: String) {
        AnnotationSymbols.ensureBlocks(&ed.doc)
        var n = 1
        while ed.doc.entities.contains(where: { $0.props["group"] == "\(prefix)\(n)" }) { n += 1 }
        let layer = ed.annotationLayer("TEXTLAYER")
        for var e in ents { e.layer = layer; e.props["group"] = "\(prefix)\(n)"; ed.doc.add(e) }
    }
    @MainActor static func labels(_ ed: Editor, _ key: String) async throws -> (String, String, Double) {
        let lastN = ed.doc.variable(key) ?? "0"
        let def = RevisionSymbols.next(after: lastN == "0" ? nil : lastN)
        let num = try await ed.getWord("Enter number", defaultValue: def) ?? def
        let sheet = try await ed.getWord("Enter sheet reference", defaultValue: ed.doc.variable("SYMSHEET") ?? "A-501") ?? "-"
        ed.doc.setVariable(key, num); ed.doc.setVariable("SYMSHEET", sheet)
        let size = try await ed.getPositive("Specify bubble size", defaultValue: AnnotationSymbols.size(ed.doc))
        return (num, sheet, size)
    }
    static var sectionMark: CommandDef {
        CommandDef("SECTIONSYMBOL", aliases: ["SECMARK", "SECTIONHEAD"], category: "Annotate", summary: "Draws a 2D section symbol: cut line with section heads (number / sheet attributes) looking to the picked side.") { ed in
            let a = try await ed.requirePoint("Specify start of cut line")
            let b = try await ed.requirePoint("Specify end of cut line", base: a) { c in [.line(LineGeom(a, c))] }
            guard a.distance(to: b) > 1e-9 else { throw CommandError.invalid("Points coincide.") }
            let side = try await ed.requirePoint("Specify viewing side", base: (a + b) / 2)
            let (num, sheet, size) = try await labels(ed, "SECTIONMARKNUM")
            symbolGroup(ed, AnnotationSymbols.section(from: a, to: b, side: side, size: size, num: num, sheet: sheet), prefix: "SECTION")
        }
    }
    static var elevationMark: CommandDef {
        CommandDef("ELEVATIONMARK", aliases: ["ELEVMARK", "ELEVATIONSYMBOL"], category: "Annotate", summary: "Places a 2D elevation marker (bubble with a pointer in the view direction; 4 for an interior elevation set).") { ed in
            let p = try await ed.requirePoint("Specify marker location")
            let q = try await ed.requirePoint("Specify view direction", base: p) { c in [.line(LineGeom(p, c))] }
            guard p.distance(to: q) > 1e-9 else { throw CommandError.invalid("Points coincide.") }
            let four = try await ed.getYesNo("Four directions (interior elevations)?", defaultValue: false)
            let (num, sheet, size) = try await labels(ed, "ELEVMARKNUM")
            var ents: [Entity] = []
            let d = q - p
            for k in 0..<(four ? 4 : 1) {
                let n = four ? "\(num)\(["a", "b", "c", "d"][k])" : num
                ents.append(AnnotationSymbols.elevationMark(at: p, direction: d.rotated(by: Double(k) * .pi / 2), size: size, num: n, sheet: sheet))
            }
            symbolGroup(ed, ents, prefix: "ELEV")
        }
    }
    static var detailMark: CommandDef {
        CommandDef("DETAILMARK", aliases: ["DETMARK", "DETAILSYMBOL"], category: "Annotate", summary: "Places a 2D detail bubble (number / sheet attributes) with an optional leader to the detail.") { ed in
            let p = try await ed.requirePoint("Specify bubble location")
            let t = try await ed.getPoint("Specify leader end point <none>", base: p).point
            let (num, sheet, size) = try await labels(ed, "DETAILMARKNUM")
            symbolGroup(ed, AnnotationSymbols.detailMark(at: p, size: size, num: num, sheet: sheet, target: t), prefix: "DETAIL")
        }
    }

    // MARK: Revision clouds by revision
    static var revCloudList: CommandDef {
        CommandDef("REVCLOUDLIST", aliases: ["REVISIONCLOUDS"], category: "Annotate", summary: "Lists revision clouds by revision, selects the clouds of one revision, and adds missing revisions to the revision table.") { ed in
            let by = RevisionClouds.byRevision(ed.doc)
            if by.isEmpty { ed.print("No revision clouds."); return }
            for (r, ids) in by.sorted(by: { $0.key < $1.key }) { ed.print("  Revision \(r): \(ids.count) cloud(s)") }
            let added = RevisionClouds.syncTable(&ed.doc)
            if !added.isEmpty { ed.print("Revision table: added \(added.joined(separator: ", ")).") }
            if let r = try await ed.getWord("Enter revision to select <none>", defaultValue: ""), !r.isEmpty, let ids = by[r] { ed.selection = Set(ids) }
        }
    }

    // MARK: Layer notification
    static var layerNotify: CommandDef {
        CommandDef("LAYERNOTIFY", aliases: ["LAYEREVAL"], category: "Layers", summary: "Notifies when unreconciled new layers appear (On/Off) or lists them.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["On", "Off", "List"], defaultValue: LayerNotify.isOn(ed.doc) ? "List" : "On") ?? "List"
            switch k {
            case "On": LayerNotify.setOn(true, &ed.doc); ed.print("New layer notification on.")
            case "Off": LayerNotify.setOn(false, &ed.doc); ed.print("New layer notification off.")
            default:
                let u = LayerNotify.unreconciled(ed.doc)
                ed.print(u.isEmpty ? "No unreconciled layers." : "Unreconciled layers: \(u.joined(separator: ", "))")
            }
        }
    }
    static var layReconcile: CommandDef {
        CommandDef("LAYRECONCILE", aliases: ["RECONCILELAYERS"], category: "Layers", summary: "Marks unreconciled layers as reconciled (all, or the named ones).") { ed in
            let u = LayerNotify.unreconciled(ed.doc)
            let w = try await ed.getString("Enter layer names separated by commas <all>", defaultValue: "") ?? ""
            let names = w.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            LayerNotify.reconcile(names.isEmpty ? nil : names, &ed.doc)
            ed.print("\(names.isEmpty ? u.count : names.count) layer(s) reconciled.")
        }
    }

    // MARK: Bundled library
    static var libraryInstall: CommandDef {
        CommandDef("LIBRARYINSTALL", aliases: ["BUNDLEDLIBRARY", "INSTALLLIBRARY"], category: "Blocks", summary: "Installs the free bundled block library (furniture, sanitary, kitchen, vehicles, people, trees, annotation symbols) into a folder and makes it the block library.", modifies: true) { ed in
            let path = try await ed.getWord("Enter library folder", defaultValue: BundledLibrary.defaultFolder) ?? BundledLibrary.defaultFolder
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            do {
                let files = try BundledLibrary.install(to: url)
                ed.doc.setVariable("BLOCKLIBRARYPATH", path)
                let n = BundledLibrary.categories.reduce(0) { $0 + $1.blocks.count }
                ed.print("\(n) blocks in \(files.count) drawings installed in \(url.path). Browse them with BLOCKLIBRARY or the block library panel.")
            } catch { throw CommandError.invalid("Cannot write \(url.path): \(error.localizedDescription)") }
        }
    }

    // MARK: Double-click editing
    static var dblClkEdit: CommandDef {
        CommandDef("DBLCLKEDIT", category: "Settings", summary: "Turns double-click editing of objects on or off; with an object, runs its double-click editor.") { ed in
            let a = try await ed.getWord("Enter double-click editing mode or #id of an object", defaultValue: ed.doubleClickEditing ? "ON" : "OFF", keywords: ["ON", "OFF"]) ?? "ON"
            if a == "ON" || a == "OFF" { ed.doc.setVariable("DBLCLKEDIT", a); ed.print("Double-click editing \(a.lowercased())."); return }
            guard let id = Int(a.trimmingCharacters(in: CharacterSet(charactersIn: "# "))), let cmd = ed.doubleClickCommand(for: id) else { throw CommandError.invalid("No double-click editor for that object.") }
            ed.print("Double-click editor: \(cmd)")
        }
    }
}
