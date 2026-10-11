# INSTALL — JEV FIT sul tuo iPhone senza Apple Developer Program

Per uso personale su un solo iPhone basta un **Apple ID gratuito**. Il progetto è già configurato
così di default: `Config/Entitlements/Personal.entitlements` (solo HealthKit) e
`JEV_ACCOUNT_ENABLED = NO` (vedi `docs/SIGNING.md` §4).

## Cosa funziona e cosa no

| | Apple ID gratuito |
|---|---|
| Onboarding, allenamenti, progressive overload, recupero | sì |
| Diario alimentare, calorie e macro, trend del peso, dispendio stimato | sì |
| Check-in settimanale, JEV con testi offline (template) | sì |
| HealthKit (peso, passi, sonno, frequenza…) | dovrebbe funzionare **[da verificare sul tuo iPhone]** |
| Account con Apple, sync nel cloud, JEV online | **no**: Sign in with Apple non è disponibile per i Personal Team |
| Durata | circa **7 giorni**, poi va rifirmata. I dati restano: rifirmare non cancella l'app |
| Limiti Apple | massimo 3 app firmate con account gratuito installate insieme |

I dati stanno tutti sul telefono (database locale). Se l'app scade, non si apre finché non la
rifirmi; non la eliminare, altrimenti perdi i dati.

## Strada A — hai un Mac

1. Installa Xcode (Mac App Store) e XcodeGen (`brew install xcodegen`).
2. Xcode → Settings → Accounts → **+** → Apple ID: accedi con il tuo Apple ID. Comparirà un team
   "Tuo Nome (Personal Team)": selezionalo e copia il **Team ID**.
3. Crea `Config/Signing.local.xcconfig`:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   // Se Xcode dice che il bundle id non è disponibile, usane uno tuo:
   // JEV_BUNDLE_ID = com.tuonome.jevfit
   ```
4. `xcodegen generate && open JevFit.xcodeproj`.
5. Collega l'iPhone via cavo, scegli lo scheme **JevFit** e il tuo iPhone, poi **⌘R**.
6. Sull'iPhone, la prima volta:
   - Impostazioni → Privacy e sicurezza → **Modalità sviluppatore** → attiva e riavvia;
   - Impostazioni → Generali → **VPN e gestione dispositivi** → il tuo Apple ID → **Autorizza**.
7. Ogni circa 7 giorni ripeti il punto 5 (⌘R): l'app viene aggiornata e i dati restano.

## Strada B — non hai un Mac (Windows o Mac, senza Xcode)

La CI costruisce l'app a ogni push (workflow **IPA**, `.github/workflows/ipa.yml`) e pubblica il
file `JevFit.ipa` non firmato per il tuo account. Lo firmi tu con il tuo Apple ID usando
**Sideloadly** (gratuito, Windows e macOS).

1. Scarica l'IPA: GitHub → repository → **Actions** → workflow **IPA** → l'ultima esecuzione
   verde → sezione *Artifacts* → **JevFit-ipa** (serve essere loggati su GitHub). Estrai lo zip:
   dentro c'è `JevFit.ipa`. Gli artifact restano disponibili 30 giorni.
2. Installa Sideloadly da sideloadly.io. Su Windows serve anche iTunes e iCloud **nella versione
   scaricata dal sito Apple**, non quella del Microsoft Store **[da verificare sul sito di Sideloadly]**.
3. Collega l'iPhone via cavo e sbloccalo (alla domanda "Autorizzare questo computer?" rispondi sì).
4. In Sideloadly: trascina `JevFit.ipa`, inserisci il tuo Apple ID e premi **Start**. La password
   va solo ad Apple; se vuoi più tranquillità usa un Apple ID secondario creato apposta.
5. Sull'iPhone fai gli stessi due passaggi della Strada A, punto 6.
6. Ogni circa 7 giorni ripeti il punto 4 con lo **stesso** Apple ID e lo **stesso** bundle id: l'app
   viene aggiornata e i dati restano. Sideloadly può anche rifirmare in automatico se il PC è
   acceso e l'iPhone sulla stessa rete Wi-Fi (opzione "auto-refresh").

In alternativa a Sideloadly puoi usare **AltStore** (altstore.io): AltServer sul PC e AltStore
sull'iPhone, che rinnova la firma via Wi-Fi quando il PC è acceso.

**HealthKit con la Strada B.** L'IPA contiene l'entitlement HealthKit. Sideloadly crea il profilo
con le capability del tuo account gratuito: se HealthKit non viene incluso, l'app funziona lo stesso
ma la schermata Salute dirà che i dati non sono disponibili, e peso e passi vanno inseriti a mano.
Per HealthKit la strada più sicura resta la A (Xcode). **[da verificare sul dispositivo:
`docs/HEALTHKIT_CHECKLIST.md`]**

## Se un giorno passi all'Apple Developer Program

In `Config/Signing.local.xcconfig` aggiungi:
```
JEV_ENTITLEMENTS = Config/Entitlements/Developer.entitlements
JEV_ACCOUNT_ENABLED = YES
```
Poi segui `docs/BACKEND.md` (provider Apple su Supabase, deploy delle Edge Function) e
`docs/SIGNING.md` §7 per TestFlight.
