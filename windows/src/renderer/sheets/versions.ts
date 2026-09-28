// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Versions window (ArchiApp/AppRound11Support.swift VersionsWindow / VersionsBrowser, FILEVERSIONS Browse): the saved
// versions of the drawing, newest first — Open Copy (a copy in a new window), Restore… (the current file is kept as a
// version) and Save Version Now. Every save of an .archi file keeps a version (up to the FILEVERSIONS Keep count).
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, flatButton, alertDialog } from "../dialogs/ui";
import { ensureRecoverySetup } from "./recovery";

export function openCopyWindow(app: App, path: string) {
  if (app.engine.native) void app.engine.native.newWindow({ kind: "open", path });
  else void app.open(path);
}

export async function openVersions(app: App) {
  await ensureRecoverySetup(app);
  const first = await app.tryCall("versions.list", {});
  if (!first) { app.print("Save the drawing as an .archi file first."); return null; }
  let selection: number | null = null;
  let message = "";
  return toolWindow("versions", `Versions — ${first.name}`, 460, 420, (body, w) => {
    const note = h("div", { class: "ver-note" });
    const list = h("div", { class: "ver-list", role: "listbox", tabindex: "0" });
    const msg = h("div", { class: "ver-msg" });
    const openBtn = flatButton("Open Copy", () => void openCopy());
    const restoreBtn = flatButton("Restore…", () => void restore());
    const saveBtn = flatButton("Save Version Now", () => void saveNow());
    let versions: any[] = first.versions ?? [];
    let keep: number = first.keep ?? 50;
    const render = () => {
      note.textContent = `Each save keeps a version (up to ${keep}). Open a copy to compare, or restore it.`;
      clear(list);
      versions.forEach((v, i) => {
        const r = h("div", { class: "ver-row" + (selection === i ? " sel" : ""), role: "option", "aria-label": `Version ${i + 1}, ${v.label}`, text: v.label });
        r.addEventListener("click", () => { selection = i; render(); });
        r.addEventListener("dblclick", () => { selection = i; void openCopy(); });
        list.append(r);
      });
      (openBtn as HTMLButtonElement).disabled = selection === null;
      (restoreBtn as HTMLButtonElement).disabled = selection === null;
      msg.textContent = message;
      msg.style.display = message ? "" : "none";
    };
    const reload = async () => {
      const r = await app.tryCall("versions.list", {});
      versions = r?.versions ?? [];
      keep = r?.keep ?? keep;
      if (selection !== null && selection >= versions.length) selection = null;
      render();
    };
    async function openCopy() {
      if (selection === null) return;
      try { const r = await app.engine.call("versions.open", { index: selection }); openCopyWindow(app, r.path); }
      catch (e: any) { message = e?.message ?? String(e); render(); }
    }
    async function restore() {
      if (selection === null) return;
      const v = versions[selection];
      const k = await alertDialog(`Restore the version of ${v.label}?`, app.info?.dirty ? "Unsaved changes in the window are lost; the saved file is kept as a version." : "The current file is kept as a version.", ["Restore", "Cancel"]);
      if (k !== 0) return;
      try { await app.engine.call("versions.restore", { index: selection }); message = "Restored."; await app.refresh(["all"]); }
      catch (e: any) { message = e?.message ?? String(e); }
      await reload();
    }
    async function saveNow() {
      const r = await app.tryCall("versions.save", {});
      message = r?.message ?? "Versions are not available on this volume.";
      await reload();
    }
    list.addEventListener("keydown", (e) => {
      if (!versions.length) return;
      if (e.key === "ArrowDown") { selection = Math.min(versions.length - 1, (selection ?? -1) + 1); render(); e.preventDefault(); }
      else if (e.key === "ArrowUp") { selection = Math.max(0, (selection ?? 1) - 1); render(); e.preventDefault(); }
      else if (e.key === "Enter") { void openCopy(); e.preventDefault(); }
    });
    body.classList.add("ver-body");
    body.append(note, list, h("div", { class: "ver-buttons" }, openBtn, restoreBtn, h("span", { class: "spacer" }), saveBtn), msg);
    render();
    void w;
  });
}
