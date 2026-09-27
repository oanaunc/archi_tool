// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Calibration probe: renders Cedar House looks at a small size with renderer constants overridden and prints region means
// next to the Mac render's (build/renders), so a constant can be tuned against every preset at once.
//   node windows/test/view3d/calib.mjs '[{"name":"base"},{"name":"ao0","look":{"ao":0}},{"name":"k","statics":{"ENV_DIFFUSE":1.2}}]'
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { openHarness, results, repo } from "./common.mjs";
const variants = JSON.parse(process.argv[2] ?? '[{"name":"base"}]');
const jobs = (process.argv[3] ?? "corner-golden-hour,front-daylight,corner-overcast,front-night").split(",");
const [W, H] = [480, 270];
const { page, close } = await openHarness(process.argv.includes("--full") ? "?meshes=/build/engine-fixtures/view3d-meshes-lod0.json&bin=/build/engine-fixtures/view3d-meshes-lod0.bin" : "");
console.log("load", JSON.stringify(await page.evaluate(() => window.loadInfo)));
const presetOf = (j) => ({ "golden-hour": "Golden hour", daylight: "Daylight", overcast: "Overcast", night: "Night" })[j.split("-").slice(1).join("-")];
const camOf = (j) => j.split("-")[0].replace(/^./, (c) => c.toUpperCase());
for (const v of variants) {
  for (const j of jobs) {
    const r = await page.evaluate(async ([v, preset, cam, W, H]) => {
      const R = window.harness.view.renderer.constructor;
      const saved = {};
      for (const [k, x] of Object.entries(v.statics ?? {})) { saved[k] = R[k]; R[k] = x; }
      const out = await window.harness.renderLook({ preset, ...(v.look ?? {}) }, cam, W, H, 1);
      for (const [k, x] of Object.entries(saved)) R[k] = x;
      return out;
    }, [v, presetOf(j), camOf(j), W, H]);
    const f = path.join(results, `calib-${v.name}-${j}.png`);
    fs.writeFileSync(f, Buffer.from(r.png, "base64"));
  }
}
await close();
const py = `
import sys, os
from PIL import Image
mac, win = sys.argv[1], sys.argv[2]
names = sys.argv[3].split(','); jobs = sys.argv[4].split(',')
R = {'front': {'limestone':(0.05,0.35,0.18,0.6),'cedar':(0.34,0.25,0.37,0.6),'sky':(0.6,0.05,0.9,0.2),'pave':(0.3,0.8,0.7,0.95),'grass':(0.9,0.66,1.0,0.72)},
     'corner': {'limestone':(0.2,0.35,0.3,0.6),'cedar':(0.54,0.3,0.6,0.6),'sky':(0.6,0.05,0.9,0.2),'pave':(0.4,0.8,0.8,0.95),'grass':(0.0,0.62,0.1,0.72)}}
def reg(im, b):
    w, h = im.size; c = im.crop((int(b[0]*w), int(b[1]*h), int(b[2]*w), int(b[3]*h))).convert('RGB')
    px = list(c.getdata()); n = len(px); return tuple(round(sum(p[i] for p in px)/n) for i in range(3))
for j in jobs:
    m = Image.open(os.path.join(mac, 'cedar-house-%s.png' % j)).convert('RGB').resize((480, 270))
    rs = R[j.split('-')[0]]
    print(j, 'mac  ', ' '.join('%s%s' % (k, reg(m, b)) for k, b in rs.items()))
    for n in names:
        w = Image.open(os.path.join(win, 'calib-%s-%s.png' % (n, j))).convert('RGB')
        print(j, ('%-5s' % n[:5]), ' '.join('%s%s' % (k, reg(w, b)) for k, b in rs.items()))
`;
process.stdout.write(execFileSync("python3", ["-W", "ignore", "-c", py, path.join(repo, "build/renders"), results, variants.map((v) => v.name).join(","), jobs.join(",")]).toString());
