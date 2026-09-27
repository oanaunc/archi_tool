// 2D canvas test (CanvasView.swift / SheetView.swift parity): the renderer as a web page with the fixture engine and the
// canvas simulation of canvas/fake-canvas.ts. Covers hover, window / crossing / lasso selection, selection cycling,
// grips (drag, click-click, Space / Enter mode cycling, typed values, Copy, the multi-functional grip menu), object snap
// tracking and the tracking readout, dynamic-input fields with Tab, the shortcut menu, snap overrides, the marking menu,
// double-click text editing, temporary dimensions, arrow-key nudging, tool-palette click-to-place with Space rotation,
// drag-and-drop of palette items and files, twisted views, wheel / touchpad navigation and sheet viewports (select,
// move, lock). Screenshots go to test-results/canvas-*.png.
// Usage: node build.mjs --web && node test/canvas.mjs   (PLAYWRIGHT_BROWSERS_PATH must point at an installed Chromium)
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
const check = (name, ok, detail = "") => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error" && !m.text().includes("404")) errors.push(m.text()); });
const shot = (name, opts = {}) => page.screenshot({ path: path.join(out, "canvas-" + name + ".png"), ...opts });
const wait = (ms) => page.waitForTimeout(ms);
const C = (fn, arg) => page.evaluate(fn, arg);
const history = async () => (await page.textContent(".cmd-history")) ?? "";
const undoLabel = () => C(() => window.archiApp.engine.call("panel.history").then((h) => h.undoLabel));
const selIds = () => C(() => window.archiApp.selection.ids.slice());
const menuTitles = () => page.$$eval(".menu .mi span:not(.ico):not(.sc)", (els) => els.map((e) => e.textContent));

await page.goto(base);
await page.waitForSelector("body.ready");
await page.click(".start .grid.s .card2 >> nth=0");
await wait(700);
const box = await page.locator(".workspace canvas.plan >> nth=1").boundingBox();
const at = (v) => [box.x + v[0], box.y + v[1]];
/** A visible stroke of the plan: its id and a point on it (canvas coordinates). */
const strokeTarget = (minLen = 40, skip = 0) => C(([minLen, skip]) => {
  const cv = window.archiCanvas; let n = 0;
  for (const e of cv.entries) {
    if (!e.id) continue;
    for (const it of e.items) {
      if (it.type !== "stroke" || it.points.length < 2) continue;
      const a = cv.toView(it.points[0]), b = cv.toView(it.points[1]);
      const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
      if (Math.hypot(b[0] - a[0], b[1] - a[1]) < minLen || mid[0] < 80 || mid[1] < 80 || mid[0] > cv.view.w - 80 || mid[1] > cv.view.h - 80) continue;
      if (n++ < skip) continue;
      return { id: e.id, a, b, mid };
    }
  }
  return null;
}, [minLen, skip]);

// ---- hover and click selection ----
await page.keyboard.press("Escape");
const t1 = await strokeTarget(60);
check("a stroke of the plan is on screen", !!t1);
await page.mouse.move(...at(t1.mid));
await wait(120);
check("hover highlight under the cursor", await C(() => !!window.archiCanvas.hover));
await shot("hover");
const hovered = await C(() => window.archiCanvas.hover?.id);
await page.mouse.click(...at(t1.mid));
await wait(250);
check("click selects the object under the cursor", (await selIds()).includes(String(hovered)) || (await selIds()).includes(t1.id), (await selIds()).join(","));
check("grips of the selection", (await C(() => window.archiCanvas.grips.length)) > 0);
await shot("selected-grips");

// ---- grip drag: stretch the first grip (one "Grip Edit" undo step) ----
const g0 = await C(() => { const cv = window.archiCanvas; const g = cv.grips[0]; return { g, v: cv.toView([g.x, g.y]) }; });
await page.mouse.move(...at(g0.v));
await wait(80);
check("hovered grip", await C(() => !!window.archiCanvas.hoverGrip));
await page.mouse.down();
await page.mouse.move(at(g0.v)[0] + 40, at(g0.v)[1] + 30, { steps: 6 });
await wait(150);
check("grip drag previews in the accent colour", (await C(() => window.archiCanvas.hot?.items.length ?? 0)) > 0);
await shot("grip-drag");
await page.mouse.up();
await wait(250);
check("grip drag commits one Grip Edit step", (await undoLabel()) === "Grip Edit", await undoLabel());
await C(() => window.archiApp.undo());
await wait(200);

// ---- click-click grip: Space / Enter cycle the grip modes, C copy, typed value ----
await C(() => window.archiApp.engine.call("select.set", { ids: [] }).then(() => window.archiApp.refresh(["selection"])));
await page.mouse.click(...at(t1.mid));
await wait(250);
const g1 = await C(() => { const cv = window.archiCanvas; const g = cv.grips[0]; return cv.toView([g.x, g.y]); });
await page.mouse.click(...at(g1));
await wait(120);
check("click on a grip makes it hot (not dragging)", (await C(() => window.archiCanvas.hotGripState?.dragging)) === false);
await page.keyboard.press(" ");
await wait(60);
check("Space cycles Stretch → Move", (await C(() => window.archiCanvas.hotGripState?.mode)) === "move");
await page.keyboard.press("Enter");
await wait(60);
check("Enter cycles Move → Rotate", (await C(() => window.archiCanvas.hotGripState?.mode)) === "rotate");
await page.mouse.move(at(g1)[0] + 120, at(g1)[1] - 60, { steps: 4 });
await wait(200);
await shot("grip-rotate-mode");
await page.keyboard.type("SC");
await page.keyboard.press("Enter");
await wait(60);
check("typed SC switches to Scale", (await C(() => window.archiCanvas.hotGripState?.mode)) === "scale");
await page.keyboard.type("MO");
await page.keyboard.press("Enter");
await page.keyboard.type("C");
await page.keyboard.press("Enter");
await wait(60);
check("typed C turns Copy on", (await C(() => window.archiCanvas.hotGripState?.copy)) === true);
const n0 = await C(() => window.archiApp.engine.raw.length);
await page.keyboard.type("500");
await page.keyboard.press("Enter");
await wait(250);
check("a typed distance in Move + Copy adds a copy", (await C(() => window.archiApp.engine.raw.length)) === n0 + 1, await undoLabel());
check("Copy keeps the grip hot", !!(await C(() => window.archiCanvas.hotGripState)));
await page.keyboard.press("Escape");
await wait(60);
check("Esc releases the hot grip", !(await C(() => window.archiCanvas.hotGripState)));
await C(() => window.archiApp.undo());
await wait(150);

// ---- multi-functional grip menu (right-click a hovered grip) ----
const poly = await C(() => { const cv = window.archiCanvas; for (const e of cv.entries) { if (!e.id) continue; const s = e.items.find((i) => i.type === "stroke" && i.points.length > 3); if (s) { const v = cv.toView(s.points[1]); if (v[0] > 60 && v[1] > 60 && v[0] < cv.view.w - 60 && v[1] < cv.view.h - 60) return { id: e.id, v }; } } return null; });
if (poly) {
  await C((id) => window.archiApp.engine.call("select.set", { ids: [Number(id)] }).then(() => window.archiApp.refresh(["selection"])), poly.id);
  await wait(200);
  const gv = await C((id) => { const cv = window.archiCanvas; const g = cv.grips.find((x) => String(x.id) === String(id) && x.index === 1) ?? cv.grips[0]; return cv.toView([g.x, g.y]); }, poly.id);
  await page.mouse.move(...at(gv));
  await wait(80);
  await page.mouse.click(...at(gv), { button: "right" });
  await wait(200);
  const items = await menuTitles();
  check("grip menu lists the grip options", items.join(",") === "Stretch,Add Vertex,Remove Vertex", items.join(","));
  await shot("grip-menu");
  await page.click('.menu .mi:has-text("Add Vertex")');
  await wait(100);
  check("grip menu option follows the cursor", (await C(() => window.archiCanvas.hotGripState?.action)) === "addVertex");
  await page.keyboard.press("Escape");
}
await C(() => window.archiApp.engine.call("select.set", { ids: [] }).then(() => window.archiApp.refresh(["selection"])));
await wait(100);

// ---- window (left→right, blue) and crossing (right→left, green dashed) selection ----
await page.mouse.move(box.x + 300, box.y + 200);
await page.mouse.down();
await page.mouse.move(box.x + 700, box.y + 520, { steps: 8 });
await shot("window-selection");
await page.mouse.up();
await wait(200);
const nWindow = (await selIds()).length;
await page.keyboard.press("Escape");
await wait(80);
await page.mouse.move(box.x + 700, box.y + 520);
await page.mouse.down();
await page.mouse.move(box.x + 300, box.y + 200, { steps: 8 });
await shot("crossing-selection");
await page.mouse.up();
await wait(200);
const nCross = (await selIds()).length;
check("crossing selects at least as much as window", nCross >= nWindow && nCross > 0, `${nWindow} / ${nCross}`);
await page.keyboard.press("Escape");

// ---- lasso: Alt+drag, clockwise = window, counter-clockwise = crossing ----
const loop = (cx, cy, r, ccw) => Array.from({ length: 25 }, (_, i) => { const a = (ccw ? -1 : 1) * (i / 24) * Math.PI * 2; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; });
await page.keyboard.down("Alt");
const lp = loop(box.x + 560, box.y + 380, 170, true);
await page.mouse.move(...lp[0]);
await page.mouse.down();
for (const p of lp.slice(1)) await page.mouse.move(p[0], p[1], { steps: 2 });
await shot("lasso-crossing");
await page.mouse.up();
await page.keyboard.up("Alt");
await wait(250);
const lassoLabel = await C(() => window.archiApp.selection.ids.length);
check("counter-clockwise lasso selects (crossing)", lassoLabel > 0, String(lassoLabel));
await page.keyboard.press("Escape");

// ---- shortcut menu (right-click when idle) ----
await page.mouse.move(box.x + 900, box.y + 120);
await page.mouse.click(box.x + 900, box.y + 120, { button: "right" });
await wait(250);
const idleMenu = await menuTitles();
check("shortcut menu (no selection) matches the Mac", idleMenu.join("|").startsWith("Repeat") && ["Recent Input", "Pan", "Zoom Window", "Zoom Extents", "Select All", "Quick Select…", "Quick Properties", "Properties"].every((t) => idleMenu.includes(t)), idleMenu.join("|"));
await shot("shortcut-menu");
await page.keyboard.press("Escape");
await page.mouse.click(...at(t1.mid));
await wait(200);
await page.mouse.click(box.x + 900, box.y + 120, { button: "right" });
await wait(250);
const selMenu = await menuTitles();
check("shortcut menu with a selection lists the edit commands", ["Move", "Copy Selection", "Rotate", "Scale", "Mirror", "Erase", "Isolate Objects", "Select Similar", "Deselect All"].every((t) => selMenu.includes(t)), selMenu.join("|"));
await page.keyboard.press("Escape");
await page.keyboard.press("Escape");

// ---- marking menu (right-drag) ----
await C(() => window.archiApp.engine.call("select.set", { ids: [] }).then(() => window.archiApp.refresh(["selection"])));
await page.mouse.move(box.x + 700, box.y + 420);
await page.mouse.down({ button: "right" });
await page.mouse.move(box.x + 700, box.y + 340, { steps: 5 });
await wait(120);
const radial = await page.$$eval(".radial-menu .rm-item span", (els) => els.map((e) => e.textContent));
check("marking menu: 8 drafting commands clockwise from the top", radial.join(",") === "Line,Polyline,Wall,Door,Dimension,Window,Rectangle,Circle", radial.join(","));
check("dragging up highlights Line", (await page.textContent(".radial-menu .rm-cmd")) === "LINE");
await shot("marking-menu");
await page.mouse.up({ button: "right" });
await wait(250);
check("releasing runs the command", (await C(() => window.archiApp.prompt.command)) === "LINE", await C(() => window.archiApp.prompt.message));

// ---- LINE: tracking readout, dynamic-input fields (Tab), snap overrides, right-click = Enter ----
const b0 = [box.x + 400, box.y + box.height * 0.8];
await page.mouse.click(...b0);
await wait(150);
await page.mouse.move(b0[0] + 240, b0[1] + 3, { steps: 4 });
await wait(200);
check("object snap tracking along the base horizontal", await C(() => window.archiCanvas.snap?.kind === "extension" && !!window.archiCanvas.tracking?.lines?.length));
await shot("tracking-readout");
await page.mouse.move(b0[0] + 200, b0[1] - 120, { steps: 3 });
await wait(150);
check("dynamic input: length / angle fields at the cursor", await C(() => typeof window.archiCanvas.dyn?.length === "number"));
await page.keyboard.down("Shift");
await page.mouse.click(b0[0] + 200, b0[1] - 120, { button: "right" });
await page.keyboard.up("Shift");
await wait(200);
const snaps = await menuTitles();
check("Shift+right-click: snap override menu", snaps.slice(0, 4).join(",") === "Temporary Track Point,From,Endpoint,Midpoint", snaps.join(","));
await page.keyboard.press("Escape");
await page.mouse.move(b0[0] + 205, b0[1] - 118);
await wait(150);
const nBefore = await C(() => window.archiApp.engine.raw.length);
await page.keyboard.type("1500");
await page.keyboard.press("Tab");
await page.keyboard.type("30");
await wait(100);
await shot("dynamic-input-fields");
await page.keyboard.press("Enter");
await wait(250);
check("Length Tab Angle Enter draws @1500<30", (await C(() => window.archiApp.engine.raw.length)) === nBefore + 1, (await history()).split("\n").slice(-3).join(" / "));
const last = await C(() => { const r = window.archiApp.engine.raw.at(-1); const p = r.items[0].points; return Math.hypot(p[1][0] - p[0][0], p[1][1] - p[0][1]); });
check("the new segment is 1500 long", Math.abs(last - 1500) < 1e-6, String(last));
await page.mouse.click(box.x + 800, box.y + 500, { button: "right" });
await wait(200);
check("right-click during a command = Enter (ends LINE)", !(await C(() => window.archiApp.prompt.active)));

// ---- selection cycling (two overlapping lines) ----
await C(() => window.archiApp.runCommand("LINE -40000,-40000 -30000,-40000 "));
await wait(100);
await C(() => window.archiApp.runCommand("LINE -40000,-40000 -30000,-40000 "));
await wait(100);
await C(() => window.archiCanvas.zoomTo([-41000, -41000, -29000, -39000]));
await wait(250);
await page.keyboard.press("Escape");
const ov = await C(() => window.archiCanvas.toView([-35000, -40000]));
await page.mouse.click(...at(ov));
await wait(300);
const firstSel = (await selIds()).join(",");
await page.mouse.click(...at(ov));
await wait(300);
const secondSel = (await selIds()).join(",");
check("clicking again cycles to the overlapping object", firstSel && secondSel && firstSel !== secondSel, `${firstSel} → ${secondSel}`);
check("cycling hint in the status bar", ((await page.textContent(".statusbar")) ?? "").includes("of 2"), await page.textContent(".statusbar"));

// ---- arrow keys nudge ----
await page.locator(".workspace canvas.plan >> nth=1").focus();
await page.keyboard.press("ArrowRight");
await wait(200);
check("arrow key nudges the selection (Nudge)", (await undoLabel()) === "Nudge", await undoLabel());
await page.keyboard.press("Escape");
await C(() => window.archiCanvas.zoomExtents());
await wait(250);

// ---- double-click text: in-place editor ----
const txt = await C(() => { const cv = window.archiCanvas; for (const e of cv.entries) { if (!e.id) continue; const t = e.items.find((i) => i.type === "text" && i.content && i.content.length > 2); if (t) return { id: e.id, p: t.position, h: t.height, content: t.content }; } return null; });
if (txt) {
  await C((t) => window.archiCanvas.zoomTo([t.p[0] - 60 * t.h, t.p[1] - 30 * t.h, t.p[0] + 60 * t.h, t.p[1] + 30 * t.h]), txt);
  await wait(300);
  const tv = await C((t) => window.archiCanvas.toView([t.p[0] + t.h * 0.3, t.p[1] + t.h * 0.4]), txt);
  await page.mouse.dblclick(...at(tv));
  await wait(400);
  check("double-click on text opens the in-place editor", await page.isVisible(".text-editor"));
  await shot("text-editor");
  if (await page.isVisible(".text-editor")) {
    await page.fill(".text-editor textarea", "Living Room");
    await page.keyboard.press("Enter");
    await wait(300);
    check("Enter commits the edit (Edit Text)", (await undoLabel()) === "Edit Text", await undoLabel());
    check("editor closed", !(await page.isVisible(".text-editor")));
  }
} else check("a text in the drawing for the double-click test", false);
await C(() => window.archiCanvas.zoomExtents());
await wait(250);

// ---- temporary dimensions of the selection ----
await C(async () => {
  const app = window.archiApp;
  for (const e of window.archiCanvas.entries.filter((x) => x.id).slice(0, 400)) {
    await app.engine.call("select.set", { ids: [Number(e.id)] });
    const d = await app.engine.call("tempdims.get");
    if (d.length && d[0].value > 500) break;
  }
  await app.refresh(["selection"]);
});
await wait(400);
const tds = await C(() => window.archiCanvas.tempDimBoxes.length);
check("temporary dimension shown for the selected object", tds > 0, String(tds));
await shot("temporary-dimension");
if (tds) {
  const tb = await C(() => { const b = window.archiCanvas.tempDimBoxes[0]; return { x: b.box[0] + b.box[2] / 2, y: b.box[1] + b.box[3] / 2, v: b.td.value }; });
  await page.mouse.click(...at([tb.x, tb.y]));
  await wait(100);
  check("clicking the value opens its field", await page.isVisible(".tempdim-edit"));
  await page.fill(".tempdim-edit", String(Math.round(tb.v + 250)));
  await page.keyboard.press("Enter");
  await wait(300);
  check("typing a value moves the object (Temporary Dimension)", (await undoLabel()) === "Temporary Dimension", await undoLabel());
}
await page.keyboard.press("Escape");
await page.keyboard.press("Escape");

// ---- tool palette: components, click-to-place with Space rotation, My Tools ----
await C(() => window.archiApp.action("@panel:Tools"));
await wait(300);
const tabsTP = await page.$$eval(".tool-palette .tp-tab", (els) => els.map((e) => e.textContent));
check("tool palette tabs", tabsTP.join(",") === "Draw,Modify,Annotate,Build,Blocks,Components,My Tools", tabsTP.join(","));
await shot("tool-palette-draw", { clip: await page.locator(".panels").boundingBox() ?? undefined });
await page.click('.tool-palette .tp-tab:text-is("Components")');
await wait(300);
check("component tiles with thumbnails", (await page.locator(".tool-palette .tp-shape canvas").count()) > 3);
await page.click('.tool-palette .tp-shape:has-text("Sofa")');
await wait(100);
check("clicking a component starts placement", (await C(() => window.archiCanvas.placementState?.item)) === "archi-component:sofa");
await page.mouse.move(box.x + 600, box.y + 400, { steps: 3 });
await page.locator(".workspace canvas.plan >> nth=1").focus();
await page.keyboard.press(" ");
await wait(200);
check("Space rotates the placement 90°", (await C(() => window.archiCanvas.placementState?.turns)) === 1);
await page.mouse.move(box.x + 610, box.y + 405);
await wait(150);
await shot("placement-preview");
const nP = await C(() => window.archiApp.engine.raw.length);
await page.mouse.click(box.x + 610, box.y + 405);
await wait(300);
check("click places the component (Place Sofa)", (await C(() => window.archiApp.engine.raw.length)) === nP + 1 && (await undoLabel()) === "Place Sofa", await undoLabel());
check("placement ends after a plain click", !(await C(() => window.archiCanvas.placementState)));
await page.click('.tool-palette .tp-tab:text-is("My Tools")');
await wait(150);
const my = await page.$$eval(".tool-palette .tp-tile .tp-title", (els) => els.map((e) => e.textContent));
check("My Tools defaults", my.join(",") === "Wall,Door,Window,Room,Dimlinear,Hatch", my.join(","));
await shot("tool-palette-mytools", { clip: await page.locator(".panels").boundingBox() ?? undefined });
await page.click('.tool-palette .tp-tab:text-is("Draw")');

// ---- drag-and-drop: a palette item and a drawing file ----
const nD = await C(() => window.archiApp.engine.raw.length);
await C(({ x, y }) => {
  const o = document.querySelectorAll(".workspace canvas.plan")[1];
  const dt = new DataTransfer(); dt.setData("text/plain", "archi-component:table");
  o.dispatchEvent(new DragEvent("dragover", { dataTransfer: dt, clientX: x, clientY: y, bubbles: true, cancelable: true }));
  o.dispatchEvent(new DragEvent("drop", { dataTransfer: dt, clientX: x, clientY: y, bubbles: true, cancelable: true }));
}, { x: box.x + 500, y: box.y + 300 });
await wait(300);
check("dropping a palette component places it", (await C(() => window.archiApp.engine.raw.length)) === nD + 1);
await C(({ x, y }) => {
  const o = document.querySelectorAll(".workspace canvas.plan")[1];
  const dt = new DataTransfer(); dt.items.add(new File(["{}"], "Cedar House.archi"));
  o.dispatchEvent(new DragEvent("drop", { dataTransfer: dt, clientX: x, clientY: y, bubbles: true, cancelable: true }));
}, { x: box.x + 500, y: box.y + 300 });
await wait(500);
check("dropping a drawing file opens it", (await history()).includes("Opened"), (await history()).split("\n").slice(-2).join(" / "));

// ---- navigation: wheel zooms about the cursor, Ctrl+wheel (pinch) zooms, Shift+wheel / touchpad pans ----
await C(() => window.archiCanvas.zoomExtents());
await wait(150);
const s0 = await C(() => window.archiCanvas.view.scale);
await page.mouse.move(box.x + 700, box.y + 400);
await C(({ x, y }) => { const o = document.querySelectorAll(".workspace canvas.plan")[1]; o.dispatchEvent(new WheelEvent("wheel", { deltaY: -100, deltaMode: 0, wheelDeltaY: 120, clientX: x, clientY: y, bubbles: true, cancelable: true })); }, { x: box.x + 700, y: box.y + 400 });
const s1 = await C(() => window.archiCanvas.view.scale);
check("mouse wheel up zooms in by 1.2", Math.abs(s1 / s0 - 1.2) < 1e-6, `${s0} → ${s1}`);
await C(({ x, y }) => { const o = document.querySelectorAll(".workspace canvas.plan")[1]; o.dispatchEvent(new WheelEvent("wheel", { deltaY: 10, deltaMode: 0, ctrlKey: true, clientX: x, clientY: y, bubbles: true, cancelable: true })); }, { x: box.x + 700, y: box.y + 400 });
const s2 = await C(() => window.archiCanvas.view.scale);
check("touchpad pinch (Ctrl+wheel) zooms out", s2 < s1, `${s1} → ${s2}`);
const c0 = await C(() => [window.archiCanvas.view.cx, window.archiCanvas.view.cy]);
await C(({ x, y }) => { const o = document.querySelectorAll(".workspace canvas.plan")[1]; o.dispatchEvent(new WheelEvent("wheel", { deltaX: 30, deltaY: 12, deltaMode: 0, clientX: x, clientY: y, bubbles: true, cancelable: true })); }, { x: box.x + 700, y: box.y + 400 });
const c1 = await C(() => [window.archiCanvas.view.cx, window.archiCanvas.view.cy]);
check("touchpad two-finger scroll pans", c1[0] > c0[0] && c1[1] < c0[1], `${c0} → ${c1}`);

// ---- twisted view (VIEWTWIST) ----
await C(() => window.archiApp.engine.call("sysvar.set", { name: "VIEWTWIST", value: "30" }).then(() => window.archiCanvas.loadState()));
await wait(200);
await C(() => window.archiCanvas.zoomExtents());
await wait(250);
const rt = await C(() => { const cv = window.archiCanvas; const v = cv.toView([1234, 5678]); return cv.toWorld(v[0], v[1]); });
check("twisted view: toView / toWorld round trip", Math.abs(rt[0] - 1234) < 1e-6 && Math.abs(rt[1] - 5678) < 1e-6, rt.join(","));
check("view twist is 30°", Math.abs((await C(() => window.archiCanvas.view.twist)) - Math.PI / 6) < 1e-9);
await page.mouse.move(box.x + 720, box.y + 430);
await shot("twisted-view");
await C(() => window.archiApp.engine.call("sysvar.set", { name: "VIEWTWIST", value: "0" }).then(() => window.archiCanvas.loadState()));
await wait(150);

// ---- sheets: select, lock, move viewports ----
await page.click('.layout-tabs .lt:has-text("Sheet 1")').catch(() => {});
await wait(800);
const vps = await C(() => window.archiCanvas.viewports.map((v) => ({ index: v.index, rect: v.rect })));
check("sheet viewports listed", vps.length > 0, JSON.stringify(vps));
if (vps.length) {
  const vc = await C((r) => window.archiCanvas.toView([(r[0] + r[2]) / 2, (r[1] + r[3]) / 2]), vps[0].rect);
  await page.mouse.click(...at(vc));
  await wait(150);
  check("click selects the viewport", (await C(() => window.archiCanvas.selectedViewport)) === vps[0].index);
  await shot("sheet-selected-viewport");
  await page.mouse.click(...at(vc), { button: "right" });
  await wait(200);
  const vmenu = await menuTitles();
  check("viewport menu (scales, lock, maximise, remove)", ["Scale 1:50", "Scale 1:100", "Lock Viewport", "Maximise (VPMAX)", "Remove"].every((t) => vmenu.includes(t)), vmenu.join("|"));
  await page.click('.menu .mi:has-text("Lock Viewport")');
  await wait(300);
  check("lock shows the badge state", await C(() => window.archiCanvas.viewports[0].locked === true));
  await shot("sheet-locked-viewport");
  const r0 = await C(() => window.archiCanvas.viewports[0].rect.slice());
  await page.mouse.move(...at(vc)); await page.mouse.down(); await page.mouse.move(at(vc)[0] + 60, at(vc)[1] + 30, { steps: 5 }); await page.mouse.up();
  await wait(300);
  check("a locked viewport pans instead of moving", JSON.stringify(await C(() => window.archiCanvas.viewports[0].rect)) === JSON.stringify(r0));
  await page.mouse.click(...at(vc), { button: "right" });
  await wait(200);
  await page.click('.menu .mi:has-text("Unlock Viewport")');
  await wait(300);
  const vc2 = await C((r) => window.archiCanvas.toView([(r[0] + r[2]) / 2, (r[1] + r[3]) / 2]), (await C(() => window.archiCanvas.viewports[0].rect)));
  await page.mouse.move(...at(vc2)); await page.mouse.down(); await page.mouse.move(at(vc2)[0] + 60, at(vc2)[1] + 30, { steps: 5 }); await page.mouse.up();
  await wait(400);
  const r1 = await C(() => window.archiCanvas.viewports[0].rect.slice());
  check("dragging an unlocked viewport moves it (Move Viewport)", Math.abs(r1[0] - r0[0]) > 1 && (await undoLabel()) === "Move Viewport", `${r0} → ${r1}`);
  await shot("sheet-moved-viewport");
}

check("no page errors", errors.length === 0, errors.slice(0, 3).join(" | "));
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} checks passed`);
fs.writeFileSync(path.join(out, "canvas-results.json"), JSON.stringify(results, null, 1));
await browser.close();
server.close();
process.exit(failed.length ? 1 : 0);
