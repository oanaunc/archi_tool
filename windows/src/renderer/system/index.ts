// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The last Mac UI-layer commands on Windows: APPSELFTEST (selftest.ts), HELPWINDOW (help-browser.ts), VRVIEW (vr.ts),
// SPACEMOUSE (spacemouse.ts) and SPELL with the Windows spell checker (spell-command.ts). The engine runs the commands
// with the Mac's prompts and messages (Host/EngineSystemCommands.swift) and asks the shell with `host` notifications:
// selfTest, helpBrowser, vrView, spaceMouse.
import type { App } from "../app";
import { showHelpBrowser } from "./help-browser";
import { report } from "./selftest";
import { vrView } from "./vr";
import { SpaceMouseController, type SpaceMouseView } from "./spacemouse";
import { installSpellCommand, primeSpelling } from "./spell-command";

export { showHelpBrowser, contextRoute } from "./help-browser";
export { rankCommands, ribbonTitles } from "./search";

export interface SystemHooks { view3d: () => SpaceMouseView | null }

export function installSystem(app: App, hooks: SystemHooks) {
  installSpellCommand(app);
  const spaceMouse = new SpaceMouseController(app, hooks.view3d);
  (window as any).archiSpaceMouse = spaceMouse; // tests
  (window as any).archiSpellPrime = primeSpelling; // tests
  let selfTestDone: ((r: { passed: number; failures: string[]; lines: string[] }) => void) | null = null;

  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (p: any) => {
    switch (p?.action) {
      case "helpBrowser": showHelpBrowser(app, String(p.route ?? "index")); return true;
      case "selfTest": {
        const r = report(app, { passed: Number(p.passed ?? 0), failures: (p.failures ?? []).map(String) });
        selfTestDone?.(r); selfTestDone = null;
        return true;
      }
      case "vrView": void vrView(app, p); return true;
      case "spaceMouse": void spaceMouse.set(p); return true;
    }
    return !!prevHost?.(p);
  };

  // The engine leaves the self-test report to the shell (its checks cover the catalogue, windows and devices).
  void app.tryCall("ui.prefs", { values: { "selfTest.shell": "1" } });
  document.addEventListener("archi:ready", async () => {
    await spaceMouse.start();
    // `--selftest`: run APPSELFTEST, print the report to stdout and exit with 0 / 1 (ArchiApp --selftest).
    const req = await app.engine.native?.initialRequest().catch(() => null);
    if (req?.kind !== "selftest") return;
    const done = new Promise<{ passed: number; failures: string[]; lines: string[] }>((res) => { selfTestDone = res; });
    await app.runCommand("APPSELFTEST");
    const r = await Promise.race([done, new Promise<null>((res) => setTimeout(() => res(null), 60000))]);
    const text = r ? r.lines.join("\n") : "APPSELFTEST did not report within 60 s.\n" + app.log.slice(-20).join("\n");
    (window as any).archiSystem?.selfTestDone(r && r.failures.length === 0 ? 0 : 1, text);
  }, { once: true });
  return { spaceMouse };
}
