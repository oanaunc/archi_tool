// Oanarina Archi Tool — GPL-3.0-or-later
// Portable plotting for archi-engine (Plot / Print / Publish / Export PDF of the Windows shell): the Mac app's pen
// resolution (ArchiApp/Plotter.swift PlotRenderer), plot style tables (AppAlgorithms.swift PlotStyleTable,
// AppNavigation.swift NamedPlotStyles), the sheet composition (Plotter.swift SheetComposer: viewports, frame, title
// block, custom title blocks, north arrow, scale bar, revision table, viewport captions), the plot stamp
// (PlotExtras.swift PlotStamp), shade plots of 3D viewports (ShadePlot.swift) and the model-space plot frame
// (Plotter.modelFrame / writeModelPDF, LayeredPDF.modelPage). The pages are written by EnginePDF (PDF, layered PDF)
// and EnginePlotSVG (preview and Windows printing), so every output shows the same thing as on the Mac.
import Foundation

// MARK: - Plot style tables (colour-dependent CTB and named STB)

/// A pen of a plot style table: output colour (0xRRGGBB, nil = object colour), lineweight (mm, nil = object's),
/// screening in percent (100 = full ink). Same JSON as the Mac PlotStyleTable.Pen.
public struct EnginePen: Codable, Hashable {
    public var color: UInt32?
    public var lineweight: Double?
    public var screening: Double = 100
    public init(color: UInt32? = nil, lineweight: Double? = nil, screening: Double = 100) {
        self.color = color; self.lineweight = lineweight; self.screening = screening
    }
    enum CodingKeys: String, CodingKey { case color, lineweight, screening }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(UInt32.self, forKey: .color)
        lineweight = try c.decodeIfPresent(Double.self, forKey: .lineweight)
        screening = try c.decodeIfPresent(Double.self, forKey: .screening) ?? 100
    }

    /// Plotted colour of a pen: its colour (or the object's), then screening towards white.
    public func apply(to c: RGBA) -> RGBA {
        var out = c
        if let v = color {
            let r = Double(v >> 16 & 255) / 255, g = Double(v >> 8 & 255) / 255, b = Double(v & 255) / 255
            out = RGBA(r, g, b, c.a)
        }
        let k = min(max(screening, 0), 100) / 100
        if k < 1 {
            let r = 1 - (1 - out.r) * k, g = 1 - (1 - out.g) * k, b = 1 - (1 - out.b) * k
            out = RGBA(r, g, b, out.a)
        }
        return out
    }
}

/// Colour-dependent plot style table (CTB): each ACI colour maps to a pen; index 0 is the pen of true colours.
/// Stored in the drawing as "PLOTSTYLE:<NAME>" = the Mac PlotStyleTable JSON.
public struct EnginePlotStyleTable: Codable, Hashable {
    public var name: String
    public var pens: [Int: EnginePen] = [:]
    public init(name: String, pens: [Int: EnginePen] = [:]) { self.name = name; self.pens = pens }

    public static let variablePrefix = "PLOTSTYLE:"

    public func pen(for c: RGBA) -> EnginePen? {
        if let i = EnginePlotStyleTable.aciIndex(c), let p = pens[i] { return p }
        return pens[0]
    }
    /// Plotted colour and lineweight of an object colour / lineweight.
    public func resolve(color c: RGBA, lineweight w: Double) -> (RGBA, Double) {
        guard let p = pen(for: c) else { return (c, w) }
        return (p.apply(to: c), p.lineweight ?? w)
    }

    /// ACI index of an exact ACI colour (black counts as ACI 7, which plots black on paper), else nil.
    public static func aciIndex(_ c: RGBA) -> Int? {
        if c.r < 0.004 && c.g < 0.004 && c.b < 0.004 { return 7 }
        for i in 1...255 {
            let a = aciColor(i)
            if abs(a.r - c.r) < 0.004 && abs(a.g - c.g) < 0.004 && abs(a.b - c.b) < 0.004 { return i }
        }
        return nil
    }

    public static let monochrome: EnginePlotStyleTable = {
        var t = EnginePlotStyleTable(name: "monochrome.ctb")
        for i in 0...255 { t.pens[i] = EnginePen(color: 0x000000) }
        return t
    }()
    public static let grayscale: EnginePlotStyleTable = {
        var t = EnginePlotStyleTable(name: "grayscale.ctb")
        for i in 1...255 {
            let c = aciColor(i)
            let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            let l = i == 7 ? 0 : min(0.75, lum)
            let v = UInt32((l * 255).rounded())
            t.pens[i] = EnginePen(color: v << 16 | v << 8 | v)
        }
        return t
    }()
    /// Architectural pens: ACI 1–9 plot black with graded lineweights, 8/9 grey screened.
    public static let archiPens: EnginePlotStyleTable = {
        var t = EnginePlotStyleTable(name: "archi pens.ctb")
        let w: [Int: Double] = [1: 0.13, 2: 0.18, 3: 0.25, 4: 0.35, 5: 0.50, 6: 0.70, 7: 0.25, 8: 0.13, 9: 0.09]
        for (i, lw) in w {
            let s: Double = i == 8 ? 50 : (i == 9 ? 30 : 100)
            t.pens[i] = EnginePen(color: 0x000000, lineweight: lw, screening: s)
        }
        return t
    }()
    public static var builtIn: [EnginePlotStyleTable] { [monochrome, grayscale, archiPens] }

    /// Built-in tables (unless the drawing redefines one) then the drawing's, sorted by variable name.
    public static func all(_ doc: ArchiDocument) -> [EnginePlotStyleTable] {
        var custom: [EnginePlotStyleTable] = []
        for k in doc.variables.keys.sorted() where k.hasPrefix(variablePrefix) {
            if let t = try? JSONDecoder().decode(EnginePlotStyleTable.self, from: Data((doc.variables[k] ?? "").utf8)) { custom.append(t) }
        }
        let b = builtIn.filter { t in !custom.contains { $0.name.lowercased() == t.name.lowercased() } }
        return b + custom
    }
    public static func named(_ name: String?, in doc: ArchiDocument) -> EnginePlotStyleTable? {
        guard let n = name?.lowercased(), !n.isEmpty else { return nil }
        return all(doc).first { $0.name.lowercased() == n }
    }
    public func store(in doc: inout ArchiDocument) {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        if let d = try? e.encode(self) { doc.variables[EnginePlotStyleTable.variablePrefix + name.uppercased()] = String(decoding: d, as: UTF8.self) }
    }
}

/// Named plot styles (STB, SHT-031): style name → pen; styles assigned to layers ("PLOTSTYLENAME:LAYER:<layer>") and
/// objects (prop "plotStyle"). "Normal" plots unchanged.
public enum EngineNamedPlotStyles {
    public static let tablePrefix = "STB:"
    public static let layerPrefix = "PLOTSTYLENAME:LAYER:"
    public static let prop = "plotStyle"
    public static let defaultName = "archi named.stb"
    public static let defaultTable: [String: EnginePen] = [
        "Normal": EnginePen(), "Black": EnginePen(color: 0x000000), "Screened 50%": EnginePen(screening: 50),
        "Screened 25%": EnginePen(screening: 25), "Heavy": EnginePen(lineweight: 0.7), "Fine": EnginePen(lineweight: 0.13),
        "Red": EnginePen(color: 0xE0201B),
    ]

    public static func tables(_ doc: ArchiDocument) -> [String] {
        var out: [String] = [defaultName]
        for k in doc.variables.keys.sorted() where k.hasPrefix(tablePrefix) {
            let n = String(k.dropFirst(tablePrefix.count))
            if !out.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { out.append(n) }
        }
        return out
    }
    public static func table(_ name: String, in doc: ArchiDocument) -> [String: EnginePen]? {
        if let s = doc.variable(tablePrefix + name.uppercased()), let t = try? JSONDecoder().decode([String: EnginePen].self, from: Data(s.utf8)) { return t }
        return name.caseInsensitiveCompare(defaultName) == .orderedSame ? defaultTable : nil
    }
    public static func layerStyle(_ layer: String, _ doc: ArchiDocument) -> String { doc.variable(layerPrefix + layer.uppercased()) ?? "Normal" }
    public static func setLayerStyle(_ layer: String, _ style: String?, _ doc: inout ArchiDocument) {
        let v: String? = (style == nil || style == "Normal") ? nil : style
        doc.variables[layerPrefix + layer.uppercased()] = v
    }
    /// Style of every object: its own (absent or "ByLayer" = its layer's).
    public static func styleMap(_ doc: ArchiDocument) -> [EntityID: String] {
        var m: [EntityID: String] = [:]
        func pick(_ props: [String: String], _ layer: String) -> String {
            if let s = props[prop], s.caseInsensitiveCompare("ByLayer") != .orderedSame { return s }
            return layerStyle(layer, doc)
        }
        for e in doc.entities { m[e.id] = pick(e.props, e.layer) }
        for el in doc.elements { m[el.id] = pick(el.props, el.layer) }
        for l in doc.layouts { for e in l.entities { m[e.id] = pick(e.props, e.layer) } }
        return m
    }
}

// MARK: - Pen resolution (PlotRenderer)

/// Whole-text formatting of a text entity (props bold / italic / underline, AppRenderInfo.TextFormat).
public struct EngineTextFormat: Hashable {
    public var bold = false, italic = false, underline = false, strike = false
    public init?(props: [String: String]) {
        bold = props["bold"] == "1"; italic = props["italic"] == "1"; underline = props["underline"] == "1"
        strike = props["strike"] == "1"
        if !bold && !italic && !underline && !strike { return nil }
    }
}

/// Maps draw items to the page (points, y up) with the plotted colours and lineweights of a page setup: the Mac
/// PlotRenderer without Core Graphics.
public struct EnginePlotRenderer {
    /// Drawing units → PDF points.
    public var transform: Transform2D
    /// Points per plotted millimetre (line weights).
    public var devicePerMM: Double
    /// Paper output: white / very light colours print black, light colours are darkened.
    public var paper: Bool
    public var minLineWidth: Double = 0.1
    public var lineweightScale: Double = 1
    /// "Color", "Monochrome" or "Grayscale".
    public var colorMode = "Color"
    public var penTable: EnginePlotStyleTable?
    /// Pens of objects from named plot styles (nil = colour-dependent).
    public var entryPens: [EntityID: EnginePen]?
    public var activePen: EnginePen?
    public var textFormat: EngineTextFormat?
    /// Document of the text styles (width factor and obliquing of text, ANN-004).
    public var document: ArchiDocument?

    public init(transform: Transform2D, devicePerMM: Double, paper: Bool, minLineWidth: Double = 0.1) {
        self.transform = transform; self.devicePerMM = devicePerMM; self.paper = paper; self.minLineWidth = minLineWidth
    }

    /// Colour mode, lineweight scale and plot style table of a page setup (named styles replace the colour table).
    mutating func apply(_ setup: EnginePageSetup, doc: ArchiDocument) {
        colorMode = setup.colorMode
        lineweightScale = setup.lineweightScale
        penTable = EnginePlotStyleTable.named(setup.plotStyleTable, in: doc)
        if let stb = setup.namedStyleTable, let table = EngineNamedPlotStyles.table(stb, in: doc) {
            penTable = nil
            var pens: [EntityID: EnginePen] = [:]
            for (id, style) in EngineNamedPlotStyles.styleMap(doc) { if let p = table[style] { pens[id] = p } }
            entryPens = pens
        }
    }

    public var scaleFactor: Double { sqrt(abs(transform.a * transform.d - transform.b * transform.c)) }
    public var rotation: Double { atan2(transform.b, transform.a) }
    public func point(_ p: Vec2) -> Vec2 { transform.apply(p) }

    /// Plotted line width in points.
    public func width(_ style: StrokeStyle) -> Double {
        var lw = style.lineweight
        if let p = activePen?.lineweight { lw = p }
        else if let t = penTable { lw = t.resolve(color: style.color, lineweight: style.lineweight).1 }
        return max(minLineWidth, lw * devicePerMM * lineweightScale)
    }

    /// Plotted colour (pen table, named pen, plot style, paper rules).
    public func color(_ c0: RGBA) -> RGBA {
        var c = c0
        if let t = penTable { c = t.resolve(color: c0, lineweight: 0).0 }
        if let p = activePen { c = p.apply(to: c) }
        switch colorMode {
        case "Monochrome": return RGBA(0, 0, 0, c.a)
        case "Grayscale":
            let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            var v = lum
            if paper { v = lum > 0.82 ? 0 : min(lum, 0.75) }
            return RGBA(v, v, v, c.a)
        default: break
        }
        var r = c.r, g = c.g, b = c.b
        if paper {
            if min(r, g, b) > 0.82 { r = 0; g = 0; b = 0 }
            else {
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if lum > 0.75 { r *= 0.55; g *= 0.55; b *= 0.55 }
            }
        }
        return RGBA(r, g, b, c.a)
    }

    /// The renderer for one entry: its named pen and text formatting.
    func forEntry(_ e: DrawEntry, formats: [EntityID: EngineTextFormat]) -> EnginePlotRenderer {
        guard let id = e.id else { return self }
        var r = self
        if let pens = entryPens { r.activePen = pens[id] }
        r.textFormat = formats[id]
        return r
    }
}

// MARK: - Pages

/// Entries in their own coordinates, how they map to the page, and an optional clip polygon (points).
public struct EnginePlotPart {
    public var entries: [DrawEntry]
    public var renderer: EnginePlotRenderer
    public var clip: [Vec2]?
}

/// One plotted page (size in millimetres).
public struct EnginePlotPage {
    public var name: String
    public var widthMM: Double
    public var heightMM: Double
    public var parts: [EnginePlotPart]
    /// Outline title (publish bookmarks).
    public var bookmark: String?
}

public enum EnginePlot {
    public static let pointsPerMM = 72.0 / 25.4
    public static let standardRatios: [Double] = [1, 2, 5, 10, 20, 25, 50, 75, 100, 125, 200, 250, 500, 1000, 1250, 2000, 2500, 5000, 10000, 20000, 50000, 100000]
    static let margin = 10.0
    static let bindingMargin = 20.0
    static let titleBlockSize = Vec2(180, 42)
    static let bottomBand = 52.0

    // MARK: Helpers

    static func stroke(_ w: Double) -> StrokeStyle { StrokeStyle(color: RGBA(0, 0, 0), lineweight: w) }
    static func text(_ p: Vec2, _ h: Double, _ s: String, _ ha: HAlign = .left, _ va: VAlign = .baseline) -> DrawItem {
        .text(TextGeom(position: p, height: h, content: s, halign: ha, valign: va), font: "Helvetica", color: RGBA(0, 0, 0))
    }
    static func rect(_ a: Vec2, _ b: Vec2, _ w: Double) -> DrawItem {
        .stroke(points: [a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, style: stroke(w))
    }
    static func unionBounds(_ es: [DrawEntry]) -> BBox2 {
        var b = BBox2.empty
        for e in es { b = b.union(e.bounds) }
        return b
    }
    static func pageRenderer(_ setup: EnginePageSetup?, doc: ArchiDocument) -> EnginePlotRenderer {
        let s = Transform2D(a: pointsPerMM, d: pointsPerMM)
        var r = EnginePlotRenderer(transform: s, devicePerMM: pointsPerMM, paper: true, minLineWidth: 0.12)
        if let setup { r.apply(setup, doc: doc) }
        return r
    }
    /// Text formats of the drawing's text entities (bold, italic, underline).
    public static func textFormats(_ doc: ArchiDocument) -> [EntityID: EngineTextFormat] {
        var m: [EntityID: EngineTextFormat] = [:]
        for e in doc.entities { if case .text = e.geometry, let f = EngineTextFormat(props: e.props) { m[e.id] = f } }
        return m
    }

    /// Sheets that plot and publish (placeholder sheets are listed but never plotted, SHT-020).
    public static func publishable(_ doc: ArchiDocument) -> [Int] { doc.layouts.indices.filter { doc.layouts[$0].titleBlock["placeholder"] != "1" } }
    public static func isPlaceholder(_ l: Layout) -> Bool { l.titleBlock["placeholder"] == "1" }

    /// Bookmark title of a sheet: "A-101 — Ground Floor Plan" (Plotter.bookmarkTitle).
    public static func bookmarkTitle(_ doc: ArchiDocument, _ i: Int) -> String {
        let num = EngineSheets.number(doc, i)
        let name = doc.layouts[i].name
        return num.isEmpty || name.hasPrefix(num) ? name : num + " — " + name
    }

    // MARK: Viewports

    /// Model point → paper point (mm) through a viewport.
    static func modelToPaper(_ vp: Viewport) -> Transform2D {
        let c = vp.origin + vp.size / 2
        let s = 1 / max(vp.scale, 1e-9)
        return Transform2D.translation(c) * Transform2D(a: s, d: s) * Transform2D.translation(-vp.viewCenter)
    }

    /// Clip boundary of a viewport in paper mm (VPCLIP polygon, SHT-004 / SHT-008), else nil.
    public static func clip(_ doc: ArchiDocument, layout: String, viewport i: Int) -> [Vec2]? {
        guard let s = doc.variable("VPCLIP:" + layout.uppercased() + ":" + String(i)) else { return nil }
        var pts: [Vec2] = []
        for p in s.split(separator: ";") {
            let c = p.split(separator: ",").compactMap { Double($0) }
            if c.count == 2 { pts.append(Vec2(c[0], c[1])) }
        }
        return pts.count >= 3 ? pts : nil
    }

    /// Default section line: horizontal through the model centre.
    static func defaultSectionLine(_ doc: ArchiDocument) -> (Vec2, Vec2) {
        let b = GeometryOps.bounds(of: doc)
        if b.isEmpty { return (Vec2(-5000, 0), Vec2(5000, 0)) }
        return (Vec2(b.min.x - 1000, b.center.y), Vec2(b.max.x + 1000, b.center.y))
    }

    /// Linetype scale inside a viewport (PSLTSCALE, LAY-025).
    static func paperLinetypeScale(_ doc: ArchiDocument, _ vp: Viewport) -> Double {
        doc.variable("PSLTSCALE") == "0" ? 1 : max(vp.scale, 1e-9) * 0.25
    }

    /// Model-space entries a viewport shows, in its view's 2D coordinates (SheetComposer.viewportEntries).
    public static func viewportEntries(doc: ArchiDocument, vp: Viewport, layout: String? = nil, index: Int? = nil) -> [DrawEntry] {
        switch vp.view {
        case .axonometric, .perspective:
            return EngineShadePlot.entries(doc: doc, vp: vp, layout: layout, index: index)
        case .plan, .ceiling:
            var o = DrawOptions(level: vp.level)
            o.forPaper = true
            o.linetypeScale = paperLinetypeScale(doc, vp)
            if vp.view == .ceiling { o.reflectedCeiling = true }
            return DrawListBuilder.entries(doc: doc, options: o)
        case .section:
            return ElevationBuilder.entries(doc: doc, view: .section, sectionLine: defaultSectionLine(doc))
        case .elevationNorth, .elevationSouth, .elevationEast, .elevationWest:
            return ElevationBuilder.entries(doc: doc, view: vp.view, sectionLine: nil)
        }
    }

    /// Paper-space entities of a sheet (annotation in mm) on visible layers.
    static func paperEntities(doc: ArchiDocument, layout: Layout) -> [DrawEntry] {
        var o = DrawOptions(level: nil)
        o.forPaper = true
        var out: [DrawEntry] = []
        for e in layout.entities where doc.isVisible(layer: e.layer) {
            out.append(DrawEntry(id: e.id, items: DrawListBuilder.items(for: e, doc: doc, options: o)))
        }
        return out
    }

    /// Custom title-block fields of a sheet (project fields overridden by the sheet's), sorted by label.
    static func customFields(_ doc: ArchiDocument, layout: Layout) -> [(String, String)] {
        var d: [String: String] = [:]
        for (k, v) in EngineSheets.projectFields(doc) { d[k] = v }
        for (k, v) in layout.titleBlock where k.hasPrefix(EngineSheets.sheetPrefix) { d[String(k.dropFirst(EngineSheets.sheetPrefix.count))] = v }
        return d.keys.sorted().map { ($0, d[$0] ?? "") }
    }

    // MARK: Sheet decorations (SheetComposer.decorations)

    /// Frame, title block, north arrow, scale bar, revision table and viewport captions in paper millimetres.
    public static func decorations(doc: ArchiDocument, layout: Layout, layoutIndex: Int, date: Date = Date()) -> [DrawEntry] {
        let W = layout.paper.width, H = layout.paper.height
        var out: [DrawEntry] = []
        out.append(DrawEntry(id: nil, items: [rect(Vec2(bindingMargin, margin), Vec2(W - margin, H - margin), 0.5)]))
        let tb = titleBlockSize
        let x0 = W - margin - tb.x, y0 = margin, x1 = W - margin, y1 = margin + tb.y
        var tbv = layout.titleBlock
        for (legacy, key) in [("Project", "project"), ("Sheet", "sheetNumber"), ("Scale", "scale")] where tbv[key] == nil {
            if let v = tbv[legacy] { tbv[key] = v }
        }
        let info = doc.info
        let scales = Array(Set(layout.viewports.map { EngineSheets.ratioText($0.scale, units: doc.units) })).sorted()
        var autoScale = "—"
        if scales.count == 1 { autoScale = scales[0] } else if scales.count > 1 { autoScale = "As indicated" }
        let scaleText = tbv["scale"] ?? autoScale
        let sheetNo = tbv["sheetNumber"] ?? "A-" + EngineSheets.pad(layoutIndex + 101, 3)
        let dateText = tbv["date"] ?? EngineSheets.dateText(date)
        var values: [String: String] = [:]
        values["project"] = tbv["project"] ?? info.name
        values["sheetName"] = tbv["sheetName"] ?? layout.name
        values["sheetNumber"] = sheetNo
        values["scale"] = scaleText
        values["date"] = dateText
        values["revision"] = tbv["revision"] ?? "—"
        values["client"] = tbv["client"] ?? info.client
        values["author"] = tbv["author"] ?? info.author
        values["number"] = tbv["number"] ?? info.number
        values["paper"] = layout.paper.name
        values["address"] = info.address
        let custom = customFields(doc, layout: layout)
        for (k, v) in custom { values[k] = v }
        if let blockEntries = EngineCustomTitleBlock.entries(doc: doc, layout: layout, anchor: Vec2(x1, y0), values: values) {
            out += blockEntries
        } else {
            out += builtInTitleBlock(doc: doc, layout: layout, tbv: tbv, box: (x0, y0, x1, y1), scaleText: scaleText, sheetNo: sheetNo, dateText: dateText, custom: custom)
        }
        out.append(northArrow(center: Vec2(x0 - 16, margin + 20), angle: info.northAngle))
        if let vp = layout.viewports.first, vp.scale > 0 { out.append(scaleBar(vp, doc: doc)) }
        let revs = EngineSheets.revisions(layout)
        if !revs.isEmpty { out.append(revisionTable(revs, x0: x0, x1: x1, y1: y1)) }
        if !EngineSheets.hasViewTitleEntities(layout) {
            for vp in layout.viewports { out.append(viewportCaption(vp, doc: doc)) }
        }
        return out
    }

    static func builtInTitleBlock(doc: ArchiDocument, layout: Layout, tbv: [String: String], box: (Double, Double, Double, Double),
                                  scaleText: String, sheetNo: String, dateText: String, custom: [(String, String)]) -> [DrawEntry] {
        let (x0, y0, x1, y1) = box
        let info = doc.info
        let tb = titleBlockSize
        var items: [DrawItem] = [rect(Vec2(x0, y0), Vec2(x1, y1), 0.5)]
        let colA = x0 + 70, colB = x0 + 125
        items.append(.stroke(points: [Vec2(x0, y1 - 14), Vec2(x1, y1 - 14)], closed: false, style: stroke(0.35)))
        items.append(.stroke(points: [Vec2(colA, y0), Vec2(colA, y1 - 14)], closed: false, style: stroke(0.25)))
        items.append(.stroke(points: [Vec2(colB, y0), Vec2(colB, y1 - 14)], closed: false, style: stroke(0.25)))
        let rowH = (tb.y - 14) / 3
        for i in 1..<3 {
            let y = y0 + Double(i) * rowH
            items.append(.stroke(points: [Vec2(x0, y), Vec2(x1, y)], closed: false, style: stroke(0.18)))
        }
        var nameX = x0 + 3
        if let logo = doc.variable("TITLEBLOCKLOGO"), !logo.isEmpty {
            items.append(.image(ImageGeom(path: logo, origin: Vec2(x0 + 2, y1 - 12.5), size: Vec2(26, 11))))
            nameX += 28
        }
        items.append(text(Vec2(nameX, y1 - 7), 4.5, tbv["project"] ?? info.name, .left, .middle))
        items.append(text(Vec2(x1 - 3, y1 - 4.5), 2.2, "OANARINA ARCHI TOOL", .right, .middle))
        items.append(text(Vec2(x1 - 3, y1 - 10), 2, info.address, .right, .middle))
        func field(_ x: Double, _ row: Int, _ label: String, _ value: String, big: Bool = false) {
            let yb = y0 + Double(2 - row) * rowH
            items.append(text(Vec2(x + 2, yb + rowH - 2.6), 1.6, label.uppercased(), .left, .middle))
            items.append(text(Vec2(x + 2, yb + 2.4), big ? 3.2 : 2.5, value, .left, .baseline))
        }
        field(x0, 0, "Sheet", tbv["sheetName"] ?? layout.name)
        field(x0, 1, "Client", tbv["client"] ?? info.client)
        field(x0, 2, "Drawn by", tbv["author"] ?? info.author)
        field(colA, 0, "Project no.", tbv["number"] ?? info.number)
        field(colA, 1, "Scale", scaleText)
        field(colA, 2, "Date", dateText)
        field(colB, 0, "Sheet no.", sheetNo, big: true)
        field(colB, 1, "Paper", layout.paper.name)
        field(colB, 2, "Revision", tbv["revision"] ?? "—")
        var out = [DrawEntry(id: nil, items: items)]
        if !custom.isEmpty {
            var rows: [DrawItem] = []
            for (k, f) in custom.enumerated() {
                let ya = y1 + Double(k) * 5, yb = ya + 5
                rows.append(rect(Vec2(x0, ya), Vec2(x1, yb), 0.18))
                rows.append(text(Vec2(x0 + 2, ya + 1.6), 1.6, f.0.uppercased(), .left, .baseline))
                rows.append(text(Vec2(colA, ya + 1.4), 2.2, f.1, .left, .baseline))
            }
            out.append(DrawEntry(id: nil, items: rows))
        }
        return out
    }

    static func northArrow(center nc: Vec2, angle: Double) -> DrawEntry {
        let north = rad(angle)
        let tip = nc + Vec2(0, 11).rotated(by: north), left = nc + Vec2(-5, -8).rotated(by: north)
        let right = nc + Vec2(5, -8).rotated(by: north), mid = nc + Vec2(0, -4).rotated(by: north)
        let circle = GeometryOps.arcPoints(center: nc, radius: 9, start: 0, sweep: 2 * .pi)
        return DrawEntry(id: nil, items: [
            .stroke(points: circle, closed: true, style: stroke(0.25)),
            .fill(loops: [[tip, mid, right]], color: RGBA(0, 0, 0)),
            .stroke(points: [tip, left, mid, right], closed: true, style: stroke(0.25)),
            text(nc + Vec2(0, 14).rotated(by: north), 3, "N", .center, .middle),
        ])
    }

    static func scaleBar(_ vp: Viewport, doc: ArchiDocument) -> DrawEntry {
        let unitsPerMM = vp.scale * doc.units.mm
        let target = 60.0 * unitsPerMM
        let pow10 = pow(10, floor(log10(target)))
        let nice = [1.0, 2, 2.5, 5, 10].map { $0 * pow10 }.last { $0 <= target } ?? pow10
        let paperLen = nice / unitsPerMM
        let o = Vec2(bindingMargin + 6, margin + 12)
        var sb: [DrawItem] = []
        for i in 0..<5 {
            let a = o + Vec2(paperLen * Double(i) / 5, 0), b = o + Vec2(paperLen * Double(i + 1) / 5, 2.5)
            if i % 2 == 0 { sb.append(.fill(loops: [[a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)]], color: RGBA(0, 0, 0))) }
        }
        sb.append(rect(o, o + Vec2(paperLen, 2.5), 0.25))
        func lbl(_ v: Double) -> String { v >= 1000 ? fmt(v / 1000, 2) + " m" : fmt(v, 0) + " mm" }
        sb.append(text(o + Vec2(0, 4.5), 2, "0", .center, .baseline))
        sb.append(text(o + Vec2(paperLen / 2, 4.5), 2, lbl(nice / 2), .center, .baseline))
        sb.append(text(o + Vec2(paperLen, 4.5), 2, lbl(nice), .center, .baseline))
        sb.append(text(o + Vec2(0, -4.5), 2, "SCALE " + EngineSheets.ratioText(vp.scale, units: doc.units), .left, .baseline))
        return DrawEntry(id: nil, items: sb)
    }

    static func revisionTable(_ revs: [EngineSheetRevision], x0: Double, x1: Double, y1: Double) -> DrawEntry {
        let rh = 5.0
        let cols: [Double] = [14, 24, titleBlockSize.x - 14 - 24 - 24, 24]
        var ri: [DrawItem] = []
        let rows = revs.count + 1
        let top = y1 + Double(rows) * rh
        ri.append(rect(Vec2(x0, y1), Vec2(x1, top), 0.35))
        for r in 1..<rows {
            let y = y1 + Double(r) * rh
            ri.append(.stroke(points: [Vec2(x0, y), Vec2(x1, y)], closed: false, style: stroke(r == 1 ? 0.35 : 0.18)))
        }
        var cx = x0
        for w in cols.dropLast() {
            cx += w
            ri.append(.stroke(points: [Vec2(cx, y1), Vec2(cx, top)], closed: false, style: stroke(0.18)))
        }
        func rowText(_ r: Int, _ vals: [String], _ h: Double) {
            var x = x0
            for (k, v) in vals.enumerated() {
                let maxChars = max(1, Int(cols[k] / (h * 0.62)))
                let shown = v.count > maxChars ? String(v.prefix(maxChars - 1)) + "…" : v
                ri.append(text(Vec2(x + 1.5, y1 + Double(r) * rh + rh / 2), h, shown, .left, .middle))
                x += cols[k]
            }
        }
        rowText(0, ["REV", "DATE", "DESCRIPTION", "BY"], 1.8)
        for (k, r) in revs.enumerated() { rowText(k + 1, [r.code, r.date, r.description, r.by], 2.2) }
        return DrawEntry(id: nil, items: ri)
    }

    static func viewportCaption(_ vp: Viewport, doc: ArchiDocument) -> DrawEntry {
        let p = vp.origin + Vec2(0, -6)
        let title = EngineSheets.viewTitle(vp, doc: doc)
        let dot = GeometryOps.arcPoints(center: p + Vec2(2.5, 1.2), radius: 2.2, start: 0, sweep: 2 * .pi)
        let ruleEnd = min(vp.size.x, 7 + Double(title.count) * 2.6)
        return DrawEntry(id: nil, items: [
            .fill(loops: [dot], color: RGBA(0, 0, 0)),
            text(p + Vec2(7, 0), 3.2, title, .left, .baseline),
            .stroke(points: [p + Vec2(6, -1.4), p + Vec2(ruleEnd, -1.4)], closed: false, style: stroke(0.35)),
            text(p + Vec2(7, -5), 2, EngineSheets.ratioText(vp.scale, units: doc.units), .left, .baseline),
        ])
    }

    // MARK: Plot stamp (PlotStamp)

    public static let stampTemplate = "{project}  ·  {sheet}  ·  plotted {date} {time}  ·  Oanarina Archi Tool"

    public static func stampText(doc: ArchiDocument, name: String, template: String?, file: String? = nil, style: String? = nil, date: Date = Date()) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter(); tf.locale = Locale(identifier: "en_US_POSIX"); tf.dateFormat = "HH:mm"
        var t = stampTemplate
        if let tt = template, !tt.isEmpty { t = tt }
        let user = doc.info.author.isEmpty ? (ProcessInfo.processInfo.environment["USERNAME"] ?? ProcessInfo.processInfo.environment["USER"] ?? "") : doc.info.author
        let values: [(String, String)] = [("{project}", doc.info.name), ("{number}", doc.info.number), ("{sheet}", name), ("{date}", df.string(from: date)),
                                          ("{time}", tf.string(from: date)), ("{user}", user), ("{file}", file ?? ""), ("{style}", style ?? "")]
        for (k, v) in values { t = t.replacingOccurrences(of: k, with: v) }
        return t
    }

    static func stampEntry(doc: ArchiDocument, name: String, setup: EnginePageSetup) -> DrawEntry {
        let style = setup.plotStyleTable ?? setup.colorMode
        let content = stampText(doc: doc, name: name, template: setup.stampText, style: style)
        return DrawEntry(id: nil, items: [text(Vec2(bindingMargin + 1, 4), 1.8, content)])
    }

    // MARK: Sheet page (SheetComposer.draw)

    /// A sheet at true size on its paper with its page setup (or `setup`): viewports clipped to their frames (or
    /// clip polygons), paper-space annotation, decorations and the plot stamp.
    static func sheetPage(doc: ArchiDocument, layoutIndex li: Int, setup s: EnginePageSetup? = nil) -> EnginePlotPage? {
        guard doc.layouts.indices.contains(li) else { return nil }
        let layout = doc.layouts[li]
        let setup = s ?? EnginePageSetup.load(doc, layoutIndex: li)
        let toPage = Transform2D(a: pointsPerMM, d: pointsPerMM)
        var parts: [EnginePlotPart] = []
        for (i, vp) in layout.viewports.enumerated() {
            let frozen = ViewportLayers.frozen(doc, layout: layout.name, viewport: i)
            let src = frozen.isEmpty ? doc : ViewportLayers.document(for: doc, layout: layout.name, viewport: i)
            let entries = viewportEntries(doc: src, vp: vp, layout: layout.name, index: i)
            var r = EnginePlotRenderer(transform: toPage * modelToPaper(vp), devicePerMM: pointsPerMM, paper: true, minLineWidth: 0.12)
            r.apply(setup, doc: doc)
            let poly = clip(doc, layout: layout.name, viewport: i) ?? [vp.origin, vp.origin + Vec2(vp.size.x, 0), vp.origin + vp.size, vp.origin + Vec2(0, vp.size.y)]
            parts.append(EnginePlotPart(entries: entries, renderer: r, clip: poly.map { toPage.apply($0) }))
        }
        let paperR = pageRenderer(setup, doc: doc)
        var deco = paperEntities(doc: doc, layout: layout)
        deco += decorations(doc: doc, layout: layout, layoutIndex: li)
        if setup.plotStamp { deco.append(stampEntry(doc: doc, name: layout.name, setup: setup)) }
        parts.append(EnginePlotPart(entries: deco, renderer: paperR, clip: nil))
        return EnginePlotPage(name: layout.name, widthMM: layout.paper.width, heightMM: layout.paper.height, parts: parts, bookmark: bookmarkTitle(doc, li))
    }

    // MARK: Model page (Plotter.modelFrame, writeModelPDF, LayeredPDF.modelPage)

    /// What a model-space plot shows (plot area, SHT-028) and at which ratio 1:n (SHT-029).
    static func modelFrame(doc: ArchiDocument, setup: EnginePageSetup, extents: BBox2, area: BBox2) -> (box: BBox2, ratio: Double) {
        var b = extents.isEmpty ? GeometryOps.bounds(of: doc) : extents
        switch setup.plotArea {
        case "Display", "Window":
            if let w = setup.plotWindow, w.count == 4 {
                let wb = BBox2(points: [Vec2(w[0], w[1]), Vec2(w[2], w[3])])
                if wb.width > 0 && wb.height > 0 { b = wb }
            }
        case "Limits":
            func pt(_ k: String) -> Vec2? {
                guard let s = doc.variable(k) else { return nil }
                let c = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                return c.count >= 2 ? Vec2(c[0], c[1]) : nil
            }
            let lb = BBox2(points: [pt("LIMMIN") ?? .zero, pt("LIMMAX") ?? Vec2(420, 297)])
            if lb.width > 0 && lb.height > 0 { b = lb }
        default: break
        }
        var ratio = 100.0
        if let fixed = setup.modelScale, fixed > 0 { ratio = fixed }
        else if !b.isEmpty && b.width + b.height > 0 {
            let needed = max(b.width / area.width, b.height / area.height) * doc.units.mm
            if setup.exactFit { ratio = max(needed, 1e-9) }
            else { ratio = standardRatios.first { $0 >= needed } ?? (ceil(needed / 1000) * 1000) }
        }
        return (b, ratio)
    }

    /// The model page setup's paper (portrait swaps the sides).
    static func modelPaper(_ setup: EnginePageSetup) -> PaperSize {
        let p = EnginePaperCatalog.find(setup.modelPaper) ?? PaperSize.standard[1]
        return setup.modelPortrait ? PaperSize(name: p.name + " portrait", width: p.height, height: p.width) : p
    }

    /// Model space of a level plotted like the Mac PLOT / PREVIEW (frame and 18 mm title strip), or like the layered
    /// PDF export (`layered`: 10 mm margins, no strip). Returns the page and the ratio 1:n.
    static func modelPage(doc: ArchiDocument, level: Int?, setup s: EnginePageSetup? = nil, layered: Bool = false, date: Date = Date()) -> (page: EnginePlotPage, ratio: Double) {
        let setup = s ?? EnginePageSetup.load(doc, layoutIndex: nil)
        let paper = modelPaper(setup)
        let W = paper.width, H = paper.height
        let strip = 18.0
        var opts = DrawOptions(level: level)
        opts.forPaper = true
        var entries = DrawListBuilder.entries(doc: doc, options: opts)
        let area = layered ? BBox2(min: Vec2(margin, margin), max: Vec2(W - margin, H - margin))
            : BBox2(min: Vec2(margin + 3, margin + strip + 3), max: Vec2(W - margin - 3, H - margin - 3))
        let (b, ratio) = modelFrame(doc: doc, setup: setup, extents: unionBounds(entries), area: area)
        let scale = ratio / doc.units.mm
        if opts.linetypeScale != max(1, scale * 0.25) {
            opts.linetypeScale = max(1, scale * 0.25)
            entries = DrawListBuilder.entries(doc: doc, options: opts)
        }
        let center = b.isEmpty ? Vec2.zero : b.center
        let k = pointsPerMM / scale
        let t = Transform2D.translation(area.center * pointsPerMM) * Transform2D(a: k, d: k) * Transform2D.translation(-center)
        var r = EnginePlotRenderer(transform: t, devicePerMM: pointsPerMM, paper: true, minLineWidth: 0.12)
        r.apply(setup, doc: doc)
        let grow = layered ? 0.0 : 3.0
        let c0 = (area.min - Vec2(grow, grow)) * pointsPerMM, c1 = (area.max + Vec2(grow, grow)) * pointsPerMM
        let clipPoly = [c0, Vec2(c1.x, c0.y), c1, Vec2(c0.x, c1.y)]
        var parts = [EnginePlotPart(entries: entries, renderer: r, clip: clipPoly)]
        let levelName = level.flatMap { doc.level($0)?.name } ?? "All levels"
        if !layered {
            let ink = RGBA(0, 0, 0)
            let info = levelName + "   ·   Scale " + EngineSheets.ratioText(scale, units: doc.units) + " (" + paper.name + ")   ·   " + EngineSheets.dateText(date)
            let deco: [DrawItem] = [
                .stroke(points: [Vec2(margin, margin), Vec2(W - margin, margin), Vec2(W - margin, H - margin), Vec2(margin, H - margin)], closed: true, style: StrokeStyle(color: ink, lineweight: 0.5)),
                .stroke(points: [Vec2(margin, margin + strip), Vec2(W - margin, margin + strip)], closed: false, style: StrokeStyle(color: ink, lineweight: 0.35)),
                .text(TextGeom(position: Vec2(margin + 4, margin + strip / 2), height: 4, content: doc.info.name, valign: .middle), font: "Helvetica", color: ink),
                .text(TextGeom(position: Vec2(W / 2, margin + strip / 2), height: 2.8, content: info, halign: .center, valign: .middle), font: "Helvetica", color: ink),
                .text(TextGeom(position: Vec2(W - margin - 4, margin + strip / 2), height: 2.4, content: "OANARINA ARCHI TOOL", halign: .right, valign: .middle), font: "Helvetica", color: ink),
            ]
            // The strip uses the plot style and the colour table but not named styles or the lineweight scale.
            var decoR = EnginePlotRenderer(transform: Transform2D(a: pointsPerMM, d: pointsPerMM), devicePerMM: pointsPerMM, paper: true)
            decoR.colorMode = setup.colorMode
            decoR.penTable = EnginePlotStyleTable.named(setup.plotStyleTable, in: doc)
            var es = [DrawEntry(id: nil, items: deco)]
            if setup.plotStamp { es.append(stampEntry(doc: doc, name: levelName, setup: setup)) }
            parts.append(EnginePlotPart(entries: es, renderer: decoR, clip: nil))
        }
        let name = layered ? (level.flatMap { doc.level($0)?.name } ?? "Model") : doc.info.name
        return (EnginePlotPage(name: name, widthMM: W, heightMM: H, parts: parts, bookmark: nil), ratio)
    }

    /// Plot style text of a setup for logs and lists ("archi pens.ctb" or "Monochrome").
    static func styleText(_ s: EnginePageSetup) -> String { s.plotStyleTable ?? s.colorMode }
}

// MARK: - Custom title blocks (CustomTitleBlock.swift)

enum EngineCustomTitleBlock {
    static let variable = "TITLEBLOCKBLOCK"

    static func blockName(_ doc: ArchiDocument, layout: String) -> String? {
        let n = doc.variable(variable + ":" + layout.uppercased()) ?? doc.variable(variable)
        guard let n, !n.isEmpty, doc.blocks[n] != nil else { return nil }
        return n
    }

    /// Replaces {key} placeholders (case-insensitive) with values.
    static func substitute(_ s: String, _ values: [String: String]) -> String {
        guard s.contains("{") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{", let close = s[i...].firstIndex(of: "}") {
                let key = String(s[s.index(after: i)..<close]).lowercased()
                if let v = values[key] { out += v; i = s.index(after: close); continue }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    /// Paper-space entries of the sheet's custom title block, or nil to draw the built-in one.
    static func entries(doc: ArchiDocument, layout: Layout, anchor: Vec2, values v0: [String: String]) -> [DrawEntry]? {
        guard let name = blockName(doc, layout: layout.name), let blk = doc.blocks[name] else { return nil }
        var values: [String: String] = [:]
        for (k, v) in v0 where values[k.lowercased()] == nil { values[k.lowercased()] = v }
        var tmp = ArchiDocument()
        tmp.layers = doc.layers; tmp.blocks = doc.blocks; tmp.textStyles = doc.textStyles; tmp.linetypes = doc.linetypes; tmp.units = .millimeters
        let t = Transform2D.translation(anchor - blk.basePoint)
        for e in blk.entities {
            var e2 = e
            e2.geometry = GeometryOps.transform(e.geometry, t)
            if case .text(var tg) = e2.geometry {
                if let tag = e.props["attdef"], let v = values[tag.lowercased()] { tg.content = v } else { tg.content = substitute(tg.content, values) }
                e2.geometry = .text(tg)
                e2.props["attdef"] = nil
                e2.props["invisible"] = nil
            }
            _ = tmp.add(e2)
        }
        var o = DrawOptions(level: nil)
        o.forPaper = true
        return DrawListBuilder.entries(doc: tmp, options: o).map { DrawEntry(id: nil, items: $0.items) }
    }
}

// MARK: - Shade plot of 3D sheet viewports (ShadePlot.swift)

public enum EngineShadePlot {
    public static let modes = ["As Displayed", "Wireframe", "Hidden", "Rendered"]
    public static func key(_ layout: String, _ index: Int) -> String { "SHADEPLOT:" + layout.uppercased() + ":" + String(index) }
    public static func cameraKey(_ layout: String, _ index: Int) -> String { "VPCAMERA:" + layout.uppercased() + ":" + String(index) }
    public static func is3D(_ vp: Viewport) -> Bool { vp.view == .axonometric || vp.view == .perspective }

    static func locate(_ vp: Viewport, in doc: ArchiDocument) -> (String, Int)? {
        for l in doc.layouts { if let i = l.viewports.firstIndex(of: vp) { return (l.name, i) } }
        return nil
    }

    /// Shade plot mode of a viewport (default Hidden).
    public static func mode(_ doc: ArchiDocument, layout: String, index: Int) -> String {
        guard let v = doc.variable(key(layout, index)) else { return "Hidden" }
        for m in modes where m.caseInsensitiveCompare(v) == .orderedSame || m.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(v) == .orderedSame { return m }
        return "Hidden"
    }

    /// Camera of a 3D viewport: its named 3D view, else an SW isometric (axonometric) or eye-level-ish perspective.
    public static func camera(_ doc: ArchiDocument, _ vp: Viewport, layout: String?, index: Int?) -> Camera? {
        if let l = layout, let i = index, let n = doc.variable(cameraKey(l, i)) {
            if let c = doc.view(named: n)?.camera { return c }
            if let c = doc.namedViews.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame })?.camera { return c }
        }
        guard var c = ProjectViews.axonCamera("sw", doc: doc) else { return nil }
        if vp.view == .perspective {
            let d = c.eye - c.target
            c.eye = c.target + Vec3(d.x, d.y, d.z * 0.45) * 0.8
            c.orthographic = false
            c.fov = 50
        }
        return c
    }

    /// Hidden line (default), wireframe or shaded faces with edges, centred on the viewport's view centre. "Rendered"
    /// uses the shell's raster render when one was stored (SHADEPLOTIMAGE:<sheet>:<n>), else a path-traced render
    /// (EngineStandards.swift pathTracedImage).
    public static func entries(doc: ArchiDocument, vp: Viewport, layout: String?, index: Int?) -> [DrawEntry] {
        var l = layout, ix = index
        if l == nil || ix == nil, let loc = locate(vp, in: doc) { l = loc.0; ix = loc.1 }
        guard let cam = camera(doc, vp, layout: l, index: ix) else { return [] }
        let m = (l != nil && ix != nil) ? mode(doc, layout: l!, index: ix!) : "Hidden"
        var raw = ElevationBuilder.entries(doc: doc, camera: cam)
        let box = EnginePlot.unionBounds(raw)
        guard !box.isEmpty else { return [] }
        switch m {
        case "Hidden":
            raw = raw.map { e in
                DrawEntry(id: e.id, items: e.items.map { it -> DrawItem in
                    if case .fill(let loops, _) = it { return .fill(loops: loops, color: RGBA(1, 1, 1)) }
                    return it
                })
            }
        case "Wireframe":
            raw = raw.compactMap { e in
                let items = e.items.filter { if case .fill = $0 { return false }; return true }
                return items.isEmpty ? nil : DrawEntry(id: e.id, items: items)
            }
        case "Rendered":
            if let l, let ix, let path = doc.variable("SHADEPLOTIMAGE:" + l.uppercased() + ":" + String(ix)), FileManager.default.fileExists(atPath: path) {
                raw = [DrawEntry(id: nil, items: [.image(ImageGeom(path: path, origin: box.min, size: Vec2(box.width, box.height)))])]
            } else if let im = pathTracedImage(doc: doc, camera: cam, box: box, maxPixels: fallbackPixels(vp)) {
                // No render stored by the shell (command line, MCP, batch, a moved drawing): the portable path tracer.
                raw = [DrawEntry(id: nil, items: [.image(im)])]
            }
        default: break
        }
        let d = vp.viewCenter - box.center
        return raw.map { e in DrawEntry(id: e.id, items: e.items.map { move($0, d) }) }
    }

    static func move(_ it: DrawItem, _ d: Vec2) -> DrawItem {
        switch it {
        case .stroke(let p, let c, let s): return .stroke(points: p.map { $0 + d }, closed: c, style: s)
        case .fill(let l, let c): return .fill(loops: l.map { $0.map { $0 + d } }, color: c)
        case .text(var t, let f, let c): t.position = t.position + d; return .text(t, font: f, color: c)
        case .image(var im): im.origin = im.origin + d; return .image(im)
        }
    }
}

// MARK: - Plot log (PlotLog, AppCommandsExtra.swift)

/// One CSV line per plot, PDF export and publish ("Plot Log.csv" in the application data folder).
public enum EnginePlotLog {
    public static var folder: URL? = nil
    public static var url: URL {
        if let f = folder { return f.appendingPathComponent("Plot Log.csv") }
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let base = env["APPDATA"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        #else
        let base = env["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        #endif
        return base.appendingPathComponent("Oanarina Archi Tool").appendingPathComponent("Plot Log.csv")
    }
    public static func ensure() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try? "Date,Drawing,Output,Sheets,Plot style,File\n".write(to: url, atomically: true, encoding: .utf8) }
    }
    public static func record(drawing: String, output: String, sheets: String, style: String, file: String) {
        ensure()
        let f = ISO8601DateFormatter()
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let line = [f.string(from: Date()), drawing, output, sheets, style, file].map(q).joined(separator: ",") + "\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    }
    public static func entries() -> [[String]] {
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var rows: [[String]] = []
        for line in t.split(separator: "\n").dropFirst() {
            var fields: [String] = [], cur = "", quoted = false
            for ch in line {
                if ch == "\"" { quoted.toggle(); continue }
                if ch == "," && !quoted { fields.append(cur); cur = ""; continue }
                cur.append(ch)
            }
            fields.append(cur)
            rows.append(fields)
        }
        return rows
    }
    public static func clear() { try? FileManager.default.removeItem(at: url) }
}
