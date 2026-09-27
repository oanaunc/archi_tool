// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Interactive checks of the 3D view in Chromium: visual styles, overlay bar, view cube, orbit / pan / zoom, picking,
// section box, walk mode, render to PNG. Screenshots go to windows/test-results/3d/ui-*.png; exits non-zero when a
// check fails.   node windows/test/view3d/ui.mjs
import fs from "node:fs";
import path from "node:path";
import { openHarness, results as out } from "./common.mjs";
const { page, close } = await openHarness("?preset=Goldenhour", { width: 1100, height: 640 });
const results = [];
const check = (name, ok, info = "") => { results.push({ name, ok, info }); console.log(`${ok ? "PASS" : "FAIL"} ${name} ${info}`); };
const shot = async (name) => { await page.waitForFunction(() => !window.harness.view.isAnimating(), null, { timeout: 120000, polling: 250 }); await page.evaluate(() => window.harness.frame()); await page.screenshot({ path: path.join(out, `ui-${name}.png`), timeout: 120000 }); };
const settle = () => page.waitForFunction(() => !window.harness.view.isAnimating(), null, { timeout: 120000, polling: 250 });
const cam = async () => { await settle(); return page.evaluate(() => window.harness.camera()); };
const dist = (c) => Math.hypot(c.eye[0] - c.target[0], c.eye[1] - c.target[1], c.eye[2] - c.target[2]);

await page.evaluate(() => window.harness.applyCamera("Corner"));
const ms = await page.evaluate(() => window.harness.frame());
check("realistic frame", ms > 0, `${Math.round(ms)} ms per frame (SwiftShader)`);
await shot("realistic-corner");

for (const s of ["Shaded", "Shaded with Edges", "Wireframe", "Hidden Line", "Conceptual", "X-Ray", "Sketchy"]) {
  await page.evaluate((st) => { window.harness.view.setStyle(st); }, s);
  await shot("style-" + s.toLowerCase().replace(/[^a-z]+/g, "-"));
}
await page.evaluate(() => window.harness.view.setStyle("Shaded with Edges"));

// Orbit: drag with the left button.
let c0 = await cam();
await page.mouse.move(500, 380); await page.mouse.down(); await page.mouse.move(600, 360, { steps: 5 }); await page.waitForTimeout(150); await page.mouse.up();
let c1 = await cam();
const yaw = (c) => Math.atan2(c.eye[1] - c.target[1], c.eye[0] - c.target[0]);
const dyaw = (a, b) => { let d = yaw(b) - yaw(a); while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; };
check("orbit (drag)", Math.abs(Math.abs(dyaw(c0, c1)) - 1.0) < 0.05 && Math.abs(dist(c1) - dist(c0)) < 0.01 * dist(c0), `Δyaw=${dyaw(c0, c1).toFixed(3)} rad for 100 px (Mac: 0.01 rad/pt)`);
// Pan: right-drag keeps the direction, moves the target.
c0 = await cam();
await page.mouse.move(500, 380); await page.mouse.down({ button: "right" }); await page.mouse.move(420, 380, { steps: 4 }); await page.mouse.up({ button: "right" });
c1 = await cam();
const moved = Math.hypot(c1.target[0] - c0.target[0], c1.target[1] - c0.target[1], c1.target[2] - c0.target[2]);
check("pan (right-drag)", moved > 0.5 && Math.abs(dist(c1) - dist(c0)) < 1e-3, `target moved ${moved.toFixed(2)} m`);
// Zoom: wheel dollies towards the target.
c0 = await cam();
await page.mouse.move(500, 380); await page.mouse.wheel(0, -400);
await page.waitForTimeout(100);
c1 = await cam();
check("zoom (wheel)", dist(c1) < dist(c0) * 0.9, `distance ${dist(c0).toFixed(1)} → ${dist(c1).toFixed(1)} m`);
// Standard view from the overlay: Top.
await page.click(".v3d-pill[title='Top']");
c1 = await cam();
check("Top view button", c1.eye[2] - c1.target[2] > 0.99 * dist(c1), "");
await shot("top");
// View cube: click the FRONT face → looking north from the south.
await page.evaluate(() => window.harness.view.setView("Iso", false));
await page.evaluate(() => window.harness.frame());
const box = await page.locator(".v3d-cube").boundingBox();
// Find a point on the FRONT face by scanning the cube for a hit whose direction is (0,−1,0).
const hit = await page.evaluate(() => { const v = window.harness.view; const cube = v.cube ?? v["cube"]; for (let y = 10; y < 90; y += 4) for (let x = 10; x < 90; x += 4) { const d = cube.directionAt(x, y); if (d && d[0] === 0 && d[1] === -1 && d[2] === 0) return [x, y]; } return null; });
if (hit) { await page.mouse.click(box.x + hit[0], box.y + hit[1]); }
c1 = await cam();
check("view cube FRONT", !!hit && (c1.target[1] - c1.eye[1]) > 0.95 * dist(c1), hit ? `clicked ${hit}` : "no FRONT face found");
await shot("viewcube-front");
// Picking: click the middle of the view (a wall) → selection.
await page.evaluate(() => window.harness.applyCamera("Front"));
await page.mouse.click(420, 250);
const sel = await page.evaluate(() => [...window.harness.view["selection"]]);
check("pick (click)", sel.length === 1, `selected ${sel.join(",")}`);
await shot("selection");
// Section box
await page.click(".v3d-pill[title='Section box']");
await page.evaluate(() => { const v = window.harness.view; const b = v.getSectionBox(); b.max[2] = 2600; v.setSectionBox(b); });
await page.evaluate(() => window.harness.applyCamera("Aerial"));
await shot("section-box");
check("section box", !!(await page.evaluate(() => window.harness.view.getSectionBox()?.on)), "");
await page.click(".v3d-pill[title='Section box']");
await page.evaluate(() => window.harness.view.setSectionBox(null));
// Walk mode: W moves forward, Esc leaves.
await page.evaluate(() => window.harness.applyCamera("Front"));
await page.click(".v3d-pill[title='Walk mode (WASD)']");
c0 = await cam();
await page.keyboard.down("w"); await page.waitForTimeout(1500); await page.keyboard.up("w");
c1 = await cam();
const step = Math.hypot(c1.eye[0] - c0.eye[0], c1.eye[1] - c0.eye[1]);
check("walk (W)", step > 0.3 && Math.abs(c1.eye[2] - 1.6) < 0.7, `moved ${step.toFixed(2)} m, eye z ${c1.eye[2].toFixed(2)} m`);
await shot("walk");
await page.keyboard.press("Escape");
check("walk exit (Esc)", !(await page.evaluate(() => window.harness.view.navigation)), "");
// Render to file from the view (PNG blob).
const png = await page.evaluate(async () => { const b = await window.harness.view.renderToPNG({ width: 320, height: 180, supersample: 2, camera: "Corner", preset: "Night" }); return b.size; });
check("renderToPNG", png > 10000, `${png} bytes`);
fs.writeFileSync(path.join(out, "ui-results.json"), JSON.stringify(results, null, 1));
await close();
process.exit(results.every((r) => r.ok) ? 0 : 1);
