// Tool windows test (part B of the Windows port): JavaScript console (V8 worker with synchronous engine calls), script
// panels, Block Library, Material Library and the Materials panel, Sheet Set Manager and Title Block, Markups / Compare /
// Revision Clouds, Family Editor, Customizer, Node Editor and Graph Player, Connect Claude and the AI Agents ribbon
// block, the tutorial commands. Renderer as a web page with the fixture engine; the page is served cross-origin
// isolated (COOP/COEP) so the script worker can block on SharedArrayBuffer like the Electron main-process worker.
// Screenshots go to test-results/tools-*.png.
// Usage: node build.mjs --web && node test/partb-tools.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
  res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream", "cross-origin-opener-policy": "same-origin", "cross-origin-embedder-policy": "require-corp", "cross-origin-resource-policy": "same-origin" });
  fs.createReadStream(p).pipe(res);
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/index.html`;

const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const wait = (ms) => page.waitForTimeout(ms);
const win = (key) => page.locator(`.pb-win[data-window="${key}"]`);
const shotWin = async (key, name) => { const b = await win(key).boundingBox(); if (b) await page.screenshot({ path: path.join(out, `tools-${name}.png`), clip: b }); };
const host = (p) => page.evaluate((x) => window.archiApp.uiHooks.host(x), p);
const history = async () => (await page.textContent(".cmd-history").catch(() => "")) ?? "";
const ribbonTab = async (t) => { await page.click(`.ribbon-tabs .tab:text-is("${t}")`); await wait(150); };
const ribbonButton = (t) => page.click(`.ribbon-body .rbtn:has(.t:text-is("${t}"))`);
const closeWin = async (key) => { await win(key).locator(".pb-close").click(); await wait(80); };

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(700);
check("page is cross-origin isolated (script worker)", await page.evaluate(() => self.crossOriginIsolated === true));

// ---- JavaScript console ----
await ribbonTab("Script");
await ribbonButton("JS Console");
await wait(200);
check("JS Console opens from the ribbon", await page.isVisible(".pb-console"));
await page.evaluate(() => { const t = document.querySelector(".pb-console textarea"); t.value = 'archi.print("sum", 1 + 1);\nconst s = archi.summary();\narchi.print(typeof s);\n6 * 7'; t.dispatchEvent(new Event("input")); });
await page.click('.pb-console .pb-btn:has-text("Run")');
await page.waitForFunction(() => /42/.test(document.querySelector(".pb-console .pb-out")?.textContent ?? ""), null, { timeout: 8000 }).catch(() => {});
const outText = (await page.textContent(".pb-console .pb-out")) ?? "";
check("console runs JavaScript with archi.print and a synchronous engine call", /sum 2/.test(outText) && /object/.test(outText) && /42/.test(outText), outText.replace(/\s+/g, " ").slice(0, 160));
await page.screenshot({ path: path.join(out, "tools-console.png"), clip: await page.locator(".pb-console").boundingBox() });
await page.evaluate(() => { const t = document.querySelector(".pb-console textarea"); t.value = 'function build(v) { archi.print("rise", v.rise); }\narchi.panel({ title: "Stairs", items: [{ type: "number", name: "rise", label: "Rise", value: 175 }, { type: "button", label: "Build", call: "build" }] });'; t.dispatchEvent(new Event("input")); });
await page.click('.pb-console .pb-btn:has-text("Run")');
await page.waitForSelector('.pb-win[data-window="script:Stairs"]', { timeout: 5000 }).catch(() => {});
check("archi.panel opens a script panel", await win("script:Stairs").isVisible());
if (await win("script:Stairs").isVisible()) {
  await win("script:Stairs").locator('.pb-btn:has-text("Build")').click();
  await page.waitForFunction(() => /rise 175/.test(document.querySelector(".cmd-history")?.textContent ?? ""), null, { timeout: 5000 }).catch(() => {});
  check("script panel button calls the global function with the values", /rise 175/.test(await history()));
  await shotWin("script:Stairs", "script-panel");
  await closeWin("script:Stairs");
}
await ribbonButton("JS Console");
await wait(100);
check("JS Console toggles off", !(await page.isVisible(".pb-console")));

// ---- AI Agents and Connect Claude ----
check("AI Agents ribbon block shows the server state", /Stopped|Listening/.test((await page.textContent(".ribbon-body .agent-status")) ?? ""));
await ribbonButton("Connect Claude");
await wait(250);
check("Connect Claude sheet opens", await page.isVisible('.pb-sheet[data-sheet="connectClaude"]'));
if (await page.isVisible('.pb-sheet[data-sheet="connectClaude"]')) {
  const t = (await page.textContent('.pb-sheet[data-sheet="connectClaude"]')) ?? "";
  check("Connect Claude shows the archi-engine --mcp configuration", /--mcp/.test(t) && /mcpServers/.test(t));
  await page.screenshot({ path: path.join(out, "tools-connect-claude.png"), clip: await page.locator('.pb-sheet[data-sheet="connectClaude"]').boundingBox() });
  await page.keyboard.press("Escape");
  await page.evaluate(() => document.querySelectorAll(".pb-sheet-overlay").forEach((e) => e.remove()));
}

// ---- Block Library (ribbon ui target) ----
await ribbonTab("Insert");
await ribbonButton("Block Library");
await wait(250);
check("Block Library opens from the ribbon", await win("blockLibrary").isVisible());
check("Block Library shows Folder / Favourites / Recent", /Folder/.test((await win("blockLibrary").textContent()) ?? "") && /Favourites/.test((await win("blockLibrary").textContent()) ?? ""));
await shotWin("blockLibrary", "block-library");
await closeWin("blockLibrary");

// ---- Material Library and the Materials panel ----
await ribbonButton("Materials");
await wait(300);
check("Material Library opens from the ribbon", await win("materialLibrary").isVisible());
await shotWin("materialLibrary", "material-library");
await closeWin("materialLibrary");
await page.evaluate(() => { const a = window.archiApp; a.showPanels = true; a.setUI("panelTab", "Materials"); });
await wait(500);
const matText = (await page.textContent(".panel-body")) ?? "";
check("Materials panel lists the drawing's materials", /Concrete|Brick|Wood/.test(matText), matText.slice(0, 80));
await page.screenshot({ path: path.join(out, "tools-materials-panel.png"), clip: await page.locator(".panels").boundingBox() });

// ---- Sheet Set Manager and Title Block ----
await page.evaluate(() => window.archiApp.setUI("panelTab", "Sheets"));
await wait(500);
const sheetText = (await page.textContent(".panel-body")) ?? "";
check("Sheets panel is the Sheet Set Manager", /Sheet/.test(sheetText) && /(Index|Revision|Renumber|New)/.test(sheetText), sheetText.slice(0, 80));
await page.screenshot({ path: path.join(out, "tools-sheet-set.png"), clip: await page.locator(".panels").boundingBox() });
await host({ action: "dialog", dialog: "titleBlock", layout: 0 });
await wait(400);
const tb = page.locator(".pb-sheet").last();
check("Title Block sheet opens", await tb.isVisible().catch(() => false));
if (await tb.isVisible().catch(() => false)) { await page.screenshot({ path: path.join(out, "tools-title-block.png"), clip: await tb.boundingBox() }); await page.keyboard.press("Escape"); }
await page.evaluate(() => document.querySelectorAll(".pb-sheet-overlay").forEach((e) => e.remove()));

// ---- Review: Markups, Compare, Revision Clouds ----
await ribbonTab("Collaborate");
await ribbonButton("Markups");
await wait(300);
check("Markups window opens from the ribbon", await win("markups").isVisible());
check("Markups has Open / Resolved / All and Around Selection", /Resolved/.test((await win("markups").textContent()) ?? "") && /Around Selection/.test((await win("markups").textContent()) ?? ""));
await shotWin("markups", "markups");
await closeWin("markups");
await ribbonButton("Compare");
await wait(200);
check("Compare Drawings window opens", await win("compare").isVisible());
await shotWin("compare", "compare");
await closeWin("compare");
await ribbonButton("Revision Clouds");
await wait(400);
check("Revision Clouds window opens", await win("revisionClouds").isVisible());
await shotWin("revisionClouds", "revision-clouds");
await closeWin("revisionClouds");

// ---- Family Editor ----
await host({ action: "dialog", dialog: "familyEditor" });
await wait(400);
check("Family Editor opens (host dialog familyEditor)", await win("familyEditor").isVisible());
await win("familyEditor").locator('.pb-btn:has-text("New from Template")').click();
await wait(100);
await page.click('.menu .mi:has-text("Furniture"), .pb-menu .mi:has-text("Furniture"), [role=menuitem]:has-text("Furniture")').catch(() => {});
await wait(800);
const fe = (await win("familyEditor").textContent()) ?? "";
check("Furniture template: parameters, forms and the evaluated size", /Width/.test(fe) && /Size 1600 × 900 × 750/.test(fe), fe.match(/Size[^A-Za-z]*/)?.[0] ?? "");
await shotWin("familyEditor", "family-editor");
await closeWin("familyEditor");

// ---- Customizer ----
await host({ action: "dialog", dialog: "customizer" });
await wait(300);
check("Customizer opens and asks for a scripted object", await win("customizer").isVisible() && /scripted object/.test((await win("customizer").textContent()) ?? ""));
await shotWin("customizer", "customizer");
await closeWin("customizer");

// ---- Node Editor and Graph Player ----
await ribbonTab("Modeling");
await ribbonButton("Node Editor");
await wait(600);
check("Node Editor opens from the ribbon", await win("nodeEditor").isVisible());
await shotWin("nodeEditor", "node-editor");
await closeWin("nodeEditor");
await host({ action: "dialog", dialog: "graphPlayer" });
await wait(300);
check("Graph Player opens", await win("graphPlayer").isVisible());
if (await win("graphPlayer").isVisible()) { await shotWin("graphPlayer", "graph-player"); await closeWin("graphPlayer"); }

// ---- Tutorials ----
await host({ action: "tutorials", mode: "List" });
await wait(200);
check("TUTORIALRECORD List answers in the command history", /tutorial/i.test(await history()));
const opened = await page.evaluate(() => { let u = ""; const o = window.open; window.open = (x) => { u = String(x); return null; }; window.archiApp.uiHooks.host({ action: "tutorials", mode: "Open" }); window.open = o; return new Promise((r) => setTimeout(() => r(u), 100)); });
check("TUTORIALS opens the tutorial videos on the website", opened.startsWith("https://www.oanarinaldi.com/"), opened);

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
await browser.close();
server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
