// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of APPSELFTEST, HELPWINDOW, VRVIEW, SPACEMOUSE and SPELL's verdicts: the portable commands of
// Host/EngineSystemCommands.swift answering with the same `host` notifications and messages, so the browser test page
// exercises the shell. Never used inside the Electron app.

export const SYSTEM_COMMANDS = [
  { name: "APPSELFTEST", aliases: ["SELFTEST"], category: "Help", summary: "Runs the app's built-in regression checks (node graph, sheet set, presets, clipboard, ribbon)." },
  { name: "HELPWINDOW", aliases: ["DOCS", "HELPBROWSER", "MANUAL"], category: "Help", summary: "Opens the offline help browser (command pages, tutorials, shortcuts); F1 opens the running command's page." },
  { name: "VRVIEW", aliases: ["WEBXR", "VREXPORT", "HEADSETVIEW"], category: "View", summary: "VR headset viewing: writes the model as a WebXR page (life-size, floor on the room floor, pinch/trigger steps forward) for Apple Vision Pro, Meta Quest or OpenXR browsers; Open, Reveal (AirDrop) or just Save." },
  { name: "SPACEMOUSE", aliases: ["3DMOUSE", "NDOF", "3DCONNEXION"], category: "View", summary: "3Dconnexion SpaceMouse: On/Off, Object (orbit) or Fly mode, Sensitivity, Status. Axes move the 3D camera; button 1 fits the view." },
];
const prefs: Record<string, string> = {};
/** Calls seen by the fixture engine (tests check that SPELL's verdicts arrive before the command). */
export const systemCalls: { method: string; params: any }[] = [];
(globalThis as any).__archiSystemCalls = systemCalls;

export function fakeSystemCall(fe: any, method: string, p: any): any {
  const host = (params: any) => fe.emit("host", params);
  const idle = { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of SYSTEM_COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c, modifies: false });
      return undefined;
    }
    case "ui.prefs": Object.assign(prefs, p?.values ?? {}); return undefined;
    case "selftest.run": return { passed: 0, failures: [] };
    case "spell.verdicts": systemCalls.push({ method, params: p }); return { misspelled: Object.keys(p?.misspelled ?? {}).length };
    case "command.run": {
      const toks = String(p?.line ?? "").trim().split(/\s+/);
      const name = (toks[0] ?? "").toUpperCase();
      if (name === "SPELL" || name === "SPELLCHECK") { systemCalls.push({ method, params: p }); return undefined; }
      const def = SYSTEM_COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (!def) return undefined;
      fe.log(`Command: ${toks.join(" ")}`);
      const arg = toks.slice(1).join(" ");
      switch (def.name) {
        case "APPSELFTEST":
          if (prefs["selfTest.shell"] === "1") host({ action: "selfTest", passed: 0, failures: [] });
          else fe.log("0 check(s) passed, 0 failed.");
          break;
        case "HELPWINDOW": {
          const l = arg.toLowerCase();
          const cmd = (fe.hello?.commands ?? []).find((c: any) => c.name === arg.toUpperCase() || (c.aliases ?? []).includes(arg.toUpperCase()));
          if (!arg) host({ action: "helpBrowser", route: "index" });
          else if (["tutorials", "shortcuts", "scripting"].includes(l)) host({ action: "helpBrowser", route: l });
          else if (cmd) host({ action: "helpBrowser", route: "cmd/" + cmd.name });
          else fe.log(`Unknown command "${arg}".`);
          break;
        }
        case "VRVIEW": {
          const k = ["Open", "Reveal", "Save"].find((x) => x.toLowerCase().startsWith((arg || "Reveal").toLowerCase())) ?? "Reveal";
          const path = "C:\\Users\\Oana\\Desktop\\Drawing1-VR.html";
          fe.log(`VR page: 1200 triangles → ${path}. Open it in the headset's browser (copy it to the headset, or host it over HTTPS) and choose Enter VR.`);
          if (k !== "Save") host({ action: "vrView", path, mode: k });
          break;
        }
        case "SPACEMOUSE": {
          const kw = ["On", "Off", "Object", "Fly", "Sensitivity", "Status"].find((x) => x.toLowerCase() === (toks[1] ?? "status").toLowerCase()) ?? "Status";
          let enabled = prefs["spaceMouse.enabled"] !== "0", mode = prefs["spaceMouse.mode"] ?? "Object", sens = Number(prefs["spaceMouse.sensitivity"] ?? 1);
          if (kw === "On") enabled = true; else if (kw === "Off") enabled = false; else if (kw === "Object" || kw === "Fly") mode = kw;
          else if (kw === "Sensitivity") sens = Math.min(10, Math.max(0.05, Number(toks[2] ?? sens)));
          if (kw !== "Status") { Object.assign(prefs, { "spaceMouse.enabled": enabled ? "1" : "0", "spaceMouse.mode": mode, "spaceMouse.sensitivity": String(sens) }); host({ action: "spaceMouse", enabled, mode, sensitivity: sens }); }
          const devs = (prefs["spaceMouse.devices"] ?? "").split("\n").filter(Boolean);
          fe.log(`SpaceMouse ${enabled && prefs["spaceMouse.available"] === "1" ? "on" : "off"}, ${mode} mode, sensitivity ${Number(sens.toFixed(2))}; devices: ${devs.length ? devs.join(", ") : "none connected"}.`);
          break;
        }
      }
      return idle;
    }
  }
  return undefined;
}
