// Oanarina Archi Tool — GPL-3.0-or-later
// Round 11 BIM commands: reinforcement and steel connections.
import Foundation

enum Round11BIMCommands {
    static var all: [CommandDef] { [rebar, steelConnection] }

    @MainActor static func pickElement(_ ed: Editor, _ msg: String, _ ok: @escaping (BIMGeometry) -> Bool) async throws -> BIMElement? {
        guard case .pick(let pk) = try await ed.pickObject(msg, filter: { id in ed.doc.element(id).map { ok($0.geometry) } ?? false }) else { return nil }
        return ed.doc.element(pk.id)
    }

    static var rebar: CommandDef {
        CommandDef("REBAR", aliases: ["REINFORCEMENT", "RB", "REBARSET"], category: "Structure", summary: "Reinforcement in a concrete beam (Bottom/Top bars, Links), column (Vertical bars, Links) or slab (X/Y mesh): cover, bar diameter, count or spacing, BS 8666 shape codes; List prints the bar schedule.") { ed in
            let first = try await ed.getKeyword("Rebar [Add/List]", ["Add", "List"], defaultValue: "Add") ?? "Add"
            if first == "List" {
                let sets = ed.doc.elements.filter { $0.props["rebarHost"] != nil }
                if sets.isEmpty { ed.print("No reinforcement."); return }
                ed.print("Mark  Host   Shape  Ø    No.  Length   Weight kg")
                var total = 0.0
                for s in sets {
                    let w = s.props["weightKg"].flatMap(Double.init) ?? 0
                    total += w
                    ed.print("\(s.props["mark"] ?? "-")  #\(s.props["rebarHost"] ?? "")  \(s.props["shapeCode"] ?? "")  \(s.props["barDiameter"] ?? "")  \(s.props["barCount"] ?? "")  \(s.props["barLength"] ?? "")  \(fmt(w, 2))")
                }
                ed.print("Total reinforcement: \(fmt(total, 2)) kg.")
                return
            }
            guard let host = try await pickElement(ed, "Select a concrete beam, column or slab", { g in
                switch g { case .beam, .slab: return true; case .column(let c): return StructuralProfiles.section(c.profile) == nil; default: return false } }) else { return }
            let sets: [String]
            switch host.geometry {
            case .beam: sets = ["Bottom", "Top", "Links"]
            case .column: sets = ["Vertical", "Links"]
            default: sets = ["X", "Y"]
            }
            let set = try await ed.getKeyword("Bar set [" + sets.joined(separator: "/") + "]", sets, defaultValue: sets[0]) ?? sets[0]
            let isLinks = set == "Links"
            let dia = try await ed.getPositive("Bar diameter", defaultValue: isLinks ? 8 : (set == "X" || set == "Y" ? 12 : 16))
            let cover = try await ed.getPositive("Cover", defaultValue: ed.variableDouble("REBARCOVER", 30))
            var p = Rebar.Params(set: set.lowercased(), diameter: dia, cover: cover)
            if isLinks || set == "X" || set == "Y" {
                p.spacing = try await ed.getPositive("Spacing", defaultValue: isLinks ? 200 : 150)
                if isLinks { p.linkDiameter = dia; p.diameter = dia }
            } else {
                p.count = max(2, try await ed.getInteger("Number of bars", defaultValue: set == "Vertical" ? 4 : (set == "Top" ? 2 : 3)) ?? 3)
                p.linkDiameter = try await ed.getPositive("Link diameter (for the bar positions)", defaultValue: 8, allowZero: true)
                if set == "Bottom" || set == "Top" { p.hook = try await ed.getPositive("End leg length (0 = straight, shape 00; else shape 11)", defaultValue: 0, allowZero: true) }
            }
            ed.doc.setVariable("REBARCOVER", fmt(cover))
            guard let id = Rebar.add(host: host.id, p, doc: &ed.doc), let el = ed.doc.element(id) else { throw CommandError.invalid("The bars do not fit in the member with that cover.") }
            ed.selection = [id]
            ed.print("Rebar \(el.props["mark"] ?? ""): shape \(el.props["shapeCode"] ?? ""), \(el.props["barCount"] ?? "") × Ø\(fmt(dia)), bar length \(el.props["barLength"] ?? ""), \(el.props["weightKg"] ?? "") kg.")
        }
    }

    static var steelConnection: CommandDef {
        CommandDef("STEELCONNECTION", aliases: ["CONNECTION", "BASEPLATE", "ENDPLATE", "STEELCONN"], category: "Structure", summary: "Steel connections sized from the member section: Base plate with anchor bolts or Cap plate on a column, End plate with bolts on a beam end; they follow the member.") { ed in
            let k = try await ed.getKeyword("Connection [BasePlate/CapPlate/EndPlate]", ["BasePlate", "CapPlate", "EndPlate"], defaultValue: "BasePlate") ?? "BasePlate"
            let kind: SteelConnections.Kind = k == "EndPlate" ? .endPlate : (k == "CapPlate" ? .capPlate : .basePlate)
            guard let host = try await pickElement(ed, kind == .endPlate ? "Select a beam" : "Select a column", { g in
                if case .beam = g { return kind == .endPlate }; if case .column = g { return kind != .endPlate }; return false }) else { return }
            var p = SteelConnections.Params(kind: kind)
            if kind == .endPlate { p.atEnd = (try await ed.getKeyword("At beam [Start/End]", ["Start", "End"], defaultValue: "End") ?? "End") == "End" }
            p.thickness = try await ed.getPositive("Plate thickness", defaultValue: kind == .endPlate ? 15 : 20)
            p.edge = try await ed.getPositive("Plate projection beyond the section", defaultValue: 60, allowZero: true)
            p.boltDiameter = try await ed.getPositive("Bolt diameter", defaultValue: kind == .basePlate ? 24 : 20)
            guard let id = SteelConnections.add(host: host.id, p, doc: &ed.doc), let el = ed.doc.element(id) else { throw CommandError.invalid("The connection cannot be placed on that member.") }
            ed.selection = [id]
            ed.print("\(el.name): \(el.props["boltCount"] ?? "") bolts Ø\(fmt(p.boltDiameter)), plate \(el.props["plateWeightKg"] ?? "") kg.")
        }
    }
}
