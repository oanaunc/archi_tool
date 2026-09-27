// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Renders one look (JSON, render.settings fields) from a saved camera, for calibration:
//   node windows/test/view3d/probe.mjs '{"preset":"Overcast","shadowRadius":4}' Corner out.png [960x540]
import fs from "node:fs";
import { openHarness } from "./common.mjs";
const [look, cam, outFile, size = "960x540"] = process.argv.slice(2);
const [W, H] = size.split("x").map(Number);
const { page, close } = await openHarness();
const r = await page.evaluate(([l, c, w, h]) => window.harness.renderLook(JSON.parse(l), c, w, h, 1), [look, cam, W, H]);
fs.writeFileSync(outFile, Buffer.from(r.png, "base64"));
await close();
