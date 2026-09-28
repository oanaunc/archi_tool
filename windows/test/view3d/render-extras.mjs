// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Renderer features of the Render window and the environment commands, on the Cedar House fixture: clay model, depth
// of field, environment image (HDRI File) and the Radiance decoder, billboards (BILLBOARD), IES light distributions
// (LIGHT IES). Images go to windows/test-results/render-match/extras-*.png.
//   node windows/test/view3d/render-extras.mjs
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { openHarness, windows } from "./common.mjs";

const out = path.join(windows, "test-results/render-match");
fs.mkdirSync(out, { recursive: true });
const results = [];
const check = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const { page, close } = await openHarness();
const W = 480, H = 270;
async function shot(name, extra, preset = "Daylight", cam = "Front") {
  const r = await page.evaluate(([e, p, c, w, h]) => window.harness.renderExtra(e, p, c, w, h), [extra, preset, cam, W, H]);
  const f = path.join(out, `extras-${name}.png`);
  fs.writeFileSync(f, Buffer.from(r.png, "base64"));
  return f;
}
// Region statistics in Python (PIL): mean RGB, saturation and gradient energy of a box (fractions of the frame).
function stats(file, box) {
  const py = `
import sys, json
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB'); w, h = im.size
b = json.loads(sys.argv[2]); c = im.crop((int(b[0]*w), int(b[1]*h), int(b[2]*w), int(b[3]*h)))
px = list(c.getdata()); n = len(px)
mean = [sum(p[i] for p in px) / n for i in range(3)]
sat = sum(max(p) - min(p) for p in px) / n
g = c.convert('L'); gw, gh = g.size; d = g.load(); e = 0
for y in range(gh - 1):
    for x in range(gw - 1): e += abs(d[x + 1, y] - d[x, y]) + abs(d[x, y + 1] - d[x, y])
print(json.dumps({'mean': mean, 'sat': sat, 'grad': e / max(1, (gw - 1) * (gh - 1))}))
`;
  return JSON.parse(execFileSync("python3", ["-W", "ignore", "-c", py, file, JSON.stringify(box)]).toString());
}
const FULL = [0, 0, 1, 1], CEDAR = [0.44, 0.30, 0.52, 0.60], SKY = [0.62, 0.03, 0.95, 0.16];

// Base and clay: every surface matte white 0.92, so the cedar loses its colour and the scene its saturation.
const base = await shot("base", {});
const clay = await shot("clay", { clay: true });
const sb = stats(base, CEDAR), sc = stats(clay, CEDAR);
check("clay model: cedar turns neutral white-grey", sc.sat < sb.sat * 0.35 && sc.mean[0] > sb.mean[0], `saturation ${sb.sat.toFixed(1)} → ${sc.sat.toFixed(1)}, R ${sb.mean[0].toFixed(0)} → ${sc.mean[0].toFixed(0)}`);

// Depth of field: focused 1 m in front of the camera at f/0.8, the house (≈15 m away) is blurred.
const dof = await shot("dof", { dof: { focus: 1, fStop: 0.8 } });
const gb = stats(base, [0.1, 0.2, 0.9, 0.8]).grad, gd = stats(dof, [0.1, 0.2, 0.9, 0.8]).grad;
check("depth of field blurs out-of-focus surfaces", gd < gb * 0.75, `gradient energy ${gb.toFixed(2)} → ${gd.toFixed(2)}`);
const dofFar = await shot("dof-house", { dof: { focus: 0, fStop: 16 } });
const gf = stats(dofFar, [0.1, 0.2, 0.9, 0.8]).grad;
check("focus on the model centre at f/16 keeps the house sharp", gf > gb * 0.85, `gradient energy ${gb.toFixed(2)} / ${gf.toFixed(2)}`);

// Environment image: a red equirectangular environment lights the scene and fills the background.
const env = await shot("hdri", {
  envImage: await page.evaluate(() => {
    const w = 64, h = 32, d = new Float32Array(w * h * 4);
    for (let i = 0; i < w * h; i++) { d[i * 4] = 1.2; d[i * 4 + 1] = 0.15; d[i * 4 + 2] = 0.1; d[i * 4 + 3] = 1; }
    return { key: "red-test", width: w, height: h, data: Array.from(d) };
  }).then((e) => ({ ...e, data: e.data })),
});
const se = stats(env, SKY);
check("HDRI environment replaces the sky", se.mean[0] > 2 * se.mean[1], `sky ${se.mean.map((v) => v.toFixed(0)).join(",")}`);

// Radiance decoder: flat and run-length encoded scanlines.
const dec = await page.evaluate(() => {
  const head = "#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 2 +X 8\n";
  const bytes = [...head].map((c) => c.charCodeAt(0));
  // Row 0 run-length encoded: all pixels (128, 64, 32, e=129) → (0.5+128)/128 × 2 … ; row 1 flat.
  bytes.push(2, 2, 0, 8);
  for (const v of [128, 64, 32, 129]) bytes.push(128 + 8, v);
  for (let x = 0; x < 8; x++) bytes.push(64, 64, 64, 128);
  const r = window.harness.hdri.decodeHDR(new Uint8Array(bytes));
  return r ? { w: r.width, h: r.height, p0: Array.from(r.data.slice(0, 4)), p1: Array.from(r.data.slice(32, 36)) } : null;
});
check("Radiance .hdr decoder (RLE and flat rows)", !!dec && dec.w === 8 && dec.h === 2 && Math.abs(dec.p0[0] - 1.0039) < 0.01 && Math.abs(dec.p0[2] - 0.2539) < 0.01 && Math.abs(dec.p1[1] - 0.252) < 0.01, JSON.stringify(dec));

// Billboards: a tree cut-out at the Front camera's target stands in front of the house, facing the camera.
const placed = await page.evaluate(async () => {
  const v = window.harness.view;
  const cam = v.cameras.find((c) => c.name === "Front");
  const t = cam.target, e = cam.eye;
  const k = 0.35;   // part of the way from the target towards the eye
  const p = [t[0] + (e[0] - t[0]) * k, t[1] + (e[1] - t[1]) * k, 0];
  v.setInfo({ billboards: [{ id: 9001, position: p, height: 6000, source: "tree" }] });
  await new Promise((r) => setTimeout(r, 300));
  const m = v.scene.meshes.find((x) => x.kind === "billboard");
  return { count: v.scene.meshes.filter((x) => x.kind === "billboard").length, p, tex: m?.mat.texture?.slice(0, 22) };
});
const bb = await shot("billboard", {});
const center = [0.40, 0.25, 0.60, 0.75];
const cb = stats(base, center), cbb = stats(bb, center);
const diff = Math.abs(cb.mean[0] - cbb.mean[0]) + Math.abs(cb.mean[1] - cbb.mean[1]) + Math.abs(cb.mean[2] - cbb.mean[2]);
check("billboard mesh built from the built-in tree", placed.count === 1 && placed.tex === "data:image/png;base64,", JSON.stringify(placed));
check("billboard drawn in front of the house", diff > 6 && cbb.mean[1] >= cbb.mean[2], `centre ${cb.mean.map((v) => v.toFixed(0))} → ${cbb.mean.map((v) => v.toFixed(0))}`);
const facing = await page.evaluate(() => {
  const v = window.harness.view, m = v.scene.meshes.find((x) => x.kind === "billboard");
  return m?.xf ? Array.from(m.xf).slice(0, 2) : null;
});
check("billboard turned towards the camera", !!facing && Math.hypot(facing[0], facing[1]) > 0.99, JSON.stringify(facing));
await page.evaluate(() => window.harness.view.setInfo({ billboards: [] }));

// IES: the photometric web's relative intensity by angle; a narrow IES spot lights a smaller pool than a plain spot.
const row = await page.evaluate(() => Array.from(window.harness.iesRow({ vertical: [0, 15, 30, 60, 90], relative: [1, 0.9, 0.45, 0.05, 0] })));
check("IES profile resampled to 32 angles (0° full, ≥ 90° dark)", Math.abs(row[0] - 1) < 1e-6 && row[16] === 0 && row[31] === 0 && row[3] < 1 && row[3] > 0.45, row.slice(0, 8).map((v) => v.toFixed(2)).join(" "));
const pools = await page.evaluate(async () => {
  const v = window.harness.view, sc = v.scene;
  const saved = sc.lights;
  const cam = v.cameras.find((c) => c.name === "Front");
  const t = cam.target, e = cam.eye;
  const p = [t[0] + (e[0] - t[0]) * 0.3, t[1] + (e[1] - t[1]) * 0.3, 2500];
  const spot = { id: "t", kind: "spot", position: p, target: [p[0], p[1], 0], lumens: 3000, cct: 3000, beam: 120 };
  // A narrow downlight: full straight down, half at 10°, dark from 20°.
  const ies = { ...spot, kind: "ies", iesProfile: { vertical: [0, 10, 20, 90], relative: [1, 0.5, 0, 0] } };
  const out = {};
  for (const [k, l] of [["none", null], ["spot", spot], ["ies", ies]]) {
    sc.lights = l ? [l] : [];
    const r = await window.harness.renderExtra({}, "Night", "Front", 320, 180);
    out[k] = r.png;
  }
  sc.lights = saved;
  return out;
});
const pf = {};
for (const k of ["none", "spot", "ies"]) { pf[k] = path.join(out, `extras-light-${k}.png`); fs.writeFileSync(pf[k], Buffer.from(pools[k], "base64")); }
const lum = (f) => { const m = stats(f, FULL).mean; return 0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]; };
const [l0, ls, li] = [lum(pf.none), lum(pf.spot), lum(pf.ies)];
check("an IES light lights less than a plain 120° spot (narrow web)", ls > l0 + 0.5 && li > l0 && li < ls, `mean luminance none ${l0.toFixed(2)}, spot ${ls.toFixed(2)}, IES ${li.toFixed(2)}`);

await close();
fs.writeFileSync(path.join(out, "extras-results.json"), JSON.stringify(results, null, 1));
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
