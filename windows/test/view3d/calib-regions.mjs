// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Calibration sweep over the render-match regions: renders Cedar House looks small with renderer constants overridden
// and prints the mean difference to the Mac render per region (sky, lawn, paving, cedar, limestone, glass).
//   node windows/test/view3d/calib-regions.mjs '[{"name":"base"},{"name":"g","statics":{"ROUGH_GAMMA":2.2}}]' front-daylight,corner-golden-hour
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { openHarness, repo, here, windows } from "./common.mjs";
const variants = JSON.parse(process.argv[2] ?? '[{"name":"base"}]');
const jobs = (process.argv[3] ?? "front-daylight,corner-golden-hour,front-night,aerial-daylight").split(",");
const out = path.join(windows, "test-results/render-match/calib");
fs.mkdirSync(out, { recursive: true });
const presetOf = (j) => ({ "golden-hour": "Golden hour", daylight: "Daylight", overcast: "Overcast", night: "Night" })[j.split("-").slice(1).join("-")];
const camOf = (j) => j.split("-")[0].replace(/^./, (c) => c.toUpperCase());
const { page, close } = await openHarness(process.argv.includes("--full") ? "?meshes=/build/engine-fixtures/view3d-meshes-lod0.json&bin=/build/engine-fixtures/view3d-meshes-lod0.bin" : "");
for (const v of variants) {
  for (const j of jobs) {
    const r = await page.evaluate(async ([v, preset, cam]) => {
      const R = window.harness.view.renderer.constructor;
      const saved = {};
      for (const [k, x] of Object.entries(v.statics ?? {})) { saved[k] = R[k]; R[k] = x; }
      const o = await window.harness.renderLook({ preset, ...(v.look ?? {}) }, cam, 480, 270, 1);
      for (const [k, x] of Object.entries(saved)) R[k] = x;
      return o;
    }, [v, presetOf(j), camOf(j)]);
    fs.writeFileSync(path.join(out, `${v.name}--cedar-house-${j}.png`), Buffer.from(r.png, "base64"));
  }
}
await close();
const py = `
import sys, os
sys.path.insert(0, sys.argv[1])
from regions import REGIONS
from PIL import Image
mac, out = sys.argv[2], sys.argv[3]
names = sys.argv[4].split(','); jobs = sys.argv[5].split(',')
def mean(im, b):
    w, h = im.size; c = im.crop((int(b[0]*w), int(b[1]*h), max(int(b[0]*w)+1, int(b[2]*w)), max(int(b[1]*h)+1, int(b[3]*h))))
    px = list(c.getdata()); n = len(px); return [sum(p[i] for p in px)/n for i in range(3)]
tot = {n: 0.0 for n in names}
for j in jobs:
    rs = REGIONS[j.split('-')[0]]
    m = Image.open(os.path.join(mac, 'cedar-house-%s.png' % j)).convert('RGB').resize((480, 270), Image.LANCZOS)
    for n in names:
        w = Image.open(os.path.join(out, '%s--cedar-house-%s.png' % (n, j))).convert('RGB')
        parts = []; s = 0
        for k, b in rs.items():
            a, c = mean(w, b), mean(m, b)
            d = [x - y for x, y in zip(a, c)]; s += sum(abs(x) for x in d) / 3
            parts.append('%s %+4.0f' % (k[:5], sum(d) / 3))
        tot[n] += s / len(rs)
        print('%-20s %-10s %s | %.1f' % (j, n[:10], '  '.join(parts), s / len(rs)))
print('mean |diff|: ' + '  '.join('%s %.2f' % (n, tot[n] / len(jobs)) for n in names))
`;
process.stdout.write(execFileSync("python3", ["-W", "ignore", "-c", py, here, path.join(repo, "build/renders"), out, variants.map((v) => v.name).join(","), jobs.join(",")]).toString());
