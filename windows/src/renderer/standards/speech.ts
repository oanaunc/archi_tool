// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// SPEAKDRAWING (A11y.announce): the description is spoken with the Windows voices (speech synthesis) and posted to a
// live region, so Narrator reads it too when it is running.
import { webRecord } from "./native";

let region: HTMLElement | null = null;
export function announce(text: string) {
  if (!region) {
    region = document.createElement("div");
    region.setAttribute("aria-live", "assertive");
    region.setAttribute("role", "status");
    region.className = "gs-live";
    document.body.append(region);
  }
  region.textContent = "";
  setTimeout(() => { if (region) region.textContent = text; }, 30);
}

export function speak(text: string) {
  if (!text) return;
  webRecord.spoken.push(text);
  announce(text);
  try {
    const s = window.speechSynthesis;
    if (!s) return;
    s.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = document.documentElement.lang || "en-US";
    s.speak(u);
  } catch { /* no voices */ }
}
