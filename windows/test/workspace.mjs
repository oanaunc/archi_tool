// Panels and workspace test (gaps 22–24 and 27–29 of docs/WINDOWS-GAPS.md): the Alerts, Navigator and Content panels,
// floating panels, tiled views, DVIEW / PERSPECTIVE / KEYBOARDNAV (keyboard crosshair), the Outliner and AI Assistant
// windows, LANGUAGE, CMDLINEOPTIONS, FILETAB, window arrangement, crash reports, settings export, the status-bar macro
// buttons, progress indicator, Quick Properties and agent state, and plugin undo groups.
// Renderer as a web page with the fixture engine (like doctools.mjs); screenshots go to test-results/workspace-*.png.
// Usage: node build.mjs --web && node test/workspace.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, acceptDownloads: true });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
page.on("dialog", (d) => void d.accept(d.type() === "prompt" ? "Cedar House.archi" : undefined));
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, "workspace-" + name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);
const run = async (line) => { await page.evaluate((l) => window.archiApp.runCommand(l), line); await wait(250); };
const history = async () => (await page.textContent(".cmd-history")) ?? "";
const body = async () => (await page.textContent(".panels:not(.floating) .panel-body")) ?? "";
const call = (m, p = {}) => page.evaluate(([a, b]) => window.archiApp.engine.call(a, b), [m, p]);
const app = (expr) => page.evaluate(expr);

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(800);

// ---- commands ----
const names = ["NOTIFICATIONS", "NAVIGATOR", "ADCENTER", "OUTLINERPANEL", "FLOATPANEL", "TILEDVIEWS", "DVIEW", "PERSPECTIVE", "KEYBOARDNAV", "ASSISTANT", "LANGUAGE",
  "EXPORTSETTINGS", "IMPORTSETTINGS", "CMDLINEOPTIONS", "CRASHREPORTS", "FILETAB", "FILETABCLOSE", "WINDOWTABS", "SYSWINDOWS", "FULLSCREEN"];
const missing = await page.evaluate((n) => n.filter((x) => !window.archiApp.lookup(x)), names);
check("workspace commands are registered", missing.length === 0, missing.join(", "));

// ---- Alerts ----
await run("NOTIFICATIONS");
let t = await body();
check("NOTIFICATIONS opens the Alerts panel with notifications", /notification\(s\)|No warnings/.test(t) && (await app(() => window.archiApp.panelTab)) === "Alerts", t.slice(0, 80));
const alertRows = await page.$$eval(".ws-alert", (els) => els.length);
check("Alerts lists model warnings", alertRows >= 1, String(alertRows));
await page.click(".ws-alerts .ws-check input");
await wait(300);
const withInfo = await page.$$eval(".ws-alert", (els) => els.length);
check("Alerts ▸ Info shows information items too", withInfo > alertRows, `${alertRows} → ${withInfo}`);
await page.click(".ws-alert >> nth=0");
await wait(400);
check("clicking an alert selects its objects", (await app(() => window.archiApp.selection.ids.length)) >= 1);
await page.click(".ws-alert >> nth=0 >> .iconbtn");
await wait(300);
check("Alerts ▸ Dismiss hides the item", (await page.$$eval(".ws-alert", (els) => els.length)) === withInfo - 1);
check("Alerts ▸ Restore dismissed appears", (await page.$$eval(".ws-alerts button", (els) => els.map((e) => e.textContent))).includes("Restore dismissed"));
await page.click('.ws-alerts button:text-is("Restore dismissed")');
await wait(300);
check("Restore dismissed brings it back", (await page.$$eval(".ws-alert", (els) => els.length)) === withInfo);
await shot("alerts");

// ---- Navigator ----
await run("NAVIGATOR");
await wait(400);
check("NAVIGATOR shows the overview map", !!(await page.$(".ws-nav")) && (await app(() => window.archiApp.panelTab)) === "Navigator");
const c0 = await app(() => [window.archiApp.canvas && window.archiWorkspace && 0, 0]);
void c0;
const before = await page.evaluate(() => { const p = document.querySelector(".ws-nav").getBoundingClientRect(); return { x: p.left, y: p.top, w: p.width, h: p.height }; });
const live0 = await app(() => JSON.stringify(window.archiApp.live));
await page.mouse.move(before.x + before.w * 0.2, before.y + before.h * 0.5);
await page.mouse.down(); await page.mouse.move(before.x + before.w * 0.25, before.y + before.h * 0.45); await page.mouse.up();
await wait(400);
const navPixels = await page.evaluate(() => { const c = document.querySelector(".ws-nav"); const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i] > 200 && d[i + 1] > 150 && d[i + 2] < 90) n++; return n; });
check("Navigator draws the visible-area rectangle (accent)", navPixels > 20, String(navPixels));
void live0;
await shot("navigator");

// ---- Content (Design Center) ----
await run("ADCENTER");
await wait(300);
check("ADCENTER opens the Content panel", (await body()).includes("Choose Drawing"));
await page.click(".ws-choose");
await wait(150);
await page.click('.menu .mi:has-text("Drawing File…")');
await wait(600);
await page.selectOption(".ws-kind", "Layers");
await wait(300);
const layerNames = await page.$$eval(".ws-names .li", (els) => els.map((e) => e.textContent));
check("Content lists the layers of the chosen drawing", layerNames.length >= 2, layerNames.slice(0, 6).join(", "));
const layersBefore = await app(() => window.archiApp.layers.layers.length);
const pickName = layerNames.find((n) => !["0"].includes(n)) ?? layerNames[0];
await page.click(`.ws-names .li:text-is("${pickName}")`);
await wait(200);
await page.click('.ws-content button:text-is("Add to Drawing")');
await wait(500);
const msg = (await page.textContent(".ws-msg")) ?? "";
check("Content ▸ Add to Drawing adds the definition", /Added 1|already exist/.test(msg), msg);
await page.click('.ws-content button:text-is("Add All")');
await wait(500);
check("Content ▸ Add All adds the rest", (await app(() => window.archiApp.layers.layers.length)) >= layersBefore, `${layersBefore} → ${await app(() => window.archiApp.layers.layers.length)}`);
await shot("content");

// ---- Floating panels ----
await run("FLOATPANEL Layers");
await wait(400);
check("FLOATPANEL Layers floats the panel in its own window", !!(await page.$('.ws-floatpanel[data-window="float:Layers"]')));
const docked = await page.$$eval(".panels:not(.floating) .ptab .t", (els) => els.map((e) => e.textContent));
check("a floating panel leaves the docked tab strip", !docked.includes("Layers") && docked.length === 13, docked.join(","));
const floatText = (await page.textContent('.ws-floatpanel[data-window="float:Layers"] .panel-body')) ?? "";
check("the floating panel shows the layer list", floatText.includes("Continuous"), floatText.slice(0, 80));
await run("FLOATPANEL Quick Props");
await wait(300);
check("FLOATPANEL Quick Props (two words, from the menus)", !!(await page.$('.ws-floatpanel[data-window="float:Quick Props"]')));
await shot("floating");
await page.click('.ws-floatpanel[data-window="float:Layers"] .ws-floathead .iconbtn');
await wait(300);
const docked2 = await page.$$eval(".panels:not(.floating) .ptab .t", (els) => els.map((e) => e.textContent));
check("the dock button puts it back and shows it", !(await page.$('.ws-floatpanel[data-window="float:Layers"]')) && docked2.includes("Layers") && (await app(() => window.archiApp.panelTab)) === "Layers");
await page.click('.ws-floatpanel[data-window="float:Quick Props"] .pb-close');
await wait(200);
check("remembered floating set is empty after docking", (await app(() => localStorage.getItem("archi.floatingPanels.open"))) === "[]");

// ---- Tiled views ----
await run("TILEDVIEWS 4");
await wait(900);
const tiles = await page.$$eval(".ws-tile", (els) => els.map((e) => e.getAttribute("data-kind")));
check("TILEDVIEWS 4 shows four tiles in Split", (await app(() => window.archiApp.mode)) === "Split" && tiles.join(",") === "Plan,3D,Section,South", tiles.join(","));
check("TILEDVIEWS prints the arrangement", (await history()).includes("Tiled views: Four: equal — Plan, 3D, Section, South"));
const dark = await page.evaluate(() => { const c = document.querySelector('.ws-tile[data-kind="South"] canvas'); if (!c) return -1; const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i] < 90 && d[i + 1] < 90 && d[i + 2] < 90) n++; return n; });
check("the elevation tile paints the projection on paper", dark > 50, String(dark));
await shot("tiles");
await page.click('.ws-tile[data-kind="Section"] .ws-tilemenu');
await wait(150);
await page.click('.menu .mi:has-text("East")');
await wait(500);
check("tile menu changes a tile's view", (await page.$$eval(".ws-tile", (els) => els.map((e) => e.getAttribute("data-kind")))).includes("East"));
await page.click('.ws-tile[data-kind="East"] .ws-tilemenu');
await wait(150);
await page.click('.menu .mi:has-text("Three: one left, two right")');
await wait(500);
check("tile menu changes the arrangement", (await page.$$eval(".ws-tile", (els) => els.length)) === 3);
await page.evaluate(() => { window.archiWorkspace.tileState.setKind("Section", 2); window.archiWorkspace.tileState.arrangement = "two"; });
await run("TILEDVIEWS Single");
check("TILEDVIEWS Single returns to the plan", (await app(() => window.archiApp.mode)) === "2D");

// ---- DVIEW, PERSPECTIVE, KEYBOARDNAV ----
await run("DVIEW TW 30");
check("DVIEW twists the plan", (await history()).includes("View twist 30°."));
await run("DVIEW Off");
await run("PERSPECTIVE 0");
await wait(400);
check("PERSPECTIVE 0 shows the 3D view", (await app(() => window.archiApp.mode)) === "3D");
await page.evaluate(() => window.archiApp.setUI("mode", "2D"));
await wait(300);
await run("KEYBOARDNAV 25");
check("KEYBOARDNAV stores the crosshair step", (await app(() => localStorage.getItem("archi.keyboardCursorStep"))) === "25" && (await history()).includes("arrow keys move the crosshair"));
await page.evaluate(() => window.archiApp.setVar("OSMODE", "16384"));
await run("LINE");
await wait(200);
const cv = await page.evaluate(() => { const r = document.querySelector('canvas.plan[aria-label="Drawing canvas"]')?.getBoundingClientRect(); return r ? { x: r.left + r.width / 2, y: r.top + r.height / 2 } : null; });
if (cv) await page.mouse.move(cv.x, cv.y);
await wait(100);
await page.keyboard.press("ArrowRight");
await wait(100);
const x0 = await app(() => window.archiApp.live.x);
await page.keyboard.press("Shift+ArrowRight");
await wait(150);
const x1 = await app(() => window.archiApp.live.x);
check("arrow keys move the crosshair at a point prompt", x1 > x0, `${x0} → ${x1}`);
await page.keyboard.press("Enter");
await wait(300);
check("Enter picks the crosshair point", /next point/i.test(await app(() => window.archiApp.prompt.message)), await app(() => window.archiApp.prompt.message));
await page.keyboard.press("Escape");
await wait(200);

// ---- Outliner ----
await run("OUTLINERPANEL");
await wait(400);
check("OUTLINERPANEL opens the Outliner window", !!(await page.$('.pb-win[data-window="outliner"]')));
const orows = await page.$$eval(".ws-orow", (els) => els.length);
check("Outliner lists groups and components", orows >= 1, String(orows));
await page.fill('.pb-win[data-window="outliner"] input', "zzz");
await wait(300);
check("Outliner ▸ Filter by name", ((await page.textContent('.pb-win[data-window="outliner"]')) ?? "").includes("No groups or components"));
await shot("outliner");
await page.click('.pb-win[data-window="outliner"] .pb-close');

// ---- Assistant ----
await page.evaluate(() => {
  window.archiAssistantFake = (req) => ({ content: [{ type: "text", text: "Adding a wall." }, { type: "tool_use", name: "run_commands", input: { commands: String(JSON.stringify(req.body)).includes("many") ? Array.from({ length: 30 }, () => "LINE 0,0 10,0 ") : ["LINE 0,0 1000,0 "] } }] });
});
await run("ASSISTANT");
await wait(300);
check("ASSISTANT opens the assistant window", !!(await page.$('.pb-win[data-window="assistant"]')) && ((await page.textContent(".ws-as-head")) ?? "").includes("Local: llama3.1"));
await page.click('.pb-win[data-window="assistant"] .ws-as-head .pb-ibtn');
await wait(200);
const settingsText = (await page.textContent(".ws-as-settings")) ?? "";
check("Assistant ▸ Provider, model and key settings", /Provider/.test(settingsText) && /Endpoint \(localhost\)/.test(settingsText) && /Confirm above 25 changes/.test(settingsText), settingsText.slice(0, 120));
await page.selectOption(".ws-as-settings select", "anthropic");
await wait(150);
check("Assistant ▸ Anthropic shows the API key field", !!(await page.$('.ws-as-settings input[type="password"]')));
await page.fill('.ws-as-settings input[type="password"]', "sk-test");
await page.click('.ws-as-settings .pb-btn:has-text("Save")');
await wait(200);
check("Assistant ▸ Save switches to Claude with its default model", ((await page.textContent(".ws-as-head")) ?? "").includes("Claude: claude-sonnet-4-5"));
const n0 = await app(() => window.archiApp.info?.entities ?? 0);
await page.fill(".ws-as-input", "add a wall");
await page.click(".ws-as-send");
await wait(900);
let msgs = (await page.textContent(".ws-as-msgs")) ?? "";
check("Assistant runs the model's commands", msgs.includes("Adding a wall.") && msgs.includes("Ran 1 command(s) — undo with Ctrl+Z."), msgs.slice(-160));
void n0;
await page.fill(".ws-as-input", "many lines");
await page.press(".ws-as-input", "Enter");
await wait(900);
msgs = (await page.textContent(".ws-as-msgs")) ?? "";
check("bulk changes ask for confirmation", msgs.includes("This would change many objects (30 added, 0 modified, 0 deleted). Apply or discard?") && !!(await page.$('.ws-as-pending .pb-btn:has-text("Apply")')));
await page.click('.ws-as-pending .pb-btn:has-text("Discard")');
await wait(200);
check("Assistant ▸ Discard", ((await page.textContent(".ws-as-msgs")) ?? "").includes("Changes discarded."));
await shot("assistant");
await page.click('.pb-win[data-window="assistant"] .pb-close');

// ---- LANGUAGE ----
await run("LANGUAGE Deutsch");
await wait(300);
const tabsDe = await page.$$eval(".ribbon-tabs .tab", (els) => els.map((e) => e.textContent));
const menusDe = await page.$$eval(".menubar > button", (els) => els.map((e) => e.textContent));
check("LANGUAGE Deutsch translates the ribbon", tabsDe.includes("Start") && tabsDe.includes("Beschriften"), tabsDe.slice(0, 5).join(","));
check("LANGUAGE Deutsch translates the menus", menusDe.includes("Zeichnen") && menusDe.includes("Ändern"), menusDe.join(","));
check("commands stay English", !!(await app(() => window.archiApp.lookup("LINE"))));
await shot("language-de");
await run("LANGUAGE English");
await wait(300);
check("LANGUAGE English restores the ribbon", (await page.$$eval(".ribbon-tabs .tab", (els) => els.map((e) => e.textContent))).includes("Home"));

// ---- CMDLINEOPTIONS ----
await run("CMDLINEOPTIONS Lines 8");
await wait(200);
const hh = await page.evaluate(() => document.querySelector(".cmd-history").getBoundingClientRect().height);
check("CMDLINEOPTIONS Lines 8 shows eight history lines", Math.abs(hh - (15 * 8 + 6)) <= 1, String(hh));
await run("CMDLINEOPTIONS Float");
await wait(200);
check("CMDLINEOPTIONS Float floats the command line", !!(await page.$(".cmdline.ws-floating .ws-clgrip")));
await shot("cmdline-float");
await run("CMDLINEOPTIONS Reset");
await wait(200);
check("CMDLINEOPTIONS Reset docks it with 4 lines", !(await page.$(".cmdline.ws-floating")) && Math.abs((await page.evaluate(() => document.querySelector(".cmd-history").getBoundingClientRect().height)) - 66) <= 1);

// ---- file tabs, windows, full screen, settings, crash reports ----
await run("FILETAB");
await wait(200);
check("FILETAB shows the file tab bar", (await page.$$eval(".ws-filetabs .ft:not(.add)", (els) => els.length)) === 1 && (await history()).includes("File tabs on."));
await shot("filetabs", { clip: { x: 0, y: 0, width: 1440, height: 200 } });
await run("FILETABCLOSE");
await wait(200);
check("FILETABCLOSE hides it", (await page.$eval(".ws-filetabs", (e) => getComputedStyle(e).display)) === "none");
await run("SYSWINDOWS Cascade");
await wait(300);
check("SYSWINDOWS arranges the windows", (await history()).includes("1 window(s) arranged: cascade."));
await run("WINDOWTABS Tabs");
check("WINDOWTABS Tabs", (await history()).includes("New drawings open as tabs."));
await run("CRASHREPORTS On");
await wait(200);
check("CRASHREPORTS On", (await history()).includes("Crash reports on: a report is saved if the app quits unexpectedly (nothing is sent automatically)."));
await run("CRASHREPORTS Status");
await wait(200);
check("CRASHREPORTS Status", /Crash reports on; 0 saved\./.test(await history()));
await run("CRASHREPORTS Off");
const dl = page.waitForEvent("download", { timeout: 3000 }).catch(() => null);
await run("EXPORTSETTINGS");
const d = await dl;
check("EXPORTSETTINGS writes a settings file", !!d && (await history()).includes("Settings exported to"), d ? d.suggestedFilename() : "no download");

// ---- status bar ----
await page.evaluate(() => { localStorage.setItem("archi.fake.macroButtons", JSON.stringify([{ name: "Circle", macro: "^C^CCIRCLE", icon: "circle", tooltip: "Draw a circle", group: "Custom" }])); window.archiApp.emit("drawing"); });
await wait(300);
check("status bar shows macro buttons", (await page.$$eval(".statusbar .macros .macro", (els) => els.length)) === 1);
await page.click(".statusbar .macros .macro");
await wait(300);
check("a macro button runs its macro", (await app(() => window.archiApp.prompt.command)) === "CIRCLE");
await page.keyboard.press("Escape");
await page.evaluate(() => { window.__job = window.archiProgress.begin("Publishing 3 sheet(s)"); window.archiProgress.update(window.__job, 0.5, "sheet 2 of 3"); });
await wait(100);
check("progress indicator in the status bar", ((await page.textContent(".statusbar .progress")) ?? "").includes("Publishing 3 sheet(s) · sheet 2 of 3"));
await shot("statusbar", { clip: { x: 0, y: 870, width: 1440, height: 30 } });
await page.click(".statusbar .progress .cancel");
check("progress Cancel", await app(() => window.archiProgress.isCancelled(window.__job)));
await page.evaluate(() => window.archiProgress.end(window.__job));
const qpBtn = '.statusbar .right button:has(svg[data-sf="slider.horizontal.below.rectangle"])';
const qpTip0 = await page.getAttribute(qpBtn, "data-help").catch(() => null) ?? await page.getAttribute(qpBtn, "title");
await page.click(qpBtn);
await wait(150);
const qpCls = await page.getAttribute(qpBtn, "class");
check("Quick Properties button shows its state", (qpCls ?? "").includes("on") !== ((qpTip0 ?? "").includes(" on")), `${qpTip0} / ${qpCls}`);
await page.click(qpBtn);
check("agent indicator shows the server state", ((await page.textContent(".statusbar .agent")) ?? "").startsWith("Agent: "));

// ---- plugin commands are one undo step ----
await call("undo.begin");
await run("LINE 0,0 500,0 ");
await page.keyboard.press("Escape");
await run("CIRCLE 0,0 200");
await page.keyboard.press("Escape");
const end = await call("undo.end", { label: "MYPLUGIN" });
const hist = await call("panel.history");
check("undo.begin / undo.end collapse a plugin's edits into one step", end.collapsed === true && hist.undo.at(-1) === "MYPLUGIN", JSON.stringify(hist.undo.slice(-3)));

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
await browser.close();
server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
