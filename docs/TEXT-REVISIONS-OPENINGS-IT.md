# Testi, revisioni e misure automatiche — Mac 1.0.5

Prima installa la versione **1.0.5, build 12**: chiudi l'app, scarica il nuovo DMG da https://www.oanarinaldi.com/archi-tool.html e trascina l'app in Applicazioni, sostituendo la vecchia copia. Apri quella in Applicazioni e verifica la versione in About.

## Salvare testo, altezza e font

Fai doppio clic sul testo del disegno. Scegli font e altezza nella prima riga; premi **Apply** nella seconda riga per applicare e chiudere. Sono accettate anche altezze con virgola, per esempio `325,5`. **Cancel** o Esc annullano. Per il testo su più righe puoi usare Cmd+Invio; per il testo su una riga anche Invio.

**Cmd+S salva il progetto anche se la modifica del testo è ancora aperta**, includendo testo, font e altezza. Cmd+Z annulla una modifica applicata. Per modificare le scritte dentro il disegno di un cartiglio personalizzato, aprilo con **Redesign Cartiglio Drawing**, modifica i testi, poi digita `BCLOSE Save` e torna a Sheet.

## Revisione direttamente nel cartiglio

1. Nel pannello **Sheets**, seleziona il foglio. In **Revisions**, inserisci Description e By e premi **Add**. Il campo Revision del cartiglio si aggiorna automaticamente.
2. Apri **Customize Sheet → Revision history / revisioni → Placement**.
3. Scegli **Cartiglio fields only** se vuoi la revisione nel cartiglio senza la tabella separata. Il comando equivalente è `SHEETREVTABLE Fields 180 5`.
4. **Inside cartiglio** aggiunge la cronologia in una fascia sotto i campi del cartiglio standard; **Above cartiglio** mantiene la disposizione precedente. In un cartiglio disegnato da te, Inside usa la zona inferiore: lascia lo spazio necessario oppure usa i campi automatici.
5. Puoi regolare larghezza e altezza delle righe e premere **Apply Revision Table Size**. Per spostare la tabella separatamente: **Move element → Revision history table → ΔX / ΔY → Apply Element Offset**. La relativa spunta nasconde la tabella senza cancellare le revisioni.

## Usare il tuo cartiglio

In **Customize Sheet → Cartiglio drawing**, scegli un blocco del tuo progetto, anche importato da DXF. Il disegno usa millimetri del foglio e il suo punto base va nell'angolo inferiore destro della cornice: disegna verso sinistra e verso l'alto. **Redesign Cartiglio Drawing** permette di modificare linee, testi, font e immagini; concludi con `BCLOSE Save`.

Per inserire automaticamente i dati usa testi con questi segnaposto:

| Campo | Segnaposto |
| --- | --- |
| Codice revisione attuale | `{revision}` |
| Data della revisione attuale | `{revisionDate}` |
| Descrizione | `{revisionDescription}` |
| Autore | `{revisionBy}` |
| Prima riga di cronologia | `{revision.1.code}`, `{revision.1.date}`, `{revision.1.description}`, `{revision.1.by}` |

Per le righe successive cambia 1 in 2, 3, ecc. La cronologia parte dalla revisione più vecchia. Puoi scegliere liberamente posizione, dimensione e font di ogni testo. I blocchi condivisi aggiornano tutti i fogli che li usano. Con **Cartiglio fields only** non viene aggiunta nessuna tabella automatica separata.

## Misure automatiche di porte e finestre

Apri il piano desiderato in **2D**, poi **Annotate → Door / Window Sizes**, oppure digita **QUOTAINFISSI** nella riga di comando.

Per gli infissi già presenti digita:

```
QUOTAINFISSI All Centimetres 180
```

Il comando aggiunge larghezza × altezza di tutte le porte e finestre BIM del piano corrente: per esempio **90×210 cm**. `Doors` limita alle porte e `Windows` alle finestre. Puoi scegliere `Millimetres`, `Centimetres`, `Metres` oppure `Drawing`. 180 è l'altezza del testo nelle unità del disegno: se lavori in mm, a scala 1:100 corrisponde a 1,8 mm sulla carta. Aumentala, per esempio a 250, se vuoi scritte più grandi.

Per etichettare automaticamente anche i nuovi infissi:

```
QUOTAINFISSI Automatic Centimetres 180
```

Per disattivare l'inserimento sulle nuove porte e finestre, mantenendo le etichette esistenti: `QUOTAINFISSI Off`.

Le misure seguono le modifiche alle dimensioni degli infissi, si vedono anche nei fogli e nel PDF e si salvano nel progetto. Ripetere il comando aggiorna le etichette senza duplicarle; le sigle già presenti restano. Puoi spostare le etichette con MOVE. Le misure automatiche richiedono elementi BIM porta/finestra: semplici linee o blocchi di un DXF 2D vanno quotati con i normali strumenti di misura, oppure trasformati in un modello BIM.
