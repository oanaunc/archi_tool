// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Ribbon/menu entries for the commands added in round 9 (core BIM, annotation, 3D and view commands, and the app's
/// navigation, lighting, output and assistant commands). Included in `CommandCatalog.coverageMenus` via `coverageMenus3`.
extension CommandCatalog {
    private static func c(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }

    static let bimRound9: [CmdItem] = [
        c("Assembly", "square.stack.3d.up", "ASSEMBLY"), c("Parts", "square.split.2x2", "PARTS"), c("Stacked Wall", "rectangle.split.1x2", "STACKEDWALL"),
        c("Rectangular Walls", "rectangle", "WALLRECT"), c("Polygon Walls", "pentagon", "WALLPOLYGON"), c("Storefront", "rectangle.split.3x3", "STOREFRONT"),
        c("Stair Types", "stairs", "STAIRTYPE"), c("Railing Types", "line.3.horizontal", "RAILTYPEDEF"), c("Story Settings", "building.2", "STORY"),
        c("Structural Column", "rectangle.portrait", "STRUCTCOLUMN"), c("Structural Usage", "building.columns", "STRUCTURAL"),
        c("Expression", "function", "EXPRESSION"), c("Family Equality Lock", "lock.rectangle", "FAMILYLOCK"), c("Parameter ↔ Cell", "tablecells", "PARAMCELL"),
        c("Reporting Parameter", "ruler", "REPORTPARAM"), c("Transfer Standards", "arrow.left.arrow.right.square", "TRANSFERSTANDARDS"),
        c("Roof by Extrusion", "house.lodge", "ROOFEXTRUSION"), c("Roof Shape Points", "point.3.filled.connected.trianglepath.dotted", "ROOFSHAPEPOINTS"),
        c("Slab Edge", "rectangle.bottomthird.inset.filled", "SLABEDGE"), c("Stair by Sketch", "stairs", "STAIRSKETCH"), c("Type Image", "photo", "TYPEIMAGE"),
    ]
    static let annotateRound9: [CmdItem] = [
        c("Detail Component", "square.on.square.dashed", "DETAILCOMPONENT"), c("Repeating Detail", "square.grid.3x1.below.line.grid.1x2", "REPEATDETAIL"),
        c("Insulation", "water.waves", "INSULATION"), c("Filled Region", "square.fill", "FILLEDREGION"), c("Masking Region", "square.dashed.inset.filled", "MASKINGREGION"),
        c("Hatch Type (Model/Drafting)", "square.grid.3x3", "HATCHTYPE"), c("Detail Mark", "circle.bottomhalf.filled", "DETAILMARK"), c("Elevation Mark", "arrowtriangle.right.circle", "ELEVATIONMARK"),
        c("Section Symbol", "arrow.left.and.line.vertical.and.arrow.right", "SECTIONSYMBOL"), c("Material Tag", "tag", "MATERIALTAG"), c("Revision Clouds", "cloud", "REVCLOUDLIST"),
        c("Schedule Cell Highlight", "tablecells.badge.ellipsis", "SCHEDULECELLS"), c("Table Style", "tablecells", "TABLESTYLE"),
    ]
    static let viewRound9: [CmdItem] = [
        c("Plan (UCS)", "square", "PLAN"), c("Plan Orientation", "location.north.line", "PLANORIENT"), c("Project Views", "list.bullet.rectangle", "PROJECTVIEW"),
        c("Axonometric View", "cube", "AXONVIEW"), c("Camera Object", "camera", "CAMERAVIEW"), c("View Crop", "crop", "VIEWCROP"), c("Scope Box", "cube.transparent", "SCOPEBOX"),
        c("Matchlines", "line.diagonal", "MATCHLINE"), c("Linework Override", "pencil.line", "LINEWORK"), c("UCS Icon", "move.3d", "UCSICON"),
        c("Axis Lock", "lock", "AXISLOCK"), c("View Section Box", "cube.transparent.fill", "VIEWSECTIONBOX"), c("Double-Click Edit", "cursorarrow.click.2", "DBLCLKEDIT"), c("Reference Plane", "square.split.diagonal", "RP"),
        c("Project Base Point", "scope", "PROJECTBASEPOINT"), c("Survey Point", "triangle", "SURVEYPOINT"), c("True North", "location.north", "TRUENORTH"),
    ]
    static let modelingRound9: [CmdItem] = [
        c("3D Align", "align.horizontal.left", "3DALIGN"), c("Extrude Mesh Face", "square.stack.3d.up", "MESHEXTRUDE"), c("Mesh Sections", "square.split.diagonal.2x2", "MESHSECTION"),
        c("Minkowski Sum", "circle.square", "MINKOWSKI"), c("OpenSCAD Script", "chevron.left.forwardslash.chevron.right", "SCAD"), c("OpenSCAD File", "doc.text", "SCADFILE"),
        c("Spring", "tornado", "SPRING"), c("CV Surface", "square.grid.4x3.fill", "SURFCV"), c("3D Text", "textformat", "TEXT3D"), c("Unfold Mesh", "square.on.square.dashed", "UNFOLD"),
        c("Wireframe Lattice", "circle.hexagongrid", "WIREFRAME"),
    ]
    static let blocksRound9: [CmdItem] = [
        c("Block Editor", "square.and.pencil", "BEDIT"), c("Save Block", "square.and.arrow.down", "BSAVE"), c("Close Block Editor", "xmark.square", "BCLOSE"),
        c("Edit Reference", "pencil.and.outline", "REFEDIT"), c("Reference Working Set", "plus.square.on.square", "REFSET"), c("Close Reference", "xmark.rectangle", "REFCLOSE"),
        c("Install Bundled Library", "books.vertical.fill", "LIBRARYINSTALL"), c("Layer Notification", "bell", "LAYERNOTIFY"), c("Reconcile Layers", "checkmark.circle", "LAYRECONCILE"),
    ]
    static let exchangeRound9: [CmdItem] = [c("DXF Output Version", "doc.badge.gearshape", "DXFOUTVERSION"), c("ifcXML Out", "chevron.left.forwardslash.chevron.right", "IFCXMLOUT")]
    /// App commands of round 9 (navigation, lighting, output, scripting assistant).
    static let appRound9: [CmdItem] = [
        c("Arrange Windows", "rectangle.split.2x1", "SYSWINDOWS"), c("Fly", "airplane", "FLY"), c("Look Around", "eye", "LOOKAROUND"),
        c("Position Camera", "camera.viewfinder", "POSITIONCAMERA"), c("Two-Point Perspective", "perspective", "TWOPOINT"), c("Steering Wheel", "steeringwheel", "NAVSWHEEL"),
        c("Lights", "lightbulb", "LIGHT"), c("Fog", "cloud.fog", "FOG"), c("Emissive Material", "sun.max", "MATEMISSIVE"), c("Texture Mapping", "square.on.square.intersection.dashed", "MATMAPPING"), c("Billboard", "person.crop.rectangle", "BILLBOARD"),
        c("Export PDF", "doc.richtext", "EXPORTPDF"), c("Shade Plot", "circle.lefthalf.filled", "SHADEPLOT"), c("Title Block Design", "list.bullet.rectangle.portrait", "TITLEBLOCKDESIGN"), c("Web Viewer Export", "globe", "WEBVIEWEREXPORT"), c("Render to File (Passes, Region, 8K)", "photo.stack", "RENDERTOFILE"), c("Stereo 360° Panorama", "visionpro", "STEREOPANORAMA"), c("Construction Sequence (4D)", "film.stack", "PHASEANIMATION"),
        c("Hyperlink", "link", "HYPERLINK"), c("AI Assistant", "sparkles", "ASSISTANT"), c("Graph Player", "play.square.stack", "GRAPHPLAYER"), c("Render Prompt", "wand.and.stars", "RENDERPROMPT"), c("Radial Menu", "circle.circle", "RADIALMENU"),
    ]

    /// Analysis, exchange and trust commands of round 9 (daylight/shadow studies, accessibility, signatures, publishing).
    static let analysisRound9: [CmdItem] = [
        c("Radiance Daylight", "sun.max.trianglebadge.exclamationmark", "DAYLIGHTRADIANCE"), c("Shadow Diagram", "shadow", "SHADOWDIAGRAM"),
        c("Colour-Blind Check", "eye.trianglebadge.exclamationmark", "COLORBLINDCHECK"), c("Memory Report", "memorychip", "MEMORYREPORT"),
        c("Survey Linework", "point.topleft.down.to.point.bottomright.curvepath", "SURVEYLINES"), c("LAZ Converter", "cloud", "LAZCONVERTER"),
        c("Presentation Out", "play.rectangle", "PRESENTOUT"), c("Documentation Site", "book", "DOCSITE"),
        c("Signing Key", "key", "SIGNKEY"), c("Sign File", "signature", "SIGNFILE"), c("Verify Signature", "checkmark.seal", "VERIFYSIGNATURE"), c("Trust Signer", "person.badge.shield.checkmark", "TRUSTSIGNER"),
    ]

    /// Sections added in round 9 (names unique across `coverageMenus`).
    static var coverageMenus4: [(String, [CmdItem])] {
        [("BIM Types & Parameters", bimRound9), ("Detailing & Tags", annotateRound9), ("Views & Coordinates", viewRound9), ("Mesh & Procedural 3D", modelingRound9),
         ("Block & Reference Editing", blocksRound9), ("Exchange Options", exchangeRound9), ("Navigate, Light & Publish", appRound9), ("Studies, Signatures & Publishing", analysisRound9)]
    }
}
