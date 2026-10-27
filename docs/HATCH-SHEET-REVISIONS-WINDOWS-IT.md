# Retini, titoli e revisioni — Windows 1.0.7 (build 15)

Scarica il nuovo installer Windows da https://www.oanarinaldi.com/archi-tool.html, chiudi l'app ed esegui il file .exe per aggiornare la versione precedente. Questa versione include le correzioni condivise con Mac 1.0.6 e completa i percorsi specifici di selezione e scala dai grip su Windows.

I comandi si digitano nella riga in basso. Alcuni nuovi controlli del pannello Mac non hanno ancora lo stesso pulsante su Windows: usa questi comandi.

- **Match proprietà:** `MA`, clic dentro il retino sorgente, poi nelle destinazioni, anche fra le righe; Invio termina. Le proprietà cambiano subito. Se necessario scegli Settings → All prima della sorgente. Clicca dentro l'area, non sul contorno.
- **Scala:** seleziona contorno e retino insieme; `SC` / `SCALE`, punto base e fattore. Anche i grip conservano l'origine del motivo e i retini copiati seguono il nuovo contorno.
- **Titolo sotto la viewport:** attiva il foglio e digita `SHEETSTYLE Captions Hide`. `SHEETSTYLE Captions Show` lo ripristina. Vale sia per didascalie generate sia per titoli già inseriti.
- **Testo 2D come PIANTA PIANO PRIMO:** sul foglio, `SHEETTEXT ListModel` elenca i testi e i loro ID. `SHEETTEXT HideModel #ID` nasconde quel testo soltanto nella tavola e nei suoi PDF/SVG. `SHEETTEXT ShowModel #ID` lo ripristina. Il disegno e gli altri fogli lo conservano. Un testo dentro un blocco si modifica con `BEDIT` / `BCLOSE Save`.
- **Revisione nel tuo cartiglio:** aggiungi la revisione con `SHEETREVISION "Descrizione" "NM"`. `TBDESIGN Bind` chiede il nome del blocco, elenca i testi, poi chiede il percorso mostrato (esempio `3/2` per un testo annidato) e il campo: `revision` per il codice A/B/01, `revisionCount` per il numero di revisioni, oppure `revisionDate`, `revisionDescription`, `revisionBy`. Il collegamento sostituisce tutto il testo scelto; per mantenere la parola “rev” scrivi `rev {revision}` con BEDIT. Un blocco condiviso aggiorna tutti i fogli che lo usano, ciascuno con le proprie revisioni.
- **Solo i campi nel cartiglio:** `SHEETREVTABLE Fields 180 5` nasconde la tabella separata lasciando aggiornati i campi.

Salva con Ctrl+S e annulla con Ctrl+Z. Tutte le impostazioni si conservano nel file .archi. Il video Mac spiega gli stessi concetti; i pulsanti e le scorciatoie di sistema possono differire.
