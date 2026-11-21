# Memoria — analizzatore dello spazio per iPhone (stile WizTree)

App iOS nativa (Swift + SwiftUI, grafica Material 3) che mostra **cosa occupa
spazio** con una mappa a blocchi: più è grande il blocco, più spazio occupa.
Tocca un blocco per entrarci e vedere il dettaglio, sempre più in profondità.

Stato CI:
[![build-simulator](https://github.com/Garoth93/memory-analyzer-IOS/actions/workflows/build-simulator.yml/badge.svg)](https://github.com/Garoth93/memory-analyzer-IOS/actions/workflows/build-simulator.yml)
[![test-linux](https://github.com/Garoth93/memory-analyzer-IOS/actions/workflows/test-linux.yml/badge.svg)](https://github.com/Garoth93/memory-analyzer-IOS/actions/workflows/test-linux.yml)
[![build-ipa](https://github.com/Garoth93/memory-analyzer-IOS/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/Garoth93/memory-analyzer-IOS/actions/workflows/build-ipa.yml)

## Cosa fa

- **Panoramica**: spazio usato / libero dell'iPhone e mappa a blocchi del
  dispositivo (foto e video, cartelle analizzate, sistema e app, libero).
- **Foto e video**: misura ogni elemento della libreria (originale, modifiche,
  video delle Live Photo) e lo disegna raggruppato per anno → mese o per tipo.
  Miniature dentro i blocchi, anteprima, riproduzione video, eliminazione.
- **Cartelle**: scegli una cartella dall'app File ("Sul mio iPhone", iCloud
  Drive, USB, rete) e la analizzo tutta, con dimensione logica e allocata.
  Anteprima, condivisione ed eliminazione di file e cartelle.
- **Esploratore**: breadcrumb, mappa con zoom animato, fino a 4 livelli
  annidati, effetto cuscino 3D, colori per tipo di file o per cartella;
  elenco del contenuto con percentuali, statistiche per estensione ("Tipi")
  e classifica dei 100 elementi più grandi.
- **Doppioni**: trova file e foto probabilmente duplicati e libera spazio
  tenendo la copia più vecchia.
- Unità decimali (come iOS) o binarie (come Windows/WizTree), tema chiaro/scuro,
  colore principale a scelta. Tutto resta sul telefono.

**Limite di iOS**: nessuna app può leggere lo spazio occupato dalle altre app.
Quello spazio compare come "Sistema, app e altri dati"; il dettaglio per app
è in Impostazioni › Generali › Spazio iPhone.

## Struttura

```
apps/MemoryAnalyzer/   app SwiftUI (project.yml per XcodeGen, Sources/, Resources/)
packages/StorageCore/  logica (treemap, albero, scansione, analisi), testata con `swift test` anche su Linux
.github/workflows/     build-simulator, build-ipa, test-linux
CLAUDE.md              convenzioni e regole di lavoro per Claude Code
```

## Installare l'app sull'iPhone

1. **Actions** → workflow **build-ipa** → ultimo run verde → sezione
   **Artifacts** → scarica `MemoryAnalyzer-unsigned-ipa` ed estrai
   `MemoryAnalyzer-unsigned.ipa`.
2. Apri **Sideloadly**, collega l'iPhone, trascina il `.ipa`, inserisci il tuo
   Apple ID e premi **Start** (oppure usa SideStore).
3. Sull'iPhone: Impostazioni → Generali → **VPN e gestione dispositivo** →
   autorizza il tuo Apple ID. Serve anche la **Modalità sviluppatore** attiva.

Con l'account gratuito la firma dura 7 giorni: rifirma lo stesso `.ipa` (le
analisi salvate restano, il bundle ID non cambia).

## Primo utilizzo

1. Apri **Memoria**: la Panoramica mostra subito lo spazio dell'iPhone.
2. Tab **Foto** → *Analizza foto e video* → consenti l'accesso a **tutte** le
   foto (con accesso limitato misuro solo quelle scelte).
3. Tab **Cartelle** → *Scegli cartella* → per esempio "Sul mio iPhone".
4. Tocca i blocchi per entrare, il breadcrumb o ↑ per tornare su.
