# SIGNING — progetto Xcode, firma, installazione e TestFlight

Autore: Agent 13 (Release) · Milestone M1 · Riferimenti: ADR-011, ARCHITECTURE_PLAN §1.3, rischio R11.

> **Nota di onestà.** Questa guida è stata scritta in un ambiente senza Xcode. I passaggi seguono
> la documentazione Apple e il comportamento noto di Xcode 16, ma la prima verifica reale avverrà
> sulla CI e sul tuo Mac. I punti marcati **[da verificare]** dipendono da regole Apple che cambiano:
> controllali su developer.apple.com prima di contarci.

---

## 1. Prerequisiti

| Cosa | Versione | Note |
|---|---|---|
| Mac con macOS recente | quello richiesto dalla tua versione di Xcode | |
| Xcode | 16 o successivo, con SDK iOS 18 | da Mac App Store o developer.apple.com/download |
| XcodeGen | 2.38 o successivo | `brew install xcodegen` |
| iPhone | iOS 18 o successivo | solo per installare sul dispositivo |
| Apple ID | gratuito o Apple Developer Program | vedi §4 |

## 2. Generare il progetto

Il file `JevFit.xcodeproj` **non è versionato**: lo genera XcodeGen da `project.yml`, insieme a
`App/Info.plist` e `App/JevFit.entitlements` (anche questi generati e ignorati da git).

```bash
cd jev-fit
xcodegen generate
open JevFit.xcodeproj
```

Rigenera il progetto ogni volta che:
- fai pull di modifiche a `project.yml`;
- aggiungi, sposti o rinomini file in `App/`, `AppTests/`, `AppUITests/`.

I file dentro `Packages/` non richiedono rigenerazione: sono package Swift e Xcode li legge direttamente.

Per cambiare permessi, Info.plist o entitlement si modifica **`project.yml`**, mai i file generati
(verrebbero sovrascritti alla generazione successiva).

## 3. Team e bundle id: `Config/Signing.local.xcconfig`

`project.yml` applica a livello di progetto `Config/Signing.xcconfig`, che contiene:

```
JEV_BUNDLE_ID = com.gianmarcogalvanini.jevfit
PRODUCT_BUNDLE_IDENTIFIER = $(JEV_BUNDLE_ID)
DEVELOPMENT_TEAM =
```

e in fondo include, se esiste, `Config/Signing.local.xcconfig` (ignorato da git). Per firmare
con il tuo account crea quel file:

```
// Config/Signing.local.xcconfig — personale, NON versionato
DEVELOPMENT_TEAM = ABCDE12345
// Facoltativo: un bundle id diverso (es. se quello di default è già registrato da un altro team)
// JEV_BUNDLE_ID = com.tuonome.jevfit
```

- Il **Team ID** (10 caratteri) si trova su developer.apple.com → Account → Membership details,
  oppure in Xcode → Settings → Accounts → seleziona il team.
- Per cambiare bundle id sovrascrivi **`JEV_BUNDLE_ID`**: i target di test ne derivano il loro
  (`<id>.tests`, `<id>.uitests`).
- Dopo aver creato o modificato il file non serve rigenerare: Xcode rilegge gli xcconfig.
  Se non vedi il cambiamento, chiudi e riapri il progetto.

Non selezionare il team dalla UI di Xcode (Signing & Capabilities): scriverebbe nel `.xcodeproj`
generato e la modifica sparirebbe alla prossima `xcodegen generate`.

## 4. Capability: HealthKit e Sign in with Apple

Gli entitlement sono dichiarati in `project.yml` (sezione `entitlements`):

| Entitlement | Valore | Usato da |
|---|---|---|
| `com.apple.developer.healthkit` | `true` | modulo `Health` (letture/scritture Salute) |
| `com.apple.developer.healthkit.access` | `[]` | nessun accesso a cartelle cliniche |
| `com.apple.developer.applesignin` | `[Default]` | account opzionale (ADR-006) |

Con la firma automatica, alla prima build su dispositivo Xcode registra l'App ID sul tuo team e
abilita le capability corrispondenti agli entitlement.

### Account gratuito vs Apple Developer Program

| | Apple ID gratuito ("Personal Team") | Apple Developer Program (a pagamento) |
|---|---|---|
| Installare sul proprio iPhone | sì | sì |
| Durata del provisioning | circa 7 giorni, poi va reinstallata **[da verificare]** | 1 anno |
| HealthKit | dovrebbe essere disponibile **[da verificare]** | sì |
| Sign in with Apple | **no**, per quanto noto: Xcode rifiuta la capability per i Personal Team **[da verificare]** | sì |
| TestFlight / App Store | no | sì |

Fonte da consultare: developer.apple.com → Help → "Supported capabilities (iOS)", che elenca le
capability disponibili per tipo di account. Se la tabella dice cose diverse da questa guida,
vale la tabella di Apple: aggiorna questo documento.

**Se usi un account gratuito** e la build fallisce per Sign in with Apple: in M1 l'app non usa
ancora l'accesso con Apple, quindi puoi rimuovere *in locale* le due righe
`com.apple.developer.applesignin` da `project.yml`, eseguire `xcodegen generate` e **non committare**
quella modifica (`git checkout project.yml` prima del commit). Dalla milestone che introduce
l'account servirà l'Apple Developer Program.

## 5. Installare JEV FIT sul tuo iPhone

1. Crea `Config/Signing.local.xcconfig` con il tuo `DEVELOPMENT_TEAM` (§3).
2. `xcodegen generate` e apri `JevFit.xcodeproj`.
3. Collega l'iPhone via cavo e sbloccalo; alla domanda "Autorizzare questo computer?" rispondi sì.
4. Sull'iPhone attiva la **Modalità sviluppatore**: Impostazioni → Privacy e sicurezza →
   Modalità sviluppatore → attiva e riavvia (l'opzione compare dopo il primo collegamento a Xcode).
5. In Xcode scegli lo scheme **JevFit** e il tuo iPhone come destinazione, poi Product → Run (⌘R).
6. Solo con account gratuito, al primo avvio: Impostazioni → Generali → VPN e gestione dispositivi →
   seleziona il tuo profilo sviluppatore → Autorizza.
7. HealthKit con permessi reali si verifica solo sul dispositivo (blocco ambiente n. 3 in PROJECT_STATE).

## 6. Build e test da riga di comando

Vedi anche la sezione "Build & test" del README.

```bash
UDID=$(scripts/ci/pick-simulator.sh)   # simulatore iPhone con iOS >= 18
xcodebuild -project JevFit.xcodeproj -scheme JevFit \
  -destination "id=$UDID" CODE_SIGNING_ALLOWED=NO test
```

La CI non firma mai (`CODE_SIGNING_ALLOWED=NO`, solo simulatore) e non contiene certificati né
segreti di firma. Una pipeline di distribuzione automatica (es. upload su TestFlight dalla CI)
richiederebbe chiavi App Store Connect come secret di GitHub: è fuori dallo scope di M1.

## 7. Checklist TestFlight

Prerequisito: **Apple Developer Program** attivo (abbonamento annuale a pagamento; prezzo e
condizioni su developer.apple.com).

**Una tantum**
- [ ] App ID `com.gianmarcogalvanini.jevfit` (o il tuo `JEV_BUNDLE_ID`) registrato con HealthKit e Sign in with Apple
      (con firma automatica lo crea Xcode; verificalo in Certificates, Identifiers & Profiles).
- [ ] App creata in App Store Connect con lo stesso bundle id, lingua principale Italiano.
- [ ] URL della privacy policy pubblicato (necessario per app che usano HealthKit) **[da verificare: requisiti correnti]**.
- [ ] Questionario "Privacy dell'app" in App Store Connect compilato in modo coerente con
      `App/PrivacyInfo.xcprivacy` e con `docs/SECURITY.md` (Agent 12).
- [ ] Verifica della guideline App Review 5.1.3 (dati HealthKit e servizi AI) — domanda aperta n. 8 di PROJECT_STATE.

**A ogni build caricata**
- [ ] **Icona dell'app**: oggi `AppIcon` è vuota (solo `Contents.json`). App Store Connect rifiuta
      l'upload senza icona 1024×1024: va aggiunta prima del primo invio.
- [ ] `App/PrivacyInfo.xcprivacy` presente e aggiornato (incluso come risorsa da `project.yml`).
- [ ] `CURRENT_PROJECT_VERSION` incrementato (ogni upload richiede un numero di build nuovo);
      `MARKETING_VERSION` aggiornato quando cambia la versione visibile. Entrambi in `project.yml`.
- [ ] CI verde sul commit da distribuire.
- [ ] Testi dei permessi (Salute, fotocamera) riletti in `project.yml`: devono descrivere l'uso reale.
- [ ] `ITSAppUsesNonExemptEncryption = false` ancora corretto (nessuna crittografia oltre a quella di sistema).
- [ ] Product → Archive (configurazione Release) → Distribute App → App Store Connect → Upload.
- [ ] In App Store Connect → TestFlight: attendere l'elaborazione, compilare "What to Test".
- [ ] Tester interni (membri del team App Store Connect): disponibile subito.
      Tester esterni: richiede la Beta App Review di Apple.
- [ ] Test manuale su iPhone fisico della checklist dispositivo (HealthKit con permessi reali).
