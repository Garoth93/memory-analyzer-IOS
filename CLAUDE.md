# CLAUDE.md — regole di lavoro per questa repo

Repo di app iOS **native (Swift + SwiftUI)** personali, sviluppate senza Mac:
il codice viene scritto su Linux (Claude Code) e compilato **solo** su GitHub
Actions con runner macOS. Le app non vanno su App Store: l'utente scarica il
`.ipa` non firmato dagli artifact e lo firma con Sideloadly/SideStore.

Stessa impostazione delle repo `Garoth93/home-alarm-IOS` e
`Garoth93/LTIDI-Last-Time-I-Did-It-IOS`.

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView, niente framework cross-platform,
  salvo richiesta esplicita dell'utente.
- Nessun `.xcodeproj` committato: il progetto è generato in CI da
  `apps/<app>/project.yml` con XcodeGen. `.gitignore` lo esclude.
- La repo è **pubblica**: mai committare segreti, chiavi API, certificati,
  profili di provisioning, dati personali, Team ID reali.
- Account Apple gratuito: nessuna firma in CI (`CODE_SIGNING_ALLOWED=NO`).
- Non modificare impostazioni della repo o secrets: spiegare all'utente cosa
  configurare.

## Struttura repo

```
apps/<NomeApp>/            un'app per cartella
  project.yml              spec XcodeGen (target, bundle id, deployment target)
  Sources/                 codice SwiftUI dell'app (solo strato UI + glue)
  Resources/               Assets.xcassets e altre risorse
  Info.plist               GENERATO da XcodeGen (git-ignored)
packages/<NomePackage>/    Swift Package con la logica NON grafica
  Package.swift            tools-version 5.9, nessuna dipendenza da UIKit/SwiftUI
  Sources/<NomePackage>/   modelli, regole, persistenza (Foundation only)
  Tests/<NomePackage>Tests/ XCTest, eseguiti anche su Linux
.github/workflows/         CI (vedi sotto)
.github/actions/setup-xcode/ composite action: seleziona Xcode, installa XcodeGen, genera il progetto
```

App presenti:

| App            | Package logica | Bundle ID                       | Deployment target |
|----------------|----------------|---------------------------------|-------------------|
| MemoryAnalyzer | StorageCore    | `com.garoth93.memoryanalyzer`   | iOS 26.0 |

MemoryAnalyzer ("Memoria" sulla Home): analizzatore dello spazio in stile
**WizTree**, con mappa a blocchi (treemap squarified) e grafica Material 3.

- **Panoramica**: capacità del volume (`volumeTotalCapacity` /
  `volumeAvailableCapacityForImportantUsage`), anello e barra a segmenti,
  mappa dell'iPhone (`DeviceMap`): Libero, Foto e video, Cartelle analizzate
  locali, Questa app, "Sistema, app e altri dati" (resto). Le parti note sono
  limitate allo spazio usato (gli originali iCloud possono superarlo).
- **Foto**: PhotoKit, `PHAssetResource` (somma di `fileSize` di tutte le
  risorse: originale, modifiche, video delle Live Photo; `fileSize` è KVC non
  pubblica ma stabile). Albero Anno → Mese o Tipo → Anno (`PhotoTreeBuilder`),
  miniature nei blocchi, anteprima/video, eliminazione con conferma di sistema.
- **Cartelle**: `fileImporter` su `.folder` → bookmark security-scoped
  (`FolderAccess`), scansione ricorsiva con `DirectoryScanner` (package,
  Foundation, testato su Linux) con dimensione logica e allocata. Anteprima
  Quick Look, condivisione, eliminazione di file e cartelle.
  Le cartelle dei File Provider (iCloud Drive, "Sul mio iPhone", Drive…)
  possono avere valori mancanti o non essere ancora "materializzate": lo
  scanner ricade su `attributesOfItem`/`fileExists` per capire se una voce è
  una cartella, e l'app gli passa `FolderLister` che, se l'elenco diretto
  fallisce o è vuoto, rilegge dentro `NSFileCoordinator`. Le cartelle che
  restano illeggibili sono marcate (`DirectoryScanner.unreadableDetail`) e
  contate in `FolderScanRecord.unreadable` (avviso nell'app).
- **Esploratore** (`ExplorerView`, comune a Foto e Cartelle): breadcrumb,
  intestazione con dimensione e percentuali, mappa `TreemapView` (Canvas,
  fino a 4 livelli annidati, effetto cuscino, etichette, colori per tipo o per
  cartella) con zoom animato al tocco su un blocco e zoom-out sul breadcrumb;
  sotto: Contenuto / Tipi (estensioni, come "Vista file" di WizTree) /
  Più grandi (top 100). Menu: colori, livelli, etichette, doppioni, rianalisi.
- **Doppioni** (`Analysis.duplicates`): stessa dimensione + nome (file) o
  dimensione + risoluzione (foto); tiene la copia più vecchia.
- Limite di iOS: nessuna app può leggere lo spazio delle altre app; è spiegato
  in app e finisce nel blocco "Sistema, app e altri dati".
- Persistenza in Application Support/MemoryAnalyzer: `settings.json`,
  `photos.json` (elementi, l'albero si ricostruisce), `folders/<uuid>.json`
  (albero completo + bookmark). JSON compatto per i file grandi.
- Tema: `M3Theme` generato dal colore seme (`MaterialScheme` del package),
  font rounded, card tonali, segmented button, FAB; colori dei blocchi da
  `TileColorizer` (palette tonali per categoria `FileCategory`).

Per aggiungere un'app: creare `apps/<Nome>/project.yml` + `Sources/` +
`Resources/`; i workflow scoprono automaticamente le cartelle in `apps/`
e i `Package.swift` in `packages/`. Il nome della cartella deve coincidere
con `name`, target e scheme nel `project.yml`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0` nel project.yml), tools-version
  5.9 nei package, in modo che Linux (`swift:6.0`) e Xcode 26 compilino lo
  stesso codice. Il package dichiara `.iOS(.v17)` come minimo: è solo il suo
  minimo, l'app può avere un target più alto.
- Logica, modelli e persistenza nel package: tipi `struct` value-type,
  `Codable`, `Equatable`, `Sendable`, senza `import SwiftUI`/`UIKit`.
  Tutto ciò che è testabile va lì e ha un test.
- Nell'app: `@Observable` (framework Observation) + `@MainActor`, iniettato
  con `.environment(...)` e letto con `@Environment(Tipo.self)`; viste piccole,
  una per file; stringhe UI in italiano. Target iOS 26.0: si possono usare
  le API SwiftUI di iOS 26 senza `#available`.
- Formattazione numeri/date in italiano con `Fmt` del package (indipendente
  dal locale, così i test su Linux danno le stesse stringhe dell'app).
- Nessuna dipendenza esterna salvo necessità motivata.
- Commit piccoli e descrittivi; un commit per argomento. Niente identificatori
  di modello AI nei commit.

## Xcode e runner

- Runner: `macos-26`. Xcode fissato con `XCODE_VERSION: "26.6"` (SDK iOS 26.5)
  (env in ogni workflow) e selezionato con `xcode-select`. Se GitHub ritira la
  versione, la composite action fallisce elencando le Xcode disponibili:
  aggiornare il valore in tutti i workflow e qui.
- Toolchain Linux per i test: immagine Docker `swift:6.0-noble`.
- XcodeGen e xcbeautify installati con Homebrew a ogni run.

## CI (GitHub Actions)

| Workflow | Trigger | Cosa fa |
|----------|---------|---------|
| `build-simulator.yml` | push su ogni branch, PR, manuale | `xcodebuild build` per iOS Simulator, senza firma. Serve a vedere gli errori di compilazione. |
| `build-ipa.yml` | push su `main` e `claude/**`, manuale | build Release per dispositivo con `CODE_SIGNING_ALLOWED=NO`, impacchetta `Payload/<App>.app` in `<App>-unsigned.ipa` e lo carica come artifact (30 giorni). |
| `test-linux.yml` | push su ogni branch, PR, manuale | `swift test` su ogni package in `packages/`. |

### Come leggere i log di CI

Con gli strumenti GitHub MCP disponibili a Claude Code: `actions_list` con
`list_workflow_runs` per trovare il run, `list_workflow_jobs` per i job,
`get_job_logs` con `failed_only=true` e `return_content=true` per i log dei
job falliti. I log raw di `xcodebuild` sono anche caricati come artifact
`xcodebuild-*-log-<App>`. Gli errori Swift compaiono come annotazioni
`::error file=...` grazie a `xcbeautify --renderer github-actions`.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare l'esito della CI e correggere da soli gli
   errori di compilazione fino a build verde. Mai dichiarare "funziona" se la
   CI non è verde: riportare l'esito reale con il link al run.
2. Non si può vedere l'interfaccia: nelle scelte grafiche ambigue usare il
   comportamento standard e dire all'utente cosa verificare sul telefono.
3. Commit piccoli e descrittivi. Mai segreti. Mai toccare impostazioni repo o
   secrets: indicare all'utente cosa configurare.
4. I test del package si possono eseguire in locale con Docker:
   `docker run --rm -v "$PWD":/src -w /src swift:6.0-noble swift test --package-path packages/StorageCore`
   (avviare `dockerd` se non è attivo). L'app SwiftUI si compila solo in CI.
