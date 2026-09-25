// Oanarina Archi Tool — GPL-3.0-or-later
// Read-only viewer export (COL-014): one self-contained HTML file to share with people who do not have the app — every
// level's plan as vector SVG (pan with drag, zoom with the wheel or pinch, layer visibility), click an element to see
// its type, name, level, material, key dimensions and properties, plus the room schedule. No scripts or data are fetched
// from the network; the file opens offline in any browser.
import Foundation

public enum ViewerExport {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Element summary shown on click (dimensions in drawing units).
    static func info(_ el: BIMElement, doc: ArchiDocument) -> [String: String] {
        let u = doc.units.abbreviation
        var o: [String: String] = ["type": el.typeName, "name": el.name, "level": doc.level(el.level)?.name ?? "\(el.level)"]
        if let m = el.material { o["material"] = m }
        switch el.geometry {
        case .wall(let w): o["length"] = "\(fmt(w.length, 1)) \(u)"; o["thickness"] = "\(fmt(w.thickness, 1)) \(u)"; o["height"] = "\(fmt(w.height, 1)) \(u)"; if let t = w.wallType { o["wall type"] = t }
        case .opening(let op): o["width"] = "\(fmt(op.width, 1)) \(u)"; o["height"] = "\(fmt(op.height, 1)) \(u)"; if op.kind == .window { o["sill"] = "\(fmt(op.sill, 1)) \(u)" }
        case .space(let s):
            o["name"] = s.name; o["number"] = s.number
            let m2 = abs(GeometryOps.signedArea(s.boundary)) * doc.units.mm * doc.units.mm / 1_000_000
            o["area"] = "\(fmt(m2, 2)) m²"
        case .slab(let s): o["thickness"] = "\(fmt(s.thickness, 1)) \(u)"; o["area"] = "\(fmt(ScheduleExporter.slabArea(s) * doc.units.mm * doc.units.mm / 1_000_000, 2)) m²"
        case .column(let c): o["size"] = "\(fmt(c.width, 0)) × \(fmt(c.depth, 0)) \(u)"; o["height"] = "\(fmt(c.height, 1)) \(u)"
        case .beam(let b): o["size"] = "\(fmt(b.width, 0)) × \(fmt(b.depth, 0)) \(u)"; o["length"] = "\(fmt(b.start.distance(to: b.end), 1)) \(u)"
        case .stair(let s): o["risers"] = "\(s.riserCount)"; o["width"] = "\(fmt(s.width, 0)) \(u)"
        case .component(let c): o["category"] = c.category
        default: break
        }
        for (k, v) in el.props where !k.hasPrefix("ifc") && o[k] == nil { o[k] = v }
        return o
    }

    public static func html(_ doc: ArchiDocument, title: String? = nil) -> String {
        let name = title ?? doc.info.name
        var levels = doc.levels.sorted { $0.elevation < $1.elevation }
        if levels.isEmpty { levels = [Level(id: 0, name: "Plan", elevation: 0)] }
        var sections = "", tabs = "", data: [[String: Any]] = []
        for (i, lv) in levels.enumerated() {
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: lv.id))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            b = b.expanded(by: max(b.width, b.height) * 0.03)
            let ppu = 1000 / max(b.width, b.height)
            var svg = SVGExporter.exportLayered(doc: doc, entries: entries, bounds: b, background: RGBA(1, 1, 1), pixelsPerUnit: ppu)
            if let r = svg.range(of: "<svg") { svg = String(svg[r.lowerBound...]) }
            svg = svg.replacingOccurrences(of: "<svg ", with: "<svg class=\"plan\" data-level=\"\(lv.id)\" data-minx=\"\(b.min.x)\" data-maxy=\"\(b.max.y)\" data-ppu=\"\(ppu)\" preserveAspectRatio=\"xMidYMid meet\" ", options: [], range: svg.range(of: "<svg "))
            sections += "<section class=\"level\(i == 0 ? " on" : "")\" id=\"lv\(lv.id)\">\(svg)</section>\n"
            tabs += "<button class=\"tab\(i == 0 ? " on" : "")\" data-level=\"\(lv.id)\">\(esc(lv.name))</button>"
            for el in doc.elements where el.level == lv.id {
                let bb = PlanRepresentation.bounds(el, doc: doc)
                guard !bb.isEmpty else { continue }
                data.append(["id": el.id, "level": lv.id, "box": [bb.min.x, bb.min.y, bb.max.x, bb.max.y], "info": info(el, doc: doc)])
            }
        }
        let rooms = doc.elements.compactMap { el -> [String]? in
            guard case .space(let s) = el.geometry else { return nil }
            return [s.number, s.name, doc.level(el.level)?.name ?? "", fmt(abs(GeometryOps.signedArea(s.boundary)) * doc.units.mm * doc.units.mm / 1_000_000, 2)]
        }.sorted { $0[2] + $0[0] < $1[2] + $1[0] }
        let roomRows = rooms.map { "<tr><td>\(esc($0[0]))</td><td>\(esc($0[1]))</td><td>\(esc($0[2]))</td><td class=\"n\">\($0[3])</td></tr>" }.joined()
        let layerBoxes = doc.layers.filter(\.visible).map { "<label><input type=\"checkbox\" checked data-layer=\"\(esc($0.name))\"> \(esc($0.name))</label>" }.joined()
        let json = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let generated = ISO8601DateFormatter().string(from: Date())
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(name)) — viewer</title>
        <style>
        :root{--bg:#f4f4f2;--fg:#1d1d1f;--mut:#6b6b70;--acc:#F5C518;--line:#dcdcd8;--panel:#ffffff}
        @media (prefers-color-scheme: dark){:root{--bg:#1c1c1e;--fg:#f2f2f2;--mut:#a0a0a6;--line:#3a3a3c;--panel:#2c2c2e}}
        *{box-sizing:border-box}body{margin:0;font:14px -apple-system,Helvetica,Arial,sans-serif;background:var(--bg);color:var(--fg)}
        header{padding:12px 16px;border-bottom:3px solid var(--acc);display:flex;flex-wrap:wrap;gap:8px;align-items:center}
        h1{font-size:18px;margin:0 16px 0 0}.tab{border:1px solid var(--line);background:var(--panel);color:var(--fg);padding:6px 12px;border-radius:6px;cursor:pointer}
        .tab.on{background:var(--acc);color:#111;border-color:var(--acc)}main{display:flex;flex-wrap:wrap;gap:12px;padding:12px 16px}
        #view{flex:1 1 520px;min-width:0;height:70vh;background:#fff;border:1px solid var(--line);border-radius:8px;overflow:hidden;position:relative;touch-action:none}
        .level{display:none;width:100%;height:100%}.level.on{display:block}.level svg{width:100%;height:100%;cursor:grab}
        aside{flex:0 1 300px;min-width:240px}.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin-bottom:12px}
        .card h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:0 0 8px}table{border-collapse:collapse;width:100%}td,th{padding:3px 4px;border-bottom:1px solid var(--line);text-align:left}
        .n{text-align:right}#layers label{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}#hl{fill:rgba(245,197,24,.25);stroke:#F5C518;stroke-width:2;pointer-events:none}
        footer{color:var(--mut);font-size:12px;padding:0 16px 16px}
        </style></head><body>
        <header><h1>\(esc(name))</h1>\(tabs)</header>
        <main><div id="view">\(sections)</div>
        <aside><div class="card"><h2>Selected</h2><div id="info">Click an element in the plan.</div></div>
        <div class="card"><h2>Rooms</h2><table><tr><th>No.</th><th>Name</th><th>Level</th><th class="n">m²</th></tr>\(roomRows)</table></div>
        <div class="card" id="layers"><h2>Layers</h2>\(layerBoxes)</div></aside></main>
        <footer>Read-only view exported by Oanarina Archi Tool on \(generated). Drag to pan, scroll or pinch to zoom, double-click to fit.</footer>
        <script>
        const ELEMENTS = \(json);
        const q = s => document.querySelector(s), qa = s => Array.from(document.querySelectorAll(s));
        function current(){ return q('.level.on svg'); }
        qa('.tab').forEach(t => t.onclick = () => { qa('.tab,.level').forEach(x => x.classList.remove('on')); t.classList.add('on'); q('#lv' + t.dataset.level).classList.add('on'); });
        qa('.plan').forEach(svg => {
          const vb0 = svg.getAttribute('viewBox').split(' ').map(Number); let vb = vb0.slice(); svg._vb0 = vb0;
          const set = () => svg.setAttribute('viewBox', vb.join(' '));
          const pt = e => { const p = svg.createSVGPoint(); p.x = e.clientX; p.y = e.clientY; return p.matrixTransform(svg.getScreenCTM().inverse()); };
          svg.addEventListener('wheel', e => { e.preventDefault(); const p = pt(e), f = e.deltaY > 0 ? 1.15 : 1/1.15;
            vb = [p.x - (p.x - vb[0]) * f, p.y - (p.y - vb[1]) * f, vb[2] * f, vb[3] * f]; set(); }, {passive:false});
          let drag = null, moved = false;
          svg.addEventListener('pointerdown', e => { drag = pt(e); moved = false; svg.setPointerCapture(e.pointerId); });
          svg.addEventListener('pointermove', e => { if (!drag) return; const p = pt(e); const dx = p.x - drag.x, dy = p.y - drag.y;
            if (Math.abs(dx) + Math.abs(dy) > vb[2] / 400) moved = true; vb[0] -= dx; vb[1] -= dy; set(); });
          svg.addEventListener('pointerup', e => { if (!moved) pick(svg, pt(e)); drag = null; });
          svg.addEventListener('dblclick', () => { vb = vb0.slice(); set(); });
        });
        function pick(svg, p){
          const ppu = +svg.dataset.ppu, x = p.x / ppu + (+svg.dataset.minx), y = (+svg.dataset.maxy) - p.y / ppu, lv = +svg.dataset.level;
          let best = null, area = Infinity;
          for (const e of ELEMENTS) { if (e.level !== lv) continue; const b = e.box;
            if (x >= b[0] && x <= b[2] && y >= b[1] && y <= b[3]) { const a = (b[2]-b[0]) * (b[3]-b[1]); if (a < area) { area = a; best = e; } } }
          const old = svg.querySelector('#hl'); if (old) old.remove();
          if (!best) { q('#info').textContent = 'Nothing here.'; return; }
          const b = best.box, r = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
          r.id = 'hl'; r.setAttribute('x', (b[0] - svg.dataset.minx) * ppu); r.setAttribute('y', (svg.dataset.maxy - b[3]) * ppu);
          r.setAttribute('width', (b[2]-b[0]) * ppu); r.setAttribute('height', (b[3]-b[1]) * ppu); svg.appendChild(r);
          const rows = Object.entries(best.info).filter(([k, v]) => v !== '').map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('');
          q('#info').innerHTML = `<b>#${best.id}</b><table>${rows}</table>`;
        }
        function esc(s){ return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }
        qa('#layers input').forEach(cb => cb.onchange = () => qa('g[inkscape\\\\:label="' + CSS.escape(cb.dataset.layer) + '"], g[data-layer="' + CSS.escape(cb.dataset.layer) + '"]').forEach(g => g.style.display = cb.checked ? '' : 'none'));
        </script></body></html>
        """
    }

    static var command: CommandDef {
        CommandDef("SHAREVIEW", aliases: ["VIEWEREXPORT", "EXPORTVIEWER", "HTMLVIEWER"], category: "Collaborate",
                   summary: "Exports a read-only, self-contained HTML viewer (all level plans as vectors with pan/zoom, element info on click, room schedule, layer toggles) to share with people without the app.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter HTML file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("html") }
            let h = html(ed.doc)
            try IOCommands.write(ed, url, "viewer", { try h.write(to: url, atomically: true, encoding: .utf8) })
        }
    }
}
