// Auditor spot checks (round 3): keys by resulting state, menu bar, Component menu, contextual tab, new windows and panels.
// Menu-bar and ribbon enablement cross-check: windows/test/audit-ribbon.mjs; menus-keys.mjs writes test-results/menus-disabled.txt.
// Renderer as a web page + fixture engine. Prints JSON; exits 1 when a check fails.
import http from "node:http"; import fs from "node:fs"; import path from "node:path"; import { createRequire } from "node:module"; import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."); const require = createRequire(import.meta.url);
const pw = require("playwright-core"); const web = path.join(root, "dist/renderer");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png" };
const server = http.createServer((req, res) => { const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname)); if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; } res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res); }).listen(0);
const browser = await pw.chromium.launch(); const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = []; page.on("pageerror", (e) => errors.push(String(e)));
const opened = []; await page.exposeFunction("__open", (u) => opened.push(u));
await page.addInitScript(() => { window.open = (u) => { window.__open(String(u)); return null; }; });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html?open=Cedar%20House.archi`); await page.waitForSelector("body.ready", { timeout: 30000 }); await page.waitForTimeout(800);
const A = (f, a) => page.evaluate(f, a); const wait = (ms) => page.waitForTimeout(ms);
let fails = 0; const out = {};
const check = (name, ok, info = "") => { if (!ok) fails++; console.log(`${ok ? "PASS" : "FAIL"}  ${name}${info ? "  — " + info : ""}`); };
const esc = async () => { for (let i = 0; i < 3; i++) { await page.keyboard.press("Escape"); await wait(60); } };
const visibleText = (sel) => page.$$eval(sel, (els) => els.filter((e) => e.offsetParent !== null).map((e) => e.textContent.trim()).join(" | "));

// ---- menu bar ----
const menus = await page.$$eval(".titlebar .menubar button", (b) => b.map((x) => x.textContent.trim()));
check("menu bar lists the Mac menus (no app menu)", menus.join(",") === "File,Edit,View,Draw,Modify,Annotate,Architecture,Model,Analyze,Tools,Window,Help", menus.join(","));
async function menuTitles(m) { await page.click(`.titlebar .menubar button:text-is("${m}")`); await wait(200); const t = await page.$$eval(".menu .mi", (els) => els.map((e) => `${e.textContent.trim()}${e.classList.contains("disabled") ? " [disabled]" : ""}`)); await esc(); return t; }
out.help = await menuTitles("Help"); out.edit = await menuTitles("Edit");
check("Help ends with About", out.help.some((t) => /^About Oanarina Archi Tool/.test(t)) , out.help.join(" / "));
check("Edit has Deselect All, Selection Tools, Groups & Isolation, Match Properties, Options…", ["Deselect All", "Selection Tools", "Groups & Isolation", "Match Properties", "Options…"].every((x) => out.edit.some((t) => t.startsWith(x))), out.edit.join(" / "));

// ---- Component menu ----
await page.click('.ribbon-tabs .tab:text-is("Insert")'); await wait(200);
await page.click('.ribbon-body .rbtn:has(.t:text-is("Component"))'); await wait(200);
const comp = await page.$$eval(".menu .mi", (els) => els.map((e) => ({ t: e.textContent.trim(), d: e.classList.contains("disabled") })));
check("Insert ▸ Component: 12 enabled entries", comp.length === 12 && comp.every((c) => !c.d), comp.map((c) => c.t + (c.d ? "[x]" : "")).join(","));
const calls = []; await page.exposeFunction("__rec", (m) => calls.push(m));
await A(() => { const a = window.archiApp; const orig = a.runCommand.bind(a); a.runCommand = (l) => { window.__rec(l); return orig(l); }; });
await esc(); await page.click('.ribbon-body .rbtn:has(.t:text-is("Component"))'); await wait(200); await A(() => { const m = [...document.querySelectorAll(".menu .mi")].find((e) => e.textContent.trim() === "Chair"); m?.dispatchEvent(new MouseEvent("mousedown", { bubbles: true })); m?.click(); }); await wait(300); await esc();
check("Component ▸ Chair runs COMPONENT Chair", calls.some((c) => /^(COMPONENT|FURNITURE) Chair/i.test(c)), calls.join(","));
await page.click('.ribbon-tabs .tab:text-is("Home")'); await wait(150);

// ---- keys, by the state they change ----
await page.mouse.click(700, 500); await esc();
const st = () => A(() => ({ mode: window.archiApp.mode, panels: window.archiApp.showPanels, console: window.archiApp.showScriptConsole, tab: window.archiApp.panelTab }));
const p0 = (await st()).panels; await page.keyboard.press("Control+Alt+KeyP"); await wait(200);
check("Ctrl+Alt+P toggles the panels", (await st()).panels === !p0); await page.keyboard.press("Control+Alt+KeyP"); await wait(150);
for (const [d, m] of [["2", "3D"], ["3", "Split"], ["4", "Sheet"], ["1", "2D"]]) { await page.keyboard.press(`Control+Alt+Digit${d}`); await wait(400); check(`Ctrl+Alt+${d} switches to ${m}`, (await st()).mode === m, (await st()).mode); }
await page.keyboard.press("Control+Alt+KeyJ"); await wait(200); check("Ctrl+Alt+J shows the script console", (await st()).console === true); await page.keyboard.press("Control+Alt+KeyJ"); await wait(150);
await page.mouse.click(700, 500); await esc();
await page.keyboard.press("F2"); await wait(200); check("F2 opens the History panel", (await st()).tab === "History", (await st()).tab);
await page.mouse.click(700, 500); await esc(); calls.length = 0; await page.keyboard.press("Control+Alt+Shift+KeyP"); await wait(300); await esc();
check("Ctrl+Alt+Shift+P runs PREVIEW, not PLOT", calls.includes("PREVIEW") && !calls.includes("PLOT"), calls.join(","));
await A(() => window.archiApp.action("@selectAll")); await wait(300);
const selN = await A(() => window.archiApp.selection.ids.length);
await page.keyboard.press("Control+Shift+KeyA"); await wait(300);
check("Ctrl+Shift+A deselects all", selN > 0 && (await A(() => window.archiApp.selection.ids.length)) === 0, `${selN} → ${await A(() => window.archiApp.selection.ids.length)}`);
await page.mouse.click(700, 500); await esc(); await page.keyboard.press("Control+Shift+Slash"); await wait(400);
out.cmdref = (await page.locator('.twin[data-window="command-reference"]').isVisible()) ? "Command Reference" : "";
check("Ctrl+Shift+/ opens the Command Reference window", /Command Reference/i.test(out.cmdref), out.cmdref); await esc();
const helpRoute = () => A(() => document.querySelector('[data-window="help-browser"] .help-browser')?.dataset.route ?? "");
opened.length = 0; await page.keyboard.press("F1"); await wait(300);
check("F1 opens the offline help browser", (await helpRoute()) === "index" && !opened.length, (await helpRoute()) + " " + opened.join(","));
opened.length = 0; await page.click(".cmdline input, #cmdline input, .commandline input").catch(() => {}); await page.keyboard.type("LINE"); await page.keyboard.press("Enter"); await wait(300); await page.keyboard.press("F1"); await wait(300); await esc();
check("F1 during LINE opens its help page", (await helpRoute()) === "cmd/LINE" && !opened.length, (await helpRoute()) + " " + opened.join(","));
await A(() => document.querySelector('[data-window="help-browser"] .twin-close')?.click());

// ---- contextual tab: select one wall ----
const call = (m, p = {}) => page.evaluate(([a, b]) => window.archiApp.engine.call(a, b), [m, p]);
const walls = ((await call("schedule.get", { kind: "all" })).rows ?? []).slice(1).filter((r) => r[1] === "wall").slice(0, 2).map((r) => Number(r[0]));
const wallId = walls[0]; await call("select.set", { ids: walls }); await A(() => window.archiApp.refresh(["selection"])); await wait(400);
out.ctx = await A(() => document.querySelector(".ctx-strip .ctx-title")?.textContent ?? "");
check("selecting a wall shows Modify Wall", /Modify Wall/i.test(out.ctx), `${wallId} ${out.ctx.slice(0, 160)}`);
await esc();

// ---- commands that open windows / panels ----
async function cmd(line) { await A((l) => window.archiApp.runCommand(l), line); await wait(700); }
await A(() => window.archiApp.action("@selectAll")); await wait(200); await cmd("SELECTIONINFO"); check("SELECTIONINFO shows the Selection panel", /Zoom to Selection/.test(await page.evaluate(() => document.body.innerText))); await esc();
for (const [line, re] of [["SPELLDIALOG", /Spelling|Change All/], ["FILEVERSIONS", /Save Version Now/],
  ["GRAPHICSTYLES", /Higher priority|Line styles|Graphic/], ["ASSISTANT", /Provider|Assistant/], ["OUTLINERPANEL", /Filter by name|Outliner/], ["TEXTSTYLEDIALOG", /Text Style/]]) {
  await cmd(line); const t = await page.evaluate(() => document.body.innerText); check(`${line} opens its window`, re.test(t)); await esc(); await wait(150);
}
for (const [line, re] of [["NAVIGATOR", /Navigator/], ["NOTIFICATIONS", /Restore dismissed|Info/], ["ADCENTER", /Choose Drawing|Add All/]]) {
  await cmd(line); const t = await page.evaluate(() => document.body.innerText); check(`${line} fills its panel`, re.test(t)); await esc();
}
await cmd("FLOATPANEL Layers"); await wait(300);
check("FLOATPANEL Layers floats the panel", await A(() => !!window.archiWorkspace?.floatingWindow("Layers") || !!document.querySelector("[class*=float]")));
check("no page errors", errors.length === 0, errors.slice(0, 3).join(" / "));
console.log(JSON.stringify(out, null, 1).slice(0, 3000));
console.log(fails ? `${fails} failed` : "all passed");
await browser.close(); server.close(); process.exit(fails ? 1 : 0);
