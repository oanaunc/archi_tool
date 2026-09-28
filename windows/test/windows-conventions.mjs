// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Windows conventions in the renderer (src/renderer/ui/windows-conventions.ts, titlebar.ts), run as a web page with the
// fixture engine: F1 opens the user guide, Alt+letter opens the title-bar menus, Ctrl+Shift+Z redoes, File ▸ Exit
// (Alt+F4), Ctrl shortcuts in the menus (no ⌘), every ribbon icon is a mapped Lucide glyph, and a devicePixelRatio
// change re-sizes the plan canvas. Usage: node build.mjs --web && node test/windows-conventions.mjs
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
const web = path.join(root, "dist/renderer");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".jsonl": "text/plain", ".map": "application/json" };
const server = http.createServer((req, res) => {
  const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!p.startsWith(web) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res);
}).listen(0);
const base = `http://127.0.0.1:${server.address().port}/index.html`;
const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
await page.addInitScript(() => { window.__opened = []; window.open = (u) => { window.__opened.push(String(u)); return null; }; });
await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await page.waitForTimeout(600);

// F1 → user guide
await page.mouse.click(700, 600);
await page.keyboard.press("F1");
const opened = await page.evaluate(() => window.__opened);
check("F1 opens archi-tool-guide.html", opened.includes("https://www.oanarinaldi.com/archi-tool-guide.html"), opened.join(" "));

// Alt+F / Alt+H open the title-bar menus
await page.keyboard.press("Alt+KeyF");
await page.waitForTimeout(150);
const fileMenu = await page.$$eval(".menu", (ms) => ms.map((m) => m.textContent ?? "").join("|"));
check("Alt+F opens the File menu", /Save As/.test(fileMenu) && /Open/.test(fileMenu));
check("File menu has Exit Alt+F4", /Exit\s*Alt\+F4/.test(fileMenu));
check("menu shortcuts use Ctrl, not ⌘", !/[⌘⌥⇧]/.test(fileMenu) && /Ctrl\+S/.test(fileMenu));
await page.keyboard.press("Escape");
await page.keyboard.press("Alt+KeyH");
await page.waitForTimeout(150);
const helpMenu = await page.$$eval(".menu", (ms) => ms.map((m) => m.textContent ?? "").join("|"));
check("Alt+H opens Help with context help on F1 and the User Guide", /Oanarina Archi Tool Help \(F1\)\s*F1/.test(helpMenu) && /User Guide/.test(helpMenu), helpMenu.slice(0, 120));
await page.keyboard.press("Escape");

// Ctrl+Shift+Z → redo (not undo)
const calls = await page.evaluate(async () => {
  const a = window.archiApp; const seen = [];
  const u = a.undo.bind(a), r = a.redo.bind(a);
  a.undo = async () => { seen.push("undo"); }; a.redo = async () => { seen.push("redo"); };
  document.querySelector("canvas")?.focus();
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "Z", code: "KeyZ", ctrlKey: true, shiftKey: true, bubbles: true }));
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "y", code: "KeyY", ctrlKey: true, bubbles: true }));
  a.undo = u; a.redo = r; return seen;
});
check("Ctrl+Shift+Z and Ctrl+Y redo", calls.join(",") === "redo,redo", calls.join(","));

// Ribbon and palette icons: no generic fallback glyph
const iconStats = await page.$$eval(".ribbon svg.icon", (s) => ({ n: s.length, generic: s.filter((x) => x.dataset.lucide === "SquareTerminal" && x.dataset.sf !== "terminal").map((x) => x.dataset.sf) }));
check("ribbon icons all mapped", iconStats.n > 20 && iconStats.generic.length === 0, `${iconStats.n} icons, fallback: ${iconStats.generic.join(" ")}`);

// High DPI: the plan canvas follows a devicePixelRatio change (window dragged to a 150 % monitor)
const dpr = await page.evaluate(async () => {
  Object.defineProperty(window, "devicePixelRatio", { configurable: true, get: () => 1.5 });
  window.dispatchEvent(new Event("archi:dpr"));
  await new Promise((r) => setTimeout(r, 100));
  const c = document.querySelector("canvas.plan"); const r = c.getBoundingClientRect();
  return { w: c.width, css: r.width };
});
check("plan canvas re-sized for 150 % scaling", Math.abs(dpr.w - Math.round(dpr.css * 1.5)) <= 1, `${dpr.w} px for ${dpr.css} CSS px`);

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
await browser.close(); server.close();
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
