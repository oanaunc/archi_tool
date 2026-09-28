// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The 3D view the shell mounts (Mac: Viewport3DView.swift + Viewport3DController): WebGL2 canvas, the overlay bar
// (standard views, projection, zoom extents, walk, orbit selection, section box, sun study, clipping plane, view cube,
// cameras, visual style), the view cube, navigation (turntable orbit, pan, dolly, inertia, walk / fly / look around)
// and the photographic renderer (renderToPNG, RENDERSAVE).

import { Renderer, UNIT, SectionBox, SectionPlane, FrameOptions } from "./renderer";
import { SceneModel, MeshesResult, MaterialMaps, SavedCamera, AssetResolver, ImageLoader, defaultImageLoader, MeshGPU } from "./scene";
import { Look, lookFrom, presetNamed, PRESETS, VISUAL_STYLES, VisualStyle, styleNamed, sunDirection } from "./look";
import {
  CameraState, cloneCamera, defaultCamera, framed, orbit, pan, zoom, zoomAt, toggleProjection, fromSaved, twoPoint, interpolate,
  viewDirection, basis, viewMatrix, projMatrix, zRange,
} from "./camera";
import { ViewCube } from "./viewcube";
import { setBillboards, BillboardItem } from "./billboards";
import { V3, add, sub, scale, len, norm, mul, invert, transform, clamp } from "./math";
import { View3DExtras, ExtrasHost } from "./extras";
import { Weather, ObjectAnimation, LevelInfo, sunStudy, sunStudyText, FieldOfView, fmt, parseWeather, CUBE_FACES, panoDirection, cubeLookup, odsOffset } from "./effects";

export type NavMode = "walk" | "fly" | "look";
const NAV_HINT: Record<NavMode, string> = {
  walk: "Walk: W A S D to move · drag to look · walls stop you, floors and stairs carry you · Shift to run · Esc to exit",
  fly: "Fly: W A S D along the view direction · Q/E down/up · drag to look · Shift for speed · Esc to exit",
  look: "Look around: drag or arrow keys to turn the head · the eye stays in place · Esc to exit",
};

export interface View3DOptions {
  /** Maps a document-relative asset path ("textures/cedar.jpg") to a URL the renderer can load. */
  resolveAsset?: AssetResolver;
  loadImage?: ImageLoader;
  /** MATMAPS of the document, keyed by upper-case material name. */
  materialMaps?: Record<string, MaterialMaps>;
  /** Show the Mac overlay bar and view cube (default true). */
  overlay?: boolean;
  /** Creates an icon element for an SF Symbol name (the shell's icons.ts); text fallbacks otherwise. */
  icon?: (sfSymbol: string, size: number) => Element;
  /** A click picked a building element (id as the engine sends it; null = empty space). */
  onPick?: (id: string | null, extend: boolean) => void;
  /** Section box / plane changed by the user (store as the SECTIONBOX / SECTIONPLANE drawing variables). */
  onSectionBox?: (box: SectionBox | null) => void;
  /** Projection toggled (store PERSPECTIVE 0/1). */
  onProjection?: (ortho: boolean) => void;
  /** Visual style picked in the overlay menu. */
  onStyle?: (style: VisualStyle) => void;
  /** Section plane changed in the clipping plane panel (SECTIONPLANE). */
  onSectionPlane?: (plane: SectionPlane | null) => void;
  /** The camera moved (the shell reports it to the engine for SAVECAMERA / FOV / PANORAMA Camera). */
  onCamera?: (c: CameraState) => void;
  /** Tools of the Mac 3D view (gizmo commits, variables, cameras, printing). */
  extras?: ExtrasHost;
}

/** Document data of the 3D view (view3d.info). */
export interface View3DInfo {
  levels?: LevelInfo[];
  currentLevel?: number;
  weather?: Weather | null;
  fog?: { on: boolean; start: number; end: number; color: string; density: number } | null;
  water?: string[];
  animations?: ObjectAnimation[];
  site?: { latitude: number; longitude: number; day: number; hour: number };
  levelView?: { isolate: number | null; explodeGap: number };
  unitMM?: number;
  /** AODIALOG settings; `viewport` is the SceneKit screen-space occlusion (intensity, radius in metres) or null (off). */
  ambientOcclusion?: { intensity: number; radius: number; samples: number; on: boolean; viewport: { intensity: number; radius: number } | null } | null;
  /** BILLBOARD cut-outs: base point (model mm), height (mm), source (person, tree, shrub or an image path). */
  billboards?: BillboardItem[];
}

export interface RenderRequest {
  width: number;
  height: number;
  /** Supersampling factor (BeautyRenderer: 3 up to 1920×1080, else 2; at most 4). */
  supersample?: number;
  /** Lighting preset (Daylight, Goldenhour, Overcast, Night); default the current one. */
  preset?: string;
  /** Saved camera name, or "Current". */
  camera?: string;
  /** Two-point correction for near-level cameras (default true). */
  verticalCorrection?: boolean;
  /** An explicit camera (panorama faces); overrides `camera`. */
  cameraState?: CameraState;
  /** Visual style of the image (VIEWIMAGE: the current style); default the photographic Realistic render. */
  style?: VisualStyle;
  /** Reuse the sun shadow map of the previous render (panorama faces). */
  reuseShadow?: boolean;
  background?: "sky" | "white" | "transparent";
}

export class View3D {
  readonly el: HTMLDivElement;
  readonly canvas: HTMLCanvasElement;
  readonly gl: WebGL2RenderingContext;
  readonly renderer: Renderer;
  readonly scene: SceneModel;
  private cube: ViewCube | null = null;
  private bar: HTMLDivElement | null = null;
  private hint: HTMLDivElement;
  private panelHost: HTMLDivElement;
  private camera: CameraState = defaultCamera();
  private positioned = false;
  private style: VisualStyle = "Realistic";
  private lookState: Look = PRESETS.Daylight;
  private explicit = false;
  private cameras: SavedCamera[] = [];
  private selection = new Set<string>();
  private box: SectionBox | null = null;
  private plane: SectionPlane | null = null;
  private sun: V3 | null = null;
  private northAngle = 0;
  private dirty = true;
  private raf = 0;
  private anim: { from: CameraState; to: CameraState; t0: number; dur: number } | null = null;
  private inertia: [number, number] = [0, 0];
  private nav: NavMode | null = null;
  private keys = new Set<string>();
  private shift = false;
  private yaw = 0; private pitch = 0; private fall = 0; private lastTick = 0;
  private showCube = true;
  private sectionPanel = false;
  private resizeObs: ResizeObserver | null = null;
  private pendingTextures = 0;
  private texWaiters: (() => void)[] = [];
  lastFrameMs = 0;
  readonly extras: View3DExtras;
  private weather: Weather | null = null;
  private fog: View3DInfo["fog"] = null;
  /** Viewport ambient occlusion of the drawing (AOINTENSITY / AORADIUS), null = the style's. */
  private aoOverride: { intensity: number; radius: number } | null = null;
  /** Camera-facing cut-outs of the drawing (BILLBOARD). */
  private billboards: BillboardItem[] = [];
  private get resolveAsset(): (p: string) => string { return this.scene.resolve; }
  private water: Set<string> | null = null;
  private sunLight: { intensity: number; color: V3 } | null = null;
  private clipPanel = false;
  private sunPanelOpen = false;
  private sunPlaying = 0;
  private cameraTimer = 0;
  private info: View3DInfo = {};

  constructor(host: HTMLElement, readonly opts: View3DOptions = {}) {
    injectStyles();
    this.el = document.createElement("div");
    this.el.className = "v3d";
    this.el.tabIndex = 0;
    this.el.setAttribute("aria-label", "3D model view");
    this.canvas = document.createElement("canvas");
    this.canvas.className = "v3d-canvas";
    this.el.append(this.canvas);
    host.append(this.el);
    const gl = this.canvas.getContext("webgl2", { antialias: false, alpha: false, depth: false, preserveDrawingBuffer: true, powerPreference: "high-performance" });
    if (!gl) throw new Error("WebGL 2 is not available");
    this.gl = gl;
    this.renderer = new Renderer(gl);
    const loader = opts.loadImage ?? defaultImageLoader;
    const counting: ImageLoader = (url) => {
      this.pendingTextures++;
      return loader(url).finally(() => { this.pendingTextures--; this.invalidate(); if (this.pendingTextures === 0) { const w = this.texWaiters; this.texWaiters = []; w.forEach((f) => f()); } });
    };
    this.scene = new SceneModel(gl, opts.resolveAsset ?? ((p) => p), counting, opts.materialMaps ?? {});
    this.scene.onTextureLoaded = () => this.invalidate();
    this.hint = div("v3d-hint");
    this.hint.hidden = true;
    this.panelHost = div("v3d-side");
    this.el.append(this.hint);
    if (opts.overlay !== false) this.buildOverlay();
    this.extras = new View3DExtras(this, opts.extras ?? {});
    if (opts.overlay === false) this.extras.toolbar.hidden = true;
    this.bindInput();
    this.resizeObs = new ResizeObserver(() => this.invalidate());
    addEventListener("archi:dpr", () => this.invalidate()); // per-monitor DPI change
    this.resizeObs.observe(this.el);
    this.invalidate();
  }

  // MARK: public API

  /** Replaces the model with a model.meshes result (`binary`: buffer file when requested with {"binary": path}). */
  setModel(result: MeshesResult, binary?: ArrayBuffer) {
    this.scene.set(result, binary);
    if (this.billboards.length) void setBillboards(this.scene, this.billboards, this.resolveAsset).then(() => this.invalidate());
    this.extras.setAnimations(this.extras.animations);
    this.extras.applyLevelView();
    if (result.sun && !this.explicit) this.lookState = lookFrom({ ...this.lookState, preset: result.sun.preset ?? this.lookState.preset });
    if (!this.positioned && !this.scene.empty) { this.positioned = true; this.setView("Iso", false); }
    this.invalidate();
  }

  setMaterialMaps(maps: Record<string, MaterialMaps>) { this.scene.materialMaps = maps; }

  /** Document data from view3d.info: levels, weather, fog, water, animations, sun study site. */
  setInfo(info: View3DInfo) {
    this.info = { ...this.info, ...info };
    if (info.levels) this.extras.levels = info.levels;
    if (info.currentLevel != null) this.extras.currentLevel = info.currentLevel;
    if ("weather" in info) this.weather = info.weather ? parseWeather(`${info.weather.kind};${info.weather.intensity};${info.weather.season};${info.weather.snowCover}`) : null;
    if ("fog" in info) this.fog = info.fog ?? null;
    // Ambient occlusion of the drawing (AODIALOG, AmbientOcclusion.settings → AOForm.viewport).
    if ("ambientOcclusion" in info) this.aoOverride = info.ambientOcclusion?.viewport ?? null;
    if (info.billboards && JSON.stringify(info.billboards) !== JSON.stringify(this.billboards)) {
      this.billboards = info.billboards;
      void setBillboards(this.scene, info.billboards, this.resolveAsset).then(() => this.invalidate());
    }
    if (info.water) this.water = new Set(info.water);
    if (info.site) this.extras.site = { ...info.site };
    if (info.levelView) this.extras.setLevelView(info.levelView.isolate, info.levelView.explodeGap * (info.unitMM ?? 1));
    if (info.animations) { this.extras.setAnimations(info.animations); this.extras.applyLevelView(); }
    this.invalidate();
  }
  getInfo(): View3DInfo { return this.info; }
  setWeather(w: Weather | null) { this.weather = w; this.invalidate(); }
  /** Section plane caps (view3d.sectionCaps): positions model mm. */
  setSectionCaps(positions: Float32Array | null, normal?: V3) { this.scene.setCaps(positions, normal); this.invalidate(); }

  // MARK: helpers for the tools (extras.ts)

  iconFor(sf: string, fallback: string): Element { return this.icon(sf, fallback); }
  getSelection(): string[] { return [...this.selection]; }
  get panelHostEl(): HTMLDivElement { return this.panelHost; }
  refreshOverlayPublic() { this.refreshOverlay(); }
  sceneCenterWorld(): V3 { return this.center(); }
  /** View point (CSS pixels) of a model point (mm), or null behind the camera. */
  project(p: V3): [number, number] | null {
    const w = Math.max(1, this.el.clientWidth), h = Math.max(1, this.el.clientHeight);
    const [near, far] = zRange(this.camera, this.center(), this.radius(), 2000);
    const vp = mul(projMatrix(this.camera, w / h, near, far), viewMatrix(this.camera));
    const q = transform(vp, [p[0] * UNIT, p[1] * UNIT, p[2] * UNIT]);
    if (q[3] <= 1e-6) return null;
    return [((q[0] / q[3]) * 0.5 + 0.5) * w, (1 - ((q[1] / q[3]) * 0.5 + 0.5)) * h];
  }

  /** Field of view of the perspective camera (FOV, Level3DMenu). */
  setFieldOfView(fov: number) { this.camera = { ...this.camera, fov: FieldOfView.clamp(fov) }; this.cameraChanged(); this.refreshOverlay(); this.invalidate(); }

  /** POSITIONCAMERA: a saved-camera-like placement (model mm), then an optional navigation mode. */
  positionCamera(c: SavedCamera, mode?: NavMode) {
    if (this.nav) this.stopNavigation();
    const cam = fromSaved(c, UNIT, false);
    this.moveTo(cam, false);
    if (mode) this.startNavigation(mode);
  }

  /** TWOPOINT On/Off; returns the Mac message. */
  twoPointCommand(on: boolean): string {
    this.setTwoPoint(on);
    return on ? `Two-point perspective: verticals are vertical (lens shift ${fmt(this.camera.shiftY, 3)}).` : "Three-point perspective restored.";
  }

  private cameraChanged() {
    if (!this.opts.onCamera) return;
    clearTimeout(this.cameraTimer);
    this.cameraTimer = setTimeout(() => this.opts.onCamera?.(cloneCamera(this.camera)), 250) as unknown as number;
  }
  setCameras(cams: SavedCamera[]) { this.cameras = cams.slice(); this.refreshOverlay(); }
  getCameras() { return this.cameras.slice(); }
  setNorthAngle(deg: number) { this.northAngle = deg; this.invalidate(); }

  /** Visual style (Wireframe, Hidden Line, Shaded, Shaded with Edges, Conceptual, Realistic, X-Ray, Sketchy). */
  setStyle(name: string) { this.style = VISUAL_STYLES.includes(name as VisualStyle) ? (name as VisualStyle) : styleNamed(name); this.custom = null; this.customName = null; this.refreshOverlay(); this.invalidate(); }
  /** Custom visual style (VISUALSTYLES Current): overrides on top of the built-in style set with setStyle; null = none. */
  private custom: FrameOptions["custom"] = null;
  private customName: string | null = null;
  setCustomStyle(c: { name?: string; edges?: boolean | null; edgeColor?: string | null; faceOpacity?: number | null; shadows?: boolean | null; background?: string | null } | null) {
    const rgb = (s?: string | null): V3 | null => { const m = /^#?([0-9a-f]{6})$/i.exec(s ?? ""); if (!m) return null; const v = parseInt(m[1], 16); return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255]; };
    this.custom = c ? { edges: c.edges ?? null, edgeColor: rgb(c.edgeColor), faceOpacity: c.faceOpacity ?? null, shadows: c.shadows ?? null, background: rgb(c.background) } : null;
    this.customName = c?.name ?? null;
    this.refreshOverlay(); this.invalidate();
  }
  getCustomStyle() { return this.custom ? { name: this.customName, ...this.custom } : null; }
  getStyle() { return this.style; }

  /** render.settings / render.preset result. `explicit`: a preset is stored in the drawing (RENDERPRESET). */
  setRenderSettings(settings: Partial<Look> | null, explicit = true) {
    this.lookState = lookFrom(settings);
    this.explicit = explicit && !!settings;
    if (settings && typeof (settings as any).northAngle === "number") this.northAngle = (settings as any).northAngle;
    this.invalidate();
  }
  getLook() { return this.lookState; }

  setSelection(ids: Iterable<string | number>) { this.selection = new Set([...ids].map(String)); this.invalidate(); }
  setSectionBox(b: SectionBox | null) { this.box = b; this.invalidate(); this.refreshOverlay(); }
  getSectionBox() { return this.box; }
  setSectionPlane(p: SectionPlane | null) { this.plane = p; this.invalidate(); this.refreshOverlay(); }
  getSectionPlane(): SectionPlane | null { return this.plane; }
  /** Sun study: direction towards the sun (model axes), or null for the style's own sun. */
  setSun(dir: V3 | null) { this.sun = dir; this.invalidate(); }

  getCamera(): CameraState { return cloneCamera(this.camera); }
  setCamera(c: CameraState, animated = false) { this.moveTo(c, animated); }

  /** Standard views: Top, Bottom, Front, Back, Left, Right, SW/SE/NE/NW Iso (Iso = SW), Ortho, Perspective. */
  setView(name: string, animated = true) {
    const k = name.toLowerCase();
    if (k === "ortho" || k === "orthographic" || k === "parallel") { if (!this.camera.ortho) this.toggleProjection(); return; }
    if (k === "perspective") { if (this.camera.ortho) this.toggleProjection(); return; }
    if (k.startsWith("named:")) { this.applyNamedCamera(name.slice(6), animated); return; }
    const d = viewDirection(name);
    if (!d) { this.applyNamedCamera(name, animated); return; }
    if (this.nav) this.stopNavigation();
    this.moveTo(framed(this.camera, this.center(), this.radius(), d.dir, d.up), animated);
  }

  /** View from a direction towards the eye (view cube; setViewDirection). */
  setViewDirection(dir: V3, animated = true) {
    if (this.nav) this.stopNavigation();
    const s = this.center(), r = this.radius();
    const center = len(sub(this.camera.target, s)) < r * 2 ? this.camera.target : s;
    this.moveTo(framed(this.camera, center, r, norm(dir), [0, 0, 1]), animated);
  }

  zoomExtents() {
    if (this.nav) this.stopNavigation();
    const dir = norm(sub(this.camera.eye, this.camera.target));
    const c = framed(this.camera, this.center(), this.radius(), dir, this.camera.up, 1.1);
    c.up = this.camera.up;
    this.moveTo(c, true);
  }

  toggleProjection() {
    this.camera = toggleProjection(this.camera);
    this.opts.onProjection?.(this.camera.ortho);
    this.refreshOverlay(); this.invalidate();
  }

  /** Two-point perspective (TWOPOINT). */
  setTwoPoint(on: boolean) { this.camera = twoPoint(this.camera, on); this.invalidate(); }

  /** Applies a saved camera by name (case-insensitive). */
  applyNamedCamera(name: string, animated = true): boolean {
    const c = this.cameras.find((x) => x.name.toLowerCase() === name.toLowerCase());
    if (!c) return false;
    if (this.nav) this.stopNavigation();
    const cam = fromSaved(c, UNIT, false);
    cam.ortho = !!c.orthographic;
    this.moveTo(cam, animated);
    return true;
  }

  /** Orbit around the selection and frame it (orbitSelection). */
  orbitSelection(ids: Iterable<string> = this.selection): boolean {
    const set = new Set([...ids].map(String));
    const ms = this.scene.meshes.filter((m) => m.id != null && set.has(m.id));
    if (!ms.length) return false;
    const lo: V3 = [Infinity, Infinity, Infinity], hi: V3 = [-Infinity, -Infinity, -Infinity];
    for (const m of ms) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], m.min[k]); hi[k] = Math.max(hi[k], m.max[k]); }
    const c: V3 = [(lo[0] + hi[0]) / 2 * UNIT, (lo[1] + hi[1]) / 2 * UNIT, (lo[2] + hi[2]) / 2 * UNIT];
    const r = Math.max(0.5, len(sub(hi, lo)) / 2 * UNIT);
    this.moveTo(framed(this.camera, c, r, norm(sub(this.camera.eye, this.camera.target)), [0, 0, 1]), true);
    return true;
  }

  /** First-person navigation (VIS-017 walk, VIS-018 fly, VIS-020 look around). */
  startNavigation(mode: NavMode) {
    if (this.camera.ortho) this.toggleProjection();
    this.nav = mode;
    const f = norm(sub(this.camera.target, this.camera.eye));
    this.yaw = Math.atan2(f[1], f[0]);
    this.pitch = Math.asin(clamp(f[2], -1, 1));
    if (mode === "walk") {
      const c = this.center(), r = this.radius();
      let p = this.camera.eye;
      if (len(sub(p, c)) > r * 1.5 || p[2] > 20) p = [c[0], c[1] - r * 1.2, 0];
      this.camera = { ...this.camera, eye: [p[0], p[1], 1.6 + Math.max(0, this.scene.min[2] * UNIT)], fov: 60, shiftY: 0, up: [0, 0, 1] };
      this.pitch = 0; this.fall = 0;
    }
    this.applyLook();
    this.hint.textContent = NAV_HINT[mode];
    this.hint.hidden = false;
    this.el.focus();
    this.lastTick = performance.now();
    this.refreshOverlay();
    this.invalidate();
  }

  stopNavigation() {
    if (!this.nav) return;
    this.nav = null;
    this.keys.clear();
    const f = norm(sub(this.camera.target, this.camera.eye));
    this.camera = { ...this.camera, fov: 45, target: add(this.camera.eye, scale(f, 5)) };
    this.hint.hidden = true;
    this.refreshOverlay();
    this.invalidate();
  }

  get navigation(): NavMode | null { return this.nav; }

  /** A camera transition or orbit inertia is running. */
  isAnimating(): boolean { return !!this.anim || Math.abs(this.inertia[0]) > 0.05 || Math.abs(this.inertia[1]) > 0.05; }

  /** Id of the building element under a point of the view (CSS pixels), or null. */
  pickAt(x: number, y: number): string | null {
    const hit = this.rayHit(x, y);
    return hit?.mesh.id ?? null;
  }

  /** Mesh (id, kind) and model point (mm) under a point of the view. */
  hitAt(x: number, y: number): { id: string | null; kind: string; point: V3 } | null {
    const h = this.rayHit(x, y);
    return h ? { id: h.mesh.id, kind: h.mesh.kind, point: h.point } : null;
  }

  /** Stores a section box edited in the view (face grip drags). */
  commitSectionBox(b: SectionBox) { this.box = b; this.opts.onSectionBox?.(b); this.panelHost.querySelector(".v3d-boxpanel") && this.rebuildBoxPanelQuiet(); this.refreshOverlay(); this.invalidate(); }
  private rebuildBoxPanelQuiet() { this.panelHost.querySelector(".v3d-boxpanel")?.replaceWith(this.sectionBoxPanel()); }

  /** Model point (mm) under a point of the view, or null. */
  pointAt(x: number, y: number): V3 | null {
    const hit = this.rayHit(x, y);
    return hit ? hit.point : null;
  }

  /** Resolves when every texture requested so far has loaded (tests, renders). */
  whenTexturesLoaded(): Promise<void> {
    // Ask for all textures of the current style first.
    this.drawNow();
    if (this.pendingTextures === 0) return Promise.resolve();
    return new Promise((res) => this.texWaiters.push(res));
  }

  /** Photographic render to a PNG (RENDERSAVE): preset, saved camera, size, supersampling. */
  async renderToPNG(r: RenderRequest): Promise<Blob> {
    const px = await this.renderPixels(r);
    const cv = document.createElement("canvas");
    cv.width = px.width; cv.height = px.height;
    const ctx = cv.getContext("2d")!;
    ctx.putImageData(new ImageData(new Uint8ClampedArray(px.data), px.width, px.height), 0, 0);
    return await new Promise<Blob>((res, rej) => cv.toBlob((b) => (b ? res(b) : rej(new Error("PNG encoding failed"))), "image/png"));
  }

  /** RGBA pixels (top row first) of a photographic render. */
  async renderPixels(r: RenderRequest): Promise<{ width: number; height: number; data: Uint8Array; supersample: number }> {
    const w = Math.round(r.width), h = Math.round(r.height);
    if (!(w >= 16 && h >= 16 && w <= 7680 && h <= 4320)) throw new Error("Use a size from 16×16 to 7680×4320.");
    const presetName = presetNamed(r.preset ?? this.lookState.preset) ?? "Daylight";
    const look = r.preset ? lookFrom({ ...PRESETS[presetName], northAngle: this.northAngle }) : this.lookState;
    let cam = r.cameraState ?? this.camera;
    if (!r.cameraState && r.camera && r.camera.toLowerCase() !== "current") {
      const c = this.cameras.find((x) => x.name.toLowerCase() === r.camera!.toLowerCase());
      if (!c) throw new Error(`No saved camera named ${r.camera}. Saved cameras: ${this.cameras.map((x) => x.name).join(", ") || "none (SAVECAMERA)"}.`);
      cam = fromSaved(c, UNIT, r.verticalCorrection !== false);
    }
    // Textures of the Realistic style must be in before the frame is taken.
    const prev = this.style;
    this.style = "Realistic";
    await this.whenTexturesLoaded();
    this.style = prev;
    return this.renderPixelsNow(r, cam, look);
  }

  /** The render itself, textures already loaded (panorama faces render many frames in a row). */
  private renderPixelsNow(r: RenderRequest, cam: CameraState, look: Look, invalidate = true): { width: number; height: number; data: Uint8Array; supersample: number } {
    const w = Math.round(r.width), h = Math.round(r.height);
    const ss = r.supersample ?? (w * h <= 1920 * 1080 ? 3 : 2);
    const style = r.style ?? "Realistic";
    const o: FrameOptions = {
      ...this.frameOptions(w, h), camera: cam, style, look: style === "Realistic" ? look : this.lookState, explicitPreset: style === "Realistic" ? true : this.explicit,
      quality: "final", supersample: ss, selection: new Set(), background: r.background ?? (style === "Realistic" ? "sky" : undefined),
      sunOverride: style === "Realistic" ? null : this.sun, time: this.extras.animTime >= 0 ? this.extras.animTime : 1, reuseShadow: !!r.reuseShadow,
    };
    const out = this.renderer.renderPixels(this.scene, o);
    if (invalidate) this.invalidate();
    return out;
  }

  /**
   * VIEWIMAGE (Viewport3DController.viewportImage): the current view in the current style at any size; with
   * `transparent` the background and ground are left out (alpha from a black and a white pass).
   */
  async viewImage(width: number, height: number, transparent = false, format: "PNG" | "JPEG" | "TIFF" = "PNG"): Promise<Blob> {
    await this.whenTexturesLoaded();
    const base: RenderRequest = { width, height, supersample: 1, style: this.style, cameraState: this.camera, verticalCorrection: false };
    let px: { width: number; height: number; data: Uint8Array };
    if (transparent && format !== "JPEG") {
      const black = this.renderStyled({ ...base }, "transparent", true), white = this.renderStyled({ ...base }, "white", true);
      const d = new Uint8Array(black.data.length);
      for (let i = 0; i < d.length; i += 4) {
        const a = 1 - ((white.data[i] - black.data[i]) + (white.data[i + 1] - black.data[i + 1]) + (white.data[i + 2] - black.data[i + 2])) / (3 * 255);
        const al = Math.min(1, Math.max(0, a));
        for (let c = 0; c < 3; c++) d[i + c] = al > 0.004 ? Math.min(255, Math.round(black.data[i + c] / al)) : 0;
        d[i + 3] = Math.round(al * 255);
      }
      px = { width: black.width, height: black.height, data: d };
    } else px = this.renderStyled(base, undefined, false);
    return encodeImage(px, format);
  }

  private renderStyled(r: RenderRequest, background: "white" | "transparent" | undefined, hideGround: boolean) {
    const o: FrameOptions = { ...this.frameOptions(r.width, r.height), camera: r.cameraState ?? this.camera, quality: "final", supersample: r.supersample ?? 1,
      selection: new Set(), background, hideGround, particles: true };
    const out = this.renderer.renderPixels(this.scene, o);
    if (background === "transparent") for (let i = 3; i < out.data.length; i += 4) out.data[i] = 255;
    this.invalidate();
    return out;
  }

  /**
   * 360° panoramas (PANORAMA, STEREOPANORAMA / RenderEngine.stereoPanorama): six 90° cube faces from the eye (model mm)
   * resampled to an equirectangular image centred on north; stereo renders each of `slices` longitude slices from eyes
   * offset sideways by half the interpupillary distance and stacks the eyes over-under (left on top).
   */
  async panorama(o: { eye: V3; width: number; stereo?: boolean; ipd?: number; slices?: number; format?: "PNG" | "JPEG"; preset?: string }): Promise<Blob> {
    const w = Math.max(256, o.width - (o.width % 2)), h = w / 2;
    const face = Math.max(64, Math.floor(w / 4));
    const prev = this.style;
    this.style = "Realistic";
    await this.whenTexturesLoaded();
    this.style = prev;
    const presetName = presetNamed(o.preset ?? this.lookState.preset) ?? "Daylight";
    const look = lookFrom({ ...PRESETS[presetName], northAngle: this.northAngle });
    let faceCount = 0;
    const renderFace = (eye: V3, f: number) => {
      const cf = CUBE_FACES[f];
      const e = scale(eye, UNIT);
      const cam: CameraState = { eye: e, target: add(e, cf.front), up: cf.up, fov: 90, ortho: false, orthoScale: 10, shiftY: 0 };
      const px = this.renderPixelsNow({ width: face, height: face, supersample: 1, cameraState: cam, verticalCorrection: false, reuseShadow: faceCount > 0 }, cam, look, false);
      faceCount++;
      return px;
    };
    const heading: V3 = [0, 1, 0];
    const rows = o.stereo ? 2 : 1;
    const out = new Uint8Array(w * h * rows * 4);
    const n = o.stereo ? Math.max(1, Math.min(o.slices ?? 24, 360)) : 1;
    for (let row = 0; row < rows; row++) {
      const eyeSign = row === 0 ? -1 : 1;
      for (let k = 0; k < n; k++) {
        const x0 = Math.floor((k * w) / n), x1 = Math.floor(((k + 1) * w) / n);
        if (x1 <= x0) continue;
        let eye = o.eye;
        if (o.stereo) {
          const dc = panoDirection((x0 + x1) / 2 / w, 0.5, heading);
          eye = add(o.eye, odsOffset(dc, o.ipd ?? 64, eyeSign));
        }
        const faces = new Map<number, Uint8Array>();
        for (let y = 0; y < h; y++) for (let x = x0; x < x1; x++) {
          const d = panoDirection((x + 0.5) / w, (y + 0.5) / h, heading);
          const l = cubeLookup(d);
          let buf = faces.get(l.face);
          if (!buf) { buf = renderFace(eye, l.face).data; faces.set(l.face, buf); }
          const px = Math.min(face - 1, Math.floor(l.s * face)), py = Math.min(face - 1, Math.floor(l.t * face));
          const src = (py * face + px) * 4, dst = ((row * h + y) * w + x) * 4;
          out[dst] = buf[src]; out[dst + 1] = buf[src + 1]; out[dst + 2] = buf[src + 2]; out[dst + 3] = 255;
        }
      }
    }
    this.invalidate();
    return encodeImage({ width: w, height: h * rows, data: out }, o.format ?? "JPEG");
  }

  /** Current view as a PNG at the canvas size (EXPORT 3D view image). */
  async snapshot(): Promise<Blob> {
    this.drawNow();
    return await new Promise<Blob>((res, rej) => this.canvas.toBlob((b) => (b ? res(b) : rej(new Error("PNG encoding failed"))), "image/png"));
  }

  invalidate() {
    this.dirty = true;
    if (!this.raf) this.raf = requestAnimationFrame(() => this.tick());
  }

  dispose() {
    cancelAnimationFrame(this.raf);
    this.resizeObs?.disconnect();
    this.scene.dispose();
    this.renderer.dispose();
    this.el.remove();
  }

  // MARK: frame loop

  private center(): V3 { return this.scene.empty ? [0, 0, 1.5] : this.scene.center.map((v) => v * UNIT) as V3; }
  private radius(): number { return this.scene.empty ? 10 : this.scene.radius * UNIT; }

  private moveTo(c: CameraState, animated: boolean) {
    this.inertia = [0, 0];
    this.cameraChanged();
    if (animated) this.anim = { from: cloneCamera(this.camera), to: c, t0: performance.now(), dur: 450 };
    else { this.anim = null; this.camera = c; }
    this.invalidate();
  }

  private frameOptions(w: number, h: number): FrameOptions {
    return {
      width: w, height: h, camera: this.camera, style: this.style, look: this.lookState, explicitPreset: this.explicit, quality: "interactive",
      supersample: 1, selection: this.selection, sectionBox: this.box, sectionPlane: this.plane, northAngle: this.northAngle, sunOverride: this.sun,
      sunLight: this.sun ? this.sunLight : null, weather: this.weather, fog: this.fog, water: this.water, time: performance.now() / 1000, particles: true,
      aoOverride: this.aoOverride, custom: this.custom,
    };
  }

  private tick() {
    this.raf = 0;
    const now = performance.now();
    let more = false;
    if (this.anim) {
      const t = Math.min(1, (now - this.anim.t0) / this.anim.dur);
      this.camera = interpolate(this.anim.from, this.anim.to, t);
      if (t >= 1) { this.camera = this.anim.to; this.anim = null; } else more = true;
      this.dirty = true;
    }
    if (!this.dragging && (Math.abs(this.inertia[0]) > 0.05 || Math.abs(this.inertia[1]) > 0.05)) {
      this.camera = orbit(this.camera, this.inertia[0], this.inertia[1]);
      this.inertia = [this.inertia[0] * 0.88, this.inertia[1] * 0.88];
      this.dirty = true; more = true;
    }
    if (this.nav) { this.walkStep(now); more = true; }
    if (this.extras.tick(now)) { more = true; this.dirty = true; }
    if (this.continuousEffects()) { more = true; this.dirty = true; }
    if (this.dirty) this.drawNow();
    if (more) this.raf = requestAnimationFrame(() => this.tick());
  }

  private drawNow() {
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    const w = Math.max(1, Math.round(this.el.clientWidth * dpr)), h = Math.max(1, Math.round(this.el.clientHeight * dpr));
    if (this.canvas.width !== w || this.canvas.height !== h) { this.canvas.width = w; this.canvas.height = h; }
    const t0 = performance.now();
    this.renderer.render(this.scene, this.frameOptions(w, h));
    this.lastFrameMs = performance.now() - t0;
    this.dirty = false;
    this.cube?.sync(this.camera);
    this.extras?.draw();
  }

  /** Falling rain / snow and moving water need a frame every refresh. */
  private continuousEffects(): boolean {
    const st = this.style;
    if (st === "Hidden Line" || st === "Wireframe") return false;
    if (this.weather?.particles && this.weather.intensity > 0) return true;
    if (["Realistic", "Shaded", "Shaded with Edges"].includes(st) && this.scene.meshes.some((m) => (this.water ? this.water.has(m.mat.name) : m.mat.name.toLowerCase() === "water"))) return true;
    return false;
  }

  // MARK: picking

  private ray(x: number, y: number): { a: V3; b: V3 } {
    const w = Math.max(1, this.el.clientWidth), h = Math.max(1, this.el.clientHeight);
    const [near, far] = zRange(this.camera, this.center(), this.radius(), 2000);
    const vp = mul(projMatrix(this.camera, w / h, near, far), viewMatrix(this.camera));
    const inv = invert(vp);
    const nx = (x / w) * 2 - 1, ny = 1 - (y / h) * 2;
    const p0 = transform(inv, [nx, ny, -1]), p1 = transform(inv, [nx, ny, 1]);
    return { a: [p0[0] / p0[3], p0[1] / p0[3], p0[2] / p0[3]], b: [p1[0] / p1[3], p1[1] / p1[3], p1[2] / p1[3]] };
  }

  private rayHit(x: number, y: number): { mesh: MeshGPU; point: V3 } | null {
    const r = this.ray(x, y);
    const a = scale(r.a, 1 / UNIT), b = scale(r.b, 1 / UNIT);
    const hit = this.scene.firstHit(a, b, (m) => this.clipAllows(m));
    if (!hit) return null;
    return { mesh: hit.mesh, point: add(a, scale(sub(b, a), hit.t)) };
  }

  private clipAllows(m: MeshGPU): boolean {
    const b = this.box;
    if (!b?.on) return true;
    return !(m.max[0] < b.min[0] || m.min[0] > b.max[0] || m.max[1] < b.min[1] || m.min[1] > b.max[1] || m.max[2] < b.min[2] || m.min[2] > b.max[2]);
  }

  // MARK: input (SCNView camera control: drag orbits, right / middle / Shift-drag pans, wheel dollies)

  private dragging = false;
  private bindInput() {
    const el = this.el;
    let down: { x: number; y: number; button: number; shift: boolean; ctrl: boolean } | null = null;
    let last = { x: 0, y: 0, t: 0 };
    el.addEventListener("contextmenu", (e) => e.preventDefault());
    let toolDrag = false;
    const local = (e: PointerEvent): [number, number] => { const r = el.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    el.addEventListener("pointerdown", (e) => {
      if ((e.target as HTMLElement).closest(".v3d-bar, .v3d-side, .v3d-cube, .v3d-toolbar, .v3d-menu")) return;
      el.focus();
      el.setPointerCapture(e.pointerId);
      const [lx, ly] = local(e);
      toolDrag = !this.nav && this.extras.pointerDown(lx, ly, e);
      if (toolDrag) { down = { x: e.clientX, y: e.clientY, button: e.button, shift: e.shiftKey, ctrl: false }; return; }
      down = { x: e.clientX, y: e.clientY, button: e.button, shift: e.shiftKey, ctrl: e.ctrlKey || e.metaKey };
      last = { x: e.clientX, y: e.clientY, t: performance.now() };
      this.inertia = [0, 0];
      this.anim = null;
      this.dragging = true;
    });
    el.addEventListener("pointermove", (e) => {
      if (!down) return;
      if (toolDrag) { const [lx, ly] = local(e); this.extras.pointerMove(lx, ly, e); return; }
      const dx = e.clientX - last.x, dy = e.clientY - last.y;
      const now = performance.now();
      last = { x: e.clientX, y: e.clientY, t: now };
      if (this.nav) { this.lookAround(dx, dy); return; }
      if (down.button === 2 || down.button === 1 || down.shift) this.camera = pan(this.camera, dx, dy, el.clientHeight);
      else { this.camera = orbit(this.camera, dx, dy); this.inertia = [dx, dy]; }
      this.invalidate();
    });
    const up = (e: PointerEvent) => {
      if (!down) return;
      const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
      if (toolDrag) { const [lx, ly] = local(e); this.extras.pointerUp(lx, ly, e, false); toolDrag = false; down = null; this.dragging = false; this.invalidate(); return; }
      if (moved < 4 && down.button === 0 && !this.nav && e.ctrlKey) {
        const [lx, ly] = local(e);
        if (this.extras.subObjectPick(lx, ly)) { down = null; this.dragging = false; return; }
      }
      if (moved < 4 && down.button === 0 && !this.nav && this.extras.measureActive) {
        const [lx, ly] = local(e); this.extras.pointerUp(lx, ly, e, true); down = null; this.dragging = false; this.invalidate(); return;
      }
      const idle = performance.now() - last.t;
      if (idle > 60) this.inertia = [0, 0];
      this.dragging = false;
      if (moved >= 4) this.cameraChanged();
      if (moved < 4 && down.button === 0 && !this.nav) {
        const r = el.getBoundingClientRect();
        const id = this.pickAt(e.clientX - r.left, e.clientY - r.top);
        const extend = e.shiftKey || e.ctrlKey || e.metaKey;
        if (this.opts.onPick) this.opts.onPick(id, extend);
        else {
          if (id) { if (extend) { this.selection.has(id) ? this.selection.delete(id) : this.selection.add(id); } else this.selection = new Set([id]); }
          else if (!extend) this.selection = new Set();
        }
        this.inertia = [0, 0];
      }
      down = null;
      this.invalidate();
    };
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
    el.addEventListener("wheel", (e) => {
      e.preventDefault();
      const d = -(e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY) * 0.25;
      if (this.nav) { this.camera = { ...this.camera, eye: add(this.camera.eye, scale(norm(sub(this.camera.target, this.camera.eye)), d * 0.03)), target: add(this.camera.target, scale(norm(sub(this.camera.target, this.camera.eye)), d * 0.03)) }; this.invalidate(); return; }
      this.camera = zoom(this.camera, d);
      this.cameraChanged();
      this.invalidate();
    }, { passive: false });
    el.addEventListener("dblclick", (e) => {
      // Double-click: centre the orbit on the surface point (SCNView behaviour).
      const r = el.getBoundingClientRect();
      const p = this.pointAt(e.clientX - r.left, e.clientY - r.top);
      if (!p || this.nav) return;
      const t = scale(p, UNIT);
      this.moveTo({ ...cloneCamera(this.camera), target: t, eye: add(t, sub(this.camera.eye, this.camera.target)) }, true);
    });
    el.addEventListener("keydown", (e) => {
      if (!this.nav) return;
      if (e.key === "Escape") { this.stopNavigation(); e.preventDefault(); return; }
      this.shift = e.shiftKey;
      this.keys.add(e.key.toLowerCase());
      e.preventDefault();
    });
    el.addEventListener("keyup", (e) => { this.shift = e.shiftKey; this.keys.delete(e.key.toLowerCase()); });
    el.addEventListener("blur", () => this.keys.clear());
  }

  // MARK: walk / fly / look (Viewport3DController.walkStep, WalkPhysics)

  private applyLook() {
    const f: V3 = [Math.cos(this.pitch) * Math.cos(this.yaw), Math.cos(this.pitch) * Math.sin(this.yaw), Math.sin(this.pitch)];
    this.camera = { ...this.camera, target: add(this.camera.eye, f), up: [0, 0, 1] };
  }

  private lookAround(dx: number, dy: number) {
    this.yaw -= dx * 0.005;
    this.pitch = clamp(this.pitch - dy * 0.005, -1.4, 1.4);
    this.applyLook();
    this.invalidate();
  }

  private collide(from: V3, to: V3): number | null {
    const a = scale(from, 1 / UNIT), b = scale(to, 1 / UNIT);
    const h = this.scene.firstHit(a, b, (m) => !m.foliage);
    return h ? h.t * len(sub(to, from)) : null;
  }

  private walkStep(now: number) {
    const dt = Math.min(0.1, (now - this.lastTick) / 1000);
    this.lastTick = now;
    const k = this.keys, mode = this.nav!;
    const eyeH = 1.6, radius = 0.3, step = 0.45;
    let eye = this.camera.eye;
    if (k.has("arrowleft")) { this.yaw += 1.8 * dt; this.applyLook(); }
    if (k.has("arrowright")) { this.yaw -= 1.8 * dt; this.applyLook(); }
    if (mode === "look") { if (k.has("arrowup")) { this.pitch = Math.min(1.4, this.pitch + 1.2 * dt); this.applyLook(); } if (k.has("arrowdown")) { this.pitch = Math.max(-1.4, this.pitch - 1.2 * dt); this.applyLook(); } this.invalidate(); return; }
    const speed = (this.shift ? 4.5 : 1.5) * dt * (mode === "fly" ? 2.5 : 1);
    const fwd: V3 = mode === "fly" ? [Math.cos(this.pitch) * Math.cos(this.yaw), Math.cos(this.pitch) * Math.sin(this.yaw), Math.sin(this.pitch)] : [Math.cos(this.yaw), Math.sin(this.yaw), 0];
    const right: V3 = [Math.sin(this.yaw), -Math.cos(this.yaw), 0];
    let m: V3 = [0, 0, 0];
    if (k.has("w") || k.has("arrowup")) m = add(m, fwd);
    if (k.has("s") || k.has("arrowdown")) m = sub(m, fwd);
    if (k.has("d")) m = add(m, right);
    if (k.has("a")) m = sub(m, right);
    if (k.has("e")) m = add(m, [0, 0, 1]);
    if (k.has("q")) m = sub(m, [0, 0, 1]);
    if (mode === "fly" || m[2] !== 0) {
      if (m[0] || m[1] || m[2]) { eye = add(eye, scale(m, speed)); this.camera = { ...this.camera, eye }; this.applyLook(); this.invalidate(); }
      return;
    }
    // Walk: horizontal move with wall collision (full, else slide along X or Y), then floors / stairs and gravity.
    const mv = scale(m, speed);
    const feet = eye[2] - eyeH;
    const l0 = Math.hypot(mv[0], mv[1]);
    let pos: V3 = [...eye] as V3;
    if (l0 > 1e-9) {
      for (const t of [[mv[0], mv[1]], [mv[0], 0], [0, mv[1]]] as [number, number][]) {
        const l = Math.hypot(t[0], t[1]);
        if (l < 1e-9) continue;
        const d = [t[0] / l, t[1] / l];
        let blocked = false;
        for (const hgt of [feet + step + 0.05, feet + 1.0, eye[2] - 0.05]) {
          const hit = this.collide([eye[0], eye[1], hgt], [eye[0] + d[0] * (l + radius), eye[1] + d[1] * (l + radius), hgt]);
          if (hit != null && hit < l + radius) { blocked = true; break; }
        }
        if (!blocked) { pos[0] += t[0]; pos[1] += t[1]; break; }
      }
    }
    const start: V3 = [pos[0], pos[1], feet + step];
    const d = this.collide(start, [pos[0], pos[1], feet - 60]);
    if (d != null) {
      const floor = start[2] - d;
      if (floor >= feet - 0.01) { pos[2] = floor + eyeH; this.fall = 0; }
      else {
        this.fall += 9.81 * dt;
        pos[2] = Math.max(floor, feet - this.fall * dt) + eyeH;
        if (pos[2] - eyeH <= floor + 1e-6) this.fall = 0;
      }
    } else { this.fall = 0; }
    if (pos.some((v, i) => v !== eye[i])) { this.camera = { ...this.camera, eye: pos }; this.applyLook(); this.invalidate(); }
  }

  // MARK: overlay (Viewport3DView.overlay)

  private icon(sf: string, fallback: string): Element {
    if (this.opts.icon) return this.opts.icon(sf, 14);
    const s = document.createElement("span");
    s.className = "v3d-glyph";
    s.textContent = fallback;
    return s;
  }

  private pills = new Map<string, HTMLButtonElement>();
  private styleBtn: HTMLButtonElement | null = null;
  private projIcon: HTMLSpanElement | null = null;

  private buildOverlay() {
    const right = div("v3d-right");
    const bar = div("v3d-bar");
    this.bar = bar;
    const pill = (key: string, help: string, sf: string, glyph: string, act: (b: HTMLButtonElement) => void) => {
      const b = document.createElement("button");
      b.className = "v3d-pill";
      b.title = help;
      b.append(this.icon(sf, glyph));
      b.addEventListener("click", (e) => { e.stopPropagation(); act(b); });
      this.pills.set(key, b);
      bar.append(b);
      return b;
    };
    const sep = () => bar.append(div("v3d-sep"));
    pill("top", "Top", "square.grid.3x3.topleft.filled", "T", () => this.setView("Top"));
    pill("front", "Front", "square.bottomhalf.filled", "F", () => this.setView("Front"));
    pill("right", "Right", "square.righthalf.filled", "R", () => this.setView("Right"));
    pill("iso", "Iso", "cube", "◇", () => this.setView("Iso"));
    sep();
    const proj = pill("proj", "Perspective (click for orthographic)", "perspective", "⟁", () => this.toggleProjection());
    this.projIcon = document.createElement("span");
    proj.replaceChildren(this.projIcon);
    pill("extents", "Zoom extents", "arrow.up.left.and.arrow.down.right", "⤢", () => this.zoomExtents());
    pill("walk", "Walk mode (WASD)", "figure.walk", "🚶", () => (this.nav ? this.stopNavigation() : this.startNavigation("walk")));
    pill("orbitsel", "Orbit around the selection (zooms to it)", "scope", "◎", () => {
      if (!this.orbitSelection()) this.extras.host.print?.("Select building elements to orbit around.");
    });
    sep();
    pill("box", "Section box", "cube.transparent", "▣", () => this.toggleSectionPanel());
    pill("sun", "Sun study", "sun.max", "☀", () => this.toggleSunPanel());
    pill("plane", "Clipping plane (SECTIONPLANE)", "square.split.diagonal", "◩", () => this.toggleClipPanel());
    pill("cube", "Hide the view cube", "cube", "▦", () => { this.showCube = !this.showCube; this.refreshOverlay(); });
    pill("cams", "Saved cameras", "camera", "🎥", (b) => this.camerasMenu(b));
    pill("levels", "Isolate or explode levels in 3D (LEVELVIEW3D), field of view (FOV)", "square.stack.3d.up", "≡", (b) => this.levelMenu(b));
    sep();
    const sb = document.createElement("button");
    sb.className = "v3d-style";
    sb.addEventListener("click", (e) => { e.stopPropagation(); this.menu(sb, VISUAL_STYLES.map((s) => ({ title: s, checked: s === this.style, action: () => { this.setStyle(s); this.opts.onStyle?.(s); } }))); });
    this.styleBtn = sb;
    bar.append(sb);
    right.append(bar);
    this.cube = new ViewCube(96);
    this.cube.onPick = (d) => this.setViewDirection(d);
    right.append(this.cube.canvas, this.panelHost);
    this.el.append(right);
    this.refreshOverlay();
  }

  private refreshOverlay() {
    if (!this.bar) return;
    const set = (k: string, active: boolean, title?: string) => { const b = this.pills.get(k); if (!b) return; b.classList.toggle("on", active); if (title) b.title = title; };
    set("proj", false, this.camera.ortho ? "Orthographic (click for perspective)" : "Perspective (click for orthographic)");
    if (this.projIcon) this.projIcon.replaceChildren(this.icon(this.camera.ortho ? "square.stack.3d.up" : "perspective", this.camera.ortho ? "▭" : "⟁"));
    set("walk", !!this.nav, this.nav ? "Exit walk mode" : "Walk mode (WASD)");
    set("box", this.sectionPanel || !!this.box?.on);
    set("plane", this.clipPanel || !!this.plane?.on);
    set("sun", this.sunPanelOpen);
    set("cube", this.showCube, this.showCube ? "Hide the view cube" : "Show the view cube");
    set("levels", !!this.extras?.levelViewActive);
    const lv = this.pills.get("levels");
    if (lv) lv.replaceChildren(this.icon(this.extras?.levelViewActive ? "square.stack.3d.up.fill" : "square.stack.3d.up", "≡"));
    if (this.cube) this.cube.canvas.hidden = !this.showCube;
    if (this.styleBtn) this.styleBtn.textContent = this.customName ?? this.style;
  }

  private menu(anchor: HTMLElement, items: MenuItem[]) {
    document.querySelector(".v3d-menu")?.remove();
    const m = div("v3d-menu");
    for (const it of items) {
      if (it.divider) { m.append(div("v3d-mdiv")); continue; }
      if (it.header) { const h = div("v3d-mhead"); h.textContent = it.title ?? ""; m.append(h); continue; }
      const b = document.createElement("button");
      if (it.sub) b.className = "sub";
      b.textContent = (it.checked ? "✓ " : "") + (it.title ?? "");
      b.disabled = !!it.disabled;
      b.addEventListener("click", (e) => { e.stopPropagation(); m.remove(); it.action?.(); });
      m.append(b);
    }
    const r = anchor.getBoundingClientRect(), hr = this.el.getBoundingClientRect();
    m.style.top = r.bottom - hr.top + 4 + "px";
    m.style.right = Math.max(4, hr.right - r.right) + "px";
    this.el.append(m);
    setTimeout(() => document.addEventListener("click", () => m.remove(), { once: true }));
  }

  /** CamerasMenu: Save Current Camera…, the saved cameras, Delete ▸. */
  private camerasMenu(anchor: HTMLElement) {
    const save = async () => {
      const h = this.extras.host;
      if (h.onSaveCamera) { h.onSaveCamera(cloneCamera(this.camera)); return; }
      // No engine: the Save Camera sheet keeps the camera in the view.
      const name = await this.extras.askCameraName(`Camera ${this.cameras.length + 1}`);
      if (!name) return;
      const c = this.camera, mm = (v: V3) => v.map((x) => x / UNIT) as V3;
      this.setCameras([...this.cameras.filter((x) => x.name.toLowerCase() !== name.toLowerCase()), { name, eye: mm(c.eye), target: mm(c.target), fov: c.fov, orthographic: c.ortho }]);
    };
    const items: MenuItem[] = [{ title: "Save Current Camera…", action: () => { void save(); } }];
    if (this.cameras.length) {
      items.push({ divider: true });
      for (const c of this.cameras) items.push({ title: c.name, action: () => this.applyNamedCamera(c.name) });
      items.push({ divider: true }, { header: true, title: "Delete" });
      for (const c of this.cameras) items.push({ title: c.name, sub: true, action: () => { const h = this.extras.host; if (h.onDeleteCamera) h.onDeleteCamera(c.name); else this.setCameras(this.cameras.filter((x) => x.name !== c.name)); } });
    }
    this.menu(anchor, items);
  }

  /** Level3DMenu: All levels / Only <level>, explode gaps, field of view. */
  private levelMenu(anchor: HTMLElement) {
    const x = this.extras;
    const items: MenuItem[] = [{ title: "All levels", checked: x.isolate == null, action: () => this.levelView(null, x.explodeGap) }];
    for (const l of [...x.levels].sort((a, b) => a.elevation - b.elevation)) items.push({ title: `Only ${l.name}`, checked: x.isolate === l.id, action: () => this.levelView(l.id, x.explodeGap) });
    items.push({ divider: true });
    for (const g of [0, 1500, 3000, 6000]) items.push({ title: g === 0 ? "Not exploded" : `Explode levels by ${fmt(g / 1000, 1)} m`, checked: Math.abs(x.explodeGap - g) < 1e-6, action: () => this.levelView(x.isolate, g) });
    items.push({ divider: true });
    for (const f of [24, 35, 45, 60, 90]) items.push({ title: `Field of view ${f}° (${Math.round(FieldOfView.focalLength(f))} mm)`, checked: Math.abs(this.camera.fov - f) < 0.5, action: () => this.setFieldOfView(f) });
    this.menu(anchor, items);
  }

  private levelView(isolate: number | null, gapMM: number) { this.extras.setLevelView(isolate, gapMM); this.refreshOverlay(); }

  // Section box panel: six sliders cutting the model live (SectionBoxPanel).
  private toggleSectionPanel(show = !this.sectionPanel) {
    this.sectionPanel = show;
    this.panelHost.querySelector(".v3d-boxpanel")?.remove();
    if (this.sectionPanel) {
      if (!this.box) this.box = { on: true, ...this.around(this.scene.min, this.scene.max) };
      this.box.on = true;
      this.panelHost.append(this.sectionBoxPanel());
      this.opts.onSectionBox?.(this.box);
    }
    this.refreshOverlay(); this.invalidate();
  }

  /** Shows the section box panel (SECTIONBOX Panel). */
  showSectionBoxPanel() { if (!this.sectionPanel) this.toggleSectionPanel(true); }

  private around(lo: V3, hi: V3): { min: V3; max: V3 } {
    const pad = Math.max(100, len(sub(hi, lo)) * 0.02);
    return { min: sub(lo, [pad, pad, pad]), max: add(hi, [pad, pad, pad]) };
  }

  private sectionBoxPanel(): HTMLElement {
    const p = div("v3d-panel v3d-boxpanel");
    const head = div("v3d-phead");
    const title = document.createElement("b"); title.textContent = "Section Box";
    const on = document.createElement("input"); on.type = "checkbox"; on.className = "v3d-switch"; on.checked = !!this.box?.on; on.title = "On";
    on.addEventListener("change", () => { if (this.box) { this.box.on = on.checked; this.opts.onSectionBox?.(this.box); this.refreshOverlay(); this.invalidate(); } });
    const close = document.createElement("button"); close.textContent = "✕"; close.title = "Close";
    close.addEventListener("click", () => this.toggleSectionPanel(false));
    head.append(this.icon("cube.transparent", "▣"), title, on, close);
    p.append(head);
    const pad = Math.max(100, len(sub(this.scene.max, this.scene.min)) * 0.02);
    const axes: [string, number][] = [["X (east)", 0], ["Y (north)", 1], ["Z (height)", 2]];
    if (!this.scene.empty) for (const [label, k] of axes) {
      const lo = this.scene.min[k] - pad, hi = Math.max(this.scene.max[k] + pad, lo + 1);
      const l = div("v3d-small"); l.textContent = label;
      const row = div("v3d-prow");
      const a = slider(lo, hi, this.box!.min[k]), b = slider(lo, hi, this.box!.max[k]);
      a.addEventListener("input", () => { this.box!.min[k] = Math.min(+a.value, this.box!.max[k] - 10); this.invalidate(); });
      b.addEventListener("input", () => { this.box!.max[k] = Math.max(+b.value, this.box!.min[k] + 10); this.invalidate(); });
      for (const s of [a, b]) s.addEventListener("change", () => this.opts.onSectionBox?.(this.box));
      row.append(a, b);
      p.append(l, row);
    }
    const btns = div("v3d-prow");
    const btn = (t: string, help: string, f: () => void, disabled = false) => { const x = document.createElement("button"); x.className = "v3d-flat"; x.textContent = t; x.title = help; x.disabled = disabled; x.addEventListener("click", f); btns.append(x); };
    btn("Selection", "Fit the box to the selected elements", () => {
      const ms = this.scene.meshes.filter((m) => m.id != null && this.selection.has(m.id));
      if (!ms.length) return;
      const lo: V3 = [Infinity, Infinity, Infinity], hi: V3 = [-Infinity, -Infinity, -Infinity];
      for (const m of ms) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], m.min[k]); hi[k] = Math.max(hi[k], m.max[k]); }
      this.box = { on: true, ...this.around(lo, hi) };
      this.rebuildBoxPanel();
    }, this.selection.size === 0);
    btn("Level", "Cut above the current level", () => {
      const l = this.extras.levels.find((x) => x.id === this.extras.currentLevel);
      if (!l || !this.box) return;
      this.box.min[2] = Math.max(this.scene.min[2] - 100, l.elevation - 50);
      this.box.max[2] = l.elevation + (l.height ?? 3000) * 0.9;
      this.box.on = true;
      this.rebuildBoxPanel();
    });
    btn("Reset", "", () => { this.box = { on: true, ...this.around(this.scene.min, this.scene.max) }; this.rebuildBoxPanel(); });
    p.append(btns);
    return p;
  }

  private rebuildBoxPanel() {
    this.panelHost.querySelector(".v3d-boxpanel")?.replaceWith(this.sectionBoxPanel());
    this.opts.onSectionBox?.(this.box);
    this.refreshOverlay();
    this.invalidate();
  }

  // Sun study (SunStudyPanel): day and time sliders place the sun at the site; play animates the day.
  private toggleSunPanel(show = !this.sunPanelOpen) {
    const cur = this.panelHost.querySelector(".v3d-sunpanel");
    if (!show) {
      cur?.remove(); this.sunPanelOpen = false; clearInterval(this.sunPlaying); this.sunPlaying = 0;
      this.sun = null; this.sunLight = null; this.refreshOverlay(); this.invalidate(); return;
    }
    if (cur) return;
    this.sunPanelOpen = true;
    const site = this.extras.site;
    let day = site.day ?? 172, hour = site.hour ?? 15;
    const p = div("v3d-panel v3d-sunpanel");
    const head = div("v3d-phead");
    const t = document.createElement("b"); t.textContent = "Sun Study";
    const play = document.createElement("button"); play.title = "Animate the day"; play.append(this.icon("play.fill", "▶"));
    const close = document.createElement("button"); close.textContent = "✕"; close.title = "Close";
    close.addEventListener("click", () => this.toggleSunPanel(false));
    head.append(this.icon("sun.max", "☀"), t, play, close);
    const date = div("v3d-mono");
    const r1 = div("v3d-prow"), r2 = div("v3d-prow");
    const l1 = document.createElement("span"), l2 = document.createElement("span");
    l1.textContent = "Day"; l2.textContent = "Time"; l1.className = l2.className = "v3d-lbl";
    const ds = slider(1, 365, day), hs = slider(4, 22, hour);
    ds.step = "1";
    const sunTxt = div("v3d-small");
    const save = () => this.extras.host.onVariable?.("SUNSTUDY", `${day},${fmt(hour, 2)}`);
    const apply = () => {
      const s = sunStudy(day, hour, site.latitude, site.longitude);
      this.sun = sunDirection(s.altitude, s.azimuth, this.northAngle);
      this.sunLight = { intensity: s.intensity, color: s.color };
      const txt = sunStudyText(day, hour, site.latitude, site.longitude);
      date.textContent = txt.date; sunTxt.textContent = txt.sun;
      this.extras.site = { ...site, day, hour };
      this.invalidate();
    };
    ds.addEventListener("input", () => { day = Math.round(+ds.value); apply(); });
    hs.addEventListener("input", () => { hour = +hs.value; apply(); });
    ds.addEventListener("change", save); hs.addEventListener("change", save);
    const presets = div("v3d-prow");
    for (const [n, d] of [["Mar 21", 80], ["Jun 21", 172], ["Sep 23", 266], ["Dec 21", 355]] as [string, number][]) {
      const b = document.createElement("button"); b.className = "v3d-flat"; b.textContent = n;
      b.addEventListener("click", () => { day = d; ds.value = String(d); apply(); save(); });
      presets.append(b);
    }
    play.addEventListener("click", () => {
      if (this.sunPlaying) { clearInterval(this.sunPlaying); this.sunPlaying = 0; play.replaceChildren(this.icon("play.fill", "▶")); play.title = "Animate the day"; save(); return; }
      if (hour >= 21.5) hour = 5;
      play.replaceChildren(this.icon("pause.fill", "❚❚")); play.title = "Pause";
      this.sunPlaying = setInterval(() => {
        hour += 0.05;
        if (hour >= 21.5) { hour = 21.5; clearInterval(this.sunPlaying); this.sunPlaying = 0; play.replaceChildren(this.icon("play.fill", "▶")); save(); }
        hs.value = String(hour); apply();
      }, 1000 / 30) as unknown as number;
    });
    r1.append(l1, ds); r2.append(l2, hs);
    p.append(head, date, r1, r2, sunTxt, presets);
    this.panelHost.append(p);
    if (this.style === "Wireframe" || this.style === "Hidden Line" || this.style === "X-Ray") { this.setStyle("Shaded"); this.opts.onStyle?.("Shaded"); }
    apply();
    this.refreshOverlay();
  }

  /** Opens the sun study panel (SUNSTUDY). */
  showSunStudy() { this.toggleSunPanel(true); }

  // Clipping plane panel (ClipPlanePanel): orientation, offset slider, on, flip, level, remove.
  private toggleClipPanel(show = !this.clipPanel) {
    this.clipPanel = show;
    this.panelHost.querySelector(".v3d-clippanel")?.remove();
    if (show) this.panelHost.append(this.clipPlanePanel());
    this.refreshOverlay(); this.invalidate();
  }

  private clipPlanePanel(): HTMLElement {
    type Orient = "Horizontal" | "Along X" | "Along Y";
    const normalOf = (o: Orient, flipped: boolean): V3 => { const n: V3 = o === "Horizontal" ? [0, 0, 1] : o === "Along X" ? [0, 1, 0] : [1, 0, 0]; return flipped ? scale(n, -1) : n; };
    const axisOf = (o: Orient) => (o === "Horizontal" ? 2 : o === "Along X" ? 1 : 0);
    let orientation: Orient = "Horizontal", offset = 1200, flipped = false, on = true;
    const range = (): [number, number] => {
      if (this.scene.empty) return [0, 10000];
      const k = axisOf(orientation);
      const lo = this.scene.min[k] - 100, hi = this.scene.max[k] + 100;
      return [lo, Math.max(hi, lo + 1)];
    };
    const mid = () => { const r = range(); return (r[0] + r[1]) / 2; };
    const current = this.plane;
    let formFound = false;
    if (current) for (const o of ["Horizontal", "Along X", "Along Y"] as Orient[]) {
      const n = normalOf(o, false), k = axisOf(o);
      const d = current.normal[0] * n[0] + current.normal[1] * n[1] + current.normal[2] * n[2];
      if (Math.abs(Math.abs(d) - 1) < 1e-6) { orientation = o; offset = current.point[k]; flipped = d < 0; on = current.on; formFound = true; break; }
    }
    const planeNow = (): SectionPlane => { const pt: V3 = [0, 0, 0]; pt[axisOf(orientation)] = offset; return { on, point: pt, normal: normalOf(orientation, flipped) }; };
    const live = () => { this.plane = planeNow(); this.refreshOverlay(); this.invalidate(); };
    const commit = () => this.opts.onSectionPlane?.(planeNow());
    const p = div("v3d-panel v3d-clippanel");
    const head = div("v3d-phead");
    const t = document.createElement("b"); t.textContent = "Clipping Plane";
    const tog = document.createElement("input"); tog.type = "checkbox"; tog.className = "v3d-switch"; tog.checked = on; tog.title = "On";
    tog.addEventListener("change", () => { on = tog.checked; live(); commit(); });
    const close = document.createElement("button"); close.textContent = "✕"; close.title = "Close";
    close.addEventListener("click", () => this.toggleClipPanel(false));
    head.append(this.icon("square.split.diagonal", "◩"), t, tog, close);
    const seg = div("v3d-segp");
    const segBtns: HTMLButtonElement[] = [];
    const row = div("v3d-prow");
    let sl = slider(range()[0], range()[1], offset);
    const val = document.createElement("span"); val.className = "v3d-mono v3d-val";
    const syncSlider = () => { const r = range(); sl.min = String(r[0]); sl.max = String(r[1]); sl.value = String(offset); val.textContent = fmt(offset, 0); segBtns.forEach((b) => b.classList.toggle("on", b.textContent === orientation)); };
    for (const o of ["Horizontal", "Along X", "Along Y"] as Orient[]) {
      const b = document.createElement("button"); b.textContent = o;
      b.addEventListener("click", () => { orientation = o; offset = mid(); syncSlider(); live(); commit(); });
      segBtns.push(b); seg.append(b);
    }
    sl.addEventListener("input", () => { offset = +sl.value; val.textContent = fmt(offset, 0); live(); });
    sl.addEventListener("change", commit);
    row.append(sl, val);
    const btns = div("v3d-prow");
    const btn = (label: string, help: string, f: () => void) => { const x = document.createElement("button"); x.className = "v3d-flat"; x.textContent = label; if (help) x.title = help; x.addEventListener("click", f); btns.append(x); };
    btn("Flip", "", () => { flipped = !flipped; live(); commit(); });
    btn("Level", "Horizontal cut 1.2 m above the current level", () => {
      orientation = "Horizontal"; flipped = false; on = true; tog.checked = true;
      const l = this.extras.levels.find((x) => x.id === this.extras.currentLevel);
      offset = (l?.elevation ?? 0) + 1200;
      syncSlider(); live(); commit();
    });
    btn("Remove", "", () => { on = false; this.plane = null; this.opts.onSectionPlane?.(null); this.toggleClipPanel(false); });
    p.append(head, seg, row, btns);
    if (!formFound) { offset = mid(); }
    syncSlider();
    if (!formFound) { live(); commit(); }
    return p;
  }

  /** Opens the clipping plane panel (CLIPPLANES). */
  showClipPlanePanel() { if (!this.clipPanel) this.toggleClipPanel(true); }
}

interface MenuItem { title?: string; checked?: boolean; action?: () => void; divider?: boolean; header?: boolean; sub?: boolean; disabled?: boolean }

// MARK: helpers

/** PNG / JPEG through a canvas; TIFF written directly (uncompressed RGBA, the Mac's TIFF export). */
export async function encodeImage(px: { width: number; height: number; data: Uint8Array }, format: "PNG" | "JPEG" | "TIFF"): Promise<Blob> {
  if (format === "TIFF") return new Blob([tiff(px).buffer as ArrayBuffer], { type: "image/tiff" });
  const cv = document.createElement("canvas");
  cv.width = px.width; cv.height = px.height;
  const ctx = cv.getContext("2d")!;
  ctx.putImageData(new ImageData(new Uint8ClampedArray(px.data), px.width, px.height), 0, 0);
  const type = format === "JPEG" ? "image/jpeg" : "image/png";
  return await new Promise<Blob>((res, rej) => cv.toBlob((b) => (b ? res(b) : rej(new Error("image encoding failed"))), type, 0.9));
}

function tiff(px: { width: number; height: number; data: Uint8Array }): Uint8Array {
  const n = 11, ifd = 8, extra = ifd + 2 + n * 12 + 4, bps = extra, data = bps + 8;
  const buf = new Uint8Array(data + px.data.length);
  const v = new DataView(buf.buffer);
  buf[0] = 0x49; buf[1] = 0x49; v.setUint16(2, 42, true); v.setUint32(4, ifd, true);
  v.setUint16(ifd, n, true);
  const tags: [number, number, number, number][] = [
    [256, 4, 1, px.width], [257, 4, 1, px.height], [258, 3, 4, bps], [259, 3, 1, 1], [262, 3, 1, 2], [273, 4, 1, data],
    [277, 3, 1, 4], [278, 4, 1, px.height], [279, 4, 1, px.data.length], [284, 3, 1, 1], [338, 3, 1, 2],
  ];
  tags.forEach(([tag, type, count, value], i) => {
    const o = ifd + 2 + i * 12;
    v.setUint16(o, tag, true); v.setUint16(o + 2, type, true); v.setUint32(o + 4, count, true);
    if (type === 3 && count === 1) v.setUint16(o + 8, value, true); else v.setUint32(o + 8, value, true);
  });
  v.setUint32(ifd + 2 + n * 12, 0, true);
  for (let i = 0; i < 4; i++) v.setUint16(bps + i * 2, 8, true);
  buf.set(px.data, data);
  return buf;
}

function div(cls: string): HTMLDivElement { const d = document.createElement("div"); d.className = cls; return d; }
function slider(lo: number, hi: number, v: number): HTMLInputElement {
  const s = document.createElement("input");
  s.type = "range"; s.min = String(lo); s.max = String(hi); s.step = "any"; s.value = String(v);
  return s;
}

let styled = false;
function injectStyles() {
  if (styled || typeof document === "undefined") return;
  styled = true;
  const css = document.createElement("style");
  css.textContent = `
.v3d{position:relative;width:100%;height:100%;overflow:hidden;background:#1a1b1d;outline:none;user-select:none;touch-action:none}
.v3d-canvas{position:absolute;inset:0;width:100%;height:100%;display:block}
.v3d-right{position:absolute;top:10px;right:10px;display:flex;flex-direction:column;align-items:flex-end;gap:8px;pointer-events:none}
.v3d-right>*{pointer-events:auto}
.v3d-bar{display:flex;align-items:center;gap:2px;padding:4px 6px;border-radius:999px;background:#26272B;border:1px solid rgba(255,255,255,.08);color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif}
.v3d-pill{width:24px;height:22px;display:grid;place-items:center;border:0;background:transparent;color:#E6E6E6;border-radius:6px;cursor:default;padding:0}
.v3d-pill:hover{background:rgba(255,255,255,.07)}
.v3d-pill.on{color:#F5C518}
.v3d-glyph{font-size:12px;line-height:1}
.v3d-sep{width:1px;height:16px;background:rgba(255,255,255,.09);margin:0 3px}
.v3d-style{border:0;background:transparent;color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif;padding:0 6px;cursor:default}
.v3d-style::after{content:" ⌄";color:#9A9BA1}
.v3d-cube{width:96px;height:96px}
.v3d-side{display:flex;flex-direction:column;gap:8px;align-items:flex-end}
.v3d-panel{width:280px;box-sizing:border-box;padding:10px;border-radius:8px;background:#26272B;border:1px solid rgba(255,255,255,.09);color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif;display:flex;flex-direction:column;gap:6px}
.v3d-phead{display:flex;align-items:center;gap:6px}.v3d-phead b{flex:1;font-weight:600}.v3d-phead .v3d-glyph{color:#F5C518}
.v3d-phead button{border:0;background:transparent;color:#9A9BA1;display:grid;place-items:center}
.v3d-prow{display:flex;align-items:center;gap:4px}.v3d-prow .v3d-lbl{color:#9A9BA1;width:34px}.v3d-prow .v3d-val{width:60px;text-align:right}
.v3d-prow input[type=range]{flex:1;accent-color:#F5C518;min-width:0}
.v3d-flat{border:1px solid rgba(255,255,255,.09);background:#2F3035;color:#E6E6E6;border-radius:5px;padding:2px 8px;font:11px -apple-system,"Segoe UI",system-ui,sans-serif}
.v3d-flat:hover{background:#3a3b40}
.v3d-menu{position:absolute;z-index:20;min-width:160px;padding:4px;border-radius:6px;background:#26272B;border:1px solid rgba(255,255,255,.12);box-shadow:0 8px 24px rgba(0,0,0,.45);display:flex;flex-direction:column}
.v3d-menu button{text-align:left;border:0;background:transparent;color:#E6E6E6;font:12px -apple-system,"Segoe UI",system-ui,sans-serif;padding:4px 10px;border-radius:4px}
.v3d-menu button:hover{background:#F5C518;color:#1E1F22}
.v3d-hint{position:absolute;left:50%;bottom:12px;transform:translateX(-50%);padding:6px 12px;border-radius:999px;background:#26272B;color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif;white-space:nowrap}
`;
  document.head.append(css);
}
