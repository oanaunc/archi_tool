// Oanarina Archi Tool — GPL-3.0-or-later
// Presentation (COL-021): the drawing's sheets and saved views as a self-contained HTML slide show that runs full screen
// in any browser, offline — one vector SVG slide per sheet (viewports at scale and clipped to their frames, paper-space
// annotation, title block fields) and per named view (plan window or camera view), with arrow-key / click navigation,
// a slide counter, the F key for full screen, and speaker notes from the sheet's "notes" title-block field.
import Foundation

public enum Presentation {
    public struct Slide: Hashable {
        public var title: String
        public var svg: String
        public var notes: String
        public init(title: String, svg: String, notes: String = "") { self.title = title; self.svg = svg; self.notes = notes }
    }

    /// Body of an SVG document (without the XML declaration) with extra attributes on its root element.
    static func embed(_ svg: String, attributes: String) -> String {
        var s = svg
        if let r = s.range(of: "?>\n") { s.removeSubrange(s.startIndex..<r.upperBound) }
        if let r = s.range(of: "<svg ") { s.replaceSubrange(r, with: "<svg " + attributes + " ") }
        return s
    }

    /// Model-space draw entries shown by a viewport.
    public static func viewportEntries(_ doc: ArchiDocument, _ vp: Viewport) -> [DrawEntry] {
        switch vp.view {
        case .plan:
            var o = DrawOptions(level: vp.level ?? doc.currentLevel); o.forPaper = true
            return DrawListBuilder.entries(doc: doc, options: o)
        case .ceiling:
            var o = DrawOptions(level: vp.level ?? doc.currentLevel); o.forPaper = true; o.reflectedCeiling = true
            return DrawListBuilder.entries(doc: doc, options: o)
        case .axonometric, .perspective:
            let b = GeometryOps.bounds(of: doc)
            guard !b.isEmpty else { return [] }
            let c = Vec3((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, 0)
            let r = max(b.width, b.height)
            return ElevationBuilder.entries(doc: doc, camera: Camera(eye: c + Vec3(-r, -r, r * 0.8), target: c, orthographic: vp.view == .axonometric))
        default:
            return ElevationBuilder.entries(doc: doc, view: vp.view)
        }
    }

    /// Vector SVG of a sheet in paper millimetres.
    public static func sheetSVG(_ doc: ArchiDocument, layout li: Int) -> String {
        guard doc.layouts.indices.contains(li) else { return "" }
        let l = doc.layouts[li]
        let W = l.paper.width, H = l.paper.height
        func n(_ v: Double) -> String { fmt(v, 3) }
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" viewBox=\"0 0 \(n(W)) \(n(H))\" width=\"\(n(W))mm\" height=\"\(n(H))mm\">\n"
        out += "<rect x=\"0\" y=\"0\" width=\"\(n(W))\" height=\"\(n(H))\" fill=\"#ffffff\"/>\n"
        for vp in l.viewports where vp.size.x > 0 && vp.size.y > 0 && vp.scale > 0 {
            let half = Vec2(vp.size.x * vp.scale / 2, vp.size.y * vp.scale / 2)
            let window = BBox2(min: vp.viewCenter - half, max: vp.viewCenter + half)
            let inner = SVGExporter.export(entries: viewportEntries(doc, vp), bounds: window, background: nil, pixelsPerUnit: 1 / vp.scale, lineweightScale: 1)
            let y = H - vp.origin.y - vp.size.y
            out += embed(inner, attributes: "x=\"\(n(vp.origin.x))\" y=\"\(n(y))\" overflow=\"hidden\"")
            if !vp.title.isEmpty {
                out += "<text x=\"\(n(vp.origin.x))\" y=\"\(n(H - vp.origin.y + 5))\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"3.5\" fill=\"#222\">\(XLSX.esc(vp.title)) — 1:\(Int(vp.scale.rounded()))</text>\n"
            }
        }
        // Paper-space annotation (title block, notes) in millimetres.
        if !l.entities.isEmpty {
            var paper = doc
            paper.entities = l.entities
            paper.elements = []
            let e = DrawListBuilder.entries(doc: paper, options: { var o = DrawOptions(level: nil); o.forPaper = true; return o }())
            out += embed(SVGExporter.export(entries: e, bounds: BBox2(min: .zero, max: Vec2(W, H)), background: nil, pixelsPerUnit: 1), attributes: "x=\"0\" y=\"0\"")
        }
        // Title block fields (bottom right).
        var fields = [("Project", doc.info.name), ("Sheet", l.name)]
        for (k, v) in l.titleBlock.sorted(by: { $0.key < $1.key }) where k.lowercased() != "notes" && !v.isEmpty { fields.append((k, v)) }
        let bw = 90.0, lh = 5.0, bh = Double(fields.count) * lh + 4
        out += "<g font-family=\"Helvetica, Arial, sans-serif\" font-size=\"3\" fill=\"#222\">\n"
        out += "<rect x=\"\(n(W - bw - 10))\" y=\"\(n(H - bh - 10))\" width=\"\(n(bw))\" height=\"\(n(bh))\" fill=\"none\" stroke=\"#222\" stroke-width=\"0.35\"/>\n"
        for (i, f) in fields.enumerated() {
            out += "<text x=\"\(n(W - bw - 7))\" y=\"\(n(H - bh - 10 + 5.5 + Double(i) * lh))\"><tspan font-weight=\"bold\">\(XLSX.esc(f.0)):</tspan> \(XLSX.esc(f.1))</text>\n"
        }
        out += "</g>\n</svg>\n"
        return out
    }

    /// SVG of a saved view: its plan window (aspect 16:10) or, for a camera view, the hidden-line projection.
    public static func viewSVG(_ doc: ArchiDocument, view v: NamedView) -> String {
        let entries: [DrawEntry]
        var bounds: BBox2
        if let cam = v.camera {
            entries = ElevationBuilder.entries(doc: doc, camera: cam)
            bounds = BBox2.empty
            for e in entries { for it in e.items { if case .stroke(let pts, _, _) = it { pts.forEach { bounds.add($0) } } } }
            if bounds.isEmpty { bounds = BBox2(min: .zero, max: Vec2(1, 1)) }
            let pad = max(bounds.width, bounds.height) * 0.05
            bounds = BBox2(min: bounds.min - Vec2(pad, pad), max: bounds.max + Vec2(pad, pad))
        } else {
            var o = DrawOptions(level: doc.currentLevel); o.forPaper = true
            entries = DrawListBuilder.entries(doc: doc, options: o)
            let h = max(v.height, 1e-6), w = h * 1.6
            bounds = BBox2(min: v.center - Vec2(w / 2, h / 2), max: v.center + Vec2(w / 2, h / 2))
        }
        let ppu = 1600 / max(bounds.width, 1e-9)
        return embed(SVGExporter.export(entries: entries, bounds: bounds, background: RGBA(1, 1, 1), pixelsPerUnit: ppu), attributes: "")
    }

    /// Slides: every sheet with content, then every saved view (or the whole plan when there is nothing else).
    public static func slides(_ doc: ArchiDocument, sheets: Bool = true, views: Bool = true) -> [Slide] {
        var out: [Slide] = []
        if sheets {
            for (i, l) in doc.layouts.enumerated() where !l.viewports.isEmpty || !l.entities.isEmpty {
                out.append(Slide(title: l.name, svg: sheetSVG(doc, layout: i), notes: l.titleBlock["notes"] ?? l.titleBlock["Notes"] ?? ""))
            }
        }
        if views { for v in doc.namedViews { out.append(Slide(title: v.name, svg: viewSVG(doc, view: v))) } }
        if out.isEmpty {
            let b = GeometryOps.bounds(of: doc)
            let c = b.isEmpty ? Vec2.zero : Vec2((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2)
            out.append(Slide(title: doc.info.name, svg: viewSVG(doc, view: NamedView(name: doc.info.name, center: c, height: b.isEmpty ? 1000 : max(b.height, b.width / 1.6) * 1.1))))
        }
        return out
    }

    /// Self-contained HTML slide show.
    public static func html(_ slides: [Slide], title: String) -> String {
        func esc(_ s: String) -> String { XLSX.esc(s) }
        var h = """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Oanarina Archi Tool"><title>\(esc(title))</title>
        <style>
        html,body{margin:0;height:100%;background:#1c1c1e;color:#eee;font-family:-apple-system,Helvetica,Arial,sans-serif;overflow:hidden}
        .slide{position:absolute;inset:0;display:none;flex-direction:column;align-items:center;justify-content:center}
        .slide.on{display:flex}
        .slide .art{flex:1;width:100%;display:flex;align-items:center;justify-content:center;min-height:0;padding:2vh 2vw;box-sizing:border-box}
        .slide svg{max-width:100%;max-height:100%;width:auto;height:auto;background:#fff;box-shadow:0 4px 24px rgba(0,0,0,.5)}
        .slide h1{font-size:2.2vh;font-weight:500;margin:1.2vh 0;color:#F5C518}
        .notes{display:none;position:fixed;left:0;right:0;bottom:0;background:rgba(0,0,0,.85);padding:1em 2em;font-size:1.6vh;white-space:pre-wrap}
        body.shownotes .slide.on .notes{display:block}
        #bar{position:fixed;right:1.5vw;bottom:1vh;font-size:1.4vh;color:#aaa;user-select:none}
        </style></head><body>

        """
        for (i, s) in slides.enumerated() {
            h += "<section class=\"slide\(i == 0 ? " on" : "")\" data-index=\"\(i)\"><h1>\(esc(s.title))</h1><div class=\"art\">\n\(s.svg)</div>"
            if !s.notes.isEmpty { h += "<div class=\"notes\">\(esc(s.notes))</div>" }
            h += "</section>\n"
        }
        h += """
        <div id="bar"><span id="n">1</span> / \(slides.count) · ←/→ navigate · F full screen · N notes</div>
        <script>
        (function(){var s=document.querySelectorAll('.slide'),i=0;
        function go(k){if(!s.length)return;s[i].classList.remove('on');i=(k+s.length)%s.length;s[i].classList.add('on');document.getElementById('n').textContent=i+1;}
        document.addEventListener('keydown',function(e){
          if(['ArrowRight','PageDown',' ','Enter'].indexOf(e.key)>=0){go(i+1);e.preventDefault();}
          else if(['ArrowLeft','PageUp','Backspace'].indexOf(e.key)>=0){go(i-1);e.preventDefault();}
          else if(e.key==='Home'){go(0);} else if(e.key==='End'){go(s.length-1);}
          else if(e.key==='f'||e.key==='F'){if(document.fullscreenElement){document.exitFullscreen();}else if(document.documentElement.requestFullscreen){document.documentElement.requestFullscreen();}}
          else if(e.key==='n'||e.key==='N'){document.body.classList.toggle('shownotes');}});
        document.addEventListener('click',function(e){go(e.clientX<window.innerWidth/3?i-1:i+1);});
        })();
        </script></body></html>

        """
        return h
    }

    static var command: CommandDef {
        CommandDef("PRESENTOUT", aliases: ["PRESENTATION", "SLIDESHOW", "PRESENTEXPORT"], category: "File",
                   summary: "Writes the sheets and saved views as a self-contained HTML slide show (full screen with F, arrow keys, speaker notes from the sheet field 'notes').", modifies: false) { ed in
            let k = try await ed.getKeyword("Include [All/Sheets/Views]", ["All", "Sheets", "Views"], defaultValue: "All") ?? "All"
            let slides = Presentation.slides(ed.doc, sheets: k != "Views", views: k != "Sheets")
            let name = (ed.fileURL?.deletingPathExtension().lastPathComponent).flatMap { $0.isEmpty ? nil : $0 } ?? ed.doc.info.name
            var url = try await IOCommands.path(ed, "Enter HTML file name <\(name).html>")
            if url.pathExtension.isEmpty { url.appendPathExtension("html") }
            try IOCommands.write(ed, url, "presentation (\(slides.count) slide\(slides.count == 1 ? "" : "s"))", {
                try Presentation.html(slides, title: ed.doc.info.name).write(to: url, atomically: true, encoding: .utf8)
            })
        }
    }
}
