// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The shell side of the portable render / material / environment commands (Host/EngineRenderExtras.swift): the host
// actions the engine sends for AODIALOG, MECHANISMPLAY, RENDERPROMPT, PROCMATERIAL and MATFROMIMAGE, on the renderer
// web page with the fixture engine. Screenshots go to test-results/render-extras-*.png.
// Usage: node build.mjs --web && node test/render-extras-ui.mjs
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
const out = path.join(root, "test-results");
fs.mkdirSync(out, { recursive: true });
const web = path.join(root, "dist/renderer");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".jsonl": "text/plain", ".map": "application/json" };
const server = http.createServer((req, res) => {
  const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!p.startsWith(web) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res);
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/index.html`;

const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const wait = (ms) => page.waitForTimeout(ms);
const host = (p) => page.evaluate((x) => window.archiApp.uiHooks.host?.(x) ?? false, p);
const history = async () => (await page.textContent(".cmd-history")) ?? "";

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(600);

// AODIALOG → the Ambient Occlusion window (intensity slider, radius, rays per point, Off / Apply).
check("AODIALOG host action handled", await host({ action: "dialog", dialog: "ambientOcclusion", settings: { intensity: 0.8, radius: 1000, samples: 24, units: "mm", on: true, viewport: { intensity: 0.72, radius: 1 } } }));
await wait(200);
const ao = page.locator('.twin[data-window="ambientOcclusion"]');
check("Ambient Occlusion window opens", await ao.isVisible());
const aoText = (await ao.textContent()) ?? "";
check("Ambient Occlusion window: the Mac's fields", ["Intensity", "Radius", "Rays per point: 24", "Off", "Apply", "mm"].every((t) => aoText.includes(t)), aoText.slice(0, 160));
check("intensity slider 0–2", await ao.locator('input[type="range"]').evaluate((e) => e.min === "0" && e.max === "2" && Math.abs(Number(e.value) - 0.8) < 1e-9));
if (await ao.isVisible()) await page.screenshot({ path: path.join(out, "render-extras-ao-dialog.png"), clip: await ao.boundingBox() });
await ao.locator(".twin-close").click();

// MECHANISMPLAY → the poses play over the plan (accent overlay), then stop.
const accentPixels = () => page.evaluate(() => {
  let n = 0;
  for (const c of document.querySelectorAll("canvas")) {
    if (!c.width || !c.height || c.closest(".twin")) continue;
    let d;
    try { d = c.getContext("2d")?.getImageData(0, 0, c.width, c.height).data; } catch { continue; }
    if (!d) continue;
    for (let i = 0; i < d.length; i += 4) if (d[i] > 220 && d[i + 1] > 170 && d[i + 1] < 215 && d[i + 2] < 90 && d[i + 3] > 200) n++;
  }
  return n;
});
const before = await accentPixels();
const stroke = (dx) => ({ type: "stroke", points: [[2000 + dx, 2000], [12000 + dx, 2000], [12000 + dx, 9000]], closed: false, style: { color: "#f5c518", lineweight: 0.5 } });
check("MECHANISMPLAY host action handled", await host({ action: "canvas", op: "mechanismPlay", poses: [[stroke(0)], [stroke(500)], [stroke(1000)]], fps: 24, mode: "Bounce", maxLoops: 20 }));
await wait(400);
const during = await accentPixels();
check("mechanism poses drawn over the plan in the accent colour", during > before + 50, `accent pixels ${before} → ${during}`);
await page.screenshot({ path: path.join(out, "render-extras-mechanism.png") });
check("mechanism stop handled", await host({ action: "canvas", op: "mechanismStop" }));
await wait(200);
const after = await accentPixels();
check("stopping removes the overlay", after <= before + 5, `accent pixels ${after}`);

// RENDERPROMPT → the "Prompt: …" preset stored and selected, Render window opened.
const preset = { name: "Prompt: golden hour, soft shadows, 4K", width: 3840, height: 2160, antialias: true, exposure: 0, background: "Sky", environment: "Sunset",
  shadowQuality: "High", shadowSoftness: 10, ambientOcclusion: 1, depthOfField: false, fStop: 2.8, whiteBalance: 5200, clay: false, hour: 19.5 };
check("RENDERPROMPT host action handled", await host({ action: "output", op: "renderPrompt", preset }));
await wait(600);
const stored = await page.evaluate(() => ({ presets: JSON.parse(localStorage.getItem("archi.render.presets") ?? "[]"), last: localStorage.getItem("archi.render.lastPreset") }));
check("prompt preset saved and selected", stored.presets.some((p) => p.name === preset.name && p.width === 3840) && stored.last === preset.name, JSON.stringify(stored).slice(0, 200));
check("Render window opens on the prompt preset", await page.isVisible('.twin[data-window="render"]'));
const rw = page.locator('.twin[data-window="render"]');
if (await rw.isVisible()) { await page.screenshot({ path: path.join(out, "render-extras-render-prompt.png"), clip: await rw.boundingBox() }); await rw.locator(".twin-close").click(); }

// PROCMATERIAL / MATFROMIMAGE → the Materials panel's generators (the web page cannot write the maps).
check("PROCMATERIAL host action handled", await host({ action: "materials", op: "procedural", name: "Floor Tile", params: { kind: "Tile", color1: "#E6E6E0", color2: "#9E9E99", tileSize: 600, rows: 4, columns: 4, joint: 0.01, seed: 3 } }));
await wait(800);
check("procedural material reports the Windows-only texture writing on the web page", (await history()).includes("The textures could not be written (Windows app only)."));
check("MATFROMIMAGE host action handled", await host({ action: "materials", op: "fromImage", path: "C:\\photos\\stone.jpg", name: "Stone", tileSize: 800 }));
await wait(300);

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
fs.writeFileSync(path.join(out, "render-extras-ui.json"), JSON.stringify(results, null, 1));
await browser.close(); server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
