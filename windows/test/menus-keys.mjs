// Menu bar, keyboard shortcuts and the help / window-chrome commands (WINDOWS-GAPS.md gaps 1, 2, 5, 6, 8, 25, 26):
// every Mac menu entry of docs/windows-parity.json is in the Windows menu bar at the same path, Shift and Alt count in
// shortcuts, AltGr still types, the Component menus run COMPONENT <name>, About / Command Reference / What's New,
// Tools ▸ All Commands, F1 context help, the More-menu Block Library / Family Editor windows, and the engine's `host`
// notifications for ABOUT, CLEANSCREENON/OFF, STARTSCREEN, SAMPLEHOUSE, WHATSNEW and EXPORTCOMMANDS.
// Usage: node tools/gen-ui-data.mjs && node build.mjs --web && node test/menus-keys.mjs
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
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const wait = (ms) => page.waitForTimeout(ms);

await page.goto(base + "?open=Cedar%20House.archi");
await page.waitForSelector("body.ready", { timeout: 30000 });
await wait(600);
// Record what runs: engine command lines, shell actions and opened URLs.
await page.evaluate(() => {
  const a = window.archiApp;
  window.__calls = [];
  const run = a.runCommand.bind(a); a.runCommand = (l) => { window.__calls.push(l); return run(l); };
  const act = a.action.bind(a); a.action = (x) => { window.__calls.push(x); return act(x); };
  window.open = (u) => { window.__calls.push("open " + u); return null; };
});
const calls = async () => page.evaluate(() => window.__calls.splice(0));
const state = () => page.evaluate(() => { const a = window.archiApp; return { mode: a.mode, panels: a.showPanels, clean: a.cleanScreen, console: a.showScriptConsole, tab: a.panelTab, start: a.showStart, sel: a.selection.ids.length }; });

// ---- menu bar: the Mac menus with the same entries ----
const parity = JSON.parse(fs.readFileSync(path.resolve(root, "../docs/windows-parity.json"), "utf8"));
const tree = await page.evaluate(() => {
  const strip = (items) => items.map((i) => ({ t: i.title ?? null, sep: !!i.separator, dis: !!i.disabled, sc: i.shortcut ?? null, sub: i.submenu ? strip(i.submenu) : null }));
  return window.archiMenuBar().map((m) => ({ title: m.title, items: strip(m.items) }));
});
check("menu bar titles", tree.map((m) => m.title).join(",") === "File,Edit,View,Draw,Modify,Annotate,Architecture,Model,Analyze,Tools,Window,Help", tree.map((m) => m.title).join(","));
const missing = [], disabled = [];
let macEntries = 0;
const findIn = (items, title) => items.find((i) => i.t === title) ?? (title === "Zoom" ? items.find((i) => i.t === "Maximize") : null);
const PICKER = new Set(["2D Plan", "3D Model", "Split", "Sheet"]);
function compare(macItems, winItems, where) {
  for (const it of macItems ?? []) {
    if (it.separator || it.dynamic || !it.title) continue;
    if (it.system && !/Minimize|Zoom|Full Screen/.test(it.title)) continue;
    const sub = it.submenu ?? it.items;
    if (it.picker) { for (const r of sub) { macEntries++; if (!findIn(winItems, r.title)) missing.push(`${where} ▸ ${r.title}`); } continue; }
    macEntries++;
    const w = it.system && /Full Screen/.test(it.title) ? findIn(winItems, "Enter Full Screen") : findIn(winItems, it.title) ?? findIn(winItems, it.title.replace(/^Show |^Hide /, (x) => (x === "Show " ? "Hide " : "Show ")));
    if (!w) { missing.push(`${where} ▸ ${it.title}`); continue; }
    if (w.dis) disabled.push(`${where} ▸ ${it.title}${it.command ? ` (${it.command}${it.args ? " " + it.args : ""})` : ""}`);
    if (Array.isArray(sub) && sub.length && w.sub) compare(sub, w.sub, `${where} ▸ ${it.title}`);
  }
}
for (const m of parity.menus) {
  if (m.title === "Oanarina Archi Tool") continue;
  const w = tree.find((x) => x.title === m.title);
  if (w) compare(m.items, w.items, m.title); else missing.push(m.title);
}
check(`every Mac menu entry is in the Windows menu bar (${macEntries} entries)`, missing.length === 0, missing.slice(0, 12).join(" | "));
fs.writeFileSync(path.join(out, "menus-disabled.txt"), disabled.join("\n") + "\n");
console.log(`      ${disabled.length} entries disabled (commands not in this engine build): test-results/menus-disabled.txt`);
const at = (p) => { let items = tree; let it = null; for (const t of p.split(" ▸ ")) { it = (items === tree ? tree.map((m) => ({ t: m.title, sub: m.items })) : items).find((i) => i.t === t); if (!it) return null; items = it.sub ?? []; } return it; };
for (const p of ["File ▸ Open Recent ▸ Clear Menu", "File ▸ Insert ▸ Import File", "File ▸ Export ▸ GeoJSON", "File ▸ Export ▸ Schedules (CSV) ▸ Walls…", "File ▸ Plot Preview…", "File ▸ Publish All Sheets to PDF…",
  "Edit ▸ Deselect All", "Edit ▸ Selection Tools ▸ Quick Select", "Edit ▸ Groups & Isolation ▸ Isolate", "Edit ▸ Match Properties", "Edit ▸ Options…", "Edit ▸ Agent Server…",
  "View ▸ Zoom Window", "View ▸ Visual Style ▸ X-Ray", "View ▸ 3D View ▸ Iso", "View ▸ Layers Panel", "View ▸ Tool Palettes", "View ▸ Material Library…", "View ▸ 3D Tools ▸ Section Box",
  "View ▸ Show Script Console", "View ▸ Enter Full Screen", "Help ▸ Tutorials", "Help ▸ Open Sample House", "Help ▸ Command Reference", "Help ▸ Connect Claude…", "Help ▸ About Oanarina Archi Tool",
  "File ▸ Exit", "Window ▸ New Window"])
  check(`menu entry ${p}`, !!at(p));
const sc = (p) => { const parts = p.split(" ▸ "); const menu = tree.find((m) => m.title === parts[0]); const hits = (menu?.items ?? []).filter((i) => i.t === parts[1]); return p.split(" ▸ ").length === 2 ? hits.map((i) => i.sc).find(Boolean) : at(p)?.sc; };
check("menu shortcuts use Windows keys", sc("Edit ▸ Redo") === "Ctrl+Y" && sc("File ▸ Plot Preview…") === "Ctrl+Alt+Shift+P" && sc("View ▸ Hide Panels") === "Ctrl+Alt+P" && sc("View ▸ 2D Plan") === "Ctrl+Alt+1" && !sc("View ▸ Zoom Extents") && sc("View ▸ Clean Screen") === "Ctrl+0" && sc("Help ▸ Command Reference") === "Ctrl+Shift+/" && sc("Edit ▸ Deselect All") === "Ctrl+Shift+A",
  JSON.stringify([sc("Edit ▸ Redo"), sc("File ▸ Plot Preview…"), sc("View ▸ Hide Panels"), sc("View ▸ 2D Plan"), sc("View ▸ Zoom Extents"), sc("View ▸ Clean Screen"), sc("Help ▸ Command Reference"), sc("Edit ▸ Deselect All")]));
const allCmds = at("Tools ▸ All Commands");
check("Tools ▸ All Commands lists every category", (allCmds?.sub?.length ?? 0) > 10 && allCmds.sub.every((c) => (c.sub?.length ?? 0) > 0), `${allCmds?.sub?.length} categories`);
check("Help ▸ Command Reference and Tools ▸ Help entries are enabled", !at("Help ▸ Command Reference").dis && !at("Tools ▸ Help ▸ Search Commands")?.dis && !at("Tools ▸ Help ▸ About")?.dis);
for (const p of ["Tools ▸ View ▸ Clean Screen On", "Tools ▸ View ▸ Clean Screen Off", "Tools ▸ View ▸ History Panel", "Tools ▸ Start & Templates ▸ Start Screen", "Tools ▸ Navigation & Sheets ▸ Sample House", "Tools ▸ Families, Views & Panels ▸ What's New", "Help ▸ Export Command Reference…"])
  check(`enabled: ${p}`, at(p) && !at(p).dis);

// Runs a menu entry by path through the real menu item action.
const runMenu = (p) => page.evaluate((p) => {
  let items = window.archiMenuBar().map((m) => ({ title: m.title, submenu: m.items }));
  let it = null;
  for (const t of p.split(" ▸ ")) { it = items.find((i) => i.title === t); if (!it) throw new Error("no menu entry " + p); items = it.submenu ?? []; }
  it.action();
}, p);

// ---- menus run the right things ----
await runMenu("View ▸ 3D View ▸ Iso"); await wait(100);
check("View ▸ 3D View ▸ Iso runs ISOVIEW", (await calls()).includes("ISOVIEW"));
await runMenu("View ▸ Visual Style ▸ Shaded with Edges"); await wait(100);
check("View ▸ Visual Style runs VSCURRENT with the style", (await calls()).includes("VSCURRENT Shaded with Edges"));
await runMenu("View ▸ History Panel"); await wait(100);
check("View ▸ History Panel shows the panel", (await state()).tab === "History");
await runMenu("Tools ▸ View ▸ Clean Screen On"); await wait(150);
check("Tools ▸ View ▸ Clean Screen On (CLEANSCREENON)", (await state()).clean === true && !(await page.isVisible(".ribbon")));
await runMenu("Tools ▸ View ▸ Clean Screen Off"); await wait(150);
check("Tools ▸ View ▸ Clean Screen Off", (await state()).clean === false && (await page.isVisible(".ribbon")));
await runMenu("Tools ▸ Help ▸ Search Commands"); await wait(150);
check("Tools ▸ Help ▸ Search Commands opens the palette", await page.isVisible(".overlay .palette"));
await page.keyboard.press("Escape"); await wait(80);
await runMenu("Help ▸ Start Screen"); await wait(150);
check("Help ▸ Start Screen (STARTSCREEN)", (await state()).start === true && (await page.isVisible(".start .card")));
await page.evaluate(() => window.archiApp.closeStart()); await wait(80);
await calls();
await runMenu("Help ▸ Open Sample House"); await wait(100);
check("Help ▸ Open Sample House opens the sample", (await calls()).includes("@newWindow:sample"));
await runMenu("Tools ▸ Navigation & Sheets ▸ Sample House"); await wait(600);
check("Tools ▸ … ▸ Sample House (SAMPLEHOUSE)", (await calls()).includes("@newWindow:sample"));
await page.evaluate(() => window.archiApp.closeStart()); await wait(80);

// About (AboutWindow.swift)
await page.click('.titlebar .menubar button:text-is("Help")'); await wait(200);
await page.click('.menu .mi:has-text("About Oanarina Archi Tool")'); await wait(200);
const about = page.locator('.twin[data-window="about"]');
const aboutText = (await about.textContent()) ?? "";
check("Help ▸ About opens the About window", await about.isVisible());
check("About: name, version, licence, thanks, website", /Oanarina Archi Tool/.test(aboutText) && /Version 1\.\d+\.\d+ \(\d+\)/.test(aboutText) && /GNU General Public License/.test(aboutText) && /IfcOpenShell/.test(aboutText) && /www\.oanarinaldi\.com/.test(aboutText) && !/oanarina\.com/.test(aboutText), aboutText.slice(0, 120));
{ const b = await about.boundingBox(); if (b) await page.screenshot({ path: path.join(out, "help-about.png"), clip: b }); }
check("About fits without scrolling", await about.locator(".about").evaluate((e) => e.scrollHeight <= e.clientHeight + 1));
await about.locator(".about-link").click(); await wait(100);
check("About: the website link opens https://www.oanarinaldi.com", (await calls()).some((c) => c === "@openURL:https://www.oanarinaldi.com"));
await about.locator(".twin-close").click(); await wait(80);
await page.click('.ribbon-tabs .app-btn'); await wait(150);
check("the app icon opens About (ABOUT)", await page.isVisible('.twin[data-window="about"]'));
await page.locator('.twin[data-window="about"] .twin-close').click();

// Command Reference window (Ctrl+Shift+/)
await page.mouse.click(700, 500);
await page.keyboard.press("Control+Shift+Slash"); await wait(200);
const cref = page.locator('.twin[data-window="command-reference"]');
check("Ctrl+Shift+/ opens the Command Reference window", await cref.isVisible());
const total = await page.evaluate(() => window.archiApp.hello.commands.length);
check("Command Reference lists every command by category", (await cref.locator(".cref-row").count()) === total && (await cref.locator(".cref-hdr").count()) > 10, `${await cref.locator(".cref-row").count()} of ${total}`);
await cref.locator(".cref-search").fill("wall");
await wait(80);
const cnt = (await cref.locator(".cref-count").textContent()) ?? "";
check("Command Reference search", /^\d+ of \d+$/.test(cnt) && (await cref.locator(".cref-row").count()) < total && (await cref.locator('.cref-row .n:text-is("WALL")').count()) === 1, cnt);
{ const b = await cref.boundingBox(); if (b) await page.screenshot({ path: path.join(out, "help-command-reference.png"), clip: b }); }
await cref.locator(".twin-close").click();

// What's New
await runMenu("Tools ▸ Families, Views & Panels ▸ What's New"); await wait(150);
const wn = page.locator('.twin[data-window="whatsnew"]');
check("What's New window", await wn.isVisible() && /What's New in Oanarina Archi Tool/.test((await wn.textContent()) ?? "") && /FAMILYPANEL/.test((await wn.textContent()) ?? ""));
await wn.locator(".twin-close").click();

// Block Library / Family Editor from the More menus and the Tools menu (gap 25)
await page.click('.ribbon-tabs .tab:text-is("Insert")'); await wait(150);
await page.click('.ribbon-body .rbtn:has(.t:text-is("Blocks"))'); await wait(150);
await page.click('.menu .mi:has-text("Block Library")'); await wait(250);
check("Insert ▸ More ▸ Blocks ▸ Block Library opens the window", await page.isVisible('.pb-win[data-window="blockLibrary"]'));
await page.locator('.pb-win[data-window="blockLibrary"] .pb-close').click().catch(() => {});
await page.click('.ribbon-tabs .tab:text-is("Architecture")'); await wait(150);
await page.click('.ribbon-body .rbtn:has(.t:text-is("Systems"))'); await wait(150);
await page.click('.menu .mi:has-text("Family Editor")'); await wait(400);
check("Architecture ▸ More ▸ Systems ▸ Family Editor opens the window", await page.isVisible('.pb-win[data-window="familyEditor"]'));
await page.locator('.pb-win[data-window="familyEditor"] .pb-close').click().catch(() => {});
await runMenu("Tools ▸ Blocks & Attributes ▸ Block Library"); await wait(250);
check("Tools ▸ Blocks & Attributes ▸ Block Library opens the window", await page.isVisible('.pb-win[data-window="blockLibrary"]'));
await page.locator('.pb-win[data-window="blockLibrary"] .pb-close').click().catch(() => {});
await runMenu("Tools ▸ BIM Authoring ▸ Family Editor"); await wait(400);
check("Tools ▸ BIM Authoring ▸ Family Editor opens the window", await page.isVisible('.pb-win[data-window="familyEditor"]'));
await page.locator('.pb-win[data-window="familyEditor"] .pb-close').click().catch(() => {});
check("the command line keeps BLOCKLIBRARY / FAMILY", !(await calls()).some((c) => /^(BLOCKLIBRARY|FAMILY)$/.test(c)));

// Component menus (gap 1): COMPONENT <name>
await page.click('.ribbon-tabs .tab:text-is("Architecture")'); await wait(150);
const comp = page.locator('.ribbon-body .rbtn:has(.t:text-is("Component"))').first();
check("Architecture ▸ Component is enabled", !(await comp.isDisabled()));
await comp.click(); await wait(150);
check("Component menu entries are enabled", (await page.locator(".menu .mi.disabled").count()) === 0 && (await page.locator(".menu .mi").count()) === 12);
await page.click('.menu .mi:has-text("Sofa")'); await wait(150);
check("Component ▸ Sofa runs COMPONENT Sofa", (await calls()).includes("COMPONENT Sofa"));
await page.keyboard.press("Escape"); await wait(100);

// ---- keyboard: Shift and Alt count ----
const press = async (k) => { await page.mouse.click(1000, 450); await page.keyboard.press("Escape"); await calls(); await page.keyboard.press(k); await wait(250); return calls(); };
let s0 = await state();
let c = await press("Control+Alt+KeyP");
check("Ctrl+Alt+P shows / hides the panels (not PLOT)", (await state()).panels === !s0.panels && !c.includes("PLOT"), c.join(","));
await press("Control+Alt+KeyP");
c = await press("Control+Alt+Shift+KeyP");
check("Ctrl+Alt+Shift+P runs PREVIEW (not PLOT)", c.includes("PREVIEW") && !c.includes("PLOT"), c.join(","));
await page.keyboard.press("Escape"); await page.evaluate(() => document.querySelectorAll(".dlg-overlay").forEach((o) => o.remove()));
c = await press("Control+KeyP");
check("Ctrl+P runs PLOT", c.includes("PLOT"), c.join(","));
await page.evaluate(() => document.querySelectorAll(".dlg-overlay").forEach((o) => o.remove()));
for (const [k, m] of [["1", "2D"], ["2", "3D"], ["3", "Split"], ["4", "Sheet"], ["1", "2D"]]) { await press(`Control+Alt+Digit${k}`); check(`Ctrl+Alt+${k} → ${m}`, (await state()).mode === m); }
s0 = await state();
await press("Control+Alt+KeyJ");
check("Ctrl+Alt+J shows the script console", (await state()).console === !s0.console);
await press("Control+Alt+KeyJ");
await page.evaluate(() => window.archiApp.tryCall("select.set", { ids: window.archiApp.info ? [1, 2, 3] : [] }).then(() => window.archiApp.refresh(["selection"])));
await press("Control+KeyA");
const selAll = (await state()).sel;
await press("Control+Shift+KeyA");
check("Ctrl+A selects all, Ctrl+Shift+A deselects all", selAll > 0 && (await state()).sel === 0, `${selAll} → ${(await state()).sel}`);
c = await press("Control+Shift+KeyI");
check("Ctrl+Shift+I is Import (not a command line)", !c.some((x) => /^[A-Z]/.test(x)), c.join(","));
c = await press("Control+KeyK");
check("Ctrl+K opens command search", await page.isVisible(".overlay .palette"));
await page.keyboard.press("Escape");
await press("F2");
check("F2 shows the history panel", (await state()).tab === "History");
s0 = await state();
await press("Control+Digit0");
check("Ctrl+0 is Clean Screen", (await state()).clean === !s0.clean);
await press("Control+Digit0");
c = await press("Control+KeyY");
check("Ctrl+Y redo does not type", !(await page.inputValue(".cmdline input").catch(() => "")).includes("y"));
// AltGr = Ctrl+Alt on European layouts: Ctrl+Alt+Q typing "@" (German) and Ctrl+Alt+2 typing "@" (Spanish) still type.
await page.mouse.click(1000, 450); await page.keyboard.press("Escape");
await page.evaluate(() => {
  for (const [key, code] of [["@", "KeyQ"], ["@", "Digit2"], ["€", "KeyE"]]) window.dispatchEvent(new KeyboardEvent("keydown", { key, code, ctrlKey: true, altKey: true, bubbles: true, cancelable: true }));
});
await wait(100);
const typed = await page.evaluate(() => window.archiApp.commandInput);
check("AltGr characters type on the command line", typed === "@@€", JSON.stringify(typed));
check("AltGr+2 does not switch to 3D", (await state()).mode === "2D");
await page.keyboard.press("Escape");

// ---- F1: help for the running / typed command ----
await page.evaluate(() => { const a = window.archiApp; a.commandInput = ""; a.prompt = { ...a.prompt, active: false }; });
c = await press("F1");
const guide = "https://www.oanarinaldi.com/archi-tool-guide.html";
check("F1 idle opens the guide", c.includes("open " + guide), c.join(","));
await page.evaluate(() => { window.archiApp.commandInput = "wall"; });
await page.keyboard.press("F1"); await wait(100);
c = await calls();
check("F1 with WALL typed opens its guide section", c.includes(`open ${guide}#architecture`), c.join(","));
await page.evaluate(() => { const a = window.archiApp; a.commandInput = ""; a.prompt = { ...a.prompt, active: true, command: "LINE" }; });
await page.keyboard.press("F1"); await wait(100);
c = await calls();
check("F1 while LINE runs opens the Draw section", c.includes(`open ${guide}#draw`), c.join(","));
await page.evaluate(() => { const a = window.archiApp; a.prompt = { ...a.prompt, active: false, command: null }; });
check("Help ▸ Oanarina Archi Tool Help (F1) shows F1", at("Help ▸ Oanarina Archi Tool Help (F1)")?.sc === "F1");

// ---- engine `host` notifications (the commands typed on the command line) ----
const host = (p) => page.evaluate((x) => window.archiApp.onNotification("host", x), p);
await host({ action: "dialog", dialog: "about" }); await wait(100);
check("host dialog about", await page.isVisible('.twin[data-window="about"]'));
await page.locator('.twin[data-window="about"] .twin-close').click();
await host({ action: "cleanScreen", on: true }); await wait(100);
check("host cleanScreen on", (await state()).clean === true);
await host({ action: "cleanScreen", on: false }); await wait(100);
check("host cleanScreen off", (await state()).clean === false);
await host({ action: "startScreen" }); await wait(100);
check("host startScreen", (await state()).start === true);
await page.evaluate(() => window.archiApp.closeStart());
await host({ action: "dialog", dialog: "whatsNew" }); await wait(100);
check("host dialog whatsNew", await page.isVisible('.twin[data-window="whatsnew"]'));
await page.locator('.twin[data-window="whatsnew"] .twin-close').click();
await host({ action: "dialog", dialog: "commandSearch" }); await wait(100);
check("host dialog commandSearch", await page.isVisible(".overlay .palette"));
await page.keyboard.press("Escape");
await calls();
await host({ action: "newWindow", kind: "sample" }); await wait(100);
check("host newWindow sample", (await calls()).includes("@newWindow:sample"));
await page.evaluate(() => window.archiApp.closeStart());
const dl = page.waitForEvent("download", { timeout: 5000 }).catch(() => null);
await host({ action: "exportCommands", path: "", csv: false });
const d = await dl;
let md = "";
if (d) { const p = path.join(out, "commands.md"); await d.saveAs(p); md = fs.readFileSync(p, "utf8"); }
check("EXPORTCOMMANDS writes the Markdown reference with Where", /^# Oanarina Archi Tool — command reference/.test(md) && /\| `LINE` \|.*\| Draw \|/.test(md), md.split("\n").find((l) => l.includes("`LINE`")) ?? "no download");

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
await browser.close(); server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
