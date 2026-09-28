// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Wires a View3D to the archi-engine session: model.meshes (one binary buffer file when the shell can read files),
// render.settings and view3d.info on load and on "changed" notifications, selection both ways, the `host` actions of
// 3D commands (setViewStyle, setView, walkthrough, render and the {"action":"view3d"} tools: gizmo, measure, levels,
// cameras, navigation, animation, panoramas, view images), section caps, gizmo commits and RENDERSAVE.

import type { View3D, View3DInfo } from "./view3d";
import type { SavedCamera, MaterialMaps, MeshesResult } from "./scene";
import type { CameraState } from "./camera";
import type { GizmoMode } from "./effects";
import { parseSectionBox, parseSectionPlane, formatSectionBox, formatSectionPlane } from "./variables";
import { presetNamed, PRESET_KEYWORDS, styleNamed } from "./look";
import { UNIT } from "./renderer";
import { fmt } from "./effects";

export interface EngineLike {
  call(method: string, params?: unknown): Promise<any>;
  onNotify(cb: (n: { method: string; params: any }) => void): void;
}

export interface BridgeOptions {
  /** Level of detail of model.meshes (0 = full; the Cedar House trees are ~1.1 M triangles at 0). */
  lod?: number;
  /** Buffer file for model.meshes; default a temporary file chosen by the engine when `readBinary` is given. */
  binaryPath?: string;
  /** Reads the engine's buffer file (model.meshes {"binary": …}); without it the buffers come as base64. */
  readBinary?: (path: string) => Promise<ArrayBuffer>;
  /** Saves a rendered PNG (RENDERSAVE); returns the path written. */
  savePNG?: (path: string, png: Blob) => Promise<string>;
  /** Saves an image (panoramas, VIEWIMAGE, animation frames): `path` null = ask with a save dialog. Returns the path or null. */
  saveFile?: (path: string | null, data: Blob, suggested?: string) => Promise<string | null>;
  /** Save dialog for images when a command gave no file name; null = cancelled. */
  chooseSavePath?: (suggested: string) => Promise<string | null>;
  /** Asks for a camera name (Save Current Camera… sheet); null = cancelled. */
  askName?: (title: string, defaultName: string) => Promise<string | null>;
  /** Prints to the command line history. */
  print?: (text: string) => void;
  /** Live hint in the status bar (gizmo drags). */
  hint?: (text: string) => void;
  /** Grid snap step for gizmo moves (0 = off). */
  gridStep?: () => number;
}

/** Document data the 3D view needs beyond model.meshes (view3d.info). */
export interface View3DDocument extends View3DInfo {
  cameras?: SavedCamera[];
  materialMaps?: Record<string, MaterialMaps>;
  variables?: Record<string, string>;
  northAngle?: number;
  sectionBox?: { on: boolean; min: number[]; max: number[] } | null;
  sectionPlane?: { on: boolean; point: number[]; normal: number[] } | null;
  perspective?: boolean;
  visualStyle?: string;
  renderPreset?: string | null;
  gizmo?: string;
  measure?: boolean;
}

export class EngineBridge {
  private reloadTimer = 0;
  private loading: Promise<void> | null = null;
  /** Requests whose "changed" notification must not reload the meshes (3D view variables, camera saves). */
  private quiet = 0;
  private styleFromEngine = false;
  private subObjectMode = "Face";
  hasInfo = false;

  constructor(readonly view: View3D, readonly engine: EngineLike, readonly opts: BridgeOptions = {}) {
    engine.onNotify((n) => this.onNotify(n.method, n.params));
    if (typeof document !== "undefined") document.addEventListener("archi:host", (e) => this.host((e as CustomEvent).detail));
    const o = view.opts;
    const prevPick = o.onPick;
    o.onPick = (id, extend) => { prevPick?.(id, extend); this.pick(id, extend); };
    const prevBox = o.onSectionBox;
    o.onSectionBox = (b) => { prevBox?.(b); if (b) this.setVariable("SECTIONBOX", formatSectionBox(b)); };
    const prevPlane = o.onSectionPlane;
    o.onSectionPlane = (p) => { prevPlane?.(p); this.setVariable("SECTIONPLANE", p ? formatSectionPlane(p) : null).then(() => this.refreshCaps()); };
    const prevProj = o.onProjection;
    o.onProjection = (ortho) => { prevProj?.(ortho); this.setVariable("PERSPECTIVE", ortho ? "0" : "1"); };
    const prevStyle = o.onStyle;
    o.onStyle = (s) => { prevStyle?.(s); this.setVariable("VSCURRENT", s); };
    const prevCam = o.onCamera;
    o.onCamera = (c) => { prevCam?.(c); this.reportCamera(c); };
    const x = view.extras.host;
    x.onTransform = (t) => this.transform(t.op, t.axis, t.amount, t.pivot, t.ids);
    x.onVariable = (n, v) => { this.setVariable(n, v); };
    x.onSaveCamera = (c) => this.saveCamera(c);
    x.onDeleteCamera = (n) => { this.quietCall("view3d.deleteCamera", { name: n }).then((cams) => { if (Array.isArray(cams)) this.view.setCameras(cams); }).catch(() => {}); };
    x.print = (t) => this.opts.print?.(t);
    x.hint = (t) => this.opts.hint?.(t);
    x.gridStep = () => this.opts.gridStep?.() ?? 0;
    x.runCommand = (line) => { this.engine.call("command.run", { line }).catch((e) => this.opts.print?.(String(e?.message ?? e))); };
    x.subObjectMode = () => this.subObjectMode;
  }

  /** Loads the model, the lighting preset and the 3D document data. */
  load(): Promise<void> {
    if (this.loading) return this.loading;
    this.loading = (async () => {
      const binary = this.opts.binaryPath ?? (this.opts.readBinary ? true : undefined);
      const [meshes, settings] = await Promise.all([
        this.engine.call("model.meshes", { level: "all", lod: this.opts.lod ?? 0, ...(binary != null ? { binary } : {}) }) as Promise<MeshesResult>,
        this.engine.call("render.settings", {}).catch(() => null),
      ]);
      let bin: ArrayBuffer | undefined;
      if (meshes?.binary && this.opts.readBinary) bin = await this.opts.readBinary(meshes.binary);
      const doc = await this.documentData();
      this.applyDocument(doc, settings);
      this.view.setModel(meshes, bin);
      // Animations split doors after the meshes exist.
      if (doc.animations) this.view.setInfo({ animations: doc.animations });
      if (doc.perspective === false && !this.view.getCamera().ortho) this.view.toggleProjection();
      await this.refreshCaps();
      await this.syncSelection();
    })().finally(() => { this.loading = null; });
    return this.loading;
  }

  private applyDocument(doc: View3DDocument, settings: any) {
    if (doc.materialMaps) this.view.setMaterialMaps(doc.materialMaps);
    if (doc.cameras) this.view.setCameras(doc.cameras);
    if (typeof doc.northAngle === "number") this.view.setNorthAngle(doc.northAngle);
    const vars = doc.variables ?? {};
    if (vars.SUBOBJECTMODE) this.subObjectMode = vars.SUBOBJECTMODE;
    this.view.setSectionBox(doc.sectionBox !== undefined ? toBox(doc.sectionBox) : parseSectionBox(vars.SECTIONBOX));
    this.view.setSectionPlane(doc.sectionPlane !== undefined ? toPlane(doc.sectionPlane) : parseSectionPlane(vars.SECTIONPLANE));
    this.view.setInfo({
      levels: doc.levels, currentLevel: doc.currentLevel, weather: doc.weather ?? null, fog: doc.fog ?? null, water: doc.water,
      site: doc.site, unitMM: doc.unitMM,
      ...("ambientOcclusion" in doc ? { ambientOcclusion: doc.ambientOcclusion ?? null } : {}),
      ...(doc.billboards ? { billboards: doc.billboards } : {}),
      ...(doc.levelView && (doc.levelView.isolate != null || doc.levelView.explodeGap > 0) ? { levelView: doc.levelView } : {}),
    });
    if (doc.visualStyle && !this.styleFromEngine && this.hasInfo === false) { this.view.setStyle(doc.visualStyle); }
    const customStyle = (window as any).archiVisualStyleCustom;
    if (customStyle && this.hasInfo === false) this.view.setCustomStyle(customStyle);
    if (doc.gizmo) this.view.extras.setGizmo(doc.gizmo as GizmoMode);
    // A preset stored in the drawing (RENDERPRESET) turns on haze, meadow and the preset camera response.
    const explicit = doc.renderPreset !== undefined ? !!doc.renderPreset : vars.RENDERPRESET != null ? !!presetNamed(vars.RENDERPRESET) : true;
    this.view.setRenderSettings(settings, explicit);
    this.hasInfo = true;
  }

  /** view3d.info (saved cameras incl. Front / Aerial / Corner, section box and plane, projection, visual style, preset, maps …). */
  private async documentData(): Promise<View3DDocument> {
    try { return (await this.engine.call("view3d.info", {})) ?? {}; } catch { return {}; }
  }

  /** Refreshes the document data only (variables changed without geometry). */
  async refreshInfo() {
    const [doc, settings] = await Promise.all([this.documentData(), this.engine.call("render.settings", {}).catch(() => null)]);
    this.applyDocument(doc, settings);
    if (doc.animations) this.view.setInfo({ animations: doc.animations });
    await this.refreshCaps();
  }

  private async quietCall(method: string, params: unknown): Promise<any> {
    this.quiet++;
    try { return await this.engine.call(method, params); } finally { setTimeout(() => { this.quiet = Math.max(0, this.quiet - 1); }, 0); }
  }

  private async setVariable(name: string, value: string | null) {
    try { await this.quietCall("view3d.setVariable", { name, value }); } catch { /* older engines: kept in the view only */ }
  }

  private reportCamera(c: CameraState) {
    const mm = (v: number[]) => v.map((x) => x / UNIT);
    this.engine.call("view3d.setCamera", { eye: mm(c.eye), target: mm(c.target), fov: c.fov, orthographic: c.ortho }).catch(() => {});
  }

  private async saveCamera(c: CameraState) {
    const n = this.view.getCameras().length + 1;
    const name = this.opts.askName ? await this.opts.askName("Save Camera", `Camera ${n}`) : await this.view.extras.askCameraName(`Camera ${n}`);
    if (!name || !name.trim()) return;
    const mm = (v: number[]) => v.map((x) => x / UNIT);
    try {
      const cams = await this.quietCall("view3d.saveCamera", { name: name.trim(), eye: mm(c.eye), target: mm(c.target), fov: c.fov, orthographic: c.ortho });
      if (Array.isArray(cams)) this.view.setCameras(cams);
    } catch (e: any) { this.opts.print?.(String(e?.message ?? e)); }
  }

  /** Commits a gizmo drag (view3d.transform, one undo step); the "changed" notification reloads the meshes. */
  private async transform(op: string, axis: number, amount: number, pivot: [number, number], ids: string[]) {
    try {
      await this.engine.call("view3d.transform", { op, axis, amount, pivot, ids: ids.map((x) => (/^\d+$/.test(x) ? Number(x) : x)) });
    } catch (e: any) { this.opts.print?.(String(e?.message ?? e)); }
  }

  /** Cap faces of the section plane (view3d.sectionCaps). */
  async refreshCaps() {
    const pl = this.view.getSectionPlane?.();
    if (!pl?.on) { this.view.setSectionCaps(null); return; }
    try {
      const r = await this.engine.call("view3d.sectionCaps", { point: pl.point, normal: pl.normal });
      this.view.setSectionCaps(r?.positions ? decodeFloats(r.positions) : null, r?.normal);
    } catch { this.view.setSectionCaps(null); }
  }

  private onNotify(method: string, params: any) {
    if (method !== "changed") return;
    const what: string[] = params?.what ?? [];
    if (what.includes("document") || what.includes("model") || what.includes("materials")) {
      clearTimeout(this.reloadTimer);
      if (this.quiet > 0) { this.reloadTimer = setTimeout(() => this.refreshInfo(), 60) as unknown as number; return; }
      this.reloadTimer = setTimeout(() => this.load(), 120) as unknown as number;
    } else if (what.includes("selection")) this.syncSelection();
  }

  private async syncSelection() {
    try { const s = await this.engine.call("select.get", {}); this.view.setSelection(s?.ids ?? []); } catch { /* no selection API */ }
  }

  private async pick(id: string | null, extend: boolean) {
    let ids: string[] = [];
    if (extend) {
      const cur = new Set<string>(((await this.engine.call("select.get", {}).catch(() => null))?.ids ?? []).map(String));
      if (id) { if (cur.has(id)) cur.delete(id); else cur.add(id); }
      ids = [...cur];
    } else if (id) ids = [id];
    const r = await this.engine.call("select.set", { ids: ids.map((x) => (/^\d+$/.test(x) ? Number(x) : x)) }).catch(() => null);
    this.view.setSelection(r?.ids ?? ids);
  }

  /** `host` notifications of 3D commands (docs/ENGINE-PROTOCOL.md). */
  host(p: any) {
    switch (p?.action) {
      case "setViewStyle":
        if (p.style) { this.styleFromEngine = true; this.view.setStyle(String(p.style)); }
        // VISUALSTYLES Current: a custom style is its base plus overrides (standards/index.ts).
        if (p.custom) this.view.setCustomStyle(p.custom);
        if (String(p.style).toLowerCase() === "realistic") this.engine.call("render.settings", {}).then((s) => this.view.setRenderSettings(s, true)).catch(() => {});
        break;
      case "setView": if (p.view) this.view.setView(String(p.view)); break;
      case "zoomExtents": this.view.zoomExtents(); break;
      case "walkthrough": this.view.startNavigation("walk"); break;
      case "render": this.view.setStyle("Realistic"); break;
      case "view3d": this.tool(p).catch((e) => this.opts.print?.("Error: " + String(e?.message ?? e))); break;
    }
  }

  /** {"action":"view3d","op":…} from the portable 3D commands (EngineView3DCommands.swift). */
  private async tool(p: any) {
    const v = this.view, x = v.extras;
    // The 3D view may just have been created by the command's show3D: let the model arrive first.
    if (this.loading) await this.loading.catch(() => {});
    switch (p.op) {
      case "gizmo": x.setGizmo((p.mode ?? "Off") as GizmoMode); break;
      case "measure": x.setMeasure(!!p.on); break;
      case "levels": x.setLevelView(p.isolate ?? null, Number(p.explodeGap ?? 0)); break;
      case "sectionBoxPanel": v.showSectionBoxPanel(); break;
      case "sunStudy": v.showSunStudy(); break;
      case "clipPlanePanel": v.showClipPlanePanel(); break;
      case "orbitSelection": v.orbitSelection((p.ids ?? []).map(String)); break;
      case "camera": if (p.camera) v.positionCamera(p.camera); else if (p.name) v.applyNamedCamera(String(p.name)); break;
      case "fov": v.setFieldOfView(Number(p.fov)); break;
      case "navigate": v.startNavigation(p.mode === "fly" ? "fly" : p.mode === "look" ? "look" : "walk"); break;
      case "positionCamera": v.positionCamera(p.camera, p.mode ?? "look"); break;
      case "twoPoint": this.opts.print?.(v.twoPointCommand(!!p.on)); break;
      case "wheel": x.toggleWheel(!!p.on); break;
      case "animate": await this.refreshInfo(); x.play(!!p.play); break;
      case "animationFrame": {
        await this.refreshInfo();
        x.prepareDoors();
        const t = Number(p.time ?? 1);
        x.animTime = t; x.applyAnimations(t);
        const png = await v.renderToPNG({ width: 960, height: 540, supersample: 2 });
        x.animTime = -1; x.applyLevelView();
        const out = await this.save(p.path ?? null, png, p.path);
        if (out) this.opts.print?.(`Frame at ${fmt(t, 2)} s (${p.samples ?? 32} samples) → ${out}`);
        break;
      }
      case "panorama": {
        const path: string | null = p.path ?? null;
        const format = /\.png$/i.test(path ?? p.suggested ?? "") ? "PNG" : "JPEG";
        const w = Math.max(256, Number(p.width ?? 4096));
        const blob = await v.panorama({ eye: p.eye, width: w, stereo: !!p.stereo, ipd: Number(p.ipd ?? 64), format });
        const out = await this.save(path, blob, p.suggested);
        const ww = w - (w % 2);
        if (out) this.opts.print?.(p.stereo ? `Saved ${ww}×${ww} stereo panorama (left eye on top) to ${out}` : `Saved ${ww}×${ww / 2} panorama to ${out}`);
        break;
      }
      case "viewImage": {
        const fmtName = (p.format ?? "PNG").toUpperCase() as "PNG" | "JPEG" | "TIFF";
        const blob = await v.viewImage(Number(p.width), Number(p.height), !!p.transparent, fmtName);
        const out = await this.save(p.path ?? null, blob, p.suggested);
        if (out) this.opts.print?.(`Saved ${p.width}×${p.height} ${fmtName} to ${out}.`);
        break;
      }
    }
  }

  /** Writes an image: the shell's saveFile, else the engine (view3d.saveImage) at `path` or a chosen path. */
  async save(path: string | null, data: Blob, suggested?: string): Promise<string | null> {
    if (this.opts.saveFile) return this.opts.saveFile(path, data, suggested);
    const p = path ?? (this.opts.chooseSavePath ? await this.opts.chooseSavePath(suggested ?? "image.png") : suggested ?? null);
    if (!p) return null;
    const r = await this.engine.call("view3d.saveImage", { path: p, data: await blobToBase64(data) });
    return r?.path ?? p;
  }

  /**
   * RENDERSAVE <preset> <camera|Current> <width> <height> <path> — offscreen photographic render to a PNG with the
   * Mac's defaults (3× supersampling up to 1920×1080, else 2×; vertical correction for eye-level cameras).
   */
  async renderSave(args: string): Promise<string> {
    const words = args.trim().split(/\s+/).filter(Boolean);
    const preset = presetNamed(words[0] ?? "") ?? "Daylight";
    if (words.length) words.shift();
    const names = [...this.view.getCameras().map((c) => c.name), "Current"];
    let camera = "Current";
    for (let k = words.length; k >= 1; k--) {
      const cand = words.slice(0, k).join(" ");
      const hit = names.find((n) => n.toLowerCase() === cand.toLowerCase());
      if (hit) { camera = hit; words.splice(0, k); break; }
    }
    const w = words.length ? parseInt(words.shift()!, 10) : 1920;
    const h = words.length ? parseInt(words.shift()!, 10) : 1080;
    if (!(w >= 16 && h >= 16 && w <= 7680 && h <= 4320)) throw new Error("Use a size from 16×16 to 7680×4320.");
    let path = words.join(" ") || `Render ${preset} ${camera}.png`;
    if (!/\.png$/i.test(path)) path += ".png";
    const t0 = performance.now();
    const ss = w * h <= 1920 * 1080 ? 3 : 2;
    const png = await this.view.renderToPNG({ width: w, height: h, supersample: ss, preset, camera });
    const out = this.opts.savePNG ? await this.opts.savePNG(path, png) : (await this.save(path, png)) ?? path;
    this.opts.print?.(`Rendered ${preset}, ${camera === "Current" ? "current view" : camera}, ${w}×${h} (${ss}× supersampled) in ${((performance.now() - t0) / 1000).toFixed(1)} s → ${out}`);
    return out;
  }
}

function toBox(b: View3DDocument["sectionBox"]) {
  if (!b) return null;
  return { on: !!b.on, min: [b.min[0], b.min[1], b.min[2]] as [number, number, number], max: [b.max[0], b.max[1], b.max[2]] as [number, number, number] };
}
function toPlane(p: View3DDocument["sectionPlane"]) {
  if (!p) return null;
  return { on: !!p.on, point: [p.point[0], p.point[1], p.point[2]] as [number, number, number], normal: [p.normal[0], p.normal[1], p.normal[2]] as [number, number, number] };
}

export async function blobToBase64(b: Blob): Promise<string> {
  const u = new Uint8Array(await b.arrayBuffer());
  let s = "";
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000));
  return btoa(s);
}

/** Little-endian base64 Float32 buffer. */
export function decodeFloats(b64: string): Float32Array {
  if (!b64) return new Float32Array(0);
  const s = atob(b64);
  const u = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i);
  return new Float32Array(u.buffer, 0, u.length >> 2);
}

export const RENDER_PRESET_KEYWORDS = PRESET_KEYWORDS;
void styleNamed;
