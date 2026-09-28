// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Schedule sheet (MainWindow.swift ScheduleSheet): a kind picker (walls, doors, windows, rooms, slabs, all), the
// schedule table from the engine (schedule.get = ScheduleExporter.table), the row count, and Export CSV… (the same
// file.export csv:<kind> as Output ▸ Schedules ▸ CSV) plus Export XLSX… (xlsx:<kind>). Close dismisses it.
import type { App } from "../app";
import { h, clear } from "../dom";
import { sheet, picker, flatButton, spacer } from "../dialogs/ui";

const titleCase = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

export async function openSchedule(app: App, kind = "all") {
  let cur = kind.toLowerCase();
  const kinds: string[] = ["walls", "doors", "windows", "rooms", "slabs", "all"];
  const grid = h("div", { class: "dt-sched-grid" });
  const count = h("div", { class: "dt-small" });
  const empty = h("div", { class: "dt-sched-empty", text: "No data for this schedule yet." });
  const table = h("div", { class: "dt-sched-scroll" }, grid);
  const holder = h("div", { class: "dt-sched-holder" });
  const load = async () => {
    const d = await app.tryCall("schedule.get", { kind: cur });
    const rows: string[][] = (d?.rows ?? []).filter((r: string[]) => r.some((c) => c !== ""));
    clear(grid); clear(holder);
    if (!rows.length) { holder.append(empty); return; }
    const cols = Math.max(...rows.map((r) => r.length));
    grid.style.gridTemplateColumns = `repeat(${cols}, auto)`;
    rows.forEach((r, i) => {
      for (let c = 0; c < cols; c++) grid.append(h("div", { class: "cell" + (i === 0 ? " head" : ""), text: r[c] ?? "" }));
      if (i === 0) grid.append(h("div", { class: "rule", style: { gridColumn: `1 / span ${cols}` } }));
    });
    count.textContent = `${rows.length - 1} row(s)`;
    holder.append(table, count);
  };
  const exportAs = (fmt: "csv" | "xlsx") => app.exportAs(`${fmt}:${cur}`);
  const top = h("div", { class: "dt-sched-top" },
    h("span", { class: "dt-label", text: "Schedule" }),
    picker(kinds.map((k) => ({ value: k, title: titleCase(k) })), cur, (v) => { cur = v; void load(); }, { width: 160 }),
    spacer(),
    flatButton("Export CSV…", () => void exportAs("csv"), { symbol: "square.and.arrow.up" }),
    flatButton("Export XLSX…", () => void exportAs("xlsx"), { symbol: "tablecells", help: "The schedule as an Excel workbook (SCHEDULE Export writes the same file)" }));
  const content = h("div", { class: "dt-sched" }, top, holder);
  await load();
  return sheet({ title: "Schedule", width: 720, content, okTitle: "Close", onOK: () => {} , cls: "dt-schedule" });
}
