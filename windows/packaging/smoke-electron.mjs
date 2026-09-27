// Oanarina Archi Tool — GPL-3.0-or-later
// Smoke test of the PACKAGED Windows app (Playwright for Electron): start screen, Cedar House sample in the 2D plan,
// 3D view with the Golden hour preset. Screenshots + results.json + app.log go to the output folder.
// Usage: node packaging/smoke-electron.mjs "<path to Oanarina Archi Tool.exe>" <out dir>
// Exit code 1 when the app does not start, the start screen is missing or the sample does not open.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const [exe, outArg] = process.argv.slice(2);
if (!exe || !fs.existsSync(exe)) { console.error(`smoke: app executable not found: ${exe}`); process.exit(2); }
const out = path.resolve(outArg || "smoke-results");
fs.mkdirSync(out, { recursive: true });
const require = createRequire(import.meta.url);
let pw;
for (const m of ["playwright-core", "playwright"]) { try { pw = require(m); break; } catch {} }
if (!pw?._electron) { console.error("smoke: playwright-core (with _electron) is not installed in windows/node_modules"); process.exit(2); }

const results = [];
const log = fs.createWriteStream(path.join(out, "app.log"));
const check = (name, ok, detail = "") => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); return !!ok; };
const finish = async (app, code) => {
  fs.writeFileSync(path.join(out, "results.json"), JSON.stringify({ exe, results }, null, 2));
  try { await app?.close(); } catch {}
  log.end(); process.exit(code);
};

let app, page;
try {
  app = await pw._electron.launch({ executablePath: exe, args: [], timeout: 90_000, env: { ...process.env, ELECTRON_ENABLE_LOGGING: "1" } });
  app.process().stdout?.on("data", (d) => log.write(d));
  app.process().stderr?.on("data", (d) => log.write(d));
  page = await app.firstWindow({ timeout: 90_000 });
} catch (e) { check("app launches", false, String(e)); await finish(app, 1); }
check("app launches", true);
page.on("console", (m) => log.write(`[console.${m.type()}] ${m.text()}\n`));
page.on("pageerror", (e) => log.write(`[pageerror] ${e}\n`));
const shot = (name) => page.screenshot({ path: path.join(out, name + ".png") }).catch((e) => check(`screenshot ${name}`, false, String(e)));
const wait = (ms) => page.waitForTimeout(ms);
try { await app.evaluate(({ BrowserWindow }) => { const w = BrowserWindow.getAllWindows()[0]; w?.setSize(1440, 900); w?.center(); }); } catch {}

// 1. Start screen
let ok = await page.waitForSelector("body.ready", { timeout: 60_000 }).then(() => true, () => false);
check("renderer ready (body.ready)", ok);
await wait(800);
await shot("01-start-screen");
if (!check("start screen visible", await page.isVisible(".start .card").catch(() => false))) await finish(app, 1);
const hello = await page.evaluate(() => window.archiApp?.hello ?? null).catch(() => null);
check("engine answered engine.hello", hello && Array.isArray(hello.commands), hello ? `version ${hello.version}, ${hello.commands?.length} commands` : "no hello (engine missing or crashed; see app.log)");

// 2. Cedar House sample -> 2D plan
const sample = page.locator(".start .grid.s .card2", { hasText: "Cedar" }).first();
const target = (await sample.count()) ? sample : page.locator(".start .grid.s .card2").first();
await target.click().catch((e) => check("click Cedar House sample", false, String(e)));
ok = await page.waitForFunction(() => /Cedar House/.test(document.querySelector(".titlebar .title")?.textContent ?? ""), null, { timeout: 60_000 }).then(() => true, () => false);
check("Cedar House opened", ok, await page.textContent(".titlebar .title").catch(() => ""));
await page.evaluate(() => window.archiApp?.setUI?.("mode", "2D")).catch(() => {});
await page.mouse.move(700, 600);
await wait(2500);
await shot("02-cedar-plan-2d");
const items = await page.evaluate(async () => (await window.archiApp?.tryCall?.("view.drawList", { rect: [-1e6, -1e6, 1e6, 1e6], pixelsPerUnit: 0.01 }))?.items?.length ?? -1).catch(() => -1);
check("plan has drawing items", items > 0, `${items} DrawItems`);
if (!ok) await finish(app, 1);

// 3. 3D view, Golden hour
await page.evaluate(() => window.archiApp?.setUI?.("mode", "3D")).catch(() => {});
await wait(1000);
const preset = await page.evaluate(async () => {
  const a = window.archiApp; if (!a) return "no archiApp";
  const btn = [...document.querySelectorAll("button, [role=button], .chip, .seg *")].find((b) => /golden\s*hour/i.test(b.textContent ?? ""));
  if (btn) { btn.click(); return "clicked " + btn.textContent.trim(); }
  const r = await a.tryCall?.("render.preset", { name: "Goldenhour" });
  a.emit?.("render"); return r ? "render.preset Goldenhour" : "render.preset failed";
}).catch((e) => String(e));
check("Golden hour preset applied", /clicked|render\.preset Goldenhour/.test(preset), preset);
const has3d = await page.locator(".workspace canvas").count().catch(() => 0);
check("3D view has a canvas", has3d > 0);
await wait(6000);
await shot("03-cedar-3d-golden-hour");
await finish(app, 0);
