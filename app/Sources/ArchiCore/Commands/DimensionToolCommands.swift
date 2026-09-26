// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Equality constraint dimensions (ANN-046).
public enum DimensionToolCommands {
    static var all: [CommandDef] { [eqdim] }

    static var eqdim: CommandDef {
        CommandDef("EQDIM", aliases: ["EQUALITYDIM", "EQCONSTRAINT"], category: "Annotate", summary: "Equality dimensions: a chain of EQ dimensions that keeps three or more objects equally spaced (Create/Toggle EQ-value/Remove).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Create", "Toggle", "Remove"], defaultValue: "Create") ?? "Create"
            if k == "Create" {
                let ids = try await ed.getEntitySelection("Select objects to space equally (3 or more)")
                let refs = ids.compactMap { ed.doc.entity($0).flatMap { EqualityDimensions.refPoint($0.geometry) } }
                guard refs.count >= 3 else { throw CommandError.invalid("Select at least three lines, points, circles or blocks.") }
                let box = BBox2(points: refs)
                var dir = box.width >= box.height ? Vec2(1, 0) : Vec2(0, 1)
                let a = try await ed.getKeyword("Chain direction", ["Horizontal", "Vertical", "Aligned"], defaultValue: box.width >= box.height ? "Horizontal" : "Vertical") ?? "Horizontal"
                if a == "Vertical" { dir = Vec2(0, 1) } else if a == "Aligned" {
                    let s = refs.sorted { $0.dot(dir) < $1.dot(dir) }
                    dir = (s.last! - s.first!).normalized
                }
                let loc = try await ed.requirePoint("Specify dimension line location")
                let made = EqualityDimensions.create(ids, direction: dir, location: loc, doc: &ed.doc)
                guard !made.isEmpty else { throw CommandError.invalid("Could not create the EQ dimensions.") }
                ed.selection = []
                ed.print("\(made.count) EQ dimension(s) created; \(made.count + 1) objects kept equally spaced.")
                return
            }
            guard case .pick(let pk) = try await ed.pickObject("Select an EQ dimension", filter: { ed.doc.entity($0)?.props[EqualityDimensions.groupProp] != nil }),
                  let g = ed.doc.entity(pk.id)?.props[EqualityDimensions.groupProp].flatMap(Int.init) else { return }
            if k == "Toggle" {
                let cur = ed.doc.entity(pk.id)?.props[EqualityDimensions.showProp] ?? "EQ"
                EqualityDimensions.setDisplay(cur == "EQ" ? "value" : "EQ", group: g, doc: &ed.doc)
            } else {
                EqualityDimensions.dissolve(g, doc: &ed.doc)
                ed.print("Equality constraint removed; the dimensions remain.")
            }
        }
    }
}

/// 3D object snap modes (PRC-022) and apparent intersection (PRC-008).
public enum SnapToolCommands {
    static var all: [CommandDef] { [osnap3D, ducs] }

    static var ducs: CommandDef {
        CommandDef("DUCS", aliases: ["UCSDETECT", "DYNUCS"], category: "Settings", summary: "Turns the dynamic UCS on or off: points picked over a 3D solid land on the face under the cursor.") { ed in
            let on = DynamicUCS.isOn(ed.doc)
            let k = try await ed.getKeyword("Dynamic UCS is \(on ? "on" : "off")", ["ON", "OFF"], defaultValue: on ? "OFF" : "ON") ?? (on ? "OFF" : "ON")
            ed.doc.setVariable(DynamicUCS.variable, k == "ON" ? "1" : "0")
            ed.print("Dynamic UCS \(k == "ON" ? "on" : "off").")
        }
    }

    static var osnap3D: CommandDef {
        CommandDef("3DOSNAP", aliases: ["-3DOSNAP", "3DOSMODE"], category: "Settings", summary: "Sets 3D object snap modes on solids: ZVertex, ZMidpoint, ZCenter (face), ZKnot, ZPerpendicular, ZNearest, ALL, NONE.") { ed in
            let cur = Snap3D.modes(ed.doc)
            let names = Snap3D.Mode.allCases.filter { cur.contains($0) }.map(\.keyword)
            guard let s = try await ed.getWord("Enter list of 3D object snap modes [ALL/NONE/?]", defaultValue: names.isEmpty ? "NONE" : names.joined(separator: ",")) else { return }
            switch s.uppercased() {
            case "?": ed.print("3D object snaps: " + (names.isEmpty ? "off" : names.joined(separator: ", ")) + "  3DOSMODE = \(ed.doc.variable(Snap3D.variable) ?? "1")"); return
            case "ALL": Snap3D.setModes(Set(Snap3D.Mode.allCases), doc: &ed.doc)
            case "NONE", "OFF": Snap3D.setModes([], doc: &ed.doc)
            default:
                var m = Set<Snap3D.Mode>()
                for part in s.split(separator: ",") {
                    let p = part.trimmingCharacters(in: .whitespaces).uppercased()
                    guard let k = Snap3D.Mode.allCases.first(where: { $0.keyword.uppercased() == p || $0.keyword.uppercased().hasPrefix(p) && p.count >= 3 }) else { throw CommandError.invalid("Unknown 3D snap mode \(p).") }
                    m.insert(k)
                }
                Snap3D.setModes(m, doc: &ed.doc)
            }
            ed.print("3DOSMODE = \(ed.doc.variable(Snap3D.variable) ?? "1")")
        }
    }
}
