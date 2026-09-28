// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// SHARE and ARQUICKLOOK Share (ShareSheet in AppCommandsReview.swift): the Windows share sheet for the files the engine
// wrote (Mail, Teams, Nearby Sharing, OneDrive …). Where it cannot open (older Windows, the test page) a small Share
// window offers Copy Files (paste them into any app) and Show in Explorer.
import type { App } from "../app";
import { h } from "../dom";
import { toolWindow, flatButton, note, spacer } from "../dialogs/ui";
import { std, webRecord } from "./native";

const base = (p: string) => p.split(/[\\/]/).pop() ?? p;

export async function shareFiles(app: App, paths: string[]) {
  if (!paths.length) return;
  const n = std();
  if (n) {
    const r = await n.share(paths).catch((e) => ({ ok: false, error: String(e) }));
    if (r.ok) return;
  } else webRecord.shared.push(paths);
  openShareWindow(app, paths);
}

export function openShareWindow(app: App, paths: string[]) {
  const existing = document.querySelector('[data-window="share"]');
  if (existing) existing.remove();
  toolWindow("share", "Share", 380, 220, (body, w) => {
    const n = std();
    let msg: HTMLElement;
    const col = h("div", { class: "gs-share" },
      h("div", { class: "gs-files" }, ...paths.map((p) => h("div", { class: "gs-file", text: base(p), title: p }))),
      note("Paste the files into Mail, Teams or any other app, or open their folder and use Share there."),
      msg = h("div", { class: "gs-msg" }),
      h("div", { class: "drow" },
        flatButton("Copy Files", async () => { const ok = n ? await n.copyFiles(paths) : false; msg.textContent = ok ? "Files copied to the clipboard." : "Could not copy the files."; }, { symbol: "doc.on.doc" }),
        flatButton("Show in Explorer", () => { if (n) void n.reveal(paths[0]); else app.print(paths[0]); }, { symbol: "folder" }),
        spacer(),
        flatButton("Done", () => w.close(), { prominent: true })));
    body.append(col);
  });
}

export async function openFile(app: App, path: string) {
  const n = std();
  if (n) { if (!(await n.openFile(path))) app.print(`Cannot open ${path}.`); return; }
  webRecord.opened.push(path);
}
