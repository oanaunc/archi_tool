// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Wires a View3D to the archi-engine session: model.meshes + render.settings on load and on "changed" notifications,
// selection both ways, the `host` actions of 3D commands (setViewStyle, setView, walkthrough, render) and RENDERSAVE.

import type { View3D } from "./view3d";
import type { SavedCamera, MaterialMaps } from "./scene";
import { parseSectionBox, parseSectionPlane, formatSectionBox } from "./variables";
import { presetNamed, PRESET_KEYWORDS } from "./look";

export interface EngineLike {
  call(method: string, params?: unknown): Promise<any>;
  onNotify(cb: (n: { method: string; params: any }) => void): void;
}

export interface BridgeOptions {
  /** Level of detail of model.meshes (0 = full; the Cedar House trees are ~1.1 M triangles at 0). */
  lod?: number;
  /** When set, model.meshes writes its buffers to this file and `readBinary` loads it (much smaller than base64). */
  binaryPath?: string;
  readBinary?: (path: string) => Promise<ArrayBuffer>;
  /** Saves a rendered PNG (RENDERSAVE); returns the path written. */
  savePNG?: (path: string, png: Blob) => Promise<string>;
  /** Prints to the command line history. */
  print?: (text: string) => void;
}

/** Document data the 3D view needs beyond model.meshes (saved cameras, MATMAPS, SECTIONBOX …). */
export interface View3DDocument {
  cameras?: SavedCamera[];
  materialMaps?: Record<string, MaterialMaps>;
  variables?: Record<string, string>;
  northAngle?: number;
}

export class EngineBridge {
  private reloadTimer = 0;
  private loading: Promise<void> | null = null;

  constructor(readonly view: View3D, readonly engine: EngineLike, readonly opts: BridgeOptions = {}) {
    engine.onNotify((n) => this.onNotify(n.method, n.params));
    if (typeof document !== "undefined") document.addEventListener("archi:host", (e) => this.host((e as CustomEvent).detail));
    const prevPick = view.opts.onPick;
    view.opts.onPick = (id, extend) => { prevPick?.(id, extend); this.pick(id, extend); };
    const prevBox = view.opts.onSectionBox;
    view.opts.onSectionBox = (b) => { prevBox?.(b); if (b) this.setVariable("SECTIONBOX", formatSectionBox(b)); };
  }

  /** Loads the model, the lighting preset and the 3D document data. */
  load(): Promise<void> {
    if (this.loading) return this.loading;
    this.loading = (async () => {
      const [meshes, settings] = await Promise.all([
        this.engine.call("model.meshes", { level: "all", lod: this.opts.lod ?? 0, ...(this.opts.binaryPath ? { binary: this.opts.binaryPath } : {}) }),
        this.engine.call("render.settings", {}).catch(() => null),
      ]);
      let bin: ArrayBuffer | undefined;
      if (meshes?.binary && this.opts.readBinary) bin = await this.opts.readBinary(meshes.binary);
      const doc = await this.documentData();
      if (doc.materialMaps) this.view.setMaterialMaps(doc.materialMaps);
      if (doc.cameras) this.view.setCameras(doc.cameras);
      if (typeof doc.northAngle === "number") this.view.setNorthAngle(doc.northAngle);
      const vars = doc.variables ?? {};
      this.view.setSectionBox(parseSectionBox(vars.SECTIONBOX));
      this.view.setSectionPlane(parseSectionPlane(vars.SECTIONPLANE));
      // A preset stored in the drawing (RENDERPRESET) turns on haze, meadow and the preset camera response.
      const explicit = vars.RENDERPRESET != null ? !!presetNamed(vars.RENDERPRESET) : true;
      this.view.setRenderSettings(settings, explicit);
      this.view.setModel(meshes, bin);
      if (vars.PERSPECTIVE === "0" && !this.view.getCamera().ortho) this.view.toggleProjection();
      await this.syncSelection();
    })().finally(() => { this.loading = null; });
    return this.loading;
  }

  /**
   * Saved cameras, material maps and 3D variables. Uses `view3d.info` when the engine offers it (proposed protocol
   * extension: {cameras:[{name,eye,target,fov,orthographic}], materialMaps:{NAME:{normal,roughness,normalStrength}},
   * variables:{SECTIONBOX,SECTIONPLANE,PERSPECTIVE,RENDERPRESET}, northAngle}); otherwise nothing.
   */
  private async documentData(): Promise<View3DDocument> {
    try { return (await this.engine.call("view3d.info", {})) ?? {}; } catch { return {}; }
  }

  private async setVariable(name: string, value: string) {
    try { await this.engine.call("view3d.setVariable", { name, value }); } catch { /* older engines: kept in the view only */ }
  }

  private onNotify(method: string, params: any) {
    if (method !== "changed") return;
    const what: string[] = params?.what ?? [];
    if (what.includes("document") || what.includes("model") || what.includes("materials")) {
      clearTimeout(this.reloadTimer);
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
      case "setViewStyle": if (p.style) this.view.setStyle(String(p.style)); if (String(p.style).toLowerCase() === "realistic") this.engine.call("render.settings", {}).then((s) => this.view.setRenderSettings(s, true)).catch(() => {}); break;
      case "setView": if (p.view) this.view.setView(String(p.view)); break;
      case "zoomExtents": this.view.zoomExtents(); break;
      case "walkthrough": this.view.startNavigation("walk"); break;
      case "render": this.view.setStyle("Realistic"); break;
    }
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
    const out = this.opts.savePNG ? await this.opts.savePNG(path, png) : path;
    this.opts.print?.(`Rendered ${preset}, ${camera === "Current" ? "current view" : camera}, ${w}×${h} (${ss}× supersampled) in ${((performance.now() - t0) / 1000).toFixed(1)} s → ${out}`);
    return out;
  }
}

export const RENDER_PRESET_KEYWORDS = PRESET_KEYWORDS;
