// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Ribbon/menu catalogs for the commands added in round 10 (feature modelling, surfaces, graphic styles, MEP circuits,
/// rendering and material tools). Included in `CommandCatalog.coverageMenus` via `coverageMenus4`.
extension CommandCatalog {
    private static func c(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }

    /// Part-design style feature modelling and solid editing.
    static let featuresRound10: [CmdItem] = [
        c("Pocket", "square.stack.3d.down.forward", "POCKET"), c("Hole", "circle.dashed.inset.filled", "HOLE"), c("Groove", "circle.bottomhalf.filled", "GROOVE"),
        c("Revolution", "arrow.triangle.2.circlepath.circle", "REVOLUTION"), c("Follow Me", "point.topleft.down.curvedto.point.bottomright.up", "FOLLOWME"),
        c("Sweep along 3D Path", "tornado", "SWEEP3D"), c("Pattern Feature", "square.grid.3x1.below.line.grid.1x2", "PATTERNFEATURE"),
        c("Mirror Feature", "arrow.left.and.right.righttriangle.left.righttriangle.right", "MIRRORFEATURE"), c("Split Solid", "scissors", "SPLITSOLID"),
        c("General Fuse", "square.on.square.intersection.dashed", "GFUSE"), c("Solid Edit", "cube.transparent", "SOLIDEDIT"), c("Offset Solid", "cube", "OFFSETSOLID"),
        c("CSG Tree", "list.bullet.indent", "CSGTREE"), c("Soften Edges", "circle.lefthalf.filled", "SOFTEN"), c("Paint Bucket", "paintbrush.pointed", "PAINT"),
        c("Tape Measure", "ruler", "TAPEMEASURE"), c("3D Object Snap", "scope", "3DOSNAP"), c("Dynamic UCS", "move.3d", "DUCS"),
        c("Shape Binder", "link.circle", "SHAPEBINDER"), c("Scale XYZ", "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "SCALE3D"),
        c("Intersect Faces", "square.on.square.intersection.dashed", "INTERSECTFACES"), c("Project Geometry", "square.dashed", "PROJECTGEOMETRY"),
        c("Scripted Object", "curlybraces.square", "SCADOBJECT"), c("Graphic Display Options", "eye.square", "GRAPHICDISPLAY"),
    ]
    /// Freeform surfaces.
    static let surfacesRound10: [CmdItem] = [
        c("Patch Surface", "square.dashed.inset.filled", "SURFPATCH"), c("Network Surface", "grid", "SURFNETWORK"), c("Sculpt to Solid", "cube.fill", "SURFSCULPT"),
        c("Offset Surface", "square.on.square", "SURFOFFSET"), c("Extend Surface", "arrow.up.left.and.arrow.down.right", "SURFEXTEND"), c("Trim Surface", "crop", "SURFTRIM"),
    ]
    /// BIM graphics, circuits, site grading and room data.
    static let bimRound10: [CmdItem] = [
        c("Line Styles", "line.3.horizontal", "LINESTYLES"), c("Lineweight by Scale", "lineweight", "LWTABLE"), c("Pen Sets", "pencil.tip", "PENSETS"),
        c("Graphic Filters", "line.3.horizontal.decrease.circle", "GFILTERS"), c("Equality Dimension", "equal.square", "EQDIM"),
        c("Curtain System", "rectangle.split.3x3", "CURTAINSYSTEM"), c("In-Place Model", "cube.transparent.fill", "INPLACE"), c("Graded Region", "mountain.2", "GRADEDREGION"),
        c("Electrical Circuits", "bolt.circle", "CIRCUIT"), c("Panel Schedule", "tablecells", "PANELSCHEDULE"), c("Room Data Sheets", "doc.text", "ROOMDATASHEET"),
    ]

    /// Sections added in round 10 (names unique across `coverageMenus`).
    static var coverageMenus5: [(String, [CmdItem])] {
        [("Feature Modelling", featuresRound10), ("Freeform Surfaces", surfacesRound10), ("BIM Graphics & Systems", bimRound10)] + coverageMenus6
    }
}
