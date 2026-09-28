// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of sheets/ (contextual ribbon tabs, sheet commands, recovery, versions): a small simulation so the
// strip, the start screen's RECOVERED DOCUMENTS, the Versions window and the host actions can be exercised in the browser
// test page. The tabs come from the Mac catalogue (docs/windows-parity.json contextualTabs). Never used in the Electron app.
import ui from "../data/ui.generated.json";

export const SHEET_COMMANDS: { name: string; aliases: string[]; category: string; summary: string; modifies: boolean }[] = [
  { name: "MVIEWPOLY", aliases: ["MVPOLY", "POLYVIEWPORT"], category: "View", summary: "Creates a polygonal sheet viewport from paper points (x,y in mm) showing the current level.", modifies: true },
  { name: "MVSETUP", aliases: [], category: "View", summary: "Aligns sheet viewports: pans one viewport so a model point lines up horizontally or vertically with a point in another.", modifies: true },
  { name: "SHEETGRID", aliases: ["LAYOUTGRID", "GUIDEGRID"], category: "Output", summary: "Guide grid on the current sheet (spacing in paper mm, 0 = off); viewports snap to it when moved.", modifies: true },
  { name: "SHEETPLACEHOLDER", aliases: ["PLACEHOLDERSHEET"], category: "Output", summary: "Adds a placeholder sheet (listed in the sheet set and index, never plotted) or toggles the current one.", modifies: true },
  { name: "SHEETFIELD", aliases: ["PROJECTFIELD", "CUSTOMFIELD"], category: "Output", summary: "Custom title block fields: Project fields appear on every sheet, Sheet fields override them on one sheet.", modifies: true },
  { name: "PSETUPIN", aliases: [], category: "Output", summary: "Imports a page setup (plot style, colour mode, lineweights, stamp, paper) from another drawing into the current sheet or all sheets.", modifies: true },
  { name: "LAYOUTTABS", aliases: ["LAYOUTTAB", "MODELTAB"], category: "View", summary: "Shows or hides the Model / layout tabs under the drawing area.", modifies: false },
  { name: "SHEETRENUMBER", aliases: ["RENUMBERSHEETS"], category: "Output", summary: "Numbers all sheets in order with a prefix and start number (e.g. A- 101).", modifies: true },
  { name: "SHEETVIEWTITLES", aliases: ["VPTITLES", "EDITABLEVIEWTITLES"], category: "Output", summary: "Editable view titles (number bubble, title, scale) under every viewport of the active sheet; keeps edited titles.", modifies: true },
  { name: "SHEETIMAGE", aliases: ["LAYOUTIMAGE", "SHEETPNG"], category: "Output", summary: "Exports a sheet (layout) or the Model view of the current level as a PNG, JPEG or TIFF image at a chosen resolution (dpi).", modifies: false },
  { name: "TITLEBLOCKDESIGN", aliases: ["TBDESIGN", "CUSTOMTITLEBLOCK", "TITLEBLOCKBLOCK"], category: "Output", summary: "Custom title blocks: Create a starter block (edit it with BEDIT: lines, logo images, {field} texts or attributes), Use a block on all or the current sheet, or go back to the Builtin one.", modifies: true },
  { name: "ZOOMXP", aliases: ["ZXP", "ZOOMPAPER", "ZOOMSCALEXP"], category: "View", summary: "ZOOM nXP: in a sheet sets the selected viewport to 1:n (1/100XP); on the plan shows the drawing at that paper scale at true size on the screen.", modifies: false },
  { name: "DRAWINGRECOVERY", aliases: ["DRM"], category: "File", summary: "Shows documents recovered from autosave after a crash.", modifies: false },
  { name: "FILEVERSIONS", aliases: ["BROWSEVERSIONS", "MACVERSIONS", "REVERTTO"], category: "File", summary: "Versions of the saved file (every save keeps one): Browse window, List, Restore a version, Open a copy, Save a version now, Keep count.", modifies: false },
];

const CATEGORY: Record<string, string> = { wall: "Wall", door: "Door", window: "Window", space: "Room", slab: "Floor", roof: "Roof", stair: "Stair", opening: "Door", component: "Block Reference" };
const TABS = ((ui as any).contextualTabs ?? []) as { selection: string; tab: string; items: { title: string; symbol: string; command: string; names?: string[] }[] }[];

let types: Map<string, string> | null = null;
async function loadTypes(fe: any) {
  if (types) return types;
  types = new Map();
  const rec = await fe.fetchJSON("doc-schedules.json");
  const all = (Array.isArray(rec) ? rec : []).find((x: any) => x.request?.params?.kind === "all");
  for (const r of (all?.response?.result?.rows ?? []).slice(1)) types.set(String(r[0]), String(r[1]));
  return types;
}
function kindOf(fe: any, id: string): string {
  const t = types?.get(String(id));
  if (t) return CATEGORY[t] ?? "Element";
  const e = (fe.raw as any[]).find((x) => String(x.id) === String(id));
  const items: any[] = e?.items ?? [];
  if (items.some((i) => i.type === "text") && !items.some((i) => i.type === "stroke" && !i.closed)) return "Text";
  if (items.some((i) => i.type === "fill") && !items.some((i) => i.type === "stroke")) return "Hatch";
  return "Geometry";
}
async function contextTab(fe: any, ids: string[]) {
  await loadTypes(fe);
  if (!ids.length) return null;
  const kinds = new Set(ids.map((id) => kindOf(fe, id)));
  if (kinds.size !== 1) return null;
  const k = [...kinds][0];
  const def = TABS.find((t) => t.selection === k) ?? TABS.find((t) => t.selection === "(other)");
  if (!def) return null;
  const known = new Set<string>();
  for (const c of fe.hello?.commands ?? []) { known.add(String(c.name).toUpperCase()); for (const a of c.aliases ?? []) known.add(String(a).toUpperCase()); }
  const items = def.items.map((i) => ({ ...i, command: (i.names ?? [i.command]).find((n) => known.has(n.toUpperCase())) ?? "" })).filter((i) => i.command);
  return { title: def.selection === "(other)" ? `Modify ${k}` : def.tab, category: k, items };
}

const state = {
  recovered: null as any[] | null,
  versions: null as any[] | null,
  keep: 50,
};
function recovered(): any[] {
  if (!state.recovered) state.recovered = ((globalThis as any).__archiFakeRecovered ?? []).map((x: any) => ({ ...x }));
  return state.recovered!;
}
function versions(fe: any): any[] {
  if (!state.versions) {
    const now = Date.now();
    state.versions = [0, 1].map((i) => {
      const d = new Date(now - (i + 1) * 3600_000);
      return { date: d.toISOString(), label: `${d.toLocaleDateString(undefined, { dateStyle: "medium" })} at ${d.toLocaleTimeString()} — DESKTOP-ARCHI` };
    });
  }
  void fe;
  return state.versions!;
}
const IDLE = { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };

export function fakeSheetsCall(fe: any, method: string, p: any): any {
  const host = (params: any) => fe.emit("host", params);
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of SHEET_COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c });
      return undefined;
    }
    case "ribbon.context": return contextTab(fe, (p.ids ?? [...fe.selection]).map(String)).then((tab) => ({ tab, count: fe.selection.size }));
    case "recovery.setup": return { id: "fake-session", folder: p.folder ?? null, versionsFolder: p.versionsFolder ?? null, keep: (state.keep = p.keep ?? state.keep) };
    case "recovery.autosave": return { written: false };
    case "recovery.discard": return {};
    case "recovery.list": return { items: recovered(), folder: "%APPDATA%\\Oanarina Archi Tool\\Recovery" };
    case "recovery.remove": state.recovered = recovered().filter((r) => r.id !== p.id); return { items: recovered() };
    case "recovery.restore": {
      const r = recovered().find((x) => x.id === p.id);
      if (!r) throw { code: -32602, message: `no recovered document '${p.id}'` };
      state.recovered = recovered().filter((x) => x.id !== p.id);
      fe.openFixture(r.originalPath ?? "Cedar House.archi");
      fe.info.path = null; fe.info.title = "Untitled"; fe.info.dirty = true;
      fe.log(`Recovered “${r.name}” from the autosave of ${r.dateText}. Save it to keep the changes.`);
      fe.changed("document", "selection");
      return { doc: fe.info, originalPath: r.originalPath ?? null };
    }
    case "versions.list": {
      if (!fe.info?.path) throw { code: -32000, message: "Save the drawing as an .archi file first." };
      const path = String(fe.info.path);
      return { path, name: path.split(/[\\/]/).pop(), keep: state.keep, versions: versions(fe).map((v, i) => ({ index: i, label: v.label, date: v.date })) };
    }
    case "versions.save": {
      const d = new Date();
      versions(fe).unshift({ date: d.toISOString(), label: `${d.toLocaleDateString(undefined, { dateStyle: "medium" })} at ${d.toLocaleTimeString()} — DESKTOP-ARCHI` });
      while (state.versions!.length > state.keep) state.versions!.pop();
      return { ok: true, message: "Version saved.", count: state.versions!.length };
    }
    case "versions.open": return { path: `C:\\Users\\oana\\AppData\\Local\\Temp\\ArchiVersions\\version ${p.index}.archi`, label: versions(fe)[p.index]?.label };
    case "versions.restore": {
      const v = versions(fe)[p.index];
      if (!v) throw { code: -32602, message: `no version ${p.index}` };
      const d = new Date();
      versions(fe).unshift({ date: d.toISOString(), label: `${d.toLocaleDateString(undefined, { dateStyle: "medium" })} at ${d.toLocaleTimeString()} — DESKTOP-ARCHI` });
      fe.log(`Restored the version of ${v.label}; the previous file is kept as a version.`);
      fe.info.dirty = false; fe.changed("document");
      return fe.info;
    }
    case "sheet.image": {
      const title = typeof p.layout === "number" ? fe.info?.layouts?.[p.layout] ?? "Sheet" : "Model";
      const w = Math.round(420 * Number(p.dpi ?? 150) / 25.4), h = Math.round(297 * Number(p.dpi ?? 150) / 25.4);
      if (p.path && String(p.format ?? "png") !== "jpeg") { fe.log(`Saved ${title} at ${p.dpi ?? 150} dpi (${w}×${h} px) to ${p.path}.`); return { path: p.path, width: w, height: h, bytes: w * h, title }; }
      return { png: "assets/app-icon.png", width: w, height: h, bytes: w * h, title, dpi: p.dpi ?? 150 };
    }
    case "command.run": {
      const toks = String(p.line ?? "").trim().split(/\s+/);
      const name = toks[0]?.toUpperCase() ?? "";
      const def = SHEET_COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (!def) return undefined;
      fe.log(`Command: ${name}`);
      const arg = (toks[1] ?? "").toUpperCase();
      switch (def.name) {
        case "LAYOUTTABS": host({ action: "layoutTabs", on: arg === "ON" ? true : arg === "OFF" ? false : null }); break;
        case "ZOOMXP": {
          const s = (toks[1] ?? "1/100XP").toLowerCase().replace(/xp?$/, "");
          const m = s.match(/^([\d.]+)\s*[:/]\s*([\d.]+)$/);
          const f = m ? Number(m[1]) / Number(m[2]) : Number(s);
          if (!(f > 0)) { fe.log("Enter a scale such as 1/100XP, 0.01XP or 1:100."); break; }
          host({ action: "paperZoom", factor: f, ratio: 1 / f, ratioText: String(Math.round(100 / f) / 100), pixelsPerUnit: (96 / 25.4) * f, viewportScale: 1 / f });
          break;
        }
        case "DRAWINGRECOVERY": {
          const list = recovered();
          if (!list.length) { fe.log("No recovered documents."); break; }
          list.forEach((r, i) => fe.log(`  ${i + 1}. ${r.name} — ${r.dateText}`));
          host({ action: "startScreen" });
          break;
        }
        case "FILEVERSIONS":
          if (!fe.info?.path) { fe.log("Save the drawing as an .archi file first."); break; }
          if (!arg || arg === "BROWSE") host({ action: "dialog", dialog: "versions", path: fe.info.path });
          else if (arg === "LIST") versions(fe).forEach((v, i) => fe.log(`  ${i + 1}. ${v.label}`));
          break;
        case "SHEETIMAGE": host({ action: "sheetImage", layout: "Model", dpi: 150, format: "png", path: null, suggested: `${fe.info?.title ?? "Drawing"}.png` }); break;
        case "PSETUPIN": host({ action: "chooseFile", purpose: "PSETUPIN", title: "Import Page Setup", extensions: ["archi"] }); break;
        default: fe.log(`${def.name} runs in archi-engine.`);
      }
      return IDLE;
    }
  }
  return undefined;
}
