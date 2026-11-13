# Porte e cartellini nei disegni in centimetri — 1.0.9

1. Verifica che in **Drawing Units** sia selezionato **Centimeters**. Se il disegno è già in cm, non serve cambiarne le unità o riscalarlo.
2. Per una porta nuova, digita `DOOR`. Se il comando mostra ancora le vecchie misure memorizzate, scegli **ReSet**: la porta torna a 90 × 210 cm. Per una misura diversa, scegli **Width** (larghezza) o **Height** (altezza), inserisci il valore in cm e clicca sul muro. Puoi scrivere anche `900mm` o `2.1m` con l'unità esplicita.
3. Per una porta già inserita, seleziona la porta, apri **Properties** e correggi **Width**, **Height** e, se necessario, **Frame Width**. Per una porta standard in un disegno in cm, i valori sono 90, 210 e 5.
4. Per aggiornare le quote esistenti al piano corrente, digita `QUOTAINFISSI Doors Centimetres 10`: una porta standard mostra **90×210 cm**, con altezza testo di 10 cm nel disegno. Il comando ripristina le misure automatiche delle quote modificate a mano. Per impostarle anche sulle prossime porte e finestre, usa `QUOTAINFISSI Automatic Centimetres 10`.
5. Se il cartellino grande è un riferimento (ad esempio **D01**), seleziona il cartellino e imposta **Height** a 10 in **Properties**. Il riferimento resta collegato alla porta.
