// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Commands for line styles (LAY-034), lineweight tables by scale (LAY-035), pen sets (LAY-036) and graphic override
/// filters (LAY-037). See `GraphicStyles`.
public enum GraphicStyleCommands {
    static var all: [CommandDef] { [lineStyles, lwTable, penSets, graphicFilters] }

    static func parseLineweight(_ s: String) -> Double? {
        if s.lowercased() == "bylayer" || s == "." { return nil }
        guard let v = Double(s), v >= 0, v <= 5 else { return nil }
        return v
    }

    static var lineStyles: CommandDef {
        CommandDef("LINESTYLES", aliases: ["LSTYLES", "-LINESTYLES"], category: "Settings", summary: "Named line styles (weight, colour, pattern): New/Edit/Delete/List, Apply to objects, set a Layer's line style.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["New", "Edit", "Delete", "List", "Apply", "LAyer"], defaultValue: "List") ?? "List"
            switch k {
            case "New", "Edit":
                guard let n = try await ed.getWord("Line style name"), BlockCommands.validName(n) else { throw CommandError.invalid("Invalid line style name.") }
                let existing = GraphicStyles.lineStyle(n, doc: ed.doc)
                if k == "New", existing != nil { throw CommandError.invalid("Line style \(n) already exists.") }
                if k == "Edit", existing == nil { throw CommandError.invalid("Line style \(n) not found.") }
                var s = existing ?? GraphicStyles.LineStyle(name: n)
                s.name = existing?.name ?? n
                let c = try await ed.getWord("Colour (ByLayer, index, #RRGGBB or name; . = unchanged)", defaultValue: s.color?.text ?? "ByLayer") ?? "."
                if c != "." {
                    if c.lowercased() == "bylayer" { s.color = nil } else if let cr = ColorRef.parse(c) { s.color = cr } else { throw CommandError.invalid("Unknown colour \(c).") }
                }
                let w = try await ed.getWord("Lineweight in mm (ByLayer)", defaultValue: s.lineweight.map { fmt($0, 4) } ?? "ByLayer") ?? "ByLayer"
                if w.lowercased() == "bylayer" { s.lineweight = nil } else if let v = parseLineweight(w) { s.lineweight = v } else { throw CommandError.invalid("Invalid lineweight \(w).") }
                let lt = try await ed.getWord("Line pattern (linetype name or ByLayer)", defaultValue: s.linetype ?? "ByLayer") ?? "ByLayer"
                if lt.lowercased() == "bylayer" { s.linetype = nil }
                else if let t = ed.doc.linetypes.first(where: { $0.name.caseInsensitiveCompare(lt) == .orderedSame }) { s.linetype = t.name }
                else { throw CommandError.invalid("Linetype \(lt) is not loaded.") }
                GraphicStyles.setLineStyle(s, doc: &ed.doc)
                ed.print("Line style \(s.name): " + (s.encoded.isEmpty ? "all ByLayer" : s.encoded.replacingOccurrences(of: ";", with: ", ")))
            case "Delete":
                guard let n = try await ed.getWord("Line style to delete"), GraphicStyles.lineStyle(n, doc: ed.doc) != nil else { throw CommandError.invalid("Line style not found.") }
                GraphicStyles.deleteLineStyle(n, doc: &ed.doc)
                ed.print("Line style \(n) deleted.")
            case "Apply":
                guard let n = try await ed.getWord("Line style (ByLayer to remove)") else { return }
                let name: String?
                if n.lowercased() == "bylayer" { name = nil } else {
                    guard let s = GraphicStyles.lineStyle(n, doc: ed.doc) else { throw CommandError.invalid("Line style \(n) not found.") }
                    name = s.name
                }
                let ids = try await ed.getEntitySelection("Select objects")
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[GraphicStyles.lineStyleProp] = name } }
                ed.selection = []
                ed.print("\(ids.count) object(s) set to line style \(name ?? "ByLayer").")
            case "LAyer":
                guard let l = try await ed.getWord("Layer name"), let layer = ed.doc.layers.first(where: { $0.name.caseInsensitiveCompare(l) == .orderedSame }) else { throw CommandError.invalid("Layer not found.") }
                guard let n = try await ed.getWord("Line style for the layer (None)", defaultValue: GraphicStyles.layerLineStyle(layer.name, doc: ed.doc) ?? "None") else { return }
                if n.lowercased() == "none" { GraphicStyles.setLayerLineStyle(layer.name, nil, doc: &ed.doc); return }
                guard let s = GraphicStyles.lineStyle(n, doc: ed.doc) else { throw CommandError.invalid("Line style \(n) not found.") }
                GraphicStyles.setLayerLineStyle(layer.name, s.name, doc: &ed.doc)
                ed.print("Layer \(layer.name) uses line style \(s.name).")
            default:
                let names = GraphicStyles.lineStyleNames(ed.doc)
                if names.isEmpty { ed.print("No line styles."); return }
                for n in names { if let s = GraphicStyles.lineStyle(n, doc: ed.doc) { ed.print("  \(s.name): " + (s.encoded.isEmpty ? "ByLayer" : s.encoded.replacingOccurrences(of: ";", with: ", "))) } }
            }
        }
    }

    static var lwTable: CommandDef {
        CommandDef("LWTABLE", aliases: ["LWSCALETABLE"], category: "Settings", summary: "Lineweight table by view scale: lineweights are multiplied by the factor of the current annotation scale (Set/Clear/List).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Set", "Clear", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "Set":
                let cur = ed.doc.variable(GraphicStyles.lineweightTableVariable) ?? "50=1;100=0.7;200=0.5"
                guard let v = try await ed.getWord("Rows scale=factor separated by ; (e.g. 50=1;100=0.7)", defaultValue: cur) else { return }
                let rows = GraphicStyles.parseTable(v)
                guard !rows.isEmpty else { throw CommandError.invalid("No valid rows.") }
                ed.doc.setVariable(GraphicStyles.lineweightTableVariable, rows.map { "\(fmt($0.scale, 6))=\(fmt($0.factor, 6))" }.joined(separator: ";"))
            case "Clear": ed.doc.variables[GraphicStyles.lineweightTableVariable] = nil
            default:
                let rows = GraphicStyles.lineweightTable(ed.doc)
                if rows.isEmpty { ed.print("No lineweight table."); return }
                let s = Annotative.currentScale(ed.doc)
                for r in rows { ed.print("  1:\(fmt(r.scale)) → ×\(fmt(r.factor, 3))") }
                ed.print("Current scale 1:\(fmt(s)): ×\(fmt(GraphicStyles.lineweightFactor(rows, scale: s) ?? 1, 3))")
            }
        }
    }

    static var penSets: CommandDef {
        CommandDef("PENSETS", aliases: ["PENSET", "PENTABLE"], category: "Settings", summary: "Pen sets mapping pen numbers (colour indexes) to plotted weights and colours: New/Pen/Current/Display/Delete/List.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["New", "Pen", "Current", "Display", "Delete", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "New":
                guard let n = try await ed.getWord("Pen set name"), BlockCommands.validName(n) else { throw CommandError.invalid("Invalid pen set name.") }
                guard GraphicStyles.penSet(n, doc: ed.doc) == nil else { throw CommandError.invalid("Pen set \(n) already exists.") }
                // Default: pens 1–7 at increasing weights, others at 0.25.
                let std: [Int: Double] = [1: 0.18, 2: 0.25, 3: 0.35, 4: 0.5, 5: 0.7, 6: 1.0, 7: 0.25]
                var pens: [Int: GraphicStyles.Pen] = [:]
                for (i, w) in std { pens[i] = GraphicStyles.Pen(lineweight: w) }
                GraphicStyles.setPenSet(n, pens, doc: &ed.doc)
                ed.print("Pen set \(n) created.")
            case "Pen":
                guard let n = try await ed.getWord("Pen set name"), var pens = GraphicStyles.penSet(n, doc: ed.doc) else { throw CommandError.invalid("Pen set not found.") }
                guard let p = try await ed.getInteger("Pen number (1-255)"), (1...255).contains(p) else { throw CommandError.invalid("Pen numbers are 1-255.") }
                let w = try await ed.getPositive("Lineweight (mm)", defaultValue: pens[p]?.lineweight ?? 0.25, allowZero: true)
                let c = try await ed.getWord("Pen colour (. = object colour)", defaultValue: ".") ?? "."
                var pen = GraphicStyles.Pen(lineweight: w)
                if c != "." {
                    guard let cr = ColorRef.parse(c) else { throw CommandError.invalid("Unknown colour \(c).") }
                    pen.color = GraphicStyles.parsePens("1=0," + cr.text)[1]?.color
                }
                pens[p] = pen
                GraphicStyles.setPenSet(n, pens, doc: &ed.doc)
            case "Current":
                guard let n = try await ed.getWord("Current pen set (None)", defaultValue: ed.doc.variable(GraphicStyles.currentPenSetVariable) ?? "None") else { return }
                if n.lowercased() == "none" { ed.doc.variables[GraphicStyles.currentPenSetVariable] = nil; return }
                guard GraphicStyles.penSet(n, doc: ed.doc) != nil else { throw CommandError.invalid("Pen set \(n) not found.") }
                ed.doc.setVariable(GraphicStyles.currentPenSetVariable, n)
            case "Display":
                let on = try await ed.getYesNo("Show pen weights on screen?", defaultValue: ed.doc.variable(GraphicStyles.penSetDisplayVariable) == "1")
                ed.doc.setVariable(GraphicStyles.penSetDisplayVariable, on ? "1" : "0")
            case "Delete":
                guard let n = try await ed.getWord("Pen set name"), GraphicStyles.penSet(n, doc: ed.doc) != nil else { throw CommandError.invalid("Pen set not found.") }
                ed.doc.variables[(GraphicStyles.penSetPrefix + n).uppercased()] = nil
                if ed.doc.variable(GraphicStyles.currentPenSetVariable)?.caseInsensitiveCompare(n) == .orderedSame { ed.doc.variables[GraphicStyles.currentPenSetVariable] = nil }
            default:
                let names = GraphicStyles.penSetNames(ed.doc)
                if names.isEmpty { ed.print("No pen sets."); return }
                let cur = ed.doc.variable(GraphicStyles.currentPenSetVariable)?.uppercased()
                for n in names {
                    ed.print("\(n == cur ? "*" : " ") \(n): " + GraphicStyles.encodePens(GraphicStyles.penSet(n, doc: ed.doc) ?? [:]).replacingOccurrences(of: ";", with: " "))
                }
            }
        }
    }

    static var graphicFilters: CommandDef {
        CommandDef("GFILTERS", aliases: ["GRAPHICFILTERS", "DRAFTFILTERS"], category: "Settings", summary: "Rule-based graphic overrides for drafting objects: Add/Remove/Enable/Disable/List (field layer/type/color/linetype/lineweight/property).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Add", "Remove", "Enable", "Disable", "List"], defaultValue: "List") ?? "List"
            var fs = GraphicStyles.filters(ed.doc)
            func find(_ n: String) throws -> Int {
                guard let i = fs.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Filter \(n) not found.") }
                return i
            }
            switch k {
            case "Add":
                guard let n = try await ed.getWord("Filter name"), !n.isEmpty else { return }
                guard !fs.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Filter \(n) already exists.") }
                let t = try await ed.getWord("Object types, comma separated (* = all)", defaultValue: "*") ?? "*"
                let field = try await ed.getWord("Field (layer, type, color, linetype, lineweight or a property)", defaultValue: "layer") ?? "layer"
                let op = try await ed.getWord("Operator (\(GraphicStyles.ops.joined(separator: " ")))", defaultValue: "=") ?? "="
                guard GraphicStyles.ops.contains(op.lowercased()) else { throw CommandError.invalid("Unknown operator \(op).") }
                let v = try await ed.getWord("Value") ?? ""
                let o = try await ed.getWord("Override (hide, halftone, color:red, lw:0.5; separated by ;)", defaultValue: "halftone") ?? "halftone"
                guard let ov = VisibilityGraphics.parseOverride(o) else { throw CommandError.invalid("Invalid override \(o).") }
                let types = t == "*" ? [] : t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                fs.append(GraphicStyles.FilterRule(name: n, types: types, field: field, op: op.lowercased(), value: v, override: ov))
            case "Remove": guard let n = try await ed.getWord("Filter name") else { return }; fs.remove(at: try find(n))
            case "Enable", "Disable": guard let n = try await ed.getWord("Filter name") else { return }; fs[try find(n)].enabled = k == "Enable"
            default:
                if fs.isEmpty { ed.print("No graphic filters."); return }
                for f in fs {
                    ed.print("\(f.enabled ? " " : "-") \(f.name): \(f.types.isEmpty ? "all" : f.types.joined(separator: ",")) where \(f.field) \(f.op) \(f.value)")
                }
                return
            }
            GraphicStyles.setFilters(fs, doc: &ed.doc)
            ed.print("\(fs.count) graphic filter(s).")
        }
    }
}
