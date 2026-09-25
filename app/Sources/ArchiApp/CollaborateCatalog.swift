// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Ribbon/menu catalogs for the Collaborate tab and for the commands added after the first coverage pass
/// (review, exchange checks, analysis, BIM authoring extras). Included in `CommandCatalog.coverageMenus`.
extension CommandCatalog {
    private static func c(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }

    static let review: [CmdItem] = [
        c("Markups", "text.bubble", "MARKUP", "MARKUPS"), c("Compare Drawings", "rectangle.on.rectangle.angled", "COMPARE", "DWGCOMPARE"),
        c("BCF Import", "square.and.arrow.down.on.square", "BCFIN"), c("BCF Export", "square.and.arrow.up.on.square", "BCFOUT"),
        c("Revision Stamp", "triangle", "REVSTAMP"),
    ]
    static let versioning: [CmdItem] = [
        c("Issue Tracker", "checklist", "ISSUETRACKER"), c("Versions", "clock.arrow.2.circlepath", "VERSIONS"), c("Merge Models", "arrow.triangle.merge", "MODELMERGE"),
        c("Office Standards", "checkmark.seal", "STANDARDS"), c("Change Journal", "book.closed", "JOURNAL"), c("Recover File", "cross.case", "RECOVER"),
        c("Recovery Files", "lifepreserver", "RECOVERYFILES"),
    ]
    static let sharing: [CmdItem] = [
        c("eTransmit", "shippingbox", "ETRANSMIT"), c("Share…", "square.and.arrow.up", "SHARE"), c("Exchange Check", "checkmark.rectangle.stack", "EXCHANGECHECK"),
        c("Batch Jobs", "gearshape.2", "BATCH"), c("IFC Options", "building.columns", "IFCOPTIONS"),
    ]
    static let checks: [CmdItem] = [
        c("Accessibility", "figure.roll", "ACCESSIBILITY"), c("Egress", "figure.walk.departure", "EGRESS"), c("Energy Balance", "bolt.horizontal.circle", "ENERGYBALANCE"),
        c("Bill of Quantities", "list.bullet.rectangle", "BOQ"), c("Takeoff by Phase", "calendar.badge.clock", "TAKEOFFPHASE"), c("Lighting Schedule", "lightbulb", "LIGHTSCHEDULE"),
        c("Fire Compartments", "flame", "FIRECOMPARTMENTS"), c("Load Takedown", "arrow.down.to.line.compact", "LOADTAKEDOWN"),
        c("Parking Check", "car.2", "PARKINGCHECK"), c("Rainwater", "cloud.rain", "RAINWATER"),
    ]
    static let imagesGeo: [CmdItem] = [
        c("Import Image", "photo.on.rectangle", "IMAGEIMPORT"), c("Scale Image", "arrow.up.left.and.down.right.magnifyingglass", "IMAGESCALE"),
        c("KML / KMZ Out", "globe.europe.africa", "KMLOUT"), c("Layered SVG Out", "square.stack.3d.down.right", "SVGLAYERSOUT"), c("Load .pat Patterns", "square.grid.3x3.topleft.filled", "PATLOAD"),
    ]
    static let draftingExtra: [CmdItem] = [
        c("Match Properties", "paintbrush.pointed", "MATCHPROP", "MA"), c("Blend Curves", "point.topleft.down.curvedto.point.bottomright.up", "BLEND"),
        c("Ellipse in Parallelogram", "oval.portrait", "ELLIPSEQUAD"), c("Gradient", "square.fill.and.line.vertical.and.square", "GRADIENT"), c("Trace", "line.horizontal.3", "TRACE"),
        c("Flatten", "square.2.layers.3d.bottom.filled", "FLATTEN"), c("Hatch Origin", "scope", "HATCHSETORIGIN"), c("Rotate 90°", "rotate.left", "ROTATE90"),
        c("Edit Spline", "scribble.variable", "SPLINEDIT"), c("Explode Text", "character", "TXTEXP"), c("Change Space", "rectangle.2.swap", "CHSPACE"),
        c("Deselect", "xmark.square", "DESELECT"), c("Select Previous", "arrow.uturn.backward.square", "SELECTPREVIOUS"), c("Select Instances", "square.stack", "SELECTINSTANCES"),
    ]
    static let annotateExtra: [CmdItem] = [
        c("Jogged Radius", "bolt", "DIMJOGGED"), c("Jog Line", "bolt.horizontal", "DIMJOGLINE"), c("Ordinate Datum", "scope", "DIMREBASE"),
        c("Grid Dimensions", "ruler", "AUTODIMGRIDS"), c("Object Scale", "a.magnify", "OBJECTSCALE"), c("Spot Coordinate", "mappin.and.ellipse", "SPOTCOORD"),
        c("Text Frame", "textbox", "TEXTFRAME"), c("Text Mask", "rectangle.fill.on.rectangle.fill", "TEXTMASK"), c("Remove Text Mask", "rectangle.on.rectangle", "TEXTUNMASK"),
    ]
    static let blocksExtra: [CmdItem] = [
        c("Dynamic Parameter", "slider.horizontal.below.rectangle", "BPARAMETER"), c("Dynamic Value", "dial.medium", "DYNPROP"), c("Reset Block", "arrow.counterclockwise", "RESETBLOCK"),
    ]
    static let bimAuthoring: [CmdItem] = [
        c("Area Scheme", "square.dashed.inset.filled", "AREASCHEME"), c("Update Associative", "arrow.triangle.2.circlepath", "BIMUPDATE"), c("Dormer", "house.lodge", "DORMER"),
        c("Elevator", "arrow.up.arrow.down.square", "ELEVATOR"), c("Family Editor", "cube.box", "FAMILY"), c("Floor Finish", "square.grid.4x3.fill", "FLOORFINISH"),
        c("Model Group", "square.on.square.squareshape.controlhandles", "MODELGROUP"), c("Opening Trim", "door.left.hand.closed", "OPENINGTRIM"), c("Profiles", "waveform.path", "PROFILE"),
        c("Railing Type", "line.3.horizontal", "RAILINGTYPE"), c("Roof Edge", "house", "ROOFEDGE"), c("Shaft", "square.stack.3d.down.forward", "SHAFT"),
        c("Skylight", "skylight", "SKYLIGHT"), c("Slab Opening", "square.dashed", "SLABOPENING"), c("Slab / Roof Type", "square.3.layers.3d", "SLABTYPE"),
        c("Wall Join", "arrow.triangle.merge", "WALLJOINEDIT"), c("Wall Wrap", "rectangle.inset.filled", "WALLWRAP"),
        c("Light Data", "lightbulb.max", "LIGHTDATA"), c("MEP Systems", "point.3.filled.connected.trianglepath.dotted", "MEPSYSTEM"),
    ]
    static let viewsExtra: [CmdItem] = [
        c("Drafting View", "pencil.and.ruler", "DRAFTINGVIEW"), c("Legend", "list.bullet.rectangle.portrait", "LEGEND"),
        c("View Graphics", "eye.trianglebadge.exclamationmark", "VIEWGRAPHICS"), c("View Templates", "rectangle.stack.badge.person.crop", "VIEWTEMPLATE"),
    ]
    static let solidsExtra: [CmdItem] = [
        c("Press/Pull Face", "arrow.up.square", "PRESSPULLFACE"), c("Section Solids", "square.split.diagonal.2x2", "SECTIONSOLIDS"),
        c("Record History", "record.circle", "SOLIDHIST"), c("Feature History", "list.bullet.indent", "SOLIDHISTORY"),
    ]
    static let panels: [CmdItem] = [
        c("Markup Panel", "text.bubble.fill", "MARKUPPANEL"), c("Compare Overlay", "rectangle.on.rectangle.angled", "COMPAREPANEL"),
        c("Revision Clouds", "cloud", "REVCLOUDPANEL"), c("Block Palette", "books.vertical.fill", "BLOCKPALETTE"),
    ]
    static let presentation3D: [CmdItem] = [
        c("Measure 3D", "ruler", "MEASURE3D"), c("3D Gizmo", "move.3d", "GIZMO3D"), c("Camera Paths", "point.topleft.down.to.point.bottomright.curvepath", "CAMERAPATHEDIT"),
        c("Render Queue", "square.stack.3d.forward.dottedline", "RENDERQUEUE"), c("Clipping Plane", "square.split.diagonal", "CLIPPLANES"), c("Print Setup", "printer.filled.and.paper", "PRINTSETUP"),
    ]
    static let inquiryExtra: [CmdItem] = [
        c("Angle Between", "angle", "ANGLEBETWEEN"), c("Distance to Object", "arrow.left.and.right.square", "DISTTOOBJECT"),
        c("Point Inside?", "smallcircle.filled.circle", "POINTINSIDE"), c("Total Length", "sum", "TLEN"),
    ]
    static let scriptingExtra: [CmdItem] = [
        c("Plug-ins", "puzzlepiece.extension", "PLUGINS"), c("Script to JavaScript", "curlybraces", "SCRIPT2JS"), c("Menu Macro", "command", "MACRO"), c("Delay", "timer", "DELAY"), c("Resume Script", "playpause", "RESUME"),
    ]

    /// Sections added to the coverage menus (names unique across `coverageMenus`).
    static var coverageMenus2: [(String, [CmdItem])] {
        [("Review & Markup", review), ("Versions & Issues", versioning), ("Inquiry Extras", inquiryExtra), ("Sharing & Exchange", sharing), ("Checks & Quantities", checks), ("Images & Geo", imagesGeo),
         ("Drafting Extras", draftingExtra), ("Annotation Extras", annotateExtra), ("Dynamic Blocks", blocksExtra), ("BIM Authoring", bimAuthoring),
         ("Views & Graphics", viewsExtra), ("Solid Features", solidsExtra), ("Script Control", scriptingExtra),
         ("Review Panels", panels), ("3D, Render & Print", presentation3D)]
    }
}
