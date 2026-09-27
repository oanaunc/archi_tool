// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Drawing templates (TemplateLibrary in ArchiApp/AppFeatures.swift): the built-in templates, the .archi /
// .architemplate files of the templates folder and recently used template files; a template opens as a new untitled
// drawing in this window when it is empty, otherwise in a new window (NEWFROMTEMPLATE, File ▸ New from Template,
// the start screen gallery, Open Template…).
import type { MenuItem } from "../ui/menu";
import { prefs } from "../prefs";
import { app, templatesFolder, reveal } from "./context";

export interface DrawingTemplate { id: string; name: string; subtitle: string; symbol: string; recent?: boolean }

/** Built-in templates when the engine is not reachable (same list as TemplateLibrary.builtIn). */
export const BUILTIN_TEMPLATES: DrawingTemplate[] = [
  { id: "builtin:metric", name: "Metric", subtitle: "Millimetres, standard layers", symbol: "square.and.pencil" },
  { id: "builtin:metricArchitectural", name: "Metric Architectural", subtitle: "AIA-style layers, 1:20–1:200 dimension styles", symbol: "ruler" },
  { id: "builtin:imperial", name: "Imperial", subtitle: "Inches, architectural dimensions", symbol: "ruler.fill" },
  { id: "builtin:building", name: "Building", subtitle: "Levels, structural grid and sheets", symbol: "building.2" },
];

export async function listTemplates(): Promise<DrawingTemplate[]> {
  const r = await app().tryCall("templates.list", { folder: await templatesFolder(), recent: prefs.get("recentTemplates") });
  return r?.templates ?? BUILTIN_TEMPLATES;
}

function isEmptyDrawing(): boolean {
  const i = app().info;
  return !i || (!i.dirty && !(i.entities ?? 0) && !(i.elements ?? 0));
}

/** TemplateLibrary.apply (or a new window when this drawing has content, as NEWFROMTEMPLATE does). */
export async function newFromTemplate(id: string, forceHere = false) {
  const a = app();
  if (!id.startsWith("builtin:")) prefs.noteTemplateUsed(id);
  if (!forceHere && !a.showStart && !isEmptyDrawing() && a.engine.native) { await a.engine.native.newWindow({ kind: "template", path: id }); return; }
  switch (id) {
    case "builtin:metric": return a.newDocument("metric");
    case "builtin:imperial": return a.newDocument("imperial");
    case "builtin:building": return a.newDocument("building");
  }
  // Metric Architectural and template files: a blank drawing with the Settings defaults, then the template's content.
  await a.newDocument("metric");
  const info = await a.tryCall("templates.new", { id });
  if (!info) return;
  await a.tryCall("drafting.defaults", { draft: prefs.get("draft") });
  a.info = info;
  a.closeStart();
  await a.refresh(["all"]);
  a.canvas?.zoomExtents();
}

/** Start screen / File ▸ Open Template…: any .architemplate (or .archi) file. */
export async function openTemplateFile() {
  const n = app().engine.native;
  if (!n) { app().print("Open Template needs the Windows app (file dialog)."); return; }
  const p = await n.openFileDialog({ title: "Choose a template (.architemplate) to start a new drawing from", filters: [{ name: "Templates", extensions: ["architemplate", "archi"] }] });
  if (p) await newFromTemplate(p, true);
}

export async function revealTemplatesFolder() { await reveal(await templatesFolder()); }

/** File ▸ New from Template submenu (Metric / Imperial / Building, the folder's templates, Save…, folder, sample). */
export async function templateMenu(): Promise<MenuItem[]> {
  const a = app();
  const list = (await listTemplates()).filter((t) => !t.id.startsWith("builtin:"));
  const nw = (req: { kind: string; path?: string }) => () => { if (a.engine.native) void a.engine.native.newWindow(req); else if (req.kind === "new") void a.newDocument(req.path); else void a.openSample("Cedar House"); };
  return [
    { title: "Metric Drawing (mm)", action: nw({ kind: "new", path: "metric" }) },
    { title: "Imperial Drawing (in)", action: nw({ kind: "new", path: "imperial" }) },
    { title: "Building (levels, grid, sheets)", action: nw({ kind: "new", path: "building" }) },
    ...(list.length ? [{ separator: true } as MenuItem, ...list.map((t) => ({ title: t.name, action: () => { if (a.engine.native) void a.engine.native.newWindow({ kind: "template", path: t.id }); else void newFromTemplate(t.id, true); } }))] : []),
    { separator: true },
    { title: "Save Drawing as Template…", action: () => void a.runCommand("SAVEASTEMPLATE") },
    { title: "Show Templates Folder", action: () => void revealTemplatesFolder() },
    { separator: true },
    { title: "Sample House", action: nw({ kind: "sample" }) },
  ];
}
