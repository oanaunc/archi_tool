// Generates the shell's UI data:
//   src/renderer/data/ui.generated.json    ribbon / menus / panels / shortcuts
//   src/renderer/data/icons.generated.json SF Symbol name -> Lucide SVG nodes
// Source of truth: ../docs/windows-parity.json (produced from the Mac catalogue) when it exists; otherwise
// src/renderer/data/ribbon-fallback.json (tools/extract_ribbon.py reads the Mac Swift sources). Layout hints
// (large/small buttons, rows, menus, dropdowns) missing from windows-parity.json are copied from the fallback by
// tab/group/title, so both sources render the same ribbon as RibbonView.swift.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { explicit, lucideFor } from "./sf-to-lucide.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const dataDir = path.join(root, "src/renderer/data");
const fallback = JSON.parse(fs.readFileSync(path.join(dataDir, "ribbon-fallback.json"), "utf8"));
const parityPath = path.resolve(root, "../docs/windows-parity.json");

function normalizeParity(p) {
  const fbTabs = new Map(fallback.ribbon.map((t) => [t.tab, t]));
  const ribbon = (p.ribbon || []).map((t) => {
    const fbt = fbTabs.get(t.tab);
    return {
      tab: t.tab,
      groups: (t.groups || []).map((g) => {
        const fbg = fbt?.groups.find((x) => x.name === g.name);
        const hints = new Map((fbg?.items || []).map((i) => [i.title, i]));
        // Groups the Mac draws with live controls (dimension-style / visual-style pickers, the agent server status)
        // come out of the catalogue as labels and "{model…}" titles; the shell renders those as its own drop-downs,
        // so the fallback's dropdown/agentStatus layout is kept for them.
        const live = (g.items || []).some((i) => i.kind === "label" || /\{[^}]+\}/.test(i.title || ""));
        if (live && fbg && fbg.items.some((i) => i.kind === "dropdown" || i.kind === "agentStatus")) return { name: g.name, items: fbg.items };
        return {
          name: g.name,
          items: (g.items || []).map((it, k) => {
            const h = hints.get(it.title) || {};
            const merged = { ...h, ...it };
            if (!merged.size) merged.size = k < 3 && (g.items || []).length > 4 ? "large" : (g.items || []).length <= 4 ? "large" : "small";
            return merged;
          }),
        };
      }),
    };
  });
  return { ribbon, menus: p.menus || fallback.menus, panels: p.panels || fallback.panels, shortcuts: p.shortcuts || [], contextualTabs: p.contextualTabs || [] };
}

let ui, source;
if (fs.existsSync(parityPath)) {
  ui = normalizeParity(JSON.parse(fs.readFileSync(parityPath, "utf8")));
  source = "docs/windows-parity.json";
} else {
  ui = { ribbon: fallback.ribbon, menus: fallback.menus, panels: fallback.panels, shortcuts: [] };
  source = "src/renderer/data/ribbon-fallback.json";
}
ui.source = source;

// ---- run-time placeholders in the catalogue ----
// The Mac builds the Component menus (RibbonView.componentMenu) from `model.command(["COMPONENT", "FURNITURE"])` and runs
// "<resolved> <furniture>"; the catalogue records the resolved name as "{r}" and the button help as "<unavailable> / <available>".
const RUNTIME_COMMANDS = { Component: ["COMPONENT", "FURNITURE"] };
const unresolved = new Set();
(function resolveRuntime(o, parentTitle) {
  if (Array.isArray(o)) { o.forEach((x) => resolveRuntime(x, parentTitle)); return; }
  if (!o || typeof o !== "object") return;
  if (typeof o.help === "string" && o.help.includes(" / ") && JSON.stringify(o).includes('"{r}"')) {
    const [unavailable, available] = o.help.split(" / ");
    o.help = available; o.helpUnavailable = unavailable;
  }
  if (o.command === "{r}") {
    const names = RUNTIME_COMMANDS[parentTitle];
    if (names) { o.command = names[0]; o.names = names; } else unresolved.add(`${parentTitle} ▸ ${o.title}`);
  }
  for (const v of Object.values(o)) if (v && typeof v === "object") resolveRuntime(v, typeof o.title === "string" && o.title ? o.title : parentTitle);
})([ui.ribbon, ui.menus]);
if (unresolved.size) console.warn(`gen-ui-data: unresolved {r} commands: ${[...unresolved].join(", ")}`);

// ---- F1: guide anchors (website archi-tool-guide.html is docs/USER-GUIDE.md through python-markdown's toc extension) ----
// Same ids as markdown.extensions.toc: slugify (NFKD, ASCII, drop [^\w\s-], lower case, runs of - and spaces -> "-")
// made unique with _1, _2 …; build_guide.py drops the leading H1. Each command maps to its Command reference section.
function guideAnchors(md) {
  const used = new Set(), commands = {}, categories = {}, sections = [];
  const slug = (t) => t.normalize("NFKD").replace(/[^\x00-\x7f]/g, "").replace(/[^\w\s-]/g, "").trim().toLowerCase().replace(/[-\s]+/g, "-");
  const unique = (id) => {
    while (!id || used.has(id)) { const m = id.match(/^(.*)_([0-9]+)$/); id = m ? `${m[1]}_${Number(m[2]) + 1}` : `${id}_1`; }
    used.add(id); return id;
  };
  const lines = md.split(/\r?\n/);
  if (/^# /.test(lines[0] ?? "")) lines.shift();
  let fenced = false, inReference = false, current = null;
  for (const line of lines) {
    if (/^\s*(```|~~~)/.test(line)) { fenced = !fenced; continue; }
    if (fenced) continue;
    const m = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (m) {
      const text = m[2].replace(/`([^`]*)`/g, "$1").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/(\*\*|__|\*)/g, "");
      current = unique(slug(text));
      if (m[1].length === 2) { inReference = /^command reference$/i.test(text); sections.push({ title: text, id: current }); }
      else if (inReference && m[1].length === 3) categories[text] = current;
      continue;
    }
    const row = inReference && line.match(/^\|\s*`([^`]+)`\s*\|/);
    if (row && current && !commands[row[1].toUpperCase()]) commands[row[1].toUpperCase()] = current;
  }
  return { commands, categories, sections };
}
const guidePath = path.resolve(root, "../docs/USER-GUIDE.md");
ui.guide = fs.existsSync(guidePath) ? guideAnchors(fs.readFileSync(guidePath, "utf8")) : { commands: {}, categories: {}, sections: [] };

// ---- version (About, What's New): app/Info.plist like packaging/sync-version.mjs ----
{
  const plistPath = path.resolve(root, "../app/Info.plist");
  const plist = fs.existsSync(plistPath) ? fs.readFileSync(plistPath, "utf8") : "";
  const key = (k) => plist.match(new RegExp(`<key>${k}</key>\\s*<string>([^<]*)</string>`))?.[1]?.trim();
  ui.appVersion = { short: key("CFBundleShortVersionString") ?? JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8")).version, build: key("CFBundleVersion") ?? "1" };
}
fs.writeFileSync(path.join(dataDir, "ui.generated.json"), JSON.stringify(ui));

// ---- icons ----
const chrome = ["doc.badge.plus", "folder", "square.and.arrow.down", "square.and.arrow.down.on.square", "arrow.uturn.backward", "arrow.uturn.forward", "printer", "eye", "doc.on.doc",
  "paintbrush.pointed", "line.3.horizontal.decrease.circle", "square.3.layers.3d", "camera.aperture", "gearshape", "chevron.down", "chevron.up", "chevron.right", "chevron.right.2",
  "magnifyingglass", "rectangle.dashed", "sidebar.right", "xmark", "xmark.circle", "macwindow.on.rectangle", "slider.horizontal.3", "building.2", "list.bullet.indent", "paintpalette",
  "clock.arrow.circlepath", "square.grid.3x3.square", "rectangle.stack", "info.square", "map", "bell.badge", "slider.horizontal.below.rectangle", "list.bullet.rectangle",
  "books.vertical.circle", "square.and.pencil", "house.lodge", "keyboard", "clock", "star.fill", "house", "lifepreserver", "cursorarrow.rays", "eye.slash", "lock", "lock.open",
  "snowflake", "sun.max", "scope", "arrow.left.arrow.right.square", "square.on.square.intersection.dashed", "plus", "minus", "square.grid.3x3", "terminal", "checkmark",
  "line.3.horizontal", "lineweight", "trash", "plus.circle", "pencil", "arrow.down.right.and.arrow.up.left", "cube", "square", "rectangle.split.2x1", "doc.richtext", "ellipsis",
  // Dialogs (src/renderer/dialogs): Settings, Customize Ribbon, Layers panel, pickers.
  "chevron.up.chevron.down", "menubar.rectangle", "arrow.up", "arrow.down", "minus.circle", "line.3.horizontal.decrease.circle.fill", "checkmark.circle",
  "checkmark.circle.fill", "lock.fill", "pencil.line", "antenna.radiowaves.left.and.right", "pencil.and.ruler", "doc.badge.gearshape", "ruler", "ruler.fill",
  "printer.dotmatrix", "circle", "folder.badge.plus", "doc.badge.arrow.up", "folder.fill", "plus.magnifyingglass", "eraser", "line.diagonal", "wand.and.rays", "textformat"];
const syms = new Set(chrome);
(function walk(o) {
  if (Array.isArray(o)) o.forEach(walk);
  else if (o && typeof o === "object") { if (typeof o.symbol === "string" && o.symbol) syms.add(o.symbol); Object.values(o).forEach(walk); }
})(ui);
// Tool palettes (palettes.generated.json) and every literal icon("…") call in the renderer also need a glyph.
const palettesPath = path.join(dataDir, "palettes.generated.json");
if (fs.existsSync(palettesPath)) (function walk(o) {
  if (Array.isArray(o)) o.forEach(walk);
  else if (o && typeof o === "object") { if (typeof o.symbol === "string" && o.symbol) syms.add(o.symbol); Object.values(o).forEach(walk); }
})(JSON.parse(fs.readFileSync(palettesPath, "utf8")));
(function scan(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) scan(p);
    else if (e.name.endsWith(".ts")) for (const m of fs.readFileSync(p, "utf8").matchAll(/\bicon\(\s*["'`]([a-z0-9]+(?:\.[a-z0-9]+)*)["'`]/g)) syms.add(m[1]);
  }
})(path.join(root, "src"));

// Icon source, in order: the lucide package (npm, ISC) by its exported PascalCase name, its per-icon ES module files,
// then react-icons' copy of Lucide (REACT_ICONS_LU or ~/.npm-global), then the previously generated set.
const require = createRequire(import.meta.url);
const kebabs = (n) => {
  const a = n.replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/([A-Z])([A-Z][a-z])/g, "$1-$2").toLowerCase();
  return [...new Set([a, a.replace(/([a-z])(\d)/g, "$1-$2"), a.replace(/(\d)-x-(\d)/g, "$1x$2"), a.replace(/([a-z])(\d)/g, "$1-$2").replace(/(\d)-x-(\d)/g, "$1x$2")])];
};
const clean = (nodes) => {
  if (!Array.isArray(nodes)) return null;
  if (nodes[0] === "svg") nodes = nodes[2];
  return nodes.map(([tag, attrs]) => [tag, Object.fromEntries(Object.entries(attrs || {}).filter(([k]) => k !== "key"))]);
};
const loaders = [];
let iconSource = "";
try {
  const lucideDir = path.dirname(require.resolve("lucide/package.json"));
  // lucide's `icons` holds the current names; renamed icons stay exported under their old names on the module itself.
  let exported = null;
  try { const mod = require("lucide"); exported = new Proxy({}, { get: (_t, n) => mod.icons?.[n] ?? mod[n] }); } catch {}
  const version = JSON.parse(fs.readFileSync(path.join(lucideDir, "package.json"), "utf8")).version;
  iconSource = `lucide ${version}`;
  loaders.push((name) => {
    if (exported && Array.isArray(exported[name])) return clean(exported[name]);
    for (const k of kebabs(name)) {
      const f = path.join(lucideDir, "dist/esm/icons", k + ".js");
      if (!fs.existsSync(f)) continue;
      const m = fs.readFileSync(f, "utf8").match(/=\s*(\[[\s\S]*\]);/);
      // Newer lucide files reference their own helpers (e.g. defaultAttributes) inside the array: skip what cannot be evaluated.
      if (m) { try { return clean(Function(`return ${m[1]}`)()); } catch { continue; } }
    }
    return null;
  });
} catch {}
{
  const candidates = [process.env.REACT_ICONS_LU, path.join(process.env.HOME || process.env.USERPROFILE || "", ".npm-global/lib/node_modules/react-icons/lu/index.js")].filter(Boolean);
  const f = candidates.find((c) => fs.existsSync(c));
  if (f) {
    const txt = fs.readFileSync(f, "utf8");
    iconSource ||= "react-icons/lu (Lucide)";
    loaders.push((name) => {
      const m = txt.match(new RegExp(`function Lu${name} \\(props\\) \\{\\s*return GenIcon\\((\\{.*?\\})\\)\\(props\\)`));
      return m ? JSON.parse(m[1]).child.map((c) => [c.tag, c.attr]) : null;
    });
  }
}
const load = (name) => { for (const l of loaders) { const n = l(name); if (n && n.length) return n; } return null; };
const iconsPath = path.join(dataDir, "icons.generated.json");
const previous = fs.existsSync(iconsPath) ? JSON.parse(fs.readFileSync(iconsPath, "utf8")).icons : {};
const icons = {};
const missing = [];   // Lucide name not found in any source (kept the previous glyph when there was one)
const unmapped = [];  // SF Symbol with no explicit entry in tools/sf-to-lucide.mjs (prefix rule or generic fallback)
for (const sf of [...syms].sort()) {
  if (!explicit[sf]) unmapped.push(sf);
  const name = lucideFor(sf);
  let nodes = load(name);
  if (!nodes && previous[sf]?.lucide === name) nodes = previous[sf].nodes;
  if (!nodes) { missing.push(sf + "->" + name); nodes = previous[sf]?.nodes || load("SquareTerminal"); }
  if (!nodes) continue;
  icons[sf] = { lucide: name, nodes };
}
fs.writeFileSync(iconsPath, JSON.stringify({ licence: "Icons: Lucide (https://lucide.dev), ISC licence. Mapped from the Mac app's SF Symbol names.", icons }));
console.log(`ui data from ${source}: ${ui.ribbon.length} tabs; ${Object.keys(ui.guide.commands).length} guide anchors; ${Object.keys(icons).length} icons from ${iconSource || "the previous icons.generated.json (no lucide installed)"}` +
  `${missing.length ? `; MISSING ${missing.length}: ${missing.join(" ")}` : ""}${unmapped.length ? `; UNMAPPED ${unmapped.length}: ${unmapped.join(" ")}` : ""}`);
if (process.argv.includes("--strict") && (missing.length || unmapped.length)) process.exit(1);
