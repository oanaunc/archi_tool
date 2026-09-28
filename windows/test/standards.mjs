// Graphic standards, printing, clipboard and sharing test (gaps 13, 14 and 30 of docs/WINDOWS-GAPS.md): the Graphic
// Styles, Object Styles, Material Fill Patterns and Image Adjust windows, custom visual styles, the lineweight display
// scale, Paste from Other App, Copy as Picture, Share, Describe Drawing, the AR export, and the printer tray / media
// pickers of Print Setup. Renderer as a web page with the fixture engine (like doctools.mjs); native services are the
// browser fallbacks (window.archiStdRecord) or small stubs. Screenshots go to test-results/standards-*.png.
// Usage: node build.mjs --web && node test/standards.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, "standards-" + name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);
const run = (line) => page.evaluate((l) => window.archiApp.runCommand(l), line);
const history = async () => (await page.textContent(".cmd-history")) ?? "";
const win = (id) => `.twin[data-window="${id}"]`;
const record = () => page.evaluate(() => JSON.parse(JSON.stringify(window.archiStdRecord)));
const shotWin = async (id) => { const b = await page.locator(win(id)).boundingBox(); if (b) await shot(id, { clip: b }); };

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(700);

// ---- Graphic Styles ----
await run("GRAPHICSTYLES");
await page.waitForSelector(win("graphicStyles"), { timeout: 3000 }).catch(() => {});
check("GRAPHICSTYLES opens the Graphic Styles window", await page.isVisible(win("graphicStyles")));
const segs = await page.$$eval(`${win("graphicStyles")} .segmented .seg`, (e) => e.map((x) => x.textContent));
check("five pages like the Mac", segs.join("|") === "Line Styles|Layers|Lineweight by Scale|Pen Sets|Filters", segs.join("|"));
await page.fill(`${win("graphicStyles")} input[placeholder="New line style name"]`, "Walls");
await page.click(`${win("graphicStyles")} .flatbtn:has-text("Add")`);
await wait(200);
check("Add creates a line style row", (await page.$$(`${win("graphicStyles")} input[placeholder^="Colour (ByLayer"]`)).length === 1);
await page.click(`${win("graphicStyles")} .seg:text-is("Lineweight by Scale")`);
await page.fill(`${win("graphicStyles")} .gs-page input.darkfield`, "1:50=1; 1:100=0.7");
await page.click(`${win("graphicStyles")} .flatbtn:has-text("Apply")`);
await wait(200);
check("lineweight table rows", (await page.textContent(`${win("graphicStyles")} .gs-msg`)) === "2 row(s)." && (await page.textContent(`${win("graphicStyles")} .gs-page`)).includes("1:100 → × 0.7"));
await page.click(`${win("graphicStyles")} .seg:text-is("Filters")`);
await page.click(`${win("graphicStyles")} .flatbtn:has-text("Add Rule")`);
await wait(150);
check("a rule needs a value and an override", (await page.textContent(`${win("graphicStyles")} .gs-msg`)) === "Give a value and an override.");
await page.fill(`${win("graphicStyles")} input[placeholder="Value"]`, "A-WALL");
await page.click(`${win("graphicStyles")} .flatbtn:has-text("Add Rule")`);
await wait(200);
const rulesText = await page.textContent(`${win("graphicStyles")} .gs-page`);
check("Add Rule lists the rule with its condition and effect", rulesText.includes("layer = A-WALL") && rulesText.includes("#FF0000"), rulesText.slice(0, 120));
await shotWin("graphicStyles");
await page.click(`${win("graphicStyles")} .twin-close`);

// ---- Object Styles ----
await run("OBJECTSTYLESDIALOG");
await page.waitForSelector(win("objectStyles"), { timeout: 3000 }).catch(() => {});
const osRows = await page.$$(`${win("objectStyles")} .gs-page .gs-row`);
check("Object Styles lists the 17 BIM categories", osRows.length === 17, String(osRows.length));
const cutField = page.locator(`${win("objectStyles")} .gs-page .gs-row >> nth=0`).locator(".gs-wf input >> nth=1");
await cutField.fill("x");
await page.click(`${win("objectStyles")} .flatbtn:has-text("Apply")`);
await wait(200);
check("invalid lineweights are refused like the Mac form", (await page.textContent(`${win("objectStyles")} .gs-msg`)) === "Check: wall: cut lineweight");
await page.locator(`${win("objectStyles")} .gs-page .gs-row >> nth=0`).locator(".gs-wf input >> nth=1").fill("0.7");
await page.click(`${win("objectStyles")} .flatbtn:has-text("Apply")`);
await wait(200);
check("Apply styles the category", (await page.textContent(`${win("objectStyles")} .gs-msg`)) === "1 category styled.");
await shotWin("objectStyles");
await page.click(`${win("objectStyles")} .twin-close`);

// ---- Material Fill Patterns ----
await run("MATPATTERNDIALOG");
await page.waitForSelector(win("matPatterns"), { timeout: 3000 }).catch(() => {});
check("MATPATTERNDIALOG opens with a row per material", (await page.$$(`${win("matPatterns")} .gs-page .gs-row`)).length > 0);
await page.locator(`${win("matPatterns")} .gs-page .gs-row >> nth=0`).locator(".picker >> nth=0").click();
await wait(150);
await page.click('.menu .mi:has-text("ANSI31")');
await page.click(`${win("matPatterns")} .flatbtn:has-text("Apply")`);
await wait(200);
check("Apply changes the pattern", (await page.textContent(`${win("matPatterns")} .gs-msg`)) === "1 pattern changed.");
await shotWin("matPatterns");
await page.click(`${win("matPatterns")} .twin-close`);

// ---- Image Adjust ----
await page.evaluate(() => window.archiApp.engine.call("select.set", { ids: [4242] }));
await run("IMAGEADJUSTDIALOG");
await page.waitForSelector(win("imageAdjust"), { timeout: 3000 }).catch(() => {});
check("IMAGEADJUSTDIALOG opens with three sliders", (await page.$$(`${win("imageAdjust")} input[type=range]`)).length === 3);
await page.locator(`${win("imageAdjust")} input[type=range] >> nth=0`).fill("70");
await page.click(`${win("imageAdjust")} .flatbtn:has-text("Apply")`);
await wait(200);
check("Apply adjusts the image", (await page.textContent(`${win("imageAdjust")} .gs-msg`)) === "1 image adjusted.");
const px = await page.evaluate(() => { const c = document.querySelector('.twin[data-window="imageAdjust"] canvas'); return c ? c.width : 0; });
check("the preview shows the image", px > 0, String(px));
await shotWin("imageAdjust");
await page.click(`${win("imageAdjust")} .twin-close`);

// ---- Custom visual styles ----
await run("VISUALSTYLES New Ghost Shaded Yes 30 No #FF0000");
await wait(200);
await run("VISUALSTYLES Current Ghost");
await wait(500);
const vs = await page.evaluate(() => ({ mode: window.archiApp.mode, custom: window.archiVisualStyles?.custom?.map((c) => c.name), current: window.archiVisualStyleCustom?.name }));
check("VISUALSTYLES Current shows the custom style in the 3D view", vs.mode === "3D" && vs.current === "Ghost" && vs.custom?.includes("Ghost"), JSON.stringify(vs));
await page.evaluate(() => window.archiApp.setUI("mode", "2D"));
await wait(300);

// ---- Lineweight display scale ----
await run("LWDISPLAYSCALE 2");
await wait(200);
check("LWDISPLAYSCALE stores the screen scale", (await page.evaluate(() => localStorage.getItem("archi.lwDisplayScale"))) === "2" && (await history()).includes("Lineweight display scale 2."));
await run("LWDISPLAYSCALE 1");

// ---- Paste from Other App ----
const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><line x1="0" y1="0" x2="100" y2="50" stroke="black"/></svg>';
await page.evaluate((s) => { window.archiTestClipboard = { type: "svg", data: btoa(s) }; dispatchEvent(new Event("focus")); }, svg);
await wait(200);
await run("PASTESPECIAL 0,0");
await wait(400);
check("PASTESPECIAL pastes the SVG another app copied", (await history()).includes("Pasted SVG content."), (await history()).slice(-120));
await page.evaluate(() => { window.archiTestClipboard = null; dispatchEvent(new Event("focus")); });
await wait(200);
await run("PASTESPECIAL 0,0");
await wait(200);
check("PASTESPECIAL with nothing from another app", (await history()).includes("The clipboard holds nothing from another app"));

// ---- Copy as Picture ----
await run("COPYPICTURE");
await wait(800);
const rec1 = await record();
check("COPYPICTURE rasterises the picture (1600 px PNG) for the clipboard", (rec1.picture?.png ?? 0) > 1000 && rec1.picture?.pdfPath?.endsWith(".pdf"), JSON.stringify(rec1.picture));

// ---- Share ----
await run("SHARE Both");
await wait(300);
const rec2 = await record();
check("SHARE hands the project and the PDF to the share sheet", rec2.shared.at(-1)?.length === 2 && /\.archi$/.test(rec2.shared.at(-1)[0]) && /\.pdf$/.test(rec2.shared.at(-1)[1]), JSON.stringify(rec2.shared));
check("the Share window offers Copy Files and Show in Explorer", await page.isVisible(`${win("share")} .flatbtn:has-text("Copy Files")`) && await page.isVisible(`${win("share")} .flatbtn:has-text("Show in Explorer")`));
await shotWin("share");
await page.click(`${win("share")} .flatbtn:has-text("Done")`);

// ---- Describe Drawing ----
await run("SPEAKDRAWING");
await wait(300);
const rec3 = await record();
check("SPEAKDRAWING speaks the description", rec3.spoken.at(-1)?.startsWith("Plan, ") ?? false, rec3.spoken.at(-1));
check("the description is announced to Narrator (live region)", ((await page.textContent(".gs-live")) ?? "").startsWith("Plan, "));

// ---- AR view ----
await run("ARQUICKLOOK Preview");
await wait(200);
check("ARQUICKLOOK opens the real-scale glTF with the default app", (await record()).opened.at(-1)?.endsWith(".glb") ?? false);

// ---- Print Setup: printer trays and media ----
await page.evaluate(() => {
  window.archiOut = { printers: async () => [{ name: "Office Laser", displayName: "Office Laser", isDefault: true, description: "" }], print: async (job) => { window.archiLastNativeJob = job; return { ok: true }; } };
  window.archiStd = { printerCaps: async (name) => ({ trays: [{ value: "JobInputBin|ns|Tray1", title: "Tray 1" }, { value: "JobInputBin|ns|Manual", title: "Manual Feed" }], media: [{ value: "PageMediaType|psk|Photographic", title: "Photo paper" }], papers: [] }) };
});
await run("PRINTSETUP");
await page.waitForSelector(win("printSetup"), { timeout: 3000 }).catch(() => {});
await wait(300);
const trayPicker = page.locator(`${win("printSetup")} .field-row:has(.fl:text-is("Tray")) .picker`);
check("Tray lists the printer's input bins", !(await trayPicker.isDisabled()));
await trayPicker.click();
await wait(150);
await page.click('.menu .mi:has-text("Manual Feed")');
const mediaPicker = page.locator(`${win("printSetup")} .field-row:has(.fl:text-is("Media")) .picker`);
check("Media lists the printer's media types", await mediaPicker.isVisible());
await mediaPicker.click();
await wait(150);
await page.click('.menu .mi:has-text("Photo paper")');
await shotWin("printSetup");
await page.click(`${win("printSetup")} .flatbtn:has-text("Print")`);
await wait(800);
const job = await page.evaluate(() => window.archiLastNativeJob ?? null);
check("the print job carries the tray and media", job?.tray === "JobInputBin|ns|Manual" && job?.mediaType === "PageMediaType|psk|Photographic", JSON.stringify({ tray: job?.tray, media: job?.mediaType }));
check("the history names the tray", (await history()).includes("tray Manual"), (await history()).slice(-120));

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
