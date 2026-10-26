# Personalizzare lo sheet — Mac 1.0.4

Prima di iniziare, chiudi Oanarina Archi Tool. Scarica **la versione Mac 1.0.4** da https://www.oanarinaldi.com/archi-tool.html, apri il DMG e trascina l'app in **Applicazioni**, sostituendo la vecchia copia. Avvia la copia in Applicazioni e verifica la versione in **About Oanarina Archi Tool**. Il download è universale per Mac Intel e Apple silicon e richiede macOS 14 o successivo.

Apri il progetto, passa a **Sheet** e seleziona il foglio. Il pulsante **Customize Sheet…**, sotto la barra del foglio, apre i controlli di personalizzazione. Le modifiche riguardano solo il foglio attivo, si annullano con **⌘Z** e vengono conservate con **Save / ⌘S**.

## Planimetria e centratura

Scegli la viewport nel pannello. Se è bloccata, disattiva **Lock viewport** prima di modificarla.

- **Centre Content (keep scale)** centra la planimetria nella viewport mantenendo la scala impostata.
- **Centre Frame on Page** centra la cornice della viewport sulla pagina intera. Puoi poi adattarne la posizione per lasciare spazio al cartiglio.
- **X mm / Y mm → Apply Position** sposta la cornice con precisione sul foglio. L'origine è l'angolo inferiore sinistro della pagina; +X va a destra, +Y in alto. Puoi anche trascinare la viewport con il mouse.
- **Width mm / Height mm → Apply Size** cambia la dimensione della cornice senza cambiare scala.
- **Scale 1: → Apply Scale (keep frame)** imposta la scala di stampa (ad esempio 100 per 1:100), mantenendo posizione e dimensioni della cornice.
- **Centre X / Centre Y → Apply Model Centre** permette di scegliere esattamente il punto del modello al centro della viewport, nelle unità del disegno.
- **Fit Content (changes scale)** centra e ridimensiona il contenuto per farlo entrare nella cornice; cambia la scala. Dopo questa operazione, imposta di nuovo la scala richiesta se ti serve una scala convenzionale.

Se la viewport è vuota, controlla il livello visualizzato e la visibilità / proprietà Plot dei layer.

## Cartiglio in basso a destra

Premi **Edit Title Block…** oppure **Title Block** nella barra del foglio. Puoi modificare i campi del progetto (nome, numero, cliente, indirizzo, autore), il logo e i campi del singolo foglio (studio, titolo, numero, scala, data e revisione). **Office / studio** sostituisce la scritta OANARINA ARCHI TOOL nel cartiglio standard. Premi **OK** per confermare. Un campo vuoto usa il valore automatico mostrato in grigio.

In **Customize Sheet**, la spunta **Title block / cartiglio** mostra o nasconde il cartiglio standard o personalizzato, comprese le sue righe di revisione. Per spostarlo scegli **Move element → Title block / cartiglio**, inserisci **ΔX mm / ΔY mm**, quindi premi **Apply Element Offset**. Gli offset partono dalla posizione predefinita: -20,5 significa 20 mm a sinistra e 5 mm in alto.

Per ridisegnare anche linee, impaginazione ed etichette del cartiglio, premi **Redesign Cartiglio Drawing…** in Customize Sheet: viene preparato un blocco per questo foglio, aperto in 2D. Modifica linee, testi e immagini con gli strumenti normali; termina con **BCLOSE Save** e torna a Sheet. Se il blocco era già condiviso, le modifiche si vedono su ogni foglio che lo usa. In alternativa, usa il comando **TITLEBLOCKDESIGN**: **Create** prepara un blocco modificabile con **BEDIT**; **Use** lo applica al foglio; **Builtin** ripristina il cartiglio standard. I testi `{project}`, `{sheetName}`, `{sheetNumber}` ecc. usano i valori del progetto/foglio.

## Nord, scala grafica e bordo

Disattiva **North arrow / Nord** per eliminare l'indicatore automatico del Nord da questo foglio. Le spunte **Scale bar**, **Page border** e **Automatic view captions** controllano separatamente scala grafica, bordo e didascalie automatiche. Nord e scala grafica si possono anche spostare con **Move element** e gli offset.

Questi controlli riguardano gli elementi automatici. Un simbolo del Nord disegnato manualmente o contenuto nel modello resta un oggetto del disegno da modificare o eliminare nel modello. Le didascalie convertite in entità modificabili con SHEETVIEWTITLES si gestiscono come entità del foglio.

## Testo libero al posto del Nord, o in qualsiasi punto del foglio

In **Customize Sheet → Free text on this sheet**, lascia **New text**, scrivi quello che vuoi (anche su più righe), imposta **Text X mm**, **Text Y mm** e **Height mm**, poi premi **Add Sheet Text**. Per esempio, su un A3 il Nord standard è vicino a X=195, Y=30: puoi nasconderlo e inserire lì la tua nota, cambiando le coordinate a piacere.

Per modificare il testo, selezionalo dal menu **Text**, cambia contenuto/posizione/altezza e premi **Update Sheet Text**. **Delete Text** lo elimina. Tutto si salva nel progetto, viene esportato nel PDF e si può annullare con ⌘Z. Il testo resta sul foglio anche quando sposti o cambi scala alla planimetria.

## Salvataggio e PDF

Salva una copia del progetto con **SAVEAS**, poi usa **PDF / PLOT** per esportare il foglio. Visibilità e posizioni personalizzate valgono anche nel PDF e nella stampa. Per stampare un PDF alla scala prevista, usa dimensione reale / 100% nel programma di stampa.

Gli stessi controlli sono disponibili dalla riga di comando e dall'API di scripting/agente:

```text
VPEDIT 1 CenterContent
VPEDIT 1 Position 55,75
VPEDIT 1 Size 280,180
VPEDIT 1 Scale 1:100
VPEDIT 1 CenterOnSheet
SHEETSTYLE North Hide
SHEETTEXT Add 195,30 3 "Qualsiasi testo"
SHEETSTYLE TitleBlock Move -20,5
SHEETSTYLE ScaleBar Hide
SHEETSTYLE North Reset
```

`VPEDIT` ha l'alias `VPE`; `SHEETSTYLE` ha gli alias `SHTSTYLE` e `SHEETCUSTOMIZE`. Il numero 1 indica la prima viewport del foglio.
