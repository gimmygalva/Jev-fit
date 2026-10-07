# Checklist HealthKit su iPhone fisico (M7)

HealthKit si verifica davvero solo su un iPhone (rischio R3). La CI copre la logica con la
sorgente simulata (`MockHealthDataSource`): permessi concessi, negati, parziali, Salute assente.
Questa checklist serve per la parte che solo tu puoi verificare. Segna ogni riga e riporta
l'esito in `PROJECT_STATE.md`.

## Preparazione
- [ ] Build firmata sul tuo iPhone (vedi `docs/SIGNING.md`), capability HealthKit attiva sull'App ID.
- [ ] In Salute ci sono almeno alcune pesate, passi e (se hai un Watch) sonno, FC a riposo e HRV.

## 1. Permessi concessi
- [ ] Completa l'onboarding: al termine compare il foglio di sistema di Salute.
- [ ] Attiva tutte le categorie e conferma.
- [ ] Entro pochi secondi le pesate degli ultimi 30 giorni sono importate (una sola volta per pesata).
- [ ] Chiudi e riapri l'app: nessuna pesata duplicata.

## 2. Permessi negati
- [ ] Elimina l'app, reinstallala, completa l'onboarding e nel foglio di Salute non attivare nulla.
- [ ] L'app funziona normalmente; nessun errore, nessun dato importato.
- [ ] Inserimento manuale del peso disponibile (arriva con M9/M10).

## 3. Permessi parziali
- [ ] Reinstalla e concedi solo "Peso" e "Passi".
- [ ] Importate solo pesate e passi; sonno, FC e HRV restano assenti (nessun valore inventato).

## 4. Revoca successiva
- [ ] Impostazioni → Salute → Accesso ai dati → JEV FIT: disattiva tutto.
- [ ] Riapri l'app: nessun crash; i dati già importati restano finché non li elimini.

## 5. Scrittura (quando l'interruttore sarà in Impostazioni, M10)
- [ ] Con la scrittura delle pesate attiva, una pesata inserita in JEV FIT compare in Salute.
- [ ] Al successivo import quella pesata NON viene reimportata come nuova.

## Note tecniche
- HealthKit non rivela se la lettura è stata negata: un tipo negato appare vuoto. L'app tratta
  "nessun campione" come dato mancante, mai come zero.
- Sonno, FC a riposo e HRV restano in una cache locale esclusa dal backup (ADR-012) e non sono
  mai sincronizzati né inviati all'AI.
- Simulatore e test UI usano la sorgente simulata (`-jev-in-memory-store` o `-jev-mock-health`):
  il foglio dei permessi di sistema non compare mai nei test automatici.
