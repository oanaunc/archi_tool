// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Materials panel with the material editor (MaterialsPanel / MaterialEditor / MaterialMapsSection: colour, roughness,
// metalness, transparency, texture, tile size, bump, cut pattern, PBR maps, identity / graphics / physical assets), the
// Material Library browser (MaterialLibrary.swift: categories, rendered sphere thumbnails, Add to Drawing, Assign to
// Selection) and procedural / photo materials (MaterialAssets.swift, PROCMATERIAL). Edits are doc.edit steps with the
// Mac undo labels.
import type { App } from "../app";
import { h, clear, button, iconButton, field, numberField, slider, picker, colorWell, toggleSwitch, spacer, header, ToolWindow, Sheet, swatch, fmt, rgbaToHex, hexToRgba, ico, help, load } from "./ui";
import * as N from "./native";
import { patternCanvas, sphereThumbnail, generate, procDefaults, PROC_KINDS, normals, gray, pngBase64, derivePhoto, type Pattern, type ProcKind, type RGB } from "./materials-gen";

// ---- data ----
interface Mat { name: string; color: { r: number; g: number; b: number; a?: number }; roughness: number; metalness: number; transparency: number; textureScale: number; cutPattern: string; texture?: string | null; [k: string]: any }
interface MatRow { material: Mat; uses: number; maps: string | null; assets: string | null; bump: string | null }
interface MatList { materials: MatRow[]; patterns: string[]; library: Mat[]; folder: string | null }

async function list(app: App): Promise<MatList> { return (await app.tryCall("material.list")) ?? { materials: [], patterns: ["SOLID"], library: [], folder: null }; }

let lastEdit: { label: string; name: string; t: number } | null = null;
/** One doc.edit step; consecutive edits of the same property (slider drags) merge into one undo step (MaterialEditor.update). */
async function edit(app: App, label: string, ops: any[], mergeKey?: string) {
  const now = Date.now();
  const merge = !!mergeKey && !!lastEdit && lastEdit.label === label && lastEdit.name === mergeKey && now - lastEdit.t < 1500;
  lastEdit = mergeKey ? { label, name: mergeKey, t: now } : null;
  const r = await app.tryCall("doc.edit", { label, ops, merge });
  for (const m of r?.messages ?? []) if (label === "Assign Material") app.print(m);
  return r;
}
const hexOf = (m: Mat) => rgbaToHex(m.color).toUpperCase();

function texUrl(app: App, folder: string | null, p?: string | null) {
  if (!p) return null;
  const abs = /^([a-zA-Z]:[\\/]|[\\/])/.test(p) ? p : folder ? N.join(folder, p) : null;
  return abs ? N.fileUrl(app, abs) : null;
}

// ---- Materials panel ----
let selectedMaterial: string | null = null;

export async function renderMaterialsPanel(app: App, body: HTMLElement) {
  const data = await list(app);
  clear(body);
  const mats = data.materials;
  if (selectedMaterial && !mats.some((r) => r.material.name === selectedMaterial)) selectedMaterial = null;
  const sel = mats.find((r) => r.material.name === selectedMaterial) ?? null;
  const redraw = () => renderMaterialsPanel(app, body);
  const newMaterial = async (src: Mat | null) => {
    const names = new Set(mats.map((r) => r.material.name.toLowerCase()));
    let n = 1, name = src ? `${src.name} copy` : "Material 1";
    while (names.has(name.toLowerCase())) { n += 1; name = src ? `${src.name} copy ${n}` : `Material ${n}`; }
    const m: Mat = src ? { ...JSON.parse(JSON.stringify(src)), name } : { name, color: { r: 0.8, g: 0.8, b: 0.8, a: 1 }, roughness: 0.8, metalness: 0, transparency: 0, textureScale: 1000, cutPattern: "SOLID" };
    await edit(app, "New Material", [{ op: "addMaterial", material: m }]);
    selectedMaterial = name;
    redraw();
  };
  const hasSel = app.selection.ids.length > 0;
  const bar = h("div", { class: "pb-row", style: { padding: "8px", gap: "4px" } },
    button("New", { icon: "plus", compact: true, onClick: () => newMaterial(null) }),
    button("Duplicate", { icon: "plus.square.on.square", compact: true, disabled: !sel, onClick: () => sel && newMaterial(sel.material) }),
    button("Delete", { icon: "minus", compact: true, disabled: !sel || sel.uses > 0, help: "Delete the selected material (only when no element uses it)",
      onClick: async () => { if (!sel || sel.uses > 0) return; await edit(app, "Delete Material", [{ op: "removeMaterial", name: sel.material.name }]); selectedMaterial = null; redraw(); } }),
    spacer(),
    iconButton("paintbrush.pointed", "Assign the material to the selected building elements", async () => {
      if (!sel) return;
      await edit(app, "Assign Material", [{ op: "assignMaterial", name: sel.material.name, ids: app.selection.ids.map(Number) }]);
      await app.refresh(["document"]); redraw();
    }, { disabled: !sel || !hasSel }));
  const listEl = h("div", { class: "pb-scroll", style: { maxHeight: sel ? "190px" : "none", flex: sel ? "none" : "1" } });
  for (const r of mats) {
    const m = r.material;
    const detail = `Rough ${fmt(m.roughness)} · Metal ${fmt(m.metalness)}${m.transparency > 0 ? ` · Transp ${fmt(m.transparency)}` : ""}${m.texture ? " · Texture" : ""}`;
    const row = h("div", { class: "pb-list-row soft" + (selectedMaterial === m.name ? " sel" : ""), style: { padding: "4px 10px", gap: "8px" }, "data-material": m.name },
      swatch(m, 26, texUrl(app, data.folder, m.texture)),
      h("div", { class: "pb-col", style: { gap: "1px", minWidth: "0", flex: "1" } }, h("div", { style: { fontWeight: "600" }, text: m.name }), h("div", { class: "pb-small pb-dim", style: { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }, text: detail })),
      r.uses ? h("span", { class: "pb-badge", text: String(r.uses) }) : null);
    if (r.uses) help(row.lastElementChild as HTMLElement, `${r.uses} element(s) use this material`);
    row.addEventListener("click", () => { selectedMaterial = selectedMaterial === m.name ? null : m.name; redraw(); });
    listEl.append(row);
  }
  body.append(bar, h("div", { class: "pb-hsep" }), listEl);
  if (sel) body.append(h("div", { class: "pb-hsep" }), materialEditor(app, sel, data, redraw));
}

function materialEditor(app: App, row: MatRow, data: MatList, redraw: () => void): HTMLElement {
  const m = row.material;
  const update = async (label: string, change: (x: Mat) => void, merge = false) => {
    const x: Mat = JSON.parse(JSON.stringify(m));
    change(x);
    Object.assign(m, x);
    await edit(app, `Material ${label}`, [{ op: "setMaterial", name: m.name, material: x }], merge ? m.name : undefined);
  };
  const name = field({ value: m.name, flex: true, onCommit: async (v) => {
    const nv = v.trim(), old = m.name;
    if (!nv || nv === old) return;
    if (data.materials.some((r) => r.material.name.toLowerCase() === nv.toLowerCase() && nv.toLowerCase() !== old.toLowerCase())) { name.value = old; return; }
    await edit(app, "Rename Material", [{ op: "renameMaterial", from: old, to: nv }]);
    selectedMaterial = nv; redraw();
  } });
  const sw = swatch(m, 44, texUrl(app, data.folder, m.texture));
  const hexLabel = h("span", { class: "pb-mono pb-dim", text: hexOf(m) });
  const color = colorWell(hexOf(m), async (hx) => { await update("Color", (x) => { x.color = hexToRgba(hx, x.color?.a ?? 1); }); hexLabel.textContent = hx; redraw(); });
  const slide = (title: string, key: "roughness" | "metalness" | "transparency", max: number) => {
    const val = h("span", { class: "pb-mono", style: { width: "34px", textAlign: "right" }, text: fmt(m[key]) });
    const s = slider(m[key], 0, max, { step: 0.01, onInput: (v) => { val.textContent = fmt(v); }, onChange: (v) => update(title, (x) => { x[key] = Math.round(v * 100) / 100; }, true).then(redraw) });
    return h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: title }), s, val);
  };
  const maps = parseJSON(row.maps) ?? {};
  const assets = parseJSON(row.assets) ?? {};
  const el = h("div", { class: "pb-col pb-scroll", style: { padding: "10px", gap: "7px", flex: "1" } },
    h("div", { class: "pb-row", style: { gap: "10px" } }, sw, h("div", { class: "pb-col", style: { gap: "4px", flex: "1" } }, name, h("div", { class: "pb-row" }, color, hexLabel))),
    slide("Roughness", "roughness", 1), slide("Metalness", "metalness", 1), slide("Transparency", "transparency", 0.95),
    h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: "Texture" }), h("span", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: m.texture ? N.basename(m.texture) : "None" }), spacer(),
      button("Choose…", { compact: true, onClick: async () => { const p = await chooseImage(app, "Choose a texture image"); if (p) { await update("Texture", (x) => { x.texture = relative(app, p); }); redraw(); } } }),
      m.texture ? iconButton("xmark.circle", "Remove the texture", async () => { await update("Texture", (x) => { x.texture = null; }); redraw(); }) : null),
    m.texture ? h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: "Tile size" }), numberField(m.textureScale, (v) => update("Texture Scale", (x) => { x.textureScale = Math.max(1, v); }).then(redraw), { width: 80 }), h("span", { class: "pb-dim", text: "mm" })) : null,
    m.texture ? bumpRow(app, m, row) : null,
    h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: "Cut pattern" }), picker(data.patterns, (m.cutPattern || "SOLID").toUpperCase(), (v) => update("Cut Pattern", (x) => { x.cutPattern = v; }).then(redraw), 140)),
    mapsSection(app, m, maps, assets, redraw));
  return el;
}

function bumpRow(app: App, m: Mat, row: MatRow): HTMLElement {
  const v0 = row.bump !== null && row.bump !== undefined && isFinite(Number(row.bump)) ? Math.max(0, Math.min(Number(row.bump), 5)) : 0.4;
  const val = h("span", { class: "pb-mono", style: { width: "34px", textAlign: "right" }, text: fmt(v0) });
  const s = slider(v0, 0, 2, { step: 0.01, onInput: (v) => { val.textContent = fmt(v); }, onChange: (v) => edit(app, "Material Bump", [{ op: "setVariable", name: "MATBUMP:" + m.name.toUpperCase(), value: fmt(v, 2) }], m.name) });
  const r = h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: "Bump" }), s, val);
  help(r, "Relief from the texture's luminance in Realistic 3D and renders (0 = off)");
  return r;
}

function parseJSON(s: string | null | undefined): any { if (!s) return null; try { return JSON.parse(s); } catch { return null; } }
function sortedJSON(o: any) { const out: any = {}; for (const k of Object.keys(o).sort()) if (o[k] !== undefined && o[k] !== null) out[k] = o[k]; return JSON.stringify(out); }

const SLOTS: [string, string][] = [["Normal", "normal"], ["Roughness", "roughness"], ["Metallic", "metallic"], ["AO", "ao"], ["Displacement", "displacement"]];

function mapsSection(app: App, m: Mat, maps: any, assets: any, redraw: () => void): HTMLElement {
  const key = m.name.toUpperCase();
  const saveMaps = async (label: string, next: any, merge = false) => {
    const empty = SLOTS.every(([, k]) => !next[k]) && (next.normalStrength ?? 1) === 1 && (next.displacementScale ?? 0) === 0;
    await edit(app, `Material ${label}`, [{ op: "setVariable", name: "MATMAPS:" + key, value: empty ? null : sortedJSON({ normalStrength: 1, displacementScale: 0, ...next }) }], merge ? m.name : undefined);
  };
  const saveAssets = async (next: any) => { await edit(app, "Material Asset", [{ op: "setVariable", name: "MATASSET:" + key, value: sortedJSON(next) }]); };
  const el = h("div", { class: "pb-col", style: { gap: "5px" } }, h("div", { class: "pb-dim", style: { fontWeight: "600" }, text: "PBR maps" }));
  for (const [title, k] of SLOTS) {
    el.append(h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: title }), h("span", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: maps[k] ? N.basename(maps[k]) : "None" }), spacer(),
      button("Choose…", { compact: true, onClick: async () => {
        const p = await chooseImage(app, `Choose the ${title.toLowerCase()} map (it tiles like the albedo texture)`);
        if (!p) return;
        const next = { ...maps, [k]: relative(app, p) };
        if (k === "displacement" && !next.displacementScale) next.displacementScale = 5;
        await saveMaps("Map", next); redraw();
      } }),
      maps[k] ? iconButton("xmark.circle", `Remove the ${title.toLowerCase()} map`, async () => { const next = { ...maps }; delete next[k]; await saveMaps("Map", next); redraw(); }) : null));
  }
  if (maps.normal) {
    const v0 = maps.normalStrength ?? 1;
    const val = h("span", { class: "pb-mono", style: { width: "34px", textAlign: "right" }, text: fmt(v0) });
    el.append(h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: "Normal" }),
      slider(v0, 0, 3, { step: 0.01, onInput: (v) => { val.textContent = fmt(v); }, onChange: (v) => saveMaps("Normal Strength", { ...maps, normalStrength: Math.round(v * 100) / 100 }, true) }), val));
  }
  if (maps.displacement) el.append(h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: "Height" }), numberField(maps.displacementScale ?? 0, (v) => saveMaps("Displacement", { ...maps, displacementScale: Math.max(0, v) }).then(redraw), { width: 70 }), h("span", { class: "pb-dim", text: "mm" })));
  const pt = button("Path Trace", { compact: true, help: "Preview the materials in the path tracer (glass refraction, PBR maps)", onClick: () => app.runCommand("PATHTRACE") });
  el.append(h("div", { class: "pb-row" }, pt, button("Procedural…", { compact: true, onClick: () => showProceduralMaterial(app) }), button("From Photo…", { compact: true, onClick: () => materialFromPhoto(app) })));
  // Identity, graphics & physical (VIS-068).
  let open = load<boolean>("materials.assetsOpen", false);
  const disclosure = h("button", { class: "pb-row pb-dim", style: { gap: "4px", padding: "2px 0" } }, ico(open ? "chevron.down" : "chevron.right", 9, 2), h("span", { text: "Identity, graphics & physical" }));
  const form = h("div", { class: "pb-col", style: { gap: "4px", paddingTop: "4px", display: open ? "" : "none" } });
  disclosure.addEventListener("click", () => { open = !open; localStorage.setItem("archi.b.materials.assetsOpen", JSON.stringify(open)); form.style.display = open ? "" : "none"; disclosure.replaceChild(ico(open ? "chevron.down" : "chevron.right", 9, 2), disclosure.firstChild!); });
  const a = { useRenderAppearance: true, description: "", manufacturer: "", model: "", mark: "", keynote: "", url: "", ...assets };
  const rowF = (t: string, ...kids: (Node | null)[]) => h("div", { class: "pb-row" }, h("span", { class: "pb-dim", style: { width: "90px", flex: "none" }, text: t }), ...kids);
  const txt = (k: string) => field({ value: a[k] ?? "", flex: true, onCommit: (v) => saveAssets({ ...a, [k]: v }) });
  const num = (k: string, unit: string) => h("div", { class: "pb-row", style: { gap: "4px" } }, numberField(a[k] ?? 0, (v) => saveAssets({ ...a, [k]: v > 0 ? v : undefined }), { width: 80 }), h("span", { class: "pb-dim", text: unit }));
  form.append(rowF("Description", txt("description")), rowF("Manufacturer", txt("manufacturer")), rowF("Mark", txt("mark")),
    toggleSwitch("Shaded views use the render colour", a.useRenderAppearance, (v) => { const n: any = { ...a, useRenderAppearance: v }; if (!v && !n.shadingColor) n.shadingColor = hexOf(m); saveAssets(n).then(redraw); }),
    a.useRenderAppearance ? "" : rowF("Shading", colorWell(a.shadingColor ?? hexOf(m), (hx) => saveAssets({ ...a, shadingColor: hx }))),
    rowF("Density", num("density", "kg/m³")), rowF("Conductivity", num("conductivity", "W/m·K")), rowF("Specific heat", num("specificHeat", "J/kg·K")));
  el.append(disclosure, form);
  return el;
}

async function chooseImage(app: App, title: string) { return N.openFile(app, title, [{ name: "Images", extensions: ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif", "webp", "heic"] }]); }
/** Paths inside the drawing's folder are stored relative to it (as the Mac does). */
function relative(app: App, p: string) {
  const dir = app.info?.path ? N.dirname(app.info.path) : null;
  if (dir && (p.startsWith(dir + "\\") || p.startsWith(dir + "/"))) return p.slice(dir.length + 1);
  return p;
}

// ---- Material library (MaterialLibraryBrowser) ----

interface LibMat { category: string; material: Mat; pattern: Pattern }
const CATEGORIES = ["All", "In Drawing", "Masonry", "Concrete & Stone", "Wood", "Metal", "Glass", "Finishes", "Roofing", "Site"];
function lm(cat: string, name: string, hx: string, r: number, o: { metal?: number; t?: number; cut?: string; p?: Pattern; scale?: number } = {}): LibMat {
  return { category: cat, pattern: o.p ?? "none", material: { name, color: hexToRgba(hx, 1), roughness: r, metalness: o.metal ?? 0, transparency: o.t ?? 0, textureScale: o.scale ?? 1000, cutPattern: o.cut ?? "SOLID" } };
}
const LIBRARY: LibMat[] = [
  lm("Masonry", "Brick Red", "9E4A36", 0.85, { cut: "ANSI31", p: "brick" }), lm("Masonry", "Brick Yellow", "C9A56A", 0.85, { cut: "ANSI31", p: "brick" }),
  lm("Masonry", "Brick White Painted", "EDEBE6", 0.8, { cut: "ANSI31", p: "brick" }), lm("Masonry", "Concrete Block", "A7A7A2", 0.9, { cut: "ANSI31", p: "brick", scale: 1600 }),
  lm("Concrete & Stone", "Concrete Smooth", "B9B8B3", 0.75, { cut: "AR-CONC" }), lm("Concrete & Stone", "Concrete Board-Formed", "A9A8A2", 0.9, { cut: "AR-CONC", p: "planks", scale: 1200 }),
  lm("Concrete & Stone", "Limestone", "D8CDB3", 0.8, { cut: "AR-SAND", p: "stone", scale: 1500 }), lm("Concrete & Stone", "Granite Dark", "4B4B4E", 0.35, { cut: "AR-SAND" }),
  lm("Concrete & Stone", "Marble White", "EEEDEA", 0.15, { cut: "AR-SAND", p: "stone", scale: 1200 }), lm("Concrete & Stone", "Terrazzo", "CFC9BF", 0.3, { cut: "AR-CONC" }),
  lm("Wood", "Oak", "B08A5B", 0.55, { cut: "ANSI32", p: "planks", scale: 900 }), lm("Wood", "Walnut", "5E4130", 0.5, { cut: "ANSI32", p: "planks", scale: 900 }),
  lm("Wood", "Pine", "D2B48C", 0.6, { cut: "ANSI32", p: "planks", scale: 900 }), lm("Wood", "Larch Cladding", "9C7A57", 0.7, { cut: "ANSI32", p: "planks", scale: 1100 }),
  lm("Wood", "Plywood", "D6BC8F", 0.6, { cut: "ANSI32" }),
  lm("Metal", "Stainless Steel", "C2C5C9", 0.25, { metal: 1, cut: "ANSI37" }), lm("Metal", "Brushed Aluminium", "B7BBC0", 0.4, { metal: 1 }),
  lm("Metal", "Corten", "8A4B2A", 0.8, { metal: 0.4 }), lm("Metal", "Copper", "B87333", 0.35, { metal: 1 }), lm("Metal", "Zinc", "8E9398", 0.5, { metal: 0.9 }),
  lm("Metal", "Black Steel", "2A2B2D", 0.45, { metal: 1, cut: "ANSI37" }),
  lm("Glass", "Clear Glass", "A9CBD9", 0.03, { t: 0.8 }), lm("Glass", "Tinted Glass", "5E7A86", 0.05, { t: 0.6 }), lm("Glass", "Frosted Glass", "DCE6EA", 0.5, { t: 0.45 }),
  lm("Finishes", "White Paint", "F3F2EE", 0.85), lm("Finishes", "Warm Grey Paint", "B8B2A8", 0.85),
  lm("Finishes", "Ceramic Tiles White", "F0EFEB", 0.2, { p: "tiles", scale: 600 }), lm("Finishes", "Ceramic Tiles Grey", "9D9E9B", 0.25, { p: "tiles", scale: 600 }),
  lm("Finishes", "Carpet Grey", "6E6F71", 1), lm("Finishes", "Linoleum", "7A8C6E", 0.5), lm("Finishes", "Acoustic Ceiling", "E8E7E3", 1, { p: "grid", scale: 600 }),
  lm("Roofing", "Clay Roof Tiles", "9A4B32", 0.8, { p: "tiles", scale: 400 }), lm("Roofing", "Slate", "3F4449", 0.6, { p: "tiles", scale: 500 }),
  lm("Roofing", "Standing Seam Zinc", "7F858A", 0.45, { metal: 0.8, p: "planks", scale: 500 }), lm("Roofing", "Green Roof", "5E7F3E", 1),
  lm("Site", "Lawn", "5B8A3A", 1), lm("Site", "Gravel", "A39E92", 1, { p: "stone", scale: 400 }), lm("Site", "Asphalt", "3B3C3E", 0.95),
  lm("Site", "Paving Stones", "9C958A", 0.85, { p: "tiles", scale: 800 }), lm("Site", "Water", "3E6F8C", 0.05, { t: 0.35 }),
];
function libraryItems(extra: Mat[]): LibMat[] {
  const out = [...LIBRARY];
  for (const m of extra) if (!out.some((x) => x.material.name === m.name)) out.push({ category: "Finishes", material: m, pattern: "none" });
  return out;
}

const patternCache = new Map<string, HTMLCanvasElement | null>();
function patternFor(it: LibMat) {
  if (!patternCache.has(it.material.name)) patternCache.set(it.material.name, patternCanvas(it.pattern, it.material.color as RGB, hexOf(it.material).slice(1)));
  return patternCache.get(it.material.name)!;
}
/** The material to add (with its pattern texture written to the Materials folder, MaterialLibrary.resolved). */
async function resolved(it: LibMat): Promise<Mat> {
  const m: Mat = JSON.parse(JSON.stringify(it.material));
  const cv = it.pattern !== "none" ? patternFor(it) : null;
  if (cv) {
    const p = N.join((await N.paths()).materials, it.material.name.replace(/\//g, "-") + ".png");
    const url = cv.toDataURL("image/png");
    if (await N.writeBase64(p, url.slice(url.indexOf(",") + 1))) m.texture = p;
  }
  return m;
}

export function showMaterialLibrary(app: App) {
  ToolWindow.show("materialLibrary", "Material Library", { w: 760, h: 560, minW: 640, minH: 440 }, (w) => { new MaterialLibraryView(app, w.body); });
}

let matLibView: MaterialLibraryView | null = null;
let matLibHooked = false;

class MaterialLibraryView {
  private category = "All";
  private query = "";
  private selected: string | null = null;
  private status = "";
  private data: MatList | null = null;
  private cats = h("div", { class: "pb-cats" });
  private grid = h("div", { class: "pb-grid", style: { gridTemplateColumns: "repeat(auto-fill, minmax(104px, 1fr))", gap: "12px", padding: "12px" } });
  private count = h("span", { class: "pb-small pb-dim" });
  private foot = h("div", { class: "pb-row", style: { padding: "10px", gap: "8px" } });
  private thumbs = new Map<string, HTMLCanvasElement>();
  constructor(private app: App, host: HTMLElement) {
    const search = field({ placeholder: "Search materials", width: 260, onInput: (v) => { this.query = v; this.render(); } });
    const right = h("div", { class: "pb-col", style: { flex: "1", gap: "0", minWidth: "0" } },
      h("div", { class: "pb-row", style: { padding: "10px" } }, search, spacer(), this.count), h("div", { class: "pb-hsep" }),
      h("div", { class: "pb-scroll", style: { flex: "1", background: "var(--panel)" } }, this.grid), h("div", { class: "pb-hsep" }), this.foot);
    host.append(h("div", { style: { display: "flex", flex: "1", minHeight: "0" } }, this.cats, right));
    this.load();
    matLibView = this;
    if (!matLibHooked) { matLibHooked = true; app.on(["doc", "selection"], () => { if (ToolWindow.isOpen("materialLibrary")) void matLibView?.load(); }); }
  }
  async load() { this.data = await list(this.app); this.render(); }
  private entries(): LibMat[] {
    const d = this.data;
    let l: LibMat[] = this.category === "In Drawing" ? (d?.materials ?? []).map((r) => ({ category: "In Drawing", material: r.material, pattern: "none" as Pattern }))
      : libraryItems(d?.library ?? []).filter((x) => this.category === "All" || x.category === this.category);
    const q = this.query.trim().toLowerCase();
    if (q) l = l.filter((x) => x.material.name.toLowerCase().includes(q) || x.category.toLowerCase().includes(q));
    return l;
  }
  private inDoc(name: string) { return (this.data?.materials ?? []).find((r) => r.material.name.toLowerCase() === name.toLowerCase())?.material ?? null; }
  private render() {
    clear(this.cats);
    for (const c of CATEGORIES) {
      const b = h("button", { class: c === this.category ? "sel" : "", text: c });
      b.addEventListener("click", () => { this.category = c; this.render(); });
      this.cats.append(b);
    }
    const entries = this.entries();
    this.count.textContent = `${entries.length} materials`;
    clear(this.grid);
    for (const e of entries) this.grid.append(this.tile(e));
    const sel = entries.find((e) => e.material.name === this.selected) ?? null;
    clear(this.foot);
    this.foot.append(this.status ? h("span", { class: "pb-status", text: this.status }) : h("span"), spacer(),
      button("Add to Drawing", { disabled: !sel, onClick: () => sel && this.add(sel) }),
      button("Assign to Selection", { prominent: true, disabled: !sel || !this.app.selection.ids.length, help: "Assign the material to the selected building elements", onClick: () => sel && this.assign(sel) }));
  }
  private tile(e: LibMat): HTMLElement {
    const inDoc = this.inDoc(e.material.name);
    const mat = this.category === "In Drawing" ? e.material : inDoc ?? e.material;
    const key = `${e.material.name}|${JSON.stringify(mat.color)}|${mat.roughness}|${mat.metalness}|${mat.transparency}`;
    let cv = this.thumbs.get(key);
    if (!cv) { cv = sphereThumbnail(mat as any, this.category === "In Drawing" || inDoc ? null : patternFor(e)); this.thumbs.set(key, cv); }
    const el = h("div", { class: "pb-mtile" + (this.selected === e.material.name ? " sel" : ""), draggable: "true", "data-material": e.material.name }, cv,
      h("div", { class: "n", text: e.material.name }), h("div", { class: "s" + (inDoc ? " pb-accent" : ""), style: inDoc ? { color: "var(--accent)" } : {}, text: inDoc ? "In drawing" : e.category }));
    const m = e.material;
    help(el, `${m.name} — roughness ${fmt(m.roughness)}, metalness ${fmt(m.metalness)}${m.transparency > 0 ? `, transparency ${fmt(m.transparency)}` : ""}\nDouble-click: assign to the selection (or add to the drawing)`);
    el.addEventListener("click", () => { this.selected = e.material.name; this.render(); });
    el.addEventListener("dblclick", () => { this.selected = e.material.name; if (this.app.selection.ids.length) this.assign(e); else this.add(e); });
    el.addEventListener("dragstart", (ev) => ev.dataTransfer?.setData("text/plain", "archi-material:" + e.material.name));
    return el;
  }
  private async add(e: LibMat) {
    const m = await resolved(e);
    const r = await edit(this.app, "Add Material", [{ op: "addMaterial", material: m }]);
    this.status = (r?.messages ?? [])[0] ?? "";
    await this.load();
  }
  private async assign(e: LibMat) {
    const ids = this.app.selection.ids.map(Number);
    if (!ids.length) return;
    const ops: any[] = [];
    if (!this.inDoc(e.material.name)) ops.push({ op: "addMaterial", material: await resolved(e) });
    ops.push({ op: "assignMaterial", name: e.material.name, ids });
    const r = await this.app.tryCall("doc.edit", { label: "Assign Material", ops });
    const msg = (r?.messages ?? []).find((x: string) => x.includes("assigned")) ?? "";
    const n = /assigned to (\d+)/.exec(msg)?.[1] ?? String(ids.length);
    this.status = `${e.material.name} assigned to ${n} element(s).`;
    await this.app.refresh(["document"]);
    await this.load();
  }
}

// ---- Procedural material (PROCMATERIAL) and material from a photo ----

export function showProceduralMaterial(app: App) {
  let p = procDefaults("Brick");
  let name = "Procedural Brick";
  const sheet = new Sheet(560);
  const preview = h("canvas", { style: { width: "220px", height: "220px", borderRadius: "6px", background: "#111" } }) as HTMLCanvasElement;
  const form = h("div", { class: "pb-col", style: { gap: "6px", flex: "1" } });
  const status = h("div", { class: "pb-small pb-dim" });
  const toHex = (c: RGB) => rgbaToHex(c).toUpperCase();
  let timer = 0;
  const repaint = () => {
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      const maps = generate({ ...p, pixels: 128 });
      preview.width = maps.size; preview.height = maps.size;
      const g = preview.getContext("2d")!; const img = g.createImageData(maps.size, maps.size); img.data.set(maps.albedo); g.putImageData(img, 0, 0);
    }, 60);
  };
  const render = () => {
    clear(form);
    const row = (label: string, ...k: (Node | null)[]) => h("div", { class: "pb-row" }, h("span", { class: "pb-label", style: { width: "120px" }, text: label }), ...k);
    form.append(
      row("Pattern", picker(PROC_KINDS, p.kind, (v) => { p = procDefaults(v as ProcKind); if (/^Procedural /.test(name)) name = "Procedural " + v; render(); repaint(); }, 140)),
      row("Material name", field({ value: name, flex: true, onInput: (v) => { name = v; } })),
      row("Main colour", colorWell(toHex(p.color1), (hx) => { p.color1 = hexToRgba(hx); repaint(); })),
      row("Second colour / joints", colorWell(toHex(p.color2), (hx) => { p.color2 = hexToRgba(hx); repaint(); })),
      row("Tile size (mm)", numberField(p.tileSize, (v) => { p.tileSize = Math.max(10, v); }, { width: 80 })),
      ["Brick", "Tile", "Stone", "Wood"].includes(p.kind) ? row("Rows / courses per tile", numberField(p.rows, (v) => { p.rows = Math.max(1, Math.min(64, Math.round(v))); repaint(); }, { width: 60 })) : "",
      ["Brick", "Tile", "Stone"].includes(p.kind) ? row("Columns per tile", numberField(p.columns, (v) => { p.columns = Math.max(1, Math.min(64, Math.round(v))); repaint(); }, { width: 60 })) : "",
      ["Brick", "Tile", "Stone", "Wood"].includes(p.kind) ? row("Joint width (fraction)", numberField(p.joint, (v) => { p.joint = Math.max(0, Math.min(0.2, v)); repaint(); }, { width: 70 })) : "",
      row("Variation", numberField(p.variation, (v) => { p.variation = Math.max(0, Math.min(1, v)); repaint(); }, { width: 70 })),
      row("Seed", numberField(p.seed, (v) => { p.seed = Math.max(0, Math.round(v)); repaint(); }, { width: 70 })));
  };
  render(); repaint();
  sheet.body.append(h("div", { class: "pb-sheet-head", text: "Procedural Material" }),
    h("div", { class: "pb-row", style: { padding: "0 14px 10px", alignItems: "flex-start", gap: "14px" } }, form, preview),
    h("div", { style: { padding: "0 14px" } }, status),
    h("div", { class: "pb-sheet-foot" }, button("Cancel", { onClick: () => sheet.close() }), button("Create", { prominent: true, onClick: async () => {
      status.textContent = "Generating…";
      await new Promise((r) => setTimeout(r, 30));
      const nm = name.trim() || "Procedural " + p.kind;
      const r = await createProcedural(app, p, nm);
      if (r) { sheet.close(); app.print(`Procedural material ${nm} (${p.kind}, ${p.pixels} px, tile ${fmt(p.tileSize, 0)} mm).`); } else status.textContent = "The textures could not be written (Windows app only).";
    } })));
}

/** ProceduralMaterial.create: writes albedo, normal and roughness PNGs and adds or updates the material with its maps. */
export async function createProcedural(app: App, p: ReturnType<typeof procDefaults>, name: string): Promise<boolean> {
  const maps = generate(p);
  const folder = N.join((await N.paths()).materials, "Procedural");
  const safe = name.replace(/\//g, "-");
  const a = N.join(folder, safe + "_albedo.png"), nm = N.join(folder, safe + "_normal.png"), r = N.join(folder, safe + "_roughness.png");
  if (!(await N.writeBase64(a, pngBase64(maps.albedo, maps.size, maps.size)))) return false;
  await N.writeBase64(nm, pngBase64(normals(maps.height, maps.size, maps.size, 3), maps.size, maps.size));
  await N.writeBase64(r, pngBase64(gray(Array.from(maps.roughness, (x) => x / 2)), maps.size, maps.size));
  let meanR = 0; for (const x of maps.roughness) meanR += x; meanR /= Math.max(maps.roughness.length, 1);
  const data = await list(app);
  const cur = data.materials.find((x) => x.material.name.toLowerCase() === name.toLowerCase());
  const m: Mat = cur ? { ...cur.material } : { name, color: { r: 1, g: 1, b: 1, a: 1 }, roughness: 0.8, metalness: 0, transparency: 0, textureScale: 1000, cutPattern: "SOLID" };
  m.color = { r: 1, g: 1, b: 1, a: 1 }; m.texture = a; m.textureScale = Math.max(1, p.tileSize); m.roughness = Math.min(1, Math.max(0.02, meanR));
  if (p.kind === "Brick") m.cutPattern = "ANSI31"; else if (p.kind === "Concrete") m.cutPattern = "AR-CONC"; else if (p.kind === "Wood") m.cutPattern = "ANSI32";
  const mm = { ...(parseJSON(cur?.maps) ?? {}), normal: nm, roughness: r };
  const params = { kind: p.kind, color1: p.color1, color2: p.color2, tileSize: p.tileSize, rows: p.rows, columns: p.columns, joint: p.joint, variation: p.variation, seed: p.seed, pixels: p.pixels };
  await app.tryCall("doc.edit", { label: "PROCMATERIAL", ops: [
    { op: "setMaterial", name: cur?.material.name ?? name, material: m },
    { op: "setVariable", name: "MATMAPS:" + name.toUpperCase(), value: sortedJSON({ normalStrength: 1, displacementScale: 0, ...mm }) },
    { op: "setVariable", name: "MATPROC:" + name.toUpperCase(), value: JSON.stringify(params) },
  ] });
  await app.refresh(["document"]);
  return true;
}

/** From Photo… (PhotoMaterial.create): a tileable PBR material from a photo of a surface. */
export async function materialFromPhoto(app: App, opts: { path?: string; name?: string; tileSize?: number } = {}) {
  const path = opts.path ?? await chooseImage(app, "Choose a photo of the surface");
  if (!path) return;
  const tile = Math.max(10, opts.tileSize ?? 1000);
  const url = N.fileUrl(app, path);
  if (!url) { app.print("Material from photo needs the Windows app."); return; }
  const img = new Image();
  img.src = url;
  try { await img.decode(); } catch { app.print(`Material from photo failed: Could not read the image ${N.basename(path)}.`); return; }
  const s = Math.min(1, 1024 / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.max(1, Math.round(img.naturalWidth * s)), hh = Math.max(1, Math.round(img.naturalHeight * s));
  const c = document.createElement("canvas"); c.width = w; c.height = hh;
  const g = c.getContext("2d")!; g.drawImage(img, 0, 0, w, hh);
  const r = derivePhoto(g.getImageData(0, 0, w, hh).data, w, hh);
  const name = opts.name ?? N.stem(path).replace(/\b\w/g, (x) => x.toUpperCase());
  const folder = N.join((await N.paths()).materials, "Photo");
  const safe = name.replace(/\//g, "-");
  const a = N.join(folder, safe + "_albedo.png"), nm = N.join(folder, safe + "_normal.png"), ro = N.join(folder, safe + "_roughness.png"), ao = N.join(folder, safe + "_ao.png");
  await N.writeBase64(a, pngBase64(r.albedo, w, hh));
  await N.writeBase64(nm, pngBase64(r.normal, w, hh));
  await N.writeBase64(ro, pngBase64(gray(Array.from(r.roughness, (x) => x / 2)), w, hh));
  await N.writeBase64(ao, pngBase64(gray(r.ao), w, hh));
  const data = await list(app);
  const cur = data.materials.find((x) => x.material.name.toLowerCase() === name.toLowerCase());
  const m: Mat = cur ? { ...cur.material } : { name, color: { r: 1, g: 1, b: 1, a: 1 }, roughness: 0.8, metalness: 0, transparency: 0, textureScale: 1000, cutPattern: "SOLID" };
  m.color = { r: 1, g: 1, b: 1, a: 1 }; m.texture = a; m.textureScale = tile; m.roughness = r.meanRoughness;
  const mm = { ...(parseJSON(cur?.maps) ?? {}), normal: nm, roughness: ro, ao };
  const asset = { useRenderAppearance: true, description: "", manufacturer: "", model: "", mark: "", keynote: "", url: "", ...(parseJSON(cur?.assets) ?? {}) };
  asset.shadingColor = rgbaToHex(r.meanColor).toUpperCase();
  if (!asset.description) asset.description = "From photo " + N.basename(path);
  await app.tryCall("doc.edit", { label: "Material from Photo", ops: [
    { op: "setMaterial", name: cur?.material.name ?? name, material: m },
    { op: "setVariable", name: "MATMAPS:" + name.toUpperCase(), value: sortedJSON({ normalStrength: 1, displacementScale: 0, ...mm }) },
    { op: "setVariable", name: "MATASSET:" + name.toUpperCase(), value: sortedJSON(asset) },
  ] });
  await app.refresh(["document"]);
  // MATFROMIMAGE's message (the Materials panel button prints the same).
  app.print(`Material ${name} from ${N.basename(path)}: roughness ${r.meanRoughness.toFixed(2)}, tile ${Math.round(tile)} mm, normal/roughness/AO maps.`);
}

/** PROCMATERIAL / MATFROMIMAGE from the command line: the engine's `host` action {"action":"materials","op":…}. */
export function materialsHost(app: App, p: any): boolean {
  if (p?.action !== "materials") return false;
  if (p.op === "procedural") {
    const q = p.params ?? {};
    const d = procDefaults((q.kind ?? "Brick") as ProcKind);
    const col = (hex: string | undefined, def: RGB): RGB => {
      const m = /^#?([0-9a-f]{6})$/i.exec(hex ?? "");
      if (!m) return def;
      const v = parseInt(m[1], 16);
      return { r: ((v >> 16) & 255) / 255, g: ((v >> 8) & 255) / 255, b: (v & 255) / 255 };
    };
    const params = { ...d, color1: col(q.color1, d.color1), color2: col(q.color2, d.color2), tileSize: Number(q.tileSize ?? d.tileSize),
      rows: Number(q.rows ?? d.rows), columns: Number(q.columns ?? d.columns), joint: Number(q.joint ?? d.joint), seed: Number(q.seed ?? 1) };
    void createProcedural(app, params, String(p.name ?? "Procedural " + params.kind)).then((ok) => { if (!ok) app.print("The textures could not be written (Windows app only)."); });
    return true;
  }
  if (p.op === "fromImage") {
    void materialFromPhoto(app, { path: String(p.path), name: p.name ? String(p.name) : undefined, tileSize: Number(p.tileSize ?? 1000) });
    return true;
  }
  return false;
}

export { header };
