// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Night preset lamps and shadows (Renderer.LAMP_SUN_SHADOW, spot shadow maps) against the Mac render of Cedar House:
//  - the two entrance spots get shadow maps (SceneLights.node castsShadow on spots and IES lights);
//  - the moon's shadows darken the lamp light, so the bollards' shadows show inside their own light pools and the soffit
//    and entrance wall under the canopy come down to the Mac's brightness;
//  - pools and entrance are closer to build/renders/cedar-house-front-night.png than with undarkened lamps.
//   node windows/test/view3d/night-lights.mjs            (writes test-results/3d/night-lights-*.png)
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { openHarness, results, repo } from "./common.mjs";

const W = 960, H = 540;
const { page, close } = await openHarness("");
const render = (statics) => page.evaluate(async ([k, w, h]) => {
  const R = window.harness.view.renderer.constructor, old = {};
  for (const [n, x] of Object.entries(k)) { old[n] = R[n]; R[n] = x; }
  try {
    const r = await window.harness.render("Night", "Front", w, h, 1);
    return { png: r.png, spots: window.harness.view.renderer.spotShadows.length };
  } finally { for (const [n, x] of Object.entries(old)) R[n] = x; }
}, [statics, W, H]);
const now = await render({});
const off = await render({ LAMP_SUN_SHADOW: 0, SPOT_SHADOWS: 0 });
await close();
const a = path.join(results, "night-lights-current.png"), b = path.join(results, "night-lights-undarkened.png");
fs.writeFileSync(a, Buffer.from(now.png, "base64"));
fs.writeFileSync(b, Buffer.from(off.png, "base64"));

let failed = 0;
const check = (ok, msg) => { console.log(`${ok ? "PASS" : "FAIL"} ${msg}`); if (!ok) failed++; };
check(now.spots === 2 && off.spots === 0, `spot shadow maps for the two entrance spots (${now.spots})`);
const mac = path.join(repo, "build/renders/cedar-house-front-night.png");
if (fs.existsSync(mac)) {
  // Mean |difference| per pixel (0-255) in the bollard pools and the entrance under the canopy (fractions of the frame).
  const py = `
import sys, json
from PIL import Image
import numpy as np
m = np.asarray(Image.open(sys.argv[1]).convert('RGB').resize((${W}, ${H}), Image.LANCZOS), float)
out = {}
for f in sys.argv[2:]:
    w = np.asarray(Image.open(f).convert('RGB'), float)
    reg = {'pools': (0.667, 0.793, 0.52, 0.94), 'entry': (0.407, 0.667, 0.54, 0.79)}
    out[f] = {k: float(np.abs(w[int(y0*${H}):int(y1*${H}), int(x0*${W}):int(x1*${W})] - m[int(y0*${H}):int(y1*${H}), int(x0*${W}):int(x1*${W})]).mean()) for k, (y0, y1, x0, x1) in reg.items()}
print(json.dumps(out))`;
  const r = JSON.parse(execFileSync("python3", ["-c", py, mac, a, b]).toString());
  const c = r[a], u = r[b];
  console.log(`pools ${u.pools.toFixed(1)} → ${c.pools.toFixed(1)}, entrance ${u.entry.toFixed(1)} → ${c.entry.toFixed(1)} (mean |diff| vs the Mac)`);
  check(c.entry < u.entry - 1, "entrance under the canopy closer to the Mac (lamps darkened by the moon's shadow)");
  check(c.pools <= u.pools + 0.2, "bollard pools no further from the Mac");
} else console.log("Mac render missing (build/renders): comparison skipped");
process.exit(failed ? 1 : 0);
