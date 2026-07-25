# Appskrifter

Flutter + Firebase-app for middagsoppskrifter og handlelister for husholdninger.

> **Status: i produksjon (i liten skala).** Koblet til det virkelige Firebase-prosjektet
> `appskrifter`, alt manuelt testet og fungerer (innlogging, husholdning, oppskrifter,
> middagsplan, handleliste, admin-godkjenning). Web-appen er publisert på
> **https://appskrifter.web.app**. Android kjører foreløpig kun via `flutter run` (debug-signert;
> se «Firebase-oppsett» for hva som gjenstår før et release-bygg/Play Store).

## Konsept

Appen har et globalt, kuratert sett med middagsoppskrifter som alle husholdninger har tilgang
til, i tillegg til at hver husholdning kan ha egne private oppskrifter. Brukeren velger ut et
sett med middager (fra globalt og/eller eget sett) som det skal handles til. For hver middag
kan man justere antall personer (standard hentes fra innstillinger, men kan overstyres per
middag, f.eks. ved besøk). Ut fra den valgte planen genererer appen en samlet handleliste,
sortert etter varekategori.

## Kjernefunksjonalitet

### Oppskrifter
- **Globalt sett**: kuratert samling av oppskrifter, tilgjengelig for alle husholdninger.
- **Husholdningens eget sett**: enhver bruker kan opprette oppskrifter som kun er synlige for
  egen husholdning.
- **Foreslå til globalt sett**: en privat oppskrift kan når som helst foreslås for det globale
  settet av den som eier den.
- **Godkjenning**: en admin-rolle (felt `isAdmin` på brukerdokumentet, kan kun settes manuelt i
  Firebase-konsollet — aldri av klienten selv) godkjenner eller avviser forslag før de havner i
  det globale settet. «Til godkjenning»-fanen har et rødt tallmerke med antall ventende forslag,
  synlig for admin.
- **Redigering**: eier-husholdningen kan redigere sine egne private/foreslåtte oppskrifter.
  Admin kan i tillegg redigere innholdet i allerede godkjente (globale) oppskrifter direkte
  (f.eks. rette en skrivefeil eller justere ingredienser).
- **Lag variant**: hvem som helst kan kopiere en hvilken som helst oppskrift de kan se (global
  eller egen) inn i redigeringsskjemaet, endre den (typisk navnet), og lagre som en helt ny,
  privat oppskrift i egen husholdning — påvirker ikke originalen. Gir feilmelding hvis navnet
  allerede finnes (sjekkes mot både det globale settet og husholdningens eget sett); samme sjekk
  gjelder for alle nye oppskrifter, ikke bare varianter.
- **Lim inn JSON fra språkmodell**: opprett/rediger-skjemaet har en egen knapp (✨-ikon i AppBar)
  som åpner en dialog for å lime inn et JSON-svar fra en hvilken som helst språkmodell, og fyller
  ut resten av skjemaet til gjennomsyn — akkurat som «Lag variant» gjør, ingenting lagres før man
  selv trykker lagre. Dialogen viser også selve lenken til formatbeskrivelsen med en
  kopier-knapp, slik at brukeren enkelt kan gi den videre til språkmodellen sin. Formatet
  språkmodellen skal svare med er beskrevet på en offentlig, ikke-innlogget side,
  **`web/llm-import.html`** (publisert på `https://appskrifter.web.app/llm-import.html` ved neste
  hosting-deploy), som brukeren selv gir språkmodellen sammen med en lenke til en oppskrift
  (nettside eller bilde). Siden inneholder også
  en innebygd oversikt over hele den sentrale ingredienslisten (navn + kategori) slik at
  språkmodellen kan gjenbruke eksisterende navn i stedet for å lage nære duplikater. Parsing skjer
  i `lib/services/llm_recipe_import.dart` — ingrediensenes `ingredientId` fra JSON-en ignoreres
  bevisst (samme navn-basert `findOrCreate`-oppslag som all annen oppskriftslagring), så en feil
  eller foreldet id fra språkmodellen kan aldri føre til at feil ingrediens gjenbrukes. Kjør
  `tool/generate_llm_import_page.py` før en deploy for å friske opp ingredienslisten på siden med
  gjeldende innhold fra Firestore (samme OAuth-autentiseringsteknikk mot Firestores REST-API som i
  «Å legge til oppskrifter via Claude» under).
- **Filtrering og søk**: oppskriftslistene (alle tre faner) har et søkefelt (matcher navn) og kan
  filtreres på type (middag/dessert/bakst/frokost, ELLER), ingrediens (velg flere, ELLER-logikk —
  «laks eller gulrot»), minimum egen vurdering og maks tilberedningstid. Rent klientsidig filtrering av
  de allerede strømmede listene, se `RecipeFilter` og `recipe_filter_sheet.dart`. Filteret
  rapporteres fortløpende til skjermen bak arket etter hver endring (ikke bare når «Bruk
  filter» trykkes) — et tap utenfor arket gir dermed samme resultat som å trykke «Bruk filter»,
  i stedet for å forkaste endringene.
- **Type + skjul som standard**: hver oppskrift har en `type` (middag/dessert/bakst/frokost,
  standard middag for eldre oppskrifter uten feltet). En husholdning kan i Innstillinger velge å
  skjule bestemte typer som standard i oppskriftslistene (`households.hiddenRecipeTypes`) — nyttig
  for et hushold som f.eks. aldri baker. Et eksplisitt type-filter i filterarket overstyrer dette,
  så en skjult type fortsatt kan hentes fram ved behov.
- Hver oppskrift inneholder: navn, type, tilberedningstid, ingredienser (mengde + enhet + kobling
  til sentral ingrediensliste), fremgangsmåte. **Ingen bilder i v1** — Google krever nå
  Blaze-planen (betal-for-bruk, krav om registrert kort) for å i det hele tatt aktivere Firebase
  Storage, noe
  som ble bevisst valgt bort. Kan legges til senere hvis Blaze blir aktuelt.
- **Hold skjermen på**: en avkrysningsboks på oppskrift-siden slår på `wakelock_plus` mens
  oppskriften er åpen, slik at skjermen ikke låser seg mens man lager mat. Slås automatisk av
  igjen etter et antall minutter (default 15), eller når man forlater oppskrift-siden. Tidsgrensen
  er en **personlig, enhetslokal** innstilling (lagret med `shared_preferences`, se
  `DeviceSettingsService`), redigerbar i Innstillinger → «Personlig» — bevisst ikke en delt
  husholdningsinnstilling i Firestore, siden skjermpå-oppførsel uansett er enhetsspesifikt.

### Å legge til oppskrifter via Claude
Claude kan legge til oppskrifter i det globale settet på forespørsel — inkludert ut fra en lenke
til en oppskrift på nett (Claude henter siden og tolker ingredienser/fremgangsmåte). Dette gjøres
ved å skrive direkte til Firestore med et engangs-script (Python + Firestore REST API, autentisert
via samme innloggede bruker som `firebase`-CLI-en, se historikk i samtalen for teknikken) —
det går utenom appens vanlige regel-håndhevede flyt, siden det effektivt tilsvarer en admin som
oppretter en ferdig godkjent oppskrift direkte. Nye ingredienser legges til i den sentrale
ingredienslisten samtidig, og gjenbrukes ved navnetreff. Standard: oppskriften havner rett i det
**globale** settet (`status: approved`), ikke i en bestemt husholdnings eget sett — si ifra hvis
en oppskrift heller skal være privat for en bestemt husholdning.

### Vurdering (personlig)
- Hver bruker kan gi **1–5 stjerner** på en oppskrift — kun for egen bruk.
- Vurderingen lagres i `recipes/{id}/ratings/{uid}` og er **kun synlig for deg selv**.
- Det finnes **ingen felles snitt** eller community-rating; lister og filter bruker
  «din vurdering».
- Filter «Minst din vurdering» viser oppskrifter du har vurdert med minst X stjerner
  (ugraderte oppskrifter filtreres bort når filteret er aktivt).
- Trykk samme stjerne igjen, eller «Fjern», for å slette vurderingen.
- Tekstlige anmeldelser/kommentarer: ikke i v1, kan legges til senere.
- Eldre oppskrifter kan fortsatt ha legacy-feltene `averageRating`/`ratingCount`/
  `ratingSum` i Firestore fra forrige modell — appen ignorerer dem.

### Ingredienser og kategorisering
- Det finnes en sentral, delt ingrediensliste med fast kategori per ingrediens (frukt/grønt,
  kjøtt og fisk, meieri, tørrvarer/sauser).
- Når man lager en oppskrift velger man ingredienser fra denne listen (evt. legger til nye med
  kategori), slik at kategorisering er konsistent på tvers av alle oppskrifter.
- Måleenheter bøyes riktig i UI ut fra mengde (entall kun ved nøyaktig 1, ellers flertall for
  hele ord som «pakke»/«boks»/«pose»/«bunt»/«klype» — forkortede metriske enheter som g/kg/dl/ss
  bøyes ikke), se `Unit.displayNameFor()` i `lib/models/enums.dart`.
- **Standardvarer** (Innstillinger → Standardvarer): en husholdning kan merke ingredienser fra
  den sentrale listen (salt, pepper, olivenolje osv.) som alltid antatt å være i hyllen
  (`households.staples`, liste med `ingredientId`). Slike ingredienser utelates helt fra
  handlelisten som genereres fra middagsplanen, selv om en valgt middag bruker dem — se
  `ShoppingListService.generateFromMealPlan`. Påvirker kun oppskrift-avledede varer, ikke manuelt
  tillagte varer.

### Middagsplan → handleliste
- Enkel liste-modell (v1): bruker huker av et sett middager fra globalt + eget sett, uten å
  binde dem til bestemte dager.
- Antall personer: standardverdi settes i innstillinger, kan overstyres per valgt middag.
- Ingrediensmengder skaleres lineært med antall personer (mengde per person × antall personer).
  Ingen støtte for "faste" ikke-skalerbare mengder i v1.
- **Person- vs. porsjon-oppskrifter**: bakeoppskrifter (brød, boller, kjeks) er typisk oppgitt for
  en hel omgang/bakst, ikke for et antall personer. Hver oppskrift har derfor en `recipeUnit`
  (`person`/`porsjon`, se `RecipeUnit` i `lib/models/enums.dart`) valgt uavhengig av `type` —
  ingrediensmengdene i oppskriften er per person for vanlige middager/desserter, eller per porsjon
  (= hele oppskriften slik den er skrevet) for bakst. En valgfri fritekst `yieldNote` (f.eks. «ca.
  18 kjeks») kan beskrive hva én porsjon faktisk gir — rent informativt, påvirker ikke
  utregningen. I middagsplanen og på oppskrift-siden byttes «antall personer» ut med «antall
  porsjoner» for slike oppskrifter (default 1 porsjon, i stedet for husholdningens standard antall
  personer), og handlelisten skalerer med samme mekanikk uansett enhet.
- Trykk på en middag i middagsplanen for å åpne selve oppskriften (samme oppskrift-side som fra
  oppskriftslistene).
- **Tøm handleliste fra middagsplan**: en knapp som kun vises når middagsplanen er tom, for å
  rydde bort gjenglemte oppskrift-avledede varer fra en tidligere generert handleliste (uten å
  måtte kjøre «Generer handleliste» på nytt for å bygge den opp igjen fra en tom plan). Fjerner
  kun oppskrift-avledede varer (`manual == false`) — manuelt tillagte varer røres ikke.
- Handlelisten slår sammen like ingredienser på tvers av valgte middager.
- Handlelisten sorteres etter kategori i denne rekkefølgen:
  1. Frukt og grønt
  2. Kjøtt og fisk
  3. Meieriprodukter
  4. Tørrvarer og sauser
  5. Annet (manuelt tillagte varer uten kategori fra en oppskrift)
- Man kan legge til egne, frie varer i handlelisten (utenom oppskriftene). Navnefeltet foreslår
  varer man har lagt til før (husholdnings-historikk, se under) *og* navn fra den sentrale
  ingredienslisten — historikken vinner ved navnekollisjon siden den husker mengde/enhet.
- **Varehistorikk-administrasjon** (Innstillinger → Varehistorikk): full liste over
  husholdningens historikk over manuelt tillagte varer, med redigering (f.eks. endre enhet fra
  «pakke» til «kg») og sletting av oppføringer man ikke lenger vil ha som forslag. Historikken
  fjernes **aldri** automatisk (se under) — dette er den eneste måten å rydde i den på.
- Varer i handlelisten kan krysses av som "kjøpt", med sanntidssynk mellom husholdningsmedlemmer
  (flere kan handle sammen uten å kjøpe dobbelt).
- **Fjern avkryssede varer**: en knapp (kun synlig når minst én vare er krysset av) for å rydde
  bort kjøpte varer uten å tømme hele listen — dekker både oppskrift-avledede og manuelt tillagte
  varer, i motsetning til regenerering som kun rydder oppskrift-avledede.
- **Regenerering** («Generer handleliste» fra middagsplanen): alle oppskrift-avledede varer
  bygges alltid helt på nytt. Manuelt tillagte varer beholdes **kun** hvis de ikke er krysset av
  — er de krysset av (dvs. kjøpt), fjernes de siden de ikke lenger er relevante for neste
  handletur.
- Handlelisten (inkl. avkrysning) fungerer offline via Firestores innebygde offline persistence,
  og synkroniserer når man er tilbake online.

### Husholdning / familie
- Innlogging med Google-konto.
- En bruker er medlem av **kun én** husholdning om gangen, men kan nå **forlate** den (se
  Innstillinger) og senere bli med i en annen — det er kun *samtidig* medlemskap i flere
  husholdninger som ikke støttes.
- En bruker kan opprette en husholdning og får en fast, gjenbrukbar invitasjonskode (kan
  genereres på nytt manuelt senere for å "stenge" den gamle koden).
- **Godkjenningsbasert innmelding**: å oppgi en gyldig kode sender en *forespørsel* om å bli med,
  den gir ikke medlemskap med det samme. Husholdningens **oppretter** må godkjenne eller avvise
  forespørselen (i Innstillinger) før personen faktisk får tilgang. Den som ba om å bli med ser en
  venteskjerm som automatisk oppdager godkjenning/avvisning i sanntid.
- Medlemmer av samme husholdning deler middagsplan og handleliste i sanntid, samt husholdningens
  eget oppskriftssett.

### Innstillinger
- Standard antall personer å handle til.
- Husholdningsnavn, invitasjonskode (kopier / regenerer).
- **Medlemsliste**: navn, bilde og e-post for hvert medlem, med en «Oppretter»-etikett.
- **Ventende forespørsler** (kun synlig for husholdningens oppretter): liste over de som har bedt
  om å bli med, med godkjenn/avvis-knapper.
- **Forlat husholdning**-knapp (med bekreftelse).
- Logg ut.

## Datamodell

- `users/{uid}`: `displayName`, `email`, `photoUrl`, `householdId` (kan kun settes én gang, kun
  til en husholdning brukeren faktisk har et medlemskapsdokument i), `isAdmin` (kun satt manuelt).
  **Leseregler:** egen profil; medlemmer i samme husholdning; husholdningens oppretter kan lese
  profiler for ventende join-forespørsler. Ikke lesbar for andre innloggede brukere.
- `households/{householdId}`: `name`, `inviteCode`, `createdBy`, `defaultServings`,
  `hiddenRecipeTypes` (liste med `RecipeType`-navn skjult som standard i oppskriftslistene),
  `staples` (liste med `ingredientId` — standardvarer som antas å alltid være i hyllen, se
  «Ingredienser og kategorisering»)
- `households/{householdId}/members/{uid}`: `joinedAt`, `memberUid` (redundant kopi av `{uid}`,
  brukt til å slå opp «hvilken husholdning er jeg allerede medlem av» via en
  `collectionGroup('members')`-spørring — se fallgruve om `FieldPath.documentId()` under; eldre
  medlemskapsdokumenter kan mangle dette feltet, se «Kjente feil») — **medlemskap er en
  underkolleksjon, ikke et array-felt**, se «Husholdnings-/invitasjonsdesign» under. Slettbar av
  medlemmet selv (forlate).
- `households/{householdId}/joinRequests/{uid}`: `requestedAt`, `joinCode` — ventende forespørsel
  om å bli med, opprettes av den som vil bli med, godkjennes/avvises av `createdBy`
- `households/{householdId}/mealPlanItems/{itemId}`: `recipeId`, `recipeName`, `recipeUnit`
  (øyeblikksbilde av oppskriftens `RecipeUnit`, samme mønster som `recipeName`), `servings`
  (antall personer eller porsjoner, avhengig av `recipeUnit`)
- `households/{householdId}/shoppingListItems/{itemId}`: `name`, `category`, `quantity`, `unit`,
  `checked`, `manual`, `ingredientId`
- `households/{householdId}/manualItemHistory/{itemId}`: `name`, `category`, `quantity`, `unit`
  — husholdningens historikk over manuelt tillagte varer, brukt til autocomplete-forslag.
  Dokument-id er en enkel slug av navnet (så samme vare oppdateres i stedet for å duplikeres).
  Fjernes **aldri** automatisk, selv om varen senere fjernes fra selve handlelisten.
- `inviteCodes/{code}`: `householdId`, `householdName` (denormalisert, for visning før man er
  medlem) — tynn oppslagstabell, dokument-id = selve koden
- `ingredients/{ingredientId}`: `name`, `category` — sentral, delt liste
- `recipes/{recipeId}`: `name`, `type` (`middag`/`dessert`/`bakst`/`frokost`, default `middag` for
  eldre dokumenter uten feltet), `recipeUnit` (`person`/`porsjon`, default `person` for eldre
  dokumenter uten feltet — se «Middagsplan → handleliste»), `yieldNote` (valgfri fritekst, kun
  brukt når `recipeUnit` er `porsjon`), `prepTimeMinutes`, `instructions`, `ingredients`
  (liste med `ingredientId` + navn/kategori-øyeblikksbilde + `quantityPerPerson` + `unit` —
  feltnavnet er historisk og beholdt for å unngå å migrere eksisterende oppskrifter, men betyr
  «per person eller per porsjon» avhengig av oppskriftens `recipeUnit`), `status`
  (`private`/`pending`/`approved`), `ownerHouseholdId` (null når `approved`), `createdByUid`
- `recipes/{recipeId}/ratings/{uid}`: `stars` (1–5), `raterUid` (redundant kopi av `{uid}`, samme
  begrunnelse/fallgruve som `memberUid` over — brukt av `RecipeService.myRatingsMapStream`) — kun
  lesbar/skrivbar av brukeren selv

## Husholdnings-/invitasjonsdesign (viktig for å forstå Firestore-reglene)

Prosjektet kjører **uten Cloud Functions** (Spark/gratis-plan, etter eksplisitt ønske). Å la en
bruker "be om å bli med i en husholdning via kode", med godkjenning fra oppretter, uten en tiltrodd
server krever et lite rules-triks:

1. Medlemskap lagres som egne dokumenter i `households/{id}/members/{uid}`, ikke som et
   `memberUids`-array. Det gjør at Firestore-reglene kan bruke `exists()`/`get()` til å verifisere
   medlemskap i andre regler, og la selve "bli med"-skrivingen verifiseres uavhengig. Et medlem kan
   slette sitt eget medlemskapsdokument når som helst for å **forlate** husholdningen.
2. `inviteCodes/{code}` er en tynn oppslagstabell (kode → husholdnings-id + navn, det siste kun for
   visning). Reglene tillater punkt-oppslag (`get`) for alle innloggede, og **listing kun for
   husholdningens oppretter** med filter på egen `householdId` (rydding ved regenerering).
   Kun oppretteren kan opprette og slette koder — hindrer at medlemmer lager «løse» koder.
3. Å oppgi en kode oppretter **ikke** medlemskap direkte lenger. Den som vil bli med skriver sin
   egen `households/{id}/joinRequests/{uid}` med et `joinCode`-felt; regelen sjekker (via `get()`)
   at `inviteCodes/{joinCode}` faktisk peker på nettopp denne husholdningen — dette beviser at
   personen kjenner en ekte, gyldig kode, uten at det gir tilgang.
4. Kun husholdningens **oppretter** (`households.createdBy`) kan opprette et
   `households/{id}/members/{uid}`-dokument for noen ANNEN enn seg selv, og kun når en
   tilsvarende `joinRequests/{uid}` finnes — dette er selve godkjenningen. Å avvise er bare å
   slette forespørselen uten å opprette medlemskap.
5. Alle disse operasjonene gjøres som **sekvensielle, separate Firestore-kall** (ikke én batch/
   transaksjon), se `HouseholdService`. Det er bevisst: `get()`/`exists()` i regler leser
   committed tilstand, og rekkefølgen sikrer at hvert steg kan verifisere det forrige.
6. `users/{uid}.householdId` kan settes til en husholdning der medlemskap allerede finnes
   (bli med, gjøres av personen selv etter godkjenning — se `HouseholdService.finalizeJoin`), og
   kan nullstilles igjen når medlemskapsdokumentet i den gamle husholdningen allerede er slettet
   (forlate). Den som venter på godkjenning strømmer `households/{id}/members/{uid}` og
   `households/{id}/joinRequests/{uid}` for å oppdage godkjenning/avvisning i sanntid.

**Kjent begrensning:** hvis oppretteren selv forlater husholdningen, er det ingen igjen som kan
godkjenne nye medlemmer (ingen overføring av eierskap er implementert).

Se `firestore.rules` for full implementasjon og kommentarer.

## Teknisk stack

- **Frontend:** Flutter, tilstand via Riverpod (`flutter_riverpod`)
  - **Plattformer:** Android (native app) + Flutter Web (brukes fra nettleser, bl.a. som
    erstatning for en native iOS-app)
  - Offline-støtte via Firestores innebygde offline persistence (cache + sync)
  - Språk: norsk (bokmål), måleenheter typisk for norske oppskrifter (g, kg, dl, l, ss, ts, stk,
    boks, pose, pakke, bunt, fedd, klype), se `lib/models/enums.dart`
  - App-ikon/favicon: `assets/icon/` (generert med Pillow, fork/skje-glyfen fra Material Icons på
    grønn bunn) + `flutter_launcher_icons` (konfig i `flutter_launcher_icons.yaml`). Bytt ut
    kildebildene og kjør `dart run flutter_launcher_icons` på nytt for å endre.
  - `wakelock_plus` (hold skjermen på inne på en oppskrift) og `shared_preferences` (lagring av
    den enhetslokale tidsgrensen for dette, se `DeviceSettingsService`) — ingen ekstra
    plattform-oppsett kreves (ingen Android-tillatelse, fungerer på web via Screen Wake Lock API).
- **Backend:** Firebase, **Spark (gratis) plan** — ingen Cloud Functions, ingen Firebase Storage
  - Firebase Auth (Google-innlogging)
  - Cloud Firestore (husholdninger, oppskrifter, ingrediensliste, middagsplaner, handlelister —
    sanntidssynk mellom medlemmer)
  - Firebase Hosting (web-appen, se under)

## Prosjektstruktur

```
lib/
  models/       Rene datamodeller (fromFirestore/toMap), ingen avhengighet til UI
  services/     All Firestore/Auth-logikk, ett service-lag per domene
  providers/    Riverpod-providers som kobler services til UI (StreamProvider per datastrøm)
  screens/      Én mappe per fane/flyt (auth, household, recipes, mealplan, shoppinglist, settings)
  widgets/      Gjenbrukbare widgets (stjerne-rating, oppskriftskort)
web/
  llm-import.html   Offentlig, ikke-innlogget side: formatbeskrivelse + ingrediensliste for
                    språkmodeller (se «Lim inn JSON fra språkmodell» over)
tool/
  generate_llm_import_page.py   Friskner opp ingredienslisten i web/llm-import.html fra Firestore
firestore.rules   Sikkerhetsregler — kilde til sannhet for hvem som kan lese/skrive hva
```

## Firebase-oppsett

Prosjektet er koblet til det virkelige Firebase-prosjektet **`appskrifter`**, prosjekt-nummer
`467765014512`:

- `lib/firebase_options.dart` er generert av `flutterfire configure` med ekte nøkler.
- `android/app/google-services.json` er lastet ned og inneholder OAuth-klienten for Android.
- Debug-signeringens SHA-1 (`~/.android/debug.keystore`) er registrert på Android-appen i
  Firebase, så Google-innlogging fungerer i debug-bygg (`flutter run`).
- Firestore-databasen er opprettet, `firestore.rules` + `firestore.indexes.json` er publisert.
- **`isAdmin: true`** er satt på eier-brukeren (`torstein.rotevatn@gmail.com`,
  uid `V92F58wNEvZKseSPprSHUaPkwIH2`) i `users`-kolleksjonen.
- **Web Hosting**: publisert til **https://appskrifter.web.app**.
  Redeploy: `flutter build web && firebase deploy --only hosting`.

### To google-spesifikke fallgruver å huske på (begge løst, men dukker opp igjen ved nye miljøer)

1. **Google Sign-In på web krever en «Authorized JavaScript origin» per URL/port** i Google
   Cloud Console (IKKE Firebase-konsollet) → APIs & Services → Credentials → OAuth 2.0 Client ID
   "Web client (auto created by Google Service)"
   (`467765014512-64r3avavso1mc610anjej457742klkcb.apps.googleusercontent.com`). Er allerede lagt
   til for `http://localhost:5000` (lokal dev) og `https://appskrifter.web.app` (prod). Ved bruk
   av en ny port/domene (f.eks. `flutter run -d chrome` uten `--web-port`, som velger tilfeldig
   port), må den nye origin-en legges til samme sted, ellers feiler innlogging med
   "Access blocked: Authorization Error".
2. **Google People API** må være aktivert for prosjektet (Google Sign-In-flyten kaller den for å
   hente profilinfo). Allerede aktivert. Direktelenke om den noensinne må aktiveres på nytt (f.eks.
   ved prosjektmigrering): `console.cloud.google.com/apis/library/people.googleapis.com?project=appskrifter`.

### Gjenstår kun for Play Store / release-bygg
Generer en release-keystore, og legg dens SHA-1 til på Android-appen i Firebase (samme
fremgangsmåte som debug-SHA-1-en over, med `keytool -list -v -keystore <release-keystore>` og
`firebase apps:android:sha:create`), ellers vil ikke Google-innlogging fungere i release-bygg.
Ikke gjort ennå — ikke behov før en eventuell Play Store-utgivelse eller distribusjon av
release-signerte APK-er.

## Utviklingsnotater / fallgruver (for videre arbeid på kodebasen)

- **`FloatingActionButton` trenger eksplisitt `heroTag`** på alle skjermer. `HomeShell` holder
  alle fire faner i live samtidig via `IndexedStack` (for å bevare tilstand ved fanebytte), så
  uten en unik `heroTag` per FAB kolliderer standard-taggen på tvers av skjermer og kaster en
  "multiple heroes share the same tag"-feil under sideoverganger.
- **`Autocomplete`-widgeten krever `focusNode` og `textEditingController` sammen** — gir du den
  ene eksplisitt (for å eie kontrolleren selv, f.eks. for å forhåndsutfylle et felt), må du gi
  begge, ellers kaster widgeten en assertion ved førstegangs bruk.
- Firestore-spørringer som kombinerer en `where`-likhet på ett felt med `orderBy`/likhet på et
  annet felt trenger en composite index (se `firestore.indexes.json`) — dukker opp som en
  kjøretidsfeil med en lenke til å opprette indeksen, første gang spørringen faktisk kjøres (ikke
  ved utvikling/kompilering).
- **`collectionGroup(...).where(FieldPath.documentId, isEqualTo: uid)` virker ALDRI** — en
  collection-group-spørring på dokument-id krever en fullstendig dokumentsti (f.eks.
  `households/x/members/uid`), noe som er umulig å oppgi når man nettopp leter etter den
  overordnede id-en (f.eks. «hvilken husholdning er denne brukeren medlem av»). Kastet
  `[cloud_firestore/invalid-argument]` i produksjon i juli 2026 og blokkerte all
  husholdningsopprettelse (se `HouseholdService.findMembershipHouseholdId`) og gjorde
  «din vurdering»-visningen i oppskriftslistene stille alltid tom (se
  `RecipeService.myRatingsMapStream`, maskert av en `?? const {}`-fallback ved feil). Løsning: legg
  et redundant felt (`memberUid`/`raterUid`) på dokumentet og filtrer på det feltet i stedet.
- **Enkelt-felt collection-group-indekser hører hjemme i `fieldOverrides`, ikke `indexes`** i
  `firestore.indexes.json` — en spørring med kun ett likhetsfilter (ingen `orderBy`) på en
  collection-group-spørring feiler med enten «this index is not necessary, configure using single
  field index controls» eller «Index must have at least one field» hvis den legges i `indexes`
  (som er for sammensatte indekser). Se `fieldOverrides`-oppføringene for `members`/`ratings` for
  riktig format.
- **`firebase deploy --only firestore:indexes`** bruker kolon, ikke punktum — `firestore.indexes`
  gir «Cannot understand what targets to deploy».
- **Flutter Webs PWA-service worker (`flutter_service_worker.js`, auto-registrert via
  `flutter_bootstrap.js`) overlever en vanlig hard refresh (Ctrl+Shift+R)** — en allerede installert
  service worker kan fortsette å svare fra sin egen cache uansett, og selv om en ny versjon lastes
  ned går den i «waiting»-tilstand til alle faner med den gamle versjonen er helt lukket. For å
  garantert se en ny deploy: lukk alle faner med siden helt og åpne på nytt, eller DevTools →
  Application → Service Workers → «Unregister» / «Update on reload», eller Application → Storage →
  «Clear site data». (Incognito unngår problemet siden det ikke har noen installert service worker
  fra før.)

## Kjente feil / bugs (uløst)

- **En husholdning om gangen** håndheves kun i klienten (`HouseholdService`), ikke i
  Firestore-reglene — en modifisert klient kan teoretisk ha medlemskap i flere husholdninger.
- **Sekvensielle skriv** i `createHousehold`, `leaveHousehold` og `regenerateInviteCode` kan etterlate
  delvis tilstand ved nettverksavbrudd (delvis mitigert av `AppGate` for «foreldreløs» profil).
- **Varehistorikk-nøkkelkollisjoner:** slug av varenavn (`foo bar` og `foo/bar` → samme nøkkel)
  kan overskrive historikk-oppføringer — kun autocomplete-forslag, ikke handlelisten.
- **Ingrediens-duplikater:** `IngredientService.findOrCreate` har ingen transaksjon — samtidige
  opprettelser av samme navn kan gi duplikater i den sentrale listen.
- **`AppGate` ved medlemskap-feil:** ved nettverksfeil under medlemskapsverifisering sendes
  brukeren inn i hovedappen uten tydelig feilmelding (se `app_gate.dart`).
- **Middagsplan → handleliste** henter live oppskriftsdata, ikke øyeblikksbilde fra planen
  (bevisst akseptert — sjeldne oppskriftsendringer etter planlegging).
- **Tilberedningstid-filter** lar oppskrifter med `prepTimeMinutes == 0` alltid slippe gjennom
  maks-tidsfilter (ukjent tid).
- **Handleliste-aggregering** bruker kategori fra første oppskrift når samme ingrediens har
  ulik kategori-øyeblikksbilde på tvers av oppskrifter.
- **Ikke-etterfylte `memberUid`/`raterUid`-felt på eldre dokumenter** (opprettet før feltene ble
  lagt til i juli 2026, se fallgruve om `FieldPath.documentId()` over): et gammelt
  medlemskapsdokument uten `memberUid` blir ikke funnet av
  `HouseholdService.findMembershipHouseholdId` (påvirker kun gjenopprettings-/
  dobbelt-medlemskap-sjekken, ikke selve medlemskapet), og en gammel vurdering uten `raterUid`
  vises ikke i «din vurdering»-merker/filter i oppskriftslistene før den vurderes på nytt. Ingen
  backfill er kjørt ennå.

## Inkonsistenser (uløst)

- **Mappenavn vs. pakkenavn:** repo-mappen heter `appskrift`, Dart-pakke og Firebase-prosjekt
  heter `appskrifter`.
- **Offline persistence:** dokumentert som aktiv overalt, men `main.dart` konfigurerer ikke
  Firestore persistence eksplisitt — oppførsel kan avvike på web vs. Android.
- **Feilhåndtering i UI:** noen flyter viser SnackBar ved feil (innlogging, oppskriftslagring,
  husholdningsoppsett, regenerer kode, generer handleliste), mens andre er stille (rating,
  godkjenn/avvis oppskrift og join-forespørsel, forlat husholdning, handleliste-CRUD, m.m.).
- **`pendingJoinRequestProfilesProvider`** bruker `FutureProvider` + `.first` og oppdateres ikke
  ved profilendringer (samme mønster `householdMembersProvider` hadde før det ble fikset).
- **State management:** `_WaitingForApprovalView` bruker rå `StreamBuilder`, resten av appen
  bruker Riverpod.
- **Ingen automatiserte tester** — kun manuell verifisering.

## Kjente begrensninger / naturlige neste steg

- Ingen bilder på oppskrifter i v1 (krever Blaze-planen for Firebase Storage, se over).
- Ingen overføring av «oppretter»-rollen — forlater oppretteren husholdningen, er det ingen igjen
  som kan godkjenne nye medlemmer (se «Husholdnings-/invitasjonsdesign»).
- Ingen tekstlige anmeldelser på oppskrifter (kun personlige stjerner), kan legges til senere.
- Ingen felles/community-rating uten Cloud Functions (personlig modell valgt bevisst).
- Ingen paginering av oppskrifts-/ingredienslister — antas å holde seg små nok for en
  familie-/vennegruppe-app.
- Ingen automatiserte tester — verifisert manuelt av bruker gjennom iterativ utprøving.
- Android er ikke deployet noe sted ennå (kun kjørt via `flutter run` lokalt).
