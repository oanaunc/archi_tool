// Oanarina Archi Tool — GPL-3.0-or-later
// Release files for the Windows installer, next to it in out/ (and out-arm64/):
//   SHA256SUMS.txt  "<sha256>  <file name>" per installer, the same format as the Mac download's
//                   downloads/archi-tool/SHA256SUMS.txt on the website (check with `sha256sum -c` or
//                   `Get-FileHash -Algorithm SHA256`), so both lists can be merged into that one file.
//   release.json    version (app/Info.plist CFBundleShortVersionString), build (CFBundleVersion), and per installer
//                   the file name, bytes, MB, sha256, whether it is Authenticode-signed and its website URL
//                   https://www.oanarinaldi.com/downloads/archi-tool/<file>.
// Warns when an installer is larger than GitHub's 100 MiB file limit (the website repository cannot hold it then;
// windows/README.md "Publishing on the website").
// Usage (from windows/): node packaging/release-files.mjs [dir ...]      (default: out, and out-arm64 when present)
//        node packaging/release-files.mjs --verify <dir>                   (recompute and compare with SHA256SUMS.txt)
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const windows = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SITE = "https://www.oanarinaldi.com/downloads/archi-tool/";
const GITHUB_FILE_LIMIT = 100 * 1024 * 1024;

function plistKey(k) {
  const plist = fs.readFileSync(path.resolve(windows, "../app/Info.plist"), "utf8");
  return plist.match(new RegExp(`<key>${k}</key>\\s*<string>([^<]*)</string>`))?.[1]?.trim() ?? "";
}

function sha256(file) {
  const h = crypto.createHash("sha256");
  const fd = fs.openSync(file, "r");
  const buf = Buffer.alloc(1 << 20);
  let n;
  while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) h.update(buf.subarray(0, n));
  fs.closeSync(fd);
  return h.digest("hex");
}

// An Authenticode signature makes the PE optional header's security directory (data directory 4) non-empty.
function isSigned(file) {
  const fd = fs.openSync(file, "r");
  try {
    const head = Buffer.alloc(4096);
    fs.readSync(fd, head, 0, head.length, 0);
    if (head.toString("latin1", 0, 2) !== "MZ") return false;
    const pe = head.readUInt32LE(0x3c);
    if (pe + 160 > head.length || head.toString("latin1", pe, pe + 4) !== "PE\0\0") return false;
    const opt = pe + 24;
    const magic = head.readUInt16LE(opt);
    const dirs = opt + (magic === 0x20b ? 112 : 96);
    return head.readUInt32LE(dirs + 4 * 8 + 4) > 0;
  } finally { fs.closeSync(fd); }
}

const installers = (dir) => fs.existsSync(dir)
  ? fs.readdirSync(dir).filter((f) => /^Oanarina-Archi-Tool-Setup-.*\.exe$/.test(f)).sort() : [];

const args = process.argv.slice(2);
if (args[0] === "--verify") {
  const dir = path.resolve(windows, args[1] ?? "out");
  const lines = fs.readFileSync(path.join(dir, "SHA256SUMS.txt"), "utf8").split(/\r?\n/).filter(Boolean);
  let bad = 0;
  for (const line of lines) {
    const m = line.match(/^([0-9a-f]{64}) [ *](.+)$/);
    if (!m) { console.log(`FAIL  malformed line: ${line}`); bad++; continue; }
    const f = path.join(dir, m[2]);
    const ok = fs.existsSync(f) && sha256(f) === m[1];
    console.log(`${ok ? "OK  " : "FAIL"}  ${m[2]}`);
    if (!ok) bad++;
  }
  process.exit(bad ? 1 : 0);
}

const dirs = args.length ? args : ["out", "out-arm64"];
const short = plistKey("CFBundleShortVersionString");
const build = Number.parseInt(plistKey("CFBundleVersion"), 10) || 0;
let found = 0;
for (const d of dirs) {
  const dir = path.resolve(windows, d);
  const files = installers(dir);
  if (!files.length) { if (args.length) console.error(`release-files: no installer in ${dir}`); continue; }
  const entries = files.map((file) => {
    const full = path.join(dir, file);
    const bytes = fs.statSync(full).size;
    return { file, bytes, mb: Math.round(bytes / 1e5) / 10, sha256: sha256(full), signed: isSigned(full), url: SITE + file };
  });
  fs.writeFileSync(path.join(dir, "SHA256SUMS.txt"), entries.map((e) => `${e.sha256}  ${e.file}\n`).join(""));
  const release = { product: "Oanarina Archi Tool", platform: "windows", version: short, build,
    fileVersion: `${short}.${build}`, minimumOS: "Windows 10 64-bit", installers: entries };
  fs.writeFileSync(path.join(dir, "release.json"), JSON.stringify(release, null, 2) + "\n");
  for (const e of entries) {
    found++;
    console.log(`${e.sha256}  ${e.file}  ${e.bytes} bytes (${e.mb} MB)  ${e.signed ? "signed" : "unsigned"}`);
    if (e.bytes > GITHUB_FILE_LIMIT)
      console.log(`note: ${e.file} is over GitHub's 100 MiB file limit: upload it to the web host directly (windows/README.md "Publishing on the website")`);
  }
  console.log(`wrote ${path.relative(windows, path.join(dir, "SHA256SUMS.txt"))} and release.json (version ${short} build ${build})`);
}
if (!found) { console.error("release-files: no Oanarina-Archi-Tool-Setup-*.exe found"); process.exit(1); }
