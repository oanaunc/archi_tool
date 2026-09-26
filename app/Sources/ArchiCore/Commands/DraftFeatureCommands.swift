// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Drafting commands: associative array editing and classic arrays, macro buttons, helix, system variable monitor,
/// relative zero, block clipping, block property tables, bullets and numbering, colour books, dimension tolerances /
/// alternate units / inspection frames, and layer descriptions.
public enum DraftFeatureCommands {
    public static var all: [CommandDef] {
        [arrayEdit, arrayClassic, macroButton, helix, sysVarMonitor, relZero, xclip, btable, textList, colorBook,
         dimTol, dimAlt, dimInspect, layDesc, textColumns, autoStack]
    }

    // MARK: - Arrays (MOD-033, MOD-034)

    static var arrayEdit: CommandDef {
        CommandDef("ARRAYEDIT", aliases: ["ARRAYED"], category: "Modify", summary: "Edits an associative array: rows, columns, spacing, items, fill angle, rotation, alignment.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select array", filter: { AssocArray.isArray(ed.doc.entity($0)) || ed.bimArrayName(of: $0) != nil }) else { return }
            if let bn = ed.bimArrayName(of: pk.id), var bp = ed.bimArrayParams(bn) {
                // BIM element array (MOD-035): rows, columns and spacing; copies are regenerated.
                ed.selection = []
                while true {
                    guard let k = try await ed.getKeyword("Enter an option", ["Rows", "Columns", "Spacing", "Explode", "eXit"], defaultValue: "eXit"), k != "eXit" else { break }
                    switch k {
                    case "Rows":
                        guard let n = try await ed.getInteger("Enter the number of rows", defaultValue: bp.rows), n >= 1 else { ed.print("Requires a positive integer."); continue }
                        bp.rows = n
                    case "Columns":
                        guard let n = try await ed.getInteger("Enter the number of columns", defaultValue: bp.columns), n >= 1 else { ed.print("Requires a positive integer."); continue }
                        bp.columns = n
                    case "Spacing":
                        bp.rowSpacing = try await ed.getDistance("Specify the distance between rows", defaultValue: bp.rowSpacing).value ?? bp.rowSpacing
                        bp.columnSpacing = try await ed.getDistance("Specify the distance between columns", defaultValue: bp.columnSpacing).value ?? bp.columnSpacing
                    case "Explode": ed.explodeBIMArray(bn); ed.print("BIM array exploded."); return
                    default: break
                    }
                    let n = ed.updateBIMArray(bn, rows: bp.rows, columns: bp.columns, rowSpacing: bp.rowSpacing, columnSpacing: bp.columnSpacing)
                    ed.print("BIM array \(bn): \(bp.rows) × \(bp.columns), \(n) object(s).")
                }
                return
            }
            guard let e = ed.doc.entity(pk.id), var p = AssocArray.params(e) else { return }
            ed.selection = []
            while true {
                let kws: [String]
                switch p.kind {
                case .rect: kws = ["Rows", "Columns", "Spacing", "Angle", "eXit"]
                case .polar: kws = ["Items", "Fill", "Rotate", "Center", "eXit"]
                case .path: kws = ["Items", "Align", "eXit"]
                }
                guard let k = try await ed.getKeyword("Enter an option", kws, defaultValue: "eXit"), k != "eXit" else { break }
                switch k {
                case "Rows":
                    guard let n = try await ed.getInteger("Enter the number of rows", defaultValue: p.rows), n >= 1 else { ed.print("Requires a positive integer."); continue }
                    p.rows = n
                    if n > 1 { p.rowSpacing = try await ed.getDistance("Specify the distance between rows", defaultValue: p.rowSpacing).value ?? p.rowSpacing }
                case "Columns":
                    guard let n = try await ed.getInteger("Enter the number of columns", defaultValue: p.columns), n >= 1 else { ed.print("Requires a positive integer."); continue }
                    p.columns = n
                    if n > 1 { p.columnSpacing = try await ed.getDistance("Specify the distance between columns", defaultValue: p.columnSpacing).value ?? p.columnSpacing }
                case "Spacing":
                    p.rowSpacing = try await ed.getDistance("Specify the distance between rows", defaultValue: p.rowSpacing).value ?? p.rowSpacing
                    p.columnSpacing = try await ed.getDistance("Specify the distance between columns", defaultValue: p.columnSpacing).value ?? p.columnSpacing
                case "Angle": p.angle = try await ed.getAngle("Specify the angle of the row axis", defaultValue: p.angle).value ?? p.angle
                case "Items":
                    guard let n = try await ed.getInteger("Enter the number of items", defaultValue: p.count), n >= 1, n <= 100000 else { ed.print("Requires a positive integer."); continue }
                    p.count = n
                case "Fill":
                    let f = try await ed.getAngle("Specify the angle to fill (+ = ccw, - = cw)", defaultValue: p.fill).value ?? p.fill
                    guard abs(f) > 1e-9 else { ed.print("Angle to fill must not be zero."); continue }
                    p.fill = f
                case "Rotate": p.rotateItems = try await ed.getYesNo("Rotate arrayed items?", defaultValue: p.rotateItems)
                case "Center": p.center = try await ed.requirePoint("Specify center point of array")
                case "Align": p.align = try await ed.getYesNo("Align arrayed items with the path?", defaultValue: p.align)
                default: break
                }
                guard p.itemCount <= 100000 else { ed.print("Too many items."); continue }
                AssocArray.update(pk.id, p, &ed.doc)
            }
            ed.print("Array: \(p.itemCount) item(s).")
        }
    }

    static var arrayClassic: CommandDef {
        CommandDef("ARRAYCLASSIC", aliases: ["-ARRAYCLASSIC", "ARRAYNONASSOC"], category: "Modify", summary: "Creates a non-associative (separate copies) rectangular, polar or path array.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let k = try await ed.getKeyword("Enter array type", ["Rectangular", "PAth", "POlar"], defaultValue: "Rectangular") ?? "Rectangular"
            ed.forceClassicArray = true
            defer { ed.forceClassicArray = false }
            switch k {
            case "POlar": try await ModifyCommands.polarArray(ed, ids)
            case "PAth": try await ModifyCommands.pathArray(ed, ids)
            default: try await ModifyCommands.rectArray(ed, ids)
            }
            ed.selection = []
        }
    }

    // MARK: - Macro buttons (CMD-041)

    static var macroButton: CommandDef {
        CommandDef("MACROBUTTON", aliases: ["MBUTTON", "-CUI", "CUIBUTTON"], category: "Tools", summary: "Creates, edits, lists, runs and deletes custom macro buttons (saved in the drawing or in your profile).") { ed in
            while true {
                guard let k = try await ed.getKeyword("Macro buttons [New/Edit/Delete/List/Run/Save/Load/eXit]", ["New", "Edit", "Delete", "List", "Run", "Save", "Load", "eXit"], defaultValue: "eXit"),
                      k != "eXit" else { return }
                var list = MacroButtons.document(ed.doc)
                switch k {
                case "New", "Edit":
                    guard let name = try await ed.getString("Button name"), !name.isEmpty else { continue }
                    let old = list.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    guard let macro = try await ed.getString("Macro (e.g. ^C^CLINE;\\;)", defaultValue: old?.macro) else { continue }
                    if let err = MacroButtons.validate(macro, registry: ed.registry, doc: ed.doc) { ed.print(err); continue }
                    let icon = try await ed.getString("Icon (SF Symbol name)", defaultValue: old?.icon ?? "command") ?? "command"
                    let tip = try await ed.getString("Tooltip", defaultValue: old?.tooltip ?? "") ?? ""
                    let group = try await ed.getString("Toolbar", defaultValue: old?.group ?? "Custom") ?? "Custom"
                    let b = MacroButton(name: name, macro: macro, icon: icon, tooltip: tip, group: group)
                    if let i = list.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { list[i] = b } else { list.append(b) }
                    MacroButtons.setDocument(list, &ed.doc)
                    ed.print("Button \"\(name)\" saved.")
                case "Delete":
                    guard let name = try await ed.getString("Button name") else { continue }
                    let n = list.count
                    list.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    MacroButtons.setDocument(list, &ed.doc)
                    ed.print(list.count < n ? "Button deleted." : "No button named \"\(name)\".")
                case "List":
                    let all = MacroButtons.all(ed.doc)
                    if all.isEmpty { ed.print("No macro buttons.") }
                    for b in all { ed.print("  [\(b.group)] \(b.name): \(b.macro)" + (b.tooltip.isEmpty ? "" : " — \(b.tooltip)")) }
                case "Run":
                    guard let name = try await ed.getString("Button name"),
                          let b = MacroButtons.all(ed.doc).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { ed.print("No such button."); continue }
                    Task { @MainActor in
                        var n = 0
                        while !ed.isIdle && n < 100000 { await Task.yield(); n += 1 }
                        ed.runMacro(b.macro)
                    }
                    return
                case "Save":
                    var user = MacroButtons.user()
                    for b in list { if let i = user.firstIndex(where: { $0.name == b.name }) { user[i] = b } else { user.append(b) } }
                    ed.print(MacroButtons.saveUser(user) ? "\(list.count) button(s) saved to your profile." : "Cannot write the profile file.")
                case "Load":
                    let user = MacroButtons.user()
                    for b in user where !list.contains(where: { $0.name == b.name }) { list.append(b) }
                    MacroButtons.setDocument(list, &ed.doc)
                    ed.print("\(user.count) profile button(s) available in this drawing.")
                default: break
                }
            }
        }
    }

    // MARK: - Helix (DRW-055)

    static var helix: CommandDef {
        CommandDef("HELIX", category: "Draw", summary: "Draws a 2D/3D helix or spiral: base and top radius, turns, height and twist direction.") { ed in
            let c = try await ed.requirePoint("Specify center point of base")
            let r0 = try await ed.getPositive("Specify base radius", base: c, defaultValue: ed.variableDouble("HELIXRAD", 1000))
            let r1 = try await ed.getPositive("Specify top radius", base: c, defaultValue: r0, allowZero: true)
            var turns = ed.variableDouble("HELIXTURNS", 3), ccw = true, height = 0.0
            let a0 = 0.0
            while true {
                let r = try await ed.getDistance("Specify helix height or [Turns/tWist]", defaultValue: ed.variableDouble("HELIXHEIGHT", 0), keywords: ["Turns", "tWist"])
                switch r {
                case .keyword("Turns"):
                    let t = try await ed.getReal("Enter number of turns", defaultValue: turns).value ?? turns
                    guard t > 0, t <= 500 else { ed.print("Enter a number of turns between 0 and 500."); continue }
                    turns = t
                case .keyword("tWist"):
                    ccw = (try await ed.getKeyword("Enter twist direction of helix [CW/CCW]", ["CW", "CCW"], defaultValue: "CCW") ?? "CCW") == "CCW"
                case .value(let h): height = h
                default: break
                }
                if case .keyword = r { continue }
                break
            }
            guard r0 > 0 || r1 > 0 else { throw CommandError.invalid("At least one radius must be greater than zero.") }
            ed.doc.setVariable("HELIXTURNS", fmt(turns)); ed.doc.setVariable("HELIXHEIGHT", fmt(height)); ed.doc.setVariable("HELIXRAD", fmt(r0))
            var e = Helix.entity(center: c, baseRadius: r0, topRadius: r1, turns: turns, height: height, startAngle: a0, ccw: ccw, layer: ed.doc.currentLayer)
            if let cc = ed.doc.variable("CECOLOR"), let cr = ColorRef.parse(cc) { e.color = cr }
            ed.doc.add(e)
        }
    }

    // MARK: - System variable monitor (CMD-037)

    static var sysVarMonitor: CommandDef {
        CommandDef("SYSVARMONITOR", aliases: ["SYSMON", "-SYSVARMONITOR"], category: "Tools", summary: "Watch list of system variables: you are notified when a command changes one of them.") { ed in
            while true {
                let cur = SysVarMonitor.watched(ed.doc)
                guard let k = try await ed.getKeyword("Monitored: \(cur.isEmpty ? "none" : cur.joined(separator: ", ")) [Add/Remove/Clear/Notify/eXit]",
                                                      ["Add", "Remove", "Clear", "Notify", "eXit"], defaultValue: "eXit"), k != "eXit" else { return }
                switch k {
                case "Add":
                    guard let w = try await ed.getWord("Enter system variable name(s), comma separated") else { continue }
                    let names = w.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
                    for n in names where SysVarCatalog.info(n) == nil && ed.doc.variable(n) == nil { ed.print("Note: \(n) is not a known system variable.") }
                    SysVarMonitor.setWatched(cur + names, &ed.doc)
                case "Remove":
                    guard let w = try await ed.getWord("Enter system variable name") else { continue }
                    SysVarMonitor.setWatched(cur.filter { $0 != w.uppercased() }, &ed.doc)
                case "Clear": SysVarMonitor.setWatched([], &ed.doc)
                case "Notify":
                    let on = try await ed.getYesNo("Notify when monitored variables change?", defaultValue: ed.doc.variable(SysVarMonitor.notifyVariable) != "0")
                    ed.doc.setVariable(SysVarMonitor.notifyVariable, on ? "1" : "0")
                default: break
                }
            }
        }
    }

    // MARK: - Relative zero (PRC-029)

    static var relZero: CommandDef {
        CommandDef("RELZERO", aliases: ["RELATIVEZERO", "SETRELZERO"], category: "Tools", summary: "Sets the relative zero (the point @ input is measured from), or locks / unlocks it.", modifies: false) { ed in
            let a = try await ed.getPoint("Specify relative zero or [Lock/Unlock] <\(ed.relativeZeroLock != nil ? "locked" : "unlocked")>", keywords: ["Lock", "Unlock"])
            switch a {
            case .point(let p):
                if ed.relativeZeroLock != nil { ed.relativeZeroLock = p } else { ed.lastPoint = p }
                ed.print("Relative zero: \(fmt(p.x, 4)),\(fmt(p.y, 4))")
            case .keyword("Lock"):
                let p = try await ed.getPoint("Specify point to lock relative zero at <last point>").point ?? ed.lastPoint ?? .zero
                ed.relativeZeroLock = p
                ed.print("Relative zero locked at \(fmt(p.x, 4)),\(fmt(p.y, 4)).")
            case .keyword("Unlock"):
                let p = ed.relativeZeroLock
                ed.relativeZeroLock = nil
                if let p { ed.lastPoint = p }
                ed.print("Relative zero unlocked.")
            default: break
            }
        }
    }

    // MARK: - XCLIP (BLK-031)

    static var xclip: CommandDef {
        CommandDef("XCLIP", aliases: ["XC", "CLIPBLOCK", "BCLIP"], category: "Blocks", summary: "Clips block references and xrefs to a rectangular or polygonal boundary (New/ON/OFF/Delete/Polyline).") { ed in
            let ids = try await ed.getEntitySelection("Select block references").filter { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }
            ed.selection = []
            guard !ids.isEmpty else { throw CommandError.invalid("No block references selected.") }
            let k = try await ed.getKeyword("Enter clipping option [ON/OFF/Delete/New boundary]", ["ON", "OFF", "Delete", "New"], defaultValue: "New") ?? "New"
            @MainActor func each(_ body: (inout Entity) -> Void) { for id in ids { if let i = ed.doc.entityIndex(id) { body(&ed.doc.entities[i]) } } }
            switch k {
            case "ON": each { $0.props[BlockClip.offProp] = nil }
            case "OFF": each { if $0.props[BlockClip.prop] != nil { $0.props[BlockClip.offProp] = "1" } }
            case "Delete": each { BlockClip.setBoundary(nil, on: &$0) }
            default:
                let m = try await ed.getKeyword("Specify clipping boundary [Select polyline/Polygonal/Rectangular]", ["Select", "Polygonal", "Rectangular"], defaultValue: "Rectangular") ?? "Rectangular"
                var poly: [Vec2] = []
                switch m {
                case "Select":
                    guard case .pick(let pk) = try await ed.pickObject("Select closed polyline"), let g = ed.doc.entity(pk.id)?.geometry,
                          let loop = CommandHelpers.closedLoop(g) else { throw CommandError.invalid("Select a closed polyline.") }
                    poly = GeometryOps.polylinePoints(loop, closed: true)
                case "Polygonal":
                    poly = [try await ed.requirePoint("Specify first point")]
                    while let p = try await ed.getPoint("Specify next point or <Enter to finish>", base: poly.last, preview: { c in [.polyline(PolylineGeom(points: poly + [c], closed: true))] }).point {
                        poly.append(p)
                    }
                default:
                    let a = try await ed.requirePoint("Specify first corner")
                    let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: [a, Vec2(c.x, a.y), c, Vec2(a.x, c.y)], closed: true))] }
                    poly = [a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)]
                }
                poly = RG.dedupe(poly, closed: true)
                guard poly.count >= 3, abs(GeometryOps.signedArea(poly)) > 1e-9 else { throw CommandError.invalid("The boundary must enclose an area.") }
                each { BlockClip.setBoundary(poly, on: &$0); $0.props[BlockClip.offProp] = nil }
            }
            ed.print("\(ids.count) reference(s) updated.")
        }
    }

    // MARK: - Block tables / lookup (BLK-025, BLK-026)

    static var btable: CommandDef {
        CommandDef("BTABLE", aliases: ["BLOCKTABLE", "BLOOKUP", "LOOKUPTABLE"], category: "Blocks", summary: "Block properties table: named sets of dynamic parameter values (Add/Delete/List) applied to references by name (Apply).") { ed in
            let w = try await ed.getWord("Enter block name or select a block reference", keywords: [])
            var block: String? = nil
            if let w, let id = Int(w.trimmingCharacters(in: CharacterSet(charactersIn: "#"))), let e = ed.doc.entity(id), case .insert(let ins) = e.geometry {
                block = e.props[DynamicBlocks.baseProp] ?? ins.block
            } else if let w { block = ed.doc.blocks.keys.first { $0.caseInsensitiveCompare(w) == .orderedSame } }
            guard let b = block, ed.doc.blocks[b] != nil else { throw CommandError.invalid("Block not found.") }
            let params = DynamicBlocks.params(b, ed.doc)
            while true {
                guard let k = try await ed.getKeyword("Block table of \(b) [Add/Delete/List/Apply/eXit]", ["Add", "Delete", "List", "Apply", "eXit"], defaultValue: "eXit"), k != "eXit" else { return }
                var rows = BlockTables.rows(b, ed.doc)
                switch k {
                case "Add":
                    guard let name = try await ed.getWord("Row name") else { continue }
                    var vals: [String: Double] = [:]
                    for p in params {
                        if let v = try await ed.getReal("Value of \(p.name)", defaultValue: p.base).value { vals[p.name] = v }
                    }
                    if params.isEmpty { ed.print("The block has no dynamic parameters (BPARAMETER)."); continue }
                    rows.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    rows.append(BlockTables.Row(name: name, values: vals))
                    BlockTables.setRows(b, rows, &ed.doc)
                case "Delete":
                    guard let name = try await ed.getWord("Row name") else { continue }
                    rows.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    BlockTables.setRows(b, rows, &ed.doc)
                case "List":
                    if rows.isEmpty { ed.print("No rows.") }
                    for r in rows { ed.print("  \(r.name): \(DynamicBlocks.valuesText(r.values))") }
                case "Apply":
                    guard let name = try await ed.getWord("Row name") else { continue }
                    let refs = try await ed.getEntitySelection("Select references of \(b)")
                    ed.selection = []
                    var n = 0
                    for id in refs { if let i = ed.doc.entityIndex(id), BlockTables.apply(row: name, toInsert: i, &ed.doc) { n += 1 } }
                    ed.print("\(n) reference(s) set to \(name).")
                default: break
                }
            }
        }
    }

    // MARK: - Bullets and numbering (ANN-005)

    static var textList: CommandDef {
        CommandDef("TEXTLIST", aliases: ["BULLETS", "NUMBERING", "MTEXTLIST"], category: "Annotate", summary: "Adds bullets, numbers or letters to the paragraphs of multiline text (or removes them).") { ed in
            let ids = try await DraftDetailCommands.textSelection(ed)
            let k = try await ed.getKeyword("List style [Bullet/Number/Letter/Uppercase/Off]", ["Bullet", "Number", "Letter", "Uppercase", "Off"], defaultValue: "Bullet") ?? "Bullet"
            let style: TextLists.Style = ["Bullet": .bullet, "Number": .number, "Letter": .letter, "Uppercase": .upperLetter][k] ?? .off
            var start = 1
            if style != .bullet && style != .off { start = try await ed.getInteger("Start at", defaultValue: 1) ?? 1 }
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .text(var t) = ed.doc.entities[i].geometry else { continue }
                t.content = TextLists.apply(t.content, style: style, start: start)
                ed.doc.entities[i].geometry = .text(t)
            }
        }
    }

    // MARK: - Colour books (LAY-030)

    static var colorBook: CommandDef {
        CommandDef("COLORBOOK", aliases: ["COLOURBOOK", "COLORBOOKS"], category: "Properties", summary: "Colour books (open palettes): list books and colours, apply a colour to objects or set it current (Book$Colour).") { ed in
            guard let k = try await ed.getKeyword("Colour books [List/Apply/Current]", ["List", "Apply", "Current"], defaultValue: "List") else { return }
            if k == "List" {
                let w = try await ed.getWord("Book name or <all books>")
                if let w, let bk = ColorBooks.books.keys.first(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) {
                    for c in ColorBooks.books[bk] ?? [] { ed.print("  \(bk)$\(c.name)  \(ColorBooks.color(c).text)") }
                } else { for n in ColorBooks.names { ed.print("  \(n) (\(ColorBooks.books[n]?.count ?? 0) colours)") } }
                return
            }
            guard let ref = try await ed.getString("Colour (Book$Colour, e.g. Archi Materials$Brick)"), let hit = ColorBooks.lookup(ref) else { throw CommandError.invalid("Unknown colour book entry.") }
            let tag = "\(hit.book)$\(hit.entry.name)"
            if k == "Current" {
                ed.doc.setVariable("CECOLOR", ColorBooks.color(hit.entry).text)
                ed.doc.setVariable("CECOLORBOOK", tag)
                ed.print("Current colour: \(tag)")
                return
            }
            let ids = try await ed.getEntitySelection("Select objects")
            ed.selection = []
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].color = ColorBooks.color(hit.entry); ed.doc.entities[i].props[ColorBooks.prop] = tag } }
            ed.print("\(ids.count) object(s) set to \(tag).")
        }
    }

    // MARK: - Dimension extras (ANN-040, ANN-039, ANN-036)

    @MainActor static func dimensions(_ ed: Editor, _ msg: String = "Select dimensions") async throws -> [EntityID] {
        let ids = try await ed.getEntitySelection(msg).filter { if case .dimension? = ed.doc.entity($0)?.geometry { return true }; return false }
        ed.selection = []
        guard !ids.isEmpty else { throw CommandError.invalid("No dimensions selected.") }
        return ids
    }

    static var dimTol: CommandDef {
        CommandDef("DIMTOLERANCE", aliases: ["DIMTOLS", "DTOL"], category: "Annotate", summary: "Adds tolerances to dimensions: Symmetrical ±t, Deviation +u/−l, Limits (upper/lower values), Basic (boxed) or None.") { ed in
            let ids = try await dimensions(ed)
            let k = try await ed.getKeyword("Tolerance [Symmetrical/Deviation/Limits/Basic/None]", ["Symmetrical", "Deviation", "Limits", "Basic", "None"], defaultValue: "Symmetrical") ?? "None"
            var v: String? = nil
            switch k {
            case "Symmetrical":
                let t = try await ed.getReal("Enter tolerance value", defaultValue: 0.1).value ?? 0.1
                v = "sym:" + fmt(abs(t), 9)
            case "Deviation", "Limits":
                let u = try await ed.getReal("Enter upper value", defaultValue: 0.1).value ?? 0.1
                let l = try await ed.getReal("Enter lower value", defaultValue: u).value ?? u
                v = (k == "Deviation" ? "dev:" : "limits:") + fmt(abs(u), 9) + "," + fmt(abs(l), 9)
            case "Basic": v = "basic"
            default: v = nil
            }
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DimExtras.toleranceProp] = v } }
        }
    }

    static var dimAlt: CommandDef {
        CommandDef("DIMALTUNITS", aliases: ["DIMALTU", "DUALUNITS"], category: "Annotate", summary: "Shows alternate units on dimensions, e.g. mm [in]: factor, decimals, suffix (Off removes them).") { ed in
            let ids = try await dimensions(ed)
            let r = try await ed.getReal("Enter alternate units factor or [Inches/Millimetres/Off]", defaultValue: 1 / 25.4, keywords: ["Inches", "Millimetres", "Off"])
            var factor = 1 / 25.4, suffix = "\""
            switch r {
            case .keyword("Off"):
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DimExtras.alternateProp] = nil } }
                return
            case .keyword("Millimetres"): factor = 25.4; suffix = " mm"
            case .keyword("Inches"): break
            case .value(let f): guard f > 0 else { throw CommandError.invalid("The factor must be positive.") }; factor = f; suffix = ""
            default: break
            }
            let dec = try await ed.getInteger("Enter decimal places", defaultValue: 2) ?? 2
            suffix = try await ed.getString("Enter suffix", defaultValue: suffix) ?? suffix
            let v = "\(fmt(factor, 12)),\(max(0, min(8, dec))),\(suffix)"
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DimExtras.alternateProp] = v } }
        }
    }

    static var dimInspect: CommandDef {
        CommandDef("DIMINSPECT", aliases: ["INSPECTDIM"], category: "Annotate", summary: "Adds or removes an inspection frame (label | value | rate, round or angular ends) on dimensions.") { ed in
            let ids = try await dimensions(ed)
            let k = try await ed.getKeyword("Inspection [Round/Angular/None/Remove]", ["Round", "Angular", "None", "Remove"], defaultValue: "Round") ?? "Round"
            if k == "Remove" {
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DimExtras.inspectProp] = nil } }
                return
            }
            let label = try await ed.getString("Enter label (optional)", defaultValue: "") ?? ""
            let rate = try await ed.getString("Enter inspection rate", defaultValue: "100%") ?? "100%"
            let v = [k.lowercased(), label, rate].joined(separator: ";")
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DimExtras.inspectProp] = v } }
        }
    }

    // MARK: - Layer descriptions (LAY-018)

    static var layDesc: CommandDef {
        CommandDef("LAYDESC", aliases: ["LAYERDESCRIPTION", "LAYERDESC"], category: "Layers", summary: "Sets or lists layer descriptions.") { ed in
            let w = try await ed.getWord("Enter layer name or [?]", defaultValue: ed.doc.currentLayer)
            guard let name = w else { return }
            if name == "?" {
                for l in ed.doc.layers { ed.print("  \(l.name)" + (l.description.isEmpty ? "" : " — \(l.description)")) }
                return
            }
            guard let i = ed.doc.layers.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw CommandError.invalid("Layer \(name) not found.") }
            let d = try await ed.getString("Enter description", defaultValue: ed.doc.layers[i].description) ?? ed.doc.layers[i].description
            ed.doc.layers[i].description = d
        }
    }

    // MARK: - Text columns (ANN-006) and stacks (ANN-007)

    static var textColumns: CommandDef {
        CommandDef("MTEXTCOLUMNS", aliases: ["TEXTCOLUMNS"], category: "Annotate", summary: "Sets columns on multiline text: Static (count, balanced), Dynamic (fixed column height) or No columns.") { ed in
            let ids = try await DraftDetailCommands.textSelection(ed)
            let k = try await ed.getKeyword("Column type [Static/Dynamic/No columns]", ["Static", "Dynamic", "No"], defaultValue: "Static") ?? "No"
            if k == "No" {
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DraftRendering.textColumnsProp] = nil } }
                return
            }
            var n = 2, height = 0.0
            if k == "Static" {
                guard let c = try await ed.getInteger("Enter number of columns", defaultValue: 2), c >= 1, c <= 100 else { throw CommandError.invalid("Enter 1 to 100 columns.") }
                n = c
            } else {
                height = try await ed.getPositive("Specify column height", defaultValue: 1000)
                n = try await ed.getInteger("Enter number of columns", defaultValue: 2) ?? 2
            }
            let gutter = try await ed.getPositive("Specify gutter width", defaultValue: ed.settings.textHeight, allowZero: true)
            var skipped = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .text(let t) = ed.doc.entities[i].geometry else { continue }
                guard t.width > 0 else { skipped += 1; continue }
                ed.doc.entities[i].props[DraftRendering.textColumnsProp] = "\(max(1, n)),\(fmt(gutter)),\(fmt(height))"
            }
            if skipped > 0 { ed.print("\(skipped) single-line text object(s) skipped (columns need a width).") }
        }
    }

    static var autoStack: CommandDef {
        CommandDef("AUTOSTACK", aliases: ["TEXTSTACK", "STACK"], category: "Annotate", summary: "Stacks typed fractions in text (1/2, 3#4, 1^2) or unstacks them.") { ed in
            let ids = try await DraftDetailCommands.textSelection(ed)
            let k = try await ed.getKeyword("[Stack/Unstack]", ["Stack", "Unstack"], defaultValue: "Stack") ?? "Stack"
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .text(var t) = ed.doc.entities[i].geometry else { continue }
                t.content = k == "Stack" ? TextStacks.autoStack(t.content) : TextStacks.unstack(t.content)
                ed.doc.entities[i].geometry = .text(t)
            }
        }
    }
}
