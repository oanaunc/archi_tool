// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// A small Markdown renderer for the bundled user guide (docs/USER-GUIDE.md) in the offline help browser: headings with
// the website's anchors (python-markdown toc ids, the same rule as tools/gen-ui-data.mjs guideAnchors, so F1 / command
// pages can link a command's section), paragraphs, bullet and numbered lists, tables, fenced code, inline code, bold,
// italics and links. Everything is escaped first; only the markup below is produced.

export function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export function slugger() {
  const used = new Set<string>();
  const slug = (t: string) => t.normalize("NFKD").replace(/[^\x00-\x7f]/g, "").replace(/[^\w\s-]/g, "").trim().toLowerCase().replace(/[-\s]+/g, "-");
  return (text: string) => {
    let id = slug(text);
    while (!id || used.has(id)) { const m = id.match(/^(.*)_([0-9]+)$/); id = m ? `${m[1]}_${Number(m[2]) + 1}` : `${id}_1`; }
    used.add(id);
    return id;
  };
}

/** Inline markup of one (already block-split) line. */
export function inline(s: string): string {
  const codes: string[] = [];
  let t = s.replace(/`([^`]+)`/g, (_m, c) => { codes.push(`<code>${esc(c)}</code>`); return `\u0000${codes.length - 1}\u0000`; });
  t = esc(t);
  t = t.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_m, label, href) => {
    const safe = /^(https:\/\/|#|archi-help:|archi-run:)/.test(href) ? href : "#";
    return `<a href="${safe}">${label}</a>`;
  });
  t = t.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>").replace(/(^|[^\w*])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>");
  return t.replace(/\u0000(\d+)\u0000/g, (_m, i) => codes[Number(i)]);
}

function plain(text: string) { return text.replace(/`([^`]*)`/g, "$1").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/(\*\*|__|\*)/g, ""); }
function cells(line: string) { return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim()); }

export function renderMarkdown(md: string): string {
  const lines = md.split(/\r?\n/);
  const id = slugger();
  const out: string[] = [];
  let i = 0, first = true;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*(```|~~~)/.test(line)) {
      const body: string[] = [];
      for (i++; i < lines.length && !/^\s*(```|~~~)/.test(lines[i]); i++) body.push(lines[i]);
      i++;
      out.push(`<pre><code>${esc(body.join("\n"))}</code></pre>`);
      continue;
    }
    const hm = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (hm) {
      const n = hm[1].length, text = hm[2];
      // The website drops the leading H1 (build_guide.py), so it takes no anchor.
      const anchor = first && n === 1 ? "" : ` id="${id(plain(text))}"`;
      first = false;
      out.push(`<h${n}${anchor}>${inline(text)}</h${n}>`);
      i++; continue;
    }
    first = false;
    if (/^\s*\|/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{3,}/.test(lines[i + 1])) {
      const head = cells(line);
      const rows: string[][] = [];
      for (i += 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) rows.push(cells(lines[i]));
      out.push(`<table><thead><tr>${head.map((c) => `<th>${inline(c)}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("")}</tbody></table>`);
      continue;
    }
    const li = line.match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);
    if (li) {
      const ordered = /\d/.test(li[2]);
      const items: string[] = [];
      while (i < lines.length) {
        const m = lines[i].match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);
        if (m) { items.push(m[3]); i++; continue; }
        if (/^\s{2,}\S/.test(lines[i]) && items.length) { items[items.length - 1] += " " + lines[i].trim(); i++; continue; }
        break;
      }
      const tag = ordered ? "ol" : "ul";
      out.push(`<${tag}>${items.map((t) => `<li>${inline(t)}</li>`).join("")}</${tag}>`);
      continue;
    }
    if (!line.trim()) { i++; continue; }
    const para: string[] = [];
    while (i < lines.length && lines[i].trim() && !/^(#{1,6}\s|\s*(```|~~~)|\s*\||\s*([-*]|\d+\.)\s)/.test(lines[i])) para.push(lines[i++].trim());
    if (!para.length) { out.push(`<p>${inline(line.trim())}</p>`); i++; continue; }
    out.push(`<p>${inline(para.join(" "))}</p>`);
  }
  return out.join("\n");
}
