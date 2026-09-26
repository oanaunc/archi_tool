// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Image clipping / adjustment (DRW-085/086), tag label templates (ANN-080), linked BIM models (BLK-035) and
/// copy/monitor from links (BLK-036).
public enum LinkImageCommands {
    static var all: [CommandDef] { [imageClip, imageAdjust, imageFrame, tagLabel, modelLink, copyMonitor, materialHatch, materialPattern] }

    // MARK: Images

    @MainActor static func pickImage(_ ed: Editor, _ msg: String = "Select image to clip") async throws -> Int {
        guard let id = try await ed.getEntity(msg), let i = ed.doc.entityIndex(id), case .image = ed.doc.entities[i].geometry else {
            throw CommandError.invalid("Select an image.")
        }
        return i
    }

    static var imageClip: CommandDef {
        CommandDef("IMAGECLIP", aliases: ["ICL", "CLIPIMAGE"], category: "Blocks",
                   summary: "Clips an image to a rectangular or polygonal boundary: ON/OFF, Delete, New boundary, Invert.") { ed in
            let i = try await pickImage(ed)
            let has = ImageDisplay.clipUV(ed.doc.entities[i]) != nil
            let k = try await ed.getKeyword("Enter image clipping option", ["ON", "OFF", "Delete", "New", "Invert"], defaultValue: "New") ?? "New"
            switch k {
            case "ON", "OFF":
                guard has else { throw CommandError.invalid("The image has no clipping boundary.") }
                ed.doc.entities[i].props[ImageDisplay.clipOnProp] = k == "OFF" ? "0" : nil
                ed.print("Image clipping \(k == "ON" ? "on" : "off").")
            case "Delete":
                ImageDisplay.removeClip(&ed.doc.entities[i]); ed.print("Clipping boundary deleted.")
            case "Invert":
                guard has else { throw CommandError.invalid("The image has no clipping boundary.") }
                let inv = ed.doc.entities[i].props[ImageDisplay.clipInvertProp] == "1"
                ed.doc.entities[i].props[ImageDisplay.clipInvertProp] = inv ? nil : "1"
                ed.print(inv ? "Outside of the boundary hidden." : "Inside of the boundary hidden.")
            default:
                let t = try await ed.getKeyword("Enter clipping type", ["Polygonal", "Rectangular"], defaultValue: "Rectangular") ?? "Rectangular"
                var pts: [Vec2]
                if t == "Rectangular" {
                    let a = try await ed.requirePoint("Specify first corner point")
                    let b = try await ed.requirePoint("Specify opposite corner point", base: a) { p in [.polyline(PolylineGeom(points: BBox2(points: [a, p]).corners, closed: true))] }
                    pts = BBox2(points: [a, b]).corners
                } else {
                    pts = [try await ed.requirePoint("Specify first point")]
                    while true {
                        let cur = pts
                        guard let p = try await ed.getPoint("Specify next point or [Undo]", base: pts.last, keywords: ["Undo"], preview: { q in [.polyline(PolylineGeom(points: cur + [q], closed: cur.count >= 2))] }).point else {
                            if pts.count >= 3 { break }
                            throw CommandError.invalid("A polygonal boundary needs at least 3 points.")
                        }
                        pts.append(p)
                    }
                }
                guard ImageDisplay.setClip(&ed.doc.entities[i], boundary: pts) else { throw CommandError.invalid("The boundary does not overlap the image.") }
                ed.print("Image clipped to a \(t.lowercased()) boundary.")
            }
        }
    }

    static var imageAdjust: CommandDef {
        CommandDef("IMAGEADJUST", aliases: ["IAD", "-IMAGEADJUST"], category: "Blocks",
                   summary: "Adjusts the brightness, contrast and fade (0–100) of images; Reset restores the defaults.") { ed in
            let ids = try await ed.getSelection("Select image(s)").filter { id in if case .image? = ed.doc.entity(id)?.geometry { return true }; return false }
            guard !ids.isEmpty else { throw CommandError.invalid("No images selected.") }
            var a = ImageDisplay.adjustment(ed.doc.entity(ids[0])!)
            while true {
                guard let k = try await ed.getKeyword("Enter image adjustment option [Brightness/Contrast/Fade/Reset] (B \(fmt(a.brightness)), C \(fmt(a.contrast)), F \(fmt(a.fade)))",
                                                      ["Brightness", "Contrast", "Fade", "Reset"], defaultValue: nil) else { break }
                if k == "Reset" { a = ImageDisplay.Adjustment(); continue }
                let cur = k == "Brightness" ? a.brightness : k == "Contrast" ? a.contrast : a.fade
                guard let v = try await ed.getReal("Enter \(k.lowercased()) value (0-100)", defaultValue: cur).value else { continue }
                guard v >= 0, v <= 100 else { ed.print("Value must be between 0 and 100."); continue }
                switch k { case "Brightness": a.brightness = v; case "Contrast": a.contrast = v; default: a.fade = v }
            }
            for id in ids { if let i = ed.doc.entityIndex(id) { ImageDisplay.setAdjustment(a, on: &ed.doc.entities[i]) } }
            ed.print("\(ids.count) image(s): brightness \(fmt(a.brightness)), contrast \(fmt(a.contrast)), fade \(fmt(a.fade)).")
        }
    }

    static var imageFrame: CommandDef {
        CommandDef("IMAGEFRAME", category: "Blocks", summary: "Image clip frames: 0 hidden, 1 shown and plotted, 2 shown but not plotted.") { ed in
            let cur = ed.doc.variable(ImageDisplay.frameVariable).flatMap(Int.init) ?? 1
            guard let v = try await ed.getInteger("Enter image frame setting [0/1/2]", defaultValue: cur) else { return }
            guard (0...2).contains(v) else { throw CommandError.invalid("Enter 0, 1 or 2.") }
            ed.doc.setVariable(ImageDisplay.frameVariable, "\(v)")
        }
    }

    // MARK: Tags

    /// Name of the label-only tag family holding a template.
    static func labelFamily(_ template: String, _ doc: inout ArchiDocument) -> String {
        if let f = doc.families.first(where: { $0.category == "Tag" && $0.symbolic.isEmpty && $0.label == template && $0.name.hasPrefix("Label ") }) { return f.name }
        var n = 1
        while doc.family(named: "Label \(n)") != nil { n += 1 }
        var f = FamilyDefinition(name: "Label \(n)", category: "Tag", description: "Tag label: " + template)
        f.label = template
        doc.families.append(f)
        return f.name
    }

    static var tagLabel: CommandDef {
        CommandDef("TAGLABEL", aliases: ["EDITLABEL", "TAGFORMAT"], category: "Annotate",
                   summary: "Tag labels linked to element parameters: Label template with {Parameter} fields, single Field, Annotative paper height, List.") { ed in
            let tags = try await ed.getSelection("Select tags").filter { ed.doc.entity($0)?.props["tagOf"] != nil }
            guard !tags.isEmpty else { throw CommandError.invalid("No tags selected.") }
            let k = try await ed.getKeyword("Enter an option", ["Label", "Field", "Annotative", "List"], defaultValue: "Label") ?? "Label"
            switch k {
            case "List":
                for id in tags {
                    guard let e = ed.doc.entity(id), let el = e.props["tagOf"].flatMap(Int.init).flatMap(ed.doc.element) else { continue }
                    let f = e.props["tagField"] ?? "mark"
                    let tpl = f.lowercased().hasPrefix("family:") ? ed.doc.family(named: String(f.dropFirst(7)))?.label ?? f : "{\(f)}"
                    ed.print("  #\(id) → \(el.name.isEmpty ? el.typeName : el.name) #\(el.id): \(tpl) = \"\(Annotations.tagText(el, field: f, doc: ed.doc).replacingOccurrences(of: "\n", with: " | "))\"")
                }
            case "Field":
                guard let f = try await ed.getWord("Enter parameter name (mark, type, name, number, area, size, keynote or any element parameter)", defaultValue: "mark") else { return }
                for id in tags { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["tagField"] = f } }
                ed.print("\(tags.count) tag(s) show \(f).")
            case "Annotative":
                let h = try await ed.getPositive("Specify paper text height (mm)", defaultValue: ed.doc.entity(tags[0])?.props["paperHeight"].flatMap(Double.init) ?? 2.5)
                for id in tags { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["annotative"] = "1"; ed.doc.entities[i].props["paperHeight"] = fmt(h, 8) } }
                Annotative.updateAll(&ed.doc)
                ed.print("\(tags.count) tag(s) annotative: \(fmt(h)) mm on paper at every annotation scale.")
            default:
                guard let t = try await ed.getString("Enter label template (e.g. {Name}\\n{Area})"), !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                guard t.contains("{") && t.contains("}") else { throw CommandError.invalid("The template needs at least one {Parameter} field.") }
                let fam = labelFamily(t, &ed.doc)
                for id in tags { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["tagField"] = "family:" + fam } }
                ed.print("\(tags.count) tag(s) use label \(t).")
            }
            // Keep the stored text in step with the live label (used by exports that read the entity text).
            for id in tags {
                guard let i = ed.doc.entityIndex(id), case .text(var tx) = ed.doc.entities[i].geometry,
                      let el = ed.doc.entities[i].props["tagOf"].flatMap(Int.init).flatMap(ed.doc.element) else { continue }
                tx.content = Annotations.tagText(el, field: ed.doc.entities[i].props["tagField"] ?? "mark", doc: ed.doc)
                ed.doc.entities[i].geometry = .text(tx)
            }
        }
    }

    // MARK: Linked models

    static var modelLink: CommandDef {
        CommandDef("RVTLINK", aliases: ["LINKMODEL", "LINKIFC", "MANAGELINKS", "MODELLINK"], category: "Blocks",
                   summary: "Linked BIM models (.archi/IFC): list, Attach (origin-to-origin, shared coordinates or a point), Reload, Unload, Detach, Position, Notify.") { ed in
            let base = ed.fileURL?.deletingLastPathComponent()
            let w = try await ed.getWord("Enter an option", defaultValue: "?", keywords: ["?", "Attach", "Reload", "Unload", "Detach", "Position", "Notify"]) ?? "?"
            @MainActor func names(_ msg: String) async throws -> [String] {
                let pat = try await ed.getWord(msg, defaultValue: "*") ?? "*"
                return LinkedModels.all(ed.doc).map(\.name).filter { n in pat.split(separator: ",").contains { SettingsCommands.glob(String($0).trimmingCharacters(in: .whitespaces), n) } }
            }
            @MainActor func attach(_ path: String) async throws {
                let pk = try await ed.getKeyword("Positioning", ["Origin", "Shared", "Point"], defaultValue: "Origin") ?? "Origin"
                var off = Vec2.zero, rot = 0.0
                if pk == "Point" {
                    off = try await ed.requirePoint("Specify insertion point of the link origin")
                    rot = try await ed.getAngle("Specify rotation angle", base: off, defaultValue: 0).value ?? 0
                }
                let n = try LinkedModels.attach(&ed.doc, path: path, placement: ModelLink.Placement(rawValue: pk.lowercased()) ?? .origin,
                                                offset: off, rotation: rot, base: base, host: ed.fileURL)
                ed.print("Linked \(n): \(LinkedModels.objectCount(ed.doc, name: n)) objects.")
            }
            do {
                switch w {
                case "?":
                    let list = LinkedModels.all(ed.doc)
                    if list.isEmpty { ed.print("No linked models."); return }
                    let changed = Set(LinkedModels.changed(ed.doc, base: base)), missing = Set(LinkedModels.missing(ed.doc, base: base))
                    for l in list {
                        let st = missing.contains(l.name) ? "Not found" : !l.loaded ? "Unloaded" : changed.contains(l.name) ? "Needs reloading" : "Loaded"
                        ed.print("  \(l.name)  \(l.placement.rawValue)  \(st)  \(LinkedModels.objectCount(ed.doc, name: l.name)) objects  \(l.path)")
                    }
                case "Attach":
                    guard let path = try await ed.getWord("Enter model file name (.archi or .ifc)") else { return }
                    try await attach(path)
                case "Reload":
                    let ns = try await names("Enter link name(s) to reload")
                    let r = try LinkedModels.reload(&ed.doc, names: ns, base: base)
                    ed.print("\(r.count) link(s) reloaded.")
                    for n in r { try reportMonitor(ed, link: n, base: base) }
                case "Unload":
                    for n in try await names("Enter link name(s) to unload") { try LinkedModels.unload(&ed.doc, name: n); ed.print("\(n) unloaded.") }
                case "Detach":
                    let ns = try await names("Enter link name(s) to detach")
                    for n in ns { try LinkedModels.detach(&ed.doc, name: n) }
                    ed.print("\(ns.count) link(s) detached.")
                case "Position":
                    guard let n = try await ed.getWord("Enter link name"), let l = LinkedModels.named(n, ed.doc) else { throw CommandError.invalid("Link not found.") }
                    let p = try await ed.getPoint("Specify new position of the link origin", base: l.offset).point ?? l.offset
                    let r = try await ed.getAngle("Specify rotation angle", base: p, defaultValue: l.rotation).value ?? l.rotation
                    try LinkedModels.reposition(&ed.doc, name: l.name, offset: p, rotation: r, base: base)
                case "Notify":
                    let c = LinkedModels.changed(ed.doc, base: base), m = LinkedModels.missing(ed.doc, base: base)
                    if c.isEmpty && m.isEmpty { ed.print("All linked models are up to date.") }
                    if !c.isEmpty { ed.print("Changed since loaded: \(c.joined(separator: ", ")) — use RVTLINK Reload.") }
                    if !m.isEmpty { ed.print("Not found: \(m.joined(separator: ", ")).") }
                default:
                    try await attach(w)
                }
            } catch let e as LinkedModels.LinkError { throw CommandError.invalid(e.localizedDescription) }
        }
    }

    @MainActor static func reportMonitor(_ ed: Editor, link: String, base: URL?) throws {
        guard let l = LinkedModels.named(link, ed.doc), MonitorLinks.pairs(ed.doc).contains(where: { $0.link == l.name }) else { return }
        let src = try LinkedModels.read(Xrefs.resolve(l.path, base: base))
        let d = MonitorLinks.check(ed.doc, link: l, source: src)
        if d.isEmpty { ed.print("Monitored levels and grids of \(l.name) are in step.") }
        else { ed.print("Coordination review — \(d.count) change(s) in \(l.name):"); d.forEach { ed.print("  " + $0.message) } }
    }

    static var copyMonitor: CommandDef {
        CommandDef("COPYMONITOR", aliases: ["COPYMON", "COORDINATIONREVIEW"], category: "Blocks",
                   summary: "Copy/monitor levels and grids from a linked model: Copy, Check (coordination review), Update, Release.") { ed in
            let base = ed.fileURL?.deletingLastPathComponent()
            let k = try await ed.getKeyword("Enter an option", ["Copy", "Check", "Update", "Release"], defaultValue: "Copy") ?? "Copy"
            let def = LinkedModels.all(ed.doc).first?.name
            guard let n = try await ed.getWord("Enter link name", defaultValue: def), let l = LinkedModels.named(n, ed.doc) else { throw CommandError.invalid("Link not found.") }
            do {
                switch k {
                case "Release":
                    MonitorLinks.release(&ed.doc, link: l.name); ed.print("Stopped monitoring \(l.name).")
                case "Check":
                    try reportMonitor(ed, link: l.name, base: base)
                case "Update":
                    let src = try LinkedModels.read(Xrefs.resolve(l.path, base: base))
                    let c = MonitorLinks.update(&ed.doc, link: l, source: src)
                    ed.print("\(c) monitored item(s) updated from \(l.name).")
                default:
                    let what = try await ed.getKeyword("Copy", ["Levels", "Grids", "All"], defaultValue: "All") ?? "All"
                    let src = try LinkedModels.read(Xrefs.resolve(l.path, base: base))
                    let r = MonitorLinks.copy(&ed.doc, link: l, source: src, levels: what != "Grids", grids: what != "Levels")
                    ed.print("\(r.copied) copied, \(r.monitored) existing item(s) monitored from \(l.name).")
                }
            } catch let e as LinkedModels.LinkError { throw CommandError.invalid(e.localizedDescription) }
        }
    }

    // MARK: Material fill patterns

    static var materialHatch: CommandDef {
        CommandDef("MATHATCH", aliases: ["MATERIALHATCH", "HATCHMATERIAL"], category: "Annotate",
                   summary: "Binds hatches to a material: they show its cut or surface pattern (and optionally its colour) and follow later pattern changes.") { ed in
            let ids = try await ed.getSelection("Select hatches").filter { id in if case .hatch? = ed.doc.entity(id)?.geometry { return true }; return false }
            guard !ids.isEmpty else { throw CommandError.invalid("No hatches selected.") }
            guard let name = try await ed.getWord("Enter material name or [?]", defaultValue: ed.doc.entity(ids[0])?.props[MaterialPatterns.prop] ?? "Concrete") else { return }
            if name == "?" {
                for m in ed.doc.materials { ed.print("  \(m.name): cut \(m.cutPattern), surface \(MaterialPatterns.surfacePattern(m.name, doc: ed.doc) ?? "none")") }
                return
            }
            guard let m = ed.doc.material(name) else { throw CommandError.invalid("Material \(name) not found.") }
            let k = try await ed.getKeyword("Pattern", ["Cut", "Surface"], defaultValue: "Cut") ?? "Cut"
            let shade = (try await ed.getKeyword("Fill with the material colour?", ["Yes", "No"], defaultValue: "No") ?? "No") == "Yes"
            let kind: MaterialPatterns.Kind = k == "Surface" ? .surface : .cut
            if kind == .surface && MaterialPatterns.surfacePattern(m.name, doc: ed.doc) == nil { ed.print("\(m.name) has no surface pattern yet (MATPATTERN); shown as a solid fill.") }
            var n = 0
            for id in ids { if let i = ed.doc.entityIndex(id), MaterialPatterns.bind(&ed.doc.entities[i], material: m.name, kind: kind, shade: shade, doc: ed.doc) { n += 1 } }
            ed.print("\(n) hatch(es) show the \(kind.rawValue) pattern of \(m.name).")
        }
    }

    static var materialPattern: CommandDef {
        CommandDef("MATPATTERN", aliases: ["MATERIALPATTERN", "FILLPATTERNS"], category: "Annotate",
                   summary: "Sets the cut or surface fill pattern of a material; walls and bound hatches update everywhere.") { ed in
            guard let name = try await ed.getWord("Enter material name"), let m = ed.doc.material(name) else { throw CommandError.invalid("Material not found.") }
            let k = try await ed.getKeyword("Pattern", ["Cut", "Surface"], defaultValue: "Cut") ?? "Cut"
            let kind: MaterialPatterns.Kind = k == "Surface" ? .surface : .cut
            let cur = MaterialPatterns.pattern(m.name, kind: kind, doc: ed.doc) ?? "None"
            guard let p = try await ed.getWord("Enter pattern name (\(kind == .surface ? "None, " : "")SOLID, ANSI31, AR-CONC …)", defaultValue: cur) else { return }
            let value: String? = p.caseInsensitiveCompare("None") == .orderedSame ? nil : p
            guard MaterialPatterns.setPattern(m.name, kind: kind, pattern: value, doc: &ed.doc) else { throw CommandError.invalid("Unknown pattern \(p).") }
            ed.print("\(m.name) \(kind.rawValue) pattern: \(value?.uppercased() ?? "none").")
        }
    }
}
