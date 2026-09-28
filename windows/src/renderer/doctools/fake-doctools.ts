// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of the document tools (doctools/): recorded Cedar House answers (doc-*.json from
// ./scripts/q.sh engine) where they exist, otherwise a small simulation over the fixture engine's drawing, so the
// Schedule sheet, Project Browser, Selection / Quick Props / Inspector / History panels, Spelling and Text Styles can be
// exercised in the browser test page. Never used inside the Electron app.

export const DOC_COMMANDS: { name: string; aliases: string[]; category: string; summary: string }[] = [
  { name: "SPELLDIALOG", aliases: ["SPELLING", "CHECKSPELLING"], category: "Annotate", summary: "Spelling dialog: lists misspelled words in text, leaders, tables and attributes with suggestions (Change / Ignore / Add)." },
  { name: "TEXTSTYLEDIALOG", aliases: ["TEXTSTYLEMANAGER", "STYLEDIALOG"], category: "Annotate", summary: "Text Style manager: font, height, width factor and oblique angle with a live preview; renaming a style updates its text." },
  { name: "TEXTEDITINPLACE", aliases: ["MTEDIT", "INPLACETEXT", "TEXTFORMAT"], category: "Annotate", summary: "In-place text editor on the canvas: bold, italic, underline, font, height and colour (also opened by double-clicking text); exported to PDF and DXF MTEXT." },
  { name: "HYPERLINK", aliases: ["LINK", "URL", "-HYPERLINK"], category: "Annotate", summary: "Attaches a URL (web page or file) to objects; exported PDFs make them clickable. Empty removes the link." },
  { name: "SELECTIONINFO", aliases: ["SELINFO", "SELECTIONPANEL"], category: "Inquiry", summary: "Selection info panel: count and types of the selected objects, layers, total length/area, keep-only/remove filters." },
  { name: "QUICKPROPS", aliases: ["QP", "QUICKPROPERTIES"], category: "View", summary: "Quick Properties: a compact editor of the selection's key properties over the drawing." },
  { name: "INSPECT", aliases: ["OBJECTINFO", "LISTPANEL"], category: "Inquiry", summary: "Opens the Inspector panel: every stored value of the selected objects, with ID and GUID." },
  { name: "SELECTWALLCHAIN", aliases: ["WALLCHAIN"], category: "Select", summary: "Selects the chain of walls joined to a picked wall (Tab over a wall does the same)." },
];
const TYPES: Record<string, string> = { "A-WALL": "wall", "A-DOOR": "door", "A-GLAZ": "window", "A-AREA": "room", "A-ANNO-DIMS": "dimension", "L-PLNT": "plant", "C-TOPO": "topography", LIGHTS: "light" };
const LAYERS: Record<string, string> = { wall: "A-WALL", door: "A-DOOR", window: "A-GLAZ", space: "A-AREA", slab: "A-FLOR", text: "A-ANNO-TEXT" };
const KINDS = ["walls", "doors", "windows", "rooms", "slabs", "all"];

const cache = new Map<string, any>();
async function fixture(fe: any, name: string) {
  if (!cache.has(name)) cache.set(name, await fe.fetchJSON(name));
  return cache.get(name);
}
const styles: any[] = [{ name: "Standard", font: "Helvetica", height: "0", widthFactor: "1", obliqueDegrees: "0", strokeFont: false, uses: 0 }];
let currentStyle = "Standard";
const custom = new Set<string>();

/** Element types of the recorded Cedar House (the id column of each schedule), loaded with the first document tool call. */
const elementTypes = new Map<string, string>();
async function loadTypes(fe: any) {
  if (elementTypes.size) return;
  const rec = await fixture(fe, "doc-schedules.json");
  // The "all" schedule: id, type, … for every element.
  const all = (Array.isArray(rec) ? rec : []).find((x: any) => x.request?.params?.kind === "all");
  for (const r of (all?.response?.result?.rows ?? []).slice(1)) elementTypes.set(String(r[0]), String(r[1]));
}
function typeOf(e: any) {
  return elementTypes.get(String(e.id)) ?? TYPES[e.layer ?? ""] ?? (e.items?.some((i: any) => (i.type ?? "") === "text") ? "text" : "line");
}
function idNum(x: string) { return isNaN(Number(x)) ? x : Number(x); }
function textItems(e: any): any[] { return (e.items ?? []).filter((i: any) => i.type === "text" && i.text); }

export function fakeDocCall(fe: any, method: string, p: any): any {
  const emitHost = (params: any) => fe.emit("host", params);
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of DOC_COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c, modifies: c.name === "HYPERLINK" });
      return undefined;
    }
    case "command.run": {
      const toks = String(p.line ?? "").trim().split(/\s+/);
      const name = toks[0]?.toUpperCase() ?? "";
      const def = DOC_COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (!def) return undefined;
      fe.log(`Command: ${name}`);
      const idle = { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };
      switch (def.name) {
        case "SPELLDIALOG": emitHost({ action: "dialog", dialog: "spelling" }); break;
        case "TEXTSTYLEDIALOG": emitHost({ action: "dialog", dialog: "textStyles" }); break;
        case "SELECTIONINFO": emitHost({ action: "showPanel", panel: "Selection" }); break;
        case "INSPECT": emitHost({ action: "showPanel", panel: "Inspector" }); break;
        case "QUICKPROPS": { const a = (toks[1] ?? "Toggle").toUpperCase(); emitHost({ action: "quickProps", mode: a === "ON" ? "on" : a === "OFF" ? "off" : "toggle" }); break; }
        case "TEXTEDITINPLACE": {
          const t = (fe.raw as any[]).find((e) => textItems(e).length && (fe.selection.size === 0 || fe.selection.has(e.id)));
          if (t) emitHost({ action: "textEditor", id: idNum(t.id) }); else fe.log("Select a text object.");
          break;
        }
        case "SELECTWALLCHAIN": {
          const walls = (fe.raw as any[]).filter((e) => elementTypes.get(String(e.id)) === "wall").slice(0, 4).map((e) => e.id);
          for (const w of walls) fe.selection.add(w);
          fe.log(`${walls.length} joined wall(s) selected.`); fe.changed("selection"); break;
        }
        case "HYPERLINK": fe.log(`${fe.selection.size} object(s) link to ${toks.slice(1).join(" ")}.`); break;
      }
      return idle;
    }
    case "schedule.get": return (async () => {
      const kind = String(p.kind ?? "all").toLowerCase();
      const rec = await fixture(fe, "doc-schedules.json");
      const r = Array.isArray(rec) ? rec.find((x: any) => x.request?.params?.kind === kind)?.response?.result : null;
      return r ?? { kind, kinds: KINDS, rows: [], count: 0 };
    })();
    case "browser.get": return (async () => {
      const rec = (await fixture(fe, "doc-browser.json"))?.response?.result;
      const levels = [...(fe.info.levels ?? [])].sort((a: any, b: any) => b.elevation - a.elevation)
        .map((l: any) => ({ id: l.id, name: l.name, elevation: l.elevation, current: l.name === fe.info.currentLevel }));
      const base = rec ? JSON.parse(JSON.stringify(rec)) : { views3d: ["Iso", "Top", "Front", "Right", "Back", "Left"], namedViews: [], projectViews: [], elevations: [], schedules: KINDS, families: [], groups: [], links: [] };
      if (!(fe.info.levels ?? []).some((l: any) => l.name === "Ground Floor")) { base.namedViews = []; base.families = []; }
      base.projectViews = [{ name: "Level 0 Plan", label: "Level 0 Plan", kind: "plan", symbol: "square.split.bottomrightquarter", current: false }];
      base.groups = [{ name: "Bathroom pod", elements: 3 }];
      base.links = [{ name: "Site survey", path: "C:\\Projects\\site.dxf", overlay: true, loaded: true }];
      return { ...base, levels, sheets: (fe.info.layouts ?? []).map((name: string, index: number) => ({ index, name })) };
    })();
    case "browser.openView": fe.log("Open View"); return { name: p.name, kind: "plan", level: 0, crop: [0, 0, 12000, 9000] };
    case "selection.info": return loadTypes(fe).then(() => {
      const by = new Map<string, string[]>(), layers = new Map<string, number>();
      let b: number[] | null = null;
      for (const e of fe.decoded as any[]) {
        if (!e.id || !fe.selection.has(e.id)) continue;
        const raw = (fe.raw as any[]).find((r) => r.id === e.id);
        const t = typeOf(raw ?? {});
        by.set(t, [...(by.get(t) ?? []), e.id]);
        const lay = raw?.layer ?? LAYERS[t] ?? "0";
        layers.set(lay, (layers.get(lay) ?? 0) + 1);
        const eb = e.bounds;
        b = b ? [Math.min(b[0], eb[0]), Math.min(b[1], eb[1]), Math.max(b[2], eb[2]), Math.max(b[3], eb[3])] : [...eb];
      }
      const rows = [...by.entries()].map(([type, ids]) => ({ type, count: ids.length, ids: ids.map(idNum) })).sort((a, c) => c.count - a.count || a.type.localeCompare(c.type));
      const lines = rows.filter((r) => r.type === "line").reduce((a, r) => a + r.count, 0);
      return { total: rows.reduce((a, r) => a + r.count, 0), rows, layers: [...layers.entries()].sort().map(([name, count]) => ({ name, count })),
        length: lines * 1000, area: 0, lengthText: String(lines * 1000), areaText: "0", bounds: b };
    });
    case "inspect.get": return loadTypes(fe).then(() => {
      const ids = (p.ids ?? [...fe.selection]).map(String);
      const objs = ids.slice(0, 20).map((id: string) => {
        const raw = (fe.raw as any[]).find((r) => r.id === id);
        const rows = [["ID", `#${id}`], ["GUID", "2x" + id.padStart(20, "0")], ["Type", typeOf(raw ?? {})], ["Layer", raw?.layer ?? LAYERS[typeOf(raw ?? {})] ?? "0"], ["Color", "ByLayer"], ["Geometry", JSON.stringify(raw?.items?.[0] ?? {}, null, 2)]];
        return { id: idNum(id), rows, text: rows.map(([k, v]) => `${k}: ${v}`).join("\n") };
      });
      return { objects: objs, count: ids.length, more: Math.max(0, ids.length - 20) };
    });
    case "history.goto": return (async () => {
      const idx = Number(p.index);
      while (fe.undo.length > idx) await fe.call("edit.undo");
      while (fe.undo.length < idx && fe.redo.length) await fe.call("edit.redo");
      return fe.history();
    })();
    case "spell.words": {
      const words: any[] = [];
      for (const e of fe.raw as any[]) {
        if (fe.selection.size && !p.all && !fe.selection.has(e.id)) continue;
        for (const it of textItems(e)) for (const w of String(it.text.content ?? "").match(/\p{L}[\p{L}'’-]*\p{L}/gu) ?? []) words.push({ entity: idNum(e.id), word: w, field: "text" });
      }
      return { words, custom: [...custom].sort(), scope: fe.selection.size ? "selection" : "all" };
    }
    case "spell.replace": {
      let n = 0;
      const re = new RegExp(`(?<!\\p{L})${String(p.word).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?!\\p{L})`, "gu");
      fe.undo.push({ label: "Spelling", raw: JSON.stringify(fe.raw) }); fe.redo.length = 0;
      for (const e of fe.raw as any[]) {
        if (!(p.ids ?? []).map(String).includes(String(e.id))) continue;
        for (const it of textItems(e)) { const before = it.text.content; it.text.content = String(before).replace(re, String(p.replacement)); if (it.text.content !== before) n++; }
      }
      fe.decode(); fe.changed("document");
      return { changed: n };
    }
    case "spell.add": custom.add(String(p.word).toLowerCase()); fe.undo.push({ label: "Add to Dictionary", raw: JSON.stringify(fe.raw) }); fe.changed("document"); return { custom: [...custom].sort() };
    case "textstyle.list": {
      let i = 1;
      while (styles.some((s) => s.name === `Style ${i}`)) i++;
      return { styles: JSON.parse(JSON.stringify(styles)), current: currentStyle, fonts: ["Helvetica", "Helvetica Neue", "Arial", "Arial Narrow", "Avenir Next", "Futura", "Gill Sans", "Menlo", "Times New Roman", "Georgia", "Archi Stroke", "romans.shx", "simplex.shx", "isocp.shx"], newName: `Style ${i}` };
    }
    case "textstyle.apply": {
      const num = (s: any) => Number(String(s ?? "").replace(",", "."));
      const errs: string[] = [];
      const name = String(p.name ?? "").trim();
      if (!name) errs.push("name");
      if (!(num(p.height ?? "0") >= 0)) errs.push("height ≥ 0");
      const wf = num(p.widthFactor ?? "1");
      if (!(wf >= 0.01 && wf <= 100)) errs.push("width factor 0.01–100");
      const ob = num(p.obliqueDegrees ?? "0");
      if (!(Math.abs(ob) <= 85)) errs.push("oblique −85…85°");
      if (errs.length) return { ok: false, message: "Check: " + errs.join(", ") };
      const orig = p.original ? styles.find((s) => s.name === p.original) : null;
      if (styles.some((s) => s.name.toLowerCase() === name.toLowerCase() && s !== orig)) return { ok: false, name, message: "A style with that name exists." };
      const st = { name, font: String(p.font ?? "Helvetica"), height: String(p.height ?? "0"), widthFactor: String(p.widthFactor ?? "1"), obliqueDegrees: String(p.obliqueDegrees ?? "0"), strokeFont: false, uses: orig?.uses ?? 0 };
      if (orig) Object.assign(orig, st); else styles.push(st);
      fe.undo.push({ label: "Text Style", raw: JSON.stringify(fe.raw) }); fe.changed("document");
      return { ok: true, name, message: `Saved ${name}.` };
    }
    case "textstyle.current": currentStyle = String(p.name); fe.changed("document"); return { current: currentStyle, message: `${currentStyle} is current.` };
    case "fake.addText": {
      // Test hook: a text object in the fixture drawing (content, position, height).
      const id = String(fe.nextId++);
      fe.raw.push({ id, layer: "A-ANNO-TEXT", items: [{ type: "text", text: { position: p.position ?? [0, 0], height: p.height ?? 250, rotation: 0, content: p.content ?? "Text", style: "Standard", halign: "left", valign: "baseline", width: 0 },
        font: "Helvetica", color: "#ffffff", ...(p.format ? { format: p.format } : {}) }] });
      fe.decode(); fe.changed("document");
      return { id: Number(id) };
    }
  }
  return undefined;
}
