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
import { lucideFor } from "./sf-to-lucide.mjs";

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
  return { ribbon, menus: p.menus || fallback.menus, panels: p.panels || fallback.panels, shortcuts: p.shortcuts || [] };
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
fs.writeFileSync(path.join(dataDir, "ui.generated.json"), JSON.stringify(ui));

// ---- icons ----
const chrome = ["doc.badge.plus", "folder", "square.and.arrow.down", "square.and.arrow.down.on.square", "arrow.uturn.backward", "arrow.uturn.forward", "printer", "eye", "doc.on.doc",
  "paintbrush.pointed", "line.3.horizontal.decrease.circle", "square.3.layers.3d", "camera.aperture", "gearshape", "chevron.down", "chevron.up", "chevron.right", "chevron.right.2",
  "magnifyingglass", "rectangle.dashed", "sidebar.right", "xmark", "xmark.circle", "macwindow.on.rectangle", "slider.horizontal.3", "building.2", "list.bullet.indent", "paintpalette",
  "clock.arrow.circlepath", "square.grid.3x3.square", "rectangle.stack", "info.square", "map", "bell.badge", "slider.horizontal.below.rectangle", "list.bullet.rectangle",
  "books.vertical.circle", "square.and.pencil", "house.lodge", "keyboard", "clock", "star.fill", "house", "lifepreserver", "cursorarrow.rays", "eye.slash", "lock", "lock.open",
  "snowflake", "sun.max", "scope", "arrow.left.arrow.right.square", "square.on.square.intersection.dashed", "plus", "minus", "square.grid.3x3", "terminal", "checkmark",
  "line.3.horizontal", "lineweight", "trash", "plus.circle", "pencil", "arrow.down.right.and.arrow.up-left", "cube", "square", "rectangle.split.2x1", "doc.richtext", "ellipsis"];
const syms = new Set(chrome);
(function walk(o) {
  if (Array.isArray(o)) o.forEach(walk);
  else if (o && typeof o === "object") { if (typeof o.symbol === "string" && o.symbol) syms.add(o.symbol); Object.values(o).forEach(walk); }
})(ui);

const require = createRequire(import.meta.url);
function kebab(n) { return n.replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/([A-Z])([A-Z][a-z])/g, "$1-$2").replace(/([a-zA-Z])(\d)/g, "$1-$2").toLowerCase(); }
let loader = null;
try {
  const lucideDir = path.dirname(require.resolve("lucide/package.json"));
  loader = (name) => {
    const f = path.join(lucideDir, "dist/esm/icons", kebab(name) + ".js");
    if (!fs.existsSync(f)) return null;
    const txt = fs.readFileSync(f, "utf8");
    const m = txt.match(/=\s*(\[[\s\S]*\]);/);
    if (!m) return null;
    let nodes = Function(`return ${m[1]}`)();
    if (nodes[0] === "svg") nodes = nodes[2];
    return nodes.map(([tag, attrs]) => [tag, Object.fromEntries(Object.entries(attrs).filter(([k]) => k !== "key"))]);
  };
} catch {}
if (!loader) {
  const candidates = [process.env.REACT_ICONS_LU, path.join(process.env.HOME || "", ".npm-global/lib/node_modules/react-icons/lu/index.js")].filter(Boolean);
  const f = candidates.find((c) => fs.existsSync(c));
  if (f) {
    const txt = fs.readFileSync(f, "utf8");
    loader = (name) => {
      const m = txt.match(new RegExp(`function Lu${name} \\(props\\) \\{\\s*return GenIcon\\((\\{.*?\\})\\)\\(props\\)`));
      if (!m) return null;
      const tree = JSON.parse(m[1]);
      return tree.child.map((c) => [c.tag, c.attr]);
    };
  }
}
const iconsPath = path.join(dataDir, "icons.generated.json");
const previous = fs.existsSync(iconsPath) ? JSON.parse(fs.readFileSync(iconsPath, "utf8")).icons : {};
const icons = {};
const missing = [];
for (const sf of [...syms].sort()) {
  const name = lucideFor(sf);
  let nodes = loader ? loader(name) : null;
  if (!nodes && previous[sf]) nodes = previous[sf].nodes;
  if (!nodes && loader) { missing.push(sf + "->" + name); nodes = loader("SquareTerminal"); }
  if (!nodes) { missing.push(sf); continue; }
  icons[sf] = { lucide: name, nodes };
}
fs.writeFileSync(iconsPath, JSON.stringify({ licence: "Icons: Lucide (https://lucide.dev), ISC licence. Mapped from the Mac app's SF Symbol names.", icons }));
console.log(`ui data from ${source}: ${ui.ribbon.length} tabs; ${Object.keys(icons).length} icons${missing.length ? `, missing ${missing.length}: ${missing.slice(0, 10).join(" ")}` : ""}${loader ? "" : " (no icon source: kept previous)"}`);
