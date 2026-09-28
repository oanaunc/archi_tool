// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Crash recovery (ArchiApp/Autosave.swift, StartView.swift recoverySection): the engine keeps this window's recovery copy
// ("<id>.archi" + "<id>.json" in %APPDATA%\Oanarina Archi Tool\Recovery) — written every N minutes while the drawing has
// unsaved changes (Settings ▸ Autosave), with a heartbeat every 30 s, removed on save and on a normal close. Copies left
// by a window that ended abnormally appear on the start screen under RECOVERED DOCUMENTS (Restore / Discard, newest
// three) and in DRAWINGRECOVERY. Versions of saved files go to %APPDATA%\Oanarina Archi Tool\Versions.
import type { App } from "../app";
import { h } from "../dom";
import { icon } from "../icons";
import { flatButton } from "../dialogs/ui";
import { folders } from "../dialogs/context";
import { prefs } from "../prefs";

let setup: Promise<boolean> | null = null;
let app: App | null = null;

export function versionsKeep(): number {
  try { const v = Number(localStorage.getItem("archi.fileVersionsKeep")); return v >= 1 && v <= 1000 ? v : 50; } catch { return 50; }
}
export function setVersionsKeep(n: number) { try { localStorage.setItem("archi.fileVersionsKeep", String(n)); } catch {} }
/** FILEPREVIEW Icons / Versions (Mac SaveExtras.finderPreview / .versions, both on by default). */
export function saveExtra(key: "finderPreviewIcons" | "fileVersionsOnSave"): boolean {
  try { return localStorage.getItem("archi." + key) !== "0"; } catch { return true; }
}
export function setSaveExtra(key: "finderPreviewIcons" | "fileVersionsOnSave", on: boolean) { try { localStorage.setItem("archi." + key, on ? "1" : "0"); } catch {} }

/** Tells the engine where the recovery and versions folders are (once per window). */
export function ensureRecoverySetup(a: App): Promise<boolean> {
  app = a;
  if (!setup) {
    setup = (async () => {
      const f = await folders();
      const versions = f.recovery.replace(/Recovery$/i, "Versions");
      const r = await a.tryCall("recovery.setup", { folder: f.recovery, versionsFolder: versions, keep: versionsKeep(),
        versionsOnSave: saveExtra("fileVersionsOnSave"), previewOnSave: saveExtra("finderPreviewIcons") });
      return !!r;
    })();
  }
  return setup;
}

let lastWrite = Date.now();
/** Every 30 s: heartbeat, and the recovery copy when the autosave interval has passed (AutosaveSession.saveNow). */
export async function recoveryTick(a: App) {
  if (!(await ensureRecoverySetup(a))) return;
  const minutes = prefs.get("autosaveMinutes");
  const due = !!minutes && !!a.info?.dirty && Date.now() - lastWrite >= minutes * 60000;
  if (due) lastWrite = Date.now();
  await a.tryCall("recovery.autosave", { write: due });
}

/** The drawing was saved or the window closes normally: no recovery copy. */
export async function recoveryDiscard(a: App) {
  if (setup) await a.tryCall("recovery.discard", {});
}

/** After a restore: close the start screen and show the recovered plan. */
export function afterRecovered(a: App) {
  a.showStart = false; a.emit("start");
  a.activeLayout = 0;
  if (a.mode !== "2D") a.setUI("mode", "2D");
  setTimeout(() => a.canvas?.zoomExtents(), 80);
}

/** RECOVERED DOCUMENTS on the start screen, or null when there is nothing to recover. */
export async function recoverySection(a: App, rerender: () => void): Promise<HTMLElement | null> {
  await ensureRecoverySetup(a);
  const r = await a.tryCall("recovery.list", {});
  const items: any[] = r?.items ?? [];
  if (!items.length) return null;
  const rows = items.slice(0, 3).map((info) => {
    const restore = flatButton("Restore", async () => {
      const res = await a.tryCall("recovery.restore", { id: info.id });
      if (res) afterRecovered(a); else rerender();
    }, { prominent: true, compact: true });
    const discard = flatButton("Discard", async () => { await a.tryCall("recovery.remove", { id: info.id }); rerender(); }, { compact: true });
    return h("div", { class: "rec-row", "data-id": String(info.id) },
      h("div", { class: "rec-text" }, h("div", { class: "rec-name", text: String(info.name ?? "Untitled") }), h("div", { class: "rec-date", text: String(info.dateText ?? info.date ?? "") })),
      h("span", { class: "spacer" }), restore, discard);
  });
  return h("div", { class: "rec-section" },
    h("div", { class: "rec-head" }, icon("lifepreserver", 12, 1.8), h("span", { text: "RECOVERED DOCUMENTS" })),
    h("div", { class: "rec-note", text: "These documents had unsaved changes when the app last quit unexpectedly." }),
    ...rows);
}

export function recoveryApp() { return app; }
