// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Ribbon/menu catalogs that complete the command coverage: every registered command is reachable from the ribbon
/// (a button or a "More" menu), from the menu bar, or from a palette. `CommandCatalog.coverage(_:)` reports the rest.
extension CommandCatalog {
    private static func c(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }

    static let drawMore: [CmdItem] = [
        c("Ray", "arrow.up.right", "RAY"), c("Construction Line", "line.diagonal.arrow", "XLINE", "XL"), c("Point", "smallcircle.filled.circle", "POINT", "PO"),
        c("Point Style", "circle.dotted", "PTYPE"), c("Donut", "circle.circle", "DONUT"), c("Region", "square.on.circle", "REGION", "REG"),
        c("Boundary", "square.dashed", "BOUNDARY", "BO"), c("Revision Cloud", "cloud", "REVCLOUD"), c("Wipeout", "rectangle.fill", "WIPEOUT"),
        c("Sketch", "scribble", "SKETCH"), c("Multiline", "equal", "MLINE", "ML"), c("Multiline Style", "equal.square", "MLSTYLE"),
        c("Double Line", "equal.circle", "DLINE"), c("2D Solid", "triangle.fill", "SOLID", "SO"), c("Star", "star", "STAR"),
        c("Polygon by Side", "hexagon", "POLYGONSS"), c("Snake Line", "water.waves", "SNAKE"), c("Parabola", "chart.xyaxis.line", "PARABOLA"),
        c("Hyperbola", "point.topleft.down.curvedto.point.bottomright.up", "HYPERBOLA"), c("Centerline", "line.3.horizontal.decrease", "CENTERLINE"),
        c("Center Mark", "plus.circle", "CENTERMARK"), c("Bounding Box", "rectangle.dashed", "BOUNDINGBOX"), c("Point Lattice", "circle.grid.3x3", "POINTLATTICE"),
        c("Points on Line", "ellipsis", "POINTSLINE"),
    ]
    static let construction: [CmdItem] = [
        c("Parallel Line", "equal", "LINEPAR"), c("Perpendicular Line", "angle", "LINEPERP"), c("Line at Angle", "angle", "LINEANG"),
        c("Bisector", "arrow.triangle.branch", "LINEBISECT"), c("Horizontal/Vertical", "plus", "LINEHV"), c("Relative Line", "arrow.up.right", "LINEREL"),
        c("Tangent Line", "circle.and.line.horizontal", "LINETAN"), c("Tangent to 2 Circles", "circle.circle", "LINETAN2"), c("Tangent Ortho", "circle.bottomhalf.filled", "LINETANORTHO"),
        c("Circle 2 Points + R", "circle", "CIRCLE2PR"), c("Circle Tan-Pt-Pt", "circle", "CIRCLETPP"), c("Circle Tan-Tan-Pt", "circle", "CIRCLETTP"),
        c("Circle Tan-Tan-Tan", "circle", "CIRCLETTT"), c("Incircle", "circle.inset.filled", "INCIRCLE"), c("Arc 2 Pts + Height", "rainbow", "ARC2PH"),
        c("Arc 2 Pts + Length", "rainbow", "ARC2PL"), c("Arc to Circle", "circle.dashed", "ARCTOCIRCLE"), c("Ellipse 4 Points", "oval", "ELLIPSE4P"),
        c("Ellipse Center 3P", "oval", "ELLIPSEC3P"), c("Ellipse by Foci", "oval", "ELLIPSEFOCI"), c("Multiple Offset", "square.on.square.dashed", "OFFSETMULTI"),
        c("Cut by Line", "scissors", "CUTBYLINE"),
    ]
    static let modifyMore: [CmdItem] = [
        c("Align", "align.horizontal.left", "ALIGN", "AL"), c("Align to Reference", "align.vertical.center", "ALIGNREF"), c("Path Array", "point.topleft.down.curvedto.point.bottomright.up", "ARRAYPATH"),
        c("Polar Array", "circle.hexagongrid", "ARRAYPOLAR"), c("Break All", "scissors.badge.ellipsis", "BREAKALL"), c("Break at Point", "minus.square", "BREAKATPOINT"),
        c("Change Properties", "slider.horizontal.3", "CHPROP"), c("Clip Polyline", "crop", "CLIPPOLY"), c("Convert to Polyline", "point.3.connected.trianglepath.dotted", "CONVERTTOPLINE"),
        c("Divide", "divide", "DIVIDE", "DIV"), c("Measure", "ruler", "MEASURE", "ME"), c("Draw Order", "square.3.layers.3d.down.right", "DRAWORDER", "DR"),
        c("Text to Front", "textformat", "TEXTTOFRONT"), c("Hatch to Back", "square.grid.3x3.bottomleft.filled", "HATCHTOBACK"), c("Extend By", "arrow.right.to.line", "EXTENDBY"),
        c("Lengthen", "arrow.left.and.right", "LENGTHEN", "LEN"), c("Line Gap", "line.3.horizontal", "LINEGAP"), c("Move + Rotate", "arrow.triangle.2.circlepath", "MOVEROTATE"),
        c("Rotate by Reference", "arrow.clockwise.circle", "ROTATE2"), c("Nudge", "arrow.up.and.down.and.arrow.left.and.right", "NUDGE"), c("Oops (Restore Erased)", "arrow.uturn.backward", "OOPS"),
        c("Overkill", "trash.slash", "OVERKILL"), c("Edit Polyline", "point.topleft.down.curvedto.point.bottomright.up", "PEDIT", "PE"), c("Polyline to Spline", "scribble.variable", "PLINETOSPLINE"),
        c("Reverse", "arrow.left.arrow.right", "REVERSE"), c("Weld", "link", "WELD"), c("Set ByLayer", "square.3.layers.3d", "SETBYLAYER"),
        c("Paste to Points", "doc.on.clipboard", "PASTETOPOINTS"), c("Region Union", "square.on.square", "REGIONUNION"), c("Region Subtract", "minus.square", "REGIONSUBTRACT"),
        c("Region Intersect", "square.on.square.intersection.dashed", "REGIONINTERSECT"), c("Edit Hatch", "square.grid.3x3.fill", "HATCHEDIT", "HE"),
        c("Hatch Boundary", "square.dashed", "HATCHGENERATEBOUNDARY"),
    ]
    static let clipboard: [CmdItem] = [
        c("Copy", "doc.on.doc", "COPYCLIP"), c("Cut", "scissors", "CUTCLIP"), c("Copy with Base Point", "doc.on.doc.fill", "COPYBASE"),
        c("Paste", "doc.on.clipboard", "PASTECLIP"), c("Paste as Block", "square.on.square.dashed", "PASTEBLOCK"), c("Undo", "arrow.uturn.backward", "UNDO", "U"),
        c("Redo", "arrow.uturn.forward", "REDO"), c("Select", "cursorarrow", "SELECT"), c("Select All", "checkmark.rectangle.stack", "SELECTALL"),
        c("Quick Select…", "line.3.horizontal.decrease.circle", "QSELECTDIALOG"),
    ]
    static let dimMore: [CmdItem] = [
        c("Smart Dimension", "ruler", "DIM"), c("Quick Dimension", "ruler.fill", "QDIM"), c("Baseline", "arrow.right.to.line", "DIMBASELINE", "DBA"),
        c("Continue", "arrow.right", "DIMCONTINUE", "DCO"), c("Arc Length", "rainbow", "DIMARC"), c("Ordinate", "number", "DIMORDINATE", "DOR"),
        c("Dimension Break", "scissors", "DIMBREAK"), c("Dimension Space", "arrow.up.and.down.text.horizontal", "DIMSPACE"), c("Edit Dimension", "pencil", "DIMEDIT"),
        c("Move Dim Text", "text.cursor", "DIMTEDIT"), c("Dim Override", "slider.horizontal.below.rectangle", "DIMOVERRIDE"), c("Reassociate", "link", "DIMREASSOCIATE"),
        c("Disassociate", "link.badge.plus", "DIMDISASSOCIATE"), c("Regenerate Dims", "arrow.clockwise", "DIMREGEN"), c("Dimension Style", "ruler", "DIMSTYLE", "D"),
        c("Tolerance", "square.grid.2x2", "TOLERANCE"), c("Dimension Walls", "rectangle.split.3x1", "AUTODIMWALLS"), c("Spot Elevation", "arrowtriangle.down", "SPOTELEV"),
        c("Spot Slope", "arrow.down.right", "SPOTSLOPE"),
    ]
    static let textMore: [CmdItem] = [
        c("Edit Text", "pencil", "TEXTEDIT", "ED"), c("Text Style", "textformat", "TEXTSTYLE", "ST"), c("Find & Replace", "magnifyingglass", "FIND"),
        c("Spelling", "textformat.abc.dottedunderline", "SPELL", "SP"), c("Spelling Dialog", "text.badge.checkmark", "SPELLDIALOG"), c("Field", "curlybraces", "FIELD"), c("Update Fields", "arrow.clockwise", "UPDATEFIELD"),
        c("Justify Text", "text.justify", "JUSTIFYTEXT"), c("Scale Text", "textformat.size", "SCALETEXT"), c("Text to MText", "text.alignleft", "TXT2MTXT"),
        c("Readable Text", "textformat.alt", "TEXTREADABLE"), c("Arc Text", "rainbow", "ARCTEXT"), c("Annotative", "a.magnify", "ANNOTATIVE"),
        c("Scale List", "list.number", "SCALELISTEDIT"), c("Leader Style", "text.bubble", "MLEADERSTYLE"), c("Align Leaders", "align.horizontal.left", "MLEADERALIGN"),
        c("Collect Leaders", "text.bubble.fill", "MLEADERCOLLECT"), c("Edit Table", "tablecells", "TABLEEDIT"), c("Export Table", "square.and.arrow.up", "TABLEEXPORT"),
        c("Link Table", "link", "TABLELINK"), c("Update Data Links", "arrow.triangle.2.circlepath", "DATALINKUPDATE"), c("North Arrow", "location.north", "NORTHARROW"),
        c("Scale Bar", "ruler", "SCALEBAR"), c("Break Line", "bolt.horizontal", "BREAKLINE"),
    ]
    static let parametric: [CmdItem] = [
        c("Geometric", "link.circle", "GEOMCONSTRAINT", "GCON"), c("Auto Constrain", "wand.and.stars", "AUTOCONSTRAIN"), c("Dimensional", "ruler", "DIMCONSTRAINT"),
        c("Convert Dims", "arrow.triangle.swap", "DCCONVERT"), c("Parameters", "function", "PARAMETERS", "PARAM"), c("List Constraints", "list.bullet", "CONSTRAINTLIST"),
        c("Delete Constraints", "trash", "DELCONSTRAINT"),
        c("Coincident", "smallcircle.filled.circle", "GCCOINCIDENT"), c("Horizontal", "arrow.left.and.right", "GCHORIZONTAL"), c("Vertical", "arrow.up.and.down", "GCVERTICAL"),
        c("Parallel", "equal", "GCPARALLEL"), c("Perpendicular", "angle", "GCPERPENDICULAR"), c("Collinear", "line.diagonal", "GCCOLLINEAR"),
        c("Equal", "equal.circle", "GCEQUAL"), c("Fix", "lock", "GCFIX"), c("Concentric", "circle.circle", "GCCONCENTRIC"), c("Tangent", "circle.and.line.horizontal", "GCTANGENT"),
        c("Symmetric", "arrow.left.and.right.righttriangle.left.righttriangle.right", "GCSYMMETRIC"), c("Midpoint", "circle.and.line.horizontal", "GCMIDPOINT"),
        c("Point on Curve", "point.topleft.down.curvedto.point.bottomright.up", "GCPOINTONCURVE"),
        c("Linear (dim)", "ruler", "DCLINEAR"), c("Horizontal (dim)", "arrow.left.and.right", "DCHORIZONTAL"), c("Vertical (dim)", "arrow.up.and.down", "DCVERTICAL"),
        c("Aligned (dim)", "arrow.up.right", "DCALIGNED"), c("Angular (dim)", "angle", "DCANGULAR"), c("Radius (dim)", "circle.and.line.horizontal", "DCRADIUS"),
        c("Diameter (dim)", "circle.circle", "DCDIAMETER"), c("Ratio (dim)", "divide", "DCRATIO"), c("Difference (dim)", "minus", "DCDIFFERENCE"),
    ]
    static let blocksMore: [CmdItem] = [
        c("Block Library", "books.vertical", "BLOCKLIBRARY"), c("Write Block", "square.and.arrow.down", "WBLOCK", "W"), c("Drawing Base", "scope", "BASE"),
        c("Block Base Point", "scope", "BLOCKBASE"), c("Replace Block", "arrow.triangle.swap", "BLOCKREPLACE"), c("Count Blocks", "number.circle", "BCOUNT"),
        c("Flip Block", "arrow.left.and.right.righttriangle.left.righttriangle.right", "BFLIP"), c("Visibility State", "eye", "BVSTATE"),
        c("Edit Attributes", "character.textbox", "ATTEDIT"), c("Sync Attributes", "arrow.triangle.2.circlepath", "ATTSYNC"), c("Attribute Manager", "list.bullet.rectangle", "BATTMAN"),
        c("Extract Attributes", "square.and.arrow.up", "ATTEXT"), c("Data Extraction", "tablecells", "DATAEXTRACTION"), c("Bind Xref", "link.badge.plus", "XBIND"),
    ]
    static let layersMore: [CmdItem] = [
        c("Layer Properties", "square.3.layers.3d", "LAYER", "LA"), c("Layer States", "rectangle.stack", "LAYERSTATE"), c("Layer Filter", "line.3.horizontal.decrease", "LAYERFILTER"),
        c("Layer Filter (cmd)", "line.3.horizontal.decrease.circle", "LAYFILTER"), c("Change to Current", "arrow.down.to.line", "LAYCUR"), c("Make Current", "checkmark.circle", "LAYMCUR"),
        c("Delete Layer", "trash", "LAYDEL"), c("Merge Layers", "arrow.triangle.merge", "LAYMRG"), c("Freeze", "snowflake", "LAYFRZ"), c("Thaw All", "sun.max", "LAYTHW"),
        c("Off", "eye.slash", "LAYOFF"), c("All On", "eye", "LAYON"), c("Isolate", "eye.circle", "LAYISO"), c("Unisolate", "eye.circle.fill", "LAYUNISO"),
        c("Lock", "lock", "LAYLCK"), c("Unlock", "lock.open", "LAYULK"), c("Layer Previous", "arrow.uturn.backward", "LAYERP"), c("Translate Layers", "arrow.left.arrow.right", "LAYTRANS"),
        c("Layer Walk", "figure.walk", "LAYWALK"), c("Viewport Layers", "rectangle.on.rectangle", "VPLAYER"), c("Color", "paintpalette", "COLOR", "COL"),
        c("Linetype", "line.3.horizontal", "LINETYPE", "LT"), c("Lineweight", "lineweight", "LWEIGHT", "LW"), c("Linetype Scale", "ruler", "LTSCALE"), c("Rename", "pencil", "RENAME", "REN"),
    ]
    static let bimMore: [CmdItem] = [
        c("Level", "building.2", "LEVEL", "LEVELS"), c("Schedule", "tablecells", "SCHEDULE"), c("Set Property", "slider.horizontal.3", "SETPROP"),
        c("Properties", "info.circle", "PROPERTIES", "PR"), c("Color Fill Plan", "paintbrush", "COLORFILL"), c("Room Finishes", "square.grid.3x3.topleft.filled", "ROOMFINISH"),
        c("Opening Parts", "door.left.hand.closed", "OPENINGPARTS"), c("Reflected Ceiling", "square.3.layers.3d.top.filled", "RCP"), c("Design Options", "square.on.square", "DESIGNOPTION"),
        c("Worksets", "person.2", "WORKSET"),
    ]
    static let structure: [CmdItem] = [
        c("Beam System", "square.split.1x2", "BEAMSYSTEM"), c("Brace", "line.diagonal", "BRACE"), c("Truss", "triangle", "TRUSS"), c("Steel Profile", "i.square", "STEELPROFILE"),
        c("Analytical Model", "point.3.connected.trianglepath.dotted", "ANALYTICALMODEL"), c("Frame Analysis", "waveform.path.ecg", "FRAMEANALYSIS"),
    ]
    static let mep: [CmdItem] = [
        c("Duct", "wind", "DUCT"), c("Pipe", "drop", "MEPPIPE"), c("Cable Tray", "cable.connector", "CABLETRAY"), c("Conduit", "bolt", "CONDUIT"),
        c("Connectors", "powerplug", "MEPCONNECTORS"),
    ]
    static let siteMore: [CmdItem] = [
        c("Property Line", "square.dashed", "PROPERTYLINE"), c("Subregion", "square.on.square.dashed", "SUBREGION"), c("Site Path", "road.lanes", "SITEPATH"),
        c("Parking", "car", "PARKINGLOT"), c("Retaining Wall", "rectangle.bottomthird.inset.filled", "RETAININGWALL"), c("Import DEM", "mountain.2", "DEMIMPORT"),
    ]
    static let surfaces: [CmdItem] = [
        c("Ruled Surface", "square.stack.3d.up", "RULESURF"), c("Tabulated Surface", "square.stack.3d.forward.dottedline", "TABSURF"), c("Revolved Surface", "arrow.triangle.2.circlepath", "REVSURF"),
        c("Edge Surface", "square.dashed", "EDGESURF"), c("Fillet Edges", "square.on.circle", "FILLETEDGE", "FILLET3D"), c("Chamfer Edges", "triangle.lefthalf.filled", "CHAMFEREDGE", "CHAMFER3D"), c("Repair Mesh", "wrench.and.screwdriver", "MESHREPAIR"), c("Decimate Mesh", "circle.hexagongrid", "MESHDECIMATE"),
    ]
    static let analysisMore: [CmdItem] = [
        c("Heat Loss", "thermometer", "HEATLOSS"), c("U-Value", "square.stack", "UVALUE"), c("Daylight", "sun.max", "DAYLIGHT"), c("Solar Radiation", "sun.dust", "SOLARRADIATION"),
        c("Sun Path", "sun.haze", "SUNPATH"), c("Isovist", "eye", "ISOVIST"), c("Reverberation", "waveform", "REVERB"), c("Embodied Carbon", "leaf", "CARBON"),
        c("Level Areas", "square.stack.3d.up", "LEVELAREAS"), c("Code Check", "checkmark.shield", "CODECHECK"), c("Code Rules", "list.bullet.clipboard", "CODERULES"),
        c("Standards Check", "checkmark.seal", "STANDARDSCHECK"), c("Validate IFC", "building.columns", "IFCVALIDATE"), c("IDS Check", "checkmark.rectangle", "IDSCHECK"),
        c("Calculator", "plusminus", "CAL"), c("Measure Geometry", "ruler", "MEASUREGEOM", "MEA"), c("Status", "info.circle", "STATUS"),
    ]
    static let exchange: [CmdItem] = [
        c("DWG In", "doc", "DWGIN"), c("DWG Converter", "arrow.triangle.2.circlepath", "DWGCONVERTER"), c("STEP In", "cube", "STEPIN"), c("Shapefile", "map", "SHPIMPORT"),
        c("OpenStreetMap", "map.fill", "OSMIMPORT"), c("CityJSON", "building.2", "CITYJSONIMPORT"), c("Point Cloud", "aqi.medium", "POINTCLOUDIMPORT"), c("Excel In", "tablecells", "XLSXIN"),
        c("DWG Out", "doc.fill", "DWGOUT"), c("STEP Out", "cube.fill", "STEPOUT"), c("Collada", "cube.transparent", "DAEOUT"), c("PLY", "aqi.low", "PLYOUT"),
        c("gbXML", "thermometer", "GBXMLOUT"), c("COBie", "tablecells.fill", "COBIEOUT"), c("IFC ZIP", "doc.zipper", "IFCZIPOUT"), c("HPGL", "printer", "HPGLOUT"),
        c("Excel Out", "tablecells.badge.ellipsis", "XLSXOUT"),
    ]
    static let fileCommands: [CmdItem] = [
        c("New", "doc", "NEW"), c("Open", "folder", "OPEN"), c("Save", "square.and.arrow.down", "SAVE"), c("Save As", "square.and.arrow.down.on.square", "SAVEAS"),
        c("Close", "xmark", "CLOSE"), c("Import", "square.and.arrow.down", "IMPORT"), c("Export", "square.and.arrow.up", "EXPORT"), c("Plot", "printer", "PLOT"),
        c("Drawing Recovery", "lifepreserver", "DRAWINGRECOVERY"), c("Run Script", "play.rectangle", "SCRIPT"), c("Script Text", "text.alignleft", "SCRIPTTEXT"),
        c("Quit", "power", "QUIT"),
    ]
    static let tools: [CmdItem] = [
        c("Record Action", "record.circle", "ACTRECORD"), c("Stop Recording", "stop.circle", "ACTSTOP"), c("Play Action", "play.circle", "ACTPLAY"),
        c("Action Manager", "list.bullet.rectangle", "ACTMANAGER"), c("Record Script", "record.circle.fill", "SCRIPTRECORD"), c("Aliases", "character.cursor.ibeam", "ALIAS"),
        c("Command History", "clock.arrow.circlepath", "HISTORY"), c("Script Console", "terminal", "SCRIPTCONSOLE"), c("Script Library", "books.vertical", "SCRIPTLIBRARY"),
        c("Node Editor", "point.3.connected.trianglepath.dotted", "NODEEDITOR"), c("Agent Settings", "antenna.radiowaves.left.and.right", "AGENTSETTINGS"),
        c("Connect Claude", "sparkles", "CONNECTCLAUDE"),
    ]
    static let settingsMore: [CmdItem] = [
        c("Options", "gearshape", "OPTIONS"), c("Units", "ruler", "UNITS", "UN"), c("Drafting Settings", "slider.horizontal.3", "DSETTINGS", "DS"), c("Limits", "rectangle.dashed", "LIMITS"),
        c("Isometric Drafting", "cube", "ISODRAFT"), c("Isoplane", "square.3.layers.3d", "ISOPLANE"), c("UCS", "move.3d", "UCS"), c("Named UCS", "list.bullet", "UCSMAN"),
        c("Snap", "circle.grid.3x3", "SNAP"), c("Grid", "grid", "GRIDDISPLAY"), c("Ortho", "plus", "ORTHO"), c("Object Snap", "scope", "OSNAP", "OS"),
        c("Cursor Size", "plus.viewfinder", "CURSORSIZE"), c("Autosave Interval", "clock", "SAVETIME"), c("System Variable", "slider.horizontal.below.square.filled.and.square", "SETVAR"),
        c("Audit", "checkmark.shield", "AUDIT"), c("Purge", "trash.slash", "PURGE", "PU"),
    ]
    static let viewMore: [CmdItem] = [
        c("Zoom", "plus.magnifyingglass", "ZOOM", "Z"), c("Pan", "hand.draw", "PAN", "P"), c("Regenerate", "arrow.clockwise", "REGEN", "RE"), c("Named Views", "binoculars", "VIEW", "V"),
        c("Layout", "doc.richtext", "LAYOUT"), c("Viewports", "rectangle.split.2x2", "MVIEW", "MV"), c("2D Plan", "square", "SHOW2D"), c("3D Model", "cube", "SHOW3D"),
        c("Split View", "rectangle.split.2x1", "SPLIT"), c("Visual Style", "circle.lefthalf.filled", "VSCURRENT"), c("Render", "camera.aperture", "RENDER"), c("Walk", "figure.walk", "WALK"),
        c("View Cube", "cube", "NAVVCUBE"), c("Orbit Selection", "scope", "ORBITSELECTION"), c("Save Camera", "camera", "SAVECAMERA"), c("Cameras", "camera.on.rectangle", "CAMERA"),
        c("Section Box", "cube.transparent", "SECTIONBOX"), c("Sun Study", "sun.max", "SUNSTUDY"), c("Top", "square.tophalf.filled", "TOPVIEW"), c("Bottom", "square.bottomhalf.filled", "BOTTOMVIEW"),
        c("Front", "square.bottomhalf.filled", "FRONTVIEW"), c("Back", "square.tophalf.filled", "BACKVIEW"), c("Left", "square.lefthalf.filled", "LEFTVIEW"), c("Right", "square.righthalf.filled", "RIGHTVIEW"),
        c("SW Iso", "cube", "ISOVIEW"), c("SE Iso", "cube", "SEISO"), c("NE Iso", "cube", "NEISO"), c("NW Iso", "cube", "NWISO"),
        c("Workspace", "rectangle.3.group", "WSCURRENT"), c("Save Workspace", "rectangle.3.group.bubble", "WSSAVE"), c("Clean Screen On", "rectangle.dashed", "CLEANSCREENON"),
        c("Clean Screen Off", "rectangle", "CLEANSCREENOFF"), c("Float Panel", "macwindow.on.rectangle", "FLOATPANEL"), c("History Panel", "clock.arrow.circlepath", "HISTORYPANEL"),
        c("Tool Palettes", "square.grid.3x3.square", "TOOLPALETTES"), c("Close Tool Palettes", "xmark.square", "TOOLPALETTESCLOSE"), c("Materials", "paintpalette", "MATERIALS"),
        c("Material Library", "books.vertical", "MATBROWSER"),
    ]
    static let outputMore: [CmdItem] = [
        c("Section Sheet Style", "paintpalette", "SECTIONSTYLE"),
        c("Page Setup", "doc.badge.gearshape", "PAGESETUP"), c("Plot Preview", "eye", "PREVIEW"), c("Publish", "doc.on.doc", "PUBLISH"), c("Title Block", "list.bullet.rectangle.portrait", "TITLEBLOCK"),
        c("Sheet Set", "rectangle.stack", "SHEETSET"), c("Sheet Index", "list.number", "SHEETINDEX"), c("Revision", "clock.badge.checkmark", "SHEETREVISION"),
        c("Renumber Sheets", "number", "SHEETRENUMBER"), c("Editable View Titles", "textformat.size", "SHEETVIEWTITLES"), c("View Title", "textformat", "VIEWTITLE"),
        c("Lock Viewports", "lock.rectangle", "VPLOCK"),
    ]
    static let animationItems: [CmdItem] = [
        c("Walkthrough Video", "film", "WALKTHROUGHVIDEO"), c("Sun Study Video", "sun.max.trianglebadge.exclamationmark", "SUNSTUDYVIDEO"),
        c("360° Panorama", "pano", "PANORAMA"), c("Section Plane", "square.split.diagonal", "SECTIONPLANE"),
    ]
    static let plotItems: [CmdItem] = [
        c("Plot Styles", "paintpalette", "PLOTSTYLE"), c("Batch Publish", "doc.on.doc.fill", "BATCHPUBLISH"), c("Plot Log", "list.bullet.clipboard", "PLOTLOG"),
    ]
    static let startItems: [CmdItem] = [
        c("Start Screen", "house", "STARTSCREEN"), c("New from Template", "doc.badge.plus", "NEWFROMTEMPLATE"), c("Save as Template", "doc.badge.arrow.up", "SAVEASTEMPLATE"),
        c("Theme", "circle.lefthalf.filled", "THEME"), c("Constraint Bar", "eye.square", "CONSTRAINTBAR"),
    ]
    static let helpCommands: [CmdItem] = [
        c("Help", "questionmark.circle", "HELP"), c("Command List", "list.bullet", "COMMANDS"), c("Search Commands", "magnifyingglass", "COMMANDSEARCH"),
        c("About", "info.circle", "ABOUT"), c("Self Test", "checkmark.seal", "APPSELFTEST"), c("Export Command Reference", "square.and.arrow.up", "EXPORTCOMMANDS"),
    ]

    /// Commands that are system variables typed as commands: reachable from the System Variables menu.
    @MainActor static var variableItems: [CmdItem] {
        (SystemVariables.known + SystemVariables.stored).sorted().map { CmdItem(title: $0, symbol: "slider.horizontal.3", names: [$0]) }
    }

    /// Catalogs added to complete coverage, with their menu titles (menu bar "Tools" and ribbon "More" menus).
    static var coverageMenus: [(String, [CmdItem])] {
        [("Draw More", drawMore), ("Construction", construction), ("Modify More", modifyMore), ("Clipboard & Selection", clipboard),
         ("Dimensions More", dimMore), ("Text & Tables", textMore), ("Parametric", parametric), ("Blocks & Attributes", blocksMore),
         ("Layers", layersMore), ("BIM Data", bimMore), ("Structure", structure), ("MEP", mep), ("Site More", siteMore), ("Surfaces & Mesh", surfaces),
         ("Analysis", analysisMore), ("Exchange", exchange), ("File", fileCommands), ("Tools & Scripting", tools), ("Settings", settingsMore),
         ("View", viewMore), ("Output", outputMore), ("Animation & Export", animationItems), ("Plot Styles", plotItems),
         ("Start & Templates", startItems), ("Help", helpCommands)] + coverageMenus2 + beautyMenus
    }

    /// Every ribbon/menu item of the curated catalogs (the original ones plus the coverage catalogs).
    static var curatedItems: [CmdItem] { allItems + coverageMenus.flatMap(\.1) }

    struct Coverage {
        /// Registered commands with no ribbon, menu or palette entry.
        var missing: [String]
        /// Commands intentionally reached another way (name → where).
        var intentional: [String: String]
        var total: Int
    }

    /// Commands reachable only through a palette or dynamic menu, by rule (name → reason).
    @MainActor static func intentional(_ d: CommandDef) -> String? {
        if d.category == "Settings" && d.summary.hasPrefix("System variable") { return "System Variables menu (Manage ▸ System Variables)" }
        return nil
    }

    /// Coverage of the registry by the curated ribbon/menu catalogs.
    @MainActor static func coverage(_ registry: CommandRegistry) -> Coverage {
        var covered: Set<String> = []
        for item in curatedItems { for n in item.names { if let d = registry.lookup(n) { covered.insert(d.name) } } }
        var missing: [String] = [], why: [String: String] = [:]
        for d in registry.sorted where !covered.contains(d.name) {
            if let r = intentional(d) { why[d.name] = r } else { missing.append(d.name) }
        }
        return Coverage(missing: missing, intentional: why, total: registry.sorted.count)
    }
}

/// Ribbon "More" button listing several catalogs as submenus.
struct RibbonCatalogMenu: View {
    @ObservedObject var model: AppModel
    let title: String
    let symbol: String
    let sections: [(String, [CmdItem])]
    var help = ""

    var body: some View {
        Menu {
            ForEach(sections, id: \.0) { name, items in
                Menu(name) {
                    ForEach(items) { item in
                        let r = model.command(item.names)
                        Button { if let r { model.runCommand(item.args.isEmpty ? r : r + " " + item.args) } } label: { Label(item.title, systemImage: item.symbol) }
                            .disabled(r == nil)
                            .help(r.flatMap { model.editor.registry.lookup($0) }.map { "\(item.title) — \($0.summary)  [\($0.name)\($0.aliases.isEmpty ? "" : ", " + $0.aliases.joined(separator: ", "))]" } ?? "")
                    }
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19)).frame(height: 24)
                Text(title).font(.system(size: 10))
            }
            .frame(width: 50, height: 58, alignment: .top).padding(.top, 4)
            .foregroundStyle(Theme.text)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(help.isEmpty ? title : help)
    }
}
