// Shell polish against the Mac app (fixture engine, Playwright/Chromium): the panel tab bar (PanelsView.swift) at
// 1440×900 and 1920×1080, the start screen's thumbnails (StartView.swift, DocumentThumbnails), the title-bar menus'
// access keys (unique Alt+letter per menu), and floating panels as separate OS windows (FloatingPanels.swift).
// Usage: node build.mjs --web && node test/shell-polish.mjs   (screenshots in test-results/polish-*.png)
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

let fails = 0;
const check = (name, ok, detail = "") => { if (!ok) fails++; console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch();
const errors = [];

async function open(width, height) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(base);
  await page.waitForSelector("body.ready");
  await page.waitForTimeout(500);
  return { context, page };
}

// ---- Bundled sample thumbnails (the packaging copies resources/assets → renderer/assets) ----
for (const name of ["Cedar House", "Nordic House"]) {
  const f = path.join(root, "resources/assets/samples", `${name}.thumb.json`);
  let n = 0;
  try { n = JSON.parse(fs.readFileSync(f, "utf8")).items.length; } catch {}
  check(`${name}.thumb.json is bundled with plan items`, n > 100, `${n} items`);
}

// ---- Start screen ----
{
  const { context, page } = await open(1440, 900);
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(out, "polish-start.png") });
  const cards = await page.$$eval(".start .card2", (els) => els.map((c) => {
    const t = c.querySelector(".thumb"), r = t.getBoundingClientRect(), cr = c.getBoundingClientRect();
    return { name: c.querySelector(".n")?.textContent, thumb: r.width, inner: cr.width - 18, left: r.left - cr.left };
  }));
  check("every start card's thumbnail box spans the card (no dark strip beside the icon)", cards.length >= 6 && cards.every((c) => Math.abs(c.thumb - c.inner) <= 1.5 && Math.abs(c.left - 9) <= 1.5), JSON.stringify(cards.map((c) => [c.name, Math.round(c.thumb), Math.round(c.inner)])));
  const samples = await page.$$eval(".start .grid.s .card2", (els) => els.map((c) => {
    const cv = c.querySelector(".thumb canvas");
    if (!cv) return { name: c.textContent, painted: 0 };
    const d = cv.getContext("2d").getImageData(0, 0, cv.width, cv.height).data;
    let painted = 0;
    for (let i = 0; i < d.length; i += 4) if (Math.abs(d[i] - 30) + Math.abs(d[i + 1] - 31) + Math.abs(d[i + 2] - 34) > 30) painted++;
    const star = c.querySelector(".n svg");
    return { name: c.querySelector(".n span")?.textContent, painted, w: cv.clientWidth, h: cv.clientHeight, starFill: star?.getAttribute("fill") };
  }));
  check("Cedar House and Nordic House show plan thumbnails", samples.length === 2 && samples.every((s) => s.painted > 400), JSON.stringify(samples));
  check("thumbnails fill the 100 px box (aspect-fill of the 320×200 plan picture)", samples.every((s) => s.h === 100 && s.w > 200), JSON.stringify(samples.map((s) => [s.w, s.h])));
  check("sample cards carry a solid star (star.fill)", samples.every((s) => s.starFill === "currentColor"));

  // ---- Title-bar menus: unique Windows access keys ----
  const mn = await page.$$eval(".titlebar .menubar button", (els) => els.map((b) => [b.textContent, b.dataset.mnemonic, b.textContent.charAt(Number(b.dataset.mnemonicAt ?? -1))]));
  const keys = mn.map((m) => m[1]);
  check("every menu has an access key and no two share one", keys.every(Boolean) && new Set(keys).size === keys.length, JSON.stringify(mn));
  const want = { File: "f", Edit: "e", View: "v", Draw: "d", Modify: "m", Annotate: "n", Architecture: "a", Model: "o", Analyze: "y", Tools: "t", Window: "w", Help: "h" };
  check("access keys: File F, Edit E, View V, Draw D, Modify M, Annotate N, Architecture A, Model O, Analyze Y, Tools T, Window W, Help H",
    Object.entries(want).every(([n, k]) => mn.some((m) => m[0] === n && m[1] === k && m[2].toLowerCase() === k)), JSON.stringify(mn.map((m) => m[0] + ":" + m[1])));
  await page.keyboard.down("Alt");
  const cues = await page.evaluate(() => [...document.querySelectorAll(".titlebar .menubar button")].map((b) => {
    const m = b.querySelector(".mn"), t = b.firstChild, at = Number(b.dataset.mnemonicAt);
    const r = document.createRange(); r.setStart(t, at); r.setEnd(t, at + 1);
    const lr = r.getBoundingClientRect(), mr = m.getBoundingClientRect();
    return { name: b.textContent, shown: getComputedStyle(m).display !== "none", under: Math.abs(mr.left - lr.left) < 0.6 && Math.abs(mr.width - lr.width) < 0.6 && mr.top >= lr.bottom - 1 && mr.top <= lr.bottom + 3 };
  }));
  await page.keyboard.up("Alt");
  const cuesOff = await page.evaluate(() => [...document.querySelectorAll(".titlebar .menubar .mn")].every((m) => getComputedStyle(m).display === "none"));
  await page.screenshot({ path: path.join(out, "polish-menubar.png"), clip: { x: 0, y: 0, width: 700, height: 32 } });
  check("holding Alt underlines each menu's access key under its letter, releasing it hides them", cues.every((c) => c.shown && c.under) && cuesOff, JSON.stringify(cues.filter((c) => !(c.shown && c.under))));
  check("menu labels stay plain text (\"Help\", not split around the access key)", mn.every((m) => /^[A-Za-z]+$/.test(m[0])));
  await page.click(".start .grid.s .card2 >> nth=0");
  await page.waitForTimeout(700);
  const opened = [];
  for (const [key, menu, item] of [["KeyA", "Architecture", /Wall/], ["KeyN", "Annotate", /Dimension|Text/], ["KeyY", "Analyze", /Area|Clash|Check|Measure/], ["KeyO", "Model", /./], ["KeyF", "File", /Save As/]]) {
    await page.keyboard.press("Alt+" + key);
    await page.waitForTimeout(250);
    const openBtn = await page.$eval(".titlebar .menubar button.open", (b) => b.textContent).catch(() => "");
    const text = await page.$eval(".menu", (m) => m.textContent).catch(() => "");
    opened.push(`${key.slice(3)}→${openBtn}`);
    check(`Alt+${key.slice(3)} opens ${menu}`, openBtn === menu && item.test(text), openBtn);
    await page.keyboard.press("Escape");
    await page.waitForTimeout(100);
  }
  await context.close();
}

// ---- Panel tab bar (PanelsView.swift) at the two common window sizes ----
for (const [w, hgt] of [[1440, 900], [1920, 1080]]) {
  const { context, page } = await open(w, hgt);
  await page.click(".start .grid.s .card2 >> nth=0");
  await page.waitForTimeout(800);
  await page.screenshot({ path: path.join(out, `polish-panel-tabs-${w}x${hgt}.png`), clip: { x: w - 300, y: 148, width: 300, height: 130 } });
  const m = await page.evaluate(() => {
    const tabs = [...document.querySelectorAll(".panels:not(.floating) .panel-tabs .ptab")];
    const rects = tabs.map((t) => t.getBoundingClientRect());
    const rows = [...new Set(rects.map((r) => Math.round(r.top)))];
    const cols = [...new Set(rects.map((r) => Math.round(r.left)))];
    const grid = document.querySelector(".panel-tabs .grid").getBoundingClientRect();
    const side = document.querySelector(".panel-tabs .side").getBoundingClientRect();
    const panel = document.querySelector(".panels:not(.floating)").getBoundingClientRect();
    const labels = tabs.map((t) => { const l = t.querySelector(".t"); return { text: l.textContent, size: parseFloat(l.style.fontSize), cut: l.scrollWidth > l.clientWidth + 0.5, width: l.clientWidth }; });
    const icons = Object.fromEntries(tabs.map((t) => [t.querySelector(".t").textContent, t.querySelector("svg")?.dataset.lucide]));
    return { n: tabs.length, rows: rows.length, cols: cols.length, cell: rects.map((r) => Math.round(r.width)), height: rects.map((r) => Math.round(r.height)),
      gridMid: (grid.top + grid.bottom) / 2, sideMid: (side.top + side.bottom) / 2, panelW: panel.width, gridLeft: grid.left - panel.left, sideRight: panel.right - side.right, labels, icons };
  });
  check(`${w}×${hgt}: 14 tabs in 6 columns × 3 rows of 25×36 px cells, like the Mac`, m.n === 14 && m.rows === 3 && m.cols === 6 && m.cell.every((c) => c === 25) && m.height.every((x) => x === 36), JSON.stringify({ n: m.n, rows: m.rows, cols: m.cols }));
  check(`${w}×${hgt}: panel column 300 px with the tab grid and the float/close buttons centred`, Math.round(m.panelW) === 300 && Math.abs(m.gridLeft - m.sideRight) <= 2, `panel ${m.panelW}, left ${m.gridLeft}, right ${m.sideRight}`);
  check(`${w}×${hgt}: float and close buttons centred beside the grid (VStack in an HStack)`, Math.abs(m.gridMid - m.sideMid) <= 1.5, `${m.gridMid} vs ${m.sideMid}`);
  // minimumScaleFactor(0.7): a label shrinks (never below 70 % of 8.5 px) until it fits; only then is it cut with "…".
  const bad = m.labels.filter((l) => l.size < 8.5 * 0.7 - 0.01 || l.size > 8.5 || (l.cut && l.size > 8.5 * 0.7 + 0.01));
  check(`${w}×${hgt}: tab labels shrink to fit (8.5 px down to 70 %) before truncating`, bad.length === 0, JSON.stringify(bad));
  const whole = ["Layers", "Levels", "Tools", "Sheets", "Alerts"].filter((t) => m.labels.find((l) => l.text === t)?.cut);
  check(`${w}×${hgt}: short labels show whole (Layers, Levels, Tools, Sheets, Alerts — cut to "Lay…" before)`, whole.length === 0, whole.join(","));
  check(`${w}×${hgt}: long labels truncate like the Mac (Properties, Quick Props)`, ["Properties", "Quick Props"].every((t) => m.labels.find((l) => l.text === t)?.cut), JSON.stringify(m.labels.map((l) => [l.text, l.size, l.cut])));
  check(`${w}×${hgt}: tab icons follow the Mac symbols (Tools: square.grid.3x3.square, Quick Props: slider.horizontal.below.rectangle)`,
    m.icons.Tools === "Grid3X3" && m.icons["Quick Props"] === "Monitor" && m.icons.Properties === "SlidersHorizontal", JSON.stringify(m.icons));
  await context.close();
}

// ---- Floating panels are separate OS windows ----
{
  const { context, page } = await open(1440, 900);
  await page.click(".start .grid.s .card2 >> nth=0");
  await page.waitForTimeout(700);
  const popup = page.waitForEvent("popup", { timeout: 5000 }).catch(() => null);
  await page.evaluate(() => window.archiApp.runCommand("FLOATPANEL Properties"));
  const win = await popup;
  await page.waitForTimeout(600);
  check("FLOATPANEL opens a separate window (window.open → BrowserWindow in Electron)", !!win && (await win.evaluate(() => window.name)) === "archi-float:Properties");
  if (win) {
    check("its title is the panel name (NSPanel.title)", (await win.title()) === "Properties");
    const head = await win.evaluate(() => {
      const hd = document.querySelector(".ws-floathead"), r = hd.getBoundingClientRect();
      return { h: Math.round(r.height), bg: getComputedStyle(hd).backgroundColor, title: hd.querySelector(".ttl").textContent, weight: getComputedStyle(hd.querySelector(".ttl")).fontWeight, body: document.querySelector(".panel-body")?.textContent ?? "", font: getComputedStyle(document.body).fontFamily };
    });
    check("floating window: 28 px header on the tab-bar colour, bold title, the panel's content, the app's fonts", head.h === 28 && head.bg === "rgb(35, 36, 40)" && head.title === "Properties" && Number(head.weight) >= 600 && /PROJECT|No selection/i.test(head.body) && /Segoe UI/.test(head.font), JSON.stringify({ ...head, body: head.body.slice(0, 40) }));
    const docked = await page.$$eval(".panels:not(.floating) .ptab .t", (els) => els.map((e) => e.textContent));
    check("the floating tab leaves the docked strip", !docked.includes("Properties") && docked.length === 13);
    // Context menus and tooltips open in the window they belong to.
    await win.hover(".ws-floathead .iconbtn");
    await win.waitForTimeout(900);
    check("tooltips of the floating window show in that window", (await win.$(".tooltip")) !== null && (await page.$(".tooltip")) === null);
    await win.setViewportSize({ width: 360, height: 600 });
    await win.waitForTimeout(500);
    await win.screenshot({ path: path.join(out, "polish-floating-properties.png") });
    await win.close({ runBeforeUnload: true });
    await page.waitForTimeout(400);
    const frame = await page.evaluate(() => JSON.parse(localStorage.getItem("archi.floatingPanels.frame.Properties") ?? "null"));
    check("the window's frame is remembered (setFrameAutosaveName)", frame && frame.w === 360 && frame.h === 600, JSON.stringify(frame));
    const docked2 = await page.$$eval(".panels:not(.floating) .ptab .t", (els) => els.map((e) => e.textContent));
    check("closing the window docks the panel and selects it", docked2.includes("Properties") && (await page.evaluate(() => window.archiApp.panelTab)) === "Properties");
    const again = page.waitForEvent("popup", { timeout: 5000 }).catch(() => null);
    await page.evaluate(() => window.archiApp.runCommand("FLOATPANEL Properties"));
    const win2 = await again;
    await page.waitForTimeout(400);
    check("floating it again reuses the remembered size", !!win2 && JSON.stringify(win2.viewportSize()) === JSON.stringify({ width: 360, height: 600 }), JSON.stringify(win2?.viewportSize()));
    await win2?.close({ runBeforeUnload: true });
  }
  await context.close();
}

// ---- Electron main process: window.open "archi-float:" becomes an owned tool window ----
{
  const main = fs.readFileSync(path.join(root, "src/main/main.ts"), "utf8");
  check("main.ts turns archi-float windows into owned, taskbar-less tool windows shown without focus",
    /setWindowOpenHandler/.test(main) && /archi-float:/.test(main) && /parent,/.test(main) && /skipTaskbar: true/.test(main) && /showInactive\(\)/.test(main));
}

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" / "));
console.log(fails ? `${fails} failed` : "all passed");
await browser.close(); server.close(); process.exit(fails ? 1 : 0);
