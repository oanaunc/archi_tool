// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Ribbon/menu entries for commands that used to be reachable only from the command line
/// (selection, 3D modeling and site, BIM additions, import and analysis).
extension CommandCatalog {
    static let selection: [CmdItem] = [
        CmdItem(title: "Quick Select", symbol: "line.3.horizontal.decrease.circle", names: ["QSELECT", "QSEL"]),
        CmdItem(title: "Select Similar", symbol: "square.on.square.intersection.dashed", names: ["SELECTSIMILAR", "SELSIM"]),
        CmdItem(title: "Invert", symbol: "arrow.left.arrow.right.square", names: ["SELECTINVERT", "INVSEL"]),
        CmdItem(title: "By Layer", symbol: "square.3.layers.3d", names: ["SELECTLAYER", "SELLAYER"]),
        CmdItem(title: "By Type", symbol: "list.bullet.rectangle", names: ["SELECTTYPE", "SELTYPE"]),
        CmdItem(title: "Chain", symbol: "link.circle", names: ["SELECTCHAIN", "SELCHAIN"]),
        CmdItem(title: "Intersecting", symbol: "square.on.square.squareshape.controlhandles", names: ["SELECTINTERSECTING", "SELINT"]),
        CmdItem(title: "Filter", symbol: "camera.filters", names: ["FILTER", "FI"]),
        CmdItem(title: "Named Sets", symbol: "bookmark", names: ["SELSET", "NAMEDSELECTION"]),
    ]
    static let groups: [CmdItem] = [
        CmdItem(title: "Group", symbol: "rectangle.3.group", names: ["GROUP", "G"]),
        CmdItem(title: "Ungroup", symbol: "rectangle.3.group.bubble", names: ["UNGROUP", "UNG"]),
        CmdItem(title: "Isolate", symbol: "eye.circle", names: ["ISOLATEOBJECTS", "ISOLATE"]),
        CmdItem(title: "Hide", symbol: "eye.slash", names: ["HIDEOBJECTS", "HIDEOBJ"]),
        CmdItem(title: "End Isolation", symbol: "eye", names: ["UNISOLATEOBJECTS", "UNISOLATE"]),
    ]
    static let solids: [CmdItem] = [
        CmdItem(title: "Box", symbol: "cube", names: ["BOX"]),
        CmdItem(title: "Cylinder", symbol: "cylinder", names: ["CYLINDER", "CYL"]),
        CmdItem(title: "Cone", symbol: "cone", names: ["CONE"]),
        CmdItem(title: "Sphere", symbol: "circle.circle", names: ["SPHERE"]),
        CmdItem(title: "Extrude", symbol: "square.stack.3d.up", names: ["EXTRUDE", "EXT"]),
        CmdItem(title: "Revolve", symbol: "arrow.triangle.2.circlepath", names: ["REVOLVE", "REV"]),
    ]
    static let modeling: [CmdItem] = [
        CmdItem(title: "Press/Pull", symbol: "arrow.up.and.down.square", names: ["PRESSPULL", "PP"]),
        CmdItem(title: "Loft", symbol: "square.stack.3d.forward.dottedline", names: ["LOFT"]),
        CmdItem(title: "Sweep", symbol: "point.topleft.down.to.point.bottomright.curvepath", names: ["SWEEP"]),
        CmdItem(title: "Pipe", symbol: "circle.dashed", names: ["PIPE", "TUBE"]),
        CmdItem(title: "Shell", symbol: "square.dashed", names: ["SHELL", "HOLLOW"]),
        CmdItem(title: "Smooth Mesh", symbol: "circle.hexagongrid", names: ["MESHSMOOTH", "SUBDIVIDE"]),
    ]
    static let booleans: [CmdItem] = [
        CmdItem(title: "Union", symbol: "square.on.square.squareshape.controlhandles", names: ["UNION", "UNI"]),
        CmdItem(title: "Subtract", symbol: "minus.square", names: ["SUBTRACT", "SU"]),
        CmdItem(title: "Intersect", symbol: "square.on.square.intersection.dashed", names: ["INTERSECT", "INTERSECTSOLIDS"]),
        CmdItem(title: "Slice", symbol: "scissors", names: ["SLICE", "SL3D"]),
        CmdItem(title: "Interfere", symbol: "exclamationmark.triangle", names: ["INTERFERE", "INF"]),
    ]
    static let transform3D: [CmdItem] = [
        CmdItem(title: "3D Mirror", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", names: ["MIRROR3D", "3DMIRROR"]),
        CmdItem(title: "3D Rotate", symbol: "rotate.3d", names: ["ROTATE3D", "3DROTATE"]),
        CmdItem(title: "3D Array", symbol: "square.grid.3x3.topleft.filled", names: ["3DARRAY", "ARRAY3D"]),
    ]
    static let site: [CmdItem] = [
        CmdItem(title: "Topography", symbol: "mountain.2", names: ["TOPO", "TOPOSURFACE", "TERRAIN"]),
        CmdItem(title: "Contours", symbol: "water.waves", names: ["CONTOURS", "CONTOUR"]),
        CmdItem(title: "Building Pad", symbol: "square.bottomhalf.filled", names: ["BUILDINGPAD", "PAD"]),
    ]
    static let buildMore: [CmdItem] = [
        CmdItem(title: "Ramp", symbol: "arrow.up.right", names: ["RAMP"]),
        CmdItem(title: "Foundation", symbol: "square.split.bottomrightquarter", names: ["FOUNDATION", "FOOTING"]),
        CmdItem(title: "Slab Slope", symbol: "arrow.up.forward.square", names: ["SLABSLOPE", "SLOPEARROW"]),
        CmdItem(title: "Curtain Grid", symbol: "square.grid.4x3.fill", names: ["CWGRID", "CURTAINGRID"]),
        CmdItem(title: "Niche", symbol: "rectangle.inset.filled", names: ["NICHE", "RECESS"]),
        CmdItem(title: "Wall Sweep", symbol: "rectangle.bottomhalf.inset.filled", names: ["WALLSWEEP", "SKIRTING"]),
        CmdItem(title: "Walls by Lines", symbol: "rectangle.split.2x1", names: ["WALLBYLINES", "WBL"]),
        CmdItem(title: "Wall Join", symbol: "arrow.triangle.merge", names: ["WALLJOIN", "WJ"]),
        CmdItem(title: "Wall Top", symbol: "arrow.up.to.line", names: ["WALLTOP", "WT"]),
        CmdItem(title: "Opening Types", symbol: "door.left.hand.closed", names: ["OPENINGTYPE", "DOORTYPE"]),
        CmdItem(title: "Copy to Level", symbol: "square.on.square", names: ["COPYTOLEVEL", "CTL"]),
        CmdItem(title: "Stair Check", symbol: "checkmark.seal", names: ["STAIRCHECK", "CHECKSTAIRS"]),
    ]
    static let roomsMore: [CmdItem] = [
        CmdItem(title: "Room Separator", symbol: "line.diagonal", names: ["ROOMSEPARATOR", "ROOMSEP"]),
        CmdItem(title: "Update Rooms", symbol: "arrow.triangle.2.circlepath", names: ["ROOMUPDATE", "RU"]),
        CmdItem(title: "Area Plan", symbol: "square.dashed", names: ["AREAPLAN", "GROSSAREA"]),
        CmdItem(title: "Room Bounding", symbol: "square.on.square.dashed", names: ["ROOMBOUNDING", "RBOUND"]),
    ]
    static let documentation: [CmdItem] = [
        CmdItem(title: "Tag", symbol: "tag", names: ["TAG", "ELEMENTTAG"]),
        CmdItem(title: "Tag All", symbol: "tag.circle", names: ["TAGALL"]),
        CmdItem(title: "Keynote", symbol: "note.text", names: ["KEYNOTE", "KN"]),
        CmdItem(title: "Marks", symbol: "number", names: ["MARKS", "RENUMBER"]),
        CmdItem(title: "Section", symbol: "arrow.left.and.line.vertical.and.arrow.right", names: ["SECTION", "SECTIONLINE"]),
        CmdItem(title: "Draw View", symbol: "rectangle.on.rectangle", names: ["VIEWDRAW", "SECTIONVIEW"]),
        CmdItem(title: "Update Views", symbol: "arrow.clockwise", names: ["VIEWUPDATE", "UPDATEVIEWS"]),
        CmdItem(title: "Interior Elev.", symbol: "square.split.bottomrightquarter", names: ["INTERIORELEV", "IELEV"]),
        CmdItem(title: "Callout", symbol: "plus.magnifyingglass", names: ["CALLOUT", "DETAILCALLOUT"]),
        CmdItem(title: "Phase", symbol: "calendar.badge.clock", names: ["PHASE", "PHASES"]),
        CmdItem(title: "3D Datums", symbol: "grid", names: ["DATUMS3D", "SHOWDATUMS"]),
        CmdItem(title: "Wall Attach", symbol: "arrow.up.and.down", names: ["WALLATTACH", "ATTACHWALL"]),
    ]
    static let importItems: [CmdItem] = [
        CmdItem(title: "Import File", symbol: "square.and.arrow.down", names: ["IMPORTFILE", "FILEIMPORT"]),
        CmdItem(title: "IFC", symbol: "building.columns", names: ["IFCIMPORT", "IFCIN"]),
        CmdItem(title: "SVG", symbol: "scribble", names: ["SVGIMPORT", "SVGIN"]),
        CmdItem(title: "Mesh (OBJ/STL)", symbol: "cube.transparent", names: ["MESHIMPORT", "OBJIMPORT"]),
        CmdItem(title: "GeoJSON", symbol: "globe", names: ["GEOJSONIMPORT", "GEOJSONIN"]),
        CmdItem(title: "Points (CSV)", symbol: "point.3.connected.trianglepath.dotted", names: ["POINTSIMPORT", "CSVPOINTS"]),
    ]
    static let referenceItems: [CmdItem] = [
        CmdItem(title: "Insert Block", symbol: "square.on.square.dashed", names: ["INSERT", "I"]),
        CmdItem(title: "Create Block", symbol: "square.dashed.inset.filled", names: ["BLOCK", "B"]),
        CmdItem(title: "Xref", symbol: "link", names: ["XREF", "XATTACH"]),
        CmdItem(title: "Image", symbol: "photo", names: ["IMAGEATTACH", "IMAGE"]),
        CmdItem(title: "Attribute", symbol: "character.textbox", names: ["ATTDEF", "ATT"]),
        CmdItem(title: "Paste Special", symbol: "doc.on.clipboard", names: ["PASTEORIG"]),
    ]
    static let exportItems: [CmdItem] = [
        CmdItem(title: "GeoJSON", symbol: "globe", names: ["GEOJSONEXPORT", "GEOJSONOUT"]),
        CmdItem(title: "Points", symbol: "point.3.filled.connected.trianglepath.dotted", names: ["POINTSEXPORT", "PTEXPORT"]),
        CmdItem(title: "3MF", symbol: "cube", names: ["EXPORT3MF", "3MFOUT"]),
        CmdItem(title: "USDZ", symbol: "arkit", names: ["USDEXPORT", "USDZEXPORT"]),
        CmdItem(title: "DXF R12", symbol: "doc", names: ["DXFR12OUT", "DXF12"]),
    ]
    static let analysis: [CmdItem] = [
        CmdItem(title: "Takeoff", symbol: "list.number", names: ["TAKEOFF", "QTO"]),
        CmdItem(title: "Cost Estimate", symbol: "dollarsign.circle", names: ["COSTESTIMATE", "COST"]),
        CmdItem(title: "Unit Prices", symbol: "tag", names: ["UNITPRICE", "COSTRATE"]),
        CmdItem(title: "Room Schedule", symbol: "tablecells", names: ["ROOMSCHEDULE", "ROOMAREAS"]),
    ]
    static let coordination: [CmdItem] = [
        CmdItem(title: "Clash Detect", symbol: "exclamationmark.triangle", names: ["CLASHDETECT", "CLASHES"]),
        CmdItem(title: "Check Model", symbol: "checkmark.shield", names: ["CHECKMODEL", "MODELCHECK"]),
        CmdItem(title: "Sun Position", symbol: "sun.max", names: ["SUNPOSITION", "SUNPOS"]),
    ]
    static let inquiry: [CmdItem] = [
        CmdItem(title: "Distance", symbol: "ruler", names: ["DIST", "DI"]),
        CmdItem(title: "Area", symbol: "square.dashed", names: ["AREA", "AA"]),
        CmdItem(title: "List", symbol: "list.bullet", names: ["LIST", "LI"]),
        CmdItem(title: "ID Point", symbol: "mappin", names: ["ID"]),
        CmdItem(title: "Mass Props", symbol: "scalemass", names: ["MASSPROP"]),
        CmdItem(title: "Count", symbol: "number.circle", names: ["COUNT"]),
    ]

    /// Every command this catalog exposes (used by tests of the menus and by the command-coverage report).
    static var allItems: [CmdItem] {
        draw + modify + text + dimensions + build + spaces + selection + groups + solids + modeling + booleans + transform3D + site
            + buildMore + roomsMore + documentation + importItems + referenceItems + exportItems + analysis + coordination + inquiry
    }

    /// Menu-bar mirrors of the extra catalogs.
    static let extraMenus: [(String, [(String, [CmdItem])])] = [
        ("Model", [("Solids", solids), ("Solid Editing", modeling), ("Booleans", booleans), ("3D Operations", transform3D), ("Site", site)]),
        ("Analyze", [("Inquiry", inquiry), ("Quantities", analysis), ("Coordination", coordination)]),
    ]

    /// Registered commands that no ribbon button or menu item reaches (for the Command Reference "coverage" view).
    @MainActor static func uncovered(_ registry: CommandRegistry) -> [CommandDef] {
        var covered: Set<String> = []
        for item in allItems { for n in item.names { if let d = registry.lookup(n) { covered.insert(d.name) } } }
        return registry.sorted.filter { !covered.contains($0.name) }
    }
}
