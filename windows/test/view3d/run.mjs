// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Renders the Cedar House fixture (build/engine-fixtures/meshes-all-lod2.json) with every lighting preset from the
// saved cameras and writes PNGs plus side-by-side comparisons with the Mac renders (build/renders) to test-results/3d.
//   node windows/test/view3d/run.mjs [--size 1200x675] [--ss 2] [--only front-daylight,corner-night]
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { openHarness, results, repo, here, arg } from "./common.mjs";

const [W, H] = arg("--size", "1200x675").split("x").map(Number);
const ss = Number(arg("--ss", "2"));
const only = arg("--only", "");
const jobs = [["Front", "Daylight"], ["Corner", "Daylight"], ["Aerial", "Daylight"], ["Front", "Golden hour"], ["Corner", "Golden hour"], ["Aerial", "Golden hour"],
  ["Front", "Overcast"], ["Corner", "Overcast"], ["Front", "Night"], ["Corner", "Night"]];
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-");

const { page, close } = await openHarness();
const out = [];
for (const [cam, preset] of jobs) {
  const name = `cedar-house-${slug(cam)}-${slug(preset)}`;
  if (only && !only.split(",").some((o) => name.includes(o))) continue;
  const r = await page.evaluate(([p, c, w, h, s]) => window.harness.render(p, c, w, h, s), [preset, cam, W, H, ss]);
  fs.writeFileSync(path.join(results, `${name}.png`), Buffer.from(r.png, "base64"));
  console.log(`${name}: ${W}×${H}, ${ss}× supersampled, ${Math.round(r.ms)} ms`);
  out.push({ name, camera: cam, preset, ms: Math.round(r.ms) });
}
fs.writeFileSync(path.join(results, "renders.json"), JSON.stringify({ size: [W, H], supersample: ss, renders: out }, null, 1));
await close();
const mac = path.join(repo, "build/renders");
if (fs.existsSync(mac)) {
  try { process.stdout.write(execFileSync("python3", [path.join(here, "compare.py"), mac, results]).toString()); }
  catch (e) { console.log("comparison skipped:", e.message); }
}
