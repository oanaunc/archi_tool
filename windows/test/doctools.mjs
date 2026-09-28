// Document tools test (gaps 3, 4, 9, 10, 11 of docs/WINDOWS-GAPS.md): PNG and schedule exports from the ribbon, the
// Schedule sheet, the Project Browser sections, Selection / Quick Props / Inspector / History panels, the Properties type
// filter, Spelling, Text Styles, TEXTEDITINPLACE with strike-through, and bold / underline / strike text on the canvas.
// Renderer as a web page with the fixture engine (like dialogs.mjs); screenshots go to test-results/doctools-*.png.
// Usage: node build.mjs --web && node test/doctools.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, "doctools-" + name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);
const run = (line) => page.evaluate((l) => window.archiApp.runCommand(l), line);
const history = async () => (await page.textContent(".cmd-history")) ?? "";
const ribbonTab = async (t) => { await page.click(`.ribbon-tabs .tab:text-is("${t}")`); await wait(120); };
const panel = async (t) => { await page.evaluate((x) => window.archiApp.action(`@panel:${x}`), t); await wait(250); };
const body = async () => (await page.textContent(".panel-body")) ?? "";
const call = (m, p = {}) => page.evaluate(([a, b]) => window.archiApp.engine.call(a, b), [m, p]);
const select = async (ids) => { await call("select.set", { ids }); await page.evaluate(() => window.archiApp.refresh(["selection"])); await wait(250); };
const idsOf = async (type, n) => ((await call("schedule.get", { kind: "all" })).rows ?? []).slice(1).filter((r) => r[1] === type).slice(0, n).map((r) => Number(r[0]));

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(700);

// ---- PNG and schedule exports (Output ribbon) ----
await ribbonTab("Output");
await page.click('.ribbon-body .rbtn:has(.t:text-is("PNG"))');
await wait(250);
check("Output ▸ Export ▸ PNG exports through the engine", (await history()).includes("Exported PNG to"), (await history()).slice(-120));
await page.click('.ribbon-body .rbtn:has(.t:text-is("CSV"))');
await wait(150);
const csvItems = await page.$$eval(".menu .mi", (els) => els.map((e) => e.textContent.trim()));
check("Schedules ▸ CSV menu lists six kinds", csvItems.filter((t) => /schedule \(CSV\)/.test(t)).length === 6, csvItems.join(" | "));
await page.click('.menu .mi:has-text("Walls schedule")');
await wait(250);
check("CSV export of the walls schedule", (await history()).includes("Exported CSV to") && (await history()).includes("-walls.csv"), (await history()).slice(-100));

// ---- Schedule sheet ----
await page.click('.ribbon-body .rbtn:has(.t:text-is("View"))');
await page.waitForSelector(".dlg.sheet.dt-schedule", { timeout: 3000 }).catch(() => {});
check("Output ▸ Schedules ▸ View opens the Schedule sheet", await page.isVisible(".dlg.sheet.dt-schedule"));
const allRows = await page.textContent(".dt-schedule .dt-small");
check("All schedule rows from the engine", /59 row\(s\)/.test(allRows ?? ""), allRows);
await page.locator(".dt-schedule .picker").click();
await wait(80);
await page.click('.menu .mi:has-text("Walls")');
await wait(250);
const wallHead = await page.$$eval(".dt-schedule .cell.head", (els) => els.map((e) => e.textContent));
check("Walls schedule table with a header row", wallHead.length > 3 && (await page.textContent(".dt-schedule .dt-small")).includes("16 row(s)"), wallHead.join(","));
await shot("schedule", { clip: await page.locator(".dlg.sheet.dt-schedule").boundingBox() });
await page.click('.dt-schedule .flatbtn:has-text("Export XLSX")');
await wait(200);
check("Export XLSX… from the Schedule sheet", (await history()).includes("Exported XLSX to") && (await history()).includes("-walls.xlsx"));
await page.click('.dt-schedule .dlg-footer .flatbtn:has-text("Close")');
await wait(150);
check("Close dismisses the Schedule sheet", !(await page.isVisible(".dlg.sheet.dt-schedule")));

// ---- Project Browser ----
await panel("Browser");
const br = await body();
const sections = ["Floor Plans", "3D Views", "Project Views", "Elevations & Sections", "Sheets", "Schedules", "Groups", "Links"];
check("Project Browser sections as on the Mac", sections.every((s) => br.includes(s)), sections.filter((s) => !br.includes(s)).join(","));
check("3D views: six directions and the saved cameras", ["3D — Iso", "3D — Left", "Front", "Aerial"].every((s) => br.includes(s)));
check("Elevations & Sections items", ["North Elevation", "South Elevation", "East Elevation", "West Elevation", "Section A-A"].every((s) => br.includes(s)));
check("Schedules items", ["Walls Schedule", "Doors Schedule", "All Schedule"].every((s) => br.includes(s)));
await shot("browser", { clip: await page.locator(".panels").boundingBox() });
await page.click('.dt-item:has-text("Doors Schedule")');
await wait(300);
check("a schedule in the browser opens the Schedule sheet on its kind", (await page.textContent(".dt-schedule .picker")).includes("Doors"));
await page.keyboard.press("Escape");
await wait(150);
await page.click('.dt-item:has-text("North Elevation")');
await wait(400);
check("an elevation shows the 3D view", (await page.evaluate(() => window.archiApp.mode)) === "3D");
await page.click('.dt-item:has-text("Ground Floor")');
await wait(400);
check("a floor plan returns to 2D", (await page.evaluate(() => window.archiApp.mode)) === "2D");
await page.click('.dt-sec:has-text("Schedules")');
await wait(200);
check("sections collapse", !(await body()).includes("Walls Schedule"));
await page.click('.dt-sec:has-text("Schedules")');
await wait(150);

// ---- Selection panel and the Properties type filter ----
const walls = await idsOf("wall", 3), doors = await idsOf("window", 1);
await select([...walls, ...doors]);
await panel("Selection");
let sp = await body();
check("Selection panel: count and types", sp.includes("4 object(s) selected") && sp.includes("wall") && sp.includes("window"), sp.slice(0, 120));
check("Only / Remove per type", (await page.locator(".dt-selrow .flatbtn:has-text('Only')").count()) === 2 && (await page.locator(".dt-selrow .flatbtn:has-text('Remove')").count()) === 2);
check("Layers, Zoom to Selection and Clear", sp.includes("Layers: A-GLAZ (1), A-WALL (3)") && sp.includes("Zoom to Selection") && sp.includes("Clear"));
await shot("selection", { clip: await page.locator(".panels").boundingBox() });
await page.click('.dt-selrow:has(.ty:text-is("window")) .flatbtn:has-text("Remove")');
await wait(300);
check("Remove drops that type", (await page.evaluate(() => window.archiApp.selection.ids.length)) === 3);
await select([...walls, ...doors]);
await panel("Properties");
await wait(200);
const tf = page.locator(".dt-typefilter");
check("Properties header of a mixed selection is a type menu", (await tf.count()) === 1 && (await tf.textContent()).includes("4 objects (3 wall, 1 window)"), (await tf.count()) ? await tf.textContent() : "none");
await tf.click();
await wait(100);
const tmenu = await page.$$eval(".menu .mi", (els) => els.map((e) => e.textContent.trim()));
check("type menu entries", tmenu.includes("Window (1)") && tmenu.includes("Wall (3)"), tmenu.join(","));
await page.click('.menu .mi:has-text("Wall (3)")');
await wait(300);
check("narrowing keeps one type", (await page.evaluate(() => window.archiApp.selection.ids.length)) === 3);

// ---- Quick Properties ----
await run("QP ON");
await wait(400);
check("QP ON shows Quick Properties over the drawing", await page.isVisible(".dt-qp-overlay"));
const qp = (await page.textContent(".dt-qp-overlay")) ?? "";
check("Quick Properties rows", qp.includes("3 selected") && qp.includes("Layer") && qp.includes("Color"), qp.slice(0, 100));
check("Dock / Float / Hide buttons", (await page.locator(".dt-qp-overlay .iconbtn").count()) === 3);
await shot("quickprops-overlay");
await page.locator(".dt-qp-overlay .iconbtn").nth(0).click();
await wait(300);
check("Dock moves Quick Properties into the panel", !(await page.isVisible(".dt-qp-overlay")) && (await page.evaluate(() => window.archiApp.panelTab)) === "Quick Props" && (await body()).includes("3 selected"));

// ---- Inspector ----
await run("INSPECT");
await wait(400);
const ins = await body();
check("INSPECT opens the Inspector with raw values", (await page.evaluate(() => window.archiApp.panelTab)) === "Inspector" && ins.includes("GUID") && ins.includes("Geometry") && ins.includes(`#${walls[0]}`), ins.slice(0, 120));
await page.locator(".dt-card .flatbtn:has-text('Copy')").first().click();
await wait(100);
check("Copy puts the object's values on the clipboard", ((await page.evaluate(() => window.archiClipboard)) ?? "").startsWith(`ID: #${walls[0]}`));
await shot("inspector", { clip: await page.locator(".panels").boundingBox() });

// ---- SELECTIONINFO / SELECTWALLCHAIN ----
await select([]);
await run("SELECTIONINFO");
await wait(300);
check("SELECTIONINFO shows the Selection panel", (await page.evaluate(() => window.archiApp.panelTab)) === "Selection" && (await body()).includes("Nothing selected"));
await run("SELECTWALLCHAIN");
await wait(300);
check("SELECTWALLCHAIN selects joined walls", (await history()).includes("joined wall(s) selected") && (await body()).includes("object(s) selected"));

// ---- History pages ----
await select([]);
await run("LINE"); await page.evaluate(async () => { const a = window.archiApp; await a.engine.call("input.point", { x: 0, y: 0 }); await a.engine.call("input.point", { x: 3000, y: 0 }); await a.engine.call("input.key", { key: "Enter" }); await a.refresh(["document"]); });
await wait(200);
await run("CIRCLE"); await page.evaluate(async () => { const a = window.archiApp; await a.engine.call("input.point", { x: 0, y: 0 }); await a.engine.call("input.text", { text: "500" }); await a.refresh(["document"]); });
await wait(200);
await panel("History");
let hs = await page.$$eval(".dt-step", (els) => els.map((e) => e.textContent));
check("numbered undo steps from the opened document", hs[0] === "0Open / new document" && hs.length >= 3, hs.join(" | "));
await shot("history", { clip: await page.locator(".panels").boundingBox() });
await page.locator(".dt-step").nth(0).click();
await wait(400);
hs = await page.$$eval(".dt-step", (els) => els.map((e) => e.className));
check("clicking step 0 undoes everything (redo steps greyed)", hs[0].includes("current") && hs.slice(1).every((c) => c.includes("undone")), hs.join(","));
await page.locator(".dt-step").last().click();
await wait(400);
hs = await page.$$eval(".dt-step", (els) => els.map((e) => e.className));
check("clicking the last step redoes them", hs[hs.length - 1].includes("current"), hs.join(","));
await page.click('.dt-segbar .seg:text-is("Commands")');
await wait(300);
const cmds = await page.$$eval(".dt-cmd .t", (els) => els.map((e) => e.textContent));
check("Commands page lists the session's commands", cmds.includes("CIRCLE") && cmds.includes("LINE"), cmds.slice(0, 6).join(","));
check("command count", (await body()).includes("command(s) this session"));
await page.click('.dt-foot .flatbtn:has-text("Copy Log")');
await wait(100);
check("Copy Log", ((await page.evaluate(() => window.archiClipboard)) ?? "").includes("Command: LINE"));
await page.click('.dt-segbar .seg:text-is("Undo History")');

// ---- Spelling ----
const t1 = (await call("fake.addText", { content: "Kitchn wiht door", position: [2000, 2000], height: 300 })).id;
await call("fake.addText", { content: "Bedrom and kitchn", position: [2000, 1000], height: 300 });
await page.evaluate(() => window.archiApp.refresh(["document"]));
await run("SPELLDIALOG");
await page.waitForSelector(".dlg.sheet.dt-spelling", { timeout: 3000 }).catch(() => {});
check("SPELLDIALOG opens Check Spelling", (await page.textContent(".dt-spelling .dlg-title")).includes("Check Spelling"));
let sw = await page.textContent(".dt-spell-word .w");
check("first misspelled word with its object", sw === "Kitchn" && (await page.textContent(".dt-spell-word")).includes(`#${t1} · text`), sw);
check("suggestion prefilled", (await page.inputValue(".dt-spell-rep")) === "Kitchen");
await shot("spelling", { clip: await page.locator(".dlg.sheet.dt-spelling").boundingBox() });
await page.click('.dt-spelling .flatbtn:has(> span:text-is("Change"))');
await wait(300);
const raw1 = await page.evaluate((id) => window.archiApp.engine.raw.find((e) => e.id === String(id)).items[0].text.content, t1);
check("Change replaces the word in the text", raw1 === "Kitchen wiht door", raw1);
sw = await page.textContent(".dt-spell-word .w");
check("next word", sw === "wiht", sw);
await page.click('.dt-spelling .flatbtn:has(> span:text-is("Ignore All"))');
await wait(200);
sw = await page.textContent(".dt-spell-word .w");
check("Ignore All moves on", sw === "Bedrom", sw);
await page.click('.dt-spelling .flatbtn:has(> span:text-is("Add to Dictionary"))');
await wait(300);
sw = await page.textContent(".dt-spell-word .w");
check("Add to Dictionary moves on", sw === "kitchn", sw);
await page.click('.dt-spelling .flatbtn:has(> span:text-is("Change All"))');
await wait(300);
check("check complete with the change count", (await page.textContent(".dt-spelling")).includes("Spelling check complete.") && (await page.textContent(".dt-spelling .dlg-title")).includes("2 changed"));
await page.click('.dt-spelling .flatbtn:has(> span:text-is("Done"))');
await wait(150);

// ---- Text Styles ----
await run("TEXTSTYLEDIALOG");
await page.waitForSelector('.twin[data-window="textStyles"]', { timeout: 3000 }).catch(() => {});
check("TEXTSTYLEDIALOG opens the Text Styles window", await page.isVisible('.twin[data-window="textStyles"]'));
await page.click('.dt-ts .flatbtn:has(> span:text-is("New"))');
await wait(150);
check("New fills a unique name", (await page.inputValue(".dt-ts-row .darkfield >> nth=0")) === "Style 1");
await page.fill(".dt-ts-row .darkfield >> nth=2", "0");
await page.click('.dt-ts .flatbtn:has(> span:text-is("Apply"))');
await wait(200);
check("invalid width factor is refused with the Mac message", (await page.textContent(".dt-ts-foot")).includes("Check: width factor 0.01–100"));
await page.fill(".dt-ts-row .darkfield >> nth=2", "0.8");
await page.fill(".dt-ts-row .darkfield >> nth=3", "12");
await page.click('.dt-ts .flatbtn:has(> span:text-is("Apply"))');
await wait(300);
check("Apply saves the style", (await page.textContent(".dt-ts-foot")).includes("Saved Style 1.") && (await page.$$eval(".dt-ts-item", (e) => e.map((x) => x.textContent))).includes("Style 1"));
const tr = await page.evaluate(() => getComputedStyle(document.querySelector(".dt-ts-sample")).transform);
check("preview slants and narrows", tr.startsWith("matrix(0.8"), tr);
await page.click('.dt-ts .flatbtn:has(> span:text-is("Current"))');
await wait(200);
check("Current", (await page.textContent(".dt-ts-foot")).includes("Style 1 is current."));
await shot("textstyles", { clip: await page.locator('.twin[data-window="textStyles"]').boundingBox() });
await page.click('.twin[data-window="textStyles"] .twin-close');

// ---- Text formatting on the canvas and TEXTEDITINPLACE ----
const t3 = (await call("fake.addText", { content: "Bold struck", position: [-2000, -4000], height: 600, format: { bold: true, underline: true, strike: true } })).id;
await page.evaluate(() => window.archiApp.refresh(["document"]));
await page.evaluate(() => window.archiApp.canvas.zoomExtents());
await wait(400);
const dec = await page.evaluate((id) => {
  const e = window.archiApp.engine.decoded.find((x) => x.id === String(id));
  return e?.items?.[0];
}, t3);
check("draw list text carries bold / underline / strike", dec?.bold === true && dec?.underline === true && dec?.strike === true && dec?.italic === false, JSON.stringify(dec ?? {}).slice(0, 160));
await shot("text-format");
await select([t3]);
await run("TEXTEDITINPLACE");
await wait(500);
check("TEXTEDITINPLACE opens the in-place editor", await page.isVisible(".text-editor"));
check("editor has Bold, Italic, Underline and Strike-through", (await page.$$eval(".text-editor .te-btn", (e) => e.map((x) => x.textContent))).join("") === "BIUS");
await page.click('.text-editor .te-btn:text-is("S")');
check("strike toggles on", (await page.getAttribute('.text-editor .te-btn:text-is("S")', "class")).includes("on"));
await shot("text-editor");
await page.click(".text-editor .te-cancel");

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
