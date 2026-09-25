// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Catalog of the most common AutoCAD system variables: type, default, allowed range, read-only flag and meaning.
/// `SystemVariables.get/set` use it to validate values, report defaults and compute read-only variables.
public enum SysVarCatalog {
    public enum Kind: String { case integer, real, string, point, flag }
    public struct Info: Equatable {
        public var name: String; public var kind: Kind; public var defaultValue: String
        /// Integer/real range ("min..max") or allowed integers ("0,1,3").
        public var range: String; public var readOnly: Bool; public var summary: String
    }

    // NAME|kind(i r s p b)|default|range|ro|summary
    static let table = """
    ANGBASE|r|0||0|Base angle (degrees) for angle 0
    ANGDIR|i|0|0,1|0|Positive angle direction: 0 counterclockwise, 1 clockwise
    APERTURE|i|10|1..50|0|Object snap target height in pixels
    ARRAYASSOCIATIVITY|b|1||0|New arrays are associative (one editable array object)
    ATTDIA|b|0||0|Attribute prompts in a dialog
    ATTMODE|i|1|0,1,2|0|Attribute display: 0 off, 1 normal, 2 all
    ATTREQ|b|1||0|Prompt for attribute values when inserting blocks
    AUNITS|i|0|0..4|0|Angular units: 0 degrees, 1 d/m/s, 2 grads, 3 radians, 4 surveyor
    AUPREC|i|0|0..8|0|Angular precision (decimals)
    AUTOSNAP|i|63|0..63|0|AutoSnap marker, tooltip, magnet and tracking bits
    BACKZ|r|0||1|Back clipping plane offset
    BLIPMODE|b|0||0|Marker blips
    CANNOSCALE|s|1:1||0|Current annotation scale
    CDATE|r|||1|Current date and time (YYYYMMDD.HHMMSS)
    CECOLOR|s|ByLayer||0|Color of new objects
    CELTSCALE|r|1|>0|0|Linetype scale of new objects
    CELTYPE|s|ByLayer||0|Linetype of new objects
    CELWEIGHT|s|ByLayer||0|Lineweight of new objects
    CENTEREXE|r|0|>=0|0|Centre line extension
    CHAMFERA|r|0|>=0|0|First chamfer distance
    CHAMFERB|r|0|>=0|0|Second chamfer distance
    CHAMFERC|r|0|>=0|0|Chamfer length
    CHAMFERD|r|0||0|Chamfer angle
    CHAMMODE|i|0|0,1|0|Chamfer input: 0 two distances, 1 length and angle
    CIRCLERAD|r|0|>=0|0|Default circle radius
    CLAYER|s|0||0|Current layer
    CLEVEL|s|||0|Current building level
    CMDACTIVE|i|||1|Whether a command is active
    CMDECHO|b|1||0|Echo prompts and input in scripts
    CMDNAMES|s|||1|Name of the active command
    CMLEADERSTYLE|s|Standard||0|Current multileader style
    COORDS|i|1|0,1,2|0|Coordinate display on the status bar
    CPLOTSTYLE|s|ByLayer||0|Plot style of new objects
    CTAB|s|Model||0|Current tab (Model or a layout)
    CURSORSIZE|i|5|1..100|0|Crosshair size in percent of the screen
    CVPORT|i|2|1..64|0|Current viewport number
    DATE|r|||1|Current Julian date
    DBMOD|i|||1|Drawing modification status (bit 1 = modified)
    DEFLPLSTYLE|s|ByColor||0|Default plot style for layer 0
    DELOBJ|i|1|-3..3|0|Keep or delete source objects (region, extrude…)
    DIMADEC|i|0|0..8|0|Angular dimension decimals
    DIMALT|b|0||0|Alternate units in dimensions
    DIMASZ|r|2.5|>=0|0|Arrowhead size (current dimension style)
    DIMAUNIT|i|0|0..4|0|Angular dimension units
    DIMBLK|s|ClosedFilled||0|Arrowhead block (current dimension style)
    DIMCEN|r|2.5||0|Centre mark size
    DIMCLRD|s|ByBlock||0|Dimension line color
    DIMCLRE|s|ByBlock||0|Extension line color
    DIMCLRT|s|ByBlock||0|Dimension text color
    DIMDEC|i|0|0..8|0|Linear dimension decimals (current dimension style)
    DIMDLE|r|0|>=0|0|Dimension line extension past ticks
    DIMDLI|r|3.75|>=0|0|Baseline dimension spacing
    DIMEXE|r|1.25|>=0|0|Extension line extension (current dimension style)
    DIMEXO|r|1|>=0|0|Extension line offset (current dimension style)
    DIMGAP|r|0.8||0|Gap around dimension text (current dimension style)
    DIMLAYER|s|.||0|Layer for new dimensions (. = current)
    DIMLFAC|r|1|>0|0|Linear measurement scale (current dimension style)
    DIMLUNIT|i|2|1..6|0|Linear units for dimensions
    DIMPOST|s|||0|Dimension text suffix (current dimension style)
    DIMRND|r|0|>=0|0|Rounding of dimension values
    DIMSCALE|r|1|>=0|0|Overall dimension scale (current dimension style)
    DIMSTYLE|s|Standard||0|Current dimension style
    DIMTAD|i|1|0..4|0|Vertical text placement
    DIMTIH|b|0||0|Text inside extension lines horizontal
    DIMTOH|b|0||0|Text outside extension lines horizontal
    DIMTXT|r|2.5|>0|0|Dimension text height (current dimension style)
    DIMZIN|i|8|0..15|0|Zero suppression
    DISPSILH|b|0||0|Silhouette curves of solids
    DONUTID|r|0.5|>=0|0|Donut inside diameter
    DONUTOD|r|1|>0|0|Donut outside diameter
    DRAGMODE|i|2|0,1,2|0|Dragging display
    DWGCODEPAGE|s|UTF-8||1|Drawing code page
    DWGNAME|s|||1|Drawing file name
    DWGPREFIX|s|||1|Drawing folder
    DWGTITLED|i|||1|Whether the drawing has been named (saved)
    DYNMODE|i|3|-3..3|0|Dynamic input (pointer and dimensional)
    DYNPICOORDS|i|0|0,1|0|Dynamic input coordinates: 0 relative, 1 absolute
    ELEVATION|r|0||0|Current elevation of new objects
    EXPERT|i|0|0..5|0|Suppress "are you sure" prompts
    EXTMAX|p|||1|Upper-right corner of the drawing extents
    EXTMIN|p|||1|Lower-left corner of the drawing extents
    FACETRES|r|0.5|0.01..10|0|Smoothness of shaded solids
    FILEDIA|b|1||0|File dialogs (0 = type names on the command line)
    FILLETRAD|r|0|>=0|0|Fillet radius
    FILLMODE|b|1||0|Fill solids, wide polylines and hatches
    FONTALT|s|Helvetica||0|Alternate font for missing fonts
    GRIDMODE|b|1||0|Grid display
    GRIDUNIT|p|100||0|Grid spacing
    GRIPBLOCK|b|0||0|Grips inside blocks
    GRIPS|i|1|0,1,2|0|Grip display
    GRIPSIZE|i|5|1..255|0|Grip size in pixels
    HIGHLIGHT|b|1||0|Selection highlighting
    HPANG|r|0||0|Hatch pattern angle
    HPASSOC|b|1||0|Associative hatches
    HPCOLOR|s|.||0|Hatch color (. = current)
    HPGAPTOL|r|0|0..5000|0|Gap tolerance when detecting hatch boundaries
    HPNAME|s|ANSI31||0|Hatch pattern
    HPORIGIN|p|0,0||0|Hatch origin
    HPSCALE|r|1|>0|0|Hatch pattern scale
    HPSEPARATE|b|0||0|Separate hatch per boundary
    HPTRANSPARENCY|s|use current||0|Hatch transparency
    INSBASE|p|0,0||0|Insertion base point of the drawing
    INSNAME|s|||0|Default block name for INSERT
    INSUNITS|i|4|0..24|0|Drawing units for inserted content
    ISOLINES|i|4|0..2047|0|Contour lines on curved solid surfaces
    LASTANGLE|r|||1|End angle of the last arc
    LASTPOINT|p|||1|Last point entered
    LAYERFILTER|s|||0|Layer filter shown in the layer panel
    LAYEREVAL|i|0|0,1,2|0|New layer evaluation
    LAYERNOTIFY|i|0|0..15|0|New layer notification
    LENSLENGTH|r|50|>0|0|Perspective lens length
    LIMCHECK|b|0||0|Prevent drawing outside the limits
    LIMMAX|p|420,297||0|Upper-right drawing limit
    LIMMIN|p|0,0||0|Lower-left drawing limit
    LOCALE|s|en||1|Language code
    LOGINNAME|s|||1|User login name
    LTSCALE|r|1|>0|0|Global linetype scale
    LUNITS|i|2|1..5|0|Linear units: 1 scientific, 2 decimal, 3 engineering, 4 architectural, 5 fractional
    LUPREC|i|0|0..8|0|Linear precision (decimals)
    LWDEFAULT|r|0.25|0..2.11|0|Default lineweight (mm)
    LWDISPLAY|b|1||0|Show lineweights
    LWUNITS|i|1|0,1|0|Lineweight units: 0 inches, 1 millimetres
    MAXACTVP|i|64|2..64|0|Maximum active viewports
    MEASUREINIT|i|1|0,1|0|Initial units: 0 imperial, 1 metric
    MEASUREMENT|i|1|0,1|0|Hatch/linetype units: 0 imperial, 1 metric
    MILLISECS|i|||1|Milliseconds since startup
    MIRRHATCH|b|0||0|Mirror hatch patterns
    MIRRTEXT|b|0||0|Mirror text (1) or keep it readable (0)
    MTEXTED|s|Internal||0|Multiline text editor
    OFFSETDIST|r|100||0|Offset distance (-1 = through)
    OFFSETGAPTYPE|i|0|0,1,2|0|Offset of closed polylines: extend, fillet, chamfer
    ORTHOMODE|b|0||0|Ortho mode
    OSMODE|i|4133|0..32767|0|Running object snap modes (bit code)
    OSNAPCOORD|i|2|0,1,2|0|Typed coordinates override running snaps
    OTRACK|b|1||0|Object snap tracking
    PDMODE|i|0|0..100|0|Point display style
    PDSIZE|r|0||0|Point display size
    PEDITACCEPT|b|0||0|Convert selected lines to polylines without asking
    PELLIPSE|b|0||0|Ellipses drawn as polylines
    PERIMETER|r|||1|Perimeter from the last AREA/LIST
    PICKADD|i|2|0,1,2|0|Selection adds (1/2) or replaces (0)
    PICKAUTO|i|5|0..7|0|Automatic window selection
    PICKBOX|i|3|0..50|0|Selection box size in pixels
    PICKDRAG|i|0|0,1,2|0|Selection window by dragging
    PICKFIRST|b|1||0|Noun-verb selection
    PICKSTYLE|i|1|0..3|0|Group and associative hatch selection
    PLATFORM|s|||1|Operating system
    PLINEGEN|b|0||0|Linetype pattern continuous around polyline vertices
    PLINEWID|r|0|>=0|0|Default polyline width
    POLARADDANG|s|||0|Additional polar tracking angles
    POLARANG|r|45|>0|0|Polar tracking increment (degrees)
    POLARDIST|r|0|>=0|0|Polar snap distance
    POLARMODE|b|1||0|Polar tracking
    POLYSIDES|i|4|3..1024|0|Default number of polygon sides
    PROJECTNAME|s|||0|Project name
    PSLTSCALE|b|1||0|Paper-space linetype scaling
    QTEXTMODE|b|0||0|Quick text (boxes instead of text)
    REGENMODE|b|1||0|Automatic regeneration
    SAVETIME|i|10|0..600|0|Automatic save interval (minutes)
    SELECTIONCYCLING|i|2|0,1,2|0|Selection cycling for overlapping objects
    SELECTIONPREVIEW|i|3|0..3|0|Selection preview highlight
    SELECTSIMILARMODE|i|130|0..255|0|Properties matched by SELECTSIMILAR
    SHORTCUTMENU|i|11|0..31|0|Right-click menus
    SKETCHINC|r|1|>0|0|SKETCH record increment
    SNAPANG|r|0||0|Snap/grid rotation (degrees)
    SNAPBASE|p|0,0||0|Snap/grid origin
    SNAPMODE|b|0||0|Grid snap
    SNAPSTYL|i|0|0,1|0|Snap style: 0 rectangular, 1 isometric
    SNAPTYPE|i|0|0,1|0|Snap type: 0 grid, 1 polar
    SNAPUNIT|p|100||0|Snap spacing
    SPLFRAME|b|0||0|Show spline control frames
    SPLINESEGS|i|8|-32768..32767|0|Segments per spline patch
    SURFTAB1|i|6|2..32766|0|Mesh density in M
    SURFTAB2|i|6|2..32766|0|Mesh density in N
    TABMODE|b|0||0|Tablet mode
    TDCREATE|r|||1|Creation date (Julian)
    TDUPDATE|r|||1|Last update date (Julian)
    TEMPPREFIX|s|||1|Temporary folder
    TEXTEVAL|b|0||0|Evaluate text input as expressions
    TEXTFILL|b|1||0|Fill TrueType text
    TEXTQLTY|i|50|0..100|0|Text resolution
    TEXTSIZE|r|250|>0|0|Default text height
    TEXTSTYLE|s|Standard||0|Current text style
    THICKNESS|r|0||0|Current 3D thickness
    TILEMODE|b|1||0|Model (1) or layout (0) tab
    TOOLTIPS|b|1||0|Tooltips
    TRACEWID|r|1|>=0|0|Default TRACE width
    TRIMMODE|b|1||0|Trim edges when filleting/chamfering
    UCSFOLLOW|b|0||0|Plan view when the UCS changes
    UCSICON|i|3|0..3|0|UCS icon display
    UCSNAME|s|||1|Name of the current UCS
    UCSORG|p|||1|Origin of the current UCS
    UNDOCTL|i|||1|Undo state
    UNITMODE|b|0||0|Unit display format
    USERI1|i|0||0|User integer 1
    USERI2|i|0||0|User integer 2
    USERR1|r|0||0|User real 1
    USERR2|r|0||0|User real 2
    USERS1|s|||0|User string 1
    USERS2|s|||0|User string 2
    VIEWCTR|p|||1|Centre of the current view
    VIEWSIZE|r|||1|Height of the current view
    VISRETAIN|b|1||0|Retain xref layer settings
    VTENABLE|i|3|0..7|0|Smooth view transitions
    WHIPARC|b|0||0|Smooth circle and arc display
    WORLDUCS|i|||1|Whether the UCS is the world coordinate system
    XCLIPFRAME|i|2|0,1,2|0|Xref clip boundary display
    XREFNOTIFY|i|2|0,1,2|0|Changed xref notification
    ZOOMFACTOR|i|60|3..100|0|Mouse wheel zoom step
    ZOOMWHEEL|b|0||0|Reverse wheel zoom direction
    """

    public static let all: [Info] = table.split(whereSeparator: \.isNewline).compactMap { raw in
        let f = raw.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 6 else { return nil }
        let kind: Kind
        switch f[1] { case "i": kind = .integer; case "r": kind = .real; case "p": kind = .point; case "b": kind = .flag; default: kind = .string }
        return Info(name: f[0], kind: kind, defaultValue: f[2], range: f[3], readOnly: f[4] == "1", summary: f[5])
    }
    static let index: [String: Info] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    public static func info(_ name: String) -> Info? { index[name.uppercased()] }

    /// Validates and normalises a value for a catalog variable. Returns (normalised value, nil) or (nil, error message).
    public static func validate(_ info: Info, _ value: String) -> (String?, String?) {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch info.kind {
        case .string: return (v, nil)
        case .flag:
            guard let b = SystemVariables.parseFlag(v) else { return (nil, "\(info.name) requires 0 or 1.") }
            return (b ? "1" : "0", nil)
        case .point:
            let parts = v.split(separator: ",").map { InputParser.parseNumber(String($0).trimmingCharacters(in: .whitespaces)) }
            if parts.count == 1, let x = parts[0] { return ("\(fmt(x, 8)),\(fmt(x, 8))", nil) }
            guard parts.count >= 2, let x = parts[0], let y = parts[1] else { return (nil, "\(info.name) requires a point x,y.") }
            return ("\(fmt(x, 8)),\(fmt(y, 8))", nil)
        case .integer, .real:
            guard let x = InputParser.parseNumber(v) else { return (nil, "\(info.name) requires a number.") }
            if info.kind == .integer && x != x.rounded() { return (nil, "\(info.name) requires an integer.") }
            if let e = check(x, info.range) { return (nil, "\(info.name): \(e)") }
            return (info.kind == .integer ? "\(Int(x))" : fmt(x, 10), nil)
        }
    }
    static func check(_ x: Double, _ range: String) -> String? {
        let r = range.trimmingCharacters(in: .whitespaces)
        if r.isEmpty { return nil }
        if r.hasPrefix(">=") { return x >= Double(r.dropFirst(2))! ? nil : "value must be at least \(r.dropFirst(2))." }
        if r.hasPrefix(">") { return x > Double(r.dropFirst())! ? nil : "value must be greater than \(r.dropFirst())." }
        if let dd = r.range(of: "..") {
            let lo = Double(r[..<dd.lowerBound])!, hi = Double(r[dd.upperBound...])!
            return (lo...hi).contains(x) ? nil : "value must be between \(r[..<dd.lowerBound]) and \(r[dd.upperBound...])."
        }
        let allowed = r.split(separator: ",").compactMap { Double($0) }
        return allowed.contains(x) ? nil : "value must be one of \(r)."
    }

    static func julian(_ d: Date) -> Double { d.timeIntervalSince1970 / 86400 + 2440587.5 }

    /// Read-only variables computed from the session.
    @MainActor public static func computed(_ name: String, _ ed: Editor) -> String? {
        switch name.uppercased() {
        case "DATE", "TDUPDATE": return fmt(julian(Date()), 8)
        case "TDCREATE": return ed.doc.variable("TDCREATE") ?? fmt(julian(Date()), 8)
        case "CDATE":
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd.HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        case "DWGNAME": return ed.fileURL?.lastPathComponent ?? ed.doc.variable("DWGNAME") ?? "Drawing1.archi"
        case "DWGPREFIX": return ed.fileURL.map { $0.deletingLastPathComponent().path + "/" } ?? ""
        case "DWGTITLED": return ed.fileURL == nil ? "0" : "1"
        case "DBMOD": return ed.isDirty ? "1" : "0"
        case "CMDACTIVE": return ed.isIdle ? "0" : "1"
        case "CMDNAMES": return ed.activeCommand?.name ?? ""
        case "LASTPOINT": return ed.lastPoint.map { "\(fmt($0.x, 8)),\(fmt($0.y, 8))" } ?? "0,0"
        case "EXTMIN", "EXTMAX":
            var b = BBox2.empty
            for e in ed.doc.entities where ed.doc.isVisible(layer: e.layer) { b.add(GeometryOps.bounds(e.geometry, doc: ed.doc)) }
            guard !b.isEmpty else { return "0,0" }
            let p = name.uppercased() == "EXTMIN" ? b.min : b.max
            return "\(fmt(p.x, 8)),\(fmt(p.y, 8))"
        case "PLATFORM": return ProcessInfo.processInfo.operatingSystemVersionString
        case "LOGINNAME": return NSUserName()
        case "TEMPPREFIX": return NSTemporaryDirectory()
        case "MILLISECS": return "\(Int(ProcessInfo.processInfo.systemUptime * 1000))"
        case "LOCALE": return Locale.current.languageCode ?? "en"
        case "DWGCODEPAGE": return "UTF-8"
        case "UCSORG": return ed.doc.variable("UCSORG") ?? "0,0"
        case "UCSNAME": return ed.doc.variable("UCSNAME") ?? ""
        case "WORLDUCS": return (ed.doc.variable("UCSORG") ?? "0,0") == "0,0" && Double(ed.doc.variable("UCSANG") ?? "0") ?? 0 == 0 ? "1" : "0"
        case "UNDOCTL": return ed.history.canUndo ? "5" : "1"
        case "PERIMETER", "LASTANGLE", "VIEWCTR", "VIEWSIZE", "BACKZ": return ed.doc.variable(name.uppercased()) ?? "0"
        default: return nil
        }
    }

    /// Variables that mirror a property of the current dimension style.
    static let dimStyleVars: Set<String> = ["DIMASZ", "DIMTXT", "DIMEXO", "DIMEXE", "DIMGAP", "DIMDEC", "DIMLFAC", "DIMPOST", "DIMSCALE", "DIMBLK"]
    static func dimGet(_ n: String, _ s: DimStyle) -> String? {
        switch n {
        case "DIMASZ": return fmt(s.arrowSize, 8)
        case "DIMTXT": return fmt(s.textHeight, 8)
        case "DIMEXO": return fmt(s.extensionOffset, 8)
        case "DIMEXE": return fmt(s.extensionExtend, 8)
        case "DIMGAP": return fmt(s.textGap, 8)
        case "DIMDEC": return "\(s.decimals)"
        case "DIMLFAC": return fmt(s.linearScale, 8)
        case "DIMPOST": return s.suffix
        case "DIMSCALE": return fmt(s.scale, 8)
        case "DIMBLK": return s.arrow.rawValue
        default: return nil
        }
    }
    static func dimSet(_ n: String, _ v: String, _ s: inout DimStyle) -> Bool {
        let x = Double(v) ?? 0
        switch n {
        case "DIMASZ": s.arrowSize = x
        case "DIMTXT": s.textHeight = x
        case "DIMEXO": s.extensionOffset = x
        case "DIMEXE": s.extensionExtend = x
        case "DIMGAP": s.textGap = x
        case "DIMDEC": s.decimals = Int(x)
        case "DIMLFAC": s.linearScale = x
        case "DIMPOST": s.suffix = v
        case "DIMSCALE": s.scale = x
        case "DIMBLK":
            guard let a = ArrowKind.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(v) == .orderedSame }) ?? (v.lowercased() == "archtick" ? .architecturalTick : nil) else { return false }
            s.arrow = a
        default: return false
        }
        return true
    }
}
