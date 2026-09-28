// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Frame renderer of the 3D view and the photographic renderer: shadow map, HDR scene (sky, ground, model, glass,
// edges), ambient occlusion, bloom and the camera response, following Scene3DBuilder.configureEnvironment /
// material, BeautyLighting.apply / configure and BeautyRenderer.snapshot (supersampling) of the Mac app.

import { GL, Program, Target, target, msTarget, depthTarget, disposeTarget, texture2D, bytesTexture } from "./gl";
import * as S from "./shaders";
import { SceneModel, MeshGPU } from "./scene";
import { Look, VisualStyle, styleEdges, SKETCH_PAPER, ACCENT, sunDirection } from "./look";
import { V3, M4, mul, invert, lookAt, ortho, perspective, linearRGB, kelvin, norm, sub, len, toLinear, ident, hex } from "./math";
import { Weather, isVegetation, seasonTint, isWater } from "./effects";
import { CameraState, viewMatrix, projMatrix, zRange } from "./camera";
import { orientBillboards } from "./billboards";
import { skyPixels, irradianceSH, horizonColor, toSK, groundTexture, gridTexture, GROUND_TILE_METRES } from "./sky";

export const UNIT = 0.001; // model millimetres → world metres

export interface SectionBox { on: boolean; min: V3; max: V3 }      // model mm
export interface SectionPlane { on: boolean; point: V3; normal: V3 } // model mm

export interface FrameOptions {
  width: number;
  height: number;
  camera: CameraState;
  style: VisualStyle;
  look: Look;
  /** A preset was chosen in the drawing (RENDERPRESET): haze, meadow ground, preset camera response, scaled lights. */
  explicitPreset: boolean;
  quality: "interactive" | "final";
  /** Supersampling factor of final renders (the frame is drawn k× larger, then filtered down). */
  supersample?: number;
  selection?: Set<string>;
  sectionBox?: SectionBox | null;
  sectionPlane?: SectionPlane | null;
  northAngle?: number;
  /** Overrides: sun direction (towards the sun, model axes) for sun studies; ambient occlusion from the drawing. */
  sunOverride?: V3 | null;
  /** Sun study light (applySun): intensity (SceneKit / 1000) and sRGB colour, with `sunOverride`. */
  sunLight?: { intensity: number; color: V3 } | null;
  aoOverride?: { intensity: number; radius: number } | null;
  background?: "sky" | "white" | "transparent";
  /** WEATHER of the drawing (snow cover, wet surfaces, season tint, haze, rain / snow particles). */
  weather?: Weather | null;
  /** FOG of the drawing (FogSettings): distances in model mm. */
  fog?: { on: boolean; start: number; end: number; color: string; density: number } | null;
  /** Water materials (MATWATER); null = the material named "Water". */
  water?: Set<string> | null;
  /** Seconds, for water waves and falling rain / snow. */
  time?: number;
  /** Draw precipitation particles (viewport; renders freeze them at `time`). */
  particles?: boolean;
  /** Hide the ground plane (transparent image export). */
  hideGround?: boolean;
  /** Keep the previous frame's sun shadow map (panorama faces: same sun, same scene). */
  reuseShadow?: boolean;
  /** Clay model (RenderEngine.applyClay): one matte white material (glass keeps its transparency). */
  clay?: boolean;
  /** Depth of field (Render window): focus distance in metres (0 = the model centre) and the f-stop. */
  dof?: { focus: number; fStop: number } | null;
  /** Environment image (HDRI File or the Render window's environment maps): linear RGBA, row 0 at the top,
   *  equirectangular like the sky; replaces the sky as image-based light and background. */
  envImage?: { key: string; width: number; height: number; data: Float32Array } | null;
  /** Lighting environment intensity override (Render window: environmentIntensity). */
  envIntensity?: number | null;
  /** Render window without a photographic preset (RenderEngine.makeScene, view3d/render-scene.ts): sun (/1000, linear colour),
   *  ambient light (SceneKit intensity, sRGB colour), environment intensity, shadow quality and the plain HDR camera. */
  renderScene?: {
    sunIntensity: number; sunColor: V3; ambient: number; ambientColor: V3; envIntensity: number;
    shadows: boolean; shadowRadius: number; shadowAlpha: number; shadowMap: number; shadowSamples: number;
    exposure: number; bloom: number; bloomThreshold: number; ao: number; aoRadius: number; vignette: number; vignettePower: number;
  } | null;
  /** No vignetting (the 90° cube faces of 360° panoramas). */
  noVignette?: boolean;
  /** Custom visual style (VISUALSTYLES, Viewport3DView.custom): edges, edge colour (sRGB), face opacity, shadows, background (sRGB). */
  custom?: { edges: boolean | null; edgeColor: V3 | null; faceOpacity: number | null; shadows: boolean | null; background: V3 | null } | null;
}

const IDENT = ident();

interface EnvState { key: string; tex: WebGLTexture; sh: Float32Array; maxLod: number; width: number }

interface StyleSetup {
  mode: number;               // shader mode 0..3
  drawFaces: boolean;
  sunI: number; sunColor: V3; ambient: V3; shadows: boolean; shadowAlpha: number; shadowRadius: number;
  env: boolean; envIntensity: number; skyBackground: boolean; top: V3; bottom: V3;
  hdr: boolean; exposure: number; white: number; bloom: number; bloomThreshold: number; saturation: number; contrast: number;
  ao: number; aoRadius: number; vignette: number; vignettePower: number;
  fog: boolean; groundKind: "meadow" | "grid"; groundBase: V3; groundLine: V3; groundMode: number; groundOpacity: number;
  lightScale: number;
  /** Shadow map size and soft-shadow samples (null: 8192 / 32 for renders, 4096 / 12 interactive). */
  shadowMapSize?: number | null; shadowSamples?: number | null;
}

const SUN_DEFAULT: V3 = norm([-0.45, -0.7, 0.75]);

export class Renderer {
  readonly gl: GL;
  private mesh: Program; private shadow: Program; private line: Program; private sky: Program; private ssao: Program;
  private blur: Program; private bright: Program; private composite: Program; private down: Program; private copy: Program;
  private dof: Program;
  private dofT: Target | null = null;
  private iesTex: WebGLTexture | null = null;
  private iesKey = "";
  private env: EnvState | null = null;
  private meadow: WebGLTexture | null = null;
  private grids = new Map<string, WebGLTexture>();
  private groundVAO: WebGLVertexArrayObject;
  private boxVAO: WebGLVertexArrayObject; private boxBuf: WebGLBuffer;
  private emptyVAO: WebGLVertexArrayObject;
  private whiteTex: WebGLTexture;
  private shadowT: Target | null = null;
  private lastShadow: { key: string; mat: M4 } | null = null;
  /** Spot / IES light shadow maps (2 × 2 atlas) and, per tile, its light's index in `sortedLights` and light matrix. */
  private spotT: Target | null = null;
  private spotShadows: { light: number; mat: M4 }[] = [];
  private targets: { key: string; ms: Target | null; hdr: Target; ao: Target; ao2: Target; b1: Target; b2: Target; ldr: Target } | null = null;
  readonly maxSamples: number;
  readonly maxSize: number;
  /** Calibration of SceneKit's photometric units against this shader (sun, IBL, lights); see test/view3d. */
  static SUN_SCALE = 0.8;
  /** SceneKit HDR camera: displayed = 0.21 × exposed scene radiance (sky, lit surfaces and emission alike), measured on
   *  the Mac renders (build/renders) against the known sky radiance and the textures' albedo. */
  static SCENE_SCALE = 0.245;
  /** Placed lights and fixtures: lumens / 1000 × LIGHT_SCALE, SceneKit attenuation, measured on the Mac renders. */
  static LIGHT_SCALE = 180;
  static ENV_SCALE = 1.0;
  /** SceneKit's SSAO darkens the ambient / image-based diffuse light, not the sun (measured on the Mac renders). */
  static AO_INDIRECT = true;
  /** Scale of the SSAO intensity (SceneKit screenSpaceAmbientOcclusionIntensity), measured on the Mac renders. */
  static AO_SCALE = 1;
  /** Multiplier of normal-map strength (calibration probe). */
  static NORMAL_SCALE = 1;
  /** Slope-scaled shadow bias covers soft-shadow kernels up to this radius in texels (measured on the Mac renders). */
  static SLOPE_TEXELS = 5;
  /** Share of the sun's (moon's) deferred shadow that darkens the placed lights too, measured on the Mac Night render:
   *  the bollards' moon shadows show inside their own light pools, and the soffit and entrance wall under the canopy
   *  are dimmer than undarkened lamps give (0: lamps never shadowed; 1: the whole pixel, as SceneKit's pass). */
  static LAMP_SUN_SHADOW = 0.7;
  /** Spot and IES lights cast shadows like the Mac's (SceneExtras.swift SceneLights.node: castsShadow, 8 samples,
   *  radius 3, shadow colour alpha 0.5; SCNLight zNear / zFar 1 / 100 m), each on its own light. At most SPOT_SHADOWS,
   *  the spots nearest the camera target; point lights cast none (as on the Mac). */
  static SPOT_SHADOWS = 4;
  static SPOT_SHADOW_ALPHA = 0.5;
  static SPOT_SHADOW_RADIUS = 3;
  static SPOT_NEAR = 1;
  static SPOT_FAR = 100;
  /** Diffuse share of the image-based light (SceneKit lightingEnvironment), measured on the Mac renders. */
  static ENV_DIFFUSE = 1.0;
  /** Image-based diffuse on vertical faces relative to up-facing ones (mixed by the normal's Z; SceneKit lights walls
   *  less than the cosine-weighted irradiance of its environment gives), measured on the Mac renders (render-match-r4). */
  static ENV_SIDE = 0.8;
  /** The same for the image-based specular of opaque dielectrics (the cedar cladding kept a grey sky sheen). */
  static ENV_SIDE_SPECULAR = 0.5;
  /** Roughness maps: texel ^ ROUGH_GAMMA (SceneKit reads 8-bit roughness images through their sRGB curve). */
  static ROUGH_GAMMA = 1.0;
  /** sRGB value the camera contrast pivots about (with CONTRAST_SCALE; calibration probe). */
  static CONTRAST_PIVOT = 0.5;
  /** Scale of the preset contrast (SCNCamera.contrast). The Mac renders show no contrast change with the HDR camera:
   *  applying it crushed the shadows (lawn, paving, the whole Night preset ~25 % too dark), so it is 0 (render-match). */
  static CONTRAST_SCALE = 0;
  /** Scale of the preset vignette (SceneKit vignettingIntensity), measured on the Mac renders. */
  static VIGNETTE_SCALE = 1;
  /** Bloom intensity and blur radius relative to SceneKit's bloomIntensity / bloomBlurRadius (measured on the Mac renders:
   *  at the full radius the soffit lamps and wall washers of the Night preset spread halos twice as wide as the Mac's). */
  static BLOOM_SCALE = 1;
  static BLOOM_RADIUS = 0.5;
  /** SceneKit's multiply colour of textured materials: false = its sRGB components scale the linear texture as they are
   *  (measured on the Mac renders: dark tints — lawn, cedar, hedge — would otherwise render too dark). */
  static MULTIPLY_LINEAR = false;

  constructor(gl: GL) {
    this.gl = gl;
    gl.getExtension("EXT_color_buffer_float");
    gl.getExtension("EXT_color_buffer_half_float");
    gl.getExtension("OES_texture_float_linear");
    this.maxSamples = Math.min(4, gl.getParameter(gl.MAX_SAMPLES) || 0);
    this.maxSize = Math.min(gl.getParameter(gl.MAX_TEXTURE_SIZE), gl.getParameter(gl.MAX_RENDERBUFFER_SIZE));
    this.mesh = new Program(gl, S.meshVS, S.meshFS, "mesh");
    this.shadow = new Program(gl, S.shadowVS, S.shadowFS, "shadow");
    this.line = new Program(gl, S.lineVS, S.lineFS, "line");
    this.sky = new Program(gl, S.quadVS, S.skyFS, "sky");
    this.ssao = new Program(gl, S.quadVS, S.ssaoFS, "ssao");
    this.blur = new Program(gl, S.quadVS, S.blurFS, "blur");
    this.bright = new Program(gl, S.quadVS, S.brightFS, "bright");
    this.composite = new Program(gl, S.quadVS, S.compositeFS, "composite");
    this.down = new Program(gl, S.quadVS, S.downsampleFS, "downsample");
    this.copy = new Program(gl, S.quadVS, S.copyFS, "copy");
    this.dof = new Program(gl, S.quadVS, S.dofFS, "dof");
    this.emptyVAO = gl.createVertexArray()!;
    // Ground: a unit quad scaled in the vertex data per frame (positions in model mm, uv in tiles).
    this.groundVAO = gl.createVertexArray()!;
    this.whiteTex = texture2D(gl, 1, 1, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));
    this.boxVAO = gl.createVertexArray()!;
    this.boxBuf = gl.createBuffer()!;
    gl.bindVertexArray(this.boxVAO);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.boxBuf);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
    gl.bindVertexArray(null);
  }

  // MARK: style set-up (Scene3DBuilder.configureEnvironment + applyCameraEffects + BeautyLighting)

  private setup(o: FrameOptions): StyleSetup {
    const s0 = this.setupStyle(o);
    if (o.sunOverride && o.sunLight && s0.sunI > 0) { s0.sunI = o.sunLight.intensity; s0.sunColor = linearRGB(o.sunLight.color); s0.shadows = s0.drawFaces && s0.mode !== 3 ? true : s0.shadows; }
    const rs = o.renderScene;
    if (rs && o.style === "Realistic") {
      // RenderEngine.makeScene: the sun of the render date, 260 ambient, the environment map and a fresh HDR camera
      // (white point 1, no saturation / contrast grading); a preset of the drawing keeps its haze, meadow and lamps.
      s0.sunI = rs.sunIntensity; s0.sunColor = [...rs.sunColor] as V3;
      s0.ambient = linearRGB(rs.ambientColor).map((v) => (v * rs.ambient) / 1000) as V3;
      s0.envIntensity = rs.envIntensity;
      s0.shadows = rs.shadows && s0.drawFaces; s0.shadowRadius = rs.shadowRadius; s0.shadowAlpha = rs.shadowAlpha;
      s0.shadowMapSize = rs.shadowMap; s0.shadowSamples = rs.shadowSamples;
      s0.exposure = rs.exposure; s0.white = 1; s0.saturation = 1; s0.contrast = 0;
      s0.bloom = rs.bloom; s0.bloomThreshold = rs.bloomThreshold; s0.ao = rs.ao; s0.aoRadius = rs.aoRadius;
      s0.vignette = rs.vignette; s0.vignettePower = rs.vignettePower;
      if (o.aoOverride) { s0.ao = Math.max(s0.ao, o.aoOverride.intensity); s0.aoRadius = o.aoOverride.radius; }
    }
    // Panorama cube faces: RenderEngine.panorama turns the camera's vignetting off.
    if (o.noVignette) s0.vignette = 0;
    const cs = o.custom;
    if (cs && cs.shadows !== null) s0.shadows = cs.shadows && s0.drawFaces;
    if (cs && cs.background) { s0.top = linearRGB(cs.background); s0.bottom = linearRGB(cs.background); s0.skyBackground = false; }
    return s0;
  }

  private setupStyle(o: FrameOptions): StyleSetup {
    const st = o.style, look = o.look, preset = o.explicitPreset;
    const warm = linearRGB([1, 0.97, 0.92]);
    const dark: [V3, V3] = [[0.2, 0.215, 0.24], [0.09, 0.095, 0.105]];
    const light: [V3, V3] = [[0.98, 0.98, 0.98], [0.9, 0.9, 0.9]];
    const base: StyleSetup = {
      mode: 1, drawFaces: true, sunI: 0.9, sunColor: warm, ambient: [0.9 * 0.42, 0.9 * 0.42, 0.9 * 0.42].map(toLinear) as V3,
      shadows: false, shadowAlpha: 0.45, shadowRadius: 4, env: false, envIntensity: 0, skyBackground: false,
      top: linearRGB(dark[0]), bottom: linearRGB(dark[1]), hdr: false, exposure: 0, white: 1, bloom: 0, bloomThreshold: 1,
      saturation: 1, contrast: 0, ao: 0, aoRadius: 0.4, vignette: 0, vignettePower: 0.6, fog: false,
      groundKind: "grid", groundBase: [0.17, 0.18, 0.19], groundLine: [0.3, 0.3, 0.3], groundMode: 2, groundOpacity: 1, lightScale: 0,
    };
    // SceneKit ambient light: intensity/1000 × colour (0.9 white, sRGB).
    const amb = (i: number, c: V3 = [0.9, 0.9, 0.9]): V3 => linearRGB(c).map((v) => (v * i) / 1000) as V3;
    switch (st) {
      case "Wireframe":
        return { ...base, drawFaces: false, groundOpacity: 0.5, ambient: amb(420) };
      case "Hidden Line":
        return { ...base, mode: 3, sunI: 0, ambient: amb(1000), top: linearRGB(light[0]), bottom: linearRGB(light[1]),
          groundBase: [1, 1, 1], groundLine: [0.86, 0.86, 0.86], groundMode: 3 };
      case "Sketchy":
        return { ...base, mode: 3, sunI: 0, top: linearRGB(SKETCH_PAPER), bottom: linearRGB(SKETCH_PAPER),
          groundBase: [1, 1, 1], groundLine: [0.86, 0.86, 0.86], groundMode: 3 };
      case "Conceptual":
        return { ...base, mode: 3, ambient: amb(420) };
      case "X-Ray":
        return { ...base, mode: 2, ambient: amb(420), groundOpacity: 0.5 };
      case "Realistic": {
        const r: StyleSetup = {
          ...base, mode: 0, sunI: 1.6, sunColor: warm, ambient: amb(220), shadows: true, env: true, envIntensity: 1.05, skyBackground: true,
          hdr: true, bloom: 0.12, bloomThreshold: 0.92, ao: 0.9, aoRadius: 0.4, vignette: 0.25, vignettePower: 0.6,
          groundBase: [0.56, 0.58, 0.53], groundLine: [0.48, 0.48, 0.48], groundMode: 0, lightScale: 1,
        };
        if (preset) {
          r.sunI = look.sunIntensity / 1000; r.sunColor = [...look.sunColor] as V3;
          r.shadowAlpha = look.shadowAlpha; r.shadowRadius = look.shadowRadius;
          r.ambient = amb(look.ambient, [0.8, 0.85, 1.0]);
          r.envIntensity = look.envIntensity;
          r.exposure = look.exposure; r.white = look.whitePoint; r.bloom = look.bloom; r.bloomThreshold = look.bloomThreshold;
          r.saturation = look.saturation; r.contrast = look.contrast; r.ao = look.ao; r.aoRadius = 0.35;
          r.vignette = 0.22; r.vignettePower = 0.55;
          r.fog = true; r.groundKind = "meadow"; r.lightScale = look.artificial;
        }
        if (o.aoOverride) { r.ao = o.aoOverride.intensity; r.aoRadius = o.aoOverride.radius; }
        return r;
      }
      default: { // Shaded, Shaded with Edges
        const r = { ...base, mode: 1, sunI: 0.9, ambient: amb(420), shadows: true, ao: 0.35 };
        if (o.aoOverride) { r.ao = o.aoOverride.intensity; r.aoRadius = o.aoOverride.radius; }
        return r;
      }
    }
  }

  // MARK: environment (procedural HDR sky)

  private environment(look: Look, sun: V3, quality: "interactive" | "final", preset: boolean): EnvState {
    const sky = preset ? look.sky : "daylight";
    const width = quality === "final" ? 2048 : 1024;
    const sunSK = toSK(norm(sun));
    const key = `${sky}|${width}|${sunSK.map((v) => v.toFixed(3)).join(",")}`;
    if (this.env?.key === key) return this.env;
    const gl = this.gl;
    const img = skyPixels(sky, sunSK, width);
    if (this.env) gl.deleteTexture(this.env.tex);
    const tex = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    // Mip chain filtered on the CPU (box, wrapping horizontally): rough reflections sample coarser levels.
    let w = img.width, h = img.height, data = img.data, level = 0;
    for (;;) {
      gl.texImage2D(gl.TEXTURE_2D, level, gl.RGBA16F, w, h, 0, gl.RGBA, gl.FLOAT, data);
      if (w <= 8 || h <= 4) break;
      const nw = w >> 1, nh = h >> 1, nd = new Float32Array(nw * nh * 4);
      for (let y = 0; y < nh; y++) for (let x = 0; x < nw; x++) for (let c = 0; c < 4; c++) {
        const s = (xx: number, yy: number) => data[(yy * w + xx) * 4 + c];
        nd[(y * nw + x) * 4 + c] = (s(2 * x, 2 * y) + s(2 * x + 1, 2 * y) + s(2 * x, 2 * y + 1) + s(2 * x + 1, 2 * y + 1)) / 4;
      }
      w = nw; h = nh; data = nd; level++;
    }
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, level);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const sh = irradianceSH(skyPixels(sky, sunSK, 256));
    this.env = { key, tex, sh, maxLod: Math.max(1, level - 1), width };
    return this.env;
  }

  /** An environment image as the lighting environment and background (HDRI File, environment maps). */
  private environmentImage(img: { key: string; width: number; height: number; data: Float32Array }): EnvState {
    const key = "image|" + img.key;
    if (this.env?.key === key) return this.env;
    const gl = this.gl;
    if (this.env) gl.deleteTexture(this.env.tex);
    const tex = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    let w = img.width, h = img.height, data = img.data, level = 0;
    const small: { w: number; h: number; d: Float32Array }[] = [];
    for (;;) {
      gl.texImage2D(gl.TEXTURE_2D, level, gl.RGBA16F, w, h, 0, gl.RGBA, gl.FLOAT, data);
      if (w <= 256 && small.length === 0) small.push({ w, h, d: data });
      if (w <= 8 || h <= 4) break;
      const nw = w >> 1, nh = h >> 1, nd = new Float32Array(nw * nh * 4);
      for (let y = 0; y < nh; y++) for (let x = 0; x < nw; x++) for (let c = 0; c < 4; c++) {
        const q = (xx: number, yy: number) => data[(yy * w + xx) * 4 + c];
        nd[(y * nw + x) * 4 + c] = (q(2 * x, 2 * y) + q(2 * x + 1, 2 * y) + q(2 * x, 2 * y + 1) + q(2 * x + 1, 2 * y + 1)) / 4;
      }
      w = nw; h = nh; data = nd; level++;
    }
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, level);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const sm = small[0] ?? { w, h, d: data };
    const sh = irradianceSH({ width: sm.w, height: sm.h, data: sm.d, key });
    this.env = { key, tex, sh, maxLod: Math.max(1, level - 1), width: img.width };
    return this.env;
  }

  private groundTexture(s: StyleSetup): WebGLTexture {
    const gl = this.gl;
    if (s.groundKind === "meadow") {
      if (!this.meadow) { const g = groundTexture(); this.meadow = bytesTexture(gl, g.size, g.data, true, 16); }
      return this.meadow;
    }
    const key = s.groundBase.join(",") + "|" + s.groundLine.join(",");
    let t = this.grids.get(key);
    if (!t) { const g = gridTexture(s.groundBase, s.groundLine); t = bytesTexture(gl, g.size, g.data, true, 8); this.grids.set(key, t); }
    return t;
  }

  // MARK: render targets

  private ensureTargets(w: number, h: number, msaa: boolean) {
    const key = `${w}x${h}|${msaa}`;
    if (this.targets?.key === key) return this.targets;
    const gl = this.gl;
    if (this.targets) for (const t of [this.targets.ms, this.targets.hdr, this.targets.ao, this.targets.ao2, this.targets.b1, this.targets.b2, this.targets.ldr]) disposeTarget(gl, t);
    const hw = Math.max(1, w >> 1), hh = Math.max(1, h >> 1);
    this.targets = {
      key,
      ms: msaa && this.maxSamples > 1 ? msTarget(gl, w, h, this.maxSamples, true) : null,
      hdr: target(gl, w, h, { hdr: true, depth: true, mrt: true }),
      ao: target(gl, hw, hh, { hdr: false }), ao2: target(gl, hw, hh, { hdr: false }),
      b1: target(gl, hw, hh, { hdr: true }), b2: target(gl, hw, hh, { hdr: true }),
      ldr: target(gl, w, h, { hdr: false }),
    };
    return this.targets;
  }

  // MARK: frame

  /**
   * Draws a frame of `o.width × o.height` device pixels into `out` (null = the canvas). Returns the matrices used.
   * The model is `scene`; textures that are still loading are drawn with their base colour.
   */
  render(scene: SceneModel, o: FrameOptions, out: Target | null = null): { view: M4; proj: M4 } {
    const gl = this.gl;
    const W = o.width, H = o.height;
    const s = this.setup(o);
    const look = o.look;
    orientBillboards(scene, o.camera.eye.map((v) => v / UNIT) as V3);
    const center: V3 = scene.center.map((v) => v * UNIT) as V3;
    const radius = scene.radius * UNIT;
    const ext = Math.max(scene.max[0] - scene.min[0], scene.max[1] - scene.min[1]) * UNIT;
    const groundSize = s.groundKind === "meadow" ? Math.max(1600, ext * 40) : Math.max(100, ext * 6);

    // Sun: preset direction, or the viewport default (Scene3DBuilder.setSun keeps z ≥ 0.05).
    let sun: V3 = o.sunOverride ?? (o.explicitPreset && o.style === "Realistic" ? (look.sunDirection ?? sunDirection(look.sunAltitude, look.sunAzimuth, o.northAngle ?? 0)) : SUN_DEFAULT);
    sun = norm(sun);
    if (sun[2] < 0.05) sun = norm([sun[0], sun[1], 0.05]);

    const env = s.env || s.skyBackground ? (o.envImage ? this.environmentImage(o.envImage) : this.environment(look, sun, o.quality, o.explicitPreset)) : null;
    if (o.envIntensity != null) s.envIntensity = o.envIntensity;
    // Clay with a preset: BeautyLighting brightens the lighting environment by 10 % (RenderEngine.makeScene).
    if (o.clay && o.explicitPreset && o.style === "Realistic" && !o.renderScene) s.envIntensity *= 1.1;
    const sunSK = toSK(sun);
    const fogColor: V3 = o.explicitPreset ? horizonColor(look.sky, sunSK).map((v) => Math.min(1, Math.max(0, v))) as V3 : [0, 0, 0];

    // Camera
    const aspect = W / Math.max(H, 1);
    const [near, far] = zRange(o.camera, center, radius, groundSize);
    const view = viewMatrix(o.camera);
    const proj = projMatrix(o.camera, aspect, near, far);
    const viewProj = mul(proj, view);

    // Shadow map (sun, orthographic over the scene sphere)
    const final = o.quality === "final";
    let shadowMat: M4 | null = null;
    const shadowKey = `${sun.join(",")}|${radius}|${center.join(",")}|${final}|${s.shadowMapSize ?? 0}`;
    if (o.reuseShadow && this.lastShadow && this.lastShadow.key === shadowKey && this.shadowT) {
      shadowMat = this.lastShadow.mat;
    } else if (s.shadows && s.drawFaces && !scene.empty && s.sunI > 0) {
      const size = Math.min(this.maxSize, s.shadowMapSize ?? (final ? 8192 : 4096));
      if (!this.shadowT || this.shadowT.width !== size) { disposeTarget(gl, this.shadowT); this.shadowT = depthTarget(gl, size); }
      const r = radius * 1.05;
      const eye: V3 = [center[0] + sun[0] * r * 3, center[1] + sun[1] * r * 3, center[2] + sun[2] * r * 3];
      const lv = lookAt(eye, center, Math.abs(sun[2]) > 0.99 ? [0, 1, 0] : [0, 0, 1]);
      const lp = ortho(-r, r, -r, r, r * 0.5, r * 5.5);
      shadowMat = mul(lp, lv);
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.shadowT.fb);
      gl.viewport(0, 0, size, size);
      gl.clear(gl.DEPTH_BUFFER_BIT);
      gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.depthMask(true);
      gl.disable(gl.CULL_FACE); gl.disable(gl.BLEND);
      gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(1.5, 2.0);
      const p = this.shadow.use();
      p.m4("uViewProj", shadowMat).f("uUnit", UNIT).m4("uModel", IDENT);
      this.drawCasters(p, scene, o);
      gl.disable(gl.POLYGON_OFFSET_FILL);
      this.lastShadow = { key: shadowKey, mat: shadowMat };
    }

    // Spot / IES light shadows (SceneLights.node castsShadow): perspective depth maps over each spot's cone.
    this.spotShadows = [];
    if (s.mode === 0 && s.lightScale > 0 && s.drawFaces && !scene.empty) {
      const casters = this.sortedLights(scene, o.camera).map((l, i) => ({ l, i }))
        .filter(({ l }) => l.kind === "spot" || l.kind === "ies").slice(0, Renderer.SPOT_SHADOWS);
      if (casters.length) {
        const size = Math.min(this.maxSize, final ? 4096 : 2048), tile = size / 2;
        if (!this.spotT || this.spotT.width !== size) { disposeTarget(gl, this.spotT); this.spotT = depthTarget(gl, size); }
        gl.bindFramebuffer(gl.FRAMEBUFFER, this.spotT.fb);
        gl.viewport(0, 0, size, size);
        gl.clear(gl.DEPTH_BUFFER_BIT);
        gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.depthMask(true);
        gl.disable(gl.CULL_FACE); gl.disable(gl.BLEND);
        gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(1.5, 2.0);
        const p = this.shadow.use();
        p.f("uUnit", UNIT).m4("uModel", IDENT);
        casters.forEach(({ l, i }, k) => {
          const eye = l.position.map((v) => v * UNIT) as V3;
          const t = l.target ?? [l.position[0], l.position[1], l.position[2] - 1000];
          const d = norm(sub(t as V3, l.position));
          const lv = lookAt(eye, [eye[0] + d[0], eye[1] + d[1], eye[2] + d[2]], Math.abs(d[2]) > 0.99 ? [0, 1, 0] : [0, 0, 1]);
          const beam = Math.min(Math.max(l.beam || 60, 1), 170);
          const mat = mul(perspective((beam * Math.PI) / 180, 1, Renderer.SPOT_NEAR, Renderer.SPOT_FAR), lv);
          gl.viewport((k % 2) * tile, Math.floor(k / 2) * tile, tile, tile);
          p.m4("uViewProj", mat);
          this.drawCasters(p, scene, o);
          this.spotShadows.push({ light: i, mat });
        });
        gl.disable(gl.POLYGON_OFFSET_FILL);
      }
    }

    // Scene into the HDR target
    const T = this.ensureTargets(W, H, true);
    const sceneFB = T.ms ?? T.hdr;
    gl.bindFramebuffer(gl.FRAMEBUFFER, sceneFB.fb);
    gl.viewport(0, 0, W, H);
    gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    // Only the mesh passes write the indirect-light attachment.
    const onlyColor = () => gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.NONE]);
    const bothColors = () => gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
    onlyColor();

    // Background: HDR sky (Realistic) or the style's gradient.
    gl.disable(gl.DEPTH_TEST); gl.depthMask(false); gl.disable(gl.BLEND); gl.disable(gl.CULL_FACE);
    {
      const p = this.sky.use();
      const white = o.background === "white", clear = o.background === "transparent";
      p.m4("uInvViewProj", invert(mul(proj, view)));
      p.i("uUseEnv", s.skyBackground && env && !white && !clear ? 1 : 0);
      if (env) p.tex("uEnv", 0, env.tex);
      const top = white ? [1, 1, 1] : clear ? [0, 0, 0] : s.top, bot = white ? [1, 1, 1] : clear ? [0, 0, 0] : s.bottom;
      p.v3("uTop", top).v3("uBottom", bot);
      gl.bindVertexArray(this.emptyVAO);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.depthMask(true);
    bothColors();
    const p = this.mesh.use();
    p.m4("uViewProj", viewProj).f("uUnit", UNIT).m4("uModel", IDENT);
    p.v3("uCamPos", o.camera.eye).v3("uViewDir", norm(sub(o.camera.target, o.camera.eye))).i("uOrtho", o.camera.ortho ? 1 : 0);
    p.v3("uSunDir", sun);
    const sunScale = s.mode === 0 ? Renderer.SUN_SCALE : 1;
    p.v3("uSunColor", s.sunColor.map((c) => c * s.sunI * sunScale));
    p.i("uShadows", shadowMat ? 1 : 0).f("uShadowAlpha", s.shadowAlpha).f("uLampSunShadow", Renderer.LAMP_SUN_SHADOW).f("uShadowRadius", s.shadowRadius * (this.shadowT ? this.shadowT.width / 4096 : 1))
      .i("uShadowSamples", Math.min(32, s.shadowSamples ?? (final ? 32 : 12))).f("uShadowBias", 0.0004).f("uShadowTexel", (radius * 2.1) / (this.shadowT?.width ?? 4096))
      .f("uShadowRange", radius * 1.05 * 5).f("uSlopeTexels", Renderer.SLOPE_TEXELS);
    if (shadowMat) p.m4("uShadowMat", shadowMat).tex("uShadowMap", 5, this.shadowT!.depth!);
    else p.tex("uShadowMap", 5, this.whiteTex);
    p.i("uHasEnv", s.env && env ? 1 : 0).f("uEnvIntensity", s.envIntensity * Renderer.ENV_SCALE).f("uEnvMaxLod", env ? env.maxLod : 0);
    p.tex("uEnv", 4, env ? env.tex : this.whiteTex).f("uEnvDiffuse", Renderer.ENV_DIFFUSE).f("uEnvSide", Renderer.ENV_SIDE).f("uEnvSideSpec", Renderer.ENV_SIDE_SPECULAR).f("uRoughGamma", Renderer.ROUGH_GAMMA);
    p.v3a("uSH", env ? env.sh : new Float32Array(27));
    p.v3("uAmbient", s.ambient);
    const fogOn = s.fog;
    p.f("uFog", Math.max(40, radius * 3), Math.max(450, radius * 20), 1.6, fogOn ? 1 : 0).v3("uFogColor", fogColor);
    // FogSettings (FOG) replaces the preset haze; weather haze when no explicit fog is set (not in line styles).
    const lineStyle = o.style === "Hidden Line" || o.style === "Wireframe";
    if (o.fog?.on) p.f("uFog", o.fog.start * UNIT, Math.max(o.fog.end, o.fog.start + 1) * UNIT, o.fog.density, 1).v3("uFogColor", linearRGB(hex(o.fog.color, [0.78, 0.8, 0.84])));
    else if (o.weather?.fogDistance && !lineStyle) {
      const d = o.weather.fogDistance;
      p.f("uFog", d * 0.1, d, 1, 1).v3("uFogColor", linearRGB(o.weather.kind === "Snow" ? [0.9, 0.9, 0.9] : [0.75, 0.75, 0.75]));
    }
    const wx = ["Realistic", "Shaded", "Shaded with Edges"].includes(o.style) ? o.weather : null;
    p.f("uSnow", wx?.snow ?? 0).f("uWet", wx?.wetness ?? 0).f("uTime", o.time ?? 0).i("uWater", 0);
    // Section box / plane (world metres)
    const box = o.sectionBox?.on ? o.sectionBox : null;
    const clipMin = box ? [box.min[0] * UNIT, box.min[1] * UNIT, box.min[2] * UNIT, 0] : [0, 0, 0, 0];
    const clipMax = box ? [box.max[0] * UNIT, box.max[1] * UNIT, box.max[2] * UNIT, 1] : [0, 0, 0, 0];
    const pl = o.sectionPlane?.on ? o.sectionPlane : null;
    const nn = pl ? norm(pl.normal) : [0, 0, 1];
    const planeP = pl ? [pl.point[0] * UNIT, pl.point[1] * UNIT, pl.point[2] * UNIT, 1] : [0, 0, 0, 0];
    const planeN = pl ? [nn[0], nn[1], nn[2], 1] : [0, 0, 0, 0];
    p.f("uClipMin", ...clipMin).f("uClipMax", ...clipMax).f("uPlaneP", ...planeP).f("uPlaneN", ...planeN);
    // Artificial lights (placed lights and fixtures): lumens / 1000, scaled by the preset (BeautyLighting.applyArtificial).
    this.setLights(p, scene, s.mode === 0 ? s.lightScale : 0, o.camera);
    p.v3("uHighlight", [0, 0, 0]);

    // Ground plane (drawn first, like renderingOrder −10), without the section clipping.
    if (!o.hideGround) {
      const z = scene.empty ? 0 : scene.min[2] - 3;
      const c = scene.empty ? [0, 0] : [(scene.min[0] + scene.max[0]) / 2, (scene.min[1] + scene.max[1]) / 2];
      const half = (groundSize / UNIT) / 2;
      const tile = s.groundKind === "meadow" ? GROUND_TILE_METRES * 1000 : 5000;
      this.updateGround(c[0] - half, c[1] - half, c[0] + half, c[1] + half, z, tile);
      p.f("uClipMax", 0, 0, 0, 0).f("uPlaneN", 0, 0, 0, 0).f("uSnow", 0).f("uWet", 0);
      p.i("uMode", s.groundMode).v3("uColor", [1, 1, 1]).f("uOpacity", s.groundOpacity);
      p.i("uHasTex", 1).tex("uAlbedo", 0, this.groundTexture(s)).v3("uMultiply", [1, 1, 1]);
      p.i("uHasNormal", 0).i("uHasRough", 0).f("uRoughness", s.groundKind === "meadow" ? 0.95 : 1).f("uMetalness", 0);
      p.f("uSpecular", 0).f("uShininess", 1).v3("uEmissive", [0, 0, 0]).i("uCutout", 0).f("uFoliage", 0).f("uUVScale", 1);
      p.tex("uNormalMap", 1, this.whiteTex).tex("uRoughMap", 2, this.whiteTex);
      if (s.groundOpacity < 1) { gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA); }
      gl.bindVertexArray(this.groundVAO);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      gl.disable(gl.BLEND);
      p.f("uClipMin", ...clipMin).f("uClipMax", ...clipMax).f("uPlaneP", ...planeP).f("uPlaneN", ...planeN);
      p.f("uSnow", wx?.snow ?? 0).f("uWet", wx?.wetness ?? 0);
    }

    const sel = o.selection ?? new Set<string>();
    if (s.drawFaces) {
      const opaque: MeshGPU[] = [], trans: MeshGPU[] = [];
      const xray = o.style === "X-Ray";
      for (const m of scene.meshes) if (!m.hidden) (xray || this.isTransparent(m, o) ? trans : opaque).push(m);
      for (const m of opaque) this.drawMesh(p, scene, m, o, s, sel);
      // Section plane caps (constant dark red, SectionPlane.capsName).
      if (scene.capVAO && o.sectionPlane?.on && o.style !== "Wireframe") {
        p.m4("uModel", IDENT).f("uPlaneN", 0, 0, 0, 0);
        p.i("uMode", 3).v3("uColor", linearRGB(scene.capColor)).f("uOpacity", 1).i("uHasTex", 0).i("uHasNormal", 0).i("uHasRough", 0)
          .v3("uEmissive", [0, 0, 0]).i("uCutout", 0).f("uFoliage", 0).v3("uHighlight", [0, 0, 0]).f("uSnow", 0).f("uWet", 0).i("uWater", 0)
          .tex("uAlbedo", 0, this.whiteTex).tex("uNormalMap", 1, this.whiteTex).tex("uRoughMap", 2, this.whiteTex);
        gl.bindVertexArray(scene.capVAO);
        gl.drawArrays(gl.TRIANGLES, 0, scene.capCount);
        p.f("uPlaneN", ...planeN).f("uSnow", wx?.snow ?? 0).f("uWet", wx?.wetness ?? 0);
      }
      // Transparent surfaces back to front.
      const eyeMM = o.camera.eye.map((v) => v / UNIT) as V3;
      trans.sort((a, b) => dist2(b, eyeMM) - dist2(a, eyeMM));
      gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      for (const m of trans) {
        gl.depthMask(!xray && o.style === "Realistic");
        this.drawMesh(p, scene, m, o, s, sel);
      }
      gl.depthMask(true); gl.disable(gl.BLEND);
    }

    // Edges
    onlyColor();
    const e0 = styleEdges(o.style);
    const e = o.custom ? { ...e0, show: o.custom.edges ?? e0.show, color: o.custom.edgeColor ?? e0.color } : e0;
    if (e.show) this.drawEdges(scene, o, viewProj, e, sel, clipMin, clipMax, planeP, planeN);
    else if (sel.size) this.drawEdges(scene, o, viewProj, { show: true, color: ACCENT, alpha: 1, depthTest: true }, sel, clipMin, clipMax, planeP, planeN, true);
    if (box) this.drawBox(box, viewProj);
    if (o.particles !== false && o.weather?.particles && !lineStyle && o.style !== "X-Ray") this.drawParticles(scene, o, viewProj);

    // Resolve MSAA
    if (T.ms) {
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, T.ms.fb);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, T.hdr.fb);
      gl.readBuffer(gl.COLOR_ATTACHMENT0);
      gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.NONE]);
      gl.blitFramebuffer(0, 0, W, H, 0, 0, W, H, gl.COLOR_BUFFER_BIT, gl.LINEAR);
      gl.readBuffer(gl.COLOR_ATTACHMENT1);
      gl.drawBuffers([gl.NONE, gl.COLOR_ATTACHMENT1]);
      gl.blitFramebuffer(0, 0, W, H, 0, 0, W, H, gl.COLOR_BUFFER_BIT, gl.LINEAR);
      gl.readBuffer(gl.COLOR_ATTACHMENT0);
      gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
      gl.blitFramebuffer(0, 0, W, H, 0, 0, W, H, gl.DEPTH_BUFFER_BIT, gl.NEAREST);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
    }
    gl.disable(gl.DEPTH_TEST); gl.depthMask(false);
    gl.bindVertexArray(this.emptyVAO);

    // Ambient occlusion (half resolution, blurred)
    const hw = T.ao.width, hh = T.ao.height;
    const aoOn = s.ao > 0 && s.drawFaces && o.style !== "X-Ray";
    if (aoOn) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, T.ao.fb);
      gl.viewport(0, 0, hw, hh);
      const q = this.ssao.use();
      q.tex("uDepth", 0, T.hdr.depth!).m4("uInvProj", invert(proj)).m4("uProj", proj).f("uRadius", s.aoRadius).f("uTexel", 1 / W, 1 / H);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      this.blurPass(T.ao, T.ao2, 1 / hw, 0, 2);
      this.blurPass(T.ao2, T.ao, 0, 1 / hh, 2);
    }
    // Bloom (after exposure, above the threshold)
    const bloomOn = s.hdr && s.bloom > 0;
    if (bloomOn) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, T.b1.fb);
      gl.viewport(0, 0, hw, hh);
      this.bright.use().tex("uTex", 0, T.hdr.color!).f("uExposure", s.exposure).f("uSceneScale", s.hdr ? Renderer.SCENE_SCALE : 1).f("uThreshold", s.bloomThreshold);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      // SceneKit bloomBlurRadius 10 points (× supersampling in final renders), at half resolution.
      const sigma = Math.max(1, (10 * (o.supersample ?? 1) * Renderer.BLOOM_RADIUS) / 2 / 2);
      this.blurPass(T.b1, T.b2, 1 / hw, 0, sigma);
      this.blurPass(T.b2, T.b1, 0, 1 / hh, sigma);
    }
    // Depth of field on the exposed HDR frame (SceneKit applies it before the camera response).
    let hdrColor = T.hdr.color!;
    if (o.dof && s.drawFaces && !o.camera.ortho) {
      if (!this.dofT || this.dofT.width !== W || this.dofT.height !== H) { disposeTarget(gl, this.dofT); this.dofT = target(gl, W, H, { hdr: true }); }
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.dofT.fb);
      gl.viewport(0, 0, W, H);
      const fovR = (o.camera.fov * Math.PI) / 180;
      const focal = 0.012 / Math.tan(fovR / 2);
      const focus = o.dof.focus > 0 ? o.dof.focus : Math.max(0.1, len(sub(center, o.camera.eye)));
      const fStop = Math.max(0.5, o.dof.fStop);
      const pxPerM = H / 0.024;
      const maxCoC = Math.max(2, Math.min(24 * (o.supersample ?? 1), H * 0.03));
      const q = this.dof.use();
      q.tex("uTex", 0, T.hdr.color!).tex("uDepth", 1, T.hdr.depth!).f("uNearFar", near, far).f("uFocus", focus).f("uFocal", focal)
        .f("uAperture", focal / fStop).f("uPixelsPerM", pxPerM).f("uMaxCoC", maxCoC).f("uTexel", 1 / W, 1 / H).i("uOrtho", o.camera.ortho ? 1 : 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      hdrColor = this.dofT.color!;
    }
    // Camera response into `out` (or the canvas)
    gl.bindFramebuffer(gl.FRAMEBUFFER, out ? out.fb : null);
    gl.viewport(0, 0, W, H);
    const c = this.composite.use();
    c.tex("uHDR", 0, hdrColor).tex("uDepth", 1, T.hdr.depth!).tex("uAO", 2, T.ao.color!).tex("uBloom", 3, T.b1.color!);
    c.i("uAOIndirect", Renderer.AO_INDIRECT ? 1 : 0).tex("uIndirect", 4, T.hdr.color2!);
    c.i("uHasAO", aoOn ? 1 : 0).f("uAOIntensity", s.ao * Renderer.AO_SCALE).f("uExposure", s.exposure).f("uSceneScale", s.hdr ? Renderer.SCENE_SCALE : 1).i("uHasBloom", bloomOn ? 1 : 0).f("uBloomIntensity", s.bloom * Renderer.BLOOM_SCALE);
    c.i("uToneMap", s.hdr ? 1 : 0).f("uWhite", s.white).f("uSaturation", s.saturation).f("uContrast", s.contrast * Renderer.CONTRAST_SCALE).f("uContrastPivot", Renderer.CONTRAST_PIVOT)
      .f("uVignette", s.vignette * Renderer.VIGNETTE_SCALE).f("uVignettePower", s.vignettePower);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.bindVertexArray(null);
    return { view, proj };
  }

  private isTransparent(m: MeshGPU, o: FrameOptions): boolean {
    const t = 1 - m.mat.opacity * (o.custom?.faceOpacity ?? 1);
    if (o.style === "Realistic" && t > 0.3 && o.explicitPreset && o.look.windowGlow > 0) return false; // lit windows are opaque
    return t > 0;
  }

  private blurPass(src: Target, dst: Target, dx: number, dy: number, sigma: number) {
    const gl = this.gl;
    gl.bindFramebuffer(gl.FRAMEBUFFER, dst.fb);
    gl.viewport(0, 0, dst.width, dst.height);
    this.blur.use().tex("uTex", 0, src.color!).f("uDir", dx, dy).f("uSigma", sigma);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  private groundKey = "";
  private groundBuf: WebGLBuffer | null = null;
  private updateGround(x0: number, y0: number, x1: number, y1: number, z: number, tile: number) {
    const key = [x0, y0, x1, y1, z, tile].join(",");
    if (key === this.groundKey) return;
    this.groundKey = key;
    const gl = this.gl;
    // Interleaved position (mm), normal, uv (tiles, from the world origin so the pattern stays put).
    const v = (x: number, y: number) => [x, y, z, 0, 0, 1, x / tile, -y / tile];
    const data = new Float32Array([...v(x0, y0), ...v(x1, y0), ...v(x1, y1), ...v(x0, y0), ...v(x1, y1), ...v(x0, y1)]);
    if (!this.groundBuf) this.groundBuf = gl.createBuffer();
    gl.bindVertexArray(this.groundVAO);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.groundBuf);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 32, 0);
    gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 3, gl.FLOAT, false, 32, 12);
    gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 2, gl.FLOAT, false, 32, 24);
    gl.bindVertexArray(null);
  }

  /** Opaque shadow casters into the bound depth target (shadow program in use: sun and spot shadow maps). */
  private drawCasters(p: Program, scene: SceneModel, o: FrameOptions) {
    for (const m of scene.meshes) {
      if (m.transparent || m.hidden) continue;
      const leaf = m.foliage && !(o.clay && o.style === "Realistic");
      const tex = leaf || m.kind === "billboard" ? scene.texturesFor(m.mat, false) : null;
      p.f("uFoliage", leaf ? 1 : 0).f("uUVScale", 1000 / Math.max(m.mat.textureScale, 1));
      const cut = (leaf || m.kind === "billboard") && !!tex?.albedo;
      p.i("uCutout", cut ? (m.kind === "billboard" ? 2 : 1) : 0).tex("uAlbedo", 0, cut ? tex!.albedo! : this.whiteTex);
      const mult = multiplyTint(m.mat.color);
      p.v3("uMultiply", mult);
      this.drawTriangles(p, m);
    }
  }

  /** Placed lights and fixtures in shader order: at most 16, the ones nearest the camera target. */
  private sortedLights(scene: SceneModel, cam: CameraState) {
    const lights = scene.lights.slice();
    const tgt = cam.target.map((v) => v / UNIT) as V3;
    lights.sort((a, b) => len(sub(a.position, tgt)) - len(sub(b.position, tgt)));
    return lights.slice(0, 16);
  }

  private setLights(p: Program, scene: SceneModel, scale: number, cam: CameraState) {
    const lights = scale > 0 ? this.sortedLights(scene, cam) : [];
    const n = Math.min(16, lights.length);
    const pos = new Float32Array(64), col = new Float32Array(64), dir = new Float32Array(64), inner = new Float32Array(16);
    const iesRows: (Float32Array | null)[] = new Array(16).fill(null);
    for (let i = 0; i < n; i++) {
      const l = lights[i];
      const end = Math.max(3, Math.sqrt(Math.max(l.lumens, 1)) / 4);
      pos.set([l.position[0] * UNIT, l.position[1] * UNIT, l.position[2] * UNIT, end], i * 4);
      const k = kelvin(l.cct);
      const I = (l.lumens / 1000) * scale * Renderer.LIGHT_SCALE;
      const prof = l.kind === "ies" ? l.iesProfile : undefined;
      const kind = l.kind === "point" ? 0 : l.kind === "area" || l.kind === "line" ? 2 : prof ? 3 : 1;
      col.set([k[0] * I, k[1] * I, k[2] * I, kind], i * 4);
      if (prof) iesRows[i] = iesRow(prof);
      const t = l.target ?? [l.position[0], l.position[1], l.position[2] - 1000];
      const d = norm(sub(t as V3, l.position));
      const outer = Math.cos(((l.beam || 60) * Math.PI) / 360), inn = Math.cos(((l.beam || 60) * 0.7 * Math.PI) / 360);
      dir.set([d[0], d[1], d[2], outer], i * 4);
      inner[i] = inn;
    }
    p.i("uNumLights", n);
    const gl = this.gl;
    const L = (nm: string) => p.loc(nm);
    gl.uniform4fv(L("uLightPos[0]"), pos); gl.uniform4fv(L("uLightColor[0]"), col); gl.uniform4fv(L("uLightDir[0]"), dir);
    gl.uniform1fv(L("uLightInner[0]"), inner);
    // IES distributions: one 32-sample row per light (relative candela, 0° = the aiming direction … 180°).
    const table = new Float32Array(32 * 16).fill(1);
    iesRows.forEach((r, i) => { if (r) table.set(r, i * 32); });
    const key = iesRows.some(Boolean) ? Array.from(table, (v) => v.toFixed(3)).join(",") : "flat";
    // Texture unit 6 is the IES table's own: binding on another unit would replace that unit's texture (sky, shadows).
    gl.activeTexture(gl.TEXTURE0 + 6);
    if (!this.iesTex) {
      this.iesTex = gl.createTexture()!;
      gl.bindTexture(gl.TEXTURE_2D, this.iesTex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
    if (key !== this.iesKey) {
      this.iesKey = key;
      const half = new Uint16Array(table.length);
      for (let i = 0; i < table.length; i++) half[i] = toHalf(table[i]);
      gl.bindTexture(gl.TEXTURE_2D, this.iesTex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16F, 32, 16, 0, gl.RED, gl.HALF_FLOAT, half);
    }
    p.tex("uIES", 6, this.iesTex);
    // Spot shadows (atlas tile k: light uSpotShadowLight[k], uSpotShadowMat[k]); texture unit 7 is the atlas's own.
    const spots = scale > 0 ? this.spotShadows : [];
    const sm = new Float32Array(64), si = new Int32Array(4).fill(-1);
    spots.forEach((x, k) => { sm.set(x.mat, k * 16); si[k] = x.light; });
    p.i("uNumSpotShadows", spots.length).f("uSpotShadowAlpha", Renderer.SPOT_SHADOW_ALPHA).f("uSpotShadowRadius", Renderer.SPOT_SHADOW_RADIUS)
      .f("uSpotNearFar", Renderer.SPOT_NEAR, Renderer.SPOT_FAR);
    gl.uniformMatrix4fv(L("uSpotShadowMat[0]"), false, sm);
    gl.uniform1iv(L("uSpotShadowLight[0]"), si);
    p.tex("uSpotShadowMap", 7, spots.length && this.spotT ? this.spotT.depth! : this.whiteTex);
  }

  /** Per-mesh material of the style (Scene3DBuilder.material + BeautyLighting.enhance). */
  private drawMesh(p: Program, scene: SceneModel, m: MeshGPU, o: FrameOptions, s: StyleSetup, sel: Set<string>) {
    const gl = this.gl;
    const mat = m.mat, st = o.style, look = o.look;
    const t = Math.min(Math.max(1 - mat.opacity, 0), 0.95);
    let colorS = mat.color;
    // Season tint of untextured vegetation (WeatherSettings.apply).
    if (o.weather && o.weather.season !== "Summer" && !mat.texture && isVegetation(mat.name)) colorS = seasonTint(colorS, o.weather.season);
    let color = linearRGB(colorS);
    let opacity = 1, rough = Math.min(Math.max(mat.roughness, 0.02), 1), metal = Math.min(Math.max(mat.metalness, 0), 1);
    let emissive: V3 = [0, 0, 0];
    let useTex = false, useNormal = false, useRough = false, normalStrength = 1, cutout = false;
    let spec = mat.metalness > 0.5 ? 0.5 : 0.08, shin = Math.max(2, (1 - mat.roughness) * 60);
    let mode = s.mode;
    const tex = mat.texture && ["Shaded", "Shaded with Edges", "Realistic"].includes(st) ? scene.texturesFor(mat, st === "Realistic") : null;
    switch (st) {
      case "Hidden Line": color = linearRGB(t > 0.3 ? [0.93, 0.93, 0.93] : [1, 1, 1]); break;
      case "Sketchy": color = linearRGB(mixS(SKETCH_PAPER, colorS, 0.16)); if (t > 0.3) opacity = 0.5; break;
      case "Conceptual": color = linearRGB(mixS(colorS, [1, 1, 1], 0.18)); if (t > 0.3) opacity = 0.45; break;
      case "X-Ray": opacity = 0.22; break;
      case "Realistic": opacity = 1 - t; break;
      default: opacity = 1 - t;
    }
    if (tex?.albedo) useTex = true;
    if (st === "Realistic") {
      const maps = mat.maps ?? scene.conventionalMaps(mat.texture ?? "");
      if (tex?.normal) { useNormal = true; normalStrength = Math.max(0, maps?.normalStrength ?? 1); }
      else if (tex?.derived) { useNormal = true; normalStrength = 0.8; }
      if (tex?.rough) useRough = true;
      if (t > 0.3) {
        // Glass (BeautyLighting.enhance): green-grey tinted, reflective; lit interiors at dusk and night.
        if (o.explicitPreset || true) {
          color = linearRGB([colorS[0] * 0.25 + 0.08, colorS[1] * 0.25 + 0.1, colorS[2] * 0.25 + 0.11]);
          rough = 0.04; metal = 0.55; opacity = Math.max(0.78, 1 - t);
          useTex = false; useNormal = false; useRough = false;
          if (o.explicitPreset && look.windowGlow > 0) { emissive = linearRGB([1, 0.74, 0.45]).map((v) => v * look.windowGlow) as V3; opacity = 1; }
        }
      } else if (mat.metalness > 0.5) rough = Math.max(0.28, Math.min(mat.roughness, 0.7));
      if (m.foliage && useTex) { cutout = true; rough = 0.95; }
      if (mat.emissive > 0) emissive = linearRGB(colorS).map((v) => v * mat.emissive * (o.explicitPreset ? look.lampGlow : 1)) as V3;
    } else if (st !== "Hidden Line" && st !== "Wireframe" && mat.emissive > 0) {
      emissive = linearRGB(colorS).map((v) => v * mat.emissive) as V3;
    }
    if (st === "X-Ray") mode = 2;
    if (o.clay && st === "Realistic" && m.kind !== "billboard") {
      // RenderEngine.applyClay: matte white 0.92, roughness 0.85; transparent surfaces keep their transparency.
      color = linearRGB([0.92, 0.92, 0.92]); rough = 0.85; metal = 0; emissive = [0, 0, 0];
      opacity = t > 0.05 ? 1 - t : 1;
      // The clay material replaces the leaves' shader modifiers too: no cut-outs, no leaf lumps.
      useTex = false; useNormal = false; useRough = false; cutout = false;
    }
    const cutMode = m.kind === "billboard" ? 2 : cutout ? 1 : 0;
    p.i("uMode", mode).v3("uColor", color).f("uOpacity", opacity * (o.custom?.faceOpacity ?? 1));
    p.i("uHasTex", useTex ? 1 : 0).tex("uAlbedo", 0, useTex ? tex!.albedo! : this.whiteTex).v3("uMultiply", multiplyTint(colorS));
    p.i("uHasNormal", useNormal ? 1 : 0).tex("uNormalMap", 1, useNormal ? (tex!.normal ?? tex!.derived)! : this.whiteTex).f("uNormalStrength", normalStrength * Renderer.NORMAL_SCALE);
    p.i("uHasRough", useRough ? 1 : 0).tex("uRoughMap", 2, useRough ? tex!.rough! : this.whiteTex);
    p.f("uRoughness", rough).f("uMetalness", metal).f("uSpecular", spec).f("uShininess", shin);
    p.v3("uEmissive", emissive).i("uCutout", cutMode);
    if (cutMode === 2 && tex?.albedo) p.i("uHasTex", 1).tex("uAlbedo", 0, tex.albedo);
    p.f("uFoliage", st === "Realistic" && m.foliage && !o.clay ? 1 : 0).f("uUVScale", 1000 / Math.max(mat.textureScale, 1));
    const hl = m.id != null && sel.has(m.id);
    p.v3("uHighlight", hl ? linearRGB(ACCENT).map((v) => v * 0.55) : [0, 0, 0]);
    p.i("uWater", ["Realistic", "Shaded", "Shaded with Edges"].includes(st) && isWater(mat.name, o.water ?? null) ? 1 : 0);
    this.drawTriangles(p, m);
  }

  /** Draws a mesh with its transform, or part by part (door frame and leaves). */
  private drawTriangles(p: Program, m: MeshGPU) {
    const gl = this.gl;
    gl.bindVertexArray(m.vao);
    if (m.parts) {
      for (const part of m.parts) {
        if (!part.count) continue;
        p.m4("uModel", part.xf ?? m.xf ?? IDENT);
        gl.drawElements(gl.TRIANGLES, part.count, gl.UNSIGNED_INT, part.start * 4);
      }
    } else {
      p.m4("uModel", m.xf ?? IDENT);
      gl.drawElements(gl.TRIANGLES, m.count, gl.UNSIGNED_INT, 0);
    }
    if (m.xf || m.parts) p.m4("uModel", IDENT);
  }

  // Rain streaks and snow flakes (WeatherSettings.node: SCNParticleSystem over the model), deterministic in time.
  private particleBuf: WebGLBuffer | null = null;
  private particleVAO: WebGLVertexArrayObject | null = null;
  private drawParticles(scene: SceneModel, o: FrameOptions, viewProj: M4) {
    const gl = this.gl, w = o.weather!, pp = w.particles!;
    if (w.intensity <= 0 || pp.birthRatePerM2 <= 0) return;
    const r = Math.max(scene.radius * UNIT, 5);
    const c = scene.center.map((v) => v * UNIT);
    const area = 4 * r * r;
    const n = Math.min(Math.floor(Math.min(pp.birthRatePerM2 * area, 20000) * Math.min(pp.life, 3)), 30000);
    if (n <= 0) return;
    const top = scene.min[2] * UNIT + r * 1.2 + 10, fall = r * 1.2 + 10;
    const rain = w.kind === "Rain";
    const t = o.time ?? 0;
    const data = new Float32Array(n * (rain ? 6 : 3));
    let seed = 1234567;
    const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
    for (let i = 0; i < n; i++) {
      const x = c[0] + (rnd() * 2 - 1) * r, y = c[1] + (rnd() * 2 - 1) * r;
      const speed = pp.speed * (1 + (rnd() * 2 - 1) * 0.15);
      const drift = rain ? 0 : Math.sin(t * 0.7 + i) * 0.3;
      const z = top - ((rnd() * fall + t * speed) % fall);
      const mm = 1 / UNIT;
      if (rain) {
        const l = Math.min(pp.size * pp.stretch * speed * 0.5, 0.6);
        data.set([x * mm, y * mm, z * mm, x * mm, y * mm, (z + l) * mm], i * 6);
      } else data.set([(x + drift) * mm, y * mm, z * mm], i * 3);
    }
    if (!this.particleBuf) { this.particleBuf = gl.createBuffer(); this.particleVAO = gl.createVertexArray(); }
    gl.bindVertexArray(this.particleVAO);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.particleBuf);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
    const q = this.line.use();
    const px = Math.max(1.5, (pp.size * o.height) / Math.max(1, 2 * Math.tan((o.camera.fov * Math.PI) / 360) * Math.max(len(sub(o.camera.eye, o.camera.target)), 1)));
    q.m4("uViewProj", viewProj).m4("uModel", IDENT).f("uUnit", UNIT).f("uPointSize", Math.min(px * 3, 12)).i("uRound", rain ? 0 : 1)
      .f("uClipMax", 0, 0, 0, 0).f("uPlaneN", 0, 0, 0, 0);
    q.f("uColor", ...(rain ? [0.85, 0.85, 0.85, 0.55] : [1, 1, 1, 0.95]) as [number, number, number, number]);
    gl.enable(gl.DEPTH_TEST); gl.depthMask(false);
    gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.drawArrays(rain ? gl.LINES : gl.POINTS, 0, rain ? n * 2 : n);
    gl.disable(gl.BLEND); gl.depthMask(true);
    q.i("uRound", 0);
  }

  private drawEdges(scene: SceneModel, o: FrameOptions, viewProj: M4, e: { show?: boolean; color: V3; alpha: number; depthTest: boolean },
    sel: Set<string>, clipMin: number[], clipMax: number[], planeP: number[], planeN: number[], onlySelected = false) {
    const gl = this.gl;
    const sketch = o.style === "Sketchy";
    if (sketch) scene.ensureSketch();
    const vao = sketch ? scene.sketchVAO : scene.edgeVAO;
    if (!vao) return;
    const p = this.line.use();
    p.m4("uViewProj", viewProj).m4("uModel", IDENT).f("uUnit", UNIT).f("uPointSize", 1).i("uRound", 0)
      .f("uClipMin", ...clipMin).f("uClipMax", ...clipMax).f("uPlaneP", ...planeP).f("uPlaneN", ...planeN);
    if (e.depthTest) gl.enable(gl.DEPTH_TEST); else gl.disable(gl.DEPTH_TEST);
    gl.depthMask(false);
    gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.bindVertexArray(vao);
    const range = (m: MeshGPU) => (sketch ? scene.sketchRanges[scene.meshes.indexOf(m)] : { start: m.edgeStart, count: m.edgeCount });
    // Edges of one mesh with its transform(s); door leaves use their part ranges (sketch strokes keep the whole mesh).
    const drawOne = (m: MeshGPU) => {
      if (m.hidden) return;
      if (m.parts && !sketch) {
        for (const part of m.parts) if (part.edgeCount) { p.m4("uModel", part.xf ?? m.xf ?? IDENT); gl.drawArrays(gl.LINES, part.edgeStart, part.edgeCount); }
      } else {
        const r = range(m);
        if (!r || !r.count) return;
        p.m4("uModel", m.xf ?? IDENT);
        gl.drawArrays(gl.LINES, r.start, r.count);
      }
      p.m4("uModel", IDENT);
    };
    const perMesh = scene.anyTransformed;
    if (!onlySelected) {
      p.f("uColor", ...linearRGB(e.color), e.alpha);
      if (perMesh) for (const m of scene.meshes) drawOne(m);
      else if (sketch) gl.drawArrays(gl.LINES, 0, scene.sketchRanges.reduce((a, r) => Math.max(a, r.start + r.count), 0));
      else gl.drawArrays(gl.LINES, 0, scene.edgeCount);
    }
    if (sel.size) {
      p.f("uColor", ...linearRGB(ACCENT), 1);
      for (const m of scene.meshes) if (m.id != null && sel.has(m.id)) drawOne(m);
    }
    gl.disable(gl.BLEND); gl.depthMask(true); gl.enable(gl.DEPTH_TEST);
  }

  private drawBox(b: SectionBox, viewProj: M4) {
    const gl = this.gl;
    const [x0, y0, z0] = b.min, [x1, y1, z1] = b.max;
    const c = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]];
    const idx = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7];
    const data = new Float32Array(idx.flatMap((i) => c[i]));
    gl.bindBuffer(gl.ARRAY_BUFFER, this.boxBuf);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.DYNAMIC_DRAW);
    const p = this.line.use();
    p.m4("uViewProj", viewProj).m4("uModel", IDENT).f("uUnit", UNIT).f("uColor", ...linearRGB(ACCENT), 1).f("uClipMax", 0, 0, 0, 0).f("uPlaneN", 0, 0, 0, 0);
    gl.enable(gl.DEPTH_TEST); gl.depthMask(false);
    gl.bindVertexArray(this.boxVAO);
    gl.drawArrays(gl.LINES, 0, idx.length);
    gl.depthMask(true);
  }

  // MARK: final renders

  /**
   * Renders offscreen at `width × height` with supersampling (BeautyRenderer.snapshot: frame drawn k× larger with 4×
   * multisampling, then filtered down). Returns RGBA bytes, top row first.
   */
  renderPixels(scene: SceneModel, o: FrameOptions): { width: number; height: number; data: Uint8Array; supersample: number } {
    const gl = this.gl;
    const W = o.width, H = o.height;
    let k = Math.max(1, Math.min(o.supersample ?? 2, 4));
    while (k > 1 && Math.max(W, H) * k > Math.min(12288, this.maxSize)) k--;
    const big = target(gl, W * k, H * k, { hdr: false });
    this.render(scene, { ...o, width: W * k, height: H * k, supersample: k, quality: "final" }, big);
    const small = target(gl, W, H, { hdr: false });
    gl.bindFramebuffer(gl.FRAMEBUFFER, small.fb);
    gl.viewport(0, 0, W, H);
    gl.bindVertexArray(this.emptyVAO);
    this.down.use().tex("uTex", 0, big.color!).i("uK", k).f("uSrcTexel", 1 / (W * k), 1 / (H * k));
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    const px = new Uint8Array(W * H * 4);
    gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, px);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    disposeTarget(gl, big); disposeTarget(gl, small);
    // The big frame's targets are not needed any more.
    if (this.targets) { for (const t of [this.targets.ms, this.targets.hdr, this.targets.ao, this.targets.ao2, this.targets.b1, this.targets.b2, this.targets.ldr]) disposeTarget(gl, t); this.targets = null; }
    // Flip to top-first rows.
    const row = W * 4, out = new Uint8Array(px.length);
    for (let y = 0; y < H; y++) out.set(px.subarray((H - 1 - y) * row, (H - y) * row), y * row);
    if (o.background === "transparent") for (let i = 3; i < out.length; i += 4) out[i] = 255;
    return { width: W, height: H, data: out, supersample: k };
  }

  dispose() {
    const gl = this.gl;
    disposeTarget(gl, this.shadowT); disposeTarget(gl, this.spotT); disposeTarget(gl, this.dofT);
    if (this.targets) for (const t of [this.targets.ms, this.targets.hdr, this.targets.ao, this.targets.ao2, this.targets.b1, this.targets.b2, this.targets.ldr]) disposeTarget(gl, t);
    if (this.env) gl.deleteTexture(this.env.tex);
  }
}

/** SceneKit multiply of textured materials: the colour blended 75 % towards white (linear). */
function multiplyTint(c: V3): V3 {
  const m = mixS(c, [1, 1, 1], 0.75);
  return Renderer.MULTIPLY_LINEAR ? linearRGB(m) : m;
}
function mixS(a: V3, b: V3, t: number): V3 { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
function dist2(m: MeshGPU, e: V3) {
  const c = [(m.min[0] + m.max[0]) / 2 - e[0], (m.min[1] + m.max[1]) / 2 - e[1], (m.min[2] + m.max[2]) / 2 - e[2]];
  return c[0] * c[0] + c[1] * c[1] + c[2] * c[2];
}

/** 32 samples (0…180° from the aiming direction) of an IES profile's relative intensity (EngineIESProfile.json). */
export function iesRow(p: { vertical: number[]; relative: number[] }): Float32Array {
  const out = new Float32Array(32);
  const v = p.vertical, r = p.relative;
  for (let i = 0; i < 32; i++) {
    const a = (i / 31) * 180;
    let x = 0;
    if (!v.length) x = 1;
    else if (a <= v[0]) x = r[0];
    else if (a >= v[v.length - 1]) x = v[v.length - 1] >= 179 ? r[r.length - 1] : 0;
    else for (let k = 1; k < v.length; k++) if (a <= v[k]) { const t = (a - v[k - 1]) / Math.max(v[k] - v[k - 1], 1e-9); x = r[k - 1] + (r[k] - r[k - 1]) * t; break; }
    out[i] = Math.max(0, x);
  }
  return out;
}
function toHalf(f: number): number {
  const b = new DataView(new ArrayBuffer(4));
  b.setFloat32(0, f);
  const x = b.getUint32(0);
  const sign = (x >> 16) & 0x8000, e = ((x >> 23) & 0xff) - 127 + 15, m = (x >> 13) & 0x3ff;
  if (e <= 0) return sign;
  if (e >= 31) return sign | 0x7c00;
  return sign | (e << 10) | m;
}
