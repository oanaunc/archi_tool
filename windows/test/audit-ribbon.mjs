// Auditor check (round 3): lists every disabled top-level ribbon button on every tab (web build + fixture engine).
import http from "node:http"; import fs from "node:fs"; import path from "node:path"; import { createRequire } from "node:module"; import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."); const require = createRequire(import.meta.url);
const pw = require("playwright-core"); const web = path.join(root, "dist/renderer");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png" };
const server = http.createServer((req, res) => { const p = path.join(web, decodeURIComponent(new URL(req.url, "http://x").pathname)); if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; } res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res); }).listen(0);
const browser = await pw.chromium.launch(); const page = await browser.newPage({ viewport: { width: 1920, height: 1000 } });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html?open=Cedar%20House.archi`); await page.waitForSelector("body.ready", { timeout: 30000 }); await page.waitForTimeout(800);
const tabs = await page.$$eval(".ribbon-tabs .tab", (t) => t.map((x) => x.textContent.trim()));
const dis = [];
for (const t of tabs) {
  await page.click(`.ribbon-tabs .tab:text-is("${t}")`); await page.waitForTimeout(200);
  const btns = await page.$$eval(".ribbon-body .rbtn", (b) => b.map((x, i) => ({ i, t: x.textContent.trim(), d: x.classList.contains("disabled") || x.disabled, menu: x.classList.contains("menu") || !!x.querySelector(".chev, .caret") })));
  for (const b of btns) {
    if (b.d) dis.push(`${t} ▸ ${b.t}`);
  }
}
console.log(dis.join("\n")); console.log("disabled:", dis.length);
await browser.close(); server.close();
