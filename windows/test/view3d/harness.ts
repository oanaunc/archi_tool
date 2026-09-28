// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Test page for the 3D view: loads the Cedar House meshes fixture and exposes window.harness for Playwright
// (windows/test/view3d/run.mjs, ui.mjs) to render each lighting preset from the saved cameras and to drive the interactive view.
import { View3D, EngineBridge, Effects } from "../../src/renderer/view3d";
import { decodeHDR, environmentFromBytes } from "../../src/renderer/view3d/hdri";
import { iesRow } from "../../src/renderer/view3d/renderer";
import { builtinBillboard } from "../../src/renderer/view3d/billboards";

declare global { interface Window { harness: any } }

async function json(url: string) { const r = await fetch(url); if (!r.ok) throw new Error(url + " " + r.status); return r.json(); }

async function main() {
  const q = new URLSearchParams(location.search);
  const meshesURL = q.get("meshes") ?? "/build/engine-fixtures/meshes-all-lod2.json";
  const doc = await json("/windows/test/view3d/fixtures/cedar-document.json");
  const raw = await json(meshesURL);
  const meshes = raw.response?.result ?? raw.result ?? raw;
  // Full detail: the engine's binary buffer file (model.meshes {"binary": …}), e.g. view3d-meshes-lod0.bin.
  const binURL = q.get("bin");
  const tLoad = performance.now();
  const bin = binURL ? await (await fetch(binURL)).arrayBuffer() : undefined;
  const presets = await json("/windows/test/fixtures/engine/render-presets.json").catch(() => json("/build/engine-fixtures/render-presets.json")).catch(() => []);
  const host = document.getElementById("host")!;
  const view = new View3D(host, {
    resolveAsset: (p: string) => "/assets/demo/" + p,
    materialMaps: doc.materialMaps,
  });
  view.setModel(meshes, bin);
  (window as any).loadInfo = { ms: performance.now() - tLoad, bytes: bin?.byteLength ?? 0, meshes: view.scene.meshes.length,
    triangles: view.scene.meshes.reduce((n, m) => n + m.count / 3, 0) };
  view.setCameras(doc.cameras);
  view.setStyle(q.get("style") ?? "Realistic");
  const settingsFor = (name: string) => {
    const hit = (presets as any[]).find((x) => x.request?.params?.name?.toLowerCase().replace(/\s/g, "") === name.toLowerCase().replace(/\s/g, ""));
    return hit?.response?.result ?? { preset: name };
  };
  view.setRenderSettings(settingsFor(q.get("preset") ?? "Daylight"), true);
  window.harness = {
    view,
    EngineBridge,
    Effects,
    frame() { const t0 = performance.now(); (view as any).drawNow(); const px = new Uint8Array(4); view.gl.readPixels(0, 0, 1, 1, view.gl.RGBA, view.gl.UNSIGNED_BYTE, px); return performance.now() - t0; },
    camera: () => view.getCamera(),
    applyCamera(name: string) { view.applyNamedCamera(name, false); (view as any).drawNow(); },
    setPreset(name: string) { view.setRenderSettings(settingsFor(name), true); },
    ready: () => view.whenTexturesLoaded(),
    async renderLook(look: any, camera: string, w: number, h: number, ss: number) {
      view.setRenderSettings({ ...settingsFor(look.preset ?? "Daylight"), ...look }, true);
      const png = await view.renderToPNG({ width: w, height: h, supersample: ss, camera });
      const buf = new Uint8Array(await png.arrayBuffer());
      let s = ""; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
      return { png: btoa(s) };
    },
    hdri: { decodeHDR, environmentFromBytes }, iesRow, builtinBillboard,
    /** A render with extra frame options (clay, dof, envImage, envIntensity …) merged into the renderer's. */
    async renderExtra(extra: any, preset: string, camera: string, w: number, h: number) {
      view.setRenderSettings(settingsFor(preset), true);
      if (extra?.envImage && Array.isArray(extra.envImage.data)) extra = { ...extra, envImage: { ...extra.envImage, data: new Float32Array(extra.envImage.data) } };
      await view.whenTexturesLoaded();
      const R: any = view.renderer, orig = R.renderPixels.bind(R);
      R.renderPixels = (sc: any, o: any) => orig(sc, { ...o, ...extra });
      let png: Blob;
      try { png = await view.renderToPNG({ width: w, height: h, supersample: 1, camera }); } finally { R.renderPixels = orig; }
      const buf = new Uint8Array(await png.arrayBuffer());
      let s = ""; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
      return { png: btoa(s) };
    },
    async render(preset: string, camera: string, w: number, h: number, ss: number) {
      view.setRenderSettings(settingsFor(preset), true);
      const t0 = performance.now();
      const png = await view.renderToPNG({ width: w, height: h, supersample: ss, camera, preset });
      const buf = new Uint8Array(await png.arrayBuffer());
      let s = ""; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
      return { png: btoa(s), ms: performance.now() - t0 };
    },
  };
  (window as any).harnessReady = true;
}
main().catch((e) => { (window as any).harnessError = String(e?.stack ?? e); console.error(e); });
