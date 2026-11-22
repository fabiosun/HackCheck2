# HackCheck 2.8.0 — Note di rilascio

Aggiornamento che collega l'app al tuo repository GitHub per il controllo delle nuove versioni.

## Novità

- **Controllo aggiornamenti**: verifica una volta al giorno il file `update.json` pubblicato su GitHub.
- **Note localizzate**: titoli e novità vengono mostrati in italiano o inglese secondo la lingua dell'app.
- **Comando globale**: **HackCheck → Controlla aggiornamenti…**, disponibile anche dalla finestra Impostazioni.
- **Impostazioni → Aggiornamenti**: controllo automatico, controllo immediato, ultimo controllo, pagina Release e repository configurabile (`utente/repo`).
- **Finestra aggiornamento**: opzioni **Scarica DMG**, **Apri release**, **Non ora** e **Ignora questa versione**.

L'aggiornamento **non viene installato automaticamente**: l'app apre la pagina Release o il download. La build è firmata *ad-hoc* e non notarizzata, quindi macOS può richiedere l'apertura manuale con Control+clic.

Vedi `GITHUB-UPDATES.md` per la procedura di pubblicazione.

## Build

App universale `x86_64 + arm64`, macOS 13.0 o successivo.

```bash
./build.sh
```

---

# HackCheck 2.8.0 — Release notes (English)

This release connects the app to your GitHub repository for version checks.

## What's new

- **Update checks**: verifies `update.json` on GitHub once a day.
- **Localized notes**: release notes are shown in Italian or English according to the app language.
- **Global command**: **HackCheck → Check for updates…**, also available from Settings.
- **Settings → Updates**: automatic check, manual check, last check time, Releases page and configurable repository (`user/repo`).
- **Update window**: **Download DMG**, **Open release**, **Not now** and **Skip this version**.

Updates are **not installed automatically**: the app opens the Release page or the download. The build is ad-hoc signed and not notarized, so macOS may require Control+click to open it.

See `GITHUB-UPDATES.md` for the publishing procedure.

## Build

Universal app `x86_64 + arm64`, macOS 13.0 or later.

```bash
./build.sh
```
