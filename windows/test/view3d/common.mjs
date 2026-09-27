// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Shared set-up of the 3D view tests: bundles harness.ts with esbuild, serves the repository root over HTTP and
// opens the harness in headless Chromium (WebGL 2; SwiftShader is enough).
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
export const here = path.dirname(fileURLToPath(import.meta.url));
export const repo = path.resolve(here, "../../..");          // archi_tool/
export const windows = path.resolve(here, "../..");          // archi_tool/windows/
export const results = path.join(windows, "test-results/3d");

function load(name, env) {
  try { return require(name); } catch { return require(process.env[env] || name); }
}

export async function openHarness(query = "", viewport = { width: 1280, height: 800 }) {
  const esbuild = load("esbuild", "ESBUILD_PATH");
  esbuild.buildSync({ entryPoints: [path.join(here, "harness.ts")], bundle: true, format: "iife", target: "es2022", outfile: path.join(here, "harness.js"), logLevel: "warning" });
  const pw = (() => { try { return require("playwright-core"); } catch { return require(process.env.PLAYWRIGHT_PATH || "playwright"); } })();
  const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".jpg": "image/jpeg", ".png": "image/png" };
  const server = http.createServer((req, res) => {
    const p = path.join(repo, decodeURIComponent(new URL(req.url, "http://x").pathname));
    if (!p.startsWith(repo) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "content-type": types[path.extname(p)] || "application/octet-stream" });
    fs.createReadStream(p).pipe(res);
  }).listen(0);
  const browser = await pw.chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage({ viewport });
  page.on("pageerror", (e) => console.log("[pageerror]", e.message));
  page.on("console", (m) => { if (m.type() === "error") console.log("[page]", m.text()); });
  await page.goto(`http://localhost:${server.address().port}/windows/test/view3d/harness.html${query}`);
  await page.waitForFunction(() => window.harnessReady || window.harnessError, null, { timeout: 300000 });
  const err = await page.evaluate(() => window.harnessError);
  if (err) throw new Error(err);
  await page.evaluate(() => window.harness.ready());
  fs.mkdirSync(results, { recursive: true });
  return { page, close: async () => { await browser.close(); server.close(); } };
}

export function arg(k, d) { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; }
