// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Main-process services of the last Mac UI-layer commands (src/renderer/system):
//  - WebHID for the SpaceMouse (SPACEMOUSE): 3Dconnexion and other multi-axis controllers are granted to the app's
//    windows without a device chooser (the Mac's IOHIDManager matching: vendor 0x256F, or generic desktop usage 8);
//  - the VR window (VRVIEW Open): the WebXR page in an app window with WebXR allowed; when no immersive-vr session is
//    available (Electron is built without OpenXR) a banner says so and "Open in Browser" hands the page to the default
//    browser (Edge / Chrome run WebXR with OpenXR headsets);
//  - `--selftest`: the renderer runs APPSELFTEST and reports here; the report goes to stdout and the exit code is 0 / 1.
import { app, BrowserWindow, ipcMain, session, shell } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";

const SPACEMOUSE_VENDOR = 0x256f;
function isSpaceMouse(d: any): boolean {
  if (!d) return false;
  if (d.vendorId === SPACEMOUSE_VENDOR) return true;
  return (d.collections ?? []).some((c: any) => c.usagePage === 0x01 && c.usage === 0x08);
}

export function installSystem(opts: { icon: string }) {
  ipcMain.handle("system:openVR", (e, file: string) => openVR(String(file), BrowserWindow.fromWebContents(e.sender), opts.icon));
  ipcMain.on("system:selftestDone", (_e, code: number, text: string) => {
    process.stdout.write(String(text) + "\n");
    app.exit(code === 0 ? 0 : 1);
  });
  app.whenReady().then(() => {
    const s = session.defaultSession;
    // HID permission: only multi-axis controllers, only for the app's own pages (file://).
    s.setPermissionCheckHandler((wc, permission, origin, details: any) => {
      if (permission === "hid") return /^file:/.test(String(details?.securityOrigin ?? origin ?? wc?.getURL() ?? ""));
      return true; // Electron's default for everything else
    });
    s.setDevicePermissionHandler((d: any) => d.deviceType === "hid" && isSpaceMouse(d.device));
    s.on("select-hid-device", (event, details, callback) => {
      event.preventDefault();
      const d = details.deviceList.find(isSpaceMouse);
      callback(d ? d.deviceId : null);
    });
  }).catch(() => {});
}

/** Script run in the VR window after load: WebXR check and the no-headset banner. */
const BANNER = `(() => {
  const show = () => {
    if (document.getElementById('archi-vr-note')) return;
    const d = document.createElement('div');
    d.id = 'archi-vr-note';
    d.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;padding:10px 14px;background:#2b2c31;color:#e6e6e6;border:1px solid #F5C518;border-radius:6px;font:13px Segoe UI,sans-serif;display:flex;gap:12px;align-items:center;z-index:10';
    const t = document.createElement('span');
    t.style.flex = '1';
    t.textContent = 'No VR headset is available to this window: this is a 3D preview. Open the page in Microsoft Edge or Chrome with an OpenXR headset (Windows Mixed Reality, Meta Quest Link, SteamVR), or copy it to the headset and open it in its browser, then choose Enter VR.';
    const a = document.createElement('a');
    a.textContent = 'Open in Browser'; a.href = location.href; a.target = '_blank';
    a.style.cssText = 'background:#F5C518;color:#1e1f22;padding:4px 10px;border-radius:4px;text-decoration:none;white-space:nowrap';
    d.append(t, a); document.body.append(d);
  };
  const xr = navigator.xr;
  if (!xr || !xr.isSessionSupported) { show(); return 'none'; }
  return xr.isSessionSupported('immersive-vr').then((ok) => { if (!ok) show(); return ok ? 'vr' : 'none'; }, () => { show(); return 'none'; });
})()`;

export async function openVR(file: string, parent: BrowserWindow | null, icon: string): Promise<string> {
  const url = pathToFileURL(file).toString();
  const win = new BrowserWindow({
    width: 1100, height: 760, title: `${path.basename(file)} — VR Headset View`, icon, backgroundColor: "#1e1f22", autoHideMenuBar: true,
    webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false, partition: "vrview" },
  });
  win.setMenu(null);
  // WebXR (and nothing else) may be used by the page; "Open in Browser" goes to the default browser.
  win.webContents.session.setPermissionRequestHandler((_wc, permission, cb) => cb(permission === "xr" as any || String(permission).startsWith("xr")));
  win.webContents.setWindowOpenHandler(({ url: u }) => { if (u === url) void shell.openExternal(url); return { action: "deny" }; });
  win.webContents.on("will-navigate", (e, u) => { if (u !== url) e.preventDefault(); });
  await win.loadURL(url);
  let result = "none";
  try { result = String(await win.webContents.executeJavaScript(BANNER, true)); } catch {}
  void parent;
  return result;
}
