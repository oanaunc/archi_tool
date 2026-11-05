# Quote e riferimenti delle porte — 1.0.8

Le voci dell’interfaccia sono in inglese. Scarica la versione 1.0.8 per Mac o Windows da https://www.oanarinaldi.com/archi-tool.html.

## Correggere una scritta

Seleziona l’etichetta della porta e modifica **Content** in **Properties**, oppure fai doppio clic sulla scritta e premi **Apply**. Il valore inserito, per esempio `900x2100`, viene ora mostrato nel disegno e nell’esportazione. La modifica si conserva salvando e riaprendo il progetto e si può annullare.

Questa operazione cambia la scritta. Per cambiare la dimensione effettiva della porta, seleziona la porta e modifica **Width** e **Height**. Le etichette automatiche seguono queste dimensioni. Per ripristinare l’automatismo dopo una modifica manuale, imposta **Label Mode** su `Automatic` in Properties, oppure usa `TAGLABEL`, seleziona le etichette, premi Invio e scegli `Automatic`.

## Mostrare solo D1, D2, D3

1. Digita `TAGLABEL` nella riga di comando.
2. Seleziona le etichette che mostrano le misure e premi Invio per concludere la selezione.
3. Scegli `Field` e digita `mark`.
4. I cerchi esistenti mostreranno il riferimento della porta. Per avere esattamente D1, D2, D3, seleziona ciascuna porta e scrivi il riferimento nel campo **Mark** di **Properties**; in alternativa usa `MARKS Set` e seleziona la porta.

Per assegnare tutti i riferimenti in ordine di lettura puoi usare `MARKS Renumber No`: il formato automatico è D01, D02, D03. Per aggiungere riferimenti dove mancano usa **Annotate → Tag All**, oppure `TAGALL Doors`. La presenza delle quote non impedisce più l’aggiunta dei riferimenti.

Su Mac salva con Cmd+S e annulla con Cmd+Z. Su Windows usa Ctrl+S e Ctrl+Z.
