// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Render window (ArchiApp/RenderController.swift RenderController.renderImage / RenderPanel): output presets,
// resolution up to 7680×4320, passes (Beauty, Alpha, Depth, Normal, Material ID), styles (Photographic, Sketch,
// Watercolour), render region, background, antialiasing, the photographic look and supersampling, environment,
// shadows and occlusion, the sun at a date and time, the camera response (exposure, white balance, bloom, depth of
// field), Render / Save… / Copy, turntable, walkthrough and sun-study videos and the 360° panorama. The image is
// drawn by the 3D view's renderer from its current camera; data passes are cast by the engine (render.pass).
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, picker, toggle, flatButton, note, label, row, stepper, slider, section, promptDialog, textField, Option } from "../dialogs/ui";
import { renderImage, alphaMask, paste, defaultSettings, applyPreset, presetFrom, sunAt, RenderSettings, OutputPreset, Pixels, SHADOW_SAMPLES, ModelCamera, V3 } from "./render";
import { view3d, modelCamera, renderWindowInfo } from "./context";
import { saveDialog, writeBytes, encodePixels, dataURL, out, docName, fileName, blobBytes } from "./native";
import { exportVideo } from "./videos";

const PRESETS_KEY = "archi.render.presets", LAST_KEY = "archi.render.lastPreset";
function customPresets(): OutputPreset[] { try { return JSON.parse(localStorage.getItem(PRESETS_KEY) ?? "[]"); } catch { return []; } }
function setCustomPresets(p: OutputPreset[]) { try { localStorage.setItem(PRESETS_KEY, JSON.stringify(p)); } catch { /* ignore */ } }
function lastPreset(): string { try { return localStorage.getItem(LAST_KEY) ?? "Standard (1080p)"; } catch { return "Standard (1080p)"; } }
function setLastPreset(n: string) { try { localStorage.setItem(LAST_KEY, n); } catch { /* ignore */ } }

/** Day of year (1…366) of a yyyy-mm-dd date, and back. */
export function dayOfYear(iso: string): number { const d = new Date(iso + "T12:00:00Z"); const y0 = Date.UTC(d.getUTCFullYear(), 0, 1); return Math.floor((d.getTime() - y0) / 86400000) + 1; }
export function isoOfDay(day: number, year = new Date().getFullYear()): string { return new Date(Date.UTC(year, 0, day, 12)).toISOString().slice(0, 10); }

export interface RenderState { settings: RenderSettings; image: Pixels | null; pass: string; npr: string; useRegion: boolean; region: [number, number, number, number] }
/** The open window's state (tests and RENDERTOFILE use the same code). */
export const renderWindow: { state: RenderState | null; render?: () => Promise<void> } = { state: null };

export async function openRenderWindow(app: App) {
  const info = await renderWindowInfo(app);
  const builtIn: OutputPreset[] = info.presets ?? [];
  const all = () => [...builtIn, ...customPresets()];
  const st: RenderState = { settings: defaultSettings(), image: null, pass: "Beauty", npr: "Photographic", useRegion: false, region: [0.25, 0.25, 0.75, 0.75] };
  renderWindow.state = st;
  let presetName = lastPreset();
  let resolution = "1920×1080", customW = 3000, customH = 2000;
  let busy = false, progress = 0, status = "";
  let seconds = 8, animSeconds = 10, sunFrom = 7, sunTo = 19;
  const s = st.settings;
  const site = { latitude: info.latitude ?? 44.43, longitude: info.longitude ?? 26.1, northAngle: info.northAngle ?? 0 };
  const cams: ModelCamera[] = info.cameras ?? [];

  toolWindow("render", `Render — ${info.title?.replace(/^Render — /, "") ?? docName(app)}`, 1100, 720, (body) => {
    const stage = h("div", { class: "rw-stage" });
    const form = h("div", { class: "rw-form" });
    body.append(stage, h("div", { class: "vsep" }), form);

    const renderStage = () => {
      clear(stage);
      if (st.image) {
        const img = h("img", { class: "rw-img", src: dataURL(st.image), alt: "Render" }) as HTMLImageElement;
        const wrap = h("div", { class: "rw-imgwrap" }, img);
        if (st.useRegion) {
          const box = h("div", { class: "rw-region" });
          const place = () => {
            const r = img.getBoundingClientRect(), p = wrap.getBoundingClientRect();
            Object.assign(box.style, { left: `${r.left - p.left + st.region[0] * r.width}px`, top: `${r.top - p.top + st.region[1] * r.height}px`,
              width: `${(st.region[2] - st.region[0]) * r.width}px`, height: `${(st.region[3] - st.region[1]) * r.height}px` });
          };
          img.addEventListener("load", place);
          requestAnimationFrame(place);
          wrap.append(box);
        }
        stage.append(wrap);
      } else stage.append(h("span", { class: "rw-hint", text: busy ? "Rendering…" : "Press Render" }));
      if (busy) stage.append(h("div", { class: "rw-progress" }, h("progress", progress > 0 ? { max: 1, value: progress } : {})));
    };

    const applyPresetNamed = (name: string) => {
      presetName = name;
      const p = all().find((x) => x.name === name);
      if (!p) return;
      applyPreset(p, s);
      resolution = `${p.width}×${p.height}`;
      if (!info.resolutions.includes(resolution)) { customW = p.width; customH = p.height; resolution = "Custom"; }
      setLastPreset(name);
    };
    const applyResolution = () => {
      if (resolution === "Custom") { s.width = Math.min(Math.max(customW, 16), 7680); s.height = Math.min(Math.max(customH, 16), 4320); return; }
      const p = resolution.split("×").map(Number);
      if (p.length === 2) { s.width = p[0]; s.height = p[1]; }
    };
    const hourText = () => `${String(Math.floor(s.hour)).padStart(2, "0")}:${String(Math.round((s.hour - Math.floor(s.hour)) * 60) % 60).padStart(2, "0")}`;
    const sunText = () => { const p = sunAt(s.day, s.hour, site.latitude, site.longitude, site.northAngle); return `Sun altitude ${p.altitude.toFixed(1)}°, azimuth ${p.azimuth.toFixed(1)}°`; };
    const sl = (text: () => string, min: number, max: number, step: number, get: () => number, set: (v: number) => void, disabled = false) => {
      const l = label(text(), { width: 150 });
      const r = slider(min, max, step, get(), (v) => { set(v); l.textContent = text(); }, 150);
      r.disabled = disabled;
      return row(l, r);
    };

    const renderForm = () => {
      const scroll = form.scrollTop;
      clear(form);
      const presetOpts: Option[] = all().map((p) => ({ value: p.name, title: p.name }));
      if (!presetOpts.some((o) => o.value === presetName)) presetOpts.push({ value: presetName, title: "Custom" });
      const isCustom = customPresets().some((p) => p.name === presetName);
      form.append(section("Preset",
        picker(presetOpts, presetName, (v) => { applyPresetNamed(v); renderForm(); }, { label: "Preset", width: 210 }),
        row(flatButton("Save as Preset…", () => void savePreset(), { compact: true }), isCustom ? flatButton("Delete", () => { setCustomPresets(customPresets().filter((p) => p.name !== presetName)); presetName = "Standard (1080p)"; renderForm(); }, { compact: true }) : null)));

      const resOpts: Option[] = (info.resolutions as string[]).map((r) => ({ value: r, title: r }));
      if (!info.resolutions.includes(resolution)) resOpts.push({ value: resolution, title: resolution });
      const outSec: HTMLElement[] = [picker(resOpts, resolution, (v) => { resolution = v; renderForm(); }, { label: "Resolution", width: 150 })];
      if (resolution === "Custom") {
        const fw = textField("Width", String(customW), (v) => { const n = Math.round(Number(v)); if (n > 0) customW = n; }, { width: 70 });
        const fh = textField("Height", String(customH), (v) => { const n = Math.round(Number(v)); if (n > 0) customH = n; }, { width: 70 });
        outSec.push(row(fw, label("×"), fh, note("px (max 7680×4320)")));
      }
      outSec.push(picker((info.passes as string[]).map((p) => ({ value: p, title: p })), st.pass, (v) => { st.pass = v; renderForm(); }, { label: "Pass", width: 150 }));
      if (st.pass === "Beauty") outSec.push(picker((info.styles as string[]).map((p) => ({ value: p, title: p })), st.npr, (v) => { st.npr = v; }, { label: "Style", width: 150 }));
      outSec.push(toggle("Render region only", st.useRegion, (v) => { st.useRegion = v; renderForm(); renderStage(); }));
      if (st.useRegion) {
        const r = st.region;
        const reg = (t: string, i: number, lo: number, hi: number, set: (v: number) => void) => sl(() => `${t} ${Math.round((i < 2 ? r[i] : r[i] - r[i - 2]) * 100)}%`, lo, hi, 0.01, () => (i < 2 ? r[i] : r[i] - r[i - 2]), (v) => { set(v); renderStage(); });
        outSec.push(
          reg("Left", 0, 0, 0.95, (v) => { const w = r[2] - r[0]; r[0] = Math.min(v, 0.95); r[2] = Math.min(1, r[0] + w); }),
          reg("Top", 1, 0, 0.95, (v) => { const hh = r[3] - r[1]; r[1] = Math.min(v, 0.95); r[3] = Math.min(1, r[1] + hh); }),
          reg("Width", 2, 0.05, 1, (v) => { r[2] = Math.min(1, r[0] + Math.max(0.05, v)); }),
          reg("Height", 3, 0.05, 1, (v) => { r[3] = Math.min(1, r[1] + Math.max(0.05, v)); }));
      }
      outSec.push(picker((info.backgrounds as string[]).map((p) => ({ value: p, title: p })), s.background, (v) => { s.background = v as RenderSettings["background"]; }, { label: "Background", width: 150 }),
        toggle("Antialiasing (4× MSAA + jitter)", s.antialias, (v) => { s.antialias = v; }));
      form.append(section("Output", ...outSec));

      form.append(section("Photographic Look",
        picker([{ value: "", title: "Custom (settings below)" }, ...(info.looks as string[]).map((l) => ({ value: l, title: l }))], s.beauty ?? "", (v) => { s.beauty = v || null; }, { label: "Look", width: 190 }),
        picker([{ value: 1, title: "Off" }, { value: 2, title: "2× (4 samples)" }, { value: 3, title: "3× (9 samples)" }], s.supersample, (v) => { s.supersample = v; }, { label: "Supersampling", width: 150 }),
        note("Daylight, Golden hour, Overcast or Night: sun, HDR sky lighting, soft shadows, exposure, bloom and glass (RENDERPRESET, RENDERSAVE)")));

      const envSec: HTMLElement[] = [picker((info.environments as string[]).map((e) => ({ value: e, title: e })), s.environment, (v) => { s.environment = v; renderForm(); }, { label: "Lighting", width: 160 })];
      if (s.environment === "HDRI File") envSec.push(row(label(s.hdriPath ? fileName(s.hdriPath) : "No file", { dim: true }), h("span", { class: "spacer" }), flatButton("Choose…", () => void chooseHDRI(), { compact: true })));
      envSec.push(sl(() => `Intensity ${s.environmentIntensity.toFixed(1)}`, 0, 3, 0.1, () => s.environmentIntensity, (v) => { s.environmentIntensity = v; }),
        toggle("Clay model (white)", s.clay, (v) => { s.clay = v; }));
      form.append(section("Environment", ...envSec));

      const off = s.shadowQuality === "Off";
      form.append(section("Shadows & Occlusion",
        picker((info.shadowQualities as string[]).map((q) => ({ value: q, title: q })), s.shadowQuality, (v) => { s.shadowQuality = v as RenderSettings["shadowQuality"]; renderForm(); }, { label: "Shadow quality", width: 120 }),
        sl(() => `Softness ${Math.round(s.shadowSoftness)}`, 0, 20, 1, () => s.shadowSoftness, (v) => { s.shadowSoftness = v; }, off),
        stepper((v) => `Soft shadow samples: ${v}`, s.shadowSamples ?? SHADOW_SAMPLES[s.shadowQuality], 1, 64, (v) => { s.shadowSamples = v; }, { disabled: off }),
        sl(() => `Ambient occlusion ${s.ambientOcclusion.toFixed(1)}`, 0, 2, 0.1, () => s.ambientOcclusion, (v) => { s.ambientOcclusion = v; })));

      const date = h("input", { type: "date", class: "darkfield", value: isoOfDay(s.day) }) as HTMLInputElement;
      const sunNote = note(sunText());
      date.addEventListener("change", () => { if (date.value) { s.day = dayOfYear(date.value); sunNote.textContent = sunText(); } });
      form.append(section("Sun",
        row(label("Date", { width: 60 }), date),
        sl(() => `Time ${hourText()}`, 5, 21, 0.25, () => s.hour, (v) => { s.hour = v; sunNote.textContent = sunText(); }),
        sunNote, note(info.site ?? "")));

      const camSec: HTMLElement[] = [
        sl(() => `Exposure ${s.exposure.toFixed(1)} EV`, -2, 2, 0.1, () => s.exposure, (v) => { s.exposure = v; }),
        sl(() => `White balance ${Math.round(s.whiteBalance)} K`, 3000, 9000, 100, () => s.whiteBalance, (v) => { s.whiteBalance = v; }),
        sl(() => `Bloom ${s.bloom.toFixed(2)}`, 0, 1, 0.01, () => s.bloom, (v) => { s.bloom = v; }),
        toggle("Depth of field", s.depthOfField, (v) => { s.depthOfField = v; renderForm(); }),
      ];
      if (s.depthOfField) camSec.push(sl(() => `f/${s.fStop.toFixed(1)}`, 0.8, 16, 0.1, () => s.fStop, (v) => { s.fStop = v; }),
        sl(() => (s.focusDistance === 0 ? "Focus: model centre" : `Focus ${s.focusDistance.toFixed(1)} m`), 0, 200, 0.5, () => s.focusDistance, (v) => { s.focusDistance = v; }));
      camSec.push(note((window as any).archiView3D ? "Uses the current 3D view camera" : "Default iso view (open the 3D view to set the camera)"));
      form.append(section("Camera", ...camSec));

      const statusEl = note(status);
      form.append(section("",
        row(flatButton("Render", () => void doRender(), { disabled: busy, help: "Ctrl+Enter" }), flatButton("Save…", () => void save(), { disabled: !st.image || busy }), flatButton("Copy", () => void copy(), { disabled: !st.image })),
        row(stepper((v) => `Turntable ${v} s`, seconds, 5, 10, (v) => { seconds = v; }), flatButton("Export Video…", () => void video("turntable"), { disabled: busy })),
        status ? statusEl : null));

      const cams2 = cams.length;
      form.append(section("Animation & Panorama",
        stepper((v) => `Length ${v} s`, animSeconds, 3, 120, (v) => { animSeconds = v; }),
        row(flatButton("Walkthrough Video…", () => void video("walkthrough"), { disabled: busy || cams2 < 2, help: cams2 < 2 ? "Save at least two cameras (SAVECAMERA); the path runs through them in order." : `Smooth path through the ${cams2} saved cameras, in order` }), note(`${cams2} camera(s)`)),
        row(stepper((v) => `From ${v}:00`, sunFrom, 0, 23, (v) => { sunFrom = v; }), stepper((v) => `to ${v}:00`, sunTo, 1, 24, (v) => { sunTo = v; })),
        flatButton("Sun Study Video…", () => void video("sunStudy"), { disabled: busy }),
        flatButton("360° Panorama…", () => void panorama(), { disabled: busy, help: "Equirectangular 2:1 panorama from the current 3D camera position" })));
      form.scrollTop = scroll;
    };

    async function savePreset() {
      applyResolution();
      const d = `Resolution ${s.width}×${s.height}, exposure ${s.exposure.toFixed(1)} EV, ${s.environment} lighting, ${s.shadowQuality.toLowerCase()} shadows${s.depthOfField ? ", depth of field" : ""}${s.clay ? ", clay" : ""}.`;
      const n = (await promptDialog("Save Render Preset", d, `My Preset ${customPresets().length + 1}`, "Save"))?.trim();
      if (!n || builtIn.some((p) => p.name === n)) return;
      setCustomPresets([...customPresets().filter((p) => p.name !== n), presetFrom(s, n)]);
      presetName = n; setLastPreset(n); renderForm();
    }
    async function chooseHDRI() {
      const p = await app.engine.native?.openFileDialog({ title: "Choose an equirectangular (2:1) environment image", filters: [{ name: "Images", extensions: ["hdr", "exr", "jpg", "jpeg", "png", "tif", "tiff"] }] });
      if (p) { s.hdriPath = p; renderForm(); }
    }

    async function doRender() {
      applyResolution();
      busy = true; progress = 0; status = ""; renderStage(); renderForm();
      const t0 = performance.now();
      const big = s.width > 2048 || s.height > 2048;
      try {
        const v = await view3d();
        const region = st.useRegion ? st.region : null;
        if (st.pass === "Beauty" || st.pass === "Alpha") {
          const settings = st.pass === "Alpha" ? { ...s, background: "Transparent" as const } : s;
          const prev = st.image;
          if (st.useRegion && st.pass === "Beauty" && st.npr === "Photographic" && prev && prev.width === s.width && prev.height === s.height) {
            const part = await renderImage(v, { settings, site, region });
            st.image = paste(prev, part, st.useRegion ? st.region : [0, 0, 1, 1]);
          } else {
            let px = await renderImage(v, { settings, site, region, style: st.pass === "Beauty" ? (st.npr as any) : "Photographic" });
            if (st.pass === "Alpha") px = alphaMask(px);
            st.image = px;
          }
        } else {
          const r = await app.engine.call("render.pass", { pass: st.pass, width: s.width, height: s.height, camera: modelCamera(v), region: region ?? null });
          st.image = await decodeDataURL(r.image);
        }
        status = `Rendered ${st.pass} ${s.width}×${s.height}${st.useRegion ? " (region)" : ""}${big ? " in tiles" : ""} in ${((performance.now() - t0) / 1000).toFixed(1)} s`;
      } catch (e: any) { status = `Rendering failed (${e?.message ?? e}).`; }
      busy = false; renderStage(); renderForm();
    }
    renderWindow.render = doRender;

    async function save() {
      if (!st.image) return;
      const path = await saveDialog(app, "Save Render", `${docName(app)} render.png`, [{ name: "PNG", extensions: ["png"] }, { name: "JPEG", extensions: ["jpg", "jpeg"] }]);
      if (!path) return;
      const jpeg = /\.jpe?g$/i.test(path);
      try { await writeBytes(path, await encodePixels(st.image, jpeg ? "image/jpeg" : "image/png")); status = `Saved ${fileName(path)}`; }
      catch (e: any) { status = e?.message ?? String(e); }
      renderForm();
    }
    async function copy() {
      if (!st.image) return;
      const png = await encodePixels(st.image);
      const n = out();
      if (n) await n.copyImage(png);
      else { try { await (navigator.clipboard as any).write([new (window as any).ClipboardItem({ "image/png": new Blob([png as any], { type: "image/png" }) })]); } catch { /* not allowed */ } }
      status = "Copied to the clipboard."; renderForm();
    }
    async function video(kind: "turntable" | "walkthrough" | "sunStudy") {
      applyResolution();
      const vs: RenderSettings = { ...s };
      if (vs.width > 1920) { vs.width = 1920; vs.height = 1080; }
      const suffix = kind === "turntable" ? "turntable" : kind === "walkthrough" ? "walkthrough" : "sun study";
      const path = await saveDialog(app, "Export Video", `${docName(app)} ${suffix}.mp4`, [{ name: "MPEG-4 movie", extensions: ["mp4"] }]);
      if (!path) return;
      busy = true; progress = 0; renderStage(); renderForm();
      try {
        const r = await exportVideo(app, { kind, settings: vs, site, path, seconds: kind === "turntable" ? seconds : animSeconds, day: s.day, fromHour: sunFrom, toHour: sunTo,
          progress: (p) => { progress = p; const pr = stage.querySelector("progress") as HTMLProgressElement | null; if (pr) pr.value = p; } });
        status = `Saved ${fileName(r)}`;
      } catch (e: any) { status = `Video export failed: ${e?.message ?? e}`; }
      busy = false; renderStage(); renderForm();
    }
    async function panorama() {
      const path = await saveDialog(app, "Save Panorama", `${docName(app)} 360.jpg`, [{ name: "JPEG", extensions: ["jpg", "jpeg"] }, { name: "PNG", extensions: ["png"] }]);
      if (!path) return;
      busy = true; progress = 0; renderStage(); renderForm();
      try {
        const v = await view3d();
        const cam = modelCamera(v);
        const width = Math.max(2048, s.width * 2);
        const jpeg = !/\.png$/i.test(path);
        const blob = await v.panorama({ eye: cam.eye as V3, width, format: jpeg ? "JPEG" : "PNG", preset: s.beauty ?? undefined });
        const bytes = await blobBytes(blob);
        await writeBytes(path, bytes);
        const img = await decodeDataURL(URL.createObjectURL(blob));
        st.image = img;
        status = `Saved ${fileName(path)} (${img.width}×${img.height})`;
      } catch (e: any) { status = `Panorama failed (${e?.message ?? e}).`; }
      busy = false; renderStage(); renderForm();
    }

    body.addEventListener("keydown", (e) => { if ((e.ctrlKey || e.metaKey) && e.key === "Enter") { e.preventDefault(); if (!busy) void doRender(); } });
    const p = all().find((x) => x.name === presetName);
    if (p) applyPresetNamed(p.name);
    renderStage(); renderForm();
  }, () => { renderWindow.state = null; renderWindow.render = undefined; });
}

/** Pixels of an image URL (data or blob URL). */
export async function decodeDataURL(src: string): Promise<Pixels> {
  const img = new Image();
  img.src = src;
  await img.decode();
  const cv = document.createElement("canvas");
  cv.width = img.naturalWidth; cv.height = img.naturalHeight;
  const g = cv.getContext("2d")!;
  g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, cv.width, cv.height);
  return { width: cv.width, height: cv.height, data: new Uint8Array(d.data.buffer.slice(0)) };
}
