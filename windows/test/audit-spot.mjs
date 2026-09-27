// Auditor spot checks (round 2): Component menu, Windows File menu, keyboard bugs. Renderer as a web page + fixture engine.
import http from "node:http"; import fs from "node:fs"; import path from "node:path"; import { createRequire } from "node:module"; import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."); const require = createRequire(import.meta.url);
const pw = require("playwright-core"); const web = path.join(root, "dist/renderer");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png" };
const server = http.createServer((req, res) => { const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname)); if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; } res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res); }).listen(0);
const browser = await pw.chromium.launch(); const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html?open=Cedar%20House.archi`); await page.waitForSelector("body.ready", { timeout: 30000 }); await page.waitForTimeout(800);
const out = {};
await page.click('.ribbon-tabs .tab:text-is("Insert")'); await page.waitForTimeout(200);
await page.click('.ribbon-body .rbtn:has(.t:text-is("Component"))'); await page.waitForTimeout(200);
out.component = await page.$$eval(".menu .mi", (els) => els.map((e) => `${e.textContent.trim()}${e.classList.contains("disabled") ? " [disabled]" : ""}`));
await page.keyboard.press("Escape");
await page.click('.titlebar .menubar button:text-is("File")'); await page.waitForTimeout(200);
out.fileMenu = await page.$$eval(".menu .mi", (els) => els.map((e) => e.textContent.trim()));
await page.keyboard.press("Escape"); await page.waitForTimeout(100);
const calls = []; await page.exposeFunction("__rec", (m) => calls.push(m));
await page.evaluate(() => { const a = window.archiApp; const orig = a.runCommand.bind(a); a.runCommand = (l) => { window.__rec(l); return orig(l); }; });
await page.mouse.click(700, 500);
for (const k of ["Control+Alt+KeyP", "Control+Alt+Shift+KeyP", "Control+Alt+Digit2", "Control+Alt+KeyJ", "Control+Shift+KeyI"]) { calls.push("--" + k); await page.keyboard.press(k); await page.waitForTimeout(250); await page.keyboard.press("Escape"); }
out.keys = calls;
out.selBefore = await page.evaluate(() => window.archiApp.selection.ids.length);
await page.keyboard.press("Control+Shift+KeyA"); await page.waitForTimeout(400);
out.selAfterCtrlShiftA = await page.evaluate(() => window.archiApp.selection.ids.length);
console.log(JSON.stringify(out, null, 1)); await browser.close(); server.close();
