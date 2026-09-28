// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiSpell: the Chromium spell checker (on Windows it uses the Windows spell-checking service and the user's
// languages) for the Spelling dialog (doctools/spelling.ts), as NSSpellChecker is on the Mac. The main window enables
// the checker (webPreferences.spellcheck) and the renderer turns the red underlines off for its own fields.
import { contextBridge, webFrame } from "electron";

contextBridge.exposeInMainWorld("archiSpell", {
  isMisspelled: (word: string) => { try { return webFrame.isWordMisspelled(word); } catch { return false; } },
  suggestions: (word: string) => { try { return webFrame.getWordSuggestions(word); } catch { return []; } },
});
