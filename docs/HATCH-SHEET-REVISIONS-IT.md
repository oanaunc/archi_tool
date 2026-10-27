# Retini, titoli in tavola e revisioni — Mac 1.0.6 (build 14)

## Installazione

Chiudi l'app. Scarica Mac 1.0.6 da https://www.oanarinaldi.com/archi-tool.html, apri il DMG e trascina Oanarina Archi Tool in Applicazioni sostituendo la copia precedente. Avvia quella in Applicazioni e controlla versione e build in About. Richiede macOS 14 o successivo; include Apple silicon e Intel.

## Match proprietà dei retini

In 2D digita `MA` (oppure `MATCHPROP`), clicca **dentro il retino sorgente**, quindi dentro uno o più retini di destinazione. La modifica appare subito, anche prima di Invio. Premi Invio per terminare e ⌘Z per annullare il comando completo. Si trasferiscono motivo, scala, angolo, origine, colori e proprietà del gradiente; i contorni delle destinazioni restano i loro.

Se hai limitato in precedenza le proprietà da copiare, usa `MA`, scegli `Settings`, poi `All`, quindi seleziona sorgente e destinazioni. Clicca dentro l'area e non sulla linea del quadrato: il contorno è un oggetto distinto. La selezione funziona anche negli spazi fra le righe di un motivo poco fitto; i fori del retino restano esclusi.

## Scala dei quadrati con retino

Seleziona **contorno e retino insieme**, poi `SC` / `SCALE`, punto base e fattore. Anche la scala dai grip usa la correzione. Motivo e origine seguono il disegno e il retino resta visibile. Se usi Copy, il nuovo retino segue il nuovo contorno. Se trasformi soltanto il retino, viene scollegato dal contorno originale per evitare che il successivo aggiornamento lo riporti alla posizione precedente. I motivi molto densi restano visibili con un numero limitato di righe di anteprima/stampa.

## Togliere «piano primo» dalla tavola

Apri **Sheet → Customize Sheet…**.

- Per il nome sotto la viewport togli la spunta a **View titles / titoli delle viste**. Ora il controllo nasconde anche i titoli già inseriti come oggetti del foglio. Comando equivalente: `SHEETSTYLE Captions Hide`.
- Per una scritta 2D dentro la pianta, come **PIANTA PIANO PRIMO** sopra il disegno: in **Text from drawing on this sheet** scegli quel testo e premi **Hide Text on This Sheet**. Rimane nel disegno 2D e sugli altri fogli; sparisce da questa tavola e dai suoi PDF/SVG. Puoi ripristinarlo con **Show Text on This Sheet**. Comandi equivalenti: `SHEETTEXT ListModel`, poi `SHEETTEXT HideModel #ID` o `SHEETTEXT ShowModel #ID`, usando l'ID elencato.
- Per testo libero aggiunto direttamente al foglio usa **Free text on this sheet → Text → Delete Text**.

Il selettore del testo 2D elenca oggetti testo autonomi. Se la scritta fa parte di un blocco importato, apri il blocco con `BEDIT` e modifica il testo, poi `BCLOSE Save`; questa modifica riguarda tutti gli usi del blocco.

## Revisione nel cartiglio personalizzato

Un testo statico del cartiglio, per esempio «rev —», non è ancora un campo automatico. Non serve ridisegnare il cartiglio:

1. Aggiungi la revisione da **Sheet Set → Revisions**, oppure `SHEETREVISION "Descrizione" "NM"`.
2. In **Customize Sheet → Cartiglio drawing** scegli il tuo blocco.
3. In **Link custom cartiglio text**, scegli il testo da sostituire e **Revision code (A, B, 01…)**; premi **Link Selected Text**. Se il testo contiene anche «rev», la sostituzione riguarda tutto il testo: puoi tenere «rev» in un oggetto separato oppure scrivere `rev {revision}` con `BEDIT`.
4. Se desideri il conteggio numerico delle revisioni (0, 1, 2…), scegli invece **Number of revisions**: usa il campo `{revisionCount}`. Il codice `{revision}` e il conteggio sono due valori distinti.
5. Scegli **Cartiglio fields only** per togliere la tabella separata mantenendo i campi nel tuo cartiglio.

I campi funzionano anche nei blocchi annidati. Il comando `TBDESIGN Bind` elenca i testi del blocco, richiede il percorso mostrato (esempio `3/2`) e il campo `revision`, `revisionCount`, `revisionDate`, `revisionDescription` o `revisionBy`. Un blocco condiviso aggiorna tutti i fogli che lo usano; le revisioni visualizzate sono quelle del singolo foglio.

Salva con ⌘S. I collegamenti e le impostazioni si salvano nel file `.archi`; ogni modifica si può annullare con ⌘Z.

Le verifiche sono state svolte su documenti di prova e sul progetto di esempio. Il progetto originale della segnalazione non era disponibile.
