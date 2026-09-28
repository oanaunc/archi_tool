// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// VRVIEW (AppCommandsRound12.swift): the engine writes the model as the WebXR page (EngineWebViewer, the Mac's
// WebViewerExport) and asks for Open or Reveal. Reveal selects the page in Explorer. Open shows it in an app window
// (src/main/system.ts) where "Enter VR" appears when WebXR offers an immersive-vr session; when no headset is available
// (Electron is built without OpenXR, so this is the usual case) the window and the command line say so and offer the
// page in the default browser — Microsoft Edge and Chrome run it with an OpenXR headset (Windows Mixed Reality, Meta
// Quest Link, SteamVR), and a headset's own browser runs it when the file is copied there or hosted over HTTPS.
import type { App } from "../app";

export const NO_HEADSET = "No VR headset is available to this window, so the page opens as a 3D preview. For VR, open it in Microsoft Edge or Chrome with an OpenXR headset (Windows Mixed Reality, Meta Quest Link, SteamVR) — the VR window has an Open in Browser button — or in the headset's own browser.";

/** True when this window's WebXR can start an immersive-vr session (a headset and an OpenXR runtime). */
export async function headsetAvailable(): Promise<boolean> {
  const xr = (navigator as any).xr;
  if (!xr?.isSessionSupported) return false;
  try { return !!(await xr.isSessionSupported("immersive-vr")); } catch { return false; }
}

export async function vrView(app: App, p: { path?: string; mode?: string }) {
  const path = String(p.path ?? "");
  if (!path) return;
  const n = app.engine.native;
  const sys = (window as any).archiSystem;
  if (p.mode === "Reveal") { if (n?.revealPath) await n.revealPath(path); else app.print(`Saved ${path}.`); return; }
  if (p.mode !== "Open") return;
  if (!(await headsetAvailable())) app.print(NO_HEADSET);
  if (sys?.openVR) await sys.openVR(path);
  else if (n?.fileUrl) window.open(n.fileUrl(path), "_blank");
}
