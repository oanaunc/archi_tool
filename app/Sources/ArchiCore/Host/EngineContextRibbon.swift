// Oanarina Archi Tool — GPL-3.0-or-later
// Contextual ribbon tabs (APP-015): the portable twin of ArchiApp/AppNavigation.swift ContextualRibbon. Selecting objects
// of one kind shows an accent-coloured tab ("Modify Wall", "Text Editor", "Hatch Editor", …) with that kind's commands
// followed by Move, Copy, Rotate, Mirror, Match Props and Select Similar. The Windows shell asks `ribbon.context` after
// every selection change and draws the strip under the ribbon exactly like ContextualRibbonStrip.
import Foundation

public struct EngineContextItem: Hashable {
    public var title: String
    public var symbol: String
    public var names: [String]
    public init(_ title: String, _ symbol: String, _ names: [String]) { self.title = title; self.symbol = symbol; self.names = names }
}

public struct EngineContextTab: Hashable {
    public var title: String
    public var category: String
    public var items: [EngineContextItem]
}

public enum EngineContextRibbon {
    static func c(_ t: String, _ s: String, _ n: String...) -> EngineContextItem { EngineContextItem(t, s, n) }
    static let common: [EngineContextItem] = [
        c("Move", "arrow.up.and.down.and.arrow.left.and.right", "MOVE"), c("Copy", "plus.square.on.square", "COPY"),
        c("Rotate", "arrow.clockwise", "ROTATE"), c("Mirror", "arrow.left.and.right.righttriangle.left.righttriangle.right", "MIRROR"),
        c("Match Props", "paintbrush.pointed", "MATCHPROP"), c("Select Similar", "square.on.square.intersection.dashed", "SELECTSIMILAR"),
    ]

    static func entityKind(_ g: Geometry) -> String {
        switch g {
        case .text: return "Text"
        case .dimension: return "Dimension"
        case .hatch: return "Hatch"
        case .insert: return "Block Reference"
        case .polyline: return "Polyline"
        case .table: return "Table"
        case .image: return "Image"
        case .leader: return "Leader"
        case .solid: return "Solid"
        default: return "Geometry"
        }
    }

    static func elementKind(_ g: BIMGeometry) -> String {
        switch g {
        case .wall, .curtainWall: return "Wall"
        case .opening(let o): return o.kind == .window ? "Window" : "Door"
        case .slab: return "Floor"
        case .roof: return "Roof"
        case .stair: return "Stair"
        case .space: return "Room"
        case .column: return "Column"
        case .beam: return "Beam"
        default: return "Element"
        }
    }

    /// Category of the selection: all objects of one kind, or nil for mixed / empty selections.
    public static func category(_ doc: ArchiDocument, _ sel: Set<EntityID>) -> String? {
        guard !sel.isEmpty else { return nil }
        var kinds: Set<String> = []
        for id in sel {
            if let e = doc.entity(id) { kinds.insert(entityKind(e.geometry)) }
            else if let el = doc.element(id) { kinds.insert(elementKind(el.geometry)) }
            if kinds.count > 1 { return nil }
        }
        return kinds.first
    }

    /// The contextual tab for a selection, nil when none applies.
    public static func tab(_ doc: ArchiDocument, _ sel: Set<EntityID>) -> EngineContextTab? {
        guard let k = category(doc, sel) else { return nil }
        let specific: [EngineContextItem]
        let title: String
        switch k {
        case "Wall":
            title = "Modify Wall"
            specific = [c("Door", "door.left.hand.open", "DOOR"), c("Window", "window.vertical.closed", "WINDOW"), c("Opening", "rectangle.dashed", "OPENING", "WALLOPENING"),
                        c("Dimension Walls", "rectangle.split.3x1", "AUTODIMWALLS"), c("Offset", "square.on.square.dashed", "OFFSET"), c("Properties", "slider.horizontal.3", "PROPERTIES")]
        case "Door", "Window":
            title = "Modify " + k
            specific = [c("Properties", "slider.horizontal.3", "PROPERTIES"), c("Set Property", "slider.horizontal.below.rectangle", "SETPROP"), c("Opening Parts", "door.left.hand.closed", "OPENINGPARTS")]
        case "Text":
            title = "Text Editor"
            specific = [c("Edit Text", "pencil", "TEXTEDIT"), c("Text Style", "textformat", "TEXTSTYLE"), c("Justify", "text.justify", "JUSTIFYTEXT"),
                        c("Scale Text", "textformat.size", "SCALETEXT"), c("Spelling", "textformat.abc.dottedunderline", "SPELL"), c("Find & Replace", "magnifyingglass", "FIND")]
        case "Hatch":
            title = "Hatch Editor"
            specific = [c("Edit Hatch", "square.grid.3x3.fill", "HATCHEDIT"), c("Recreate Boundary", "square.dashed", "HATCHGENERATEBOUNDARY"), c("Send to Back", "square.3.layers.3d.down.right", "HATCHTOBACK")]
        case "Dimension":
            title = "Dimension"
            specific = [c("Edit Dimension", "pencil", "DIMEDIT"), c("Move Text", "text.cursor", "DIMTEDIT"), c("Dimension Style", "ruler", "DIMSTYLE"),
                        c("Break", "scissors", "DIMBREAK"), c("Space", "arrow.up.and.down.text.horizontal", "DIMSPACE"), c("Reassociate", "link", "DIMREASSOCIATE")]
        case "Block Reference":
            title = "Block Reference"
            specific = [c("Edit Attributes", "character.textbox", "ATTEDIT"), c("Replace Block", "arrow.triangle.swap", "BLOCKREPLACE"), c("Count", "number.circle", "BCOUNT"), c("Explode", "burst", "EXPLODE")]
        case "Polyline":
            title = "Polyline"
            specific = [c("Edit Polyline", "point.topleft.down.curvedto.point.bottomright.up", "PEDIT"), c("Join", "link", "JOIN"), c("Reverse", "arrow.left.arrow.right", "REVERSE"), c("Explode", "burst", "EXPLODE")]
        case "Table":
            title = "Table Cell"
            specific = [c("Edit Table", "tablecells", "TABLEEDIT"), c("Export Table", "square.and.arrow.up", "TABLEEXPORT")]
        case "Room":
            title = "Modify Room"
            specific = [c("Room Finishes", "square.grid.3x3.topleft.filled", "ROOMFINISH"), c("Color Fill", "paintbrush", "COLORFILL"), c("Properties", "slider.horizontal.3", "PROPERTIES")]
        default:
            title = "Modify " + k
            specific = [c("Properties", "slider.horizontal.3", "PROPERTIES")]
        }
        return EngineContextTab(title: title, category: k, items: specific + common)
    }
}

extension EngineSession {
    /// `ribbon.context {ids?}` → `{tab: {title, category, items:[{title, symbol, command, names}]} | null}`: the contextual
    /// tab of the selection (or of `ids`). Items whose command is not registered are left out, as the Mac strip does.
    func ribbonContext(_ p: EngineJSON) -> EngineJSON {
        var sel = editor.selection
        if let ids = p["ids"]?.arrayValue { sel = Set(ids.compactMap { $0.intValue.map { EntityID($0) } }) }
        var o = EngineObject()
        guard let t = EngineContextRibbon.tab(editor.doc, sel) else { o.set("tab", EngineJSON.null); return o.json }
        var items: [EngineJSON] = []
        for it in t.items {
            guard let name = it.names.first(where: { editor.registry.lookup($0) != nil }) else { continue }
            var i = EngineObject()
            i.set("title", it.title)
            i.set("symbol", it.symbol)
            i.set("command", name)
            i.set("names", EngineJSON.strings(it.names))
            if let def = editor.registry.lookup(name) { i.set("help", def.name + " — " + def.summary) }
            items.append(i.json)
        }
        var tab = EngineObject()
        tab.set("title", t.title)
        tab.set("category", t.category)
        tab.set("items", EngineJSON.array(items))
        o.set("tab", tab.json)
        o.set("count", sel.count)
        return o.json
    }
}
