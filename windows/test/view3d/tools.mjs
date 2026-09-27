// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Mac 3D tools in Chromium (Cedar House fixture): the bottom tool bar, move / rotate / scale gizmo with its commit,
// 3D measuring, levels in 3D (isolate / explode), field of view, the cameras and levels menus, the clipping plane panel
// with section caps, the sun study panel, the steering wheel, door and object animation, weather / seasons / water,
// two-point perspective, VIEWIMAGE (transparent), mono and stereo panoramas, and the engine bridge's view3d host actions.
//   node windows/test/view3d/tools.mjs            (screenshots: windows/test-results/3d/tools-*.png)
import fs from "node:fs";
import path from "node:path";
import { openHarness, results as out } from "./common.mjs";

const { page, close } = await openHarness("?style=Shaded%20with%20Edges", { width: 1100, height: 640 });
const results = [];
const check = (name, ok, info = "") => { results.push({ name, ok, info }); console.log(`${ok ? "PASS" : "FAIL"} ${name} ${info}`); };
const settle = () => page.waitForFunction(() => !window.harness.view.isAnimating(), null, { timeout: 120000, polling: 250 });
const shot = async (name) => { await settle(); await page.evaluate(() => window.harness.frame()); await page.screenshot({ path: path.join(out, `tools-${name}.png`), timeout: 120000 }); };
const pixels = (x, y, w, h) => page.evaluate(([x, y, w, h]) => {
  const v = window.harness.view; window.harness.frame();
  const gl = v.gl, dpr = window.devicePixelRatio || 1, px = new Uint8Array(w * h * 4);
  gl.readPixels(Math.round(x * dpr), Math.round(gl.drawingBufferHeight - (y + h) * dpr), w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
  let r = 0, g = 0, b = 0; for (let i = 0; i < px.length; i += 4) { r += px[i]; g += px[i + 1]; b += px[i + 2]; }
  const n = px.length / 4; return [r / n, g / n, b / n];
}, [x, y, w, h]);

// Record what the view hands to the shell / engine.
await page.evaluate(() => {
  const x = window.harness.view.extras.host;
  window.calls = [];
  x.onTransform = (t) => window.calls.push(["transform", t]);
  x.onVariable = (n, v) => window.calls.push(["variable", n, v]);
  x.print = (t) => window.calls.push(["print", t]);
  window.harness.view.opts.onSectionPlane = (p) => window.calls.push(["plane", p]);
  window.harness.view.opts.onCamera = (c) => window.calls.push(["camera", c]);
});
const calls = () => page.evaluate(() => window.calls);

// ---- tool bar ----
check("tool bar", await page.locator(".v3d-toolbar .v3d-seg button").count() === 4, "ruler + Off/Move/Rotate/Scale");

// ---- gizmo: select a wall, Move, drag the X arrow ----
await page.evaluate(() => { window.harness.applyCamera("Corner"); });
await settle();
const wallId = await page.evaluate(() => window.harness.view.scene.meshes.find((m) => m.kind === "wall").id);
await page.evaluate((id) => { window.harness.view.setSelection([id]); window.harness.view.extras.setGizmo("Move"); }, wallId);
await page.locator(".v3d-toolbar .v3d-seg button", { hasText: "Move" }).click();
const handle = await page.evaluate(() => {
  const x = window.harness.view.extras;
  const o = x.selectionCenter(); o[2] += 50;
  const size = Math.max(400, Math.max(...[0, 1].map((k) => window.harness.view.scene.max[k] - window.harness.view.scene.min[k])) / 12);
  const a = window.harness.view.project(o), b = window.harness.view.project([o[0] + size * 0.8, o[1], o[2]]);
  return { a, b, axis: x.gizmoAxis(b[0], b[1]) };
});
check("gizmo X arrow hit", handle.axis === 0, JSON.stringify(handle.axis));
await shot("gizmo-move");
const r = await page.locator(".v3d").boundingBox();
await page.mouse.move(r.x + handle.b[0], r.y + handle.b[1]);
await page.mouse.down();
await page.mouse.move(r.x + handle.b[0] + (handle.b[0] - handle.a[0]) * 0.5, r.y + handle.b[1] + (handle.b[1] - handle.a[1]) * 0.5, { steps: 6 });
const hint = await page.locator(".v3d-ttext").textContent();
const previewXf = await page.evaluate((id) => { const m = window.harness.view.scene.meshes.find((m) => m.id === id); return m.xf ? m.xf[12] : null; }, wallId);
await shot("gizmo-drag");
await page.mouse.up();
let c = await calls();
const tr = c.find((x) => x[0] === "transform");
check("gizmo move preview", previewXf != null && previewXf > 50, `xf dx ${previewXf?.toFixed(0)} mm, hint "${hint}"`);
check("gizmo move commit", !!tr && tr[1].op === "move" && tr[1].axis === 0 && tr[1].amount > 50 && tr[1].ids[0] === wallId, JSON.stringify(tr?.[1]));
check("gizmo preview reset", await page.evaluate((id) => !window.harness.view.scene.meshes.find((m) => m.id === id).xf, wallId), "");
// Rotate ring (seen from above: the Aerial camera)
await page.evaluate(() => { window.harness.view.setView("Top", false); window.harness.view.extras.setGizmo("Rotate"); });
await settle();
const ring = await page.evaluate(() => { const x = window.harness.view.extras; const o = x.selectionCenter(); o[2] += 50; const size = Math.max(400, Math.max(...[0, 1].map((k) => window.harness.view.scene.max[k] - window.harness.view.scene.min[k])) / 12); const p = window.harness.view.project([o[0] + size * 0.7, o[1], o[2]]); const q = window.harness.view.project([o[0], o[1] + size * 0.7, o[2]]); return { p, q, axis: x.gizmoAxis(p[0], p[1]) }; });
check("gizmo ring hit", ring.axis === 2, "");
await page.mouse.move(r.x + ring.p[0], r.y + ring.p[1]); await page.mouse.down();
await page.mouse.move(r.x + ring.q[0], r.y + ring.q[1], { steps: 8 });
await shot("gizmo-rotate");
await page.mouse.up();
c = await calls();
const rot = c.filter((x) => x[0] === "transform").pop();
check("gizmo rotate commit", rot?.[1].op === "rotate" && Math.abs(rot[1].amount - Math.PI / 2) < 0.1, `${((rot?.[1].amount ?? 0) * 180 / Math.PI).toFixed(1)}° (+X → +Y from above is +90°)`);
await page.evaluate(() => window.harness.view.extras.setGizmo("Off"));

// ---- measure ----
await page.locator(".v3d-toolbar .v3d-tbtn").click();
const pts = await page.evaluate(() => { const v = window.harness.view; const w = v.el.clientWidth, h = v.el.clientHeight; const out = []; for (let y = h * 0.3; y < h * 0.8 && out.length < 2; y += 20) for (let x = w * 0.2; x < w * 0.8; x += 37) { if (v.pointAt(x, y) && (!out.length || Math.hypot(x - out[0][0], y - out[0][1]) > 150)) { out.push([x, y]); break; } } return out; });
for (const p of pts) await page.mouse.click(r.x + p[0], r.y + p[1]);
const mtext = await page.locator(".v3d-ttext").textContent();
c = await calls();
check("measure 3D", /^Distance [\d.]+ · ΔX -?[\d.]+ · ΔY -?[\d.]+ · ΔZ -?[\d.]+ · plan [\d.]+$/.test(mtext ?? "") && c.some((x) => x[0] === "print" && x[1] === mtext), mtext);
await shot("measure");
await page.locator(".v3d-toolbar .v3d-tbtn").click();

// ---- levels in 3D ----
await page.evaluate(() => {
  const v = window.harness.view;
  // The fixture predates per-mesh levels: level 0 below 2.9 m, level 1 above.
  for (const m of v.scene.meshes) m.level = m.min[2] < 2900 ? 0 : 1;
  v.setInfo({ levels: [{ id: 0, name: "Ground Floor", elevation: 0, height: 3000 }, { id: 1, name: "First Floor", elevation: 3000, height: 3000 }], currentLevel: 0 });
});
await page.evaluate(() => window.harness.applyCamera("Aerial"));
await page.click(".v3d-pill[title^='Isolate or explode levels']");
const menuItems = await page.locator(".v3d-menu button").allTextContents();
check("levels menu", menuItems.includes("✓ All levels") && menuItems.includes("Only First Floor") && menuItems.some((t) => t.startsWith("Explode levels by 3 m")) && menuItems.some((t) => t.includes("Field of view 35° (38 mm)")), menuItems.join(" | "));
await page.locator(".v3d-menu button", { hasText: "Only Ground Floor" }).click();
const hidden = await page.evaluate(() => window.harness.view.scene.meshes.filter((m) => m.hidden).length);
check("isolate level", hidden > 0 && await page.evaluate(() => window.harness.view.scene.meshes.filter((m) => m.level === 0 && m.hidden).length) === 0, `${hidden} meshes hidden`);
await shot("isolate");
await page.click(".v3d-pill[title^='Isolate or explode levels']");
await page.locator(".v3d-menu button", { hasText: "All levels" }).click();
await page.click(".v3d-pill[title^='Isolate or explode levels']");
await page.locator(".v3d-menu button", { hasText: "Explode levels by 6 m" }).click();
const lifted = await page.evaluate(() => window.harness.view.scene.meshes.filter((m) => m.level === 1 && m.xf && Math.abs(m.xf[14] - 6000) < 1e-3).length);
check("explode levels", lifted > 0, `${lifted} meshes lifted 6 m`);
await shot("explode");
await page.evaluate(() => window.harness.view.extras.setLevelView(null, 0));

// ---- field of view ----
await page.click(".v3d-pill[title^='Isolate or explode levels']");
await page.locator(".v3d-menu button", { hasText: "Field of view 24°" }).click();
check("field of view", Math.abs((await page.evaluate(() => window.harness.camera().fov)) - 24) < 1e-6, "");
await page.evaluate(() => window.harness.view.setFieldOfView(45));

// ---- cameras menu ----
await page.click(".v3d-pill[title='Saved cameras']");
const cams = await page.locator(".v3d-menu button").allTextContents();
check("cameras menu", cams[0] === "Save Current Camera…" && ["Front", "Aerial", "Corner"].every((n) => cams.includes(n)) && (await page.locator(".v3d-menu .v3d-mhead").textContent()) === "Delete", cams.join(" | "));
await page.locator(".v3d-menu button", { hasText: "Save Current Camera…" }).first().click();
check("save camera sheet", await page.locator(".v3d-sheet input").inputValue() === "Camera 4", "");
await page.locator(".v3d-sheet input").fill("Garden");
await page.locator(".v3d-sheet .v3d-flat", { hasText: "Save" }).click();
check("save camera (no engine)", (await page.evaluate(() => window.harness.view.getCameras().map((c) => c.name))).includes("Garden"), "");

// ---- clipping plane panel + caps ----
await page.evaluate(() => window.harness.applyCamera("Corner"));
await page.click(".v3d-pill[title='Clipping plane (SECTIONPLANE)']");
c = await calls();
const plane = c.filter((x) => x[0] === "plane").pop();
check("clipping plane panel", !!plane && plane[1].on && plane[1].normal[2] === 1, JSON.stringify(plane?.[1]));
await page.locator(".v3d-clippanel .v3d-flat", { hasText: "Level" }).click();
const lvlPlane = (await calls()).filter((x) => x[0] === "plane").pop();
check("clipping plane Level", lvlPlane?.[1].point[2] === 1200, `cut at ${lvlPlane?.[1].point[2]}`);
// Caps as the engine sends them: a square slab of cap faces at the cut height.
await page.evaluate(() => {
  const v = window.harness.view, s = v.scene, z = 1199.5;
  const a = [s.min[0], s.min[1], z], b = [s.max[0], s.min[1], z], cc = [s.max[0], s.max[1], z], d = [s.min[0], s.max[1], z];
  v.setSectionCaps(new Float32Array([...a, ...b, ...cc, ...a, ...cc, ...d]), [0, 0, 1]);
});
await page.evaluate(() => window.harness.view.setView("Top", false));
const capColor = await pixels(540, 300, 20, 20);
check("section caps", capColor[0] > capColor[1] * 1.8 && capColor[0] > 60, `rgb ${capColor.map((v) => v.toFixed(0))}`);
await shot("caps");
await page.locator(".v3d-clippanel .v3d-flat", { hasText: "Remove" }).click();
await page.evaluate(() => window.harness.view.setSectionCaps(null));

// ---- section box face grips (drag the top face down), Ctrl-click sub-object ----
await page.evaluate(() => {
  const v = window.harness.view, s = v.scene;
  window.harness.applyCamera("Aerial");
  window.calls = window.calls.filter((c) => c[0] !== "box");
  v.opts.onSectionBox = (b) => window.calls.push(["box", JSON.parse(JSON.stringify(b))]);
  v.setSectionBox({ on: true, min: [s.min[0] - 200, s.min[1] - 200, s.min[2] - 200], max: [s.max[0] + 200, s.max[1] + 200, s.max[2] + 200] });
});
await settle();
const grip = await page.evaluate(() => { const v = window.harness.view, b = v.getSectionBox(); const c = [(b.min[0] + b.max[0]) / 2, (b.min[1] + b.max[1]) / 2, b.max[2]]; const p = v.project(c), q = v.project([c[0], c[1], c[2] - 3000]); return { p, q, face: v.extras.boxFaceAt(p[0], p[1]) }; });
check("section box grip hit (+Z)", grip.face === 5, JSON.stringify(grip.face));
await shot("box-grips");
await page.mouse.move(r.x + grip.p[0], r.y + grip.p[1]); await page.mouse.down();
await page.mouse.move(r.x + grip.q[0], r.y + grip.q[1], { steps: 5 }); await page.mouse.up();
const boxCall = (await calls()).filter((x) => x[0] === "box").pop();
const zTop = await page.evaluate(() => window.harness.view.scene.max[2] + 200);
check("section box grip drag", !!boxCall && Math.abs(boxCall[1].max[2] - (zTop - 3000)) < 150, `top ${zTop.toFixed(0)} → ${boxCall?.[1].max[2].toFixed(0)}`);
await page.evaluate(() => window.harness.view.setSectionBox(null));
const sub = await page.evaluate(() => {
  const v = window.harness.view; let line = null;
  v.extras.host.runCommand = (l) => { line = l; };
  v.extras.host.subObjectMode = () => "Edge";
  const w = v.el.clientWidth, h = v.el.clientHeight;
  for (let y = 40; y < h - 40; y += 9) for (let x = 40; x < w - 40; x += 13) { const hit = v.hitAt(x, y); if (hit && hit.kind === "solid") { v.extras.subObjectPick(x, y); return { line, hit }; } }
  return null;
});
check("Ctrl-click sub-object", !!sub && /^SUBOBJECT #\d+ Edge \*-?[\d.]+,-?[\d.]+,-?[\d.]+$/.test(sub.line ?? ""), sub?.line ?? "no solid under the cursor");

// ---- sun study ----
await page.evaluate(() => { window.harness.applyCamera("Corner"); window.harness.view.extras.site = { latitude: 44.43, longitude: 26.1, day: 172, hour: 15 }; });
await page.click(".v3d-pill[title='Sun study']");
const sunTxt = await page.locator(".v3d-sunpanel .v3d-small").textContent();
const dateTxt = await page.locator(".v3d-sunpanel .v3d-mono").textContent();
check("sun study panel", /^21 June {2}15:00$/.test(dateTxt ?? "") && /^Altitude [\d.]+°, azimuth [\d.]+° · site 44.43°, 26.1°$/.test(sunTxt ?? ""), `${dateTxt} · ${sunTxt}`);
await page.locator(".v3d-sunpanel .v3d-flat", { hasText: "Dec 21" }).click();
c = await calls();
check("sun study saves SUNSTUDY", c.some((x) => x[0] === "variable" && x[1] === "SUNSTUDY" && x[2] === "355,15"), "");
await shot("sun-study");
await page.click(".v3d-pill[title='Sun study']");

// ---- steering wheel ----
await page.evaluate(() => window.harness.view.extras.toggleWheel(true));
const c0 = await page.evaluate(() => window.harness.camera());
await page.evaluate(() => { const x = window.harness.view.extras; x.pushHistory(); x.wheelOp("ZOOM", 0, 50); });
const c1 = await page.evaluate(() => window.harness.camera());
const d0 = Math.hypot(...c0.eye.map((v, i) => v - c0.target[i])), d1 = Math.hypot(...c1.eye.map((v, i) => v - c1.target[i]));
check("steering wheel zoom", Math.abs(d1 / d0 - Math.exp(-0.5)) < 1e-3, `${d0.toFixed(1)} → ${d1.toFixed(1)} m`);
await page.evaluate(() => window.harness.view.extras.wheelRewind());
const c2 = await page.evaluate(() => window.harness.camera());
check("steering wheel rewind", Math.abs(c2.eye[0] - c0.eye[0]) < 1e-6, "");
await shot("wheel");
await page.evaluate(() => window.harness.view.extras.toggleWheel(false));

// ---- door animation ----
const door = await page.evaluate(() => {
  const v = window.harness.view, ms = v.scene.meshes.filter((m) => m.kind === "door");
  if (!ms.length) return null;
  const lo = [Infinity, Infinity], hi = [-Infinity, -Infinity];
  for (const m of ms) for (let k = 0; k < 2; k++) { lo[k] = Math.min(lo[k], m.min[k]); hi[k] = Math.max(hi[k], m.max[k]); }
  const alongX = hi[0] - lo[0] > hi[1] - lo[1];
  const cy = (lo[1] + hi[1]) / 2, cx = (lo[0] + hi[0]) / 2;
  const leaf = alongX ? { hinge: [lo[0] + 50, cy], sign: 1, s0: 50, s1: hi[0] - lo[0] - 50, origin: [lo[0], cy], dir: [1, 0], normal: [0, 1], wallHalf: 150 }
    : { hinge: [cx, lo[1] + 50], sign: 1, s0: 50, s1: hi[1] - lo[1] - 50, origin: [cx, lo[1]], dir: [0, 1], normal: [-1, 0], wallHalf: 150 };
  v.setInfo({ animations: [{ id: 1, target: Number(ms[0].id), kind: "Door", pivot: [leaf.hinge[0], leaf.hinge[1], 0], angle: 90, start: 0, duration: 2, pingPong: true, leafIndex: 0, leaf }] });
  v.extras.animTime = 2; v.extras.applyAnimations(2);
  const parts = ms.map((m) => m.parts ? m.parts.map((p) => p.count) : null);
  return { id: ms[0].id, parts, rotated: ms.some((m) => m.parts && m.parts[1] && m.parts[1].xf && Math.abs(m.parts[1].xf[0]) < 1e-6) };
});
check("door split + swing", !!door && door.parts.some((p) => p && p.length === 2 && p[1] > 0) && door.rotated, JSON.stringify(door));
await page.evaluate(() => window.harness.view.extras.play(true));
// The frame loop (requestAnimationFrame) can stall for seconds under software WebGL on a busy machine, so the check
// drives one frame-loop step half a second after the start instead of waiting for real frames.
const played = await page.evaluate(() => { const e = window.harness.view.extras; return e.tick(e.playT0 + 500) && Math.abs(e.animTime - 0.5) < 1e-6; });
check("animation playback", played, `t = ${(await page.evaluate(() => window.harness.view.extras.animTime)).toFixed(2)} s`);
await page.evaluate(() => window.harness.view.extras.play(false));

// ---- weather, season, water ----
await page.evaluate(() => { window.harness.view.setStyle("Shaded"); window.harness.applyCamera("Aerial"); });
const before = await pixels(300, 220, 500, 200);
await page.evaluate(() => window.harness.view.setWeather(window.harness.Effects.parseWeather("Snow;0.7;Winter;0.9")));
const snow = await pixels(300, 220, 500, 200);
check("snow cover", snow[0] + snow[1] + snow[2] > before[0] + before[1] + before[2] + 15, `mean ${before.map((v) => v.toFixed(0))} → ${snow.map((v) => v.toFixed(0))}`);
await shot("snow");
await page.evaluate(() => window.harness.view.setWeather(window.harness.Effects.parseWeather("Rain;0.8;Autumn;0")));
await shot("rain-autumn");
check("weather haze (rain)", await page.evaluate(() => window.harness.view["weather"].fogDistance === 300 + 1500 * 0.2), "");
await page.evaluate(() => window.harness.view.setWeather(null));
const E = await page.evaluate(() => { const e = window.harness.Effects; return { w: e.seasonTint([0.3, 0.6, 0.2], "Autumn"), v: e.isVegetation("Lawn Grass"), water: e.isWater("Water", null) }; });
check("season tint / vegetation / water", Math.abs(E.w[0] - 0.588) < 1e-3 && E.v && E.water, JSON.stringify(E));

// ---- two-point perspective ----
await page.evaluate(() => window.harness.applyCamera("Front"));
const tp = await page.evaluate(() => window.harness.view.twoPointCommand(true));
check("two-point perspective", /^Two-point perspective: verticals are vertical \(lens shift -?[\d.]+\)\.$/.test(tp), tp);
await page.evaluate(() => window.harness.view.twoPointCommand(false));

// ---- VIEWIMAGE, panoramas ----
await page.evaluate(() => { window.harness.view.setStyle("Shaded with Edges"); window.harness.applyCamera("Corner"); });
const vi = await page.evaluate(async () => {
  const b = await window.harness.view.viewImage(320, 200, true, "PNG");
  const img = await createImageBitmap(b); const cv = new OffscreenCanvas(img.width, img.height); const g = cv.getContext("2d"); g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, img.width, img.height).data; let clear = 0, solid = 0; for (let i = 3; i < d.length; i += 4) { if (d[i] < 10) clear++; if (d[i] > 245) solid++; }
  const t = await window.harness.view.viewImage(64, 40, false, "TIFF");
  const tb = new Uint8Array(await t.arrayBuffer());
  return { w: img.width, h: img.height, clear, solid, tiff: String.fromCharCode(tb[0], tb[1]) + (tb[2] | (tb[3] << 8)), tiffBytes: tb.length };
});
check("VIEWIMAGE transparent PNG", vi.w === 320 && vi.clear > 1000 && vi.solid > 1000, JSON.stringify(vi));
check("VIEWIMAGE TIFF", vi.tiff === "II42" && vi.tiffBytes > 64 * 40 * 4, "");
const pano = await page.evaluate(async () => {
  const v = window.harness.view, s = v.scene;
  const eye = [(s.min[0] + s.max[0]) / 2, s.min[1] - 6000, 1600];
  const m = await v.panorama({ eye, width: 256, format: "PNG" });
  const st = await v.panorama({ eye, width: 256, stereo: true, ipd: 64, slices: 4, format: "PNG" });
  const dims = async (b) => { const i = await createImageBitmap(b); return [i.width, i.height]; };
  return { mono: await dims(m), stereo: await dims(st), bytes: st.size };
});
check("PANORAMA 2:1", pano.mono[0] === 256 && pano.mono[1] === 128, JSON.stringify(pano.mono));
check("STEREOPANORAMA over-under", pano.stereo[0] === 256 && pano.stereo[1] === 256, JSON.stringify(pano));
fs.writeFileSync(path.join(out, "tools-pano.json"), JSON.stringify(pano));

// ---- engine bridge: view3d host actions and view3d.info ----
const bridge = await page.evaluate(async () => {
  const log = [];
  const info = { cameras: [{ name: "Front", eye: [0, -20000, 1600], target: [0, 0, 1600], fov: 45 }], visualStyle: "Sketchy", perspective: false,
    sectionPlane: { on: true, point: [0, 0, 1200], normal: [0, 0, 1] }, levels: [{ id: 0, name: "Ground Floor", elevation: 0 }], weather: { kind: "Snow", intensity: 0.5, season: "Winter", snowCover: 0 }, animations: [] };
  const fake = { notify: null, onNotify(cb) { this.notify = cb; }, async call(m, p) {
    log.push(m);
    if (m === "view3d.info") return info;
    if (m === "model.meshes") return { meshes: [], units: "millimeters" };
    if (m === "view3d.sectionCaps") return { triangleCount: 1, positions: btoa(String.fromCharCode(...new Uint8Array(new Float32Array([0, 0, 1199.5, 1000, 0, 1199.5, 0, 1000, 1199.5]).buffer))), normal: [0, 0, 1] };
    if (m === "select.get") return { ids: [] };
    return {};
  } };
  const host = document.createElement("div"); host.style.cssText = "position:absolute;left:0;top:0;width:400px;height:300px"; document.body.append(host);
  const V = window.harness.view.constructor;
  const v2 = new V(host, { resolveAsset: (p) => "/assets/demo/" + p });
  const b = new window.harness.EngineBridge(v2, fake, {});
  await b.load();
  const st = { style: v2.getStyle(), ortho: v2.getCamera().ortho, caps: v2.scene.capCount, cams: v2.getCameras().length, snow: v2["weather"]?.snow };
  b.host({ action: "view3d", op: "gizmo", mode: "Scale" });
  b.host({ action: "view3d", op: "fov", fov: 30 });
  b.host({ action: "view3d", op: "measure", on: true });
  const after = { gizmo: v2.extras.gizmoMode, measure: v2.extras.measureActive, fov: v2.getCamera().fov };
  v2.dispose(); host.remove();
  return { log, st, after };
});
check("bridge uses view3d.info", bridge.log.includes("view3d.info") && bridge.log.includes("view3d.sectionCaps") && bridge.st.style === "Sketchy" && bridge.st.ortho && bridge.st.caps === 3 && bridge.st.cams === 1 && bridge.st.snow === 0.4, JSON.stringify(bridge.st));
check("bridge view3d host actions", bridge.after.measure && bridge.after.gizmo === "Off" && bridge.after.fov === 30, JSON.stringify(bridge.after));

fs.writeFileSync(path.join(out, "tools-results.json"), JSON.stringify(results, null, 1));
await close();
const failed = results.filter((x) => !x.ok);
console.log(`${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
