// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Render match: renders Cedar House from Front, Corner and Aerial with every lighting preset and compares the mean colour
// of each material region (sky, lawn, paving, cedar, limestone, glass; regions.py) with the Mac renders (build/renders).
// Writes the renders, side-by-side comparisons (Mac | Windows, regions outlined) and match.json to
// windows/test-results/render-match/<tag>/.
//   node windows/test/view3d/render-match.mjs [--tag after] [--size 960x540] [--ss 2] [--only front-night] [--full]
//   node windows/test/view3d/render-match.mjs --compare-only --tag before      (re-run the statistics only)
//   node windows/test/view3d/render-match.mjs --tag k --size 480x270 --ss 1 --statics '{"SUN_SCALE":0.9}'   (calibration)
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { openHarness, repo, here, windows, arg } from "./common.mjs";

const tag = arg("--tag", "current");
const out = path.join(windows, "test-results/render-match", tag);
fs.mkdirSync(out, { recursive: true });
const [W, H] = arg("--size", "960x540").split("x").map(Number);
const ss = Number(arg("--ss", "2"));
const only = arg("--only", "");
const statics = JSON.parse(arg("--statics", "{}"));
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-");
if (!process.argv.includes("--compare-only")) {
  const full = process.argv.includes("--full");
  const { page, close } = await openHarness(full ? "?meshes=/build/engine-fixtures/view3d-meshes-lod0.json&bin=/build/engine-fixtures/view3d-meshes-lod0.bin" : "");
  for (const cam of ["Front", "Corner", "Aerial"]) {
    for (const preset of ["Daylight", "Golden hour", "Overcast", "Night"]) {
      const name = `cedar-house-${slug(cam)}-${slug(preset)}`;
      if (only && !only.split(",").some((o) => name.includes(o))) continue;
      const r = await page.evaluate(([p, c, w, h, s, k]) => {
        const R = window.harness.view.renderer.constructor;
        for (const [n, x] of Object.entries(k)) R[n] = x;
        return window.harness.render(p, c, w, h, s);
      }, [preset, cam, W, H, ss, statics]);
      fs.writeFileSync(path.join(out, `${name}.png`), Buffer.from(r.png, "base64"));
      console.log(`${name}: ${Math.round(r.ms)} ms`);
    }
  }
  await close();
}
process.stdout.write(execFileSync("python3", ["-W", "ignore", path.join(here, "render-match.py"), path.join(repo, "build/renders"), out]).toString());
