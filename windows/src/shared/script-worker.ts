// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Script worker: one JavaScript context per document window (the Mac keeps one JSContext per window), running the
// archi API of script-runtime.ts. Works as a Node worker thread (Electron main process: console, plugins, agents'
// eval_js) and as a browser Web Worker (the renderer served as a web page for tests).
import { ScriptRuntime, syncCall } from "./script-runtime";

declare const require: any;
let post: (m: any) => void = () => {};
let sab: SharedArrayBuffer | null = null;
let rt: ScriptRuntime | null = null;

function runtime(): ScriptRuntime {
  if (rt) return rt;
  rt = new ScriptRuntime({
    call: (method, params) => {
      if (!sab) throw { code: -32000, message: "The script channel is not ready." };
      return syncCall(sab, post, method, params);
    },
    emit: (line) => post({ type: "line", text: line }),
    panel: (spec) => post({ type: "panel", spec }),
    hooks: (events) => post({ type: "hooks", events }),
  });
  return rt;
}

function onMessage(m: any) {
  switch (m?.type) {
    case "init": sab = m.sab; post({ type: "ready" }); break;
    case "eval": {
      const r = runtime().evaluate(String(m.code ?? ""), m.name || "console.js");
      post({ type: "result", id: m.id, ...r });
      break;
    }
    case "fire": {
      for (const [e, a] of m.events ?? []) runtime().fire(e, a);
      post({ type: "fired", id: m.id });
      break;
    }
    case "callGlobal": runtime().callGlobal(String(m.name), m.arg); post({ type: "fired", id: m.id }); break;
  }
}

let isNode = false;
try { const proc = (globalThis as any).process; isNode = !!proc?.versions?.node && typeof (globalThis as any).window === "undefined" && typeof (globalThis as any).importScripts !== "function"; } catch { isNode = false; }
if (isNode) {
  const wt = require("node:worker_threads");
  post = (m) => wt.parentPort.postMessage(m);
  if (wt.workerData?.sab) sab = wt.workerData.sab;
  wt.parentPort.on("message", onMessage);
} else {
  const g: any = globalThis;
  post = (m) => g.postMessage(m);
  g.onmessage = (e: MessageEvent) => onMessage(e.data);
}
