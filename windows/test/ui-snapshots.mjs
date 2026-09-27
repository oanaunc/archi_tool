// Renderer UI test: serves dist/renderer (built with `node build.mjs --web`) with the fixture engine, drives it with
// Playwright/Chromium at the Mac window size (1440×900 @2x) and saves screenshots to test-results/.
// Usage: node test/ui-snapshots.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);

await page.goto(base);
await page.waitForSelector("body.ready");
await wait(400);
await shot("start-screen");
check("start screen visible", await page.isVisible(".start .card"));
check("start tiles", (await page.locator(".start .tile").count()) === 3);
check("templates", (await page.locator(".start .grid.t .card2").count()) === 4);

// Cedar House sample (fixture engine opens build/demo-plan.svg's DrawList).
await page.click(".start .grid.s .card2 >> nth=0");
await wait(600);
check("start closes after opening", !(await page.isVisible(".start .card")));
check("title shows document", (await page.textContent(".titlebar .title")).includes("Cedar House — Oanarina Archi Tool"));
await page.mouse.move(700, 600);
await wait(200);
await shot("cedar-plan-home");
const tabs = await page.$$eval(".ribbon-tabs .tab", (els) => els.map((e) => e.textContent));
check("11 ribbon tabs", tabs.join(",") === "Home,Insert,Annotate,Architecture,Modeling,Analyze,Collaborate,View,Output,Manage,Script", tabs.join(","));
for (const t of tabs) {
  await page.click(`.ribbon-tabs .tab:text-is("${t}")`);
  await wait(120);
  await shot(`ribbon-${t.toLowerCase()}`, { clip: { x: 0, y: 0, width: 1440, height: 152 } });
}
await page.click('.ribbon-tabs .tab:text-is("Architecture")');
await page.mouse.move(700, 600);
await wait(150);
await shot("cedar-plan-architecture");
await page.click('.ribbon-tabs .tab:text-is("Home")');

// Status bar toggles.
const before = await page.getAttribute('.statusbar .tog:text-is("ORTHO")', "aria-pressed");
await page.click('.statusbar .tog:text-is("ORTHO")');
await wait(100);
check("ORTHO toggles", (await page.getAttribute('.statusbar .tog:text-is("ORTHO")', "aria-pressed")) !== before);
check("toggle echoed in history", (await page.textContent(".cmd-history")).includes("<Ortho on>"));
await page.click('.statusbar .tog:text-is("ORTHO")');

// Selection: click a wall, grips and properties.
await page.keyboard.press("Escape");
const canvasBox = await page.locator(".workspace canvas.plan >> nth=1").boundingBox();
// Window-select everything in the left third of the view.
await page.mouse.move(canvasBox.x + 40, canvasBox.y + 60);
await page.mouse.down(); await page.mouse.move(canvasBox.x + 500, canvasBox.y + 700, { steps: 8 });
await shot("window-selection-drag");
await page.mouse.up();
await wait(400);
const sel = await page.evaluate(() => window.archiApp.selection);
check("window selection selects objects", sel.ids.length > 0, `${sel.ids.length} selected: ${sel.summary}`);
await page.mouse.move(canvasBox.x + 700, canvasBox.y + 420);
await wait(200);
await shot("selection-grips-properties");
check("properties show the selection", (await page.textContent(".panel-body")).includes("GENERAL") || (await page.textContent(".panel-body")).toUpperCase().includes("GENERAL"));
await page.keyboard.press("Escape");
await wait(300);
check("Esc clears the selection", (await page.evaluate(() => window.archiApp.selection.ids.length)) === 0);

// Command line: type LINE, autocomplete, click points, rubber band preview, keyword chips.
await page.locator(".workspace canvas.plan >> nth=1").focus();
await page.keyboard.type("LI");
await wait(150);
await shot("command-autocomplete", { clip: { x: 0, y: 600, width: 900, height: 300 } });
check("autocomplete shows LINE", (await page.textContent(".suggest")).includes("LINE"));
await page.keyboard.type("NE");
await page.keyboard.press("Enter");
await wait(200);
check("LINE prompt", (await page.textContent(".cmd-input .prompt")).includes("Specify first point"));
await page.mouse.click(canvasBox.x + 300, canvasBox.y + 500);
await wait(150);
await page.mouse.move(canvasBox.x + 520, canvasBox.y + 380, { steps: 6 });
await wait(250);
await shot("line-rubber-band");
check("keyword chip Undo", await page.isVisible('.kw:text-is("Undo")'));
await page.mouse.click(canvasBox.x + 520, canvasBox.y + 380);
await wait(150);
await page.keyboard.press("Escape");
await wait(200);
check("line committed", (await page.textContent(".cmd-history")).includes("Command: LINE"));

// Panels: every tab renders something.
for (const t of ["Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Properties"]) {
  await page.click(`.panel-tabs .ptab:has(.t:text-is("${t}"))`);
  await wait(150);
  if (t === "Layers" || t === "Materials") await shot(`panel-${t.toLowerCase()}`, { clip: { x: 1440 - 301, y: 150, width: 301, height: 600 } });
  check(`panel ${t}`, ((await page.textContent(".panel-body")) ?? "").trim().length > 0);
}

// Levels and sheets (engine fixtures: drawlist-level-1, drawlist-sheet).
await page.click('.statusbar .dropfield >> nth=0');
await page.click('.menu .mi:has-text("Upper Floor")');
await wait(400);
await shot("level-upper-floor");
check("level switch", (await page.textContent(".badge")).includes("Upper Floor"));
await page.click('.statusbar .dropfield >> nth=0');
await page.click('.menu .mi:has-text("Ground Floor")');
await wait(300);
await page.click('.layout-tabs .lt:has-text("Sheet 1")');
await wait(400);
await shot("sheet-1");
check("sheet mode", await page.isVisible('.badge button.sel:text-is("Sheet")'));
await page.click('.layout-tabs .lt:has-text("Model")');
await wait(300);

// Modes.
await page.click('.badge button:text-is("Split")');
await wait(300);
await shot("mode-split");
check("split shows plan and 3D", (await page.locator(".workspace .split").count()) === 1);
// 3D view (view3d/ WebGL 2 module) mounted with the recorded Cedar House meshes (SwiftShader is slow: wait).
await page.click('.badge button:text-is("3D")');
let meshes3d = 0;
for (let k = 0; k < 120 && !meshes3d; k++) { await wait(500); meshes3d = await page.evaluate(() => window.archiView3D?.scene?.meshes?.length ?? 0); }
await wait(1500);
await shot("mode-3d");
check("3D view has a canvas", (await page.locator(".viewport3d canvas").count()) >= 1);
check("3D view shows the model", meshes3d > 0, `${meshes3d} meshes`);
// Menu bar built from docs/windows-parity.json (submenus nest under "submenu").
const menuNames = await page.$$eval(".titlebar .menubar button", (bs) => bs.map((b) => b.textContent));
check("parity menus in the menu bar", menuNames.length >= 8, menuNames.join(","));
await page.click('.badge button:text-is("2D")');
await wait(300);
await page.mouse.move(700, 500);
await wait(150);
await shot("cedar-plan-final");
check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
fs.writeFileSync(path.join(out, "results.json"), JSON.stringify({ date: new Date().toISOString(), results, errors }, null, 1));
await browser.close();
server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
