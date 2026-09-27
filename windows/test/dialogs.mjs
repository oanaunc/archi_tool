// Dialogs test (part A of the Windows port): Settings (every page), Drawing Units, Drafting Settings, Quick Select,
// Layer States, the Layers panel (filters, tree), Page Setup, Customize Ribbon, workspaces, custom shortcuts, the
// keyboard reference, templates, and the portable UI commands' host notifications. Renderer as a web page with the
// fixture engine (like ui-snapshots.mjs); screenshots go to test-results/dialog-*.png.
// Usage: node build.mjs --web && node test/dialogs.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, "dialog-" + name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);
const run = (line) => page.evaluate((l) => window.archiApp.runCommand(l), line);
const history = async () => (await page.textContent(".cmd-history")) ?? "";
const ribbonTab = async (t) => { await page.click(`.ribbon-tabs .tab:text-is("${t}")`); await wait(120); };
const ribbonButton = (t) => page.click(`.ribbon-body .rbtn:has(.t:text-is("${t}"))`);
const sheetTitle = async () => (await page.textContent(".dlg.sheet .dlg-title").catch(() => "")) ?? "";
const pickFrom = async (pickerIndex, title) => { await page.locator(".dlg.sheet .picker").nth(pickerIndex).click(); await wait(80); await page.click(`.menu .mi:has-text("${title}")`); await wait(150); };

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(600);

// ---- Settings (OPTIONS): Manage ▸ Settings ▸ Options opens the window directly (ui target). ----
await ribbonTab("Manage");
await ribbonButton("Options");
await wait(250);
check("Settings window opens from the ribbon", await page.isVisible('.twin[data-window="settings"]'));
const tabs = await page.$$eval(".prefs-side .ptabbtn", (bs) => bs.map((b) => b.textContent));
check("six settings pages", tabs.join(",") === "General,Drafting,Display,Shortcuts,Toolbar,Agents", tabs.join(","));
for (const t of tabs) {
  await page.click(`.prefs-side .ptabbtn:has-text("${t}")`);
  await wait(120);
  await shot(`settings-${t.toLowerCase()}`, { clip: await page.locator('.twin[data-window="settings"]').boundingBox() });
}
await page.click('.prefs-side .ptabbtn:has-text("General")');
const general = await page.textContent(".prefs-main");
check("General page sections", ["AUTOSAVE AND RECOVERY", "CRASH REPORTS", "RECENT FILES", "NEW DRAWINGS", "FILE LOCATIONS", "SCRIPTS"].every((s) => general.includes(s)), general.slice(0, 120));
check("autosave default every 5 min", general.includes("every 5 min"));
await page.click('.prefs-main .stepper >> nth=0 >> .stb >> nth=0');
await wait(80);
check("autosave stepper", (await page.textContent(".prefs-main")).includes("every 6 min"));
await page.click('.prefs-main .chk:has-text("Autosave")');
await wait(80);
const asv = await page.evaluate(() => localStorage.getItem("archi.pref.autosaveMinutes"));
check("autosave off", (await page.textContent(".prefs-main")).includes("off") && asv === "0", String(asv));
// Display: theme, accent, crosshair.
await page.click('.prefs-side .ptabbtn:has-text("Display")');
await page.click('.prefs-main .segmented .seg:text-is("Light")');
await wait(150);
check("light theme applies at once", (await page.evaluate(() => document.documentElement.dataset.theme)) === "light");
await shot("light-theme");
await page.click('.prefs-main .segmented .seg:text-is("Dark")');
await page.click('.prefs-main .swatch-btn[aria-label="Blue"]');
await wait(100);
check("accent colour", (await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--accent").trim().toUpperCase())) === "#4C9AFF");
// Drafting defaults.
await page.click('.prefs-side .ptabbtn:has-text("Drafting")');
const drafting = await page.textContent(".prefs-main");
const nsnap = await page.locator(".prefs-main .chkgrid .chk").count();
check("Drafting page: 13 object snaps", nsnap === 13 && drafting.includes("Grid spacing (mm)"), `${nsnap} ${drafting.slice(0, 60)}`);
// Shortcuts: record Ctrl+Shift+L for LINE, then use it.
await page.click('.prefs-side .ptabbtn:has-text("Shortcuts")');
await page.click('.prefs-main button:has-text("Record Shortcut")');
await wait(50);
check("recording state", (await page.textContent(".prefs-main")).includes("Press keys… (Esc cancels)"));
await page.keyboard.press("Control+Shift+L");
await wait(80);
await page.fill('.prefs-main input[placeholder="Command (e.g. WALL or ZOOM E)"]', "LINE");
await page.click('.prefs-main button:has-text("Assign")');
await wait(100);
check("shortcut assigned", (await page.textContent(".prefs-main")).includes("Ctrl+Shift+L now runs LINE."));
await page.fill('.prefs-main input[placeholder="Search commands to assign"]', "matchprop");
await wait(100);
check("command search lists MATCHPROP", (await page.locator('.prefs-main .sc-row .cmdname:text-is("MATCHPROP")').count()) === 1, await page.$$eval('.prefs-main .sc-row .cmdname', (e) => e.map((x) => x.textContent).join(",")));
await shot("settings-shortcuts-assigned", { clip: await page.locator('.twin[data-window="settings"]').boundingBox() });
// Toolbar: quick access and ribbon tabs.
await page.click('.prefs-side .ptabbtn:has-text("Toolbar")');
await wait(100);
const qaBefore = await page.locator(".ribbon-tabs > .iconbtn").count();
await page.fill('.prefs-main input[placeholder="Command name (e.g. MATCHPROP)"]', "MATCHPROP");
await page.click('.prefs-main button:has-text("Add")');
await wait(150);
check("quick access toolbar gains MATCHPROP", (await page.locator(".ribbon-tabs > .iconbtn").count()) === qaBefore + 1);
await page.click('.prefs-main .chk:has-text("Collaborate")');
await wait(150);
check("hidden ribbon tab", !(await page.$$eval(".ribbon-tabs .tab", (els) => els.map((e) => e.textContent))).includes("Collaborate"));
await page.click('.prefs-main .chk:has-text("Collaborate")');
// Reset to Defaults (alert).
await page.click('.prefs-side button:has-text("Reset to Defaults")');
await wait(150);
check("reset alert", (await page.textContent(".dlg.sheet")).includes("Reset all settings to their defaults?"));
await page.click('.dlg.sheet button:has-text("Reset")');
await wait(150);
check("reset restores quick access and accent", (await page.locator(".ribbon-tabs > .iconbtn").count()) === qaBefore && (await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--accent").trim().toUpperCase())) === "#F5C518");
await page.click('.twin[data-window="settings"] .twin-close');
// The shortcut survives? (reset clears custom shortcuts, as on the Mac) — re-assign through the prefs and use it.
await page.evaluate(() => localStorage.setItem("archi.pref.shortcuts", JSON.stringify({ "ctrl+shift+l": "LINE" })));
await page.evaluate(() => window.dispatchEvent(new StorageEvent("storage", { key: "archi.pref.shortcuts" })));
await page.locator(".workspace canvas.plan >> nth=1").focus();
await page.keyboard.press("Control+Shift+L");
await wait(250);
check("custom shortcut runs LINE", (await page.evaluate(() => window.archiApp.prompt.command)) === "LINE");
await page.keyboard.press("Escape");
await wait(100);
// OPTIONS from the command line: engine host notification → Settings on that page.
await run("OPTIONS Display");
await wait(250);
check("OPTIONS Display opens the Display page", (await page.textContent(".prefs-side .ptabbtn.sel")) === "Display");
await page.click('.twin[data-window="settings"] .twin-close');

// ---- Drawing Units ----
await ribbonButton("Units");
await wait(250);
check("Drawing Units sheet", (await sheetTitle()) === "Drawing Units");
const sample0 = await page.textContent(".dlg.sheet .sample");
await pickFrom(0, "Architectural");
const sample1 = await page.textContent(".dlg.sheet .sample");
check("units sample updates", sample0 !== sample1 && (await page.textContent(".dlg.sheet")).includes("Precision: 1/4\""), `${sample0} → ${sample1}`);
await page.click('.dlg.sheet .radio:has-text("Inches (in)")');
await shot("units");
await page.click('.dlg.sheet button:has-text("OK")');
await wait(250);
check("units applied", (await page.evaluate(() => window.archiApp.info.units)) === "inches");
await run("UNITS");
await wait(250);
check("UNITS command opens the sheet (showPanel)", (await sheetTitle()) === "Drawing Units");
await page.keyboard.press("Escape");
await wait(100);
check("Esc cancels the sheet", !(await page.isVisible(".dlg.sheet")));

// ---- Drafting Settings ----
await ribbonButton("Drafting");
await wait(250);
check("Drafting Settings sheet", (await sheetTitle()) === "Drafting Settings");
check("13 snap toggles + Object snap", (await page.locator(".dlg.sheet .chk").count()) === 13 + 7);
await page.click('.dlg.sheet .chk:has-text("Ortho (F8)")');
await page.click('.dlg.sheet button:has-text("Clear All")');
await shot("drafting");
await page.click('.dlg.sheet button:has-text("OK")');
await wait(300);
check("ortho on after OK", (await page.getAttribute('.statusbar .tog:text-is("ORTHO")', "aria-pressed")) === "true");

// ---- Quick Select ----
await ribbonTab("Home");
await ribbonButton("Quick Select");
await wait(250);
check("Quick Select sheet", (await sheetTitle()) === "Quick Select");
await page.locator(".dlg.sheet .picker").nth(1).click();
await wait(80);
const typeTitle = await page.locator(".menu .mi >> nth=1").textContent();
await page.locator(".menu .mi >> nth=1").click();
await wait(150);
const match = await page.textContent(".dlg.sheet .match");
check("live match count", /^[1-9]\d* object\(s\) match$/.test(match), `${typeTitle}: ${match}`);
await shot("quick-select");
await page.click('.dlg.sheet .dlg-footer button.prominent');
await wait(300);
const selN = await page.evaluate(() => window.archiApp.selection.ids.length);
check("Select replaces the selection", selN === Number(match.split(" ")[0]), `${selN}`);
await page.keyboard.press("Escape");
await wait(200);

// ---- Layer States ----
await page.click('.ribbon-body .rbtn:has(.t:text-is("States"))');
await wait(250);
check("Layer States Manager", (await sheetTitle()) === "Layer States Manager");
await page.fill('.dlg.sheet input[placeholder="New state name"]', "plan");
await page.click('.dlg.sheet button:has-text("Save Current Layers")');
await wait(200);
check("layer state saved", (await page.textContent(".dlg.sheet .dlist")).includes("PLAN"));
await shot("layer-states");
await page.click('.dlg.sheet button:has-text("Close")');
await wait(100);

// ---- Layers panel (Layer Properties Manager) ----
await page.click('.panel-tabs .ptab:has(.t:text-is("Layers"))');
await wait(300);
const rows = await page.locator(".lp .lp-row").count();
check("layers panel rows", rows > 3, `${rows}`);
await page.fill(".lp .lp-filter input", "A-");
await wait(250);
const foot = await page.textContent(".lp .lp-foot");
check("layer filter", /of \d+ layers match the filter/.test(foot), foot);
await page.click('.lp .lp-tools .iconbtn >> nth=0');
await wait(250);
check("layer tree groups", (await page.locator(".lp .lp-group").count()) > 0);
await shot("layers-panel", { clip: { x: 1440 - 301, y: 150, width: 301, height: 600 } });
await page.click('.lp .lp-tools .iconbtn >> nth=0');
await page.fill(".lp .lp-filter input", "");
await wait(200);

// ---- Page Setup (Ctrl+Shift+P) ----
await page.locator(".workspace canvas.plan >> nth=1").focus();
await page.keyboard.press("Control+Shift+P");
await wait(300);
check("Page Setup — Model", (await sheetTitle()) === "Page Setup — Model");
await pickFrom(5, "1:100");
check("exact fit disabled at a fixed scale", await page.isDisabled('.dlg.sheet .chk:has-text("Exact fit")'));
await page.click('.dlg.sheet .chk:has-text("Plot stamp")');
await wait(100);
check("plot stamp fields", (await page.textContent(".dlg.sheet")).includes("Fields: {project}"));
await shot("page-setup-model");
await page.click('.dlg.sheet button:has-text("OK")');
await wait(200);
await page.click('.layout-tabs .lt:has-text("Sheet 1")');
await wait(300);
await run("PAGESETUP");
await wait(300);
check("Page Setup — sheet", (await sheetTitle()) === "Page Setup — Sheet 1");
await shot("page-setup-sheet");
await page.click('.dlg.sheet button:has-text("Cancel")');
await page.click('.layout-tabs .lt:has-text("Model")');
await wait(200);

// ---- Customize Ribbon ----
await run("CUI");
await wait(250);
check("Customize Ribbon window", await page.isVisible('.twin[data-window="cui"]'));
await page.click('.twin[data-window="cui"] .iconbtn[aria-label="New panel"]');
await page.fill('.twin[data-window="cui"] input[placeholder="Command (e.g. ZOOM E)"]', "line");
await page.click('.twin[data-window="cui"] button:has-text("Add")');
await page.fill('.twin[data-window="cui"] input[placeholder="Command (e.g. ZOOM E)"]', "nosuch");
await page.click('.twin[data-window="cui"] button:has-text("Add")');
await wait(100);
check("unknown command rejected", (await page.textContent('.twin[data-window="cui"]')).includes("Unknown command: nosuch"));
await page.fill('.twin[data-window="cui"] input[placeholder="Panel title (e.g. Selection)"]', "Selection");
await page.click('.twin[data-window="cui"] button:has-text("Hide")');
await wait(200);
await shot("cui", { clip: await page.locator('.twin[data-window="cui"]').boundingBox() });
await page.click('.twin[data-window="cui"] .twin-close');
await ribbonTab("Home");
const groups = await page.$$eval(".ribbon-body .rgroup .label", (ls) => ls.map((l) => l.textContent));
check("custom panel on Home", groups.includes("My Tools"), groups.join(","));
check("hidden built-in panel", !groups.includes("Selection"));
await shot("ribbon-custom", { clip: { x: 0, y: 0, width: 1440, height: 152 } });
await page.evaluate(() => { localStorage.removeItem("archi.pref.ribbonCustomization"); window.dispatchEvent(new StorageEvent("storage", { key: "archi.pref.ribbonCustomization" })); });
await wait(150);

// ---- Workspaces ----
await run("WSCURRENT 3D Modeling");
await wait(300);
const ws = await page.evaluate(() => ({ mode: window.archiApp.mode, tab: window.archiApp.ribbonTab, panel: window.archiApp.panelTab }));
check("workspace 3D Modeling", ws.mode === "3D" && ws.tab === "View" && ws.panel === "Materials", JSON.stringify(ws));
await page.click('.titlebar .menubar button:text-is("View")');
await page.hover('.menu .mi:has-text("Workspace")');
await wait(150);
await shot("workspace-menu");
await page.click('.menu .mi:has-text("Drafting & Annotation")');
await wait(300);
check("workspace from the View menu", (await page.evaluate(() => window.archiApp.mode)) === "2D");

// ---- Help ▸ Keyboard Shortcuts, File ▸ New from Template ----
await page.click('.titlebar .menubar button:text-is("Help")');
await page.click('.menu .mi:has-text("Keyboard Shortcuts")');
await wait(200);
const kbd = await page.textContent('.twin[data-window="keyboard-shortcuts"]');
check("keyboard reference with Windows keys", kbd.includes("Ctrl+K") && kbd.includes("Search commands") && !kbd.includes("⌘"), kbd.slice(0, 80));
await shot("keyboard-shortcuts", { clip: await page.locator('.twin[data-window="keyboard-shortcuts"]').boundingBox() });
await page.click('.twin[data-window="keyboard-shortcuts"] button:has-text("Done")');
await page.click('.titlebar .menubar button:text-is("File")');
await page.hover('.menu .mi:has-text("New from Template")');
await wait(200);
const tmenu = (await page.$$eval(".menu >> nth=1 >> .mi", (m) => m.map((x) => x.textContent))).join("|");
check("New from Template menu", tmenu.includes("Metric Drawing (mm)") && tmenu.includes("Save Drawing as Template…") && tmenu.includes("Show Templates Folder"), tmenu);
await page.keyboard.press("Escape");

// ---- Start screen templates (engine list) ----
await page.evaluate(() => { window.archiApp.showStart = true; window.archiApp.emit("start"); });
await wait(300);
const cards = await page.$$eval(".start .grid.t .card2 .n", (n) => n.map((x) => x.textContent));
check("start screen template gallery", cards.join(",") === "Metric,Metric Architectural,Imperial,Building", cards.join(","));
await page.click('.start .grid.t .card2:has-text("Metric Architectural")');
await wait(400);
check("Metric Architectural template", (await history()).includes("Metric Architectural template"));

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
fs.writeFileSync(path.join(out, "dialogs-results.json"), JSON.stringify({ date: new Date().toISOString(), results, errors }, null, 1));
await browser.close();
server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
