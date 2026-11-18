# Tag di porte e finestre — 1.0.11 (build 21)

Chiudi l'app, scarica l'aggiornamento da [Oanarina Archi Tool](https://www.oanarinaldi.com/archi-tool.html) e installalo. Su Mac sostituisci l'app in Applicazioni; su Windows esegui il nuovo installer. Riapri il progetto e il piano interessato.

## Aggiungere le misure mancanti

Apri **Annotate → Door / Window Sizes**, oppure digita `QUOTAINFISSI`. Scegli **All**, l'unità e l'altezza del testo. La ricerca comprende anche gli infissi visibili nei muri che attraversano più piani; i tag di un altro piano non impediscono di creare quelli del piano aperto.

Per riportare accanto agli infissi anche i tag finiti lontano, in un disegno in centimetri digita:

```
QUOTAINFISSI Reposition Centimetres 10
```

**Reposition** riposiziona i tag delle misure di porte e finestre sul piano aperto e aggiunge quelli mancanti. **All**, **Doors** e **Windows** conservano invece le posizioni manuali. Il testo torna alle misure effettive dell'infisso. Assicurati che il layer **A-ANNO-TAGS** sia acceso e scongelato.

## Correggere un tag copiato

Apri **Tag Label**, seleziona il tag, premi Invio per terminare la selezione, scegli **Rehost** e clicca la porta o finestra corretta. In alternativa digita `TAGLABEL` e segui gli stessi passaggi. Il tag mantiene posizione e formattazione e legge le misure dell'infisso appena scelto. Un eventuale testo manuale viene sostituito dalle misure automatiche.

Copiando insieme un infisso e il suo tag, il nuovo tag si collega al nuovo infisso. Lo stesso vale per la copia di un muro con infissi e tag selezionati. Copiando solo un tag nello stesso disegno, il collegamento cambia automaticamente quando il punto iniziale della sua linea di richiamo, spostato con la copia, coincide entro 10 cm con un solo altro infisso della stessa categoria sul piano corrente. Se la destinazione è ambigua o lontana, usa **Rehost** per indicarla esplicitamente.

Le modifiche si possono annullare con **Undo**. Salva infine il progetto con **Cmd+S** su Mac o **Ctrl+S** su Windows. I file `.archi` restano nel formato 6.
