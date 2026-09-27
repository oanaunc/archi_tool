// Oanarina Archi Tool — GPL-3.0-or-later
// Smoke test of the PACKAGED Windows app (Playwright for Electron), run by .github/workflows/windows-app.yml:
//   1. start screen                     5. save (Ctrl+Shift+S, save dialog answered by the test) and reopen: the app is
//   2. Cedar House sample in the 2D plan   closed and started again with the saved .archi on its command line, like a
//   3. 3D view with the Golden hour preset double-click on a file associated with the app
//   4. LINE typed in the command line    6. PDF plot: "PLOT <file.pdf>" in the command line writes a PDF (checked: %PDF-)
// Screenshots, results.json and app.log (main process, renderer console, engine stderr) go to the output folder; the
// results are written after every check, so a cancelled run still leaves them.
// Usage: node packaging/smoke-electron.mjs "<path to Oanarina Archi Tool.exe>" <out dir>
//        node packaging/smoke-electron.mjs --web <out dir>   (the same scenario on dist/renderer with the fixture engine
//        in Chromium; steps that need the main process or the real engine are reported as SKIP)
// Exit code 1 when a required check fails (app start, start screen, Cedar House, LINE, save/reopen, PDF).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import http from "node:http";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const argv = process.argv.slice(2);
const web = argv[0] === "--web";
const exe = web ? null : argv[0];
const out = path.resolve(argv[1] || "smoke-results");
if (!web && (!exe || !fs.existsSync(exe))) { console.error(`smoke: app executable not found: ${exe}`); process.exit(2); }
fs.mkdirSync(out, { recursive: true });
const require = createRequire(import.meta.url);
let pw;
for (const m of ["playwright-core", "playwright", process.env.PLAYWRIGHT_MODULE].filter(Boolean)) { try { pw = require(m); break; } catch {} }
if (!pw || (!web && !pw._electron)) { console.error("smoke: playwright-core (with _electron) is not installed in windows/node_modules"); process.exit(2); }

const results = [];
const log = fs.createWriteStream(path.join(out, "app.log"));
const save = () => { try { fs.writeFileSync(path.join(out, "results.json"), JSON.stringify({ exe: exe ?? "web", results }, null, 2)); } catch {} };
const check = (name, ok, detail = "", required = false) => {
  const status = ok === "skip" ? "SKIP" : ok ? "PASS" : "FAIL";
  results.push({ name, ok: ok === "skip" ? null : !!ok, required, detail: String(detail ?? "") });
  console.log(`${status}  ${name}${detail ? "  — " + detail : ""}`);
  save();
  return ok === true || (ok && ok !== "skip");
};
const required = (name, ok, detail = "") => check(name, ok, detail, true);
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const work = fs.mkdtempSync(path.join(os.tmpdir(), "archismoke-"));   // no spaces: PLOT takes the path as a word
const savedFile = path.join(work, "SmokeCedar.archi");
const pdfFile = path.join(work, "SmokeCedar.pdf");

let app = null, browser = null, server = null, page = null;
async function finish(code) {
  save();
  try { await app?.close(); } catch {}
  try { await browser?.close(); } catch {}
  server?.close();
  log.end();
  const failed = results.filter((r) => r.required && r.ok === false).map((r) => r.name);
  console.log(`smoke: ${results.filter((r) => r.ok).length} passed, ${results.filter((r) => r.ok === false).length} failed, ${results.filter((r) => r.ok === null).length} skipped` + (failed.length ? ` (required: ${failed.join("; ")})` : ""));
  process.exit(code || (failed.length ? 1 : 0));
}
process.on("SIGINT", () => finish(130));
process.on("SIGTERM", () => finish(143));

async function launch(args = []) {
  if (web) {
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../dist/renderer");
    const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".jsonl": "text/plain" };
    server ??= http.createServer((req, res) => {
      const p = path.join(root, decodeURIComponent(new URL(req.url, "http://x").pathname));
      if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { "content-type": types[path.extname(p)] ?? "application/octet-stream" }); fs.createReadStream(p).pipe(res);
    }).listen(0);
    browser ??= await pw.chromium.launch();
    const pg = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await pg.goto(`http://127.0.0.1:${server.address().port}/index.html`);
    return pg;
  }
  app = await pw._electron.launch({ executablePath: exe, args, timeout: 90_000, env: { ...process.env, ELECTRON_ENABLE_LOGGING: "1" } });
  app.process().stdout?.on("data", (d) => log.write(d));
  app.process().stderr?.on("data", (d) => log.write(d));
  const pg = await app.firstWindow({ timeout: 90_000 });
  try { await app.evaluate(({ BrowserWindow }) => { const w = BrowserWindow.getAllWindows()[0]; w?.setSize(1440, 900); w?.center(); }); } catch {}
  return pg;
}
function watch(pg) {
  pg.on("console", (m) => log.write(`[console.${m.type()}] ${m.text()}\n`));
  pg.on("pageerror", (e) => log.write(`[pageerror] ${e}\n`));
}
const shot = (name) => page.screenshot({ path: path.join(out, name + ".png") }).catch((e) => check(`screenshot ${name}`, false, String(e)));
const title = () => page.textContent(".titlebar .title").catch(() => "");
const itemCount = () => page.evaluate(async () => (await window.archiApp?.tryCall?.("view.drawList", { rect: [-1e7, -1e7, 1e7, 1e7], pixelsPerUnit: 0.01 }))?.items?.length ?? -1).catch(() => -1);
const lastLog = (n = 12) => page.evaluate((k) => (window.archiApp?.log ?? []).slice(-k).join(" ⏎ "), n).catch(() => "");
/** Types a line in the command line and presses Enter (the way a user runs a command). */
async function typeLine(text) {
  await page.click(".cmdline .cmd-input input");
  await page.keyboard.type(text, { delay: 15 });
  await page.keyboard.press("Enter");
  await page.waitForTimeout(400);
}

// ---- 1. start screen ----
try { page = await launch(); watch(page); }
catch (e) { required("app launches", false, String(e)); await finish(1); }
required("app launches", true);
let ok = await page.waitForSelector("body.ready", { timeout: 60_000 }).then(() => true, () => false);
required("renderer ready (body.ready)", ok);
await page.waitForTimeout(800);
await shot("01-start-screen");
if (!required("start screen visible", await page.isVisible(".start .card").catch(() => false))) await finish(1);
const hello = await page.evaluate(() => window.archiApp?.hello ?? null).catch(() => null);
check("engine answered engine.hello", hello && Array.isArray(hello.commands), hello ? `version ${hello.version}, ${hello.commands?.length} commands` : "no hello (engine missing or crashed; see app.log)", !web);
if (!web) {
  const native = await page.evaluate(() => ({ captions: document.body.classList.contains("native-captions"), dpr: window.devicePixelRatio })).catch(() => null);
  check("Windows title bar (native caption buttons)", native?.captions, JSON.stringify(native));
}

// ---- 2. Cedar House sample → 2D plan ----
const sample = page.locator(".start .grid.s .card2", { hasText: "Cedar" }).first();
const target = (await sample.count()) ? sample : page.locator(".start .grid.s .card2").first();
await target.click().catch((e) => check("click Cedar House sample", false, String(e)));
ok = await page.waitForFunction(() => /Cedar House/.test(document.querySelector(".titlebar .title")?.textContent ?? ""), null, { timeout: 60_000 }).then(() => true, () => false);
required("Cedar House opened", ok, await title());
await page.evaluate(() => window.archiApp?.setUI?.("mode", "2D")).catch(() => {});
await page.mouse.move(700, 600);
await page.waitForTimeout(2500);
await shot("02-cedar-plan-2d");
const before = await itemCount();
required("plan has drawing items", before > 0, `${before} DrawItems`);
if (!ok) await finish(1);

// ---- 3. 3D view, Golden hour ----
await page.evaluate(() => window.archiApp?.setUI?.("mode", "3D")).catch(() => {});
await page.waitForTimeout(1000);
const preset = await page.evaluate(async () => {
  const a = window.archiApp; if (!a) return "no archiApp";
  const btn = [...document.querySelectorAll("button, [role=button], .chip, .seg *")].find((b) => /golden\s*hour/i.test(b.textContent ?? ""));
  if (btn) { btn.click(); return "clicked " + btn.textContent.trim(); }
  const r = await a.tryCall?.("render.preset", { name: "Goldenhour" });
  a.emit?.("render"); return r ? "render.preset Goldenhour" : "render.preset failed";
}).catch((e) => String(e));
check("Golden hour preset applied", /clicked|render\.preset Goldenhour/.test(preset), preset);
check("3D view has a canvas", (await page.locator(".workspace canvas").count().catch(() => 0)) > 0);
await page.waitForTimeout(web ? 1500 : 6000);
await shot("03-cedar-3d-golden-hour");

// ---- 4. LINE in the command line ----
await page.evaluate(() => window.archiApp?.setUI?.("mode", "2D")).catch(() => {});
await page.waitForTimeout(800);
await typeLine("LINE");
const prompting = await page.evaluate(() => !!window.archiApp?.prompt?.active).catch(() => false);
check("LINE starts and prompts for a point", prompting, await lastLog(3));
await typeLine("-3000,-3000");
await typeLine("-1000,-2000");
await typeLine("");            // Enter ends LINE
await page.waitForTimeout(800);
const after = await itemCount();
required("LINE added a line to the plan", after > before, `${before} → ${after} DrawItems; log: ${await lastLog(4)}`);
await page.mouse.move(700, 600);
await shot("04-line-command");

// ---- 5. save and reopen ----
if (web) {
  await page.keyboard.press("Control+Shift+S").catch(() => {});
  await page.waitForTimeout(500);
  check("save (Ctrl+Shift+S)", /Saved/.test(await lastLog(3)) ? true : "skip", "fixture engine: no file is written");
  check("reopen the saved file", "skip", "needs the Electron main process");
  check("PDF plot", "skip", "needs archi-engine");
  await finish(0);
}
await app.evaluate(({ dialog }, file) => { dialog.showSaveDialog = async () => ({ canceled: false, filePath: file }); }, savedFile);
await page.click(".cmdline .cmd-input input").catch(() => {});
await page.keyboard.press("Control+Shift+S");
ok = await (async () => { for (let i = 0; i < 60; i++) { if (fs.existsSync(savedFile) && fs.statSync(savedFile).size > 0) return true; await wait(500); } return false; })();
required("saved with Ctrl+Shift+S", ok, ok ? `${savedFile} (${fs.statSync(savedFile).size} bytes)` : `no file; log: ${await lastLog(4)}`);
await page.waitForTimeout(500);
check("title shows the saved name", /SmokeCedar/.test(await title()), await title());
await app.close().catch(() => {});
app = null;
if (ok) {
  // Reopen: a new app process with the file on its command line (Explorer double-click on an associated .archi).
  try { page = await launch([savedFile]); watch(page); }
  catch (e) { required("app relaunches with the saved file", false, String(e)); await finish(1); }
  ok = await page.waitForFunction(() => /SmokeCedar/.test(document.querySelector(".titlebar .title")?.textContent ?? ""), null, { timeout: 60_000 }).then(() => true, () => false);
  required("reopened the saved file from the command line", ok, await title());
  await page.evaluate(() => window.archiApp?.setUI?.("mode", "2D")).catch(() => {});
  await page.waitForTimeout(2000);
  const reopened = await itemCount();
  required("reopened drawing has the new line", reopened === after, `${reopened} DrawItems (saved ${after})`);
  await shot("05-reopened");

  // ---- 6. PDF plot ----
  await typeLine(`PLOT ${pdfFile}`);
  let pdf = await (async () => { for (let i = 0; i < 90; i++) { if (fs.existsSync(pdfFile) && fs.statSync(pdfFile).size > 0) return true; await wait(500); } return false; })();
  let how = "PLOT command";
  if (!pdf) {
    check("PLOT <file> in the command line writes the PDF", false, await lastLog(4));
    const r = await page.evaluate((p) => window.archiApp?.tryCall?.("plot.pdf", { path: p }), pdfFile).catch((e) => String(e));
    how = `plot.pdf RPC (${JSON.stringify(r)})`;
    pdf = fs.existsSync(pdfFile) && fs.statSync(pdfFile).size > 0;
  }
  const head = pdf ? fs.readFileSync(pdfFile).subarray(0, 5).toString("latin1") : "";
  required("PDF plot written", pdf && head === "%PDF-", pdf ? `${how}: ${fs.statSync(pdfFile).size} bytes, header ${head}` : `no PDF; log: ${await lastLog(4)}`);
  if (pdf) try { fs.copyFileSync(pdfFile, path.join(out, "06-plot.pdf")); } catch {}
  await shot("06-after-plot");
}
await finish(0);
