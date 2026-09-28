// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// 3D look and render parity (round 4), on the renderer web page with the fixture engine:
// - render.preset / RENDERPRESET switch the interactive 3D view to Realistic with the preset's look (BeautyRender.swift:
//   m.viewStyle = "Realistic"; Scene3DBuilder reads BeautyPreset.current(doc)), mark the drawing changed like the Mac
//   command, and "Off" returns to the default Realistic look;
// - the status bar keeps the plan's zoom while the 3D view is shown (the Mac CanvasView keeps its scale);
// - the drawing compare overlay (CompareOverlay.draw) is painted by the plan canvas in world coordinates;
// - the Render window environments are the Mac gradient maps (EnvironmentMaps.image) and the Physical Sky;
// - 360° panoramas use the Render window scene (RenderEngine.panorama), not the photographic preset.
// Screenshots: test-results/render-match-r4/.
// Usage: node build.mjs --web && node test/render-r4.mjs
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
let pw;
for (const m of ["playwright-core", "playwright", process.env.PLAYWRIGHT_MODULE].filter(Boolean)) { try { pw = require(m); break; } catch {} }
if (!pw) throw new Error("playwright-core not found (npm i -D playwright-core, or set PLAYWRIGHT_MODULE)");
const out = path.join(root, "test-results/render-match-r4");
fs.mkdirSync(out, { recursive: true });
const web = path.join(root, "dist/renderer");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg", ".jsonl": "text/plain", ".map": "application/json" };
const server = http.createServer((req, res) => {
  const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!p.startsWith(web) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res);
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/index.html`;

const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const wait = (ms) => page.waitForTimeout(ms);
const zoomText = () => page.evaluate(() => document.querySelector(".statusbar .zoom, .zoom")?.textContent ?? "");
const title = () => page.evaluate(() => window.archiApp.windowTitle);
/** Mean sRGB colour of the 3D canvas (a band of rows, fractions of the height). */
const canvasMean = (y0 = 0, y1 = 1) => page.evaluate(([a, b]) => {
  const v = window.archiView3D; v.drawNow?.();
  const c = v.canvas, cv = document.createElement("canvas");
  cv.width = c.width; cv.height = c.height;
  const g = cv.getContext("2d"); g.drawImage(c, 0, 0);
  const d = g.getImageData(0, Math.floor(a * c.height), c.width, Math.max(1, Math.floor((b - a) * c.height))).data;
  let r = 0, gg = 0, bb = 0, n = 0;
  for (let i = 0; i < d.length; i += 16) { r += d[i]; gg += d[i + 1]; bb += d[i + 2]; n++; }
  return [r / n, gg / n, bb / n].map((x) => Math.round(x * 10) / 10);
}, [y0, y1]);
const shot3D = async (name) => { const b = await page.locator(".workspace").boundingBox(); await page.screenshot({ path: path.join(out, name), clip: b }); };

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await page.waitForFunction(() => /Cedar House/.test(window.archiApp.windowTitle), null, { timeout: 30000 });
await wait(800);

// ---- status bar zoom: the plan's scale stays while 3D is shown ----
await page.evaluate(() => window.archiApp.setUI("mode", "2D"));
await wait(1200);
const z2 = await zoomText();
await page.evaluate(() => window.archiApp.setUI("mode", "3D"));
await page.waitForFunction(() => window.archiView3D && !window.archiView3D.scene.empty, null, { timeout: 120000 });
await wait(2500);
const z3 = await zoomText();
check("status bar Zoom in 3D is the plan's (Mac CanvasView keeps its scale)", z2 && z3 === z2, `2D "${z2}", 3D "${z3}"`);
await page.evaluate(() => window.archiApp.setUI("mode", "2D"));
await wait(800);
check("back in 2D the plan zoom is unchanged", (await zoomText()) === z2, await zoomText());
await page.evaluate(() => window.archiApp.setUI("mode", "3D"));
await wait(1500);

// ---- render.preset → Realistic with the preset look, drawing changed ----
const style0 = await page.evaluate(() => window.archiView3D.getStyle());
const dirty0 = / •/.test(await title());
const before = await canvasMean(0, 1);
await shot3D("interactive-before-preset.png");
await page.evaluate(() => window.archiApp.tryCall("render.preset", { name: "Goldenhour" }));
await page.waitForFunction(() => window.archiView3D.getStyle() === "Realistic" && window.archiView3D.getLook().preset === "Golden hour", null, { timeout: 20000 }).catch(() => {});
await wait(4000);
const st = await page.evaluate(() => ({ style: window.archiView3D.getStyle(), preset: window.archiView3D.getLook().preset, explicit: window.archiView3D.explicit, sunAlt: window.archiView3D.getLook().sunAltitude }));
check("render.preset switches the 3D view to Realistic (was " + style0 + ")", st.style === "Realistic", JSON.stringify(st));
check("the view shows the Golden hour look (explicit preset: sun 11° high, sky, haze, meadow)", st.preset === "Golden hour" && st.explicit === true && st.sunAlt === 11, JSON.stringify(st));
const after = await canvasMean(0, 1);
const sky = await canvasMean(0.02, 0.2);
await shot3D("interactive-golden-hour.png");
check("the frame turns warm (red over blue) like the Mac's golden hour", after[0] > after[2] + 8, `mean before ${before} → after ${after}; sky band ${sky}`);
check("the style picker shows Realistic", await page.evaluate(() => [...document.querySelectorAll(".v3d *")].some((e) => e.children.length === 0 && /^Realistic/.test(e.textContent?.trim() ?? ""))));
check("setting a preset marks the drawing changed (as the Mac RENDERPRESET command)", !dirty0 && / •/.test(await title()), await title());

// ---- Off: the default Realistic look ----
await page.evaluate(async () => {
  await window.archiApp.tryCall("view3d.setVariable", { name: "RENDERPRESET", value: null });
  document.dispatchEvent(new CustomEvent("archi:host", { detail: { action: "setViewStyle", style: "Realistic" } }));
});
await wait(2500);
const off = await page.evaluate(() => ({ style: window.archiView3D.getStyle(), explicit: window.archiView3D.explicit }));
check("RENDERPRESET Off: Realistic without a preset (default daylight look)", off.style === "Realistic" && off.explicit === false, JSON.stringify(off));
await shot3D("interactive-preset-off.png");
await page.evaluate(() => window.archiApp.tryCall("render.preset", { name: "Overcast" }));
await wait(3500);
check("Overcast preset follows too", await page.evaluate(() => window.archiView3D.getLook().preset === "Overcast" && window.archiView3D.explicit));
await shot3D("interactive-overcast.png");

// ---- Render window environments: the Mac gradient maps ----
const maps = await page.evaluate(() => {
  const R = window.archiRenderScene;
  if (!R) return null;
  const px = (img, u, v) => { const x = Math.min(img.width - 1, Math.floor(u * img.width)), y = Math.min(img.height - 1, Math.floor(v * img.height)); const i = (y * img.width + x) * 4; return [img.data[i], img.data[i + 1], img.data[i + 2]]; };
  const s = (l) => l.map((c) => Math.round(255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055)));
  const out = {};
  for (const n of ["Clear Sky", "Overcast", "Sunset", "Studio", "Night"]) {
    const img = R.gradientEnvironment(n);
    out[n] = { size: [img.width, img.height], zenith: s(px(img, 0.9, 0.001)), horizonUp: s(px(img, 0.9, 0.499)), horizonDown: s(px(img, 0.9, 0.501)), nadir: s(px(img, 0.9, 0.999)), glow: s(px(img, 0.3, 0.44)) };
  }
  const ps = R.physicalSkyEnvironment([0.3, 0.3, 0.9]);
  out.physical = { size: [ps.width, ps.height], zenith: s(px(ps, 0.5, 0.001)), ground: s(px(ps, 0.5, 0.9)) };
  return out;
});
if (maps) {
  const near = (a, b, t = 2) => a.every((v, i) => Math.abs(v - b[i]) <= t);
  const S = (c) => c.map((v) => Math.round(v * 255));
  check("Clear Sky map: zenith (0.24, 0.45, 0.78), horizon (0.78, 0.86, 0.94), ground (0.36, 0.35, 0.32)",
    near(maps["Clear Sky"].zenith, S([0.24, 0.45, 0.78])) && near(maps["Clear Sky"].horizonUp, S([0.78, 0.86, 0.94])) && near(maps["Clear Sky"].nadir, S([0.36, 0.35, 0.32])), JSON.stringify(maps["Clear Sky"]));
  check("below the horizon: the horizon / ground mix", near(maps["Clear Sky"].horizonDown, S([0.57, 0.605, 0.63])), JSON.stringify(maps["Clear Sky"].horizonDown));
  check("Sunset map: the sun glow left of centre above the horizon", maps.Sunset.glow[0] > 240 && maps.Sunset.glow[2] > 120, JSON.stringify(maps.Sunset));
  check("Night map: dark blue zenith (0.02, 0.03, 0.07)", near(maps.Night.zenith, S([0.02, 0.03, 0.07])), JSON.stringify(maps.Night));
  check("maps are 1024 × 512", maps["Clear Sky"].size.join("x") === "1024x512" && maps.physical.size.join("x") === "1024x512");
  check("Physical Sky: blue zenith, grey ground (SkyModel)", maps.physical.zenith[2] > maps.physical.zenith[0] && Math.abs(maps.physical.ground[0] - maps.physical.ground[1]) < 12, JSON.stringify(maps.physical));
} else check("render-scene module exposed for tests", false);

// ---- 360° panorama: the Render window scene (clear sky gradient), not the preset sky ----
const pano = await page.evaluate(async () => {
  const v = window.archiView3D;
  const c = v.scene.center;
  const blob = await v.panorama({ eye: [c[0], c[1] - 30000, 1600], width: 512, format: "PNG" });
  const bmp = await createImageBitmap(blob);
  const cv = document.createElement("canvas"); cv.width = bmp.width; cv.height = bmp.height;
  const g = cv.getContext("2d"); g.drawImage(bmp, 0, 0);
  const d = g.getImageData(0, 0, cv.width, 8).data;
  let r = 0, gg = 0, b = 0, n = 0;
  for (let i = 0; i < d.length; i += 4) { r += d[i]; gg += d[i + 1]; b += d[i + 2]; n++; }
  const url = cv.toDataURL("image/png");
  return { w: cv.width, h: cv.height, zenith: [r / n, gg / n, b / n].map(Math.round), url };
});
fs.writeFileSync(path.join(out, "panorama-default.png"), Buffer.from(pano.url.split(",")[1], "base64"));
check("PANORAMA is 2:1", pano.w === 512 && pano.h === 256, `${pano.w}×${pano.h}`);
check("panorama zenith is the Clear Sky map's (blue), not the Overcast preset's grey", pano.zenith[2] > pano.zenith[0] + 30, JSON.stringify(pano.zenith));

// ---- compare overlay painted by the plan canvas ----
await page.evaluate(() => window.archiApp.setUI("mode", "2D"));
await wait(800);
await page.evaluate(() => window.archiApp.uiHooks.ui?.("window:CompareWindow"));
await wait(400);
const ov = await page.evaluate(() => {
  const o = window.archiCompareOverlay;
  if (!o) return null;
  const c = window.archiApp.info?.extents ?? [0, 0, 20000, 15000];
  const cx = (c[0] + c[2]) / 2, cy = (c[1] + c[3]) / 2, r = Math.min(c[2] - c[0], c[3] - c[1]) / 6;
  const sq = (x, y, k) => [[x - k, y - k], [x + k, y - k], [x + k, y + k], [x - k, y + k], [x - k, y - k]];
  o.set({ colors: { added: "#1acc33", removed: "#e6261a", modified: "#f5c417" }, counts: { added: 1, removed: 1, modified: 0 },
    shapes: [{ kind: "added", polylines: [sq(cx - r, cy, r * 0.8)], type: "Line", id: 1, layer: "0" }, { kind: "removed", polylines: [sq(cx + r, cy, r * 0.8)], type: "Line", id: 2, layer: "0" }] }, "old.archi");
  return true;
});
await wait(500);
const counts = () => page.evaluate(() => {
  let g = 0, rr = 0;
  for (const c of document.querySelectorAll(".workspace canvas")) {
    let d; try { d = c.getContext("2d")?.getImageData(0, 0, c.width, c.height).data; } catch { continue; }
    if (!d) continue;
    for (let i = 0; i < d.length; i += 4) { if (d[i] < 60 && d[i + 1] > 170 && d[i + 2] < 90 && d[i + 3] > 200) g++; if (d[i] > 200 && d[i + 1] < 70 && d[i + 2] < 60 && d[i + 3] > 200) rr++; }
  }
  return { green: g, red: rr };
});
const c1 = await counts();
check("compare overlay: added (green) and removed (red, dashed) outlines drawn over the plan", ov && c1.green > 200 && c1.red > 100, JSON.stringify(c1));
await page.screenshot({ path: path.join(out, "compare-overlay.png"), clip: await page.locator(".workspace").boundingBox() });
await page.evaluate(() => window.archiApp.canvas?.zoomBy?.(1.5));
await wait(300);
const c2 = await counts();
check("the overlay follows the plan view (zoom)", c2.green > c1.green, `${JSON.stringify(c1)} → ${JSON.stringify(c2)}`);
await page.evaluate(() => { const o = window.archiCompareOverlay; o.visible = false; o.refresh(); });
await wait(300);
const c3 = await counts();
check("Overlay off hides it", c3.green < 20 && c3.red < 20, JSON.stringify(c3));

// ---- Render window without a look: each environment map lights and backs the render (RenderEngine.makeScene) ----
// Eye-level Front camera so the environment shows as the sky (the Render window renders the 3D view's camera).
await page.evaluate(() => window.archiApp.setUI("mode", "3D"));
await wait(800);
await page.evaluate(() => window.archiView3D.applyNamedCamera("Front", false));
await wait(300);
await page.evaluate(() => window.archiApp.runCommand("RENDER"));
const rw = '.twin[data-window="render"]';
await page.waitForSelector(rw, { timeout: 20000 });
const pickIn = async (label, title) => {
  await page.locator(`${rw} .field-row:has(.fl:text-is("${label}")) .picker`).first().click(); await wait(80);
  await page.click(`.menu .mi:has-text("${title}")`); await wait(200);
};
await pickIn("Preset", "Draft (720p, fast)");
await pickIn("Look", "Custom (settings below)");
const envMeans = {};
for (const e of ["Clear Sky", "Sunset", "Overcast", "Studio", "Night", "Physical Sky"]) {
  await pickIn("Lighting", e);
  await page.evaluate(() => document.querySelector('.twin[data-window="render"] .rw-img')?.remove());
  await page.click(`${rw} button.flatbtn:has(span:text-is("Render"))`);
  await page.waitForSelector(`${rw} .rw-img`, { timeout: 120000 }).catch(() => {});
  const r = await page.evaluate(() => {
    const im = document.querySelector('.twin[data-window="render"] .rw-img');
    if (!im || !im.naturalWidth) return null;
    const cv = document.createElement("canvas"); cv.width = im.naturalWidth; cv.height = im.naturalHeight;
    const g = cv.getContext("2d"); g.drawImage(im, 0, 0);
    const top = g.getImageData(0, 0, cv.width, Math.floor(cv.height * 0.12)).data;
    let r = 0, gg = 0, b = 0, n = 0;
    for (let i = 0; i < top.length; i += 16) { r += top[i]; gg += top[i + 1]; b += top[i + 2]; n++; }
    return { url: cv.toDataURL("image/jpeg", 0.85), w: cv.width, h: cv.height, sky: [r / n, gg / n, b / n].map(Math.round) };
  });
  if (r) fs.writeFileSync(path.join(out, `render-window-${e.toLowerCase().replace(/ /g, "-")}.jpg`), Buffer.from(r.url.split(",")[1], "base64"));
  envMeans[e] = r ? r.sky : null;
}
console.log("render window sky (top 12 %):", JSON.stringify(envMeans));
const em = envMeans;
check("Render window renders with every environment", Object.values(em).every((v) => v), JSON.stringify(em));
if (Object.values(em).every((v) => v)) {
  check("Clear Sky: blue gradient sky", em["Clear Sky"][2] > em["Clear Sky"][0] + 20, JSON.stringify(em["Clear Sky"]));
  check("Overcast and Studio: neutral grey skies", Math.abs(em.Overcast[0] - em.Overcast[2]) < 12 && Math.abs(em.Studio[0] - em.Studio[2]) < 12, `${em.Overcast} / ${em.Studio}`);
  check("Night: dark sky", Math.max(...em.Night) < 60, JSON.stringify(em.Night));
  check("Sunset: warm sky near the horizon (orange horizon and sun glow of the map)", em.Sunset[0] > em.Sunset[2] + 20, JSON.stringify(em.Sunset));
}
await page.locator(`${rw} .twin-close`).click().catch(() => {});

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
fs.writeFileSync(path.join(out, "render-r4.json"), JSON.stringify({ results, zoom: { plan: z2, view3d: z3 }, colours: { before, after, sky }, renderWindowSky: envMeans }, null, 1));
await browser.close(); server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
