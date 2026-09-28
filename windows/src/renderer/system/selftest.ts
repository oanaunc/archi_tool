// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// APPSELFTEST / SELFTEST (AppSelfTests.swift): the engine runs its half (node graphs, sheet sets, help routes, VR page,
// spelling, SpaceMouse status: Host/EngineSystemCommands.swift) and sends the result with {"action":"selfTest"}; the
// shell adds the checks of what it owns — every ribbon, menu and contextual-tab entry runs a registered command, command
// coverage, the command search ranking, the help browser pages, the SpaceMouse maths and HID reports, the spell checker
// and WebXR — and prints the report in the Mac's words:
//   Command coverage: N in ribbon/menus, M in palettes (system variables), K without UI entry.
//   FAIL: …
//   P check(s) passed, F failed.
// `Oanarina Archi Tool.exe --selftest` runs it headless and exits with 0 (pass) or 1 (fail), like the Mac's --selftest.
import type { App } from "../app";
import { entryEnabled, shellCommand } from "../ui/shell-commands";
import { commandLocations } from "../ui/help";
import { spellChecker } from "../doctools/spelling";
import { catalogItems, rankCommands, ribbonTitles } from "./search";
import { FUNCTION_KEYS, TUTORIALS, indexPage, commandPage, shortcutsPage, scriptingPage, guidePage, helpHtml } from "./help-browser";
import { motion, applyMotion, defaultConfig, reportLayout, applyReport, emptyState, isSpaceMouse } from "./spacemouse-math";

/** Commands of the Mac catalogue that are not on Windows until Oana decides (docs/WINDOWS-FILEPREVIEW.md). */
export const PENDING_ON_WINDOWS = ["FILEPREVIEW"];

export interface Coverage { missing: string[]; intentional: number; total: number }

export function coverage(app: App): Coverage {
  const where = commandLocations();
  const covered = new Set<string>();
  for (const it of catalogItems()) for (const n of [it.command.split(" ")[0], ...it.names]) { const d = app.lookup(n.split(" ")[0]); if (d) covered.add(d.name); }
  for (const n of where.keys()) { const d = app.lookup(n); if (d) covered.add(d.name); }
  const missing: string[] = [];
  let intentional = 0;
  for (const d of [...(app.hello?.commands ?? [])].sort((a, b) => (a.name < b.name ? -1 : 1))) {
    if (covered.has(d.name)) continue;
    if (d.category === "Settings" && d.summary.startsWith("System variable")) intentional++;
    else missing.push(d.name);
  }
  return { missing, intentional, total: app.hello?.commands?.length ?? 0 };
}

export function shellChecks(app: App, check: (ok: boolean, name: string) => void): Coverage {
  const cmds = app.hello?.commands ?? [];
  // Every ribbon / menu item resolves to a registered command (or a shell window / action).
  const missing = catalogItems().filter((it) => {
    if (it.command.startsWith("@") || (it.ui && !it.command)) return false;
    const n = it.command.split(" ")[0].toUpperCase();
    if (PENDING_ON_WINDOWS.includes(n)) return false;
    return !entryEnabled(app, it) && !shellCommand(n);
  }).map((it) => it.title);
  check(missing.length === 0, `ribbon items without a command: ${[...new Set(missing)].join(", ")}`);
  const cov = coverage(app);
  check(cov.missing.length === 0, `commands without a ribbon/menu/palette entry: ${cov.missing.join(", ")}`);
  // Command search (CommandSearch.rank).
  const tm = ribbonTitles((n) => app.lookup(n)?.name);
  check(rankCommands("prspl", cmds, tm)[0]?.name === "PRESSPULL", "fuzzy search finds PRESSPULL");
  check(rankCommands("tag all", cmds, tm).some((c) => c.name === "TAGALL"), "ribbon title search finds TAGALL");
  // Help browser (APP-055 / APP-057 / APP-058 / APP-059).
  const sp = shortcutsPage();
  check(FUNCTION_KEYS.every(([k]) => sp.includes(`<code>${k}</code>`)), "function keys documented in the help");
  const idx = indexPage(cmds);
  check(cmds.every((c) => idx.includes(`archi-help:cmd/${c.name}"`)), "help index links every command");
  const lineAlias = cmds.find((c) => c.name === "LINE")?.aliases?.[0] ?? "LINE";
  check(!!commandPage(cmds, lineAlias)?.includes("<code>LINE</code>") && commandPage(cmds, "NOPE_NOT_A_CMD") === null, "command page by alias");
  const missingTut = TUTORIALS.flatMap((t) => t.steps).map(([, l]) => l.split(" ")[0]).filter((n) => !app.lookup(n));
  check(missingTut.length === 0, `tutorial steps run real commands: missing ${missingTut.join(", ")}`);
  check(helpHtml(cmds, "cmd/LINE").includes("archi-run:LINE"), "command page has a Run link");
  check(scriptingPage().includes("archi.wall(x1, y1, x2, y2, opts)"), "API reference in the help browser");
  check(/id="the-command-line"/.test(guidePage()) && /<table>/.test(guidePage()), "user guide bundled with its sections");
  // SpaceMouse maths (AppSelfTestsRound10 uiChecks).
  const cfg = defaultConfig();
  const z = motion([10, -10, 5, 0, 0, 3], cfg, 1 / 60);
  check(z.right === 0 && z.up === 0 && z.forward === 0 && z.yaw === 0 && z.pitch === 0, "SpaceMouse dead zone");
  const cam = { eye: [10000, 0, 2000] as [number, number, number], target: [0, 0, 2000] as [number, number, number] };
  const dist = (c: typeof cam) => Math.hypot(c.eye[0] - c.target[0], c.eye[1] - c.target[1], c.eye[2] - c.target[2]);
  const zoom = applyMotion(motion([0, -350, 0, 0, 0, 0], cfg, 0.1), cam, "Object");
  check(dist(zoom) < 10000 && zoom.target.every((v, i) => v === cam.target[i]), "SpaceMouse push zooms towards the target");
  const spin = applyMotion(motion([0, 0, 0, 0, 0, 300], cfg, 0.1), cam, "Object");
  check(Math.abs(dist(spin) - 10000) < 1e-6 && Math.hypot(spin.eye[0] - cam.eye[0], spin.eye[1] - cam.eye[1]) > 1, "SpaceMouse spin orbits at a constant distance");
  const fly = applyMotion(motion([300, 0, 0, 0, 0, 0], cfg, 0.1), cam, "Fly");
  const de = fly.eye.map((v, i) => v - cam.eye[i]), dt = fly.target.map((v, i) => v - cam.target[i]);
  check(de.every((v, i) => Math.abs(v - dt[i]) < 1e-6) && fly.eye[1] !== cam.eye[1], "SpaceMouse fly pans eye and target together");
  const dm = motion([300, 200, 0, 0, 0, 0], { ...cfg, dominant: true }, 0.1);
  check(dm.right !== 0 && dm.forward === 0, "dominant axis mode keeps the strongest axis");
  // HID reports: a descriptor with six 16-bit axes and two buttons, and the classic 3Dconnexion reports.
  const layout = reportLayout([{ usagePage: 1, usage: 8, inputReports: [{ reportId: 1, items: [{ usages: [0x10030, 0x10031, 0x10032, 0x10033, 0x10034, 0x10035], reportSize: 16, reportCount: 6, logicalMinimum: -350 }] },
    { reportId: 3, items: [{ isRange: true, usageMinimum: 0x90001, usageMaximum: 0x90002, reportSize: 1, reportCount: 2, logicalMinimum: 0 }, { isConstant: true, reportSize: 6, reportCount: 1 }] }] }]);
  const st = emptyState();
  const b = new DataView(new ArrayBuffer(12)); [120, -80, 0, 5, 0, -300].forEach((v, i) => b.setInt16(i * 2, v, true));
  applyReport(st, layout, 1, b);
  applyReport(st, layout, 3, new DataView(new Uint8Array([0b10]).buffer));
  check(st.axes.join() === "120,-80,0,5,0,-300" && st.buttons.has(2) && !st.buttons.has(1), "SpaceMouse HID report (descriptor)");
  const legacy = emptyState();
  const t = new DataView(new ArrayBuffer(6)); t.setInt16(0, 40, true); t.setInt16(4, -7, true);
  applyReport(legacy, new Map(), 1, t); applyReport(legacy, new Map(), 3, new DataView(new Uint8Array([1]).buffer));
  check(legacy.axes[0] === 40 && legacy.axes[2] === -7 && legacy.buttons.has(1), "SpaceMouse HID report (3Dconnexion)");
  check(isSpaceMouse({ vendorId: 0x256f }) && isSpaceMouse({ vendorId: 0x046d, collections: [{ usagePage: 1, usage: 8 }] }) && !isSpaceMouse({ vendorId: 0x046d, collections: [{ usagePage: 1, usage: 2 }] }), "SpaceMouse device matching");
  // Spelling: the Windows spell checker answers (Chromium / Windows spell-checking service).
  const sc = spellChecker();
  check(sc.isMisspelled("wiht") && !sc.isMisspelled("kitchen"), "spell checker available");
  return cov;
}

/** Prints the report (the Mac APPSELFTEST command's lines); returns the number of failures. */
export function report(app: App, engine: { passed: number; failures: string[] }, extra?: (ok: boolean, name: string) => void): { passed: number; failures: string[]; lines: string[] } {
  let passed = engine.passed;
  const failures = [...engine.failures];
  const check = (ok: boolean, name: string) => { if (ok) passed++; else failures.push(name); extra?.(ok, name); };
  let cov: Coverage | null = null;
  try { cov = shellChecks(app, check); } catch (e: any) { failures.push(`shell checks stopped: ${e?.message ?? e}`); }
  const lines: string[] = [];
  if (cov) {
    lines.push(`Command coverage: ${cov.total - cov.missing.length - cov.intentional} in ribbon/menus, ${cov.intentional} in palettes (system variables), ${cov.missing.length} without UI entry.`);
    if (cov.missing.length) lines.push("  Without UI entry: " + cov.missing.join(", "));
  }
  const pending = PENDING_ON_WINDOWS.filter((n) => !app.lookup(n));
  if (pending.length) lines.push(`  Not on Windows yet: ${pending.join(", ")} (docs/WINDOWS-FILEPREVIEW.md).`);
  for (const f of failures) lines.push("FAIL: " + f);
  lines.push(`${passed} check(s) passed, ${failures.length} failed.`);
  if (failures.length) lines.push(`${failures.length} self-test check(s) failed.`);
  for (const l of lines) app.print(l);
  return { passed, failures, lines };
}
