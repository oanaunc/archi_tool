// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Ribbon/menu entries for core commands added after the Collaborate catalogs (3D primitives, dimensions extras,
/// BIM grids and zones, data and diagnostics). Included in `CommandCatalog.coverageMenus` via `coverageMenus2`.
extension CommandCatalog {
    private static func c(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }

    static let primitivesMore: [CmdItem] = [
        c("Wedge", "triangle.righthalf.filled", "WEDGE"), c("Torus", "circle.circle", "TORUS"), c("Pyramid", "pyramid", "PYRAMID"), c("Prism", "hexagon", "PRISM"),
        c("Polyhedron", "diamond", "POLYHEDRON"), c("Polysolid", "rectangle.split.3x1", "POLYSOLID"), c("Helix", "tornado", "HELIX"), c("Planar Surface", "square", "PLANESURF"),
        c("Thicken", "square.stack.3d.up.fill", "THICKEN"), c("Convex Hull", "hexagon.fill", "HULL"), c("Separate Solids", "square.split.2x1", "SEPARATE"),
        c("Check Solid", "checkmark.circle", "SOLIDCHECK"), c("Section Object", "square.split.diagonal.2x2.fill", "SECTIONOBJECT"),
        c("Mesh Primitive", "circle.hexagongrid.fill", "MESH"), c("Convert to Mesh", "circle.hexagongrid", "CONVTOMESH"), c("Convert to Solid", "cube.fill", "CONVTOSOLID"),
        c("Linear Extrude", "square.stack.3d.up", "LINEAREXTRUDE"),
    ]
    static let annotationMore: [CmdItem] = [
        c("Alternate Units", "textformat.123", "DIMALTUNITS"), c("Dimension Tolerance", "plusminus", "DIMTOLERANCE"), c("Inspection Dimension", "checkmark.rectangle", "DIMINSPECT"),
        c("Text Columns", "text.justify.left", "MTEXTCOLUMNS"), c("Text List", "list.bullet", "TEXTLIST"), c("Color Books", "swatchpalette", "COLORBOOK"),
        c("Layer Description", "text.bubble", "LAYDESC"), c("Block Table", "tablecells", "BTABLE"), c("Clip Xref", "crop", "XCLIP"),
    ]
    static let bimMore2: [CmdItem] = [
        c("Grid System", "grid", "GRIDSYSTEM"), c("Radial Grid", "circle.grid.cross", "RADIALGRID"), c("Zone", "square.dashed.inset.filled", "ZONE"),
        c("Escalator", "stairs", "ESCALATOR"), c("Split Wall", "scissors", "SPLITWALL"), c("Flip Wall", "arrow.left.and.right.square", "WALLFLIP"),
        c("Flip Opening", "door.left.hand.open", "OPENINGFLIP"), c("Classify", "tag.square", "CLASSIFY"), c("Property Sets", "list.bullet.rectangle", "PSET"),
        c("Global Parameters", "function", "GLOBALPARAM"), c("Auto Stack", "square.stack.3d.up.badge.automatic", "AUTOSTACK"), c("Relative Zero", "scope", "RELZERO"),
        c("Roof by Shape", "house", "ROOFSHAPE"), c("View Range", "arrow.up.and.down.text.horizontal", "VIEWRANGE"), c("Geolocation", "location.circle", "GEOLOCATION"),
        c("Underlay", "doc.on.doc", "UNDERLAY"),
    ]
    static let visibilityMore: [CmdItem] = [
        c("Temporary Hide", "eye.slash.circle", "TEMPHIDE"), c("Temporary Isolate", "eye.circle", "TEMPISOLATE"), c("Reveal Hidden", "lightbulb", "REVEALHIDDEN"),
    ]
    static let toolsMore: [CmdItem] = [
        c("Array (Dialog)", "square.grid.3x3", "ARRAYCLASSIC"), c("Edit Array", "square.grid.3x3.middle.filled", "ARRAYEDIT"), c("Macro Button", "command.square", "MACROBUTTON"),
        c("Variable Monitor", "eye.circle", "SYSVARMONITOR"),
    ]

    static let interopMore: [CmdItem] = [
        c("Import PDF", "doc.richtext", "PDFIMPORT"), c("PDF Markups", "pencil.and.outline", "PDFMARKUPS"), c("Import DWFx", "doc.zipper", "DWFIMPORT"),
        c("Import DGN", "square.and.arrow.down", "DGNIMPORT"), c("Export DGN", "square.and.arrow.up", "DGNEXPORT"), c("IFC Class Mapping", "tablecells.badge.ellipsis", "IFCMAP"),
        c("Laser Export", "scissors.circle", "LASEREXPORT"), c("Share View", "square.and.arrow.up.on.square", "SHAREVIEW"), c("Point Cloud View", "aqi.medium", "POINTCLOUDVIEW"),
        c("Point Cloud Plane", "square.on.square.dashed", "PCPLANE"), c("Scan to BIM", "cube.transparent", "SCANTOBIM"), c("Central Model", "server.rack", "CENTRAL"),
        c("Git Version", "arrow.triangle.branch", "GITVERSION"), c("Trace Review", "square.2.layers.3d", "TRACEREVIEW"),
    ]
    static let analysisAssist: [CmdItem] = [
        c("Structural Loads", "arrow.down.to.line", "STRUCTLOAD"), c("Structural Supports", "triangle.bottomhalf.filled", "STRUCTSUPPORT"),
        c("Thermal Bridges", "thermometer.medium", "THERMALBRIDGES"), c("EnergyPlus Export", "bolt.circle", "ENERGYPLUS"), c("Work Schedule (4D)", "calendar.badge.clock", "WORKSCHEDULE"),
        c("Auto-Dimension Plan", "ruler", "AUTODIMPLAN"), c("Auto-Name Rooms", "character.textbox", "AUTONAMEROOMS"), c("Generate Plan", "square.grid.3x1.below.line.grid.1x2", "PLANGEN"),
        c("QA Assistant", "checklist", "QAASSIST"), c("Ask (Natural Language)", "text.bubble", "ASK"), c("AutoLISP", "chevron.left.forwardslash.chevron.right", "LISP"),
        c("Load LISP File", "doc.text", "LISPLOAD"),
    ]

    /// Sections added after `coverageMenus2` (names unique across `coverageMenus`).
    static var coverageMenus3: [(String, [CmdItem])] {
        [("3D Primitives & Solid Tools", primitivesMore), ("Annotation & Data", annotationMore), ("BIM Grids, Zones & Data", bimMore2), ("Arrays, Macros & Monitor", toolsMore), ("Temporary Visibility", visibilityMore), ("Import, Export & Collaboration", interopMore), ("Analysis & Design Assist", analysisAssist), ("Navigation & Sheets", navigationItems), ("File Tools & Exchange", fileExchangeItems), ("Analysis & Generative", analysisGenerativeItems)] + coverageMenus4
    }
}
