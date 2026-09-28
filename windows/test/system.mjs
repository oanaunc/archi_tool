// APPSELFTEST, HELPWINDOW (offline help browser), VRVIEW, SPACEMOUSE and SPELL with the Windows spell checker
// (src/renderer/system/, Host/EngineSystemCommands.swift). Renderer as a web page + fixture engine. Exits 1 on a failure.
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
let fails = 0;
const check = (name, ok, info = "") => { if (!ok) fails++; console.log(`${ok ? "PASS" : "FAIL"}  ${name}${info ? "  — " + info : ""}`); };
const run = async (line) => { await A((l) => window.archiApp.runCommand(l), line); await wait(250); };
const logTail = (n = 12) => A((n) => window.archiApp.log.slice(-n), n);
const shadowText = () => A(() => document.querySelector('[data-window="help-browser"] .help-browser')?.shadowRoot?.textContent ?? "");

// ---- menus: the four commands are enabled ----
const disabled = await A(() => {
  const out = [];
  for (const n of ["APPSELFTEST", "HELPWINDOW", "VRVIEW", "SPACEMOUSE"]) if (!window.archiApp.has(n)) out.push(n);
  return out;
});
check("APPSELFTEST, HELPWINDOW, VRVIEW, SPACEMOUSE are commands", disabled.length === 0, disabled.join(","));

// ---- HELPWINDOW ----
await run("HELPWINDOW");
check("HELPWINDOW opens the help browser", await A(() => !!document.querySelector('[data-window="help-browser"]')));
check("window title", (await A(() => document.querySelector('[data-window="help-browser"] .twin-title')?.textContent)) === "Oanarina Archi Tool Help");
let t = await shadowText();
check("index lists the commands", /Oanarina Archi Tool help/.test(t) && /\d+ commands\./.test(t), t.slice(0, 120));
const rows0 = await A(() => document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.querySelectorAll("tr.c").length);
await A(() => { const q = document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.getElementById("q"); q.value = "presspull"; q.dispatchEvent(new Event("input")); });
const rows1 = await A(() => [...document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.querySelectorAll("tr.c")].filter((r) => r.style.display !== "none").length);
check("filter narrows the index", rows0 > 500 && rows1 >= 1 && rows1 < 5, `${rows0} → ${rows1}`);
await A(() => document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.querySelector('a[href="archi-help:cmd/LINE"]').click()); await wait(150);
t = await shadowText();
check("command page: aliases, category, where, undo, Run", /LINE/.test(t) && /Aliases/.test(t) && /Where/.test(t) && /Home ▸ Draw|Draw/.test(t) && /Run LINE/.test(t), t.slice(0, 200));
await A(() => document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.querySelector('a.run').click()); await wait(300);
const p1 = await A(() => window.archiApp.prompt);
check("Run link runs the command", p1.active && /LINE/i.test(p1.command ?? p1.message), JSON.stringify(p1).slice(0, 100));
await A(() => window.archiApp.cancel()); await wait(150);
await run("DOCS tutorials"); t = await shadowText();
check("DOCS tutorials", /Tutorials and sample project/.test(t) && /Your first floor plan/.test(t));
await run("MANUAL shortcuts"); t = await shadowText();
check("keyboard and mouse page", /Function keys/.test(t) && /F12/.test(t) && /Alt-drag/.test(t));
await run("HELPBROWSER scripting"); t = await shadowText();
check("scripting page with the archi API", /archi\.wall\(x1, y1, x2, y2, opts\)/.test(t) && /Ctrl\+Alt\+J/.test(t));
await A(() => document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.querySelector('a[href="archi-help:guide"]').click()); await wait(300);
t = await shadowText();
const guide = await A(() => { const s = document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot; return { ids: s.querySelectorAll("[id]").length, tables: s.querySelectorAll("table").length, cmdline: !!s.getElementById("the-command-line"), draw: !!s.getElementById("draw") }; });
check("user guide rendered offline with anchors", /User Guide/.test(t) && guide.tables > 20 && guide.cmdline && guide.draw, JSON.stringify(guide));
await A(() => document.querySelector('[data-window="help-browser"] .help-browser').shadowRoot.querySelector('a[href="#selecting-objects"]')?.click()); await wait(200);
const scrolled = await A(() => document.querySelector('[data-window="help-browser"] .help-browser').scrollTop);
check("contents link scrolls within the guide", scrolled > 200, String(scrolled));
await run("HELPWINDOW circle"); t = await shadowText();
check("HELPWINDOW <command> opens its page", /CIRCLE/.test(t) && /User guide: /.test(t), t.slice(0, 80));
await run("HELPWINDOW NOPE_NOT_A_CMD");
check("unknown topic refused", (await logTail(3)).some((l) => l.includes('Unknown command "NOPE_NOT_A_CMD".')));
check("no external page opened by the help browser", opened.length === 0, opened.join(","));
await A(() => document.querySelector('[data-window="help-browser"] .twin-close').click());

// ---- APPSELFTEST ----
await run("APPSELFTEST"); await wait(300);
let log = await logTail(12);
const summary = log.find((l) => /check\(s\) passed, \d+ failed\./.test(l)) ?? "";
check("APPSELFTEST prints the Mac report", /^Command coverage: \d+ in ribbon\/menus, \d+ in palettes \(system variables\), \d+ without UI entry\.$/.test(log.find((l) => l.startsWith("Command coverage")) ?? "") && !!summary, log.join(" | "));
const failsST = log.filter((l) => l.startsWith("FAIL: "));
check("self-test checks pass on the fixture engine", /, 0 failed\./.test(summary), failsST.join(" | ").slice(0, 600));
check("no Mac command pending on Windows (FILEPREVIEW is built)", !log.some((l) => /Not on Windows yet/.test(l)), log.find((l) => /Not on Windows yet/.test(l)) ?? "");

// ---- command search uses the Mac ranking ----
const ranked = await A(() => { document.dispatchEvent(new CustomEvent("archi:commandSearch")); const inp = document.querySelector(".overlay .palette input"); inp.value = "prspl"; inp.dispatchEvent(new Event("input")); const r = [...document.querySelectorAll(".overlay .rows .row .n")].map((e) => e.textContent); document.querySelector(".overlay")?.remove(); return r; });
check("Ctrl+K search: prspl → PRESSPULL first", ranked[0] === "PRESSPULL", ranked.slice(0, 4).join(","));

// ---- VRVIEW ----
await run("VRVIEW Save");
log = await logTail(3);
check("VRVIEW Save writes the page (message)", log.some((l) => /^VR page: \d+ triangles → .*-VR\.html\. Open it in the headset's browser/.test(l)), log.join(" | "));
opened.length = 0;
await run("VRVIEW Open"); await wait(300);
log = await logTail(4);
check("VRVIEW Open without a headset: fallback message", log.some((l) => /^No VR headset is available to this window/.test(l)), log.join(" | "));

// ---- SPACEMOUSE ----
await run("SPACEMOUSE Fly");
log = await logTail(2);
check("SPACEMOUSE Fly: status line", /^SpaceMouse (on|off), Fly mode, sensitivity 1; devices: none connected\.$/.test(log.at(-1)), log.at(-1));
check("shell took the mode", (await A(() => window.archiSpaceMouse.config.mode)) === "Fly");
await run("SPACEMOUSE Sensitivity 2.5");
check("sensitivity", (await A(() => window.archiSpaceMouse.config.sensitivity)) === 2.5 && /sensitivity 2\.5;/.test((await logTail(1))[0]));
await run("SPACEMOUSE Object");
// Axes drive the 3D camera: simulate a HID report in 3D mode.
await A(() => window.archiApp.setUI("mode", "3D")); await wait(1500);
const cam = await A(async () => {
  const sm = window.archiSpaceMouse, v = window.archiView3D;
  if (!v) return { err: "no 3D view" };
  const c0 = v.getCamera();
  sm.state.axes = [0, 0, 0, 0, 0, 300];
  const t0 = performance.now(); sm.tick(t0 - 50); sm.tick(t0 + 50); sm.tick(t0 + 100);
  sm.state.axes = [0, 0, 0, 0, 0, 0];
  const c1 = v.getCamera();
  const d = (c) => Math.hypot(c.eye[0] - c.target[0], c.eye[1] - c.target[1], c.eye[2] - c.target[2]);
  return { moved: Math.hypot(c1.eye[0] - c0.eye[0], c1.eye[1] - c0.eye[1]), d0: d(c0), d1: d(c1) };
});
check("SpaceMouse spin orbits the 3D camera at constant distance", cam.moved > 0.01 && Math.abs(cam.d0 - cam.d1) < 1e-6 * cam.d0 + 1e-6, JSON.stringify(cam));
await A(() => window.archiApp.setUI("mode", "2D")); await wait(300);
await run("SPACEMOUSE Off");
check("SPACEMOUSE Off", (await A(() => window.archiSpaceMouse.enabled)) === false && /^SpaceMouse off/.test((await logTail(1))[0]));
await run("SPACEMOUSE On");

// ---- SPELL primes the engine with the spell checker's verdicts ----
await run("SPELL"); await wait(200); await A(() => window.archiApp.cancel()); await wait(100);
const seq = await A(() => (window.__archiSystemCalls ?? []).map((c) => c.method + (c.method === "command.run" ? ":" + c.params.line : "")));
check("SPELL: the verdicts reach the engine before the command", seq.at(-2) === "spell.verdicts" && seq.at(-1) === "command.run:SPELL", seq.join(" | "));
const verdicts = await A(async () => {
  const sent = [];
  const words = { words: [{ entity: 12, word: "Kitchn", field: "text" }, { entity: 13, word: "Bedroom", field: "text" }, { entity: 13, word: "wiht", field: "text" }], custom: [] };
  const n = await window.archiSpellPrime(async (m, p) => { sent.push([m, p]); return m === "spell.words" ? words : { misspelled: 0 }; });
  return { n, sent: JSON.stringify(sent) };
});
check("verdicts carry the misspelled words with suggestions", verdicts.n === 2 && /"spell.words",\{"all":true\}/.test(verdicts.sent) && /"Kitchn":\["Kitchen"\]/.test(verdicts.sent) && /"wiht":\["with","wit"\]/.test(verdicts.sent) && !/"Bedroom":/.test(verdicts.sent), verdicts.sent);
check("no page errors", errors.length === 0, errors.join(" | "));
await browser.close(); server.close();
console.log(fails ? `${fails} check(s) failed` : "all checks passed");
process.exit(fails ? 1 : 0);
