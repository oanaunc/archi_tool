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
const wait = (ms = 100) => page.waitForTimeout(ms);
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

// Test UI protocol with deterministic replies; the real engine paths are exercised by NamedPageSetupTests.
await page.evaluate(() => {
  const a = window.archiApp, original = a.tryCall.bind(a);
  window.feedbackCalls = []; const presets = new Map();
  a.tryCall = async (method, p) => {
    window.feedbackCalls.push({ method, p });
    if (method === "pagepresets.list") return { presets: [...presets].map(([name, preset]) => ({ name, preset })) };
    if (method === "pagepresets.delete") { presets.delete(p.name); return {}; }
    if (method === "pagepresets.apply") return {};
    if (method === "pagesetup.set" && p.presetName) presets.set(p.presetName, { settings: JSON.stringify(p.setup), paper: { name: p.paper, width: 420, height: 297 }, sectionStyle: p.sectionStyle });
    const result = await original(method, p);
    if (method === "pagesetup.get" && result?.isSheet) Object.assign(result, { hasSection: true, layouts: [{ index: 0, name: "Sheet 1" }, { index: 1, name: "Sheet 2" }], presets: [...presets].map(([name, preset]) => ({ name, preset })) });
    return result;
  };
});
await page.click('.layout-tabs .lt:has-text("Sheet 1")');
await run("PAGESETUP"); await wait(300);
check("sheet setup opens", (await sheetTitle()).includes("Sheet 1"), await sheetTitle());
await page.click('.dlg.sheet .chk:has-text("Customize section graphics on this sheet")');
check("section print controls visible", await page.isVisible('input[aria-label="Cut fill colour"]'));
await page.fill('input[aria-label="Section line colour"]', '#124578');
await page.fill('.dlg.sheet input[placeholder="mm"] >> nth=0', '0.8');
await page.click('.dlg.sheet .chk:has-text("Shaded surfaces")');
await page.fill('.dlg.sheet input[placeholder="Save current settings as…"]', 'Presentation');
await page.click('.dlg.sheet button:has-text("Save")'); await wait(180);
const saved = await page.evaluate(() => window.feedbackCalls.filter(x => x.method === "pagesetup.set").at(-1)?.p);
check("save preset includes section style", saved?.presetName === "Presentation" && saved?.presetOnly === true && saved?.sectionStyle?.lines?.cutLineweight === .8 && saved?.sectionStyle?.shaded === false && Math.abs(saved?.sectionStyle?.lines?.color?.r - 18/255) < .001);
check("named preset load enabled", await page.isEnabled('.dlg.sheet button:has-text("Load")'));
await page.click('.dlg.sheet button:has-text("Load")'); await wait();
await page.click('.dlg.sheet summary');
await page.click('.dlg.sheet .chk:has-text("Sheet 2")');
await page.click('.dlg.sheet button:has-text("Apply to Selected")'); await wait(250);
const applied = await page.evaluate(() => window.feedbackCalls.filter(x => x.method === "pagepresets.apply").at(-1)?.p);
check("selected-sheet targets sent to engine", applied?.name === "Presentation" && applied.layouts?.join(',') === '0,1');
await page.click('.dlg.sheet button:has-text("Cancel")');

for (const width of [600, 1280, 1920]) {
  await page.setViewportSize({ width, height: 900 }); await wait();
  const titles = await page.$$eval('.ribbon-tab-scroll .tab', es => es.map(e => e.textContent));
  for (const title of titles) { await page.locator('.ribbon-tab-scroll .tab').filter({ hasText: new RegExp(`^${title}$`) }).click(); await wait(20); }
  const bounds = await page.$$eval('.ribbon-tabs > .iconbtn', es => es.map(e => { const b = e.getBoundingClientRect(); return [b.x, b.right]; }));
  check(`all ribbon tabs and recovery controls fit at ${width}px`, titles.length === 11 && bounds.every(([x,r]) => x >= 0 && r <= width), JSON.stringify(bounds));
  await page.evaluate(() => { window.archiApp.setUI("ribbonCollapsed", true); window.archiApp.setUI("cleanScreen", true); });
  await run("RB"); await wait();
  check(`RB restores expanded ribbon at ${width}px`, await page.isVisible('.ribbon-body'));
}
check("no browser errors", errors.length === 0, errors.join("\n"));
await shot("sheet-feedback", { fullPage: true });
await browser.close(); server.close();
if (results.some(r => !r.ok)) process.exitCode = 1;
