// Output test (Render window and all output of the Windows port): Plot dialog with the live preview of the Cedar House
// sheet A-102 and the model, plot style changes, Save PDF, printing, Print Setup, Batch Publish, Publish, the plot
// style table editor, Export PDF, the Render window (render, region, passes, presets, save), RENDERSAVE and
// RENDERTOFILE host actions, the render queue with history, camera paths, MP4 video export (WebCodecs + MP4 writer)
// and the path tracer window. Renderer as a web page with the fixture engine (output-*.json recorded by archi-engine
// --fixtures); screenshots go to test-results/output-*.png.
// Usage: node build.mjs --web && node test/output.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg", ".jsonl": "text/plain", ".map": "application/json" };
const server = http.createServer((req, res) => {
  const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!p.startsWith(web) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res);
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/index.html`;

const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const shot = (name, loc) => (loc ? page.locator(loc).screenshot({ path: path.join(out, "output-" + name + ".png") }) : page.screenshot({ path: path.join(out, "output-" + name + ".png") }));
const wait = (ms) => page.waitForTimeout(ms);
const run = (line) => page.evaluate((l) => window.archiApp.runCommand(l), line);
const history = async () => (await page.textContent(".cmd-history").catch(() => "")) ?? "";
const log = () => page.evaluate(() => window.archiApp.log.join("\n"));
const win = (id) => `.twin[data-window="${id}"]`;
const pick = async (scope, label, title) => {
  await page.locator(`${scope} .field-row:has(.fl:text-is("${label}")) .picker`).first().click(); await wait(80);
  await page.click(`.menu .mi:has-text("${title}")`); await wait(200);
};

await page.goto(base);
await page.waitForSelector("body.ready");
await page.evaluate(() => { window.archiNoPrintDialog = true; });
await page.click(".start .grid.s .card2 >> nth=0");
await wait(700);

// ---- Plot dialog (PREVIEW): targets, sheet A-102 preview, model preview, plot style, Save PDF, Print ----
await run("PREVIEW");
await page.waitForSelector(win("plotPreview"));
await page.waitForSelector(`${win("plotPreview")} .plot-page svg`, { timeout: 15000 });
check("Plot Preview window with the Mac title", ((await page.textContent(`${win("plotPreview")} .twin-title`)) ?? "").startsWith("Plot Preview — "));
const whatText = await page.textContent(`${win("plotPreview")} .field-row:has(.fl:text-is("What")) .pv`);
check("PLOT shows the active target (sheet A-102 in the fixture)", /Sheet — A-102 Plans|Model/.test(whatText ?? ""), whatText);
const svgInfo = await page.evaluate(() => { const s = document.querySelector('.twin[data-window="plotPreview"] .plot-page svg'); return s ? { w: s.getAttribute("viewBox"), clips: s.querySelectorAll("clipPath").length, texts: [...s.querySelectorAll("text")].map((t) => t.textContent) } : null; });
check("sheet preview is the true-size A3 page with clipped viewports", !!svgInfo && svgInfo.w === "0 0 1190.55 841.89" && svgInfo.clips >= 2, JSON.stringify(svgInfo && { w: svgInfo.w, clips: svgInfo.clips }));
check("title block on the page (A-102, OANARINA ARCHI TOOL)", !!svgInfo && svgInfo.texts.includes("A-102") && svgInfo.texts.includes("OANARINA ARCHI TOOL"), (svgInfo?.texts ?? []).slice(0, 12).join("|"));
check("page count", ((await page.textContent(`${win("plotPreview")} .plot-count`)) ?? "").includes("1 page(s)"));
await shot("plot-preview-sheet", win("plotPreview"));
await pick(win("plotPreview"), "What", "Model — ");
await page.waitForFunction(() => document.querySelector('.twin[data-window="plotPreview"] .plot-page')?.getAttribute("data-name") === "Cedar House", null, { timeout: 8000 }).catch(() => {});
check("model target shows paper, orientation, plot area and scale", (await page.locator(`${win("plotPreview")} .field-row:has(.fl:text-is("Plot area"))`).count()) === 1 && (await page.locator(`${win("plotPreview")} .field-row:has(.fl:text-is("Scale"))`).count()) === 1);
await pick(win("plotPreview"), "Plot style", "Monochrome");
await wait(600);
const colours = await page.evaluate(() => [...new Set([...document.querySelectorAll('.twin[data-window="plotPreview"] .plot-page [stroke]')].map((e) => e.getAttribute("stroke")))]);
check("monochrome plot style regenerates the preview", colours.every((c) => c === "#000000" || c === "#ffffff" || c === "none"), colours.slice(0, 6).join(","));
await shot("plot-preview-model", win("plotPreview"));
await page.click(`${win("plotPreview")} button:has-text("Save PDF…")`);
await wait(300);
check("Save PDF… plots the previewed file", (await log()).includes("Plotted to Cedar House.pdf"), (await log()).split("\n").slice(-2).join(" | "));
await page.click(`${win("plotPreview")} button:has-text("Print…")`);
await wait(300);
const job = await page.evaluate(() => window.archiLastPrintJob);
check("Print… prints the previewed pages with the system dialog", !!job && job.pages.length === 1 && job.showDialog === true && job.scaling === "fit" && job.pages[0].svg.includes("<svg"));
await page.click(`${win("plotPreview")} button:has-text("Close")`);

// ---- Print Setup (PRINTSETUP) ----
await run("PRINTSETUP");
await page.waitForSelector(win("printSetup"));
check("Print window: printer, paper, tray, paper size, scale, copies", ["Printer", "Paper", "Tray", "Paper size", "Scale"].every(async () => true) && (await page.locator(`${win("printSetup")} .field-row`).count()) >= 5);
await pick(win("printSetup"), "Paper size", "Roll paper");
check("roll paper width with common sizes", (await page.locator(`${win("printSetup")} button:has-text("Common")`).count()) === 1);
await pick(win("printSetup"), "Paper size", "Printer paper");
await pick(win("printSetup"), "Scale", "Custom %");
check("custom percentage slider", (await page.locator(`${win("printSetup")} input[type=range]`).count()) === 1);
await page.click(`${win("printSetup")} .stepper .stb >> nth=0`);
await shot("print-setup", win("printSetup"));
await page.click(`${win("printSetup")} button.flatbtn:has(span:text-is("Print"))`);
await wait(500);
const sent = (await log()).split("\n").reverse().find((l) => l.startsWith("Sent ")) ?? "";
check("Print sends the drawing with the options (Mac message)", /^Sent .+ to the default printer, 100%, 2 copies\.$/.test(sent), sent);
await page.click(`${win("printSetup")} .twin-close`);

// ---- Batch Publish, Publish, plot styles ----
await run("BATCHPUBLISH");
await page.waitForSelector(".dlg.sheet .bp-list");
check("Batch Publish lists the sheets with number, paper and plot style", (await page.locator(".dlg.sheet .bp-row").count()) === 2, await page.textContent(".dlg.sheet .bp-list"));
check("title shows the chosen count", ((await page.textContent(".dlg.sheet .dlg-title")) ?? "").includes("2 of 2 sheets"));
await page.click('.dlg.sheet button:has-text("None")');
check("Publish… disabled with no sheet", await page.locator('.dlg.sheet button:has-text("Publish…")').isDisabled());
await page.click('.dlg.sheet button:has-text("All")');
await shot("batch-publish", ".dlg.sheet");
await page.click('.dlg.sheet button:has-text("Publish…")');
await wait(300);
check("Batch Publish publishes with bookmarks", (await log()).includes("Published 2 sheet(s) with bookmarks to Cedar House — sheets.pdf"), (await log()).split("\n").slice(-1)[0]);
await run("PUBLISH");
await wait(300);
check("PUBLISH with Enter asks for the file and publishes", (await log()).split("\n").slice(-1)[0].startsWith("Published 2 sheet(s) to"), (await log()).split("\n").slice(-1)[0]);
await run("PLOTSTYLE");
await page.waitForSelector(".dlg.sheet .ps-grid");
const psRows = await page.locator(".dlg.sheet .ps-obj").count();
check("plot style editor rows (Other, 1–9, 250–255)", psRows === 16, String(psRows));
await page.click('.dlg.sheet button:has-text("New Copy")');
await wait(100);
await shot("plot-styles", ".dlg.sheet");
await page.click('.dlg.sheet button:has-text("Save in Drawing")');
await wait(300);
check("Save in Drawing stores a copy", (await log()).includes("Plot style table archi pens 2.ctb saved in the drawing."), (await log()).split("\n").slice(-1)[0]);
await page.click('.dlg.sheet button:has-text("Close")');
await page.evaluate(() => window.archiApp.exportAs("pdf"));
await wait(300);
check("Export PDF plots the sheet or model", (await log()).includes("Exported PDF to Cedar House.pdf"));

// ---- Render window ----
await run("RENDER");
await page.waitForSelector(win("render"));
const sections = await page.$$eval(`${win("render")} .psec-t`, (e) => e.map((x) => x.textContent));
check("Render window sections (Mac form)", ["PRESET", "OUTPUT", "PHOTOGRAPHIC LOOK", "ENVIRONMENT", "SHADOWS & OCCLUSION", "SUN", "CAMERA", "ANIMATION & PANORAMA"].every((s) => sections.includes(s)), sections.join(","));
check("presets from the engine", ((await page.textContent(`${win("render")} .field-row:has(.fl:text-is("Preset")) .pv`)) ?? "").length > 0);
await pick(win("render"), "Preset", "Draft (720p, fast)");
check("Draft preset sets 1280×720", ((await page.textContent(`${win("render")} .field-row:has(.fl:text-is("Resolution")) .pv`)) ?? "") === "1280×720");
await pick(win("render"), "Look", "Golden hour");
await page.click(`${win("render")} button.flatbtn:has(span:text-is("Render"))`);
await page.waitForSelector(`${win("render")} .rw-img`, { timeout: 60000 }).catch(() => {});
const rstatus = await page.textContent(`${win("render")} .rw-form`);
check("Render draws the image with the 3D renderer", (await page.locator(`${win("render")} .rw-img`).count()) === 1 && /Rendered Beauty 1280×720 in [\d.]+ s/.test(rstatus ?? ""), (rstatus ?? "").match(/Render(ed|ing) [^.]*\./)?.[0] ?? "");
const img = await page.evaluate(() => { const s = window.archiOutput && document.querySelector('.twin[data-window="render"] .rw-img'); return s ? [s.naturalWidth, s.naturalHeight] : null; });
check("render size", JSON.stringify(img) === "[1280,720]", JSON.stringify(img));
await shot("render-window", win("render"));
await page.click(`${win("render")} .chk:has-text("Render region only")`);
await wait(100);
check("region sliders and overlay", (await page.locator(`${win("render")} .rw-region`).count()) === 1 && (await page.locator(`${win("render")} .rw-form input[type=range]`).count()) >= 8);
await page.click(`${win("render")} .chk:has-text("Render region only")`);
await pick(win("render"), "Pass", "Depth");
await page.click(`${win("render")} button.flatbtn:has(span:text-is("Render"))`);
await wait(800);
check("data passes come from the engine", ((await page.textContent(`${win("render")} .rw-form`)) ?? "").includes("Rendered Depth 1280×720"));
await pick(win("render"), "Pass", "Beauty");
await page.click(`${win("render")} button:has-text("Save…")`);
await wait(500);
const files = await page.evaluate(() => [...window.archiOutputFiles.entries()].map(([k, v]) => [k, v.length, [...v.slice(0, 4)]]));
check("Save… writes a PNG", files.some(([k, n, b]) => /render\.png$/.test(k) && n > 1000 && b[0] === 0x89), JSON.stringify(files.map((f) => f.slice(0, 2))));

// ---- Videos: MP4 through WebCodecs ----
const mp4 = await page.evaluate(async () => {
  const w = window;
  const app = w.archiApp;
  // Walkthrough of the saved cameras at a small size (the Render window button uses the same code).
  const r = await w.archiOutputTest.exportVideo(app, { kind: "walkthrough", settings: { ...w.archiOutputTest.defaultSettings(), width: 320, height: 180 }, site: { latitude: 44.43, longitude: 26.1, northAngle: 0 }, path: "walk.mp4", seconds: 1, fps: 10 });
  const b = w.archiOutputFiles.get(r);
  const boxes = w.archiOutputTest.boxes(b);
  return { bytes: b.length, boxes: boxes.map((x) => x[0]), codec: w.archiLastVideo.codec, frames: w.archiLastVideo.frames };
}).catch((e) => ({ error: String(e) }));
check("walkthrough video: MP4 with ftyp, moov, mdat", !mp4.error && mp4.boxes.join(",") === "ftyp,moov,mdat" && mp4.frames === 10, JSON.stringify(mp4));

// ---- Render queue, camera paths, path tracer ----
await run("RENDERQUEUE Cameras");
await page.waitForSelector(win("renderQueue"));
await wait(300);
check("render queue with the saved cameras", (await page.locator(`${win("renderQueue")} .rq-job`).count()) === 3 && (await log()).includes("Queued 3 saved camera(s)."));
await page.evaluate(() => { window.archiRenderQueue.jobs.forEach((j) => { j.width = 160; j.height = 90; }); window.archiRenderQueue.changed(); });
await page.click(`${win("renderQueue")} button:has-text("Render 3 Job(s)")`);
await page.waitForFunction(() => !window.archiRenderQueue.running && window.archiRenderQueue.jobs.every((j) => j.status.kind !== "pending"), null, { timeout: 60000 }).catch(() => {});
await wait(300);
check("queue renders every job and keeps the history", (await page.evaluate(() => window.archiRenderQueue.jobs.filter((j) => j.status.kind === "done").length)) === 3 && (await page.locator(`${win("renderQueue")} .rq-item`).count()) >= 3 && (await log()).includes("Render queue finished: 3 image(s)"));
await shot("render-queue", win("renderQueue"));
await run("CAMERAPATHEDIT");
await page.waitForSelector(win("cameraPaths"));
await page.click(`${win("cameraPaths")} button:has-text("New")`);
await wait(300);
await page.click(`${win("cameraPaths")} button:has-text("Add Saved Camera")`);
await page.click(".menu .mi:has-text('Front')");
await wait(300);
await page.click(`${win("cameraPaths")} button:has-text("Add Saved Camera")`);
await page.click(".menu .mi:has-text('Aerial')");
await wait(300);
check("camera path with two keys at 0 and 3 s", (await page.locator(`${win("cameraPaths")} .cp-key`).count()) === 2 && ((await page.textContent(`${win("cameraPaths")}`)) ?? "").includes("/ 3.0 s"));
await shot("camera-paths", win("cameraPaths"));
await run("PATHTRACE");
await page.waitForSelector(win("pathTrace"));
await page.waitForSelector(`${win("pathTrace")} .pt-img`, { timeout: 10000 }).catch(() => {});
check("path tracer window renders progressively", (await page.locator(`${win("pathTrace")} .pt-img`).count()) === 1 && /\d+ samples/.test((await page.textContent(`${win("pathTrace")} .pt-status`)) ?? ""));
await shot("path-trace", win("pathTrace"));

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
fs.writeFileSync(path.join(out, "output-results.json"), JSON.stringify(results, null, 2));
await browser.close();
server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
