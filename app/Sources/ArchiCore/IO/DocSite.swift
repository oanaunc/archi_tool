// Oanarina Archi Tool — GPL-3.0-or-later
// Documentation site (SYS-031): the user guide, scripting guide, agent API, architecture notes and the generated
// command / API reference as a static, offline HTML site (one page per document with a table of contents, a search
// box over every heading and command, light/dark styling). `archi-cli --docs DIR` and the DOCSITE command write it.
// Includes a CommonMark-style Markdown converter for the subset the documents use: ATX headings (GitHub slugs), fenced
// code, paragraphs, nested bullet and numbered lists, block quotes, pipe tables with alignment, rules, inline code,
// strong / emphasis, links (.md links become .html), images and autolinks.
import Foundation

public enum Markdown {
    public struct Heading: Hashable { public var level: Int; public var text: String; public var id: String }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// GitHub-style heading anchor.
    public static func slug(_ s: String) -> String {
        var out = ""
        for c in plain(s).lowercased() {
            if c.isLetter || c.isNumber || c == "-" || c == "_" { out.append(c) } else if c == " " { out.append("-") }
        }
        return out
    }
    /// Text of inline Markdown without its markup (for anchors and search).
    public static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        // [text](url) → text
        while let r = t.range(of: #"\[([^\]]*)\]\([^)]*\)"#, options: .regularExpression) {
            let m = String(t[r]); let text = m.dropFirst().prefix { $0 != "]" }
            t.replaceSubrange(r, with: text)
        }
        return t.replacingOccurrences(of: "*", with: "")
    }

    /// Inline markup to HTML.
    public static func inline(_ s: String, linkMap: (String) -> String = { $0 }) -> String {
        var out = ""
        let c = Array(s)
        var i = 0
        func find(_ pat: String, from: Int) -> Int? {
            let p = Array(pat)
            var j = from
            while j + p.count <= c.count { if Array(c[j..<(j + p.count)]) == p { return j }; j += 1 }
            return nil
        }
        while i < c.count {
            let ch = c[i]
            if ch == "\\", i + 1 < c.count, "\\`*_{}[]()#+-.!|<>".contains(c[i + 1]) { out += esc(String(c[i + 1])); i += 2; continue }
            if ch == "`" {
                var n = 0; while i + n < c.count && c[i + n] == "`" { n += 1 }
                if let e = find(String(repeating: "`", count: n), from: i + n) {
                    out += "<code>" + esc(String(c[(i + n)..<e]).trimmingCharacters(in: .whitespaces)) + "</code>"; i = e + n; continue
                }
            }
            if ch == "!" || ch == "[" {
                let img = ch == "!"
                let open = img ? i + 1 : i
                if open < c.count, c[open] == "[" {
                    var depth = 0, j = open, close: Int? = nil
                    while j < c.count { if c[j] == "[" { depth += 1 } else if c[j] == "]" { depth -= 1; if depth == 0 { close = j; break } }; j += 1 }
                    if let cl = close, cl + 1 < c.count, c[cl + 1] == "(", let pe = c[(cl + 1)...].firstIndex(of: ")") {
                        let text = String(c[(open + 1)..<cl])
                        var url = String(c[(cl + 2)..<pe]).trimmingCharacters(in: .whitespaces)
                        if let sp = url.firstIndex(of: " ") { url = String(url[..<sp]) }
                        url = linkMap(url)
                        out += img ? "<img src=\"\(esc(url))\" alt=\"\(esc(plain(text)))\">" : "<a href=\"\(esc(url))\">" + inline(text, linkMap: linkMap) + "</a>"
                        i = pe + 1; continue
                    }
                }
            }
            if ch == "<", let e = c[i...].firstIndex(of: ">") {
                let u = String(c[(i + 1)..<e])
                if u.hasPrefix("http://") || u.hasPrefix("https://") || u.hasPrefix("mailto:") { out += "<a href=\"\(esc(u))\">\(esc(u))</a>"; i = e + 1; continue }
            }
            if (ch == "*" || ch == "_"), i + 1 < c.count, c[i + 1] == ch, let e = find(String([ch, ch]), from: i + 2), e > i + 2 {
                out += "<strong>" + inline(String(c[(i + 2)..<e]), linkMap: linkMap) + "</strong>"; i = e + 2; continue
            }
            if ch == "*" || (ch == "_" && (i == 0 || !(c[i - 1].isLetter || c[i - 1].isNumber))), i + 1 < c.count, c[i + 1] != " ",
               let e = find(String(ch), from: i + 1), e > i + 1, c[e - 1] != " ",
               ch == "*" || e + 1 >= c.count || !(c[e + 1].isLetter || c[e + 1].isNumber) {
                out += "<em>" + inline(String(c[(i + 1)..<e]), linkMap: linkMap) + "</em>"; i = e + 1; continue
            }
            out += esc(String(ch)); i += 1
        }
        return out
    }

    /// Converts a document. `linkMap` rewrites link targets (e.g. "GUIDE.md#x" → "guide.html#x").
    public static func html(_ md: String, linkMap: (String) -> String = { $0 }) -> (html: String, headings: [Heading]) {
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out = "", headings: [Heading] = [], usedIDs: [String: Int] = [:]
        var i = 0
        var para: [String] = []
        func flush() {
            if !para.isEmpty { out += "<p>" + inline(para.joined(separator: " ").trimmingCharacters(in: .whitespaces), linkMap: linkMap) + "</p>\n"; para = [] }
        }
        func indent(_ s: String) -> Int { s.prefix { $0 == " " }.count }
        func listItem(_ s: String) -> (ordered: Bool, text: String)? {
            let t = s.drop { $0 == " " }
            if let f = t.first, "-*+".contains(f), t.dropFirst().first == " " { return (false, String(t.dropFirst(2))) }
            let digits = t.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count <= 9, t.dropFirst(digits.count).hasPrefix(". ") || t.dropFirst(digits.count).hasPrefix(") ") { return (true, String(t.dropFirst(digits.count + 2))) }
            return nil
        }
        func cells(_ row: String) -> [String] {
            var r = row.trimmingCharacters(in: .whitespaces)
            if r.hasPrefix("|") { r.removeFirst() }
            if r.hasSuffix("|") && !r.hasSuffix("\\|") { r.removeLast() }
            var out: [String] = [], cur = "", prev: Character = " "
            for ch in r { if ch == "|" && prev != "\\" { out.append(cur); cur = "" } else { cur.append(ch) }; prev = ch }
            out.append(cur)
            return out.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|") }
        }
        func isSeparator(_ row: String) -> Bool {
            let cs = cells(row)
            return !cs.isEmpty && cs.allSatisfy { c in let t = c.trimmingCharacters(in: CharacterSet(charactersIn: ": ")); return t.count >= 1 && t.allSatisfy { $0 == "-" } }
        }
        /// Renders a list starting at line `start`; returns the next line index.
        func list(_ start: Int, _ base: Int) -> Int {
            var j = start
            guard let first = listItem(lines[j]) else { return j }
            let tag = first.ordered ? "ol" : "ul"
            out += "<\(tag)>\n"
            while j < lines.count, indent(lines[j]) == base, let it = listItem(lines[j]), it.ordered == first.ordered {
                var text = it.text
                j += 1
                // Continuation lines (more indented, not list items) join the item's text.
                while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).isEmpty, indent(lines[j]) > base, listItem(lines[j]) == nil {
                    text += " " + lines[j].trimmingCharacters(in: .whitespaces); j += 1
                }
                out += "<li>" + inline(text, linkMap: linkMap)
                if j < lines.count, indent(lines[j]) > base, listItem(lines[j]) != nil { out += "\n"; j = list(j, indent(lines[j])) }
                out += "</li>\n"
                // A blank line between items keeps the list going.
                if j + 1 < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty, indent(lines[j + 1]) == base, listItem(lines[j + 1])?.ordered == first.ordered { j += 1 }
            }
            out += "</\(tag)>\n"
            return j
        }
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                flush()
                let fence = String(t.prefix(3)), lang = t.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                i += 1
                out += "<pre><code" + (lang.isEmpty ? "" : " class=\"language-\(esc(lang))\"") + ">" + esc(code.joined(separator: "\n")) + "</code></pre>\n"
                continue
            }
            if t.isEmpty { flush(); i += 1; continue }
            if t.hasPrefix("#") {
                let n = t.prefix { $0 == "#" }.count
                if n <= 6, t.count == n || t.dropFirst(n).first == " " {
                    flush()
                    var text = t.dropFirst(n).trimmingCharacters(in: .whitespaces)
                    while text.hasSuffix("#") { text.removeLast() }
                    text = text.trimmingCharacters(in: .whitespaces)
                    var id = slug(text)
                    if let k = usedIDs[id] { usedIDs[id] = k + 1; id += "-\(k)" } else { usedIDs[id] = 1 }
                    headings.append(Heading(level: n, text: plain(text), id: id))
                    out += "<h\(n) id=\"\(id)\">" + inline(text, linkMap: linkMap) + "</h\(n)>\n"
                    i += 1; continue
                }
            }
            if (t.allSatisfy { $0 == "-" || $0 == " " } && t.filter { $0 == "-" }.count >= 3) || (t.allSatisfy { $0 == "*" || $0 == " " } && t.filter { $0 == "*" }.count >= 3) {
                if para.isEmpty { out += "<hr>\n"; i += 1; continue }
            }
            if t.hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    if l.first == " " { l = l.dropFirst() }
                    q.append(String(l)); i += 1
                }
                out += "<blockquote>\n" + html(q.joined(separator: "\n"), linkMap: linkMap).html + "</blockquote>\n"
                continue
            }
            if t.hasPrefix("|") || (t.contains("|") && i + 1 < lines.count && isSeparator(lines[i + 1])), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                flush()
                let head = cells(line)
                let aligns = cells(lines[i + 1]).map { c -> String in
                    let l = c.hasPrefix(":"), r = c.hasSuffix(":")
                    return l && r ? " style=\"text-align:center\"" : (r ? " style=\"text-align:right\"" : "")
                }
                out += "<table>\n<thead><tr>" + head.enumerated().map { "<th\($0.offset < aligns.count ? aligns[$0.offset] : "")>" + inline($0.element, linkMap: linkMap) + "</th>" }.joined() + "</tr></thead>\n<tbody>\n"
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let r = cells(lines[i])
                    var row = "<tr>"
                    for k in 0..<head.count {
                        let align: String = k < aligns.count ? aligns[k] : ""
                        let cell: String = k < r.count ? inline(r[k], linkMap: linkMap) : ""
                        row += "<td\(align)>" + cell + "</td>"
                    }
                    out += row + "</tr>\n"
                    i += 1
                }
                out += "</tbody>\n</table>\n"
                continue
            }
            if listItem(line) != nil && (para.isEmpty || indent(line) == 0) {
                flush()
                i = list(i, indent(line))
                continue
            }
            para.append(t)
            i += 1
        }
        flush()
        return (out, headings)
    }
}

public enum DocSite {
    public struct Page { public var file: String; public var title: String; public var markdown: String }

    /// Documents of the site in order: (source name, output page).
    public static let documents: [(source: String, page: String)] = [
        ("USER-GUIDE.md", "user-guide.html"), ("SCRIPTING.md", "scripting.html"), ("AGENT-API.md", "agent-api.html"),
        ("ARCHITECTURE.md", "architecture.html"), ("ROADMAP.md", "roadmap.html"), ("THIRD-PARTY.md", "third-party.html"),
    ]

    static func pageName(_ source: String) -> String? { documents.first { $0.source.caseInsensitiveCompare(source) == .orderedSame }?.page }

    static func linkMap(_ url: String) -> String {
        guard !url.contains("://"), !url.hasPrefix("#"), !url.hasPrefix("mailto:") else { return url }
        let parts = url.split(separator: "#", maxSplits: 1).map(String.init)
        let file = (parts[0] as NSString).lastPathComponent
        if let p = pageName(file) { return p + (parts.count > 1 ? "#" + parts[1] : "") }
        if file.lowercased() == "api-reference.md" { return "reference.html" + (parts.count > 1 ? "#" + parts[1] : "") }
        return url
    }

    static let css = """
    :root{--bg:#fbfbfa;--fg:#1d1d1f;--muted:#6e6e73;--line:#e3e3e0;--code:#f2f2ef;--accent:#b08900;--side:#f4f4f1}
    @media (prefers-color-scheme:dark){:root{--bg:#1c1c1e;--fg:#ececec;--muted:#9a9aa0;--line:#333336;--code:#2a2a2d;--accent:#F5C518;--side:#232326}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif}
    header{display:flex;align-items:center;gap:1rem;padding:.7rem 1.2rem;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--bg);z-index:2}
    header a.brand{font-weight:600;color:var(--fg);text-decoration:none}header a.brand span{color:var(--accent)}
    header nav a{margin-right:.9rem;color:var(--muted);text-decoration:none;font-size:.92rem}header nav a.on{color:var(--fg);font-weight:600}
    #q{margin-left:auto;padding:.35rem .6rem;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg);width:16rem;max-width:40vw}
    #results{position:absolute;right:1.2rem;top:3rem;width:28rem;max-width:90vw;max-height:60vh;overflow:auto;background:var(--bg);border:1px solid var(--line);border-radius:8px;display:none;box-shadow:0 8px 30px rgba(0,0,0,.2)}
    #results a{display:block;padding:.45rem .8rem;color:var(--fg);text-decoration:none;border-bottom:1px solid var(--line)}#results a small{color:var(--muted);display:block}
    .wrap{display:flex;max-width:1250px;margin:0 auto}aside{width:17rem;flex:none;padding:1.2rem;position:sticky;top:3.2rem;height:calc(100vh - 3.2rem);overflow:auto;background:var(--side);font-size:.88rem}
    aside a{display:block;color:var(--muted);text-decoration:none;padding:.12rem 0}aside a.l3{padding-left:.9rem}aside a:hover{color:var(--fg)}
    main{flex:1;min-width:0;padding:1.5rem 2.5rem 4rem}h1,h2,h3{line-height:1.25}h2{margin-top:2.2rem;border-bottom:1px solid var(--line);padding-bottom:.3rem}
    a{color:var(--accent)}code{background:var(--code);padding:.1rem .3rem;border-radius:4px;font:.88em ui-monospace,Menlo,monospace}
    pre{background:var(--code);padding:.9rem 1rem;border-radius:8px;overflow:auto}pre code{background:none;padding:0}
    table{border-collapse:collapse;margin:1rem 0;font-size:.92rem;display:block;overflow-x:auto}th,td{border:1px solid var(--line);padding:.35rem .6rem;text-align:left;vertical-align:top}th{background:var(--side)}
    blockquote{margin:1rem 0;padding:.2rem 1rem;border-left:4px solid var(--accent);color:var(--muted)}img{max-width:100%}
    .cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(15rem,1fr));gap:1rem}.card{border:1px solid var(--line);border-radius:10px;padding:1rem 1.1rem;text-decoration:none;color:var(--fg)}.card p{color:var(--muted);margin:.3rem 0 0;font-size:.92rem}
    footer{color:var(--muted);font-size:.85rem;padding:2rem 0 0}
    @media (max-width:800px){aside{display:none}main{padding:1rem}}
    """

    static let searchJS = """
    (function(){var q=document.getElementById('q'),r=document.getElementById('results');if(!q)return;
    function show(){var t=q.value.trim().toLowerCase();if(t.length<2){r.style.display='none';return;}
    var hits=SEARCH.filter(function(e){return e.t.toLowerCase().indexOf(t)>=0||(e.s&&e.s.toLowerCase().indexOf(t)>=0);}).slice(0,40);
    r.innerHTML=hits.map(function(e){return '<a href="'+e.u+'">'+e.t.replace(/&/g,'&amp;').replace(/</g,'&lt;')+'<small>'+(e.p||'')+'</small></a>';}).join('')||'<a>No results</a>';
    r.style.display='block';}
    q.addEventListener('input',show);q.addEventListener('keydown',function(e){if(e.key==='Enter'){var a=r.querySelector('a[href]');if(a)location.href=a.getAttribute('href');}if(e.key==='Escape'){q.value='';show();}});
    document.addEventListener('click',function(e){if(e.target!==q)r.style.display='none';});})();
    """

    static func frame(title: String, current: String, pages: [Page], sidebar: String, body: String) -> String {
        var nav = ""
        for p in pages { nav += "<a href=\"\(p.file)\"" + (p.file == current ? " class=\"on\"" : "") + ">\(Markdown.esc(p.title))</a>" }
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(Markdown.esc(title)) — Oanarina Archi Tool</title><link rel="stylesheet" href="style.css"></head><body>
        <header><a class="brand" href="index.html">Oanarina <span>Archi Tool</span></a><nav>\(nav)</nav>
        <input id="q" type="search" placeholder="Search commands and topics" aria-label="Search"><div id="results"></div></header>
        <div class="wrap">\(sidebar.isEmpty ? "" : "<aside>\(sidebar)</aside>")<main>
        \(body)
        <footer>Oanarina Archi Tool — free software under the GPL-3.0-or-later. Generated documentation.</footer></main></div>
        <script src="search-index.js"></script><script src="search.js"></script></body></html>

        """
    }

    static func shortTitle(_ md: String, fallback: String) -> String {
        let h1 = md.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) } ?? fallback
        let t = h1.replacingOccurrences(of: "Oanarina Archi Tool — ", with: "").replacingOccurrences(of: "Oanarina Archi Tool - ", with: "")
        return Markdown.plain(t)
    }

    /// Builds the site into `dir` from the Markdown documents found in `source` and the generated API reference.
    /// Returns the written file names.
    @discardableResult
    public static func build(source: URL, into dir: URL, apiReference: String) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var pages: [Page] = []
        for d in documents {
            guard let text = try? String(contentsOf: source.appendingPathComponent(d.source), encoding: .utf8) else { continue }
            pages.append(Page(file: d.page, title: shortTitle(text, fallback: d.source), markdown: text))
        }
        if !apiReference.isEmpty { pages.append(Page(file: "reference.html", title: "Command reference", markdown: apiReference)) }
        guard !pages.isEmpty else { throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No documentation files in \(source.path)"]) }
        var written: [String] = []
        var index: [[String: String]] = []
        for p in pages {
            let (body, heads) = Markdown.html(p.markdown, linkMap: linkMap)
            var side = ""
            for h in heads where h.level == 2 || h.level == 3 { side += "<a class=\"l\(h.level)\" href=\"#\(h.id)\">\(Markdown.esc(h.text))</a>" }
            try frame(title: p.title, current: p.file, pages: pages, sidebar: side, body: body).write(to: dir.appendingPathComponent(p.file), atomically: true, encoding: .utf8)
            written.append(p.file)
            for h in heads where h.level >= 2 { index.append(["t": h.text, "u": p.file + "#" + h.id, "p": p.title]) }
        }
        // Commands in the search index (from the reference's tables: | `NAME` | aliases | description |).
        for line in apiReference.split(separator: "\n") where line.hasPrefix("| `") {
            let cs = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cs.count >= 3 else { continue }
            let name = cs[0].replacingOccurrences(of: "`", with: "")
            index.append(["t": name, "u": "reference.html#commands", "p": "Command", "s": cs[1].replacingOccurrences(of: "`", with: "") + " " + String(cs[2].prefix(160))])
        }
        // Landing page.
        var cards = "<h1>Oanarina Archi Tool documentation</h1>\n<p>A free, native Mac application for architectural drawing and building design: AutoCAD-style drafting with a command line, Revit-style building elements, 3D, rendering, sheets, analysis, exchange formats and scripting for people and AI agents.</p>\n<div class=\"cards\">\n"
        let blurbs = ["user-guide.html": "Everything the app does, from the command line to sheets and analysis.",
                      "scripting.html": "JavaScript, Python and command scripts.", "agent-api.html": "Driving the app from AI agents: the local server and MCP.",
                      "architecture.html": "How the code is organised (for developers).", "roadmap.html": "What comes next.",
                      "third-party.html": "Licences of adapted code.", "reference.html": "Every command, alias and agent tool."]
        for p in pages { cards += "<a class=\"card\" href=\"\(p.file)\"><strong>\(Markdown.esc(p.title))</strong><p>\(blurbs[p.file] ?? "")</p></a>\n" }
        cards += "</div>\n"
        try frame(title: "Documentation", current: "index.html", pages: pages, sidebar: "", body: cards).write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try css.write(to: dir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try searchJS.write(to: dir.appendingPathComponent("search.js"), atomically: true, encoding: .utf8)
        let json = String(data: try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]), encoding: .utf8) ?? "[]"
        try ("var SEARCH=" + json + ";\n").write(to: dir.appendingPathComponent("search-index.js"), atomically: true, encoding: .utf8)
        return ["index.html"] + written + ["style.css", "search.js", "search-index.js"]
    }

    /// Where the documentation Markdown lives: the app bundle's resources, else a "docs" folder next to the working directory.
    public static func defaultSource() -> URL? {
        let fm = FileManager.default
        var cands: [URL] = []
        if let r = Bundle.main.resourceURL { cands.append(r) }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        cands += [cwd.appendingPathComponent("docs"), cwd.deletingLastPathComponent().appendingPathComponent("docs"), cwd]
        return cands.first { fm.fileExists(atPath: $0.appendingPathComponent("USER-GUIDE.md").path) }
    }

    static var command: CommandDef {
        CommandDef("DOCSITE", aliases: ["DOCUMENTATIONSITE", "HELPSITE", "MANUALHTML"], category: "Help",
                   summary: "Writes the documentation (user guide, scripting, agent API, command reference) as an offline HTML site with search.", modifies: false) { ed in
            let dir = try await IOCommands.path(ed, "Enter folder for the site")
            let src = try await ed.getWord("Documentation source folder <built-in>")
            guard let source = (src?.isEmpty ?? true) ? defaultSource() : IOCommands.resolve(ed, src!) else { throw CommandError.invalid("The documentation files were not found; give the docs folder.") }
            do {
                let files = try build(source: source, into: dir, apiReference: APIReference.markdown())
                ed.print("Wrote \(files.count) files to \(dir.path) (open index.html).")
            } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }
}
