// Contextual ribbon tabs, sheet commands, crash recovery and file versions (gaps 7, 12, 15, 16 of docs/WINDOWS-GAPS.md):
// the accent strip under the ribbon for walls / windows / text …, the start screen's RECOVERED DOCUMENTS, the Versions
// window, LAYOUTTABS, ZOOMXP, SHEETIMAGE and PSETUPIN host actions. Renderer as a web page with the fixture engine;
// screenshots go to test-results/sheets-*.png.
// Usage: node build.mjs --web && node test/sheets.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const ui = JSON.parse(fs.readFileSync(path.join(root, "src/renderer/data/ui.generated.json"), "utf8"));

const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, "sheets-" + name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);
const run = async (line) => { await page.evaluate((l) => window.archiApp.runCommand(l), line); await wait(250); };
const history = async () => (await page.textContent(".cmd-history")) ?? "";
const call = (m, p = {}) => page.evaluate(([a, b]) => window.archiApp.engine.call(a, b), [m, p]);
const select = async (ids) => { await call("select.set", { ids }); await page.evaluate(() => window.archiApp.refresh(["selection"])); await wait(300); };
const strip = async () => page.evaluate(() => {
  const el = document.querySelector(".ctx-strip");
  if (!el || el.style.display === "none" || !el.isConnected) return null;
  return { title: el.querySelector(".ctx-title")?.textContent, buttons: [...el.querySelectorAll(".ctx-btn")].map((b) => b.textContent.trim()), commands: [...el.querySelectorAll(".ctx-btn")].map((b) => b.dataset.command),
    bg: getComputedStyle(el).backgroundColor, chip: getComputedStyle(el.querySelector(".ctx-title")).backgroundColor, h: el.getBoundingClientRect().height,
    underRibbon: el.previousElementSibling?.classList.contains("ribbon") ?? false };
});

await page.addInitScript(() => { window.__archiFakeRecovered = [{ id: "r1", name: "Cedar House", dateText: "27 Sep 2026 at 21:14", originalPath: "Cedar House.archi" }]; });
await page.goto(base);
await page.waitForSelector("body.ready");
await wait(400);

// ---- crash recovery on the start screen ----
const rec = await page.evaluate(() => {
  const s = document.querySelector(".start .rec-section");
  return s ? { head: s.querySelector(".rec-head")?.textContent, rows: [...s.querySelectorAll(".rec-row")].map((r) => r.textContent), buttons: [...s.querySelectorAll(".rec-row button")].map((b) => b.textContent),
    beforeTip: s.nextElementSibling?.classList.contains("tip") ?? false } : null;
});
check("start screen lists RECOVERED DOCUMENTS", rec?.head?.includes("RECOVERED DOCUMENTS") && rec.rows.length === 1 && rec.rows[0].includes("Cedar House"), JSON.stringify(rec));
check("recovered row has Restore and Discard, above the tip", JSON.stringify(rec?.buttons) === JSON.stringify(["Restore", "Discard"]) && rec.beforeTip, JSON.stringify(rec?.buttons));
await shot("start-recovery", { clip: { x: 260, y: 150, width: 920, height: 600 } });
await page.click(".start .rec-row button.prominent");
await wait(900);
const afterRestore = await page.evaluate(() => ({ start: document.querySelector(".start")?.style.display, dirty: window.archiApp.info?.dirty, mode: window.archiApp.mode }));
check("Restore opens the recovered drawing unsaved", afterRestore.start === "none" && afterRestore.dirty === true && afterRestore.mode === "2D", JSON.stringify(afterRestore));
check("restore message on the command line", (await history()).includes("Recovered “Cedar House” from the autosave"), (await history()).slice(-160));
await run("DRAWINGRECOVERY");
check("DRAWINGRECOVERY with nothing left", (await history()).includes("No recovered documents."));

// ---- contextual ribbon tabs ----
const sched = await call("schedule.get", { kind: "all" });
const idsOf = (type, n) => (sched.rows ?? []).slice(1).filter((r) => r[1] === type).slice(0, n).map((r) => Number(r[0]));
const walls = idsOf("wall", 3), wins = idsOf("window", 2);
check("no strip without a selection", (await strip()) === null);
await select(walls);
const sw = await strip();
check("walls selected → MODIFY WALL", sw?.title === "MODIFY WALL", JSON.stringify(sw));
const macWall = ui.contextualTabs.find((t) => t.selection === "Wall").items.map((i) => i.title);
check("Modify Wall has the Mac buttons in order", JSON.stringify(sw?.buttons) === JSON.stringify(macWall.filter((t) => sw?.buttons.includes(t))) && sw.buttons.length >= 10, JSON.stringify(sw?.buttons));
check("strip look: accent chip, 14 % accent band, 22 px, directly under the ribbon", sw?.chip === "rgb(245, 197, 24)" && /rgba\(245, 197, 24, 0\.14/.test(sw?.bg ?? "") && Math.round(sw?.h) === 22 && sw.underRibbon, JSON.stringify(sw));
await shot("context-wall", { clip: { x: 0, y: 0, width: 1440, height: 170 } });
await select(wins);
const swin = await strip();
check("windows selected → MODIFY WINDOW (Properties, Set Property, Opening Parts …)", swin?.title === "MODIFY WINDOW" && swin.buttons.slice(0, 3).join("|") === "Properties|Set Property|Opening Parts", JSON.stringify(swin?.buttons));
await select([...walls.slice(0, 1), ...wins.slice(0, 1)]);
check("mixed selection hides the strip", (await strip()) === null);
await select(walls.slice(0, 1));
await page.click('.ctx-strip .ctx-btn[data-command="MOVE"]');
await wait(300);
check("strip buttons run their command", (await history()).includes("Command: MOVE") || (await page.evaluate(() => window.archiApp.prompt.command)) === "MOVE", (await history()).slice(-80));
await page.evaluate(() => window.archiApp.cancel()); await wait(150);
await select([]);
check("deselecting hides the strip", (await strip()) === null);
const known = await page.evaluate(() => window.archiApp.hello.commands.map((c) => c.name));
const missing = [...new Set(ui.contextualTabs.flatMap((t) => t.items.flatMap((i) => (i.names ?? [i.command]).some((n) => known.includes(n)) ? [] : [i.command])))];
check("every contextual tab command is registered in the fixture engine", missing.length === 0, missing.join(", "));
await page.evaluate(() => window.archiApp.action("@cleanScreen")); await wait(150);
await select(walls);
check("clean screen hides the strip with the ribbon", !(await page.evaluate(() => document.querySelector(".ctx-strip")?.isConnected)));
await page.evaluate(() => window.archiApp.action("@cleanScreen")); await wait(250);
await select([]);

// ---- LAYOUTTABS, ZOOMXP, SHEETIMAGE, PSETUPIN ----
await run("LAYOUTTABS OFF");
check("LAYOUTTABS OFF hides the Model / sheet tabs", !(await page.$(".layout-tabs")));
await run("LAYOUTTABS");
check("LAYOUTTABS toggles them back", !!(await page.$(".layout-tabs")));
const s0 = await page.evaluate(() => window.archiSheetsPlanScale?.() ?? null);
void s0;
await run("ZOOMXP 1/50XP");
check("ZOOMXP on the plan: true size at 1:50", (await history()).includes("Plan shown at 1:50 on paper, true size on this screen."), (await history()).slice(-120));
await run("SHEETIMAGE");
check("SHEETIMAGE saves through sheet.image", /Saved Model at 150 dpi \(\d+×\d+ px\)/.test(await history()), (await history()).slice(-120));
await run("PSETUPIN");
const chooser = await page.$(".dlg.sheet");
check("PSETUPIN with Enter asks for the drawing", !!chooser);
if (chooser) { await page.keyboard.press("Escape"); await wait(150); }

// ---- versions ----
await run("FILEVERSIONS");
check("FILEVERSIONS needs a saved drawing", (await history()).includes("Save the drawing as an .archi file first."));
await call("doc.save", { path: "C:\\Users\\oana\\Documents\\Cedar House.archi" });
await page.evaluate(() => window.archiApp.refresh(["document"])); await wait(200);
await run("FILEVERSIONS");
await wait(300);
const vw = await page.evaluate(() => {
  const w = document.querySelector('[data-window="versions"]');
  return w ? { title: w.querySelector(".twin-title")?.textContent, note: w.querySelector(".ver-note")?.textContent, rows: w.querySelectorAll(".ver-row").length,
    buttons: [...w.querySelectorAll(".ver-buttons button")].map((b) => b.textContent + (b.disabled ? " (disabled)" : "")), width: w.getBoundingClientRect().width } : null;
});
check("Versions window: title, note, two versions", vw?.title === "Versions — Cedar House.archi" && vw.note.startsWith("Each save keeps a version (up to 50)") && vw.rows === 2, JSON.stringify(vw));
check("Open Copy and Restore… disabled until a version is chosen", JSON.stringify(vw?.buttons) === JSON.stringify(["Open Copy (disabled)", "Restore… (disabled)", "Save Version Now"]), JSON.stringify(vw?.buttons));
await page.click('[data-window="versions"] .ver-buttons button >> text=Save Version Now');
await wait(300);
const vw2 = await page.evaluate(() => ({ rows: document.querySelectorAll('[data-window="versions"] .ver-row').length, msg: document.querySelector('[data-window="versions"] .ver-msg')?.textContent }));
check("Save Version Now adds a version", vw2.rows === 3 && vw2.msg === "Version saved.", JSON.stringify(vw2));
await page.click('[data-window="versions"] .ver-row >> nth=1');
await wait(100);
await shot("versions", { clip: { x: 440, y: 180, width: 560, height: 520 } });
await page.click('[data-window="versions"] .ver-buttons button >> text=Restore…');
await wait(250);
const alertText = await page.evaluate(() => document.querySelector(".dlg.sheet .alert-m")?.textContent ?? "");
check("Restore… asks first", alertText.startsWith("Restore the version of "), alertText);
await page.click('.dlg.sheet button.prominent');
await wait(400);
const vw3 = await page.evaluate(() => document.querySelector('[data-window="versions"] .ver-msg')?.textContent);
check("Restore restores and keeps the current file as a version", vw3 === "Restored." && (await history()).includes("the previous file is kept as a version"), vw3);

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
await browser.close(); server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
